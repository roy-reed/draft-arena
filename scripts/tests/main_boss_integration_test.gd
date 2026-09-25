extends SceneTree


class TestMain:
	extends "res://scripts/main.gd"

	var draft_entries := 0


	func _ready() -> void:
		pass


	func _process(_delta: float) -> void:
		pass


	func _enter_draft() -> void:
		draft_entries += 1
		state = "draft"


class TestPlayer:
	extends Node2D

	var radius := 16.0
	var active := true
	var drafting := false
	var magnet := 0


	func take_damage(_amount: float, _source: Node2D) -> void:
		pass


class TestUI:
	extends CanvasLayer

	var boss_shown := 0
	var boss_hidden := 0
	var over_messages := PackedStringArray()


	func show_boss() -> void:
		boss_shown += 1


	func hide_boss() -> void:
		boss_hidden += 1


	func set_boss(_current: float, _maximum: float) -> void:
		pass


	func update_coins(_coins: int) -> void:
		pass


	func update_xp(_level: int, _current: int, _needed: int) -> void:
		pass


	func flash_banner(_message: String) -> void:
		pass


	func show_over(message: String) -> void:
		over_messages.append(message)


var _failures := PackedStringArray()


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := TestMain.new()
	root.add_child(main)
	var player := TestPlayer.new()
	player.position = Vector2(640.0, 360.0)
	main.add_child(player)
	var ui := TestUI.new()
	main.add_child(ui)
	main.player = player
	main.ui = ui
	main.region_i = 2
	main.state = "wave"
	main._endless = true

	var definitions := main._endless_boss_definitions()
	_expect(definitions.size() == 3 and not definitions.has(null), "Main exposes all three production Boss definitions")
	for definition in definitions:
		await _verify_endless_start(main, definition)

	main._endless_boss_n = 4
	var failed_rank := main._start_endless_boss(null, main.regions[2])
	_expect(failed_rank != OK, "invalid endless definition is rejected")
	_expect(main._endless_boss_n == 4, "failed endless start cannot consume a rank")

	await _verify_abort_wiring(main, definitions[0], player, ui)
	_verify_single_draft_entry(main, player, ui)

	main.queue_free()
	await process_frame
	_finish()


func _verify_endless_start(main: TestMain, definition: BossDefinition) -> void:
	main._endless_boss_n = 0
	var result := main._start_endless_boss(definition, main.regions[2])
	_expect(result == OK, "%s starts through Main" % definition.boss_id)
	_expect(main._endless_boss_n == 1, "%s advances rank only after success" % definition.boss_id)
	var encounter := main._boss_encounter
	_expect(encounter != null, "%s is owned by Main" % definition.boss_id)
	if encounter == null:
		return
	_expect(encounter.aborted.is_connected(main._on_boss_encounter_aborted), "%s abort signal reaches Main" % definition.boss_id)
	var boss := encounter.primary_boss()
	_expect(boss != null, "%s creates a primary Boss" % definition.boss_id)
	if boss != null:
		boss.set_physics_process(false)
		_expect(boss.encounter_context.mode == BossEncounterContext.Mode.ENDLESS, "%s keeps endless mode" % definition.boss_id)
		_expect(boss.encounter_context.endless_rank == 1, "%s keeps the committed rank" % definition.boss_id)
		_expect_float(boss.encounter_context.base_hp_override, 1400.0, "%s receives region base HP" % definition.boss_id)
		_expect_float(boss.max_hp, 6720.0, "%s receives production endless scaling" % definition.boss_id)
		_expect(boss.services.validate(boss.required_services()).is_empty(), "%s receives valid production services" % definition.boss_id)
	main._boss_encounter = null
	main.boss_ref = null
	encounter.abort("test_cleanup")
	encounter.queue_free()
	await process_frame


func _verify_abort_wiring(main: TestMain, definition: BossDefinition, player: TestPlayer, ui: TestUI) -> void:
	main.state = "wave"
	main.is_boss_wave = true
	player.active = true
	var result := main._start_endless_boss(definition, main.regions[2])
	_expect(result == OK, "abort integration encounter starts")
	var encounter := main._boss_encounter
	if encounter == null:
		return
	var boss := encounter.primary_boss()
	var telegraph := boss.get_node_or_null("TelegraphLayer") if boss != null else null
	var minion := Node2D.new()
	minion.add_to_group("enemies")
	minion.add_to_group("minions")
	main.add_child(minion)
	main._spawn_ebullet(main.to_global(Vector2(300.0, 300.0)), Vector2.RIGHT, 0.0, 1.0)
	var bullets := get_nodes_in_group("bullets")
	var projectile: Node = bullets.back() if not bullets.is_empty() else null
	if projectile != null:
		projectile.set_physics_process(false)
	_expect(boss != null and telegraph != null and projectile != null, "abort fixture includes Boss, telegraph, minion, and projectile")
	main._fail_boss_encounter("integration_test", false)
	_expect(main.state == "over", "Main fails closed after an encounter abort")
	_expect(not main.is_boss_wave and not player.active, "abort disables the active Boss wave")
	_expect(main._boss_encounter == null and main.boss_ref == null, "abort clears Main encounter references")
	_expect(ui.over_messages.size() == 1 and "integration_test" in ui.over_messages[0], "abort exposes one actionable failure message")
	await process_frame
	await process_frame
	_expect(not is_instance_valid(encounter), "abort releases the encounter")
	_expect(not is_instance_valid(boss), "abort releases the Boss member")
	_expect(not is_instance_valid(telegraph), "abort releases the Boss telegraph layer")
	_expect(not is_instance_valid(minion), "abort clears encounter minions")
	_expect(not is_instance_valid(projectile), "abort clears encounter projectiles")
	_expect(get_nodes_in_group("enemies").is_empty() and get_nodes_in_group("bullets").is_empty(), "abort leaves no Boss wave combat nodes")


func _verify_single_draft_entry(main: TestMain, player: TestPlayer, ui: TestUI) -> void:
	main.state = "wave"
	main.is_boss_wave = true
	main._endless = true
	main.region_i = 2
	main.wave_i = 6
	main.run_coins = 0
	main.pending_picks = 0
	main.player_level = 1
	main.xp_accum = main._xp_needed() - 1
	main.draft_entries = 0
	player.active = true
	ui.over_messages.clear()
	main._on_boss_encounter_completed(1, 25, 1)
	_expect(main.player_level == 2 and main.pending_picks == 1, "Boss reward queues exactly one level-up pick")
	_expect(main.draft_entries == 1, "Boss completion enters the draft exactly once")
	_expect(main.state == "draft", "Boss level-up finishes in draft state")


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _expect_float(actual: float, expected: float, label: String) -> void:
	if not is_equal_approx(actual, expected):
		_failures.append("%s expected=%s actual=%s" % [label, expected, actual])


func _finish() -> void:
	if _failures.is_empty():
		print("MAIN_BOSS_INTEGRATION_OK")
		quit(0)
	else:
		for failure in _failures:
			push_error("MAIN_BOSS_INTEGRATION_FAIL: %s" % failure)
		quit(1)
