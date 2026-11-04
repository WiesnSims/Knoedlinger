extends GutTest
## M4: main menu, settings and the run setup.

const BOOT := preload("res://scripts/core/boot.gd")


func test_plain_start_opens_the_menu() -> void:
	assert_eq(BOOT.start_scene([]), "menu")
	assert_eq(BOOT.start_scene(["mute"]), "menu")
	assert_eq(BOOT.start_scene(["mute", "debug"]), "menu")


func test_run_options_skip_the_menu() -> void:
	for option: String in ["bot", "autoplay", "net", "enemies", "character", "start_time", "seconds"]:
		assert_eq(BOOT.start_scene([option]), "run", option)


func test_player_name_is_cleaned() -> void:
	assert_eq(Settings.clean_name("  Resi  "), "Resi")
	assert_eq(Settings.clean_name("Onkel   Ferdl"), "Onkel Ferdl")
	assert_eq(Settings.clean_name("<b>Hofrat</b>"), "bHofrat/b")
	assert_eq(Settings.clean_name("Ein sehr langer Name der nicht passt").length(), Settings.NAME_MAX)
	assert_eq(Settings.clean_name("   "), "")


func test_settings_clamp_and_snap() -> void:
	var before: float = Settings.get_float(&"camera_fov")
	Settings.set_value(&"camera_fov", 500.0)
	assert_eq(Settings.get_float(&"camera_fov"), 100.0)
	Settings.set_value(&"camera_fov", before)
	assert_false(Settings.persistent, "tests never touch the player's settings file")


func test_content_lists_characters_and_maps() -> void:
	var content: GameContent = GameContent.load_default()
	assert_gt(content.characters.size(), 0)
	assert_gt(content.maps.size(), 0)
	for character: CharacterData in content.characters:
		assert_not_null(character.start_weapon, String(character.id))
		assert_not_null(character.knodl_sort, String(character.id))
		assert_ne(character.role_key, "", String(character.id))
	for info: MapInfo in content.maps:
		assert_true(ResourceLoader.exists("res://data/maps/%s.tres" % info.id), String(info.id))
	assert_not_null(content.character(&"ferdl"))
	assert_eq(RunSetup.character_id(), RunSetup.character)


func test_every_scene_script_compiles() -> void:
	# Scripts only the scenes load (not the tests) would otherwise hide a parse error until a run.
	for path: String in ["res://scripts/run/run_world.gd", "res://scripts/menu/main_menu.gd",
			"res://scripts/stress/stress_arena.gd", "res://scripts/core/boot.gd"]:
		var script: GDScript = load(path)
		assert_not_null(script, path)
		assert_true(script != null and script.can_instantiate(), path)
