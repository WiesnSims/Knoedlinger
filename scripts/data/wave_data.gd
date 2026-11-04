class_name WaveData
extends Resource
## Which enemies a run sends and when. `enemies` lists every type the run uses (its index is the
## type id in snapshots, max 16); `entries` is the timeline that mixes them over the minutes. The
## crowd size ramps by the spawn numbers in balance.tres. Without entries every type spawns all the
## time by its EnemyTypeData.spawn_weight.

@export var id: StringName = &""
@export var enemies: Array[EnemyTypeData] = []
@export var entries: Array[WaveEntry] = []
## Mini-bosses on the clock.
@export var bosses: Array[WaveBoss] = []
## The main boss behind the gate (GAME-DESIGN.md "Run timeline"): at formular_minute the Formular
## appears (collect the Stempel to open the gate); at final_boss_minute he comes out anyway.
@export var final_boss: BossData
@export var formular_minute: float = 10.0
@export var final_boss_minute: float = 12.0
## The Touristenbus: for bus_seconds from bus_minute the crowd comes from one direction, with
## bus_extra more enemies.
@export var bus_minute: float = 8.0
@export var bus_seconds: float = 45.0
@export var bus_extra: int = 80


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
