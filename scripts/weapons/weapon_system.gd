class_name WeaponSystem
extends RefCounted
## Fires every player's weapons on the host (auto-attack: GAME-DESIGN.md pillar 1) and applies the
## damage through EnemyManager's grid. Patterns: ARC (melee arc in facing direction, a second one
## behind from amount 2), PROJECTILE (piercing shots in facing direction), RING (a shockwave all
## around), AURA (hurts everything close at every tick) and ORBIT (pieces circling the player).
## Every timed attack bumps the weapon's fire counter, which every machine turns into the effect;
## orbit pieces need none (everyone places them from the run time).

## Below the player's hand: where shots start and orbit pieces fly.
const SHOT_HEIGHT: float = 1.0


## Host: one player's weapons for this frame.
static func update(build: PlayerBuild, player: Player, enemies: EnemyManager, projectiles: ProjectilePool,
		run_time: float, delta: float, rng: RandomNumberGenerator, balance: BalanceData) -> void:
	for owned: PlayerBuild.OwnedWeapon in build.weapons:
		var weapon: WeaponData = owned.data
		var area: float = Formulas.weapon_area(weapon, owned.mods, build.stat(&"area"))
		var damage: float = Formulas.weapon_damage(weapon, owned.mods, build.stat(&"damage"))
		var crit: float = Formulas.weapon_crit(weapon, owned.mods, build.stat(&"crit"))
		if weapon.pattern == WeaponData.Pattern.ORBIT:
			orbit_hit(owned, player.global_position, enemies, run_time, area, damage, crit, build.stat(&"move_speed"), rng)
			continue
		owned.timer -= delta
		if owned.timer > 0.0:
			continue
		var cooldown: float = Formulas.weapon_cooldown(weapon, owned.mods, build.stat(&"cooldown"), balance)
		owned.timer += cooldown
		if owned.timer < 0.0:
			owned.timer = cooldown
		var hit_damage: float = damage * (weapon.crit_multiplier if rng.randf() < crit else 1.0)
		var origin: Vector3 = player.global_position
		var facing: Vector3 = player.facing_direction()
		var amount: int = Formulas.weapon_amount(weapon, owned.mods)
		match weapon.pattern:
			WeaponData.Pattern.ARC:
				arc_hit(weapon, origin, facing, enemies, hit_damage, area)
				if amount >= 2:
					arc_hit(weapon, origin, -facing, enemies, hit_damage, area)
			WeaponData.Pattern.PROJECTILE:
				fire_shots(weapon, origin, facing, amount, area, hit_damage, projectiles)
			WeaponData.Pattern.RING, WeaponData.Pattern.AURA:
				ring_hit(weapon, origin, enemies, hit_damage, weapon.reach * area)
		owned.fires = (owned.fires + 1) & 0xFF


## Damages every enemy inside the arc in front of `origin`. Returns how many were hit.
static func arc_hit(weapon: WeaponData, origin: Vector3, facing: Vector3, enemies: EnemyManager,
		damage: float = -1.0, area: float = 1.0) -> int:
	if damage < 0.0:
		damage = weapon.damage
	var reach_base: float = weapon.reach * area
	var grid: SpatialHash = enemies.grid
	var found: int = grid.query(origin.x, origin.z, reach_base + 0.8)
	var half_arc_cos: float = cos(deg_to_rad(weapon.arc_degrees) * 0.5)
	var forward := Vector2(facing.x, facing.z).normalized()
	var hit: int = 0
	for k: int in found:
		var j: int = grid.results[k]
		if enemies.alive[j] == 0:
			continue
		var dx: float = enemies.pos_x[j] - origin.x
		var dz: float = enemies.pos_z[j] - origin.z
		var reach: float = reach_base + enemies.radius[j]
		var d_sq: float = dx * dx + dz * dz
		if d_sq > reach * reach:
			continue
		var d: float = sqrt(d_sq)
		var to := Vector2(dx, dz) / d if d > 0.001 else forward
		# Enemies right at the player's feet count as in front.
		if d > enemies.radius[j] + 0.3 and to.dot(forward) < half_arc_cos:
			continue
		if absf(enemies.ground_at(enemies.pos_x[j], enemies.pos_z[j]) - origin.y) > weapon.height_reach:
			continue
		enemies.damage(j, damage, to.x * weapon.knockback, to.y * weapon.knockback)
		hit += 1
	return hit


## Damages every enemy within `radius` of `origin`, pushing them outward. Returns how many.
static func ring_hit(weapon: WeaponData, origin: Vector3, enemies: EnemyManager, damage: float, radius: float) -> int:
	var grid: SpatialHash = enemies.grid
	var found: int = grid.query(origin.x, origin.z, radius + 0.8)
	var hit: int = 0
	for k: int in found:
		var j: int = grid.results[k]
		if enemies.alive[j] == 0:
			continue
		var dx: float = enemies.pos_x[j] - origin.x
		var dz: float = enemies.pos_z[j] - origin.z
		var reach: float = radius + enemies.radius[j]
		var d_sq: float = dx * dx + dz * dz
		if d_sq > reach * reach:
			continue
		if absf(enemies.ground_at(enemies.pos_x[j], enemies.pos_z[j]) - origin.y) > weapon.height_reach:
			continue
		var d: float = sqrt(d_sq)
		var away := Vector2(dx, dz) / d if d > 0.001 else Vector2.RIGHT
		enemies.damage(j, damage, away.x * weapon.knockback, away.y * weapon.knockback)
		hit += 1
	return hit


## `amount` shots fanned out around the facing direction.
static func fire_shots(weapon: WeaponData, origin: Vector3, facing: Vector3, amount: int, area: float,
		damage: float, projectiles: ProjectilePool) -> void:
	if projectiles == null:
		return
	var base: float = atan2(facing.x, facing.z)
	var spread: float = deg_to_rad(weapon.spread_degrees)
	for k: int in amount:
		var angle: float = base + (k - (amount - 1) * 0.5) * spread
		var vx: float = sin(angle) * weapon.projectile_speed
		var vz: float = cos(angle) * weapon.projectile_speed
		projectiles.fire_shot(origin.x, origin.z, vx, vz, weapon.projectile_lifetime, damage,
				weapon.projectile_radius * area, weapon.pierce, weapon.knockback)


## The orbiting pieces hit what they touch; each enemy at most every hit_interval per weapon.
static func orbit_hit(owned: PlayerBuild.OwnedWeapon, origin: Vector3, enemies: EnemyManager, run_time: float,
		area: float, damage: float, crit: float, move_speed: float, rng: RandomNumberGenerator) -> int:
	var weapon: WeaponData = owned.data
	if owned.hit_until.size() != enemies.capacity:
		owned.hit_until.resize(enemies.capacity)
		owned.hit_until.fill(0.0)
	var count: int = Formulas.weapon_amount(weapon, owned.mods)
	var piece_radius: float = weapon.projectile_radius * area
	var grid: SpatialHash = enemies.grid
	var hit: int = 0
	for k: int in count:
		var offset: Vector2 = Formulas.orbit_offset(weapon, k, count, run_time, area, move_speed)
		var px: float = origin.x + offset.x
		var pz: float = origin.z + offset.y
		var found: int = grid.query(px, pz, piece_radius + 0.8)
		for f: int in found:
			var j: int = grid.results[f]
			if enemies.alive[j] == 0 or owned.hit_until[j] > run_time:
				continue
			var dx: float = enemies.pos_x[j] - px
			var dz: float = enemies.pos_z[j] - pz
			var reach: float = piece_radius + enemies.radius[j]
			if dx * dx + dz * dz > reach * reach:
				continue
			if absf(enemies.ground_at(enemies.pos_x[j], enemies.pos_z[j]) - origin.y) > weapon.height_reach:
				continue
			owned.hit_until[j] = run_time + weapon.hit_interval
			var away := Vector2(enemies.pos_x[j] - origin.x, enemies.pos_z[j] - origin.z).normalized()
			var amount: float = damage * (weapon.crit_multiplier if rng.randf() < crit else 1.0)
			enemies.damage(j, amount, away.x * weapon.knockback, away.y * weapon.knockback)
			hit += 1
	return hit
