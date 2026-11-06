class_name Knodl
extends RigidBody3D
## Da Knödl (GAME-DESIGN.md, "The twist"): a dumpling on an elastic string (the Spagat) behind its
## player. It grows with every Brösel it absorbs, crushes enemies it rolls into (damage = base *
## speed * radius), and can be thrown (Schupfn) and reeled back in.
##
## The host simulates every player's Knödl with Jolt (CLAUDE.md: host-authoritative Knödl physics).
## Clients get a frozen copy that follows the host's world state (apply_remote()).

## LOOSE: torn off its string by the Familienstreit (co-op event), rolling away on its own.
enum State { ATTACHED, THROWN, REELING, LOOSE }

## Below the ground by more than this, it fell out of the world and comes back.
const FALL_LIMIT: float = 12.0
## Smoothing of a client's copy toward the host's state (1/s).
const REMOTE_FOLLOW_SPEED: float = 14.0
const LAYER_KNODL: int = 4
## Crumb pattern density in the shader, per metre of radius.
const CRUMBS_PER_METRE: float = 7.0
## View fade: fully solid from FADE_NEAR + FADE_RANGE metres between camera and dough, never below
## FADE_MIN, and FADE_HIDING while it hides its player.
const FADE_NEAR: float = 0.3
const FADE_RANGE: float = 2.0
const FADE_MIN: float = 0.25
const FADE_HIDING: float = 0.45

var owner_peer: int = 1
var balance: BalanceData
var sort: KnodlSortData
## The player it is tied to.
var holder: Player
## Co-op Riesenknödl: the second player holding this merged Knödl by their string too.
var co_holder: Player
## Co-op: merged into a partner's Knödl (hidden, frozen, waiting to split off again).
var merged_away: bool = false
## Knödl-Pass: the teammate this throw is aimed at (0 = none) and seconds since the throw.
var pass_target: int = 0
var throw_age: float = 0.0
## Familienstreit: where it rolls while LOOSE.
var loose_direction: Vector3 = Vector3.ZERO
var loose_speed: float = 0.0
## The string's length factor on top of Spagat aus Hanf (Doppelportion's shorter second string).
var rest_mult: float = 1.0
## Host: simulated with physics; client: follows apply_remote().
var simulated: bool = true
var knodl_mass: float = 0.0
var radius: float = 0.5
var state: State = State.ATTACHED
## The Spagat's length factor (Spagat aus Hanf); also reels in faster by the same factor.
var string_mult: float = 1.0
## Host: a push on the Knödl in m/s^2 (Grant modifier Föhn).
var wind: Vector3 = Vector3.ZERO
## Host, from its player's items: damage per second to everything stuck to it (Bröselbutter), and
## extra contact damage rolling downhill (Bergab-Gesetz, +100 % per copy).
var spikes: float = 0.0
var slope_bonus: float = 0.0
## Rodel (1.4 item): on the string, rolling downhill pushes it on and lets it go this much faster.
var rodel: float = 0.0
## "Knödl folgt brav" (1.4 setting, host): on the string it rolls toward this point (Brösel), INF = off.
var follow_target: Vector3 = Vector3.INF
## Seconds until Schupfn works again.
var cooldown: float = 0.0
## A Serviettenknödl's rolling direction (flat, either way along it; KnodlSortData.turn_rate).
var heading: Vector3 = Vector3.FORWARD
## Its holder's extra contact damage (Cousine Mitzi's Trab), set by RunWorld every frame.
var damage_bonus: float = 0.0
## Run-Abrechnung: its damage source id (EnemyManager.source), host.
var damage_source: int = -1
## Stats for tests and the balance log.
var throws: int = 0
var crushed: int = 0
var hits: int = 0
var auto_returns: int = 0

var _shape: SphereShape3D
var _applied_radius: float = -1.0
var _visual: MeshInstance3D
var _material: ShaderMaterial
var _wobble: float = 0.0
var _stuck_timer: float = 0.0
var _reel_timer: float = 0.0
var _shed_pending: float = 0.0
## Riesenknödl der Apokalypse: the radius times this (past the usual cap), and no mass is ever lost
## (a cash-in still empties it: set_size_rule clears keeps_mass for that moment).
var size_mult: float = 1.0
var keeps_mass: bool = false
var _remote_position: Vector3 = Vector3.ZERO
var _remote_rotation: Quaternion = Quaternion.IDENTITY
var _speed: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
## A Serviettenknödl's roll around its own axis, for the look.
var _spin: float = 0.0


func setup(p_owner: int, p_balance: BalanceData, p_sort: KnodlSortData, p_holder: Player, p_simulated: bool) -> void:
	owner_peer = p_owner
	balance = p_balance
	sort = p_sort
	holder = p_holder
	simulated = p_simulated
	name = "Knodl_%d" % owner_peer
	_shape = SphereShape3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = _shape
	add_child(collision)
	_visual = MeshInstance3D.new()
	_visual.name = "Dough"
	_visual.mesh = MeshFactory.knodl()
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/knodl.gdshader")
	_material.set_shader_parameter(&"dough_color", sort.color)
	_material.set_shader_parameter(&"crumb_color", sort.crumb_color)
	_material.set_shader_parameter(&"fleck_color", sort.fleck_color)
	_visual.material_override = _material
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_visual)
	var spagat := Spagat.new()
	spagat.name = "Spagat"
	spagat.knodl = self
	add_child(spagat)
	var material := PhysicsMaterial.new()
	material.friction = balance.knodl_friction
	material.bounce = sort.bounce
	physics_material_override = material
	linear_damp = balance.knodl_linear_damp
	angular_damp = balance.knodl_angular_damp
	continuous_cd = true
	can_sleep = false
	collision_layer = LAYER_KNODL
	collision_mask = MapBuilder.LAYER_WORLD
	if not simulated:
		# A client's copy is smoothed in _process; physics interpolation would fight that.
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		collision_layer = 0
		collision_mask = 0
	set_knodl_mass(balance.knodl_start_mass * sort.start_mass_mult)


## Puts the Knödl down next to its holder (start of a run, respawn, stuck for good).
func place_at(where: Vector3) -> void:
	global_position = where
	_remote_position = where
	_last_position = where
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	state = State.ATTACHED
	_stuck_timer = 0.0
	reset_physics_interpolation()


func set_knodl_mass(value: float) -> void:
	if keeps_mass and value < knodl_mass:
		value = knodl_mass
	knodl_mass = maxf(value, 0.0)
	radius = Formulas.knodl_radius(knodl_mass, balance) * size_mult
	# Resizing the Jolt shape for every crumb would be wasted work; a few millimetres do not show.
	if absf(radius - _applied_radius) < 0.002:
		return
	_applied_radius = radius
	_shape.radius = radius
	_visual.scale = Vector3(radius, radius * sort.flatness, radius)
	# Crumbs keep their real size as the Knödl grows.
	_material.set_shader_parameter(&"crumb_scale", CRUMBS_PER_METRE * radius)
	mass = 1.0 + knodl_mass * 0.02


## The Riesenknödl rule (every role, from the build): twice the size, never shrinks.
func set_size_rule(mult: float, keep: bool) -> void:
	keeps_mass = keep
	if mult != size_mult:
		size_mult = mult
		set_knodl_mass(knodl_mass)


## Starts over at `value` (a cash-in, a respawn): the only way a Riesenknödl gets smaller.
func reset_knodl_mass(value: float) -> void:
	var keep: bool = keeps_mass
	keeps_mass = false
	set_knodl_mass(value)
	keeps_mass = keep


## Host: Brösel eaten; makes it wobble.
func add_knodl_mass(amount: float) -> void:
	if amount <= 0.0:
		return
	set_knodl_mass(knodl_mass + amount)
	_wobble = minf(_wobble + 0.25, 0.7)


func rest_length() -> float:
	return balance.knodl_rest_length * string_mult * rest_mult


func max_length() -> float:
	return balance.knodl_max_length * string_mult * rest_mult


## Host, co-op: hides it inside its merge partner (or brings it back out next to it).
func set_merged_away(on: bool, where: Vector3 = Vector3.ZERO) -> void:
	merged_away = on
	visible = not on
	if simulated:
		freeze = on
		collision_layer = 0 if on else LAYER_KNODL
		collision_mask = 0 if on else MapBuilder.LAYER_WORLD
	if not on:
		place_at(where)


## Host: tears it off its string and sends it rolling (Familienstreit).
func set_loose(direction: Vector3, speed: float) -> void:
	direction.y = 0.0
	loose_direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD
	loose_speed = speed
	state = State.LOOSE
	pass_target = 0
	_stuck_timer = 0.0


## Host: back on the string (a teammate caught the loose Knödl, or its time ran out).
func reel_home() -> void:
	if state == State.LOOSE or state == State.THROWN:
		_start_reel()


## Host: Bröselfresser ate `amount` mass. `spill` of it falls off as loose Brösel (take_shed()),
## the rest is gone.
func bite(amount: float, spill: float) -> void:
	if amount <= 0.0 or keeps_mass:
		return
	amount = minf(amount, knodl_mass)
	set_knodl_mass(knodl_mass - amount * (1.0 - spill))
	_shed_pending += amount * spill
	_wobble = minf(_wobble + 0.15, 0.7)


## Host: the Schupfn button. Throws when attached and ready, reels in when thrown.
## Returns true when something happened.
func schupfn(direction: Vector3) -> bool:
	match state:
		State.ATTACHED:
			if cooldown > 0.0:
				return false
			direction.y = 0.0
			if direction.length_squared() < 0.0001:
				direction = holder.facing_direction()
			direction = direction.normalized()
			var carry: Vector3 = holder.motion_velocity
			carry.y = 0.0
			linear_velocity = direction * balance.knodl_throw_speed * sort.throw_distance_mult + carry * 0.5 \
					+ Vector3.UP * balance.knodl_throw_lift
			state = State.THROWN
			cooldown = full_cooldown()
			_stuck_timer = 0.0
			throw_age = 0.0
			pass_target = 0
			throws += 1
			return true
		State.THROWN:
			_start_reel()
			return true
	return false


## Host: mass the Knödl shed since the last call, in whole units, for BroselField; 0 until a chunk
## of about 2 % of its mass has come together (a few big crumbs, not a flood of tiny ones). The
## caller drops it as Brösel and takes it off the Knödl.
func take_shed() -> int:
	if _shed_pending < maxf(1.0, knodl_mass * 0.02):
		return 0
	var whole: int = int(_shed_pending)
	_shed_pending -= whole
	return whole


## Host: hurts and pushes every enemy it touches (a Kaspressknödl cuts through them, a
## Grammelknödl's trail slows them). Returns how many it killed.
func crush(enemies: EnemyManager, delta: float = 0.0) -> int:
	enemies.source = damage_source
	var centre: Vector3 = global_position
	var speed: float = linear_velocity.length()
	var damage: float = Formulas.knodl_contact_damage(speed, radius, balance, sort.contact_damage_mult) 			* (1.0 + damage_bonus)
	# Bergab-Gesetz: rolling downhill hits harder.
	if slope_bonus > 0.0 and speed > 1.0:
		var ahead: Vector3 = centre + linear_velocity / speed
		if enemies.ground_at(centre.x, centre.z) - enemies.ground_at(ahead.x, ahead.z) > 0.12:
			damage *= 1.0 + slope_bonus
	var grid: SpatialHash = enemies.grid
	var side: float = radius * sort.width
	var found: int = grid.query(centre.x, centre.z, side + 0.8)
	var kills: int = 0
	var bottom: float = centre.y - radius
	var top: float = centre.y + radius
	var push_dir := Vector2(linear_velocity.x, linear_velocity.z)
	push_dir = push_dir / maxf(push_dir.length(), 0.001)
	var knock: float = minf(balance.knodl_knockback * speed * radius, balance.knodl_max_knockback)
	for k: int in found:
		var j: int = grid.results[k]
		if enemies.alive[j] == 0:
			continue
		var ex: float = enemies.pos_x[j]
		var ez: float = enemies.pos_z[j]
		var dx: float = ex - centre.x
		var dz: float = ez - centre.z
		var reach: float = radius + enemies.radius[j]
		var d_sq: float = dx * dx + dz * dz
		var solid: bool = d_sq < reach * reach
		if not solid and not _in_strip(dx, dz, reach, side + enemies.radius[j]):
			continue
		var gy: float = enemies.ground_at(ex, ez)
		if bottom > gy + balance.enemy_contact_height or top < gy:
			continue
		var d: float = sqrt(d_sq)
		var away := Vector2(dx, dz) / d if d > 0.001 else push_dir
		# The Knödl is solid: nobody stands inside it (a fast Kaspressknödl goes right through).
		if solid and not (sort.pierce and speed > 3.0):
			enemies.shove(j, centre.x + away.x * reach, centre.z + away.y * reach)
		if sort.trail_slow > 0.0 and speed > 1.0:
			enemies.slow(j, 1.0 - sort.trail_slow, 1.5)
		if spikes > 0.0 and delta > 0.0 and enemies.damage(j, spikes * delta):
			kills += 1
			continue
		if damage > 0.0 and enemies.knodl_timer[j] <= 0.0:
			enemies.knodl_timer[j] = balance.knodl_hit_cooldown
			var kick: Vector2 = (away + push_dir).normalized() * knock
			hits += 1
			if enemies.damage(j, damage, kick.x, kick.y):
				kills += 1
			_wobble = minf(_wobble + 0.1, 1.0)
	crushed += kills
	enemies.source = -1
	return kills


## A Serviettenknödl's wide strip: inside the ellipse `along` deep on its heading, `across` wide.
func _in_strip(dx: float, dz: float, along: float, across: float) -> bool:
	if sort.width <= 1.0:
		return false
	var a: float = (dx * heading.x + dz * heading.z) / along
	var c: float = (dx * heading.z - dz * heading.x) / across
	return a * a + c * c < 1.0


## The full Schupfn cooldown for this sort (a Topfenknödl's is shorter).
func full_cooldown() -> float:
	return balance.knodl_cooldown * sort.cooldown_mult


## Client: the host's latest state for this Knödl.
func apply_remote(where: Vector3, rotation_q: Quaternion, new_mass: float, new_state: State, new_cooldown: float) -> void:
	if knodl_mass != new_mass:
		if new_mass > knodl_mass:
			_wobble = minf(_wobble + 0.25, 0.7)
		set_knodl_mass(new_mass)
	_remote_position = where
	_remote_rotation = rotation_q
	state = new_state
	cooldown = new_cooldown


## Where it is drawn right now (between physics ticks on the host).
func visual_position() -> Vector3:
	return get_global_transform_interpolated().origin if simulated else global_position


## Speed in m/s, on host and clients alike.
func current_speed() -> float:
	return _speed


func _process(delta: float) -> void:
	if not simulated:
		var blend: float = 1.0 - exp(-REMOTE_FOLLOW_SPEED * delta)
		global_position = global_position.lerp(_remote_position, blend)
		quaternion = quaternion.slerp(_remote_rotation, blend)
	if simulated:
		_speed = linear_velocity.length()
	else:
		_speed = lerpf(_speed, (global_position - _last_position).length() / maxf(delta, 0.0001), 0.2)
	_last_position = global_position
	if _wobble > 0.0:
		_wobble = maxf(_wobble - delta * 2.5, 0.0)
	_material.set_shader_parameter(&"wobble", _wobble)
	_material.set_shader_parameter(&"fade", _view_fade())
	if sort.turn_rate > 0.0:
		_place_roll(delta)


## A Serviettenknödl looks like a roll lying across its heading and spinning about its long axis,
## whatever the ball under it does (the body stays a sphere for Jolt).
func _place_roll(delta: float) -> void:
	var moved: Vector3 = linear_velocity if simulated else (global_position - _last_position) / maxf(delta, 0.0001)
	moved.y = 0.0
	if not simulated and moved.length() > 0.5:
		heading = _turned(heading, moved, sort.turn_rate * delta)
	_spin += moved.dot(heading) / maxf(radius, 0.1) * delta
	var look := Basis.looking_at(heading, Vector3.UP)
	_visual.global_basis = look * Basis(Vector3.RIGHT, -_spin) * Basis.from_scale(Vector3(radius * sort.width, radius, radius))


## `from` turned toward `toward` (or its back, a roll has no front) by at most `step` radians.
static func _turned(from: Vector3, toward: Vector3, step: float) -> Vector3:
	var want: Vector3 = toward.normalized()
	if want.dot(from) < 0.0:
		want = -want
	var angle: float = from.signed_angle_to(want, Vector3.UP)
	return from.rotated(Vector3.UP, clampf(angle, -step, step)).normalized()


## Dithers the Knödl away while it fills the camera or sits between the camera and its player, so
## a big Knödl trailing toward the low camera never hides the game.
func _view_fade() -> float:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or holder == null:
		return 1.0
	var eye: Vector3 = camera.global_position
	var centre: Vector3 = visual_position()
	var fade: float = clampf((eye.distance_to(centre) - radius - FADE_NEAR) / FADE_RANGE, FADE_MIN, 1.0)
	var player: Vector3 = holder.get_global_transform_interpolated().origin + Vector3(0.0, 1.0, 0.0)
	var sight: Vector3 = player - eye
	var t: float = clampf((centre - eye).dot(sight) / maxf(sight.length_squared(), 0.0001), 0.0, 1.0)
	if t < 1.0 and centre.distance_to(eye + sight * t) < radius:
		fade = minf(fade, FADE_HIDING)
	return fade


func _physics_process(delta: float) -> void:
	if not simulated or merged_away:
		return
	if cooldown > 0.0:
		cooldown = maxf(cooldown - delta, 0.0)
	if holder == null:
		return
	var anchor: Vector3 = holder.hand_position()
	var to_holder: Vector3 = anchor - global_position
	var distance: float = to_holder.length()
	var moving: float = linear_velocity.length()
	match state:
		State.LOOSE:
			# Hung up on something: it still comes back in the end (CoopRules ends the event).
			_stuck_timer = _stuck_timer + delta if moving < balance.knodl_stuck_speed else 0.0
		State.THROWN:
			throw_age += delta
			if not keeps_mass:
				_shed_pending += knodl_mass * balance.knodl_shed_per_second * delta
			_stuck_timer = _stuck_timer + delta if moving < balance.knodl_stuck_speed else 0.0
			if _stuck_timer >= balance.knodl_stuck_seconds or distance > balance.knodl_max_throw_distance:
				auto_returns += 1
				_start_reel()
		State.REELING:
			_reel_timer -= delta
			if distance <= rest_length():
				state = State.ATTACHED
			elif _reel_timer < -1.0:
				# Stuck behind something on the way back: it simply turns up next to the player.
				place_at(anchor - holder.facing_direction() * rest_length())
		State.ATTACHED:
			# Hung up behind a wall far beyond the string's length: free it after a while.
			_stuck_timer = _stuck_timer + delta if distance > max_length() + 1.5 else 0.0
			if _stuck_timer >= balance.knodl_stuck_seconds:
				auto_returns += 1
				place_at(anchor - holder.facing_direction() * rest_length())
	var ground_y: float = holder.ground_height_at(global_position)
	if global_position.y < ground_y - FALL_LIMIT:
		place_at(anchor - holder.facing_direction() * rest_length())


func _integrate_forces(body: PhysicsDirectBodyState3D) -> void:
	if not simulated or holder == null or merged_away:
		return
	var dt: float = body.step
	var v: Vector3 = body.linear_velocity
	var p: Vector3 = body.transform.origin
	var anchor: Vector3 = holder.hand_position()
	var to_holder: Vector3 = anchor - p
	var distance: float = to_holder.length()
	match state:
		State.ATTACHED:
			# A merged Riesenknödl: the second string pulls too (a clothesline between the two).
			if co_holder != null:
				var to_co: Vector3 = co_holder.hand_position() - p
				var co_distance: float = to_co.length()
				if co_distance > rest_length() and co_distance > 0.001:
					var co_dir: Vector3 = to_co / co_distance
					var co_pull: float = balance.knodl_spring * (co_distance - rest_length()) 							- balance.knodl_spring_damping * (v - co_holder.motion_velocity).dot(co_dir)
					if co_pull > 0.0:
						v += co_dir * co_pull * dt
			if distance > rest_length() and distance > 0.001:
				var dir: Vector3 = to_holder / distance
				var relative: Vector3 = v - holder.motion_velocity
				# A damped spring along the string; a string can pull, never push.
				var pull: float = balance.knodl_spring * (distance - rest_length()) \
						- balance.knodl_spring_damping * relative.dot(dir)
				if pull > 0.0:
					v += dir * pull * dt
				if distance > max_length():
					# Never longer than the string: back onto it, and no more moving away.
					p = anchor - dir * max_length()
					body.transform = Transform3D(body.transform.basis, p)
					var outward: float = (v - holder.motion_velocity).dot(dir)
					if outward < 0.0:
						v -= dir * outward
		State.REELING:
			var remaining: float = maxf(_reel_timer, 0.2)
			var wanted: Vector3 = to_holder / remaining
			v = v.lerp(wanted, minf(10.0 * dt, 1.0))
		State.LOOSE:
			var roll: Vector3 = loose_direction * loose_speed
			v.x = lerpf(v.x, roll.x, minf(3.0 * dt, 1.0))
			v.z = lerpf(v.z, roll.z, minf(3.0 * dt, 1.0))
	if state != State.REELING:
		v += wind * dt
		if sort.turn_rate > 0.0:
			# A roll: it turns slowly toward where it is pulled and hardly slides sideways.
			var flat := Vector3(v.x, 0.0, v.z)
			if flat.length() > 0.5:
				heading = _turned(heading, flat, sort.turn_rate * dt)
			var sideways: Vector3 = flat - heading * flat.dot(heading)
			v -= sideways * (1.0 - exp(-sort.lateral_grip * dt))
	var max_speed: float = balance.knodl_max_speed * sort.roll_speed_mult
	if follow_target.is_finite() and state == State.ATTACHED:
		var toward := Vector3(follow_target.x - p.x, 0.0, follow_target.z - p.z)
		if toward.length() > 0.3:
			v += toward.normalized() * balance.knodl_follow_pull * dt
	if rodel > 0.0 and state == State.ATTACHED and v.y < -0.3:
		var flat_v := Vector3(v.x, 0.0, v.z)
		if flat_v.length() > 0.5:
			v += flat_v.normalized() * balance.rodel_push * rodel * dt
		max_speed *= 1.0 + rodel
	if v.length() > max_speed:
		v = v.normalized() * max_speed
	body.linear_velocity = v


func _start_reel() -> void:
	state = State.REELING
	_reel_timer = balance.knodl_reel_time * sort.reel_time_mult / maxf(string_mult, 0.5)
	_stuck_timer = 0.0
