class_name Player
extends CharacterBody3D
## A Knödlinger. The local player moves themselves (Jolt, CharacterBody3D) from the keyboard or a
## BotInput and reports where they went as an InputMessage; remote players only follow the messages
## they receive. Movement is relative to the camera; jumping uses coyote time and a jump buffer.
## Movement in the style of Megabonk: jumps and downhill runs build momentum the air keeps, held
## jumps go higher, and glide items let a held jump float down (docs/DECISIONS.md, movement).
## HP, damage and respawns are host state (PlayerState); the player only shows and obeys them.

## Seconds the bot waits after the last key press before it takes over again.
const MANUAL_HOLD: float = 3.0
const REMOTE_FOLLOW_SPEED: float = 12.0
const TURN_SPEED: float = 14.0
const LAYER_PLAYER: int = 2
const BODY_HEIGHT: float = 1.8

var peer_id: int = 1
var is_local: bool = false
var balance: BalanceData
var character: CharacterData
var bot: BotInput
var last_input: InputMessage = InputMessage.new()
## The ground the enemies walk on, for "how high is the floor here" questions; null = flat.
var ground: Heightfield
## Where the player starts and comes back after being knocked down.
var spawn_point: Vector3 = Vector3.ZERO
## Players stay inside +-bounds on x and z.
var bounds: float = 100.0
## Steep slopes are jumped off only this far from the centre on x and z: the mountains round the map
## (MapData.rim_start) stay a wall.
var slope_jump_reach: float = INF
## Yaw of the camera, so "up" on the stick runs away from it (local player only).
var camera_yaw: float = 0.0
## A big Knödl slows its player down (Formulas.knodl_speed_factor).
var speed_factor: float = 1.0
## Knocked down: cannot move (host state, see PlayerState).
var downed: bool = false
## Choosing from the Speisekarte in co-op: stands still under a sign (host state).
var choosing: bool = false
## From the build (PlayerBuild stats): move speed factor, jump height bonus, extra jumps.
var stat_speed: float = 1.0
var stat_jump_height: float = 0.0
var stat_extra_jumps: int = 0
## Glide (items): holding jump on the way down falls slowly (balance.player_glide_strength).
var stat_glide: float = 0.0
## Velocity on host and clients alike; remote players estimate it from their poses.
var motion_velocity: Vector3 = Vector3.ZERO
var jumps_used: int = 0
## Every jump so far (wraps at 256; the host counts Kevin's shockwaves from it).
var jump_count: int = 0

var _tick: int = 0
var _manual_timer: float = 0.0
var _remote_target: Vector3 = Vector3.ZERO
var _remote_yaw: float = 0.0
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
## Still rising from a jump whose height letting go of jump can cut short.
var _rising: bool = false
## This tick's stick, world space (x = world X, y = world Z).
var _move: Vector2 = Vector2.ZERO
var _schupfn_presses: int = 0
## The last Schupfn's mouse aim (yaw) and whether it had one (keyboard and mouse only).
var _schupfn_aim: float = 0.0
var _schupfn_aimed: bool = false
var _last_position: Vector3 = Vector3.ZERO
var _look: Node3D
var _sign: Label3D
## Co-op: a line over the player while knocked down ("Umgfoin! 23"); empty = none.
var note: String = ""


func setup(p_peer_id: int, local: bool, p_balance: BalanceData, p_character: CharacterData, p_bot: BotInput) -> void:
	peer_id = p_peer_id
	is_local = local
	balance = p_balance
	character = p_character
	bot = p_bot
	name = "Player_%d" % peer_id
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = balance.player_radius
	capsule.height = BODY_HEIGHT
	shape.shape = capsule
	shape.position.y = BODY_HEIGHT * 0.5
	add_child(shape)
	_look = _build_look(local)
	add_child(_look)
	_sign = Label3D.new()
	# Co-op signs ("Bin glei wieder da", "Umgfoin!") only draw near the camera (draw calls, M6).
	_sign.visibility_range_end = 70.0
	_sign.font = UiStyle.font("number")
	_sign.name = "BinGleiWiederDa"
	_sign.text = tr("SIGN_BACK_SOON")
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.position = Vector3(0.0, 2.9, 0.0)
	_sign.font_size = 56
	_sign.pixel_size = 0.01
	_sign.outline_size = 12
	_sign.outline_modulate = Color(0.2, 0.12, 0.06)
	_sign.visible = false
	add_child(_sign)
	collision_layer = LAYER_PLAYER if local else 0
	collision_mask = MapBuilder.LAYER_WORLD
	floor_max_angle = deg_to_rad(balance.player_max_slope_degrees)
	floor_snap_length = 0.45
	floor_constant_speed = true
	_remote_target = position


func hand_position() -> Vector3:
	return global_position + Vector3(0.0, balance.knodl_hand_height, 0.0)


## Where the string starts as drawn (between physics ticks, see physics interpolation).
func hand_position_visual() -> Vector3:
	return get_global_transform_interpolated().origin + Vector3(0.0, balance.knodl_hand_height, 0.0)


## Unit vector the player faces, on the ground plane.
func facing_direction() -> Vector3:
	return Vector3(sin(rotation.y), 0.0, cos(rotation.y))


func ground_height_at(where: Vector3) -> float:
	return ground.height_at(where.x, where.z) if ground != null else 0.0


func max_jumps() -> int:
	return balance.player_jumps + (character.extra_jumps if character != null else 0) + stat_extra_jumps


## Run speed on flat ground with the build and the Knödl's drag (also the host's pose check).
func run_speed() -> float:
	return balance.player_speed * speed_factor * stat_speed


## The fastest this player can be: momentum from jumps and slopes, or Cousin Toni's slope bonus
## (the host's pose check).
func max_speed() -> float:
	return maxf(momentum_cap(), run_speed() * (1.0 + (character.slope_speed if character != null else 0.0)))


## Momentum never carries a player faster than this.
func momentum_cap() -> float:
	return run_speed() * balance.player_momentum_max


## Puts the player back at a point (start of a run, respawn).
func teleport(where: Vector3) -> void:
	global_position = where
	_remote_target = where
	_last_position = where
	velocity = Vector3.ZERO
	motion_velocity = Vector3.ZERO
	_rising = false
	last_input.position = where
	reset_physics_interpolation()


func _process(_delta: float) -> void:
	# Knocked down: lie on the ground (only the look turns, the body stays upright for Jolt).
	var lying: float = PI * 0.5 if downed else 0.0
	_look.rotation.x = lerpf(_look.rotation.x, lying, 0.2)
	# Solo pauses for the Speisekarte; the sign is for teammates (co-op runs on).
	if note != "":
		_sign.text = note
		_sign.visible = true
	else:
		_sign.text = tr("SIGN_BACK_SOON")
		_sign.visible = choosing and NetworkManager.is_online()


func _physics_process(delta: float) -> void:
	if not is_local:
		var blend: float = 1.0 - exp(-REMOTE_FOLLOW_SPEED * delta)
		global_position = global_position.lerp(_remote_target, blend)
		rotation.y = lerp_angle(rotation.y, _remote_yaw, blend)
		_update_motion(delta)
		return
	var stuck: bool = downed or choosing
	var move: Vector2 = Vector2.ZERO if stuck else _sample_move(delta)
	_move = move
	var on_floor: bool = is_on_floor()
	if on_floor or _on_steep_slope():
		# Too steep to stand on is still firm enough to jump off: a hillside is climbed in hops.
		_coyote = balance.player_coyote_time
		jumps_used = 0
		_rising = false
	else:
		_coyote = maxf(_coyote - delta, 0.0)
	var speed: float = run_speed()
	# Cousin Toni: faster on any slope steeper than about 8 degrees.
	if on_floor and character != null and character.slope_speed > 0.0 and get_floor_normal().y < 0.99:
		speed *= 1.0 + character.slope_speed
	var horizontal: Vector2 = _steer(Vector2(velocity.x, velocity.z), move, speed, on_floor, delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	var held: bool = _jump_held()
	var jump_pressed: bool = Input.is_action_just_pressed(&"jump") or (bot != null and _manual_timer <= 0.0 and bot.take_jump())
	if jump_pressed and not stuck:
		_jump_buffer = balance.player_jump_buffer
	else:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if _jump_buffer > 0.0:
		# A ground jump (also just after leaving a ledge), or an air jump while some are left.
		if _coyote > 0.0 and jumps_used == 0:
			_jump()
		elif jumps_used > 0 and jumps_used < max_jumps():
			_jump()
		elif not on_floor and _coyote <= 0.0 and jumps_used == 0 and max_jumps() > 1:
			# Walked off a ledge without jumping: the air jump is the second one.
			jumps_used = 1
			_jump()
	# Let go while rising: a short hop instead of the full arc (once per jump).
	if _rising and not held and velocity.y > 0.0:
		velocity.y *= balance.player_jump_cut
		_rising = false
	if not on_floor:
		_fall(held, delta)
	move_and_slide()
	var half: float = bounds - 1.0
	global_position.x = clampf(global_position.x, -half, half)
	global_position.z = clampf(global_position.z, -half, half)
	if global_position.y < ground_height_at(global_position) - 20.0:
		teleport(spawn_point)
	if move.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(move.x, move.y), 1.0 - exp(-TURN_SPEED * delta))
	var pressed: bool = Input.is_action_just_pressed(&"schupfn")
	var schupfn: bool = pressed or (bot != null and _manual_timer <= 0.0 and bot.take_schupfn())
	if schupfn and not stuck:
		_schupfn_presses = (_schupfn_presses + 1) & 0xFF
		var aim: float = _mouse_aim() if pressed else NAN
		_schupfn_aimed = not is_nan(aim)
		if _schupfn_aimed:
			_schupfn_aim = aim
	_update_motion(delta)
	_tick += 1
	last_input.tick = _tick
	last_input.move = move
	last_input.buttons = InputMessage.BUTTON_JUMP if Input.is_action_pressed(&"jump") else 0
	if _schupfn_aimed:
		last_input.buttons |= InputMessage.BUTTON_AIM
	last_input.aim_yaw = _schupfn_aim
	last_input.schupfn_presses = _schupfn_presses
	last_input.jumps = jump_count
	last_input.position = global_position
	last_input.yaw = rotation.y


## Keyboard and mouse: the yaw toward the ground under the cursor, or where the camera looks while it
## holds the pointer (mouse look); NAN on a pad or touch, which throw the way the player moves.
func _mouse_aim() -> float:
	if InputDevice.kind != InputDevice.Kind.KEYS:
		return NAN
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return NAN
	var toward: Vector3 = -camera.global_basis.z
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		var mouse: Vector2 = get_viewport().get_mouse_position()
		var origin: Vector3 = camera.project_ray_origin(mouse)
		var ray: Vector3 = camera.project_ray_normal(mouse)
		var hit: Variant = Plane(Vector3.UP, global_position.y).intersects_ray(origin, ray)
		# Above the horizon the ray never meets the ground: its heading still says where.
		toward = (hit as Vector3) - global_position if hit != null else ray
	toward.y = 0.0
	if toward.length_squared() < 0.01:
		return NAN
	return atan2(toward.x, toward.z)


## Applies a validated message from the network to a remote player.
func apply_remote(message: InputMessage) -> void:
	last_input = message
	_remote_target = message.position
	_remote_yaw = message.yaw


func _jump() -> void:
	GameAudio.play(&"jump", global_position)
	# Jump height grows with the bonus: v = v0 * sqrt(1 + bonus).
	velocity.y = balance.player_jump_velocity * sqrt(1.0 + maxf(stat_jump_height, 0.0))
	# Momentum: every jump while moving pushes forward a little more, up to the cap.
	var horizontal := Vector2(velocity.x, velocity.z)
	if _move.length_squared() > 0.01:
		var forward: Vector2 = horizontal.normalized() if horizontal.length_squared() > 1.0 else _move.normalized()
		horizontal = (horizontal + forward * balance.player_jump_forward_boost).limit_length(momentum_cap())
		velocity.x = horizontal.x
		velocity.z = horizontal.y
	jumps_used += 1
	jump_count = (jump_count + 1) & 0xFF
	_jump_buffer = 0.0
	_coyote = 0.0
	_rising = true


## Horizontal velocity for this tick. Up to the run speed it is the old run: accelerate toward the
## stick. Above it (jumps, slopes) the stick only steers and the speed fades on flat ground, never
## in the air; pulling back brakes. Running downhill gains speed (docs/DECISIONS.md, movement).
func _steer(horizontal: Vector2, move: Vector2, speed: float, on_floor: bool, delta: float) -> Vector2:
	var accel: float = balance.player_acceleration * (1.0 if on_floor else balance.player_air_control)
	var current: float = horizontal.length()
	var moving: bool = move.length_squared() > 0.01
	var downhill: float = 0.0
	if on_floor and moving:
		# The floor normal leans downhill; its flat part along the stick is how steep "down" runs.
		var normal: Vector3 = get_floor_normal()
		downhill = Vector2(normal.x, normal.z).dot(move.normalized())
	# Steer while the stick points less than 120 degrees away from the flight; further back brakes.
	if moving and current > speed and (horizontal / current).dot(move.normalized()) > -0.5:
		var direction: Vector2 = horizontal.move_toward(move.normalized() * current, accel * delta).normalized()
		if on_floor and downhill <= 0.05:
			current = maxf(current - balance.player_momentum_decay * delta, speed)
		horizontal = direction * current
	elif moving or on_floor:
		horizontal = horizontal.move_toward(move * speed, accel * delta)
	if downhill > 0.05:
		horizontal += move.normalized() * balance.player_gravity * downhill * balance.player_slope_gain * delta
	return horizontal.limit_length(momentum_cap())


## Gravity for this tick: harder falling, a hang at the top while jump is held, gliding (items)
## when jump is held on the way down, and never above the height ceiling.
func _fall(held: bool, delta: float) -> void:
	var gravity: float = balance.player_gravity
	var max_fall: float = balance.player_max_fall_speed
	if held and absf(velocity.y) < balance.player_apex_speed:
		gravity *= balance.player_apex_gravity_mult
	elif velocity.y < 0.0:
		gravity *= balance.player_fall_gravity_mult
	if held and velocity.y < 0.0 and stat_glide > 0.0:
		var glide: float = 1.0 + stat_glide * balance.player_glide_strength
		gravity /= glide
		max_fall = minf(max_fall, balance.player_glide_fall_speed / glide)
	velocity.y = maxf(velocity.y - gravity * delta, -max_fall)
	if velocity.y > 0.0 and global_position.y - ground_height_at(global_position) > balance.player_height_ceiling:
		velocity.y = 0.0


## Sliding down ground steeper than a walk (balance.player_max_slope_degrees) but not a wall
## (balance.player_slope_jump_degrees): counts as ground for a jump, not for running.
func _on_steep_slope() -> bool:
	if not is_on_wall() or velocity.y > 0.5:
		return false
	if maxf(absf(global_position.x), absf(global_position.z)) > slope_jump_reach:
		return false
	return get_wall_normal().y > cos(deg_to_rad(balance.player_slope_jump_degrees))


## Jump held down (keys, pad, touch); the bot always holds its jumps to the top.
func _jump_held() -> bool:
	return Input.is_action_pressed(&"jump") or (bot != null and _manual_timer <= 0.0)


func _update_motion(delta: float) -> void:
	var measured: Vector3 = (global_position - _last_position) / maxf(delta, 0.0001)
	_last_position = global_position
	if is_local:
		motion_velocity = velocity
	else:
		motion_velocity = motion_velocity.lerp(measured, 0.3)


## World-space movement (x = world X, y = world Z) from the keys, relative to the camera, or the bot.
func _sample_move(delta: float) -> Vector2:
	var keys: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if keys.length_squared() > 0.0 or Input.is_action_pressed(&"jump") or Input.is_action_pressed(&"schupfn"):
		_manual_timer = MANUAL_HOLD
	if keys.length_squared() > 0.0:
		var right := Vector2(cos(camera_yaw), -sin(camera_yaw))
		var forward := Vector2(-sin(camera_yaw), -cos(camera_yaw))
		var world: Vector2 = right * keys.x - forward * keys.y
		return world.limit_length(1.0)
	if _manual_timer > 0.0:
		_manual_timer -= delta
		return Vector2.ZERO
	if bot != null:
		return bot.sample(delta, global_position)
	return Vector2.ZERO


func _build_look(local: bool) -> Node3D:
	var look := Node3D.new()
	look.name = "Look"
	var coat: Color = character.coat_color if character != null else Color(0.16, 0.42, 0.25)
	if not local:
		coat = coat.lerp(Color(0.85, 0.85, 0.9), 0.35)
	var trousers: Color = character.trouser_color if character != null else Color(0.3, 0.24, 0.18)
	var hat: Color = character.hat_color if character != null else Color(0.22, 0.35, 0.2)
	var skin := Color(0.95, 0.78, 0.65)
	var r: float = balance.player_radius
	# One mesh with vertex colours, not a node per part: co-op shows four of them (draw calls, M6).
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_part(tool, _capsule(r * 0.95, 1.1), Vector3(0.0, 0.95, 0.0), coat)
	_add_part(tool, _capsule(r * 0.8, 0.7), Vector3(0.0, 0.35, 0.0), trousers)
	_add_part(tool, _sphere(0.3), Vector3(0.0, 1.62, 0.0), skin)
	# Every Knödlinger has the family's round nose (GAME-DESIGN.md: one shared visual trait).
	_add_part(tool, _sphere(0.12), Vector3(0.0, 1.6, 0.3), Color(0.95, 0.6, 0.5))
	var brim := CylinderMesh.new()
	brim.top_radius = 0.42
	brim.bottom_radius = 0.42
	brim.height = 0.05
	brim.radial_segments = 12
	_add_part(tool, brim, Vector3(0.0, 1.86, 0.0), hat)
	var crown := CylinderMesh.new()
	crown.top_radius = 0.2
	crown.bottom_radius = 0.26
	crown.height = 0.26
	crown.radial_segments = 10
	_add_part(tool, crown, Vector3(0.0, 2.0, 0.0), hat)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = tool.commit()
	body.material_override = material
	look.add_child(body)
	return look


## Appends a primitive's triangles at `where` in `color` (stored linear: the Compatibility renderer
## ignores vertex_color_is_srgb, docs/DECISIONS.md M1).
func _add_part(tool: SurfaceTool, mesh: PrimitiveMesh, where: Vector3, color: Color) -> void:
	var arrays: Array = mesh.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var linear: Color = color.srgb_to_linear()
	for index: int in indices:
		tool.set_color(linear)
		tool.set_normal(normals[index])
		tool.add_vertex(vertices[index] + where)


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	mesh.radial_segments = 14
	mesh.rings = 4
	return mesh


static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh
