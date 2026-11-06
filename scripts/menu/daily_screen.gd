class_name DailyScreen
extends PanelContainer
## "Tageskarte" (Daily Kirtag, 1.4 task 5.1): today's card – the Knödlinger, map and Grant level that
## everyone plays today (Daily.pick) – whether today's first try is still open, the streak, and the
## day's own Ehrentafel. "Auf geht's!" (Enter) starts it.

signal start_pressed
signal closed

var content: GameContent
var balance: BalanceData
var _day: String = ""
var _date: Label
var _portrait_box: CenterContainer
var _name: Label
var _role: Label
var _map: Label
var _grant: Label
var _trait: Label
var _status: Label
var _streak: Label
var _board: BoardPanel


func _init(p_content: GameContent) -> void:
	content = p_content
	balance = load("res://data/balance.tres")
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := UiStyle.vbox(&"Gap16")
	add_child(column)
	var header: PanelContainer = UiStyle.panel(&"PanelHeader")
	column.add_child(header)
	var heading := UiStyle.vbox(&"Tight")
	header.add_child(heading)
	heading.add_child(UiStyle.label(&"LabelTitle", tr("DAILY_TITLE")))
	_date = UiStyle.label(&"LabelMuted")
	heading.add_child(_date)
	# The card: portrait, who, where, how grantig.
	var card := UiStyle.hbox(&"Row16")
	column.add_child(card)
	_portrait_box = CenterContainer.new()
	_portrait_box.custom_minimum_size = Vector2(80.0, 80.0)
	card.add_child(_portrait_box)
	var who := UiStyle.vbox(&"Tight")
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.add_child(who)
	_name = UiStyle.label(&"LabelAccent")
	who.add_child(_name)
	_role = UiStyle.label(&"LabelMuted")
	who.add_child(_role)
	_map = UiStyle.label(&"LabelSmall")
	who.add_child(_map)
	_grant = UiStyle.label(&"LabelSmall")
	who.add_child(_grant)
	_trait = UiStyle.label(&"LabelMuted")
	_trait.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_trait.custom_minimum_size = Vector2(560.0, 0.0)
	column.add_child(_trait)
	var notes := UiStyle.vbox(&"Tight")
	column.add_child(notes)
	_status = UiStyle.label(&"LabelSmall")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(560.0, 0.0)
	notes.add_child(_status)
	_streak = UiStyle.label(&"LabelChange")
	notes.add_child(_streak)
	column.add_child(UiStyle.label(&"LabelAccent", tr("DAILY_BOARD")))
	_board = BoardPanel.new(content, "daily", Daily.board_map(Daily.today()))
	column.add_child(_board)
	var buttons := UiStyle.hbox(&"Row16")
	column.add_child(buttons)
	var start := ActionPill.new("Enter", &"ui_accept")
	start.set_label(tr("PLAY_START"))
	start.pressed.connect(_on_start)
	buttons.add_child(start)
	var back := ActionPill.new("Esc", &"ui_cancel")
	back.set_label(tr("MENU_BACK"))
	back.pressed.connect(func() -> void: closed.emit())
	buttons.add_child(back)


## Today's card (the day may have turned since the menu opened).
func refresh() -> void:
	_day = Daily.today()
	var card: Dictionary = Daily.pick(content, balance, _day)
	var character: CharacterData = content.character(card["character"])
	var info: MapInfo = content.map_info(card["map"])
	_date.text = tr("DAILY_DATE") % Daily.date_text(_day)
	for child: Node in _portrait_box.get_children():
		child.queue_free()
	_portrait_box.add_child(FamilyPortrait.new(character, 72.0))
	_name.text = tr(character.name_key)
	_role.text = tr(character.role_key)
	_map.text = tr("DAILY_MAP") % tr(info.name_key)
	_grant.text = tr("DAILY_GRANT") % tr(content.grants[int(card["grant"])].name_key)
	_trait.text = tr(character.trait_key)
	_status.text = tr("DAILY_PRACTICE") if Profile.daily_played(_day) else tr("DAILY_FIRST")
	_streak.text = tr("DAILY_STREAK") % [Profile.daily_streak(_day), Profile.daily_best_streak()]
	_board.set_map(Daily.board_map(_day))
	_board.fetch()


func focus_first() -> void:
	pass


func day() -> String:
	return _day


func _on_start() -> void:
	GameAudio.play(&"card")
	start_pressed.emit()


## Enter (or A) starts.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var key: InputEventKey = event as InputEventKey
	var start: bool = (key != null and key.pressed and not key.echo
			and (key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_KP_ENTER)) \
			or (event is InputEventJoypadButton and event.is_action_pressed(&"ui_accept"))
	if start:
		get_viewport().set_input_as_handled()
		_on_start()
