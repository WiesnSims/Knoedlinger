extends Node
## Which device the player used last (autoload InputDevice): keyboard and mouse, a gamepad, or
## touch. Keycaps show the matching glyph (KeycapLabel), menus focus their first entry for the pad,
## and the touch controls show themselves. A small stick wobble or a mouse twitch does not count.

signal changed(kind: Kind)

enum Kind { KEYS, PAD, TOUCH }

## Gamepad glyphs per action (Xbox layout); actions without one hide their keycap on the pad.
const PAD_GLYPHS: Dictionary[StringName, String] = {
	&"move": "LS",
	&"look": "RS",
	&"jump": "A",
	&"schupfn": "RB",
	&"pause": "Start",
	&"inventory": "Back",
	&"card_reroll": "X",
	&"card_banish": "Y",
	&"card_skip": "LB",
	&"ui_accept": "A",
	&"ui_cancel": "B",
	&"shoulder_left": "LB",
	&"shoulder_right": "RB",
	&"trigger_left": "LT",
	&"trigger_right": "RT",
}
const STICK_THRESHOLD: float = 0.5
const MOUSE_THRESHOLD: float = 6.0

var kind: Kind = Kind.KEYS


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputSetup.ensure_actions()
	# A phone starts on touch, so its first screen already shows the touch layout.
	if OS.has_feature("web_android") or OS.has_feature("web_ios"):
		kind = Kind.TOUCH


func is_pad() -> bool:
	return kind == Kind.PAD


func is_touch() -> bool:
	return kind == Kind.TOUCH


## The text on a keycap for `action`: the gamepad glyph on the pad, `keys` (the keyboard's own
## label) otherwise, "" when the current device has no button for it.
func glyph(action: StringName, keys: String) -> String:
	match kind:
		Kind.PAD:
			return PAD_GLYPHS.get(action, "")
		Kind.TOUCH:
			return ""
	return keys


func _input(event: InputEvent) -> void:
	var next: Kind = kind
	if event is InputEventJoypadButton:
		if (event as InputEventJoypadButton).pressed:
			next = Kind.PAD
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > STICK_THRESHOLD:
			next = Kind.PAD
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		next = Kind.TOUCH
	elif event is InputEventKey:
		if (event as InputEventKey).pressed:
			next = Kind.KEYS
	elif event is InputEventMouseButton:
		# Touch also sends emulated mouse clicks; those must not flip back to the keyboard.
		var click := event as InputEventMouseButton
		if click.pressed and click.device != InputEvent.DEVICE_ID_EMULATION:
			next = Kind.KEYS
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.device != InputEvent.DEVICE_ID_EMULATION and motion.relative.length() > MOUSE_THRESHOLD:
			next = Kind.KEYS
	if next != kind:
		kind = next
		changed.emit(kind)
