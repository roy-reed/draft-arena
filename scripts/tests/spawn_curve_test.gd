extends SceneTree

const SpawnCurveS := preload("res://scripts/spawn_curve.gd")
const PlayerS := preload("res://scripts/player.gd")

var _failures := PackedStringArray()
var _captured_bullet_origin := Vector2.ZERO


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
	_expect(SpawnCurveS.scaled_density(32, 2.3) == 64, "density obeys hard cap of 64 (GDD)")
	_expect(SpawnCurveS.campaign_density(8, 1, total_waves) == 10, "campaign density shares multiplier and rounding")
	_expect_close(SpawnCurveS.interval_for(12.0, 10), 1.2, "spawn interval follows target density")
	# 期望值取自 GDD「最短刷怪间隔 0.16s」，不引用被测常量，避免常量改动后测试仍自洽通过
	const DESIGN_MIN_SPAWN_INTERVAL := 0.16
	_expect_close(SpawnCurveS.interval_for(1.0, 64), DESIGN_MIN_SPAWN_INTERVAL, "spawn interval obeys frame-safe floor (0.16s)")
	_expect_close(SpawnCurveS.interval_for(1.6, 10), DESIGN_MIN_SPAWN_INTERVAL, "interval exactly at floor stays 0.16s")
	_expect_close(SpawnCurveS.interval_for(1.7, 10), 0.17, "interval just above floor is not clamped")
	_expect_close(SpawnCurveS.interval_for(-5.0, 10), DESIGN_MIN_SPAWN_INTERVAL, "negative window clamps to floor")

	var shaken_parent := Node2D.new()
	shaken_parent.position = Vector2(37.0, -19.0)
	root.add_child(shaken_parent)
	var player := PlayerS.new()
	player.position = Vector2(120.0, 80.0)
	shaken_parent.add_child(player)
	player.weapon_id = "w_dragon"
	player.bullet_spawner = Callable(self, "_capture_bullet")
	player._fire_dir(Vector2.RIGHT, 1.0, 0, null)
	_expect_close(_captured_bullet_origin.x, player.global_position.x, "player bullet keeps global x under parent shake")
	_expect_close(_captured_bullet_origin.y, player.global_position.y, "player bullet keeps global y under parent shake")
	var base_knockback := player.hit_knockback_strength()
	player.weapon_id = "w_shotgun"
	var shotgun_knockback := player.hit_knockback_strength()
	_expect_close(base_knockback, 130.0, "non-shotgun knockback stays unchanged")
	_expect_close(shotgun_knockback, 155.0, "shotgun knockback is strengthened")
	_expect(shotgun_knockback > base_knockback and shotgun_knockback <= base_knockback * 1.25, "shotgun buff remains small")
	shaken_parent.free()

	if _failures.is_empty():
		print("SPAWN_CURVE_OK opening=1.20 late_min=2.00 cap=64 shotgun_kb=155")
		quit(0)
	else:
		for failure in _failures:
			push_error("SPAWN_CURVE_FAIL: %s" % failure)
		quit(1)


func _capture_bullet(pos: Vector2, _dir: Vector2, _damage: float, _pierce: int, _bounce: int, _from_player: Node2D) -> void:
	_captured_bullet_origin = pos


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _expect_close(actual: float, expected: float, label: String) -> void:
	if not is_equal_approx(actual, expected):
		_failures.append("%s (got %.3f, expected %.3f)" % [label, actual, expected])
