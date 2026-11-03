extends Node
## The main scene: picks what to run from LaunchArgs (`--scene=stress` / `?scene=stress`), the
## game run by default.

const SCENES: Dictionary[String, String] = {
	"run": "res://scenes/run/run_world.tscn",
	"stress": "res://scenes/stress/stress_arena.tscn",
}


func _ready() -> void:
	var wanted: String = LaunchArgs.get_string("scene", "run")
	if not SCENES.has(wanted):
		push_warning("Unknown scene '%s', starting the run." % wanted)
		wanted = "run"
	get_tree().change_scene_to_file.call_deferred(SCENES[wanted])
