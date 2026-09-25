extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var definition := _make_definition()
	var context := _make_context()
	var policy := BossScalingPolicy.new()
	var stats := policy.build_stats(definition, context)

	_expect_float(stats.max_hp, 840.0, "campaign max_hp")
	_expect_float(stats.armor, 2.0, "campaign armor")
	_expect_float(stats.speed, 72.0, "campaign speed")
	_expect_float(stats.contact_damage, 36.0, "campaign contact_damage")
	_expect(stats.reward_coin == 15, "campaign reward_coin")

	var stats_copy := stats.copy()
	stats_copy.max_hp = 1.0
	_expect_float(stats.max_hp, 840.0, "runtime stats copy isolation")

	var boss := BossBase.new()
	var configure_result := boss.configure(definition, context, stats, BossServices.new())
	_expect(configure_result == OK, "first configure succeeds")
	var before_ready := _snapshot(boss)
	root.add_child(boss)
	var after_ready := _snapshot(boss)
	_expect(before_ready == after_ready, "ready preserves configured combat values")
	_expect_float(boss.hp, boss.max_hp, "configured boss starts at full health")
	boss.queue_free()
	await process_frame

	var endless_context := _make_context()
	endless_context.mode = BossEncounterContext.Mode.ENDLESS
	endless_context.endless_rank = 1
	endless_context.base_hp_override = 1400.0
	var endless_stats := policy.build_stats(definition, endless_context)
	_expect_float(endless_stats.max_hp, 6720.0, "endless max_hp")
	_expect(endless_stats.reward_coin == 25, "endless reward_coin")
	context.player.free()
	endless_context.player.free()

	if _failures.is_empty():
		print("BOSS_FOUNDATION_OK")
		quit(0)
	else:
		for failure in _failures:
			push_error("BOSS_FOUNDATION_FAIL: %s" % failure)
		quit(1)


func _make_definition() -> BossDefinition:
	var packed_scene := PackedScene.new()
	var scene_root := Node2D.new()
	packed_scene.pack(scene_root)
	scene_root.free()

	var definition := BossDefinition.new()
	definition.boss_id = &"charge"
	definition.display_name = "Charge Boss"
	definition.scene = packed_scene
	definition.base_max_hp = 420.0
	definition.base_armor = 0.0
	definition.base_speed = 60.0
	definition.base_contact_damage = 18.0
	definition.gameplay_radius = 34.0
	definition.reward_coin = 15
	definition.reward_xp = 120
	return definition


func _make_context() -> BossEncounterContext:
	var context := BossEncounterContext.new()
	context.region_index = 0
	context.arena = Rect2(40.0, 40.0, 1200.0, 640.0)
	context.spawn_position = Vector2(640.0, 120.0)
	context.player = Node2D.new()
	return context


func _snapshot(boss: BossBase) -> Array:
	return [
		boss.max_hp,
		boss.hp,
		boss.armor,
		boss.speed,
		boss.contact_damage,
		boss.radius,
		boss.coin,
		boss.xp,
	]


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _expect_float(actual: float, expected: float, label: String) -> void:
	if not is_equal_approx(actual, expected):
		_failures.append("%s expected=%s actual=%s" % [label, expected, actual])
