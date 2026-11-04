// Prepares a Godot web export for Cloudflare Pages (taken over from Berghittn's tools/build_web.mjs).
// Usage: node tools/pack_wasm.mjs build/web   (tools/build_web.ps1 runs it after the export)
//
// Pages rejects files over 25 MiB, and the Godot 4.7 engine wasm is ~38 MiB. We gzip it ourselves
// (Pages serves unknown types uncompressed), split it into parts if it is still too big, and
// web/wasm_parts_loader.js puts it back together in the browser. Then (M5, docs/DECISIONS.md):
// every engine file gets a content hash in its name (k-<hash>.js, .pck, .wasm.part0 ...) so _headers
// can cache them for a year while index.html is always revalidated; the loading screen in
// web/shell.html gets its text from i18n/strings.csv and its title font. Then web/* is copied next
// to the export and every file size is listed. Exits 1 if any file is over 25 MiB or a placeholder
// in index.html was left unfilled.
import { copyFileSync, readFileSync, readdirSync, renameSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync, constants } from 'node:zlib';

const MIB = 1024 * 1024;
const LIMIT_BYTES = 25 * MIB;
const MAX_PART_BYTES = 16 * MIB;
const PCK_TARGET_BYTES = 15 * MIB;
// Files of web/ that are templates for the export, not part of the site.
const TEMPLATES = new Set(['shell.html']);

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const dir = resolve(process.argv[2] || join(root, 'build', 'web'));
const wasm = join(dir, 'index.wasm');
const problems = [];

const size = statSync(wasm).size;
const gz = gzipSync(readFileSync(wasm), { level: constants.Z_BEST_COMPRESSION });
const count = Math.ceil(gz.length / MAX_PART_BYTES);
const partSize = Math.ceil(gz.length / count);
const names = [];
for (let i = 0; i < count; i++) {
	const name = `index.wasm.part${i}`;
	writeFileSync(join(dir, name), gz.subarray(i * partSize, (i + 1) * partSize));
	names.push(name);
}
rmSync(wasm);

// Hashed names: one hash over everything the engine loads, so a new build never meets an old cache.
const hash = createHash('sha256');
hash.update(gz);
for (const file of ['index.pck', 'index.js', 'index.audio.worklet.js', 'index.audio.position.worklet.js']) {
	hash.update(readFileSync(join(dir, file)));
}
const stem = `k-${hash.digest('hex').slice(0, 10)}`;
let html = readFileSync(join(dir, 'index.html'), 'utf8');
// The wasm itself only exists as parts; Godot still asks for "<stem>.wasm" (and its size).
html = html.replace('"executable":"index"', `"executable":"${stem}"`).replace('"index.wasm":', `"${stem}.wasm":`);
for (const file of readdirSync(dir)) {
	if (!file.startsWith('index.') || file === 'index.html') {
		continue;
	}
	const renamed = stem + file.slice('index'.length);
	renameSync(join(dir, file), join(dir, renamed));
	html = html.split(`"${file}"`).join(`"${renamed}"`);
}
writeFileSync(join(dir, `${stem}.wasm.parts.json`),
	JSON.stringify({ encoding: 'gzip', parts: names.map((n) => stem + n.slice('index'.length)) }));

// The title font of the loading screen, named by its own hash (it rarely changes).
const font = readFileSync(join(root, 'assets', 'fonts', 'grenze_gotisch.ttf'));
const fontName = `k-${createHash('sha256').update(font).digest('hex').slice(0, 10)}.ttf`;
writeFileSync(join(dir, fontName), font);
html = html.replace("/*KNOEDL_TITLE_FONT*/", fontName);

// Player-facing text from the translation CSV (CLAUDE.md: never hard-coded).
const strings = readStrings(join(root, 'i18n', 'strings.csv'));
const escape = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
html = html.replace(/\{\{(js:)?([A-Z0-9_]+)\}\}/g, (match, js, key) => {
	if (!(key in strings)) {
		problems.push(`index.html: no string ${key} in i18n/strings.csv`);
		return match;
	}
	return js ? JSON.stringify(strings[key]) : escape(strings[key]);
});
const jokes = Object.keys(strings).filter((k) => k.startsWith('LOADING_JOKE_')).sort().map((k) => strings[k]);
html = html.replace('/*KNOEDL_JOKES*/[]', JSON.stringify(jokes));
for (const left of html.match(/\{\{[^}]*\}\}|\/\*KNOEDL_[A-Z_]+\*\/|\$GODOT_[A-Z_]+/g) || []) {
	problems.push(`index.html: placeholder ${left} left unfilled`);
}
writeFileSync(join(dir, 'index.html'), html);

const webDir = join(root, 'web');
for (const file of readdirSync(webDir).filter((f) => (!f.startsWith('.') || f === '_headers') && !TEMPLATES.has(f))) {
	copyFileSync(join(webDir, file), join(dir, file));
}

let tooBig = false;
console.log(`\nwasm: ${(size / MIB).toFixed(2)} MiB, gzipped ${(gz.length / MIB).toFixed(2)} MiB in ${count} part(s); files as ${stem}.*, ${jokes.length} loading jokes\n`);
for (const file of readdirSync(dir).sort()) {
	const bytes = statSync(join(dir, file)).size;
	let flag = '';
	if (bytes > LIMIT_BYTES) {
		flag = '  <-- OVER 25 MiB';
		tooBig = true;
	} else if (file.endsWith('.pck') && bytes > PCK_TARGET_BYTES) {
		flag = '  (note: above the 15 MiB pck target)';
	}
	console.log(`${(bytes / MIB).toFixed(2).padStart(8)} MiB  ${file}${flag}`);
}
if (tooBig) {
	problems.push('a file is over the Cloudflare Pages limit of 25 MiB');
}
for (const p of problems) {
	console.log(`FAIL: ${p}`);
}
process.exit(problems.length ? 1 : 0);

// key,de CSV with optional "quoted, values" ("" inside quotes is a quote).
function readStrings(path) {
	const out = {};
	const lines = readFileSync(path, 'utf8').split(/\r?\n/).slice(1);
	for (const line of lines) {
		if (!line.trim()) {
			continue;
		}
		const cells = [];
		let cell = '';
		let quoted = false;
		for (let i = 0; i < line.length; i++) {
			const c = line[i];
			if (quoted) {
				if (c === '"' && line[i + 1] === '"') {
					cell += '"';
					i++;
				} else if (c === '"') {
					quoted = false;
				} else {
					cell += c;
				}
			} else if (c === '"') {
				quoted = true;
			} else if (c === ',') {
				cells.push(cell);
				cell = '';
			} else {
				cell += c;
			}
		}
		cells.push(cell);
		out[cells[0]] = cells[1] ?? '';
	}
	return out;
}
