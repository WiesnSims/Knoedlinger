class_name PortalGate
extends Node3D
## The boss gate in front of the Gemeindeamt (GAME-DESIGN.md: the portal to the Amt der Unterwelt).
## Closed, it is a stone frame with a sealed, slowly turning swirl; once the Formular has all its
## Stempel it opens and glows; while the Hofrat is out it burns violet. Only a look: the host
## decides the state and every machine shows it.

enum State { SEALED, OPEN, BOSS_OUT, DONE }

const FRAME := Color(0.55, 0.53, 0.5)
const HEIGHT: float = 5.0
const WIDTH: float = 4.2

var state: State = State.SEALED

var _swirl: MeshInstance3D
var _material: ShaderMaterial
var _sign: Label3D


func setup(map: MapData, ground: Heightfield) -> void:
	name = "PortalGate"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var at: Vector2 = map.portal_point
	position = Vector3(at.x, ground.height_at(at.x, at.y), at.y)
	# Face the village (the map centre).
	rotation.y = atan2(-at.x, -at.y)
	var parts: Array[Dictionary] = []
	for side: float in [-1.0, 1.0]:
		parts.append(MeshFactory._part(MeshFactory._box(Vector3(0.7, HEIGHT, 0.8)), Transform3D(Basis(), Vector3(side * WIDTH * 0.5, HEIGHT * 0.5, 0.0)), FRAME))
		parts.append(MeshFactory._part(MeshFactory._box(Vector3(1.0, 0.4, 1.1)), Transform3D(Basis(), Vector3(side * WIDTH * 0.5, 0.2, 0.0)), FRAME.darkened(0.2)))
	parts.append(MeshFactory._part(MeshFactory._box(Vector3(WIDTH + 1.4, 0.8, 1.0)), Transform3D(Basis(), Vector3(0.0, HEIGHT + 0.4, 0.0)), FRAME))
	# The Amt's seal on top.
	parts.append(MeshFactory._part(MeshFactory._cylinder(0.6, 0.6, 0.2, 12), Transform3D(Basis.from_euler(Vector3(PI / 2.0, 0.0, 0.0)), Vector3(0.0, HEIGHT + 0.4, 0.55)), Color(0.85, 0.7, 0.3)))
	for part: Dictionary in parts:
		part["color"] = (part["color"] as Color).srgb_to_linear()
	var frame := MeshInstance3D.new()
	frame.name = "Frame"
	frame.mesh = MeshFactory.merge(parts)
	frame.material_override = MapBuilder.vertex_color_material()
	add_child(frame)
	_swirl = MeshInstance3D.new()
	_swirl.name = "Swirl"
	var quad := QuadMesh.new()
	quad.size = Vector2(WIDTH - 0.6, HEIGHT - 0.3)
	_swirl.mesh = quad
	_swirl.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	_swirl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/portal.gdshader")
	_swirl.material_override = _material
	add_child(_swirl)
	_sign = Label3D.new()
	_sign.name = "Sign"
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.position = Vector3(0.0, HEIGHT + 1.8, 0.0)
	_sign.font_size = 72
	_sign.pixel_size = 0.012
	_sign.outline_size = 14
	_sign.modulate = Color(1.0, 0.97, 0.88)
	_sign.outline_modulate = Color(0.15, 0.08, 0.15)
	add_child(_sign)
	set_state(State.SEALED, 0, 0)


func set_state(new_state: State, found: int, total: int) -> void:
	state = new_state
	var title: String = tr("GATE_NAME")
	match state:
		State.SEALED:
			_sign.text = "%s\n%s" % [title, tr("GATE_SEALED") % [found, total] if total > 0 else tr("GATE_CLOSED")]
			_material.set_shader_parameter(&"tint", Color(0.35, 0.3, 0.45))
			_material.set_shader_parameter(&"energy", 0.35)
		State.OPEN:
			_sign.text = "%s\n%s" % [title, tr("GATE_OPEN")]
			_material.set_shader_parameter(&"tint", Color(0.55, 0.95, 0.6))
			_material.set_shader_parameter(&"energy", 1.0)
		State.BOSS_OUT:
			_sign.text = "%s\n%s" % [title, tr("GATE_BOSS_OUT")]
			_material.set_shader_parameter(&"tint", Color(0.6, 0.35, 0.9))
			_material.set_shader_parameter(&"energy", 1.0)
		State.DONE:
			_sign.text = "%s\n%s" % [title, tr("GATE_DONE")]
			_material.set_shader_parameter(&"tint", Color(0.5, 0.5, 0.5))
			_material.set_shader_parameter(&"energy", 0.15)


## Where a player must stand to go through, and where the boss comes out.
func mouth() -> Vector3:
	return global_position + global_transform.basis.z * 2.5
