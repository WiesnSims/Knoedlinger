extends Node3D
## M0 stress test (GAME-DESIGN.md, M0): flat plane, capsule players, N data-driven enemies chasing
## them through the spatial hash, M pooled projectiles. Solo, host or client, from LaunchArgs:
##   --enemies=500 --projectiles=300   crowd size (URL: ?enemies=500&projectiles=300)
##   --seconds=60                      measure for this long after warm-up, print [RESULT], quit (desktop)
##   --bot=0                           no bot; the player stands still until WASD
##   --encode=1                        encode snapshots even with no clients (host cost in solo)
##   --net=ws --host | --join=<ip>     WebSocket backend (NetworkManager)
## Every second it prints a [STATS] line; the browser also gets window.knoedlStats / knoedlResult.

const ENEMY_DIR: String = "res://data/enemies"
## Clients size their arrays for any host crowd up to this.
const CLIENT_SLOTS: int = 1024
const WARMUP_SECONDS: float = 3.0

var balance: BalanceData
var types: Array[EnemyTypeData] = []
var enemies: EnemyManager
var replica: EnemyReplica
var renderer: EnemyRenderer
var projectiles: ProjectilePool
var players: Dictionary[int, Player] = {}
var camera: ChaseCamera
var stats := FrameStats.new()

var _enemy_count: int = 500
var _projectile_count: int = 300
var _seconds: float = 0.0
var _bot: bool = true
var _encode_always: bool = false
var _snapshot_timer: float = 0.0
var _pose_timer: float = 0.0
var _overlay_timer: float = 0.0
var _stats_timer: float = 0.0
var _seq: int = 0
var _fire_budget: float = 0.0
var _fire_angle: float = 0.0
var _fire_turn: int = 0
var _finished: bool = false
var _snapshot_bytes: int = 0
var _snapshots_encoded: int = 0
var _bytes_sent_start: int = -1
var _bytes_received_start: int = -1
var _clients_at_measure: int = 0
var _rejected_poses: int = 0
var _ended_reason: String = ""
# Host validation: the last accepted pose time per remote peer.
var _last_pose_ms: Dictionary[int, int] = {}


func _ready() -> void:
	InputSetup.ensure_actions()
	stats.warmup = WARMUP_SECONDS
	_enemy_count = maxi(LaunchArgs.get_int("enemies", 500), 0)
	_projectile_count = maxi(LaunchArgs.get_int("projectiles", 300), 0)
	_seconds = LaunchArgs.get_float("seconds", 0.0)
	_bot = LaunchArgs.get_flag("bot", true)
	_encode_always = LaunchArgs.get_flag("encode", false)
	balance = load("res://data/balance.tres")
	types = _load_types()
	_build_world()
	var host: bool = NetworkManager.is_host()
	var slots: int = maxi(_enemy_count, 1) if host else CLIENT_SLOTS
	renderer = EnemyRenderer.new()
	renderer.name = "EnemyRenderer"
	add_child(renderer)
	renderer.setup(types, slots)
	var local: Player = _spawn_player(NetworkManager.local_id(), true)
	camera = ChaseCamera.new()
	camera.name = "ChaseCamera"
	camera.far = 400.0
	add_child(camera)
	camera.target = local
	camera.snap_to_target()
	camera.make_current()
	if host:
		enemies = EnemyManager.new(balance, types, slots, LaunchArgs.get_int("seed", 1))
		enemies.populate(_enemy_count, _player_positions())
		if _projectile_count > 0:
			projectiles = ProjectilePool.new()
			projectiles.name = "Projectiles"
			add_child(projectiles)
			projectiles.setup(balance, _projectile_count)
	else:
		replica = EnemyReplica.new(balance, types, slots)
	NetworkManager.snapshot_received.connect(_on_snapshot)
	NetworkManager.events_received.connect(_on_events)
	NetworkManager.player_input_received.connect(_on_player_input)
	NetworkManager.peer_left.connect(_on_peer_left)
	NetworkManager.join_failed.connect(_on_join_failed)
	NetworkManager.session_ended.connect(_on_session_ended)
	print("[ARENA] role=%s enemies=%d projectiles=%d seconds=%s bot=%s types=%d adapter=%s" % [
		_role(), _enemy_count, _projectile_count, _seconds, _bot, types.size(), RenderingServer.get_video_adapter_name()])


func _process(delta: float) -> void:
	if _finished:
		return
	delta = minf(delta, 0.1)
	var was_measuring: bool = stats.is_measuring()
	stats.add_frame(delta)
	if stats.is_measuring() and not was_measuring:
		_bytes_sent_start = NetworkManager.bytes_sent
		_bytes_received_start = NetworkManager.bytes_received
		_clients_at_measure = NetworkManager.client_ids().size()
	if enemies != null:
		_host_frame(delta)
	elif replica != null:
		var t0: int = Time.get_ticks_usec()
		replica.update(Time.get_ticks_msec(), delta)
		renderer.draw(replica.capacity, replica.alive, replica.x, replica.z, replica.yaw, replica.type,
				replica.radius, replica.flash, replica.phase)
		stats.add_system("replica", Time.get_ticks_usec() - t0)
	_send_pose(delta)
	_report(delta)
	if _seconds > 0.0 and stats.measured_seconds() >= _seconds:
		_finish()


func _host_frame(delta: float) -> void:
	var targets: PackedVector3Array = _player_positions()
	var t0: int = Time.get_ticks_usec()
	enemies.update(delta, targets)
	var t1: int = Time.get_ticks_usec()
	stats.add_system("enemies", t1 - t0)
	if projectiles != null:
		_fire(delta, targets)
		projectiles.update(delta, enemies)
	var t2: int = Time.get_ticks_usec()
	stats.add_system("projectiles", t2 - t1)
	renderer.draw(enemies.capacity, enemies.alive, enemies.pos_x, enemies.pos_z, enemies.yaw, enemies.type,
			enemies.radius, enemies.flash, enemies.phase)
	var t3: int = Time.get_ticks_usec()
	stats.add_system("render_upload", t3 - t2)
	_snapshot_timer += delta
	var interval: float = 1.0 / balance.snapshot_rate_hz
	if _snapshot_timer >= interval:
		_snapshot_timer = fmod(_snapshot_timer, interval)
		var events: Array[PackedInt32Array] = enemies.take_events()
		var clients: bool = not NetworkManager.client_ids().is_empty()
		if clients or _encode_always:
			_seq = (_seq + 1) & 0xFFFF
			var snapshot: PackedByteArray = SnapshotCodec.encode_manager(_seq, Time.get_ticks_msec(), enemies)
			_snapshot_bytes += snapshot.size()
			_snapshots_encoded += 1
			var event_data: PackedByteArray = SnapshotCodec.encode_events(events[0], events[1], enemies)
			if clients:
				NetworkManager.send_events(event_data)
				NetworkManager.send_snapshot(snapshot)
	stats.add_system("net", Time.get_ticks_usec() - t3)


## The stress weapon: a spiral of shots from every player that keeps the projectile pool full.
func _fire(delta: float, targets: PackedVector3Array) -> void:
	if targets.is_empty():
		return
	_fire_budget = minf(_fire_budget + balance.projectile_fire_rate * delta, float(_projectile_count))
	while _fire_budget >= 1.0 and projectiles.has_free():
		_fire_budget -= 1.0
		_fire_angle += 2.39996
		_fire_turn = (_fire_turn + 1) % targets.size()
		var origin: Vector3 = targets[_fire_turn]
		projectiles.fire(origin.x, origin.z, cos(_fire_angle), sin(_fire_angle))


func _send_pose(delta: float) -> void:
	if not NetworkManager.is_online():
		return
	_pose_timer += delta
	var interval: float = 1.0 / balance.pose_rate_hz
	if _pose_timer < interval:
		return
	_pose_timer = fmod(_pose_timer, interval)
	var local: Player = players.get(NetworkManager.local_id())
	if local != null:
		NetworkManager.send_input(local.last_input.to_bytes())


func _report(delta: float) -> void:
	_overlay_timer += delta
	_stats_timer += delta
	if _overlay_timer >= 0.25:
		_overlay_timer = 0.0
		DebugOverlay.show_text(_overlay_text())
	if _stats_timer >= 1.0:
		_stats_timer = 0.0
		var line: Dictionary = {
			"t": snappedf(stats.elapsed, 0.1),
			"role": _role(),
			"fps": snappedf(stats.last_fps(), 0.1),
			"enemies": enemies.alive_count if enemies != null else replica.alive_count,
			"projectiles": projectiles.active_count if projectiles != null else 0,
			"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"players": players.size(),
		}
		var json: String = JSON.stringify(line)
		print("[STATS] " + json)
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.knoedlStats = %s;" % json)


func _overlay_text() -> String:
	var lines: PackedStringArray = []
	lines.append(tr("STRESS_HINT"))
	lines.append("%s | %.0f fps | %d draw calls | players %d" % [_role(), stats.last_fps(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), players.size()])
	if enemies != null:
		lines.append("enemies %d / %d | projectiles %d | kills %d | contacts %d" % [enemies.alive_count,
				enemies.capacity, projectiles.active_count if projectiles != null else 0, enemies.kills, enemies.contacts])
	elif replica != null:
		lines.append("enemies shown %d (host %d) | snapshots %d | pops %d" % [replica.alive_count,
				replica.host_alive_count(), replica.snapshots, replica.pops])
	var summary: Dictionary = stats.summary()
	if summary["frames"] > 0:
		lines.append("frame ms p50 %.2f p95 %.2f p99 %.2f max %.2f" % [summary["frame_ms_p50"],
				summary["frame_ms_p95"], summary["frame_ms_p99"], summary["frame_ms_max"]])
		var systems: Dictionary = summary["system_ms_avg"]
		var parts: PackedStringArray = []
		for system: String in systems:
			parts.append("%s %.2f" % [system, systems[system]])
		lines.append("ms/frame: " + ", ".join(parts))
	return "\n".join(lines)


func _finish() -> void:
	_finished = true
	var seconds: float = maxf(stats.measured_seconds(), 0.001)
	var result: Dictionary = {
		"role": _role(),
		"enemies_config": _enemy_count,
		"projectiles_config": _projectile_count,
		"adapter": RenderingServer.get_video_adapter_name(),
		"web": OS.has_feature("web"),
		"version": NetworkManager.version,
		"build": NetworkManager.build_id,
		"frame": stats.summary(),
		"players": players.size(),
		"rejected_poses": _rejected_poses,
	}
	if _ended_reason != "":
		result["ended_reason"] = _ended_reason
	if _snapshots_encoded > 0:
		result["snapshot_bytes_avg"] = _snapshot_bytes / _snapshots_encoded
	if enemies != null:
		result["kills"] = enemies.kills
		result["enemies_alive"] = enemies.alive_count
	if NetworkManager.is_online() or _ended_reason != "":
		var sent: int = NetworkManager.bytes_sent - maxi(_bytes_sent_start, 0)
		var received: int = NetworkManager.bytes_received - maxi(_bytes_received_start, 0)
		result["net"] = {
			"kib_per_s_in": snappedf(received / seconds / 1024.0, 0.01),
			"kib_per_s_out": snappedf(sent / seconds / 1024.0, 0.01),
			"kib_per_s_out_per_client": snappedf(sent / seconds / 1024.0 / maxi(_clients_at_measure, 1), 0.01),
			"clients": NetworkManager.client_ids().size(),
		}
	if replica != null:
		result["replica"] = replica.stats()
	_print_result(result)


func _print_result(result: Dictionary) -> void:
	var json: String = JSON.stringify(result)
	print("[RESULT] " + json)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.knoedlResult = %s;" % json)
		return
	NetworkManager.leave()
	get_tree().quit(0)


func _on_snapshot(data: PackedByteArray) -> void:
	if replica != null:
		replica.push(data, Time.get_ticks_msec())


func _on_events(data: PackedByteArray) -> void:
	if replica != null:
		replica.push_events(data)


func _on_player_input(peer_id: int, data: PackedByteArray) -> void:
	var message: InputMessage = InputMessage.from_bytes(data)
	if message == null or peer_id == NetworkManager.local_id():
		return
	var player: Player = players.get(peer_id)
	if player == null:
		player = _spawn_player(peer_id, false)
		player.global_position = message.position
	elif NetworkManager.is_host() and not _pose_is_plausible(peer_id, player, message):
		_rejected_poses += 1
		return
	_last_pose_ms[peer_id] = Time.get_ticks_msec()
	player.apply_remote(message)


## Host validation: a player may not move faster than they can walk (plus tolerance and slack for jitter).
func _pose_is_plausible(peer_id: int, player: Player, message: InputMessage) -> bool:
	var elapsed: float = (Time.get_ticks_msec() - _last_pose_ms.get(peer_id, Time.get_ticks_msec())) / 1000.0
	var allowed: float = balance.player_speed * balance.player_max_speed_tolerance * maxf(elapsed, 0.05) + 1.0
	var moved: Vector3 = message.position - player.last_input.position
	moved.y = 0.0
	return moved.length() <= allowed


func _on_peer_left(peer_id: int) -> void:
	var player: Player = players.get(peer_id)
	if player != null:
		players.erase(peer_id)
		player.queue_free()
	_last_pose_ms.erase(peer_id)


func _on_join_failed(reason: String) -> void:
	print("[RESULT] " + JSON.stringify({"role": "client", "rejected": reason}))
	_finished = true
	if not OS.has_feature("web"):
		NetworkManager.leave()
		get_tree().quit(0)


func _on_session_ended(reason: String) -> void:
	_ended_reason = reason
	print("[NET] session ended: %s" % reason)
	if not _finished:
		_finish()


func _spawn_player(peer_id: int, local: bool) -> Player:
	var player := Player.new()
	var bot: BotInput = BotInput.new(fposmod(peer_id * 0.37, 1.0)) if (local and _bot) else null
	player.setup(peer_id, local, balance, bot)
	add_child(player)
	player.global_position = Vector3(0.0, 0.05, 0.0)
	players[peer_id] = player
	return player


func _player_positions() -> PackedVector3Array:
	var positions := PackedVector3Array()
	for peer_id: int in players:
		positions.append(players[peer_id].global_position)
	return positions


func _role() -> String:
	match NetworkManager.mode:
		NetworkManager.Mode.HOST:
			return "host"
		NetworkManager.Mode.CLIENT:
			return "client"
	return "solo"


func _load_types() -> Array[EnemyTypeData]:
	var loaded: Array[EnemyTypeData] = []
	var files: PackedStringArray = ResourceLoader.list_directory(ENEMY_DIR)
	files.sort()
	for file: String in files:
		if file.ends_with(".tres") or file.ends_with(".res"):
			var data: EnemyTypeData = load(ENEMY_DIR.path_join(file)) as EnemyTypeData
			if data != null:
				loaded.append(data)
	return loaded


func _build_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.55, 0.75, 0.95)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.8, 0.9)
	environment.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	var size: float = balance.arena_half_size * 2.0
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 1.0, size)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	var plane := MeshInstance3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(size, size)
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.38, 0.6, 0.3)
	grass.roughness = 1.0
	plane_mesh.material = grass
	plane.mesh = plane_mesh
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.add_child(plane)
	# A Maibaum in the middle, so moving is visible on the flat plane.
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.15
	pole_mesh.bottom_radius = 0.25
	pole_mesh.height = 14.0
	pole_mesh.radial_segments = 8
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.85, 0.85, 0.9)
	pole_mesh.material = wood
	pole.mesh = pole_mesh
	pole.position = Vector3(0.0, 7.0, -6.0)
	ground.add_child(pole)
	add_child(ground)
