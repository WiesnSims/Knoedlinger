class_name Wirtshaus
extends Node3D
## A Wirtshaus at one of the map's spots (GAME-DESIGN.md, "Einkehren"). The building itself is part
## of the map (building_props(), baked into collision and the ground); this node is the living part:
## the Wirt at the door, the sign, and the glowing door mat where a rolled-in Knödl is eaten. The
## host decides which spots are open in a run and when one has served; everyone shows that state.

## The house: width, wall height, depth. The door is in the middle of its front (+z) wall.
const HOUSE_SIZE := Vector3(7.0, 3.6, 6.0)
const ROOF_HEIGHT: float = 1.4
## The door mat's centre, in front of the door.
const MAT_DISTANCE: float = 2.0
## Colours: whitewashed walls, dark shingles, a wooden door (no Krampus red).
const WALL_COLOR := Color(0.94, 0.91, 0.82)
const ROOF_COLOR := Color(0.5, 0.3, 0.16)
const DOOR_COLOR := Color(0.45, 0.3, 0.17)
const MAT_OPEN := Color(1.0, 0.82, 0.35)
const MAT_SERVED := Color(0.55, 0.85, 0.5)

var spot: int = 0
var open: bool = false
var served: bool = false
## The tier it was paid in (0 = S .. 3 = XL), once served.
var tier: int = 0

var _mat: MeshInstance3D
var _mat_material: ShaderMaterial
var _sign: Label3D
var _wirt: Node3D
var _mat_centre: Vector3 = Vector3.ZERO
var _time: float = 0.0


## The house as map props at spot `k`: walls, a roof that overhangs, the door.
static func building_props(map: MapData, k: int) -> Array[MapProp]:
	var place: Transform3D = map.wirtshaus_transform(k)
	var yaw: float = rad_to_deg(place.basis.get_euler().y)
	var props: Array[MapProp] = []
	props.append(_prop(place, Vector3.ZERO, HOUSE_SIZE, yaw, WALL_COLOR))
	var roof: MapProp = _prop(place, Vector3(0.0, HOUSE_SIZE.y, 0.0),
			Vector3(HOUSE_SIZE.x + 0.8, ROOF_HEIGHT * 1.8, HOUSE_SIZE.z + 0.8), yaw, ROOF_COLOR)
	roof.kind = MapProp.Kind.ROOF
	props.append(roof)
	props.append(_prop(place, Vector3(0.0, 0.0, HOUSE_SIZE.z * 0.5 + 0.05), Vector3(1.6, 2.4, 0.2), yaw, DOOR_COLOR))
	return props


static func _prop(place: Transform3D, local: Vector3, size: Vector3, yaw: float, color: Color) -> MapProp:
	var prop := MapProp.new()
	prop.kind = MapProp.Kind.BLOCK
	prop.position = place * local
	prop.size = size
	prop.yaw_degrees = yaw
	prop.color = color
	return prop


func setup(map: MapData, p_spot: int, ground: Heightfield) -> void:
	spot = p_spot
	name = "Wirtshaus_%d" % spot
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var place: Transform3D = map.wirtshaus_transform(spot)
	transform = place
	var front: Vector3 = place.basis * Vector3(0.0, 0.0, HOUSE_SIZE.z * 0.5 + MAT_DISTANCE)
	_mat_centre = place.origin + front
	_mat_centre.y = ground.height_at(_mat_centre.x, _mat_centre.z)
	_mat = MeshInstance3D.new()
	_mat.name = "DoorMat"
	_mat.top_level = true
	_mat.mesh = MeshFactory.swing_fan(TAU, 32)
	_mat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat_material = ShaderMaterial.new()
	_mat_material.shader = load("res://shaders/pulse.gdshader")
	_mat.material_override = _mat_material
	add_child(_mat)
	_mat.global_position = _mat_centre + Vector3(0.0, 0.08, 0.0)
	_sign = Label3D.new()
	# Only nearby signs draw (draw calls, M6); the HUD marker points to the nearest open one.
	_sign.visibility_range_end = 45.0
	_sign.font = UiStyle.font("number")
	_sign.name = "Sign"
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.position = Vector3(0.0, HOUSE_SIZE.y + ROOF_HEIGHT * 1.8 + 1.0, HOUSE_SIZE.z * 0.5)
	_sign.font_size = 72
	_sign.pixel_size = 0.01
	_sign.outline_size = 14
	_sign.modulate = Color(1.0, 0.97, 0.88)
	_sign.outline_modulate = Color(0.2, 0.12, 0.06)
	_sign.no_depth_test = false
	add_child(_sign)
	_wirt = figure(1.0, false)
	_wirt.position = Vector3(1.4, 0.0, HOUSE_SIZE.z * 0.5 + 0.6)
	add_child(_wirt)
	set_state(false, false, 0)


## Where a Knödl must roll to be eaten, and how far from it counts.
func mat_centre() -> Vector3:
	return _mat_centre


## True when a Knödl at `where` with `radius` touches the door mat.
func touches(where: Vector3, radius: float, mat_radius: float) -> bool:
	var dx: float = where.x - _mat_centre.x
	var dz: float = where.z - _mat_centre.z
	var reach: float = mat_radius + radius
	return dx * dx + dz * dz < reach * reach and absf(where.y - _mat_centre.y) < radius + 3.0


func set_state(p_open: bool, p_served: bool, p_tier: int) -> void:
	open = p_open
	served = p_served
	tier = p_tier
	var title: String = tr("WIRT_NAME_%d" % (spot % 6))
	if served:
		_sign.text = "%s\n%s" % [title, tr("WIRT_SIGN_SERVED") % tr("TIER_%d" % tier)]
	elif open:
		_sign.text = "%s\n%s" % [title, tr("WIRT_SIGN_OPEN")]
	else:
		_sign.text = "%s\n%s" % [title, tr("WIRT_SIGN_CLOSED")]
	_mat.visible = open or served
	_wirt.visible = open and not served
	_mat_material.set_shader_parameter(&"tint", MAT_SERVED if served else MAT_OPEN)
	_mat_material.set_shader_parameter(&"fill", 0.06 if served else 0.18)


func set_mat_radius(radius: float) -> void:
	_mat.scale = Vector3.ONE * radius


func _process(delta: float) -> void:
	if not open or served:
		return
	# The door mat breathes so an open Wirtshaus is easy to spot.
	_time += delta
	_mat_material.set_shader_parameter(&"progress", 0.5 + 0.5 * sin(_time * 3.0))


## A Wirt: round, white shirt, green waistcoat, long apron. `broom` for the Riesen-Wirt.
static func figure(size: float, broom: bool) -> Node3D:
	var look := Node3D.new()
	look.name = "Wirt"
	var parts: Array[Dictionary] = []
	var belly := SphereMesh.new()
	belly.radius = 0.55
	belly.height = 1.2
	belly.radial_segments = 12
	belly.rings = 6
	var vest := CylinderMesh.new()
	vest.top_radius = 0.42
	vest.bottom_radius = 0.5
	vest.height = 0.6
	vest.radial_segments = 12
	vest.rings = 1
	var apron := BoxMesh.new()
	apron.size = Vector3(0.8, 0.9, 0.08)
	var head := SphereMesh.new()
	head.radius = 0.3
	head.height = 0.6
	head.radial_segments = 10
	head.rings = 5
	var nose := SphereMesh.new()
	nose.radius = 0.1
	nose.height = 0.2
	nose.radial_segments = 6
	nose.rings = 3
	var leg := BoxMesh.new()
	leg.size = Vector3(0.2, 0.55, 0.22)
	parts.append({"mesh": belly, "transform": Transform3D(Basis(), Vector3(0.0, 0.95, 0.0)), "color": Color(0.96, 0.96, 0.94)})
	parts.append({"mesh": vest, "transform": Transform3D(Basis(), Vector3(0.0, 1.25, 0.0)), "color": Color(0.2, 0.42, 0.25)})
	parts.append({"mesh": apron, "transform": Transform3D(Basis(), Vector3(0.0, 0.75, 0.5)), "color": Color(0.98, 0.98, 0.96)})
	parts.append({"mesh": head, "transform": Transform3D(Basis(), Vector3(0.0, 1.78, 0.0)), "color": Color(0.95, 0.76, 0.62)})
	parts.append({"mesh": nose, "transform": Transform3D(Basis(), Vector3(0.0, 1.76, 0.3)), "color": Color(0.95, 0.58, 0.48)})
	parts.append({"mesh": leg, "transform": Transform3D(Basis(), Vector3(0.18, 0.27, 0.0)), "color": Color(0.25, 0.2, 0.15)})
	parts.append({"mesh": leg, "transform": Transform3D(Basis(), Vector3(-0.18, 0.27, 0.0)), "color": Color(0.25, 0.2, 0.15)})
	if broom:
		var stick := CylinderMesh.new()
		stick.top_radius = 0.05
		stick.bottom_radius = 0.05
		stick.height = 2.2
		stick.radial_segments = 6
		stick.rings = 1
		var bristles := BoxMesh.new()
		bristles.size = Vector3(1.2, 0.25, 0.3)
		parts.append({"mesh": stick, "transform": Transform3D(Basis.from_euler(Vector3(0.9, 0.0, 0.0)), Vector3(0.55, 0.9, 0.7)), "color": Color(0.6, 0.45, 0.28)})
		parts.append({"mesh": bristles, "transform": Transform3D(Basis(), Vector3(0.55, 0.15, 1.55)), "color": Color(0.85, 0.72, 0.4)})
	for part: Dictionary in parts:
		part["color"] = (part["color"] as Color).srgb_to_linear()
	var mesh := MeshInstance3D.new()
	mesh.mesh = MeshFactory.merge(parts)
	mesh.material_override = MapBuilder.vertex_color_material()
	mesh.scale = Vector3.ONE * size
	look.add_child(mesh)
	return look
