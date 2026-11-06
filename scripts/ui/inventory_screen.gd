class_name InventoryScreen
extends CanvasLayer
## Tab (or I) opens the build view (BuildView: tiles, what the picked one does, the stats); Tab, I or
## Esc closes it. RunWorld pauses solo games while it is open (`toggled`), like the Speisekarte.

signal toggled(open: bool)

var _shown: Control
var _view: BuildView
var _tween: Tween
## RunWorld turns it off while the Speisekarte or the end screen is up.
var allowed: bool = true


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root: Control = UiStyle.root(self)
	_shown = Control.new()
	_shown.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_shown)
	var shade := ColorRect.new()
	shade.color = Color(UiStyle.color("panel"), 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shown.add_child(shade)
	var column := UiStyle.vbox(&"Gap16")
	UiStyle.centred(_shown).add_child(column)
	_view = BuildView.new()
	column.add_child(_view)
	var hint := UiStyle.hbox()
	hint.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(hint)
	var cap := KeycapLabel.new(&"inventory", "Tab")
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.add_child(cap)
	hint.add_child(UiStyle.label(&"HudSmall", tr("INV_CLOSE")))
	_shown.visible = false


func is_open() -> bool:
	return _shown.visible


func show_player(state: PlayerState, knodl: Knodl, balance: BalanceData, ledger: DamageLedger, peer: int,
		run_time: float) -> void:
	_view.show_player(state, knodl, balance, ledger, peer, run_time)


func set_open(on: bool) -> void:
	if on == is_open() or (on and not allowed):
		return
	if _tween != null:
		_tween.kill()
	# Closing is instant, so the game resumes at once; opening fades in.
	_shown.visible = on
	if on:
		_shown.modulate.a = 0.0
		_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_shown, "modulate:a", 1.0, UiStyle.T_PANEL_IN)
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_view.focus_first.call_deferred()
	toggled.emit(on)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"inventory"):
		set_open(not is_open())
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		if not is_open():
			return
		set_open(false)
	else:
		return
	get_viewport().set_input_as_handled()
