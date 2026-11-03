class_name UpgradeCard
extends Button
## One card on the Speisekarte: the item's icon, its name, rarity, a NEU / STUFE / EVOLUTION badge
## and level pips. The one-liner and what the card adds only show while the card is hovered or
## focused (arrow keys), so the menu stays clean; the icon steps back behind them.

const CARD_SIZE := Vector2(214.0, 292.0)
const HOVER_SCALE: float = 1.05
const PIP_SIZE := Vector2(12.0, 6.0)

var _icon: TextureRect
var _details: Label
var _accent: Color = UiStyle.RARITY[0]
var _tween: Tween


## `owned_level` is the item's level before this card (0 = not owned).
func setup(card: Card, key: int, details: String, owned_level: int, catalog: UpgradeCatalog) -> void:
	_accent = UiStyle.rarity_color(card.rarity)
	if card.kind == Card.Kind.EVOLUTION:
		_accent = UiStyle.GOLD
	custom_minimum_size = CARD_SIZE
	focus_mode = Control.FOCUS_ALL
	add_theme_stylebox_override("normal", UiStyle.box(UiStyle.PANEL, 16, 0, _accent.darkened(0.35), 2, 8))
	add_theme_stylebox_override("hover", UiStyle.box(UiStyle.PANEL_HOVER, 16, 0, _accent, 3, 14))
	add_theme_stylebox_override("focus", UiStyle.box(Color.TRANSPARENT, 16, 0, _accent, 3, 0))
	add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.PANEL, 16, 0, _accent, 3, 6))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	# Rarity on the left, what kind of card on the right.
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)
	var rarity: Label = UiStyle.label(13, _accent)
	rarity.text = tr("RARITY_%d" % card.rarity).to_upper()
	rarity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(rarity)
	var badge_text: String = Speisekarte.level_text(card).to_upper()
	if badge_text != "":
		var badge := PanelContainer.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_stylebox_override("panel", UiStyle.box(_accent, 8, 0))
		var badge_label: Label = UiStyle.label(12, Color(0.1, 0.08, 0.06))
		badge_label.text = " %s " % badge_text
		badge.add_child(badge_label)
		top.add_child(badge)
	# The icon, with the details on top of it while hovered.
	var stage := Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(stage)
	_icon = UiStyle.icon_rect(UiStyle.card_icon(card, catalog), 120.0)
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(_icon)
	_details = UiStyle.label(15, UiStyle.TEXT)
	_details.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_details.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_details.text = details
	_details.modulate.a = 0.0
	stage.add_child(_details)
	var title: Label = UiStyle.label(20, UiStyle.TEXT)
	title.text = Speisekarte.card_name(card, catalog)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	column.add_child(_pips(card, owned_level, catalog))
	var hint: Label = UiStyle.label(12, UiStyle.MUTED)
	hint.text = str(key)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	mouse_entered.connect(grab_focus)
	mouse_exited.connect(release_focus)
	focus_entered.connect(_open.bind(true))
	focus_exited.connect(_open.bind(false))


## One pip per level: owned ones light, the one this card adds in the card's colour, the rest dim.
func _pips(card: Card, owned_level: int, catalog: UpgradeCatalog) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	row.custom_minimum_size = Vector2(0.0, PIP_SIZE.y)
	var levels: int = UiStyle.card_max_level(card, catalog)
	for k: int in levels:
		var pip := Panel.new()
		pip.custom_minimum_size = PIP_SIZE
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var color := Color(1.0, 1.0, 1.0, 0.12)
		if k < owned_level:
			color = Color(0.92, 0.88, 0.8)
		elif k < card.level:
			color = _accent
		pip.add_theme_stylebox_override("panel", UiStyle.box(color, 3, 0))
		row.add_child(pip)
	return row


func _open(on: bool) -> void:
	pivot_offset = size * 0.5
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE * (HOVER_SCALE if on else 1.0), 0.14)
	_tween.tween_property(_icon, "modulate:a", 0.1 if on else 1.0, 0.14)
	_tween.tween_property(_details, "modulate:a", 1.0 if on else 0.0, 0.14)
