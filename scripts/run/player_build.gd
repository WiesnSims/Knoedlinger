class_name PlayerBuild
extends RefCounted
## One player's build in a run (GAME-DESIGN.md pillar 4): weapons (2 slots, more from the meta) with
## open-ended levels whose cards each rolled one mod, stat upgrades (4 slots, open-ended levels
## scaled by rarity), items from chests (no slot limit, stacking), the stats all of that adds up to,
## gold, and what is left of their rerolls and banishes. The host owns it and changes it (cards,
## chests); clients get a mirror through the world state, enough to compute the same stats (their
## own movement, the look of everyone's weapons).

## Every stat a stat upgrade or item can raise. Fractions are percentages (0.1 = +10 %).
const STATS: Array[StringName] = [
	&"damage", &"area", &"cooldown", &"move_speed", &"max_hp", &"regen", &"armor", &"crit", &"pickup",
	&"jump_height", &"extra_jumps", &"string_length", &"luck", &"gold", &"knodl_guard",
]
## Counted per level, never scaled by rarity (half a jump makes no sense).
const COUNT_STATS: Array[StringName] = [&"extra_jumps", &"knodl_guard"]
## What a weapon level card can roll (WeaponData.level_mods); the index is the mod's id on the wire.
const WEAPON_MODS: Array[StringName] = [&"damage", &"rate", &"area", &"crit", &"amount"]
const MOD_AMOUNT: int = 4
## The item rules the game knows (ItemData.effect): a map chest is free (chance), more damage per
## chest opened, a revive per copy.
const EFFECTS: Array[StringName] = [&"free_chest", &"damage_per_chest", &"revive"]


class OwnedWeapon:
	extends RefCounted
	var index: int = 0
	var data: WeaponData
	var level: int = 1
	## Gains its level cards rolled, by WEAPON_MODS index (amount in pieces, the rest as fractions).
	var mods := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
	## Counts attacks (wraps at 256); every machine plays the effect when it changes.
	var fires: int = 0
	# Host only.
	var timer: float = 0.0
	## Continuous weapons: per enemy slot, the run time from which it may be hit again.
	var hit_until: PackedFloat32Array = PackedFloat32Array()

	func mod(key: StringName) -> float:
		return mods[WEAPON_MODS.find(key)]


class OwnedPassive:
	extends RefCounted
	var index: int = 0
	var data: PassiveData
	var level: int = 1
	## Sum of the rarity bonuses of its levels (= level when every card was Gewöhnlich).
	var bonus: float = 1.0


class OwnedItem:
	extends RefCounted
	var index: int = 0
	var data: ItemData
	var count: int = 1


var catalog: UpgradeCatalog
var weapons: Array[OwnedWeapon] = []
var passives: Array[OwnedPassive] = []
## In the order they were found.
var items: Array[OwnedItem] = []
var stats: Dictionary[StringName, float] = {}
## EFFECTS -> summed effect_value of the items held.
var effects: Dictionary[StringName, float] = {}
var gold: int = 0
var rerolls: int = 0
var banishes: int = 0
## Map chests this player opened (Sparbuch: damage per chest).
var chests_opened: int = 0
## Host: all gold this player picked up in the run (it becomes Schilling at the end).
var gold_earned: int = 0
## The player's Stammtisch bonus (Profile.meta_bonus()), stats on top of the build.
var meta: Dictionary[StringName, float] = {}
var weapon_slots: int = 2
var passive_slots: int = 4
var evolution_level: int = 8
## Host: item keys (Card.item_key()) this player banished for the run, and those still locked
## behind a quest (Profile).
var banished: Dictionary[int, bool] = {}
var locked: Dictionary[int, bool] = {}


func _init(p_catalog: UpgradeCatalog, balance: BalanceData = null) -> void:
	catalog = p_catalog
	if balance != null:
		rerolls = balance.rerolls_per_run
		banishes = balance.banishes_per_run
		weapon_slots = balance.weapon_slots
		passive_slots = balance.passive_slots
		evolution_level = balance.evolution_level
	recompute()


## The Stammtisch ranks this player brings: their stats, plus slots, rerolls and banishes.
func apply_meta(bonus: Dictionary) -> void:
	meta.clear()
	for key: Variant in bonus:
		meta[StringName(str(key))] = float(bonus[key])
	weapon_slots += roundi(meta.get(&"weapon_slots", 0.0))
	rerolls += roundi(meta.get(&"rerolls", 0.0))
	banishes += roundi(meta.get(&"banishes", 0.0))
	recompute()


func stat(key: StringName) -> float:
	return stats.get(key, 0.0)


func effect(key: StringName) -> float:
	return effects.get(key, 0.0)


func weapon_slots_used() -> int:
	return weapons.size()


func passive_slots_used() -> int:
	return passives.size()


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


func owned_item(index: int) -> OwnedItem:
	for owned: OwnedItem in items:
		if owned.index == index:
			return owned
	return null


func item_count(index: int) -> int:
	var owned: OwnedItem = owned_item(index)
	return owned.count if owned != null else 0


## True while this player can still take another copy of the item (and it is unlocked).
func can_take_item(index: int) -> bool:
	if locked.has(Card.Kind.ITEM * 256 + index):
		return false
	var data: ItemData = catalog.items[index]
	return data.max_stacks <= 0 or item_count(index) < data.max_stacks


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
		if data.evolution == null or data.evolves_with == null or owned.level < evolution_level:
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
				weapons.append(owned)
			else:
				owned.level += 1
				if card.mod >= 0 and card.mod < WEAPON_MODS.size():
					owned.mods[card.mod] += card.value
		Card.Kind.PASSIVE:
			var owned: OwnedPassive = owned_passive(card.index)
			if owned == null:
				owned = OwnedPassive.new()
				owned.index = card.index
				owned.data = catalog.passives[card.index]
				owned.bonus = bonus
				passives.append(owned)
			elif owned.data.can_level(owned.level):
				owned.level += 1
				owned.bonus += bonus
		Card.Kind.EVOLUTION:
			var evolved: WeaponData = catalog.weapons[card.index]
			for owned: OwnedWeapon in weapons:
				if owned.data.evolution == evolved:
					# Same slot, same fire counter, same level and mods: the weapon turns into its evolution.
					owned.index = card.index
					owned.data = evolved
					owned.timer = 0.0
					owned.hit_until = PackedFloat32Array()
					break
		Card.Kind.ITEM:
			add_item(card.index)
		Card.Kind.GOLD:
			add_gold(balance.fallback_gold if balance != null else 0)
		Card.Kind.HEAL:
			recompute()
			return balance.fallback_heal if balance != null else 0.0
	recompute()
	return 0.0


func add_item(index: int) -> void:
	if index < 0 or index >= catalog.items.size():
		return
	var owned: OwnedItem = owned_item(index)
	if owned == null:
		owned = OwnedItem.new()
		owned.index = index
		owned.data = catalog.items[index]
		owned.count = 0
		items.append(owned)
	owned.count += 1
	recompute()


## Gold with the gold bonus.
func add_gold(amount: int) -> void:
	var gained: int = roundi(amount * (1.0 + stat(&"gold")))
	gold += gained
	gold_earned += maxi(gained, 0)


func set_chests_opened(count: int) -> void:
	if count != chests_opened:
		chests_opened = count
		recompute()


func recompute() -> void:
	stats.clear()
	effects.clear()
	for key: StringName in STATS:
		stats[key] = 0.0
	for key: StringName in EFFECTS:
		effects[key] = 0.0
	for owned: OwnedPassive in passives:
		for key: StringName in owned.data.stats:
			var times: float = float(owned.level) if COUNT_STATS.has(key) else owned.bonus
			stats[key] = stats.get(key, 0.0) + owned.data.stats[key] * times
	for owned: OwnedItem in items:
		for key: StringName in owned.data.stats:
			stats[key] = stats.get(key, 0.0) + owned.data.stats[key] * owned.count
		if owned.data.effect != &"":
			effects[owned.data.effect] = effects.get(owned.data.effect, 0.0) + owned.data.effect_value * owned.count
	stats[&"damage"] += effect(&"damage_per_chest") * chests_opened
	for key: StringName in meta:
		if stats.has(key):
			stats[key] += meta[key]


## Client: takes the host's view of this build (from the world state): rows as weapon_rows(),
## passive_rows() and item_rows() make them. Returns false for indices this catalog does not know.
func mirror(weapon_rows: PackedInt32Array, passive_rows: PackedInt32Array, item_rows: PackedInt32Array,
		p_gold: int, p_rerolls: int, p_banishes: int, p_chests: int) -> bool:
	gold = p_gold
	rerolls = p_rerolls
	banishes = p_banishes
	chests_opened = p_chests
	var width: int = 3 + WEAPON_MODS.size()
	var count: int = weapon_rows.size() / width
	if weapons.size() != count:
		weapons.resize(count)
	for k: int in count:
		var o: int = k * width
		var index: int = weapon_rows[o]
		if index < 0 or index >= catalog.weapons.size():
			return false
		if weapons[k] == null or weapons[k].index != index:
			weapons[k] = OwnedWeapon.new()
			weapons[k].index = index
			weapons[k].data = catalog.weapons[index]
		weapons[k].level = weapon_rows[o + 1]
		weapons[k].fires = weapon_rows[o + 2]
		for m: int in WEAPON_MODS.size():
			weapons[k].mods[m] = weapon_rows[o + 3 + m] / 1000.0
	var passive_count: int = passive_rows.size() / 3
	if passives.size() != passive_count:
		passives.resize(passive_count)
	for k: int in passive_count:
		var index: int = passive_rows[k * 3]
		if index < 0 or index >= catalog.passives.size():
			return false
		if passives[k] == null or passives[k].index != index:
			passives[k] = OwnedPassive.new()
			passives[k].index = index
			passives[k].data = catalog.passives[index]
		passives[k].level = passive_rows[k * 3 + 1]
		passives[k].bonus = passive_rows[k * 3 + 2] / 100.0
	var item_count_rows: int = item_rows.size() / 2
	if items.size() != item_count_rows:
		items.resize(item_count_rows)
	for k: int in item_count_rows:
		var index: int = item_rows[k * 2]
		if index < 0 or index >= catalog.items.size():
			return false
		if items[k] == null or items[k].index != index:
			items[k] = OwnedItem.new()
			items[k].index = index
			items[k].data = catalog.items[index]
		items[k].count = item_rows[k * 2 + 1]
	recompute()
	return true


## The rows mirror() takes, for the world state: per weapon index, level, fire counter, then each
## mod * 1000.
func weapon_rows() -> PackedInt32Array:
	var rows := PackedInt32Array()
	for owned: OwnedWeapon in weapons:
		rows.append_array([owned.index, owned.level, owned.fires & 0xFF])
		for m: int in WEAPON_MODS.size():
			rows.append(roundi(owned.mods[m] * 1000.0))
	return rows


func passive_rows() -> PackedInt32Array:
	var rows := PackedInt32Array()
	for owned: OwnedPassive in passives:
		rows.append_array([owned.index, owned.level, roundi(owned.bonus * 100.0)])
	return rows


func item_rows() -> PackedInt32Array:
	var rows := PackedInt32Array()
	for owned: OwnedItem in items:
		rows.append_array([owned.index, owned.count])
	return rows
