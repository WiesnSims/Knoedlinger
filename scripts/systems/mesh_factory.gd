class_name MeshFactory
extends RefCounted
## Builds the chunky low-poly, vertex-coloured placeholder meshes in code (no textures, tiny .pck).
## Real models replace these from M1 on; the triangle counts stay in the 200-800 fodder budget.


## Merges primitive meshes into one ArrayMesh with one colour per part. Each part is
## {"mesh": PrimitiveMesh, "transform": Transform3D, "color": Color}.
static func merge(parts: Array[Dictionary]) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for part: Dictionary in parts:
		var mesh: PrimitiveMesh = part["mesh"]
		var transform: Transform3D = part["transform"]
		var color: Color = part["color"]
		var arrays: Array = mesh.get_mesh_arrays()
		var part_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var part_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var part_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var offset: int = vertices.size()
		for i: int in part_vertices.size():
			vertices.append(transform * part_vertices[i])
			normals.append((transform.basis * part_normals[i]).normalized())
			colors.append(color)
		for index: int in part_indices:
			indices.append(index + offset)
	var surface: Array = []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = vertices
	surface[Mesh.ARRAY_NORMAL] = normals
	surface[Mesh.ARRAY_COLOR] = colors
	surface[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	return result


## A fodder enemy standing on y = 0 and facing +Z, about 1.6 m tall before model_scale.
static func enemy(type: EnemyTypeData) -> ArrayMesh:
	var s: float = type.model_scale
	var parts: Array[Dictionary] = []
	var head := SphereMesh.new()
	head.radius = 0.32
	head.height = 0.64
	head.radial_segments = 12
	head.rings = 6
	var nose := SphereMesh.new()
	nose.radius = 0.09
	nose.height = 0.18
	nose.radial_segments = 6
	nose.rings = 3
	if type.flying:
		var body := SphereMesh.new()
		body.radius = 0.3
		body.height = 0.75
		body.radial_segments = 10
		body.rings = 5
		var wing := BoxMesh.new()
		wing.size = Vector3(0.7, 0.04, 0.3)
		parts.append(_part(body, Transform3D(Basis.from_euler(Vector3(PI / 2.0, 0.0, 0.0)), Vector3(0.0, 1.0, 0.0)), type.body_color))
		parts.append(_part(head, Transform3D(Basis(), Vector3(0.0, 1.15, 0.38)), type.head_color))
		parts.append(_part(wing, Transform3D(Basis.from_euler(Vector3(0.0, 0.0, 0.3)), Vector3(0.45, 1.15, 0.0)), Color(0.85, 0.9, 1.0)))
		parts.append(_part(wing, Transform3D(Basis.from_euler(Vector3(0.0, 0.0, -0.3)), Vector3(-0.45, 1.15, 0.0)), Color(0.85, 0.9, 1.0)))
		parts.append(_part(nose, Transform3D(Basis().scaled(Vector3(0.5, 0.5, 3.0)), Vector3(0.0, 1.12, 0.75)), Color(0.1, 0.1, 0.1)))
	else:
		var body := CylinderMesh.new()
		body.top_radius = 0.3
		body.bottom_radius = 0.4
		body.height = 0.8
		body.radial_segments = 12
		body.rings = 2
		var leg := BoxMesh.new()
		leg.size = Vector3(0.16, 0.45, 0.18)
		var arm := BoxMesh.new()
		arm.size = Vector3(0.14, 0.5, 0.14)
		parts.append(_part(body, Transform3D(Basis(), Vector3(0.0, 0.85, 0.0)), type.body_color))
		parts.append(_part(head, Transform3D(Basis(), Vector3(0.0, 1.5, 0.0)), type.head_color))
		parts.append(_part(nose, Transform3D(Basis(), Vector3(0.0, 1.48, 0.32)), type.head_color.darkened(0.25)))
		parts.append(_part(leg, Transform3D(Basis(), Vector3(0.15, 0.22, 0.0)), type.body_color.darkened(0.4)))
		parts.append(_part(leg, Transform3D(Basis(), Vector3(-0.15, 0.22, 0.0)), type.body_color.darkened(0.4)))
		parts.append(_part(arm, Transform3D(Basis.from_euler(Vector3(-0.5, 0.0, 0.2)), Vector3(0.42, 0.95, 0.1)), type.body_color))
		parts.append(_part(arm, Transform3D(Basis.from_euler(Vector3(-0.5, 0.0, -0.2)), Vector3(-0.42, 0.95, 0.1)), type.body_color))
	for part: Dictionary in parts:
		var transform: Transform3D = part["transform"]
		part["transform"] = Transform3D(transform.basis.scaled(Vector3.ONE * s), transform.origin * s)
	return merge(parts)


static func projectile() -> ArrayMesh:
	var ball := SphereMesh.new()
	ball.radius = 0.18
	ball.height = 0.36
	ball.radial_segments = 6
	ball.rings = 3
	return merge([_part(ball, Transform3D(), Color(1.0, 0.92, 0.55))])


## A flat 1 x 1 m quad facing up, for blob shadows under enemies.
static func blob_quad() -> PlaneMesh:
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	return quad


static func _part(mesh: PrimitiveMesh, transform: Transform3D, color: Color) -> Dictionary:
	return {"mesh": mesh, "transform": transform, "color": color}
