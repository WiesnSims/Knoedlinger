class_name PlayerBuild
extends RefCounted
## One player's build in a run: their weapons and passives with levels, the stats those add up to,
## gold, and what is left of their rerolls and banishes. The host owns it and changes it (cards,
## chests); clients get a mirror through the world state, enough to compute the same stats (their
## own movement, the look of everyone's weapons).

## Every stat a passive can raise. Fractions are percentages (0.1 = +10 %).
const STATS: Array[StringName] = [
	&"damage", &"area", &"cooldown", &"move_speed", &"max_hp", &"regen", &"armor", &"crit", &"pickup",
	&"jump_height", &"extra_jumps", &"string_length", &"luck", &"gold", &"knodl_guard",
]
## Counted per level, never scaled by rarity (half a jump makes no sense).
const COUNT_STATS: Array[StringName] = [&"extra_jumps", &"knodl_guard"]


class OwnedWeapon:
	extends RefCounted
	var index: int = 0
	var data: WeaponData
	var level: int = 1
	## Sum of the rarity bonuses of its levels (= level when every card was Gewöhnlich).
	var bonus: float = 1.0
	## Counts attacks (wraps at 256); every machine plays the effect when it changes.
	var fires: int = 0
	# Host only.
	var timer: float = 0.0
	## Continuous weapons: per enemy slot, the run time from which it may be hit again.
	var hit_until: PackedFloat32Array = PackedFloat32Array()


class OwnedPassive:
	extends RefCounted
	var index: int = 0
	var data: PassiveData
	var level: int = 1
	var bonus: float = 1.0


var catalog: UpgradeCatalog
var weapons: Array[OwnedWeapon] = []
## Passives and Knödl upgrades.
var passives: Array[OwnedPassive] = []
var stats: Dictionary[StringName, float] = {}
var gold: int = 0
var rerolls: int = 0
var banishes: int = 0
## Host: item keys (Card.item_key()) this player banished for the run.
var banished: Dictionary[int, bool] = {}


func _init(p_catalog: UpgradeCatalog, balance: BalanceData = null) -> void:
	catalog = p_catalog
	if balance != null:
		rerolls = balance.rerolls_per_run
		banishes = balance.banishes_per_run
	recompute()


func stat(key: StringName) -> float:
	return stats.get(key, 0.0)


func weapon_slots_used() -> int:
	return weapons.size()


func passive_slots_used() -> int:
	var used: int = 0
	for owned: OwnedPassive in passives:
		if owned.data.kind == PassiveData.Kind.PASSIVE:
			used += 1
	return used


func owned_weapon(index: int) -> OwnedWeapon:
	for owned: OwnedWeapon in weapons:
		if owned.index == index:
			return owned
	return null


func owned_passive(index: int) -> OwnedPassive:
	for owned: OwnedPassive in passives:
		if owned.index == index:
			return owned
	return null


## The start weapon of the character, at level 1.
func add_start_weapon(weapon: WeaponData) -> void:
	var index: int = catalog.weapons.find(weapon)
	if index >= 0 and owned_weapon(index) == null:
		apply(Card.new(Card.Kind.WEAPON, index, Card.Rarity.COMMON, 1), null)


## Weapons that could evolve now: [slot in `weapons`, catalog index of the evolution].
func evolutions_ready() -> Array[Vector2i]:
	var ready: Array[Vector2i] = []
	for slot: int in weapons.size():
		var owned: OwnedWeapon = weapons[slot]
		var data: WeaponData = owned.data
		if data.evolution == null or data.evolves_with == null or owned.level < data.max_level:
			continue
		var partner: int = catalog.passives.find(data.evolves_with)
		var evolution: int = catalog.weapons.find(data.evolution)
		if partner >= 0 and evolution >= 0 and owned_passive(partner) != null:
			ready.append(Vector2i(slot, evolution))
	return ready


## Host: takes a card. Returns HP to heal (HEAL cards), else 0.
func apply(card: Card, balance: BalanceData) -> float:
	var bonus: float = balance.rarity_bonus[clampi(card.rarity, 0, balance.rarity_bonus.size() - 1)] if balance != null else 1.0
	match card.kind:
		Card.Kind.WEAPON:
			var owned: OwnedWeapon = owned_weapon(card.index)
			if owned == null:
				owned = OwnedWeapon.new()
				owned.index = card.index
				owned.data = catalog.weapons[card.index]
				owned.level = 1
				owned.bonus = bonus
				weapons.append(owned)
			elif owned.level < owned.data.max_level:
				owned.level += 1
				owned.bonus += bonus
		Card.Kind.PASSIVE:
			var owned: OwnedPassive = owned_passive(card.index)
			if owned == null:
				owned = OwnedPassive.new()
				owned.index = card.index
				owned.data = catalog.passives[card.index]
				owned.level = 1
				owned.bonus = bonus
				passives.append(owned)
			elif owned.level < owned.data.max_level:
				owned.level += 1
				owned.bonus += bonus
		Card.Kind.EVOLUTION:
			var evolved: WeaponData = catalog.weapons[card.index]
			for owned: OwnedWeapon in weapons:
				if owned.data.evolution == evolved:
					# Same slot, same fire counter: the base weapon turns into its evolution.
					owned.index = card.index
					owned.data = evolved
					owned.level = 1
					owned.bonus = 1.0
					owned.timer = 0.0
					owned.hit_until = PackedFloat32Array()
					break
		Card.Kind.GOLD:
			add_gold(balance.fallback_gold if balance != null else 0)
		Card.Kind.HEAL:
			recompute()
			return balance.fallback_heal if balance != null else 0.0
	recompute()
	return 0.0


## Gold with the gold bonus.
func add_gold(amount: int) -> void:
	gold += roundi(amount * (1.0 + stat(&"gold")))


func recompute() -> void:
	stats.clear()
	for key: StringName in STATS:
		stats[key] = 0.0
	for owned: OwnedPassive in passives:
		for key: StringName in owned.data.stats:
			var times: float = float(owned.level) if COUNT_STATS.has(key) else owned.bonus
			stats[key] = stats.get(key, 0.0) + owned.data.stats[key] * times


## Client: takes the host's view of this build (from the world state). `weapon_rows` holds
## (catalog index, level, bonus * 100, fire counter) per weapon, `passive_rows` (index, level,
## bonus * 100) per passive. Returns false for indices this catalog does not know.
func mirror(weapon_rows: PackedInt32Array, passive_rows: PackedInt32Array, p_gold: int, p_rerolls: int, p_banishes: int) -> bool:
	gold = p_gold
	rerolls = p_rerolls
	banishes = p_banishes
	var count: int = weapon_rows.size() / 4
	if weapons.size() != count:
		weapons.resize(count)
	for k: int in count:
		var index: int = weapon_rows[k * 4]
		if index < 0 or index >= catalog.weapons.size():
			return false
		if weapons[k] == null or weapons[k].index != index:
			weapons[k] = OwnedWeapon.new()
			weapons[k].index = index
			weapons[k].data = catalog.weapons[index]
		weapons[k].level = weapon_rows[k * 4 + 1]
		weapons[k].bonus = weapon_rows[k * 4 + 2] / 100.0
		weapons[k].fires = weapon_rows[k * 4 + 3]
	var passive_count: int = passive_rows.size() / 3
	var changed: bool = passives.size() != passive_count
	if changed:
		passives.resize(passive_count)
	for k: int in passive_count:
		var index: int = passive_rows[k * 3]
		if index < 0 or index >= catalog.passives.size():
			return false
		if passives[k] == null or passives[k].index != index:
			passives[k] = OwnedPassive.new()
			passives[k].index = index
			passives[k].data = catalog.passives[index]
			changed = true
		var level: int = passive_rows[k * 3 + 1]
		var bonus: float = passive_rows[k * 3 + 2] / 100.0
		if passives[k].level != level or not is_equal_approx(passives[k].bonus, bonus):
			changed = true
		passives[k].level = level
		passives[k].bonus = bonus
	if changed:
		recompute()
	return true


## The rows mirror() takes, for the world state.
func weapon_rows() -> PackedInt32Array:
	var rows := PackedInt32Array()
	for owned: OwnedWeapon in weapons:
		rows.append_array([owned.index, owned.level, roundi(owned.bonus * 100.0), owned.fires & 0xFF])
	return rows


func passive_rows() -> PackedInt32Array:
	var rows := PackedInt32Array()
	for owned: OwnedPassive in passives:
		rows.append_array([owned.index, owned.level, roundi(owned.bonus * 100.0)])
	return rows
