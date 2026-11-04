// Render resolution for the quality levels (scripts/systems/quality_scaler.gd, docs/DECISIONS.md M5).
// Godot sizes its canvas as CSS size x window.devicePixelRatio and reads the ratio on every resize
// check, so handing it a smaller ratio shrinks the whole backbuffer and the browser scales it up.
// That costs nothing per frame, unlike Godot's 3D render scale in the Compatibility renderer, which
// draws into an extra buffer and copies it. The game sets the ratio with knoedlSetPixelRatio().
(function () {
	const own = Object.getOwnPropertyDescriptor(window, 'devicePixelRatio')
		|| Object.getOwnPropertyDescriptor(Window.prototype, 'devicePixelRatio');
	if (!own || !own.get) {
		return;
	}
	const real = () => own.get.call(window) || 1;
	let wanted = 0;
	try {
		Object.defineProperty(window, 'devicePixelRatio', {
			configurable: true,
			get: () => (wanted > 0 ? wanted : real()),
		});
	} catch (e) {
		return;
	}
	// The real ratio of the screen (a phone: about 2.6).
	window.knoedlRealPixelRatio = real;
	// ratio <= 0: the screen's own again.
	window.knoedlSetPixelRatio = function (ratio) {
		wanted = ratio > 0 ? ratio : 0;
		window.dispatchEvent(new Event('resize'));
	};
})();
