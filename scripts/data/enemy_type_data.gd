class_name EnemyTypeData
extends Resource
## One enemy type. EnemyManager keeps enemies as packed arrays; this only holds their numbers and look.

@export var id: StringName = &""
## Translation key of the player-facing name.
@export var name_key: String = ""
@export var max_hp: float = 3.0
@export var speed: float = 3.0
@export var radius: float = 0.4
@export var model_scale: float = 1.0
## Damage per touch on a player (the player is invulnerable for player_hurt_cooldown afterwards).
@export var contact_damage: float = 5.0
## XP of the Brösel it drops on death (one of balance.brosel_values, or a sum of them).
@export var brosel_xp: int = 1
## How much knockback moves it: 1 = normal, 0 = immovable.
@export var knockback_factor: float = 1.0
## Procedural low-poly look for now: body colour, head colour, and whether it flies.
@export var body_color: Color = Color(0.4, 0.6, 0.3)
@export var head_color: Color = Color(0.9, 0.75, 0.6)
@export var flying: bool = false
## Share of the spawn mix when the wave has no timeline (relative weight).
@export var spawn_weight: float = 1.0
## Bröselfresser (GAME-DESIGN.md): goes for the nearest Knödl instead of a player and eats this
## much of its mass per second while touching it.
@export var eats_knodl: bool = false
@export var bite_per_second: float = 0.0
