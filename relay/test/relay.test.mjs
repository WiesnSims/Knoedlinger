// Relay behaviour against the real Durable Object in `wrangler dev` (local, nothing deployed):
//     node --test relay/test/relay.test.mjs
// Set RELAY_URL to test a running relay instead (e.g. ws://127.0.0.1:8790).
import { spawn } from 'node:child_process';
import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const PORT = 8790;
let base = process.env.RELAY_URL;
let dev;

before(async () => {
	if (base) {
		return;
	}
	const cwd = fileURLToPath(new URL('..', import.meta.url));
	dev = spawn('npx', ['wrangler@latest', 'dev', '--port', String(PORT), '--ip', '127.0.0.1'], { cwd, shell: true });
	await new Promise((resolve, reject) => {
		const timer = setTimeout(() => reject(new Error('wrangler dev did not start')), 90_000);
		const watch = (chunk) => {
			if (/Ready on/i.test(String(chunk))) {
				clearTimeout(timer);
				resolve();
			}
		};
		dev.stdout.on('data', watch);
		dev.stderr.on('data', watch);
	});
	base = `ws://127.0.0.1:${PORT}`;
});

after(() => {
	if (dev) {
		// shell: true on Windows starts a tree; kill all of it.
		if (process.platform === 'win32') {
			spawn('taskkill', ['/pid', String(dev.pid), '/t', '/f']);
		} else {
			dev.kill();
		}
	}
});

// A socket with a queue of what arrived, so a test can wait for "the next text" or "the next binary".
function open(path, build = 'test') {
	const ws = new WebSocket(`${base}/api/room/${path}?game=knoedlinger&build=${build}`);
	ws.binaryType = 'arraybuffer';
	const inbox = [];
	const waiters = [];
	const push = (item) => {
		const i = waiters.findIndex((w) => w.match(item));
		if (i >= 0) {
			waiters.splice(i, 1)[0].resolve(item);
		} else {
			inbox.push(item);
		}
	};
	ws.addEventListener('message', (e) => push(typeof e.data === 'string' ? { text: JSON.parse(e.data) } : { bytes: new Uint8Array(e.data) }));
	const next = (match, ms = 5000) => {
		const i = inbox.findIndex(match);
		if (i >= 0) {
			return Promise.resolve(inbox.splice(i, 1)[0]);
		}
		return new Promise((resolve, reject) => {
			const timer = setTimeout(() => reject(new Error('timed out')), ms);
			waiters.push({ match, resolve: (v) => { clearTimeout(timer); resolve(v); } });
		});
	};
	return {
		ws,
		text: (t) => next((m) => m.text && (!t || m.text.t === t)).then((m) => m.text),
		bytes: () => next((m) => m.bytes).then((m) => m.bytes),
		quiet: async (ms = 400) => {
			await new Promise((r) => setTimeout(r, ms));
			return inbox.filter((m) => m.bytes).length === 0;
		},
		send: (target, ...payload) => ws.send(new Uint8Array([target & 0xff, ...payload])),
	};
}

async function room() {
	const host = open('new');
	const welcome = await host.text('welcome');
	assert.equal(welcome.id, 1);
	assert.match(welcome.code, /^[A-HJ-NP-Z]{4}$/);
	return { host, code: welcome.code };
}

test('players get ids 2-4, the fifth is refused', async () => {
	const { host, code } = await room();
	const ids = [];
	const guests = [];
	for (let i = 0; i < 3; i++) {
		const g = open(code);
		guests.push(g);
		const w = await g.text('welcome');
		ids.push(w.id);
		assert.equal(w.peers.length, i + 1);
		assert.equal((await host.text('joined')).id, w.id);
	}
	assert.deepEqual(ids, [2, 3, 4]);
	const fifth = open(code);
	assert.equal((await fifth.text('closed')).reason, 'full');
	host.ws.close();
	for (const g of guests) {
		assert.equal((await g.text('closed')).reason, 'host_left');
	}
});

test('frames carry the sender, targets are honoured', async () => {
	const { host, code } = await room();
	const a = open(code);
	await a.text('welcome');
	const b = open(code);
	await b.text('welcome');
	// Host to everyone.
	host.send(0, 7, 8);
	assert.deepEqual([...(await a.bytes())], [1, 7, 8]);
	assert.deepEqual([...(await b.bytes())], [1, 7, 8]);
	// Peer 2 to the host only.
	a.send(1, 9);
	assert.deepEqual([...(await host.bytes())], [2, 9]);
	assert.ok(await b.quiet());
	// Peer 3 to everyone but peer 2.
	b.send(-2, 5);
	assert.deepEqual([...(await host.bytes())], [3, 5]);
	assert.ok(await a.quiet());
	// The host to exactly peers 2 and 3 (mask bits 1 and 2), and a newcomer (4) gets nothing.
	const c = open(code);
	await c.text('welcome');
	host.send(0x20 | 0b110, 6);
	assert.deepEqual([...(await a.bytes())], [1, 6]);
	assert.deepEqual([...(await b.bytes())], [1, 6]);
	assert.ok(await c.quiet());
	host.ws.close();
});

test('a guest leaving is announced, a kick closes the guest', async () => {
	const { host, code } = await room();
	const a = open(code);
	await a.text('welcome');
	const b = open(code);
	await b.text('welcome');
	await host.text('joined');
	await host.text('joined');
	a.ws.close();
	assert.equal((await host.text('left')).id, 2);
	host.ws.send(JSON.stringify({ t: 'kick', id: 3 }));
	assert.equal((await b.text('closed')).reason, 'kicked');
	assert.equal((await host.text('left')).id, 3);
	host.ws.close();
});

test('wrong build, unknown room and a started match are refused', async () => {
	const { host, code } = await room();
	const old = open(code, 'other');
	assert.equal((await old.text('closed')).reason, 'version');
	host.ws.send(JSON.stringify({ t: 'start' }));
	// Give the start a moment to land before the late joiner knocks.
	await new Promise((r) => setTimeout(r, 200));
	const late = open(code);
	assert.equal((await late.text('closed')).reason, 'started');
	// Back in the lobby after a game over, joining is open again.
	host.ws.send(JSON.stringify({ t: 'lobby' }));
	await new Promise((r) => setTimeout(r, 200));
	const again = open(code);
	assert.equal((await again.text('welcome')).id, 2);
	host.ws.close();
	await new Promise((r) => setTimeout(r, 200));
	const ghost = open(code);
	assert.equal((await ghost.text('closed')).reason, 'no_room');
});
