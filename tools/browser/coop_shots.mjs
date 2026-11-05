// UI screenshots of co-op (M6), for tools/ui_shots.ps1 -Only coop: two players go through the real
// menus. The host names itself, opens "Stammtisch aufmachen" (offline view), opens a room (alone),
// a guest joins with an invite link (?room=CODE), both see the full room, the host starts, and both
// HUDs are shot a while into the run (the family panel, teammate markers).
//
//   node coop_shots.mjs --url=http://127.0.0.1:8062/ --out=<dir>/coop-1920x1080 --size=1920x1080
//        [--relay=ws://127.0.0.1:8790] [--max-draws=150]
// Saves <out>-<moment>.png and exits 1 on console errors or a moment at --max-draws or more.
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const args = Object.fromEntries(process.argv.slice(2).map((a) => {
	const [key, ...rest] = a.replace(/^--/, '').split('=');
	return [key, rest.join('=')];
}));
const [width, height] = (args.size || '1280x720').split('x').map(Number);
const maxDraws = Number(args['max-draws'] || 150);
const base = args.url || 'http://127.0.0.1:8062/';
const browser = await chromium.launch({
	channel: 'msedge',
	headless: true,
	args: ['--enable-gpu', '--ignore-gpu-blocklist', '--use-angle=d3d11', '--mute-audio'],
});
const errors = [];
const failures = [];

function urlFor(extra) {
	const query = new URLSearchParams({ mute: '1', debug: '0', ...extra });
	if (args.relay) {
		query.set('relay', args.relay);
	}
	return `${base}${base.includes('?') ? '&' : '?'}${query}`;
}

async function open(name, extra) {
	const page = await (await browser.newContext({ viewport: { width, height } })).newPage();
	const player = { name, page, code: '' };
	page.on('console', (message) => {
		const text = message.text();
		const room = text.match(/^\[NET\] ROOM ([A-Z]{4}) open/);
		if (room) {
			player.code = room[1];
		}
		if (message.type() === 'error' || (message.type() === 'warning' && /^(USER |SCRIPT )?(ERROR|WARNING):/.test(text))) {
			errors.push(`${name}: ${text}`);
		}
	});
	page.on('pageerror', (error) => errors.push(`${name}: pageerror ${error.message}`));
	await page.goto(urlFor(extra), { waitUntil: 'load', timeout: 120_000 });
	return player;
}

async function keys(player, list) {
	// Two pages: only the one in front gets the keys.
	await player.page.bringToFront();
	for (const key of list) {
		if (key.startsWith('type:')) {
			await player.page.keyboard.type(key.slice(5), { delay: 40 });
		} else {
			await player.page.keyboard.press(key);
		}
		await player.page.waitForTimeout(120);
	}
}

async function shot(player, moment) {
	const path = `${args.out}-${moment}.png`;
	mkdirSync(dirname(path), { recursive: true });
	await player.page.screenshot({ path });
	const draws = await player.page.evaluate(() => window.knoedlDraws ?? -1);
	console.log(`${moment}: ${draws} draw calls -> ${path}`);
	if (draws >= maxDraws) {
		failures.push(`${moment}: ${draws} draw calls`);
	}
}

const host = await open('host', { coop: '1' });
await host.page.waitForTimeout(12_000);
await keys(host, ['type:Wirt', 'Enter']);
await host.page.waitForTimeout(1500);
await shot(host, 'offline');
await keys(host, ['Enter']);
for (let i = 0; i < 40 && !host.code; i++) {
	await host.page.waitForTimeout(250);
}
if (!host.code) {
	failures.push('the host opened no room');
} else {
	await host.page.waitForTimeout(1000);
	await shot(host, 'room-alone');
	const guest = await open('guest', { room: host.code });
	await guest.page.waitForTimeout(12_000);
	await keys(guest, ['type:Resi', 'Enter']);
	await guest.page.waitForTimeout(3000);
	await shot(guest, 'room-guest');
	await shot(host, 'room-full');
	await keys(host, ['Enter']);
	await host.page.waitForTimeout(16_000);
	// Co-op Speisekarte (the game runs on), then the HUD with the family panel once both picked.
	await shot(guest, 'menu-guest');
	// Both pick in turn (standing still, they would be knocked down before long).
	for (let i = 0; i < 12; i++) {
		for (const p of [host, guest]) {
			await keys(p, ['Digit1']);
			await p.page.waitForTimeout(150);
		}
	}
	await host.page.waitForTimeout(800);
	await shot(host, 'hud-host');
	await shot(guest, 'hud-guest');
}
await browser.close();
for (const e of errors) {
	failures.push(`console: ${e}`);
}
console.log(failures.length ? `SHOTS FAILED:\n  - ${failures.join('\n  - ')}` : 'SHOTS DONE');
process.exit(failures.length ? 1 : 0);
