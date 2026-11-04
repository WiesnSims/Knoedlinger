class_name ChaseCamera
extends Camera3D
## Third-person camera in the style of Megabonk (docs/DECISIONS.md): the mouse always looks around
## (one click into the game captures the pointer, Esc lets go), the player runs relative to where
## the camera looks, the view sits close and low behind the player with a wide field of view, and
## the mouse wheel zooms. Q/E turn it for keyboard-only play, the right stick on the gamepad. It
## follows the player tightly, never sinks into the terrain between it and the player (props it
## looks through), and backs off as the Knödl grows. All numbers come from balance.tres.

var balance: BalanceData
var target: Node3D
## Radians; 0 = the camera sits on +Z of the player, looking toward -Z.
var yaw: float = 0.0
## Radians above the horizon the camera sits (positive = looking down at the player).
var pitch: float = 0.0
## The player's chosen distance (mouse wheel), before the Knödl's extra.
var zoom: float = 0.0
## Extra metres of distance (a big Knödl).
var extra_distance: float = 0.0
## Allow capturing the mouse on click (never in automated runs).
var mouse_capture_allowed: bool = true
## Swing behind the running direction on its own (balance.camera_auto_turn_speed; off by default).
var auto_turn: bool = true
## Metres; > 0 replaces the zoom (the M0 stress view).
var distance_override: float = 0.0
## Materials with the see-through uniforms (map props, enemies): told where the player is.
var see_through: Array[ShaderMaterial] = []
## The see-through circle around the player, in metres.
var see_through_radius: float = 1.9

var _sensitivity: float = 0.0
var _pad_speed: float = 1.0
var _touch_speed: float = 1.0
var _invert: float = 1.0
var _smoothing: float = 0.0
var _yaw_target: float = 0.0
var _pitch_target: float = 0.0
var _focus: Vector3 = Vector3.ZERO
var _distance: float = 0.0
var _last_target: Vector3 = Vector3.ZERO


func setup(p_balance: BalanceData, p_target: Node3D) -> void:
	balance = p_balance
	target = p_target
	# Moved every rendered frame from interpolated positions; not a physics object itself.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fov = balance.camera_fov
	zoom = balance.camera_distance
	_apply_settings(&"")
	if Settings.persistent:
		zoom = clampf(Settings.get_float(&"camera_distance"), balance.camera_min_distance, balance.camera_max_distance)
	if not Settings.changed.is_connected(_apply_settings):
		Settings.changed.connect(_apply_settings)
	set_view(yaw, deg_to_rad(balance.camera_pitch_degrees))


## The player's camera settings (Einstellungen); automated runs keep the balance numbers.
func _apply_settings(key: StringName) -> void:
	_sensitivity = balance.camera_mouse_sensitivity
	_invert = 1.0
	_smoothing = balance.camera_look_smoothing
	_pad_speed = 1.0
	if not Settings.persistent:
		return
	fov = Settings.get_float(&"camera_fov")
	_sensitivity *= Settings.get_float(&"mouse_sensitivity")
	_invert = -1.0 if Settings.get_bool(&"invert_y") else 1.0
	_smoothing = Settings.get_float(&"look_smoothing")
	_pad_speed = Settings.get_float(&"pad_look_speed")
	_touch_speed = Settings.get_float(&"mouse_sensitivity")
	if key == &"camera_distance":
		zoom = clampf(Settings.get_float(&"camera_distance"), balance.camera_min_distance, balance.camera_max_distance)


## A finger dragging on the touch screen (TouchControls), in UI pixels.
func touch_look(relative: Vector2) -> void:
	_yaw_target -= relative.x * balance.camera_touch_sensitivity * _touch_speed
	_pitch_target = clampf(_pitch_target + relative.y * balance.camera_touch_sensitivity * _touch_speed * _invert,
			deg_to_rad(balance.camera_min_pitch_degrees), deg_to_rad(balance.camera_max_pitch_degrees))


## Points the camera without smoothing (start of a run, the stress view).
func set_view(new_yaw: float, new_pitch: float) -> void:
	yaw = new_yaw
	pitch = new_pitch
	_yaw_target = new_yaw
	_pitch_target = new_pitch
	snap_to_target()


func snap_to_target() -> void:
	if target == null:
		return
	_focus = _focus_point()
	_last_target = _target_position()
	_distance = _base_distance() + extra_distance
	_place(_distance)


## Unit vector "forward" on the ground plane, away from the camera.
func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _unhandled_input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw_target -= motion.relative.x * _sensitivity
		_pitch_target = clampf(_pitch_target + motion.relative.y * _sensitivity * _invert,
				deg_to_rad(balance.camera_min_pitch_degrees), deg_to_rad(balance.camera_max_pitch_degrees))
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed:
		match click.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom = maxf(zoom - balance.camera_zoom_step, balance.camera_min_distance)
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom = minf(zoom + balance.camera_zoom_step, balance.camera_max_distance)
			MOUSE_BUTTON_LEFT:
				# A tap on a touch screen also arrives as a click: never capture the pointer for it.
				if mouse_capture_allowed and click.device != InputEvent.DEVICE_ID_EMULATION:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if target == null or balance == null:
		return
	var turn: float = Input.get_axis(&"camera_right", &"camera_left")
	_yaw_target += turn * balance.camera_key_turn_speed * delta
	# The right stick, on a squared curve so small tilts aim finely.
	var stick: Vector2 = Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	stick *= stick.length()
	if stick != Vector2.ZERO:
		turn -= stick.x
		_yaw_target -= stick.x * balance.camera_pad_yaw_speed * _pad_speed * delta
		_pitch_target = clampf(_pitch_target + stick.y * balance.camera_pad_pitch_speed * _pad_speed * _invert * delta,
				deg_to_rad(balance.camera_min_pitch_degrees), deg_to_rad(balance.camera_max_pitch_degrees))
	var moved: Vector3 = _target_position() - _last_target
	_last_target = _target_position()
	moved.y = 0.0
	# Optional swing behind the running direction: full speed when running sideways, never when
	# running at the camera (it would spin round). Off while the mouse looks.
	if auto_turn and balance.camera_auto_turn_speed > 0.0 and turn == 0.0 \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and delta > 0.0 and moved.length() / delta > 1.0:
		var wanted: float = atan2(-moved.x, -moved.z)
		var difference: float = wrapf(wanted - _yaw_target, -PI, PI)
		if absf(difference) < deg_to_rad(110.0):
			_yaw_target += sin(difference) * balance.camera_auto_turn_speed * delta
	_yaw_target = wrapf(_yaw_target, -PI, PI)
	# A touch of look smoothing, so mouse steps do not jerk the view.
	var look: float = 1.0 if _smoothing <= 0.0 else 1.0 - exp(-delta / _smoothing)
	yaw = lerp_angle(yaw, _yaw_target, look)
	pitch = lerpf(pitch, _pitch_target, look)
	_focus = _focus.lerp(_focus_point(), 1.0 - exp(-balance.camera_follow_speed * delta))
	var wanted_distance: float = _base_distance() + extra_distance
	_distance = lerpf(_distance, wanted_distance, 1.0 - exp(-6.0 * delta))
	_place(_distance)


func _base_distance() -> float:
	return distance_override if distance_override > 0.0 else zoom


func _target_position() -> Vector3:
	return target.get_global_transform_interpolated().origin


func _focus_point() -> Vector3:
	return _target_position() + Vector3(0.0, balance.camera_focus_height, 0.0)


func _place(distance: float) -> void:
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	var wanted: Vector3 = _focus + offset
	if is_inside_tree():
		var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(_focus, wanted, MapBuilder.LAYER_TERRAIN)
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty():
			var at: Vector3 = hit["position"]
			wanted = at + (_focus - at).normalized() * balance.camera_collision_margin
	global_position = wanted
	look_at(_focus)
	_update_see_through()


## Tells the props' shader where the player is on screen, so walls in front of them turn see-through.
func _update_see_through() -> void:
	if see_through.is_empty() or not is_inside_tree():
		return
	var view: Vector2 = get_viewport().get_visible_rect().size
	var body: Vector3 = _target_position() + Vector3(0.0, 1.0, 0.0)
	var depth: float = global_position.distance_to(body)
	if view.y <= 0.0 or depth < 0.1 or is_position_behind(body):
		for material: ShaderMaterial in see_through:
			material.set_shader_parameter(&"cut_radius", 0.0)
		return
	var uv: Vector2 = unproject_position(body) / view
	var radius: float = see_through_radius / (depth * tan(deg_to_rad(fov) * 0.5)) * 0.5
	for material: ShaderMaterial in see_through:
		material.set_shader_parameter(&"focus_uv", uv)
		material.set_shader_parameter(&"focus_depth", depth)
		material.set_shader_parameter(&"aspect", view.x / view.y)
		material.set_shader_parameter(&"cut_radius", radius)
