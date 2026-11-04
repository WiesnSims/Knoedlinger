class_name ActionPill
extends Button
## A pill button of the theme with a keycap, a verb and an optional count:  [R] Nochmal bitte  3
## (docs/UI-STYLE.md: verb + count, the key as a keycap). The text is laid out by its own row,
## so the button's own `text` stays empty.

var _key: Label
var _text: Label
var _count: Label


func _init(key: String = "") -> void:
	focus_mode = Control.FOCUS_NONE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row: HBoxContainer = UiStyle.hbox()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16.0
	row.offset_right = -16.0
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)
	_key = UiStyle.label(&"Keycap", key)
	_key.visible = key != ""
	_key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_key)
	_text = UiStyle.label(&"LabelSmall")
	row.add_child(_text)
	_count = UiStyle.label(&"LabelChange")
	_count.visible = false
	row.add_child(_count)
	# The labels only know their width once they have the theme's font.
	for part: Label in [_key, _text, _count]:
		part.minimum_size_changed.connect(_measure)


func set_label(text: String, count: String = "") -> void:
	_text.text = text
	_count.text = count
	_count.visible = count != ""
	_measure()


## Button sizes itself from its own text (empty here), so the row's width is set as the minimum.
func _measure() -> void:
	var width: float = 32.0
	var visible_parts: int = 0
	for part: Label in [_key, _text, _count]:
		if part.visible:
			width += part.get_combined_minimum_size().x
			visible_parts += 1
	custom_minimum_size = Vector2(width + 8.0 * maxi(visible_parts - 1, 0), 32.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAW:
		# Disabled pills dim their content as well as their box.
		var dim: float = 0.4 if disabled else 1.0
		for part: Label in [_key, _text, _count]:
			part.modulate.a = dim
