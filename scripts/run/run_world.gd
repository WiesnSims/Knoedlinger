class_name RunWorld
extends Node3D
## One run (M3: the Kirtag map with bosses, the gate and loot). Solo, host or client, from LaunchArgs:
##   --character=ferdl          who plays (data/characters/<id>.tres)
##   --grant=1                  Grant level (index into GameContent.grants; 1 = Normal)
##   --map=kirtag               which map (data/maps/<id>.tres; testfeld is the M1 test field)
##   --respawn=1                knocked down = back at the spawn after a few seconds instead of the
##                              run ending (the automated checks and the balance log)
##   --enemies=500              hold this many enemies (stress); without it the wave timeline runs
##   --seconds=60               measure for this long after warm-up, print [RESULT], quit (desktop)
##   --bot=0                    no bot; the player stands still until WASD
##   --god=1                    players take no damage
##   --weapons=a,b --items=c,d  extra start weapons and items (testing; locks and slots aside)
##   --knodl_mass=500           start every Knödl this heavy (tuning)
##   --start_time=880           start the clock here (test Sperrstund' or late waves)
##   --autoplay=1 --runs=3      balance log: the bot plays whole runs, stats go to build/balance/
##   --log_slow=1               print a [SLOW] line for every measured frame over 40 ms
##   --net=ws --host | --join=<ip>   WebSocket backend (NetworkManager)
## The host simulates everything that matters (enemies, every Knödl, Brösel, HP, XP, builds,
## Wirtshäuser, the clock) and sends it out; every player moves themselves. Solo is a host with
## zero clients; only solo pauses for the Speisekarte. Every second it prints a [STATS] line; the
## browser also gets window.knoedlStats / knoedlResult.

## RUNNING until Sperrstund' (balance.run_seconds), which settles the result; then the Nachspielzeit
## (SPERRSTUND): the Riesen-Wirt sweeps the crowd out, the Stammgast-Geister come faster and harder
## until everyone is down, and the run is ENDED. It also ends early when everyone is down.
enum Phase { RUNNING, SPERRSTUND, ENDED }
## How a run ended: WON = Sperrstund' with the Hofrat beaten, CLOSED = Sperrstund' without,
## LOST = everyone knocked down before Sperrstund'.
enum Result { NONE, WON, CLOSED, LOST }

const MAP_DIR: String = "res://data/maps"
const WAVE_PATH: String = "res://data/waves/kirtag.tres"
const CATALOG_PATH: String = "res://data/catalog/catalog.tres"
## What the Riesen-Wirt says as he comes for Sperrstund' (he is no enemy, so not in the wave).
const RIESEN_WIRT_VOICE: String = "res://data/voice_lines/riesen_wirt.tres"
const CHARACTER_DIR: String = "res://data/characters"
## Clients size their arrays for any host crowd up to this.
const CLIENT_SLOTS: int = 1024
const MAX_PLAYERS: int = 4
const WARMUP_SECONDS: float = 3.0
## Map chests show their price over them up to this far away (and only while on screen).
const CHEST_PRICE_REACH: float = 45.0
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
## The local player's Knödlinger; everyone's is in _characters (each player picks their own).
var character: CharacterData
var _characters: Dictionary[int, CharacterData] = {}
var content: GameContent
## The Grant level of this run (difficulty) and its index.
var grant: GrantData
var grant_index: int = 1
var types: Array[EnemyTypeData] = []
var terrain: Heightfield
var ground: Heightfield
var enemies: EnemyManager
var replica: EnemyReplica
var slime: SlimeTrail
var renderer: EnemyRenderer
var brosel: BroselField
## Host: the real shots; client: shots shown from the players' fire counters.
var projectiles: ProjectilePool
var players: Dictionary[int, Player] = {}
var states: Dictionary[int, PlayerState] = {}
var knodls: Dictionary[int, Knodl] = {}
## Doppelportion: each holder's second, smaller Knödl (it eats and crushes for its player; the mass
## goes to the main Knödl, Bröselfresser leave it alone).
var seconds: Dictionary[int, Knodl] = {}
var weapon_vfx: Dictionary[int, WeaponVfx] = {}
var wirtshaeuser: Array[Wirtshaus] = []
var hazards: HazardField
## Die Hausmeisterin's locked stairs (every role).
var stairs: StairLock
## Talking enemies: the host picks the lines, every role shows them.
var voices: EnemyVoices
var loot: LootField
var gate: PortalGate
## Host: the bosses of the run.
var bosses: BossDirector
## Host: revives, shared XP, Knödl-Pass, Riesenknödl, Familienstreit (CoopRules).
var coop: CoopRules
## Der Standler and the Marterl (1.4): host logic, and their look on every machine.
var sites: RunSites
## Host: the items' rules (1.4, ItemProcs).
var procs: ItemProcs
## Every machine: damage per player and source (1.4 build view; the host sends DAMAGE events).
var ledger := DamageLedger.new()
var _ledger_timer: float = 0.0
var _ledger_sent: Dictionary[String, Vector2] = {}
## The bot went to Der Standler's stall on this visit (RunSites.stand_visits).
var _bot_shopped: int = 0
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
var quality: QualityScaler
var touch: TouchControls
var _riesen_seen: bool = false
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
## Client: the host's end-of-run numbers for us (kills, bosses, knock-downs ...), merged into the summary.
var _host_summary: Dictionary = {}
## The most draw calls of a frame this second and what was up then (the [STATS] line).
var _draws_peak: int = 0
var _draws_peak_what: String = ""
## Most Doppelportion Knödl a client showed at once.
var _seconds_max: int = 0
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
## Host: Wirtshaus spots that have served Steffi a second time.
var _second_serves: Dictionary[int, bool] = {}
var _weapon_rng := RandomNumberGenerator.new()
var _riesen_wirt: Node3D
## The first frame after a solo pause carries the paused time; it is left out of the frame stats.
var _resumed: bool = false
## Solo without the bot: nothing runs until the player first moves (_start_held).
var _start_hold: bool = false
## The Tab screen or the pause menu holds the solo pause (not the Speisekarte).
var _panel_paused: bool = false
## The pointer was captured last frame (the browser lets go of it on Esc without telling the game).
var _was_captured: bool = false
## The Speisekarte or the Tab screen opened while the mouse looked; the pointer is taken back when
## the panel is gone.
var _panel_had_mouse: bool = false
## Shown until ShaderWarmup is through (not in headless runs).
var _loading: LoadingScreen
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
## Host: seconds until the next Fassl may stand up.
var _fassl_timer: float = 0.0
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
var _voice_lines_received: int = 0
var _gate_shown: int = -1
var _last_hp: float = 0.0
var _was_downed: bool = false
var _sound_level: int = 0
var _last_xp: float = 0.0
var _knodl_state_heard: int = 0
var _knodl_hits_heard: int = 0
## Host: enemies beaten per type id (quests, Almanach).
var _kills_by_type: Dictionary[StringName, int] = {}
## Host: the Stammtisch bonus each player brings (the local one from the Profile; clients send
## theirs with the co-op lobby in M6).
var _meta: Dictionary[int, Dictionary] = {}
## What the Profile paid for this run (shown on the end screen); recorded once.
var _reward: Dictionary = {}
var _recorded: bool = false
var _wind_angle: float = 0.0
## Host: the Kontrolleur standing at each Wirtshaus (spot -> enemy slot), once they came.
var _guards: Dictionary[int, int] = {}
var _guards_sent: bool = false
## Host: trait clocks per player (free banish, coffee break) and the jumps already counted.
var _trait_timers: Dictionary[int, Dictionary] = {}
var _jumps_seen: Dictionary[int, int] = {}
## Shockwave rings (Kevin's jumps, items): a few reused ones, their materials and ages.
var _shockwaves: Array[MeshInstance3D] = []
var _shockwave_materials: Array[ShaderMaterial] = []
var _shockwave_times: PackedFloat32Array = PackedFloat32Array()
var _shockwave_next: int = 0
var _shockwave_sizes: PackedFloat32Array = PackedFloat32Array()
## Host: each Knödl's state last frame (a Schupfn ending sets off the Powidl), the bell clocks.
var _knodl_state_last: Dictionary[int, int] = {}
var _bell_timers: Dictionary[int, float] = {}
## Host: enemy types whose arrive_toast was shown this run.
var _arrived: Dictionary[int, bool] = {}
## Run-Abrechnung (1.4 task 5.4), host: damage source id -> [peer, kind, id]; kind is "weapon" (id =
## weapon id), "knodl" or "extra" (items, traits, reflects). EnemyManager counts per id.
var _sources: Array = []
var _source_ids: Dictionary[String, int] = {}
const SHOCKWAVES: int = 16
const SHOCKWAVE_SECONDS: float = 0.4


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
	# `daily=1`: today's Tageskarte straight from the command line or URL (tests).
	if LaunchArgs.get_flag("daily", false) and RunSetup.daily == "" and not RunSetup.from_room:
		RunSetup.use_daily(GameContent.load_default(), balance, Daily.today())
	map = _load_map(RunSetup.map_id())
	wave = map.wave if map.wave != null else load(WAVE_PATH)
	catalog = load(CATALOG_PATH)
	UiStyle.build_icon_atlas(catalog)
	character = _load_character(RunSetup.character_id())
	content = GameContent.load_default()
	grant_index = clampi(RunSetup.grant_index(), 0, content.grants.size() - 1)
	grant = content.grants[grant_index]
	types = wave.enemies
	run_time = maxf(LaunchArgs.get_float("start_time", 0.0), 0.0)
	var seed_value: int = LaunchArgs.get_int("seed", RunSetup.seed if RunSetup.seed > 0 else 1) + _autoplay_run * 7919
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
	quality = QualityScaler.new()
	quality.name = "QualityScaler"
	add_child(quality)
	quality.setup(balance, get_node_or_null(^"Sun") as DirectionalLight3D)
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
	slime = SlimeTrail.new()
	slime.name = "SlimeTrail"
	add_child(slime)
	slime.setup(types, ground, balance)
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
	stairs = StairLock.new()
	add_child(stairs)
	stairs.setup(map, balance)
	voices = EnemyVoices.new()
	voices.name = "EnemyVoices"
	add_child(voices)
	voices.setup(balance, types, ground, events, seed_value)
	loot = LootField.new()
	loot.name = "Loot"
	add_child(loot)
	loot.setup(ground)
	gate = PortalGate.new()
	add_child(gate)
	gate.setup(map, ground)
	sites = RunSites.new(self, balance, seed_value)
	procs = ItemProcs.new(self, balance, seed_value)
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
		return speisekarte.is_shown() or inventory.is_open() or end_screen.visible or pause.is_open() or _loading != null
	touch = TouchControls.new()
	touch.name = "TouchControls"
	touch.camera = camera
	touch.covered = hud.covered
	touch.layout_changed.connect(hud.set_touch_layout)
	add_child(touch)
	if host:
		enemies = EnemyManager.new(balance, types, slots, seed_value, ground, map.half_size)
		enemies.brosel = brosel
		voices.enemies = enemies
		enemies.ring_min = balance.spawn_first_ring_min
		enemies.ring_max = balance.spawn_first_ring_max
		enemies.ring_ahead = balance.spawn_ring_ahead
		_start_hold = not NetworkManager.is_online() and not _bot and _forced_enemies == 0 and _seconds <= 0.0
		enemies.speed_mult = grant.enemy_speed
		_update_wave()
		if _forced_enemies > 0:
			enemies.populate(_forced_enemies, _player_positions())
		else:
			enemies.respawn_delay = balance.spawn_respawn_delay
			enemies.target_count = balance.spawn_start_count
		level_flow = LevelUpFlow.new(balance, seed_value)
		# Grant "Streik": one Wirtshaus stays shut.
		_open_wirtshaeuser(balance.wirtshaus_count - (1 if grant.modifier == &"streik" else 0), seed_value)
		_scatter_start_brosel(seed_value)
		bosses = BossDirector.new(balance, enemies, hazards, wave)
		bosses.brosel = brosel
		bosses.stairs = stairs
		coop = CoopRules.new(self, balance, seed_value)
		_place_map_chests()
		sites.place_marterl()
		level_flow.bought.connect(sites.on_bought)
		level_flow.shop_closed.connect(sites.on_shop_closed)
	else:
		replica = EnemyReplica.new(balance, types, slots)
		voices.replica = replica
	NetworkManager.snapshot_received.connect(_on_snapshot)
	NetworkManager.events_received.connect(_on_events)
	NetworkManager.player_input_received.connect(_on_player_input)
	NetworkManager.world_state_received.connect(_on_world_state)
	NetworkManager.brosel_received.connect(_on_brosel)
	NetworkManager.run_events_received.connect(_on_run_events)
	NetworkManager.offer_received.connect(_on_offer)
	NetworkManager.choice_received.connect(_on_choice)
	NetworkManager.peer_run_ready.connect(_on_peer_joined)
	NetworkManager.peer_left.connect(_on_peer_left)
	NetworkManager.joined_host.connect(_on_joined_host)
	NetworkManager.join_failed.connect(_on_join_failed)
	NetworkManager.session_ended.connect(_on_session_ended)
	NetworkManager.run_summary_received.connect(func(data: Dictionary) -> void: _host_summary = data)
	DebugOverlay.visible = LaunchArgs.get_flag("debug", _bot and not _autoplay)
	# The browser builds the run's shaders behind the loading screen; a solo run waits for it.
	if DisplayServer.get_name() != "headless":
		_loading = LoadingScreen.new()
		add_child(_loading)
		var warmup: ShaderWarmup = ShaderWarmup.start(self, camera)
		warmup.progressed.connect(_loading.set_progress)
		warmup.finished.connect(_on_warmed)
		# Compiling shaders is slow on purpose: Automatisch must not read it as a weak device.
		quality.hold = true
		# No Tab screen or pause menu under the loading screen (RunWorld allows them again per frame).
		pause.allowed = false
		inventory.allowed = false
		if host and not NetworkManager.is_coop():
			get_tree().paused = true
	GameAudio.music(map.music if map != null else &"kirtag")
	GameAudio.bark(&"servas")
	# Die Ehrentafel: a ticket for this run (only real runs from the menu; Board decides).
	# The Tageskarte: only the day's first try gets a ticket (a restart is practice).
	if host:
		if RunSetup.daily == "":
			Board.start_run("coop" if NetworkManager.is_online() else "solo", String(map.id))
		elif RunSetup.daily_counts:
			Board.start_run("daily", Daily.board_map(RunSetup.daily))
		else:
			Board.forget()
		RunSetup.daily_counts = false
		Board.ranked.connect(_on_ranked)
	print("[RUN] role=%s map=%s character=%s enemies=%s seconds=%s bot=%s bake_ms=%d adapter=%s" % [
		_role(), map.id, character.id, _forced_enemies if _forced_enemies > 0 else "wave", _seconds, _bot,
		_bake_ms, RenderingServer.get_video_adapter_name()])
	WebPage.loaded()
	# A client from the co-op room: our scene is up, the host may send the world now.
	if not host:
		NetworkManager.send_run_ready()


func _on_warmed() -> void:
	_loading.finish()
	_loading = null
	quality.hold = false
	if NetworkManager.is_host() and not NetworkManager.is_coop() and not speisekarte.is_open() \
			and not _panel_paused:
		get_tree().paused = false
	_resumed = true


func _exit_tree() -> void:
	# A solo Speisekarte may still hold the pause when the scene goes, the Nachspielzeit's end its
	# slow motion.
	get_tree().paused = false
	Engine.time_scale = 1.0
	if Board.ranked.is_connected(_on_ranked):
		Board.ranked.disconnect(_on_ranked)


func _on_ranked(rank: int, week_rank: int, _id: int) -> void:
	end_screen.show_rank(rank, week_rank, RunSetup.daily != "")


func _process(delta: float) -> void:
	if _finished:
		return
	delta = minf(delta, 0.1)
	var was_measuring: bool = stats.is_measuring()
	if _resumed:
		_resumed = false
	elif _loading == null:
		# Co-op runs on behind the loading screen (no pause): shader compiling is not measured.
		stats.add_frame(delta)
		if _log_slow and delta > 0.04 and stats.is_measuring():
			print("[SLOW] run %.1f s: %.0f ms, weapons %s, menu %s" % [run_time, delta * 1000.0,
					Hud.build_text(states[NetworkManager.local_id()].build).replace("
", " / "), speisekarte.is_open()])
	if stats.is_measuring() and not was_measuring:
		_bytes_sent_start = NetworkManager.bytes_sent
		_bytes_received_start = NetworkManager.bytes_received
		_clients_at_measure = NetworkManager.client_ids().size()
		if replica != null:
			replica.reset_counters()
	if enemies != null:
		_host_frame(delta)
	elif replica != null:
		_client_frame(delta)
	_local_frame(delta)
	_send_pose(delta)
	var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	if draws > _draws_peak:
		_draws_peak = draws
		_draws_peak_what = "menu" if speisekarte.is_shown() else ("chest" if speisekarte._chest_panel.visible else "game")
	_report(delta)
	if _seconds > 0.0 and stats.measured_seconds() >= _seconds:
		_finish()


## Where a player is going, for the spawn ring: the way they run, or the way they face standing.
func _heading(player: Player) -> Vector2:
	var moving := Vector2(player.motion_velocity.x, player.motion_velocity.z)
	if moving.length() > balance.spawn_heading_min_speed:
		return moving.normalized()
	var facing: Vector3 = player.facing_direction()
	return Vector2(facing.x, facing.z)


## Solo: the clock, the spawns and the crowd wait for the player's first step (or jump, or Schupfn),
## so a run never starts behind their back while they find the keys.
func _start_held() -> bool:
	if not _start_hold:
		return false
	if Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down").length_squared() > 0.0 			or Input.is_action_pressed(&"jump") or Input.is_action_pressed(&"schupfn"):
		_start_hold = false
	return _start_hold


func _host_frame(delta: float) -> void:
	if _start_held():
		# The family's crumbs lie there already; the key hints wait with the run.
		brosel.draw()
		hud.hold_intro()
		return
	if phase != Phase.ENDED:
		run_time += delta
	_wave_timer -= delta
	if _wave_timer <= 0.0:
		_wave_timer = 1.0
		_update_wave()
	if _forced_enemies == 0 and phase != Phase.ENDED:
		var ramp: float = (balance.spawn_start_count + balance.spawn_count_per_minute * run_time / 60.0) \
				* Formulas.early_ease(run_time, balance.spawn_ease_count, balance)
		# Nachspielzeit: the Stammgast-Geister come in a crowd of their own.
		if phase == Phase.SPERRSTUND:
			ramp = balance.overtime_start_count + balance.overtime_count_per_minute * overtime_seconds() / 60.0
		ramp *= 1.0 + balance.coop_count_per_player * (players.size() - 1)
		var cap: int = ceili(balance.spawn_max_count * (1.0 + balance.coop_count_per_player * (players.size() - 1)))
		if _bus_left > 0.0:
			ramp += wave.bus_extra
			cap += wave.bus_extra
		# Marterl "Gier": twice the crowd for a while.
		ramp *= sites.crowd_mult()
		cap = ceili(cap * sites.crowd_mult())
		var thin: float = quality.enemy_factor(players.size() == 1)
		ramp *= thin
		cap = ceili(cap * thin)
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
	enemies.target_heading.resize(peers.size())
	for k: int in peers.size():
		enemies.target_heading[k] = _heading(players[peers[k]])
	var knodl_peers: Array[int] = []
	var knodl_targets := PackedVector4Array()
	enemies.knodl_sweet.clear()
	for peer: int in knodls:
		if states[peer].build.stat(&"knodl_guard") <= 0.0 and not knodls[peer].merged_away:
			var at: Vector3 = knodls[peer].global_position
			knodl_peers.append(peer)
			knodl_targets.append(Vector4(at.x, at.y, at.z, knodls[peer].radius))
			enemies.knodl_sweet.append(1 if knodls[peer].sort.sweet else 0)
	var t0: int = Time.get_ticks_usec()
	enemies.pace = overtime_pace()
	enemies.update(delta, targets, knodl_targets)
	_alive_held = enemies.alive_count
	_start_attacks()
	_on_bosses_beaten(bosses.update(delta, targets, phase == Phase.RUNNING))
	bosses.touch_damage(targets, enemies.touch_damage)
	var boss_slots := PackedInt32Array()
	for boss: BossDirector.Active in bosses.active:
		boss_slots.append(boss.slot)
	voices.host_update(delta, targets, boss_slots)
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
			voices.offer_bite(knodls[knodl_peers[k]].global_position, knodls[knodl_peers[k]].radius)
	var damage_mult: float = grant.enemy_damage * Formulas.early_ease(run_time, balance.spawn_ease_damage, balance) \
			* (1.0 + balance.overtime_damage_per_step * _overtime_steps())
	for t: int in peers.size():
		var state: PlayerState = states[peers[t]]
		var hit: float = Formulas.hit_damage(enemies.touch_damage[t] * damage_mult, state.build.stat(&"armor"), balance)
		if enemies.touch_type[t] >= 0:
			state.last_cause = types[enemies.touch_type[t]].id
		var hp_before: float = state.hp
		if not _god and phase != Phase.ENDED and state.hurt(hit, balance):
			on_downed(peers[t])
		if state.hp < hp_before:
			_on_hurt(peers[t])
			_reflect_hit(peers[t], hp_before - state.hp)
			procs.on_hurt(peers[t], hp_before - state.hp)
	procs.tick(delta)
	procs.prepare(delta)
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
			# Co-op: Schupfn in a Riesenknödl lets go; a throw toward a teammate is a pass.
			if not state.downed and not state.choosing and not coop.schupfn_splits(peer) and not knodl.merged_away:
				var aim: Array = coop.pass_aim(peer, player.last_input.throw_direction())
				if knodl.schupfn(aim[0]) and knodl.state == Knodl.State.THROWN:
					knodl.pass_target = aim[1]
					if aim[1] != 0:
						print("[RUN] pass-throw peer=%d to=%d t=%.1f" % [peer, aim[1], run_time])
		if not state.downed and not state.choosing:
			for owned: PlayerBuild.OwnedWeapon in state.build.weapons:
				if owned.source < 0:
					owned.source = _source(peer, "weapon", String(owned.data.id))
			WeaponSystem.update(state.build, player, enemies, projectiles, run_time, delta, _weapon_rng, balance)
			enemies.source = -1
			projectiles.source = -1
		knodl.damage_source = _source(peer, "knodl", "knodl")
		# Knödl folgt brav (the player's setting rides in their input): toward the nearest Brösel in reach.
		knodl.follow_target = Vector3.INF
		if player.last_input.buttons & InputMessage.BUTTON_FOLLOW and not state.downed:
			var at: Vector3 = player.global_position
			var crumb: Vector2 = brosel.nearest(at.x, at.z, knodl.max_length())
			if crumb.is_finite():
				knodl.follow_target = Vector3(crumb.x, 0.0, crumb.y)
		if not knodl.merged_away:
			knodl.crush(enemies, delta)
		if seconds.has(peer):
			seconds[peer].damage_source = knodl.damage_source
			seconds[peer].crush(enemies, delta)
	projectiles.update(delta, enemies)
	procs.after_hits()
	hazards.update(delta)
	stairs.update(delta)
	_resolve_hazards()
	var wind := Vector3.ZERO
	if grant.modifier == &"foehn":
		_wind_angle += delta * 0.07
		var gust: float = balance.foehn_force * (0.55 + 0.45 * sin(run_time * 0.5))
		wind = Vector3(cos(_wind_angle), 0.0, sin(_wind_angle)) * gust
	# Der Sturm pulls every Knödl that is not too heavy toward it.
	for peer: int in knodls:
		var knodl: Knodl = knodls[peer]
		knodl.wind = wind + (Vector3.ZERO if knodl.sort.heavy else bosses.pull_on(knodl.global_position))
	var t2: int = Time.get_ticks_usec()
	stats.add_system("knodl_weapons", t2 - t1)
	_update_traits(delta)
	_update_item_effects(delta)
	_send_guards()
	procs.on_kills()
	_kill_blasts()
	_drop_brosel()
	_feed_knodls(delta)
	_check_wirtshaeuser(delta)
	_collect_loot(delta)
	_update_fassl(delta)
	_send_damage(delta)
	level_flow.update(states, delta, NetworkManager.is_coop())
	coop.update(delta)
	sites.update(delta)
	for peer: int in states:
		states[peer].merge_partner = coop.merge_partner(peer)
	_update_timeline(delta)
	_update_phase(delta)
	_flush_events()
	var t3: int = Time.get_ticks_usec()
	stats.add_system("brosel", t3 - t2)
	_update_air_targets()
	renderer.draw(enemies.capacity, enemies.alive, enemies.pos_x, enemies.pos_z, enemies.yaw, enemies.type,
			enemies.radius, enemies.flash, enemies.phase, enemies.statuses())
	slime.update(delta, enemies.capacity, enemies.alive, enemies.pos_x, enemies.pos_z, enemies.type)
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
	# Grant "Kontrolle": elites (enemies with an attack of their own) come twice as often.
	if grant.modifier == &"kontrolle":
		for t: int in mini(enemies.type_weights.size(), types.size()):
			if types[t].attack != null and not types[t].boss:
				enemies.type_weights[t] *= balance.kontrolle_elite_mult
	enemies.hp_mult = (1.0 + balance.spawn_hp_per_minute * run_time / 60.0) \
			* (1.0 + balance.coop_hp_per_player * maxi(players.size() - 1, 0)) * grant.enemy_hp * wave.enemy_hp \
			* Formulas.early_ease(run_time, balance.spawn_ease_hp, balance) \
			* (1.0 + balance.overtime_hp_per_step * _overtime_steps())
	# A type that announces itself (the grantige Stammgast-Geist) does so once it joins the mix.
	for t: int in mini(enemies.type_weights.size(), types.size()):
		if enemies.type_weights[t] > 0.0 and types[t].arrive_toast != "" and not _arrived.has(t):
			_arrived[t] = true
			events.toast(types[t].arrive_toast)


## Seconds past Sperrstund' (0 before it, and for a run lost before it).
func overtime_seconds() -> float:
	if result == Result.LOST:
		return 0.0
	return maxf(run_time - balance.run_seconds, 0.0)


## Whole overtime_step_seconds steps of Nachspielzeit so far: every step hurries the crowd on.
func _overtime_steps() -> int:
	if phase == Phase.RUNNING:
		return 0
	return floori(overtime_seconds() / maxf(balance.overtime_step_seconds, 0.01))


## How much faster than normal every enemy moves right now (1 before Sperrstund').
func overtime_pace() -> float:
	return minf(1.0 + balance.overtime_pace_per_step * _overtime_steps(), balance.overtime_pace_max)


## Host: Sperrstund' at 15:00 settles the result (won with the Hofrat beaten). Then the Nachspielzeit:
## the Riesen-Wirt sweeps the Kirtag crowd out while the Stammgast-Geister come (the wave's entries
## past minute 15), faster and harder every step, until the last player is down.
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
				result = Result.WON if gate_flags & WorldStateCodec.GATE_BOSS_BEATEN else Result.CLOSED
				_set_phase(Phase.SPERRSTUND)
		Phase.SPERRSTUND:
			_phase_timer += delta
			if fmod(_phase_timer, 0.5) < delta:
				_send_guests_home()
			if _riesen_wirt != null:
				var at: Vector3 = _riesen_wirt.global_position
				var found: int = enemies.grid.query(at.x, at.z, RIESEN_WIRT_SWEEP)
				for k: int in found:
					var slot: int = enemies.grid.results[k]
					# Bosses stay (a swept boss is not a beaten boss), and so do the Stammgast-Geister.
					if enemies.controlled[slot] == 0 and not types[enemies.type[slot]].stays_at_sperrstund:
						enemies.despawn(slot)
			if _lose_timer >= 0.0:
				# The last one fell: the slow motion runs in real seconds.
				_lose_timer -= delta / maxf(Engine.time_scale, 0.01)
				if _lose_timer < 0.0:
					_set_phase(Phase.ENDED)
			elif overtime_seconds() >= balance.overtime_max_seconds:
				_set_phase(Phase.ENDED)


## Host, Nachspielzeit: the Kirtag crowd goes home out of sight (no drops, no kill), so their slots
## fill with Stammgast-Geister. Those close by stay until beaten or swept by the Riesen-Wirt.
func _send_guests_home() -> void:
	var positions: PackedVector3Array = _player_positions()
	var reach_sq: float = balance.overtime_leave_distance * balance.overtime_leave_distance
	for i: int in enemies.capacity:
		if enemies.alive[i] == 0 or enemies.controlled[i] != 0 or types[enemies.type[i]].stays_at_sperrstund:
			continue
		var near: bool = false
		for at: Vector3 in positions:
			var dx: float = enemies.pos_x[i] - at.x
			var dz: float = enemies.pos_z[i] - at.z
			if dx * dx + dz * dz < reach_sq:
				near = true
				break
		if not near:
			enemies.despawn(i)


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
			stairs.release()
		Phase.ENDED:
			Engine.time_scale = 1.0
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
	voices.say_local(load(RIESEN_WIRT_VOICE) as VoiceLineSet, VoiceLineData.Moment.ARRIVE, _riesen_wirt, 3.5 * 2.2)


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
	# Host: every client gets what only the host counted, before its end screen and Profile.
	if NetworkManager.is_host():
		for peer: int in NetworkManager.client_ids():
			NetworkManager.send_run_summary(peer, _shared_summary(peer))
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
	_record_profile(Result.keys()[result])
	# Co-op from the room: the host takes everyone back to the Stammtisch, the others may leave.
	var room: bool = Lobby.is_active()
	if room:
		end_screen.set_button_labels("END_AGAIN_COOP", "COOP_LEAVE")
	end_screen.show_result(_run_summary(), not NetworkManager.is_online() or (room and NetworkManager.is_host()),
			local_state.build if local_state != null else null, balance, _reward)


## Solo: the Tab screen pauses the game like the Speisekarte does; co-op runs on.
func _on_inventory_toggled(open: bool) -> void:
	if open:
		_note_panel_mouse()
		inventory.show_player(states.get(NetworkManager.local_id()), knodls.get(NetworkManager.local_id()), balance,
				ledger, NetworkManager.local_id(), run_time)
	_hold_pause(open)


## A panel that frees the pointer opens: remember to take it back (in the browser the release is
## not seen at once, so last frame's state counts too).
func _note_panel_mouse() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or _was_captured:
		_panel_had_mouse = true


func _on_pause_toggled(open: bool) -> void:
	if open:
		pause.show_player(states.get(NetworkManager.local_id()), knodls.get(NetworkManager.local_id()), balance,
				ledger, NetworkManager.local_id(), run_time)
	_hold_pause(open)


## Solo: a full-screen panel (Tab screen, pause menu) stops the game while it is open.
func _hold_pause(open: bool) -> void:
	if open:
		speisekarte.hide_chest()
		if NetworkManager.is_host() and not NetworkManager.is_coop() and not get_tree().paused:
			get_tree().paused = true
			_panel_paused = true
	elif _panel_paused and not inventory.is_open() and not pause.is_open():
		_panel_paused = false
		if not speisekarte.is_open():
			get_tree().paused = false
			_resumed = true


## Pause menu "Zum Menü" or the end screen: leave the run for the title screen.
func _quit_to_menu() -> void:
	_record_leaving()
	_finished = true
	get_tree().paused = false
	Engine.time_scale = 1.0
	if Lobby.is_active():
		Lobby.leave()
	elif NetworkManager.is_online():
		NetworkManager.leave()
	get_tree().change_scene_to_file.call_deferred("res://scenes/menu/main_menu.tscn")


## Leaving before the end still pays what the run made so far (like being knocked out); leaving in
## the Nachspielzeit keeps the result Sperrstund' settled.
func _record_leaving() -> void:
	if phase == Phase.RUNNING:
		result = Result.LOST
		_record_profile("QUIT")
	elif phase == Phase.SPERRSTUND:
		_record_profile(Result.keys()[result])


func _restart() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	if Lobby.is_active():
		# Co-op: everyone back to the room (the Lobby changes the scene).
		Lobby.back_to_room()
		return
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
## From Sperrstund' on every Wirt is shut (so nobody is woken up in the Nachspielzeit either).
func _check_wirtshaeuser(delta: float) -> void:
	if phase != Phase.RUNNING:
		return
	for peer: int in _notice_timers.keys():
		_notice_timers[peer] -= delta
		if _notice_timers[peer] <= 0.0:
			_notice_timers.erase(peer)
	for peer: int in knodls:
		var state: PlayerState = states[peer]
		var knodl: Knodl = knodls[peer]
		if state.downed or knodl.merged_away:
			continue
		for wirt: Wirtshaus in wirtshaeuser:
			if not wirt.open or not _serves(wirt, peer) or not wirt.touches(knodl.global_position, knodl.radius, balance.wirtshaus_door_radius):
				continue
			if _guarded(wirt):
				if not _notice_timers.has(peer):
					_notice_timers[peer] = NOTICE_INTERVAL
					level_flow.notify(peer, OfferCodec.Notice.KONTROLLE)
				continue
			var tier: int = Formulas.wirtshaus_tier(knodl.knodl_mass, balance)
			if tier < 0:
				if not _notice_timers.has(peer):
					_notice_timers[peer] = NOTICE_INTERVAL
					level_flow.notify(peer, OfferCodec.Notice.TOO_SMALL)
				continue
			_cash_in(peer, wirt, tier)
			break


## Host: whether this Wirtshaus still serves this player. Each serves once per run; one that has
## served already serves Steffi once more ("Ausg'steckt", trait_effects[&"serves_twice"]).
func _serves(wirt: Wirtshaus, peer: int) -> bool:
	if not wirt.served:
		return true
	return character_of(peer).trait_effects.has(&"serves_twice") and not _second_serves.has(wirt.spot)


func _cash_in(peer: int, wirt: Wirtshaus, tier: int) -> void:
	var state: PlayerState = states[peer]
	var knodl: Knodl = knodls[peer]
	if wirt.served:
		_second_serves[wirt.spot] = true
	wirt.set_state(true, true, tier)
	state.cash_ins[tier] += 1
	procs.on_cashin(peer)
	var gold: int = roundi(knodl.knodl_mass * balance.wirtshaus_gold_per_mass) if tier == 0 else 0
	if tier == 2:
		state.build.rerolls += balance.wirtshaus_l_rerolls
	var items: int = balance.wirtshaus_chest_items[tier] if tier < balance.wirtshaus_chest_items.size() else 0
	level_flow.give_chest(peer, state, tier, items, tier == 3, gold, -1, balance.boss_chest_min_rarity if tier == 3 else 0)
	# Gemeinsam einkehren: a merged Riesenknödl pays every player in it.
	var merge: CoopRules.Merge = coop.merge_of(peer)
	if merge != null:
		var partner: int = merge.partner if merge.primary == peer else merge.primary
		var other: PlayerState = states.get(partner)
		if other != null:
			other.cash_ins[tier] += 1
			if tier == 2:
				other.build.rerolls += balance.wirtshaus_l_rerolls
			level_flow.give_chest(partner, other, tier, items, tier == 3, gold, -1, balance.boss_chest_min_rarity if tier == 3 else 0)
			for s: PlayerState in [state, other]:
				s.merged_cash_in_tier = maxi(s.merged_cash_in_tier, tier)
		coop.split(merge, true)
	else:
		knodl.reset_knodl_mass(knodl_start_mass(knodl))
	# A cash-in wakes everyone who is down (co-op).
	coop.wake_everyone()
	print("[RUN] cash-in peer=%d tier=%d merged=%s t=%.1f" % [peer, tier, merge != null, run_time])


## Host: from kontrolleur_minute on, a Kontrolleur stands at every open Wirtshaus that still serves.
func _send_guards() -> void:
	if _guards_sent or _forced_enemies > 0 or run_time < balance.kontrolleur_minute * 60.0:
		return
	_guards_sent = true
	var guard: int = -1
	for t: int in types.size():
		if types[t].guards_wirtshaus:
			guard = t
	if guard < 0:
		return
	for wirt: Wirtshaus in wirtshaeuser:
		if wirt.open and not wirt.served:
			var at: Vector3 = wirt.mat_centre()
			var slot: int = enemies.spawn_at(guard, at.x, at.z)
			if slot >= 0:
				_guards[wirt.spot] = slot
				voices.offer(slot, VoiceLineData.Moment.ARRIVE)


## True while this Wirtshaus' Kontrolleur still stands at its door.
func _guarded(wirt: Wirtshaus) -> bool:
	var slot: int = _guards.get(wirt.spot, -1)
	if slot < 0 or enemies.alive[slot] == 0 or not types[enemies.type[slot]].guards_wirtshaus:
		_guards.erase(wirt.spot)
		return false
	var at: Vector3 = wirt.mat_centre()
	return Vector2(enemies.pos_x[slot] - at.x, enemies.pos_z[slot] - at.z).length() < balance.guard_radius


## Host: Brösel from the dead and from Knödl that shed (thrown, or bitten).
func _drop_brosel() -> void:
	for k: int in enemies.kill_x.size():
		var id: StringName = types[enemies.kill_type[k]].id
		_kills_by_type[id] = _kills_by_type.get(id, 0) + 1
		var kx: float = enemies.kill_x[k]
		var kz: float = enemies.kill_z[k]
		# Last words; a Knödl that just rolled over it gets its own.
		var dead: int = enemies.kill_slot[k]
		if not (enemies.knodl_timer[dead] > 0.0 and voices.offer(dead, VoiceLineData.Moment.CRUSHED)):
			voices.offer(dead, VoiceLineData.Moment.DEATH)
		# The Gartenzwerg goes off where it falls.
		var death: AttackData = types[enemies.kill_type[k]].death_attack
		if death != null:
			hazards.start_attack(death, kx, kz, kx, kz, -1)
		if k < 4:
			GameAudio.play(&"kill", Vector3(kx, ground.height_at(kx, kz), kz))
		for piece: int in Formulas.split_into_brosel(enemies.kill_xp[k], balance):
			brosel.drop(kx, kz, piece, true)
		var coins: int = types[enemies.kill_type[k]].gold_drop
		if coins == 0 and _loot_rng.randf() < balance.coin_drop_chance and loot.count < balance.coin_loot_cap:
			coins = 1
		for c: int in coins:
			_drop_loot(LootField.Kind.COIN, kx + _loot_rng.randf_range(-1.0, 1.0), kz + _loot_rng.randf_range(-1.0, 1.0),
					Formulas.coin_value(run_time, balance) * sites.gold_mult())
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


## Fliers rise toward players and Knödl in the air: the renderer needs to know where they are.
func _update_air_targets() -> void:
	var targets := PackedVector3Array()
	for peer: int in players:
		targets.append(players[peer].global_position)
	for peer: int in knodls:
		var knodl: Knodl = knodls[peer]
		targets.append(knodl.global_position - Vector3(0.0, knodl.radius, 0.0))
	renderer.air_targets = targets
	renderer.air_climb_range = balance.enemy_air_climb_range


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
			brosel.attract(player, Player.BODY_HEIGHT, reach, peer)
		# Half of a Riesenknödl eats nothing itself: the merged one does, for both.
		if not knodl.merged_away:
			brosel.absorb(at, knodl.radius, peer)
		if seconds.has(peer):
			brosel.absorb(seconds[peer].global_position, seconds[peer].radius, peer)
	brosel.update(delta, positions)
	var credits: Dictionary[int, Vector2] = brosel.take_credits()
	for peer: int in credits:
		if not states.has(peer):
			continue
		var credit: Vector2 = credits[peer]
		var state: PlayerState = states[peer]
		var knodl: Knodl = knodls[peer]
		state.add_xp(credit.x, balance, run_time)
		procs.on_brosel(peer, ceili(credit.y))
		coop.share_xp(peer, credit.x)
		knodl.add_knodl_mass(credit.y * balance.knodl_mass_per_xp)
		state.best_knodl_mass = maxf(state.best_knodl_mass, knodl.knodl_mass)
		if knodl.sort.heal_per_mass > 0.0:
			state.heal(credit.y / knodl.sort.heal_per_mass)


func on_downed(peer: int) -> void:
	var state: PlayerState = states[peer]
	# Stehengebliebene Uhr and the like: the hit that would knock them down does not (once).
	if procs != null and phase != Phase.SPERRSTUND and procs.on_lethal(peer):
		state.deaths -= 1
		events.toast("TOAST_SAVED")
		print("[RUN] saved by an item peer=%d t=%.1f" % [peer, run_time])
		return
	# Marterl-Kerze (per copy) and the Stammtisch's Nachschlag: back up at once with half the HP.
	if state.revives_used < roundi(state.build.effect(&"revive") + state.build.meta.get(&"revives", 0.0)):
		state.revives_used += 1
		state.deaths -= 1
		state.downed = false
		state.downed_timer = 0.0
		state.hp = state.max_hp * balance.item_revive_hp
		events.toast("TOAST_REVIVED")
		procs.on_revive(peer)
		return
	state.downed_times.append(run_time)
	if state.last_cause != &"":
		state.downed_by[state.last_cause] = state.downed_by.get(state.last_cause, 0) + 1
	# Nachspielzeit: down is out for good (no respawn, no teammate, the Wirtshäuser are shut). When the
	# last one falls, a moment of slow motion, then the end screen.
	if phase == Phase.SPERRSTUND:
		state.bleeds_out = true
		state.out = players.size() > 1
		state.downed_timer = INF
		for other: int in states:
			if not states[other].downed:
				return
		_lose_timer = balance.overtime_end_seconds
		if not _autoplay and _seconds <= 0.0 and DisplayServer.get_name() != "headless":
			Engine.time_scale = balance.overtime_slowmo
		return
	if _respawn:
		return
	# Solo: the run is over. Co-op: down for coop_down_seconds (teammates can wake them, CoopRules),
	# then out until the next cash-in; the run is lost when everyone is down at once.
	state.bleeds_out = players.size() > 1
	state.downed_timer = INF if players.size() <= 1 else balance.coop_down_seconds
	for other: int in states:
		if not states[other].downed:
			return
	_lose_timer = balance.death_screen_delay


func _on_respawned(peer: int) -> void:
	var knodl: Knodl = knodls[peer]
	knodl.reset_knodl_mass(knodl_start_mass(knodl))
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
	NetworkManager.flush()


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
		e.out = state.out
		e.revive = state.revive_progress
		e.down_left = state.downed_timer if state.downed and state.bleeds_out and not state.out else -1.0
		e.merge_partner = coop.merge_partner(peer)
		e.revives_given = state.revives_given
		e.passes = state.passes
		e.catches = state.catches
		e.merges = state.merges
		e.streit_catches = state.streit_catches
		e.merged_tier = state.merged_cash_in_tier
		for id: String in state.knodl_revives:
			for c: int in content.characters.size():
				if String(content.characters[c].id) == id:
					e.knodl_revive_mask |= 1 << c
		e.life = state.life
		e.pending_levels = state.pending_levels
		e.knodl_state = knodl.state
		e.knodl_cooldown = knodl.cooldown
		# Half of a Riesenknödl is hidden inside the other: mass 0 tells clients.
		e.knodl_mass = 0.0 if knodl.merged_away else knodl.knodl_mass
		e.knodl_position = knodl.global_position
		e.knodl_rotation = knodl.quaternion
		var second: Knodl = seconds.get(peer)
		if second != null:
			e.has_second = true
			e.second_position = second.global_position
			e.second_rotation = second.quaternion
			e.second_radius = second.radius
		e.gold = state.build.gold
		e.rerolls = state.build.rerolls
		e.banishes = state.build.banishes
		e.chests_opened = state.chests_opened
		e.chests_bought = state.chests_bought
		e.shield = state.shield / maxf(state.max_hp, 1.0)
		e.schilling = _schilling_of(peer)
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
	_update_air_targets()
	renderer.draw(replica.capacity, replica.alive, replica.x, replica.z, replica.yaw, replica.type,
			replica.radius, replica.flash, replica.phase, replica.status)
	slime.update(delta, replica.capacity, replica.alive, replica.x, replica.z, replica.type)
	brosel.draw()
	projectiles.update(delta, null)
	hazards.update(delta)
	stairs.update(delta)
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
		player.stat_glide = build.stat(&"glide")
		player.stat_sure_footing = minf(build.stat(&"sure_footing"), balance.sure_footing_cap)
		var peer_knodl: Knodl = knodls.get(peer)
		if peer_knodl != null:
			peer_knodl.string_mult = 1.0 + build.stat(&"string_length")
			if not NetworkManager.is_host():
				# Clients only draw the size; the mass rule is the host's.
				peer_knodl.set_size_rule(balance.riesenknodl_size if build.effect(&"riesenknodl") > 0.0 else 1.0, false)
			player.speed_factor = Formulas.knodl_speed_factor(peer_knodl.radius, balance)
		if weapon_vfx.has(peer):
			weapon_vfx[peer].sync(build, run_time, delta, null if NetworkManager.is_host() else projectiles)
	if state != null:
		camera.wobble = state.build.screen_wobble()
		if state.build.effect(&"riesenknodl") > 0.0 and not _riesen_seen:
			_riesen_seen = true
			hud.toast(tr("TOAST_RIESENKNODL"), 3.0)
			GameAudio.play(&"level_up")
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
	_move_shockwave(delta)
	_show_run_state(local, state, delta)
	_show_team(local, state)
	if state != null:
		hud.show_state(state, shown_knodl(id), run_time, balance)
		if speisekarte.is_open():
			speisekarte.show_player(state, knodl)
		if inventory.is_open():
			inventory.show_player(state, knodl, balance, ledger, NetworkManager.local_id(), run_time)
		if pause.is_open():
			pause.show_player(state, knodl, balance, ledger, NetworkManager.local_id(), run_time)
	inventory.allowed = not speisekarte.is_open() and not pause.is_open() and phase != Phase.ENDED
	if not inventory.allowed and inventory.is_open():
		inventory.set_open(false)
	pause.allowed = not speisekarte.is_open() and not inventory.is_open() and phase != Phase.ENDED
	if not pause.allowed and pause.is_open():
		pause.set_open(false)
	# The browser lets go of the pointer on Esc without passing the key on: treat it as Esc. The
	# Speisekarte and the Tab screen let go of it on their own (and a solo pause stops this check
	# meanwhile), so that is no Esc: once the panel is gone the pointer is taken back (the pick or
	# key press was the user gesture for it).
	var captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if speisekarte.is_shown() or inventory.is_open():
		_was_captured = false
	elif _panel_had_mouse:
		_panel_had_mouse = false
		_was_captured = false
		if camera.mouse_capture_allowed and not captured and not pause.is_open() and phase != Phase.ENDED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
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
	# Co-op: wake a knocked-down teammate first (stand by them).
	if players.size() > 1 and not _respawn:
		var nearest: float = 60.0
		var downed_at := Vector2.INF
		for peer: int in players:
			var mate: PlayerState = states.get(peer)
			if peer != local.peer_id and mate != null and mate.downed and not mate.out:
				var p: Vector3 = players[peer].global_position
				var d: float = here.distance_to(Vector2(p.x, p.z))
				if d < nearest:
					nearest = d
					downed_at = Vector2(p.x, p.z)
		if downed_at.is_finite():
			return downed_at
	# Co-op: now and then the family closes ranks (the bot then throws toward a teammate: a pass,
	# and two Knödl meeting may merge).
	if players.size() > 1 and fmod(run_time, 12.0) < 3.0:
		var mate_at := Vector2.INF
		var mate_d: float = 40.0
		for peer: int in players:
			if peer != local.peer_id and states.has(peer) and not states[peer].downed:
				var p: Vector3 = players[peer].global_position
				var d: float = here.distance_to(Vector2(p.x, p.z))
				if d < mate_d:
					mate_d = d
					mate_at = Vector2(p.x, p.z)
		if mate_at.is_finite():
			# Close enough to pass, not so close the Knödl lands on their feet: throw it over.
			if mate_d > 8.0 and mate_d < 22.0 and local.bot != null:
				local.bot.throw_now()
			return mate_at
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
	# A Marterl close by first (the rarer chance), then chests it can pay, Fassl, and Der Standler once per
	# visit when it can pay for something.
	for k: int in sites.marterl_at.size():
		var shrine: Vector3 = sites.marterl_at[k]
		if sites.marterl_state[k] == RunSites.State.PLACED and here.distance_to(Vector2(shrine.x, shrine.z)) < 40.0:
			return Vector2(shrine.x, shrine.z)
	chest = loot.nearest(LootField.Kind.CHEST, at.x, at.z)
	if chest >= 0 and state != null and state.build.gold >= _chest_price(chest, state) \
			and here.distance_to(Vector2(loot.xs[chest], loot.zs[chest])) < 70.0:
		return Vector2(loot.xs[chest], loot.zs[chest])
	var barrel: int = loot.nearest(LootField.Kind.FASSL, at.x, at.z)
	if barrel >= 0 and here.distance_to(Vector2(loot.xs[barrel], loot.zs[barrel])) < 18.0:
		return Vector2(loot.xs[barrel], loot.zs[barrel])
	if sites.stand_at.is_finite() and _bot_shopped != sites.stand_visits and state != null 			and state.build.gold >= sites.price(0, 0, run_time):
		var stall := Vector2(sites.stand_at.x, sites.stand_at.z)
		if here.distance_to(stall) < balance.standler_radius * 0.6:
			_bot_shopped = sites.stand_visits
		elif here.distance_to(stall) < 60.0:
			return stall
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
			"pos": [snappedf(players[NetworkManager.local_id()].global_position.x, 0.1),
					snappedf(players[NetworkManager.local_id()].global_position.z, 0.1)] if players.has(NetworkManager.local_id()) else [],
			"menu": speisekarte.is_shown(),
			"draws_peak": _draws_peak,
			"peak_with": _draws_peak_what,
		}
		_draws_peak = 0
		var json: String = JSON.stringify(line)
		if not _autoplay:
			print("[STATS] " + json)
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.knoedlStats = %s;" % json)


func _overlay_text() -> String:
	var lines: PackedStringArray = []
	lines.append("%s | %.0f fps | %d draw calls | players %d | quality %s%s | %s" % [_role(), stats.last_fps(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), players.size(),
			QualityScaler.NAMES[quality.level], " (auto)" if quality.auto else "", tr("HUD_BOT_HINT") if _bot else ""])
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
		report["voices_said"] = voices.said
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
		replica_stats["seconds_shown"] = _seconds_max
		replica_stats["offers_received"] = _offers_received
		replica_stats["run_events"] = _run_events_received
		replica_stats["hazards_seen"] = _hazards_seen
		replica_stats["voice_lines"] = _voice_lines_received
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
		"hofrat_beaten": (gate_flags & WorldStateCodec.GATE_BOSS_BEATEN) != 0, "bosses_beaten": _bosses_beaten.duplicate(),
		"character": String(character.id), "map": String(map.id), "grant": grant_index,
		"overtime": snappedf(overtime_seconds(), 0.1), "daily": RunSetup.daily}
	var boss_ids: Array = []
	for beaten: Array in _bosses_beaten:
		boss_ids.append(beaten[0])
	summary["bosses"] = boss_ids
	var by_type: Dictionary = {}
	for enemy_id: StringName in _kills_by_type:
		by_type[String(enemy_id)] = _kills_by_type[enemy_id]
	summary["kills_by_type"] = by_type
	if state != null:
		summary["level"] = state.level
		summary["schilling"] = _schilling_of(id) if NetworkManager.is_host() else state.schilling
		summary["stempel"] = stempel_found
		summary["xp"] = snappedf(state.xp, 0.1)
		summary["hp"] = snappedf(state.hp, 0.1)
		summary["deaths"] = state.deaths
		summary["damage_taken"] = snappedf(state.damage_taken, 0.1)
		summary["best_knodl_mass"] = snappedf(state.best_knodl_mass, 0.1)
		summary["gold"] = state.build.gold
		summary["gold_earned"] = state.build.gold_earned
		summary["chests_bought"] = state.chests_bought
		summary["chests_opened"] = state.chests_opened
		summary["chest_times"] = Array(state.chest_times).map(func(t: float) -> int: return roundi(t))
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
		# Co-op deeds for the Gemeindeamt quests (Profile.record_run, kind "coop").
		if players.size() > 1:
			var coop_deeds: Dictionary = {"runs": 1, "revives": state.revives_given, "passes": state.passes,
				"streit": state.streit_catches, "merges": state.merges,
				"merge_cash_xl": 1 if state.merged_cash_in_tier >= 3 else 0,
				"family_win": 1 if result == Result.WON and players.size() >= MAX_PLAYERS else 0}
			for revived: String in state.knodl_revives:
				coop_deeds["knodl_revive_" + revived] = int(coop_deeds.get("knodl_revive_" + revived, 0)) + 1
			summary["coop"] = coop_deeds
		var downs: Array = []
		for t: float in state.downed_times:
			downs.append(snappedf(t, 0.1))
		summary["downed_times"] = downs
		var weapons: Array = []
		for owned: PlayerBuild.OwnedWeapon in state.build.weapons:
			weapons.append("%s %d" % [owned.data.id, owned.level])
		summary["weapons"] = weapons
		var ids: Dictionary = {"weapons": [], "passives": [], "items": []}
		for owned: PlayerBuild.OwnedWeapon in state.build.weapons:
			ids["weapons"].append(String(owned.data.id))
		for owned: PlayerBuild.OwnedPassive in state.build.passives:
			ids["passives"].append(String(owned.data.id))
		for owned: PlayerBuild.OwnedItem in state.build.items:
			ids["items"].append(String(owned.data.id))
		summary["found"] = ids
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
		summary.merge(_reckoning(id), true)
		summary["kills"] = enemies.kills
		summary["brosel_merges"] = brosel.merges
		summary["cards_picked"] = level_flow.picks
		summary["standler_buys"] = sites.bought_by(id)
		summary["marterl_used"] = sites.marterl_by.get(id, 0)
	else:
		summary.merge(_host_summary, true)
	return summary


## Host: the run numbers a client cannot count itself (the crowd lives here): team kills by type,
## bosses, and that player's knock-downs, biggest Knödl, cash-ins, throws.
func _shared_summary(peer: int) -> Dictionary:
	var shared: Dictionary = {}
	var by_type: Dictionary = {}
	for enemy_id: StringName in _kills_by_type:
		by_type[String(enemy_id)] = _kills_by_type[enemy_id]
	shared["kills"] = enemies.kills
	shared["kills_by_type"] = by_type
	shared.merge(_reckoning(peer), true)
	var state: PlayerState = states.get(peer)
	if state != null:
		shared["deaths"] = state.deaths
		shared["best_knodl_mass"] = snappedf(state.best_knodl_mass, 0.1)
		shared["cash_ins"] = Array(state.cash_ins)
		var total: int = 0
		for count: int in state.cash_ins:
			total += count
		shared["cash_in_total"] = total
		shared["mass_eaten"] = snappedf(state.mass_eaten_by_enemies, 0.1)
		shared["damage_taken"] = snappedf(state.damage_taken, 0.1)
		shared["gold_earned"] = state.build.gold_earned
		shared["chests_opened"] = state.chests_opened
		shared["chest_times"] = Array(state.chest_times).map(func(t: float) -> int: return roundi(t))
		shared["standler_buys"] = sites.bought_by(peer)
		shared["marterl_used"] = sites.marterl_by.get(peer, 0)
	var knodl: Knodl = knodls.get(peer)
	if knodl != null:
		shared["throws"] = knodl.throws
		shared["knodl_hits"] = knodl.hits
		shared["knodl_kills"] = knodl.crushed
	return shared


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
		state.out = e.out
		state.revive_progress = e.revive
		state.downed_timer = e.down_left
		state.merge_partner = e.merge_partner
		state.revives_given = e.revives_given
		state.passes = e.passes
		state.catches = e.catches
		state.merges = e.merges
		state.streit_catches = e.streit_catches
		state.merged_cash_in_tier = e.merged_tier
		state.knodl_revives.clear()
		for c: int in content.characters.size():
			if e.knodl_revive_mask & (1 << c):
				state.knodl_revives.append(String(content.characters[c].id))
		state.life = e.life
		state.pending_levels = e.pending_levels
		state.chests_opened = e.chests_opened
		state.chests_bought = e.chests_bought
		state.shield = e.shield * state.max_hp
		state.schilling = e.schilling
		if not state.build.mirror(e.weapons, e.passives, e.items, e.gold, e.rerolls, e.banishes, e.chests_opened):
			push_warning("World state names an item this build does not know.")
		var knodl: Knodl = knodls.get(e.peer_id)
		if knodl == null:
			knodl = _spawn_knodl(e.peer_id, players[e.peer_id], false)
			knodl.place_at(e.knodl_position)
		# Half of a Riesenknödl (mass 0) hides inside the other half, which hangs on both strings.
		var away: bool = e.merge_partner != 0 and e.knodl_mass <= 0.0
		knodl.visible = not away
		if not away:
			knodl.apply_remote(e.knodl_position, e.knodl_rotation, e.knodl_mass, e.knodl_state as Knodl.State, e.knodl_cooldown)
		else:
			knodl.apply_remote(e.knodl_position, e.knodl_rotation, knodl.knodl_mass, e.knodl_state as Knodl.State, e.knodl_cooldown)
		knodl.co_holder = players.get(e.merge_partner) if e.merge_partner != 0 and not away else null
		var second: Knodl = _update_second_knodl(e.peer_id, e.has_second, e.second_position)
		if second != null:
			second.apply_remote(e.second_position, e.second_rotation, knodl.knodl_mass, Knodl.State.ATTACHED, 0.0)
	# The host picked for us (co-op time ran out) and nothing else is waiting: close the menu.
	var local: PlayerState = states.get(NetworkManager.local_id())
	if local != null and not local.choosing and speisekarte.is_open() and speisekarte.open_seconds() > 1.0:
		speisekarte.close()
	_knodls_max = maxi(_knodls_max, knodls.size())
	_seconds_max = maxi(_seconds_max, seconds.size())


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
		OfferCodec.Type.OFFER, OfferCodec.Type.SHOP:
			_note_panel_mouse()
			speisekarte.show_offer(offer, state.build)
			# The host's own offer arrives deferred, after the HUD looked this frame: step back now,
			# not a frame late (one frame with both drawn went over the draw-call budget, M6).
			hud.refresh_cover()
			speisekarte.show_player(state, knodls.get(NetworkManager.local_id()))
			inventory.set_open(false)
			# Solo is the only time the game stops (GAME-DESIGN.md); co-op runs on.
			if NetworkManager.is_host() and not NetworkManager.is_coop():
				get_tree().paused = true
		OfferCodec.Type.CHEST:
			speisekarte.show_chest(offer)
		OfferCodec.Type.NOTICE:
			hud.toast(tr("NOTICE_%d" % offer.value))


## Host: a player's answer to their offer.
func _on_choice(peer_id: int, data: PackedByteArray) -> void:
	if level_flow == null:
		return
	level_flow.on_choice(peer_id, data, states.get(peer_id), NetworkManager.is_coop())
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
	var speed: float = maxf(player.max_speed(), balance.player_speed)
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
	sites.resend(lying)
	var list: Array[RunEventCodec.Event] = lying.take()
	while not list.is_empty():
		NetworkManager.send_run_events_to(peer_id, RunEventCodec.encode(list.slice(0, RunEventCodec.MAX_EVENTS)))
		list = list.slice(RunEventCodec.MAX_EVENTS)


func _on_peer_left(peer_id: int) -> void:
	for nodes: Dictionary in [players, knodls, weapon_vfx, seconds]:
		var node: Node = nodes.get(peer_id)
		if node != null:
			nodes.erase(peer_id)
			node.queue_free()
	states.erase(peer_id)
	_characters.erase(peer_id)
	_last_pose_ms.erase(peer_id)
	_respawn_grace.erase(peer_id)
	if level_flow != null:
		level_flow.forget(peer_id)


## Client: the host told us our peer id; file the local player under it.
func _on_joined_host() -> void:
	var id: int = NetworkManager.local_id()
	if id == _local_key:
		return
	for nodes: Dictionary in [players, states, knodls, weapon_vfx, _characters, seconds]:
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
	if _finished:
		return
	if _seconds > 0.0 or _autoplay or DisplayServer.get_name() == "headless":
		_finish()
		return
	# A player in the browser: say why, keep what the run made so far (like leaving), back to the menu.
	hud.toast(CoopScreen.error_text(reason), 3.0)
	_finished = true
	_record_leaving()
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn"))


func _spawn_player(peer_id: int, local: bool) -> Player:
	var player := Player.new()
	var bot: BotInput = null
	if local and _bot:
		bot = BotInput.new(fposmod(peer_id * 0.37, 1.0))
		bot.set_waypoints(map.bot_waypoints, peer_id % maxi(map.bot_waypoints.size(), 1))
		bot.jump_every = 3.5
		bot.schupfn_every = 6.0
	var who: CharacterData = character_of(peer_id)
	player.setup(peer_id, local, balance, who, bot)
	player.ground = ground
	player.bounds = map.half_size
	player.slope_jump_reach = map.rim_start
	player.spawn_point = _spawn_position(peer_id)
	add_child(player)
	player.teleport(player.spawn_point)
	players[peer_id] = player
	if NetworkManager.is_host():
		var build := PlayerBuild.new(catalog, balance)
		_meta[peer_id] = _loadout(_meta_of(peer_id, local), who)
		build.apply_meta(_meta[peer_id])
		build.extra_cards = who.extra_cards
		_lock_content(build)
		# The character's own weapon levels (and evolves) even before its quest unlocks it for the
		# others: Kevin's Watschn-Aura stayed at level 1 on a fresh profile (balance log, M5).
		var own: int = catalog.weapons.find(who.start_weapon)
		if own >= 0:
			build.locked.erase(Card.Kind.WEAPON * 256 + own)
			var evolved: int = catalog.weapons.find(who.start_weapon.evolution)
			if evolved >= 0:
				build.locked.erase(Card.Kind.WEAPON * 256 + evolved)
		build.add_start_weapon(who.start_weapon)
		# Testing: --weapons=hagelkanone,sachertorte adds these too (locks and slots aside).
		for id: String in LaunchArgs.get_string("weapons", "").split(",", false):
			for weapon: WeaponData in catalog.weapons:
				if String(weapon.id) == id:
					build.weapon_slots = maxi(build.weapon_slots, build.weapons.size() + 1)
					build.add_start_weapon(weapon)
		# Testing: --items=doppelportion,powidl gives these items at the start.
		for item_id: String in LaunchArgs.get_string("items", "").split(",", false):
			for k: int in catalog.items.size():
				if String(catalog.items[k].id) == item_id:
					build.add_item(k)
		# Testing: --gold=200 starts with that much gold (Der Standler's shop in the screenshots).
		build.gold += maxi(LaunchArgs.get_int("gold", 0), 0)
		states[peer_id] = PlayerState.new(peer_id, balance.player_max_hp, build)
		states[peer_id].refresh_max_hp(balance.player_max_hp)
		states[peer_id].hp = states[peer_id].max_hp
		var knodl: Knodl = _spawn_knodl(peer_id, player, true)
		knodl.place_at(player.spawn_point + Vector3(0.0, 0.6, knodl.rest_length()))
	elif local:
		# The host's world state fills it in; the Stammtisch bonus moves this player like the host does.
		var mirror := PlayerBuild.new(catalog)
		mirror.apply_meta(_loadout(_meta_of(peer_id, true), who))
		states[peer_id] = PlayerState.new(peer_id, balance.player_max_hp, mirror)
	var vfx := WeaponVfx.new()
	vfx.setup(player)
	add_child(vfx)
	weapon_vfx[peer_id] = vfx
	return player


func _spawn_knodl(peer_id: int, holder: Player, simulated: bool) -> Knodl:
	var knodl := Knodl.new()
	knodl.setup(peer_id, balance, character_of(peer_id).knodl_sort, holder, simulated)
	add_child(knodl)
	if simulated:
		knodl.set_knodl_mass(knodl_start_mass(knodl))
	knodls[peer_id] = knodl
	return knodl


## The Stammtisch bonus plus the character's trait stats and start Knödl, as one stat bonus.
func _loadout(meta: Dictionary, who: CharacterData) -> Dictionary:
	var total: Dictionary = meta.duplicate()
	for key: StringName in who.trait_stats:
		total[key] = float(total.get(key, 0.0)) + who.trait_stats[key]
	if who.knodl_start > 0.0:
		total[&"knodl_start"] = float(total.get(&"knodl_start", 0.0)) + who.knodl_start
	return total


## A player's Stammtisch bonus: the local one from the Profile, a co-op player's from their room
## profile (each player's own meta progress counts for them). Automated runs use none.
func _meta_of(peer_id: int, local: bool) -> Dictionary:
	if _autoplay:
		return {}
	if local:
		return Profile.meta_bonus()
	var meta: Dictionary = {}
	var raw: Dictionary = NetworkManager.profiles.get(peer_id, {}).get("meta", {})
	for key: Variant in raw:
		meta[StringName(str(key))] = float(raw[key])
	return meta


## Each player's Knödlinger: the local one from RunSetup (flags win), the others from the room.
func character_of(peer_id: int) -> CharacterData:
	if _characters.has(peer_id):
		return _characters[peer_id]
	var who: CharacterData = character
	if peer_id != NetworkManager.local_id():
		var id: String = str(NetworkManager.profiles.get(peer_id, {}).get("character", ""))
		if id != "":
			who = _load_character(id)
	_characters[peer_id] = who
	return who


## Host: the character traits that are rules, not stats (CharacterData.trait_effects).
func _update_traits(delta: float) -> void:
	for peer: int in players:
		var effects: Dictionary[StringName, float] = character_of(peer).trait_effects
		if effects.is_empty():
			continue
		var state: PlayerState = states[peer]
		var player: Player = players[peer]
		if not _trait_timers.has(peer):
			_trait_timers[peer] = {}
		var timers: Dictionary = _trait_timers[peer]
		for key: StringName in [&"free_banish", &"coffee_break"]:
			if not effects.has(key) or state.downed:
				continue
			timers[key] = float(timers.get(key, 0.0)) + delta
			if float(timers[key]) < effects[key]:
				continue
			timers[key] = 0.0
			if key == &"free_banish":
				state.build.banishes += 1
			else:
				_coffee_break(player.global_position)
		if effects.has(&"idle_rate"):
			var rate: float = effects[&"idle_rate"] if player.still_time >= balance.idle_seconds and not state.downed else 0.0
			if rate != state.build.trait_rate:
				state.build.trait_rate = rate
				state.build.recompute()
		if effects.has(&"trot") and knodls.has(peer):
			(knodls[peer] as Knodl).damage_bonus = player.trot_bonus()
		if effects.has(&"jump_wave"):
			var jumps: int = player.jump_count if peer == NetworkManager.local_id() else player.last_input.jumps
			var seen: int = _jumps_seen.get(peer, jumps)
			var every: int = maxi(roundi(effects[&"jump_wave"]), 1)
			var count: int = int(timers.get(&"jumps", 0))
			for k: int in (jumps - seen) & 0xFF:
				count += 1
				if count % every == 0:
					var at: Vector3 = player.global_position
					var damage: float = balance.jump_wave_damage * (1.0 + state.build.stat(&"damage"))
					_ring_damage(at, balance.jump_wave_radius * (1.0 + state.build.stat(&"area")), damage, balance.jump_wave_knockback, peer)
					events.cue(RunEventCodec.Cue.SHOCKWAVE, at.x, at.z)
			timers[&"jumps"] = count
			_jumps_seen[peer] = jumps


## Host: Onkel Ferdl's Grant, one hit at a time.
func _on_hurt(peer: int) -> void:
	var per_hit: float = character_of(peer).trait_effects.get(&"grant", 0.0)
	if per_hit > 0.0:
		var build: PlayerBuild = states[peer].build
		build.grant_damage = minf(build.grant_damage + per_hit, balance.grant_cap)
		build.recompute()


## Host: Watschn-Baum and every weapon with `reflect_share`: the hit comes back to all in reach.
func _reflect_hit(peer: int, taken: float) -> void:
	var build: PlayerBuild = states[peer].build
	for owned: PlayerBuild.OwnedWeapon in build.weapons:
		var damage: float = Formulas.reflect_damage(taken, owned.data, owned.mods, build.stat(&"damage"))
		if damage <= 0.0:
			continue
		var at: Vector3 = players[peer].global_position
		var reach: float = owned.data.reach * Formulas.weapon_area(owned.data, owned.mods, build.stat(&"area"))
		_ring_damage(at, reach, damage, owned.data.knockback, peer)
		events.cue(RunEventCodec.Cue.SHOCKWAVE, at.x, at.z)


## Kommerzialrat Gustl: a few enemies near him stop for a coffee.
func _coffee_break(at: Vector3) -> void:
	var found: int = enemies.grid.query(at.x, at.z, balance.coffee_range)
	for k: int in mini(found, balance.coffee_enemies):
		enemies.slow(enemies.grid.results[k], 0.0, balance.coffee_seconds)


## Damages and pushes every enemy within `radius` of `at` (Kevin's shockwave); `peer`'s extra damage.
func _ring_damage(at: Vector3, radius: float, damage: float, knockback: float, peer: int = 0) -> void:
	enemies.source = _source(peer, "extra", "extra") if players.has(peer) else -1
	var found: int = enemies.grid.query(at.x, at.z, radius)
	for k: int in found:
		var j: int = enemies.grid.results[k]
		var away := Vector2(enemies.pos_x[j] - at.x, enemies.pos_z[j] - at.z)
		if away.length() > radius:
			continue
		away = away.normalized() if away.length() > 0.01 else Vector2.RIGHT
		enemies.damage(j, damage, away.x * knockback, away.y * knockback)
	enemies.source = -1


## Every role: a ring that grows and fades where a shockwave went off (a few, reused in turn).
func _show_shockwave(x: float, z: float, radius: float = -1.0) -> void:
	if radius < 0.0:
		radius = balance.jump_wave_radius
	if _shockwaves.is_empty():
		for k: int in SHOCKWAVES:
			var ring := MeshInstance3D.new()
			ring.mesh = MeshFactory.swing_fan(TAU, 32)
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ring.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			ring.visible = false
			var material := ShaderMaterial.new()
			material.shader = load("res://shaders/pulse.gdshader")
			material.set_shader_parameter(&"tint", Color(1.0, 0.95, 0.75))
			material.set_shader_parameter(&"fill", 0.0)
			ring.material_override = material
			add_child(ring)
			_shockwaves.append(ring)
			_shockwave_materials.append(material)
			_shockwave_times.append(SHOCKWAVE_SECONDS)
			_shockwave_sizes.append(balance.jump_wave_radius)
	var k: int = _shockwave_next
	_shockwave_next = (_shockwave_next + 1) % SHOCKWAVES
	_shockwaves[k].global_position = Vector3(x, ground.height_at(x, z) + 0.15, z)
	_shockwave_times[k] = 0.0
	_shockwave_sizes[k] = radius
	# Item sparks are small and many: only the big rings slam.
	if radius >= balance.jump_wave_radius:
		GameAudio.play(&"slam", _shockwaves[k].global_position)


func _move_shockwave(delta: float) -> void:
	for k: int in _shockwaves.size():
		_shockwave_times[k] += delta
		var t: float = _shockwave_times[k] / SHOCKWAVE_SECONDS
		_shockwaves[k].visible = t < 1.0
		if t < 1.0:
			_shockwaves[k].scale = Vector3.ONE * _shockwave_sizes[k] * lerpf(0.3, 1.0, sqrt(t))
			_shockwave_materials[k].set_shader_parameter(&"progress", t)


## Host: the items with effects on the Knödl and the world (PlayerBuild.EFFECTS).
func _update_item_effects(delta: float) -> void:
	for peer: int in players:
		var build: PlayerBuild = states[peer].build
		var knodl: Knodl = knodls.get(peer)
		var player: Player = players[peer]
		# Item evolutions (Riesenknödl der Apokalypse) arrive by themselves once earned.
		for index: int in build.item_evolutions_ready():
			build.add_item(index)
			print("[RUN] item evolution peer=%d %s t=%.1f" % [peer, build.catalog.items[index].id, run_time])
		_update_second_knodl(peer, build.effect(&"second_knodl") > 0.0)
		if knodl != null:
			var riesen: bool = build.effect(&"riesenknodl") > 0.0
			knodl.set_size_rule(balance.riesenknodl_size if riesen else 1.0, riesen)
			knodl.spikes = build.effect(&"knodl_spikes")
			knodl.slope_bonus = build.effect(&"knodl_slope")
			# Powidl-Füllung: the end of a Schupfn bursts.
			var last: int = _knodl_state_last.get(peer, knodl.state)
			if last == Knodl.State.THROWN and knodl.state != Knodl.State.THROWN and build.effect(&"knodl_burst") > 0.0:
				var at: Vector3 = knodl.global_position
				var damage: float = balance.powidl_damage * knodl.radius * (1.0 + build.stat(&"damage"))
				_ring_damage(at, knodl.radius + balance.powidl_radius, damage, 10.0, peer)
				knodl.set_knodl_mass(knodl.knodl_mass * (1.0 - balance.powidl_cost))
				events.cue(RunEventCodec.Cue.SHOCKWAVE, at.x, at.z)
			_knodl_state_last[peer] = knodl.state
		# Kirchenglocke: a ring every few seconds (more copies ring more often).
		var bells: float = build.effect(&"bell")
		if bells > 0.0 and not states[peer].downed:
			_bell_timers[peer] = _bell_timers.get(peer, 0.0) + delta * bells
			if _bell_timers[peer] >= balance.bell_seconds:
				_bell_timers[peer] = 0.0
				var at: Vector3 = player.global_position
				_ring_damage(at, balance.bell_radius * (1.0 + build.stat(&"area")), balance.bell_damage * (1.0 + build.stat(&"damage")), 12.0, peer)
				events.cue(RunEventCodec.Cue.SHOCKWAVE, at.x, at.z)
				GameAudio.play(&"gate_open", at)


## Every role: Doppelportion's second Knödl appears with the item and follows the main one's mass
## at second_knodl_scale (host: simulated; client: placed from the world state).
func _update_second_knodl(peer: int, wanted: bool, where: Vector3 = Vector3.INF) -> Knodl:
	var second: Knodl = seconds.get(peer)
	var main: Knodl = knodls.get(peer)
	if not wanted or main == null or not players.has(peer):
		if second != null:
			seconds.erase(peer)
			second.queue_free()
		return null
	if second == null:
		second = Knodl.new()
		var simulated: bool = NetworkManager.is_host()
		second.setup(peer, balance, character_of(peer).knodl_sort, players[peer], simulated)
		second.name = "Knodl2_%d" % peer
		second.rest_mult = balance.second_knodl_rest / maxf(balance.knodl_rest_length, 0.01)
		add_child(second)
		second.set_size_rule(balance.second_knodl_scale, false)
		second.place_at(where if where.is_finite() else main.global_position + Vector3(0.6, 0.0, 0.0))
		seconds[peer] = second
	second.string_mult = main.string_mult
	if NetworkManager.is_host():
		second.reset_knodl_mass(main.knodl_mass)
	return second


## Host: Schweizerkracher blasts at a few of this frame's kills.
func _kill_blasts() -> void:
	var chance: float = 0.0
	var holder: int = 0
	for peer: int in states:
		chance += states[peer].build.effect(&"kill_blast")
		if holder == 0 and states[peer].build.effect(&"kill_blast") > 0.0:
			holder = peer
	if chance <= 0.0:
		return
	var blasts: int = 0
	for k: int in enemies.kill_x.size():
		if blasts >= 3 or _loot_rng.randf() >= chance:
			continue
		blasts += 1
		var x: float = enemies.kill_x[k]
		var z: float = enemies.kill_z[k]
		_ring_damage(Vector3(x, 0.0, z), balance.kracher_radius, balance.kracher_damage, 8.0, holder)
		events.cue(RunEventCodec.Cue.SHOCKWAVE, x, z)


## Host: what is still locked behind a quest (Profile) stays out of the Speisekarte and the chests.
func _lock_content(build: PlayerBuild) -> void:
	for k: int in catalog.weapons.size():
		if not Profile.is_unlocked(&"weapon", catalog.weapons[k].id):
			build.locked[Card.Kind.WEAPON * 256 + k] = true
	for k: int in catalog.passives.size():
		if not Profile.is_unlocked(&"passive", catalog.passives[k].id):
			build.locked[Card.Kind.PASSIVE * 256 + k] = true
	for k: int in catalog.items.size():
		if not Profile.is_unlocked(&"item", catalog.items[k].id):
			build.locked[Card.Kind.ITEM * 256 + k] = true


## Host: the damage source id of a player's weapon, Knödl or extras (Run-Abrechnung).
func _source(peer: int, kind: String, id: String) -> int:
	var key: String = "%d|%s|%s" % [peer, kind, id]
	var found: int = _source_ids.get(key, -1)
	if found < 0:
		found = _sources.size()
		_sources.append([peer, kind, id])
		_source_ids[key] = found
	return found


## Host: one player's Run-Abrechnung: damage and kills per weapon (by weapon id), by the Knödl and by
## extras, and what knocked them down how often (enemy id -> n).
func _reckoning(peer: int) -> Dictionary:
	var damage: Dictionary = {}
	var kills: Dictionary = {}
	for id: int in mini(_sources.size(), enemies.dealt.size()):
		var entry: Array = _sources[id]
		if int(entry[0]) != peer:
			continue
		var key: String = str(entry[2])
		damage[key] = snappedf(float(damage.get(key, 0.0)) + enemies.dealt[id], 0.1)
		kills[key] = int(kills.get(key, 0)) + enemies.source_kills[id]
	var downed: Dictionary = {}
	var state: PlayerState = states.get(peer)
	if state != null:
		for cause: StringName in state.downed_by:
			downed[String(cause)] = state.downed_by[cause]
	return {"damage_by_source": damage, "kills_by_source": kills, "downed_by": downed}


## Host: the Schilling a player's run is worth so far (GAME-DESIGN.md: gold, cash-ins, and 25 % of the
## Knödl when knocked out), times the Grant level and the co-op bonus.
func _schilling_of(peer: int) -> int:
	var state: PlayerState = states.get(peer)
	var knodl: Knodl = knodls.get(peer)
	if state == null:
		return 0
	var total: float = state.build.gold_earned * balance.schilling_per_gold
	for tier: int in mini(state.cash_ins.size(), balance.schilling_per_cash_in.size()):
		total += state.cash_ins[tier] * balance.schilling_per_cash_in[tier]
	if result == Result.LOST and knodl != null:
		total += knodl.knodl_mass * balance.schilling_knodl_share
	elif result == Result.WON:
		total += balance.schilling_win_bonus
	total += overtime_seconds() * balance.schilling_per_overtime_second
	total *= grant.schilling * (1.0 + balance.coop_schilling_per_player * maxi(players.size() - 1, 0))
	return roundi(total)


## The local player's run goes into the Profile once (Schilling, quests, records). Not for the
## balance log or measuring runs.
func _record_profile(outcome: String) -> void:
	if _recorded or _autoplay or _seconds > 0.0:
		return
	_recorded = true
	var summary: Dictionary = _run_summary()
	summary["result"] = outcome
	_reward = Profile.record_run(summary)
	# A Tageskarte run leaves the player's own choice on the Play screen alone.
	if RunSetup.daily == "":
		Profile.remember_choice(character.id, map.id, grant_index)
	if outcome != "QUIT" and NetworkManager.is_host():
		Board.submit({
			"names": _board_names(), "characters": _board_characters(), "result": outcome,
			"grant": grant_index, "time": int(summary.get("time", 0.0)), "level": int(summary.get("level", 0)),
			"kills": int(summary.get("kills", 0)), "knodl": int(summary.get("best_knodl_mass", 0.0)),
		})


## Die Ehrentafel: everyone in the run (co-op lists the whole family), host first.
func _board_names() -> Array:
	var names: Array = []
	for peer: int in _board_order():
		var name: String = Settings.player_name() if peer == NetworkManager.local_id() else NetworkManager.player_name(peer)
		names.append(name if name != "" else Settings.NAME_FALLBACK)
	return names


func _board_characters() -> Array:
	var ids: Array = []
	for peer: int in _board_order():
		ids.append(String(character_of(peer).id))
	return ids


func _board_order() -> Array[int]:
	var order: Array[int] = []
	for peer: int in players:
		order.append(peer)
	order.sort()
	return order


func knodl_start_mass(knodl: Knodl) -> float:
	if _start_mass >= 0.0:
		return _start_mass
	var meta: Dictionary = _meta.get(knodl.owner_peer, {})
	return balance.knodl_start_mass * knodl.sort.start_mass_mult * (1.0 + float(meta.get(&"knodl_start", 0.0)))


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
		if phase != Phase.ENDED and not _god:
			for peer: int in players:
				var state: PlayerState = states[peer]
				if state.downed or state.choosing:
					continue
				var at: Vector3 = players[peer].global_position
				if at.y - ground.height_at(at.x, at.z) > balance.hazard_dodge_height:
					continue
				if HazardField.contains(h, at.x, at.z, balance.player_radius):
					state.last_cause = types[enemies.type[h.source]].id if h.source >= 0 else &"attack"
					var hp_before: float = state.hp
					if state.hurt(Formulas.hit_damage(attack.damage * grant.enemy_damage, state.build.stat(&"armor"), balance), balance):
						on_downed(peer)
					if state.hp < hp_before:
						procs.on_hurt(peer, hp_before - state.hp)
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
		voices.offer(boss.slot, VoiceLineData.Moment.BEATEN)
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
		voices.offer(boss.slot, VoiceLineData.Moment.ARRIVE)
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


## Host: about once a second, every player's damage so far per weapon, item, Knödl and extras (and
## the procs per item) as DAMAGE events, for the build view on every machine.
func _send_damage(delta: float) -> void:
	_ledger_timer -= delta
	if _ledger_timer > 0.0:
		return
	_ledger_timer = 1.0
	for id: int in _sources.size():
		var entry: Array = _sources[id]
		var peer: int = int(entry[0])
		var name: String = str(entry[2])
		var kind: int = DamageLedger.Kind.EXTRA
		var index: int = 0
		var count: int = 0
		match str(entry[1]):
			"weapon":
				kind = DamageLedger.Kind.WEAPON
				index = _weapon_index(name)
			"item":
				kind = DamageLedger.Kind.ITEM
				index = _item_index(name)
				count = procs.procs_of(peer, name)
			"knodl":
				kind = DamageLedger.Kind.KNODL
		if index < 0:
			continue
		var total: float = enemies.dealt[id] if id < enemies.dealt.size() else 0.0
		var key: String = DamageLedger.key(peer, kind as DamageLedger.Kind, index)
		var now := Vector2(total, count)
		# Weapons and the Knödl always (the 30 s window needs the samples), the rest when it changed.
		if _ledger_sent.get(key, Vector2(-1.0, -1.0)) == now and kind == DamageLedger.Kind.ITEM:
			continue
		_ledger_sent[key] = now
		events.damage(peer, kind, index, total, count)


func _weapon_index(id: String) -> int:
	for k: int in catalog.weapons.size():
		if String(catalog.weapons[k].id) == id:
			return k
	return -1


func _item_index(id: String) -> int:
	for k: int in catalog.items.size():
		if String(catalog.items[k].id) == id:
			return k
	return -1


## Host: Fassl stand around the players (a new one every few seconds, far ones go) and burst into
## coins when a player walks into one or a Knödl rolls over it.
func _update_fassl(delta: float) -> void:
	if phase != Phase.RUNNING:
		return
	var positions: PackedVector3Array = _player_positions()
	if positions.is_empty():
		return
	var standing: int = 0
	for slot: int in loot.capacity:
		if loot.alive[slot] == 0 or loot.kinds[slot] != LootField.Kind.FASSL:
			continue
		var x: float = loot.xs[slot]
		var z: float = loot.zs[slot]
		var near: float = INF
		var breaker: int = 0
		for peer: int in players:
			var at: Vector3 = players[peer].global_position
			var d: float = Vector2(at.x - x, at.z - z).length()
			near = minf(near, d)
			if d < balance.fassl_break_radius and not states[peer].downed:
				breaker = peer
		for peer: int in knodls:
			var ball: Knodl = knodls[peer]
			if Vector2(ball.global_position.x - x, ball.global_position.z - z).length() < ball.radius + 0.5:
				breaker = peer
		if breaker != 0:
			_take_loot(slot, breaker)
			for c: int in balance.fassl_coins:
				var angle: float = TAU * c / maxi(balance.fassl_coins, 1)
				_drop_loot(LootField.Kind.COIN, x + cos(angle) * 1.2, z + sin(angle) * 1.2,
						Formulas.coin_value(run_time, balance) * sites.gold_mult())
		elif near > balance.fassl_far:
			_take_loot(slot, 0)
		else:
			standing += 1
	_fassl_timer -= delta
	if standing >= balance.fassl_count or _fassl_timer > 0.0 or loot.count >= balance.coin_loot_cap:
		return
	_fassl_timer = balance.fassl_respawn if standing > 0 else 0.0
	# Somewhere flat a little off one player, about as high as they stand (not up on a roof).
	var centre: Vector3 = positions[_loot_rng.randi_range(0, positions.size() - 1)]
	var half: float = map.half_size - 4.0
	for attempt: int in 6:
		var angle: float = _loot_rng.randf() * TAU
		var reach: float = _loot_rng.randf_range(balance.fassl_min, balance.fassl_max)
		var x: float = clampf(centre.x + cos(angle) * reach, -half, half)
		var z: float = clampf(centre.z + sin(angle) * reach, -half, half)
		if ground.slope_at(x, z) < 0.3 and absf(ground.height_at(x, z) - centre.y) < 2.5:
			_drop_loot(LootField.Kind.FASSL, x, z, 0)
			return


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
					# Past Sperrstund' the Formular is moot: the result is settled.
					if d < balance.stempel_pickup_radius and phase == Phase.RUNNING:
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
								state.chests_bought += 1
							var rarity: int = LootField.chest_rarity(loot.values[slot])
							state.chests_opened += 1
							state.chest_times.append(run_time)
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


## The price over every map chest in view and within CHEST_PRICE_REACH, so the player sees from afar
## whether they can afford it (accent: yes, muted: not yet).
func _mark_chest_prices(from: Vector3) -> void:
	var state: PlayerState = states.get(NetworkManager.local_id())
	if state == null or state.build == null:
		return
	var view: Rect2 = get_viewport().get_visible_rect()
	for slot: int in loot.capacity:
		if loot.alive[slot] == 0 or loot.kinds[slot] != LootField.Kind.CHEST:
			continue
		var at: Vector3 = loot.position_of(slot) + Vector3(0.0, 1.6, 0.0)
		if from.distance_to(at) > CHEST_PRICE_REACH or camera.is_position_behind(at) 				or not view.has_point(camera.unproject_position(at)):
			continue
		var price: int = _chest_price(slot, state)
		hud.marker(camera, at, tr("HUD_CHEST_MARKER") % price, "accent" if state.build.gold >= price else "muted")


## What a map chest costs this player: its base price, dearer for every chest they bought.
func _chest_price(slot: int, state: PlayerState) -> int:
	return Formulas.chest_price(LootField.chest_low(loot.values[slot]), state.chests_bought if state != null else 0, balance)


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
		if h.tag >= 0:
			events.lock(h.tag, h.telegraph, h.attack.lock_seconds)
		else:
			events.hazard(h)
		if h.source >= 0 and enemies.alive[h.source] != 0:
			voices.offer(h.source, VoiceLineData.Moment.ATTACK)
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
			RunEventCodec.Kind.SAY:
				_voice_lines_received += 1
			RunEventCodec.Kind.LOOT:
				loot.add_remote(e.id, e.a, e.x, e.z, e.b)
			RunEventCodec.Kind.TAKEN:
				loot.remove(e.id)
			RunEventCodec.Kind.LOCK:
				if e.a < stairs.feet.size():
					hazards.add_slope(stairs.mark_foot(e.a), stairs.mark_top(e.a), stairs.widths[e.a] * 0.5, e.seconds)
					_hazards_seen += 1


## Every role: the sound, toast or look of a run event.
func _present(e: RunEventCodec.Event) -> void:
	var local: Player = players.get(NetworkManager.local_id())
	match e.kind:
		RunEventCodec.Kind.HAZARD:
			if local != null and Vector2(e.x - local.global_position.x, e.z - local.global_position.z).length() < e.radius + e.length + 10.0:
				GameAudio.play(&"warn", Vector3(e.x, ground.height_at(e.x, e.z), e.z))
		RunEventCodec.Kind.LOCK:
			stairs.lock(e.a, e.seconds, e.length)
			print("[RUN] stairs locked %d for %.0f s t=%.1f" % [e.a, e.length, run_time])
			if e.a < stairs.feet.size():
				GameAudio.play(&"warn", stairs.feet[e.a])
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
				LootField.Kind.FASSL:
					if e.b != 0:
						GameAudio.play(&"knodl_hit", at)
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
			elif e.a == RunEventCodec.Cue.SHOCKWAVE:
				_show_shockwave(e.x, e.z)
			elif e.a == RunEventCodec.Cue.SPARK:
				_show_shockwave(e.x, e.z, balance.spark_radius)
		RunEventCodec.Kind.SAY:
			voices.present(e.a, e.b, e.id, e.x, e.z)
		RunEventCodec.Kind.SITE:
			sites.present(e)
		RunEventCodec.Kind.DAMAGE:
			ledger.record(e.b, e.a, e.c, e.x, e.id, run_time)


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
		# Teammates: a knocked-down one always (go wake them), the others once far or off screen.
		for peer: int in players:
			var mate: PlayerState = states.get(peer)
			if peer == NetworkManager.local_id() or mate == null or mate.out:
				continue
			var at: Vector3 = players[peer].global_position + Vector3(0.0, 2.4, 0.0)
			var far: float = from.distance_to(at)
			var off_screen: bool = camera.is_position_behind(at) or not get_viewport().get_visible_rect().has_point(camera.unproject_position(at))
			if mate.downed:
				hud.marker(camera, at, tr("HUD_WAKE_MARKER") % [_mate_name(peer), roundi(far)], "accent")
			elif far > 25.0 or off_screen:
				hud.marker(camera, at, "%s · %d m" % [_mate_name(peer), roundi(far)], "rarity_1")
		_mark_chest_prices(from)
	hud.end_markers()
	var hint: String = ""
	var chest: int = loot.nearest(LootField.Kind.CHEST, from.x, from.z)
	if chest >= 0 and Vector2(loot.xs[chest] - from.x, loot.zs[chest] - from.z).length() < 7.0:
		var price: int = _chest_price(chest, state)
		hint = tr("HINT_CHEST") % [price, state.build.gold if state != null and state.build != null else 0]
	hud.show_hint(hint)
	if state != null:
		hud.downed_key = "TOAST_DOWNED" if _respawn or players.size() > 1 else "TOAST_DOWNED_SOLO"
		if phase != Phase.RUNNING:
			hud.downed_key = "TOAST_THROWN_OUT"
		hud.downed_text = ""
		if state.downed and not _respawn and players.size() > 1 and phase == Phase.RUNNING:
			if state.out:
				hud.downed_text = tr("TOAST_OUT")
			elif state.revive_progress > 0.01:
				hud.downed_text = tr("TOAST_BEING_WOKEN") % roundi(state.revive_progress * 100.0)
			else:
				hud.downed_text = tr("TOAST_DOWNED_COOP") % maxi(ceili(state.downed_timer), 0)
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
		local.ground_slow = 1.0 - (1.0 - slime.speed_factor(local.global_position)) * (1.0 - local.stat_sure_footing)
		GameAudio.set_listener(local.global_position)
		voices.update_view(delta, local.global_position)
	if phase == Phase.RUNNING:
		GameAudio.music(&"boss" if boss_alive else (map.music if map != null else &"kirtag"))
		if not boss_alive:
			GameAudio.set_music_speed(1.0 + 0.12 * clampf(run_time / balance.run_seconds, 0.0, 1.0))
	elif phase == Phase.SPERRSTUND:
		# The Schunkel waltz hurries along with the Stammgast-Geister.
		GameAudio.set_music_speed(minf(overtime_pace(), 1.5))


## Co-op: the family panel, the signs over knocked-down teammates, and once out the camera
## follows someone still standing.
func _show_team(local: Player, state: PlayerState) -> void:
	var rows: Array[TeamPanel.Row] = []
	var me: int = NetworkManager.local_id()
	var order: Array[int] = []
	for peer: int in players:
		order.append(peer)
	order.sort()
	for peer: int in order:
		var mate: PlayerState = states.get(peer)
		var player: Player = players[peer]
		player.note = ""
		if mate == null or players.size() < 2 or _respawn:
			continue
		# Our own state is in the HUD's toast; signs are for the teammates.
		if mate.downed and peer != me:
			if mate.out:
				player.note = tr("SIGN_OUT")
			elif mate.revive_progress > 0.01:
				player.note = tr("SIGN_WAKING") % roundi(mate.revive_progress * 100.0)
			else:
				player.note = tr("SIGN_DOWNED") % maxi(ceili(mate.downed_timer), 0)
		if peer == me:
			continue
		var row := TeamPanel.Row.new()
		row.name = _mate_name(peer)
		row.color = character_of(peer).coat_color
		row.level = mate.level
		row.hp = mate.hp / maxf(mate.max_hp, 1.0)
		row.downed = mate.downed
		row.out = mate.out
		row.down_left = mate.downed_timer
		row.revive = mate.revive_progress
		rows.append(row)
	hud.show_team(rows)
	# Out: watch the nearest teammate still standing.
	var target: Node3D = local
	if state != null and state.out and local != null:
		var best: float = INF
		for peer: int in players:
			var mate: PlayerState = states.get(peer)
			if peer != me and mate != null and not mate.downed:
				var d: float = players[peer].global_position.distance_to(local.global_position)
				if d < best:
					best = d
					target = players[peer]
	if target != null and camera.target != target:
		camera.target = target


## A teammate's name for markers and the panel (their character's when the room has none).
func _mate_name(peer: int) -> String:
	var name: String = NetworkManager.player_name(peer)
	return name if name != "" else tr(character_of(peer).name_key)


## The Knödl a player rolls right now: their own, or the merged Riesenknödl they hold with a partner.
func shown_knodl(peer: int) -> Knodl:
	var knodl: Knodl = knodls.get(peer)
	var partner: int = states[peer].merge_partner if states.has(peer) else 0
	if knodl != null and partner != 0 and not knodl.visible and knodls.has(partner):
		return knodls[partner]
	return knodl


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
