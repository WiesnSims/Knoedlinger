class_name WaveEntry
extends Resource
## One line of a run's timeline: this enemy joins the spawn mix from `from_minute` until
## `to_minute` with this weight.

@export var enemy: EnemyTypeData
@export var from_minute: float = 0.0
@export var to_minute: float = 15.0
@export var weight: float = 1.0
