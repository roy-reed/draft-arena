extends SceneTree

class TestPlayer:
	extends Node2D
	var radius := 16.0

	func take_damage(_amount: float, _source: Node2D) -> void:
		pass


var _failures := PackedStringArray()
var _spawns: Array[Dictionary] = []
var _living_minions := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var definition := load("res://resources/bosses/summoner_boss.tres") as BossDefinition
	_expect(definition != null, "production summoner definition loads")
	if definition == null:
		_finish()
		return

	var player := TestPlayer.new()
	player.position = Vector2(640.0, 360.0)
	root.add_child(player)
	var context := BossEncounterContext.new()
	context.region_index = 2
	context.arena = Rect2(40.0, 40.0, 1200.0, 640.0)
	context.spawn_position = Vector2(640.0, 160.0)
	context.player = player
	context.rng.seed = 73

	var services := BossServices.new()
	services.spawn_minion = _record_spawn
	services.living_minion_count = func() -> int: return _living_minions
	_expect(services.validate([&"spawn_minion", &"living_minion_count"]).is_empty(), "summoner services validate")
	_expect(BossServices.new().validate([&"spawn_minion", &"living_minion_count"]).size() == 2, "missing summoner services are rejected")

	var encounter := BossEncounterController.new()
	encounter.position = Vector2(137.0, 91.0)
	root.add_child(encounter)
	var result := encounter.start_single(definition, context, services)
	_expect(result == OK, "production encounter starts")
	var boss := encounter.primary_boss() as SummonerBoss
	_expect(boss != null, "encounter creates SummonerBoss")
	if boss == null:
		encounter.queue_free()
		player.queue_free()
		await process_frame
		_finish()
		return

	_expect_float(boss.max_hp, 2800.0, "campaign max_hp")
	_expect_float(boss.hp, 2800.0, "campaign current hp")
	_expect_float(boss.armor, 2.0, "campaign armor")
	_expect_float(boss.speed, 45.6, "campaign speed")
	_expect_float(boss.contact_damage, 16.0, "campaign contact_damage")
	_expect(boss.coin == 15 and boss.xp == 120, "campaign rewards")
	_expect(boss.required_services() == [&"spawn_minion", &"living_minion_count"], "required service contract")
	_expect(boss.visual_contract_errors().is_empty(), "visual semantic contract")
	_expect(boss.find_children("*", "Line2D", true, false).is_empty(), "scene contains no laser line")
	_expect(not _has_laser_property(boss), "boss exposes no legacy laser state")

	boss.set_physics_process(false)
	boss.speed = 0.0
	_living_minions = 0
	_spawns.clear()
	boss._summon_n = 0
	boss._summon_t = SummonerBoss.INITIAL_SUMMON_DELAY
	boss._physics_process(1.9)
	_expect(_spawns.is_empty(), "initial summon waits for the full delay")
	boss._physics_process(0.11)
	_expect(_spawns.size() == 2, "initial delay creates one pair")
	_expect(_spawn_kinds(0) == [&"melee", &"ranged"], "pair contains melee and ranged")
	_expect(not bool(_spawns[0]["elite"]) and not bool(_spawns[1]["elite"]), "first pair is normal")
	_expect_float((Vector2(_spawns[0]["position"]) - boss.global_position).length(), 70.0, "melee global spawn radius")
	_expect_float((Vector2(_spawns[1]["position"]) - boss.global_position).length(), 70.0, "ranged global spawn radius")
	_expect(Vector2(_spawns[0]["position"]) != Vector2(_spawns[1]["position"]), "pair uses independent deterministic offsets")

	boss._physics_process(3.1)
	_expect(_spawns.size() == 2, "repeat summon waits for the full interval")
	boss._physics_process(0.11)
	_expect(_spawns.size() == 4, "repeat interval creates the second pair")
	boss._summon()
	_expect(_spawns.size() == 6, "three summon cycles create three pairs")
	_expect(not bool(_spawns[2]["elite"]) and not bool(_spawns[3]["elite"]), "second pair is normal")
	_expect(bool(_spawns[4]["elite"]) and bool(_spawns[5]["elite"]), "third pair is elite")

	_living_minions = 7
	boss._summon()
	_expect(_spawns.size() == 6, "seven living minions blocks an overflowing pair")
	_expect(boss._summon_n == 3, "blocked summon does not advance elite cadence")

	encounter.queue_free()
	player.queue_free()
	await process_frame
	_finish()


func _record_spawn(pos: Vector2, kind: String, elite: bool) -> void:
	_spawns.append({"position": pos, "kind": StringName(kind), "elite": elite})


func _spawn_kinds(start: int) -> Array[StringName]:
	return [StringName(_spawns[start]["kind"]), StringName(_spawns[start + 1]["kind"])]


func _has_laser_property(boss: SummonerBoss) -> bool:
	for property in boss.get_property_list():
		if "laser" in String(property["name"]).to_lower():
			return true
	return false


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _expect_float(actual: float, expected: float, label: String) -> void:
	if not is_equal_approx(actual, expected):
		_failures.append("%s expected=%s actual=%s" % [label, expected, actual])


func _finish() -> void:
	if _failures.is_empty():
		print("SUMMONER_BOSS_OK")
		quit(0)
	else:
		for failure in _failures:
			push_error("SUMMONER_BOSS_FAIL: %s" % failure)
		quit(1)
