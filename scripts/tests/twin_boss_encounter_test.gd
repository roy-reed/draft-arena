extends SceneTree

class TestPlayer:
	extends Node2D
	var radius := 16.0

	func take_damage(_amount: float, _source: Node2D) -> void:
		pass

var _failures := PackedStringArray()
var _health_samples: Array[Vector2] = []
var _completed_count := 0
var _defeated_count := 0
var _reward_coin := 0
var _reward_xp := 0
var _revived_count := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var definition := load("res://resources/bosses/spitter_boss.tres") as BossDefinition
	_expect(definition != null, "production spitter definition loads")
	if definition == null:
		_finish()
		return

	var player := TestPlayer.new()
	player.position = Vector2(640.0, 360.0)
	root.add_child(player)
	var services := BossServices.new()
	services.spawn_enemy_projectile = func(_pos: Vector2, _dir: Vector2, _speed: float, _damage: float): pass

	var contexts: Array[BossEncounterContext] = []
	for i in 2:
		var context := BossEncounterContext.new()
		context.region_index = 1
		context.arena = Rect2(40.0, 40.0, 1200.0, 640.0)
		context.spawn_position = Vector2(480.0 + 320.0 * i, 160.0)
		context.player = player
		context.rng.seed = 30 + i
		contexts.append(context)

	var encounter := TwinBossEncounterController.new()
	encounter.revive_delay = 0.02
	encounter.health_changed.connect(func(current: float, maximum: float): _health_samples.append(Vector2(current, maximum)))
	encounter.member_revived.connect(func(): _revived_count += 1)
	encounter.completed.connect(_on_completed)
	root.add_child(encounter)
	var result := encounter.start_twins(definition, contexts, services)
	_expect(result == OK, "twin encounter starts")
	_expect(encounter.total_count() == 2 and encounter.living_count() == 2, "two logical slots start alive")
	_expect(_health_samples[-1] == Vector2(3160.0, 3160.0), "twin aggregate health uses configured region value")

	var first := encounter.primary_boss()
	if first != null:
		_expect(is_equal_approx(first.max_hp, 1580.0), "spitter max health is configured before ready")
		_expect(is_equal_approx(first.hp, 1580.0), "spitter current health matches maximum")
		_expect(is_equal_approx(first.speed, 50.4), "spitter speed scaling survives ready")
		first.take_damage(99999.0, player)
	_expect(encounter.living_count() == 1 and _completed_count == 0, "first defeat opens revive window")
	_expect(_health_samples[-1] == Vector2(1580.0, 3160.0), "defeated slot remains in HUD maximum")

	await create_timer(0.06).timeout
	_expect(_revived_count == 1, "defeated twin revives after the window")
	_expect(encounter.total_count() == 2 and encounter.living_count() == 2, "revival replaces its logical slot")
	_expect(_health_samples[-1] == Vector2(3160.0, 3160.0), "revival restores health without growing HUD maximum")

	encounter.revive_delay = 1.0
	var penultimate := encounter.primary_boss()
	if penultimate != null:
		penultimate.take_damage(99999.0, player)
	var last := encounter.primary_boss()
	if last != null:
		last.take_damage(99999.0, player)
	_expect(_completed_count == 1, "killing both inside the window completes exactly once")
	_expect(_defeated_count == 3, "completion includes the pre-revival defeat")
	_expect(_reward_coin == 45 and _reward_xp == 360, "all defeated members contribute rewards exactly once")
	_expect(_health_samples[-1] == Vector2(0.0, 3160.0), "final HUD reaches zero across two logical slots")

	await process_frame
	encounter.queue_free()
	player.queue_free()
	await process_frame
	_finish()


func _on_completed(defeated_count: int, reward_coin: int, reward_xp: int) -> void:
	_completed_count += 1
	_defeated_count = defeated_count
	_reward_coin = reward_coin
	_reward_xp = reward_xp


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("TWIN_BOSS_ENCOUNTER_OK")
		quit(0)
	else:
		for failure in _failures:
			push_error("TWIN_BOSS_ENCOUNTER_FAIL: %s" % failure)
		quit(1)
