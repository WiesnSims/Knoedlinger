class_name Hud
extends CanvasLayer
## The M1 HUD: HP, level and XP, run time, the Knödl's size and whether Schupfn is ready, and short
## toasts. Plain shapes for now; the Lebkuchenherzen, Krügerl and wall clock come with the art pass.
## Every player-facing word goes through tr() (i18n/strings.csv).

const TOAST_SECONDS: float = 1.6

var _hp_bar: ProgressBar
var _hp_label: Label
var _xp_bar: ProgressBar
var _level_label: Label
var _time_label: Label
var _knodl_label: Label
var _schupfn_label: Label
var _toast: Label
var _hint: Label
var _toast_timer: float = 0.0
var _last_level: int = 1


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_hp_bar = _bar(Color(0.86, 0.36, 0.42), Vector2(220.0, 18.0))
	_hp_bar.position = Vector2(16.0, 16.0)
	root.add_child(_hp_bar)
	_hp_label = _label(15)
	_hp_label.position = Vector2(244.0, 13.0)
	root.add_child(_hp_label)
	_time_label = _label(28)
	_time_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.position = Vector2(-60.0, 8.0)
	_time_label.size = Vector2(120.0, 36.0)
	root.add_child(_time_label)
	_xp_bar = _bar(Color(0.95, 0.78, 0.3), Vector2(0.0, 12.0))
	_xp_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_xp_bar.offset_top = -14.0
	_xp_bar.offset_bottom = -2.0
	root.add_child(_xp_bar)
	_level_label = _label(18)
	_level_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_level_label.position = Vector2(16.0, -44.0)
	root.add_child(_level_label)
	_knodl_label = _label(18)
	_knodl_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_knodl_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_knodl_label.position = Vector2(-376.0, -70.0)
	_knodl_label.size = Vector2(360.0, 26.0)
	root.add_child(_knodl_label)
	_schupfn_label = _label(16)
	_schupfn_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_schupfn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_schupfn_label.position = Vector2(-376.0, -44.0)
	_schupfn_label.size = Vector2(360.0, 24.0)
	root.add_child(_schupfn_label)
	_toast = _label(34)
	_toast.set_anchors_preset(Control.PRESET_CENTER)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position = Vector2(-300.0, -140.0)
	_toast.size = Vector2(600.0, 48.0)
	root.add_child(_toast)
	_hint = _label(14)
	_hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.position = Vector2(-536.0, 12.0)
	_hint.size = Vector2(520.0, 60.0)
	_hint.text = tr("HUD_CONTROLS")
	root.add_child(_hint)


func show_state(state: PlayerState, knodl: Knodl, run_time: float, balance: BalanceData) -> void:
	_hp_bar.max_value = state.max_hp
	_hp_bar.value = state.hp
	_hp_label.text = "%d / %d" % [ceili(state.hp), roundi(state.max_hp)]
	_xp_bar.value = Formulas.level_progress(state.xp, balance) * 100.0
	_level_label.text = tr("HUD_LEVEL") % state.level
	_time_label.text = "%d:%02d" % [floori(run_time / 60.0), int(run_time) % 60]
	if state.level > _last_level:
		toast(tr("TOAST_LEVEL_UP") % state.level)
	_last_level = state.level
	if knodl != null:
		_knodl_label.text = tr("HUD_KNODL") % [roundi(knodl.knodl_mass), knodl.radius * 2.0]
		match knodl.state:
			Knodl.State.THROWN:
				_schupfn_label.text = tr("HUD_SCHUPFN_REEL")
			Knodl.State.REELING:
				_schupfn_label.text = tr("HUD_SCHUPFN_REELING")
			_:
				_schupfn_label.text = tr("HUD_SCHUPFN_READY") if knodl.cooldown <= 0.0 \
						else tr("HUD_SCHUPFN_COOLDOWN") % knodl.cooldown
	if state.downed:
		_toast.text = tr("TOAST_DOWNED")
		_toast_timer = 0.2


func toast(text: String) -> void:
	_toast.text = text
	_toast_timer = TOAST_SECONDS


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		_toast.modulate.a = clampf(_toast_timer / 0.4, 0.0, 1.0)


func _label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(1.0, 0.98, 0.92))
	label.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.05))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _bar(color: Color, bar_size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = bar_size
	bar.size = bar_size
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.1, 0.07, 0.05, 0.6)
	back.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar
