class_name ChaseCamera
extends Camera3D
## Third-person chase cam (GAME-DESIGN.md: follows the movement direction with slight lag; free
## mouse orbit optional). Pitch, distance and turn speeds come from balance.tres. The camera swings
## behind the running direction on its own (not when running toward it), Q/E turn it, and with the
## mouse captured (click into the game, Esc to let go) the mouse orbits it. It never sinks into
## the terrain between it and the player (props it simply looks through), and backs off as the
## Knödl grows.

var balance: BalanceData
var target: Node3D
## Radians; 0 = the camera sits on +Z of the player, looking toward -Z.
var yaw: float = 0.0
var pitch: float = 0.0
## Extra metres of distance (a big Knödl).
var extra_distance: float = 0.0
## Allow capturing the mouse on click (never in automated runs).
var mouse_capture_allowed: bool = true
## Swing behind the running direction on its own.
var auto_turn: bool = true
## Metres; > 0 replaces balance.camera_distance (the M0 stress view).
var distance_override: float = 0.0

var _focus: Vector3 = Vector3.ZERO
var _distance: float = 0.0
var _last_target: Vector3 = Vector3.ZERO


func setup(p_balance: BalanceData, p_target: Node3D) -> void:
	balance = p_balance
	target = p_target
	# Moved every rendered frame from interpolated positions; not a physics object itself.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	pitch = deg_to_rad(balance.camera_pitch_degrees)
	_distance = _base_distance()
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
		yaw -= motion.relative.x * balance.camera_mouse_sensitivity
		pitch = clampf(pitch + motion.relative.y * balance.camera_mouse_sensitivity,
				deg_to_rad(balance.camera_min_pitch_degrees), deg_to_rad(balance.camera_max_pitch_degrees))
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and mouse_capture_allowed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"pause") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if target == null or balance == null:
		return
	var turn: float = Input.get_axis(&"camera_right", &"camera_left")
	yaw += turn * balance.camera_key_turn_speed * delta
	# Swing behind the running direction: full speed when running sideways, not at all when running
	# straight at the camera (it would spin round).
	var moved: Vector3 = _target_position() - _last_target
	_last_target = _target_position()
	moved.y = 0.0
	if auto_turn and turn == 0.0 and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and delta > 0.0 and moved.length() / delta > 1.0:
		var wanted: float = atan2(-moved.x, -moved.z)
		var difference: float = wrapf(wanted - yaw, -PI, PI)
		if absf(difference) < deg_to_rad(110.0):
			yaw += sin(difference) * balance.camera_auto_turn_speed * delta
	yaw = wrapf(yaw, -PI, PI)
	_focus = _focus.lerp(_focus_point(), 1.0 - exp(-balance.camera_follow_speed * delta))
	var wanted_distance: float = _base_distance() + extra_distance
	_distance = lerpf(_distance, wanted_distance, 1.0 - exp(-2.0 * delta))
	_place(_distance)


func _base_distance() -> float:
	return distance_override if distance_override > 0.0 else balance.camera_distance


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
