extends CanvasLayer
## F3 debug overlay (GAME-DESIGN.md): fps, enemy count, draw calls, frame time per system. Whoever
## owns the numbers calls show(); automated tests read the same numbers from the [STATS] log lines.
## A developer tool, but it still uses the theme (docs/UI-STYLE.md); it sits under the health panel.
## In the web build it also keeps `window.knoedlDraws` (most draw calls of a frame in the last 0.25 s)
## up to date, even while a menu pauses the game, so tools/ui_shots.ps1 can check UI screens.

var _label: Label
var _draws_max: int = 0
var _draws_timer: float = 0.0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root: Control = UiStyle.root(self)
	_label = UiStyle.label(&"HudSmall")
	_label.position = Vector2(16.0, 104.0)
	root.add_child(_label)


func _process(delta: float) -> void:
	if not OS.has_feature("web"):
		return
	_draws_max = maxi(_draws_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	_draws_timer += delta
	if _draws_timer >= 0.25:
		JavaScriptBridge.eval("window.knoedlDraws = %d;" % _draws_max)
		_draws_max = 0
		_draws_timer = 0.0


func show_text(text: String) -> void:
	_label.text = text


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_F3:
		visible = not visible
