class_name InputSetup
extends RefCounted
## Registers the input actions in code, so project.godot needs no hand-written InputEvent blobs.
## Controls follow GAME-DESIGN.md ("Controls"); gamepad and touch come in M5.

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
}
const MOUSE: Dictionary[StringName, Array] = {
	&"schupfn": [MOUSE_BUTTON_RIGHT],
}


static func ensure_actions() -> void:
	for action: StringName in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for key: Key in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
		for button: MouseButton in MOUSE.get(action, []):
			var click := InputEventMouseButton.new()
			click.button_index = button
			InputMap.action_add_event(action, click)
