class_name WeaponVfx
extends Node3D
## Shows one player's weapons on every machine, from their (mirrored) build alone: swing fans for
## ARC, a growing ring for RING, a glowing disc that pulses for AURA, circling pieces for ORBIT,
## and on clients the shots of PROJECTILE weapons (the host's pool already shows its real ones). A
## weapon's fire counter changing means "it just attacked"; orbit pieces are placed from the run
## time like on the host. Effects are built once per weapon and replayed (no instantiate() per
## attack).

const RING_SECONDS: float = 0.35
const AURA_PULSE_SECONDS: float = 0.3
const AURA_FILL: float = 0.12
## Height of effects above the player's feet.
const GROUND_LIFT: float = 0.15


class Effect:
	extends RefCounted
	var index: int = -1
	var seen_fires: int = 0
	var time: float = 1000.0
	var nodes: Array[Node3D] = []
	var material: ShaderMaterial
	var multimesh: MultiMesh


var player: Player

var _effects: Array[Effect] = []


func setup(p_player: Player) -> void:
	player = p_player
	name = "Weapons_%d" % player.peer_id
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Every frame: follows the build's weapons and plays what fired. `shots` is the client's
## cosmetic projectile pool (null on the host).
func sync(build: PlayerBuild, run_time: float, delta: float, shots: ProjectilePool) -> void:
	if player == null or build == null:
		return
	while _effects.size() > build.weapons.size():
		_drop(_effects.pop_back())
	var origin: Vector3 = player.get_global_transform_interpolated().origin
	for slot: int in build.weapons.size():
		var owned: PlayerBuild.OwnedWeapon = build.weapons[slot]
		if slot >= _effects.size():
			_effects.append(null)
		var effect: Effect = _effects[slot]
		if effect == null or effect.index != owned.index:
			if effect != null:
				_drop(effect)
			effect = _build(owned)
			_effects[slot] = effect
		var weapon: WeaponData = owned.data
		var area: float = Formulas.weapon_area(weapon, owned.level, build.stat(&"area"))
		var fired: bool = owned.fires != effect.seen_fires
		effect.seen_fires = owned.fires
		if fired:
			effect.time = 0.0
		else:
			effect.time += delta
		match weapon.pattern:
			WeaponData.Pattern.ARC:
				if fired:
					(effect.nodes[0] as SwingVfx).play(area)
					if Formulas.weapon_amount(weapon, owned.level) >= 2:
						(effect.nodes[1] as SwingVfx).play(area)
			WeaponData.Pattern.PROJECTILE:
				if fired and shots != null:
					WeaponSystem.fire_shots(weapon, origin, player.facing_direction(),
							Formulas.weapon_amount(weapon, owned.level), area, 0.0, shots)
			WeaponData.Pattern.RING:
				var ring: Node3D = effect.nodes[0]
				var t: float = effect.time / RING_SECONDS
				ring.visible = t < 1.0
				if ring.visible:
					ring.global_position = origin + Vector3(0.0, GROUND_LIFT, 0.0)
					ring.scale = Vector3.ONE * weapon.reach * area * lerpf(0.35, 1.0, sqrt(t))
					effect.material.set_shader_parameter(&"progress", t)
			WeaponData.Pattern.AURA:
				var disc: Node3D = effect.nodes[0]
				disc.global_position = origin + Vector3(0.0, GROUND_LIFT, 0.0)
				disc.scale = Vector3.ONE * weapon.reach * area
				effect.material.set_shader_parameter(&"progress", clampf(effect.time / AURA_PULSE_SECONDS, 0.0, 1.0))
			WeaponData.Pattern.ORBIT:
				_place_orbit(effect, owned, build, origin, run_time, area)


func _place_orbit(effect: Effect, owned: PlayerBuild.OwnedWeapon, build: PlayerBuild, origin: Vector3,
		run_time: float, area: float) -> void:
	var weapon: WeaponData = owned.data
	var count: int = mini(Formulas.weapon_amount(weapon, owned.level), effect.multimesh.instance_count)
	var size: float = weapon.projectile_radius * area * 2.0
	var spin: float = run_time * 6.0
	for k: int in count:
		var offset: Vector2 = Formulas.orbit_offset(weapon, k, count, run_time, area, build.stat(&"move_speed"))
		var angle: float = atan2(offset.y, offset.x)
		# Pins lie along the circle; balls also tumble.
		var basis := Basis(Vector3.UP, -angle - PI * 0.5)
		if weapon.look == WeaponData.Look.BALL:
			basis = basis * Basis(Vector3.RIGHT, spin)
		var at := Vector3(origin.x + offset.x, origin.y + WeaponSystem.SHOT_HEIGHT, origin.z + offset.y)
		effect.multimesh.set_instance_transform(k, Transform3D(basis.scaled(Vector3.ONE * size), at))
	effect.multimesh.visible_instance_count = count


func _build(owned: PlayerBuild.OwnedWeapon) -> Effect:
	var weapon: WeaponData = owned.data
	var effect := Effect.new()
	effect.index = owned.index
	effect.seen_fires = owned.fires
	match weapon.pattern:
		WeaponData.Pattern.ARC:
			for behind: bool in [false, true]:
				var swing := SwingVfx.new()
				swing.setup(player, weapon, behind)
				add_child(swing)
				effect.nodes.append(swing)
		WeaponData.Pattern.RING, WeaponData.Pattern.AURA:
			var disc := MeshInstance3D.new()
			disc.name = "Disc_%s" % weapon.id
			disc.top_level = true
			disc.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			disc.mesh = MeshFactory.swing_fan(TAU, 32)
			disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			effect.material = ShaderMaterial.new()
			effect.material.shader = load("res://shaders/pulse.gdshader")
			effect.material.set_shader_parameter(&"tint", weapon.color)
			effect.material.set_shader_parameter(&"fill", AURA_FILL if weapon.pattern == WeaponData.Pattern.AURA else 0.0)
			disc.material_override = effect.material
			disc.visible = weapon.pattern == WeaponData.Pattern.AURA
			add_child(disc)
			effect.nodes.append(disc)
		WeaponData.Pattern.ORBIT:
			var pieces := MultiMeshInstance3D.new()
			pieces.name = "Orbit_%s" % weapon.id
			pieces.top_level = true
			pieces.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			effect.multimesh = MultiMesh.new()
			effect.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			# White instance colours (docs/DECISIONS.md: without them the Compatibility renderer
			# multiplies COLOR by stray per-instance data).
			effect.multimesh.use_colors = true
			effect.multimesh.mesh = MeshFactory.orbit_piece(weapon.look)
			effect.multimesh.instance_count = Formulas.weapon_amount(weapon, weapon.max_level)
			for k: int in effect.multimesh.instance_count:
				effect.multimesh.set_instance_color(k, Color.WHITE)
			effect.multimesh.visible_instance_count = 0
			var material := ShaderMaterial.new()
			material.shader = load("res://shaders/projectile.gdshader")
			pieces.material_override = material
			pieces.multimesh = effect.multimesh
			pieces.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pieces.custom_aabb = AABB(Vector3(-1000.0, -50.0, -1000.0), Vector3(2000.0, 200.0, 2000.0))
			add_child(pieces)
			effect.nodes.append(pieces)
	return effect


func _drop(effect: Effect) -> void:
	if effect == null:
		return
	for node: Node3D in effect.nodes:
		node.queue_free()
