class_name TeamPanel
extends Control
## Co-op: the family in the bottom-left corner (docs/UI-STYLE.md keeps that corner for teammates),
## one row per teammate: a coat-coloured dot, the name, the level, a thin HP bar and, when knocked
## down, "umgfoin" with the seconds left (or the revive filling up) or "draußen". Drawn in one pass
## like TileGrid (a few draw calls for the whole panel instead of a dozen nodes per row); fonts and
## colours still come from the theme (HudSmall, Palette).

const ROW_HEIGHT: float = 40.0
const WIDTH: float = 224.0
const BAR := Vector2(120.0, 6.0)
const DOT: float = 6.0


class Row:
	extends RefCounted
	var name: String = ""
	var color: Color = Color.WHITE
	var level: int = 1
	var hp: float = 1.0
	var downed: bool = false
	var out: bool = false
	## Seconds until out (-1 = not counting) and the revive progress 0..1.
	var down_left: float = -1.0
	var revive: float = 0.0


var _rows: Array[Row] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_rows(rows: Array[Row]) -> void:
	_rows = rows
	custom_minimum_size = Vector2(WIDTH, ROW_HEIGHT * rows.size())
	visible = not rows.is_empty()
	queue_redraw()


func _draw() -> void:
	var font: Font = get_theme_font("font", &"HudSmall")
	var font_size: int = get_theme_font_size("font_size", &"HudSmall")
	var text: Color = get_theme_color("font_color", &"HudSmall")
	var muted: Color = UiStyle.color("muted")
	var line: Color = UiStyle.color("line")
	var hp: Color = UiStyle.color("hp")
	var accent: Color = UiStyle.color("accent")
	for k: int in _rows.size():
		var row: Row = _rows[k]
		var top: float = k * ROW_HEIGHT
		var baseline: float = top + 16.0
		draw_circle(Vector2(DOT, baseline - font_size * 0.35), DOT, row.color)
		var name_color: Color = muted if row.downed else text
		draw_string(font, Vector2(DOT * 2.0 + 8.0, baseline), row.name, HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 72.0,
				font_size, name_color, TextServer.JUSTIFICATION_NONE)
		var level: String = TranslationServer.translate("HUD_LEVEL") % row.level
		draw_string(font, Vector2(0.0, baseline), level, HORIZONTAL_ALIGNMENT_RIGHT, WIDTH, font_size, muted)
		var bar_at := Vector2(DOT * 2.0 + 8.0, top + 24.0)
		if row.downed:
			var status: String
			if row.out:
				status = TranslationServer.translate("TEAM_OUT")
			elif row.revive > 0.01:
				status = TranslationServer.translate("TEAM_REVIVING") % roundi(row.revive * 100.0)
			else:
				status = TranslationServer.translate("TEAM_DOWN") % maxi(ceili(row.down_left), 0)
			draw_string(font, bar_at + Vector2(0.0, 12.0), status, HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24.0,
					font_size, accent if not row.out else muted)
			continue
		draw_rect(Rect2(bar_at, BAR), line)
		draw_rect(Rect2(bar_at, Vector2(BAR.x * clampf(row.hp, 0.0, 1.0), BAR.y)), hp)
