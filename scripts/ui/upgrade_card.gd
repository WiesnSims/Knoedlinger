class_name UpgradeCard
extends Button
## One dish on the Speisekarte (docs/UI-STYLE.md): a big icon, the name, one line with what it
## changes ("+18 % Schaden", "Neu!"), level pips and the key, in a row whose border is the rarity
## (theme variation CardRarity0..3 / CardEvolution). The one-liner and the full numbers live in the
## menu's details footer, shown while the card is hovered or focused. Animates in, grows a little
## on hover.

signal hovered(on: bool)

const ROW_HEIGHT: float = 88.0
const ICON: float = 64.0

var _pips: PipRow
var _tween: Tween


## `owned_level` is the item's level before this card (0 = not owned).
## `price` >= 0: Der Standler's price in gold under the keycap, dimmed when the player cannot pay it.
func setup(card: Card, key: int, change: String, owned_level: int, catalog: UpgradeCatalog, price: int = -1,
		affordable: bool = true) -> void:
	theme_type_variation = UiStyle.rarity_variation("Card", card)
	custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	focus_mode = Control.FOCUS_ALL
	var row := UiStyle.hbox(&"Row16")
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12.0
	row.offset_right = -16.0
	add_child(row)
	var icon: TextureRect = UiStyle.icon_rect(UiStyle.card_icon(card, catalog), ICON)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var text := UiStyle.vbox(&"Tight")
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var title: Label = UiStyle.label(&"", Speisekarte.card_name(card, catalog))
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(title)
	text.add_child(UiStyle.label(&"LabelChange", change))
	var side := UiStyle.vbox()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(side)
	# Pad and touch pick the focused or tapped row; only the keyboard has number keys.
	var cap := KeycapLabel.new(&"", str(key))
	cap.size_flags_horizontal = Control.SIZE_SHRINK_END
	side.add_child(cap)
	_pips = PipRow.new()
	_pips.levels = UiStyle.card_max_level(card, catalog)
	_pips.owned = owned_level
	_pips.adds = card.level - owned_level if _pips.levels > 0 else 0
	_pips.tone = UiStyle.rarity_color(card.rarity) if card.kind != Card.Kind.EVOLUTION else UiStyle.color("evolution")
	side.add_child(_pips)
	if price >= 0:
		var cost: Label = UiStyle.label(&"LabelChange" if affordable else &"LabelMuted",
				TranslationServer.translate("SHOP_PRICE") % price)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		side.add_child(cost)
		if not affordable:
			modulate = Color(1.0, 1.0, 1.0, 0.6)
	# Open-ended levels: the level it reaches, as a number.
	if _pips.levels == 0 and card.level > 1 and (card.kind == Card.Kind.WEAPON or card.kind == Card.Kind.PASSIVE):
		var level: Label = UiStyle.label(&"LabelMuted", TranslationServer.translate("CARD_LEVEL") % card.level)
		level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		side.add_child(level)
	mouse_entered.connect(grab_focus)
	mouse_exited.connect(release_focus)
	focus_entered.connect(_open.bind(true))
	focus_exited.connect(_open.bind(false))


## Fades and grows in, `delay` seconds after the menu opened.
func reveal(delay: float) -> void:
	modulate.a = 0.0
	scale = Vector2.ONE * 0.96
	_pivot()
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, UiStyle.T_PANEL_IN).set_delay(delay)
	_tween.tween_property(self, "scale", Vector2.ONE, UiStyle.T_PANEL_IN).set_delay(delay)


func _open(on: bool) -> void:
	_pivot()
	if _tween != null:
		_tween.kill()
	modulate.a = 1.0
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE * (UiStyle.HOVER_SCALE if on else 1.0), UiStyle.T_HOVER)
	if on:
		GameAudio.play(&"ui_hover")
	hovered.emit(on)


func _pivot() -> void:
	pivot_offset = size * 0.5


## The level pips: owned levels light, the ones this card adds in its rarity colour, the rest dim.
class PipRow:
	extends Control
	const PIP := Vector2(10.0, 4.0)
	const GAP: float = 4.0
	var levels: int = 0
	var owned: int = 0
	var adds: int = 0
	var tone := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _get_minimum_size() -> Vector2:
		return Vector2(levels * (PIP.x + GAP) - GAP if levels > 0 else 0.0, PIP.y)

	func _draw() -> void:
		var x: float = size.x - (levels * (PIP.x + GAP) - GAP)
		for k: int in levels:
			var color := Color(1.0, 1.0, 1.0, 0.14)
			if k < owned:
				color = UiStyle.color("text")
			elif k < owned + adds:
				color = tone
			draw_rect(Rect2(Vector2(x + k * (PIP.x + GAP), 0.0), PIP), color)
