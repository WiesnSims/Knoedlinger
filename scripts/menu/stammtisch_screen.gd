class_name StammtischScreen
extends PanelContainer
## "Stammtisch": the family's permanent upgrades, bought with Schilling (GAME-DESIGN.md, "Meta
## progression"). Two columns of rows: icon, name, what one rank gives, the ranks owned, and the
## price; clicking a row (or Enter) buys the next rank. Schilling top right.

signal closed

const ROW := Vector2(368.0, 64.0)
## Lines for the specials (MetaUpgradeData.SPECIALS); stats use the Speisekarte's stat line.
const SPECIAL_KEYS: Dictionary[StringName, String] = {
	&"weapon_slots": "META_EFFECT_WEAPON_SLOTS", &"rerolls": "META_EFFECT_REROLLS", &"banishes": "META_EFFECT_BANISHES",
	&"knodl_start": "META_EFFECT_KNODL_START", &"revives": "META_EFFECT_REVIVES",
}

var content: GameContent
var _schilling: Label
var _rows: Array[Button] = []
var _lines: Array[Label] = []
var _prices: Array[Label] = []


func _init(p_content: GameContent) -> void:
	content = p_content
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := UiStyle.vbox(&"Gap24")
	add_child(column)
	var header: PanelContainer = UiStyle.panel(&"PanelHeader")
	column.add_child(header)
	var title_row := UiStyle.hbox()
	header.add_child(title_row)
	var title: Label = UiStyle.label(&"LabelTitle", tr("STAMMTISCH_TITLE"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	_schilling = UiStyle.label(&"LabelNumber")
	_schilling.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_schilling)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(grid)
	for upgrade: MetaUpgradeData in content.upgrades:
		grid.add_child(_row(upgrade))
	var back := ActionPill.new("Esc", &"ui_cancel")
	back.set_label(tr("MENU_BACK"))
	back.pressed.connect(func() -> void: closed.emit())
	column.add_child(back)
	Profile.changed.connect(refresh)
	refresh()


func focus_first() -> void:
	if not _rows.is_empty():
		_rows[0].grab_focus()


func refresh() -> void:
	_schilling.text = tr("SCHILLING_AMOUNT") % Profile.schilling()
	for k: int in content.upgrades.size():
		var upgrade: MetaUpgradeData = content.upgrades[k]
		var owned: int = Profile.rank(upgrade.id)
		var maxed: bool = owned >= upgrade.max_rank
		_lines[k].text = "%s · %s" % [effect_text(upgrade), tr("STAMMTISCH_RANK") % [owned, upgrade.max_rank]]
		_prices[k].text = tr("STAMMTISCH_MAXED") if maxed else tr("SCHILLING_AMOUNT") % upgrade.cost(owned)
		var affordable: bool = not maxed and Profile.schilling() >= upgrade.cost(owned)
		_rows[k].theme_type_variation = &"CardEvolution" if maxed else (&"CardRarity1" if affordable else &"CardRarity0")
		_prices[k].theme_type_variation = &"LabelAccent" if affordable else &"LabelMuted"


## What one rank gives: "+10 max. HP", "+1 Waffenplatz".
static func effect_text(upgrade: MetaUpgradeData) -> String:
	if SPECIAL_KEYS.has(upgrade.stat):
		var amount: float = upgrade.per_rank * (100.0 if upgrade.stat == &"knodl_start" else 1.0)
		return TranslationServer.translate(SPECIAL_KEYS[upgrade.stat]) % roundi(amount)
	return Speisekarte.stat_text(upgrade.stat, upgrade.per_rank)


func _row(upgrade: MetaUpgradeData) -> Button:
	var button := Button.new()
	button.custom_minimum_size = ROW
	button.tooltip_text = tr(upgrade.desc_key)
	var row := UiStyle.hbox(&"Row16")
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8.0
	row.offset_right = -16.0
	button.add_child(row)
	var icon: TextureRect = UiStyle.icon_rect(upgrade.icon, 48.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var text := UiStyle.vbox(&"Tight")
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var name: Label = UiStyle.label(&"LabelSmall", tr(upgrade.name_key))
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(name)
	var line: Label = UiStyle.label(&"LabelMuted")
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(line)
	var price: Label = UiStyle.label(&"LabelAccent")
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(price)
	button.pressed.connect(func() -> void:
		if Profile.buy(upgrade):
			GameAudio.play(&"coin")
		else:
			GameAudio.play(&"no_gold"))
	button.focus_entered.connect(func() -> void: GameAudio.play(&"ui_hover"))
	_rows.append(button)
	_lines.append(line)
	_prices.append(price)
	return button
