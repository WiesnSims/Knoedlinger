class_name MeshFactory
extends RefCounted
## Builds the chunky low-poly, vertex-coloured placeholder meshes in code (no textures, tiny .pck).
## Real models replace these later; the triangle counts stay in the 200-800 fodder budget.


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
	if type.look != &"":
		parts = _special_look(type)
		for part: Dictionary in parts:
			var placed: Transform3D = part["transform"]
			part["transform"] = Transform3D(placed.basis.scaled(Vector3.ONE * s), placed.origin * s)
		return merge(parts)
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


## A shot: a ski pole pointing along +z (the pool turns it into its flight direction).
static func projectile() -> ArrayMesh:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.05
	pole.bottom_radius = 0.05
	pole.height = 1.3
	pole.radial_segments = 5
	pole.rings = 1
	var basket := CylinderMesh.new()
	basket.top_radius = 0.16
	basket.bottom_radius = 0.16
	basket.height = 0.04
	basket.radial_segments = 8
	basket.rings = 1
	var along_z := Basis.from_euler(Vector3(PI / 2.0, 0.0, 0.0))
	return merge([
		_part(pole, Transform3D(along_z, Vector3.ZERO), Color(0.95, 0.9, 0.55)),
		_part(basket, Transform3D(along_z, Vector3(0.0, 0.0, 0.45)), Color(0.3, 0.3, 0.35)),
	])


## An orbiting piece about 1 m across before its scale: a Mozartkugel (BALL) or a rolling pin
## lying along the circle (PIN).
static func orbit_piece(look: WeaponData.Look) -> ArrayMesh:
	if look == WeaponData.Look.PIN:
		var roll := CylinderMesh.new()
		roll.top_radius = 0.2
		roll.bottom_radius = 0.2
		roll.height = 1.1
		roll.radial_segments = 8
		roll.rings = 1
		var handle := CylinderMesh.new()
		handle.top_radius = 0.07
		handle.bottom_radius = 0.07
		handle.height = 1.7
		handle.radial_segments = 6
		handle.rings = 1
		var along_x := Basis.from_euler(Vector3(0.0, 0.0, PI / 2.0))
		return merge([
			_part(roll, Transform3D(along_x, Vector3.ZERO), Color(0.86, 0.68, 0.45)),
			_part(handle, Transform3D(along_x, Vector3.ZERO), Color(0.62, 0.45, 0.28)),
		])
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 10
	ball.rings = 5
	var foil := SphereMesh.new()
	foil.radius = 0.2
	foil.height = 0.3
	foil.radial_segments = 8
	foil.rings = 3
	return merge([
		_part(ball, Transform3D(), Color(0.42, 0.25, 0.14)),
		_part(foil, Transform3D(Basis(), Vector3(0.0, 0.42, 0.0)), Color(0.95, 0.8, 0.35)),
	])


## A Brösel: a lumpy low-poly crumb about 1 m across before the instance scale.
static func brosel() -> ArrayMesh:
	var crumb := SphereMesh.new()
	crumb.radius = 0.5
	crumb.height = 0.75
	crumb.radial_segments = 6
	crumb.rings = 3
	var chip := BoxMesh.new()
	chip.size = Vector3(0.45, 0.35, 0.45)
	return merge([
		_part(crumb, Transform3D(), Color.WHITE),
		_part(chip, Transform3D(Basis.from_euler(Vector3(0.5, 0.7, 0.3)), Vector3(0.25, 0.15, 0.1)), Color(0.85, 0.85, 0.85)),
	])


## The Knödl: a unit sphere (radius 1), scaled to the Knödl's radius by its node. Fine enough
## (about 4,000 triangles, inside the hero budget) that a 4 m Knödl still has a round outline.
static func knodl() -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	return sphere


## A flat fan on the ground for melee swings, centred on the player and facing +Z: `segments`
## slices over `arc` radians from radius 0.4 to 1 (scaled to the reach by the node).
## UV.x runs across the arc, UV.y outward.
static func swing_fan(arc: float, segments: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for s: int in segments + 1:
		var t: float = float(s) / segments
		var angle: float = -arc * 0.5 + arc * t
		var direction := Vector3(sin(angle), 0.0, cos(angle))
		vertices.append(direction * 0.4)
		uvs.append(Vector2(t, 0.0))
		vertices.append(direction)
		uvs.append(Vector2(t, 1.0))
	for s: int in segments:
		var i: int = s * 2
		indices.append_array(PackedInt32Array([i, i + 1, i + 2, i + 1, i + 3, i + 2]))
	var surface: Array = []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = vertices
	surface[Mesh.ARRAY_TEX_UV] = uvs
	surface[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	return mesh


## A flat 1 x 1 m quad facing up, for blob shadows under enemies.
static func blob_quad() -> PlaneMesh:
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	return quad


static func _part(mesh: PrimitiveMesh, transform: Transform3D, color: Color) -> Dictionary:
	return {"mesh": mesh, "transform": transform, "color": color}


static func _sphere(radius: float, segments: int = 10) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = maxi(segments / 2, 3)
	return mesh


static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


## A cylinder (top_radius 0 makes a cone) standing on its middle.
static func _cylinder(top: float, bottom: float, height: float, segments: int = 8) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return mesh


static func _at(where: Vector3, euler: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(euler), where)


## Elites, bosses and the Hofrat's paperwork: built like the fodder (facing +z, feet at y 0, about
## 1.6 m before model_scale), one merged mesh each.
static func _special_look(type: EnemyTypeData) -> Array[Dictionary]:
	var body: Color = type.body_color
	var head: Color = type.head_color
	var parts: Array[Dictionary] = []
	var dark := Color(0.12, 0.1, 0.09)
	match type.look:
		&"perchte":
			# Shaggy fur, a carved wooden mask with horns, cow bells on the belt.
			parts.append(_part(_cylinder(0.42, 0.6, 1.1, 10), _at(Vector3(0.0, 0.6, 0.0)), body))
			for k: int in 6:
				var angle: float = TAU * k / 6.0
				parts.append(_part(_box(Vector3(0.3, 0.5, 0.12)), _at(Vector3(sin(angle) * 0.52, 0.3, cos(angle) * 0.52), Vector3(0.0, angle, 0.2)), body.darkened(0.2)))
			parts.append(_part(_sphere(0.34), _at(Vector3(0.0, 1.38, 0.05)), head))
			parts.append(_part(_box(Vector3(0.36, 0.12, 0.1)), _at(Vector3(0.0, 1.28, 0.34)), Color(0.95, 0.95, 0.9)))
			for side: float in [-1.0, 1.0]:
				parts.append(_part(_cylinder(0.0, 0.1, 0.7, 6), _at(Vector3(side * 0.28, 1.75, 0.0), Vector3(0.0, 0.0, -side * 0.5)), Color(0.9, 0.86, 0.75)))
				parts.append(_part(_sphere(0.06, 6), _at(Vector3(side * 0.12, 1.45, 0.32)), dark))
				parts.append(_part(_cylinder(0.08, 0.12, 0.18, 6), _at(Vector3(side * 0.3, 0.75, 0.42)), Color(0.85, 0.7, 0.3)))
		&"radler":
			# A cyclist in lycra on a bike, helmet on, bent over the handlebar.
			for z: float in [-0.5, 0.5]:
				parts.append(_part(_cylinder(0.38, 0.38, 0.07, 12), _at(Vector3(0.0, 0.38, z), Vector3(0.0, 0.0, PI / 2.0)), dark))
			parts.append(_part(_box(Vector3(0.06, 0.08, 1.0)), _at(Vector3(0.0, 0.62, 0.0), Vector3(0.2, 0.0, 0.0)), Color(0.9, 0.9, 0.95)))
			parts.append(_part(_cylinder(0.24, 0.28, 0.75, 8), _at(Vector3(0.0, 1.05, 0.05), Vector3(0.9, 0.0, 0.0)), body))
			parts.append(_part(_sphere(0.24), _at(Vector3(0.0, 1.32, 0.42)), Color(0.95, 0.78, 0.65)))
			parts.append(_part(_sphere(0.27), _at(Vector3(0.0, 1.42, 0.38)), head))
			parts.append(_part(_box(Vector3(0.3, 0.06, 0.06)), _at(Vector3(0.0, 1.34, 0.64)), dark))
			for side: float in [-1.0, 1.0]:
				parts.append(_part(_box(Vector3(0.1, 0.5, 0.1)), _at(Vector3(side * 0.15, 0.62, 0.02)), body.darkened(0.3)))
				parts.append(_part(_box(Vector3(0.08, 0.45, 0.08)), _at(Vector3(side * 0.2, 1.05, 0.48), Vector3(-0.9, 0.0, 0.0)), body))
		&"akten":
			# A floating file folder with papers sticking out and a stern pair of glasses.
			parts.append(_part(_box(Vector3(0.75, 0.95, 0.18)), _at(Vector3(0.0, 1.0, 0.0)), body))
			for k: int in 3:
				parts.append(_part(_box(Vector3(0.62, 0.2, 0.12)), _at(Vector3(0.05 * k - 0.05, 1.5 + k * 0.03, 0.0), Vector3(0.0, 0.0, 0.1 * (k - 1))), head))
			for side: float in [-1.0, 1.0]:
				parts.append(_part(_cylinder(0.11, 0.11, 0.04, 8), _at(Vector3(side * 0.16, 1.15, 0.11), Vector3(PI / 2.0, 0.0, 0.0)), dark))
			parts.append(_part(_box(Vector3(0.36, 0.05, 0.04)), _at(Vector3(0.0, 0.92, 0.11)), dark))
		&"formular":
			parts.append(_part(_box(Vector3(0.5, 0.7, 0.04)), _at(Vector3(0.0, 1.0, 0.0), Vector3(0.2, 0.0, 0.1)), body))
			for k: int in 4:
				parts.append(_part(_box(Vector3(0.36, 0.03, 0.05)), _at(Vector3(0.0, 1.2 - k * 0.12, 0.0), Vector3(0.2, 0.0, 0.1)), head))
		&"krampus":
			# Black fur, long horns, a long tongue, chains, the Rute and a basket on his back.
			parts.append(_part(_cylinder(0.45, 0.58, 1.05, 12), _at(Vector3(0.0, 0.62, 0.0)), body))
			parts.append(_part(_sphere(0.36, 12), _at(Vector3(0.0, 1.42, 0.06)), head))
			parts.append(_part(_box(Vector3(0.14, 0.42, 0.06)), _at(Vector3(0.0, 1.12, 0.38), Vector3(0.3, 0.0, 0.0)), Color(0.7, 0.32, 0.42)))
			for side: float in [-1.0, 1.0]:
				parts.append(_part(_cylinder(0.0, 0.11, 0.9, 6), _at(Vector3(side * 0.34, 1.86, -0.05), Vector3(-0.35, 0.0, -side * 0.65)), Color(0.85, 0.8, 0.68)))
				parts.append(_part(_sphere(0.06, 6), _at(Vector3(side * 0.13, 1.5, 0.36)), Color(0.98, 0.85, 0.3)))
				parts.append(_part(_box(Vector3(0.16, 0.6, 0.16)), _at(Vector3(side * 0.6, 0.95, 0.15), Vector3(-0.4, 0.0, side * 0.25)), body))
			for k: int in 5:
				parts.append(_part(_box(Vector3(0.12, 0.12, 0.05)), _at(Vector3(-0.45 + k * 0.22, 0.9 - absf(k - 2) * 0.06, 0.48)), Color(0.55, 0.55, 0.58)))
			parts.append(_part(_cylinder(0.05, 0.08, 1.2, 5), _at(Vector3(0.72, 1.1, 0.5), Vector3(0.6, 0.0, 0.0)), Color(0.5, 0.36, 0.22)))
			parts.append(_part(_cylinder(0.32, 0.26, 0.5, 8), _at(Vector3(0.0, 1.05, -0.5)), Color(0.55, 0.4, 0.25)))
			for side: float in [-1.0, 1.0]:
				parts.append(_part(_box(Vector3(0.2, 0.4, 0.25)), _at(Vector3(side * 0.2, 0.12, 0.05)), dark))
		&"lawine":
			# A tumbling heap of snow lumps with a few rocks and a broken fir in it.
			for k: int in 9:
				var angle: float = TAU * k / 9.0
				var r: float = 0.35 + 0.08 * (k % 3)
				parts.append(_part(_sphere(r, 10), _at(Vector3(cos(angle) * 0.45, 0.45 + 0.25 * (k % 2), sin(angle) * 0.4)), body if k % 2 == 0 else head))
			parts.append(_part(_sphere(0.6, 12), _at(Vector3(0.0, 0.85, 0.0)), body))
			parts.append(_part(_sphere(0.16, 6), _at(Vector3(0.4, 0.95, 0.35)), Color(0.5, 0.5, 0.52)))
			parts.append(_part(_sphere(0.12, 6), _at(Vector3(-0.45, 0.6, 0.4)), Color(0.45, 0.45, 0.48)))
			parts.append(_part(_cylinder(0.0, 0.2, 0.8, 6), _at(Vector3(-0.2, 1.3, -0.2), Vector3(0.6, 0.0, 0.4)), StructureKit.FIR_GREEN))
		&"wuehlmaus":
			# A plump vole half out of its molehill.
			parts.append(_part(_cylinder(0.55, 0.75, 0.35, 10), _at(Vector3(0.0, 0.17, 0.0)), Color(0.36, 0.26, 0.18)))
			parts.append(_part(_sphere(0.42, 10), _at(Vector3(0.0, 0.55, 0.0)), body))
			parts.append(_part(_sphere(0.28, 8), _at(Vector3(0.0, 0.8, 0.3)), head))
			for side: float in [-1.0, 1.0]:
				parts.append(_part(_sphere(0.1, 6), _at(Vector3(side * 0.2, 1.02, 0.2)), head.darkened(0.2)))
				parts.append(_part(_sphere(0.05, 6), _at(Vector3(side * 0.1, 0.86, 0.54)), dark))
			parts.append(_part(_sphere(0.07, 6), _at(Vector3(0.0, 0.78, 0.58)), Color(0.85, 0.55, 0.55)))
		&"rasenmaeher":
			# A round robot mower with a blade housing and a little antenna.
			parts.append(_part(_cylinder(0.62, 0.7, 0.3, 14), _at(Vector3(0.0, 0.25, 0.0)), body))
			parts.append(_part(_cylinder(0.4, 0.5, 0.18, 12), _at(Vector3(0.0, 0.48, -0.05)), head))
			parts.append(_part(_box(Vector3(0.36, 0.08, 0.1)), _at(Vector3(0.0, 0.5, 0.42)), dark))
			parts.append(_part(_cylinder(0.02, 0.02, 0.4, 4), _at(Vector3(0.2, 0.75, -0.2)), dark))
			parts.append(_part(_sphere(0.06, 6), _at(Vector3(0.2, 0.96, -0.2)), Color(0.4, 0.85, 1.0)))
			for x: float in [-0.62, 0.62]:
				parts.append(_part(_cylinder(0.2, 0.2, 0.1, 10), _at(Vector3(x, 0.2, -0.25), Vector3(0.0, 0.0, PI / 2.0)), dark))
		&"schneemann":
			# Three snowballs, a carrot nose, coal eyes, a pot for a hat and twig arms.
			parts.append(_part(_sphere(0.55, 12), _at(Vector3(0.0, 0.5, 0.0)), body))
			parts.append(_part(_sphere(0.42, 12), _at(Vector3(0.0, 1.2, 0.0)), body))
			parts.append(_part(_sphere(0.3, 10), _at(Vector3(0.0, 1.75, 0.0)), head))
			parts.append(_part(_cylinder(0.0, 0.07, 0.35, 6), _at(Vector3(0.0, 1.75, 0.42), Vector3(PI / 2.0, 0.0, 0.0)), Color(0.95, 0.55, 0.2)))
			parts.append(_part(_cylinder(0.24, 0.26, 0.3, 10), _at(Vector3(0.0, 2.08, 0.0)), Color(0.35, 0.36, 0.4)))
			for side: float in [-1.0, 1.0]:
				parts.append(_part(_sphere(0.05, 6), _at(Vector3(side * 0.1, 1.85, 0.27)), dark))
				parts.append(_part(_box(Vector3(0.05, 0.05, 0.7)), _at(Vector3(side * 0.6, 1.3, 0.0), Vector3(0.0, side * 1.4, 0.4)), Color(0.4, 0.28, 0.18)))
		&"gartenzwerg":
			# Red cap? No: a blue coat and a gold-yellow pointed cap (red is for danger only), white beard.
			parts.append(_part(_cylinder(0.3, 0.42, 0.7, 10), _at(Vector3(0.0, 0.45, 0.0)), body))
			parts.append(_part(_sphere(0.3, 10), _at(Vector3(0.0, 1.0, 0.0)), head))
			parts.append(_part(_cylinder(0.0, 0.3, 0.7, 10), _at(Vector3(0.0, 1.52, -0.05)), Color(0.95, 0.75, 0.2)))
			parts.append(_part(_cylinder(0.26, 0.12, 0.4, 8), _at(Vector3(0.0, 0.8, 0.2)), Color(0.96, 0.96, 0.94)))
			parts.append(_part(_sphere(0.08, 6), _at(Vector3(0.0, 1.0, 0.3)), head.darkened(0.2)))
			parts.append(_part(_box(Vector3(0.5, 0.18, 0.4)), _at(Vector3(0.0, 0.09, 0.05)), dark))
		&"kontrolleur":
			# A ticket inspector in a dark uniform with a peaked cap and a clipboard.
			parts.append(_part(_cylinder(0.4, 0.46, 1.0, 12), _at(Vector3(0.0, 0.8, 0.0)), body))
			parts.append(_part(_sphere(0.3, 10), _at(Vector3(0.0, 1.5, 0.0)), head))
			parts.append(_part(_cylinder(0.32, 0.3, 0.14, 12), _at(Vector3(0.0, 1.76, 0.0)), body.darkened(0.2)))
			parts.append(_part(_box(Vector3(0.4, 0.04, 0.2)), _at(Vector3(0.0, 1.7, 0.3)), dark))
			parts.append(_part(_box(Vector3(0.36, 0.46, 0.04)), _at(Vector3(0.35, 1.0, 0.38), Vector3(0.3, -0.4, 0.0)), Color(0.9, 0.86, 0.75)))
			for side: float in [-1.0, 1.0]:
				parts.append(_part(_box(Vector3(0.18, 0.5, 0.2)), _at(Vector3(side * 0.13, 0.25, 0.0)), body.darkened(0.3)))
				parts.append(_part(_sphere(0.04, 6), _at(Vector3(side * 0.1, 1.55, 0.28)), dark))
		&"hofrat":
			# Grey suit, white shirt, tie, glasses, a briefcase and the giant ABGELEHNT stamp.
			parts.append(_part(_cylinder(0.42, 0.48, 1.0, 12), _at(Vector3(0.0, 0.8, 0.0)), body))
			parts.append(_part(_box(Vector3(0.3, 0.55, 0.08)), _at(Vector3(0.0, 1.0, 0.43)), Color(0.96, 0.96, 0.95)))
			parts.append(_part(_box(Vector3(0.09, 0.45, 0.06)), _at(Vector3(0.0, 0.98, 0.48)), Color(0.2, 0.36, 0.28)))
			parts.append(_part(_sphere(0.32, 12), _at(Vector3(0.0, 1.55, 0.0)), head))
			parts.append(_part(_cylinder(0.33, 0.33, 0.14, 10), _at(Vector3(0.0, 1.62, -0.04)), Color(0.75, 0.75, 0.78)))
			for side: float in [-1.0, 1.0]:
				parts.append(_part(_cylinder(0.08, 0.08, 0.03, 8), _at(Vector3(side * 0.12, 1.58, 0.3), Vector3(PI / 2.0, 0.0, 0.0)), dark))
				parts.append(_part(_box(Vector3(0.18, 0.5, 0.2)), _at(Vector3(side * 0.13, 0.25, 0.0)), body.darkened(0.25)))
			parts.append(_part(_box(Vector3(0.16, 0.55, 0.16)), _at(Vector3(0.55, 1.15, 0.2), Vector3(-0.3, 0.0, 0.3)), body))
			parts.append(_part(_cylinder(0.06, 0.06, 0.5, 6), _at(Vector3(0.68, 1.55, 0.38)), Color(0.5, 0.36, 0.22)))
			parts.append(_part(_box(Vector3(0.6, 0.22, 0.45)), _at(Vector3(0.68, 1.85, 0.38)), Color(0.42, 0.3, 0.58)))
			parts.append(_part(_box(Vector3(0.5, 0.36, 0.12)), _at(Vector3(-0.58, 0.6, 0.1)), Color(0.42, 0.28, 0.16)))
		&"geist":
			# A Stammgast-Geist: a bedsheet ghost with a ragged hem, arms out, round black eyes, a
			# wailing mouth and his Krügerl (head colour) still in one hand. He hovers, so no feet.
			parts.append(_part(_sphere(0.42, 10), _at(Vector3(0.0, 1.25, 0.0)), body))
			parts.append(_part(_cylinder(0.42, 0.52, 0.85, 12), _at(Vector3(0.0, 0.82, 0.0)), body))
			for k: int in 8:
				var angle: float = TAU * k / 8.0
				parts.append(_part(_cylinder(0.14, 0.0, 0.3, 6), _at(Vector3(sin(angle) * 0.42, 0.28, cos(angle) * 0.42)), body))
			for side: float in [-1.0, 1.0]:
				parts.append(_part(_sphere(0.09, 6), _at(Vector3(side * 0.15, 1.32, 0.36)), dark))
				parts.append(_part(_cylinder(0.1, 0.13, 0.5, 6), _at(Vector3(side * 0.5, 1.0, 0.22), Vector3(PI / 2.4, 0.0, side * 0.3)), body))
			parts.append(_part(_sphere(0.08, 6), _at(Vector3(0.0, 1.1, 0.39)), dark))
			parts.append(_part(_cylinder(0.11, 0.11, 0.24, 8), _at(Vector3(0.58, 1.1, 0.5)), head))
			parts.append(_part(_cylinder(0.12, 0.12, 0.06, 8), _at(Vector3(0.58, 1.24, 0.5)), Color(0.98, 0.97, 0.92)))
		&"schnecke":
			# A vineyard snail: a long soft foot, a striped spiral house on its back, two eye stalks.
			parts.append(_part(_box(Vector3(0.42, 0.22, 1.2)), _at(Vector3(0.0, 0.11, 0.05)), body))
			parts.append(_part(_sphere(0.2, 8), _at(Vector3(0.0, 0.26, 0.62)), body))
			parts.append(_part(_sphere(0.5, 12), _at(Vector3(0.0, 0.62, -0.12)), head))
			parts.append(_part(_sphere(0.34, 10), _at(Vector3(0.12, 0.7, -0.08)), head.darkened(0.15)))
			parts.append(_part(_sphere(0.18, 8), _at(Vector3(0.24, 0.76, -0.04)), head.lightened(0.15)))
			for side: float in [-1.0, 1.0]:
				parts.append(_part(_cylinder(0.03, 0.04, 0.4, 5), _at(Vector3(side * 0.1, 0.48, 0.66), Vector3(-0.3, 0.0, side * 0.25)), body))
				parts.append(_part(_sphere(0.06, 6), _at(Vector3(side * 0.15, 0.68, 0.72)), dark))
		&"star":
			# A starling: glossy dark speckled body, a yellow beak, wings out.
			parts.append(_part(_sphere(0.3, 8), _at(Vector3(0.0, 0.5, 0.0)), body))
			parts.append(_part(_sphere(0.2, 8), _at(Vector3(0.0, 0.66, 0.24)), body.lightened(0.08)))
			parts.append(_part(_cylinder(0.0, 0.06, 0.22, 5), _at(Vector3(0.0, 0.64, 0.48), Vector3(PI / 2.0, 0.0, 0.0)), head))
			parts.append(_part(_box(Vector3(0.18, 0.04, 0.3)), _at(Vector3(0.0, 0.5, -0.36), Vector3(0.2, 0.0, 0.0)), body.darkened(0.2)))
			for side: float in [-1.0, 1.0]:
				parts.append(_part(_box(Vector3(0.5, 0.04, 0.26)), _at(Vector3(side * 0.4, 0.58, -0.02), Vector3(0.0, 0.0, side * 0.35)), body.darkened(0.15)))
				parts.append(_part(_sphere(0.04, 4), _at(Vector3(side * 0.18, 0.46, 0.12)), Color(0.85, 0.85, 0.8)))
		&"wespe":
			# A wasp: yellow and black stripes (no red: red is for danger), see-through-ish wings, a sting.
			parts.append(_part(_sphere(0.16, 8), _at(Vector3(0.0, 0.62, 0.3)), dark))
			parts.append(_part(_sphere(0.14, 8), _at(Vector3(0.0, 0.62, 0.1)), body))
			for k: int in 3:
				parts.append(_part(_cylinder(0.2 - k * 0.03, 0.2 - k * 0.03, 0.12, 8), _at(Vector3(0.0, 0.58, -0.1 - k * 0.13), Vector3(PI / 2.0, 0.0, 0.0)), body if k % 2 == 0 else dark))
			parts.append(_part(_cylinder(0.0, 0.05, 0.16, 4), _at(Vector3(0.0, 0.56, -0.5), Vector3(-PI / 2.0, 0.0, 0.0)), dark))
			for side: float in [-1.0, 1.0]:
				parts.append(_part(_box(Vector3(0.42, 0.02, 0.2)), _at(Vector3(side * 0.26, 0.78, 0.08), Vector3(0.0, side * 0.3, side * 0.3)), head))
				parts.append(_part(_sphere(0.05, 5), _at(Vector3(side * 0.08, 0.68, 0.42)), dark))
		&"sturm":
			# Der Sturm: a whirlwind funnel of young wine with leaves and a vine stake caught in it.
			for k: int in 6:
				var r: float = 0.25 + k * 0.17
				parts.append(_part(_cylinder(r, r + 0.12, 0.38, 12), _at(Vector3(sin(k * 1.3) * 0.12, 0.2 + k * 0.36, cos(k * 1.3) * 0.12)), body if k % 2 == 0 else head))
			for k: int in 5:
				var angle: float = TAU * k / 5.0
				parts.append(_part(_box(Vector3(0.24, 0.03, 0.18)), _at(Vector3(cos(angle) * (0.6 + k * 0.12), 0.6 + k * 0.38, sin(angle) * (0.6 + k * 0.12)), Vector3(0.6, angle, 0.4)), StructureKit.FIR_GREEN.lightened(0.2)))
			parts.append(_part(_cylinder(0.04, 0.04, 1.4, 5), _at(Vector3(0.5, 1.4, 0.2), Vector3(0.4, 0.0, 0.9)), Color(0.5, 0.36, 0.22)))
			parts.append(_part(_sphere(0.12, 6), _at(Vector3(-0.6, 1.9, 0.3)), Color(0.55, 0.2, 0.45)))
	return parts
