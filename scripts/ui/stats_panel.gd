class_name StatsPanel
extends PanelContainer
## Every stat of the local player in five short groups (docs/UI-STYLE.md; Megabonk's stats panel):
## name left, value right. While a Speisekarte card is hovered, the stats it changes show their new
## value in the accent ("+8 %  →  +16 %"). Shown right of the Speisekarte and in the Tab screen.

const WIDTH: float = 280.0
## Group title key, then the rows: [stat key or special id, label key].
const GROUPS: Array = [
	["STATS_SURVIVE", [[&"max_hp", "STAT_MAX_HP"], [&"regen", "STAT_REGEN"], [&"armor", "STAT_ARMOR"]]],
	["STATS_ATTACK", [[&"damage", "STAT_DAMAGE"], [&"crit", "STAT_CRIT"], [&"cooldown", "STAT_COOLDOWN"], [&"area", "STAT_AREA"], [&"knockback", "STAT_KNOCKBACK"]]],
	["STATS_MOVE", [[&"move_speed", "STAT_MOVE_SPEED"], [&"jump_height", "STAT_JUMP_HEIGHT"], [&"extra_jumps", "STAT_EXTRA_JUMPS"], [&"glide", "STAT_GLIDE"], [&"sure_footing", "STAT_SURE_FOOTING"]]],
	["STATS_KNODL", [[&"knodl_mass", "STATS_KNODL_MASS"], [&"knodl_size", "STATS_KNODL_SIZE"], [&"string_length", "STAT_STRING_LENGTH"], [&"pickup", "STAT_PICKUP"]]],
	["STATS_LUCK", [[&"luck", "STAT_LUCK"], [&"gold", "STAT_GOLD"], [&"xp_gain", "STAT_XP_GAIN"]]],
]

var _values: Dictionary[StringName, Label] = {}
var _previews: Dictionary[StringName, Label] = {}
var _now: Dictionary[StringName, float] = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, 0.0)
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var column := UiStyle.vbox(&"Gap16")
	add_child(column)
	column.add_child(UiStyle.label(&"LabelTitle", tr("STATS_TITLE")))
	for group: Array in GROUPS:
		var box := UiStyle.vbox(&"Tight")
		column.add_child(box)
		box.add_child(UiStyle.label(&"LabelChange", tr(group[0]).to_upper()))
		for row_def: Array in group[1]:
			var row := UiStyle.hbox()
			box.add_child(row)
			var name: Label = UiStyle.label(&"LabelMuted", tr(row_def[1]))
			name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# Trimmed, not clipped: a clipped label is its own draw call (scissor), about 18 here.
			name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			row.add_child(name)
			var value: Label = UiStyle.label(&"LabelSmall")
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(value)
			var preview: Label = UiStyle.label(&"LabelChange")
			preview.visible = false
			row.add_child(preview)
			_values[row_def[0]] = value
			_previews[row_def[0]] = preview


func show_stats(state: PlayerState, knodl: Knodl, balance: BalanceData) -> void:
	if state == null or state.build == null:
		return
	var build: PlayerBuild = state.build
	for key: StringName in PlayerBuild.STATS:
		_now[key] = build.stat(key)
	_now[&"max_hp"] = state.max_hp
	_now[&"knodl_mass"] = knodl.knodl_mass if knodl != null else 0.0
	_now[&"knodl_size"] = knodl.radius * 2.0 if knodl != null else 0.0
	for key: StringName in _values:
		_values[key].text = value_text(key, _now.get(key, 0.0), balance)


## Shows what a card would change (stat -> added amount); an empty dictionary clears it.
func preview(changes: Dictionary, balance: BalanceData) -> void:
	for key: StringName in _previews:
		var label: Label = _previews[key]
		label.visible = changes.has(key)
		if label.visible:
			label.text = "→ " + value_text(key, _now.get(key, 0.0) + float(changes[key]), balance)


## "105", "+0.5/s", "+16 %", "7.6 m/s", "1.2 m".
static func value_text(key: StringName, value: float, balance: BalanceData) -> String:
	match key:
		&"max_hp", &"knodl_mass":
			return str(roundi(value))
		&"regen":
			return "%.2f/s" % value if value > 0.0 else "0"
		&"armor":
			# The number, and the share of every hit it takes.
			return "%d (−%d %%)" % [roundi(value), roundi(Formulas.armor_share(value, balance) * 100.0)] if value > 0.0 else "0"
		&"extra_jumps":
			return "+%d" % roundi(value) if value > 0.0 else "0"
		&"move_speed":
			return "%.1f m/s" % (balance.player_speed * (1.0 + value))
		&"knodl_size":
			return "%.1f m" % value
	return "+%d %%" % roundi(value * 100.0) if absf(value) > 0.001 else "0 %"
