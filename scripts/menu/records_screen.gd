class_name RecordsScreen
extends PanelContainer
## "Rekorde": the player's own best runs per map, one row per Knödlinger (longest time, wins and
## highest Grant won, highest level, most kills, biggest Knödl, most Schilling from one run). The
## online Ehrentafel sits beside it (`board`, added when it exists).

signal closed

const COLUMNS: Array = [
	["time", "REC_TIME"], ["wins", "REC_WINS"], ["level", "REC_LEVEL"], ["kills", "REC_KILLS"],
	["knodl", "REC_KNODL"], ["schilling", "REC_SCHILLING"],
]
const NAME_WIDTH: float = 168.0
const VALUE_WIDTH: float = 88.0

var content: GameContent
var _body: VBoxContainer
var _tabs: HBoxContainer
## The online board (part of this screen once it exists); null shows only the own records.
var board: Control


func _init(p_content: GameContent) -> void:
	content = p_content
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := UiStyle.vbox(&"Gap16")
	add_child(column)
	var header: PanelContainer = UiStyle.panel(&"PanelHeader")
	column.add_child(header)
	header.add_child(UiStyle.label(&"LabelTitle", tr("RECORDS_TITLE")))
	_tabs = UiStyle.hbox(&"Row16")
	column.add_child(_tabs)
	_body = UiStyle.vbox(&"Gap24")
	column.add_child(_body)
	var back := ActionPill.new("Esc")
	back.set_label(tr("MENU_BACK"))
	back.pressed.connect(func() -> void: closed.emit())
	column.add_child(back)


func refresh() -> void:
	for child: Node in _body.get_children():
		child.queue_free()
	for info: MapInfo in content.maps:
		var block := UiStyle.vbox()
		_body.add_child(block)
		block.add_child(UiStyle.label(&"LabelAccent", tr(info.name_key)))
		var grid := GridContainer.new()
		grid.columns = COLUMNS.size() + 1
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		block.add_child(grid)
		grid.add_child(_cell("", NAME_WIDTH, &"LabelMuted"))
		for def: Array in COLUMNS:
			grid.add_child(_cell(tr(def[1]), VALUE_WIDTH, &"LabelMuted"))
		var any: bool = false
		for character: CharacterData in content.characters:
			var record: Dictionary = Profile.record(character.id, info.id)
			if record.is_empty():
				continue
			any = true
			grid.add_child(_cell(tr(character.name_key), NAME_WIDTH, &"LabelSmall"))
			for def: Array in COLUMNS:
				grid.add_child(_cell(value_text(def[0], record), VALUE_WIDTH, &"LabelSmall"))
		if not any:
			grid.visible = false
			block.add_child(UiStyle.label(&"LabelMuted", tr("RECORDS_NONE")))


func focus_first() -> void:
	pass


static func value_text(key: String, record: Dictionary) -> String:
	var value: float = float(record.get(key, 0))
	match key:
		"time":
			return "%d:%02d" % [floori(value / 60.0), int(value) % 60]
		"wins":
			var grant: int = int(record.get("grant", -1))
			if value <= 0.0:
				return "0"
			var content: GameContent = GameContent.load_default()
			return "%d · %s" % [roundi(value), TranslationServer.translate(content.grants[clampi(grant, 0, content.grants.size() - 1)].name_key)]
	return str(roundi(value))


func _cell(text: String, width: float, variation: StringName) -> Label:
	var label: Label = UiStyle.label(variation, text)
	label.custom_minimum_size = Vector2(width, 0.0)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label
