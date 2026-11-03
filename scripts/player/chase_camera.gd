class_name ChaseCamera
extends Camera3D
## Third-person chase cam (GAME-DESIGN.md: about 50 degrees pitch, 14 m distance, slight lag).
## Turning with the movement direction is tuned in M1.

@export var pitch_degrees: float = 50.0
@export var distance: float = 14.0
@export var follow_speed: float = 6.0

var target: Node3D


func _process(delta: float) -> void:
	if target == null:
		return
	var pitch: float = deg_to_rad(pitch_degrees)
	var focus: Vector3 = target.global_position + Vector3(0.0, 1.0, 0.0)
	var desired: Vector3 = focus + Vector3(0.0, sin(pitch), cos(pitch)) * distance
	global_position = global_position.lerp(desired, 1.0 - exp(-follow_speed * delta))
	look_at(focus)


func snap_to_target() -> void:
	if target == null:
		return
	var pitch: float = deg_to_rad(pitch_degrees)
	var focus: Vector3 = target.global_position + Vector3(0.0, 1.0, 0.0)
	global_position = focus + Vector3(0.0, sin(pitch), cos(pitch)) * distance
	look_at(focus)
