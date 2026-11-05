// Shared by the Pages Function (production) and the relay Worker's own fetch (local tests only:
// in production the Worker has no route). Cheap checks happen here, before a Durable Object request.
// Room codes are four letters without I and O (net/room_code.gd), handshake fields game and build.

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
const CODE = /^[A-HJ-NP-Z]{4}$/;
const BUILD = /^[\w.-]{1,40}$/;
const GAME = 'knoedlinger';
// A random code is taken while its room is open; a few tries find a free one.
const CREATE_TRIES = 8;

export async function routeRoom(request, env, code) {
	if (request.headers.get('Upgrade') !== 'websocket') {
		return new Response('Expected a WebSocket', { status: 426 });
	}
	const url = new URL(request.url);
	if (url.searchParams.get('game') !== GAME) {
		return new Response('Wrong game', { status: 400 });
	}
	if (!BUILD.test(url.searchParams.get('build') || '')) {
		return new Response('Missing build', { status: 400 });
	}
	if (code === 'new') {
		for (let i = 0; i < CREATE_TRIES; i++) {
			let candidate = '';
			for (let k = 0; k < 4; k++) {
				candidate += ALPHABET[Math.floor(Math.random() * ALPHABET.length)];
			}
			const response = await forward(request, env, candidate, true);
			if (response.status !== 409) {
				return response;
			}
		}
		return new Response('No free room code', { status: 503 });
	}
	code = code.toUpperCase();
	if (!CODE.test(code)) {
		return new Response('Bad room code', { status: 404 });
	}
	return forward(request, env, code, false);
}

function forward(request, env, code, create) {
	const url = new URL(request.url);
	url.searchParams.set('code', code);
	url.searchParams.set('create', create ? '1' : '0');
	const stub = env.ROOMS.get(env.ROOMS.idFromName(code));
	return stub.fetch(new Request(url, request));
}
