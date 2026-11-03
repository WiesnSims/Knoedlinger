class_name UiStyle
extends RefCounted
## The look shared by the menus and the HUD: dark, rounded, quiet panels with one accent colour per
## rarity, and the icon of every card. Nothing friendly is Krampus red (reserved for enemy attacks).

const PANEL := Color(0.11, 0.09, 0.08, 0.94)
const PANEL_HOVER := Color(0.17, 0.14, 0.12, 0.97)
const LINE := Color(0.36, 0.3, 0.25)
const TEXT := Color(0.97, 0.94, 0.88)
const MUTED := Color(0.72, 0.66, 0.58)
const GOLD := Color(1.0, 0.82, 0.35)
## Gewöhnlich, Fein, Edel, Hofratswürdig.
const RARITY: Array[Color] = [
	Color(0.78, 0.75, 0.68), Color(0.45, 0.72, 0.98), Color(0.74, 0.55, 0.98), Color(1.0, 0.8, 0.3),
]
const ICON_GOLD: String = "res://assets/icons/trinkgeld.svg"
const ICON_HEAL: String = "res://assets/icons/gulasch.svg"


static func rarity_color(rarity: int) -> Color:
	return RARITY[clampi(rarity, 0, RARITY.size() - 1)]


static func box(color: Color, radius: int = 14, margin: int = 14, border: Color = Color.TRANSPARENT,
		border_width: int = 0, shadow: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	style.border_color = border
	style.set_border_width_all(border_width)
	style.shadow_size = shadow
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.anti_aliasing = true
	return style


static func label(font_size: int, color: Color = TEXT) -> Label:
	var text := Label.new()
	text.add_theme_font_size_override("font_size", font_size)
	text.add_theme_color_override("font_color", color)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return text


## A flat pill button with a key hint ("R  Nochmal bitte").
static func pill(parent: Control) -> Button:
	var button := Button.new()
	button.add_theme_font_size_override("font_size", 16)
	button.custom_minimum_size = Vector2(0.0, 40.0)
	button.add_theme_stylebox_override("normal", box(Color(0.17, 0.14, 0.12, 0.92), 20, 10, LINE, 1))
	button.add_theme_stylebox_override("hover", box(Color(0.25, 0.2, 0.17, 0.96), 20, 10, GOLD, 1))
	button.add_theme_stylebox_override("pressed", box(Color(0.12, 0.1, 0.08, 0.96), 20, 10, GOLD, 1))
	button.add_theme_stylebox_override("focus", box(Color(0.25, 0.2, 0.17, 0.96), 20, 10, GOLD, 1))
	button.add_theme_stylebox_override("disabled", box(Color(0.12, 0.1, 0.09, 0.6), 20, 10, Color(0.25, 0.22, 0.2), 1))
	for state: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		button.add_theme_color_override(state, TEXT)
	button.add_theme_color_override("font_disabled_color", Color(0.5, 0.46, 0.42))
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button


static func card_icon(card: Card, catalog: UpgradeCatalog) -> Texture2D:
	match card.kind:
		Card.Kind.WEAPON, Card.Kind.EVOLUTION:
			return catalog.weapons[card.index].icon
		Card.Kind.PASSIVE:
			return catalog.passives[card.index].icon
		Card.Kind.GOLD:
			return load(ICON_GOLD)
	return load(ICON_HEAL)


## Highest level of the card's item (0 for gold and heal, which have none).
static func card_max_level(card: Card, catalog: UpgradeCatalog) -> int:
	match card.kind:
		Card.Kind.WEAPON:
			return catalog.weapons[card.index].max_level
		Card.Kind.PASSIVE:
			return catalog.passives[card.index].max_level
	return 0


static var _atlas: Dictionary[Texture2D, AtlasTexture] = {}


## The icons of a catalog packed into one texture (plus the fallback cards'), so the HUD draws all
## of them in one canvas batch instead of one draw call per icon. Call once per run.
static func build_icon_atlas(catalog: UpgradeCatalog) -> void:
	var icons: Array[Texture2D] = []
	for weapon: WeaponData in catalog.weapons:
		if weapon.icon != null and not icons.has(weapon.icon):
			icons.append(weapon.icon)
	for passive: PassiveData in catalog.passives:
		if passive.icon != null and not icons.has(passive.icon):
			icons.append(passive.icon)
	for path: String in [ICON_GOLD, ICON_HEAL]:
		icons.append(load(path))
	if icons.is_empty():
		return
	var cell: int = icons[0].get_width()
	var columns: int = ceili(sqrt(icons.size()))
	var sheet := Image.create_empty(columns * cell, ceili(float(icons.size()) / columns) * cell, false, Image.FORMAT_RGBA8)
	var placed: Array[Rect2] = []
	for k: int in icons.size():
		var image: Image = icons[k].get_image()
		image.convert(Image.FORMAT_RGBA8)
		if image.get_width() != cell or image.get_height() != cell:
			image.resize(cell, cell, Image.INTERPOLATE_LANCZOS)
		var at := Vector2i((k % columns) * cell, (k / columns) * cell)
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, Vector2i(cell, cell)), at)
		placed.append(Rect2(at, Vector2(cell, cell)))
	var texture := ImageTexture.create_from_image(sheet)
	_atlas.clear()
	for k: int in icons.size():
		var region := AtlasTexture.new()
		region.atlas = texture
		region.region = placed[k]
		_atlas[icons[k]] = region


## The atlas version of an icon (the icon itself until the atlas is built).
static func atlas_icon(icon: Texture2D) -> Texture2D:
	return _atlas.get(icon, icon)


static func icon_rect(texture: Texture2D, edge: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = atlas_icon(texture)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(edge, edge)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
