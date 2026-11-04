class_name FamilyPortrait
extends Control
## A Knödlinger as a little drawn bust for the character choice: coat, face, hat in the character's
## colours, and the round family nose every Knödlinger shares (GAME-DESIGN.md, "Art"). Locked
## characters are a dark silhouette.

const SKIN := Color("f0c8a0")
const NOSE := Color("e39a82")

var character: CharacterData
var locked: bool = false


func _init(p_character: CharacterData = null, edge: float = 64.0) -> void:
	character = p_character
	custom_minimum_size = Vector2(edge, edge)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if character == null:
		return
	var s: float = minf(size.x, size.y)
	var c := Vector2(size.x * 0.5, size.y * 0.5)
	var dark: Color = UiStyle.color("panel_raised").lightened(0.08)
	var coat: Color = dark if locked else character.coat_color
	var hat: Color = dark if locked else character.hat_color
	var skin: Color = dark if locked else SKIN
	# Shoulders: a half disc standing on the bottom edge, inside the box.
	var shoulders := PackedVector2Array()
	var base := Vector2(c.x, size.y)
	for k: int in 17:
		var a: float = PI + PI * k / 16.0
		shoulders.append(base + Vector2(cos(a) * s * 0.4, sin(a) * s * 0.34))
	draw_colored_polygon(shoulders, coat)
	# Face, nose, eyes.
	var face := Vector2(c.x, size.y - s * 0.46)
	draw_circle(face, s * 0.2, skin)
	if not locked:
		draw_circle(face + Vector2(0.0, s * 0.04), s * 0.065, NOSE)
		draw_circle(face + Vector2(-s * 0.08, -s * 0.04), s * 0.022, UiStyle.color("panel"))
		draw_circle(face + Vector2(s * 0.08, -s * 0.04), s * 0.022, UiStyle.color("panel"))
	# Hat: brim and crown.
	draw_rect(Rect2(face.x - s * 0.27, face.y - s * 0.2, s * 0.54, s * 0.05), hat)
	draw_rect(Rect2(face.x - s * 0.16, face.y - s * 0.36, s * 0.32, s * 0.17), hat)
	if locked:
		var font: Font = UiStyle.font("number")
		var body: int = UiStyle.font_size("body")
		draw_string(font, Vector2(0.0, c.y + s * 0.12), "?", HORIZONTAL_ALIGNMENT_CENTER, size.x, body, UiStyle.color("muted"))
