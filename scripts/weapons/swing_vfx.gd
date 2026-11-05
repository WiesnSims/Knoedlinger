class_name SwingVfx
extends MeshInstance3D
## One melee swing effect: a fan on the ground that sweeps open and fades. One per ARC weapon (and
## one more for its swing behind), replayed on every swing (no instantiate() per swing). Host and
## clients play it when the weapon's fire counter changes (WeaponVfx). A FLAME weapon (the Obstler)
## shows a flickering flame stream instead, a little longer than its cooldown, so it never breaks.

const DURATION: float = 0.28
const FLAME_DURATION: float = 0.5

var player: Player
var reach: float = 3.2

var _material: ShaderMaterial
var _time: float = DURATION
var _duration: float = DURATION
var _flame: bool = false
## PI for the swing behind the player.
var _turn: float = 0.0
## The heading of this swing (the weapon's aim), as Player.rotation.y.
var _yaw: float = 0.0


func setup(p_player: Player, weapon: WeaponData, behind: bool = false) -> void:
	player = p_player
	reach = weapon.reach
	_turn = PI if behind else 0.0
	name = "Swing_%s" % weapon.id
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mesh = MeshFactory.swing_fan(deg_to_rad(weapon.arc_degrees), 16)
	_flame = weapon.look == WeaponData.Look.FLAME
	_duration = FLAME_DURATION if _flame else DURATION
	_time = _duration
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/flame.gdshader" if _flame else "res://shaders/swing.gdshader")
	_material.set_shader_parameter(&"tint", weapon.color)
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scale = Vector3.ONE * reach
	visible = false


## Plays one swing toward `yaw`, `area` times the weapon's reach.
func play(area: float = 1.0, yaw: float = 0.0) -> void:
	scale = Vector3.ONE * reach * area
	_yaw = yaw
	# A flame still burning keeps its full length (no regrowing every burst).
	_time = _duration * 0.2 if _flame and visible else 0.0
	visible = true


func _process(delta: float) -> void:
	if not visible or player == null:
		return
	_time += delta
	if _time >= _duration:
		visible = false
		return
	global_position = player.get_global_transform_interpolated().origin + Vector3(0.0, 0.6, 0.0)
	rotation = Vector3(0.0, _yaw + _turn, 0.0)
	_material.set_shader_parameter(&"progress", _time / _duration)
