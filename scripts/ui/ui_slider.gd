class_name UiSlider
extends Range
## A slider in the theme's colours (docs/UI-STYLE.md: drawn widgets read the Palette): a dark track,
## an accent fill and a round knob. Drag or click with the mouse; Left/Right step it when focused.
## One control, a few draw commands, no textures.

const TRACK_HEIGHT: float = 4.0
const KNOB: float = 8.0

var _dragging: bool = false


func _init() -> void:
	custom_minimum_size = Vector2(192.0, 24.0)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	value_changed.connect(func(_v: float) -> void: queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _draw() -> void:
	var y: float = size.y * 0.5
	var left: float = KNOB
	var right: float = size.x - KNOB
	var t: float = 0.0 if max_value <= min_value else (value - min_value) / (max_value - min_value)
	var at: float = lerpf(left, right, t)
	draw_rect(Rect2(left, y - TRACK_HEIGHT * 0.5, right - left, TRACK_HEIGHT), UiStyle.color("track"))
	draw_rect(Rect2(left, y - TRACK_HEIGHT * 0.5, at - left, TRACK_HEIGHT), UiStyle.color("accent"))
	var lit: bool = has_focus() or _dragging or get_global_rect().has_point(get_global_mouse_position())
	if lit:
		draw_circle(Vector2(at, y), KNOB + 4.0, Color(UiStyle.color("accent"), 0.25))
	draw_circle(Vector2(at, y), KNOB, UiStyle.color("text"))


func _gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		_dragging = click.pressed
		if click.pressed:
			grab_focus()
			_set_from(click.position.x)
		accept_event()
		queue_redraw()
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and _dragging:
		_set_from(motion.position.x)
		accept_event()
		return
	if event.is_action_pressed(&"ui_left", true):
		value -= step if step > 0.0 else (max_value - min_value) / 20.0
		accept_event()
	elif event.is_action_pressed(&"ui_right", true):
		value += step if step > 0.0 else (max_value - min_value) / 20.0
		accept_event()


func _set_from(x: float) -> void:
	var t: float = clampf((x - KNOB) / maxf(size.x - 2.0 * KNOB, 1.0), 0.0, 1.0)
	value = lerpf(min_value, max_value, t)
