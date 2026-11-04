class_name QuestsScreen
extends PanelContainer
## "Aufträge": the Gemeindeamt quests as a list of forms (GAME-DESIGN.md, "Meta progression"):
## title, what to do, progress, what it pays and unlocks; done ones carry the stamp. Open quests come
## first, closest to done on top.

signal closed

const WIDTH: float = 736.0
const LIST_HEIGHT: float = 416.0

var content: GameContent
var _count: Label
var _list: VBoxContainer
var _scroll: ScrollContainer


func _init(p_content: GameContent) -> void:
	content = p_content
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := UiStyle.vbox(&"Gap16")
	add_child(column)
	var header: PanelContainer = UiStyle.panel(&"PanelHeader")
	column.add_child(header)
	var title_row := UiStyle.hbox()
	header.add_child(title_row)
	var title: Label = UiStyle.label(&"LabelTitle", tr("QUESTS_TITLE"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	_count = UiStyle.label(&"LabelNumber")
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_count)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(WIDTH, LIST_HEIGHT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.focus_mode = Control.FOCUS_ALL
	column.add_child(_scroll)
	_list = UiStyle.vbox()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	var back := ActionPill.new("Esc", &"ui_cancel")
	back.set_label(tr("MENU_BACK"))
	back.pressed.connect(func() -> void: closed.emit())
	column.add_child(back)


func refresh() -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	var open: Array[QuestData] = []
	var done: Array[QuestData] = []
	for quest: QuestData in content.quests:
		if Profile.is_quest_done(quest.id):
			done.append(quest)
		else:
			open.append(quest)
	open.sort_custom(func(a: QuestData, b: QuestData) -> bool:
		return Profile.progress(a) / maxf(a.target, 0.001) > Profile.progress(b) / maxf(b.target, 0.001))
	for quest: QuestData in open + done:
		_list.add_child(_row(quest))
	_count.text = "%d / %d" % [done.size(), content.quests.size()]
	_scroll.scroll_vertical = 0


func focus_first() -> void:
	_scroll.grab_focus()


func _row(quest: QuestData) -> Control:
	var finished: bool = Profile.is_quest_done(quest.id)
	var panel: PanelContainer = UiStyle.panel(&"PanelRaised")
	var row := UiStyle.hbox(&"Row16")
	panel.add_child(row)
	var stamp := QuestStamp.new()
	stamp.done = finished
	stamp.fill = clampf(Profile.progress(quest) / maxf(quest.target, 0.001), 0.0, 1.0)
	row.add_child(stamp)
	var text := UiStyle.vbox(&"Tight")
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	text.add_child(UiStyle.label(&"LabelSmall" if not finished else &"LabelMuted", tr(quest.title_key)))
	var line: Label = UiStyle.label(&"LabelMuted", tr(quest.desc_key))
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(line)
	var side := UiStyle.vbox(&"Tight")
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(side)
	var progress: Label = UiStyle.label(&"LabelSmall", tr("QUEST_DONE") if finished else progress_text(quest))
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	side.add_child(progress)
	var reward: Label = UiStyle.label(&"LabelChange", reward_text(quest))
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	side.add_child(reward)
	return panel


static func progress_text(quest: QuestData) -> String:
	var now: float = minf(Profile.progress(quest), quest.target)
	if quest.kind == &"grant_win":
		return "–"
	return "%d / %d" % [floori(maxf(now, 0.0)), roundi(quest.target)]


## "+100 S · Marterl-Kerze".
static func reward_text(quest: QuestData) -> String:
	var parts: PackedStringArray = []
	if quest.reward_schilling > 0:
		parts.append("+" + TranslationServer.translate("SCHILLING_AMOUNT") % quest.reward_schilling)
	if quest.unlock_kind != &"":
		parts.append(unlock_name(quest.unlock_kind, quest.unlock_id))
	return " · ".join(parts)


## The player-facing name of something a quest unlocks.
static func unlock_name(kind: StringName, id: StringName) -> String:
	var catalog: UpgradeCatalog = load("res://data/catalog/catalog.tres")
	var content: GameContent = GameContent.load_default()
	var key: String = ""
	match kind:
		&"weapon":
			for weapon: WeaponData in catalog.weapons:
				if weapon.id == id:
					key = weapon.name_key
		&"passive":
			for passive: PassiveData in catalog.passives:
				if passive.id == id:
					key = passive.name_key
		&"item":
			for item: ItemData in catalog.items:
				if item.id == id:
					key = item.name_key
		&"character":
			var character: CharacterData = content.character(id)
			key = character.name_key if character != null else ""
		&"map":
			var info: MapInfo = content.map_info(id)
			key = info.name_key if info != null else ""
	return TranslationServer.translate(key) if key != "" else String(id)


## The form's stamp: a ring that fills with the progress, the round Gemeindeamt stamp when done.
class QuestStamp:
	extends Control
	var done: bool = false
	var fill: float = 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(40.0, 40.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 - 4.0
		if done:
			draw_circle(c, r, Color(UiStyle.color("accent"), 0.18))
			draw_arc(c, r, 0.0, TAU, 32, UiStyle.color("accent"), 3.0, true)
			draw_arc(c, r - 6.0, 0.0, TAU, 32, UiStyle.color("accent"), 1.5, true)
			draw_line(c + Vector2(-7.0, 0.0), c + Vector2(-2.0, 6.0), UiStyle.color("accent"), 3.0, true)
			draw_line(c + Vector2(-2.0, 6.0), c + Vector2(8.0, -6.0), UiStyle.color("accent"), 3.0, true)
			return
		draw_arc(c, r, 0.0, TAU, 32, Color(UiStyle.color("muted"), 0.35), 4.0, true)
		if fill > 0.0:
			draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * fill, 32, UiStyle.color("accent"), 4.0, true)
