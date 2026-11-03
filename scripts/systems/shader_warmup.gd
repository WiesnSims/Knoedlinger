class_name ShaderWarmup
extends Node3D
## Draws one tiny copy of every effect material in front of the camera for the first frames of a
## run, then frees itself. WebGL compiles a shader the first time it draws with it; without this the
## first ski pole, aura or orbit of a run stalls the game for up to 100 ms (measured in M2).

const FRAMES: int = 8

var _frames: int = 0


## Puts the warm-up under `camera`.
static func attach(camera: Camera3D) -> void:
	var warmup := ShaderWarmup.new()
	warmup.name = "ShaderWarmup"
	camera.add_child(warmup)
	warmup.position = Vector3(0.0, 0.0, -2.0)
	warmup.scale = Vector3.ONE * 0.001


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var projectile: Shader = load("res://shaders/projectile.gdshader")
	# The same variants the pools use: shots without instance colours, orbit pieces with them.
	add_child(_instanced(MeshFactory.projectile(), projectile, false))
	add_child(_instanced(MeshFactory.orbit_piece(WeaponData.Look.BALL), projectile, true))
	for path: String in ["res://shaders/pulse.gdshader", "res://shaders/swing.gdshader"]:
		var disc := MeshInstance3D.new()
		disc.mesh = MeshFactory.swing_fan(TAU, 8)
		var material := ShaderMaterial.new()
		material.shader = load(path)
		material.set_shader_parameter(&"progress", 0.5)
		disc.material_override = material
		add_child(disc)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames >= FRAMES:
		queue_free()


func _instanced(mesh: Mesh, shader: Shader, colors: bool) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = colors
	multimesh.mesh = mesh
	multimesh.instance_count = 1
	multimesh.set_instance_transform(0, Transform3D())
	if colors:
		multimesh.set_instance_color(0, Color.WHITE)
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	var material := ShaderMaterial.new()
	material.shader = shader
	instance.material_override = material
	return instance
