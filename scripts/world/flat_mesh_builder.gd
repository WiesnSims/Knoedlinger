class_name FlatMeshBuilder
extends RefCounted
## Collects flat-shaded, vertex-coloured convex pieces (boxes, wedges, cylinders) into one mesh.
## Colours come in as sRGB and are stored linear (see MapBuilder.vertex_color_material()).
## Every triangle is turned to face away from its piece's centre, so the winding never has to be
## typed by hand.

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()


## An axis-aligned box from `low` to `high` in the local space of `xform`.
func add_box(xform: Transform3D, low: Vector3, high: Vector3, color: Color) -> void:
	var points := PackedVector3Array()
	for corner: int in 8:
		points.append(Vector3(high.x if corner & 1 else low.x, high.y if corner & 2 else low.y, high.z if corner & 4 else low.z))
	add_convex(xform, points, color)


## Any convex hull given by its points (local space of `xform`).
func add_convex(xform: Transform3D, points: PackedVector3Array, color: Color) -> void:
	var hull: Array[PackedVector3Array] = _hull_faces(points)
	var centre := Vector3.ZERO
	for p: Vector3 in points:
		centre += p
	centre /= points.size()
	for face: PackedVector3Array in hull:
		for k: int in range(1, face.size() - 1):
			_add_triangle(xform, face[0], face[k], face[k + 1], centre, color)


## An upright cylinder with `segments` sides from y0 to y1.
func add_cylinder(xform: Transform3D, radius: float, y0: float, y1: float, segments: int, color: Color) -> void:
	var centre := Vector3(0.0, (y0 + y1) * 0.5, 0.0)
	for s: int in segments:
		var a0: float = TAU * s / segments
		var a1: float = TAU * (s + 1) / segments
		var p0 := Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		var shade: Color = color.darkened(0.06 * (s % 2))
		_add_triangle(xform, p0 + Vector3.UP * y0, p1 + Vector3.UP * y0, p1 + Vector3.UP * y1, centre, shade)
		_add_triangle(xform, p0 + Vector3.UP * y0, p1 + Vector3.UP * y1, p0 + Vector3.UP * y1, centre, shade)
		_add_triangle(xform, Vector3.UP * y1, p0 + Vector3.UP * y1, p1 + Vector3.UP * y1, centre, color)


func commit() -> ArrayMesh:
	var surface: Array = []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = _vertices
	surface[Mesh.ARRAY_NORMAL] = _normals
	surface[Mesh.ARRAY_COLOR] = _colors
	var mesh := ArrayMesh.new()
	if not _vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	return mesh


func _add_triangle(xform: Transform3D, a: Vector3, b: Vector3, c: Vector3, centre: Vector3, color: Color) -> void:
	# Godot's front faces wind clockwise seen from the front: normal = (c - a) x (b - a).
	var normal: Vector3 = (c - a).cross(b - a)
	if normal.length_squared() < 0.0000001:
		return
	if normal.dot((a + b + c) / 3.0 - centre) < 0.0:
		var swap: Vector3 = b
		b = c
		c = swap
		normal = -normal
	var world_normal: Vector3 = (xform.basis * normal).normalized()
	for p: Vector3 in [a, b, c]:
		_vertices.append(xform * p)
		_normals.append(world_normal)
		_colors.append(color.srgb_to_linear())


## Faces of the convex hull of a few points (brute force; props have at most 8 points). Each face
## is returned as its points in order around the face.
static func _hull_faces(points: PackedVector3Array) -> Array[PackedVector3Array]:
	var faces: Array[PackedVector3Array] = []
	var seen: Array[Plane] = []
	var count: int = points.size()
	for i: int in count:
		for j: int in range(i + 1, count):
			for k: int in range(j + 1, count):
				var normal: Vector3 = (points[j] - points[i]).cross(points[k] - points[i])
				if normal.length_squared() < 0.000001:
					continue
				var plane := Plane(normal.normalized(), points[i])
				var front: int = 0
				var back: int = 0
				for p: Vector3 in points:
					var d: float = plane.distance_to(p)
					if d > 0.0001:
						front += 1
					elif d < -0.0001:
						back += 1
				if front > 0 and back > 0:
					continue
				if back > 0:
					plane = -plane
				var duplicate: bool = false
				for other: Plane in seen:
					if other.normal.dot(plane.normal) > 0.9999 and absf(other.d - plane.d) < 0.0001:
						duplicate = true
						break
				if duplicate:
					continue
				seen.append(plane)
				faces.append(_face_points(points, plane))
	return faces


## The points lying on a plane, sorted by angle around their centre.
static func _face_points(points: PackedVector3Array, plane: Plane) -> PackedVector3Array:
	var on: Array[Vector3] = []
	var centre := Vector3.ZERO
	for p: Vector3 in points:
		if absf(plane.distance_to(p)) <= 0.0001:
			on.append(p)
			centre += p
	centre /= on.size()
	var axis_u: Vector3 = (on[0] - centre).normalized()
	var axis_v: Vector3 = plane.normal.cross(axis_u)
	on.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return atan2((a - centre).dot(axis_v), (a - centre).dot(axis_u)) < atan2((b - centre).dot(axis_v), (b - centre).dot(axis_u)))
	return PackedVector3Array(on)
