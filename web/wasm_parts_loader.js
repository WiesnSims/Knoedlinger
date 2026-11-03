// Cloudflare Pages rejects single files over 25 MiB, but the Godot engine wasm is larger.
// tools/pack_wasm.mjs (run by tools/build_web.ps1) gzips and splits it; this shim reassembles and inflates it so Godot's loader sees one normal wasm response.
(function () {
	const originalFetch = window.fetch.bind(window);

	async function fetchSplitWasm(wasmUrl, init) {
		let manifest;
		try {
			const response = await originalFetch(wasmUrl + '.parts.json', init);
			if (!response.ok) {
				return null;
			}
			manifest = await response.json();
		} catch (e) {
			// No valid manifest (e.g. an unsplit local export, or an SPA fallback page): load the wasm normally.
			return null;
		}
		const base = new URL(wasmUrl, location.href);
		// Start all downloads in parallel, but fail the whole fetch up front so Godot's own retry logic kicks in.
		const responses = await Promise.all(manifest.parts.map((name) => originalFetch(new URL(name, base), init)));
		const bad = responses.find((r) => !r.ok);
		if (bad) {
			throw new Error(`Failed loading wasm part '${bad.url}' (${bad.status})`);
		}
		const joined = new ReadableStream({
			async start(controller) {
				for (const response of responses) {
					const reader = response.body.getReader();
					for (;;) {
						const { done, value } = await reader.read();
						if (done) {
							break;
						}
						controller.enqueue(value);
					}
				}
				controller.close();
			},
		});
		const body = manifest.encoding === 'gzip' ? joined.pipeThrough(new DecompressionStream('gzip')) : joined;
		return new Response(body, { headers: { 'Content-Type': 'application/wasm' } });
	}

	window.fetch = async function (input, init) {
		const url = typeof input === 'string' || input instanceof URL ? String(input) : input.url;
		if (new URL(url, location.href).pathname.endsWith('.wasm')) {
			const split = await fetchSplitWasm(url, init);
			if (split) {
				return split;
			}
		}
		return originalFetch(input, init);
	};
})();
