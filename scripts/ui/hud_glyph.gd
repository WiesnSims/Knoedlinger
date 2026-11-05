class_name HudGlyph
extends Control
## The small drawn pictures of the HUD (docs/UI-STYLE.md): the Lebkuchenherz in front of the health
## bar, the Wirtshaus wall clock in front of the timer (its arc fills toward Sperrstund'), the
## Krügerl that fills with XP, and the Knödl whose size follows the real one, with the Schupfn
## cooldown as a ring. Colours come from the theme palette.

enum Kind { HEART, CLOCK, KRUEGERL, KNODL }

var kind: Kind = Kind.HEART
## 0..1: how full (clock: share of the run, Krügerl: XP to the next level).
var fill: float = 0.0
## Heart: blinks in the danger colour while low.
var warn: bool = false
## Knödl: 0..1 size between the start size and the cap; ring = Schupfn cooldown left (0 = ready).
var knodl_size: float = 0.0
var ring: float = 0.0
var hollow: bool = false
var _shown_fill: float = 0.0


func _init(p_kind: Kind = Kind.HEART, edge: float = 24.0) -> void:
	kind = p_kind
	custom_minimum_size = Vector2(edge, edge)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var target: float = clampf(fill, 0.0, 1.0)
	# A level-up empties the Krügerl at once instead of draining it backwards.
	if target < _shown_fill - 0.5:
		_shown_fill = target
	_shown_fill = move_toward(_shown_fill, target, delta / UiStyle.T_BAR)
	queue_redraw()


func _draw() -> void:
	match kind:
		Kind.HEART:
			_heart()
		Kind.CLOCK:
			_clock()
		Kind.KRUEGERL:
			_kruegerl()
		Kind.KNODL:
			_knodl()


func _heart() -> void:
	var s: Vector2 = size
	var color: Color = UiStyle.color("hp")
	if warn and int(Time.get_ticks_msec() / 250) % 2 == 0:
		color = UiStyle.color("danger")
	var points := PackedVector2Array()
	for k: int in 40:
		var t: float = TAU * k / 40.0
		# The classic heart curve, scaled into the box.
		var x: float = 16.0 * pow(sin(t), 3.0)
		var y: float = -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		points.append(Vector2(0.5 + x / 36.0, 0.47 + y / 36.0) * s)
	draw_colored_polygon(points, color)
	# Icing, like a Lebkuchenherz from the Kirtag.
	var icing := points.duplicate()
	for k: int in icing.size():
		icing[k] = s * 0.5 + (icing[k] - s * 0.5) * 0.72
	icing.append(icing[0])
	draw_polyline(icing, Color(1.0, 1.0, 1.0, 0.75), 1.5, true)


func _clock() -> void:
	var centre: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - 1.0
	draw_circle(centre, radius, UiStyle.color("panel_raised"))
	if _shown_fill > 0.0:
		# Nachspielzeit: the full arc blinks in the danger colour.
		var arc: Color = UiStyle.color("danger") if warn and int(Time.get_ticks_msec() / 250) % 2 == 0 else UiStyle.color("accent")
		draw_arc(centre, radius - 2.5, -PI * 0.5, -PI * 0.5 + TAU * _shown_fill, 32, arc, 3.0, true)
	draw_arc(centre, radius, 0.0, TAU, 32, UiStyle.color("text"), 1.5, true)
	# The hands: the big one shows the share of the run, the small one stays near the Sperrstund'.
	var angle: float = -PI * 0.5 + TAU * _shown_fill
	draw_line(centre, centre + Vector2(cos(angle), sin(angle)) * radius * 0.7, UiStyle.color("text"), 2.0, true)
	draw_line(centre, centre + Vector2(0.0, -radius * 0.45), UiStyle.color("text"), 2.0, true)
	draw_circle(centre, 2.0, UiStyle.color("text"))


func _kruegerl() -> void:
	var s: Vector2 = size
	var body := Rect2(Vector2(s.x * 0.08, s.y * 0.12), Vector2(s.x * 0.64, s.y * 0.82))
	draw_rect(body, UiStyle.color("glass"))
	var level: float = body.size.y * _shown_fill
	if level > 0.5:
		draw_rect(Rect2(Vector2(body.position.x, body.end.y - level), Vector2(body.size.x, level)), UiStyle.color("beer"))
		# A foam head on top of the beer.
		var foam: float = minf(level, s.y * 0.12)
		draw_rect(Rect2(Vector2(body.position.x, body.end.y - level), Vector2(body.size.x, foam)), UiStyle.color("foam"))
	var outline: Color = UiStyle.color("text")
	draw_rect(body, outline, false, 2.0)
	# The handle.
	var handle_centre := Vector2(body.end.x, body.position.y + body.size.y * 0.45)
	draw_arc(handle_centre, s.y * 0.2, -PI * 0.5, PI * 0.5, 12, outline, 2.0, true)
	# Dimples of a real Krügerl.
	for k: int in 2:
		var x: float = body.position.x + body.size.x * (0.33 + 0.34 * k)
		draw_line(Vector2(x, body.position.y + 4.0), Vector2(x, body.end.y - 4.0), Color(outline, 0.25), 1.0)


func _knodl() -> void:
	var centre: Vector2 = size * 0.5
	var outer: float = minf(size.x, size.y) * 0.5 - 2.0
	var radius: float = lerpf(outer * 0.42, outer * 0.78, clampf(knodl_size, 0.0, 1.0))
	var ring_color: Color = UiStyle.color("accent")
	# The ring: full and calm when Schupfn is ready, filling up while it cools down.
	draw_arc(centre, outer, 0.0, TAU, 40, Color(ring_color, 0.25), 3.0, true)
	var ready: float = 1.0 - clampf(ring, 0.0, 1.0)
	if ready > 0.0:
		draw_arc(centre, outer, -PI * 0.5, -PI * 0.5 + TAU * ready, 40, ring_color if ring <= 0.0 else Color(ring_color, 0.7), 3.0, true)
	if hollow:
		draw_arc(centre, radius, 0.0, TAU, 32, UiStyle.color("knodl"), 2.0, true)
		return
	draw_circle(centre, radius, UiStyle.color("knodl_edge"))
	draw_circle(centre + Vector2(-0.12, -0.12) * radius, radius * 0.86, UiStyle.color("knodl"))
	# Parsley flecks of the Semmelknödl.
	for k: int in 3:
		var a: float = 1.3 + k * 2.1
		draw_circle(centre + Vector2(cos(a), sin(a)) * radius * 0.5, maxf(radius * 0.09, 1.0), UiStyle.color("rarity_1"))
