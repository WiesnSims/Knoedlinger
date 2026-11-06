class_name ItemProcs
extends RefCounted
## The items' rules (1.4, DECISIONS 6.7): every ItemEffect of every item a player holds, run on the
## host. RunWorld calls prepare() before the weapons fire (conditions, target bonuses, timers),
## after_hits() once the frame's weapon and projectile hits are in (on-hit procs), on_kills() before
## the kills turn into Brösel, and the hooks (hurt, lethal, revive, cash-in, Brösel) where those
## happen. Procs never trigger procs: their damage goes out under the item's own source, which logs
## no hits. A frame handles at most balance.item_proc_budget procs, so a stacked build keeps 60 fps.

const T := ItemEffect.Trigger
const A := ItemEffect.Action

## One effect of one held item: the item, how many copies, its damage source.
class Held:
	extends RefCounted
	var item: ItemData
	var effect: ItemEffect
	var count: int = 1
	var source: int = -1
	var timer: float = 0.0


var world: RunWorld
var balance: BalanceData
var rng := RandomNumberGenerator.new()
## Procs this run per item id (all players), for the build view.
var procs_by_item: Dictionary[StringName, int] = {}

## Per peer: the held effects, the build signature they were made from, kills by their weapons,
## executes, the last position (moving / standing still), seconds standing still, ON_LETHAL used.
var _held: Dictionary[int, Array] = {}
var _signature: Dictionary[int, int] = {}
var _kills: Dictionary[int, int] = {}
var _executes: Dictionary[int, int] = {}
var _last_at: Dictionary[int, Vector3] = {}
var _still: Dictionary[int, float] = {}
var _moving: Dictionary[int, bool] = {}
var _lethal_used: Dictionary[int, int] = {}
## Weapon source -> peer, for kills and hits.
var _source_peer: Dictionary[int, int] = {}
var _budget: int = 0
var _cues: int = 0


func _init(p_world: RunWorld, p_balance: BalanceData, seed_value: int) -> void:
	world = p_world
	balance = p_balance
	rng.seed = seed_value * 29 + 11


## Chance after `count` copies and the player's proc bonus (Stallaterne).
static func stacked_chance(chance: float, count: int, proc_bonus: float = 0.0) -> float:
	return clampf((1.0 - pow(1.0 - clampf(chance, 0.0, 1.0), maxi(count, 1))) * (1.0 + proc_bonus), 0.0, 1.0)


## Value after `count` copies (capped at `cap` when it has one).
static func stacked_value(effect: ItemEffect, count: int) -> float:
	var total: float = effect.value * maxi(count, 1)
	return minf(total, effect.cap) if effect.cap > 0.0 and effect.action != A.CHAIN else total


## The effects a build holds, as Held rows (one per effect per item).
static func held_of(build: PlayerBuild) -> Array[Held]:
	var out: Array[Held] = []
	for owned: PlayerBuild.OwnedItem in build.items:
		for effect: ItemEffect in owned.data.effects:
			var row := Held.new()
			row.item = owned.data
			row.effect = effect
			row.count = owned.count
			out.append(row)
	return out


## Sum of one action's stacked values in a build (e.g. PROC_CHANCE, EXTRA_ROLL, SHIELD).
static func total(build: PlayerBuild, action: ItemEffect.Action) -> float:
	var sum: float = 0.0
	for owned: PlayerBuild.OwnedItem in build.items:
		for effect: ItemEffect in owned.data.effects:
			if effect.action == action:
				sum += stacked_value(effect, owned.count)
	return sum


## Host, before the weapons: refresh what each player holds, their conditional damage and target
## bonuses, regen and timed effects.
func prepare(delta: float) -> void:
	_budget = balance.item_proc_budget
	_cues = 0
	var enemies: EnemyManager = world.enemies
	for peer: int in world.players:
		var state: PlayerState = world.states[peer]
		var build: PlayerBuild = state.build
		_refresh(peer, build)
		var player: Player = world.players[peer]
		var at: Vector3 = player.global_position
		var last: Vector3 = _last_at.get(peer, at)
		var speed: float = Vector2(at.x - last.x, at.z - last.z).length() / maxf(delta, 0.0001)
		_last_at[peer] = at
		_moving[peer] = speed > 1.0
		_still[peer] = 0.0 if speed > 0.3 else _still.get(peer, 0.0) + delta
		var airborne: bool = at.y - world.ground.height_at(at.x, at.z) > 0.4
		var low: bool = state.hp < state.max_hp * 0.5
		var cond: float = 0.0
		var bonus := Vector4(0.0, 0.0, 0.0, at.y)
		var procs: bool = false
		state.shield_share = 0.0
		var knodl: Knodl = world.knodls.get(peer)
		if knodl != null:
			knodl.rodel = 0.0
		for row: Held in _held.get(peer, []):
			var effect: ItemEffect = row.effect
			var value: float = stacked_value(effect, row.count)
			match effect.trigger:
				T.ON_HIT:
					procs = true
				T.AIRBORNE:
					if airborne and effect.action == A.DAMAGE:
						cond += value
				T.MOVING:
					if _moving[peer] and effect.action == A.DAMAGE:
						cond += value
				T.LOW_HP:
					if effect.action == A.DAMAGE:
						# Up to `value` as the HP falls to nothing.
						cond += value * clampf(1.0 - state.hp / maxf(state.max_hp, 1.0), 0.0, 1.0)
					elif low and effect.action == A.REGEN and not state.downed:
						state.heal(value * delta)
				T.STANDING_STILL:
					if _still[peer] >= effect.seconds and not state.downed:
						if effect.action == A.REGEN:
							state.heal(value * delta)
						elif effect.action == A.DAMAGE:
							cond += value
				T.TARGET_HEALTHY:
					bonus.x += value
				T.TARGET_ELITE:
					bonus.y += value
				T.TARGET_BELOW:
					bonus.z += value
				T.PERIODIC:
					row.timer += delta
					if row.timer >= effect.cooldown and not state.downed:
						row.timer = 0.0
						_act(peer, row, -1, 0.0, at)
				T.ALWAYS:
					match effect.action:
						A.DAMAGE_PER_KILL:
							cond += minf(effect.value * _kills.get(peer, 0) * row.count, effect.cap if effect.cap > 0.0 else INF)
						A.DAMAGE_PER_EXECUTE:
							cond += minf(effect.value * _executes.get(peer, 0) * row.count, effect.cap if effect.cap > 0.0 else INF)
						A.SHIELD:
							state.shield_share += value
						A.RODEL:
							if knodl != null:
								knodl.rodel += value
		build.cond_damage = cond
		for owned: PlayerBuild.OwnedWeapon in build.weapons:
			if owned.source < 0:
				continue
			_source_peer[owned.source] = peer
			_flag(enemies, owned.source, procs, bonus)
		if knodl != null and knodl.damage_source >= 0:
			_flag(enemies, knodl.damage_source, false, bonus)


## Host, after the weapons and projectiles: the on-hit procs of this frame's hits.
func after_hits() -> void:
	var enemies: EnemyManager = world.enemies
	var hits: int = enemies.hit_slot.size()
	if hits == 0:
		return
	var slots: PackedInt32Array = enemies.hit_slot
	var sources: PackedInt32Array = enemies.hit_source
	var amounts: PackedFloat32Array = enemies.hit_amount
	enemies.hit_slot = PackedInt32Array()
	enemies.hit_source = PackedInt32Array()
	enemies.hit_amount = PackedFloat32Array()
	# Spread the budget over the frame's hits: start at a random one when there are more.
	var start: int = rng.randi_range(0, hits - 1) if hits > _budget else 0
	for n: int in hits:
		if _budget <= 0:
			break
		var k: int = (start + n) % hits
		var peer: int = _source_peer.get(sources[k], 0)
		if peer == 0 or not world.states.has(peer):
			continue
		var bonus: float = total(world.states[peer].build, A.PROC_CHANCE)
		for row: Held in _held.get(peer, []):
			if row.effect.trigger != T.ON_HIT or _budget <= 0:
				continue
			if rng.randf() < stacked_chance(row.effect.chance, row.count, bonus):
				_act(peer, row, slots[k], amounts[k], Vector3.INF)


## Host, with this frame's kills still listed: on-kill procs and the kill counters.
func on_kills() -> void:
	var enemies: EnemyManager = world.enemies
	for k: int in enemies.kill_x.size():
		var peer: int = _source_peer.get(enemies.kill_source[k] if k < enemies.kill_source.size() else -1, 0)
		if peer == 0 or not world.states.has(peer):
			continue
		_kills[peer] = _kills.get(peer, 0) + 1
		var bonus: float = total(world.states[peer].build, A.PROC_CHANCE)
		var at := Vector3(enemies.kill_x[k], 0.0, enemies.kill_z[k])
		for row: Held in _held.get(peer, []):
			if row.effect.trigger != T.ON_KILL or _budget <= 0:
				continue
			if rng.randf() < stacked_chance(row.effect.chance, row.count, bonus):
				_act(peer, row, -1, 0.0, at)


## Host: the player took `taken` HP of damage.
func on_hurt(peer: int, taken: float) -> void:
	_fire(peer, T.ON_HURT, taken)


## Host: a hit would knock the player down. Returns true when an item stopped it (once per copy).
func on_lethal(peer: int) -> bool:
	var used: int = _lethal_used.get(peer, 0)
	var copies: int = 0
	for row: Held in _held.get(peer, []):
		if row.effect.trigger == T.ON_LETHAL:
			copies = maxi(copies, row.item.max_stacks if row.item.max_stacks > 0 else row.count)
			copies = mini(copies, row.count)
	if used >= copies:
		return false
	_lethal_used[peer] = used + 1
	var state: PlayerState = world.states[peer]
	state.downed = false
	state.downed_timer = 0.0
	state.hp = 1.0
	_fire(peer, T.ON_LETHAL, 0.0)
	return true


## Host: the Marterl-Kerze stood the player up.
func on_revive(peer: int) -> void:
	_fire(peer, T.ON_REVIVE, 0.0)


## Host: the player cashed a Knödl in.
func on_cashin(peer: int) -> void:
	_fire(peer, T.ON_CASHIN, 0.0)


## Host: the player's Knödl soaked up `count` Brösel this frame.
func on_brosel(peer: int, count: int) -> void:
	if count > 0:
		_fire(peer, T.ON_BROSEL, float(count))


## How many times ON_LETHAL items saved this player (the build view).
func lethal_used(peer: int) -> int:
	return _lethal_used.get(peer, 0)


func _fire(peer: int, trigger: ItemEffect.Trigger, amount: float) -> void:
	if not world.players.has(peer):
		return
	var at: Vector3 = world.players[peer].global_position
	var bonus: float = total(world.states[peer].build, A.PROC_CHANCE)
	for row: Held in _held.get(peer, []):
		if row.effect.trigger != trigger or row.timer > 0.0:
			continue
		if rng.randf() < stacked_chance(row.effect.chance, row.count, bonus):
			_act(peer, row, -1, amount, at)
			row.timer = row.effect.cooldown


## Counts cooldowns down (ON_HURT and friends); PERIODIC rows count up in prepare().
func tick(delta: float) -> void:
	for peer: int in _held:
		for row: Held in _held[peer]:
			if row.effect.trigger != T.PERIODIC and row.timer > 0.0:
				row.timer -= delta


## Does one effect. `slot`: the enemy hit (-1 = none), `amount`: the hit or the damage taken,
## `at`: where (INF = at the enemy hit).
func _act(peer: int, row: Held, slot: int, amount: float, at: Vector3) -> void:
	var enemies: EnemyManager = world.enemies
	var state: PlayerState = world.states[peer]
	var build: PlayerBuild = state.build
	var effect: ItemEffect = row.effect
	var value: float = stacked_value(effect, row.count)
	if slot >= 0:
		if enemies.alive[slot] == 0 and effect.action != A.BLAST and effect.action != A.CHAIN:
			return
		at = Vector3(enemies.pos_x[slot], 0.0, enemies.pos_z[slot])
	_budget -= 1
	procs_by_item[row.item.id] = procs_by_item.get(row.item.id, 0) + 1
	if row.source < 0:
		row.source = world._source(peer, "item", String(row.item.id))
	var held_source: int = enemies.source
	enemies.source = row.source
	var power: float = 1.0 + build.stat(&"damage") + build.cond_damage
	match effect.action:
		A.FREEZE:
			enemies.slow(slot, 0.0, effect.seconds)
		A.BURN:
			enemies.burn(slot, amount * value, effect.seconds)
		A.BLAST:
			_hurt_around(at, effect.radius, amount * value, slot)
			_cue(RunEventCodec.Cue.SPARK, at)
		A.CHAIN:
			var from: int = slot
			var hit: Dictionary[int, bool] = {slot: true}
			for jump: int in roundi(effect.cap):
				var next: int = _nearest(enemies.pos_x[from], enemies.pos_z[from], effect.radius, hit)
				if next < 0:
					break
				hit[next] = true
				enemies.damage(next, amount * value)
				_cue(RunEventCodec.Cue.SPARK, Vector3(enemies.pos_x[next], 0.0, enemies.pos_z[next]))
				from = next
		A.WISP:
			var target: int = _nearest(at.x, at.z, effect.radius, {})
			if target >= 0:
				enemies.damage(target, balance.item_base_damage * value * power)
				_cue(RunEventCodec.Cue.SPARK, Vector3(enemies.pos_x[target], 0.0, enemies.pos_z[target]))
		A.EXECUTE:
			if not world.types[enemies.type[slot]].boss:
				enemies.damage(slot, enemies.hp[slot] + 1.0)
				_executes[peer] = _executes.get(peer, 0) + 1
				_cue(RunEventCodec.Cue.SPARK, at)
		A.BIG_HIT:
			enemies.damage(slot, amount * maxf(value - 1.0, 0.0))
			_cue(RunEventCodec.Cue.SPARK, at)
		A.HEAL:
			state.heal(value * state.max_hp if value < 1.0 else value)
		A.INVULNERABLE:
			state.hurt_timer = maxf(state.hurt_timer, effect.seconds)
		A.TIME_STOP:
			for j: int in WeaponSystem.enemies_near(enemies, at.x, at.z, effect.radius):
				enemies.slow(j, 0.0, effect.seconds)
			world.events.cue(RunEventCodec.Cue.SHOCKWAVE, at.x, at.z)
		A.SHOCK:
			_hurt_around(at, effect.radius, balance.item_base_damage * value * power, -1)
			world.events.cue(RunEventCodec.Cue.SHOCKWAVE, at.x, at.z)
		A.THORNS:
			_hurt_around(at, effect.radius, amount * value * power, -1)
		A.PULL_BROSEL:
			world.brosel.attract(at, Player.BODY_HEIGHT, effect.radius, peer)
			world.events.cue(RunEventCodec.Cue.SHOCKWAVE, at.x, at.z)
		A.DROP_FOOD:
			world._drop_loot(LootField.Kind.HEAL, at.x, at.z, roundi(value))
		A.STRING_CUT:
			var knodl: Knodl = world.knodls.get(peer)
			if knodl != null:
				_hurt_along(at, knodl.global_position, effect.radius,
						balance.item_base_damage * value * minf(amount, 10.0) * power)
	enemies.source = held_source


func _refresh(peer: int, build: PlayerBuild) -> void:
	var signature: int = 0
	for owned: PlayerBuild.OwnedItem in build.items:
		signature = signature * 31 + owned.index * 7 + owned.count
	if _signature.get(peer, -1) == signature and _held.has(peer):
		return
	_signature[peer] = signature
	# Keep the running timers of effects still held.
	var old: Array = _held.get(peer, [])
	var rows: Array[Held] = held_of(build)
	for row: Held in rows:
		for before: Held in old:
			if before.effect == row.effect:
				row.timer = before.timer
				row.source = before.source
	_held[peer] = rows


func _flag(enemies: EnemyManager, source: int, procs: bool, bonus: Vector4) -> void:
	if source >= enemies.proc_source.size():
		enemies.proc_source.resize(source + 1)
		enemies.source_bonus.resize(source + 1)
	enemies.proc_source[source] = 1 if procs else 0
	enemies.source_bonus[source] = bonus


func _hurt_around(at: Vector3, radius: float, damage: float, skip: int) -> void:
	var enemies: EnemyManager = world.enemies
	for j: int in WeaponSystem.enemies_near(enemies, at.x, at.z, radius):
		if j != skip:
			enemies.damage(j, damage)


## Everything within `radius` of the line from `a` to `b` (the Spagat).
func _hurt_along(a: Vector3, b: Vector3, radius: float, damage: float) -> void:
	var enemies: EnemyManager = world.enemies
	var mid := (a + b) * 0.5
	var half: float = Vector2(b.x - a.x, b.z - a.z).length() * 0.5
	var line := Vector2(b.x - a.x, b.z - a.z)
	var length_sq: float = maxf(line.length_squared(), 0.0001)
	for j: int in WeaponSystem.enemies_near(enemies, mid.x, mid.z, half + radius):
		var p := Vector2(enemies.pos_x[j] - a.x, enemies.pos_z[j] - a.z)
		var t: float = clampf(p.dot(line) / length_sq, 0.0, 1.0)
		if (p - line * t).length() <= radius + enemies.radius[j]:
			enemies.damage(j, damage)


func _nearest(x: float, z: float, radius: float, skip: Dictionary) -> int:
	var enemies: EnemyManager = world.enemies
	var best: int = -1
	var best_sq: float = INF
	for j: int in WeaponSystem.enemies_near(enemies, x, z, radius):
		if skip.has(j):
			continue
		var d_sq: float = (enemies.pos_x[j] - x) * (enemies.pos_x[j] - x) + (enemies.pos_z[j] - z) * (enemies.pos_z[j] - z)
		if d_sq < best_sq:
			best_sq = d_sq
			best = j
	return best


func _cue(which: RunEventCodec.Cue, at: Vector3) -> void:
	if _cues < balance.item_cue_budget:
		_cues += 1
		world.events.cue(which, at.x, at.z)
