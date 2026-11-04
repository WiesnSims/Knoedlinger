class_name PlayScreen
extends PanelContainer
## "Spielen": pick a Knödlinger, a map and how grantig it gets, then off to the Kirtag. Characters
## are cards with a drawn portrait (the chosen one has the gold border); under them the chosen one's
## start weapon, Knödl sort and trait; then the maps and the Grant level; "Auf geht's!" (Enter)
## starts the run. Locked characters and maps show the quest that unlocks them.

signal start_pressed(character: StringName, map: StringName, grant: int)
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
var _grant: int = 1
var _grant_name: Label
var _grant_desc: Label
var _grant_down: ActionPill
var _grant_up: ActionPill


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
	# Grant level: the hardest one unlocked so far at most.
	var grants := UiStyle.vbox()
	column.add_child(grants)
	grants.add_child(UiStyle.label(&"LabelAccent", tr("PLAY_GRANT")))
	var grant_row := UiStyle.hbox(&"Row16")
	grants.add_child(grant_row)
	_grant_down = ActionPill.new("Q")
	_grant_down.set_label("‹")
	_grant_down.pressed.connect(func() -> void: _select_grant(_grant - 1))
	grant_row.add_child(_grant_down)
	_grant_name = UiStyle.label(&"LabelSmall")
	_grant_name.custom_minimum_size = Vector2(136.0, 0.0)
	_grant_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grant_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grant_row.add_child(_grant_name)
	_grant_up = ActionPill.new("E")
	_grant_up.set_label("›")
	_grant_up.pressed.connect(func() -> void: _select_grant(_grant + 1))
	grant_row.add_child(_grant_up)
	_grant_desc = UiStyle.label(&"LabelMuted")
	_grant_desc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grant_row.add_child(_grant_desc)
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
	refresh()


## The Profile may have changed (a run, a quest): locks, last choice, Grant levels.
func refresh() -> void:
	for character: CharacterData in content.characters:
		var card: Button = _character_cards[character.id]
		var quest: QuestData = Profile.unlocking_quest(&"character", character.id)
		(card.get_meta(&"portrait") as FamilyPortrait).locked = quest != null
		(card.get_meta(&"portrait") as FamilyPortrait).queue_redraw()
		(card.get_meta(&"name") as Label).text = tr(character.name_key) if quest == null else tr("ALM_UNKNOWN")
		(card.get_meta(&"role") as Label).text = tr(character.role_key) if quest == null else tr(quest.title_key)
	var last: Dictionary = Profile.last_choice()
	var first: StringName = StringName(str(last.get("character", RunSetup.character)))
	_select_character(first if _character_cards.has(first) else content.characters[0].id)
	var first_map: StringName = StringName(str(last.get("map", RunSetup.map)))
	_select_map(first_map if _map_cards.has(first_map) else content.maps[0].id)
	_select_grant(int(last.get("grant", RunSetup.grant)))


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
	card.set_meta(&"portrait", portrait)
	card.set_meta(&"name", name)
	card.set_meta(&"role", role)
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
	_update_start()
	var quest: QuestData = Profile.unlocking_quest(&"character", id)
	if quest != null:
		_weapon_icon.texture = null
		_weapon_name.text = ""
		_knodl_name.text = ""
		_trait.text = tr("PLAY_LOCKED") % tr(quest.title_key) + " – " + tr(quest.desc_key)
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
	var quest: QuestData = Profile.unlocking_quest(&"map", id)
	if quest != null:
		_map_desc.text = tr("PLAY_LOCKED") % tr(quest.title_key)
	else:
		_map_desc.text = tr(info.desc_key) if info != null else ""
	_update_start()


func _select_grant(index: int) -> void:
	_grant = clampi(index, 0, Profile.grant_unlocked())
	var data: GrantData = content.grants[_grant]
	_grant_name.text = tr(data.name_key)
	_grant_desc.text = tr(data.desc_key)
	_grant_down.disabled = _grant <= 0
	_grant_up.disabled = _grant >= Profile.grant_unlocked()


## Only an unlocked character on an unlocked map can start.
func _update_start() -> void:
	if _start != null:
		_start.disabled = _character == &"" or _map == &"" or not Profile.is_unlocked(&"character", _character) \
				or not Profile.is_unlocked(&"map", _map)


func _on_start() -> void:
	if _start.disabled:
		GameAudio.play(&"no_gold")
		return
	GameAudio.play(&"card")
	start_pressed.emit(_character, _map, _grant)


## Enter starts even while a card has the focus (the card would only take it as a click).
func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if not is_visible_in_tree() or key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_KP_ENTER:
		get_viewport().set_input_as_handled()
		_on_start()
	elif key.physical_keycode == KEY_Q or key.physical_keycode == KEY_E:
		get_viewport().set_input_as_handled()
		_select_grant(_grant + (1 if key.physical_keycode == KEY_E else -1))
