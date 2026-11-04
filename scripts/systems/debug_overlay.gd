extends CanvasLayer
## F3 debug overlay (GAME-DESIGN.md): fps, enemy count, draw calls, frame time per system. Whoever
## owns the numbers calls show(); automated tests read the same numbers from the [STATS] log lines.
## A developer tool, but it still uses the theme (docs/UI-STYLE.md); it sits under the health panel.

var _label: Label


func _ready() -> void:
	layer = 100
	var root: Control = UiStyle.root(self)
	_label = UiStyle.label(&"HudSmall")
	_label.position = Vector2(16.0, 104.0)
	root.add_child(_label)


func show_text(text: String) -> void:
	_label.text = text


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_F3:
		visible = not visible
