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
## Procedural low-poly look for the stress test: body colour, head colour, and whether it flies.
@export var body_color: Color = Color(0.4, 0.6, 0.3)
@export var head_color: Color = Color(0.9, 0.75, 0.6)
@export var flying: bool = false
## Share of the spawn mix (relative weight).
@export var spawn_weight: float = 1.0
