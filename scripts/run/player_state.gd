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
## The last Schupfn press counter acted on (InputMessage.schupfn_presses).
var schupfn_seen: int = 0
var deaths: int = 0
var damage_taken: float = 0.0
## The Knödl's largest mass this run.
var best_knodl_mass: float = 0.0
## Run stats for the end screen and the balance log.
var cash_ins: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var mass_eaten_by_enemies: float = 0.0
## Run time of every level-up (balance log: is the first one within 10 s?).
var level_times: PackedFloat32Array = PackedFloat32Array()
## Run time of every knock-down.
var downed_times: PackedFloat32Array = PackedFloat32Array()


func _init(p_peer_id: int = 1, p_max_hp: float = 100.0, p_build: PlayerBuild = null) -> void:
	peer_id = p_peer_id
	max_hp = p_max_hp
	hp = p_max_hp
	build = p_build


## Host: a hit (already reduced by armor). Returns true when it knocked the player down.
func hurt(amount: float, balance: BalanceData) -> bool:
	if downed or choosing or hurt_timer > 0.0 or amount <= 0.0:
		return false
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


func heal(amount: float) -> void:
	if not downed and amount > 0.0:
		hp = minf(hp + amount, max_hp)


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
	downed = false
	hp = max_hp
	life = (life + 1) & 0xFF
	return true
