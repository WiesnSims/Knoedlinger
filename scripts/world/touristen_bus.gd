class_name TouristenBus
extends Node3D
## The Touristenbus (GAME-DESIGN.md, 8:00): a coach that rolls in from the edge of the village and
## stops; the tourist wave comes from its direction. Only a look; the host picks where.

const DRIVE_SECONDS: float = 3.0
const DRIVE_DISTANCE: float = 30.0
const LENGTH: float = 11.0

var _target: Vector3 = Vector3.ZERO
var _from: Vector3 = Vector3.ZERO
var _time: float = 0.0
var _ground: Heightfield


func setup(where: Vector3, yaw: float, ground: Heightfield) -> void:
	name = "TouristenBus"
	_ground = ground
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	rotation.y = yaw
	_target = where
	_from = where - Vector3(sin(yaw), 0.0, cos(yaw)) * DRIVE_DISTANCE
	var body := Color(0.97, 0.92, 0.6)
	var stripe := Color(0.25, 0.45, 0.78)
	var glass := Color(0.3, 0.38, 0.48)
	var tyre := Color(0.12, 0.12, 0.12)
	var parts: Array[Dictionary] = []
	parts.append(MeshFactory._part(MeshFactory._box(Vector3(2.6, 2.6, LENGTH)), Transform3D(Basis(), Vector3(0.0, 2.0, 0.0)), body))
	parts.append(MeshFactory._part(MeshFactory._box(Vector3(2.65, 0.35, LENGTH + 0.02)), Transform3D(Basis(), Vector3(0.0, 1.4, 0.0)), stripe))
	parts.append(MeshFactory._part(MeshFactory._box(Vector3(2.7, 0.9, LENGTH - 2.0)), Transform3D(Basis(), Vector3(0.0, 2.55, -0.6)), glass))
	parts.append(MeshFactory._part(MeshFactory._box(Vector3(2.3, 1.2, 0.1)), Transform3D(Basis(), Vector3(0.0, 2.5, LENGTH * 0.5 + 0.01)), glass))
	for z: float in [-LENGTH * 0.32, LENGTH * 0.32]:
		for x: float in [-1.3, 1.3]:
			parts.append(MeshFactory._part(MeshFactory._cylinder(0.55, 0.55, 0.4, 10), Transform3D(Basis.from_euler(Vector3(0.0, 0.0, PI / 2.0)), Vector3(x, 0.55, z)), tyre))
	for part: Dictionary in parts:
		part["color"] = (part["color"] as Color).srgb_to_linear()
	var mesh := MeshInstance3D.new()
	mesh.mesh = MeshFactory.merge(parts)
	mesh.material_override = MapBuilder.vertex_color_material()
	add_child(mesh)
	var sign := Label3D.new()
	sign.text = tr("BUS_SIGN")
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = Vector3(0.0, 4.4, 0.0)
	sign.font_size = 56
	sign.pixel_size = 0.012
	sign.outline_size = 12
	sign.outline_modulate = Color(0.1, 0.15, 0.3)
	add_child(sign)
	_place(0.0)


func _process(delta: float) -> void:
	if _time >= DRIVE_SECONDS:
		return
	_time = minf(_time + delta, DRIVE_SECONDS)
	_place(_time / DRIVE_SECONDS)


func _place(t: float) -> void:
	# Eases into its stop.
	var at: Vector3 = _from.lerp(_target, 1.0 - pow(1.0 - t, 3.0))
	at.y = _ground.height_at(at.x, at.z) if _ground != null else 0.0
	position = at
