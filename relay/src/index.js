// The co-op relay (Berghittn's, docs/DECISIONS.md M6). A Room knows sockets, peer ids and who is host; it never
// looks inside the game's packets.
//
// Binary frames: [peer i8][payload...]. From a player the byte is the target (0 = everyone else,
// n = peer n, -n = everyone else but n, 0x20 | mask = exactly the peers in the mask, bit k = peer
// k + 1: a broadcast never reaches someone who joined after the sender last looked); the relay
// rewrites it to the sender before passing it on, so nobody can pretend to be the host. Text frames are JSON control messages (see control() below).
import { DurableObject } from 'cloudflare:workers';
import { routeRoom } from './route.js';

const MAX_PLAYERS = 4;
const HOST = 1;
const MAX_FRAME_BYTES = 64 * 1024;
// Frames per second a socket may send before the rest is dropped (20 Hz batches to up to 4 targets,
// with room to spare): keeps a broken client from burning the Free plan's daily quota.
const MAX_FRAMES_PER_SECOND = 120;
// Close codes the game turns into a message.
const CLOSE = { hostLeft: 4000, refused: 4001, kicked: 4002, badFrame: 4003 };

export class Room extends DurableObject {
	constructor(ctx, env) {
		super(ctx, env);
		// Answered by the runtime without waking the object: the lobby's keep-alive costs nothing.
		ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('ping', 'pong'));
		// Per-socket frame counts for the rate limit; losing them to hibernation is harmless.
		this.rates = new Map();
	}

	async fetch(request) {
		const url = new URL(request.url);
		const code = url.searchParams.get('code');
		const build = url.searchParams.get('build');
		const players = this.players();
		let id;
		if (url.searchParams.get('create') === '1') {
			if (players.length > 0) {
				return new Response(null, { status: 409 });
			}
			id = HOST;
		} else {
			const host = players.find((p) => p.meta.id === HOST);
			if (!host) {
				return refuse('no_room');
			}
			if (host.meta.started) {
				return refuse('started');
			}
			if (players.length >= MAX_PLAYERS) {
				return refuse('full');
			}
			if (host.meta.build !== build) {
				return refuse('version');
			}
			const taken = new Set(players.map((p) => p.meta.id));
			id = [2, 3, 4].find((n) => !taken.has(n));
		}
		const [client, server] = Object.values(new WebSocketPair());
		this.ctx.acceptWebSocket(server);
		server.serializeAttachment({ id, build, started: false });
		server.send(JSON.stringify({ t: 'welcome', id, code, peers: players.map((p) => p.meta.id) }));
		for (const p of players) {
			p.ws.send(JSON.stringify({ t: 'joined', id }));
		}
		return new Response(null, { status: 101, webSocket: client });
	}

	async webSocketMessage(ws, message) {
		const meta = ws.deserializeAttachment();
		if (typeof message === 'string') {
			this.control(ws, meta, message);
			return;
		}
		if (!this.allow(ws)) {
			return;
		}
		const bytes = new Uint8Array(message);
		if (bytes.length < 2 || bytes.length > MAX_FRAME_BYTES) {
			ws.close(CLOSE.badFrame, 'bad frame');
			return;
		}
		const target = (bytes[0] << 24) >> 24;
		const mask = (bytes[0] & 0xe0) === 0x20 ? bytes[0] & 0x1f : -1;
		const out = bytes.slice();
		out[0] = meta.id;
		for (const p of this.players()) {
			const to = p.meta.id;
			if (to === meta.id) {
				continue;
			}
			const wanted = mask >= 0 ? (mask & (1 << (to - 1))) !== 0
				: target === 0 || (target > 0 && to === target) || (target < 0 && to !== -target);
			if (wanted) {
				p.ws.send(out);
			}
		}
	}

	// From the host only: {"t":"start"} (the match began, nobody else may join), {"t":"lobby"} (back in
	// the lobby after a game over: joining is open again), {"t":"kick","id":n}.
	control(ws, meta, text) {
		let msg;
		try {
			msg = JSON.parse(text);
		} catch {
			return;
		}
		if (meta.id !== HOST) {
			return;
		}
		if (msg.t === 'start' || msg.t === 'lobby') {
			meta.started = msg.t === 'start';
			ws.serializeAttachment(meta);
		} else if (msg.t === 'kick' && msg.id !== HOST) {
			const p = this.players().find((q) => q.meta.id === msg.id);
			if (p) {
				shut(p.ws, CLOSE.kicked, 'kicked');
			}
		}
	}

	async webSocketClose(ws, code) {
		this.leave(ws);
		try {
			ws.close(code === 1005 ? 1000 : code, 'bye');
		} catch {
			// Already closed.
		}
	}

	async webSocketError(ws) {
		this.leave(ws);
	}

	leave(ws) {
		this.rates.delete(ws);
		const meta = ws.deserializeAttachment();
		if (!meta) {
			return;
		}
		for (const p of this.players()) {
			if (p.ws === ws) {
				continue;
			}
			if (meta.id === HOST) {
				// No host migration: the room ends with its host.
				shut(p.ws, CLOSE.hostLeft, 'host_left');
			} else {
				p.ws.send(JSON.stringify({ t: 'left', id: meta.id }));
			}
		}
	}

	players() {
		const list = [];
		for (const ws of this.ctx.getWebSockets()) {
			const meta = ws.deserializeAttachment();
			if (meta && ws.readyState === WebSocket.OPEN) {
				list.push({ ws, meta });
			}
		}
		return list;
	}

	allow(ws) {
		const now = Math.floor(Date.now() / 1000);
		const rate = this.rates.get(ws) || { second: now, count: 0 };
		if (rate.second !== now) {
			rate.second = now;
			rate.count = 0;
		}
		rate.count++;
		this.rates.set(ws, rate);
		return rate.count <= MAX_FRAMES_PER_SECOND;
	}
}

// Says why before closing: a close the relay starts does not always reach the client as a close
// event at once (seen in local workerd), so the game acts on the message and closes from its side.
function shut(ws, code, reason) {
	ws.send(JSON.stringify({ t: 'closed', reason }));
	ws.close(code, reason);
}

// A browser cannot read the HTTP status of a failed WebSocket, so a refusal is a short-lived socket
// that says why and closes.
function refuse(reason) {
	const [client, server] = Object.values(new WebSocketPair());
	server.accept();
	server.send(JSON.stringify({ t: 'closed', reason }));
	server.close(CLOSE.refused, reason);
	return new Response(null, { status: 101, webSocket: client });
}

export default {
	fetch(request, env) {
		const match = new URL(request.url).pathname.match(/^\/api\/room\/([^/]+)$/);
		if (!match) {
			return new Response('Not found', { status: 404 });
		}
		return routeRoom(request, env, match[1]);
	},
};
