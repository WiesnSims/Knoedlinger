class_name Formulas
extends RefCounted
## The game's formulas in one place, as pure functions of the balance numbers, so the unit tests can
## pin them down (GAME-DESIGN.md: XP curve, Knödl size, contact damage).


## Knödl radius for a mass: base * (1 + mass / scale) ^ exponent, capped.
static func knodl_radius(mass: float, balance: BalanceData) -> float:
	var grown: float = balance.knodl_base_radius * pow(1.0 + maxf(mass, 0.0) / balance.knodl_mass_scale,
			balance.knodl_radius_exponent)
	return minf(grown, balance.knodl_max_radius)


## Damage of one Knödl contact: base * speed * radius, nothing below the minimum speed.
static func knodl_contact_damage(speed: float, radius: float, balance: BalanceData, sort_mult: float = 1.0) -> float:
	if speed < balance.knodl_min_hit_speed:
		return 0.0
	return balance.knodl_contact_damage * speed * radius * sort_mult


## How much of their speed a player keeps while dragging a Knödl of this radius.
static func knodl_speed_factor(radius: float, balance: BalanceData) -> float:
	var extra: float = maxf(radius - balance.knodl_base_radius, 0.0)
	return maxf(1.0 - extra * balance.knodl_drag_per_radius, balance.knodl_min_speed_factor)


## XP needed to go from level n to n + 1.
static func xp_to_next(level: int, balance: BalanceData) -> float:
	return balance.xp_base + balance.xp_linear * level + balance.xp_quadratic * level * level


## The level reached with this much XP in total (level 1 at 0 XP).
static func level_for_xp(total_xp: float, balance: BalanceData) -> int:
	var level: int = 1
	var needed: float = xp_to_next(level, balance)
	while total_xp >= needed:
		total_xp -= needed
		level += 1
		needed = xp_to_next(level, balance)
	return level


## Progress 0..1 toward the next level.
static func level_progress(total_xp: float, balance: BalanceData) -> float:
	var level: int = 1
	var needed: float = xp_to_next(level, balance)
	while total_xp >= needed:
		total_xp -= needed
		level += 1
		needed = xp_to_next(level, balance)
	return total_xp / needed


## Damage of one weapon hit before crits: base, its damage mod (what its level cards rolled) and
## the damage stat. `mods` are PlayerBuild.OwnedWeapon.mods (indexed by PlayerBuild.WEAPON_MODS).
static func weapon_damage(weapon: WeaponData, mods: PackedFloat32Array, damage_stat: float) -> float:
	return weapon.damage * (1.0 + mods[0]) * (1.0 + damage_stat)


## Seconds between attacks: its rate mod divides it, the cooldown stat takes off a share (never
## more than 60 %), and it never drops below balance.weapon_min_cooldown.
static func weapon_cooldown(weapon: WeaponData, mods: PackedFloat32Array, cooldown_stat: float, balance: BalanceData,
		rate_stat: float = 0.0) -> float:
	return maxf(weapon.cooldown / (1.0 + maxf(mods[1], 0.0)) / (1.0 + maxf(rate_stat, 0.0)) * maxf(1.0 - cooldown_stat, 0.4),
			balance.weapon_min_cooldown)


## Size factor for reach, radius and orbit: its area mod and the area stat.
## Watschn-Baum: what a hit of `taken` HP sends back to each enemy in reach.
static func reflect_damage(taken: float, weapon: WeaponData, mods: PackedFloat32Array, damage_stat: float) -> float:
	if weapon.reflect_share <= 0.0 or weapon.damage <= 0.0:
		return 0.0
	return taken * weapon.reflect_share * weapon_damage(weapon, mods, damage_stat) / weapon.damage


static func weapon_area(weapon: WeaponData, mods: PackedFloat32Array, area_stat: float) -> float:
	return (1.0 + mods[2]) * (1.0 + area_stat)


static func weapon_crit(weapon: WeaponData, mods: PackedFloat32Array, crit_stat: float) -> float:
	return weapon.crit_chance + mods[3] + crit_stat


## Shots or pieces per attack: the base amount plus the amount mod, at most max_amount.
static func weapon_amount(weapon: WeaponData, mods: PackedFloat32Array) -> int:
	return mini(weapon.amount + roundi(mods[PlayerBuild.MOD_AMOUNT]), maxi(weapon.max_amount, weapon.amount))


## Where piece `k` of `count` of an orbiting weapon is, relative to the player (x, z). Host and
## clients use the same run time, so everyone sees the pieces where the host hits with them.
static func orbit_offset(weapon: WeaponData, k: int, count: int, run_time: float, area: float, move_speed_stat: float) -> Vector2:
	var speed: float = weapon.orbit_speed * (1.0 + weapon.orbit_speed_from_move_speed * maxf(move_speed_stat, 0.0))
	var angle: float = run_time * speed + TAU * k / maxi(count, 1)
	var radius: float = weapon.orbit_radius * area * (1.0 + weapon.orbit_wobble * sin(run_time * 1.7))
	return Vector2(cos(angle), sin(angle)) * radius


## Damage a player takes from a hit after armor (never below balance.min_hit_damage).
static func hit_damage(amount: float, armor: float, balance: BalanceData) -> float:
	if amount <= 0.0:
		return 0.0
	return maxf(amount - maxf(armor, 0.0), minf(balance.min_hit_damage, amount))


## Wirtshaus tier for a Knödl mass: -1 below S, then 0 = S, 1 = M, 2 = L, 3 = XL.
static func wirtshaus_tier(mass: float, balance: BalanceData) -> int:
	var tier: int = -1
	for k: int in balance.wirtshaus_tier_mass.size():
		if mass >= balance.wirtshaus_tier_mass[k]:
			tier = k
	return tier


## Splits an XP amount into Brösel sizes, largest first (balance.brosel_values is ascending).
static func split_into_brosel(xp: int, balance: BalanceData) -> PackedInt32Array:
	var pieces := PackedInt32Array()
	var values: PackedInt32Array = balance.brosel_values
	for k: int in range(values.size() - 1, -1, -1):
		while xp >= values[k]:
			pieces.append(values[k])
			xp -= values[k]
	return pieces
