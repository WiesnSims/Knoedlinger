// Co-op in real browsers (M6): N headless Edge tabs meet in one room through the relay and play.
// Used by tools/browser_mp_check.ps1.
//
//   node mp_tabs.mjs --url=http://127.0.0.1:8062/ --tabs=4 --seconds=60 [--relay=ws://127.0.0.1:8790]
//        [--enemies=300] [--min-fps=30] [--out=report.json] [--shot-dir=<dir>]
//
// The first tab opens a room (?net=relay&host=1&lobby=<tabs-1>), prints "[NET] ROOM XXXX open", the
// others join it (?net=relay&room=XXXX&lobby=1); the host starts the run once everyone is in the
// room (Lobby autoload), and every tab plays with the bot and prints one [RESULT]. Without --relay
// the page's own origin is the relay (a preview or the live site). Each tab gets its own browser
// context (own storage, like separate players).
// Fails on: any console error, a tab without [RESULT], a client that does not show every Knödl or
// the host's crowd, a client below --min-fps (four tabs share one GPU and CPU here).
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

const args = Object.fromEntries(process.argv.slice(2).map((a) => {
	const [key, ...rest] = a.replace(/^--/, '').split('=');
	return [key, rest.length ? rest.join('=') : '1'];
}));
const tabs = Number(args.tabs || 4);
const seconds = Number(args.seconds || 60);
const base = args.url || 'http://127.0.0.1:8062/';
const minFps = Number(args['min-fps'] || 30);
const LOAD_TIMEOUT_MS = 120_000;
const CHARACTERS = ['ferdl', 'resi', 'toni', 'poldi'];

function urlFor(extra) {
	const query = new URLSearchParams({
		net: 'relay', bot: '1', respawn: '1', mute: '1', debug: '0',
		enemies: args.enemies || '300',
		...extra,
	});
	if (args.relay) {
		query.set('relay', args.relay);
	}
	return `${base}${base.includes('?') ? '&' : '?'}${query}`;
}

const browser = await chromium.launch({
	channel: 'msedge',
	headless: true,
	args: ['--enable-gpu', '--ignore-gpu-blocklist', '--use-angle=d3d11', '--disable-gpu-vsync',
		'--disable-frame-rate-limit', '--autoplay-policy=no-user-gesture-required', '--mute-audio'],
});

const players = [];
function watch(index, page) {
	const player = { index, page, errors: [], result: null, code: '', lines: [], stats: [] };
	page.on('console', (message) => {
		const text = message.text();
		if (text.startsWith('[STATS] ')) {
			player.stats.push(JSON.parse(text.slice(8)));
		} else if (text.startsWith('[RESULT] ')) {
			player.result = JSON.parse(text.slice(9));
		} else if (text.startsWith('[NET]') || text.startsWith('[LOBBY]')) {
			player.lines.push(text);
			const room = text.match(/^\[NET\] ROOM ([A-Z]{4}) open/);
			if (room) {
				player.code = room[1];
			}
		}
		if (message.type() === 'error' || (message.type() === 'warning' && /^(USER |SCRIPT )?(ERROR|WARNING):/.test(text))) {
			player.errors.push(text);
		}
	});
	page.on('pageerror', (error) => player.errors.push(`pageerror: ${error.message}`));
	players.push(player);
	return player;
}

async function openTab(index, extra) {
	const context = await browser.newContext({ viewport: { width: 960, height: 540 }, deviceScaleFactor: 1 });
	const page = await context.newPage();
	const player = watch(index, page);
	const url = urlFor({ name: index === 0 ? 'Wirt' : `Gast${index}`, character: CHARACTERS[index % CHARACTERS.length], ...extra });
	console.log(`tab ${index}: ${url}`);
	await page.goto(url, { waitUntil: 'load', timeout: LOAD_TIMEOUT_MS });
	return player;
}

const failures = [];
// The host plays a little longer, so the clients finish their measurement before it leaves.
const host = await openTab(0, { host: '1', lobby: String(tabs - 1), seconds: String(seconds + 15) });
const codeDeadline = Date.now() + LOAD_TIMEOUT_MS;
while (!host.code && Date.now() < codeDeadline) {
	await host.page.waitForTimeout(250);
}
if (!host.code) {
	failures.push('the host tab opened no room');
} else {
	console.log(`room ${host.code}`);
	for (let i = 1; i < tabs; i++) {
		await openTab(i, { room: host.code, lobby: '1', seconds: String(seconds) });
	}
	const deadline = Date.now() + LOAD_TIMEOUT_MS + (seconds + 40) * 1000;
	while (players.some((p) => !p.result) && Date.now() < deadline) {
		await host.page.waitForTimeout(1000);
	}
}
if (args['shot-dir']) {
	mkdirSync(args['shot-dir'], { recursive: true });
	for (const p of players) {
		await p.page.screenshot({ path: join(args['shot-dir'], `tab${p.index}.png`) }).catch(() => {});
	}
}
await browser.close();

for (const p of players) {
	const name = p.index === 0 ? 'host' : `client${p.index}`;
	for (const e of p.errors) {
		failures.push(`${name} console: ${e}`);
	}
	const r = p.result;
	if (!r) {
		failures.push(`${name}: no [RESULT] (${p.lines.slice(-3).join(' | ')})`);
		continue;
	}
	if (r.rejected) {
		failures.push(`${name}: refused (${r.rejected})`);
		continue;
	}
	const f = r.frame;
	const rep = r.replica;
	console.log(`${name}: ${r.run?.character} level ${r.run?.level}, fps ${f.fps_avg} (p95 ${f.frame_ms_p95} ms), draws max ${f.draw_calls_max}`
		+ (rep ? `, ${r.net?.kib_per_s_in} KiB/s down, Knödl ${rep.knodls_shown}, enemies ${rep.alive_shown}/${rep.alive_host}, pops ${rep.pops}` : ''));
	if (p.index > 0) {
		if (f.fps_avg < minFps) failures.push(`${name}: fps ${f.fps_avg} below ${minFps}`);
		if (!rep) {
			failures.push(`${name}: no replica stats`);
		} else {
			if (rep.knodls_shown < tabs) failures.push(`${name}: shows ${rep.knodls_shown} Knödl for ${tabs} players`);
			if (Math.abs(rep.alive_shown - rep.alive_host) > 10) failures.push(`${name}: shows ${rep.alive_shown} enemies, host ${rep.alive_host}`);
			if (rep.world_states < 10) failures.push(`${name}: only ${rep.world_states} world states`);
		}
		if (r.ended_reason) failures.push(`${name}: session ended early (${r.ended_reason})`);
	}
	if (f.draw_calls_max >= 150) failures.push(`${name}: ${f.draw_calls_max} draw calls`);
}
const characters = players.map((p) => p.result?.run?.character).filter(Boolean);
if (new Set(characters).size !== characters.length) failures.push(`two tabs played the same Knödlinger (${characters.join(', ')})`);
const report = { tabs, url: base, relay: args.relay || 'page origin', code: host.code, failures,
	players: players.map((p) => ({ index: p.index, errors: p.errors, lines: p.lines, stats: p.stats, result: p.result })) };
if (args.out) {
	mkdirSync(dirname(args.out), { recursive: true });
	writeFileSync(args.out, JSON.stringify(report, null, 2));
}
console.log(failures.length ? `RUN FAILED:\n  - ${failures.join('\n  - ')}` : `RUN PASSED (${tabs} tabs, room ${host.code})`);
process.exit(failures.length ? 1 : 0);
