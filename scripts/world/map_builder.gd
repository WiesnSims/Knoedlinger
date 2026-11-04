class_name MapBuilder
extends RefCounted
## Turns a MapData into nodes: one vertex-coloured terrain mesh with a Jolt HeightMapShape3D, one
## merged mesh for all props with their collision shapes, the sky and the sun. One draw call for
## the terrain and one for all props (CLAUDE.md: < 150 draw calls).

const LAYER_WORLD: int = 1
## The terrain alone (also on LAYER_WORLD): the camera only avoids this, props never yank it.
const LAYER_TERRAIN: int = 8
## Above this height the rim mountains turn white.
const SNOW_HEIGHT: float = 13.0


## Builds the map under `parent` from its baked terrain.
## Returns the props' see-through material (ChaseCamera drives it), or null without props.
static func build(map: MapData, terrain: Heightfield, parent: Node3D) -> ShaderMaterial:
	_build_environment(map, parent)
	var body := StaticBody3D.new()
	body.name = "Terrain"
	body.collision_layer = LAYER_WORLD | LAYER_TERRAIN
	body.collision_mask = 0
	parent.add_child(body)
	var shape := CollisionShape3D.new()
	var height_map := HeightMapShape3D.new()
	height_map.map_width = terrain.samples
	height_map.map_depth = terrain.samples
	height_map.map_data = terrain.heights
	shape.shape = height_map
	# HeightMapShape3D spaces its samples 1 m apart around the origin; scale to the map's spacing.
	shape.scale = Vector3(terrain.cell, 1.0, terrain.cell)
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.name = "TerrainMesh"
	mesh.mesh = terrain_mesh(map, terrain)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.material_override = vertex_color_material()
	body.add_child(mesh)
	return _build_props(map, parent)


static func vertex_color_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	# Vertex colours are stored linear (see _ground_color / FlatMeshBuilder): the Compatibility
	# renderer lights in linear space but skips vertex_color_is_srgb (docs/DECISIONS.md).
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


static func terrain_mesh(map: MapData, terrain: Heightfield) -> ArrayMesh:
	var n: int = terrain.samples
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	var h: PackedFloat32Array = terrain.heights
	var two_cells: float = terrain.cell * 2.0
	for iz: int in n:
		var z: float = terrain.world_x(iz)
		for ix: int in n:
			var i: int = iz * n + ix
			var y: float = h[i]
			vertices[i] = Vector3(terrain.world_x(ix), y, z)
			var left: float = h[i - 1] if ix > 0 else y
			var right: float = h[i + 1] if ix < n - 1 else y
			var back: float = h[i - n] if iz > 0 else y
			var front: float = h[i + n] if iz < n - 1 else y
			var normal := Vector3(left - right, two_cells, back - front).normalized()
			normals[i] = normal
			colors[i] = _ground_color(map, vertices[i], normal).srgb_to_linear()
	var indices := PackedInt32Array()
	indices.resize((n - 1) * (n - 1) * 6)
	var o: int = 0
	for iz: int in n - 1:
		for ix: int in n - 1:
			var i: int = iz * n + ix
			# Godot's front faces wind clockwise seen from the front (here: from above).
			indices[o] = i
			indices[o + 1] = i + 1
			indices[o + 2] = i + n
			indices[o + 3] = i + 1
			indices[o + 4] = i + n + 1
			indices[o + 5] = i + n
			o += 6
	var surface: Array = []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = vertices
	surface[Mesh.ARRAY_NORMAL] = normals
	surface[Mesh.ARRAY_COLOR] = colors
	surface[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	return mesh


static func _ground_color(map: MapData, p: Vector3, normal: Vector3) -> Color:
	# Patches of lighter meadow from a cheap hash of the position (no texture).
	var patch: float = 0.5 + 0.5 * sin(p.x * 0.11 + sin(p.z * 0.07) * 2.0) * cos(p.z * 0.09 - p.x * 0.03)
	var color: Color = map.grass_color.lerp(map.meadow_color, patch * 0.7)
	var steep: float = smoothstep(0.86, 0.68, normal.y)
	var path: float = map.path_cover(p.x, p.z)
	if path > 0.0:
		color = color.lerp(map.path_color.darkened(0.06 * patch), path * (1.0 - steep))
	color = color.lerp(map.rock_color, steep)
	if p.y > SNOW_HEIGHT:
		color = color.lerp(Color(0.93, 0.95, 0.97), smoothstep(SNOW_HEIGHT, SNOW_HEIGHT + 3.0, p.y) * (1.0 - steep * 0.6))
	if p.y < -0.6:
		color = color.lerp(map.dirt_color, smoothstep(-0.6, -2.0, p.y) * 0.6)
	return color


static func _build_environment(map: MapData, parent: Node3D) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = map.sky_color
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.83, 0.92)
	environment.ambient_light_energy = 0.4
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.fog_enabled = true
	environment.fog_light_color = map.sky_color
	environment.fog_density = 0.005
	environment.fog_sky_affect = 0.0
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = environment
	parent.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	parent.add_child(sun)


static func _build_props(map: MapData, parent: Node3D) -> ShaderMaterial:
	if map.all_props().is_empty():
		return null
	var body := StaticBody3D.new()
	body.name = "Props"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	parent.add_child(body)
	var builder := FlatMeshBuilder.new()
	for prop: MapProp in map.all_props():
		var shape := CollisionShape3D.new()
		shape.transform = prop.transform()
		var sx: float = prop.size.x * 0.5
		var sz: float = prop.size.z * 0.5
		var top: float = prop.size.y
		var bottom: float = -MapProp.SINK
		match prop.kind:
			MapProp.Kind.BLOCK:
				var box := BoxShape3D.new()
				box.size = Vector3(prop.size.x, top - bottom, prop.size.z)
				shape.shape = box
				shape.position += Vector3(0.0, (top + bottom) * 0.5, 0.0)
				builder.add_box(prop.transform(), Vector3(-sx, bottom, -sz), Vector3(sx, top, sz), prop.color)
			MapProp.Kind.RAMP, MapProp.Kind.STAIRS:
				var wedge := ConvexPolygonShape3D.new()
				wedge.points = PackedVector3Array([
					Vector3(-sx, bottom, -sz), Vector3(sx, bottom, -sz), Vector3(-sx, bottom, sz), Vector3(sx, bottom, sz),
					Vector3(-sx, 0.0, -sz), Vector3(sx, 0.0, -sz), Vector3(-sx, top, sz), Vector3(sx, top, sz)])
				shape.shape = wedge
				if prop.kind == MapProp.Kind.RAMP:
					builder.add_convex(prop.transform(), wedge.points, prop.color)
				else:
					var count: int = maxi(prop.steps, 1)
					for k: int in count:
						var z0: float = -sz + prop.size.z * k / count
						var z1: float = -sz + prop.size.z * (k + 1) / count
						var y1: float = top * (k + 1) / count
						var shade: Color = prop.color.darkened(0.08 * (k % 2))
						builder.add_box(prop.transform(), Vector3(-sx, bottom, z0), Vector3(sx, y1, z1), shade)
			MapProp.Kind.POLE:
				var cylinder := CylinderShape3D.new()
				cylinder.radius = sx
				cylinder.height = top - bottom
				shape.shape = cylinder
				shape.position += Vector3(0.0, (top + bottom) * 0.5, 0.0)
				builder.add_cylinder(prop.transform(), sx, bottom, top, 8, prop.color)
			MapProp.Kind.ROOF:
				var prism := ConvexPolygonShape3D.new()
				prism.points = PackedVector3Array([
					Vector3(-sx, 0.0, -sz), Vector3(sx, 0.0, -sz), Vector3(-sx, 0.0, sz), Vector3(sx, 0.0, sz),
					Vector3(-sx, top, 0.0), Vector3(sx, top, 0.0)])
				shape.shape = prism
				builder.add_convex(prop.transform(), prism.points, prop.color)
			MapProp.Kind.SPIRE:
				var pyramid := ConvexPolygonShape3D.new()
				pyramid.points = PackedVector3Array([
					Vector3(-sx, 0.0, -sz), Vector3(sx, 0.0, -sz), Vector3(-sx, 0.0, sz), Vector3(sx, 0.0, sz),
					Vector3(0.0, top, 0.0)])
				shape.shape = pyramid
				builder.add_convex(prop.transform(), pyramid.points, prop.color)
		if prop.solid:
			body.add_child(shape)
		else:
			shape.free()
	var mesh := MeshInstance3D.new()
	mesh.name = "PropMesh"
	mesh.mesh = builder.commit()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/world_props.gdshader")
	mesh.material_override = material
	body.add_child(mesh)
	return material
