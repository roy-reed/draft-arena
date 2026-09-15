extends SceneTree

class TestPlayer:
	extends Node2D
	var radius := 16.0

	func take_damage(_amount: float, _source: Node2D) -> void:
		pass

var _failures := PackedStringArray()
var _health_samples: Array[Vector2] = []
var _spawned_count := 0
var _completed_count := 0
var _defeated_count := 0
var _reward_coin := 0
var _reward_xp := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var definition := load("res://resources/bosses/charge_boss.tres") as BossDefinition
	_expect(definition != null, "production definition loads")
	if definition == null:
		_finish()
		return
	var definition_before := _definition_snapshot(definition)

	var player := TestPlayer.new()
	player.position = Vector2(900.0, 300.0)
	root.add_child(player)
	var context := BossEncounterContext.new()
	context.region_index = 0
	context.arena = Rect2(40.0, 40.0, 1200.0, 640.0)
	context.spawn_position = Vector2(640.0, 120.0)
	context.player = player
	context.rng.seed = 11

	var encounter := BossEncounterController.new()
	encounter.boss_spawned.connect(func(_boss: BossBase): _spawned_count += 1)
	encounter.health_changed.connect(func(current: float, maximum: float): _health_samples.append(Vector2(current, maximum)))
	encounter.completed.connect(_on_completed)
	root.add_child(encounter)
	var result := encounter.start_single(definition, context, BossServices.new())
	_expect(result == OK, "encounter starts")
	_expect(encounter.total_count() == 1, "roster owns one member")
	_expect(encounter.living_count() == 1, "one member is alive")
	_expect(_spawned_count == 1, "spawn signal fires once")

	var boss := encounter.primary_boss()
	_expect(boss != null, "primary boss is available")
	if boss != null:
		_expect_float(boss.max_hp, 840.0, "production scaling is applied")
		_expect(not _health_samples.is_empty(), "initial HUD snapshot is emitted")
		if not _health_samples.is_empty():
			_expect(_health_samples[-1] == Vector2(840.0, 840.0), "initial HUD snapshot is exact")
		boss.take_damage(99999.0, player)

	_expect(encounter.living_count() == 0, "defeated member leaves living roster")
	_expect(encounter.primary_boss() == null, "primary boss clears after completion")
	_expect(_completed_count == 1, "completion fires exactly once")
	_expect(_defeated_count == 1, "completion reports defeated count")
	_expect(_reward_coin == 15, "completion aggregates coin reward")
	_expect(_reward_xp == 120, "completion aggregates XP reward")
	_expect(not _health_samples.is_empty() and _health_samples[-1] == Vector2(0.0, 840.0), "final HUD snapshot preserves total maximum")
	_expect(_definition_snapshot(definition) == definition_before, "runtime does not mutate definition")

	await process_frame
	encounter.queue_free()
	await process_frame
	await _run_multi_member_contract(definition, player)
	player.queue_free()
	await process_frame
	_finish()


func _run_multi_member_contract(definition: BossDefinition, player: Node2D) -> void:
	_health_samples.clear()
	_spawned_count = 0
	_completed_count = 0
	_defeated_count = 0
	_reward_coin = 0
	_reward_xp = 0

	var definitions: Array[BossDefinition] = [definition, definition]
	var contexts: Array[BossEncounterContext] = []
	for i in 2:
		var context := BossEncounterContext.new()
		context.region_index = 0
		context.arena = Rect2(40.0, 40.0, 1200.0, 640.0)
		context.spawn_position = Vector2(480.0 + 320.0 * i, 120.0)
		context.player = player
		context.rng.seed = 20 + i
		contexts.append(context)

	var encounter := BossEncounterController.new()
	encounter.boss_spawned.connect(func(_boss: BossBase): _spawned_count += 1)
	encounter.health_changed.connect(func(current: float, maximum: float): _health_samples.append(Vector2(current, maximum)))
	encounter.completed.connect(_on_completed)
	root.add_child(encounter)
	var result := encounter.start(definitions, contexts, BossServices.new())
	_expect(result == OK, "multi-member encounter starts")
	_expect(encounter.total_count() == 2 and encounter.living_count() == 2, "multi-member roster is complete")
	_expect(_spawned_count == 2, "multi-member spawn signals are complete")
	_expect(not _health_samples.is_empty() and _health_samples[-1] == Vector2(1680.0, 1680.0), "aggregate HUD starts at full health")

	var first := encounter.primary_boss()
	if first != null:
		first.take_damage(99999.0, player)
	_expect(encounter.living_count() == 1, "first defeat keeps encounter active")
	_expect(_completed_count == 0, "first defeat does not complete multi-member encounter")
	_expect(not _health_samples.is_empty() and _health_samples[-1] == Vector2(840.0, 1680.0), "aggregate HUD preserves maximum after first defeat")

	var second := encounter.primary_boss()
	if second != null:
		second.take_damage(99999.0, player)
	_expect(_completed_count == 1, "multi-member completion fires exactly once")
	_expect(_defeated_count == 2 and _reward_coin == 30 and _reward_xp == 240, "multi-member rewards aggregate exactly once")
	_expect(not _health_samples.is_empty() and _health_samples[-1] == Vector2(0.0, 1680.0), "aggregate HUD reaches zero without shrinking")

	await process_frame
	encounter.queue_free()
	await process_frame


func _on_completed(defeated_count: int, reward_coin: int, reward_xp: int) -> void:
	_completed_count += 1
	_defeated_count = defeated_count
	_reward_coin = reward_coin
	_reward_xp = reward_xp


func _definition_snapshot(definition: BossDefinition) -> Array:
	return [
		definition.base_max_hp,
		definition.base_armor,
		definition.base_speed,
		definition.base_contact_damage,
		definition.gameplay_radius,
		definition.reward_coin,
		definition.reward_xp,
	]


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _expect_float(actual: float, expected: float, label: String) -> void:
	if not is_equal_approx(actual, expected):
		_failures.append("%s expected=%s actual=%s" % [label, expected, actual])


func _finish() -> void:
	if _failures.is_empty():
		print("BOSS_ENCOUNTER_OK")
		quit(0)
	else:
		for failure in _failures:
			push_error("BOSS_ENCOUNTER_FAIL: %s" % failure)
		quit(1)
