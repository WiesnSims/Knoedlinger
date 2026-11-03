class_name FrameStats
extends RefCounted
## Frame times, draw calls and time per system, for the F3 overlay and the automated perf runs.
## The first `warmup` seconds (shader compiles, first spawns) are not measured.

var warmup: float = 3.0
var elapsed: float = 0.0
var frame_ms: PackedFloat32Array = PackedFloat32Array()
var draw_calls_sum: float = 0.0
var draw_calls_max: int = 0

var _system_usec: Dictionary[String, int] = {}
var _second_frames: int = 0
var _second_time: float = 0.0
var _last_fps: float = 0.0


func is_measuring() -> bool:
	return elapsed >= warmup


func measured_seconds() -> float:
	return maxf(elapsed - warmup, 0.0)


func add_frame(delta: float) -> void:
	elapsed += delta
	_second_frames += 1
	_second_time += delta
	if _second_time >= 1.0:
		_last_fps = _second_frames / _second_time
		_second_frames = 0
		_second_time = 0.0
	if not is_measuring():
		return
	frame_ms.append(delta * 1000.0)
	var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	draw_calls_sum += draws
	draw_calls_max = maxi(draw_calls_max, draws)


func add_system(system: String, usec: int) -> void:
	if is_measuring():
		_system_usec[system] = _system_usec.get(system, 0) + usec


func last_fps() -> float:
	return _last_fps


func summary() -> Dictionary:
	var sorted: PackedFloat32Array = frame_ms.duplicate()
	sorted.sort()
	var frames: int = sorted.size()
	var total_ms: float = 0.0
	for ms: float in sorted:
		total_ms += ms
	var systems: Dictionary = {}
	for system: String in _system_usec:
		systems[system] = snappedf(_system_usec[system] / 1000.0 / maxi(frames, 1), 0.001)
	return {
		"frames": frames,
		"seconds": snappedf(measured_seconds(), 0.01),
		"fps_avg": snappedf(frames / maxf(total_ms / 1000.0, 0.001), 0.1),
		"frame_ms_p50": snappedf(_percentile(sorted, 0.5), 0.01),
		"frame_ms_p95": snappedf(_percentile(sorted, 0.95), 0.01),
		"frame_ms_p99": snappedf(_percentile(sorted, 0.99), 0.01),
		"frame_ms_max": snappedf(sorted[frames - 1] if frames > 0 else 0.0, 0.01),
		"draw_calls_avg": snappedf(draw_calls_sum / maxi(frames, 1), 0.1),
		"draw_calls_max": draw_calls_max,
		"system_ms_avg": systems,
	}


static func _percentile(sorted: PackedFloat32Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(int(q * (sorted.size() - 1)), 0, sorted.size() - 1)]
