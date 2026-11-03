class_name Spagat
extends MeshInstance3D
## The string between a player's hand and their Knödl: a thin camera-facing ribbon that sags when
## slack and runs straight when taut. Hidden while the Knödl is thrown (the string is let go).
## Purely visual; the pull itself lives in Knodl._integrate_forces().

const SEGMENTS: int = 10
const WIDTH: float = 0.05

var knodl: Knodl

var _mesh := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.85, 0.76, 0.55)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = material
	# The ribbon is rebuilt in world space every frame; never cull it.
	custom_aabb = AABB(Vector3(-1000.0, -100.0, -1000.0), Vector3(2000.0, 400.0, 2000.0))


func _process(_delta: float) -> void:
	_mesh.clear_surfaces()
	if knodl == null or knodl.holder == null or knodl.state == Knodl.State.THROWN:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var a: Vector3 = knodl.holder.hand_position_visual()
	var to_knodl: Vector3 = knodl.visual_position() - a
	var length: float = to_knodl.length()
	if length < 0.01:
		return
	# Ends on the dough's surface, not in its centre.
	var b: Vector3 = a + to_knodl * maxf(length - knodl.radius * 0.9, 0.0) / length
	var rest: float = knodl.rest_length()
	var sag: float = 0.0
	if knodl.state == Knodl.State.ATTACHED and length < rest:
		sag = sqrt(rest * rest - length * length) * 0.5
	var eye: Vector3 = camera.global_position
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for s: int in SEGMENTS + 1:
		var t: float = float(s) / SEGMENTS
		var p: Vector3 = a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		var along: Vector3 = (b - a).normalized()
		var side: Vector3 = along.cross(eye - p).normalized() * WIDTH * 0.5
		_mesh.surface_add_vertex(p - side)
		_mesh.surface_add_vertex(p + side)
	_mesh.surface_end()
