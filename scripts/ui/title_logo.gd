class_name TitleLogo
extends Control
## The game's logo on the title screen: "Knödlinger" in the title font with a gold underline and the
## subtitle under it. A drawn graphic, not UI text: it is the one place that draws the title font
## bigger than the theme's display size (docs/UI-STYLE.md, "Type"), the way a logo image would.

const LOGO_SIZE: int = 88
const SUBTITLE_GAP: float = 8.0

var title: String = ""
var subtitle: String = ""


func _init(p_title: String = "", p_subtitle: String = "") -> void:
	title = p_title
	subtitle = p_subtitle
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(400.0, 136.0)


func _draw() -> void:
	var font: Font = UiStyle.font("title")
	var small: Font = UiStyle.font("bold")
	var body: int = UiStyle.font_size("body")
	var ascent: float = font.get_ascent(LOGO_SIZE)
	var shadow: Color = UiStyle.color("shadow")
	draw_string(font, Vector2(0.0, ascent + 3.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LOGO_SIZE, shadow)
	draw_string(font, Vector2(0.0, ascent), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LOGO_SIZE, UiStyle.color("text"))
	var width: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LOGO_SIZE).x
	var line_y: float = ascent + font.get_descent(LOGO_SIZE) * 0.4
	draw_rect(Rect2(4.0, line_y, width * 0.62, 4.0), UiStyle.color("accent"))
	var sub_y: float = line_y + 4.0 + SUBTITLE_GAP + small.get_ascent(body)
	draw_string(small, Vector2(4.0, sub_y), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1.0, body, UiStyle.color("accent"))
