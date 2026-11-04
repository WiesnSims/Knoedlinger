class_name TouchControls
extends CanvasLayer
## On-screen controls for phones and tablets (GAME-DESIGN.md "Controls", touch column): a floating
## stick wherever the left thumb lands in the left part of the screen, Hupfn and Schupfn buttons
## bottom right, Pause and the Inventory under the clock, and dragging anywhere else on the right
## turns the camera. Everything feeds the normal input actions, so the player, the Speisekarte and
## the menus need no touch code of their own (taps on menus arrive as mouse clicks). Shown by the
## "Touch-Knöpfe" setting (Automatisch = once the screen is touched); hidden while a full-screen
## panel is up. One drawn control, so it costs a handful of draw calls.

const STICK_AREA: float = 0.45
const STICK_RADIUS: float = 64.0
const KNOB_RADIUS: float = 28.0
const JUMP_RADIUS: float = 52.0
const SCHUPFN_RADIUS: float = 40.0
const SMALL_RADIUS: float = 30.0
const EDGE: float = 16.0
## Top band where touches never start the stick or the camera (the HUD corners live there).
const TOP_BAND: float = 112.0
## The small buttons hang this far below the top edge, under the clock.
const SMALL_TOP: float = 96.0

signal layout_changed(clearance: float)

enum Kind { NONE, JUMP, SCHUPFN, PAUSE, INVENTORY }
## What a finger does when it is not on a button.
const STICK: int = 100
const LOOK: int = 101

## Asked every frame: true while a full-screen panel (Speisekarte, pause ...) owns the screen.
var covered: Callable = func() -> bool: return false
var camera: ChaseCamera
## Touches: finger index -> what it does (a Kind, or STICK / LOOK).
var _fingers: Dictionary[int, int] = {}
var _stick_origin: Vector2 = Vector2.ZERO
var _stick_at: Vector2 = Vector2.ZERO
var _stick_finger: int = -1
var _pressed: Dictionary[int, bool] = {}
var _view: TouchView
var _forced: bool = false
var _was_covered: bool = false
var _clearance: float = 0.0

func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_forced = LaunchArgs.get_flag("touch", false)
	_view = TouchView.new()
	_view.owner_controls = self
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	Settings.changed.connect(func(_key: StringName) -> void: _refresh())
	InputDevice.changed.connect(func(_kind: int) -> void: _refresh())
	_refresh()


## True when the controls are on screen and take touches.
func is_active() -> bool:
	return _view.visible


func _refresh() -> void:
	var mode: String = str(Settings.get_value(&"touch_controls"))
	var on: bool = _forced or mode == "on" or (mode == "auto" and InputDevice.is_touch())
	_view.visible = on and not covered.call()
	_view.scale_factor = Settings.get_float(&"touch_size")
	_view.modulate.a = Settings.get_float(&"touch_opacity")
	if not _view.visible:
		_release_all()
	_view.queue_redraw()
	var clearance: float = _view.clearance() if on else 0.0
	if clearance != _clearance:
		_clearance = clearance
		layout_changed.emit(clearance)


func _process(_delta: float) -> void:
	var now_covered: bool = covered.call()
	if now_covered != _was_covered:
		_was_covered = now_covered
		_refresh()


func _input(event: InputEvent) -> void:
	if not is_active():
		return
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_touch_down(touch.index, touch.position)
		else:
			_touch_up(touch.index)
		get_viewport().set_input_as_handled()
		return
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null and _fingers.has(drag.index):
		match _fingers[drag.index]:
			STICK:
				_move_stick(drag.position)
			LOOK:
				if camera != null:
					camera.touch_look(drag.relative)
		get_viewport().set_input_as_handled()


func _touch_down(finger: int, at: Vector2) -> void:
	var button: int = _view.button_at(at)
	if button != Kind.NONE:
		_fingers[finger] = button
		_press(button)
		return
	var size: Vector2 = _view.get_viewport_rect().size
	if at.y < TOP_BAND:
		return
	if at.x < size.x * STICK_AREA and _stick_finger < 0:
		_fingers[finger] = STICK
		_stick_finger = finger
		_stick_origin = at
		_stick_at = at
		_view.queue_redraw()
	else:
		_fingers[finger] = LOOK


func _touch_up(finger: int) -> void:
	if not _fingers.has(finger):
		return
	var what: int = _fingers[finger]
	_fingers.erase(finger)
	if what == STICK:
		_stick_finger = -1
		_set_move(Vector2.ZERO)
		_view.queue_redraw()
	elif what != LOOK:
		_release(what)


func _move_stick(at: Vector2) -> void:
	var reach: float = STICK_RADIUS * _view.scale_factor
	var offset: Vector2 = (at - _stick_origin).limit_length(reach)
	_stick_at = _stick_origin + offset
	_set_move(offset / reach)
	_view.queue_redraw()


func _set_move(v: Vector2) -> void:
	for pair: Array in [[&"move_left", -v.x], [&"move_right", v.x], [&"move_up", -v.y], [&"move_down", v.y]]:
		if pair[1] > 0.05:
			Input.action_press(pair[0], minf(pair[1], 1.0))
		else:
			Input.action_release(pair[0])


func _press(button: int) -> void:
	_pressed[button] = true
	_view.queue_redraw()
	match button:
		Kind.JUMP:
			Input.action_press(&"jump")
		Kind.SCHUPFN:
			Input.action_press(&"schupfn")
		Kind.PAUSE:
			_send_action(&"pause")
		Kind.INVENTORY:
			_send_action(&"inventory")


func _release(button: int) -> void:
	_pressed.erase(button)
	_view.queue_redraw()
	match button:
		Kind.JUMP:
			Input.action_release(&"jump")
		Kind.SCHUPFN:
			Input.action_release(&"schupfn")


## Pause and the Inventory listen for the action as an event, like a key press.
func _send_action(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)


func _release_all() -> void:
	for button: int in _pressed.keys():
		_release(button)
	_fingers.clear()
	_stick_finger = -1
	_set_move(Vector2.ZERO)


func stick_state() -> Array:
	return [_stick_finger >= 0, _stick_origin, _stick_at]


func is_pressed(button: int) -> bool:
	return _pressed.has(button)


## The drawing: one control, shapes only (palette colours, no textures or labels).
class TouchView:
	extends Control

	var owner_controls: TouchControls
	var scale_factor: float = 1.0

	## Centre and radius of every button, from the current size.
	func buttons() -> Dictionary:
		var s: float = scale_factor
		var view: Vector2 = get_viewport_rect().size if is_inside_tree() else size
		var w: float = view.x
		var h: float = view.y
		var jump := Vector2(w - TouchControls.EDGE - TouchControls.JUMP_RADIUS * s - 24.0, h - TouchControls.EDGE - TouchControls.JUMP_RADIUS * s - 24.0)
		var schupfn: Vector2 = jump + Vector2(-(TouchControls.JUMP_RADIUS + TouchControls.SCHUPFN_RADIUS + 24.0) * s, 28.0 * s)
		var pause := Vector2(w - TouchControls.EDGE - TouchControls.SMALL_RADIUS, TouchControls.SMALL_TOP + TouchControls.SMALL_RADIUS)
		var inventory: Vector2 = pause - Vector2(2.0 * TouchControls.SMALL_RADIUS + 16.0, 0.0)
		return {
			TouchControls.Kind.JUMP: [jump, TouchControls.JUMP_RADIUS * s],
			TouchControls.Kind.SCHUPFN: [schupfn, TouchControls.SCHUPFN_RADIUS * s],
			TouchControls.Kind.PAUSE: [pause, TouchControls.SMALL_RADIUS],
			TouchControls.Kind.INVENTORY: [inventory, TouchControls.SMALL_RADIUS],
		}

	## How far up from the bottom edge the big buttons reach, plus a gap.
	func clearance() -> float:
		var all: Dictionary = buttons()
		var bottom: float = get_viewport_rect().size.y
		var top: float = bottom
		for button: int in [TouchControls.Kind.JUMP, TouchControls.Kind.SCHUPFN]:
			top = minf(top, (all[button][0] as Vector2).y - float(all[button][1]))
		return bottom - top

	func button_at(at: Vector2) -> int:
		var all: Dictionary = buttons()
		for button: int in all:
			# A little extra reach: thumbs are not precise.
			if at.distance_to(all[button][0]) <= float(all[button][1]) + 12.0:
				return button
		return TouchControls.Kind.NONE

	func _draw() -> void:
		var panel: Color = Color(UiStyle.color("panel"), 0.55)
		var line: Color = Color(UiStyle.color("text"), 0.7)
		var accent: Color = UiStyle.color("accent")
		var all: Dictionary = buttons()
		for button: int in all:
			var centre: Vector2 = all[button][0]
			var radius: float = all[button][1]
			var down: bool = owner_controls.is_pressed(button)
			draw_circle(centre, radius, Color(accent, 0.45) if down else panel)
			draw_arc(centre, radius, 0.0, TAU, 48, line, 2.0, true)
			var r: float = radius * 0.42
			match button:
				TouchControls.Kind.JUMP:
					# An upward chevron.
					draw_polyline(PackedVector2Array([centre + Vector2(-r, r * 0.4), centre + Vector2(0.0, -r * 0.6),
							centre + Vector2(r, r * 0.4)]), line, 4.0, true)
				TouchControls.Kind.SCHUPFN:
					# The Knödl with a throw line.
					draw_circle(centre + Vector2(r * 0.3, 0.0), r * 0.75, UiStyle.color("knodl"))
					draw_line(centre + Vector2(-r * 1.3, -r * 0.4), centre + Vector2(-r * 0.6, -r * 0.4), line, 3.0, true)
					draw_line(centre + Vector2(-r * 1.3, r * 0.4), centre + Vector2(-r * 0.6, r * 0.4), line, 3.0, true)
				TouchControls.Kind.PAUSE:
					draw_rect(Rect2(centre + Vector2(-r * 0.7, -r), Vector2(r * 0.5, r * 2.0)), line)
					draw_rect(Rect2(centre + Vector2(r * 0.2, -r), Vector2(r * 0.5, r * 2.0)), line)
				TouchControls.Kind.INVENTORY:
					for k: int in 4:
						var cell := Vector2(-r + (k % 2) * r * 1.1, -r + floori(k / 2.0) * r * 1.1)
						draw_rect(Rect2(centre + cell, Vector2(r * 0.9, r * 0.9)), line)
		# The stick: where the thumb landed, or a faint hint where it usually goes.
		var stick: Array = owner_controls.stick_state()
		var s: float = scale_factor
		var origin: Vector2 = stick[1] if stick[0] else Vector2(TouchControls.EDGE + 64.0 + TouchControls.STICK_RADIUS * s, size.y - TouchControls.EDGE - 48.0 - TouchControls.STICK_RADIUS * s)
		var knob: Vector2 = stick[2] if stick[0] else origin
		var faint: float = 1.0 if stick[0] else 0.5
		draw_circle(origin, TouchControls.STICK_RADIUS * s, Color(panel, panel.a * faint))
		draw_arc(origin, TouchControls.STICK_RADIUS * s, 0.0, TAU, 48, Color(line, line.a * faint), 2.0, true)
		draw_circle(knob, TouchControls.KNOB_RADIUS * s, Color(accent, 0.8 * faint))
