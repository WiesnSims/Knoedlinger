class_name ItemEffect
extends Resource
## One rule of an item (1.4, DECISIONS 6.7): when `trigger` happens (with `chance`), do `action`.
## Items list any number of these in ItemData.effects, so a new item is a .tres and no code. The host
## runs them (ItemProcs); procs never trigger procs. Per extra copy of the item a chance stacks as
## 1 - (1 - chance)^n and a value adds up (ItemProcs.stacked_*); `cap` limits what adds up.

enum Trigger {
	## A weapon hit lands (not burns, not the Knödl).
	ON_HIT,
	## An enemy the player's weapons hit dies.
	ON_KILL,
	## The player takes a hit.
	ON_HURT,
	## A hit would knock the player down (once per run per copy).
	ON_LETHAL,
	## The Marterl-Kerze (or the Stammtisch's Nachschlag) stood the player back up.
	ON_REVIVE,
	## Every `cooldown` seconds.
	PERIODIC,
	## Always on (rules like more proc chance, extra card rolls, no knockback).
	ALWAYS,
	## The player is below half their HP (DAMAGE scales with the HP missing).
	LOW_HP,
	## The player has stood still for `seconds`.
	STANDING_STILL,
	## The player is moving.
	MOVING,
	## The player's feet are off the ground.
	AIRBORNE,
	## The enemy hit has at least 90 % of its HP.
	TARGET_HEALTHY,
	## The enemy hit is an elite (drops gold) or a boss.
	TARGET_ELITE,
	## The enemy hit stands lower than the player.
	TARGET_BELOW,
	## The player cashes a Knödl in at a Wirtshaus.
	ON_CASHIN,
	## The player's Knödl soaks up Brösel.
	ON_BROSEL,
}

enum Action {
	## Freeze the enemy hit for `seconds` (bosses only slow down).
	FREEZE,
	## Set the enemy hit on fire: `value` × the hit per second for `seconds`.
	BURN,
	## A burst on the enemy hit: `value` × the hit to everything within `radius`.
	BLAST,
	## Lightning from the enemy hit to `cap` more within `radius`, `value` × the hit each.
	CHAIN,
	## A wisp flies from the kill to the nearest enemy within `radius`: `value` × base damage.
	WISP,
	## The enemy hit (not a boss) dies at once.
	EXECUTE,
	## The hit deals `value` times its damage.
	BIG_HIT,
	## Heal `value` HP (below 1: a share of max HP).
	HEAL,
	## Heal `value` HP per second while the trigger holds.
	REGEN,
	## Healing above max HP becomes a shield, up to `value` × max HP.
	SHIELD,
	## No damage for `seconds`.
	INVULNERABLE,
	## Every enemy within `radius` of the player freezes for `seconds`.
	TIME_STOP,
	## +`value` damage (a fraction) while the trigger holds.
	DAMAGE,
	## +`value` damage per kill, up to `cap`.
	DAMAGE_PER_KILL,
	## +`value` damage per execute, up to `cap` (goes with EXECUTE).
	DAMAGE_PER_EXECUTE,
	## A shock ring around the player: `value` × (1 + damage) to everything within `radius`.
	SHOCK,
	## The enemies touching the player take `value` × the hit back.
	THORNS,
	## Every proc chance × (1 + `value`).
	PROC_CHANCE,
	## Weapon cards on the Speisekarte roll `value` extra bonuses.
	EXTRA_ROLL,
	## Every Brösel within `radius` flies to the player's Knödl.
	PULL_BROSEL,
	## A Semmel drops that heals `value` HP.
	DROP_FOOD,
	## The Spagat cuts what it crosses: `value` × (1 + damage) per Brösel soaked (a few at a time).
	STRING_CUT,
	## On the string, the Knödl rolls `value` faster downhill.
	RODEL,
}

@export var trigger: Trigger = Trigger.ON_HIT
@export var action: Action = Action.FREEZE
## Chance per trigger (1 = always). Stacks per copy as 1 - (1 - chance)^n.
@export_range(0.0, 1.0) var chance: float = 1.0
## The action's strength (see Action); adds up per copy.
@export var value: float = 0.0
@export var radius: float = 0.0
@export var seconds: float = 0.0
## Seconds before it can happen again (PERIODIC: the period).
@export var cooldown: float = 0.0
## Upper limit of what adds up (DAMAGE_PER_KILL, DAMAGE_PER_EXECUTE) or how many jumps (CHAIN).
@export var cap: float = 0.0
