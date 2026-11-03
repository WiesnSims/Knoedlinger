class_name WaveData
extends Resource
## Which enemies a run sends. M1: one list, mixed by EnemyTypeData.spawn_weight and ramped up by the
## spawn numbers in balance.tres; the timeline (events, elites, bosses) comes in M2/M3.

@export var id: StringName = &""
@export var enemies: Array[EnemyTypeData] = []
