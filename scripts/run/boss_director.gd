class_name BossDirector
extends RefCounted
## Host: runs the bosses of a run (GAME-DESIGN.md: Oberkrampus at 5:00 and 10:00, the Hofrat der
## Unterwelt behind the gate). A boss's body is a "controlled" slot in EnemyManager, so weapons, the
## Knödl and snapshots handle it like any enemy; this moves it toward the nearest player, plays its
## attacks one after another (as HazardField marks) and dashes it along a charge line when the
## charge hits.

const DASH_SECONDS: float = 0.4
## A boss stops walking this far from its target (it is big).
const KEEP_DISTANCE: float = 2.2
## A whirlwind moves the loose Brösel this often (each move goes to the clients).
const SWIRL_SECONDS: float = 0.25


class Active:
	extends RefCounted
	## Index into BossDirector.list (also on the wire).
	var index: int = 0
	var data: BossData
	var slot: int = -1
	var pause: float = 2.0
	var waiting: float = 0.0
	var next_attack: int = 0
	var dash_x: float = 0.0
	var dash_z: float = 0.0
	var dash_time: float = 0.0
	var last_x: float = 0.0
	var last_z: float = 0.0


var balance: BalanceData
var enemies: EnemyManager
var hazards: HazardField
## Every boss this run can have: the wave's mini-bosses in order, then the final boss.
var list: Array[BossData] = []
var active: Array[Active] = []
## Toast keys to show everyone (attack names) since the last take.
var toasts: PackedStringArray = PackedStringArray()

## Host: the loose Brösel a whirlwind boss pulls in and flings out.
var brosel: BroselField

var _type_index: Dictionary[BossData, int] = {}
var _swirl_timer: float = 0.0


func _init(p_balance: BalanceData, p_enemies: EnemyManager, p_hazards: HazardField, wave: WaveData) -> void:
	balance = p_balance
	enemies = p_enemies
	hazards = p_hazards
	for entry: WaveBoss in wave.bosses:
		list.append(entry.boss)
	if wave.final_boss != null:
		list.append(wave.final_boss)
	for boss: BossData in list:
		_type_index[boss] = wave.enemies.find(boss.enemy)


## Brings boss `index` in at (x, z) with its escort. `players` scales its HP (co-op).
func spawn(index: int, x: float, z: float, players: int) -> Active:
	var data: BossData = list[index]
	var t: int = _type_index.get(data, -1)
	if t < 0:
		push_warning("Boss %s has no body in the wave's enemy list." % data.id)
		return null
	var slot: int = enemies.spawn_at(t, x, z, true)
	if slot < 0:
		return null
	var hp: float = data.max_hp * (1.0 + balance.coop_boss_hp_per_player * maxi(players - 1, 0))
	enemies.hp[slot] = hp
	enemies.max_hp[slot] = hp
	var boss := Active.new()
	boss.index = index
	boss.data = data
	boss.slot = slot
	boss.pause = 2.5
	boss.last_x = x
	boss.last_z = z
	active.append(boss)
	if data.escort != null:
		var escort: int = enemies.types.find(data.escort)
		for k: int in data.escort_count:
			var angle: float = TAU * k / maxi(data.escort_count, 1)
			enemies.spawn_at(escort, x + cos(angle) * 3.5, z + sin(angle) * 3.5)
	return boss


## Moves and fights (only while `fighting`: at Sperrstund' they stand and wait). `targets` are the
## players bosses may go for. Returns the bosses that died since the last update.
func update(delta: float, targets: PackedVector3Array, fighting: bool = true) -> Array[Active]:
	var beaten: Array[Active] = []
	var k: int = 0
	while k < active.size():
		var boss: Active = active[k]
		if enemies.alive[boss.slot] == 0 or enemies.controlled[boss.slot] == 0:
			beaten.append(boss)
			active.remove_at(k)
			continue
		if fighting:
			_think(boss, delta, targets)
			if boss.data.pull_radius > 0.0:
				_pull(boss, delta)
		boss.last_x = enemies.pos_x[boss.slot]
		boss.last_z = enemies.pos_z[boss.slot]
		k += 1
	return beaten


## The pull of every whirlwind boss on a Knödl at `at` (m/s^2, for Knodl.wind).
func pull_on(at: Vector3) -> Vector3:
	var push := Vector3.ZERO
	for boss: Active in active:
		if boss.data.pull_radius <= 0.0:
			continue
		var dx: float = enemies.pos_x[boss.slot] - at.x
		var dz: float = enemies.pos_z[boss.slot] - at.z
		var d: float = sqrt(dx * dx + dz * dz)
		if d > 1.0 and d < boss.data.pull_radius:
			push += Vector3(dx, 0.0, dz) / d * boss.data.pull_knodl * (1.0 - d / boss.data.pull_radius * 0.5)
	return push


## A mark hit: a boss's charge line sends the boss along it (once per attack).
func on_hit(h: HazardField.Hazard) -> void:
	if h.attack == null or not h.attack.dash or h.shape != AttackData.Shape.LINE:
		return
	for boss: Active in active:
		if boss.slot == h.source and boss.dash_time <= 0.0:
			boss.dash_x = sin(h.angle) * h.length / DASH_SECONDS
			boss.dash_z = cos(h.angle) * h.length / DASH_SECONDS
			boss.dash_time = DASH_SECONDS
			enemies.yaw[boss.slot] = h.angle


## Per target, the damage of a boss touching them this frame.
func touch_damage(targets: PackedVector3Array, out: PackedFloat32Array) -> void:
	for boss: Active in active:
		var x: float = enemies.pos_x[boss.slot]
		var z: float = enemies.pos_z[boss.slot]
		var reach: float = enemies.radius[boss.slot] + balance.player_radius
		var gy: float = enemies.ground_at(x, z)
		for t: int in targets.size():
			var p: Vector3 = targets[t]
			if (p.x - x) * (p.x - x) + (p.z - z) * (p.z - z) < reach * reach and absf(p.y - gy) < balance.enemy_contact_height + 1.0:
				out[t] = maxf(out[t], boss.data.enemy.contact_damage)


func is_boss_slot(slot: int) -> bool:
	for boss: Active in active:
		if boss.slot == slot:
			return true
	return false


func take_toasts() -> PackedStringArray:
	var out: PackedStringArray = toasts
	toasts = PackedStringArray()
	return out


func _think(boss: Active, delta: float, targets: PackedVector3Array) -> void:
	var slot: int = boss.slot
	var x: float = enemies.pos_x[slot]
	var z: float = enemies.pos_z[slot]
	if boss.dash_time > 0.0:
		boss.dash_time -= delta
		enemies.shove(slot, x + boss.dash_x * delta, z + boss.dash_z * delta)
		return
	if targets.is_empty():
		return
	var best: int = 0
	var best_sq: float = INF
	for t: int in targets.size():
		var d_sq: float = (targets[t].x - x) * (targets[t].x - x) + (targets[t].z - z) * (targets[t].z - z)
		if d_sq < best_sq:
			best_sq = d_sq
			best = t
	var tx: float = targets[best].x
	var tz: float = targets[best].z
	var distance: float = sqrt(best_sq)
	if distance > 0.01:
		enemies.yaw[slot] = atan2(tx - x, tz - z)
	if boss.waiting > 0.0:
		# Standing still while its marks fill up.
		boss.waiting -= delta
		return
	if distance > KEEP_DISTANCE:
		var step: float = minf(boss.data.speed * delta, distance - KEEP_DISTANCE)
		enemies.shove(slot, x + (tx - x) / distance * step, z + (tz - z) / distance * step)
	boss.pause -= delta
	if boss.pause > 0.0 or boss.data.attacks.is_empty():
		return
	var attack: AttackData = boss.data.attacks[boss.next_attack % boss.data.attacks.size()]
	if distance > attack.range:
		return
	boss.next_attack += 1
	hazards.start_attack(attack, enemies.pos_x[slot], enemies.pos_z[slot], tx, tz, slot)
	if attack.aim == AttackData.Aim.SPIRAL and boss.data.fling_speed > 0.0:
		_fling(boss, attack.spread)
	if attack.toast_key != "":
		toasts.append(attack.toast_key)
	boss.waiting = attack.telegraph + 0.2
	var enraged: bool = enemies.hp[slot] < enemies.max_hp[slot] * boss.data.enraged_below
	boss.pause = attack.telegraph + boss.data.attack_pause * (boss.data.enraged_pause_mult if enraged else 1.0)


## Der Sturm: the crowd within its pull_radius swirls in toward it (and round it), Brösel too.
func _pull(boss: Active, delta: float) -> void:
	var cx: float = enemies.pos_x[boss.slot]
	var cz: float = enemies.pos_z[boss.slot]
	var radius: float = boss.data.pull_radius
	var found: int = enemies.grid.query(cx, cz, radius)
	for k: int in found:
		var i: int = enemies.grid.results[k]
		if enemies.alive[i] == 0 or enemies.controlled[i] != 0:
			continue
		var dx: float = cx - enemies.pos_x[i]
		var dz: float = cz - enemies.pos_z[i]
		var d: float = sqrt(dx * dx + dz * dz)
		if d < 2.5 or d > radius:
			continue
		var step: float = boss.data.pull_speed * delta * enemies.types[enemies.type[i]].knockback_factor
		enemies.shove(i, enemies.pos_x[i] + (dx + dz * 0.6) / d * step, enemies.pos_z[i] + (dz - dx * 0.6) / d * step)
	if brosel != null:
		_swirl_timer -= delta
		if _swirl_timer <= 0.0:
			_swirl_timer = SWIRL_SECONDS
			brosel.swirl(cx, cz, radius, boss.data.pull_speed * SWIRL_SECONDS)


## Der Sturm lets go: what it pulled in flies out to where its spiral of marks lands.
func _fling(boss: Active, reach: float) -> void:
	var cx: float = enemies.pos_x[boss.slot]
	var cz: float = enemies.pos_z[boss.slot]
	var inner: float = boss.data.pull_radius * 0.5
	var found: int = enemies.grid.query(cx, cz, inner)
	for k: int in found:
		var i: int = enemies.grid.results[k]
		if enemies.alive[i] == 0 or enemies.controlled[i] != 0:
			continue
		var dx: float = enemies.pos_x[i] - cx
		var dz: float = enemies.pos_z[i] - cz
		var d: float = maxf(sqrt(dx * dx + dz * dz), 0.1)
		enemies.kb_x[i] += dx / d * boss.data.fling_speed
		enemies.kb_z[i] += dz / d * boss.data.fling_speed
	if brosel != null:
		brosel.fling(cx, cz, inner, reach)
