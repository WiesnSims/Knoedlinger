class_name Hud
extends CanvasLayer
## The HUD (docs/UI-STYLE.md: only the corners are permanent). Top left: health (Lebkuchenherz,
## bar, number) and the XP Krügerl with the level. Top right: the wall clock up to Sperrstund'.
## Bottom right: the Knödl (its size, mass, Wirtshaus tier and the Schupfn cooldown ring).
## Everything else only shows while it matters: the boss bar and the Formular line at the top, toasts,
## the chest hint and the mouse hint at the bottom, the controls for the first seconds of a run, and
## small markers over places (the Wirtshaus one only once the Knödl is worth cashing in).
## The build, gold and stats live in the Inventory screen (Tab). Every word goes through tr().

const TOAST_SECONDS: float = 1.6
const INTRO_SECONDS: float = 10.0
const MARKERS: int = 6
const EDGE: float = 16.0
const HP_BAR := Vector2(176.0, 16.0)

var _hp_bar: ProgressBar
var _hp_label: Label
var _heart: HudGlyph
var _kruegerl: HudGlyph
var _level_label: Label
var _clock: HudGlyph
var _time_label: Label
var _knodl: HudGlyph
var _knodl_mass: Label
var _knodl_tier: Label
var _toast: Label
var _intro: PanelContainer
var _mouse_hint: PanelContainer
var _hint_panel: PanelContainer
var _hint_line: Label
var _boss_box: VBoxContainer
var _boss_name: Label
var _boss_bar: ProgressBar
var _formular_panel: PanelContainer
var _formular: Label
var _wirt_marker: WorldMarker
var _markers: Array[WorldMarker] = []
var _markers_used: int = 0
var _toast_timer: float = 0.0
var _toast_tween: Tween
var _intro_timer: float = INTRO_SECONDS
var _hp_target: float = 0.0
var _boss_target: float = 0.0
var _knodl_tier_index: int = -1
## What the toast says while the local player is down (solo: the run is over).
var downed_key: String = "TOAST_DOWNED"
var _last_level: int = 1
## True while a full-screen panel (Speisekarte, Tab screen, end screen) covers the game; the HUD
## steps back then (RunWorld sets it).
var covered: Callable = func() -> bool: return false
var _root: Control


func _ready() -> void:
	layer = 10
	# Runs while paused, so it can step back behind a solo Speisekarte.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root: Control = UiStyle.root(self)
	_root = root
	# Top left: health and the Krügerl.
	var top_left: PanelContainer = _corner(root, Control.PRESET_TOP_LEFT, &"HudPanel")
	var left := UiStyle.vbox()
	top_left.add_child(left)
	var hp_row := UiStyle.hbox()
	left.add_child(hp_row)
	_heart = HudGlyph.new(HudGlyph.Kind.HEART, 24.0)
	hp_row.add_child(_heart)
	_hp_bar = UiStyle.bar(&"BarHp")
	_hp_bar.custom_minimum_size = HP_BAR
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(_hp_bar)
	_hp_label = UiStyle.label(&"HudSmall")
	_hp_label.custom_minimum_size = Vector2(64.0, 0.0)
	hp_row.add_child(_hp_label)
	var level_row := UiStyle.hbox()
	left.add_child(level_row)
	_kruegerl = HudGlyph.new(HudGlyph.Kind.KRUEGERL, 24.0)
	level_row.add_child(_kruegerl)
	_level_label = UiStyle.label(&"HudLabel")
	level_row.add_child(_level_label)
	# Top right: the clock.
	var top_right: PanelContainer = _corner(root, Control.PRESET_TOP_RIGHT, &"HudPanel")
	var clock_row := UiStyle.hbox()
	top_right.add_child(clock_row)
	_clock = HudGlyph.new(HudGlyph.Kind.CLOCK, 32.0)
	_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clock_row.add_child(_clock)
	_time_label = UiStyle.label(&"HudNumber")
	_time_label.custom_minimum_size = Vector2(80.0, 0.0)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock_row.add_child(_time_label)
	# Bottom right: the Knödl.
	var bottom_right: PanelContainer = _corner(root, Control.PRESET_BOTTOM_RIGHT, &"HudPanel")
	var knodl_row := UiStyle.hbox()
	bottom_right.add_child(knodl_row)
	var knodl_text := UiStyle.vbox(&"Tight")
	knodl_text.alignment = BoxContainer.ALIGNMENT_CENTER
	knodl_row.add_child(knodl_text)
	_knodl_mass = UiStyle.label(&"HudNumber")
	_knodl_mass.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_knodl_mass.custom_minimum_size = Vector2(72.0, 0.0)
	knodl_text.add_child(_knodl_mass)
	_knodl_tier = UiStyle.label(&"HudSmall")
	_knodl_tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	knodl_text.add_child(_knodl_tier)
	_knodl = HudGlyph.new(HudGlyph.Kind.KNODL, 56.0)
	knodl_row.add_child(_knodl)
	# Top centre, only while it matters: the boss bar and the Formular line.
	var top := UiStyle.vbox()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = EDGE
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(top)
	_boss_box = UiStyle.vbox()
	_boss_box.visible = false
	top.add_child(_boss_box)
	_boss_name = UiStyle.label(&"HudLabel")
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_name)
	_boss_bar = UiStyle.bar(&"BarBoss")
	_boss_bar.custom_minimum_size = Vector2(400.0, 12.0)
	_boss_box.add_child(_boss_bar)
	_formular_panel = UiStyle.panel(&"HudPanel")
	_formular_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_formular_panel.visible = false
	top.add_child(_formular_panel)
	_formular = UiStyle.label(&"HudSmall")
	_formular_panel.add_child(_formular)
	# The toast, in the upper middle.
	_toast = UiStyle.label(&"HudNumber")
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position = Vector2(-320.0, -168.0)
	_toast.size = Vector2(640.0, 48.0)
	_toast.pivot_offset = _toast.size * 0.5
	_toast.modulate.a = 0.0
	root.add_child(_toast)
	# Bottom centre: the controls (first seconds only), the mouse hint and the chest hint.
	var bottom := UiStyle.vbox()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -EDGE
	bottom.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(bottom)
	_hint_panel = UiStyle.panel(&"HudPanel")
	_hint_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hint_panel.visible = false
	bottom.add_child(_hint_panel)
	_hint_line = UiStyle.label(&"HudSmall")
	_hint_panel.add_child(_hint_line)
	_mouse_hint = _key_hint(bottom, [["", "HUD_MOUSE_HINT"]])
	_mouse_hint.visible = false
	_intro = _key_hint(bottom, [["WASD", "HELP_MOVE"], [tr("KEY_SPACE"), "HELP_JUMP"], ["Shift", "HELP_SCHUPFN"], ["Tab", "HELP_INVENTORY"]])
	_wirt_marker = WorldMarker.new()
	_wirt_marker.visible = false
	root.add_child(_wirt_marker)
	for k: int in MARKERS:
		var marker := WorldMarker.new()
		marker.visible = false
		root.add_child(marker)
		_markers.append(marker)


func show_state(state: PlayerState, knodl: Knodl, run_time: float, balance: BalanceData) -> void:
	_hp_bar.max_value = state.max_hp
	_hp_target = state.hp
	_hp_label.text = "%d/%d" % [ceili(state.hp), roundi(state.max_hp)]
	_heart.warn = state.hp < state.max_hp * 0.3
	_hp_bar.theme_type_variation = &"BarBoss" if _heart.warn else &"BarHp"
	_kruegerl.fill = Formulas.level_progress(state.xp, balance)
	_level_label.text = tr("HUD_LEVEL") % state.level
	var clock: float = minf(run_time, balance.run_seconds)
	_clock.fill = clock / balance.run_seconds
	_time_label.text = "%d:%02d" % [floori(clock / 60.0), int(clock) % 60]
	if run_time >= balance.run_seconds:
		_time_label.text = tr("HUD_SPERRSTUND")
	if state.level > _last_level:
		toast(tr("TOAST_LEVEL_UP") % state.level)
	_last_level = state.level
	if knodl != null:
		_knodl_tier_index = Formulas.wirtshaus_tier(knodl.knodl_mass, balance)
		_knodl_mass.text = str(roundi(knodl.knodl_mass))
		_knodl_tier.text = tr("HUD_KNODL_TIER") % tr("TIER_%d" % _knodl_tier_index) if _knodl_tier_index >= 0 else tr("HUD_KNODL_SMALL")
		# Most runs stay below 4x the start radius; the disc fills its ring there.
		_knodl.knodl_size = inverse_lerp(balance.knodl_base_radius, balance.knodl_base_radius * 4.0, knodl.radius)
		_knodl.hollow = knodl.state != Knodl.State.ATTACHED
		_knodl.ring = knodl.cooldown / maxf(balance.knodl_cooldown, 0.01)
	if state.downed:
		toast(tr(downed_key), 0.2)


## Weapons and passives with their levels, one line each (the [SLOW] log line).
static func build_text(build: PlayerBuild) -> String:
	var weapons: PackedStringArray = []
	for owned: PlayerBuild.OwnedWeapon in build.weapons:
		weapons.append("%s %d" % [TranslationServer.translate(owned.data.name_key), owned.level])
	var passives: PackedStringArray = []
	for owned: PlayerBuild.OwnedPassive in build.passives:
		passives.append("%s %d" % [TranslationServer.translate(owned.data.name_key), owned.level])
	return " · ".join(weapons) + "\n" + " · ".join(passives)


## Points at the nearest open Wirtshaus, once the Knödl is big enough to cash in.
func show_wirt_marker(camera: Camera3D, target: Vector3, distance: float) -> void:
	if camera == null or not is_finite(distance) or _knodl_tier_index < 0:
		_wirt_marker.visible = false
		return
	_place(_wirt_marker, camera, target + Vector3(0.0, 6.5, 0.0), tr("HUD_WIRT_MARKER") % roundi(distance), "accent")


func hide_wirt_marker() -> void:
	_wirt_marker.visible = false


## The boss bar at the top (name and HP); hp_max <= 0 hides it.
func show_boss(boss_name: String, hp: float, hp_max: float) -> void:
	var on: bool = hp_max > 0.0
	if on and not _boss_box.visible:
		_boss_bar.value = hp
	_boss_box.visible = on
	if on:
		_boss_name.text = boss_name
		_boss_bar.max_value = hp_max
		_boss_target = hp


## The Formular quest line ("" hides it).
func show_formular(text: String) -> void:
	_formular_panel.visible = text != ""
	_formular.text = text


## A one-line hint at the bottom ("" hides it).
func show_hint(text: String) -> void:
	_hint_panel.visible = text != ""
	_hint_line.text = text


## Markers toward places (Stempel, the gate, a boss): call begin, then marker() per place, then end.
func begin_markers() -> void:
	_markers_used = 0


## `tone` is a palette colour name ("accent", "danger" ...).
func marker(camera: Camera3D, target: Vector3, text: String, tone: String) -> void:
	if camera == null or _markers_used >= _markers.size():
		return
	var pill: WorldMarker = _markers[_markers_used]
	_markers_used += 1
	_place(pill, camera, target, text, tone)


func end_markers() -> void:
	for k: int in range(_markers_used, _markers.size()):
		_markers[k].visible = false


## "Click into the game to look around with the mouse", while the pointer is free.
func show_mouse_hint(on: bool) -> void:
	_mouse_hint.visible = on and _intro_timer <= 0.0


func toast(text: String, seconds: float = TOAST_SECONDS) -> void:
	var fresh: bool = _toast_timer <= 0.0 or _toast.text != text
	_toast.text = text
	_toast_timer = seconds
	if fresh:
		if _toast_tween != null:
			_toast_tween.kill()
		_toast.scale = Vector2.ONE * 0.9
		_toast_tween = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_toast_tween.tween_property(_toast, "scale", Vector2.ONE, 0.15)
		_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.15)


func _process(delta: float) -> void:
	_root.visible = not covered.call()
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer < 0.4:
			_toast.modulate.a = clampf(_toast_timer / 0.4, 0.0, 1.0)
	if _intro_timer > 0.0:
		_intro_timer -= delta
		_intro.modulate.a = clampf(_intro_timer / 0.6, 0.0, 1.0)
		_intro.visible = _intro_timer > 0.0
	var ease: float = clampf(delta / UiStyle.T_BAR * 4.0, 0.0, 1.0)
	_hp_bar.value = lerpf(_hp_bar.value, _hp_target, ease)
	if _boss_box.visible:
		_boss_bar.value = lerpf(_boss_bar.value, _boss_target, ease)


func _place(pill: WorldMarker, camera: Camera3D, point: Vector3, text: String, tone: String) -> void:
	var view: Vector2 = pill.get_viewport_rect().size
	var screen: Vector2 = camera.unproject_position(point)
	if camera.is_position_behind(point):
		# Behind the camera: mirror it to the bottom edge.
		screen = Vector2(view.x - screen.x, view.y)
	pill.text = text
	pill.tone = tone
	# Kept clear of the corner widgets.
	pill.place(screen, Rect2(Vector2(EDGE, 96.0), view - Vector2(2.0 * EDGE, 192.0)))
	pill.visible = true


## A themed panel pinned to a screen corner, 16 px in.
func _corner(root: Control, preset: Control.LayoutPreset, variation: StringName) -> PanelContainer:
	var box: PanelContainer = UiStyle.panel(variation)
	root.add_child(box)
	box.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, int(EDGE))
	match preset:
		Control.PRESET_TOP_RIGHT:
			box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_BOTTOM_RIGHT:
			box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			box.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_BOTTOM_LEFT:
			box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	return box


## A row of keycaps with their words ("[WASD] gehn  [Leertaste] hupfn ...") in a HUD panel.
func _key_hint(parent: Control, pairs: Array) -> PanelContainer:
	var box: PanelContainer = UiStyle.panel(&"HudPanel")
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(box)
	var row := UiStyle.hbox(&"Row16")
	box.add_child(row)
	for pair: Array in pairs:
		var item := UiStyle.hbox()
		row.add_child(item)
		if pair[0] != "":
			var cap: Label = UiStyle.label(&"Keycap", pair[0])
			cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			item.add_child(cap)
		item.add_child(UiStyle.label(&"HudSmall", tr(pair[1])))
	return box
