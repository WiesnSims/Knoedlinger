class_name UiChoice
extends Control
## A choice between a few named values in the theme's colours:  ‹  Auto  ›. Click the left or right
## half, or Left/Right (D-pad) while focused, to step; it wraps around. Drawn like UiSlider (one
## control, a few draw commands), so it costs no extra draw calls for labels or buttons.

signal chosen(index: int)

const CHEVRON: float = 8.0

## Already translated names, one per value.
var names: PackedStringArray = PackedStringArray()
var index: int = 0


func _init() -> void:
	custom_minimum_size = Vector2(192.0, 32.0)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func set_index_no_signal(value: int) -> void:
	index = clampi(value, 0, maxi(names.size() - 1, 0))
	queue_redraw()


func step(by: int) -> void:
	if names.is_empty():
		return
	index = posmod(index + by, names.size())
	queue_redraw()
	chosen.emit(index)


func _draw() -> void:
	var y: float = size.y * 0.5
	var lit: bool = has_focus() or get_global_rect().has_point(get_global_mouse_position())
	var tone: Color = UiStyle.color("accent") if lit else UiStyle.color("muted")
	if lit:
		draw_rect(Rect2(Vector2(0.0, y + 12.0), Vector2(size.x, 2.0)), Color(UiStyle.color("accent"), 0.5))
	# ‹ on the left, › on the right.
	for right: bool in [false, true]:
		var tip_x: float = size.x - CHEVRON * 0.5 if right else CHEVRON * 0.5
		var arm_x: float = tip_x + (-CHEVRON if right else CHEVRON) * 0.7
		draw_polyline(PackedVector2Array([Vector2(arm_x, y - CHEVRON * 0.7), Vector2(tip_x, y),
				Vector2(arm_x, y + CHEVRON * 0.7)]), tone, 2.0, true)
	if names.is_empty():
		return
	var font: Font = UiStyle.font("bold")
	var font_size: int = UiStyle.font_size("small")
	var text: String = names[index]
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline: float = y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, Vector2((size.x - width) * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			UiStyle.color("text"))


func _gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		if click.pressed:
			grab_focus()
			step(-1 if click.position.x < size.x * 0.5 else 1)
			GameAudio.play(&"ui_hover")
		accept_event()
		return
	if event.is_action_pressed(&"ui_left", true):
		step(-1)
		accept_event()
	elif event.is_action_pressed(&"ui_right", true) or event.is_action_pressed(&"ui_accept"):
		step(1)
		accept_event()
