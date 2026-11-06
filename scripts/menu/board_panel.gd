class_name BoardPanel
extends VBoxContainer
## Die Ehrentafel in the Rekorde screen: the top 50 of a map, solo or with the family, all time or
## this week (Board.fetch). One row per run: place, name(s), Knödlinger, result and Grant level, time,
## level, kills, biggest Knödl; the player's own entries in the accent. With a fixed mode and map
## (the Tageskarte's board of the day) it has no filter pills and a shorter list.

const LIST_HEIGHT: float = 320.0
const FIXED_LIST_HEIGHT: float = 200.0
const COLUMNS: Array = [["#", 40.0], ["", 136.0], ["", 112.0], ["", 152.0], ["REC_TIME", 64.0], ["REC_LEVEL", 56.0],
	["REC_KILLS", 64.0], ["REC_KNODL", 56.0]]

var content: GameContent
var _map: StringName = &"kirtag"
var _mode: String = "solo"
var _period: String = "all"
var _pills: Dictionary[String, ActionPill] = {}
var _grid: GridContainer
var _status: Label


func _init(p_content: GameContent, fixed_mode: String = "", fixed_map: String = "") -> void:
	content = p_content
	theme_type_variation = &"Gap16"
	if fixed_mode != "":
		_mode = fixed_mode
		_map = StringName(fixed_map)
		_build_list(FIXED_LIST_HEIGHT)
		return
	# Two rows (maps, then mode and period): in one row they were wider than the menu's free area.
	var maps := UiStyle.hbox()
	add_child(maps)
	var filters := UiStyle.hbox(&"Row24")
	add_child(filters)
	for info: MapInfo in content.maps:
		_pill(maps, "map:" + String(info.id), tr(info.name_key), func() -> void:
			_map = info.id
			fetch())
	var modes := UiStyle.hbox()
	filters.add_child(modes)
	_pill(modes, "mode:solo", tr("BOARD_SOLO"), func() -> void:
		_mode = "solo"
		fetch())
	_pill(modes, "mode:coop", tr("BOARD_COOP"), func() -> void:
		_mode = "coop"
		fetch())
	var periods := UiStyle.hbox()
	filters.add_child(periods)
	_pill(periods, "period:all", tr("BOARD_ALL"), func() -> void:
		_period = "all"
		fetch())
	_pill(periods, "period:week", tr("BOARD_WEEK"), func() -> void:
		_period = "week"
		fetch())
	_build_list(LIST_HEIGHT)


## Shows another fixed map key (the Tageskarte after midnight).
func set_map(map: String) -> void:
	_map = StringName(map)


func _build_list(height: float) -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, height)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS.size()
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(_grid)
	_status = UiStyle.label(&"LabelMuted", "")
	add_child(_status)
	Board.listed.connect(_on_listed)


func fetch() -> void:
	for key: String in _pills:
		var parts: PackedStringArray = key.split(":")
		var on: bool = (parts[0] == "map" and parts[1] == String(_map)) or (parts[0] == "mode" and parts[1] == _mode) \
				or (parts[0] == "period" and parts[1] == _period)
		_pills[key].set_pressed_no_signal(on)
	_status.text = tr("BOARD_LOADING")
	_fill([])
	Board.fetch(_mode, String(_map), _period)


func _pill(row: HBoxContainer, key: String, text: String, pressed: Callable) -> void:
	var pill := ActionPill.new()
	pill.set_label(text)
	pill.toggle_mode = true
	pill.pressed.connect(pressed)
	row.add_child(pill)
	_pills[key] = pill


func _on_listed(mode: String, map: String, period: String, entries: Array, ok: bool) -> void:
	if mode != _mode or map != String(_map) or period != _period:
		return
	_status.text = "" if ok and not entries.is_empty() else tr("BOARD_OFFLINE") if not ok else tr("BOARD_EMPTY")
	_fill(entries)


func _fill(entries: Array) -> void:
	for child: Node in _grid.get_children():
		child.queue_free()
	if entries.is_empty():
		return
	for def: Array in COLUMNS:
		_grid.add_child(_cell(tr(def[0]) if def[0] != "" and def[0] != "#" else def[0], def[1], &"LabelMuted"))
	for k: int in entries.size():
		var entry: Dictionary = entries[k]
		var variation: StringName = &"LabelAccent" if Board.is_mine(int(entry.get("id", 0))) else &"LabelSmall"
		var characters: PackedStringArray = []
		for id: Variant in entry.get("characters", []):
			var character: CharacterData = content.character(StringName(str(id)))
			characters.append(tr(character.name_key) if character != null else str(id))
		var grant: int = clampi(int(entry.get("grant", 1)), 0, content.grants.size() - 1)
		var time: int = int(entry.get("time", 0))
		var cells: Array = [
			str(k + 1), ", ".join(PackedStringArray(entry.get("names", []))), ", ".join(characters),
			"%s · %s" % [tr("BOARD_RESULT_%d" % clampi(int(entry.get("result", 0)), 0, 2)), tr(content.grants[grant].name_key)],
			"%d:%02d" % [time / 60, time % 60], str(int(entry.get("level", 0))), str(int(entry.get("kills", 0))),
			str(int(entry.get("knodl", 0))),
		]
		for c: int in cells.size():
			_grid.add_child(_cell(cells[c], COLUMNS[c][1], variation if c > 0 else &"LabelMuted"))


func _cell(text: String, width: float, variation: StringName) -> Label:
	var label: Label = UiStyle.label(variation, text)
	label.custom_minimum_size = Vector2(width, 0.0)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label
