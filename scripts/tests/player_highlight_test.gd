extends SceneTree
# 玩家着重显示：明亮轮廓 + 外发光 + 环绕光点；身体半径/缩放不变；桌面与触屏同逻辑。

const PlayerS := preload("res://scripts/player.gd")

var _failures := PackedStringArray()


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_highlight()
	if _failures.is_empty():
		print("PLAYER_HIGHLIGHT_OK")
		quit(0)
	else:
		for f in _failures:
			push_error("PLAYER_HIGHLIGHT_FAIL: %s" % f)
		quit(1)


func _test_highlight() -> void:
	# 三角色各建一只，半径取配置真值，不调用被测函数算期望
	var cfgs := [
		{"id": "ranger", "hp": 100.0, "speed": 220.0, "weapon": "w_dragon", "dmg_mult": 1.0, "radius": 16.0, "shape": "circle", "color": Color(0.35, 0.75, 1.0)},
		{"id": "brute", "hp": 140.0, "speed": 190.0, "weapon": "w_sawblade", "dmg_mult": 1.0, "radius": 19.0, "shape": "square", "color": Color(1.0, 0.55, 0.25)},
		{"id": "gunner", "hp": 80.0, "speed": 230.0, "weapon": "w_shotgun", "dmg_mult": 1.1, "radius": 13.0, "shape": "triangle", "color": Color(0.95, 0.85, 0.3)},
	]
	for cfg in cfgs:
		var pl: Node2D = PlayerS.new()
		pl.setup(cfg, 0)
		root.add_child(pl)
		await process_frame
		_expect(pl.has_highlight(), "%s has highlight" % cfg.id)
		_expect(is_equal_approx(pl.radius, float(cfg.radius)), "%s radius unchanged (got %s)" % [cfg.id, pl.radius])
		_expect(pl.highlight_spark_count() == 4, "%s has 4 orbit sparks (got %s)" % [cfg.id, pl.highlight_spark_count()])
		_expect(pl._outline != null and pl._outline.points.size() >= 3, "%s outline has shape points" % cfg.id)
		_expect(pl._outline.default_color.is_equal_approx(PlayerS.HIGHLIGHT_OUTLINE), "%s outline is bright highlight color" % cfg.id)
		_expect(pl._outline.width >= 2.5, "%s outline stroke visible" % cfg.id)
		_expect(pl._glow != null and pl._glow.color.a > 0.1, "%s glow is visible" % cfg.id)
		# 发光环略大于身体，但身体多边形尺度仍为 radius（碰撞/体型不变）
		var body_extent := 0.0
		for p in pl._shape_points():
			body_extent = maxf(body_extent, p.length())
		_expect(is_equal_approx(body_extent, float(cfg.radius)), "%s body extent == radius" % cfg.id)
		var glow_extent := 0.0
		for p in pl._glow.polygon:
			glow_extent = maxf(glow_extent, p.length())
		_expect(glow_extent > body_extent, "%s glow larger than body" % cfg.id)
		# 光点在环上：推进一帧后位置应绕半径外
		var before: Vector2 = pl._sparks.get_child(0).position
		pl._physics_process(0.05)
		var after: Vector2 = pl._sparks.get_child(0).position
		_expect(not before.is_equal_approx(after), "%s sparks orbit over time" % cfg.id)
		_expect(after.length() > float(cfg.radius), "%s sparks outside body" % cfg.id)
		# 缩放未被动过（Sprite/Poly 的根 scale 仍为 1）
		_expect(pl.scale.is_equal_approx(Vector2.ONE), "%s root scale unchanged" % cfg.id)
		pl.queue_free()
	await process_frame
	# 变异锚：若去掉轮廓色常量或 has_highlight，上面断言会失败


func _expect(c: bool, label: String) -> void:
	if not c:
		_failures.append(label)
