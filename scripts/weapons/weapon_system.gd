class_name WeaponSystem
extends RefCounted
## Fires every player's weapons on the host (auto-attack: GAME-DESIGN.md pillar 1) and applies the
## damage through EnemyManager's grid. Patterns: ARC (melee arc or cone in facing direction, a second
## one behind from amount 2), PROJECTILE (piercing shots in facing direction, boomerangs come back),
## RING (a shockwave all around), AURA (hurts everything close at every tick), ORBIT (pieces circling
## the player), DROP (impacts on enemies nearby), MINE (blasts where the player stood, later) and
## CHAIN (a hit jumping from enemy to enemy). Hits can burn and slow (WeaponData "On hit").
## Every timed attack bumps the weapon's fire counter, which every machine turns into the effect;
## orbit pieces need none (everyone places them from the run time).

## Below the player's hand: where shots start and orbit pieces fly.
const SHOT_HEIGHT: float = 1.0


## Host: one player's weapons for this frame.
static func update(build: PlayerBuild, player: Player, enemies: EnemyManager, projectiles: ProjectilePool,
		run_time: float, delta: float, rng: RandomNumberGenerator, balance: BalanceData) -> void:
	for owned: PlayerBuild.OwnedWeapon in build.weapons:
		var weapon: WeaponData = owned.data
		owned.impacts.clear()
		if weapon.pattern == WeaponData.Pattern.MINE:
			_tick_mines(owned, enemies, delta, Formulas.weapon_area(weapon, owned.mods, build.stat(&"area")),
					Formulas.weapon_damage(weapon, owned.mods, build.stat(&"damage")), build.stat(&"duration"))
		var area: float = Formulas.weapon_area(weapon, owned.mods, build.stat(&"area"))
		var damage: float = Formulas.weapon_damage(weapon, owned.mods, build.stat(&"damage"))
		var crit: float = Formulas.weapon_crit(weapon, owned.mods, build.stat(&"crit"))
		if weapon.pattern == WeaponData.Pattern.ORBIT:
			orbit_hit(owned, player.global_position, enemies, run_time, area, damage, crit, build.stat(&"move_speed"), rng)
			continue
		owned.timer -= delta
		if owned.timer > 0.0:
			continue
		var cooldown: float = Formulas.weapon_cooldown(weapon, owned.mods, build.stat(&"cooldown"), balance, build.stat(&"rate"))
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
				fire_shots(weapon, origin, facing, amount, area, hit_damage, projectiles, build.stat(&"duration"))
			WeaponData.Pattern.RING, WeaponData.Pattern.AURA:
				ring_hit(weapon, origin, enemies, hit_damage, weapon.reach * area)
			WeaponData.Pattern.DROP:
				drop_hit(owned, origin, enemies, hit_damage, area, amount, rng, build.stat(&"duration"))
			WeaponData.Pattern.MINE:
				for k: int in amount:
					var angle: float = TAU * k / amount + rng.randf() * 0.5
					var spread: float = 0.0 if amount == 1 else 1.2 * area
					owned.mines.append(Vector3(origin.x + cos(angle) * spread, origin.z + sin(angle) * spread, weapon.mine_delay))
			WeaponData.Pattern.CHAIN:
				chain_hit(owned, origin, enemies, hit_damage, area, amount, build.stat(&"duration"))
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
		apply_hit(weapon, enemies, j, damage, to.x * weapon.knockback, to.y * weapon.knockback)
		hit += 1
	return hit


## One hit with the weapon's statuses (burn, slow) on top. `duration` is the duration stat.
static func apply_hit(weapon: WeaponData, enemies: EnemyManager, j: int, damage: float, kx: float, kz: float,
		duration: float = 0.0) -> void:
	if enemies.damage(j, damage, kx, kz):
		return
	if weapon.burn_share > 0.0:
		enemies.burn(j, damage * weapon.burn_share, weapon.burn_seconds * (1.0 + duration))
	if weapon.slow_seconds > 0.0:
		enemies.slow(j, weapon.slow_mult, weapon.slow_seconds * (1.0 + duration))


## Every enemy within `radius` of (x, z): its slot, as a list (the grid's results get reused).
static func enemies_near(enemies: EnemyManager, x: float, z: float, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var found: int = enemies.grid.query(x, z, radius + 0.8)
	for k: int in found:
		var j: int = enemies.grid.results[k]
		if enemies.alive[j] == 0:
			continue
		var dx: float = enemies.pos_x[j] - x
		var dz: float = enemies.pos_z[j] - z
		var reach: float = radius + enemies.radius[j]
		if dx * dx + dz * dz <= reach * reach:
			out.append(j)
	return out


## Blasts at (x, z): everything in the radius is hit and pushed outward.
static func blast(weapon: WeaponData, enemies: EnemyManager, x: float, z: float, radius: float, damage: float,
		duration: float) -> void:
	for j: int in enemies_near(enemies, x, z, radius):
		var away := Vector2(enemies.pos_x[j] - x, enemies.pos_z[j] - z)
		away = away.normalized() if away.length() > 0.01 else Vector2.RIGHT
		apply_hit(weapon, enemies, j, damage, away.x * weapon.knockback, away.y * weapon.knockback, duration)


## DROP: `amount` impacts on random enemies within reach (stamps, hail, snow globes).
static func drop_hit(owned: PlayerBuild.OwnedWeapon, origin: Vector3, enemies: EnemyManager, damage: float, area: float,
		amount: int, rng: RandomNumberGenerator, duration: float) -> void:
	var weapon: WeaponData = owned.data
	var near: PackedInt32Array = enemies_near(enemies, origin.x, origin.z, weapon.reach * area)
	for k: int in amount:
		if near.is_empty():
			return
		var pick: int = rng.randi_range(0, near.size() - 1)
		var j: int = near[pick]
		near.remove_at(pick)
		var x: float = enemies.pos_x[j]
		var z: float = enemies.pos_z[j]
		owned.impacts.append(Vector2(x, z))
		blast(weapon, enemies, x, z, weapon.impact_radius * area, damage, duration)


## MINE: mines count down and go off where they were laid.
static func _tick_mines(owned: PlayerBuild.OwnedWeapon, enemies: EnemyManager, delta: float, area: float, damage: float,
		duration: float) -> void:
	var k: int = 0
	while k < owned.mines.size():
		var mine: Vector3 = owned.mines[k]
		mine.z -= delta
		if mine.z > 0.0:
			owned.mines[k] = mine
			k += 1
			continue
		owned.impacts.append(Vector2(mine.x, mine.y))
		blast(owned.data, enemies, mine.x, mine.y, owned.data.impact_radius * area, damage, duration)
		owned.mines.remove_at(k)


## CHAIN: the nearest enemy within reach, then the nearest one not hit yet within chain_range of the
## last, `amount` times; each jump hits a little softer.
static func chain_hit(owned: PlayerBuild.OwnedWeapon, origin: Vector3, enemies: EnemyManager, damage: float, area: float,
		amount: int, duration: float) -> void:
	var weapon: WeaponData = owned.data
	var hit: Dictionary[int, bool] = {}
	var x: float = origin.x
	var z: float = origin.z
	var reach: float = weapon.reach * area
	owned.impacts.append(Vector2(x, z))
	for k: int in amount:
		var best: int = -1
		var best_sq: float = INF
		for j: int in enemies_near(enemies, x, z, reach):
			if hit.has(j):
				continue
			var d_sq: float = (enemies.pos_x[j] - x) * (enemies.pos_x[j] - x) + (enemies.pos_z[j] - z) * (enemies.pos_z[j] - z)
			if d_sq < best_sq:
				best_sq = d_sq
				best = j
		if best < 0:
			return
		hit[best] = true
		var dir := Vector2(enemies.pos_x[best] - x, enemies.pos_z[best] - z).normalized()
		x = enemies.pos_x[best]
		z = enemies.pos_z[best]
		owned.impacts.append(Vector2(x, z))
		apply_hit(weapon, enemies, best, damage * pow(0.85, k), dir.x * weapon.knockback, dir.y * weapon.knockback, duration)
		reach = weapon.chain_range * area


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
		apply_hit(weapon, enemies, j, damage, away.x * weapon.knockback, away.y * weapon.knockback)
		hit += 1
	return hit


## `amount` shots fanned out around the facing direction.
static func fire_shots(weapon: WeaponData, origin: Vector3, facing: Vector3, amount: int, area: float,
		damage: float, projectiles: ProjectilePool, duration: float = 0.0) -> void:
	if projectiles == null:
		return
	var base: float = atan2(facing.x, facing.z)
	var spread: float = deg_to_rad(weapon.spread_degrees)
	for k: int in amount:
		var angle: float = base + (k - (amount - 1) * 0.5) * spread
		var vx: float = sin(angle) * weapon.projectile_speed
		var vz: float = cos(angle) * weapon.projectile_speed
		projectiles.fire_shot(origin.x, origin.z, vx, vz, weapon.projectile_lifetime * (1.0 + duration), damage,
				weapon.projectile_radius * area, weapon.pierce, weapon.knockback, weapon.boomerang, weapon)


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
			apply_hit(weapon, enemies, j, amount, away.x * weapon.knockback, away.y * weapon.knockback)
			hit += 1
	return hit
