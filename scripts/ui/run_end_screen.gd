class_name RunEndScreen
extends CanvasLayer
## The end of a run with the local player's numbers: won (Sperrstund' with the Hofrat beaten,
## GAME-DESIGN.md "run ends as victory if you survived the boss"), closed (Sperrstund' but the Hofrat
## still sits in his Amt) or lost (knocked out). A title, one line, the numbers as a two-column list,
## the final build beside it. In solo "Nochmal!" starts a new run; online the host decides (M6).
## Schilling and the 25 % Knödl payout are saved from M4 on.

signal again_pressed
signal menu_pressed

const WIDTH: float = 400.0
## Summary key, label key, how to show it.
const ROWS: Array = [
	["time", "END_STAT_TIME", "time"], ["level", "END_STAT_LEVEL", "int"], ["kills", "END_STAT_KILLS", "int"],
	["gold", "END_STAT_GOLD", "int"], ["best_knodl_mass", "END_STAT_KNODL", "int"],
	["cash_in_total", "END_STAT_CASH_INS", "int"], ["bosses_beaten", "END_STAT_BOSSES", "count"],
	["stempel", "END_STAT_STEMPEL", "int"], ["deaths", "END_STAT_DOWNED", "int"],
]

var _shown: Control
var _title: Label
var _line: Label
var _grid: GridContainer
## What the Profile paid: Schilling, quests stamped, a new Grant level.
var _reward_box: VBoxContainer
var _inventory: InventoryPanel
var _again: ActionPill
var _menu: ActionPill


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
	var panel: PanelContainer = UiStyle.panel()
	panel.custom_minimum_size = Vector2(WIDTH, 0.0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(panel)
	var column := UiStyle.vbox(&"Gap24")
	panel.add_child(column)
	var heading := UiStyle.vbox(&"Tight")
	column.add_child(heading)
	_title = UiStyle.label(&"LabelTitle")
	heading.add_child(_title)
	_line = UiStyle.label(&"LabelMuted")
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(_line)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_grid)
	_reward_box = UiStyle.vbox(&"Tight")
	column.add_child(_reward_box)
	_again = ActionPill.new("Enter")
	_again.set_label(tr("END_AGAIN"))
	_again.pressed.connect(func() -> void: again_pressed.emit())
	var buttons := UiStyle.hbox(&"Row16")
	column.add_child(buttons)
	buttons.add_child(_again)
	_menu = ActionPill.new("Esc")
	_menu.set_label(tr("END_MENU"))
	_menu.pressed.connect(func() -> void: menu_pressed.emit())
	buttons.add_child(_menu)
	_inventory = InventoryPanel.new()
	row.add_child(_inventory)
	visible = false


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
	var outcome: String = str(summary.get("result", "WON"))
	_title.text = tr("END_TITLE_%s" % outcome)
	_line.text = tr("END_%s" % outcome)
	for child: Node in _grid.get_children():
		child.queue_free()
	for row_def: Array in ROWS:
		var name: Label = UiStyle.label(&"LabelMuted", tr(row_def[1]))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(name)
		var raw: Variant = summary.get(row_def[0], 0)
		var text: String = ""
		match row_def[2]:
			"time":
				var seconds: int = int(float(raw))
				text = "%d:%02d" % [floori(seconds / 60.0), seconds % 60]
			"count":
				text = str((raw as Array).size()) if raw is Array else str(raw)
			"int":
				text = str(roundi(float(raw)))
		var value: Label = UiStyle.label(&"LabelSmall", text)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_grid.add_child(value)
	_inventory.visible = build != null and balance != null
	if _inventory.visible:
		_inventory.show_build(build, balance)
	_again.visible = can_restart
	visible = true
	_shown.modulate.a = 0.0
	create_tween().tween_property(_shown, "modulate:a", 1.0, UiStyle.T_PANEL_IN * 2.0)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if not visible or key == null or not key.pressed or key.echo:
		return
	if _again.visible and (key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		again_pressed.emit()
	elif key.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		menu_pressed.emit()
