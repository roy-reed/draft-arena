extends SceneTree
# 手游版 M3：空间网格与原线性扫描逐次等价；粒子对象池复用且参数与新建一致。
# 参考实现 _reference_first_hit 是原 bullet._check_hit 的逐行副本（不调用被测代码）。

const EnemyS := preload("res://scripts/enemy.gd")
const FXS := preload("res://scripts/fx.gd")

var _failures := PackedStringArray()
var _world: Node2D


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	EnemyGrid.enabled = true
	EnemyGrid.verify = false
	_world = Node2D.new()
	root.add_child(_world)
	await _test_random_equivalence()
	await _test_tie_break_and_lifecycle()
	await _test_physics_interleaved()
	await _test_boss_movement()
	_world.queue_free()
	await process_frame
	_expect(EnemyGrid.tracked_count() == 0, "grid empty after world freed (got %d)" % EnemyGrid.tracked_count())
	await _test_particle_pool()
	if _failures.is_empty():
		print("COLLISION_GRID_OK")
		quit(0)
	else:
		for f in _failures:
			push_error("COLLISION_GRID_FAIL: %s" % f)
		quit(1)


func _reference_first_hit(pos: Vector2, hit_list: Array) -> Node2D:
	for e in get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e in hit_list:
			continue
		if pos.distance_to(e.position) <= e.radius + 4.0:
			return e
	return null


func _spawn(pos: Vector2, r: float) -> Node2D:
	var e := EnemyS.new()
	e.radius = r
	e.position = pos
	_world.add_child(e)
	return e


func _test_random_equivalence() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261012
	var enemies: Array = []
	for i in 64:
		var r := 14.0 if rng.randf() < 0.85 else rng.randf_range(20.0, 48.0)  # 混入首领尺寸
		enemies.append(_spawn(Vector2(rng.randf_range(40, 1240), rng.randf_range(40, 680)), r))
	await process_frame
	var mismatch := 0
	var hits := 0
	var linear_checks := 0
	EnemyGrid.reset_stats()
	for step in 4000:
		# 每步随机移动一部分敌人（含跨格大位移与击退式瞬移），验证网格实时换格
		for k in 6:
			var e: Node2D = enemies[rng.randi_range(0, enemies.size() - 1)]
			if rng.randf() < 0.1:
				e.position = Vector2(rng.randf_range(0, 1280), rng.randf_range(0, 720))
			else:
				e.position += Vector2(rng.randf_range(-12, 12), rng.randf_range(-12, 12))
			EnemyGrid.moved(e)  # 约定：树内直接改敌人坐标须同帧通知网格（游戏内移动点均已遵守）
		var pos := Vector2(rng.randf_range(0, 1280), rng.randf_range(0, 720))
		if rng.randf() < 0.5:  # 一半查询贴着某个敌人，保证命中样本充足
			var t: Node2D = enemies[rng.randi_range(0, enemies.size() - 1)]
			pos = t.position + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(0, t.radius + 8)
		var excl: Array = []
		for k in rng.randi_range(0, 3):
			excl.append(enemies[rng.randi_range(0, enemies.size() - 1)])
		var expected := _reference_first_hit(pos, excl)
		linear_checks += get_nodes_in_group("enemies").size()
		var got := EnemyGrid.first_hit(self, pos, excl)
		if got != expected:
			mismatch += 1
		if expected != null:
			hits += 1
	_expect(mismatch == 0, "grid == reference on 4000 random queries (mismatches %d)" % mismatch)
	_expect(hits > 1000, "enough hit samples (%d)" % hits)
	_expect(EnemyGrid.checks * 5 < linear_checks, "grid does far fewer distance checks (%d vs <=%d)" % [EnemyGrid.checks, linear_checks])
	print("GRID_RANDOM queries=4000 hits=%d grid_checks=%d linear_upper=%d" % [hits, EnemyGrid.checks, linear_checks])
	for e in enemies:
		e.queue_free()
	await process_frame


func _test_tie_break_and_lifecycle() -> void:
	_expect(EnemyGrid.tracked_count() == 0 and is_zero_approx(EnemyGrid.max_radius), "grid empty and reach reset between tests")
	# 两个重叠敌人都命中时，取场景树中靠前的那个（原实现遍历组的顺序）
	var a := _spawn(Vector2(500, 300), 14.0)
	var b := _spawn(Vector2(505, 300), 14.0)
	await process_frame
	_expect(EnemyGrid.first_hit(self, Vector2(502, 300), []) == a, "tie -> earlier in tree (a)")
	_world.move_child(b, 0)  # 调整树顺序后应改为 b
	_expect(EnemyGrid.first_hit(self, Vector2(502, 300), []) == b, "tie follows tree order after move_child")
	_expect(EnemyGrid.first_hit(self, Vector2(502, 300), [b]) == a, "excluded enemy skipped")
	# 跨格移动（64px 格）
	a.position = Vector2(900, 600)
	EnemyGrid.moved(a)
	_expect(EnemyGrid.first_hit(self, Vector2(900, 600), [b]) == a, "moved enemy found in new cell")
	_expect(EnemyGrid.first_hit(self, Vector2(502, 300), [b]) == null, "moved enemy gone from old cell")
	# 连续两次移动（无人读取全局变换）也要跟上
	a.position = Vector2(100, 100)
	EnemyGrid.moved(a)
	a.position = Vector2(200, 650)
	EnemyGrid.moved(a)
	_expect(EnemyGrid.first_hit(self, Vector2(200, 650), [b]) == a, "consecutive moves tracked")
	# 兜底：未调用 moved 的外部改动，帧末 TRANSFORM_CHANGED 下发后也会换格
	a.position = Vector2(1000, 120)
	await process_frame
	_expect(EnemyGrid.first_hit(self, Vector2(1000, 120), [b]) == a, "TRANSFORM_CHANGED safety net updates by next frame")
	a.position = Vector2(200, 650)
	EnemyGrid.moved(a)
	# 移动父节点不影响本地坐标判定（与原实现一致：比较的是 position）
	_world.position = Vector2(37, -19)
	_expect(EnemyGrid.first_hit(self, Vector2(200, 650), [b]) == a, "parent shake keeps local-space lookup")
	_world.position = Vector2.ZERO
	# queue_free 当帧仍在组内：两边都仍能命中；下一帧两边都不再命中
	a.queue_free()
	_expect(EnemyGrid.first_hit(self, Vector2(200, 650), [b]) == _reference_first_hit(Vector2(200, 650), [b]), "queue_free same frame matches reference")
	await process_frame
	_expect(EnemyGrid.first_hit(self, Vector2(200, 650), [b]) == null, "freed enemy untracked")
	# 移出再加入场景树
	_world.remove_child(b)
	_expect(EnemyGrid.first_hit(self, Vector2(505, 300), []) == null, "removed from tree -> not hit")
	_world.add_child(b)
	_expect(EnemyGrid.first_hit(self, Vector2(505, 300), []) == b, "re-added -> tracked again")
	# 格子边界 + 命中余量：敌人在 x=63.9（第 0 格），查询点在其右侧 radius+3.9 处（第 1 格），仍应命中
	var edge := _spawn(Vector2(63.9, 300), 14.0)
	await process_frame
	_expect(EnemyGrid.first_hit(self, Vector2(63.9 + 17.9, 300), [b]) == edge, "hit pad reaches across cell boundary")
	_expect(EnemyGrid.first_hit(self, Vector2(63.9 + 18.1, 300), [b]) == null, "just beyond radius+4 misses")
	edge.queue_free()
	await process_frame
	# 半径大于此前所有敌人的新敌人（首领）
	var boss := _spawn(Vector2(800, 200), 60.0)
	_expect(EnemyGrid.first_hit(self, Vector2(800 + 62, 200), []) == boss, "large radius counted at registration (same frame)")
	await process_frame
	_expect(EnemyGrid.first_hit(self, Vector2(800 + 62, 200), []) == boss, "large radius reach covers neighbour cells")
	b.queue_free()
	boss.queue_free()
	await process_frame


# 真实物理帧：敌人自己追击移动（enemy._physics_process），查询节点穿插在敌人之间的不同树位置，
# 每个物理帧都与参考实现比对——覆盖“同一帧内部分敌人已移动、部分未移动”的顺序语义。
class Probe extends Node2D:
	var test: SceneTree
	var mismatches := 0
	var queries := 0
	var rng := RandomNumberGenerator.new()
	func _physics_process(_d: float) -> void:
		for i in 8:
			var p := Vector2(rng.randf_range(0, 1280), rng.randf_range(0, 720))
			var enemies := get_tree().get_nodes_in_group("enemies")
			if not enemies.is_empty() and i % 2 == 0:
				var t: Node2D = enemies[rng.randi_range(0, enemies.size() - 1)]
				p = t.position + Vector2(rng.randf_range(-18, 18), rng.randf_range(-18, 18))
			queries += 1
			if EnemyGrid.first_hit(get_tree(), p, []) != test._reference_first_hit(p, []):
				mismatches += 1

class FakePlayer extends Node2D:
	var radius := 16.0
	var t := 0.0
	func take_damage(_a: float, _f: Node2D) -> void:
		pass
	func _physics_process(d: float) -> void:
		t += d
		position = Vector2(640, 360) + Vector2(cos(t * 3.0), sin(t * 2.0)) * 300.0


func _test_physics_interleaved() -> void:
	var player := FakePlayer.new()
	_world.add_child(player)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var probes: Array = []
	for i in 48:
		if i % 12 == 0:
			var pr := Probe.new()
			pr.test = self
			pr.rng.seed = i
			_world.add_child(pr)
			probes.append(pr)
		var e := EnemyS.new()
		e.player = player
		e.speed = rng.randf_range(60.0, 900.0)  # 含高速，单帧跨格
		e.radius = 14.0
		e.position = Vector2(rng.randf_range(40, 1240), rng.randf_range(40, 680))
		e._spawn_guard = 999.0
		_world.add_child(e)
		if i % 5 == 0:
			e.kb = Vector2(rng.randf_range(-2000, 2000), rng.randf_range(-2000, 2000))  # 击退
	for f in 90:
		await physics_frame
	var q := 0
	var m := 0
	for pr in probes:
		q += pr.queries
		m += pr.mismatches
	_expect(q >= 1000, "physics probes ran (%d queries)" % q)
	_expect(m == 0, "grid == reference across interleaved physics frames (mismatches %d / %d)" % [m, q])
	for c in _world.get_children():
		c.queue_free()
	await process_frame


# 首领自己的位移代码（冲锋首领 dash、吐酸首领走位）同帧更新网格：每个子步后立刻查询并与参考比对
func _test_boss_movement() -> void:
	for path in ["res://resources/bosses/charge_boss.tres", "res://resources/bosses/spitter_boss.tres"]:
		var definition := load(path) as BossDefinition
		var context := BossEncounterContext.new()
		context.region_index = 0
		context.arena = Rect2(40.0, 40.0, 1200.0, 640.0)
		context.spawn_position = Vector2(100.0, 100.0)
		var player := FakePlayer.new()
		player.set_physics_process(false)
		player.position = Vector2(1150.0, 600.0)
		context.player = player
		context.rng.seed = 7
		var stats := BossScalingPolicy.new().build_stats(definition, context)
		var boss = definition.scene.instantiate()
		var services := BossServices.new()
		services.spawn_enemy_projectile = func(_p, _d, _s, _dmg): pass
		var cfg: int = boss.configure(definition, context, stats, services)
		_expect(cfg == OK, "%s configures" % path.get_file())
		_world.add_child(player)
		_world.add_child(boss)
		boss.set_physics_process(false)  # 由测试逐步驱动，避免与引擎物理帧交错
		var moved_cells := 0
		var m := 0
		var last := EnemyGrid.cell_of(boss.position)
		for i in 400:
			boss._physics_process(1.0 / 60.0)
			var c := EnemyGrid.cell_of(boss.position)
			if c != last:
				moved_cells += 1
				last = c
			for off in [Vector2.ZERO, Vector2(boss.radius + 2.0, 0), Vector2(0, -boss.radius - 3.0)]:
				var q: Vector2 = boss.position + off
				if EnemyGrid.first_hit(self, q, []) != _reference_first_hit(q, []):
					m += 1
		_expect(moved_cells >= 3, "%s crossed cells while moving (%d)" % [path.get_file(), moved_cells])
		_expect(m == 0, "%s movement keeps grid in sync within the frame (mismatches %d)" % [path.get_file(), m])
		boss.queue_free()
		player.queue_free()
		await process_frame


func _test_particle_pool() -> void:
	var fx: FX = FXS.new()
	root.add_child(fx)
	await process_frame
	FX.bursts_created = 0
	FX.bursts_spawned = 0
	for i in 30:
		FX.hit_spark(Vector2(i * 10, 50), Color(1, 0.9, 0.4))
	_expect(FX.bursts_created == 30 and fx.pool_busy_count() == 30, "first wave creates 30")
	await _secs(0.6)  # hit_spark lifetime 0.28s
	_expect(fx.pool_busy_count() == 0 and fx.pool_idle_count() == 30, "finished bursts return to pool (busy %d idle %d)" % [fx.pool_busy_count(), fx.pool_idle_count()])
	for round in 5:
		for i in 30:
			FX.death_burst(Vector2(i * 10, 80), Color(0.2, 0.4, 0.9), 14 + round)
		await _secs(0.9)  # death_burst lifetime 0.5s
	_expect(FX.bursts_created == 30, "reused across 5 rounds (created %d)" % FX.bursts_created)
	_expect(FX.bursts_spawned == 180, "spawned count 180 (got %d)" % FX.bursts_spawned)
	# 复用节点的参数与原实现新建时逐项一致
	FX.death_burst(Vector2(321, 123), Color(0.7, 0.1, 0.3), 23)
	var p: CPUParticles2D = null
	for c in fx.get_children():
		if c is CPUParticles2D and c.visible:
			p = c
	_expect(p != null, "active particle found")
	if p != null:
		_expect(p.one_shot and is_equal_approx(p.explosiveness, 1.0) and is_equal_approx(p.spread, 180.0), "fixed params")
		_expect(p.amount == 23 and is_equal_approx(p.lifetime, 0.5), "amount/lifetime")
		_expect(is_equal_approx(p.initial_velocity_min, 140.0) and is_equal_approx(p.initial_velocity_max, 340.0), "velocity")
		_expect(is_equal_approx(p.scale_amount_min, 5.0) and is_equal_approx(p.scale_amount_max, 9.0), "scale")
		_expect(p.gravity.is_equal_approx(Vector2(0, 260)) and p.color.is_equal_approx(Color(0.7, 0.1, 0.3)), "gravity/color")
		_expect(p.global_position.is_equal_approx(Vector2(321, 123)) and p.z_index == 20, "position/z")
		_expect(p.emitting, "reused particle is emitting")
	# 兜底回收：finished 未触发时 lifetime+1s 后回收
	if p != null:
		fx._tick_bursts(1.6)
		_expect(not p.visible and fx.pool_busy_count() == 0, "guard recycles after lifetime + 1s")
	# 空闲上限：同时 60 个，结束后最多留 48 个，其余释放
	for i in 60:
		FX.hit_spark(Vector2(i, i), Color.WHITE)
	await _secs(0.6)
	_expect(fx.pool_idle_count() == FX.POOL_MAX_IDLE, "idle capped at %d (got %d)" % [FX.POOL_MAX_IDLE, fx.pool_idle_count()])
	await process_frame
	var n := 0
	for c in fx.get_children():
		if c is CPUParticles2D:
			n += 1
	_expect(n == FX.POOL_MAX_IDLE, "excess particles freed (children %d)" % n)
	# 禁用时（smoke）不产生粒子
	fx.enabled = false
	var before := FX.bursts_spawned
	FX.hit_spark(Vector2.ZERO, Color.WHITE)
	_expect(FX.bursts_spawned == before, "disabled FX spawns nothing")
	fx.queue_free()
	await process_frame


func _secs(t: float) -> void:
	await create_timer(t).timeout


func _expect(c: bool, label: String) -> void:
	if not c:
		_failures.append(label)
