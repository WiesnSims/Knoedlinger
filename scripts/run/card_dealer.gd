class_name CardDealer
extends RefCounted
## Deals the Speisekarte (GAME-DESIGN.md, "XP and levelling"): `count` different cards drawn by
## weight from everything this player can still take (new weapons and passives while slots are
## free, levels of what they own, Knödl upgrades), minus what they banished. A ready evolution is
## always on the menu. When the pool runs dry, gold and a heal fill the gaps. Host only; pure
## functions of the build, the balance and the RNG, so the tests can pin them down.


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
		cards.append(card)
		pool.remove_at(pick)
		weights.remove_at(pick)
	for fallback: Card.Kind in [Card.Kind.GOLD, Card.Kind.HEAL]:
		if cards.size() < count:
			cards.append(Card.new(fallback, 0, Card.Rarity.COMMON, 1))
	return cards


## Rarity by the balance weights; luck makes the rarer ones likelier ((1 + luck) ^ rank).
static func roll_rarity(balance: BalanceData, rng: RandomNumberGenerator, luck: float) -> int:
	var weights := PackedFloat32Array()
	for k: int in balance.rarity_weights.size():
		weights.append(balance.rarity_weights[k] * pow(1.0 + maxf(luck, 0.0), k))
	return _weighted(weights, rng)


## Host: a chest (Wirtshaus cash-in) gives `items` cards right away, no choice. An evolution chest
## evolves a ready weapon first. Returns the cards taken.
static func open_chest(build: PlayerBuild, balance: BalanceData, rng: RandomNumberGenerator, items: int,
		evolution_first: bool) -> Array[Card]:
	var taken: Array[Card] = []
	if evolution_first:
		var ready: Array[Vector2i] = build.evolutions_ready()
		if not ready.is_empty():
			var card := Card.new(Card.Kind.EVOLUTION, ready[0].y, Card.Rarity.HOFRAT, 1)
			build.apply(card, balance)
			taken.append(card)
	while taken.size() < items:
		var pool: Array[Card] = []
		var weights := PackedFloat32Array()
		_fill_pool(build, balance, pool, weights)
		if pool.is_empty():
			var gold := Card.new(Card.Kind.GOLD, 0, Card.Rarity.COMMON, 1)
			build.apply(gold, balance)
			taken.append(gold)
			continue
		var card: Card = pool[_weighted(weights, rng)]
		card.rarity = roll_rarity(balance, rng, build.stat(&"luck"))
		build.apply(card, balance)
		taken.append(card)
	return taken


## Whether the card can still be taken by this build (an offer may be stale after a chest).
static func is_valid(card: Card, build: PlayerBuild, balance: BalanceData) -> bool:
	match card.kind:
		Card.Kind.WEAPON:
			if card.index < 0 or card.index >= build.catalog.weapons.size():
				return false
			var owned: PlayerBuild.OwnedWeapon = build.owned_weapon(card.index)
			if owned == null:
				var data: WeaponData = build.catalog.weapons[card.index]
				return build.weapon_slots_used() < balance.weapon_slots and not data.is_evolution and not _evolved(build, data)
			return owned.level < owned.data.max_level
		Card.Kind.PASSIVE:
			if card.index < 0 or card.index >= build.catalog.passives.size():
				return false
			var owned: PlayerBuild.OwnedPassive = build.owned_passive(card.index)
			if owned == null:
				var data: PassiveData = build.catalog.passives[card.index]
				return data.kind == PassiveData.Kind.KNODL or build.passive_slots_used() < balance.passive_slots
			return owned.level < owned.data.max_level
		Card.Kind.EVOLUTION:
			for ready: Vector2i in build.evolutions_ready():
				if ready.y == card.index:
					return true
			return false
	return true


static func _fill_pool(build: PlayerBuild, balance: BalanceData, pool: Array[Card], weights: PackedFloat32Array) -> void:
	var catalog: UpgradeCatalog = build.catalog
	for index: int in catalog.weapons.size():
		var data: WeaponData = catalog.weapons[index]
		if data.is_evolution or build.banished.has(Card.Kind.WEAPON * 256 + index) or _evolved(build, data):
			continue
		var owned: PlayerBuild.OwnedWeapon = build.owned_weapon(index)
		if owned == null:
			if build.weapon_slots_used() < balance.weapon_slots:
				pool.append(Card.new(Card.Kind.WEAPON, index, Card.Rarity.COMMON, 1))
				weights.append(balance.card_weight_new_weapon)
		elif owned.level < data.max_level:
			pool.append(Card.new(Card.Kind.WEAPON, index, Card.Rarity.COMMON, owned.level + 1))
			weights.append(balance.card_weight_weapon_level)
	for index: int in catalog.passives.size():
		var data: PassiveData = catalog.passives[index]
		if build.banished.has(Card.Kind.PASSIVE * 256 + index):
			continue
		var knodl: bool = data.kind == PassiveData.Kind.KNODL
		var owned: PlayerBuild.OwnedPassive = build.owned_passive(index)
		if owned == null:
			if knodl or build.passive_slots_used() < balance.passive_slots:
				pool.append(Card.new(Card.Kind.PASSIVE, index, Card.Rarity.COMMON, 1))
				weights.append(balance.card_weight_knodl if knodl else balance.card_weight_new_passive)
		elif owned.level < data.max_level:
			pool.append(Card.new(Card.Kind.PASSIVE, index, Card.Rarity.COMMON, owned.level + 1))
			weights.append(balance.card_weight_knodl if knodl else balance.card_weight_passive_level)


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
