class_name SwingVfx
extends MeshInstance3D
## One player's melee swing effect: a fan on the ground that sweeps open and fades. One per player,
## replayed on every swing (no instantiate() per swing). Host and clients play it when the
## player's swing counter changes.

const DURATION: float = 0.28

var player: Player

var _material: ShaderMaterial
var _time: float = DURATION


func setup(p_player: Player, weapon: WeaponData) -> void:
	player = p_player
	name = "Swing_%d" % player.peer_id
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mesh = MeshFactory.swing_fan(deg_to_rad(weapon.arc_degrees), 16)
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/swing.gdshader")
	_material.set_shader_parameter(&"tint", weapon.color)
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scale = Vector3.ONE * weapon.reach
	visible = false


func play() -> void:
	_time = 0.0
	visible = true


func _process(delta: float) -> void:
	if not visible or player == null:
		return
	_time += delta
	if _time >= DURATION:
		visible = false
		return
	global_position = player.get_global_transform_interpolated().origin + Vector3(0.0, 0.6, 0.0)
	rotation = Vector3(0.0, player.rotation.y, 0.0)
	_material.set_shader_parameter(&"progress", _time / DURATION)
