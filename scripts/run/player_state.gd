class_name PlayerState
extends RefCounted
## What the host decides about one player: HP, XP, level, knocked down or not, weapon timing.
## The host owns it (CLAUDE.md: host-authoritative damage) and sends it to everyone in the world
## state; a client keeps a mirror of each player's state for the HUD and the look.

var peer_id: int = 1
var hp: float = 100.0
var max_hp: float = 100.0
var xp: float = 0.0
var level: int = 1
var downed: bool = false
## Counts respawns (wraps at 256); the owning player teleports to the spawn when it changes.
var life: int = 0
## Counts weapon swings (wraps at 256); everyone plays the swing effect when it changes.
var swing_count: int = 0

# Host only.
var hurt_timer: float = 0.0
var downed_timer: float = 0.0
var weapon_timer: float = 0.0
## The last Schupfn press counter acted on (InputMessage.schupfn_presses).
var schupfn_seen: int = 0
var deaths: int = 0
var damage_taken: float = 0.0
## The Knödl's largest mass this run.
var best_knodl_mass: float = 0.0


func _init(p_peer_id: int = 1, p_max_hp: float = 100.0) -> void:
	peer_id = p_peer_id
	max_hp = p_max_hp
	hp = p_max_hp


## Host: a hit. Returns true when it knocked the player down.
func hurt(amount: float, balance: BalanceData) -> bool:
	if downed or hurt_timer > 0.0 or amount <= 0.0:
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


## Host: XP in; returns how many levels were gained.
func add_xp(amount: float, balance: BalanceData) -> int:
	if amount <= 0.0:
		return 0
	xp += amount
	var new_level: int = Formulas.level_for_xp(xp, balance)
	var gained: int = new_level - level
	level = new_level
	return gained


## Host: counts the timers down. Returns true when a knocked-down player is back.
func tick(delta: float) -> bool:
	if hurt_timer > 0.0:
		hurt_timer -= delta
	if not downed:
		return false
	downed_timer -= delta
	if downed_timer > 0.0:
		return false
	downed = false
	hp = max_hp
	life = (life + 1) & 0xFF
	return true
