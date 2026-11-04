class_name RunSetup
extends RefCounted
## The run the main menu asked for (character, map). Command-line and URL flags still win, so the
## automated checks start runs exactly as before; the menu only fills in what they leave open.

static var character: String = "ferdl"
static var map: String = "kirtag"
## Grant level (index into GameContent.grants; 1 = Normal).
static var grant: int = 1
## True when the run was started from the main menu (its end screen and pause menu lead back there).
static var from_menu: bool = false


static func character_id() -> String:
	return LaunchArgs.get_string("character", character)


static func map_id() -> String:
	return LaunchArgs.get_string("map", map)
