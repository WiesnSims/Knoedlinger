extends Node3D
## One run (M3: the Kirtag map with bosses, the gate and loot). Solo, host or client, from LaunchArgs:
##   --character=ferdl          who plays (data/characters/<id>.tres)
##   --map=kirtag               which map (data/maps/<id>.tres; testfeld is the M1 test field)
##   --respawn=1                knocked down = back at the spawn after a few seconds instead of the
##                              run ending (the automated checks and the balance log)
##   --enemies=500              hold this many enemies (stress); without it the wave timeline runs
##   --seconds=60               measure for this long after warm-up, print [RESULT], quit (desktop)
##   --bot=0                    no bot; the player stands still until WASD
##   --god=1                    players take no damage
##   --knodl_mass=500           start every Knödl this heavy (tuning)
##   --start_time=880           start the clock here (test Sperrstund' or late waves)
##   --autoplay=1 --runs=3      balance log: the bot plays whole runs, stats go to build/balance/
##   --log_slow=1               print a [SLOW] line for every measured frame over 40 ms
##   --net=ws --host | --join=<ip>   WebSocket backend (NetworkManager)
## The host simulates everything that matters (enemies, every Knödl, Brösel, HP, XP, builds,
## Wirtshäuser, the clock) and sends it out; every player moves themselves. Solo is a host with
## zero clients; only solo pauses for the Speisekarte. Every second it prints a [STATS] line; the
## browser also gets window.knoedlStats / knoedlResult.

## RUNNING until Sperrstund' (balance.run_seconds), then the Riesen-Wirt sweeps for
## sperrstund_seconds, then the run is ENDED. It also ends early when everyone is down.
enum Phase { RUNNING, SPERRSTUND, ENDED }
## How a run ended: WON = Sperrstund' with the Hofrat beaten, CLOSED = Sperrstund' without,
## LOST = everyone knocked down.
enum Result { NONE, WON, CLOSED, LOST }

const MAP_DIR: String = "res://data/maps"
const WAVE_PATH: String = "res://data/waves/kirtag.tres"
const CATALOG_PATH: String = "res://data/catalog/catalog.tres"
const CHARACTER_DIR: String = "res://data/characters"
## Clients size their arrays for any host crowd up to this.
const CLIENT_SLOTS: int = 1024
const MAX_PLAYERS: int = 4
const WARMUP_SECONDS: float = 3.0
## Seconds after a respawn in which the host accepts any pose from that player (they teleported).
const RESPAWN_GRACE: float = 1.5
## The bot walks to Brösel closer than this before following its waypoints.
const BOT_BROSEL_REACH: float = 10.0
## The bot only walks to a Wirtshaus this close.
const BOT_WIRT_REACH: float = 110.0
## A "too small" notice per player at most this often.
const NOTICE_INTERVAL: float = 3.0
## The Riesen-Wirt sweeps enemies within this radius out of the Kirtag.
const RIESEN_WIRT_SWEEP: float = 4.0
## Chest reveal titles beyond the Wirtshaus tiers (CHEST_TITLE_4 / _5): a map Kistl, a boss chest.
const CHEST_TIER_MAP: int = 4
const CHEST_TIER_BOSS: int = 5
## A boss's gold falls as this many coins.
const BOSS_COINS: int = 8

static var _autoplay_run: int = 0

var balance: BalanceData
var map: MapData
var wave: WaveData
var catalog: UpgradeCatalog
var character: CharacterData
var types: Array[EnemyTypeData] = []
var terrain: Heightfield
var ground: Heightfield
var enemies: EnemyManager
var replica: EnemyReplica
var renderer: EnemyRenderer
var brosel: BroselField
## Host: the real shots; client: shots shown from the players' fire counters.
var projectiles: ProjectilePool
var players: Dictionary[int, Player] = {}
var states: Dictionary[int, PlayerState] = {}
var knodls: Dictionary[int, Knodl] = {}
var weapon_vfx: Dictionary[int, WeaponVfx] = {}
var wirtshaeuser: Array[Wirtshaus] = []
var hazards: HazardField
var loot: LootField
var gate: PortalGate
## Host: the bosses of the run.
var bosses: BossDirector
## Host: run events of this frame (attack marks, loot, toasts ...).
var events := RunEventCodec.Queue.new()
var result: Result = Result.NONE
## The Formular quest and the gate (host state, mirrored in the world state).
var stempel_found: int = 0
var stempel_total: int = 0
var gate_flags: int = 0
var level_flow: LevelUpFlow
var camera: ChaseCamera
var hud: Hud
var speisekarte: Speisekarte
var end_screen: RunEndScreen
var inventory: InventoryScreen
var pause: PauseMenu
var stats := FrameStats.new()
var run_time: float = 0.0
var phase: Phase = Phase.RUNNING

var _forced_enemies: int = 0
var _seconds: float = 0.0
var _bot: bool = true
var _god: bool = false
var _autoplay: bool = false
var _start_mass: float = -1.0
var _snapshot_timer: float = 0.0
var _pose_timer: float = 0.0
var _overlay_timer: float = 0.0
var _stats_timer: float = 0.0
var _wave_timer: float = 0.0
var _phase_timer: float = 0.0
var _seq: int = 0
var _world_seq: int = 0
var _last_world_seq: int = -1
var _finished: bool = false
var _snapshot_bytes: int = 0
var _snapshots_encoded: int = 0
var _world_states: int = 0
var _brosel_messages: int = 0
var _brosel_errors: int = 0
var _offers_received: int = 0
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
var _notice_timers: Dictionary[int, float] = {}
var _seen_life: Dictionary[int, int] = {}
var _seen_served: Dictionary[int, bool] = {}
var _weapon_rng := RandomNumberGenerator.new()
var _riesen_wirt: Node3D
## The first frame after a solo pause carries the paused time; it is left out of the frame stats.
var _resumed: bool = false
## The Tab screen or the pause menu holds the solo pause (not the Speisekarte).
var _panel_paused: bool = false
## The pointer was captured last frame (the browser lets go of it on Esc without telling the game).
var _was_captured: bool = false
var _log_slow: bool = false
## The key the local player is stored under; a client only learns its real peer id once joined.
var _local_key: int = 1
var _respawn: bool = false
## Host: which mini-bosses have come, the bus, the death countdown, gold notices per player.
var _bosses_started: Dictionary[int, bool] = {}
var _bus_left: float = 0.0
var _bus_done: bool = false
var _lose_timer: float = -1.0
var _no_gold_timers: Dictionary[int, float] = {}
var _loot_rng := RandomNumberGenerator.new()
## Run events waiting for the next send to the clients.
var _outgoing: Array[RunEventCodec.Event] = []
## The boss in the HUD bar: BossDirector.list index (or NO_BOSS), its body's slot and HP.
var _focus_boss: int = WorldStateCodec.NO_BOSS
var _focus_slot: int = 0
var _focus_hp: float = 0.0
var _focus_max_hp: float = 0.0
## Every boss of the run by index, for names on clients (the same list the host's director has).
var _boss_list: Array[BossData] = []
## (index, run time) of every boss beaten, for the summary.
var _bosses_beaten: Array = []
var _bus: TouristenBus
var _run_events_received: int = 0
var _hazards_seen: int = 0
var _gate_shown: int = -1
var _last_hp: float = 0.0
var _was_downed: bool = false
var _sound_level: int = 0
var _last_xp: float = 0.0
var _knodl_state_heard: int = 0
var _knodl_hits_heard: int = 0


func _ready() -> void:
	InputSetup.ensure_actions()
	stats.warmup = WARMUP_SECONDS
	_forced_enemies = maxi(LaunchArgs.get_int("enemies", 0), 0)
	_seconds = LaunchArgs.get_float("seconds", 0.0)
	_autoplay = LaunchArgs.get_flag("autoplay", false)
	# A run is played by a person unless asked otherwise (the automated checks pass bot=1).
	_bot = LaunchArgs.get_flag("bot", false) or _autoplay
	_god = LaunchArgs.get_flag("god", false)
	_log_slow = LaunchArgs.get_flag("log_slow", false)
	_start_mass = LaunchArgs.get_float("knodl_mass", -1.0)
	_respawn = LaunchArgs.get_flag("respawn", false) or _autoplay
	balance = load("res://data/balance.tres")
	map = _load_map(RunSetup.map_id())
	wave = load(WAVE_PATH)
	catalog = load(CATALOG_PATH)
	UiStyle.build_icon_atlas(catalog)
	character = _load_character(RunSetup.character_id())
	types = wave.enemies
	run_time = maxf(LaunchArgs.get_float("start_time", 0.0), 0.0)
	var seed_value: int = LaunchArgs.get_int("seed", 1) + _autoplay_run * 7919
	_weapon_rng.seed = seed_value
	_loot_rng.seed = seed_value * 13 + 5
	for entry: WaveBoss in wave.bosses:
		_boss_list.append(entry.boss)
	if wave.final_boss != null:
		_boss_list.append(wave.final_boss)
	var t0: int = Time.get_ticks_msec()
	terrain = Heightfield.bake_terrain(map)
	ground = Heightfield.bake_ground(map, terrain)
	var props_material: ShaderMaterial = MapBuilder.build(map, terrain, self)
	_bake_ms = Time.get_ticks_msec() - t0
	var host: bool = NetworkManager.is_host()
	var slots: int = CLIENT_SLOTS
	if host:
		var crowd: float = balance.spawn_max_count
		if NetworkManager.is_online():
			crowd *= 1.0 + balance.coop_count_per_player * (MAX_PLAYERS - 1)
		slots = maxi(_forced_enemies, mini(ceili(crowd) + balance.spawn_extra_slots, CLIENT_SLOTS))
	renderer = EnemyRenderer.new()
	renderer.name = "EnemyRenderer"
	add_child(renderer)
	renderer.setup(types, slots, ground)
	brosel = BroselField.new()
	brosel.name = "BroselField"
	add_child(brosel)
	brosel.setup(balance, ground, map.half_size)
	projectiles = ProjectilePool.new()
	projectiles.name = "Projectiles"
	add_child(projectiles)
	projectiles.setup(balance, 400, ground)
	hazards = HazardField.new()
	hazards.name = "Hazards"
	add_child(hazards)
	hazards.setup(ground, seed_value)
	loot = LootField.new()
	loot.name = "Loot"
	add_child(loot)
	loot.setup(ground)
	gate = PortalGate.new()
	add_child(gate)
	gate.setup(map, ground)
	for spot: int in map.wirtshaus_spots.size():
		var wirt := Wirtshaus.new()
		add_child(wirt)
		wirt.setup(map, spot, ground)
		wirt.set_mat_radius(balance.wirtshaus_door_radius)
		wirtshaeuser.append(wirt)
	_local_key = NetworkManager.local_id()
	var local: Player = _spawn_player(_local_key, true)
	camera = ChaseCamera.new()
	camera.name = "ChaseCamera"
	camera.far = 400.0
	add_child(camera)
	camera.mouse_capture_allowed = not _bot or LaunchArgs.get_flag("mouse", false)
	camera.setup(balance, local)
	if props_material != null:
		camera.see_through.append(props_material)
	camera.see_through.append_array(renderer.materials)
	camera.make_current()
	ShaderWarmup.attach(camera)
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	speisekarte = Speisekarte.new()
	speisekarte.name = "Speisekarte"
	speisekarte.catalog = catalog
	speisekarte.balance = balance
	speisekarte.auto_pick = _bot
	add_child(speisekarte)
	speisekarte.answered.connect(NetworkManager.send_choice)
	end_screen = RunEndScreen.new()
	end_screen.name = "RunEnd"
	add_child(end_screen)
	end_screen.again_pressed.connect(_restart)
	inventory = InventoryScreen.new()
	inventory.name = "Inventory"
	add_child(inventory)
	inventory.toggled.connect(_on_inventory_toggled)
	end_screen.menu_pressed.connect(_quit_to_menu)
	pause = PauseMenu.new()
	pause.name = "Pause"
	add_child(pause)
	pause.toggled.connect(_on_pause_toggled)
	pause.quit_pressed.connect(_quit_to_menu)
	hud.covered = func() -> bool:
		return speisekarte.is_shown() or inventory.is_open() or end_screen.visible or pause.is_open()
	if host:
		enemies = EnemyManager.new(balance, types, slots, seed_value, ground, map.half_size)
		enemies.ring_min = balance.spawn_first_ring_min
		enemies.ring_max = balance.spawn_first_ring_max
		_update_wave()
		if _forced_enemies > 0:
			enemies.populate(_forced_enemies, _player_positions())
		else:
			enemies.respawn_delay = balance.spawn_respawn_delay
			enemies.target_count = balance.spawn_start_count
		level_flow = LevelUpFlow.new(balance, seed_value)
		_open_wirtshaeuser(balance.wirtshaus_count, seed_value)
		_scatter_start_brosel(seed_value)
		bosses = BossDirector.new(balance, enemies, hazards, wave)
		_place_map_chests()
	else:
		replica = EnemyReplica.new(balance, types, slots)
	NetworkManager.snapshot_received.connect(_on_snapshot)
	NetworkManager.events_received.connect(_on_events)
	NetworkManager.player_input_received.connect(_on_player_input)
	NetworkManager.world_state_received.connect(_on_world_state)
	NetworkManager.brosel_received.connect(_on_brosel)
	NetworkManager.run_events_received.connect(_on_run_events)
	NetworkManager.offer_received.connect(_on_offer)
	NetworkManager.choice_received.connect(_on_choice)
	NetworkManager.peer_joined.connect(_on_peer_joined)
	NetworkManager.peer_left.connect(_on_peer_left)
	NetworkManager.joined_host.connect(_on_joined_host)
	NetworkManager.join_failed.connect(_on_join_failed)
	NetworkManager.session_ended.connect(_on_session_ended)
	DebugOverlay.visible = LaunchArgs.get_flag("debug", _bot and not _autoplay)
	GameAudio.music(&"kirtag")
	GameAudio.bark(&"servas")
	print("[RUN] role=%s map=%s character=%s enemies=%s seconds=%s bot=%s bake_ms=%d adapter=%s" % [
		_role(), map.id, character.id, _forced_enemies if _forced_enemies > 0 else "wave", _seconds, _bot,
		_bake_ms, RenderingServer.get_video_adapter_name()])


func _exit_tree() -> void:
	# A solo Speisekarte may still hold the pause when the scene goes.
	get_tree().paused = false


func _process(delta: float) -> void:
	if _finished:
		return
	delta = minf(delta, 0.1)
	var was_measuring: bool = stats.is_measuring()
	if _resumed:
		_resumed = false
	else:
		stats.add_frame(delta)
		if _log_slow and delta > 0.04 and stats.is_measuring():
			print("[SLOW] run %.1f s: %.0f ms, weapons %s, menu %s" % [run_time, delta * 1000.0,
					Hud.build_text(states[NetworkManager.local_id()].build).replace("
", " / "), speisekarte.is_open()])
	if stats.is_measuring() and not was_measuring:
		_bytes_sent_start = NetworkManager.bytes_sent
		_bytes_received_start = NetworkManager.bytes_received
		_clients_at_measure = NetworkManager.client_ids().size()
	if enemies != null:
		_host_frame(delta)
	elif replica != null:
		_client_frame(delta)
	_local_frame(delta)
	_send_pose(delta)
	_report(delta)
	if _seconds > 0.0 and stats.measured_seconds() >= _seconds:
		_finish()


func _host_frame(delta: float) -> void:
	if phase != Phase.ENDED:
		run_time += delta
	_wave_timer -= delta
	if _wave_timer <= 0.0:
		_wave_timer = 1.0
		_update_wave()
	if _forced_enemies == 0 and phase == Phase.RUNNING:
		var ramp: float = balance.spawn_start_count + balance.spawn_count_per_minute * run_time / 60.0
		ramp *= 1.0 + balance.coop_count_per_player * (players.size() - 1)
		var cap: int = ceili(balance.spawn_max_count * (1.0 + balance.coop_count_per_player * (players.size() - 1)))
		if _bus_left > 0.0:
			ramp += wave.bus_extra
			cap += wave.bus_extra
		enemies.target_count = mini(int(ramp), mini(cap, enemies.capacity - balance.spawn_extra_slots))
	var peers: Array[int] = []
	var targets := PackedVector3Array()
	for peer: int in players:
		if not states[peer].downed and not states[peer].choosing:
			peers.append(peer)
			targets.append(players[peer].global_position)
	# Nobody to chase (all down or choosing): the crowd gathers round them, harmlessly.
	if targets.is_empty():
		for peer: int in players:
			peers.append(peer)
			targets.append(players[peer].global_position)
	var knodl_peers: Array[int] = []
	var knodl_targets := PackedVector4Array()
	for peer: int in knodls:
		if states[peer].build.stat(&"knodl_guard") <= 0.0:
			var at: Vector3 = knodls[peer].global_position
			knodl_peers.append(peer)
			knodl_targets.append(Vector4(at.x, at.y, at.z, knodls[peer].radius))
	var t0: int = Time.get_ticks_usec()
	enemies.update(delta, targets, knodl_targets)
	_alive_held = enemies.alive_count
	_start_attacks()
	_on_bosses_beaten(bosses.update(delta, targets, phase == Phase.RUNNING))
	bosses.touch_damage(targets, enemies.touch_damage)
	if run_time > 1.0:
		enemies.ring_min = balance.spawn_ring_min
		enemies.ring_max = balance.spawn_ring_max
	var t1: int = Time.get_ticks_usec()
	stats.add_system("enemies", t1 - t0)
	for k: int in knodl_peers.size():
		var eaten: float = enemies.knodl_bites[k]
		if eaten > 0.0:
			states[knodl_peers[k]].mass_eaten_by_enemies += eaten
			knodls[knodl_peers[k]].bite(eaten, balance.knodl_bite_spill)
	for t: int in peers.size():
		var state: PlayerState = states[peers[t]]
		var hit: float = Formulas.hit_damage(enemies.touch_damage[t], state.build.stat(&"armor"), balance)
		if not _god and phase == Phase.RUNNING and state.hurt(hit, balance):
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
		player.choosing = state.choosing
		var presses: int = player.last_input.schupfn_presses
		if presses != state.schupfn_seen:
			state.schupfn_seen = presses
			if not state.downed and not state.choosing:
				var move: Vector2 = player.last_input.move
				knodl.schupfn(Vector3(move.x, 0.0, move.y))
		if not state.downed and not state.choosing:
			WeaponSystem.update(state.build, player, enemies, projectiles, run_time, delta, _weapon_rng, balance)
		knodl.crush(enemies)
	projectiles.update(delta, enemies)
	hazards.update(delta)
	_resolve_hazards()
	var t2: int = Time.get_ticks_usec()
	stats.add_system("knodl_weapons", t2 - t1)
	_drop_brosel()
	_feed_knodls(delta)
	_check_wirtshaeuser(delta)
	_collect_loot(delta)
	level_flow.update(states, delta, not NetworkManager.client_ids().is_empty())
	_update_timeline(delta)
	_update_phase(delta)
	_flush_events()
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


## Host: the spawn mix and enemy HP follow the clock and the number of players.
func _update_wave() -> void:
	enemies.type_weights = wave.weights_at(run_time)
	enemies.hp_mult = (1.0 + balance.spawn_hp_per_minute * run_time / 60.0) \
			* (1.0 + balance.coop_hp_per_player * maxi(players.size() - 1, 0))


## Host: Sperrstund' at 15:00. The crowd stops coming, the Riesen-Wirt sweeps the Kirtag empty,
## then the run ends as a win.
func _update_phase(delta: float) -> void:
	match phase:
		Phase.RUNNING:
			if _lose_timer >= 0.0:
				_lose_timer -= delta
				if _lose_timer < 0.0:
					result = Result.LOST
					_set_phase(Phase.ENDED)
				return
			if run_time >= balance.run_seconds:
				_set_phase(Phase.SPERRSTUND)
				enemies.target_count = 0
		Phase.SPERRSTUND:
			_phase_timer += delta
			if _riesen_wirt != null:
				var at: Vector3 = _riesen_wirt.global_position
				var found: int = enemies.grid.query(at.x, at.z, RIESEN_WIRT_SWEEP)
				for k: int in found:
					# Bosses stay (a swept boss is not a beaten boss).
					if enemies.controlled[enemies.grid.results[k]] == 0:
						enemies.despawn(enemies.grid.results[k])
			if _phase_timer >= balance.sperrstund_seconds:
				result = Result.WON if gate_flags & WorldStateCodec.GATE_BOSS_BEATEN else Result.CLOSED
				_set_phase(Phase.ENDED)


## Every role: the phase changed (host: its own clock; client: the world state).
func _set_phase(new_phase: Phase) -> void:
	if new_phase == phase:
		return
	phase = new_phase
	match phase:
		Phase.SPERRSTUND:
			hud.toast(tr("TOAST_SPERRSTUND"))
			GameAudio.play(&"sperrstund")
			GameAudio.music(&"sperrstund")
			_spawn_riesen_wirt()
			hazards.clear()
		Phase.ENDED:
			_on_run_ended()


func _spawn_riesen_wirt() -> void:
	var local: Player = players.get(NetworkManager.local_id())
	if local == null:
		return
	_riesen_wirt = Wirtshaus.figure(3.5, true)
	_riesen_wirt.name = "RiesenWirt"
	add_child(_riesen_wirt)
	var behind: Vector3 = local.global_position - local.facing_direction() * 22.0
	behind.y = ground.height_at(behind.x, behind.z)
	_riesen_wirt.global_position = behind


## The Riesen-Wirt walks to the nearest player with his broom (every machine moves its own copy).
func _move_riesen_wirt(delta: float) -> void:
	if _riesen_wirt == null:
		return
	var local: Player = players.get(NetworkManager.local_id())
	if local == null:
		return
	var at: Vector3 = _riesen_wirt.global_position
	var to: Vector3 = local.global_position - at
	to.y = 0.0
	if to.length() > 3.0:
		at += to.normalized() * balance.riesen_wirt_speed * delta
		at.y = ground.height_at(at.x, at.z)
		_riesen_wirt.global_position = at
		_riesen_wirt.rotation.y = atan2(to.x, to.z)


func _on_run_ended() -> void:
	speisekarte.close()
	if result == Result.WON:
		GameAudio.play(&"victory")
	else:
		GameAudio.play(&"defeat")
		if result == Result.LOST:
			GameAudio.music(&"")
	if _autoplay:
		_write_balance_log()
		return
	if _seconds > 0.0:
		return
	var local_state: PlayerState = states.get(NetworkManager.local_id())
	end_screen.show_result(_run_summary(), not NetworkManager.is_online(),
			local_state.build if local_state != null else null, balance)


## Solo: the Tab screen pauses the game like the Speisekarte does; co-op runs on.
func _on_inventory_toggled(open: bool) -> void:
	if open:
		inventory.show_player(states.get(NetworkManager.local_id()), knodls.get(NetworkManager.local_id()), balance)
	_hold_pause(open)


func _on_pause_toggled(open: bool) -> void:
	_hold_pause(open)


## Solo: a full-screen panel (Tab screen, pause menu) stops the game while it is open.
func _hold_pause(open: bool) -> void:
	if open:
		speisekarte.hide_chest()
		if NetworkManager.is_host() and NetworkManager.client_ids().is_empty() and not get_tree().paused:
			get_tree().paused = true
			_panel_paused = true
	elif _panel_paused and not inventory.is_open() and not pause.is_open():
		_panel_paused = false
		if not speisekarte.is_open():
			get_tree().paused = false
			_resumed = true


## Pause menu "Zum Menü" or the end screen: leave the run for the title screen.
func _quit_to_menu() -> void:
	_finished = true
	get_tree().paused = false
	if NetworkManager.is_online():
		NetworkManager.leave()
	get_tree().change_scene_to_file.call_deferred("res://scenes/menu/main_menu.tscn")


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


## Host: crumbs from the family's Knödl stand around the spawn, for the first level-up.
func _scatter_start_brosel(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var centre: Vector3 = map.spawn_point
	for k: int in balance.start_brosel_count:
		var angle: float = TAU * k / maxi(balance.start_brosel_count, 1) + rng.randf_range(-0.2, 0.2)
		var distance: float = rng.randf_range(balance.start_brosel_ring_min, balance.start_brosel_ring_max)
		brosel.drop(centre.x + cos(angle) * distance, centre.z + sin(angle) * distance, balance.brosel_values[0], true)


## Host: which Wirtshäuser serve this run (GAME-DESIGN.md: random placement among the map's spots).
func _open_wirtshaeuser(count: int, seed_value: int) -> void:
	var closed: Array[int] = []
	for wirt: Wirtshaus in wirtshaeuser:
		if not wirt.open:
			closed.append(wirt.spot)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + wirtshaeuser.size()
	for k: int in mini(count, closed.size()):
		var pick: int = rng.randi_range(0, closed.size() - 1)
		wirtshaeuser[closed[pick]].set_state(true, false, 0)
		closed.remove_at(pick)


## Host: a Knödl rolled onto an open Wirtshaus door mat is eaten ("Mahlzeit!") and paid out by size.
func _check_wirtshaeuser(delta: float) -> void:
	for peer: int in _notice_timers.keys():
		_notice_timers[peer] -= delta
		if _notice_timers[peer] <= 0.0:
			_notice_timers.erase(peer)
	for peer: int in knodls:
		var state: PlayerState = states[peer]
		var knodl: Knodl = knodls[peer]
		if state.downed:
			continue
		for wirt: Wirtshaus in wirtshaeuser:
			if not wirt.open or wirt.served or not wirt.touches(knodl.global_position, knodl.radius, balance.wirtshaus_door_radius):
				continue
			var tier: int = Formulas.wirtshaus_tier(knodl.knodl_mass, balance)
			if tier < 0:
				if not _notice_timers.has(peer):
					_notice_timers[peer] = NOTICE_INTERVAL
					level_flow.notify(peer, OfferCodec.Notice.TOO_SMALL)
				continue
			_cash_in(peer, wirt, tier)
			break


func _cash_in(peer: int, wirt: Wirtshaus, tier: int) -> void:
	var state: PlayerState = states[peer]
	var knodl: Knodl = knodls[peer]
	wirt.set_state(true, true, tier)
	state.cash_ins[tier] += 1
	var gold: int = roundi(knodl.knodl_mass * balance.wirtshaus_gold_per_mass) if tier == 0 else 0
	if tier == 2:
		state.build.rerolls += balance.wirtshaus_l_rerolls
	var items: int = balance.wirtshaus_chest_items[tier] if tier < balance.wirtshaus_chest_items.size() else 0
	level_flow.give_chest(peer, state, tier, items, tier == 3, gold, -1, balance.boss_chest_min_rarity if tier == 3 else 0)
	knodl.set_knodl_mass(_knodl_start_mass(knodl))
	print("[RUN] cash-in peer=%d tier=%d t=%.1f" % [peer, tier, run_time])


## Host: Brösel from the dead and from Knödl that shed (thrown, or bitten).
func _drop_brosel() -> void:
	for k: int in enemies.kill_x.size():
		var kx: float = enemies.kill_x[k]
		var kz: float = enemies.kill_z[k]
		if k < 4:
			GameAudio.play(&"kill", Vector3(kx, ground.height_at(kx, kz), kz))
		for piece: int in Formulas.split_into_brosel(enemies.kill_xp[k], balance):
			brosel.drop(kx, kz, piece, true)
		var coins: int = types[enemies.kill_type[k]].gold_drop
		if coins == 0 and _loot_rng.randf() < balance.coin_drop_chance:
			coins = 1
		for c: int in coins:
			_drop_loot(LootField.Kind.COIN, kx + _loot_rng.randf_range(-1.0, 1.0), kz + _loot_rng.randf_range(-1.0, 1.0), balance.coin_value)
		if _loot_rng.randf() < balance.heal_drop_chance:
			_drop_loot(LootField.Kind.HEAL, kx, kz, roundi(balance.heal_amount))
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
			var reach: float = balance.player_pickup_range * (1.0 + states[peer].build.stat(&"pickup"))
			brosel.attract(player.x, player.z, reach, peer)
		brosel.absorb(at, knodl.radius, peer)
	brosel.update(delta, positions)
	var credits: Dictionary[int, Vector2] = brosel.take_credits()
	for peer: int in credits:
		if not states.has(peer):
			continue
		var credit: Vector2 = credits[peer]
		var state: PlayerState = states[peer]
		var knodl: Knodl = knodls[peer]
		state.add_xp(credit.x, balance, run_time)
		knodl.add_knodl_mass(credit.y * balance.knodl_mass_per_xp)
		state.best_knodl_mass = maxf(state.best_knodl_mass, knodl.knodl_mass)
		if knodl.sort.heal_per_mass > 0.0:
			state.heal(credit.y / knodl.sort.heal_per_mass)


func _on_downed(peer: int) -> void:
	var state: PlayerState = states[peer]
	# Marterl-Kerze: one revive per copy, back up at once with half the HP.
	if state.revives_used < roundi(state.build.effect(&"revive")):
		state.revives_used += 1
		state.deaths -= 1
		state.downed = false
		state.downed_timer = 0.0
		state.hp = state.max_hp * balance.item_revive_hp
		events.toast("TOAST_REVIVED")
		return
	state.downed_times.append(run_time)
	if _respawn:
		return
	# Solo: the run is over. Co-op: down until the M6 revives exist (coop_down_seconds); the run
	# is lost when everyone is down at once.
	state.downed_timer = INF if players.size() <= 1 else balance.coop_down_seconds
	for other: int in states:
		if not states[other].downed:
			return
	_lose_timer = balance.death_screen_delay


func _on_respawned(peer: int) -> void:
	var knodl: Knodl = knodls[peer]
	knodl.set_knodl_mass(_knodl_start_mass(knodl))
	knodl.place_at(_spawn_position(peer) + Vector3(0.0, 0.6, knodl.rest_length()))
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
	while not _outgoing.is_empty():
		var chunk: Array[RunEventCodec.Event] = _outgoing.slice(0, RunEventCodec.MAX_EVENTS)
		_outgoing = _outgoing.slice(RunEventCodec.MAX_EVENTS)
		NetworkManager.send_run_events(RunEventCodec.encode(chunk))
	NetworkManager.send_world_state(WorldStateCodec.encode(_world_frame()))


func _world_frame() -> WorldStateCodec.Frame:
	var frame := WorldStateCodec.Frame.new()
	_world_seq = (_world_seq + 1) & 0xFFFF
	frame.seq = _world_seq
	frame.host_ms = Time.get_ticks_msec()
	frame.run_time = run_time
	frame.brosel_alive = brosel.active_count
	frame.phase = phase
	frame.stempel_found = stempel_found
	frame.stempel_total = stempel_total
	frame.gate = gate_flags
	frame.result = result
	frame.boss = _focus_boss
	frame.boss_slot = _focus_slot
	frame.boss_hp = _focus_hp
	frame.boss_max_hp = _focus_max_hp
	for wirt: Wirtshaus in wirtshaeuser:
		var flags: int = (WorldStateCodec.WIRT_OPEN if wirt.open else 0) | (WorldStateCodec.WIRT_SERVED if wirt.served else 0)
		frame.wirtshaeuser.append(Vector3i(wirt.spot, flags, wirt.tier))
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
		e.choosing = state.choosing
		e.life = state.life
		e.pending_levels = state.pending_levels
		e.knodl_state = knodl.state
		e.knodl_cooldown = knodl.cooldown
		e.knodl_mass = knodl.knodl_mass
		e.knodl_position = knodl.global_position
		e.knodl_rotation = knodl.quaternion
		e.gold = state.build.gold
		e.rerolls = state.build.rerolls
		e.banishes = state.build.banishes
		e.chests_opened = state.chests_opened
		e.weapons = state.build.weapon_rows()
		e.passives = state.build.passive_rows()
		e.items = state.build.item_rows()
		frame.entries.append(e)
	return frame


func _client_frame(delta: float) -> void:
	if phase != Phase.ENDED:
		run_time += delta
	var t0: int = Time.get_ticks_usec()
	replica.update(Time.get_ticks_msec(), delta)
	renderer.draw(replica.capacity, replica.alive, replica.x, replica.z, replica.yaw, replica.type,
			replica.radius, replica.flash, replica.phase)
	brosel.draw()
	projectiles.update(delta, null)
	hazards.update(delta)
	for at: Vector2 in replica.recent_deaths:
		GameAudio.play(&"kill", Vector3(at.x, ground.height_at(at.x, at.y), at.y))
	replica.recent_deaths.clear()
	stats.add_system("replica", Time.get_ticks_usec() - t0)


## Every role: what the view needs (camera, HUD, weapon effects, stats on the player nodes, the
## local player's respawn, the bot's goals).
func _local_frame(delta: float) -> void:
	var id: int = NetworkManager.local_id()
	var local: Player = players.get(id)
	var state: PlayerState = states.get(id)
	var knodl: Knodl = knodls.get(id)
	for peer: int in states:
		var peer_state: PlayerState = states[peer]
		var player: Player = players.get(peer)
		if player == null:
			continue
		var build: PlayerBuild = peer_state.build
		player.choosing = peer_state.choosing
		player.downed = peer_state.downed
		player.stat_speed = 1.0 + build.stat(&"move_speed")
		player.stat_jump_height = build.stat(&"jump_height")
		player.stat_extra_jumps = roundi(build.stat(&"extra_jumps"))
		var peer_knodl: Knodl = knodls.get(peer)
		if peer_knodl != null:
			peer_knodl.string_mult = 1.0 + build.stat(&"string_length")
			player.speed_factor = Formulas.knodl_speed_factor(peer_knodl.radius, balance)
		if weapon_vfx.has(peer):
			weapon_vfx[peer].sync(build, run_time, delta, null if NetworkManager.is_host() else projectiles)
	if local != null:
		local.camera_yaw = camera.yaw
		if local.bot != null and Engine.get_process_frames() % 10 == 0:
			local.bot.attractor = _bot_goal(local, knodl)
		if state != null and state.life != _seen_life.get(id, 0):
			_seen_life[id] = state.life
			local.teleport(_spawn_position(id))
		if knodl != null:
			camera.extra_distance = maxf(knodl.radius - balance.knodl_base_radius, 0.0) * balance.camera_distance_per_knodl_radius
	for wirt: Wirtshaus in wirtshaeuser:
		if wirt.served and not _seen_served.get(wirt.spot, false):
			hud.toast(tr("TOAST_MAHLZEIT"))
		_seen_served[wirt.spot] = wirt.served
	_point_to_wirtshaus(local)
	_move_riesen_wirt(delta)
	_show_run_state(local, state, delta)
	if state != null:
		hud.show_state(state, knodl, run_time, balance)
		if speisekarte.is_open():
			speisekarte.show_player(state, knodl)
		if inventory.is_open():
			inventory.show_player(state, knodl, balance)
	inventory.allowed = not speisekarte.is_open() and not pause.is_open() and phase != Phase.ENDED
	if not inventory.allowed and inventory.is_open():
		inventory.set_open(false)
	pause.allowed = not speisekarte.is_open() and not inventory.is_open() and phase != Phase.ENDED
	if not pause.allowed and pause.is_open():
		pause.set_open(false)
	# The browser lets go of the pointer on Esc without passing the key on: treat it as Esc.
	var captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if _was_captured and not captured and pause.allowed:
		pause.set_open(true)
	_was_captured = captured
	hud.show_mouse_hint(camera.mouse_capture_allowed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
			and not speisekarte.is_open() and not pause.is_open() and phase != Phase.ENDED)


func _point_to_wirtshaus(local: Player) -> void:
	var wirt: Wirtshaus = _nearest_open_wirtshaus(local.global_position if local != null else Vector3.ZERO)
	if local == null or wirt == null or phase != Phase.RUNNING:
		hud.hide_wirt_marker()
		return
	var at: Vector3 = wirt.mat_centre()
	hud.show_wirt_marker(camera, at, local.global_position.distance_to(at))


func _nearest_open_wirtshaus(from: Vector3) -> Wirtshaus:
	var best: Wirtshaus = null
	var best_sq: float = INF
	for wirt: Wirtshaus in wirtshaeuser:
		if not wirt.open or wirt.served:
			continue
		var d_sq: float = from.distance_squared_to(wirt.mat_centre())
		if d_sq < best_sq:
			best_sq = d_sq
			best = wirt
	return best


## Where the bot walks first: a heavy Knödl goes to the nearest open Wirtshaus, else to Brösel.
func _bot_goal(local: Player, knodl: Knodl) -> Vector2:
	var at: Vector3 = local.global_position
	var here := Vector2(at.x, at.z)
	# Out of any attack mark first (sideways out of a line, straight out of a circle).
	for h: HazardField.Hazard in hazards.hazards:
		if h.left > 0.0 and HazardField.contains(h, at.x, at.z, 0.8):
			if h.shape == AttackData.Shape.LINE:
				var side := Vector2(cos(h.angle), -sin(h.angle))
				var rel := Vector2(at.x - h.x, at.z - h.z)
				return here + side * signf(rel.dot(side) + 0.001) * (h.radius + 2.5)
			var away := Vector2(at.x - h.x, at.z - h.z)
			return Vector2(h.x, h.z) + (away.normalized() if away.length() > 0.1 else Vector2.RIGHT) * (h.radius + 2.5)
	# The Formular quest: Stempel, then the gate.
	var stempel: int = loot.nearest(LootField.Kind.STEMPEL, at.x, at.z)
	if stempel >= 0:
		return Vector2(loot.xs[stempel], loot.zs[stempel])
	if gate_flags & WorldStateCodec.GATE_OPEN and not gate_flags & WorldStateCodec.GATE_BOSS_OUT:
		var mouth: Vector3 = gate.mouth()
		return Vector2(mouth.x, mouth.z)
	# Stay a few metres in front of a boss, facing it, the way a player fights one (its marks are
	# dodged above).
	var boss_at: Vector3 = _boss_position() if _focus_boss != WorldStateCodec.NO_BOSS else Vector3.INF
	if boss_at.is_finite() and here.distance_to(Vector2(boss_at.x, boss_at.z)) < 60.0:
		var boss_2d := Vector2(boss_at.x, boss_at.z)
		return boss_2d + (here - boss_2d).normalized() * 2.5
	var chest: int = loot.nearest(LootField.Kind.BOSS_CHEST, at.x, at.z)
	if chest >= 0 and here.distance_to(Vector2(loot.xs[chest], loot.zs[chest])) < 80.0:
		return Vector2(loot.xs[chest], loot.zs[chest])
	var state: PlayerState = states.get(local.peer_id)
	if state != null and state.hp < state.max_hp * 0.6:
		var heal: int = loot.nearest(LootField.Kind.HEAL, at.x, at.z)
		if heal >= 0 and here.distance_to(Vector2(loot.xs[heal], loot.zs[heal])) < 30.0:
			return Vector2(loot.xs[heal], loot.zs[heal])
	chest = loot.nearest(LootField.Kind.CHEST, at.x, at.z)
	if chest >= 0 and state != null and state.build.gold >= _chest_price(chest, state) \
			and here.distance_to(Vector2(loot.xs[chest], loot.zs[chest])) < 40.0:
		return Vector2(loot.xs[chest], loot.zs[chest])
	if knodl != null and knodl.knodl_mass >= balance.bot_cash_in_mass:
		var wirt: Wirtshaus = _nearest_open_wirtshaus(at)
		if wirt != null and at.distance_to(wirt.mat_centre()) < BOT_WIRT_REACH:
			var mat: Vector3 = wirt.mat_centre()
			return Vector2(mat.x, mat.z)
	return brosel.nearest(at.x, at.z, BOT_BROSEL_REACH)


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
			"run": snappedf(run_time, 0.1),
			"role": _role(),
			"fps": snappedf(stats.last_fps(), 0.1),
			"enemies": enemies.alive_count if enemies != null else replica.alive_count,
			"projectiles": projectiles.active_count,
			"brosel": brosel.active_count,
			"level": local.level if local != null else 0,
			"knodl": snappedf(knodl.knodl_mass, 0.1) if knodl != null else 0.0,
			"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"players": players.size(),
		}
		var json: String = JSON.stringify(line)
		if not _autoplay:
			print("[STATS] " + json)
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.knoedlStats = %s;" % json)


func _overlay_text() -> String:
	var lines: PackedStringArray = []
	lines.append("%s | %.0f fps | %d draw calls | players %d | %s" % [_role(), stats.last_fps(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), players.size(),
			tr("HUD_BOT_HINT") if _bot else ""])
	if enemies != null:
		lines.append("enemies %d / %d (hp x%.2f) | kills %d | contacts %d | shots %d | brosel %d (merges %d)" % [
				enemies.alive_count, enemies.target_count, enemies.hp_mult, enemies.kills, enemies.contacts,
				projectiles.active_count, brosel.active_count, brosel.merges])
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
	get_tree().paused = false
	var seconds: float = maxf(stats.measured_seconds(), 0.001)
	var report: Dictionary = {
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
		report["ended_reason"] = _ended_reason
	if _snapshots_encoded > 0:
		report["snapshot_bytes_avg"] = _snapshot_bytes / _snapshots_encoded
	if enemies != null:
		report["kills"] = enemies.kills
		report["enemies_alive"] = _alive_held
		report["loot"] = loot.count
	if NetworkManager.is_online() or _ended_reason != "":
		var sent: int = NetworkManager.bytes_sent - maxi(_bytes_sent_start, 0)
		var received: int = NetworkManager.bytes_received - maxi(_bytes_received_start, 0)
		report["net"] = {
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
		replica_stats["offers_received"] = _offers_received
		replica_stats["run_events"] = _run_events_received
		replica_stats["hazards_seen"] = _hazards_seen
		replica_stats["loot_shown"] = loot.count
		report["replica"] = replica_stats
	var json: String = JSON.stringify(report)
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
	var summary: Dictionary = {"time": snappedf(run_time, 0.1), "phase": Phase.keys()[phase],
		"brosel_alive": brosel.active_count, "result": Result.keys()[result], "stempel": stempel_found,
		"hofrat_beaten": (gate_flags & WorldStateCodec.GATE_BOSS_BEATEN) != 0, "bosses_beaten": _bosses_beaten.duplicate()}
	if state != null:
		summary["level"] = state.level
		summary["xp"] = snappedf(state.xp, 0.1)
		summary["hp"] = snappedf(state.hp, 0.1)
		summary["deaths"] = state.deaths
		summary["damage_taken"] = snappedf(state.damage_taken, 0.1)
		summary["best_knodl_mass"] = snappedf(state.best_knodl_mass, 0.1)
		summary["gold"] = state.build.gold
		summary["cash_ins"] = Array(state.cash_ins)
		var total: int = 0
		for count: int in state.cash_ins:
			total += count
		summary["cash_in_total"] = total
		summary["mass_eaten"] = snappedf(state.mass_eaten_by_enemies, 0.1)
		var times: Array = []
		for t: float in state.level_times:
			times.append(snappedf(t, 0.1))
		summary["level_times"] = times
		var downs: Array = []
		for t: float in state.downed_times:
			downs.append(snappedf(t, 0.1))
		summary["downed_times"] = downs
		var weapons: Array = []
		for owned: PlayerBuild.OwnedWeapon in state.build.weapons:
			weapons.append("%s %d" % [owned.data.id, owned.level])
		summary["weapons"] = weapons
		var passives: Array = []
		for owned: PlayerBuild.OwnedPassive in state.build.passives:
			passives.append("%s %d" % [owned.data.id, owned.level])
		summary["passives"] = passives
		var items: Array = []
		for owned: PlayerBuild.OwnedItem in state.build.items:
			items.append("%s %d" % [owned.data.id, owned.count])
		summary["items"] = items
	if knodl != null:
		summary["knodl_mass"] = snappedf(knodl.knodl_mass, 0.1)
		summary["knodl_radius"] = snappedf(knodl.radius, 0.01)
		summary["throws"] = knodl.throws
		summary["knodl_hits"] = knodl.hits
		summary["knodl_kills"] = knodl.crushed
		summary["auto_returns"] = knodl.auto_returns
	if enemies != null:
		summary["kills"] = enemies.kills
		summary["brosel_merges"] = brosel.merges
		summary["cards_picked"] = level_flow.picks
	return summary


## Balance log (CLAUDE.md: --autoplay): one JSON per run in build/balance/, then the next run.
func _write_balance_log() -> void:
	var dir: String = LaunchArgs.get_string("out", "user://balance")
	DirAccess.make_dir_recursive_absolute(dir)
	var summary: Dictionary = _run_summary()
	summary["run"] = _autoplay_run + 1
	summary["seed"] = LaunchArgs.get_int("seed", 1) + _autoplay_run * 7919
	summary["character"] = String(character.id)
	var path: String = dir.path_join("run-%s-%02d.json" % [Time.get_datetime_string_from_system().replace(":", ""), _autoplay_run + 1])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(summary, "  "))
		file.close()
	print("[BALANCE] " + JSON.stringify(summary))
	_autoplay_run += 1
	if _autoplay_run < LaunchArgs.get_int("runs", 1):
		_restart.call_deferred()
	else:
		_finished = true
		get_tree().quit(0)


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
	stempel_found = frame.stempel_found
	stempel_total = frame.stempel_total
	gate_flags = frame.gate
	result = frame.result as Result
	_focus_boss = frame.boss
	_focus_slot = frame.boss_slot
	_focus_hp = frame.boss_hp
	_focus_max_hp = frame.boss_max_hp
	for wirt_state: Vector3i in frame.wirtshaeuser:
		if wirt_state.x < wirtshaeuser.size():
			var wirt: Wirtshaus = wirtshaeuser[wirt_state.x]
			var open: bool = (wirt_state.y & WorldStateCodec.WIRT_OPEN) != 0
			var served: bool = (wirt_state.y & WorldStateCodec.WIRT_SERVED) != 0
			if open != wirt.open or served != wirt.served or wirt_state.z != wirt.tier:
				wirt.set_state(open, served, wirt_state.z)
	_set_phase(frame.phase as Phase)
	for e: WorldStateCodec.Entry in frame.entries:
		# A player we have not heard from yet (their first pose is on its way) shows up next time.
		if not players.has(e.peer_id):
			continue
		var state: PlayerState = states.get(e.peer_id)
		if state == null:
			state = PlayerState.new(e.peer_id, e.max_hp, PlayerBuild.new(catalog))
			states[e.peer_id] = state
		state.hp = e.hp
		state.max_hp = e.max_hp
		state.xp = e.xp
		state.level = e.level
		state.downed = e.downed
		state.choosing = e.choosing
		state.life = e.life
		state.pending_levels = e.pending_levels
		state.chests_opened = e.chests_opened
		if not state.build.mirror(e.weapons, e.passives, e.items, e.gold, e.rerolls, e.banishes, e.chests_opened):
			push_warning("World state names an item this build does not know.")
		var knodl: Knodl = knodls.get(e.peer_id)
		if knodl == null:
			knodl = _spawn_knodl(e.peer_id, players[e.peer_id], false)
			knodl.place_at(e.knodl_position)
		knodl.apply_remote(e.knodl_position, e.knodl_rotation, e.knodl_mass, e.knodl_state as Knodl.State, e.knodl_cooldown)
	# The host picked for us (co-op time ran out) and nothing else is waiting: close the menu.
	var local: PlayerState = states.get(NetworkManager.local_id())
	if local != null and not local.choosing and speisekarte.is_open() and speisekarte.open_seconds() > 1.0:
		speisekarte.close()
	_knodls_max = maxi(_knodls_max, knodls.size())


func _on_brosel(data: PackedByteArray) -> void:
	if NetworkManager.is_host():
		return
	_brosel_messages += 1
	if not BroselCodec.apply(data, brosel):
		_brosel_errors += 1


## Every role: a Speisekarte message for the local player.
func _on_offer(data: PackedByteArray) -> void:
	var offer: OfferCodec.Offer = OfferCodec.decode_offer(data)
	var state: PlayerState = states.get(NetworkManager.local_id())
	if offer == null or state == null or _finished:
		return
	_offers_received += 1
	match offer.type:
		OfferCodec.Type.OFFER:
			speisekarte.show_offer(offer, state.build)
			speisekarte.show_player(state, knodls.get(NetworkManager.local_id()))
			inventory.set_open(false)
			# Solo is the only time the game stops (GAME-DESIGN.md); co-op runs on.
			if NetworkManager.is_host() and NetworkManager.client_ids().is_empty():
				get_tree().paused = true
		OfferCodec.Type.CHEST:
			speisekarte.show_chest(offer)
		OfferCodec.Type.NOTICE:
			hud.toast(tr("NOTICE_%d" % offer.value))


## Host: a player's answer to their offer.
func _on_choice(peer_id: int, data: PackedByteArray) -> void:
	if level_flow == null:
		return
	level_flow.on_choice(peer_id, data, states.get(peer_id), not NetworkManager.client_ids().is_empty())
	if peer_id == NetworkManager.local_id() and not level_flow.is_open(peer_id) and get_tree().paused:
		get_tree().paused = false
		_resumed = true


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
	var speed: float = maxf(player.run_speed(), balance.player_speed)
	var allowed: float = speed * balance.player_max_speed_tolerance * maxf(elapsed, 0.05) + 1.0
	var moved: Vector3 = message.position - player.last_input.position
	moved.y = 0.0
	return moved.length() <= allowed


## Host: a new client gets every Brösel lying around once; changes follow at the snapshot rate.
## Co-op stops the solo pause and opens one more Wirtshaus per extra player.
func _on_peer_joined(peer_id: int) -> void:
	get_tree().paused = false
	_open_wirtshaeuser(balance.coop_wirtshaus_per_player, LaunchArgs.get_int("seed", 1) + peer_id)
	var all := PackedInt32Array()
	for i: int in brosel.capacity:
		if brosel.alive[i] != 0:
			all.append(i)
	if not all.is_empty():
		NetworkManager.send_brosel_to(peer_id, BroselCodec.encode(PackedInt32Array(), all, brosel))
	# Everything lying around (chests, coins, Stempel) for the new client.
	var lying := RunEventCodec.Queue.new()
	for slot: int in loot.all_slots():
		lying.loot(loot.ids[slot], loot.kinds[slot], loot.xs[slot], loot.zs[slot], loot.values[slot])
	var list: Array[RunEventCodec.Event] = lying.take()
	while not list.is_empty():
		NetworkManager.send_run_events_to(peer_id, RunEventCodec.encode(list.slice(0, RunEventCodec.MAX_EVENTS)))
		list = list.slice(RunEventCodec.MAX_EVENTS)


func _on_peer_left(peer_id: int) -> void:
	for nodes: Dictionary in [players, knodls, weapon_vfx]:
		var node: Node = nodes.get(peer_id)
		if node != null:
			nodes.erase(peer_id)
			node.queue_free()
	states.erase(peer_id)
	_last_pose_ms.erase(peer_id)
	_respawn_grace.erase(peer_id)
	if level_flow != null:
		level_flow.forget(peer_id)


## Client: the host told us our peer id; file the local player under it.
func _on_joined_host() -> void:
	var id: int = NetworkManager.local_id()
	if id == _local_key:
		return
	for nodes: Dictionary in [players, states, knodls, weapon_vfx]:
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
		var build := PlayerBuild.new(catalog, balance)
		build.add_start_weapon(character.start_weapon)
		states[peer_id] = PlayerState.new(peer_id, balance.player_max_hp, build)
		var knodl: Knodl = _spawn_knodl(peer_id, player, true)
		knodl.place_at(player.spawn_point + Vector3(0.0, 0.6, knodl.rest_length()))
	elif local:
		# The host's world state fills it in.
		states[peer_id] = PlayerState.new(peer_id, balance.player_max_hp, PlayerBuild.new(catalog))
	var vfx := WeaponVfx.new()
	vfx.setup(player)
	add_child(vfx)
	weapon_vfx[peer_id] = vfx
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


## Host: a loot item on the ground, announced to everyone.
func _drop_loot(kind: LootField.Kind, x: float, z: float, value: int) -> void:
	var half: float = map.half_size - 2.0
	x = clampf(x, -half, half)
	z = clampf(z, -half, half)
	var id: int = loot.add(kind, x, z, value)
	if id >= 0:
		events.loot(id, kind, x, z, value)


## Host: the run's map chests at random spots (GAME-DESIGN.md: random chest placement).
func _place_map_chests() -> void:
	var spots: Array[Vector2] = []
	spots.assign(map.chest_spots)
	for k: int in mini(balance.map_chest_count, spots.size()):
		var pick: int = _loot_rng.randi_range(0, spots.size() - 1)
		var rarity: int = CardDealer.roll_chest_rarity(balance, _loot_rng, 0.0, 0)
		_drop_loot(LootField.Kind.CHEST, spots[pick].x, spots[pick].y, LootField.chest_value(balance.map_chest_price, rarity))
		spots.remove_at(pick)


## Host: elites that started an attack this frame put their marks down.
func _start_attacks() -> void:
	for k: int in enemies.attack_slot.size():
		var slot: int = enemies.attack_slot[k]
		var attack: AttackData = types[enemies.type[slot]].attack
		if attack != null:
			hazards.start_attack(attack, enemies.pos_x[slot], enemies.pos_z[slot], enemies.attack_x[k], enemies.attack_z[k], slot)
	enemies.clear_attacks()


## Host: marks that hit this frame hurt the players inside (jumping over one dodges it), send
## dashers along their line and bring summons.
func _resolve_hazards() -> void:
	for h: HazardField.Hazard in hazards.hits:
		var attack: AttackData = h.attack
		if phase == Phase.RUNNING and not _god:
			for peer: int in players:
				var state: PlayerState = states[peer]
				if state.downed or state.choosing:
					continue
				var at: Vector3 = players[peer].global_position
				if at.y - ground.height_at(at.x, at.z) > balance.hazard_dodge_height:
					continue
				if HazardField.contains(h, at.x, at.z, balance.player_radius):
					if state.hurt(Formulas.hit_damage(attack.damage, state.build.stat(&"armor"), balance), balance):
						_on_downed(peer)
		if attack.dash and h.source >= 0:
			if bosses.is_boss_slot(h.source):
				bosses.on_hit(h)
			elif enemies.alive[h.source] != 0:
				enemies.start_dash(h.source, sin(h.angle), cos(h.angle), h.length / HazardField.DASH_SECONDS, HazardField.DASH_SECONDS)
		if attack.summon != null and attack.summon_count > 0:
			var t: int = types.find(attack.summon)
			for c: int in (attack.summon_count if t >= 0 else 0):
				enemies.spawn_at(t, h.x + _loot_rng.randf_range(-1.5, 1.5), h.z + _loot_rng.randf_range(-1.5, 1.5))


## Host: a boss fell: golden Kaiserschmarrn bits, coins and its chest where it stood.
func _on_bosses_beaten(beaten: Array[BossDirector.Active]) -> void:
	for boss: BossDirector.Active in beaten:
		var data: BossData = boss.data
		var x: float = boss.last_x
		var z: float = boss.last_z
		for k: int in data.golden_brosel:
			var angle: float = TAU * k / maxi(data.golden_brosel, 1)
			brosel.drop(x + cos(angle) * 2.0, z + sin(angle) * 2.0, balance.brosel_values[3], true)
		# A handful of heavy coins rather than dozens of single ones.
		var coins: int = clampi(data.gold, 0, BOSS_COINS)
		for k: int in coins:
			_drop_loot(LootField.Kind.COIN, x + _loot_rng.randf_range(-3.0, 3.0), z + _loot_rng.randf_range(-3.0, 3.0),
					floori(float(data.gold) / coins) + (1 if k < data.gold % coins else 0))
		var chest: int = data.chest_items | (LootField.EVOLUTION_BIT if data.chest_evolution else 0)
		var rarity: int = CardDealer.roll_chest_rarity(balance, _loot_rng, 0.0, balance.boss_chest_min_rarity)
		_drop_loot(LootField.Kind.BOSS_CHEST, x, z, LootField.chest_value(chest, rarity))
		events.boss(boss.index, RunEventCodec.BossState.BEATEN, boss.slot)
		if data.final:
			gate_flags |= WorldStateCodec.GATE_BOSS_BEATEN
		_bosses_beaten.append([String(data.id), snappedf(run_time, 0.1)])
		print("[RUN] boss beaten %s t=%.1f" % [data.id, run_time])


## Host: the run's timeline beyond the crowd (GAME-DESIGN.md "Run timeline"): mini-bosses, the
## Touristenbus, the Formular and the Hofrat behind the gate.
func _update_timeline(delta: float) -> void:
	if _bus_left > 0.0:
		_bus_left -= delta
		if _bus_left <= 0.0:
			enemies.spawn_sector_width = 0.0
	if phase != Phase.RUNNING or _forced_enemies > 0:
		return
	var minute: float = run_time / 60.0
	for k: int in wave.bosses.size():
		if not _bosses_started.has(k) and minute >= wave.bosses[k].minute:
			_bosses_started[k] = true
			_spawn_boss_near_players(k)
	if not _bus_done and minute >= wave.bus_minute:
		_start_bus()
	if wave.final_boss == null:
		return
	if gate_flags & WorldStateCodec.GATE_FORMULAR == 0 and minute >= wave.formular_minute:
		_start_formular()
	if gate_flags & WorldStateCodec.GATE_BOSS_OUT == 0:
		var mouth: Vector3 = gate.mouth()
		var entered: bool = false
		if gate_flags & WorldStateCodec.GATE_OPEN:
			for peer: int in players:
				var at: Vector3 = players[peer].global_position
				if not states[peer].downed and Vector2(at.x - mouth.x, at.z - mouth.z).length() < balance.portal_radius:
					entered = true
		var forced: bool = minute >= wave.final_boss_minute
		if entered or forced:
			gate_flags |= WorldStateCodec.GATE_BOSS_OUT
			if forced and not entered:
				events.toast("TOAST_HOFRAT_FORCED")
			_spawn_boss(_boss_list.size() - 1, mouth.x, mouth.z)


func _spawn_boss_near_players(index: int) -> void:
	var positions: PackedVector3Array = _player_positions()
	var centre: Vector3 = positions[_loot_rng.randi_range(0, positions.size() - 1)] if not positions.is_empty() else Vector3.ZERO
	var angle: float = _loot_rng.randf() * TAU
	var distance: float = _boss_list[index].arrive_distance
	var half: float = map.half_size - 15.0
	_spawn_boss(index, clampf(centre.x + cos(angle) * distance, -half, half), clampf(centre.z + sin(angle) * distance, -half, half))


func _spawn_boss(index: int, x: float, z: float) -> void:
	var boss: BossDirector.Active = bosses.spawn(index, x, z, players.size())
	if boss != null:
		events.boss(index, RunEventCodec.BossState.ARRIVED, boss.slot)
		print("[RUN] boss %s t=%.1f" % [boss.data.id, run_time])


## Host: the Formular appears; its Stempel lie at random spots of the map.
func _start_formular() -> void:
	gate_flags |= WorldStateCodec.GATE_FORMULAR
	var spots: Array[Vector2] = []
	spots.assign(map.stempel_spots)
	stempel_total = mini(balance.stempel_count, spots.size())
	for k: int in stempel_total:
		var pick: int = _loot_rng.randi_range(0, spots.size() - 1)
		_drop_loot(LootField.Kind.STEMPEL, spots[pick].x, spots[pick].y, k)
		spots.remove_at(pick)
	events.toast("TOAST_FORMULAR")
	if stempel_total == 0:
		_open_gate()


func _open_gate() -> void:
	gate_flags |= WorldStateCodec.GATE_OPEN
	events.toast("TOAST_GATE_OPEN")
	var mouth: Vector3 = gate.mouth()
	events.cue(RunEventCodec.Cue.GATE_OPEN, mouth.x, mouth.z)


## Host: the Touristenbus pulls up near a player and the crowd comes from its side for a while.
func _start_bus() -> void:
	_bus_done = true
	var positions: PackedVector3Array = _player_positions()
	if positions.is_empty():
		return
	_bus_left = wave.bus_seconds
	var centre: Vector3 = positions[_loot_rng.randi_range(0, positions.size() - 1)]
	var angle: float = _loot_rng.randf() * TAU
	enemies.spawn_sector_angle = angle
	enemies.spawn_sector_width = 0.9
	var half: float = map.half_size - 14.0
	var x: float = clampf(centre.x + cos(angle) * 24.0, -half, half)
	var z: float = clampf(centre.z + sin(angle) * 24.0, -half, half)
	events.bus(x, z, atan2(centre.x - x, centre.z - z))


## Host: players walking over loot: coins, Gulasch, Stempel, chests (map chests cost gold).
func _collect_loot(delta: float) -> void:
	for peer: int in _no_gold_timers.keys():
		_no_gold_timers[peer] -= delta
		if _no_gold_timers[peer] <= 0.0:
			_no_gold_timers.erase(peer)
	var reach: float = maxf(balance.chest_pickup_radius, balance.stempel_pickup_radius)
	for peer: int in players:
		var state: PlayerState = states[peer]
		if state.downed or state.choosing:
			continue
		var at: Vector3 = players[peer].global_position
		var reach_mult: float = 1.0 + state.build.stat(&"pickup")
		loot.attract(at.x, at.z, balance.coin_magnet_range * reach_mult, delta)
		for slot: int in loot.near(at.x, at.y, at.z, reach):
			if loot.alive[slot] == 0:
				continue
			var d: float = Vector2(loot.xs[slot] - at.x, loot.zs[slot] - at.z).length()
			match loot.kinds[slot]:
				LootField.Kind.COIN:
					if d < balance.coin_pickup_radius:
						state.build.add_gold(loot.values[slot])
						_take_loot(slot, peer)
				LootField.Kind.HEAL:
					if d < balance.coin_pickup_radius and state.hp < state.max_hp:
						state.heal(loot.values[slot])
						_take_loot(slot, peer)
				LootField.Kind.STEMPEL:
					if d < balance.stempel_pickup_radius:
						_take_loot(slot, peer)
						stempel_found += 1
						events.toast("TOAST_STEMPEL_%d" % mini(stempel_found, 3))
						if stempel_found >= stempel_total:
							_open_gate()
				LootField.Kind.CHEST:
					if d < balance.chest_pickup_radius:
						var price: int = _chest_price(slot, state)
						if state.build.gold >= price:
							# Zweitschlüssel vom Gemeindeamt: sometimes the chest is open anyway.
							if _loot_rng.randf() >= state.build.effect(&"free_chest"):
								state.build.gold -= price
							var rarity: int = LootField.chest_rarity(loot.values[slot])
							state.chests_opened += 1
							state.build.set_chests_opened(state.chests_opened)
							_take_loot(slot, peer)
							level_flow.give_chest(peer, state, CHEST_TIER_MAP, balance.map_chest_items, false, 0, rarity)
						elif not _no_gold_timers.has(peer):
							_no_gold_timers[peer] = NOTICE_INTERVAL
							level_flow.notify(peer, OfferCodec.Notice.NO_GOLD)
				LootField.Kind.BOSS_CHEST:
					if d < balance.chest_pickup_radius:
						var value: int = loot.values[slot]
						_take_loot(slot, peer)
						level_flow.give_chest(peer, state, CHEST_TIER_BOSS, value & 0xFF, (value & LootField.EVOLUTION_BIT) != 0, 0,
								LootField.chest_rarity(value))


## What a map chest costs this player: its base price, dearer for every chest they opened.
func _chest_price(slot: int, state: PlayerState) -> int:
	var opened: int = state.chests_opened if state != null else 0
	return LootField.chest_low(loot.values[slot]) + balance.map_chest_price_step * opened


func _take_loot(slot: int, peer: int) -> void:
	var id: int = loot.ids[slot]
	# The event is shown before the item goes (the sound needs to know what it was).
	events.taken(id, peer)
	_flush_events()
	loot.remove(id)


## Host: this frame's run events: shown here right away, sent to the clients with the next world
## state.
func _flush_events() -> void:
	for h: HazardField.Hazard in hazards.take_made():
		events.hazard(h)
	for key: String in bosses.take_toasts():
		events.toast(key)
	_update_focus()
	var batch: Array[RunEventCodec.Event] = events.take()
	for e: RunEventCodec.Event in batch:
		_present(e)
	if not NetworkManager.client_ids().is_empty():
		_outgoing.append_array(batch)


## Host: the boss in the HUD bar is the latest one still standing.
func _update_focus() -> void:
	_focus_boss = WorldStateCodec.NO_BOSS
	_focus_max_hp = 0.0
	if bosses.active.is_empty():
		return
	var boss: BossDirector.Active = bosses.active.back()
	_focus_boss = boss.index
	_focus_slot = boss.slot
	_focus_hp = maxf(enemies.hp[boss.slot], 0.0)
	_focus_max_hp = enemies.max_hp[boss.slot]


## Client: run events from the host.
func _on_run_events(data: PackedByteArray) -> void:
	if NetworkManager.is_host():
		return
	for e: RunEventCodec.Event in RunEventCodec.decode(data):
		_run_events_received += 1
		_present(e)
		match e.kind:
			RunEventCodec.Kind.HAZARD:
				hazards.add_remote(e.id, e.a, e.x, e.z, e.angle, e.radius, e.length, e.seconds)
				_hazards_seen += 1
			RunEventCodec.Kind.LOOT:
				loot.add_remote(e.id, e.a, e.x, e.z, e.b)
			RunEventCodec.Kind.TAKEN:
				loot.remove(e.id)


## Every role: the sound, toast or look of a run event.
func _present(e: RunEventCodec.Event) -> void:
	var local: Player = players.get(NetworkManager.local_id())
	match e.kind:
		RunEventCodec.Kind.HAZARD:
			if local != null and Vector2(e.x - local.global_position.x, e.z - local.global_position.z).length() < e.radius + e.length + 10.0:
				GameAudio.play(&"warn", Vector3(e.x, ground.height_at(e.x, e.z), e.z))
		RunEventCodec.Kind.TAKEN:
			var slot: int = loot.slot_of(e.id)
			if slot < 0:
				return
			var at: Vector3 = loot.position_of(slot)
			match loot.kinds[slot]:
				LootField.Kind.COIN:
					GameAudio.play(&"coin", at)
				LootField.Kind.HEAL:
					GameAudio.play(&"heal", at)
				LootField.Kind.STEMPEL:
					GameAudio.play(&"stempel", at)
				_:
					GameAudio.play(&"chest", at)
		RunEventCodec.Kind.TOAST:
			hud.toast(tr(e.text))
		RunEventCodec.Kind.BOSS:
			if e.a >= _boss_list.size():
				return
			var data: BossData = _boss_list[e.a]
			if e.c == RunEventCodec.BossState.ARRIVED:
				hud.toast(tr(data.intro_key))
				GameAudio.play(&"boss_arrive")
			else:
				hud.toast(tr(data.defeat_key))
				GameAudio.play(&"boss_beaten")
				GameAudio.bark(&"geh_bitte")
		RunEventCodec.Kind.BUS:
			if _bus != null:
				_bus.queue_free()
			_bus = TouristenBus.new()
			add_child(_bus)
			_bus.setup(Vector3(e.x, 0.0, e.z), e.angle, ground)
			hud.toast(tr("TOAST_BUS"))
			GameAudio.play(&"bus_horn", Vector3(e.x, ground.height_at(e.x, e.z), e.z))
		RunEventCodec.Kind.CUE:
			if e.a == RunEventCodec.Cue.GATE_OPEN:
				GameAudio.play(&"gate_open")


## Every role: the gate, the boss bar, the Formular line, markers, hints, music and the local
## player's sounds.
func _show_run_state(local: Player, state: PlayerState, delta: float) -> void:
	loot.draw(delta)
	var gate_state: PortalGate.State = PortalGate.State.SEALED
	if gate_flags & WorldStateCodec.GATE_BOSS_BEATEN:
		gate_state = PortalGate.State.DONE
	elif gate_flags & WorldStateCodec.GATE_BOSS_OUT:
		gate_state = PortalGate.State.BOSS_OUT
	elif gate_flags & WorldStateCodec.GATE_OPEN:
		gate_state = PortalGate.State.OPEN
	var gate_key: int = gate_state * 256 + stempel_found * 16 + stempel_total
	if gate_key != _gate_shown:
		_gate_shown = gate_key
		gate.set_state(gate_state, stempel_found, stempel_total)
	var boss_alive: bool = _focus_boss != WorldStateCodec.NO_BOSS and _focus_boss < _boss_list.size() and _focus_max_hp > 0.0
	hud.show_boss(tr(_boss_list[_focus_boss].name_key) if boss_alive else "", _focus_hp, _focus_max_hp if boss_alive else 0.0)
	var formular: String = ""
	if gate_flags & WorldStateCodec.GATE_BOSS_BEATEN:
		formular = tr("HUD_HOFRAT_BEATEN")
	elif gate_flags & WorldStateCodec.GATE_BOSS_OUT:
		formular = ""
	elif gate_flags & WorldStateCodec.GATE_OPEN:
		formular = tr("HUD_GATE_OPEN")
	elif gate_flags & WorldStateCodec.GATE_FORMULAR:
		formular = tr("HUD_FORMULAR") % [stempel_found, stempel_total]
	hud.show_formular(formular)
	hud.begin_markers()
	var from: Vector3 = local.global_position if local != null else Vector3.ZERO
	if phase == Phase.RUNNING:
		for slot: int in loot.capacity:
			if loot.alive[slot] != 0 and loot.kinds[slot] == LootField.Kind.STEMPEL:
				var at: Vector3 = loot.position_of(slot)
				hud.marker(camera, at + Vector3(0.0, 3.0, 0.0), tr("HUD_STEMPEL_MARKER") % roundi(from.distance_to(at)), "accent")
		if gate_flags & WorldStateCodec.GATE_OPEN and not gate_flags & WorldStateCodec.GATE_BOSS_OUT:
			var mouth: Vector3 = gate.mouth()
			hud.marker(camera, mouth + Vector3(0.0, 6.0, 0.0), tr("HUD_GATE_MARKER") % roundi(from.distance_to(mouth)), "rarity_1")
		if boss_alive:
			var boss_at: Vector3 = _boss_position()
			if boss_at.is_finite() and from.distance_to(boss_at) > 18.0:
				hud.marker(camera, boss_at + Vector3(0.0, 5.0, 0.0), "%s · %d m" % [tr(_boss_list[_focus_boss].name_key), roundi(from.distance_to(boss_at))], "danger")
	hud.end_markers()
	var hint: String = ""
	var chest: int = loot.nearest(LootField.Kind.CHEST, from.x, from.z)
	if chest >= 0 and Vector2(loot.xs[chest] - from.x, loot.zs[chest] - from.z).length() < 7.0:
		var price: int = _chest_price(chest, state)
		hint = tr("HINT_CHEST") % [price, state.build.gold if state != null and state.build != null else 0]
	hud.show_hint(hint)
	if state != null:
		hud.downed_key = "TOAST_DOWNED" if _respawn or players.size() > 1 else "TOAST_DOWNED_SOLO"
	# Sounds of the local player, from the state the host keeps.
	if state != null:
		if state.hp < _last_hp - 0.01 and not state.downed:
			GameAudio.play(&"hurt")
			if state.hp < state.max_hp * 0.3:
				GameAudio.bark(&"heast")
		if state.downed and not _was_downed:
			GameAudio.play(&"downed")
		if state.level > _sound_level and _sound_level > 0:
			GameAudio.play(&"level_up")
		elif state.xp > _last_xp + 0.01:
			GameAudio.play(&"brosel")
		_last_xp = state.xp
		_last_hp = state.hp
		_was_downed = state.downed
		_sound_level = state.level
	var knodl: Knodl = knodls.get(NetworkManager.local_id())
	if knodl != null:
		if knodl.state != _knodl_state_heard:
			if knodl.state == Knodl.State.THROWN:
				GameAudio.play(&"schupfn", knodl.global_position)
			elif knodl.state == Knodl.State.REELING:
				GameAudio.play(&"reel", knodl.global_position)
			_knodl_state_heard = knodl.state
		if knodl.hits > _knodl_hits_heard:
			GameAudio.play(&"knodl_hit", knodl.global_position)
		_knodl_hits_heard = knodl.hits
	for h: HazardField.Hazard in hazards.struck:
		GameAudio.play(&"slam", Vector3(h.x, ground.height_at(h.x, h.z), h.z))
	if local != null:
		GameAudio.set_listener(local.global_position)
	if phase == Phase.RUNNING:
		GameAudio.music(&"boss" if boss_alive else &"kirtag")
		if not boss_alive:
			GameAudio.set_music_speed(1.0 + 0.12 * clampf(run_time / balance.run_seconds, 0.0, 1.0))


## Where the boss in the HUD bar stands (host: its slot; client: its replica), or INF.
func _boss_position() -> Vector3:
	var x: float = 0.0
	var z: float = 0.0
	if enemies != null:
		if _focus_slot >= enemies.capacity or enemies.alive[_focus_slot] == 0:
			return Vector3.INF
		x = enemies.pos_x[_focus_slot]
		z = enemies.pos_z[_focus_slot]
	elif replica != null:
		if _focus_slot >= replica.capacity or replica.alive[_focus_slot] == 0:
			return Vector3.INF
		x = replica.x[_focus_slot]
		z = replica.z[_focus_slot]
	return Vector3(x, ground.height_at(x, z), z)


func _load_map(id: String) -> MapData:
	var path: String = MAP_DIR.path_join(id + ".tres")
	if not ResourceLoader.exists(path):
		push_warning("Unknown map '%s', playing the Kirtag." % id)
		path = MAP_DIR.path_join("kirtag.tres")
	return load(path) as MapData


func _load_character(id: String) -> CharacterData:
	var path: String = CHARACTER_DIR.path_join(id + ".tres")
	if not ResourceLoader.exists(path):
		push_warning("Unknown character '%s', playing Onkel Ferdl." % id)
		path = CHARACTER_DIR.path_join("ferdl.tres")
	return load(path) as CharacterData
