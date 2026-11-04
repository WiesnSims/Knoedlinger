extends SceneTree
## Builds ui/theme.tres, the one theme every screen uses (docs/UI-STYLE.md): the palette, the two
## fonts in three sizes, and the type variations (LabelSmall, CardRarity1, BarHp ...). Change the
## look here, then regenerate:  godot --headless --path . -s tools/ui/make_theme.gd

const OUT: String = "res://ui/theme.tres"

const PANEL := Color("12141a", 0.88)
const PANEL_RAISED := Color("1e222b", 0.92)
const PANEL_HOVER := Color("2a2f3a", 0.96)
const LINE := Color(1.0, 1.0, 1.0, 0.1)
const TEXT := Color("f5f1e8")
const MUTED := Color("9a9aa6")
const ACCENT := Color("ffc94a")
const DANGER := Color("e5383b")
const HP := Color("e9738b")
const SHADOW := Color(0.0, 0.0, 0.0, 0.55)
## Gewöhnlich, Fein, Edel, Hofratswürdig.
const RARITY: Array[Color] = [Color("b8b8c0"), Color("5ccb6b"), Color("4aa3ff"), Color("b57bff")]

const SMALL: int = 14
const BODY: int = 20
const DISPLAY: int = 32


func _init() -> void:
	var theme := Theme.new()
	var nunito: FontFile = load("res://assets/fonts/nunito.ttf")
	var grenze: FontFile = load("res://assets/fonts/grenze_gotisch.ttf")
	var bold: FontVariation = _weight(nunito, 700)
	var extra: FontVariation = _weight(nunito, 800)
	var black: FontVariation = _weight(nunito, 900)
	var title: FontVariation = _weight(grenze, 700)
	theme.default_font = extra
	theme.default_font_size = BODY

	# The palette, for widgets that draw themselves (pips, bars, the Krügerl).
	var palette: Dictionary[String, Color] = {
		"panel": PANEL, "panel_raised": PANEL_RAISED, "panel_hover": PANEL_HOVER, "line": LINE,
		"text": TEXT, "muted": MUTED, "accent": ACCENT, "danger": DANGER, "hp": HP, "shadow": SHADOW,
		"evolution": ACCENT, "track": Color(0.0, 0.0, 0.0, 0.45),
		"xp": ACCENT, "beer": Color("f2b233"), "foam": Color("fff6e0"), "glass": Color(1.0, 1.0, 1.0, 0.22),
		"knodl": Color("efd9a0"), "knodl_edge": Color("b08a48"),
	}
	for k: int in RARITY.size():
		palette["rarity_%d" % k] = RARITY[k]
	for key: String in palette:
		theme.set_color(key, "Palette", palette[key])
	theme.set_font_size("small", "Palette", SMALL)
	theme.set_font_size("body", "Palette", BODY)
	theme.set_font_size("display", "Palette", DISPLAY)
	theme.set_font("bold", "Palette", bold)
	theme.set_font("number", "Palette", black)
	theme.set_font("title", "Palette", title)
	theme.set_constant("pad", "Palette", 16)
	theme.set_constant("gap", "Palette", 8)

	# Labels.
	theme.set_color("font_color", "Label", TEXT)
	_label(theme, "LabelSmall", bold, SMALL, TEXT)
	_label(theme, "LabelMuted", bold, SMALL, MUTED)
	_label(theme, "LabelAccent", extra, BODY, ACCENT)
	_label(theme, "LabelTitle", title, DISPLAY, TEXT)
	_label(theme, "LabelNumber", black, DISPLAY, TEXT)
	_label(theme, "LabelChange", extra, SMALL, ACCENT)
	for name: String in ["HudLabel", "HudSmall", "HudNumber", "HudAccent"]:
		var font: Font = {"HudLabel": extra, "HudSmall": bold, "HudNumber": black, "HudAccent": extra}[name]
		var font_size: int = {"HudLabel": BODY, "HudSmall": SMALL, "HudNumber": DISPLAY, "HudAccent": BODY}[name]
		_label(theme, name, font, font_size, ACCENT if name == "HudAccent" else TEXT)
		theme.set_color("font_shadow_color", name, SHADOW)
		theme.set_constant("shadow_offset_x", name, 0)
		theme.set_constant("shadow_offset_y", name, 2)
		theme.set_constant("shadow_outline_size", name, 6)
	_label(theme, "Keycap", bold, SMALL, MUTED)
	var keycap := _box(PANEL_RAISED, 4, LINE, 1)
	keycap.content_margin_left = 6
	keycap.content_margin_right = 6
	keycap.content_margin_top = 0
	keycap.content_margin_bottom = 0
	theme.set_stylebox("normal", "Keycap", keycap)

	# Panels.
	var panel := _box(PANEL, 8, LINE, 1, 16)
	panel.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	panel.shadow_size = 8
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)
	_panel(theme, "PanelRaised", _box(PANEL_RAISED, 6, Color.TRANSPARENT, 0, 8))
	var header := _box(Color(1.0, 1.0, 1.0, 0.04), 8, Color.TRANSPARENT, 0, 16)
	header.content_margin_top = 8
	header.content_margin_bottom = 8
	_panel(theme, "PanelHeader", header)
	var hud := _box(Color("12141a", 0.62), 8, Color(1.0, 1.0, 1.0, 0.06), 1, 8)
	_panel(theme, "HudPanel", hud)
	_panel(theme, "PanelClear", _box(Color.TRANSPARENT, 0, Color.TRANSPARENT, 0, 0))

	# Buttons: quiet pills that light up in the accent.
	var normal := _pill(PANEL_RAISED, LINE, 1)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", _pill(PANEL_HOVER, ACCENT, 1))
	theme.set_stylebox("focus", "Button", _pill(Color.TRANSPARENT, ACCENT, 2))
	theme.set_stylebox("pressed", "Button", _pill(Color("2a2f3a"), ACCENT, 2))
	theme.set_stylebox("hover_pressed", "Button", _pill(Color("2a2f3a"), ACCENT, 2))
	theme.set_stylebox("disabled", "Button", _pill(Color(PANEL_RAISED, 0.5), Color(1.0, 1.0, 1.0, 0.04), 1))
	for state: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(state, "Button", TEXT)
	theme.set_color("font_disabled_color", "Button", Color(MUTED, 0.5))
	theme.set_font("font", "Button", extra)
	theme.set_font_size("font_size", "Button", BODY)
	theme.set_constant("h_separation", "Button", 8)

	# Main menu entries: quiet rows that get a gold bar on the left when hovered or focused.
	theme.set_type_variation("MenuEntry", "Button")
	var entry := _box(Color.TRANSPARENT, 6, Color.TRANSPARENT, 0, 8)
	entry.content_margin_left = 16
	entry.content_margin_right = 16
	theme.set_stylebox("normal", "MenuEntry", entry)
	var entry_lit := _box(PANEL_HOVER, 2, ACCENT, 0, 8)
	entry_lit.border_width_left = 4
	entry_lit.content_margin_left = 16
	entry_lit.content_margin_right = 16
	for state: String in ["hover", "pressed", "hover_pressed"]:
		theme.set_stylebox(state, "MenuEntry", entry_lit)
	var entry_focus := entry_lit.duplicate() as StyleBoxFlat
	entry_focus.bg_color = Color.TRANSPARENT
	theme.set_stylebox("focus", "MenuEntry", entry_focus)
	theme.set_stylebox("disabled", "MenuEntry", entry)
	theme.set_color("font_hover_color", "MenuEntry", ACCENT)
	theme.set_color("font_focus_color", "MenuEntry", ACCENT)
	theme.set_color("font_disabled_color", "MenuEntry", Color(MUTED, 0.45))

	# Text fields (the player name).
	theme.set_stylebox("normal", "LineEdit", _box(PANEL_RAISED, 6, LINE, 1, 8))
	theme.set_stylebox("focus", "LineEdit", _box(Color.TRANSPARENT, 6, ACCENT, 2, 8))
	theme.set_stylebox("read_only", "LineEdit", _box(Color(PANEL_RAISED, 0.5), 6, LINE, 1, 8))
	theme.set_font("font", "LineEdit", extra)
	theme.set_font_size("font_size", "LineEdit", BODY)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.7))
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("selection_color", "LineEdit", Color(ACCENT, 0.3))

	# Speisekarte rows and item tiles: the border is the rarity.
	var accents: Dictionary[String, Color] = {"Evolution": ACCENT}
	for k: int in RARITY.size():
		accents["Rarity%d" % k] = RARITY[k]
	for suffix: String in accents:
		var color: Color = accents[suffix]
		var card: String = "Card" + suffix
		theme.set_type_variation(card, "Button")
		theme.set_stylebox("normal", card, _card(PANEL_RAISED, color.darkened(0.15), 2, 0))
		theme.set_stylebox("hover", card, _card(PANEL_HOVER, color.lightened(0.15), 3, 10, color))
		theme.set_stylebox("focus", card, _card(Color.TRANSPARENT, color.lightened(0.15), 3, 0))
		theme.set_stylebox("pressed", card, _card(PANEL_HOVER, color.lightened(0.3), 3, 14, color))
		theme.set_stylebox("hover_pressed", card, _card(PANEL_HOVER, color.lightened(0.3), 3, 14, color))
		theme.set_stylebox("disabled", card, _card(Color(PANEL_RAISED, 0.5), Color(color, 0.3), 2, 0))
		var tile: String = "Tile" + suffix
		theme.set_type_variation(tile, "PanelContainer")
		theme.set_stylebox("panel", tile, _box(PANEL_RAISED, 6, color, 2, 4))
	_panel(theme, "TileEmpty", _box(Color(1.0, 1.0, 1.0, 0.03), 6, Color(1.0, 1.0, 1.0, 0.08), 1, 4))

	# Tooltips (inventory tiles).
	theme.set_stylebox("panel", "TooltipPanel", _box(Color("12141a", 0.96), 6, LINE, 1, 8))
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_font("font", "TooltipLabel", bold)
	theme.set_font_size("font_size", "TooltipLabel", SMALL)

	# Bars.
	var bars: Dictionary[String, Color] = {"BarHp": HP, "BarXp": ACCENT, "BarBoss": DANGER, "BarTimer": ACCENT}
	for bar: String in bars:
		theme.set_type_variation(bar, "ProgressBar")
		theme.set_stylebox("background", bar, _box(Color(0.0, 0.0, 0.0, 0.45), 4, Color.TRANSPARENT, 0, 0))
		theme.set_stylebox("fill", bar, _box(bars[bar], 4, Color.TRANSPARENT, 0, 0))
		theme.set_font_size("font_size", bar, SMALL)

	# Containers on the grid.
	theme.set_constant("separation", "VBoxContainer", 8)
	theme.set_constant("separation", "HBoxContainer", 8)
	theme.set_constant("h_separation", "GridContainer", 8)
	theme.set_constant("v_separation", "GridContainer", 8)
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		theme.set_constant(side, "MarginContainer", 0)
	theme.set_type_variation("Gap16", "VBoxContainer")
	theme.set_constant("separation", "Gap16", 16)
	theme.set_type_variation("Gap24", "VBoxContainer")
	theme.set_constant("separation", "Gap24", 24)
	theme.set_type_variation("Row16", "HBoxContainer")
	theme.set_constant("separation", "Row16", 16)
	theme.set_type_variation("Row32", "HBoxContainer")
	theme.set_constant("separation", "Row32", 32)
	theme.set_type_variation("Tight", "VBoxContainer")
	theme.set_constant("separation", "Tight", 0)
	theme.set_type_variation("Row4", "HBoxContainer")
	theme.set_constant("separation", "Row4", 4)
	theme.set_type_variation("Row24", "HBoxContainer")
	theme.set_constant("separation", "Row24", 24)
	theme.set_type_variation("Gap32", "VBoxContainer")
	theme.set_constant("separation", "Gap32", 32)
	theme.set_type_variation("Gap4", "VBoxContainer")
	theme.set_constant("separation", "Gap4", 4)

	var error: int = ResourceSaver.save(theme, OUT)
	if error != OK:
		push_error("could not save %s (%d)" % [OUT, error])
		quit(1)
		return
	print("saved %s" % OUT)
	quit(0)


func _weight(base: FontFile, weight: int) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = base
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return font


func _label(theme: Theme, name: String, font: Font, font_size: int, color: Color) -> void:
	theme.set_type_variation(name, "Label")
	theme.set_font("font", name, font)
	theme.set_font_size("font_size", name, font_size)
	theme.set_color("font_color", name, color)


func _panel(theme: Theme, name: String, style: StyleBox) -> void:
	theme.set_type_variation(name, "PanelContainer")
	theme.set_stylebox("panel", name, style)


func _box(color: Color, radius: int, border: Color, border_width: int, margin: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_content_margin_all(margin)
	style.anti_aliasing = true
	return style


func _pill(color: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := _box(color, 20, border, width, 8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	return style


func _card(color: Color, border: Color, width: int, glow: int, glow_color: Color = Color.BLACK) -> StyleBoxFlat:
	var style := _box(color, 8, border, width, 0)
	style.shadow_size = glow
	style.shadow_color = Color(glow_color, 0.35)
	return style
