// Screenshots of the game at chosen moments, for checking how menus and effects look (headless Edge).
//   node screenshots.mjs --url=http://127.0.0.1:8061/?bot=1 --out=../../build/shots/m2 --at=4,12,30 [--echo=[SLOW]]
//        [--move=10:10,640:360,10:10]   (mouse position before each shot)
//        [--size=1920x1080]              (viewport, default 1280x720)
//        [--keys=,Tab,]                   (key pressed before each shot, empty = none; "Escape+Enter" =
//                                          several in a row, "type:Resi" types text)
//        [--max-draws=150]                (fail when a moment needs this many draw calls or more)
// Saves <out>-<seconds>s.png per moment (and prints the draw calls of that moment) and exits 1 on any console error. --echo prints every console
// line that starts with the given text.
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const args = Object.fromEntries(process.argv.slice(2).map((a) => {
	const [key, ...rest] = a.replace(/^--/, '').split('=');
	return [key, rest.join('=')];
}));
const browser = await chromium.launch({
	channel: 'msedge',
	headless: true,
	args: ['--enable-gpu', '--ignore-gpu-blocklist', '--use-angle=d3d11', '--mute-audio'],
});
const [width, height] = (args.size || '1280x720').split('x').map(Number);
const page = await (await browser.newContext({ viewport: { width, height } })).newPage();
const errors = [];
page.on('console', (message) => {
	if (args.echo && message.text().startsWith(args.echo)) {
		console.log(message.text());
	}
	if (message.type() === 'error' || /^(USER |SCRIPT )?(ERROR|WARNING):/.test(message.text())) {
		errors.push(message.text());
	}
});
page.on('pageerror', (error) => errors.push(`pageerror: ${error.message}`));
mkdirSync(dirname(args.out), { recursive: true });
await page.goto(args.url, { waitUntil: 'load', timeout: 90_000 });
const started = Date.now();
for (const at of args.at.split(',').map(Number)) {
	const wait = started + at * 1000 - Date.now();
	if (wait > 0) {
		await page.waitForTimeout(wait);
	}
	if (args.move) {
		// One mouse position per moment (x:y, joined by commas), e.g. to hover a card.
		const point = args.move.split(',')[Math.min(args.at.split(',').indexOf(String(at)), args.move.split(',').length - 1)];
		const [x, y] = point.split(':').map(Number);
		// In steps: Godot only updates hover from real motion across the canvas.
		await page.mouse.move(x, y + 40, { steps: 2 });
		await page.mouse.move(x, y, { steps: 4 });
		await page.waitForTimeout(300);
	}
	if (args.keys) {
		const key = args.keys.split(',')[Math.min(args.at.split(',').indexOf(String(at)), args.keys.split(',').length - 1)];
		// "Escape+ArrowDown+Enter" presses one after another; "type:Resi" types text.
		for (const step of key ? key.split('+') : []) {
			if (step.startsWith('type:')) {
				await page.keyboard.type(step.slice(5), { delay: 60 });
			} else {
				await page.keyboard.press(step);
			}
			await page.waitForTimeout(250);
		}
		if (key) {
			await page.waitForTimeout(300);
		}
	}
	await page.screenshot({ path: `${args.out}-${at}s.png` });
	await page.waitForTimeout(300);
	const draws = await page.evaluate(() => window.knoedlDraws ?? -1);
	console.log(`shot ${args.out}-${at}s.png draws=${draws}`);
	if (args['max-draws'] && draws >= Number(args['max-draws'])) {
		errors.push(`${draws} draw calls at ${at} s (budget below ${args['max-draws']})`);
	}
}
await browser.close();
console.log(errors.length ? `errors:\n  ${errors.join('\n  ')}` : 'no console errors');
process.exit(errors.length ? 1 : 0);
