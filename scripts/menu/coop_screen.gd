class_name CoopScreen
extends PanelContainer
## "Stammtisch aufmachen" (GAME-DESIGN.md, Co-op): open a room and get its 4-letter code, or join a
## friend's room with theirs. In the room: the four seats (name, Knödlinger, the Wirt = host), the
## family to choose from (a Knödlinger someone else plays is taken: "Es gibt nur eine Oma!"), the
## host's map and Grant level, and "Auf geht's!" for the host once everyone has their own Knödlinger.
## The rules and messages live in the Lobby autoload; this screen only shows them.

signal closed

const SEAT_PORTRAIT: float = 48.0
const PICK := Vector2(72.0, 72.0)
const WIDTH: float = 640.0

## An invite link joins once per page load (leaving the room must not rejoin it).
static var _url_used: bool = false

var content: GameContent
var _offline: VBoxContainer
var _connecting: VBoxContainer
var _room: VBoxContainer
var _error: Label
var _code_edit: LineEdit
var _code_label: Label
var _copy: ActionPill
var _seats: Array[HBoxContainer] = []
var _picks: Dictionary[StringName, Button] = {}
var _map_name: Label
var _grant_name: Label
var _map_row: HBoxContainer
var _grant_row: HBoxContainer
var _room_info: Label
var _status: Label
var _start: ActionPill


func _init(p_content: GameContent) -> void:
	content = p_content
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, 0.0)
	var column := UiStyle.vbox(&"Gap16")
	add_child(column)
	var header: PanelContainer = UiStyle.panel(&"PanelHeader")
	column.add_child(header)
	header.add_child(UiStyle.label(&"LabelTitle", tr("MENU_COOP")))
	_build_offline(column)
	_build_connecting(column)
	_build_room(column)
	_error = UiStyle.label(&"LabelAccent")
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.custom_minimum_size = Vector2(WIDTH - 48.0, 0.0)
	column.add_child(_error)
	Lobby.changed.connect(_show)
	NetworkManager.roster_changed.connect(_show)
	Lobby.failed.connect(func(reason: String) -> void:
		GameAudio.play(&"no_gold")
		_say(error_text(reason))
		_show())
	# The menu calls refresh() when it opens the screen (after the name prompt, so an invite link
	# joins with the right name).
	_show()


## The menu opened this screen: a link with ?room=KNDL joins at once.
func refresh() -> void:
	_say(error_text(Lobby.error) if Lobby.error != "" else "")
	if Lobby.state == Lobby.State.OFFLINE:
		var room: String = _room_from_url()
		if room != "":
			_code_edit.text = room
			Lobby.join_room(room)
	_show()


func focus_first() -> void:
	if Lobby.state == Lobby.State.OFFLINE:
		_code_edit.grab_focus()


## A relay or handshake reason as a sentence for the player.
static func error_text(reason: String) -> String:
	match reason:
		"", "left":
			return ""
		"version", "build":
			return TranslationServer.translate("NET_VERSION_MISMATCH")
		"full", "started", "no_room", "host_left", "kicked", "game":
			return TranslationServer.translate("COOP_ERR_" + reason.to_upper())
	return TranslationServer.translate("COOP_ERR_LOST")


func _build_offline(column: VBoxContainer) -> void:
	_offline = UiStyle.vbox(&"Gap16")
	column.add_child(_offline)
	var line: Label = UiStyle.label(&"LabelMuted", tr("COOP_LINE"))
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(WIDTH - 48.0, 0.0)
	_offline.add_child(line)
	var open := ActionPill.new("Enter", &"ui_accept")
	open.set_label(tr("COOP_OPEN"))
	open.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	open.pressed.connect(func() -> void:
		GameAudio.play(&"card")
		Lobby.open_room())
	_offline.add_child(open)
	_offline.add_child(UiStyle.label(&"LabelAccent", tr("COOP_JOIN_TITLE")))
	var row := UiStyle.hbox(&"Row16")
	_offline.add_child(row)
	_code_edit = LineEdit.new()
	_code_edit.max_length = RoomCode.LENGTH
	_code_edit.placeholder_text = "KNDL"
	_code_edit.custom_minimum_size = Vector2(160.0, 40.0)
	_code_edit.text_changed.connect(func(text: String) -> void:
		var caret: int = _code_edit.caret_column
		_code_edit.text = RoomCode.normalize(text)
		_code_edit.caret_column = caret)
	# Enter with no code opens a room (the Aufmachen pill shows the Enter key), with a code joins it.
	_code_edit.text_submitted.connect(func(text: String) -> void:
		if text.strip_edges() == "":
			GameAudio.play(&"card")
			Lobby.open_room()
		else:
			_join())
	row.add_child(_code_edit)
	var join := ActionPill.new("", &"")
	join.set_label(tr("COOP_JOIN"))
	join.pressed.connect(_join)
	row.add_child(join)
	var back := ActionPill.new("Esc", &"ui_cancel")
	back.set_label(tr("MENU_BACK"))
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func() -> void: closed.emit())
	_offline.add_child(back)


func _build_connecting(column: VBoxContainer) -> void:
	_connecting = UiStyle.vbox(&"Gap16")
	column.add_child(_connecting)
	_connecting.add_child(UiStyle.label(&"LabelSmall", tr("COOP_CONNECTING")))
	var cancel := ActionPill.new("Esc", &"ui_cancel")
	cancel.set_label(tr("COOP_LEAVE"))
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cancel.pressed.connect(Lobby.leave)
	_connecting.add_child(cancel)


func _build_room(column: VBoxContainer) -> void:
	_room = UiStyle.vbox(&"Gap16")
	column.add_child(_room)
	# The code, big, and the invite link.
	var code_row := UiStyle.hbox(&"Row16")
	_room.add_child(code_row)
	var code_box := UiStyle.vbox(&"Tight")
	code_row.add_child(code_box)
	code_box.add_child(UiStyle.label(&"LabelMuted", tr("COOP_ROOM")))
	# Letters a friend has to read out: the number font, not the Fraktur title font.
	_code_label = UiStyle.label(&"HudNumber")
	code_box.add_child(_code_label)
	_copy = ActionPill.new("", &"")
	_copy.set_label(tr("COOP_COPY"))
	_copy.size_flags_vertical = Control.SIZE_SHRINK_END
	_copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(NetworkManager.invite_url())
		GameAudio.play(&"card")
		_copy.set_label(tr("COOP_COPIED")))
	code_row.add_child(_copy)
	# The four seats, two by two.
	var seats := GridContainer.new()
	seats.columns = 2
	seats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room.add_child(seats)
	for k: int in NetworkManager.MAX_PLAYERS:
		var seat := UiStyle.hbox()
		seat.custom_minimum_size = Vector2((WIDTH - 64.0) * 0.5, SEAT_PORTRAIT)
		seats.add_child(seat)
		var portrait := FamilyPortrait.new(null, SEAT_PORTRAIT)
		seat.add_child(portrait)
		var text := UiStyle.vbox(&"Tight")
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seat.add_child(text)
		var name_label: Label = UiStyle.label(&"LabelSmall")
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text.add_child(name_label)
		var role: Label = UiStyle.label(&"LabelMuted")
		text.add_child(role)
		seat.set_meta(&"portrait", portrait)
		seat.set_meta(&"name", name_label)
		seat.set_meta(&"role", role)
		_seats.append(seat)
	# Who am I: the family, taken ones dimmed.
	_room.add_child(UiStyle.label(&"LabelAccent", tr("COOP_PICK")))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room.add_child(grid)
	for character: CharacterData in content.characters:
		var pick := Button.new()
		pick.custom_minimum_size = PICK
		pick.theme_type_variation = &"CardRarity0"
		var portrait := FamilyPortrait.new(character, PICK.x - 16.0)
		portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		portrait.offset_left = 8.0
		portrait.offset_top = 8.0
		portrait.offset_right = -8.0
		portrait.offset_bottom = -8.0
		pick.add_child(portrait)
		pick.set_meta(&"portrait", portrait)
		var id: StringName = character.id
		pick.pressed.connect(func() -> void: _pick(id))
		pick.mouse_entered.connect(func() -> void: GameAudio.play(&"ui_hover"))
		grid.add_child(pick)
		_picks[id] = pick
	# The host's map and Grant level; the others see them.
	var choices := UiStyle.hbox(&"Row32")
	_room.add_child(choices)
	_map_row = _stepper(choices, func(step: int) -> void: _step_map(step))
	_map_name = _map_row.get_meta(&"label")
	_grant_row = _stepper(choices, func(step: int) -> void: Lobby.choose_map(Lobby.room_map(), clampi(Lobby.room_grant() + step, 0, Profile.grant_unlocked())))
	_grant_name = _grant_row.get_meta(&"label")
	_room_info = UiStyle.label(&"LabelSmall")
	_room.add_child(_room_info)
	_status = UiStyle.label(&"LabelMuted")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(WIDTH - 48.0, 0.0)
	_room.add_child(_status)
	var buttons := UiStyle.hbox(&"Row16")
	_room.add_child(buttons)
	_start = ActionPill.new("Enter", &"ui_accept")
	_start.set_label(tr("PLAY_START"))
	_start.pressed.connect(_on_start)
	buttons.add_child(_start)
	var leave := ActionPill.new("Esc", &"ui_cancel")
	leave.set_label(tr("COOP_LEAVE"))
	leave.pressed.connect(Lobby.leave)
	buttons.add_child(leave)


## ‹ value › with the label in its meta.
func _stepper(parent: Control, step: Callable) -> HBoxContainer:
	var row := UiStyle.hbox(&"Row16")
	parent.add_child(row)
	var down := ActionPill.new("", &"")
	down.set_label("‹")
	down.pressed.connect(func() -> void: step.call(-1))
	row.add_child(down)
	var label: Label = UiStyle.label(&"LabelSmall")
	label.custom_minimum_size = Vector2(160.0, 0.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var up := ActionPill.new("", &"")
	up.set_label("›")
	up.pressed.connect(func() -> void: step.call(1))
	row.add_child(up)
	row.set_meta(&"label", label)
	return row


func _show() -> void:
	_error.visible = _error.text != ""
	if not is_inside_tree():
		return
	_offline.visible = Lobby.state == Lobby.State.OFFLINE
	_connecting.visible = Lobby.state == Lobby.State.CONNECTING
	_room.visible = Lobby.state == Lobby.State.LOBBY
	if not _room.visible:
		return
	_code_label.text = " ".join(NetworkManager.room_code.split(""))
	_copy.visible = NetworkManager.backend == NetworkManager.Backend.RELAY
	var profiles: Dictionary[int, Dictionary] = NetworkManager.profiles
	var order: Array[int] = []
	for peer: int in profiles:
		order.append(peer)
	order.sort()
	var me: int = NetworkManager.local_id()
	var mine: String = str(profiles.get(me, {}).get("character", ""))
	for k: int in _seats.size():
		var seat: HBoxContainer = _seats[k]
		var portrait: FamilyPortrait = seat.get_meta(&"portrait")
		var name_label: Label = seat.get_meta(&"name")
		var role: Label = seat.get_meta(&"role")
		if k >= order.size():
			portrait.character = null
			name_label.text = tr("COOP_FREE")
			role.text = ""
			seat.modulate.a = 0.5
		else:
			var profile: Dictionary = profiles[order[k]]
			var data: CharacterData = content.character(StringName(str(profile.get("character", ""))))
			portrait.character = data
			name_label.text = str(profile.get("name", "")) + (" · " + tr("COOP_HOST") if order[k] == NetworkManager.HOST_ID else "")
			role.text = tr(data.name_key) if data != null else "…"
			seat.modulate.a = 1.0
		portrait.queue_redraw()
	for id: StringName in _picks:
		var pick: Button = _picks[id]
		var taken: bool = Lobby.taken_by_other(id)
		var locked: bool = not Profile.is_unlocked(&"character", id)
		pick.theme_type_variation = &"CardEvolution" if String(id) == mine else &"CardRarity0"
		pick.modulate.a = 0.35 if taken or locked else 1.0
		(pick.get_meta(&"portrait") as FamilyPortrait).locked = locked
		pick.get_meta(&"portrait").queue_redraw()
		var data: CharacterData = content.character(id)
		pick.tooltip_text = tr(data.name_key) if not locked else tr("ALM_UNKNOWN")
		if taken:
			pick.tooltip_text += " – " + tr("COOP_TAKEN")
	var host: bool = NetworkManager.is_host()
	var info: MapInfo = content.map_info(Lobby.room_map())
	var map_text: String = tr(info.name_key) if info != null else String(Lobby.room_map())
	var grant: GrantData = content.grants[clampi(Lobby.room_grant(), 0, content.grants.size() - 1)]
	_map_name.text = map_text
	_grant_name.text = tr(grant.name_key)
	_map_row.visible = host
	_grant_row.visible = host
	_room_info.visible = not host
	_room_info.text = "%s · %s" % [map_text, tr(grant.name_key)]
	_start.visible = host
	_start.disabled = not Lobby.can_start()
	if not host:
		_status.text = tr("COOP_WAIT_HOST")
	elif profiles.size() < Lobby.MIN_PLAYERS:
		_status.text = tr("COOP_WAIT_PLAYERS")
	else:
		_status.text = ""


## The error line, shown only when it says something.
func _say(text: String) -> void:
	_error.text = text
	_error.visible = text != ""


func _join() -> void:
	var code: String = RoomCode.normalize(_code_edit.text)
	if not RoomCode.is_valid(code):
		GameAudio.play(&"no_gold")
		_say(tr("COOP_ERR_NO_ROOM"))
		return
	GameAudio.play(&"card")
	_say("")
	Lobby.join_room(code)


func _pick(id: StringName) -> void:
	if Lobby.taken_by_other(id):
		GameAudio.play(&"no_gold")
		_say(tr("COOP_ONLY_ONE"))
		return
	if not Profile.is_unlocked(&"character", id):
		GameAudio.play(&"no_gold")
		return
	GameAudio.play(&"card")
	_say("")
	Lobby.choose_character(id)


func _step_map(step: int) -> void:
	var at: int = 0
	for k: int in content.maps.size():
		if content.maps[k].id == Lobby.room_map():
			at = k
	# Only maps the host has unlocked.
	for tries: int in content.maps.size():
		at = posmod(at + step, content.maps.size())
		if Profile.is_unlocked(&"map", content.maps[at].id):
			break
	Lobby.choose_map(content.maps[at].id, Lobby.room_grant())


func _on_start() -> void:
	if not Lobby.can_start():
		GameAudio.play(&"no_gold")
		return
	GameAudio.play(&"card")
	Lobby.start()


func _room_from_url() -> String:
	if _url_used:
		return ""
	_url_used = true
	var room: String = ""
	if OS.has_feature("web"):
		room = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('room') || ''", true))
	else:
		room = LaunchArgs.get_string("room", "")
	room = RoomCode.normalize(room)
	return room if RoomCode.is_valid(room) else ""


## Enter starts (host), Esc goes back or leaves the room.
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		if Lobby.state == Lobby.State.OFFLINE:
			closed.emit()
		else:
			Lobby.leave()
	elif event.is_action_pressed(&"ui_accept") and Lobby.state == Lobby.State.LOBBY and NetworkManager.is_host():
		get_viewport().set_input_as_handled()
		_on_start()
