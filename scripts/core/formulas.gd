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


## Splits an XP amount into Brösel sizes, largest first (balance.brosel_values is ascending).
static func split_into_brosel(xp: int, balance: BalanceData) -> PackedInt32Array:
	var pieces := PackedInt32Array()
	var values: PackedInt32Array = balance.brosel_values
	for k: int in range(values.size() - 1, -1, -1):
		while xp >= values[k]:
			pieces.append(values[k])
			xp -= values[k]
	return pieces
