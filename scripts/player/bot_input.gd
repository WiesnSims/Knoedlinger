class_name BotInput
extends RefCounted
## Stands in for a player's stick in automated runs and the stress test. Without waypoints it walks
## a figure eight around the centre so the horde keeps moving and turning; with waypoints it wanders
## between them. In a run it also jumps now and then and throws and reels in its Knödl.

const STUCK_CHECK: float = 1.0
const STUCK_DISTANCE: float = 1.2
const DETOUR_SECONDS: float = 1.4

var radius: float = 18.0
## Seconds per figure eight.
var period: float = 24.0
## Seconds between jumps and between Schupfn presses (0 = never); a throw is reeled in after
## reel_after seconds.
var jump_every: float = 0.0
var schupfn_every: float = 0.0
var reel_after: float = 1.6
## Something worth walking to first (Brösel), as world (x, z); INF when there is nothing.
var attractor: Vector2 = Vector2(INF, INF)

var _time: float = 0.0
var _waypoints: PackedVector2Array = PackedVector2Array()
var _waypoint: int = 0
var _jump_timer: float = 0.0
var _schupfn_timer: float = 0.0
var _reel_timer: float = -1.0
var _jump_pending: bool = false
var _schupfn_pending: bool = false
var _progress_from: Vector2 = Vector2.ZERO
var _progress_timer: float = 0.0
var _detour_timer: float = 0.0
var _detour_side: float = 1.0


func _init(start_phase: float = 0.0) -> void:
	_time = start_phase * period
	_jump_timer = 1.0 + start_phase * 2.0
	_schupfn_timer = 3.0 + start_phase * 3.0


func set_waypoints(points: PackedVector2Array, first: int = 0) -> void:
	_waypoints = points
	_waypoint = first % maxi(points.size(), 1)


## World-space direction to walk (x = world X, y = world Z).
func sample(delta: float, position: Vector3) -> Vector2:
	_time += delta
	_tick_buttons(delta)
	var here := Vector2(position.x, position.z)
	# No path finding: a bot that has not got anywhere for a second walks sideways for a moment
	# and jumps (round a house, over a fence).
	_progress_timer += delta
	if _progress_timer >= STUCK_CHECK:
		if here.distance_to(_progress_from) < STUCK_DISTANCE and _detour_timer <= 0.0:
			_detour_timer = DETOUR_SECONDS
			_detour_side = -_detour_side
			_jump_pending = true
		_progress_from = here
		_progress_timer = 0.0
	if attractor.is_finite() and here.distance_to(attractor) > 0.3:
		var toward: Vector2 = (attractor - here).normalized()
		if _detour_timer > 0.0:
			_detour_timer -= delta
			return (toward * 0.3 + Vector2(-toward.y, toward.x) * _detour_side).normalized()
		return toward
	if not _waypoints.is_empty():
		var goal: Vector2 = _waypoints[_waypoint]
		if here.distance_to(goal) < 2.5:
			_waypoint = (_waypoint + 1) % _waypoints.size()
			goal = _waypoints[_waypoint]
		var ahead: Vector2 = (goal - here).normalized()
		if _detour_timer > 0.0:
			_detour_timer -= delta
			return (ahead * 0.3 + Vector2(-ahead.y, ahead.x) * _detour_side).normalized()
		return ahead
	var w: float = TAU / period
	var ahead: float = _time + 0.6
	var target := Vector2(sin(ahead * w) * radius, sin(ahead * w * 2.0) * radius * 0.5)
	var to_target := target - here
	return to_target.normalized() if to_target.length() > 0.2 else Vector2.ZERO


## True once per planned jump.
func take_jump() -> bool:
	var pressed: bool = _jump_pending
	_jump_pending = false
	return pressed


## Throws at once (co-op: a pass toward the teammate it walks to), unless a throw is already out.
func throw_now() -> void:
	if _reel_timer > 0.0 or _schupfn_pending:
		return
	_schupfn_pending = true
	_reel_timer = reel_after + 0.6
	_schupfn_timer = maxf(_schupfn_timer, schupfn_every)


## True once per planned Schupfn press (the throw, and later the reel-in).
func take_schupfn() -> bool:
	var pressed: bool = _schupfn_pending
	_schupfn_pending = false
	return pressed


func _tick_buttons(delta: float) -> void:
	if jump_every > 0.0:
		_jump_timer -= delta
		if _jump_timer <= 0.0:
			_jump_timer = jump_every
			_jump_pending = true
	if schupfn_every > 0.0:
		_schupfn_timer -= delta
		if _schupfn_timer <= 0.0:
			_schupfn_timer = schupfn_every
			_schupfn_pending = true
			_reel_timer = reel_after
	if _reel_timer > 0.0:
		_reel_timer -= delta
		if _reel_timer <= 0.0:
			_schupfn_pending = true
