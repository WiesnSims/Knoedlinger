class_name ShaderWarmup
extends Node3D
## Has the browser build every shader of a run behind the LoadingScreen, a few per frame, before the
## clock starts. WebGL compiles a program the first time something draws with it, and on a first
## visit each one blocks the page for 0.1-0.7 s: without this the first frame of a run froze for
## ~11 s in headless Edge (117 programs, tools/browser/hitch_probe.mjs). Same idea as Berghittn's.
##
## The camera first sees only WARM_LAYER. Then each frame one more node joins that layer, never
## frustum-culled and with at least one MultiMesh instance, so its programs compile in a frame of
## their own and the bar moves: first one representative of every distinct look (class, materials,
## mesh format, shadows), then the rest, which mostly cost nothing by then. Effects that only turn
## up later in a run (shots, orbits, attack marks, loot, the portal, swings) are tiny copies in front
## of the camera and go first. At the end everything is put back and `finished` is emitted. A frame
## that compiles nothing takes a few ms, so a second run, with the programs cached, is through in
## about a second. (Several nodes per frame after a quick one was tried: a batch then often held a
## few new looks and froze for seconds.)

signal finished
signal progressed(value: float)

## Render layer 20, which nothing else in the game uses.
const WARM_LAYER: int = 1 << 19
## Frames to wait after everything is shown, so the last compiles land before the clock starts.
const SETTLE_FRAMES: int = 3
const NEVER_CULLED := AABB(Vector3(-1.0e5, -1.0e5, -1.0e5), Vector3(2.0e5, 2.0e5, 2.0e5))

## 0..1 for the LoadingScreen.
var progress: float = 0.0

var _camera: Camera3D
var _world: Node
var _camera_mask: int = 0
## One representative node per look, then the reveal order (looks first), and every node changed.
var _looks: Array[GeometryInstance3D] = []
var _queue: Array[GeometryInstance3D] = []
var _saved: Dictionary[GeometryInstance3D, Array] = {}
var _seen_keys: Dictionary[String, bool] = {}
## Lights and other non-geometry visuals, with their layers.
var _lit: Dictionary[VisualInstance3D, int] = {}
var _next: int = 0
var _settle: int = -1
var _done: bool = false
var _started_ms: int = 0
var _frame_ms: int = 0
## log_slow=1: which looks the slow frames built.
var _log_slow: bool = false
var _last_shown: PackedStringArray = []


## Starts the warm-up for everything under `world`, seen through `camera`.
static func start(world: Node, camera: Camera3D) -> ShaderWarmup:
	var warmup := ShaderWarmup.new()
	warmup.name = "ShaderWarmup"
	warmup._world = world
	warmup._camera = camera
	camera.add_child(warmup)
	return warmup


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	position = Vector3(0.0, 0.0, -2.0)
	scale = Vector3.ONE * 0.001
	_add_effects()
	_collect(_world)
	_queue = _looks.duplicate()
	for node: GeometryInstance3D in _saved:
		if not _looks.has(node):
			_queue.append(node)
	_camera_mask = _camera.cull_mask
	_camera.cull_mask = WARM_LAYER
	_started_ms = Time.get_ticks_msec()
	_frame_ms = _started_ms
	_log_slow = LaunchArgs.get_flag("log_slow", false)


func _process(_delta: float) -> void:
	if _done:
		return
	# Wall-clock time of the last frame (a shader build stalls the whole page, delta does not show it all).
	var now: int = Time.get_ticks_msec()
	var frame_ms: int = now - _frame_ms
	_frame_ms = now
	if _log_slow and frame_ms > 250:
		print("[WARM] %d ms for %s" % [frame_ms, ", ".join(_last_shown)])
	_last_shown.clear()
	if _next < _queue.size():
		var node: GeometryInstance3D = _queue[_next]
		if _log_slow and is_instance_valid(node):
			_last_shown.append(String(node.get_path()).trim_prefix(String(_world.get_path())))
		_show(node)
		_next += 1
		progress = 0.95 * float(_next) / float(_queue.size())
		progressed.emit(progress)
		return
	if _settle < 0:
		_settle = SETTLE_FRAMES
		return
	_settle -= 1
	if _settle > 0:
		return
	_restore()
	progress = 1.0
	_done = true
	print("[WARM] %d looks of %d nodes in %d ms" % [_looks.size(), _saved.size(), Time.get_ticks_msec() - _started_ms])
	finished.emit()
	queue_free()


## Puts every node back the way it was and gives the camera the world again.
func _restore() -> void:
	for node: GeometryInstance3D in _saved:
		if not is_instance_valid(node):
			continue
		var saved: Array = _saved[node]
		node.layers = saved[0]
		node.cast_shadow = saved[1]
		node.custom_aabb = saved[2]
		var multi: MultiMeshInstance3D = node as MultiMeshInstance3D
		if multi != null and multi.multimesh != null and multi.multimesh.visible_instance_count == 1:
			multi.multimesh.visible_instance_count = saved[3]
	for visual: VisualInstance3D in _lit:
		if is_instance_valid(visual):
			visual.layers = _lit[visual]
	_camera.cull_mask = _camera_mask


func _show(node: GeometryInstance3D) -> void:
	if not is_instance_valid(node):
		return
	var saved: Array = _saved[node]
	node.layers = saved[0] | WARM_LAYER
	node.cast_shadow = saved[1]
	node.custom_aabb = NEVER_CULLED
	var multi: MultiMeshInstance3D = node as MultiMeshInstance3D
	if multi != null and multi.multimesh != null and multi.multimesh.instance_count > 0 \
			and multi.multimesh.visible_instance_count == 0:
		multi.multimesh.visible_instance_count = 1


## Every visible geometry under `node`: hidden from the camera and its shadows until its turn.
func _collect(node: Node) -> void:
	if node == self:
		return
	var geometry: GeometryInstance3D = node as GeometryInstance3D
	if geometry != null and geometry.is_visible_in_tree():
		var multi: MultiMeshInstance3D = geometry as MultiMeshInstance3D
		var count: int = multi.multimesh.visible_instance_count if multi != null and multi.multimesh != null else 0
		var key: String = _look_key(geometry)
		if not _seen_keys.has(key):
			_seen_keys[key] = true
			_looks.append(geometry)
		_saved[geometry] = [geometry.layers, geometry.cast_shadow, geometry.custom_aabb, count]
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif node is VisualInstance3D:
		# Lights and decals: the camera's mask hides them too, and without them the lit variants
		# would only be built when the run starts. They stay on from the first frame.
		var visual: VisualInstance3D = node as VisualInstance3D
		_lit[visual] = visual.layers
		visual.layers |= WARM_LAYER
	for child: Node in node.get_children():
		_collect(child)



## What decides which programs a node needs: its class, materials, mesh format, skin and shadows.
static func _look_key(node: GeometryInstance3D) -> String:
	var parts := PackedStringArray([node.get_class(), str(node.cast_shadow), _id(node.material_override)])
	var mesh: Mesh = null
	var mesh_node: MeshInstance3D = node as MeshInstance3D
	var multi: MultiMeshInstance3D = node as MultiMeshInstance3D
	if mesh_node != null:
		mesh = mesh_node.mesh
		parts.append("skin" if mesh_node.skin != null or not mesh_node.skeleton.is_empty() else "")
	elif multi != null and multi.multimesh != null:
		mesh = multi.multimesh.mesh
		parts.append("c%d d%d" % [int(multi.multimesh.use_colors), int(multi.multimesh.use_custom_data)])
	elif node is Label3D:
		var text: Label3D = node as Label3D
		parts.append("%d %d %d" % [text.billboard, int(text.shaded), int(text.double_sided)])
	if mesh != null:
		var arrays: ArrayMesh = mesh as ArrayMesh
		for s: int in mesh.get_surface_count():
			var material: Material = mesh_node.get_active_material(s) if mesh_node != null else mesh.surface_get_material(s)
			parts.append(_id(material))
			if arrays != null:
				parts.append(str(arrays.surface_get_format(s)))
		parts.append(mesh.get_class())
	return "|".join(parts)


static func _id(material: Material) -> String:
	if material == null:
		return "-"
	# Materials of one shader share its programs.
	var shader_material: ShaderMaterial = material as ShaderMaterial
	if shader_material != null and shader_material.shader != null:
		return "s%d" % shader_material.shader.get_instance_id()
	return "m%d" % material.get_instance_id()


## Tiny copies of the effects that are not in the scene yet when a run starts.
func _add_effects() -> void:
	var projectile: Shader = load("res://shaders/projectile.gdshader")
	# The same variants the pools use: shots without instance colours, orbit pieces with them.
	_add_effect(_instanced(MeshFactory.projectile(), projectile, false))
	_add_effect(_instanced(MeshFactory.orbit_piece(WeaponData.Look.BALL), projectile, true))
	# M3: attack marks (colours + custom data), Stempel beams, loot (vertex colours, instanced), the gate.
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	_add_effect(_instanced(quad, load("res://shaders/hazard.gdshader"), true, true))
	_add_effect(_instanced(quad, load("res://shaders/beam.gdshader"), true))
	var loot_look: MultiMeshInstance3D = _instanced(MeshFactory.brosel(), null, true)
	loot_look.material_override = MapBuilder.vertex_color_material()
	_add_effect(loot_look)
	var portal := MeshInstance3D.new()
	portal.mesh = quad
	var portal_material := ShaderMaterial.new()
	portal_material.shader = load("res://shaders/portal.gdshader")
	portal.material_override = portal_material
	_add_effect(portal)
	for path: String in ["res://shaders/pulse.gdshader", "res://shaders/swing.gdshader"]:
		var disc := MeshInstance3D.new()
		disc.mesh = MeshFactory.swing_fan(TAU, 8)
		var material := ShaderMaterial.new()
		material.shader = load(path)
		material.set_shader_parameter(&"progress", 0.5)
		disc.material_override = material
		_add_effect(disc)
	# 1.2: an enemy's line over its head (fixed size, no depth test: a look of its own).
	var line: Label3D = EnemyVoices.make_text()
	line.text = tr("SET_ENEMY_CHATTER")
	_add_effect(line)


## Effects go first: they sit in front of the camera and are freed with the warm-up.
func _add_effect(node: GeometryInstance3D) -> void:
	node.layers = 0
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_saved[node] = [WARM_LAYER, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, AABB(), 1]
	_looks.append(node)


func _instanced(mesh: Mesh, shader: Shader, colors: bool, custom: bool = false) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = colors
	multimesh.use_custom_data = custom
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
