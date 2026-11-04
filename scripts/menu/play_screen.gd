class_name PlayScreen
extends PanelContainer
## "Spielen": pick a Knödlinger and a map, then off to the Kirtag. Characters are cards with a
## drawn portrait (the chosen one has the gold border); under them the chosen one's start weapon,
## Knödl sort and trait; then the maps; "Auf geht's!" (Enter) starts the run.

signal start_pressed(character: StringName, map: StringName)
signal closed

const CARD := Vector2(136.0, 176.0)
const COLUMNS: int = 4

var content: GameContent
var _character: StringName = &""
var _map: StringName = &""
var _character_cards: Dictionary[StringName, Button] = {}
var _map_cards: Dictionary[StringName, Button] = {}
var _weapon_icon: TextureRect
var _weapon_name: Label
var _knodl_name: Label
var _trait: Label
var _map_desc: Label
var _start: ActionPill


func _init(p_content: GameContent) -> void:
	content = p_content
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := UiStyle.vbox(&"Gap24")
	add_child(column)
	var header: PanelContainer = UiStyle.panel(&"PanelHeader")
	column.add_child(header)
	header.add_child(UiStyle.label(&"LabelTitle", tr("PLAY_TITLE")))
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(grid)
	for character: CharacterData in content.characters:
		var card := _character_card(character)
		grid.add_child(card)
		_character_cards[character.id] = card
	# The chosen one: start weapon, Knödl sort, trait.
	var detail := UiStyle.vbox()
	column.add_child(detail)
	var weapon_row := UiStyle.hbox()
	detail.add_child(weapon_row)
	_weapon_icon = UiStyle.icon_rect(null, 32.0)
	weapon_row.add_child(_weapon_icon)
	_weapon_name = UiStyle.label(&"LabelSmall")
	_weapon_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	weapon_row.add_child(_weapon_name)
	_knodl_name = UiStyle.label(&"LabelSmall")
	_knodl_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	weapon_row.add_child(_knodl_name)
	_trait = UiStyle.label(&"LabelMuted")
	_trait.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_trait.custom_minimum_size = Vector2(CARD.x * COLUMNS + 8.0 * (COLUMNS - 1), 0.0)
	detail.add_child(_trait)
	# Maps.
	var maps := UiStyle.vbox()
	column.add_child(maps)
	maps.add_child(UiStyle.label(&"LabelAccent", tr("PLAY_MAP")))
	var map_row := UiStyle.hbox()
	maps.add_child(map_row)
	for info: MapInfo in content.maps:
		var card := _map_card(info)
		map_row.add_child(card)
		_map_cards[info.id] = card
	_map_desc = UiStyle.label(&"LabelMuted")
	maps.add_child(_map_desc)
	var buttons := UiStyle.hbox(&"Row16")
	column.add_child(buttons)
	_start = ActionPill.new("Enter")
	_start.set_label(tr("PLAY_START"))
	_start.pressed.connect(_on_start)
	buttons.add_child(_start)
	var back := ActionPill.new("Esc")
	back.set_label(tr("MENU_BACK"))
	back.pressed.connect(func() -> void: closed.emit())
	buttons.add_child(back)
	var first: StringName = StringName(RunSetup.character)
	_select_character(first if _character_cards.has(first) else content.characters[0].id)
	var first_map: StringName = StringName(RunSetup.map)
	_select_map(first_map if _map_cards.has(first_map) else content.maps[0].id)


func focus_first() -> void:
	if _character_cards.has(_character):
		_character_cards[_character].grab_focus()


func _character_card(character: CharacterData) -> Button:
	var card := Button.new()
	card.custom_minimum_size = CARD
	card.theme_type_variation = &"CardRarity0"
	card.focus_entered.connect(func() -> void: _select_character(character.id))
	card.pressed.connect(func() -> void: _select_character(character.id))
	card.mouse_entered.connect(func() -> void: GameAudio.play(&"ui_hover"))
	var column := UiStyle.vbox()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 8.0
	column.offset_right = -8.0
	column.offset_top = 16.0
	column.offset_bottom = -8.0
	card.add_child(column)
	var portrait := FamilyPortrait.new(character, 80.0)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(portrait)
	var name: Label = UiStyle.label(&"LabelSmall", tr(character.name_key))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(name)
	var role: Label = UiStyle.label(&"LabelMuted", tr(character.role_key))
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(role)
	return card


func _map_card(info: MapInfo) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(CARD.x * 2.0 + 8.0, 48.0)
	card.theme_type_variation = &"CardRarity0"
	card.pressed.connect(func() -> void: _select_map(info.id))
	card.focus_entered.connect(func() -> void: _select_map(info.id))
	var row := UiStyle.hbox()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8.0
	row.offset_right = -8.0
	card.add_child(row)
	var swatch := ColorRect.new()
	swatch.color = info.swatch
	swatch.custom_minimum_size = Vector2(24.0, 24.0)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(swatch)
	var name: Label = UiStyle.label(&"LabelSmall", tr(info.name_key))
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	return card


func _select_character(id: StringName) -> void:
	_character = id
	for key: StringName in _character_cards:
		_character_cards[key].theme_type_variation = &"CardEvolution" if key == id else &"CardRarity0"
	var character: CharacterData = content.character(id)
	if character == null:
		return
	var weapon: WeaponData = character.start_weapon
	_weapon_icon.texture = weapon.icon if weapon != null else null
	_weapon_name.text = tr(weapon.name_key) if weapon != null else ""
	_knodl_name.text = "· " + tr(character.knodl_sort.name_key) if character.knodl_sort != null else ""
	_trait.text = tr(character.trait_key)


func _select_map(id: StringName) -> void:
	_map = id
	for key: StringName in _map_cards:
		_map_cards[key].theme_type_variation = &"CardEvolution" if key == id else &"CardRarity0"
	var info: MapInfo = content.map_info(id)
	_map_desc.text = tr(info.desc_key) if info != null else ""


func _on_start() -> void:
	GameAudio.play(&"card")
	start_pressed.emit(_character, _map)


## Enter starts even while a card has the focus (the card would only take it as a click).
func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if not is_visible_in_tree() or key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_KP_ENTER:
		get_viewport().set_input_as_handled()
		_on_start()
