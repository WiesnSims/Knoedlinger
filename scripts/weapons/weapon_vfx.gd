class_name WeaponVfx
extends Node3D
## Shows one player's weapons on every machine, from their (mirrored) build alone: swing fans for
## ARC (one per swing), a growing ring for RING, a glowing disc that pulses for AURA, circling pieces for ORBIT,
## on clients the shots of PROJECTILE weapons (the host's pool already shows its real ones), and
## impact rings and chain bolts for DROP, MINE and CHAIN (the host shows where it really hit; clients
## draw them around the player from the fire counter, cosmetic only), and the splash of every
## landing of a lobbed shot (known from the aim, so the same everywhere). A
## weapon's fire counter changing means "it just attacked"; orbit pieces are placed from the run
## time like on the host. Effects are built once per weapon and replayed (no instantiate() per
## attack).

const RING_SECONDS: float = 0.35
const AURA_PULSE_SECONDS: float = 0.3
const AURA_FILL: float = 0.12
## Height of effects above the player's feet.
const GROUND_LIFT: float = 0.15
## Impacts and bolts per weapon at once, and how long each shows.
const SPARKS: int = 64
const IMPACT_SECONDS: float = 0.4
const BOLT_SECONDS: float = 0.18


## One impact ring or chain bolt being shown.
class Spark:
	extends RefCounted
	var at: Vector3 = Vector3.ZERO
	## Negative = not yet (a mine still ticking).
	var age: float = 0.0
	var radius: float = 1.0
	var bolt: bool = false
	var angle: float = 0.0
	var length: float = 0.0


class Effect:
	extends RefCounted
	var index: int = -1
	var seen_fires: int = 0
	var time: float = 1000.0
	var nodes: Array[Node3D] = []
	var material: ShaderMaterial
	var multimesh: MultiMesh
	var sparks: Array[Spark] = []


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
		var area: float = Formulas.weapon_area(weapon, owned.mods, build.stat(&"area"))
		var fired: bool = owned.fires != effect.seen_fires
		effect.seen_fires = owned.fires
		if fired:
			effect.time = 0.0
			if player.is_local and weapon.pattern == WeaponData.Pattern.ARC:
				GameAudio.play(&"swing", player.global_position)
		else:
			effect.time += delta
		match weapon.pattern:
			WeaponData.Pattern.ARC:
				if fired:
					var yaw: float = owned.aim * TAU / 256.0
					var swings: int = mini(Formulas.weapon_amount(weapon, owned.mods, owned.extra_amount), effect.nodes.size())
					for k: int in swings:
						(effect.nodes[k] as SwingVfx).play(area, yaw + WeaponSystem.arc_turn(k, swings))
			WeaponData.Pattern.PROJECTILE:
				if fired and shots != null:
					WeaponSystem.fire_shots(weapon, origin, WeaponSystem.aim_direction(owned.aim),
							Formulas.weapon_amount(weapon, owned.mods, owned.extra_amount), area, 0.0, shots, build.stat(&"duration"))
				if weapon.hops > 0:
					if fired:
						_add_landings(effect, owned, origin, area, build.stat(&"duration"))
					_draw_sparks(effect, weapon, delta)
			WeaponData.Pattern.RING:
				var ring: Node3D = effect.nodes[0]
				# A pulling ring (Harmonika) first closes in over the pull, then goes off as usual.
				var t: float = (effect.time - weapon.pull_seconds) / RING_SECONDS
				ring.visible = t < 1.0
				if ring.visible:
					var grow: float = lerpf(0.35, 1.0, sqrt(t)) if t >= 0.0 \
							else lerpf(1.0, 0.35, effect.time / weapon.pull_seconds)
					ring.global_position = origin + Vector3(0.0, GROUND_LIFT, 0.0)
					ring.scale = Vector3.ONE * weapon.reach * area * grow
					effect.material.set_shader_parameter(&"progress", maxf(t, 0.0))
			WeaponData.Pattern.AURA:
				var disc: Node3D = effect.nodes[0]
				disc.global_position = origin + Vector3(0.0, GROUND_LIFT, 0.0)
				disc.scale = Vector3.ONE * weapon.reach * area
				effect.material.set_shader_parameter(&"progress", clampf(effect.time / AURA_PULSE_SECONDS, 0.0, 1.0))
			WeaponData.Pattern.ORBIT:
				_place_orbit(effect, owned, build, origin, run_time, area)
			WeaponData.Pattern.DROP, WeaponData.Pattern.MINE, WeaponData.Pattern.CHAIN:
				if shots == null:
					_add_host_sparks(effect, owned, area)
				elif fired:
					_add_client_sparks(effect, owned, origin, area)
				_draw_sparks(effect, weapon, delta)


func _place_orbit(effect: Effect, owned: PlayerBuild.OwnedWeapon, build: PlayerBuild, origin: Vector3,
		run_time: float, area: float) -> void:
	var weapon: WeaponData = owned.data
	var count: int = mini(Formulas.weapon_amount(weapon, owned.mods, owned.extra_amount), effect.multimesh.instance_count)
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


## Host: where the weapon really hit this frame (a chain's points in order).
func _add_host_sparks(effect: Effect, owned: PlayerBuild.OwnedWeapon, area: float) -> void:
	var weapon: WeaponData = owned.data
	var points: PackedVector2Array = owned.impacts
	if weapon.pattern == WeaponData.Pattern.CHAIN:
		# (from, to) per bolt; a forking chain branches, a splashing one rings where it hit.
		for k: int in range(1, points.size(), 2):
			_bolt(effect, points[k - 1], points[k])
			if weapon.chain_splash > 0.0:
				_ring(effect, points[k], weapon.chain_splash * area, 0.0)
		return
	for point: Vector2 in points:
		_ring(effect, point, weapon.impact_radius * area, 0.0)


## Client: the same kind of picture around the player, from the fire counter (cosmetic only).
func _add_client_sparks(effect: Effect, owned: PlayerBuild.OwnedWeapon, origin: Vector3, area: float) -> void:
	var weapon: WeaponData = owned.data
	var rng := RandomNumberGenerator.new()
	rng.seed = owned.fires * 7919 + owned.index
	var amount: int = Formulas.weapon_amount(weapon, owned.mods, owned.extra_amount)
	var here := Vector2(origin.x, origin.z)
	match weapon.pattern:
		WeaponData.Pattern.DROP:
			for k: int in amount:
				var angle: float = rng.randf() * TAU
				var distance: float = rng.randf_range(0.3, 0.7) * weapon.reach * area
				_ring(effect, here + Vector2(cos(angle), sin(angle)) * distance, weapon.impact_radius * area, 0.0)
		WeaponData.Pattern.MINE:
			_ring(effect, here, weapon.impact_radius * area, weapon.mine_delay)
		WeaponData.Pattern.CHAIN:
			var facing: Vector3 = player.facing_direction()
			var heading: float = atan2(facing.z, facing.x)
			var last: Vector2 = here
			for k: int in amount:
				heading += rng.randf_range(-0.9, 0.9)
				var next: Vector2 = last + Vector2(cos(heading), sin(heading)) * weapon.chain_range * area * 0.6
				_bolt(effect, last, next)
				if weapon.chain_splash > 0.0:
					_ring(effect, next, weapon.chain_splash * area, 0.0)
				last = next


## A lobbed weapon (hops): a splash ring where each shot will land, each when it gets there.
func _add_landings(effect: Effect, owned: PlayerBuild.OwnedWeapon, origin: Vector3, area: float, duration: float) -> void:
	var weapon: WeaponData = owned.data
	var amount: int = Formulas.weapon_amount(weapon, owned.mods, owned.extra_amount)
	var facing: Vector3 = WeaponSystem.aim_direction(owned.aim)
	var every: float = weapon.projectile_lifetime * (1.0 + duration) / weapon.hops
	for k: int in amount:
		var angle: float = WeaponSystem.shot_angle(weapon, facing, k, amount)
		var step := Vector2(sin(angle), cos(angle)) * weapon.projectile_speed * every
		for hop: int in range(1, weapon.hops + 1):
			_ring(effect, Vector2(origin.x, origin.z) + step * hop, weapon.impact_radius * area, every * hop)


func _ring(effect: Effect, at: Vector2, radius: float, delay: float) -> void:
	var spark := Spark.new()
	spark.at = Vector3(at.x, player.ground_height_at(Vector3(at.x, 0.0, at.y)) + GROUND_LIFT, at.y)
	spark.radius = radius
	spark.age = -delay
	_keep(effect, spark)


func _bolt(effect: Effect, from: Vector2, to: Vector2) -> void:
	var spark := Spark.new()
	var mid: Vector2 = (from + to) * 0.5
	spark.at = Vector3(mid.x, player.ground_height_at(Vector3(mid.x, 0.0, mid.y)) + WeaponSystem.SHOT_HEIGHT, mid.y)
	spark.bolt = true
	spark.angle = atan2(to.x - from.x, to.y - from.y)
	spark.length = from.distance_to(to)
	_keep(effect, spark)


func _keep(effect: Effect, spark: Spark) -> void:
	if effect.sparks.size() >= SPARKS:
		effect.sparks.pop_front()
	effect.sparks.append(spark)


func _draw_sparks(effect: Effect, weapon: WeaponData, delta: float) -> void:
	var shown: int = 0
	var k: int = 0
	while k < effect.sparks.size():
		var spark: Spark = effect.sparks[k]
		spark.age += delta
		var life: float = BOLT_SECONDS if spark.bolt else IMPACT_SECONDS
		if spark.age >= life:
			effect.sparks.remove_at(k)
			continue
		k += 1
		if spark.age < 0.0:
			continue
		var t: float = spark.age / life
		var basis: Basis
		if spark.bolt:
			basis = Basis(Vector3.UP, spark.angle).scaled(Vector3(0.14, 0.14, spark.length))
		else:
			basis = Basis.IDENTITY.scaled(Vector3.ONE * spark.radius * lerpf(0.4, 1.0, sqrt(t)))
		effect.multimesh.set_instance_transform(shown, Transform3D(basis, spark.at))
		effect.multimesh.set_instance_color(shown, weapon.color)
		effect.multimesh.set_instance_custom_data(shown, Color(t, 1.0 if spark.bolt else 0.0, 0.0, 0.0))
		shown += 1
	effect.multimesh.visible_instance_count = shown


func _build(owned: PlayerBuild.OwnedWeapon) -> Effect:
	var weapon: WeaponData = owned.data
	var effect := Effect.new()
	effect.index = owned.index
	effect.seen_fires = owned.fires
	match weapon.pattern:
		WeaponData.Pattern.ARC:
			for k: int in maxi(2, maxi(weapon.max_amount, weapon.amount)):
				var swing := SwingVfx.new()
				swing.setup(player, weapon)
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
			effect.multimesh.instance_count = maxi(weapon.max_amount, weapon.amount)
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
		WeaponData.Pattern.DROP, WeaponData.Pattern.MINE, WeaponData.Pattern.CHAIN, WeaponData.Pattern.PROJECTILE:
			if weapon.pattern == WeaponData.Pattern.PROJECTILE and weapon.hops <= 0:
				return effect
			# Rings lie flat (the fan mesh); a chain bolt is a thin box along +Z.
			var sparks := MultiMeshInstance3D.new()
			sparks.name = "Sparks_%s" % weapon.id
			sparks.top_level = true
			sparks.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			effect.multimesh = MultiMesh.new()
			effect.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			effect.multimesh.use_colors = true
			effect.multimesh.use_custom_data = true
			if weapon.pattern == WeaponData.Pattern.CHAIN:
				var bolt := BoxMesh.new()
				bolt.size = Vector3(1.0, 1.0, 1.0)
				effect.multimesh.mesh = bolt
			else:
				effect.multimesh.mesh = MeshFactory.swing_fan(TAU, 24)
			effect.multimesh.instance_count = SPARKS
			effect.multimesh.visible_instance_count = 0
			var spark_material := ShaderMaterial.new()
			spark_material.shader = load("res://shaders/impact.gdshader")
			sparks.material_override = spark_material
			sparks.multimesh = effect.multimesh
			sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sparks.custom_aabb = AABB(Vector3(-1000.0, -50.0, -1000.0), Vector3(2000.0, 200.0, 2000.0))
			add_child(sparks)
			effect.nodes.append(sparks)
	return effect


func _drop(effect: Effect) -> void:
	if effect == null:
		return
	for node: Node3D in effect.nodes:
		node.queue_free()
