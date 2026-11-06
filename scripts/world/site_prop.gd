class_name SiteProp
extends Node3D
## The look of a RunSites site on every machine (1.4 tasks 5.2, 5.3): Der Standler's market stall
## (striped awning, counter, crates, a sign seen through walls so players find him) or a Marterl (a
## wooden wayside shrine on a post, its panel in the colour of its kind, a candle that is lit while
## it works and grey once it is used up). Built from merged boxes like the Touristenbus.

const WOOD := Color(0.47, 0.31, 0.18)
const DARK_WOOD := Color(0.3, 0.2, 0.12)
const WHITE := Color(0.95, 0.93, 0.88)
const AWNING := Color(0.3, 0.6, 0.32)
## Marterl panels by kind (RunSites.Marterl): Mutprobe orange, Gier gold, Segen sky blue. Never
## Krampus red, which is for attacks only.
const KIND_COLORS: Array[Color] = [Color(0.93, 0.55, 0.2), Color(0.95, 0.8, 0.25), Color(0.45, 0.7, 0.95)]
const CANDLE_LIT := Color(1.0, 0.85, 0.35)
const CANDLE_OUT := Color(0.55, 0.55, 0.55)

var _candle: MeshInstance3D
var _label: Label3D


func setup_standler(at: Vector3, yaw: float) -> void:
	name = "Standler"
	rotation.y = yaw
	position = at
	var parts: Array[Dictionary] = []
	for x: float in [-1.4, 1.4]:
		for z: float in [-0.8, 0.8]:
			parts.append(_box(Vector3(0.14, 2.4, 0.14), Vector3(x, 1.2, z), WOOD))
	parts.append(_box(Vector3(3.0, 0.9, 1.0), Vector3(0.0, 0.45, 0.4), WOOD))
	parts.append(_box(Vector3(3.1, 0.08, 1.1), Vector3(0.0, 0.94, 0.4), DARK_WOOD))
	# The awning: green and white stripes.
	for k: int in 6:
		var stripe: Color = AWNING if k % 2 == 0 else WHITE
		parts.append(_box(Vector3(0.53, 0.1, 2.0), Vector3(-1.32 + k * 0.53, 2.45, 0.0), stripe))
	for k: int in 3:
		parts.append(_box(Vector3(0.5, 0.4, 0.5), Vector3(-0.9 + k * 0.9, 1.18, 0.35), [WHITE, AWNING, WOOD][k]))
	_add_mesh(parts)
	_label = _sign(tr("STANDLER_SIGN"), Vector3(0.0, 3.3, 0.0), AWNING)
	_label.no_depth_test = true


func setup_marterl(at: Vector3, kind: int) -> void:
	name = "Marterl"
	position = at
	var parts: Array[Dictionary] = []
	parts.append(_box(Vector3(0.22, 1.5, 0.22), Vector3(0.0, 0.75, 0.0), WOOD))
	parts.append(_box(Vector3(0.8, 0.8, 0.5), Vector3(0.0, 1.9, 0.0), WHITE))
	parts.append(_box(Vector3(0.56, 0.56, 0.06), Vector3(0.0, 1.9, 0.26), KIND_COLORS[clampi(kind, 0, 2)]))
	parts.append(_box(Vector3(1.0, 0.1, 0.7), Vector3(0.0, 2.35, 0.0), DARK_WOOD))
	parts.append(_box(Vector3(0.6, 0.1, 0.55), Vector3(0.0, 2.45, 0.0), DARK_WOOD))
	_add_mesh(parts)
	_candle = MeshInstance3D.new()
	var wick: Array[Dictionary] = [_box(Vector3(0.1, 0.22, 0.1), Vector3(0.0, 1.62, 0.33), Color.WHITE)]
	_candle.mesh = MeshFactory.merge(wick)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = CANDLE_OUT
	_candle.material_override = material
	add_child(_candle)
	_label = _sign(tr("MARTERL_%d" % clampi(kind, 0, 2)), Vector3(0.0, 3.0, 0.0), KIND_COLORS[clampi(kind, 0, 2)])


## A Marterl: lit while it works, grey once used up (its sign then goes).
func set_state(state: int) -> void:
	if _candle != null:
		(_candle.material_override as StandardMaterial3D).albedo_color = CANDLE_LIT if state == RunSites.State.ACTIVE else CANDLE_OUT
	if _label != null:
		_label.visible = state == RunSites.State.PLACED or state == RunSites.State.ACTIVE
	if state == RunSites.State.DONE:
		for child: Node in get_children():
			if child is MeshInstance3D and child != _candle:
				(child as MeshInstance3D).transparency = 0.35


func _box(size: Vector3, at: Vector3, color: Color) -> Dictionary:
	var part: Dictionary = MeshFactory._part(MeshFactory._box(size), Transform3D(Basis(), at), color)
	part["color"] = (part["color"] as Color).srgb_to_linear()
	return part


func _add_mesh(parts: Array[Dictionary]) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = MeshFactory.merge(parts)
	mesh.material_override = MapBuilder.vertex_color_material()
	add_child(mesh)


func _sign(text: String, at: Vector3, outline: Color) -> Label3D:
	var sign := Label3D.new()
	sign.font = UiStyle.font("number")
	sign.text = text
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = at
	sign.font_size = 48
	sign.pixel_size = 0.012
	sign.outline_size = 12
	sign.outline_modulate = outline.darkened(0.6)
	add_child(sign)
	return sign
