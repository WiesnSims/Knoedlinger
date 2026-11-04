class_name CardDealer
extends RefCounted
## Deals the Speisekarte (GAME-DESIGN.md, "XP and levelling"): `count` different cards drawn by
## weight from what this player can still take: new weapons while a weapon slot is free, a level of
## each weapon they hold (with a rolled mod), new stat upgrades while a stat slot is free, a level of
## each stat they hold; minus what they banished. Nothing else: items only come from chests. A ready
## evolution is always on the menu. When the pool runs dry, gold and a heal fill the gaps. Chests
## roll a rarity and give items of it. Host only; pure functions of the build, the balance and the
## RNG, so the tests can pin them down.


static func deal(build: PlayerBuild, balance: BalanceData, rng: RandomNumberGenerator, count: int) -> Array[Card]:
	var cards: Array[Card] = []
	for ready: Vector2i in build.evolutions_ready():
		if cards.size() < count:
			cards.append(Card.new(Card.Kind.EVOLUTION, ready.y, Card.Rarity.HOFRAT, 1))
	var pool: Array[Card] = []
	var weights := PackedFloat32Array()
	_fill_pool(build, balance, pool, weights)
	while cards.size() < count and not pool.is_empty():
		var pick: int = _weighted(weights, rng)
		var card: Card = pool[pick]
		card.rarity = roll_rarity(balance, rng, build.stat(&"luck"))
		if card.kind == Card.Kind.WEAPON and card.level > 1:
			roll_weapon_mod(card, build, balance, rng)
		cards.append(card)
		pool.remove_at(pick)
		weights.remove_at(pick)
	for fallback: Card.Kind in [Card.Kind.GOLD, Card.Kind.HEAL]:
		if cards.size() < count:
			cards.append(Card.new(fallback, 0, Card.Rarity.COMMON, 1))
	return cards


## Rarity by the balance weights; luck makes the rarer ones likelier ((1 + luck) ^ rank).
static func roll_rarity(balance: BalanceData, rng: RandomNumberGenerator, luck: float,
		weights_in: PackedFloat32Array = PackedFloat32Array(), at_least: int = 0) -> int:
	var base: PackedFloat32Array = weights_in if not weights_in.is_empty() else balance.rarity_weights
	var weights := PackedFloat32Array()
	for k: int in base.size():
		weights.append(0.0 if k < at_least else base[k] * pow(1.0 + maxf(luck, 0.0), k))
	return _weighted(weights, rng)


## A weapon level card's gain: one of the weapon's level_mods by balance.weapon_mod_weights (no
## "+1 piece" once it holds its max_amount), the roll times the card's rarity bonus.
static func roll_weapon_mod(card: Card, build: PlayerBuild, balance: BalanceData, rng: RandomNumberGenerator) -> void:
	var weapon: WeaponData = build.catalog.weapons[card.index]
	var owned: PlayerBuild.OwnedWeapon = build.owned_weapon(card.index)
	var keys: Array[StringName] = []
	var weights := PackedFloat32Array()
	for key: StringName in weapon.level_mods:
		var mod: int = PlayerBuild.WEAPON_MODS.find(key)
		if mod < 0:
			continue
		if mod == PlayerBuild.MOD_AMOUNT and owned != null and Formulas.weapon_amount(weapon, owned.mods) >= weapon.max_amount:
			continue
		keys.append(key)
		weights.append(balance.weapon_mod_weights.get(key, 1.0))
	if keys.is_empty():
		keys.append(&"damage")
		weights.append(1.0)
	var key: StringName = keys[_weighted(weights, rng)]
	var bonus: float = balance.rarity_bonus[clampi(card.rarity, 0, balance.rarity_bonus.size() - 1)]
	var base: float = weapon.level_mods.get(key, 0.15)
	card.mod = PlayerBuild.WEAPON_MODS.find(key)
	# Pieces come whole: one, two at Hofratswürdig.
	card.value = floorf(base * bonus) if card.mod == PlayerBuild.MOD_AMOUNT else base * bonus
	card.value = maxf(card.value, 1.0) if card.mod == PlayerBuild.MOD_AMOUNT else card.value


## Host: a chest gives `items` items right away, no choice (GAME-DESIGN.md, "Items"). It rolls one
## rarity (luck raises it, `at_least` sets a floor) and hands out items of that rarity, falling back
## to lower rarities when this player holds every copy there is. An evolution chest evolves a ready
## weapon first. Returns the cards taken.
static func open_chest(build: PlayerBuild, balance: BalanceData, rng: RandomNumberGenerator, items: int,
		evolution_first: bool, rarity: int = -1) -> Array[Card]:
	var taken: Array[Card] = []
	if evolution_first:
		for ready: Vector2i in build.evolutions_ready():
			var card := Card.new(Card.Kind.EVOLUTION, ready.y, Card.Rarity.HOFRAT, 1)
			build.apply(card, balance)
			taken.append(card)
			break
	if rarity < 0:
		rarity = roll_chest_rarity(balance, rng, build.stat(&"luck"), 0)
	while taken.size() < items:
		var index: int = pick_item(build, rng, rarity)
		if index < 0:
			var gold := Card.new(Card.Kind.GOLD, 0, Card.Rarity.COMMON, 1)
			build.apply(gold, balance)
			taken.append(gold)
			continue
		var card := Card.new(Card.Kind.ITEM, index, build.catalog.items[index].rarity, build.item_count(index) + 1)
		build.apply(card, balance)
		taken.append(card)
	return taken


static func roll_chest_rarity(balance: BalanceData, rng: RandomNumberGenerator, luck: float, at_least: int) -> int:
	return roll_rarity(balance, rng, luck, balance.chest_rarity_weights, at_least)


## A random item of `rarity` this build can still take; failing that the next lower rarity, then
## the higher ones. -1 when there is none at all.
static func pick_item(build: PlayerBuild, rng: RandomNumberGenerator, rarity: int) -> int:
	var order: Array[int] = []
	for r: int in range(rarity, -1, -1):
		order.append(r)
	for r: int in range(rarity + 1, 4):
		order.append(r)
	for r: int in order:
		var choices: Array[int] = []
		for index: int in build.catalog.items.size():
			if build.catalog.items[index].rarity == r and build.can_take_item(index):
				choices.append(index)
		if not choices.is_empty():
			return choices[rng.randi_range(0, choices.size() - 1)]
	return -1


## Whether the card can still be taken by this build (an offer may be stale after a chest).
static func is_valid(card: Card, build: PlayerBuild, balance: BalanceData) -> bool:
	match card.kind:
		Card.Kind.WEAPON:
			if card.index < 0 or card.index >= build.catalog.weapons.size():
				return false
			var owned: PlayerBuild.OwnedWeapon = build.owned_weapon(card.index)
			if owned == null:
				var data: WeaponData = build.catalog.weapons[card.index]
				return build.weapon_slots_used() < build.weapon_slots and not data.is_evolution and not _evolved(build, data)
			return true
		Card.Kind.PASSIVE:
			if card.index < 0 or card.index >= build.catalog.passives.size():
				return false
			var owned: PlayerBuild.OwnedPassive = build.owned_passive(card.index)
			if owned == null:
				return build.passive_slots_used() < build.passive_slots
			return owned.data.can_level(owned.level)
		Card.Kind.EVOLUTION:
			for ready: Vector2i in build.evolutions_ready():
				if ready.y == card.index:
					return true
			return false
		Card.Kind.ITEM:
			return card.index >= 0 and card.index < build.catalog.items.size() and build.can_take_item(card.index)
	return true


static func _fill_pool(build: PlayerBuild, balance: BalanceData, pool: Array[Card], weights: PackedFloat32Array) -> void:
	var catalog: UpgradeCatalog = build.catalog
	for index: int in catalog.weapons.size():
		var data: WeaponData = catalog.weapons[index]
		if build.banished.has(Card.Kind.WEAPON * 256 + index) or build.locked.has(Card.Kind.WEAPON * 256 + index):
			continue
		var owned: PlayerBuild.OwnedWeapon = build.owned_weapon(index)
		if owned == null:
			if not data.is_evolution and not _evolved(build, data) and build.weapon_slots_used() < build.weapon_slots:
				pool.append(Card.new(Card.Kind.WEAPON, index, Card.Rarity.COMMON, 1))
				weights.append(balance.card_weight_new_weapon)
		else:
			pool.append(Card.new(Card.Kind.WEAPON, index, Card.Rarity.COMMON, owned.level + 1))
			weights.append(balance.card_weight_weapon_level)
	for index: int in catalog.passives.size():
		var data: PassiveData = catalog.passives[index]
		if build.banished.has(Card.Kind.PASSIVE * 256 + index) or build.locked.has(Card.Kind.PASSIVE * 256 + index):
			continue
		var owned: PlayerBuild.OwnedPassive = build.owned_passive(index)
		if owned == null:
			if build.passive_slots_used() < build.passive_slots:
				pool.append(Card.new(Card.Kind.PASSIVE, index, Card.Rarity.COMMON, 1))
				weights.append(balance.card_weight_new_passive)
		elif data.can_level(owned.level):
			pool.append(Card.new(Card.Kind.PASSIVE, index, Card.Rarity.COMMON, owned.level + 1))
			weights.append(balance.card_weight_passive_level)


## True when the player already turned this weapon into its evolution (it is not offered again).
static func _evolved(build: PlayerBuild, weapon: WeaponData) -> bool:
	return weapon.evolution != null and build.owned_weapon(build.catalog.weapons.find(weapon.evolution)) != null


static func _weighted(weights: PackedFloat32Array, rng: RandomNumberGenerator) -> int:
	var total: float = 0.0
	for w: float in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return 0
	var roll: float = rng.randf() * total
	for k: int in weights.size():
		roll -= maxf(weights[k], 0.0)
		if roll <= 0.0:
			return k
	return weights.size() - 1
