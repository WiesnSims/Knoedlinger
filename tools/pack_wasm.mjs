// Prepares a Godot web export for Cloudflare Pages (taken over from Berghittn's tools/build_web.mjs).
// Usage: node tools/pack_wasm.mjs build/web   (tools/build_web.ps1 runs it after the export)
//
// Pages rejects files over 25 MiB, and the Godot 4.7 engine wasm is ~38 MiB. We gzip it ourselves
// (Pages serves unknown types uncompressed), split it into parts if it is still too big, and
// web/wasm_parts_loader.js puts it back together in the browser. Then web/* is copied next to the
// export and every file size is listed. Exits 1 if any file is over 25 MiB.
import { copyFileSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync, constants } from 'node:zlib';

const MIB = 1024 * 1024;
const LIMIT_BYTES = 25 * MIB;
const MAX_PART_BYTES = 16 * MIB;
const PCK_TARGET_BYTES = 15 * MIB;

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const dir = resolve(process.argv[2] || join(root, 'build', 'web'));
const wasm = join(dir, 'index.wasm');

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
writeFileSync(join(dir, 'index.wasm.parts.json'), JSON.stringify({ encoding: 'gzip', parts: names }));

const webDir = join(root, 'web');
for (const file of readdirSync(webDir).filter((f) => !f.startsWith('.') || f === '_headers')) {
	copyFileSync(join(webDir, file), join(dir, file));
}

let tooBig = false;
console.log(`\nwasm: ${(size / MIB).toFixed(2)} MiB, gzipped ${(gz.length / MIB).toFixed(2)} MiB in ${count} part(s)\n`);
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
	console.log('\nFAIL: a file is over the Cloudflare Pages limit of 25 MiB');
}
process.exit(tooBig ? 1 : 0);
