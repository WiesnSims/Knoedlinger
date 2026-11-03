class_name BotInput
extends RefCounted
## Stands in for a player's stick in automated runs and the stress test: walks a figure eight around
## the arena centre so the horde keeps moving and turning.

var radius: float = 18.0
## Seconds per figure eight.
var period: float = 24.0
var _time: float = 0.0


func _init(start_phase: float = 0.0) -> void:
	_time = start_phase * period


func sample(delta: float, position: Vector3) -> Vector2:
	_time += delta
	var w: float = TAU / period
	var ahead: float = _time + 0.6
	var target := Vector2(sin(ahead * w) * radius, sin(ahead * w * 2.0) * radius * 0.5)
	var to_target := target - Vector2(position.x, position.z)
	return to_target.normalized() if to_target.length() > 0.2 else Vector2.ZERO
