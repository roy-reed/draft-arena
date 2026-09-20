class_name SpawnCurve
extends RefCounted

# 战役密度曲线与运行时安全边界。Main 只负责提供当前全局普通波序号。
const OPENING_WAVES := 2
const OPENING_MULTIPLIER := 1.2
const MID_START_MULTIPLIER := 1.3
const MID_END_MULTIPLIER := 1.85
const LATE_START_MULTIPLIER := 2.0
const LATE_END_MULTIPLIER := 2.3
const ENDLESS_MULTIPLIER := LATE_END_MULTIPLIER
const MAX_ACTIVE_ENEMIES := 64
const MIN_SPAWN_INTERVAL := 0.16


static func campaign_multiplier(wave_number: int, total_waves: int) -> float:
	var safe_total := maxi(total_waves, 1)
	var current := clampi(wave_number, 1, safe_total)
	var opening_end := mini(OPENING_WAVES, safe_total)
	if current <= opening_end:
		return OPENING_MULTIPLIER

	var late_start := maxi(opening_end + 1, int(floor(float(safe_total) * 2.0 / 3.0)) + 1)
	if current < late_start:
		var mid_first := opening_end + 1
		var mid_last := late_start - 1
		var mid_t := 0.0 if mid_last <= mid_first else float(current - mid_first) / float(mid_last - mid_first)
		return lerpf(MID_START_MULTIPLIER, MID_END_MULTIPLIER, mid_t)

	var late_t := 0.0 if safe_total <= late_start else float(current - late_start) / float(safe_total - late_start)
	return lerpf(LATE_START_MULTIPLIER, LATE_END_MULTIPLIER, late_t)


static func scaled_density(base_cap: int, multiplier: float) -> int:
	return clampi(roundi(maxi(base_cap, 1) * maxf(multiplier, 1.0)), 1, MAX_ACTIVE_ENEMIES)


static func interval_for(spawn_window: float, target_density: int) -> float:
	return maxf(maxf(spawn_window, 0.0) / float(maxi(target_density, 1)), MIN_SPAWN_INTERVAL)
