extends SceneTree

const PlayerS := preload("res://scripts/player.gd")
const MainS := preload("res://scripts/main.gd")
const UIS := preload("res://scripts/ui.gd")
const CardsS := preload("res://scripts/cards.gd")
const MetaS := preload("res://scripts/meta.gd")

class TestMain:
	extends "res://scripts/main.gd"
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass
	func _finish_boss_wave() -> void:
		pass
	func add_xp(_amount: int, _draft := true) -> void:
		pass

var failures := PackedStringArray()

func _init() -> void:
	_run.call_deferred()

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _run() -> void:
	var main := TestMain.new()
	root.add_child(main)
	var player := PlayerS.new()
	player.active = false
	main.add_child(player)
	main.player = player
	var ui := UIS.new()
	main.add_child(ui)
	main.ui = ui
	player.set_weapon("w_shotgun")
	for count in [3, 5, 8]:
		player.pellet_count = count
		var center := false
		for i in count:
			var angle := player.pellet_angle(i)
			expect(absf(angle) <= PlayerS.SHOTGUN_HALF_ANGLE + 0.0001, "pellets stay within fixed spread")
			center = center or is_zero_approx(angle)
		expect(center, "every shotgun tier includes an aimed center pellet")
	var shots := []
	player.bullet_spawner = func(pos, dir, dmg, pierce, _bounce, _owner): shots.append([pos, dir, dmg, pierce])
	var target := Node2D.new()
	target.position = Vector2(700, 360)
	main.add_child(target)
	target.add_to_group("enemies")
	player.position = Vector2(640, 360)
	player.pellet_count = 3
	player.double_chance = 1.0
	player._shoot()
	expect(shots.size() == 3, "extra pellet is not simultaneous")
	player.active = true
	player._tick_extra_shot(0.06)
	expect(shots.size() == 3, "extra waits for delay")
	player.drafting = true
	player._tick_extra_shot(1.0)
	expect(shots.size() == 3, "draft freezes queued shot")
	player.drafting = false
	player._tick_extra_shot(0.07)
	expect(shots.size() == 4, "extra fires exactly once after delay")
	player._tick_extra_shot(1.0)
	expect(shots.size() == 4, "no repeated extra shot")
	player._queue_extra_shot(Vector2.RIGHT, 6.0, 0)
	player._tick_extra_shot(0.06)
	player._queue_extra_shot(Vector2.RIGHT, 6.0, 0)
	player._tick_extra_shot(0.07)
	expect(shots.size() == 5, "high attack speed preserves older queued shot")
	player._tick_extra_shot(0.06)
	expect(shots.size() == 6, "newer queued shot also fires once")
	player.active = false
	var fang := CardsS.get_card("p_fang")
	expect(not fang.has("req"), "fang is available to shotgun")
	fang["apply"].call(player)
	fang["apply"].call(player)
	expect(player.lifesteal == 2.0, "fang stacks one healing per card")
	player.hp = 70.0
	player.max_hp = 80.0
	main._on_enemy_killed(1, Vector2.ZERO, 0)
	expect(player.hp == 72.0, "shotgun kill restores stacked health")
	player.owned_passives = ["p_fang", "p_fang"]
	ui.update_stats(player.combat_summary())
	expect(ui.draft_stats.text.contains("吸血獠牙×2"), "draft displays current buff stacks")
	expect(ui.pause_stats.text.contains("每弹伤害"), "pause identifies shotgun per-pellet damage")
	ui.toggle_stats()
	expect(ui.stats_label.visible, "HUD stats toggle on")
	ui.toggle_stats()
	expect(not ui.stats_label.visible, "HUD stats toggle off")
	expect(ui.pause_buttons.has("menu") and ui.pause_buttons.size() == 4, "pause has all four requested actions")
	expect(ui.draft_buttons[0].autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "long card descriptions wrap instead of overflowing mobile screen")
	expect(main._pause_cbs().has("menu"), "main wires return-to-menu")
	main.run_coins = 0
	player.magnet = 2
	main._on_boss_encounter_completed(2, 30, 0)
	expect(main.run_coins == 42, "magnet rewards both logical slots at +3 per stack")

	# 调用生产结算，测试专用 XDG_DATA_HOME 下保留并还原文件。
	var previous := MetaS.load_data()
	var previous_persist := MetaS.persist
	MetaS.persist = true
	var data := MetaS.default_data()
	data["coins"] = 100
	MetaS.save_data(data)
	main.smoke = false
	main._endless = true
	main.state = "wave"
	main.run_coins = 27
	main._banked_run_coins = 0
	expect(main._bank_run_coins() == 127, "endless early exit banks earned coins without pity")
	expect(main._bank_run_coins() == 127, "repeated exit does not duplicate coins")
	main.run_coins += 5
	expect(main._bank_run_coins() == 132, "only newly earned coins are banked")
	main.state = "over"
	expect(main._bank_run_coins() == 132, "exit after settlement does not duplicate coins")
	MetaS.save_data(previous)
	MetaS.persist = previous_persist
	target.free()
	main.free()
	await _test_boss_boundary()
	await _test_restart_menu()
	if failures.is_empty():
		print("PLAYTEST_FEEDBACK_OK")
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)

func _test_boss_boundary() -> void:
	var definition := load("res://resources/bosses/charge_boss.tres") as BossDefinition
	var context := BossEncounterContext.new()
	var player := PlayerS.new()
	player.active = false
	player.position = Vector2(600, 350)
	root.add_child(player)
	context.player = player
	context.region_index = 0
	context.arena = Rect2(40, 40, 1200, 640)
	context.spawn_position = Vector2(1200, 600)
	var boss := definition.scene.instantiate() as ChargeBoss
	var stats := BossScalingPolicy.new().build_stats(definition, context)
	expect(boss.configure(definition, context, stats, BossServices.new()) == OK, "boundary test configures production boss")
	root.add_child(boss)
	boss.set_physics_process(false)
	var fx := FX.new()
	root.add_child(fx)
	FX.I.enabled = true
	for weapon in ["w_shotgun", "w_sawblade"]:
		player.set_weapon(weapon)
		for state in [&"chase", &"aim", &"dash", &"rest"]:
			boss.change_state(state)
			boss._state_time = 100.0
			boss.hp = 10000.0
			boss.position = context.arena.end - Vector2.ONE * boss.radius
			for i in 30:
				boss.take_damage(1.0, player)
				expect(boss.kb.length() <= 155.01, "repeated shotgun/saw hits cap knockback")
				boss._physics_process(0.016)
				expect(boss.position.x <= context.arena.end.x - boss.radius + 0.01 and boss.position.y <= context.arena.end.y - boss.radius + 0.01, "boss remains in arena in every state")
	boss.free()
	player.free()
	fx.free()
	await process_frame

func _test_restart_menu() -> void:
	var previous := MetaS.load_data()
	var previous_persist := MetaS.persist
	MetaS.persist = true
	var data := MetaS.default_data()
	data["coins"] = 100
	MetaS.save_data(data)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game._menu_select(2)
	game._menu_start()
	game.run_coins = 27
	game._endless = true
	game.request_pause()
	expect(paused, "production pause freezes tree")
	game._cb_restart()
	await process_frame
	await process_frame
	game = current_scene
	expect(not paused and game.char_i == 2 and game.player != null, "restart resumes same character without menu")
	expect(game.region_i == 0 and game.wave_i == 0 and not game._endless, "restart resets endless run to first wave")
	expect(MetaS.load_data()["coins"] == 127, "restart saves earned coins once")
	game.run_coins = 5
	game.request_pause()
	game._cb_menu()
	await process_frame
	await process_frame
	game = current_scene
	expect(not paused and game.state == "menu" and game.player == null, "return-to-menu resets scene and pause")
	expect(game.meta_d["coins"] == 132, "menu loads banked coins without duplication")
	game.free()
	current_scene = null
	MetaS.save_data(previous)
	MetaS.persist = previous_persist
