class_name UiToggle
extends Button
## An on/off switch in the theme's colours: a pill track that fills with the accent and a knob that
## slides across. A flat toggle button (no box of its own), so the click and focus handling and the
## `toggled` signal are Godot's.

const TRACK := Vector2(40.0, 24.0)

var _knob: float = 0.0


func _init() -> void:
	toggle_mode = true
	flat = true
	custom_minimum_size = TRACK
	focus_mode = Control.FOCUS_ALL
	toggled.connect(func(_on: bool) -> void: _slide())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func set_on(on: bool) -> void:
	set_pressed_no_signal(on)
	_knob = 1.0 if on else 0.0
	queue_redraw()


func _slide() -> void:
	var tween: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(func(t: float) -> void:
		_knob = t
		queue_redraw(), _knob, 1.0 if button_pressed else 0.0, UiStyle.T_HOVER)


func _draw() -> void:
	var origin := Vector2(0.0, (size.y - TRACK.y) * 0.5)
	var radius: float = TRACK.y * 0.5
	var off: Color = UiStyle.color("track")
	var track: Color = off.lerp(UiStyle.color("accent"), _knob)
	var lit: bool = has_focus() or is_hovered()
	if lit:
		_pill(origin - Vector2(2.0, 2.0), TRACK + Vector2(4.0, 4.0), Color(UiStyle.color("accent"), 0.3))
	_pill(origin, TRACK, track)
	var x: float = lerpf(radius, TRACK.x - radius, _knob)
	draw_circle(origin + Vector2(x, radius), radius - 4.0, UiStyle.color("text"))


func _pill(at: Vector2, extent: Vector2, color: Color) -> void:
	var r: float = extent.y * 0.5
	draw_rect(Rect2(at.x + r, at.y, extent.x - 2.0 * r, extent.y), color)
	draw_circle(at + Vector2(r, r), r, color)
	draw_circle(at + Vector2(extent.x - r, r), r, color)
