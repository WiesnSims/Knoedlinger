class_name InventoryPanel
extends PanelContainer
## The build as icon tiles (docs/UI-STYLE.md; Megabonk's inventory panel): weapons, passives and
## Knödl upgrades, each tile with its level, free slots as faint outlines, gold and what is left of
## Nochmal bitte / Des mog i ned at the bottom. Shown left of the Speisekarte and in the Tab screen.
## Rebuilt only when the build changes.

const TILE: float = 40.0
const COLUMNS: int = 6
const WIDTH: float = 312.0

var _weapons: GridContainer
var _passives: GridContainer
var _extras_title: Label
var _extras: GridContainer
var _gold: Label
var _rerolls: Label
var _banishes: Label
var _signature: String = ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, 0.0)
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var column := UiStyle.vbox(&"Gap16")
	add_child(column)
	column.add_child(UiStyle.label(&"LabelTitle", tr("INV_TITLE")))
	_weapons = _section(column, "INV_WEAPONS")
	_passives = _section(column, "INV_PASSIVES")
	var extras: Array = _section_parts(column, "INV_KNODL")
	_extras_title = extras[0]
	_extras = extras[1]
	var footer := UiStyle.hbox(&"Row16")
	column.add_child(footer)
	_gold = _counter(footer, "INV_GOLD")
	_rerolls = _counter(footer, "INV_REROLLS")
	_banishes = _counter(footer, "INV_BANISHES")


func show_build(build: PlayerBuild, balance: BalanceData) -> void:
	_gold.text = str(build.gold)
	_rerolls.text = str(build.rerolls)
	_banishes.text = str(build.banishes)
	var signature: String = ""
	for owned: PlayerBuild.OwnedWeapon in build.weapons:
		signature += "%d.%d," % [owned.index, owned.level]
	signature += "|"
	for owned: PlayerBuild.OwnedPassive in build.passives:
		signature += "%d.%d," % [owned.index, owned.level]
	if signature == _signature:
		return
	_signature = signature
	for grid: GridContainer in [_weapons, _passives, _extras]:
		for child: Node in grid.get_children():
			child.queue_free()
	for owned: PlayerBuild.OwnedWeapon in build.weapons:
		_weapons.add_child(_tile(owned.data.icon, owned.level, owned.data.max_level, owned.data.is_evolution,
				TranslationServer.translate(owned.data.name_key)))
	for k: int in range(build.weapons.size(), balance.weapon_slots):
		_weapons.add_child(_empty())
	var passives: int = 0
	var extras: int = 0
	for owned: PlayerBuild.OwnedPassive in build.passives:
		var name: String = TranslationServer.translate(owned.data.name_key)
		if owned.data.kind == PassiveData.Kind.PASSIVE:
			_passives.add_child(_tile(owned.data.icon, owned.level, owned.data.max_level, false, name))
			passives += 1
		else:
			_extras.add_child(_tile(owned.data.icon, 0, 0, true, name))
			extras += 1
	for k: int in range(passives, balance.passive_slots):
		_passives.add_child(_empty())
	_extras_title.visible = extras > 0
	_extras.visible = extras > 0


func _section(column: VBoxContainer, title_key: String) -> GridContainer:
	return _section_parts(column, title_key)[1]


func _section_parts(column: VBoxContainer, title_key: String) -> Array:
	# The title sits closer to its tiles (8) than to the section above (16).
	var pair := UiStyle.vbox()
	column.add_child(pair)
	var title: Label = UiStyle.label(&"LabelMuted", tr(title_key).to_upper())
	pair.add_child(title)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pair.add_child(grid)
	return [title, grid]


func _counter(row: HBoxContainer, key: String) -> Label:
	var item := UiStyle.vbox(&"Tight")
	row.add_child(item)
	item.add_child(UiStyle.label(&"LabelMuted", tr(key)))
	var value: Label = UiStyle.label(&"LabelAccent")
	item.add_child(value)
	return value


## One owned item: its icon, its level in the corner; maxed or evolved items get the gold frame.
func _tile(icon: Texture2D, level: int, max_level: int, special: bool, name: String) -> PanelContainer:
	var maxed: bool = max_level > 0 and level >= max_level
	var tile: PanelContainer = UiStyle.panel(&"TileEvolution" if special or maxed else &"TileRarity0")
	tile.custom_minimum_size = Vector2(TILE, TILE)
	tile.tooltip_text = name if level <= 0 else "%s · %s" % [name, tr("CARD_LEVEL") % level]
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	tile.add_child(UiStyle.icon_rect(icon, TILE - 8.0))
	if level > 0:
		var number: Label = UiStyle.label(&"HudSmall", str(level))
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		number.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		number.size_flags_vertical = Control.SIZE_SHRINK_END
		number.size_flags_horizontal = Control.SIZE_SHRINK_END
		tile.add_child(number)
	return tile


func _empty() -> PanelContainer:
	var tile: PanelContainer = UiStyle.panel(&"TileEmpty")
	tile.custom_minimum_size = Vector2(TILE, TILE)
	return tile
