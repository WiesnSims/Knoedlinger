class_name InventoryPanel
extends PanelContainer
## The build as icon tiles (docs/UI-STYLE.md; Megabonk's inventory panel): weapons, passives and
## Knödl upgrades, each tile with its level, free slots as faint outlines, gold and what is left of
## Nochmal bitte / Des mog i ned at the bottom. Shown left of the Speisekarte and in the Tab screen.
## Rebuilt only when the build changes; the tiles are drawn by TileGrid (a few draw calls per grid).

const TILE: float = 40.0
const COLUMNS: int = 6
const WIDTH: float = 312.0

var _weapons: TileGrid
var _passives: TileGrid
var _extras_title: Label
var _extras: TileGrid
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
	var weapons: Array[TileGrid.Tile] = []
	for owned: PlayerBuild.OwnedWeapon in build.weapons:
		weapons.append(_tile(owned.data.icon, owned.level, owned.data.max_level, owned.data.is_evolution,
				TranslationServer.translate(owned.data.name_key)))
	for k: int in range(build.weapons.size(), balance.weapon_slots):
		weapons.append(TileGrid.Tile.new())
	var passives: Array[TileGrid.Tile] = []
	var extras: Array[TileGrid.Tile] = []
	for owned: PlayerBuild.OwnedPassive in build.passives:
		var name: String = TranslationServer.translate(owned.data.name_key)
		if owned.data.kind == PassiveData.Kind.PASSIVE:
			passives.append(_tile(owned.data.icon, owned.level, owned.data.max_level, false, name))
		else:
			extras.append(_tile(owned.data.icon, 0, 0, true, name))
	for k: int in range(passives.size(), balance.passive_slots):
		passives.append(TileGrid.Tile.new())
	_weapons.set_tiles(weapons)
	_passives.set_tiles(passives)
	_extras.set_tiles(extras)
	_extras_title.visible = not extras.is_empty()
	_extras.visible = not extras.is_empty()


func _section(column: VBoxContainer, title_key: String) -> TileGrid:
	return _section_parts(column, title_key)[1]


func _section_parts(column: VBoxContainer, title_key: String) -> Array:
	# The title sits closer to its tiles (8) than to the section above (16).
	var pair := UiStyle.vbox()
	column.add_child(pair)
	var title: Label = UiStyle.label(&"LabelMuted", tr(title_key).to_upper())
	pair.add_child(title)
	var grid := TileGrid.new(COLUMNS, TILE)
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
func _tile(icon: Texture2D, level: int, max_level: int, special: bool, name: String) -> TileGrid.Tile:
	var maxed: bool = max_level > 0 and level >= max_level
	var tile := TileGrid.Tile.new()
	tile.icon = icon
	tile.level = level
	tile.variation = &"TileEvolution" if special or maxed else &"TileRarity0"
	tile.tooltip = name if level <= 0 else "%s · %s" % [name, tr("CARD_LEVEL") % level]
	return tile
