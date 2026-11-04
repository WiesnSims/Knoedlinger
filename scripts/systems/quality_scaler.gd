class_name QualityScaler
extends Node
## Render quality (GAME-DESIGN.md, performance item 6): Hoch, Mittel, Niedrig set the render
## resolution (in the browser the canvas's pixel ratio, natively the 3D scale), the sun's shadows
## and MSAA, and (Niedrig, solo only) a smaller enemy crowd; the numbers live in balance.tres.
## "Automatisch" starts on Hoch and steps down one level when the frame rate stays below the target
## for `quality_drop_seconds`, and back up after a long stretch well above it.
## Automated runs stay on Hoch (or `quality=<level>`), so a measurement never changes underneath.

signal level_changed(level: int)

enum Level { HIGH, MEDIUM, LOW }

const NAMES: PackedStringArray = ["high", "medium", "low"]

var balance: BalanceData
## The sun whose shadows the levels switch (may be null).
var sun: DirectionalLight3D
var level: int = Level.HIGH
var auto: bool = true
## Frames per second the automatic mode keeps (lower on phones: their budget is 30).
var target_fps: float = 50.0
## The browser pixel ratio the canvas renders at (web only).
var pixel_ratio: float = 1.0
## True while frames are slow for another reason (the shader warm-up behind the loading screen).
var hold: bool = false

var _second_time: float = 0.0
var _second_frames: int = 0
var _low_seconds: int = 0
var _high_seconds: int = 0
## Seconds since the last step down; stepping up waits a while after one.
var _since_drop: float = 0.0
var _warmup: float = 0.0


func setup(p_balance: BalanceData, p_sun: DirectionalLight3D) -> void:
	balance = p_balance
	sun = p_sun
	process_mode = Node.PROCESS_MODE_PAUSABLE
	target_fps = balance.quality_target_fps_mobile if is_mobile() else balance.quality_target_fps
	_warmup = balance.quality_warmup_seconds
	_since_drop = balance.quality_raise_cooldown
	var choice: String = str(Settings.get_value(&"quality")) if Settings.persistent else "high"
	choice = LaunchArgs.get_string("quality", choice)
	auto = choice == "auto"
	level = maxi(NAMES.find(choice), 0)
	if not Settings.changed.is_connected(_on_setting):
		Settings.changed.connect(_on_setting)
	apply()


static func is_mobile() -> bool:
	return OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile")


## How many enemies the host keeps compared with Hoch (only Niedrig in a solo game thins the crowd:
## in co-op the host's quality would change everyone's game).
func enemy_factor(solo: bool) -> float:
	return balance.quality_low_enemy_factor if solo and level == Level.LOW else 1.0


func apply() -> void:
	var scale: float = balance.quality_render_scale[clampi(level, 0, balance.quality_render_scale.size() - 1)]
	if OS.has_feature("web"):
		# The canvas itself gets fewer pixels (web/pixel_scale.js); a phone's 2.6x screen is capped too.
		var real: float = float(JavaScriptBridge.eval("window.knoedlRealPixelRatio ? window.knoedlRealPixelRatio() : 1", true))
		var cap: float = balance.quality_max_pixel_ratio[clampi(level, 0, balance.quality_max_pixel_ratio.size() - 1)]
		pixel_ratio = maxf(minf(real * scale, cap), 0.5)
		JavaScriptBridge.eval("window.knoedlSetPixelRatio && window.knoedlSetPixelRatio(%f)" % pixel_ratio, true)
	elif is_inside_tree():
		var viewport: Viewport = get_viewport()
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_scale = scale
	# Kantenglättung (MSAA) as the setting says, but never on Niedrig: it costs most on phones.
	if is_inside_tree():
		var msaa: bool = Settings.get_bool(&"antialiasing") and level < Level.LOW
		get_tree().root.msaa_3d = Settings.MSAA_ON if msaa else Viewport.MSAA_DISABLED
	if sun != null:
		sun.shadow_enabled = level < Level.LOW
		sun.directional_shadow_max_distance = balance.quality_shadow_distance[clampi(level, 0, 1)]


func set_level(value: int) -> void:
	value = clampi(value, Level.HIGH, Level.LOW)
	if value == level:
		return
	level = value
	apply()
	print("[QUALITY] %s (%s)" % [NAMES[level], "auto" if auto else "fixed"])
	level_changed.emit(level)


func _enter_tree() -> void:
	if balance != null:
		apply()


func _process(delta: float) -> void:
	if not auto or balance == null or hold:
		return
	if _warmup > 0.0:
		_warmup -= delta
		return
	_since_drop += delta
	_second_time += delta
	_second_frames += 1
	if _second_time < 1.0:
		return
	var fps: float = _second_frames / _second_time
	_second_time = 0.0
	_second_frames = 0
	_low_seconds = _low_seconds + 1 if fps < target_fps else 0
	_high_seconds = _high_seconds + 1 if fps > target_fps * balance.quality_raise_margin else 0
	if _low_seconds >= balance.quality_drop_seconds and level < Level.LOW:
		_low_seconds = 0
		_since_drop = 0.0
		set_level(level + 1)
	elif _high_seconds >= balance.quality_raise_seconds and level > Level.HIGH \
			and _since_drop >= balance.quality_raise_cooldown:
		_high_seconds = 0
		set_level(level - 1)


func _on_setting(key: StringName) -> void:
	if key == &"antialiasing":
		apply()
		return
	if key != &"quality" or not Settings.persistent:
		return
	var choice: String = str(Settings.get_value(&"quality"))
	auto = choice == "auto"
	_low_seconds = 0
	_high_seconds = 0
	if not auto:
		set_level(maxi(NAMES.find(choice), 0))
