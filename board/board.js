// Die Ehrentafel vom Goldenen Knödl (docs/DECISIONS.md, M4): the global highscore board, in the Pages
// project's D1 database (binding BOARD, schema in board/migrations). Reused from Berghittn's
// Gipfelbuch. Called by the Pages Function functions/api/board/[action].js:
//     POST /api/board/ticket  {mode, map}                                  -> {ticket}
//     POST /api/board/entry   {ticket, names, characters, result, grant,
//                              time, level, kills, knodl, version}         -> {id, rank, week_rank}
//     GET  /api/board/list?mode=solo|coop&map=<id>&range=all|week          -> {entries: [...]}
// Order: result (won 2 > Sperrstund' survived 1 > knocked out 0), then Grant level, then time, then
// kills. A browser game cannot stop cheating; the tickets only make a faked result harder.
// Die Tageskarte (1.4): mode 'daily', map 'daily_<YYYYMMDD>' (UTC), solo only; a ticket only for
// today's card (or yesterday's, for a run started just before midnight).

export const MODES = ['solo', 'coop', 'daily'];
export const LIST_SIZE = 50;
export const NAME_MAX = 16;
export const MAX_PLAYERS = 4;
export const RESULTS = { LOST: 0, CLOSED: 1, WON: 2 };
// A run lasts 15:00 plus at most 10:00 of Nachspielzeit (balance overtime_max_seconds); a minute more
// to be safe.
export const MAX_RUN_SECONDS = 1560;
export const MAX_GRANT = 4;
// A ticket is good this long after the run started (s), and is removed a while after that.
export const TICKET_LIFE = 3 * 3600;
export const TICKETS_PER_HOUR = 30;
// The ticket must be at least this much older than the time the run claims (clock slack).
const TIME_SLACK = 30;
const MAX_TEXT = 48;
const MAP_PATTERN = /^[a-z0-9_]{1,24}$/;
const DAILY_PATTERN = /^daily_\d{8}$/;
// Swear words and worse (after folding look-alike digits): such a name becomes "Knödlinger".
const BANNED = [
	'fuck', 'cunt', 'shit', 'bitch', 'nigg', 'fagg', 'retard', 'hitler', 'nazi', 'fotze', 'wichs',
	'hurensohn', 'schwuchtel', 'kanake', 'arschloch', 'spast', 'missgeburt',
];
const LOOKALIKE = { '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '@': 'a', '$': 's', '!': 'i' };
export const FALLBACK_NAME = 'Knödlinger';

export async function handleBoard(request, env, action) {
	try {
		if (action === 'list' && request.method === 'GET') {
			return json(await list(env, new URL(request.url)));
		}
		if (request.method !== 'POST') {
			return json({ error: 'method' }, 405);
		}
		const body = await request.json().catch(() => null);
		if (!body || typeof body !== 'object') {
			return json({ error: 'body' }, 400);
		}
		if (action === 'ticket') {
			return await ticket(env, request, body);
		}
		if (action === 'entry') {
			return await entry(env, body);
		}
		return json({ error: 'action' }, 404);
	} catch (error) {
		console.error(error);
		return json({ error: 'server' }, 500);
	}
}

// Monday 00:00 UTC of this week, in seconds.
export function weekStart(now = Date.now()) {
	const day = new Date(now);
	const sinceMonday = (day.getUTCDay() + 6) % 7;
	return Math.floor(Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate() - sinceMonday) / 1000);
}

// The Tageskarte's board key of a UTC day ("daily_20261106").
export function dailyMap(now = Date.now()) {
	const day = new Date(now);
	const pad = (n) => String(n).padStart(2, '0');
	return `daily_${day.getUTCFullYear()}${pad(day.getUTCMonth() + 1)}${pad(day.getUTCDate())}`;
}

// A daily ticket is for today's card, or yesterday's in the first hour after midnight.
export function dailyOpen(map, now = Date.now()) {
	return DAILY_PATTERN.test(map) && (map === dailyMap(now) || map === dailyMap(now - 3600 * 1000));
}

// Printable, trimmed, at most NAME_MAX characters; a banned word turns it into FALLBACK_NAME.
export function cleanName(value) {
	const name = [...String(value ?? '').replace(/[\p{C}]/gu, '').trim()].slice(0, NAME_MAX).join('').trim();
	const folded = [...name.toLowerCase()].map((c) => LOOKALIKE[c] ?? c).join('').replace(/[^\p{L}]/gu, '');
	if (name === '' || BANNED.some((word) => folded.includes(word))) {
		return FALLBACK_NAME;
	}
	return name;
}

// The most kills a run of this length could plausibly hold, per player (generous).
export function maxKills(time, players) {
	return players * (2000 + 120 * time);
}

function seconds() {
	return Math.floor(Date.now() / 1000);
}

function int(value, max) {
	return Number.isInteger(value) && value >= 0 && value <= max ? value : null;
}

function ident(value) {
	const text = String(value ?? '');
	return MAP_PATTERN.test(text) ? text : null;
}

async function ticket(env, request, body) {
	if (!MODES.includes(body.mode) || !ident(body.map) || (body.mode === 'daily') !== DAILY_PATTERN.test(body.map)) {
		return json({ error: 'mode' }, 400);
	}
	if (body.mode === 'daily' && !dailyOpen(body.map)) {
		return json({ error: 'day' }, 400);
	}
	const now = seconds();
	const ip = await hash(request.headers.get('CF-Connecting-IP') || 'local');
	const recent = await env.BOARD.prepare('SELECT COUNT(*) AS n FROM tickets WHERE ip = ? AND created > ?')
		.bind(ip, now - 3600).first('n');
	if (recent >= TICKETS_PER_HOUR) {
		return json({ error: 'busy' }, 429);
	}
	const id = crypto.randomUUID();
	await env.BOARD.batch([
		env.BOARD.prepare('DELETE FROM tickets WHERE created < ?').bind(now - 2 * TICKET_LIFE),
		env.BOARD.prepare('INSERT INTO tickets (id, mode, map, ip, created) VALUES (?, ?, ?, ?, ?)')
			.bind(id, body.mode, body.map, ip, now),
	]);
	return json({ ticket: id });
}

async function entry(env, body) {
	const now = seconds();
	const found = typeof body.ticket === 'string'
		? await env.BOARD.prepare('SELECT mode, map, created, used FROM tickets WHERE id = ?').bind(body.ticket).first()
		: null;
	if (!found) {
		return json({ error: 'ticket' }, 403);
	}
	if (found.used || now - found.created > TICKET_LIFE) {
		return json({ error: 'ticket_used' }, 403);
	}
	const mode = found.mode;
	const names = Array.isArray(body.names) ? body.names.slice(0, MAX_PLAYERS).map(cleanName) : [];
	const characters = Array.isArray(body.characters) ? body.characters.slice(0, MAX_PLAYERS).map(ident) : [];
	const players = mode === 'coop' ? names.length : 1;
	const result = Object.hasOwn(RESULTS, body.result) ? RESULTS[body.result] : null;
	const grant = int(body.grant, MAX_GRANT);
	const time = int(body.time, MAX_RUN_SECONDS);
	const level = int(body.level, 999);
	const kills = int(body.kills, Number.MAX_SAFE_INTEGER);
	const knodl = int(body.knodl, 10_000_000);
	if (players < 1 || names.length !== players || characters.length !== players || characters.includes(null)
		|| result === null || grant === null || time === null || level === null || kills === null || knodl === null) {
		return json({ error: 'entry' }, 400);
	}
	// Could the run have lasted this long since its ticket, and do the kills fit it? A win or a
	// survived Sperrstund' means the whole run was played.
	if (now - found.created + TIME_SLACK < time || kills > maxKills(time, players) || (result > 0 && time < 890)) {
		return json({ error: 'implausible' }, 422);
	}
	// Taken once: the update only counts if the ticket was still unused.
	const claim = await env.BOARD.prepare('UPDATE tickets SET used = 1 WHERE id = ? AND used = 0').bind(body.ticket).run();
	if (claim.meta.changes !== 1) {
		return json({ error: 'ticket_used' }, 403);
	}
	const version = String(body.version ?? '').replace(/[^\w.-]/g, '').slice(0, MAX_TEXT);
	const saved = await env.BOARD.prepare(
		'INSERT INTO entries (mode, map, names, characters, result, grant_level, time, level, kills, knodl, players, version, created) '
		+ 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id',
	).bind(mode, found.map, JSON.stringify(names), JSON.stringify(characters), result, grant, time, level, kills, knodl,
		players, version, now).first('id');
	const key = { mode, map: found.map, result, grant, time, kills };
	return json({ id: saved, rank: await rank(env, key, 0), week_rank: await rank(env, key, weekStart()) });
}

// The place of a just saved entry: the entries that sort before it, or equal (an earlier one keeps
// its place on a tie), the entry itself among them.
async function rank(env, e, since) {
	return env.BOARD.prepare(
		'SELECT COUNT(*) AS n FROM entries WHERE mode = ? AND map = ? AND created >= ? AND ('
		+ 'result > ? OR (result = ? AND (grant_level > ? OR (grant_level = ? AND (time > ? OR (time = ? AND kills >= ?))))))',
	).bind(e.mode, e.map, since, e.result, e.result, e.grant, e.grant, e.time, e.time, e.kills).first('n');
}

async function list(env, url) {
	const mode = url.searchParams.get('mode');
	const map = ident(url.searchParams.get('map'));
	if (!MODES.includes(mode) || !map) {
		return { error: 'mode' };
	}
	const since = url.searchParams.get('range') === 'week' ? weekStart() : 0;
	const { results } = await env.BOARD.prepare(
		'SELECT id, names, characters, result, grant_level AS grant, time, level, kills, knodl, players, created FROM entries '
		+ 'WHERE mode = ? AND map = ? AND created >= ? ORDER BY result DESC, grant_level DESC, time DESC, kills DESC, id ASC LIMIT ?',
	).bind(mode, map, since, LIST_SIZE).all();
	return {
		entries: results.map((row) => ({ ...row, names: JSON.parse(row.names), characters: JSON.parse(row.characters) })),
	};
}

async function hash(text) {
	const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`knoedlinger:${text}`));
	return [...new Uint8Array(digest).slice(0, 12)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function json(data, status = 200) {
	return new Response(JSON.stringify(data), {
		status,
		headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
	});
}
