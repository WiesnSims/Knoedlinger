// Minimal static server for the web build, used by the browser checks.
// Usage: node tools/browser/serve.mjs <dir> [port=8060]   (binds 127.0.0.1 only)
import { createReadStream, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize, resolve, sep } from 'node:path';

const dir = resolve(process.argv[2] || '.');
const port = Number(process.argv[3] || 8060);
const TYPES = {
	'.html': 'text/html; charset=utf-8',
	'.js': 'text/javascript; charset=utf-8',
	'.json': 'application/json',
	'.wasm': 'application/wasm',
	'.pck': 'application/octet-stream',
	'.png': 'image/png',
	'.svg': 'image/svg+xml',
	'.txt': 'text/plain; charset=utf-8',
};

createServer((request, response) => {
	const path = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
	// No Pages Functions here: the Ehrentafel answers "offline" (the game shows its offline line)
	// instead of a 404 that the checks would count as a console error.
	if (path.startsWith('/api/')) {
		response.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }).end('{"error":"offline"}');
		return;
	}
	const file = normalize(join(dir, path === '/' ? 'index.html' : path));
	if (!file.startsWith(dir + sep)) {
		response.writeHead(403).end();
		return;
	}
	let stats;
	try {
		stats = statSync(file);
	} catch {
		response.writeHead(404).end('Not found');
		return;
	}
	if (!stats.isFile()) {
		response.writeHead(404).end('Not found');
		return;
	}
	response.writeHead(200, {
		'Content-Type': TYPES[extname(file)] || 'application/octet-stream',
		'Content-Length': stats.size,
		'Cache-Control': 'no-store',
	});
	createReadStream(file).pipe(response);
}).listen(port, '127.0.0.1', () => console.log(`serving ${dir} on http://127.0.0.1:${port}`));
