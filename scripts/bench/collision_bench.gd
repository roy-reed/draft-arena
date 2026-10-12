extends SceneTree
# 性能基准（不在 CI 中运行）：64 个追击敌人 + 每帧 6 发子弹，外加每帧 4 次死亡爆裂粒子。
# 用法：godot --headless --fixed-fps 60 --path . --script res://scripts/bench/collision_bench.gd [-- --legacy-collision]
# 输出 BENCH 行：每帧耗时（平均/p95）、每帧距离判定次数、粒子节点新建数、结果摘要（同一输入应完全相同）。
# 兼容 M3 之前的代码（没有 enemy_grid.gd 时按原实现运行），用于前后对比。

const EnemyS := preload("res://scripts/enemy.gd")
const BulletS := preload("res://scripts/bullet.gd")
const FXS := preload("res://scripts/fx.gd")
const FRAMES := 900
const WARMUP := 60

class FakePlayer extends Node2D:
	var radius := 16.0
	var t := 0.0
	var last_crit := false
	func take_damage(_a: float, _f: Node2D) -> void:
		pass
	func _physics_process(d: float) -> void:
		t += d
		position = Vector2(640, 360) + Vector2(cos(t * 1.3), sin(t * 0.9)) * 220.0

var _world: Node2D
var _player: FakePlayer
var _enemies: Array = []
var _rng := RandomNumberGenerator.new()
var _frame_us := PackedInt64Array()
var _particles_created := 0
var _grid = null


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var legacy := "--legacy-collision" in OS.get_cmdline_user_args()
	if ResourceLoader.exists("res://scripts/enemy_grid.gd"):
		_grid = load("res://scripts/enemy_grid.gd")
		_grid.enabled = not legacy
		_grid.reset_stats()
	node_added.connect(func(n): if n is CPUParticles2D or n is Timer: _particles_created += 1)
	_rng.seed = 1234
	seed(1234)
	_world = Node2D.new()
	root.add_child(_world)
	var fx = FXS.new()
	_world.add_child(fx)
	_player = FakePlayer.new()
	_world.add_child(_player)
	for i in 64:
		var e := EnemyS.new()
		e.player = _player
		e.max_hp = 1e12
		e.speed = _rng.randf_range(70.0, 140.0)
		e.radius = 14.0 if i % 8 else 20.0
		e.position = Vector2(_rng.randf_range(40, 1240), _rng.randf_range(40, 680))
		e._spawn_guard = 1e9
		_world.add_child(e)
		_enemies.append(e)
	var ang := 0.0
	var last := Time.get_ticks_usec()
	_particles_created = 0
	for f in FRAMES + WARMUP:
		for k in 6:
			ang += 0.37
			var b := BulletS.new()
			b.dir = Vector2.RIGHT.rotated(ang)
			b.dmg = 1.0
			b.owner_player = _player
			b.position = _player.position
			_world.add_child(b)
		for k in 4:
			FX.death_burst(Vector2(_rng.randf_range(40, 1240), _rng.randf_range(40, 680)), Color(1, 0.4, 0.3), 24)
		await physics_frame
		var now := Time.get_ticks_usec()
		if f >= WARMUP:
			_frame_us.append(now - last)
		last = now
	var digest := 0
	var hp_sum := 0.0
	for e in _enemies:
		digest = hash([digest, e.position.round(), e.hp])
		hp_sum += 1e12 - e.hp
	var sorted := _frame_us.duplicate()
	sorted.sort()
	var total := 0
	for v in sorted:
		total += v
	var checks := -1
	var queries := -1
	var mode := "pre-m3-linear"
	if _grid != null:
		checks = _grid.checks
		queries = _grid.queries
		mode = "linear" if legacy else "grid"
	print("BENCH mode=%s frames=%d frame_avg_us=%d frame_p95_us=%d checks_per_frame=%s queries_per_frame=%s bullets_alive=%d particle_nodes_created=%d damage_total=%d digest=%08x" % [
		mode, FRAMES, total / sorted.size(), sorted[int(sorted.size() * 0.95)],
		("%.1f" % (float(checks) / (FRAMES + WARMUP))) if checks >= 0 else "n/a",
		("%.1f" % (float(queries) / (FRAMES + WARMUP))) if queries >= 0 else "n/a",
		get_nodes_in_group("bullets").size(), _particles_created, int(hp_sum), digest & 0xffffffff])
	quit(0)
