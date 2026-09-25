extends SceneTree

class TestPlayer:
	extends Node2D
	var radius := 16.0

	func take_damage(_amount: float, _source: Node2D) -> void:
		pass


const BASE_HP_OVERRIDE := 1400.0

var _failures := PackedStringArray()
var _completed_count := 0
var _completed_defeats := 0
var _completed_coin := 0
var _completed_xp := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var definitions: Array[BossDefinition] = [
		load("res://resources/bosses/charge_boss.tres") as BossDefinition,
		load("res://resources/bosses/spitter_boss.tres") as BossDefinition,
		load("res://resources/bosses/summoner_boss.tres") as BossDefinition,
	]
	_expect(not definitions.has(null), "all production Boss definitions load")
	if definitions.has(null):
		_finish()
		return

	var player := TestPlayer.new()
	player.position = Vector2(640.0, 360.0)
	root.add_child(player)
	var services := _make_services()

	for i in definitions.size():
		await _verify_rank_one(definitions[i], player, services, i)
	await _verify_rank_two(definitions[0], player, services)

	player.queue_free()
	await process_frame
	_finish()


func _verify_rank_one(
		definition: BossDefinition,
		player: Node2D,
		services: BossServices,
		index: int
) -> void:
	_reset_completion()
	var context := _make_context(player, 1, Vector2(480.0 + 160.0 * index, 140.0))
	var encounter := BossEncounterController.new()
	encounter.completed.connect(_on_completed)
	root.add_child(encounter)
	var result := encounter.start_single(definition, context, services)
	_expect(result == OK, "%s endless encounter starts" % definition.boss_id)
	var boss := encounter.primary_boss()
	_expect(boss != null, "%s creates a primary Boss" % definition.boss_id)
	if boss != null:
		_expect(boss.visual_contract_errors().is_empty(), "%s satisfies production visual contract" % definition.boss_id)
		_expect(boss.get_node_or_null("TelegraphLayer") != null, "%s exposes TelegraphLayer" % definition.boss_id)
		_expect_float(boss.max_hp, 6720.0, "%s rank 1 HP uses endless base override" % definition.boss_id)
		_expect_float(boss.hp, boss.max_hp, "%s starts at full HP" % definition.boss_id)
		_expect_float(boss.armor, definition.base_armor * 1.5 + 2.0, "%s armor policy" % definition.boss_id)
		_expect_float(boss.speed, definition.base_speed * 1.2, "%s speed policy" % definition.boss_id)
		_expect_float(boss.contact_damage, definition.base_contact_damage, "%s endless damage avoids campaign-only multiplier" % definition.boss_id)
		_expect(boss.coin == 25 and boss.xp == definition.reward_xp, "%s endless rewards" % definition.boss_id)
		_expect(boss.encounter_context.mode == BossEncounterContext.Mode.ENDLESS, "%s keeps endless mode" % definition.boss_id)
		_expect(boss.encounter_context.endless_rank == 1, "%s keeps endless rank" % definition.boss_id)
		boss.take_damage(999999.0, player)
	_expect(_completed_count == 1, "%s completes exactly once" % definition.boss_id)
	_expect(_completed_defeats == 1, "%s reports one defeated slot" % definition.boss_id)
	_expect(_completed_coin == 25 and _completed_xp == definition.reward_xp, "%s completion rewards remain exact" % definition.boss_id)
	await process_frame
	encounter.queue_free()
	await process_frame


func _verify_rank_two(definition: BossDefinition, player: Node2D, services: BossServices) -> void:
	_reset_completion()
	var encounter := BossEncounterController.new()
	encounter.completed.connect(_on_completed)
	root.add_child(encounter)
	var result := encounter.start_single(definition, _make_context(player, 2, Vector2(640.0, 140.0)), services)
	_expect(result == OK, "rank 2 endless encounter starts")
	var boss := encounter.primary_boss()
	_expect(boss != null, "rank 2 creates a primary Boss")
	if boss != null:
		_expect_float(boss.max_hp, 8960.0, "rank 2 HP advances exactly one endless step")
		boss.take_damage(999999.0, player)
	_expect(_completed_count == 1 and _completed_coin == 25, "rank 2 completes with stable reward")
	await process_frame
	encounter.queue_free()
	await process_frame


func _make_context(player: Node2D, rank: int, spawn_position: Vector2) -> BossEncounterContext:
	var context := BossEncounterContext.new()
	context.mode = BossEncounterContext.Mode.ENDLESS
	context.region_index = 2
	context.endless_rank = rank
	context.arena = Rect2(40.0, 40.0, 1200.0, 640.0)
	context.spawn_position = spawn_position
	context.player = player
	context.base_hp_override = BASE_HP_OVERRIDE
	context.rng.seed = 100 + rank
	return context


func _make_services() -> BossServices:
	var services := BossServices.new()
	services.spawn_enemy_projectile = _ignore_projectile
	services.spawn_minion = _ignore_minion
	services.living_minion_count = func() -> int: return 0
	return services


func _ignore_projectile(_pos: Vector2, _dir: Vector2, _speed: float, _damage: float) -> void:
	pass


func _ignore_minion(_pos: Vector2, _kind: String, _elite: bool) -> void:
	pass


func _reset_completion() -> void:
	_completed_count = 0
	_completed_defeats = 0
	_completed_coin = 0
	_completed_xp = 0


func _on_completed(defeated_count: int, reward_coin: int, reward_xp: int) -> void:
	_completed_count += 1
	_completed_defeats = defeated_count
	_completed_coin = reward_coin
	_completed_xp = reward_xp


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _expect_float(actual: float, expected: float, label: String) -> void:
	if not is_equal_approx(actual, expected):
		_failures.append("%s expected=%s actual=%s" % [label, expected, actual])


func _finish() -> void:
	if _failures.is_empty():
		print("ENDLESS_BOSS_OK")
		quit(0)
	else:
		for failure in _failures:
			push_error("ENDLESS_BOSS_FAIL: %s" % failure)
		quit(1)
