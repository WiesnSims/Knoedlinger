class_name EnemyTypeData
extends Resource
## One enemy type. EnemyManager keeps enemies as packed arrays; this only holds their numbers and look.

@export var id: StringName = &""
## Translation key of the player-facing name.
@export var name_key: String = ""
## Translation key of its deadpan line in the Almanach.
@export var desc_key: String = ""
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
## A flier rises up to this many metres to reach a player (or Knödl) in the air; 0 = stays low.
@export var air_reach: float = 0.0
## Share of the spawn mix when the wave has no timeline (relative weight).
@export var spawn_weight: float = 1.0
## Bröselfresser (GAME-DESIGN.md): goes for the nearest Knödl instead of a player and eats this
## much of its mass per second while touching it.
@export var eats_knodl: bool = false
@export var bite_per_second: float = 0.0
## Elites: one telegraphed attack (null = it only hurts by touch).
@export var attack: AttackData
## Bosses are not moved by the crowd logic; BossDirector moves them and runs their BossData.
@export var boss: bool = false
## On death it falls apart into this many of another type (Akten-Geist: 3 Formulare).
@export var split_into: EnemyTypeData
@export var split_count: int = 0
## Gold coins it drops on death (elites and bosses).
@export var gold_drop: int = 0
## Which model MeshFactory builds: "" = the plain fodder figure, or perchte, radler, akten,
## formular, krampus, hofrat.
@export var look: StringName = &""
## What it says now and then (EnemyVoices); null = it keeps quiet (Gelsen, the Lawine).
@export var voice: VoiceLineSet

@export_group("Behaviour")
## Pops up this close to a player instead of on the far ring (Wühlmaus); 0 = the normal ring.
@export var spawn_near: float = 0.0
## Circles its target at this distance instead of walking into it (Rasenmäher-Roboter); 0 = no.
@export var orbit_distance: float = 0.0
## Stops coming closer than this and attacks from there (Schneemann); 0 = walks right up.
@export var keep_distance: float = 0.0
## A mark it leaves where it dies (Gartenzwerg: it explodes).
@export var death_attack: AttackData
## Stands at the door of an open Wirtshaus, and the Wirt serves nobody until it is beaten (Kontrolleur).
@export var guards_wirtshaus: bool = false
