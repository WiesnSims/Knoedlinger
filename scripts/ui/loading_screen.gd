class_name LoadingScreen
extends CanvasLayer
## Covers the screen while a run is being prepared: "Der Knödl wird no geformt …", a progress bar
## and a rotating dialect line. The main menu shows it before it switches scenes (the map bake
## would freeze the menu otherwise), RunWorld while ShaderWarmup has the browser build its shaders
## (each one blocks the page for up to ~0.7 s on a first visit; GAME-DESIGN.md, Tech: loading screen).

## The jokes are the ones the page's loading screen rotates (LOADING_JOKE_01 is the title).
const JOKES: int = 16
const TIP_SECONDS: float = 2.5
const BAR_WIDTH: float = 480.0

var _bar: ProgressBar
var _tip: Label
var _shown: Control
var _tip_index: int = 0
var _tip_timer: float = TIP_SECONDS
var _target: float = 0.0


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root: Control = UiStyle.root(self)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_shown = Control.new()
	_shown.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_shown)
	# Opaque: whatever ShaderWarmup draws behind it is never seen.
	var back := ColorRect.new()
	back.color = Color(UiStyle.color("panel"), 1.0)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shown.add_child(back)
	var column := UiStyle.vbox(&"Gap16")
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	UiStyle.centred(_shown).add_child(column)
	var title: Label = UiStyle.label(&"LabelTitle", tr("LOADING_JOKE_01"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_bar = UiStyle.bar(&"BarXp")
	_bar.custom_minimum_size = Vector2(BAR_WIDTH, 16.0)
	_bar.max_value = 1.0
	_bar.step = 0.0
	column.add_child(_bar)
	_tip_index = randi() % (JOKES - 1)
	_tip = UiStyle.label(&"LabelMuted", _joke(_tip_index))
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_tip)


## 0..1; the bar eases toward it.
func set_progress(value: float) -> void:
	_target = clampf(value, 0.0, 1.0)


## Fades out, then frees itself.
func finish() -> void:
	_target = 1.0
	_bar.value = 1.0
	var tween: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_shown, "modulate:a", 0.0, UiStyle.T_PANEL_OUT)
	tween.tween_callback(queue_free)


func _process(delta: float) -> void:
	# Frames can be long here (a shader build each), so the step is capped rather than timed.
	_bar.value = move_toward(_bar.value, _target, maxf(delta, 1.0 / 60.0) * 2.0)
	_tip_timer -= delta
	if _tip_timer <= 0.0:
		_tip_timer = TIP_SECONDS
		_tip_index = (_tip_index + 1) % (JOKES - 1)
		_tip.text = _joke(_tip_index)


## Jokes 02..16 rotate under the title.
func _joke(index: int) -> String:
	return tr("LOADING_JOKE_%02d" % (index + 2))
