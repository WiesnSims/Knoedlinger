// Die Ehrentafel's Functions against a local D1 in `wrangler pages dev` (nothing deployed):
//     node --test board/test/board.test.mjs
// Set BOARD_URL to test a running server instead (its database is written to; the tests that age
// tickets need the local one).
import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { cleanName, maxKills, weekStart, FALLBACK_NAME, TICKETS_PER_HOUR } from '../board.js';
import { startBoard } from './local.mjs';

let base = process.env.BOARD_URL;
let server;

before(async () => {
	if (!base) {
		server = await startBoard(8790);
		base = server.url;
	}
});

after(() => server?.stop());

// Each request comes from its own made-up address, so the ticket limit only bites where a test wants it.
let address = 0;
function post(path, body, ip = `10.0.${Math.floor(++address / 250)}.${address % 250}`) {
	return fetch(`${base}/api/board/${path}`, {
		method: 'POST',
		headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': ip },
		body: JSON.stringify(body),
	});
}

async function ticket(mode = 'solo', map = 'kirtag', ageSeconds = 0) {
	const response = await post('ticket', { mode, map });
	assert.equal(response.status, 200);
	const id = (await response.json()).ticket;
	if (ageSeconds > 0) {
		await server.sql(`UPDATE tickets SET created = created - ${ageSeconds} WHERE id = '${id}'`);
	}
	return id;
}

function run(fields = {}) {
	return {
		names: ['Resi'], characters: ['ferdl'], result: 'LOST', grant: 1, time: 20, level: 3, kills: 40, knodl: 30,
		version: '1.0.0', ...fields,
	};
}

async function list(mode, map, range = 'all') {
	return (await (await fetch(`${base}/api/board/list?mode=${mode}&map=${map}&range=${range}`)).json()).entries;
}

test('names: trimmed, at most 16 characters, swear words become Knödlinger', () => {
	assert.equal(cleanName('  Resi  '), 'Resi');
	assert.equal(cleanName('Onkel Ferdl der Grantige'), 'Onkel Ferdl der');
	assert.equal(cleanName('F0tze'), FALLBACK_NAME);
	assert.equal(cleanName(''), FALLBACK_NAME);
	assert.equal(cleanName('Kommerzialrat'), 'Kommerzialrat');
});

test('the week starts on Monday 00:00 UTC', () => {
	assert.equal(weekStart(Date.UTC(2026, 10, 6, 15)), Date.UTC(2026, 10, 2) / 1000);
	assert.equal(weekStart(Date.UTC(2026, 10, 2, 0, 0, 1)), Date.UTC(2026, 10, 2) / 1000);
});

test('a short run is saved and ranked', async () => {
	const response = await post('entry', { ticket: await ticket('solo', 'testmap_a'), ...run() });
	assert.equal(response.status, 200);
	const saved = await response.json();
	assert.equal(saved.rank, 1);
	assert.equal(saved.week_rank, 1);
	const entries = await list('solo', 'testmap_a');
	assert.equal(entries.length, 1);
	assert.deepEqual(entries[0].names, ['Resi']);
	assert.deepEqual(entries[0].characters, ['ferdl']);
	assert.equal(entries[0].grant, 1);
});

test('a ticket counts once', async () => {
	const id = await ticket();
	assert.equal((await post('entry', { ticket: id, ...run() })).status, 200);
	assert.equal((await post('entry', { ticket: id, ...run() })).status, 403);
	assert.equal((await post('entry', { ticket: 'made-up', ...run() })).status, 403);
});

test('a run cannot be longer than its ticket is old, nor hold too many kills', async () => {
	assert.equal((await post('entry', { ticket: await ticket(), ...run({ time: 600 }) })).status, 422);
	assert.equal((await post('entry', { ticket: await ticket(), ...run({ kills: maxKills(20, 1) + 1 }) })).status, 422);
	assert.equal((await post('entry', { ticket: await ticket(), ...run({ result: 'WON', time: 25 }) })).status, 422,
		'a win means the whole run');
	assert.equal((await post('entry', { ticket: await ticket(), ...run({ result: 'MAYBE' }) })).status, 400);
	assert.equal((await post('entry', { ticket: await ticket(), ...run({ characters: ['../x'] }) })).status, 400);
});

test('the order: won before survived before knocked out, then Grant, then time, then kills', async () => {
	const map = 'testmap_b';
	const send = async (fields) => (await post('entry', { ticket: await ticket('solo', map, 1000), ...run(fields) })).json();
	await send({ names: ['Lost'], result: 'LOST', time: 700, kills: 9000 });
	await send({ names: ['Closed'], result: 'CLOSED', time: 905 });
	await send({ names: ['WonNormal'], result: 'WON', grant: 1, time: 905 });
	const top = await send({ names: ['WonGrantig'], result: 'WON', grant: 2, time: 905 });
	assert.equal(top.rank, 1);
	const names = (await list('solo', map)).map((e) => e.names[0]);
	assert.deepEqual(names, ['WonGrantig', 'WonNormal', 'Closed', 'Lost']);
});

test('maps and modes keep their own boards', async () => {
	await post('entry', { ticket: await ticket('coop', 'testmap_c'), ...run({ names: ['A', 'B'], characters: ['ferdl', 'ferdl'] }) });
	assert.equal((await list('coop', 'testmap_c')).length, 1);
	assert.equal((await list('solo', 'testmap_c')).length, 0);
	assert.equal((await list('coop', 'testmap_d')).length, 0);
});

test('too many tickets from one address are refused', async () => {
	const statuses = [];
	for (let k = 0; k <= TICKETS_PER_HOUR; k++) {
		statuses.push((await post('ticket', { mode: 'solo', map: 'kirtag' }, '10.9.9.9')).status);
	}
	assert.equal(statuses.at(-1), 429);
});
