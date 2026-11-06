class_name TileGrid
extends Control
## A grid of build tiles (icon, level in the corner, frame by rarity) drawn by one control: all
## frames first, then all icons (one atlas), then all numbers. One PanelContainer, TextureRect and
## Label per tile cost about three draw calls each in the Compatibility renderer; this costs about
## four for the whole grid. Colours, font and gaps still come from the theme (Tile* styles,
## HudSmall, GridContainer). Tooltips show the tile under the mouse; a `selectable` grid (1.4 build
## view) instead reports the tile under the mouse, a tap or the pad/keyboard focus (`picked`) and rings
## it in the accent colour, so a detail panel can say what it is.

signal picked(index: int)

## One tile: icon (null = free slot), level (0 = none shown), the theme variation of its frame.
class Tile:
	var icon: Texture2D
	var level: int = 0
	var variation: StringName = &"TileEmpty"
	var tooltip: String = ""

const TEXTURE_CELL: int = 64

static var _shapes: ImageTexture

var columns: int = 6
var edge: float = 40.0
var selectable: bool = false
var selected: int = -1
var _tiles: Array[Tile] = []


func _init(p_columns: int = 6, p_edge: float = 40.0) -> void:
	columns = p_columns
	edge = p_edge
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_selectable(on: bool) -> void:
	selectable = on
	focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_PASS
	if on and not focus_entered.is_connected(_on_focus):
		focus_entered.connect(_on_focus)
		focus_exited.connect(queue_redraw)


## Rings tile `index` (-1 = none) and says so.
func select(index: int) -> void:
	index = clampi(index, -1, _owned_count() - 1)
	if index == selected:
		return
	selected = index
	queue_redraw()
	if index >= 0:
		picked.emit(index)


func set_tiles(tiles: Array[Tile]) -> void:
	_tiles = tiles
	if selected >= _owned_count():
		selected = -1
	var rows: int = ceili(float(tiles.size()) / columns)
	var gap: Vector2 = _gap()
	custom_minimum_size = Vector2(
			mini(tiles.size(), columns) * (edge + gap.x) - gap.x if not tiles.is_empty() else 0.0,
			rows * (edge + gap.y) - gap.y if rows > 0 else 0.0)
	queue_redraw()


func tile_count() -> int:
	return _tiles.size()


func _get_tooltip(at: Vector2) -> String:
	if selectable:
		return ""
	for k: int in _tiles.size():
		if _rect(k).has_point(at):
			return _tiles[k].tooltip
	return ""


func _draw() -> void:
	var shapes: ImageTexture = _shape_texture()
	var cell := float(TEXTURE_CELL)
	for k: int in _tiles.size():
		var style: StyleBoxFlat = get_theme_stylebox("panel", _tiles[k].variation) as StyleBoxFlat
		if style != null:
			draw_texture_rect_region(shapes, _rect(k), Rect2(0.0, 0.0, cell, cell), style.bg_color)
	for k: int in _tiles.size():
		var style: StyleBoxFlat = get_theme_stylebox("panel", _tiles[k].variation) as StyleBoxFlat
		if style != null and style.border_width_left > 0:
			var ring: float = cell * (1.0 if style.border_width_left >= 2 else 2.0)
			draw_texture_rect_region(shapes, _rect(k), Rect2(ring, 0.0, cell, cell), style.border_color)
	for k: int in _tiles.size():
		if _tiles[k].icon != null:
			draw_texture_rect(UiStyle.atlas_icon(_tiles[k].icon), _rect(k).grow(-4.0), false)
	if selectable and selected >= 0 and selected < _tiles.size():
		var accent: Color = UiStyle.color("accent")
		if not has_focus():
			accent.a = 0.6
		draw_texture_rect_region(shapes, _rect(selected).grow(4.0), Rect2(cell, 0.0, cell, cell), accent)
	var font: Font = get_theme_font("font", &"HudSmall")
	var font_size: int = get_theme_font_size("font_size", &"HudSmall")
	var shadow: Color = get_theme_color("font_shadow_color", &"HudSmall")
	var shadow_size: int = get_theme_constant("shadow_outline_size", &"HudSmall")
	var shadow_offset := Vector2(get_theme_constant("shadow_offset_x", &"HudSmall"),
			get_theme_constant("shadow_offset_y", &"HudSmall"))
	var color: Color = get_theme_color("font_color", &"HudSmall")
	var spots: Array[Vector2] = []
	for k: int in _tiles.size():
		var text: String = str(_tiles[k].level) if _tiles[k].level > 0 else ""
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var corner: Vector2 = _rect(k).end - Vector2(4.0, 4.0)
		spots.append(Vector2(corner.x - width, corner.y - font.get_descent(font_size)))
	for k: int in _tiles.size():
		if _tiles[k].level > 0:
			draw_string_outline(font, spots[k] + shadow_offset, str(_tiles[k].level), HORIZONTAL_ALIGNMENT_LEFT,
					-1, font_size, shadow_size, shadow)
	for k: int in _tiles.size():
		if _tiles[k].level > 0:
			draw_string(font, spots[k], str(_tiles[k].level), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _gui_input(event: InputEvent) -> void:
	if not selectable:
		return
	var motion := event as InputEventMouseMotion
	var press := event as InputEventMouseButton
	var touch := event as InputEventScreenTouch
	if motion != null or (press != null and press.pressed) or (touch != null and touch.pressed):
		var at: Vector2 = (event as InputEventMouse).position if event is InputEventMouse else touch.position
		var index: int = _index_at(at)
		if index >= 0:
			select(index)
			if press != null or touch != null:
				grab_focus()
				accept_event()
		return
	if not has_focus():
		return
	var step: int = 0
	if event.is_action_pressed(&"ui_left"):
		step = -1 if selected % columns > 0 else 0
	elif event.is_action_pressed(&"ui_right"):
		step = 1 if selected % columns < columns - 1 and selected + 1 < _owned_count() else 0
	elif event.is_action_pressed(&"ui_up"):
		step = -columns if selected - columns >= 0 else 0
	elif event.is_action_pressed(&"ui_down"):
		step = columns if selected + columns < _owned_count() else 0
	else:
		return
	# At an edge the event goes on, so the focus moves to the next control.
	if step != 0:
		select(selected + step)
		accept_event()


func _on_focus() -> void:
	if selected < 0 and _owned_count() > 0:
		select(0)
	queue_redraw()


func _index_at(at: Vector2) -> int:
	for k: int in _owned_count():
		if _rect(k).grow(2.0).has_point(at):
			return k
	return -1


## Tiles with something in them (free slots come last and cannot be picked).
func _owned_count() -> int:
	var count: int = 0
	for tile: Tile in _tiles:
		if tile.icon != null:
			count += 1
	return count


func _gap() -> Vector2:
	return Vector2(get_theme_constant("h_separation", &"GridContainer"),
			get_theme_constant("v_separation", &"GridContainer"))


func _rect(k: int) -> Rect2:
	var gap: Vector2 = _gap()
	return Rect2(Vector2((k % columns) * (edge + gap.x), (k / columns) * (edge + gap.y)), Vector2(edge, edge))


## White shapes the tiles are tinted from, side by side: the rounded fill, the 2 px frame and the
## 1 px frame (radius 6 px at the 40 px tile edge, like the Tile* styles), antialiased.
static func _shape_texture() -> ImageTexture:
	if _shapes != null:
		return _shapes
	var cell: int = TEXTURE_CELL
	var scale: float = cell / 40.0
	var image := Image.create_empty(cell * 3, cell, false, Image.FORMAT_RGBA8)
	var half: float = cell * 0.5
	var radius: float = 6.0 * scale
	for y: int in cell:
		for x: int in cell:
			# Signed distance to the rounded square (negative inside).
			var q := Vector2(absf(x + 0.5 - half), absf(y + 0.5 - half)) - Vector2(half - radius, half - radius)
			var outside: float = Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius
			var fill: float = clampf(0.5 - outside, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, fill))
			for ring: int in [1, 2]:
				var width: float = (2.0 if ring == 1 else 1.0) * scale
				var inner: float = clampf(0.5 - (outside + width), 0.0, 1.0)
				image.set_pixel(x + cell * ring, y, Color(1.0, 1.0, 1.0, maxf(fill - inner, 0.0)))
	_shapes = ImageTexture.create_from_image(image)
	return _shapes
