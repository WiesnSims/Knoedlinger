class_name Player
extends CharacterBody3D
## A Knödlinger. The local player moves themselves (Jolt, CharacterBody3D) from the keyboard or a
## BotInput and reports where they went as an InputMessage; remote players only follow the messages
## they receive. M0 placeholder look: a capsule.

const GRAVITY: float = 20.0
## Seconds the bot waits after the last key press before it takes over again.
const MANUAL_HOLD: float = 3.0
const REMOTE_FOLLOW_SPEED: float = 12.0

var peer_id: int = 1
var is_local: bool = false
var balance: BalanceData
var bot: BotInput
var last_input: InputMessage = InputMessage.new()

var _tick: int = 0
var _manual_timer: float = 0.0
var _remote_target: Vector3 = Vector3.ZERO
var _remote_yaw: float = 0.0
var _body: MeshInstance3D


func setup(p_peer_id: int, local: bool, p_balance: BalanceData, p_bot: BotInput) -> void:
	peer_id = p_peer_id
	is_local = local
	balance = p_balance
	bot = p_bot
	name = "Player_%d" % peer_id
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = balance.player_radius
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	_body = MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = balance.player_radius
	mesh.height = 1.8
	mesh.radial_segments = 16
	mesh.rings = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.42, 0.25) if local else Color(0.2, 0.35, 0.8)
	mesh.material = material
	_body.mesh = mesh
	_body.position.y = 0.9
	add_child(_body)
	var nose := MeshInstance3D.new()
	var nose_mesh := SphereMesh.new()
	nose_mesh.radius = 0.14
	nose_mesh.height = 0.28
	var nose_material := StandardMaterial3D.new()
	nose_material.albedo_color = Color(0.95, 0.6, 0.5)
	nose_mesh.material = nose_material
	nose.mesh = nose_mesh
	# Every Knödlinger has the family's round nose (GAME-DESIGN.md: one shared visual trait).
	nose.position = Vector3(0.0, 0.65, balance.player_radius)
	_body.add_child(nose)
	collision_layer = 2 if local else 0
	collision_mask = 1
	_remote_target = position


func _physics_process(delta: float) -> void:
	if not is_local:
		global_position = global_position.lerp(_remote_target, 1.0 - exp(-REMOTE_FOLLOW_SPEED * delta))
		rotation.y = lerp_angle(rotation.y, _remote_yaw, 1.0 - exp(-REMOTE_FOLLOW_SPEED * delta))
		return
	var move: Vector2 = _sample_move(delta)
	velocity.x = move.x * balance.player_speed
	velocity.z = move.y * balance.player_speed
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	var half: float = balance.arena_half_size - 1.0
	global_position.x = clampf(global_position.x, -half, half)
	global_position.z = clampf(global_position.z, -half, half)
	if move.length_squared() > 0.01:
		rotation.y = atan2(move.x, move.y)
	_tick += 1
	last_input.tick = _tick
	last_input.move = move
	last_input.buttons = InputMessage.BUTTON_JUMP if Input.is_action_pressed(&"jump") else 0
	last_input.position = global_position
	last_input.yaw = rotation.y


## Applies a validated message from the network to a remote player.
func apply_remote(message: InputMessage) -> void:
	last_input = message
	_remote_target = message.position
	_remote_yaw = message.yaw


func _sample_move(delta: float) -> Vector2:
	var keys: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if keys.length_squared() > 0.0:
		_manual_timer = MANUAL_HOLD
		return keys
	if _manual_timer > 0.0:
		_manual_timer -= delta
		return Vector2.ZERO
	if bot != null:
		return bot.sample(delta, global_position)
	return Vector2.ZERO
