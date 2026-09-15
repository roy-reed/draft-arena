extends SceneTree

class TestPlayer:
	extends Node2D
	var radius := 16.0
	var damage_taken := 0.0

	func take_damage(amount: float, _source: Node2D) -> void:
		damage_taken += amount

var _failures := PackedStringArray()


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var definition := load("res://resources/bosses/charge_boss.tres") as BossDefinition
	_expect(definition != null, "production definition loads")
	if definition == null:
		_finish()
		return

	var context := BossEncounterContext.new()
	context.region_index = 0
	context.arena = Rect2(40.0, 40.0, 1200.0, 640.0)
	context.spawn_position = Vector2(640.0, 120.0)
	context.player = TestPlayer.new()
	context.player.position = Vector2(900.0, 300.0)
	context.rng.seed = 7

	var stats := BossScalingPolicy.new().build_stats(definition, context)
	var boss := definition.scene.instantiate() as ChargeBoss
	_expect(boss != null, "production scene instantiates ChargeBoss")
	if boss == null:
		context.player.free()
		_finish()
		return

	var configure_result := boss.configure(definition, context, stats, BossServices.new())
	_expect(configure_result == OK, "production boss configures")
	var before_ready := _snapshot(boss)
	root.add_child(context.player)
	root.add_child(boss)
	var after_ready := _snapshot(boss)

	_expect(before_ready == after_ready, "ready preserves configured combat values")
	_expect_float(boss.max_hp, 840.0, "scaled max_hp")
	_expect_float(boss.hp, 840.0, "full hp")
	_expect_float(boss.speed, 72.0, "scaled speed")
	_expect_float(boss.contact_damage, 36.0, "scaled contact damage")
	_expect(boss.get_state_id() == &"chase", "state machine starts in chase")
	_expect(boss.visual_contract_errors().is_empty(), "visual contract is complete")
	_expect(boss.anchor_global_position(&"ProjectileOrigin") != boss.global_position, "projectile anchor is distinct")
	_expect(not (boss.get_node("VisualRoot/Placeholder") as Polygon2D).visible, "production artwork replaces placeholder")

	boss._physics_process(3.1)
	_expect(boss.get_state_id() == &"aim", "chase transitions to aim")
	boss._physics_process(0.8)
	_expect(boss.get_state_id() == &"dash", "aim transitions to dash")
	boss._physics_process(0.6)
	_expect(boss.get_state_id() == &"rest", "dash transitions to rest")
	boss._physics_process(1.3)
	_expect(boss.get_state_id() == &"chase", "rest transitions to chase")

	boss.queue_free()
	context.player.queue_free()
	await process_frame
	await _verify_artwork_variants(definition)
	_finish()


func _verify_artwork_variants(definition: BossDefinition) -> void:
	for variant in [&"missing", &"static", &"animated"]:
		var context := BossEncounterContext.new()
		context.region_index = 0
		context.arena = Rect2(40.0, 40.0, 1200.0, 640.0)
		context.spawn_position = Vector2(640.0, 120.0)
		context.player = TestPlayer.new()
		context.player.position = Vector2(900.0, 300.0)
		context.rng.seed = 7

		var boss := definition.scene.instantiate() as ChargeBoss
		var visual_root := boss.get_node("VisualRoot") as BossVisual
		var texture := GradientTexture2D.new()
		if variant == &"missing":
			visual_root.skin_name = &""
		elif variant == &"static":
			(boss.get_node("VisualRoot/Artwork") as Sprite2D).texture = texture
		else:
			var old_artwork := boss.get_node("VisualRoot/Artwork")
			visual_root.remove_child(old_artwork)
			old_artwork.free()
			var animated := AnimatedSprite2D.new()
			animated.name = "Artwork"
			animated.sprite_frames = SpriteFrames.new()
			animated.sprite_frames.add_animation(&"idle")
			animated.sprite_frames.add_frame(&"idle", texture)
			visual_root.add_child(animated)

		var stats := BossScalingPolicy.new().build_stats(definition, context)
		_expect(boss.configure(definition, context, stats, BossServices.new()) == OK, "%s artwork configures" % variant)
		var before_ready := _snapshot(boss)
		root.add_child(context.player)
		root.add_child(boss)
		_expect(before_ready == _snapshot(boss), "%s artwork preserves combat values" % variant)
		_expect(boss.visual_contract_errors().is_empty(), "%s artwork preserves visual contract" % variant)
		var placeholder_visible := (boss.get_node("VisualRoot/Placeholder") as Polygon2D).visible
		_expect(placeholder_visible == (variant == &"missing"), "%s artwork uses expected fallback" % variant)

		boss.queue_free()
		context.player.queue_free()
		await process_frame


func _snapshot(boss: BossBase) -> Array:
	return [boss.max_hp, boss.hp, boss.armor, boss.speed, boss.contact_damage, boss.radius, boss.coin, boss.xp]


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _expect_float(actual: float, expected: float, label: String) -> void:
	if not is_equal_approx(actual, expected):
		_failures.append("%s expected=%s actual=%s" % [label, expected, actual])


func _finish() -> void:
	if _failures.is_empty():
		print("CHARGE_BOSS_OK")
		quit(0)
	else:
		for failure in _failures:
			push_error("CHARGE_BOSS_FAIL: %s" % failure)
		quit(1)
