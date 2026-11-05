class_name PatchNotes
extends Resource
## Every release, newest first (data/patch_notes/patch_notes.tres). A release adds its note on top;
## tests/unit/test_menu.gd checks that the newest one is the version in project.godot.

const PATH: String = "res://data/patch_notes/patch_notes.tres"

@export var notes: Array[PatchNote] = []


static func load_default() -> PatchNotes:
	return load(PATH)
