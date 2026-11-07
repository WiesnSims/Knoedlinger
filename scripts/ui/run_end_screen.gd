class_name RunEndScreen
extends CanvasLayer
## The end of a run with the local player's numbers: won (Sperrstund' with the Hofrat beaten,
## GAME-DESIGN.md "run ends as victory if you survived the boss"), closed (Sperrstund' but the Hofrat
## still sits in his Amt) or lost (knocked out). A title, one line, the numbers as a two-column list,
## the final build beside it. In solo "Nochmal!" starts a new run; online the host decides (M6).
## Schilling and the 25 % Knödl payout are saved from M4 on. A second tab, the Run-Abrechnung (1.4
## task 5.4), bills the damage: per weapon, the Knödl and the extras (share and kills), and what
## knocked the player down most often. Left / Right (LB / RB) switch the tabs. A long list (many
## items, many Aufträge) scrolls inside the panel, so the buttons below always stay on screen (1.4.1, B4).

signal again_pressed
signal menu_pressed

const WIDTH: float = 400.0
## Milliseconds before the pad's A / B count on this screen.
const PAD_ARM_MS: int = 1000
## Space kept free above and below the panel; the pad / arrow keys scroll the list this far per press.
const SCREEN_MARGIN: float = 32.0
const SCROLL_STEP: float = 48.0
## Summary key, label key, how to show it ("time_past": a time, only shown when there was any).
const ROWS: Array = [
	["time", "END_STAT_TIME", "time"], ["overtime", "END_STAT_OVERTIME", "time_past"],
	["level", "END_STAT_LEVEL", "int"], ["kills", "END_STAT_KILLS", "int"],
	["gold", "END_STAT_GOLD", "int"], ["best_knodl_mass", "END_STAT_KNODL", "int"],
	["cash_in_total", "END_STAT_CASH_INS", "int"], ["bosses_beaten", "END_STAT_BOSSES", "count"],
	["stempel", "END_STAT_STEMPEL", "int"], ["deaths", "END_STAT_DOWNED", "int"],
]

## Run-Abrechnung columns: label key, width.
const BILL_COLUMNS: Array = [["", 168.0], ["BILL_DAMAGE", 72.0], ["BILL_SHARE", 56.0], ["BILL_KILLS", 64.0]]

var _shown: Control
var _title: Label
var _line: Label
var _grid: GridContainer
## The Run-Abrechnung tab and the two tab pills.
var _bill: VBoxContainer
var _numbers_pill: ActionPill
var _bill_pill: ActionPill
## What the Profile paid: Schilling, quests stamped, a new Grant level.
var _reward_box: VBoxContainer
## "Ehrentafel: Platz 12 · diese Woche 3", once the board answered.
var _rank_label: Label
var _inventory: InventoryPanel
var _again: ActionPill
var _shown_ms: int = 0
var _menu: ActionPill
var _panel: PanelContainer
## The numbers, the Run-Abrechnung and the rewards scroll; the heading, tabs and buttons do not.
var _scroll: ScrollContainer
var _body: VBoxContainer


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root: Control = UiStyle.root(self)
	_shown = Control.new()
	_shown.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_shown)
	var shade := ColorRect.new()
	shade.color = Color(UiStyle.color("panel"), 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shown.add_child(shade)
	var row := UiStyle.hbox(&"Row32")
	UiStyle.centred(_shown).add_child(row)
	_panel = UiStyle.panel()
	_panel.custom_minimum_size = Vector2(WIDTH, 0.0)
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_panel)
	var column := UiStyle.vbox(&"Gap24")
	_panel.add_child(column)
	var heading := UiStyle.vbox(&"Tight")
	column.add_child(heading)
	_title = UiStyle.label(&"LabelTitle")
	heading.add_child(_title)
	_line = UiStyle.label(&"LabelMuted")
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(_line)
	var tabs := UiStyle.hbox()
	column.add_child(tabs)
	_numbers_pill = ActionPill.new("", &"shoulder_left")
	_numbers_pill.set_label(tr("END_TAB_NUMBERS"))
	_numbers_pill.toggle_mode = true
	_numbers_pill.pressed.connect(func() -> void: _show_bill(false))
	tabs.add_child(_numbers_pill)
	_bill_pill = ActionPill.new("", &"shoulder_right")
	_bill_pill.set_label(tr("END_TAB_BILL"))
	_bill_pill.toggle_mode = true
	_bill_pill.pressed.connect(func() -> void: _show_bill(true))
	tabs.add_child(_bill_pill)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_body = UiStyle.vbox(&"Gap24")
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	_body.add_child(_grid)
	_bill = UiStyle.vbox()
	_body.add_child(_bill)
	_reward_box = UiStyle.vbox(&"Tight")
	_body.add_child(_reward_box)
	_again = ActionPill.new("Enter", &"ui_accept")
	_again.set_label(tr("END_AGAIN"))
	_again.pressed.connect(func() -> void: again_pressed.emit())
	var buttons := UiStyle.hbox(&"Row16")
	column.add_child(buttons)
	buttons.add_child(_again)
	_menu = ActionPill.new("Esc", &"ui_cancel")
	_menu.set_label(tr("END_MENU"))
	_menu.pressed.connect(func() -> void: menu_pressed.emit())
	buttons.add_child(_menu)
	_inventory = InventoryPanel.new(false, true)
	row.add_child(_inventory)
	visible = false
	get_viewport().size_changed.connect(_fit_scroll)


## `summary` is RunWorld's run summary of the local player; `build` and `balance` show the build.
func show_result(summary: Dictionary, can_restart: bool, build: PlayerBuild = null, balance: BalanceData = null,
		reward: Dictionary = {}) -> void:
	for child: Node in _reward_box.get_children():
		child.queue_free()
	_reward_box.visible = not reward.is_empty()
	if not reward.is_empty():
		var schilling := UiStyle.hbox()
		_reward_box.add_child(schilling)
		var label: Label = UiStyle.label(&"LabelAccent", tr("END_SCHILLING"))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		schilling.add_child(label)
		schilling.add_child(UiStyle.label(&"LabelAccent", "+%d" % int(reward.get("schilling", 0))))
		for quest: QuestData in reward.get("quests", []):
			var line: String = tr("END_QUEST_DONE") % tr(quest.title_key)
			if quest.unlock_kind != &"":
				line += " · " + tr("END_UNLOCKED")
			_reward_box.add_child(UiStyle.label(&"LabelSmall", line))
		if reward.get("grant_unlocked", false):
			_reward_box.add_child(UiStyle.label(&"LabelSmall", tr("END_GRANT_UP")))
		_rank_label = UiStyle.label(&"LabelChange", "")
		_rank_label.visible = false
		_reward_box.add_child(_rank_label)
	var outcome: String = str(summary.get("result", "WON"))
	_title.text = tr("END_TITLE_%s" % outcome)
	_line.text = tr("END_%s" % outcome)
	var daily: String = str(summary.get("daily", ""))
	if daily != "":
		_line.text += "
" + tr("END_DAILY") % Daily.date_text(daily)
	for child: Node in _grid.get_children():
		child.queue_free()
	for row_def: Array in ROWS:
		if row_def[2] == "time_past" and float(summary.get(row_def[0], 0.0)) < 1.0:
			continue
		var name: Label = UiStyle.label(&"LabelMuted", tr(row_def[1]))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(name)
		var raw: Variant = summary.get(row_def[0], 0)
		var text: String = ""
		match row_def[2]:
			"time", "time_past":
				var seconds: int = int(float(raw))
				text = "%d:%02d" % [floori(seconds / 60.0), seconds % 60]
			"count":
				text = str((raw as Array).size()) if raw is Array else str(raw)
			"int":
				text = str(roundi(float(raw)))
		var value: Label = UiStyle.label(&"LabelSmall", text)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_grid.add_child(value)
	_fill_bill(summary)
	_show_bill(false)
	_even_tabs()
	_inventory.visible = build != null and balance != null
	if _inventory.visible:
		_inventory.show_build(build, balance)
	_again.visible = can_restart
	visible = true
	_shown_ms = Time.get_ticks_msec()
	_shown.modulate.a = 0.0
	create_tween().tween_property(_shown, "modulate:a", 1.0, UiStyle.T_PANEL_IN * 2.0)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Co-op: "again" takes everyone back to the room (host), the other button leaves it.
func set_button_labels(again_key: String, menu_key: String) -> void:
	_again.set_label(tr(again_key))
	_menu.set_label(tr(menu_key))


func show_rank(rank: int, week_rank: int, daily: bool = false) -> void:
	if _rank_label != null and is_instance_valid(_rank_label):
		_rank_label.text = tr("END_BOARD_RANK_DAILY") % rank if daily else tr("END_BOARD_RANK") % [rank, week_rank]
		_rank_label.visible = true


func _show_bill(on: bool) -> void:
	_numbers_pill.set_pressed_no_signal(not on)
	_bill_pill.set_pressed_no_signal(on)
	_grid.visible = not on
	_bill.visible = on


## Both tabs get the taller one's height, so switching them does not move the panels. Measured over
## two frames after layout, while the screen is still fading in.
func _even_tabs() -> void:
	_grid.custom_minimum_size.y = 0.0
	_bill.custom_minimum_size.y = 0.0
	await get_tree().process_frame
	var numbers: float = _grid.size.y
	var was_bill: bool = _bill.visible
	_show_bill(true)
	await get_tree().process_frame
	var height: float = maxf(numbers, _bill.size.y)
	_grid.custom_minimum_size.y = height
	_bill.custom_minimum_size.y = height
	_show_bill(was_bill)
	_fit_scroll()


## The scrolling part is as tall as its content, but never so tall that the panel leaves the screen.
func _fit_scroll() -> void:
	if _scroll == null or not visible:
		return
	_scroll.custom_minimum_size.y = 0.0
	var fixed: float = _panel.get_combined_minimum_size().y
	var room: float = get_viewport().get_visible_rect().size.y - 2.0 * SCREEN_MARGIN - fixed
	_scroll.custom_minimum_size.y = clampf(_body.get_combined_minimum_size().y, 0.0, maxf(room, SCROLL_STEP))
	_scroll.scroll_vertical = 0


## The Run-Abrechnung from the summary's damage_by_source / kills_by_source / downed_by.
func _fill_bill(summary: Dictionary) -> void:
	for child: Node in _bill.get_children():
		child.queue_free()
	var damage: Dictionary = summary.get("damage_by_source", {})
	var kills: Dictionary = summary.get("kills_by_source", {})
	var total: float = 0.0
	for key: Variant in damage:
		total += float(damage[key])
	var grid := GridContainer.new()
	grid.columns = BILL_COLUMNS.size()
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bill.add_child(grid)
	for def: Array in BILL_COLUMNS:
		grid.add_child(_bill_cell(tr(def[0]) if def[0] != "" else "", def[1], &"LabelMuted", def[0] != ""))
	var order: Array = damage.keys()
	order.sort_custom(func(a: Variant, b: Variant) -> bool: return float(damage[a]) > float(damage[b]))
	var catalog: UpgradeCatalog = load("res://data/catalog/catalog.tres")
	for key: Variant in order:
		var name: String = tr("BILL_KNODL") if key == "knodl" else tr("BILL_EXTRA") if key == "extra" else str(key)
		for weapon: WeaponData in catalog.weapons:
			if String(weapon.id) == str(key):
				name = tr(weapon.name_key)
		grid.add_child(_bill_cell(name, BILL_COLUMNS[0][1], &"LabelSmall", false))
		grid.add_child(_bill_cell(short_number(float(damage[key])), BILL_COLUMNS[1][1], &"LabelSmall", true))
		grid.add_child(_bill_cell("%d %%" % roundi(100.0 * float(damage[key]) / maxf(total, 0.001)), BILL_COLUMNS[2][1],
				&"LabelSmall", true))
		grid.add_child(_bill_cell(str(int(kills.get(key, 0))), BILL_COLUMNS[3][1], &"LabelSmall", true))
	grid.visible = not order.is_empty()
	if order.is_empty():
		_bill.add_child(UiStyle.label(&"LabelMuted", tr("BILL_NONE")))
	# The most frequent knock-down cause.
	var downed: Dictionary = summary.get("downed_by", {})
	var worst: String = ""
	for cause: Variant in downed:
		if worst == "" or int(downed[cause]) > int(downed[worst]):
			worst = str(cause)
	var line: Label
	if worst == "":
		line = UiStyle.label(&"LabelMuted", tr("BILL_NEVER_DOWN"))
	else:
		var who: String = tr("BILL_ATTACK")
		for enemy: EnemyTypeData in GameContent.load_default().enemies:
			if String(enemy.id) == worst:
				who = tr(enemy.name_key)
		line = UiStyle.label(&"LabelMuted", tr("BILL_DOWN_BY") % [who, int(downed[worst])])
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(WIDTH - 48.0, 0.0)
	_bill.add_child(line)


## 950, 12,3k, 4,5 Mio.
static func short_number(value: float) -> String:
	if value < 10000.0:
		return str(roundi(value))
	if value < 1000000.0:
		return ("%.1fk" % (value / 1000.0)).replace(".", ",")
	return ("%.1f Mio" % (value / 1000000.0)).replace(".", ",")


func _bill_cell(text: String, width: float, variation: StringName, right: bool) -> Label:
	var label: Label = UiStyle.label(variation, text)
	label.custom_minimum_size = Vector2(width, 0.0)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if right:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var tab_key: InputEventKey = event as InputEventKey
	if tab_key != null and tab_key.pressed and not tab_key.echo \
			and (tab_key.physical_keycode == KEY_LEFT or tab_key.physical_keycode == KEY_RIGHT):
		get_viewport().set_input_as_handled()
		_show_bill(tab_key.physical_keycode == KEY_RIGHT)
		return
	if event.is_action_pressed(&"shoulder_left") or event.is_action_pressed(&"shoulder_right"):
		get_viewport().set_input_as_handled()
		_show_bill(event.is_action_pressed(&"shoulder_right"))
		return
	if event.is_action_pressed(&"ui_up", true) or event.is_action_pressed(&"ui_down", true):
		get_viewport().set_input_as_handled()
		_scroll.scroll_vertical += roundi(SCROLL_STEP * (1.0 if event.is_action_pressed(&"ui_down", true) else -1.0))
		return
	var key: InputEventKey = event as InputEventKey
	var pad: InputEventJoypadButton = event as InputEventJoypadButton
	# The pad's A was a jump a moment ago: it only counts once the screen has been up a little.
	var armed: bool = Time.get_ticks_msec() - _shown_ms > PAD_ARM_MS
	var again: bool = (key != null and key.pressed and not key.echo
			and (key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_KP_ENTER)) 			or (pad != null and armed and event.is_action_pressed(&"ui_accept"))
	var back: bool = (key != null and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE) 			or (pad != null and armed and event.is_action_pressed(&"ui_cancel"))
	if _again.visible and again:
		get_viewport().set_input_as_handled()
		again_pressed.emit()
	elif back:
		get_viewport().set_input_as_handled()
		menu_pressed.emit()
