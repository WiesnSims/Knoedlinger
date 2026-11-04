class_name BossData
extends Resource
## A boss (GAME-DESIGN.md: Oberkrampus, Hofrat der Unterwelt ...). Its body is an enemy type in the
## wave's list (so weapons, the Knödl and snapshots treat it like any enemy); BossDirector moves it
## and runs its attacks one after another with a pause between, faster once it is badly hurt.

@export var id: StringName = &""
@export var name_key: String = ""
## Toasts when it arrives and when it is beaten.
@export var intro_key: String = ""
@export var defeat_key: String = ""
## Its body in WaveData.enemies (EnemyTypeData.boss = true).
@export var enemy: EnemyTypeData
## HP before co-op scaling (balance.coop_boss_hp_per_player); not scaled by the run clock.
@export var max_hp: float = 1000.0
@export var speed: float = 3.0
## Used in turn; each starts from where the boss stands toward the nearest player.
@export var attacks: Array[AttackData] = []
@export var attack_pause: float = 2.5
## Below this share of its HP the pauses shrink by enraged_pause_mult.
@export var enraged_below: float = 0.5
@export var enraged_pause_mult: float = 0.6
## Enemies that come with it.
@export var escort: EnemyTypeData
@export var escort_count: int = 0
## Its reward: a chest with this many items (evolutions first when chest_evolution), gold coins and
## golden Kaiserschmarrn bits (100 XP each).
@export var chest_items: int = 3
@export var chest_evolution: bool = false
@export var gold: int = 30
@export var golden_brosel: int = 3
## Beating it wins the run at Sperrstund' (the Hofrat).
@export var final: bool = false
## Bosses that do not come through the gate appear this far from a player.
@export var arrive_distance: float = 20.0
