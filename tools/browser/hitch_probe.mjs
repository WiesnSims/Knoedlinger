// Finds start-up hitches: loads the web build in a fresh browser profile (cold shader cache), lets the
// bot play, and prints every browser frame that took longer than --min-ms, next to the game's own
// console lines (same clock: ms since navigation).
//
//   node hitch_probe.mjs --url=http://127.0.0.1:8060/ [--seconds=40] [--min-ms=50] [--query=map=kirtag]
//        [--browser=msedge|firefox] [--menu] [--profile=<dir>]
//        [--shot=<png> --shot-ms=<ms>]
import { chromium, firefox } from 'playwright';

const args = Object.fromEntries(process.argv.slice(2).map((a) => {
	const [key, ...rest] = a.replace(/^--/, '').split('=');
	return [key, rest.length ? rest.join('=') : '1'];
}));
const seconds = Number(args.seconds || 40);
const minMs = Number(args['min-ms'] || 50);
const base = args.url || 'http://127.0.0.1:8060/';
// --menu: the plain URL (main menu, nothing started) watched for --seconds.
const query = args.menu ? 'mute=1' : `bot=1&respawn=1&mute=1&seconds=${seconds}${args.query ? '&' + args.query : ''}`;
const url = `${base}${base.includes('?') ? '&' : '?'}${query}`;

// --profile=<dir> keeps the browser profile (and its shader cache) between probes: a returning visitor.
const engine = args.browser === 'firefox' ? firefox : chromium;
const launch = args.browser === 'firefox' ? { headless: true } : { channel: 'msedge', headless: true,
	args: ['--enable-gpu', '--ignore-gpu-blocklist', '--use-angle=d3d11', '--mute-audio'] };
const viewport = { viewport: { width: 1280, height: 720 } };
const browser = args.profile
	? await engine.launchPersistentContext(args.profile, { ...launch, ...viewport })
	: await (await engine.launch(launch)).newContext(viewport);
const page = await browser.newPage();
await page.addInitScript((limit) => {
	// Shader programs: the browser compiles lazily, so the stall lands on the first status query or use.
	window.__programs = { linked: 0, ms: 0 };
	const gl = WebGL2RenderingContext.prototype;
	for (const name of ['linkProgram', 'getProgramParameter', 'getShaderParameter', 'useProgram']) {
		const original = gl[name];
		gl[name] = function (...parts) {
			const start = performance.now();
			const value = original.apply(this, parts);
			window.__programs.ms += performance.now() - start;
			if (name === 'linkProgram') window.__programs.linked++;
			return value;
		};
	}
	// Frames over the limit, and every frame that linked a shader program.
	window.__hitches = [];
	let last = performance.now();
	let linkedBefore = 0;
	const tick = (now) => {
		const linked = window.__programs.linked - linkedBefore;
		linkedBefore = window.__programs.linked;
		if (now - last > limit || linked > 0) window.__hitches.push([Math.round(last), Math.round(now - last), linked]);
		last = now;
		requestAnimationFrame(tick);
	};
	requestAnimationFrame(tick);
	window.__lines = [];
	for (const level of ['log', 'warn', 'error']) {
		const original = console[level].bind(console);
		console[level] = (...parts) => {
			const text = parts.join(' ');
			if (!text.startsWith('[STATS]')) {
				const p = window.__programs;
				window.__lines.push([Math.round(performance.now()), `${text.slice(0, 160)}   (programs ${p.linked}, ${Math.round(p.ms)} ms)`]);
			}
			original(...parts);
		};
	}
}, minMs);
let done = false;
page.on('console', (message) => { if (message.text().startsWith('[RESULT]')) done = true; });
await page.goto(url, { waitUntil: 'load', timeout: 90_000 });
// --shot=<png> --shot-ms=<ms>: a screenshot that long after load (e.g. the loading screen).
if (args.shot) setTimeout(() => page.screenshot({ path: args.shot }).catch(() => {}), Number(args['shot-ms'] || 6000));
const deadline = Date.now() + 90_000 + seconds * 1000;
if (args.menu) await page.waitForTimeout(seconds * 1000);
while (!args.menu && !done && Date.now() < deadline) await page.waitForTimeout(500);
const [hitches, lines, programs] = await page.evaluate(() => [window.__hitches, window.__lines, window.__programs]);
await browser.close();

const events = [...hitches.map(([t, ms, linked]) => [t, `frame ${ms} ms${linked ? `, ${linked} programs` : ''}`]), ...lines].sort((a, b) => a[0] - b[0]);
for (const [t, text] of events) console.log(`${(t / 1000).toFixed(2).padStart(7)} s  ${text}`);
const slow = hitches.filter(([, ms]) => ms > minMs);
const total = slow.reduce((sum, [, ms]) => sum + ms, 0);
console.log(`\n${slow.length} frames over ${minMs} ms, ${(total / 1000).toFixed(1)} s in total`);
console.log(`${programs.linked} shader programs linked, ${(programs.ms / 1000).toFixed(1)} s spent compiling`);
