class_name Boot
extends Node
## The main scene: a plain start opens the main menu; any run option on the command line or in the
## URL (`bot=1`, `scene=stress`, `autoplay=1`, `--net=ws` ...) starts that scene directly, so the
## automated checks skip the menu (docs/DECISIONS.md, M4 plan).

const SCENES: Dictionary[String, String] = {
	"menu": "res://scenes/menu/main_menu.tscn",
	"run": "res://scenes/run/run_world.tscn",
	"stress": "res://scenes/stress/stress_arena.tscn",
}
## Options that change nothing about what to start.
## `room` is an invite link (?room=KNDL): the menu opens and joins that room; `coop` opens the
## menu on "Stammtisch aufmachen" (the co-op screenshots), `relay` points it at a test relay.
const NEUTRAL: Array[String] = ["mute", "debug", "log_slow", "room", "coop", "relay"]


func _ready() -> void:
	# Headless co-op room (--lobby): the Lobby autoload starts the run when the host does.
	if LaunchArgs.has("lobby"):
		print("[BOOT] waiting in the co-op room")
		return
	var wanted: String = LaunchArgs.get_string("scene", start_scene(LaunchArgs.keys()))
	if not SCENES.has(wanted):
		push_warning("Unknown scene '%s', starting the run." % wanted)
		wanted = "run"
	get_tree().change_scene_to_file.call_deferred(SCENES[wanted])


## "menu" without options, else "run".
static func start_scene(options: Array[String]) -> String:
	for key: String in options:
		if not NEUTRAL.has(key):
			return "run"
	return "menu"
