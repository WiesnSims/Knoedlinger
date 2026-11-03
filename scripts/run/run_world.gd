extends Node3D
## One run (M1: the Knödl prototype on the test field). Solo, host or client, from LaunchArgs:
##   --character=ferdl          who plays (data/characters/<id>.tres)
##   --enemies=500              hold this many enemies (stress); without it the spawn ramp runs
##   --seconds=60               measure for this long after warm-up, print [RESULT], quit (desktop)
##   --bot=0                    no bot; the player stands still until WASD
##   --god=1                    players take no damage
##   --knodl_mass=500           start every Knödl this heavy (tuning)
##   --net=ws --host | --join=<ip>   WebSocket backend (NetworkManager)
## The host simulates everything that matters (enemies, every Knödl, Brösel, HP, XP) and sends it out;
## every player moves themselves. Solo is a host with zero clients. Every second it prints a [STATS]
## line; the browser also gets window.knoedlStats / knoedlResult.

const MAP_PATH: String = "res://data/maps/testfeld.tres"
const WAVE_PATH: String = "res://data/waves/m1_prototype.tres"
const CHARACTER_DIR: String = "res://data/characters"
## Clients size their arrays for any host crowd up to this.
const CLIENT_SLOTS: int = 1024
const WARMUP_SECONDS: float = 3.0
## Seconds after a respawn in which the host accepts any pose from that player (they teleported).
const RESPAWN_GRACE: float = 1.5
## The bot walks to Brösel closer than this before following its waypoints.
const BOT_BROSEL_REACH: float = 10.0

var balance: BalanceData
var map: MapData
var wave: WaveData
var character: CharacterData
var types: Array[EnemyTypeData] = []
var terrain: Heightfield
var ground: Heightfield
var enemies: EnemyManager
var replica: EnemyReplica
var renderer: EnemyRenderer
var brosel: BroselField
var players: Dictionary[int, Player] = {}
var states: Dictionary[int, PlayerState] = {}
var knodls: Dictionary[int, Knodl] = {}
var swings: Dictionary[int, SwingVfx] = {}
var camera: ChaseCamera
var hud: Hud
var stats := FrameStats.new()
var run_time: float = 0.0

var _forced_enemies: int = 0
var _seconds: float = 0.0
var _bot: bool = true
var _god: bool = false
var _start_mass: float = -1.0
var _snapshot_timer: float = 0.0
var _pose_timer: float = 0.0
var _overlay_timer: float = 0.0
var _stats_timer: float = 0.0
var _seq: int = 0
var _world_seq: int = 0
var _last_world_seq: int = -1
var _finished: bool = false
var _snapshot_bytes: int = 0
var _snapshots_encoded: int = 0
var _world_states: int = 0
var _brosel_messages: int = 0
var _brosel_errors: int = 0
var _host_brosel: int = 0
## Enemies alive right after the last enemy update, before this frame's kills (they respawn next
## update): the crowd the run actually holds.
var _alive_held: int = 0
## Most Knödl a client showed at once (players come and go; the end count says little).
var _knodls_max: int = 0
var _bytes_sent_start: int = -1
var _bytes_received_start: int = -1
var _clients_at_measure: int = 0
var _rejected_poses: int = 0
var _ended_reason: String = ""
var _bake_ms: int = 0
var _last_pose_ms: Dictionary[int, int] = {}
var _respawn_grace: Dictionary[int, float] = {}
var _seen_swings: Dictionary[int, int] = {}
var _seen_life: Dictionary[int, int] = {}
## The key the local player is stored under; a client only learns its real peer id once joined.
var _local_key: int = 1


func _ready() -> void:
	InputSetup.ensure_actions()
	stats.warmup = WARMUP_SECONDS
	_forced_enemies = maxi(LaunchArgs.get_int("enemies", 0), 0)
	_seconds = LaunchArgs.get_float("seconds", 0.0)
	# A run is played by a person unless asked otherwise (the automated checks pass bot=1).
	_bot = LaunchArgs.get_flag("bot", false)
	_god = LaunchArgs.get_flag("god", false)
	_start_mass = LaunchArgs.get_float("knodl_mass", -1.0)
	balance = load("res://data/balance.tres")
	map = load(MAP_PATH)
	wave = load(WAVE_PATH)
	character = _load_character(LaunchArgs.get_string("character", "ferdl"))
	types = wave.enemies
	var t0: int = Time.get_ticks_msec()
	terrain = Heightfield.bake_terrain(map)
	ground = Heightfield.bake_ground(map, terrain)
	MapBuilder.build(map, terrain, self)
	_bake_ms = Time.get_ticks_msec() - t0
	var host: bool = NetworkManager.is_host()
	var slots: int = maxi(_forced_enemies, balance.spawn_max_count) if host else CLIENT_SLOTS
	renderer = EnemyRenderer.new()
	renderer.name = "EnemyRenderer"
	add_child(renderer)
	renderer.setup(types, slots, ground)
	brosel = BroselField.new()
	brosel.name = "BroselField"
	add_child(brosel)
	brosel.setup(balance, ground, map.half_size)
	_local_key = NetworkManager.local_id()
	var local: Player = _spawn_player(_local_key, true)
	camera = ChaseCamera.new()
	camera.name = "ChaseCamera"
	camera.far = 400.0
	camera.fov = 70.0
	add_child(camera)
	camera.mouse_capture_allowed = not _bot or LaunchArgs.get_flag("mouse", false)
	camera.setup(balance, local)
	camera.yaw = 0.0
	camera.snap_to_target()
	camera.make_current()
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	if host:
		enemies = EnemyManager.new(balance, types, slots, LaunchArgs.get_int("seed", 1), ground, map.half_size)
		enemies.ring_min = balance.spawn_first_ring_min
		enemies.ring_max = balance.spawn_first_ring_max
		if _forced_enemies > 0:
			enemies.populate(_forced_enemies, _player_positions())
		else:
			enemies.respawn_delay = balance.spawn_respawn_delay
			enemies.target_count = balance.spawn_start_count
	else:
		replica = EnemyReplica.new(balance, types, slots)
	NetworkManager.snapshot_received.connect(_on_snapshot)
	NetworkManager.events_received.connect(_on_events)
	NetworkManager.player_input_received.connect(_on_player_input)
	NetworkManager.world_state_received.connect(_on_world_state)
	NetworkManager.brosel_received.connect(_on_brosel)
	NetworkManager.peer_joined.connect(_on_peer_joined)
	NetworkManager.peer_left.connect(_on_peer_left)
	NetworkManager.joined_host.connect(_on_joined_host)
	NetworkManager.join_failed.connect(_on_join_failed)
	NetworkManager.session_ended.connect(_on_session_ended)
	DebugOverlay.visible = _bot or LaunchArgs.get_flag("debug", false)
	print("[RUN] role=%s map=%s character=%s enemies=%s seconds=%s bot=%s bake_ms=%d adapter=%s" % [
		_role(), map.id, character.id, _forced_enemies if _forced_enemies > 0 else "ramp", _seconds, _bot,
		_bake_ms, RenderingServer.get_video_adapter_name()])


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
		_client_frame(delta)
	_local_frame()
	_send_pose(delta)
	_report(delta)
	if _seconds > 0.0 and stats.measured_seconds() >= _seconds:
		_finish()


func _host_frame(delta: float) -> void:
	run_time += delta
	if _forced_enemies == 0:
		var ramp: float = balance.spawn_start_count + balance.spawn_count_per_minute * run_time / 60.0
		enemies.target_count = mini(int(ramp), mini(balance.spawn_max_count, enemies.capacity))
	var peers: Array[int] = []
	var targets := PackedVector3Array()
	for peer: int in players:
		if not states[peer].downed:
			peers.append(peer)
			targets.append(players[peer].global_position)
	# Everybody knocked down: the crowd gathers round them (a downed player takes no damage).
	if targets.is_empty():
		for peer: int in players:
			peers.append(peer)
			targets.append(players[peer].global_position)
	var t0: int = Time.get_ticks_usec()
	enemies.update(delta, targets)
	_alive_held = enemies.alive_count
	if run_time > 1.0:
		enemies.ring_min = balance.spawn_ring_min
		enemies.ring_max = balance.spawn_ring_max
	var t1: int = Time.get_ticks_usec()
	stats.add_system("enemies", t1 - t0)
	for t: int in peers.size():
		if not _god and states[peers[t]].hurt(enemies.touch_damage[t], balance):
			_on_downed(peers[t])
	for peer: int in players:
		var state: PlayerState = states[peer]
		var player: Player = players[peer]
		var knodl: Knodl = knodls[peer]
		if state.tick(delta):
			_on_respawned(peer)
		if _respawn_grace.has(peer):
			_respawn_grace[peer] -= delta
			if _respawn_grace[peer] <= 0.0:
				_respawn_grace.erase(peer)
		player.downed = state.downed
		player.speed_factor = Formulas.knodl_speed_factor(knodl.radius, balance)
		var presses: int = player.last_input.schupfn_presses
		if presses != state.schupfn_seen:
			state.schupfn_seen = presses
			if not state.downed:
				var move: Vector2 = player.last_input.move
				knodl.schupfn(Vector3(move.x, 0.0, move.y))
		WeaponSystem.update(state, character.start_weapon, player, enemies, delta)
		knodl.crush(enemies)
	var t2: int = Time.get_ticks_usec()
	stats.add_system("knodl_weapons", t2 - t1)
	_drop_brosel()
	_feed_knodls(delta)
	var t3: int = Time.get_ticks_usec()
	stats.add_system("brosel", t3 - t2)
	renderer.draw(enemies.capacity, enemies.alive, enemies.pos_x, enemies.pos_z, enemies.yaw, enemies.type,
			enemies.radius, enemies.flash, enemies.phase)
	brosel.draw()
	var t4: int = Time.get_ticks_usec()
	stats.add_system("render_upload", t4 - t3)
	_snapshot_timer += delta
	var interval: float = 1.0 / balance.snapshot_rate_hz
	if _snapshot_timer >= interval:
		_snapshot_timer = fmod(_snapshot_timer, interval)
		_send_world()
	stats.add_system("net", Time.get_ticks_usec() - t4)


## Host: Brösel from the dead and from detached Knödl.
func _drop_brosel() -> void:
	for k: int in enemies.kill_x.size():
		for piece: int in Formulas.split_into_brosel(enemies.kill_xp[k], balance):
			brosel.drop(enemies.kill_x[k], enemies.kill_z[k], piece, true)
	enemies.clear_kills()
	for peer: int in knodls:
		var knodl: Knodl = knodls[peer]
		var shed: int = knodl.take_shed()
		if shed > 0:
			var at: Vector3 = knodl.global_position
			brosel.drop(at.x, at.z, shed, false, balance.brosel_shed_pickup_delay)
			knodl.set_knodl_mass(knodl.knodl_mass - shed)


## Host: Brösel near a player fly to their Knödl; every Knödl eats what it touches; the credits
## turn into XP and mass.
func _feed_knodls(delta: float) -> void:
	var positions: Dictionary[int, Vector4] = {}
	for peer: int in knodls:
		var knodl: Knodl = knodls[peer]
		var at: Vector3 = knodl.global_position
		positions[peer] = Vector4(at.x, at.y, at.z, knodl.radius)
		if not states[peer].downed:
			var player: Vector3 = players[peer].global_position
			brosel.attract(player.x, player.z, balance.player_pickup_range, peer)
		brosel.absorb(at, knodl.radius, peer)
	brosel.update(delta, positions)
	var credits: Dictionary[int, Vector2] = brosel.take_credits()
	for peer: int in credits:
		if not states.has(peer):
			continue
		var credit: Vector2 = credits[peer]
		var state: PlayerState = states[peer]
		var knodl: Knodl = knodls[peer]
		state.add_xp(credit.x, balance)
		knodl.add_knodl_mass(credit.y * balance.knodl_mass_per_xp)
		state.best_knodl_mass = maxf(state.best_knodl_mass, knodl.knodl_mass)
		if knodl.sort.heal_per_mass > 0.0 and not state.downed:
			state.hp = minf(state.hp + credit.y / knodl.sort.heal_per_mass, state.max_hp)


func _on_downed(peer: int) -> void:
	if peer == NetworkManager.local_id():
		hud.toast(tr("TOAST_DOWNED"))


func _on_respawned(peer: int) -> void:
	var knodl: Knodl = knodls[peer]
	knodl.set_knodl_mass(_knodl_start_mass(knodl))
	knodl.place_at(_spawn_position(peer) + Vector3(0.0, 0.6, balance.knodl_rest_length))
	_respawn_grace[peer] = RESPAWN_GRACE


func _send_world() -> void:
	var events: Array[PackedInt32Array] = enemies.take_events()
	var changes: Array[PackedInt32Array] = brosel.take_changes()
	if NetworkManager.client_ids().is_empty():
		return
	_seq = (_seq + 1) & 0xFFFF
	var snapshot: PackedByteArray = SnapshotCodec.encode_manager(_seq, Time.get_ticks_msec(), enemies)
	_snapshot_bytes += snapshot.size()
	_snapshots_encoded += 1
	NetworkManager.send_events(SnapshotCodec.encode_events(events[0], events[1], enemies))
	NetworkManager.send_snapshot(snapshot)
	if not changes[0].is_empty() or not changes[1].is_empty():
		NetworkManager.send_brosel(BroselCodec.encode(changes[1], changes[0], brosel))
	NetworkManager.send_world_state(WorldStateCodec.encode(_world_frame()))


func _world_frame() -> WorldStateCodec.Frame:
	var frame := WorldStateCodec.Frame.new()
	_world_seq = (_world_seq + 1) & 0xFFFF
	frame.seq = _world_seq
	frame.host_ms = Time.get_ticks_msec()
	frame.run_time = run_time
	frame.brosel_alive = brosel.active_count
	for peer: int in states:
		var state: PlayerState = states[peer]
		var knodl: Knodl = knodls[peer]
		var e := WorldStateCodec.Entry.new()
		e.peer_id = peer
		e.hp = state.hp
		e.max_hp = state.max_hp
		e.xp = state.xp
		e.level = state.level
		e.downed = state.downed
		e.life = state.life
		e.swing_count = state.swing_count
		e.knodl_state = knodl.state
		e.knodl_cooldown = knodl.cooldown
		e.knodl_mass = knodl.knodl_mass
		e.knodl_position = knodl.global_position
		e.knodl_rotation = knodl.quaternion
		frame.entries.append(e)
	return frame


func _client_frame(delta: float) -> void:
	run_time += delta
	var t0: int = Time.get_ticks_usec()
	replica.update(Time.get_ticks_msec(), delta)
	renderer.draw(replica.capacity, replica.alive, replica.x, replica.z, replica.yaw, replica.type,
			replica.radius, replica.flash, replica.phase)
	brosel.draw()
	stats.add_system("replica", Time.get_ticks_usec() - t0)


## Every role: what the local view needs (camera, HUD, swings, the local player's respawn).
func _local_frame() -> void:
	var id: int = NetworkManager.local_id()
	var local: Player = players.get(id)
	var state: PlayerState = states.get(id)
	var knodl: Knodl = knodls.get(id)
	if local != null:
		local.camera_yaw = camera.yaw
		if local.bot != null and Engine.get_process_frames() % 10 == 0:
			var at: Vector3 = local.global_position
			local.bot.attractor = brosel.nearest(at.x, at.z, BOT_BROSEL_REACH)
		if state != null:
			local.downed = state.downed
			if state.life != _seen_life.get(id, 0):
				_seen_life[id] = state.life
				local.teleport(_spawn_position(id))
		if knodl != null:
			local.speed_factor = Formulas.knodl_speed_factor(knodl.radius, balance)
			camera.extra_distance = maxf(knodl.radius - balance.knodl_base_radius, 0.0) * balance.camera_distance_per_knodl_radius
	for peer: int in states:
		var count: int = states[peer].swing_count
		if count != _seen_swings.get(peer, 0):
			_seen_swings[peer] = count
			if swings.has(peer):
				swings[peer].play()
		if players.has(peer) and peer != id:
			players[peer].downed = states[peer].downed
	if state != null:
		hud.show_state(state, knodl, run_time, balance)


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
		var local: PlayerState = states.get(NetworkManager.local_id())
		var knodl: Knodl = knodls.get(NetworkManager.local_id())
		var line: Dictionary = {
			"t": snappedf(stats.elapsed, 0.1),
			"role": _role(),
			"fps": snappedf(stats.last_fps(), 0.1),
			"enemies": enemies.alive_count if enemies != null else replica.alive_count,
			"projectiles": 0,
			"brosel": brosel.active_count,
			"level": local.level if local != null else 0,
			"knodl": snappedf(knodl.knodl_mass, 0.1) if knodl != null else 0.0,
			"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"players": players.size(),
		}
		var json: String = JSON.stringify(line)
		print("[STATS] " + json)
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.knoedlStats = %s;" % json)


func _overlay_text() -> String:
	var lines: PackedStringArray = []
	lines.append("%s | %.0f fps | %d draw calls | players %d | %s" % [_role(), stats.last_fps(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), players.size(),
			tr("HUD_BOT_HINT") if _bot else ""])
	if enemies != null:
		lines.append("enemies %d / %d | kills %d | contacts %d | brosel %d (merges %d)" % [enemies.alive_count,
				enemies.target_count, enemies.kills, enemies.contacts, brosel.active_count, brosel.merges])
	elif replica != null:
		lines.append("enemies shown %d (host %d) | snapshots %d | pops %d | brosel %d (host %d)" % [
				replica.alive_count, replica.host_alive_count(), replica.snapshots, replica.pops,
				brosel.active_count, _host_brosel])
	var knodl: Knodl = knodls.get(NetworkManager.local_id())
	if knodl != null:
		lines.append("knodl mass %.0f radius %.2f speed %.1f state %s | throws %d hits %d kills %d" % [
				knodl.knodl_mass, knodl.radius, knodl.current_speed(), Knodl.State.keys()[knodl.state],
				knodl.throws, knodl.hits, knodl.crushed])
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
		"scene": "run",
		"role": _role(),
		"enemies_config": _forced_enemies,
		"projectiles_config": 0,
		"adapter": RenderingServer.get_video_adapter_name(),
		"web": OS.has_feature("web"),
		"version": NetworkManager.version,
		"build": NetworkManager.build_id,
		"bake_ms": _bake_ms,
		"frame": stats.summary(),
		"players": players.size(),
		"rejected_poses": _rejected_poses,
		"run": _run_summary(),
	}
	if _ended_reason != "":
		result["ended_reason"] = _ended_reason
	if _snapshots_encoded > 0:
		result["snapshot_bytes_avg"] = _snapshot_bytes / _snapshots_encoded
	if enemies != null:
		result["kills"] = enemies.kills
		result["enemies_alive"] = _alive_held
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
		var replica_stats: Dictionary = replica.stats()
		replica_stats["world_states"] = _world_states
		replica_stats["brosel_messages"] = _brosel_messages
		replica_stats["brosel_errors"] = _brosel_errors
		replica_stats["brosel_shown"] = brosel.active_count
		replica_stats["brosel_host"] = _host_brosel
		replica_stats["knodls_shown"] = _knodls_max
		result["replica"] = replica_stats
	var json: String = JSON.stringify(result)
	print("[RESULT] " + json)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.knoedlResult = %s;" % json)
		return
	NetworkManager.leave()
	get_tree().quit(0)


func _run_summary() -> Dictionary:
	var id: int = NetworkManager.local_id()
	var state: PlayerState = states.get(id)
	var knodl: Knodl = knodls.get(id)
	var summary: Dictionary = {"time": snappedf(run_time, 0.1), "brosel_alive": brosel.active_count}
	if state != null:
		summary["level"] = state.level
		summary["xp"] = snappedf(state.xp, 0.1)
		summary["hp"] = snappedf(state.hp, 0.1)
		summary["deaths"] = state.deaths
		summary["damage_taken"] = snappedf(state.damage_taken, 0.1)
		summary["best_knodl_mass"] = snappedf(state.best_knodl_mass, 0.1)
	if knodl != null:
		summary["knodl_mass"] = snappedf(knodl.knodl_mass, 0.1)
		summary["knodl_radius"] = snappedf(knodl.radius, 0.01)
		summary["throws"] = knodl.throws
		summary["knodl_hits"] = knodl.hits
		summary["knodl_kills"] = knodl.crushed
		summary["auto_returns"] = knodl.auto_returns
	if enemies != null:
		summary["brosel_merges"] = brosel.merges
	return summary


func _on_snapshot(data: PackedByteArray) -> void:
	if replica != null:
		replica.push(data, Time.get_ticks_msec())


func _on_events(data: PackedByteArray) -> void:
	if replica != null:
		replica.push_events(data)


func _on_world_state(data: PackedByteArray) -> void:
	var frame: WorldStateCodec.Frame = WorldStateCodec.decode(data)
	if frame == null or NetworkManager.is_host():
		return
	if _last_world_seq >= 0 and EnemyReplica._seq_newer(_last_world_seq, frame.seq) <= 0:
		return
	_last_world_seq = frame.seq
	_world_states += 1
	run_time = frame.run_time
	_host_brosel = frame.brosel_alive
	for e: WorldStateCodec.Entry in frame.entries:
		# A player we have not heard from yet (their first pose is on its way) shows up next time.
		if not players.has(e.peer_id):
			continue
		var state: PlayerState = states.get(e.peer_id)
		if state == null:
			state = PlayerState.new(e.peer_id, e.max_hp)
			states[e.peer_id] = state
		state.hp = e.hp
		state.max_hp = e.max_hp
		state.xp = e.xp
		state.level = e.level
		state.downed = e.downed
		state.life = e.life
		state.swing_count = e.swing_count
		var knodl: Knodl = knodls.get(e.peer_id)
		if knodl == null:
			knodl = _spawn_knodl(e.peer_id, players[e.peer_id], false)
			knodl.place_at(e.knodl_position)
		knodl.apply_remote(e.knodl_position, e.knodl_rotation, e.knodl_mass, e.knodl_state as Knodl.State, e.knodl_cooldown)
	_knodls_max = maxi(_knodls_max, knodls.size())


func _on_brosel(data: PackedByteArray) -> void:
	if NetworkManager.is_host():
		return
	_brosel_messages += 1
	if not BroselCodec.apply(data, brosel):
		_brosel_errors += 1


func _on_player_input(peer_id: int, data: PackedByteArray) -> void:
	var message: InputMessage = InputMessage.from_bytes(data)
	if message == null or peer_id == NetworkManager.local_id():
		return
	var player: Player = players.get(peer_id)
	if player == null:
		player = _spawn_player(peer_id, false)
		player.teleport(message.position)
	elif NetworkManager.is_host() and not _respawn_grace.has(peer_id) and not _pose_is_plausible(peer_id, player, message):
		_rejected_poses += 1
		return
	_last_pose_ms[peer_id] = Time.get_ticks_msec()
	player.apply_remote(message)


## Host validation: a player may not move faster than they can run (plus tolerance and slack for jitter).
func _pose_is_plausible(peer_id: int, player: Player, message: InputMessage) -> bool:
	var elapsed: float = (Time.get_ticks_msec() - _last_pose_ms.get(peer_id, Time.get_ticks_msec())) / 1000.0
	var allowed: float = balance.player_speed * balance.player_max_speed_tolerance * maxf(elapsed, 0.05) + 1.0
	var moved: Vector3 = message.position - player.last_input.position
	moved.y = 0.0
	return moved.length() <= allowed


## Host: a new client gets every Brösel lying around once; changes follow at the snapshot rate.
func _on_peer_joined(peer_id: int) -> void:
	var all := PackedInt32Array()
	for i: int in brosel.capacity:
		if brosel.alive[i] != 0:
			all.append(i)
	if not all.is_empty():
		NetworkManager.send_brosel_to(peer_id, BroselCodec.encode(PackedInt32Array(), all, brosel))


func _on_peer_left(peer_id: int) -> void:
	for nodes: Dictionary in [players, knodls, swings]:
		var node: Node = nodes.get(peer_id)
		if node != null:
			nodes.erase(peer_id)
			node.queue_free()
	states.erase(peer_id)
	_last_pose_ms.erase(peer_id)
	_respawn_grace.erase(peer_id)


## Client: the host told us our peer id; file the local player under it.
func _on_joined_host() -> void:
	var id: int = NetworkManager.local_id()
	if id == _local_key:
		return
	for nodes: Dictionary in [players, states, knodls, swings]:
		if nodes.has(_local_key):
			nodes[id] = nodes[_local_key]
			nodes.erase(_local_key)
	var player: Player = players.get(id)
	if player != null:
		player.peer_id = id
		player.name = "Player_%d" % id
	_local_key = id


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
	var bot: BotInput = null
	if local and _bot:
		bot = BotInput.new(fposmod(peer_id * 0.37, 1.0))
		bot.set_waypoints(map.bot_waypoints, peer_id % maxi(map.bot_waypoints.size(), 1))
		bot.jump_every = 3.5
		bot.schupfn_every = 6.0
	player.setup(peer_id, local, balance, character, bot)
	player.ground = ground
	player.bounds = map.half_size
	player.spawn_point = _spawn_position(peer_id)
	add_child(player)
	player.teleport(player.spawn_point)
	players[peer_id] = player
	if NetworkManager.is_host():
		states[peer_id] = PlayerState.new(peer_id, balance.player_max_hp)
		var knodl: Knodl = _spawn_knodl(peer_id, player, true)
		knodl.place_at(player.spawn_point + Vector3(0.0, 0.6, balance.knodl_rest_length))
	var swing := SwingVfx.new()
	swing.setup(player, character.start_weapon)
	add_child(swing)
	swings[peer_id] = swing
	return player


func _spawn_knodl(peer_id: int, holder: Player, simulated: bool) -> Knodl:
	var knodl := Knodl.new()
	knodl.setup(peer_id, balance, character.knodl_sort, holder, simulated)
	add_child(knodl)
	if simulated:
		knodl.set_knodl_mass(_knodl_start_mass(knodl))
	knodls[peer_id] = knodl
	return knodl


func _knodl_start_mass(knodl: Knodl) -> float:
	if _start_mass >= 0.0:
		return _start_mass
	return balance.knodl_start_mass * knodl.sort.start_mass_mult


## Where a player starts: the map's spawn point, players side by side, on the ground.
func _spawn_position(peer_id: int) -> Vector3:
	var slot: int = 0 if peer_id == NetworkManager.HOST_ID else 1 + (absi(peer_id) % 3)
	var at: Vector3 = map.spawn_point + Vector3(slot * 2.0 - 3.0 if slot > 0 else 0.0, 0.0, 0.0)
	at.y = ground.height_at(at.x, at.z) + 0.1
	return at


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


func _load_character(id: String) -> CharacterData:
	var path: String = CHARACTER_DIR.path_join(id + ".tres")
	if not ResourceLoader.exists(path):
		push_warning("Unknown character '%s', playing Onkel Ferdl." % id)
		path = CHARACTER_DIR.path_join("ferdl.tres")
	return load(path) as CharacterData
