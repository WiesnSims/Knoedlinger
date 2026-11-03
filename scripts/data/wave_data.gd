class_name WaveData
extends Resource
## Which enemies a run sends and when. `enemies` lists every type the run uses (its index is the
## type id in snapshots, max 16); `entries` is the timeline that mixes them over the minutes. The
## crowd size ramps by the spawn numbers in balance.tres. Without entries every type spawns all the
## time by its EnemyTypeData.spawn_weight.

@export var id: StringName = &""
@export var enemies: Array[EnemyTypeData] = []
@export var entries: Array[WaveEntry] = []


## Spawn weight per entry of `enemies` at this run time.
func weights_at(seconds: float) -> PackedFloat32Array:
	var weights := PackedFloat32Array()
	weights.resize(enemies.size())
	weights.fill(0.0)
	if entries.is_empty():
		for t: int in enemies.size():
			weights[t] = enemies[t].spawn_weight
		return weights
	var minute: float = seconds / 60.0
	for entry: WaveEntry in entries:
		var t: int = enemies.find(entry.enemy)
		if t >= 0 and minute >= entry.from_minute and minute < entry.to_minute:
			weights[t] += entry.weight
	return weights
