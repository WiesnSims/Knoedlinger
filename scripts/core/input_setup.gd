class_name InputSetup
extends RefCounted
## Registers the input actions in code, so project.godot needs no hand-written InputEvent blobs.
## Controls follow GAME-DESIGN.md ("Controls"): keyboard and mouse, and a gamepad in the Xbox layout
## (left stick moves, right stick looks, A jumps, RB or RT throws, Start pauses, View/Back opens the
## inventory; X / Y / LB answer the Speisekarte). Touch feeds the same actions (TouchControls).
## Menus use Godot's ui_* actions, which already know the D-pad, the left stick, A and B.

const KEYS: Dictionary[StringName, Array] = {
	&"move_up": [KEY_W, KEY_UP],
	&"move_down": [KEY_S, KEY_DOWN],
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"jump": [KEY_SPACE],
	&"schupfn": [KEY_SHIFT],
	&"pause": [KEY_ESCAPE],
	&"debug_overlay": [KEY_F3],
	&"camera_left": [KEY_Q],
	&"camera_right": [KEY_E],
	## The right stick (the mouse looks by itself, ChaseCamera).
	&"look_left": [],
	&"look_right": [],
	&"look_up": [],
	&"look_down": [],
	&"inventory": [KEY_TAB, KEY_I],
	&"card_reroll": [KEY_R],
	&"card_banish": [KEY_B],
	&"card_skip": [KEY_N],
	## Pad-only page and value steps in the menus (keyboard screens keep their own keys).
	&"shoulder_left": [],
	&"shoulder_right": [],
	&"trigger_left": [],
	&"trigger_right": [],
}
const MOUSE: Dictionary[StringName, Array] = {
	&"schupfn": [MOUSE_BUTTON_RIGHT],
}
const PAD_BUTTONS: Dictionary[StringName, Array] = {
	&"jump": [JOY_BUTTON_A],
	&"schupfn": [JOY_BUTTON_RIGHT_SHOULDER],
	&"pause": [JOY_BUTTON_START],
	&"inventory": [JOY_BUTTON_BACK],
	&"card_reroll": [JOY_BUTTON_X],
	&"card_banish": [JOY_BUTTON_Y],
	&"card_skip": [JOY_BUTTON_LEFT_SHOULDER],
	&"shoulder_left": [JOY_BUTTON_LEFT_SHOULDER],
	&"shoulder_right": [JOY_BUTTON_RIGHT_SHOULDER],
}
## [axis, direction] pairs.
const PAD_AXES: Dictionary[StringName, Array] = {
	&"move_up": [[JOY_AXIS_LEFT_Y, -1.0]],
	&"move_down": [[JOY_AXIS_LEFT_Y, 1.0]],
	&"move_left": [[JOY_AXIS_LEFT_X, -1.0]],
	&"move_right": [[JOY_AXIS_LEFT_X, 1.0]],
	&"look_left": [[JOY_AXIS_RIGHT_X, -1.0]],
	&"look_right": [[JOY_AXIS_RIGHT_X, 1.0]],
	&"look_up": [[JOY_AXIS_RIGHT_Y, -1.0]],
	&"look_down": [[JOY_AXIS_RIGHT_Y, 1.0]],
	&"schupfn": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	&"trigger_left": [[JOY_AXIS_TRIGGER_LEFT, 1.0]],
	&"trigger_right": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]],
}
const DEADZONE: float = 0.2
## Triggers count as pressed past half way, so resting fingers do not fire.
const TRIGGER_DEADZONE: float = 0.5


static func ensure_actions() -> void:
	for action: StringName in KEYS:
		if InputMap.has_action(action):
			continue
		var trigger: bool = action == &"trigger_left" or action == &"trigger_right"
		InputMap.add_action(action, TRIGGER_DEADZONE if trigger else DEADZONE)
		for key: Key in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
		for button: MouseButton in MOUSE.get(action, []):
			var click := InputEventMouseButton.new()
			click.button_index = button
			InputMap.action_add_event(action, click)
		for pad_button: JoyButton in PAD_BUTTONS.get(action, []):
			var press := InputEventJoypadButton.new()
			press.button_index = pad_button
			InputMap.action_add_event(action, press)
		for pair: Array in PAD_AXES.get(action, []):
			var motion := InputEventJoypadMotion.new()
			motion.axis = pair[0]
			motion.axis_value = pair[1]
			InputMap.action_add_event(action, motion)
