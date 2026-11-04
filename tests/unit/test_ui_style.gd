extends GutTest
## docs/UI-STYLE.md: one theme for every screen, no per-node overrides, three font sizes.

const UI_DIRS: Array[String] = ["res://scripts/ui", "res://scripts/systems"]


func _scripts() -> Dictionary[String, String]:
	var sources: Dictionary[String, String] = {}
	for dir_path: String in UI_DIRS:
		for file: String in DirAccess.get_files_at(dir_path):
			if file.ends_with(".gd"):
				var path: String = dir_path.path_join(file)
				sources[path] = FileAccess.get_file_as_string(path)
	return sources


func test_theme_is_project_wide() -> void:
	assert_eq(ProjectSettings.get_setting("gui/theme/custom"), UiStyle.THEME_PATH)
	assert_eq(ProjectSettings.get_setting("display/window/stretch/mode"), "canvas_items")
	assert_not_null(UiStyle.theme())


func test_no_theme_overrides_in_ui_code() -> void:
	for path: String in _scripts():
		assert_false(_scripts()[path].contains("add_theme_"), "%s uses a per-node theme override" % path)


func test_three_font_sizes() -> void:
	var theme: Theme = UiStyle.theme()
	var sizes: Dictionary[int, bool] = {theme.default_font_size: true}
	for type_name: StringName in theme.get_font_size_type_list():
		for size_name: StringName in theme.get_font_size_list(type_name):
			sizes[theme.get_font_size(size_name, type_name)] = true
	assert_eq(sizes.size(), 3, "font sizes in the theme: %s" % str(sizes.keys()))


func test_variations_used_in_code_exist() -> void:
	var theme: Theme = UiStyle.theme()
	var pattern := RegEx.create_from_string("&\"((?:Label|Hud|Card|Tile|Bar|Panel|Gap|Row|Keycap|Tight)[A-Za-z0-9]*)\"")
	for path: String in _scripts():
		for found: RegExMatch in pattern.search_all(_scripts()[path]):
			var name: String = found.get_string(1)
			assert_true(theme.is_type_variation(name, theme.get_type_variation_base(name)) and theme.get_type_variation_base(name) != &"",
					"%s uses unknown variation %s" % [path, name])
	for k: int in 4:
		assert_ne(theme.get_type_variation_base("CardRarity%d" % k), &"")
		assert_ne(theme.get_type_variation_base("TileRarity%d" % k), &"")


func test_spacing_on_the_grid() -> void:
	var theme: Theme = UiStyle.theme()
	for type_name: StringName in theme.get_constant_type_list():
		for constant: StringName in theme.get_constant_list(type_name):
			if constant.begins_with("separation") or constant.ends_with("_separation"):
				assert_eq(theme.get_constant(constant, type_name) % 4, 0, "%s/%s off the grid" % [type_name, constant])


func test_change_line_names_the_gain() -> void:
	var catalog: UpgradeCatalog = load("res://data/catalog/catalog.tres")
	var balance: BalanceData = load("res://data/balance.tres")
	var card := Card.new()
	card.kind = Card.Kind.WEAPON
	card.index = 0
	card.level = 2
	var text: String = Speisekarte.change_text(card, catalog, balance, null)
	assert_true(text.begins_with("+"), "weapon level line: %s" % text)
	card.level = 1
	assert_eq(Speisekarte.change_text(card, catalog, balance, null), TranslationServer.translate("CARD_NEW"))
