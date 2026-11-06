class_name PlayerState
extends RefCounted
## What the host decides about one player: HP, XP, level, their build, knocked down or not, and
## whether they are choosing from the Speisekarte. The host owns it (CLAUDE.md: host-authoritative
## damage) and sends it to everyone in the world state; a client keeps a mirror of each player's
## state for the HUD and the look.

var peer_id: int = 1
var hp: float = 100.0
var max_hp: float = 100.0
var xp: float = 0.0
var level: int = 1
var downed: bool = false
## Co-op: knocked down and nobody came in time; out until the next Wirtshaus cash-in (still downed).
var out: bool = false
## Co-op: a teammate standing by fills this to 1 and the player is back up (GAME-DESIGN.md: 3 s).
var revive_progress: float = 0.0
## Co-op: the peer whose Knödl ours is merged with (0 = none); the host keeps it in CoopRules, a
## client reads it from the world state.
var merge_partner: int = 0
## Counts respawns (wraps at 256); the owning player teleports to the spawn when it changes.
var life: int = 0
## Level-ups not chosen yet, and whether a Speisekarte is open right now (co-op: the player stands
## still, invulnerable and ignored by enemies).
var pending_levels: int = 0
var choosing: bool = false
var build: PlayerBuild

# Host only.
var hurt_timer: float = 0.0
var downed_timer: float = 0.0
## Revives taken from items (Marterl-Kerze) this run.
var revives_used: int = 0
## Co-op: a knock-down runs out into `out` instead of a respawn.
var bleeds_out: bool = false
## Co-op deeds this run (quests, the end screen): teammates woken by standing by / by the Knödl
## (and whom: character ids), Knödl passed and caught, merges, Familienstreit Knödl caught.
var revives_given: int = 0
var knodl_revives: PackedStringArray = PackedStringArray()
var passes: int = 0
var catches: int = 0
var merges: int = 0
var merged_cash_in_tier: int = -1
var streit_catches: int = 0
## The last Schupfn press counter acted on (InputMessage.schupfn_presses).
var schupfn_seen: int = 0
var deaths: int = 0
var damage_taken: float = 0.0
## The Knödl's largest mass this run.
var best_knodl_mass: float = 0.0
## Run stats for the end screen and the balance log.
var cash_ins: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var mass_eaten_by_enemies: float = 0.0
## Map chests opened (Sparbuch counts them) and bought (each one makes the next dearer:
## balance.map_chest_price_growth; free ones do not). Both in the world state.
var chests_opened: int = 0
var chests_bought: int = 0
## Host: run time of every map chest opened (balance log: first chest ~1:30, then about one a minute).
var chest_times := PackedFloat32Array()
## Federbett (1.4): healing above max HP becomes this shield, up to shield_share × max HP (ItemProcs
## sets the share every frame). The shield is in the world state.
var shield: float = 0.0
var shield_share: float = 0.0
## Client: the Schilling the host says this run pays (the world state).
var schilling: int = 0
## Run time of every level-up (balance log: is the first one within 10 s?).
var level_times: PackedFloat32Array = PackedFloat32Array()
## Run time of every knock-down.
var downed_times: PackedFloat32Array = PackedFloat32Array()
## Run-Abrechnung (host): the enemy type whose touch or attack hurt last, and what knocked this
## player down how often (enemy id -> n).
var last_cause: StringName = &""
var downed_by: Dictionary[StringName, int] = {}


func _init(p_peer_id: int = 1, p_max_hp: float = 100.0, p_build: PlayerBuild = null) -> void:
	peer_id = p_peer_id
	max_hp = p_max_hp
	hp = p_max_hp
	build = p_build


## Host: a hit (already reduced by armor). Returns true when it knocked the player down. A shield
## (Federbett) takes it first.
func hurt(amount: float, balance: BalanceData) -> bool:
	if downed or choosing or hurt_timer > 0.0 or amount <= 0.0:
		return false
	var soaked: float = minf(shield, amount)
	shield -= soaked
	amount -= soaked
	hp = maxf(hp - amount, 0.0)
	damage_taken += amount
	hurt_timer = balance.player_hurt_cooldown
	if hp > 0.0:
		return false
	downed = true
	downed_timer = balance.player_respawn_seconds
	deaths += 1
	return true


## Host: XP in; returns how many levels were gained (they wait in pending_levels).
func add_xp(amount: float, balance: BalanceData, run_time: float = 0.0) -> int:
	if amount <= 0.0:
		return 0
	if build != null:
		amount *= 1.0 + build.stat(&"xp_gain")
	xp += amount
	var new_level: int = Formulas.level_for_xp(xp, balance)
	var gained: int = new_level - level
	level = new_level
	pending_levels += gained
	for k: int in gained:
		level_times.append(run_time)
	return gained


## Host: max HP from the base and the build; HP rises with it.
func refresh_max_hp(base_hp: float) -> void:
	var wanted: float = base_hp + (build.stat(&"max_hp") if build != null else 0.0)
	if wanted > max_hp:
		hp += wanted - max_hp
	max_hp = wanted
	hp = minf(hp, max_hp)


## Host, co-op: back up where they lie (a teammate, a Knödl or a cash-in woke them).
func revive(hp_share: float, grace: float) -> void:
	downed = false
	out = false
	bleeds_out = false
	revive_progress = 0.0
	downed_timer = 0.0
	hp = maxf(max_hp * hp_share, 1.0)
	hurt_timer = grace


func heal(amount: float) -> void:
	if not downed and amount > 0.0:
		var over: float = hp + amount - max_hp
		hp = minf(hp + amount, max_hp)
		if over > 0.0 and shield_share > 0.0:
			shield = minf(shield + over, max_hp * shield_share)


## Host: counts the timers down and regenerates. Returns true when a knocked-down player is back.
func tick(delta: float) -> bool:
	if hurt_timer > 0.0:
		hurt_timer -= delta
	if not downed:
		if build != null:
			heal(build.stat(&"regen") * delta)
		return false
	downed_timer -= delta
	if downed_timer > 0.0:
		return false
	if bleeds_out:
		out = true
		return false
	downed = false
	hp = max_hp
	life = (life + 1) & 0xFF
	return true
