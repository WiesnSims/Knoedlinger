class_name AttackData
extends Resource
## One telegraphed enemy attack (GAME-DESIGN.md pillar 6: every attack is shown first as a
## Krampus-red mark on the ground). The enemy stops, the mark fills up for `telegraph` seconds,
## then everyone inside it is hit. Elites carry one; bosses list several in their BossData.

## CIRCLE: a disc of `radius`. LINE: a strip `radius` wide on each side and `length` long.
enum Shape { CIRCLE, LINE }
## Where it lands: on the target player, around the attacker, or (LINE) from the attacker toward
## the target. RING: `count` circles evenly around the attacker at `spread` metres.
enum Aim { TARGET, SELF, RING }

@export var id: StringName = &""
@export var shape: Shape = Shape.CIRCLE
@export var aim: Aim = Aim.TARGET
@export var radius: float = 3.0
@export var length: float = 12.0
## Seconds between the mark appearing and the hit.
@export var telegraph: float = 1.0
@export var damage: float = 15.0
## Seconds before the same attacker may use it again.
@export var cooldown: float = 5.0
## An enemy only starts it when its target is this close.
@export var range: float = 6.0
## How many marks (TARGET: scattered `spread` metres around the target; RING: around the attacker).
@export var count: int = 1
@export var spread: float = 0.0
## LINE: the attacker dashes along the line when it hits (the Radlfahrer, the Oberkrampus' charge).
@export var dash: bool = false
## Enemies that appear when it hits (the Hofrat's Warteschlange); one per mark.
@export var summon: EnemyTypeData
@export var summon_count: int = 0
## Translation key of a toast shown to everyone when a boss uses it ("" = none).
@export var toast_key: String = ""
