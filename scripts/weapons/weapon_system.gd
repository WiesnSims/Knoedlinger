class_name WeaponSystem
extends RefCounted
## Fires every player's weapons on the host (auto-attack: GAME-DESIGN.md pillar 1) and applies the
## damage through EnemyManager's grid. M1 has one pattern, the melee arc in facing direction.


## Host: counts the player's weapon down and swings when it is ready. Returns true on a swing.
static func update(state: PlayerState, weapon: WeaponData, player: Player, enemies: EnemyManager, delta: float) -> bool:
	if state.downed:
		return false
	state.weapon_timer -= delta
	if state.weapon_timer > 0.0:
		return false
	state.weapon_timer += weapon.cooldown
	if state.weapon_timer < 0.0:
		state.weapon_timer = weapon.cooldown
	match weapon.pattern:
		WeaponData.Pattern.ARC:
			arc_hit(weapon, player.global_position, player.facing_direction(), enemies)
	state.swing_count = (state.swing_count + 1) & 0xFF
	return true


## Damages every enemy inside the arc in front of `origin`. Returns how many were hit.
static func arc_hit(weapon: WeaponData, origin: Vector3, facing: Vector3, enemies: EnemyManager) -> int:
	var grid: SpatialHash = enemies.grid
	var found: int = grid.query(origin.x, origin.z, weapon.reach + 0.8)
	var half_arc_cos: float = cos(deg_to_rad(weapon.arc_degrees) * 0.5)
	var forward := Vector2(facing.x, facing.z).normalized()
	var hit: int = 0
	for k: int in found:
		var j: int = grid.results[k]
		if enemies.alive[j] == 0:
			continue
		var dx: float = enemies.pos_x[j] - origin.x
		var dz: float = enemies.pos_z[j] - origin.z
		var reach: float = weapon.reach + enemies.radius[j]
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
		enemies.damage(j, weapon.damage, to.x * weapon.knockback, to.y * weapon.knockback)
		hit += 1
	return hit
