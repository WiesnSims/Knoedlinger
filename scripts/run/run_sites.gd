class_name RunSites
extends RefCounted
## Places on the map that offer a deal (1.4 tasks 5.2 and 5.3), on top of RunWorld's state:
##   - Der Standler: at each of balance.standler_minutes a market stall sets up near the players for
##     standler_stay seconds. Walking up to it opens his shop (LevelUpFlow.open_shop): items for gold,
##     each player their own standler_items (co-op too), dearer for every item that player already
##     bought from him and as the clock runs. Leaving the shop keeps it shut until they step away.
##   - Marterl: marterl_count wayside shrines on free chest spots, each of one kind, used once by
##     standing at it for marterl_pray_seconds:
##       Mutprobe – marterl_mutprobe_seconds of rings of enemies closing in, then a free chest;
##       Gier – for marterl_gier_seconds twice the crowd and twice the gold from coins;
##       Segen – the one who prays gets a free Speisekarte (one level's worth of cards).
## The host decides everything and tells every machine with SITE run events; each machine builds
## the stall and the shrines from them (SiteProp). Numbers in balance.tres ("Der Standler", "Marterl").

enum Site { STANDLER, MARTERL }
enum Marterl { MUTPROBE, GIER, SEGEN }
enum State { PLACED, ACTIVE, DONE, GONE }

var world: RunWorld
var balance: BalanceData
## Every role: where the stall stands (INF while he is away), and how often he came.
var stand_at: Vector3 = Vector3.INF
var stand_visits: int = 0
## Every role: the Marterl, by index.
var marterl_at: Array[Vector3] = []
var marterl_kind: PackedInt32Array = PackedInt32Array()
var marterl_state: PackedInt32Array = PackedInt32Array()
## Host: seconds of Gier left (0 = none).
var gier_left: float = 0.0
## Host, balance log: items bought from Der Standler and Marterl used.
var stand_buys: int = 0
var marterl_used: int = 0

var _rng := RandomNumberGenerator.new()
var _stand_index: int = 0
var _stand_left: float = 0.0
var _stand_yaw: float = 0.0
## Host: per peer, the item indices on their own offer (taken out when bought), the items bought
## from him this run, and whether they must step away before the shop opens again.
var _stand_items: Dictionary[int, PackedInt32Array] = {}
var _stand_bought: Dictionary[int, int] = {}
var _stand_wait: Dictionary[int, bool] = {}
var _pray: Dictionary[int, float] = {}
var _mutprobe: int = -1
var _mutprobe_left: float = 0.0
var _ring_timer: float = 0.0
var _stall: SiteProp
var _shrines: Dictionary[int, SiteProp] = {}
## Test hook: `standler_at=<s>` brings him at that second, right where the first player stands.
var _stand_test_at: float = -1.0


func _init(p_world: RunWorld, p_balance: BalanceData, seed_value: int) -> void:
	world = p_world
	balance = p_balance
	_rng.seed = seed_value * 29 + 11
	_stand_test_at = LaunchArgs.get_float("standler_at", -1.0)


## Host, at the start: the Marterl on chest spots no chest took.
func place_marterl() -> void:
	var spots: Array[Vector2] = []
	for spot: Vector2 in world.map.chest_spots:
		var taken: bool = false
		for slot: int in world.loot.all_slots():
			if Vector2(world.loot.xs[slot] - spot.x, world.loot.zs[slot] - spot.y).length() < 4.0:
				taken = true
		if not taken:
			spots.append(spot)
	# Test hook `marterl_drill=<kind>`: the first one of that kind right at the spawn.
	var drill: int = LaunchArgs.get_int("marterl_drill", -1)
	if drill >= 0:
		spots.insert(0, Vector2(world.map.spawn_point.x + 1.0, world.map.spawn_point.z))
	for k: int in mini(balance.marterl_count, spots.size()):
		var pick: int = 0 if drill >= 0 and k == 0 else _rng.randi_range(0, spots.size() - 1)
		var kind: int = k % 3 if balance.marterl_count >= 3 else _rng.randi_range(0, 2)
		if drill >= 0 and k == 0:
			kind = clampi(drill, 0, 2)
		elif drill >= 0:
			kind = (drill + k) % 3
		world.events.site(Site.MARTERL, k, State.PLACED, kind, spots[pick].x, spots[pick].y)
		spots.remove_at(pick)


## Host: once a frame.
func update(delta: float) -> void:
	_update_standler(delta)
	_update_marterl(delta)


## Host: the crowd and coin gold factors while a Gier runs.
func crowd_mult() -> float:
	return balance.marterl_gier_mult if gier_left > 0.0 else 1.0


func gold_mult() -> int:
	return roundi(balance.marterl_gier_mult) if gier_left > 0.0 else 1


## Host: everything standing, as run events for a client that just arrived.
func resend(queue: RunEventCodec.Queue) -> void:
	for k: int in marterl_at.size():
		queue.site(Site.MARTERL, k, marterl_state[k], marterl_kind[k], marterl_at[k].x, marterl_at[k].z)
	if stand_at.is_finite():
		queue.site(Site.STANDLER, _stand_index - 1, State.PLACED, roundi(_stand_yaw * 40.0) & 0xFF, stand_at.x, stand_at.z)


## Every role: a SITE run event.
func present(e: RunEventCodec.Event) -> void:
	var y: float = world.ground.height_at(e.x, e.z)
	if e.a == Site.STANDLER:
		if e.c == State.GONE:
			stand_at = Vector3.INF
			if _stall != null:
				_stall.queue_free()
				_stall = null
			world.hud.toast(tr("TOAST_STANDLER_GONE"))
			return
		stand_at = Vector3(e.x, y, e.z)
		if _stall != null:
			return
		stand_visits += 1
		_stall = SiteProp.new()
		world.add_child(_stall)
		_stall.setup_standler(stand_at, (e.b & 0xFF) / 40.0)
		world.hud.toast(tr("TOAST_STANDLER"))
		GameAudio.play(&"chest", stand_at)
		print("[RUN] Standler at %.0f, %.0f t=%.1f" % [e.x, e.z, world.run_time])
		return
	while marterl_at.size() <= e.id:
		marterl_at.append(Vector3.ZERO)
		marterl_kind.append(0)
		marterl_state.append(State.PLACED)
	marterl_at[e.id] = Vector3(e.x, y, e.z)
	marterl_kind[e.id] = e.b
	var was: int = marterl_state[e.id]
	marterl_state[e.id] = e.c
	if not _shrines.has(e.id):
		var shrine := SiteProp.new()
		world.add_child(shrine)
		shrine.setup_marterl(marterl_at[e.id], e.b)
		_shrines[e.id] = shrine
	_shrines[e.id].set_state(e.c)
	if e.c == State.ACTIVE and was == State.PLACED:
		world.hud.toast(tr("TOAST_MARTERL_%d" % clampi(e.b, 0, 2)))
		GameAudio.play(&"gate_open", marterl_at[e.id])
		print("[RUN] Marterl %d (%d) t=%.1f" % [e.id, e.b, world.run_time])
	elif e.c == State.DONE and was == State.ACTIVE and e.b != Marterl.SEGEN:
		world.hud.toast(tr("TOAST_MARTERL_DONE_%d" % clampi(e.b, 0, 2)))


## Host: LevelUpFlow says a player bought card `card` of their shop.
func on_bought(peer: int, card: int) -> void:
	var items: PackedInt32Array = _stand_items.get(peer, PackedInt32Array())
	if card < items.size():
		items.remove_at(card)
		_stand_items[peer] = items
	_stand_bought[peer] = _stand_bought.get(peer, 0) + 1
	stand_buys += 1
	if stand_at.is_finite():
		world.events.cue(RunEventCodec.Cue.CHEST, stand_at.x, stand_at.z)
	print("[RUN] Standler sold peer=%d t=%.1f" % [peer, world.run_time])
	# With nothing left on the counter, the shop stays shut.
	_stand_wait[peer] = items.is_empty()


## Host: a player left the shop.
func on_shop_closed(peer: int) -> void:
	_stand_wait[peer] = true


func _update_standler(delta: float) -> void:
	var minutes: PackedFloat32Array = balance.standler_minutes
	if stand_at.is_finite():
		_stand_left -= delta
		if _stand_left <= 0.0 or world.phase != RunWorld.Phase.RUNNING:
			world.events.site(Site.STANDLER, _stand_index - 1, State.GONE, 0, stand_at.x, stand_at.z)
			_stand_items.clear()
			_stand_wait.clear()
			return
		_serve_standler()
		return
	if world.phase != RunWorld.Phase.RUNNING or world.players.is_empty():
		return
	var due: bool = _stand_index < minutes.size() and world.run_time >= minutes[_stand_index] * 60.0
	if _stand_test_at >= 0.0:
		due = _stand_index == 0 and world.run_time >= _stand_test_at
	if not due:
		return
	_stand_index += 1
	_stand_left = balance.standler_stay
	var first: Player = world.players[world.players.keys()[0]]
	var at: Vector3 = first.global_position
	if _stand_test_at < 0.0:
		# A few metres off one player, inside the map.
		var angle: float = _rng.randf() * TAU
		at += Vector3(cos(angle), 0.0, sin(angle)) * balance.standler_distance
		var half: float = world.map.half_size - 6.0
		at.x = clampf(at.x, -half, half)
		at.z = clampf(at.z, -half, half)
	_stand_yaw = _rng.randf() * TAU
	world.events.site(Site.STANDLER, _stand_index - 1, State.PLACED, roundi(_stand_yaw * 40.0) & 0xFF, at.x, at.z)


## Host: whoever steps up to the stall gets their shop (once nothing else is open for them).
func _serve_standler() -> void:
	var coop: bool = NetworkManager.is_coop()
	for peer: int in world.players:
		var state: PlayerState = world.states[peer]
		var at: Vector3 = world.players[peer].global_position
		var near: float = Vector2(at.x - stand_at.x, at.z - stand_at.z).length()
		if near > balance.standler_radius + 1.5:
			_stand_wait[peer] = false
			continue
		if near > balance.standler_radius or _stand_wait.get(peer, false) or state.downed or state.choosing \
				or world.level_flow.is_open(peer) or state.pending_levels > 0:
			continue
		var cards: Array[Card] = []
		var prices := PackedInt32Array()
		var items: PackedInt32Array = _stand_items.get(peer, _roll_items(state.build))
		var kept := PackedInt32Array()
		for index: int in items:
			if not state.build.can_take_item(index):
				continue
			kept.append(index)
			var data: ItemData = state.build.catalog.items[index]
			cards.append(Card.new(Card.Kind.ITEM, index, data.rarity, state.build.item_count(index) + 1))
			prices.append(price(data.rarity, _stand_bought.get(peer, 0), world.run_time))
		_stand_items[peer] = kept
		if cards.is_empty():
			_stand_wait[peer] = true
			continue
		print("[RUN] Standler shop peer=%d gold=%d prices=%s t=%.1f" % [peer, state.build.gold, prices, world.run_time])
		world.level_flow.open_shop(peer, state, cards, prices, coop)


## What an item of `rarity` costs after `bought` items from him, at `seconds` into the run.
func price(rarity: int, bought: int, seconds: float) -> int:
	var base: int = balance.standler_prices[clampi(rarity, 0, balance.standler_prices.size() - 1)]
	return roundi(base * pow(balance.standler_price_growth, bought) * (1.0 + balance.standler_price_per_minute * seconds / 60.0))


func _roll_items(build: PlayerBuild) -> PackedInt32Array:
	var items := PackedInt32Array()
	for k: int in balance.standler_items * 3:
		if items.size() >= balance.standler_items:
			break
		var rarity: int = CardDealer.roll_chest_rarity(balance, _rng, build.stat(&"luck"), 0)
		var index: int = CardDealer.pick_item(build, _rng, rarity)
		if index >= 0 and not items.has(index):
			items.append(index)
	return items


func _update_marterl(delta: float) -> void:
	if gier_left > 0.0:
		gier_left -= delta
		if gier_left <= 0.0:
			_finish_marterl(_index_of(Marterl.GIER, State.ACTIVE))
	if _mutprobe >= 0:
		_update_mutprobe(delta)
	if world.phase != RunWorld.Phase.RUNNING:
		return
	for k: int in marterl_at.size():
		if marterl_state[k] != State.PLACED:
			continue
		var praying: int = 0
		for peer: int in world.players:
			var at: Vector3 = world.players[peer].global_position
			if not world.states[peer].downed and Vector2(at.x - marterl_at[k].x, at.z - marterl_at[k].z).length() < balance.marterl_radius:
				praying = peer
		if praying == 0:
			_pray.erase(k)
			continue
		_pray[k] = _pray.get(k, 0.0) + delta
		if _pray[k] >= balance.marterl_pray_seconds:
			_pray.erase(k)
			_start_marterl(k, praying)


func _start_marterl(k: int, peer: int) -> void:
	marterl_used += 1
	world.events.site(Site.MARTERL, k, State.ACTIVE, marterl_kind[k], marterl_at[k].x, marterl_at[k].z)
	match marterl_kind[k]:
		Marterl.MUTPROBE:
			_mutprobe = k
			_mutprobe_left = balance.marterl_mutprobe_seconds
			_ring_timer = 0.0
		Marterl.GIER:
			gier_left = balance.marterl_gier_seconds
		Marterl.SEGEN:
			world.states[peer].pending_levels += balance.marterl_segen_levels
			world.events.site(Site.MARTERL, k, State.DONE, marterl_kind[k], marterl_at[k].x, marterl_at[k].z)


## Mutprobe: a ring of enemies round the Marterl every marterl_ring_every seconds, then the chest.
func _update_mutprobe(delta: float) -> void:
	var at: Vector3 = marterl_at[_mutprobe]
	_mutprobe_left -= delta
	_ring_timer -= delta
	if _ring_timer <= 0.0 and _mutprobe_left > 0.0:
		_ring_timer = balance.marterl_ring_every
		var t: int = _fodder_type()
		for n: int in balance.marterl_ring_count:
			var angle: float = TAU * n / balance.marterl_ring_count
			world.enemies.spawn_at(t, at.x + cos(angle) * balance.marterl_ring_radius,
					at.z + sin(angle) * balance.marterl_ring_radius)
	if _mutprobe_left <= 0.0:
		var rarity: int = maxi(CardDealer.roll_chest_rarity(balance, _rng, 0.0, 0), 1)
		world._drop_loot(LootField.Kind.BOSS_CHEST, at.x, at.z, LootField.chest_value(1, rarity))
		_finish_marterl(_mutprobe)
		_mutprobe = -1


func _finish_marterl(k: int) -> void:
	if k >= 0:
		world.events.site(Site.MARTERL, k, State.DONE, marterl_kind[k], marterl_at[k].x, marterl_at[k].z)


func _index_of(kind: int, state: int) -> int:
	for k: int in marterl_at.size():
		if marterl_kind[k] == kind and marterl_state[k] == state:
			return k
	return -1


## The plain enemy that spawns most right now (for the Mutprobe's rings).
func _fodder_type() -> int:
	var weights: PackedFloat32Array = world.wave.weights_at(world.run_time)
	var best: int = 0
	for t: int in mini(weights.size(), world.types.size()):
		if not world.types[t].boss and world.types[t].attack == null and weights[t] > weights[best]:
			best = t
	return best
