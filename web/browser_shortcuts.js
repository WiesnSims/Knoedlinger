// Godot's web runtime calls preventDefault() on every key while the canvas has focus, which
// swallows browser shortcuts like F5. Stop these keys in the capture phase, before they reach
// the canvas, so the browser handles them. None of them are game controls.
(function () {
	const PASS_THROUGH = new Set(['F5', 'F11', 'F12']);
	window.addEventListener('keydown', (e) => {
		const reloadCombo = (e.ctrlKey || e.metaKey) && e.code === 'KeyR';
		if (PASS_THROUGH.has(e.key) || reloadCombo) {
			e.stopImmediatePropagation();
		}
	}, true);
})();
