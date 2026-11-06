class_name DamageLedger
extends RefCounted
## Every player's damage so far by weapon, item, Knödl and extras (1.4 build view, DECISIONS 6.8),
## on every machine. The host counts (EnemyManager.dealt per source) and sends the totals about once
## a second as DAMAGE run events; everyone keeps one sample per second for the DPS of the last 30 s.

enum Kind { WEAPON, ITEM, KNODL, EXTRA }

## Seconds the measured DPS looks back.
const WINDOW: float = 30.0

## "peer|kind|index" -> total damage, procs, and the samples (time, total), oldest first.
var _totals: Dictionary[String, float] = {}
var _procs: Dictionary[String, int] = {}
var _samples: Dictionary[String, PackedVector2Array] = {}


static func key(peer: int, kind: Kind, index: int) -> String:
	return "%d|%d|%d" % [peer, kind, index]


func record(peer: int, kind: int, index: int, total: float, procs: int, run_time: float) -> void:
	var k: String = key(peer, kind as Kind, index)
	_totals[k] = total
	_procs[k] = procs
	var samples: PackedVector2Array = _samples.get(k, PackedVector2Array())
	samples.append(Vector2(run_time, total))
	while samples.size() > 2 and samples[1].x < run_time - WINDOW:
		samples.remove_at(0)
	_samples[k] = samples


func total(peer: int, kind: Kind, index: int) -> float:
	return _totals.get(key(peer, kind, index), 0.0)


func procs(peer: int, kind: Kind, index: int) -> int:
	return _procs.get(key(peer, kind, index), 0)


## Damage per second over the last WINDOW seconds (or since the source started, if later), as of
## `run_time`: nothing new since the last sample counts as nothing dealt.
func recent_dps(peer: int, kind: Kind, index: int, run_time: float) -> float:
	var samples: PackedVector2Array = _samples.get(key(peer, kind, index), PackedVector2Array())
	if samples.size() < 2:
		return 0.0
	var first: Vector2 = samples[0]
	var last: Vector2 = samples[samples.size() - 1]
	var span: float = maxf(run_time - first.x, 1.0)
	return (last.y - first.y) / minf(span, WINDOW + 1.0)


func clear() -> void:
	_totals.clear()
	_procs.clear()
	_samples.clear()
