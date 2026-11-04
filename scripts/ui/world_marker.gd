class_name WorldMarker
extends Control
## A small pill over a place in the world (Wirtshaus, Stempel, gate, boss): a coloured dot and a
## short text with the distance, pinned to the screen edge when the place is off screen
## (docs/UI-STYLE.md: world markers are icon pills, not floating sentences).

const HEIGHT: float = 24.0

var text: String = ""
## Palette colour of the dot ("accent", "danger", "rarity_1" ...).
var tone: String = "accent"
var _font: Font
var _font_size: int = 14
var _box := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UiStyle.font("bold")
	_font_size = UiStyle.font_size("small")
	_box.bg_color = UiStyle.color("panel")
	_box.set_corner_radius_all(int(HEIGHT * 0.5))
	_box.anti_aliasing = true


## Puts the marker over `screen` (its centre), clamped inside `bounds`.
func place(screen: Vector2, bounds: Rect2) -> void:
	var width: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size).x + 32.0
	size = Vector2(width, HEIGHT)
	var half: Vector2 = size * 0.5
	screen = screen.clamp(bounds.position + half, bounds.end - half)
	position = (screen - half).round()
	queue_redraw()


func _draw() -> void:
	draw_style_box(_box, Rect2(Vector2.ZERO, size))
	draw_circle(Vector2(12.0, HEIGHT * 0.5), 4.0, UiStyle.color(tone))
	var baseline: float = (HEIGHT + _font.get_ascent(_font_size) - _font.get_descent(_font_size)) * 0.5
	draw_string(_font, Vector2(22.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size, UiStyle.color("text"))
