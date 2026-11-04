class_name InventoryPanel
extends PanelContainer
## The build as icon tiles (docs/UI-STYLE.md; Megabonk's inventory panel): weapons and stat
## upgrades with their level, free slots as faint outlines, then the Kirtagsware (items from
## chests, with how many of each, framed in their rarity), and gold and what is left of
## Nochmal bitte / Des mog i ned at the bottom. Shown left of the Speisekarte and in the Tab screen.
## Rebuilt only when the build changes; the tiles are drawn by TileGrid (a few draw calls per grid).

const TILE: float = 40.0
const COLUMNS: int = 6
const WIDTH: float = 312.0

var _weapons: TileGrid
var _passives: TileGrid
var _items_title: Label
var _items: TileGrid
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
	var items: Array = _section_parts(column, "INV_ITEMS")
	_items_title = items[0]
	_items = items[1]
	var footer := UiStyle.hbox(&"Row16")
	column.add_child(footer)
	_gold = _counter(footer, "INV_GOLD")
	_rerolls = _counter(footer, "INV_REROLLS")
	_banishes = _counter(footer, "INV_BANISHES")


func show_build(build: PlayerBuild, _balance: BalanceData) -> void:
	_gold.text = str(build.gold)
	_rerolls.text = str(build.rerolls)
	_banishes.text = str(build.banishes)
	var signature: String = "%d.%d|" % [build.weapon_slots, build.passive_slots]
	for owned: PlayerBuild.OwnedWeapon in build.weapons:
		signature += "%d.%d," % [owned.index, owned.level]
	signature += "|"
	for owned: PlayerBuild.OwnedPassive in build.passives:
		signature += "%d.%d," % [owned.index, owned.level]
	signature += "|"
	for owned: PlayerBuild.OwnedItem in build.items:
		signature += "%d.%d," % [owned.index, owned.count]
	if signature == _signature:
		return
	_signature = signature
	var weapons: Array[TileGrid.Tile] = []
	for owned: PlayerBuild.OwnedWeapon in build.weapons:
		weapons.append(_tile(owned.data.icon, owned.level, &"TileEvolution" if owned.data.is_evolution else &"TileRarity0",
				TranslationServer.translate(owned.data.name_key), true))
	for k: int in range(build.weapons.size(), build.weapon_slots):
		weapons.append(TileGrid.Tile.new())
	var passives: Array[TileGrid.Tile] = []
	for owned: PlayerBuild.OwnedPassive in build.passives:
		var maxed: bool = not owned.data.can_level(owned.level)
		passives.append(_tile(owned.data.icon, owned.level, &"TileEvolution" if maxed else &"TileRarity0",
				TranslationServer.translate(owned.data.name_key), true))
	for k: int in range(passives.size(), build.passive_slots):
		passives.append(TileGrid.Tile.new())
	var items: Array[TileGrid.Tile] = []
	for owned: PlayerBuild.OwnedItem in build.items:
		# The count in the corner only once there are two or more.
		items.append(_tile(owned.data.icon, owned.count if owned.count > 1 else 0,
				StringName("TileRarity%d" % clampi(owned.data.rarity, 0, 3)), TranslationServer.translate(owned.data.name_key), false))
	_weapons.set_tiles(weapons)
	_passives.set_tiles(passives)
	_items.set_tiles(items)
	_items_title.visible = not items.is_empty()
	_items.visible = not items.is_empty()


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


## One owned thing: its icon, a number in the corner (level, or copies of an item), its frame.
func _tile(icon: Texture2D, number: int, variation: StringName, name: String, is_level: bool) -> TileGrid.Tile:
	var tile := TileGrid.Tile.new()
	tile.icon = icon
	tile.level = number
	tile.variation = variation
	if number <= 0:
		tile.tooltip = name
	elif is_level:
		tile.tooltip = "%s · %s" % [name, tr("CARD_LEVEL") % number]
	else:
		tile.tooltip = "%s ×%d" % [name, number]
	return tile
