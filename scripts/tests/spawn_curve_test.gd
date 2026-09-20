extends SceneTree

const SpawnCurveS := preload("res://scripts/spawn_curve.gd")
const PlayerS := preload("res://scripts/player.gd")

var _failures := PackedStringArray()


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var total_waves := 12
	_expect_close(SpawnCurveS.campaign_multiplier(1, total_waves), 1.2, "wave 1 uses 1.2x")
	_expect_close(SpawnCurveS.campaign_multiplier(2, total_waves), 1.2, "wave 2 uses 1.2x")

	var previous := 0.0
	for wave_number in range(1, total_waves + 1):
		var multiplier := SpawnCurveS.campaign_multiplier(wave_number, total_waves)
		_expect(multiplier >= previous, "campaign curve is monotonic at wave %d" % wave_number)
		if wave_number >= 9:
			_expect(multiplier >= 2.0, "late wave %d is at least 2x" % wave_number)
		previous = multiplier

	_expect(SpawnCurveS.scaled_density(8, 1.2) == 10, "opening density rounds 8 to 10")
	_expect(SpawnCurveS.scaled_density(32, 2.0) == 64, "late density reaches 64")
	_expect(SpawnCurveS.scaled_density(32, 2.3) == SpawnCurveS.MAX_ACTIVE_ENEMIES, "density obeys hard cap")
	_expect_close(SpawnCurveS.interval_for(12.0, 10), 1.2, "spawn interval follows target density")
	_expect_close(SpawnCurveS.interval_for(1.0, 64), SpawnCurveS.MIN_SPAWN_INTERVAL, "spawn interval obeys frame-safe floor")

	var player := PlayerS.new()
	player.weapon_id = "w_dragon"
	var base_knockback := player.hit_knockback_strength()
	player.weapon_id = "w_shotgun"
	var shotgun_knockback := player.hit_knockback_strength()
	_expect_close(base_knockback, 130.0, "non-shotgun knockback stays unchanged")
	_expect_close(shotgun_knockback, 155.0, "shotgun knockback is strengthened")
	_expect(shotgun_knockback > base_knockback and shotgun_knockback <= base_knockback * 1.25, "shotgun buff remains small")
	player.free()

	if _failures.is_empty():
		print("SPAWN_CURVE_OK opening=1.20 late_min=2.00 cap=64 shotgun_kb=155")
		quit(0)
	else:
		for failure in _failures:
			push_error("SPAWN_CURVE_FAIL: %s" % failure)
		quit(1)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _expect_close(actual: float, expected: float, label: String) -> void:
	if not is_equal_approx(actual, expected):
		_failures.append("%s (got %.3f, expected %.3f)" % [label, actual, expected])
