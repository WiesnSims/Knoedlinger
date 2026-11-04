class_name Player
extends CharacterBody3D
## A Knödlinger. The local player moves themselves (Jolt, CharacterBody3D) from the keyboard or a
## BotInput and reports where they went as an InputMessage; remote players only follow the messages
## they receive. Movement is relative to the camera; jumping uses coyote time and a jump buffer.
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
## Velocity on host and clients alike; remote players estimate it from their poses.
var motion_velocity: Vector3 = Vector3.ZERO
var jumps_used: int = 0

var _tick: int = 0
var _manual_timer: float = 0.0
var _remote_target: Vector3 = Vector3.ZERO
var _remote_yaw: float = 0.0
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _schupfn_presses: int = 0
var _last_position: Vector3 = Vector3.ZERO
var _look: Node3D
var _sign: Label3D


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


## Puts the player back at a point (start of a run, respawn).
func teleport(where: Vector3) -> void:
	global_position = where
	_remote_target = where
	_last_position = where
	velocity = Vector3.ZERO
	motion_velocity = Vector3.ZERO
	last_input.position = where
	reset_physics_interpolation()


func _process(_delta: float) -> void:
	# Knocked down: lie on the ground (only the look turns, the body stays upright for Jolt).
	var lying: float = PI * 0.5 if downed else 0.0
	_look.rotation.x = lerpf(_look.rotation.x, lying, 0.2)
	# Solo pauses for the Speisekarte; the sign is for teammates (co-op runs on).
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
	var on_floor: bool = is_on_floor()
	if on_floor:
		_coyote = balance.player_coyote_time
		jumps_used = 0
	else:
		_coyote = maxf(_coyote - delta, 0.0)
	var target := Vector2(move.x, move.y) * run_speed()
	var accel: float = balance.player_acceleration * (1.0 if on_floor else balance.player_air_control)
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(target, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
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
	if not on_floor:
		velocity.y -= balance.player_gravity * delta
	move_and_slide()
	var half: float = bounds - 1.0
	global_position.x = clampf(global_position.x, -half, half)
	global_position.z = clampf(global_position.z, -half, half)
	if global_position.y < ground_height_at(global_position) - 20.0:
		teleport(spawn_point)
	if move.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(move.x, move.y), 1.0 - exp(-TURN_SPEED * delta))
	var schupfn: bool = Input.is_action_just_pressed(&"schupfn") or (bot != null and _manual_timer <= 0.0 and bot.take_schupfn())
	if schupfn and not stuck:
		_schupfn_presses = (_schupfn_presses + 1) & 0xFF
	_update_motion(delta)
	_tick += 1
	last_input.tick = _tick
	last_input.move = move
	last_input.buttons = InputMessage.BUTTON_JUMP if Input.is_action_pressed(&"jump") else 0
	last_input.schupfn_presses = _schupfn_presses
	last_input.position = global_position
	last_input.yaw = rotation.y


## Applies a validated message from the network to a remote player.
func apply_remote(message: InputMessage) -> void:
	last_input = message
	_remote_target = message.position
	_remote_yaw = message.yaw


func _jump() -> void:
	GameAudio.play(&"jump", global_position)
	# Jump height grows with the bonus: v = v0 * sqrt(1 + bonus).
	velocity.y = balance.player_jump_velocity * sqrt(1.0 + maxf(stat_jump_height, 0.0))
	jumps_used += 1
	_jump_buffer = 0.0
	_coyote = 0.0


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
	look.add_child(_part(_capsule(r * 0.95, 1.1), Vector3(0.0, 0.95, 0.0), coat))
	look.add_child(_part(_capsule(r * 0.8, 0.7), Vector3(0.0, 0.35, 0.0), trousers))
	look.add_child(_part(_sphere(0.3), Vector3(0.0, 1.62, 0.0), skin))
	# Every Knödlinger has the family's round nose (GAME-DESIGN.md: one shared visual trait).
	look.add_child(_part(_sphere(0.12), Vector3(0.0, 1.6, 0.3), Color(0.95, 0.6, 0.5)))
	var brim := CylinderMesh.new()
	brim.top_radius = 0.42
	brim.bottom_radius = 0.42
	brim.height = 0.05
	brim.radial_segments = 12
	look.add_child(_part(brim, Vector3(0.0, 1.86, 0.0), hat))
	var crown := CylinderMesh.new()
	crown.top_radius = 0.2
	crown.bottom_radius = 0.26
	crown.height = 0.26
	crown.radial_segments = 10
	look.add_child(_part(crown, Vector3(0.0, 2.0, 0.0), hat))
	return look


func _part(mesh: PrimitiveMesh, where: Vector3, color: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = where
	return instance


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
