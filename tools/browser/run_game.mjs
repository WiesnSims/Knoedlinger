// Loads the web build in a browser through Playwright, lets the bot play, and checks the result.
// Used by tools/stress_test.ps1 and tools/browser_check.ps1.
//
//   node run_game.mjs --url=http://127.0.0.1:8060/ --browser=msedge|firefox|chromium --seconds=60
//        --scene=run|stress --enemies=500 --projectiles=300 --min-fps=60 --max-p95=16.7
//        --max-draw-calls=150 --out=report.json --shot=shot.png [--headed]
//
// The game measures itself after a 3 s warm-up and prints [STATS] each second and one [RESULT]
// (scripts/run/run_world.gd, scripts/stress/stress_arena.gd). Frame-rate caps are lifted where the browser allows it, so the
// numbers show headroom instead of the monitor's refresh rate. A software WebGL renderer (no GPU)
// fails the run: its frame rate says nothing about real players.
// Exit code 0 = within budget and no console errors.
import { chromium, firefox } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';

const args = Object.fromEntries(process.argv.slice(2).map((a) => {
	const [key, ...rest] = a.replace(/^--/, '').split('=');
	return [key, rest.length ? rest.join('=') : '1'];
}));
const browserName = args.browser || 'msedge';
const seconds = Number(args.seconds || 60);
const headed = args.headed === '1';
const LOAD_TIMEOUT_MS = 90_000;
const SOFTWARE = /swiftshader|llvmpipe|softpipe|software|basic render|warp/i;

const query = new URLSearchParams({
	scene: args.scene || 'run',
	enemies: args.enemies || '500',
	projectiles: args.projectiles || '300',
	seconds: String(seconds),
	bot: '1',
	// Knocked down = back at the spawn, so a 60 s measurement never ends in the death screen.
	respawn: '1',
	// Count the host's snapshot encoding too, as if clients were connected.
	encode: '1',
});
const url = `${args.url || 'http://127.0.0.1:8060/'}${(args.url || '').includes('?') ? '&' : '?'}${query}`;

// A visible window is only used when headless rendering is not trustworthy: small, off-screen, muted.
const windowArgs = headed ? ['--window-size=1280,720', '--window-position=-2400,0', '--mute-audio'] : ['--mute-audio'];
let browser;
if (browserName === 'firefox') {
	browser = await firefox.launch({
		headless: !headed,
		firefoxUserPrefs: {
			// ASAP mode: draw as fast as possible instead of at the display's refresh rate.
			'layout.frame_rate': 0,
			'webgl.force-enabled': true,
			'media.autoplay.default': 0,
			'media.volume_scale': '0.0',
		},
	});
} else {
	browser = await chromium.launch({
		channel: browserName === 'msedge' ? 'msedge' : undefined,
		headless: !headed,
		args: [
			'--enable-gpu',
			'--ignore-gpu-blocklist',
			'--use-angle=d3d11',
			'--disable-gpu-vsync',
			'--disable-frame-rate-limit',
			'--autoplay-policy=no-user-gesture-required',
			...windowArgs,
		],
	});
}

const context = await browser.newContext({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1 });
const page = await context.newPage();
const errors = [];
const stats = [];
let result = null;
page.on('console', (message) => {
	const text = message.text();
	if (text.startsWith('[STATS] ')) {
		stats.push(JSON.parse(text.slice(8)));
	} else if (text.startsWith('[RESULT] ')) {
		result = JSON.parse(text.slice(9));
	}
	if (message.type() === 'error') {
		errors.push(text);
	}
	if (message.type() === 'warning' && /^(USER |SCRIPT )?(ERROR|WARNING):/.test(text)) {
		errors.push(text);
	}
});
page.on('pageerror', (error) => errors.push(`pageerror: ${error.message}`));

const renderer = await page.evaluate(() => {
	const gl = document.createElement('canvas').getContext('webgl2');
	if (!gl) {
		return 'no WebGL2';
	}
	const info = gl.getExtension('WEBGL_debug_renderer_info');
	return info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
});
console.log(`${browserName}: WebGL2 renderer ${renderer}`);
console.log(`loading ${url}`);
const started = Date.now();
await page.goto(url, { waitUntil: 'load', timeout: LOAD_TIMEOUT_MS });
const deadline = started + LOAD_TIMEOUT_MS + (seconds + 10) * 1000;
let lastPrinted = 0;
while (!result && Date.now() < deadline) {
	await page.waitForTimeout(500);
	if (stats.length > lastPrinted) {
		const s = stats[stats.length - 1];
		console.log(`  t=${s.t}s fps=${s.fps} enemies=${s.enemies} projectiles=${s.projectiles} draws=${s.draws}`);
		lastPrinted = stats.length;
	}
}
if (args.shot) {
	mkdirSync(dirname(args.shot), { recursive: true });
	await page.screenshot({ path: args.shot });
}
await browser.close();

const failures = [];
const software = SOFTWARE.test(renderer) || renderer === 'no WebGL2';
if (software) {
	failures.push(`software or missing WebGL2 renderer (${renderer}); fps not representative`);
}
if (!result) {
	failures.push('the game printed no [RESULT] in time');
} else {
	const f = result.frame;
	if (f.fps_avg < Number(args['min-fps'] || 60)) failures.push(`fps_avg ${f.fps_avg} below ${args['min-fps']}`);
	if (f.frame_ms_p95 > Number(args['max-p95'] || 16.7)) failures.push(`frame_ms_p95 ${f.frame_ms_p95} above ${args['max-p95']}`);
	if (f.draw_calls_max >= Number(args['max-draw-calls'] || 150)) failures.push(`draw_calls_max ${f.draw_calls_max} not below ${args['max-draw-calls']}`);
	if ((result.enemies_alive ?? 0) < Number(args.enemies || 500) * 0.98) failures.push(`only ${result.enemies_alive} enemies alive`);
}
for (const e of errors) {
	failures.push(`console: ${e}`);
}
const report = { browser: browserName, renderer, software, url, headed, result, errors, stats, failures };
if (args.out) {
	mkdirSync(dirname(args.out), { recursive: true });
	writeFileSync(args.out, JSON.stringify(report, null, 2));
}
if (result) {
	const f = result.frame;
	console.log(`${browserName}: fps_avg ${f.fps_avg}, frame ms p50 ${f.frame_ms_p50} / p95 ${f.frame_ms_p95} / p99 ${f.frame_ms_p99} / max ${f.frame_ms_max}, draw calls max ${f.draw_calls_max}`);
	console.log(`${browserName}: ms per frame ${JSON.stringify(f.system_ms_avg)}, enemies ${result.enemies_alive}, kills ${result.kills}, snapshot ${result.snapshot_bytes_avg} B`);
}
console.log(failures.length ? `RUN FAILED:\n  - ${failures.join('\n  - ')}` : `RUN PASSED (${browserName})`);
process.exit(failures.length ? 1 : 0);
