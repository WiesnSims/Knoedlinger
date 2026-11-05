class_name RunSetup
extends RefCounted
## The run the main menu asked for (character, map). Command-line and URL flags still win, so the
## automated checks start runs exactly as before; the menu only fills in what they leave open.

static var character: String = "ferdl"
static var map: String = "kirtag"
## Grant level (index into GameContent.grants; 1 = Normal).
static var grant: int = 1
## The run's seed from the co-op room (the host rolls it); -1 = the default.
static var seed: int = -1
## The co-op room started this run: its character, map and Grant level count, not the flags.
static var from_room: bool = false
## True when the run was started from the main menu (its end screen and pause menu lead back there).
static var from_menu: bool = false


static func character_id() -> String:
	return character if from_room else LaunchArgs.get_string("character", character)


static func map_id() -> String:
	return map if from_room else LaunchArgs.get_string("map", map)


static func grant_index() -> int:
	return grant if from_room else LaunchArgs.get_int("grant", grant)
