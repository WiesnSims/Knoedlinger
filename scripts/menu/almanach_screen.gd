class_name AlmanachScreen
extends PanelContainer
## "Almanach" (GAME-DESIGN.md, "Meta progression"): the bestiary and item list that fills as you
## discover things. Tabs: Familie, Waffen, Verbesserungen, Kirtagsware, Viecher. Each entry is a tile;
## the hovered or focused one shows its name and deadpan line on the right. Unknown entries stay "???";
## locked ones name the quest that unlocks them.

signal closed

const TILE: float = 56.0
const COLUMNS: int = 7
const DETAIL_WIDTH: float = 256.0
const TABS: Array = [
	[&"character", "ALM_FAMILY"], [&"weapon", "ALM_WEAPONS"], [&"passive", "ALM_STATS"], [&"item", "ALM_ITEMS"],
	[&"enemy", "ALM_ENEMIES"],
]

var content: GameContent
var catalog: UpgradeCatalog
var _tab: StringName = &"character"
var _tab_buttons: Dictionary[StringName, ActionPill] = {}
var _grid: GridContainer
var _count: Label
var _name: Label
var _line: Label
var _extra: Label
var _first: Button


func _init(p_content: GameContent) -> void:
	content = p_content
	catalog = load("res://data/catalog/catalog.tres")
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := UiStyle.vbox(&"Gap16")
	add_child(column)
	var header: PanelContainer = UiStyle.panel(&"PanelHeader")
	column.add_child(header)
	var title_row := UiStyle.hbox()
	header.add_child(title_row)
	var title: Label = UiStyle.label(&"LabelTitle", tr("ALMANACH_TITLE"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	_count = UiStyle.label(&"LabelMuted")
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_count)
	var tabs := UiStyle.hbox()
	column.add_child(tabs)
	for def: Array in TABS:
		var pill := ActionPill.new()
		pill.set_label(tr(def[1]))
		pill.toggle_mode = true
		var kind: StringName = def[0]
		pill.pressed.connect(func() -> void: _show_tab(kind))
		tabs.add_child(pill)
		_tab_buttons[kind] = pill
	var body := UiStyle.hbox(&"Row24")
	column.add_child(body)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.custom_minimum_size = Vector2(COLUMNS * (TILE + 8.0) - 8.0, (TILE + 8.0) * 4.0)
	body.add_child(_grid)
	var detail: PanelContainer = UiStyle.panel(&"PanelRaised")
	detail.custom_minimum_size = Vector2(DETAIL_WIDTH, 0.0)
	body.add_child(detail)
	var text := UiStyle.vbox()
	detail.add_child(text)
	_name = UiStyle.label(&"", "")
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_name)
	_line = UiStyle.label(&"LabelMuted", "")
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_line)
	_extra = UiStyle.label(&"LabelChange", "")
	_extra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_extra)
	var back := ActionPill.new("Esc", &"ui_cancel")
	back.set_label(tr("MENU_BACK"))
	back.pressed.connect(func() -> void: closed.emit())
	column.add_child(back)


func refresh() -> void:
	_show_tab(_tab)


func focus_first() -> void:
	if _first != null:
		_first.grab_focus()


func _show_tab(kind: StringName) -> void:
	_tab = kind
	for key: StringName in _tab_buttons:
		_tab_buttons[key].set_pressed_no_signal(key == kind)
	for child: Node in _grid.get_children():
		child.queue_free()
	_first = null
	var entries: Array = _entries(kind)
	var found: int = 0
	for entry: Array in entries:
		var known: bool = entry[4]
		if known:
			found += 1
		var tile := _tile(entry)
		_grid.add_child(tile)
		if _first == null:
			_first = tile
	_count.text = tr("ALM_COUNT") % [found, entries.size()]
	_describe(entries[0] if not entries.is_empty() else [])


## Per entry: [kind, id, name key, desc key, known, look (Texture2D, CharacterData or EnemyTypeData)].
func _entries(kind: StringName) -> Array:
	var out: Array = []
	match kind:
		&"character":
			for character: CharacterData in content.characters:
				out.append([kind, character.id, character.name_key, character.trait_key,
						Profile.is_unlocked(kind, character.id), character])
		&"weapon":
			for weapon: WeaponData in catalog.weapons:
				out.append([kind, weapon.id, weapon.name_key, weapon.desc_key, Profile.is_found(kind, weapon.id), weapon.icon])
		&"passive":
			for passive: PassiveData in catalog.passives:
				out.append([kind, passive.id, passive.name_key, passive.desc_key, Profile.is_found(kind, passive.id), passive.icon])
		&"item":
			for item: ItemData in catalog.items:
				out.append([kind, item.id, item.name_key, item.desc_key, Profile.is_found(kind, item.id), item.icon])
		&"enemy":
			for enemy: EnemyTypeData in content.enemies:
				out.append([kind, enemy.id, enemy.name_key, enemy.desc_key, Profile.is_found(kind, enemy.id), enemy])
	return out


func _tile(entry: Array) -> Button:
	var known: bool = entry[4]
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(TILE, TILE)
	tile.theme_type_variation = &"CardRarity0"
	var look: Variant = entry[5]
	var inner: Control
	if look is Texture2D:
		var icon: TextureRect = UiStyle.icon_rect(look, TILE - 16.0)
		icon.modulate = Color.WHITE if known else Color(0.0, 0.0, 0.0, 0.55)
		inner = icon
	elif look is CharacterData:
		var portrait := FamilyPortrait.new(look, TILE - 8.0)
		portrait.locked = not known
		inner = portrait
	else:
		var badge := EnemyBadge.new(look as EnemyTypeData, TILE - 12.0)
		badge.known = known
		inner = badge
	# Fills the tile 8 px in; the portrait and badge draw themselves centred in their box.
	inner.custom_minimum_size = Vector2.ZERO
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: Side in [SIDE_LEFT, SIDE_TOP]:
		inner.set_offset(side, 8.0)
	for side: Side in [SIDE_RIGHT, SIDE_BOTTOM]:
		inner.set_offset(side, -8.0)
	tile.add_child(inner)
	tile.focus_entered.connect(func() -> void:
		_describe(entry)
		GameAudio.play(&"ui_hover"))
	tile.mouse_entered.connect(tile.grab_focus)
	return tile


func _describe(entry: Array) -> void:
	if entry.is_empty():
		_name.text = ""
		_line.text = ""
		_extra.text = ""
		return
	var known: bool = entry[4]
	_name.text = tr(entry[2]) if known else tr("ALM_UNKNOWN")
	_line.text = tr(entry[3]) if known else tr("ALM_UNKNOWN_LINE")
	var quest: QuestData = Profile.unlocking_quest(entry[0], entry[1])
	_extra.text = tr("ALM_LOCKED") % tr(quest.title_key) if quest != null else ""


## An enemy as a small drawn badge (they have no icons): its body and head colours, a dark
## silhouette while it is unknown.
class EnemyBadge:
	extends Control
	var enemy: EnemyTypeData
	var known: bool = false

	func _init(p_enemy: EnemyTypeData = null, edge: float = 40.0) -> void:
		enemy = p_enemy
		custom_minimum_size = Vector2(edge, edge)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if enemy == null:
			return
		var s: float = minf(size.x, size.y)
		var c := size * 0.5
		var dark: Color = UiStyle.color("panel_raised").lightened(0.08)
		var body: Color = enemy.body_color if known else dark
		var head: Color = enemy.head_color if known else dark
		draw_circle(c + Vector2(0.0, s * 0.16), s * 0.32, body)
		draw_circle(c - Vector2(0.0, s * 0.2), s * 0.2, head)
		if known:
			draw_circle(c - Vector2(s * 0.07, s * 0.22), s * 0.03, UiStyle.color("panel"))
			draw_circle(c - Vector2(-s * 0.07, s * 0.22), s * 0.03, UiStyle.color("panel"))
		else:
			var font: Font = UiStyle.font("number")
			draw_string(font, Vector2(0.0, c.y + s * 0.1), "?", HORIZONTAL_ALIGNMENT_CENTER, size.x,
					UiStyle.font_size("body"), UiStyle.color("muted"))
