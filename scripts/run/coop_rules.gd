class_name CoopRules
extends RefCounted
## The host's co-op rules (GAME-DESIGN.md, "Co-op: Familienausflug"), on top of RunWorld's state:
##   - Downed, not dead: a knocked-down player waits coop_down_seconds; a teammate standing by for
##     revive_seconds, or any teammate's Knödl rolling over them ("Aufgweckt!"), wakes them. After
##     that they are out until the next Wirtshaus cash-in, which wakes everyone.
##   - Shared XP: Brösel go to the Knödl that eats them, every other player within
##     shared_xp_radius also gets shared_xp_share of that XP (no mass).
##   - Knödl-Pass: a Schupfn toward a teammate (aim cone) flies to them; they catch it and its mass
##     (above the start size) goes into their Knödl.
##   - Riesenknödl: two Knödl that roll into each other merge into one held by both strings, until
##     merge_seconds are up or one of the two presses Schupfn; a cash-in of it pays both.
##   - Familienstreit: at streit_minute one random player's Knödl tears loose and rolls off for
##     streit_seconds; a teammate touching it brings it back.
## Solo (one player) none of this happens; `--respawn=1` keeps its own respawn rule.

## A merge: primary peer -> partner peer, seconds left, the partner's share of the mass.
class Merge:
	extends RefCounted
	var primary: int = 0
	var partner: int = 0
	var left: float = 0.0
	var share: float = 0.5

var world: RunWorld
var balance: BalanceData
var merges: Array[Merge] = []
## Familienstreit: whose Knödl is loose (0 = nobody), seconds left, done for this run.
var streit_peer: int = 0
var streit_left: float = 0.0
var streit_done: bool = false
var _rng := RandomNumberGenerator.new()
var _merge_cooldowns: Dictionary[String, float] = {}
## Seconds each player has been in the run (no merge right at the spawn, where the Knödl all start
## side by side).
var _age: Dictionary[int, float] = {}
## Test hooks: `--streit_at=<s>` moves the Familienstreit; `--coop_drill=1` knocks the first
## client down at 10 s and rolls two Knödl into each other at 25 s (mp_test.ps1 -Coop).
var _streit_at: float = -1.0
var _drill: bool = false
var _drill_step: int = 0

const MERGE_MIN_AGE: float = 5.0


func _init(p_world: RunWorld, p_balance: BalanceData, seed_value: int) -> void:
	world = p_world
	balance = p_balance
	_rng.seed = seed_value * 17 + 3
	_streit_at = LaunchArgs.get_float("streit_at", -1.0)
	_drill = LaunchArgs.get_flag("coop_drill", false)


func active() -> bool:
	return world.players.size() > 1


func update(delta: float) -> void:
	for key: String in _merge_cooldowns.keys():
		_merge_cooldowns[key] -= delta
		if _merge_cooldowns[key] <= 0.0:
			_merge_cooldowns.erase(key)
	for peer: int in world.players:
		_age[peer] = _age.get(peer, 0.0) + delta
	if not active():
		_end_streit()
		while not merges.is_empty():
			split(merges[0], false)
		return
	if _drill:
		_update_drill()
	_update_revives(delta)
	_update_passes()
	_update_merges(delta)
	_update_streit(delta)


# --- Downed, not dead ----------------------------------------------------------------------------

func _update_revives(delta: float) -> void:
	for peer: int in world.states:
		var state: PlayerState = world.states[peer]
		if not state.downed or state.out or not world.players.has(peer):
			state.revive_progress = 0.0
			continue
		var at: Vector3 = world.players[peer].global_position
		# A teammate's Knödl rolling over them wakes them at once.
		var woken_by: int = 0
		for other: int in world.knodls:
			if other == peer or not world.states.has(other) or world.states[other].downed:
				continue
			var knodl: Knodl = world.knodls[other]
			if knodl.merged_away:
				continue
			if knodl.global_position.distance_to(at + Vector3(0.0, 0.4, 0.0)) < knodl.radius + 0.9:
				woken_by = other
				break
		if woken_by != 0:
			_revive(peer, woken_by, true)
			continue
		var helper: int = 0
		for other: int in world.players:
			var other_state: PlayerState = world.states.get(other)
			if other == peer or other_state == null or other_state.downed or other_state.choosing:
				continue
			var d := Vector2(world.players[other].global_position.x - at.x, world.players[other].global_position.z - at.z)
			if d.length() <= balance.revive_radius:
				helper = other
				break
		if helper != 0:
			state.revive_progress += delta / maxf(balance.revive_seconds, 0.01)
			if state.revive_progress >= 1.0:
				_revive(peer, helper, false)
		else:
			state.revive_progress = maxf(state.revive_progress - balance.revive_decay * delta, 0.0)


func _revive(peer: int, by: int, with_knodl: bool) -> void:
	world.states[peer].revive(balance.revive_hp, balance.revive_grace)
	var helper: PlayerState = world.states.get(by)
	if helper != null:
		helper.revives_given += 1
		if with_knodl:
			helper.knodl_revives.append(String(world.character_of(peer).id))
	world.events.toast("TOAST_AUFGWECKT" if with_knodl else "TOAST_WIEDER_AUF")
	var at: Vector3 = world.players[peer].global_position
	world.events.cue(RunEventCodec.Cue.SHOCKWAVE, at.x, at.z)
	print("[RUN] revive peer=%d by=%d knodl=%s t=%.1f" % [peer, by, with_knodl, world.run_time])


## A Wirtshaus cash-in: everyone knocked down (or out) is back up.
func wake_everyone() -> void:
	if not active():
		return
	var woke: bool = false
	for peer: int in world.states:
		if world.states[peer].downed:
			world.states[peer].revive(balance.revive_hp, balance.revive_grace)
			woke = true
	if woke:
		world.events.toast("TOAST_WIRT_WECKT")


## True while somebody can still play (the run is lost when everyone is down at once).
func anyone_standing() -> bool:
	for peer: int in world.states:
		if not world.states[peer].downed:
			return true
	return false


# --- Shared XP -----------------------------------------------------------------------------------

## XP that `peer`'s Knödl ate: everyone else close by gets their share (a merge partner gets all of it).
func share_xp(peer: int, xp: float) -> void:
	if not active() or xp <= 0.0 or not world.players.has(peer):
		return
	var partner: int = merge_partner(peer)
	var from: Vector3 = world.players[peer].global_position
	for other: int in world.states:
		if other == peer or not world.players.has(other) or world.states[other].out:
			continue
		if other == partner:
			world.states[other].add_xp(xp, balance, world.run_time)
			continue
		if world.players[other].global_position.distance_to(from) <= balance.shared_xp_radius:
			world.states[other].add_xp(xp * balance.shared_xp_share, balance, world.run_time)


# --- Knödl-Pass ----------------------------------------------------------------------------------

## The Schupfn direction: straight at a teammate inside the aim cone (a pass), else as asked.
## Returns [direction, teammate peer or 0].
func pass_aim(peer: int, wanted: Vector3) -> Array:
	if not active() or not world.players.has(peer):
		return [wanted, 0]
	var from: Vector3 = world.players[peer].global_position
	var direction: Vector3 = wanted
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		direction = world.players[peer].facing_direction()
	direction = direction.normalized()
	var best: int = 0
	var best_angle: float = deg_to_rad(balance.pass_cone_degrees)
	for other: int in world.players:
		var state: PlayerState = world.states.get(other)
		if other == peer or state == null or state.downed or state.choosing:
			continue
		var to: Vector3 = world.players[other].global_position - from
		to.y = 0.0
		if to.length() > balance.pass_range or to.length() < 2.0:
			continue
		var angle: float = direction.angle_to(to.normalized())
		if angle <= best_angle:
			best_angle = angle
			best = other
	if best == 0:
		return [wanted, 0]
	var aim: Vector3 = world.players[best].global_position - from
	aim.y = 0.0
	return [aim.normalized(), best]


func _update_passes() -> void:
	for peer: int in world.knodls:
		var knodl: Knodl = world.knodls[peer]
		if knodl.state != Knodl.State.THROWN or knodl.pass_target == 0 or knodl.throw_age < balance.pass_min_seconds:
			continue
		var target: int = knodl.pass_target
		var catcher: Player = world.players.get(target)
		var catcher_state: PlayerState = world.states.get(target)
		if catcher == null or catcher_state == null or catcher_state.downed:
			knodl.pass_target = 0
			continue
		var d: Vector3 = catcher.global_position + Vector3(0.0, 0.9, 0.0) - knodl.global_position
		if Vector2(d.x, d.z).length() > knodl.radius + balance.pass_catch_radius or absf(d.y) > knodl.radius + 2.0:
			continue
		var start: float = world.knodl_start_mass(knodl)
		var gift: float = knodl.knodl_mass - start
		var into: Knodl = _holding_knodl(target)
		if gift > 0.0 and into != null:
			into.add_knodl_mass(gift)
			catcher_state.best_knodl_mass = maxf(catcher_state.best_knodl_mass, into.knodl_mass)
			knodl.reset_knodl_mass(start)
		knodl.pass_target = 0
		knodl.reel_home()
		world.states[peer].passes += 1
		catcher_state.catches += 1
		world.events.toast("TOAST_PASS")
		print("[RUN] pass peer=%d to=%d mass=%.0f t=%.1f" % [peer, target, gift, world.run_time])


# --- Riesenknödl ---------------------------------------------------------------------------------

func merge_of(peer: int) -> Merge:
	for m: Merge in merges:
		if m.primary == peer or m.partner == peer:
			return m
	return null


## The other player of `peer`'s merge, or 0.
func merge_partner(peer: int) -> int:
	var m: Merge = merge_of(peer)
	if m == null:
		return 0
	return m.partner if m.primary == peer else m.primary


## The Knödl a player rolls right now: their own, or the merged one they hold.
func _holding_knodl(peer: int) -> Knodl:
	var m: Merge = merge_of(peer)
	return world.knodls.get(m.primary if m != null else peer)


func _update_merges(delta: float) -> void:
	for m: Merge in merges.duplicate():
		m.left -= delta
		var a: PlayerState = world.states.get(m.primary)
		var b: PlayerState = world.states.get(m.partner)
		if m.left <= 0.0 or a == null or b == null or a.downed or b.downed \
				or not world.knodls.has(m.primary) or not world.knodls.has(m.partner):
			split(m, false)
			continue
		# The hidden half travels inside the merged Knödl.
		world.knodls[m.partner].global_position = world.knodls[m.primary].global_position
	var peers: Array[int] = []
	for peer: int in world.knodls:
		peers.append(peer)
	for i: int in peers.size():
		for j: int in range(i + 1, peers.size()):
			_try_merge(peers[i], peers[j])


func _try_merge(a: int, b: int) -> void:
	if merge_of(a) != null or merge_of(b) != null or _merge_cooldowns.has(_pair(a, b)):
		return
	var sa: PlayerState = world.states.get(a)
	var sb: PlayerState = world.states.get(b)
	if sa == null or sb == null or sa.downed or sb.downed or a == streit_peer or b == streit_peer:
		return
	if _age.get(a, 0.0) < MERGE_MIN_AGE or _age.get(b, 0.0) < MERGE_MIN_AGE:
		return
	var ka: Knodl = world.knodls[a]
	var kb: Knodl = world.knodls[b]
	if ka.state == Knodl.State.LOOSE or kb.state == Knodl.State.LOOSE or ka.state == Knodl.State.REELING \
			or kb.state == Knodl.State.REELING:
		return
	# A pass in the air is no merge.
	if (ka.state == Knodl.State.THROWN and ka.pass_target != 0) or (kb.state == Knodl.State.THROWN and kb.pass_target != 0):
		return
	if ka.global_position.distance_to(kb.global_position) > ka.radius + kb.radius + 0.15:
		return
	if (ka.linear_velocity - kb.linear_velocity).length() < balance.merge_min_speed:
		return
	var primary: int = a if ka.knodl_mass >= kb.knodl_mass else b
	var partner: int = b if primary == a else a
	var big: Knodl = world.knodls[primary]
	var small: Knodl = world.knodls[partner]
	var m := Merge.new()
	m.primary = primary
	m.partner = partner
	m.left = balance.merge_seconds
	m.share = small.knodl_mass / maxf(big.knodl_mass + small.knodl_mass, 0.001)
	big.add_knodl_mass(small.knodl_mass)
	small.set_merged_away(true)
	big.co_holder = world.players[partner]
	if big.state == Knodl.State.THROWN:
		big.reel_home()
	merges.append(m)
	sa.merges += 1
	sb.merges += 1
	for s: PlayerState in [sa, sb]:
		s.best_knodl_mass = maxf(s.best_knodl_mass, big.knodl_mass)
	world.events.toast("TOAST_MERGE")
	var at: Vector3 = big.global_position
	world.events.cue(RunEventCodec.Cue.SHOCKWAVE, at.x, at.z)
	print("[RUN] merge primary=%d partner=%d mass=%.0f t=%.1f" % [primary, partner, big.knodl_mass, world.run_time])


## Back into two Knödl, each with its share (or both at their start size after a cash-in).
func split(m: Merge, emptied: bool) -> void:
	merges.erase(m)
	_merge_cooldowns[_pair(m.primary, m.partner)] = balance.merge_cooldown
	var big: Knodl = world.knodls.get(m.primary)
	var small: Knodl = world.knodls.get(m.partner)
	if big != null:
		big.co_holder = null
	if small == null:
		return
	var at: Vector3 = big.global_position if big != null else small.global_position
	var partner_player: Player = world.players.get(m.partner)
	var toward: Vector3 = (partner_player.global_position - at) if partner_player != null else Vector3.RIGHT
	toward.y = 0.0
	toward = toward.normalized() if toward.length_squared() > 0.01 else Vector3.RIGHT
	var total: float = big.knodl_mass if big != null else 0.0
	small.set_merged_away(false, at + toward * ((big.radius if big != null else 0.5) + 0.6))
	if emptied:
		small.reset_knodl_mass(world.knodl_start_mass(small))
		if big != null:
			big.reset_knodl_mass(world.knodl_start_mass(big))
	elif big != null:
		small.reset_knodl_mass(maxf(total * m.share, world.knodl_start_mass(small)))
		big.reset_knodl_mass(maxf(total - total * m.share, world.knodl_start_mass(big)))
	print("[RUN] split primary=%d partner=%d t=%.1f" % [m.primary, m.partner, world.run_time])


## Schupfn while merged lets go instead of throwing. True when it was a merge.
func schupfn_splits(peer: int) -> bool:
	var m: Merge = merge_of(peer)
	if m == null:
		return false
	split(m, false)
	return true


static func _pair(a: int, b: int) -> String:
	return "%d-%d" % [mini(a, b), maxi(a, b)]


# --- Familienstreit ------------------------------------------------------------------------------

func _update_streit(delta: float) -> void:
	if streit_peer == 0:
		var start: float = _streit_at if _streit_at >= 0.0 else balance.streit_minute * 60.0
		if streit_done or world.run_time < start or world.phase != RunWorld.Phase.RUNNING:
			return
		streit_done = true
		var candidates: Array[int] = []
		for peer: int in world.knodls:
			if not world.states[peer].downed:
				candidates.append(peer)
		if candidates.is_empty():
			return
		streit_peer = candidates[_rng.randi_range(0, candidates.size() - 1)]
		var m: Merge = merge_of(streit_peer)
		if m != null:
			split(m, false)
		var knodl: Knodl = world.knodls[streit_peer]
		var angle: float = _rng.randf() * TAU
		knodl.set_loose(Vector3(cos(angle), 0.0, sin(angle)), balance.streit_speed)
		streit_left = balance.streit_seconds
		world.events.toast("TOAST_FAMILIENSTREIT")
		print("[RUN] familienstreit peer=%d t=%.1f" % [streit_peer, world.run_time])
		return
	var knodl: Knodl = world.knodls.get(streit_peer)
	if knodl == null or knodl.state != Knodl.State.LOOSE:
		_end_streit()
		return
	streit_left -= delta
	# It wanders a little and turns back at the edge of the map.
	knodl.loose_direction = knodl.loose_direction.rotated(Vector3.UP, sin(world.run_time * 1.3) * delta * 0.8)
	var at: Vector3 = knodl.global_position
	var edge: float = world.map.half_size - 12.0
	if absf(at.x) > edge or absf(at.z) > edge:
		knodl.loose_direction = -Vector3(at.x, 0.0, at.z).normalized()
	for other: int in world.players:
		var state: PlayerState = world.states.get(other)
		if other == streit_peer or state == null or state.downed:
			continue
		var d: Vector3 = world.players[other].global_position - at
		if Vector2(d.x, d.z).length() <= knodl.radius + 1.2:
			state.streit_catches += 1
			world.events.toast("TOAST_STREIT_CAUGHT")
			_end_streit()
			return
	if streit_left <= 0.0:
		world.events.toast("TOAST_STREIT_OVER")
		_end_streit()


## Test hook (mp_test -Coop): makes sure a knock-down and a merge happen early in a short run.
func _update_drill() -> void:
	var clients: Array[int] = []
	for peer: int in world.players:
		if peer != NetworkManager.HOST_ID:
			clients.append(peer)
	if clients.is_empty():
		return
	clients.sort()
	var first: int = clients[0]
	if _drill_step == 0 and world.run_time >= 10.0 and world.states.has(first) and not world.states[first].downed:
		_drill_step = 1
		var state: PlayerState = world.states[first]
		state.hurt_timer = 0.0
		state.hp = 0.001
		if state.hurt(1.0, balance):
			world.on_downed(first)
		print("[RUN] drill: peer %d knocked down t=%.1f" % [first, world.run_time])
	elif _drill_step == 1 and world.run_time >= 25.0:
		_drill_step = 2
		var a: Knodl = world.knodls.get(NetworkManager.HOST_ID)
		var b: Knodl = world.knodls.get(first)
		if a != null and b != null and merge_of(NetworkManager.HOST_ID) == null and merge_of(first) == null \
				and not world.states[first].downed and not world.states[NetworkManager.HOST_ID].downed:
			_merge_cooldowns.erase(_pair(NetworkManager.HOST_ID, first))
			b.place_at(a.global_position + Vector3(a.radius + b.radius, 0.0, 0.0))
			b.linear_velocity = Vector3(-6.0, 0.0, 0.0)
			print("[RUN] drill: rolling Knödl %d into %d t=%.1f" % [first, NetworkManager.HOST_ID, world.run_time])


func _end_streit() -> void:
	if streit_peer == 0:
		return
	var knodl: Knodl = world.knodls.get(streit_peer)
	if knodl != null:
		knodl.reel_home()
	streit_peer = 0
