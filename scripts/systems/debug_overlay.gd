extends CanvasLayer
## F3 debug overlay (GAME-DESIGN.md): fps, enemy count, draw calls, frame time per system. Whoever
## owns the numbers calls show(); automated tests read the same numbers from the [STATS] log lines.

var _label: Label


func _ready() -> void:
	layer = 100
	_label = Label.new()
	# Below the HUD's HP bar.
	_label.position = Vector2(12.0, 44.0)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)


func show_text(text: String) -> void:
	_label.text = text


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_F3:
		visible = not visible
