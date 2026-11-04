class_name KeycapLabel
extends Label
## A keycap that follows the device in use (InputDevice): the keyboard label, the gamepad glyph, or
## hidden on touch and where the pad has no button for it.

var action: StringName
var keys: String


func _init(p_action: StringName = &"", p_keys: String = "") -> void:
	action = p_action
	keys = p_keys
	theme_type_variation = &"Keycap"
	_refresh()


func _enter_tree() -> void:
	if not InputDevice.changed.is_connected(_on_device):
		InputDevice.changed.connect(_on_device)
	_refresh()


func _exit_tree() -> void:
	if InputDevice.changed.is_connected(_on_device):
		InputDevice.changed.disconnect(_on_device)


func _on_device(_kind: int) -> void:
	_refresh()


func _refresh() -> void:
	var shown: String = InputDevice.glyph(action, keys) if is_inside_tree() else keys
	text = shown
	visible = shown != ""
