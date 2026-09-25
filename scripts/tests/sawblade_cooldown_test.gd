extends SceneTree

const SawbladeS := preload("res://scripts/sawblade.gd")

class TestHolder:
	extends Node2D
	var saw_count := 1
	var saw_speed_mult := 1.0
	var saw_dmg_mult := 1.0
	var attack_speed_mult := 1.0
	var weapon_level := 1


var _failures := PackedStringArray()


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var holder := TestHolder.new()
	root.add_child(holder)
	var sawblade := SawbladeS.new()
	sawblade.holder = holder
	root.add_child(sawblade)
	sawblade.set_physics_process(false)
	var live_enemy := Node2D.new()
	root.add_child(live_enemy)
	var freed_enemy := Node2D.new()
	root.add_child(freed_enemy)
	sawblade._cds[live_enemy] = 0.7
	sawblade._cds[freed_enemy] = 0.3
	freed_enemy.free()

	sawblade._physics_process(4.9)
	_expect(sawblade._cds.size() == 2, "automatic cooldown GC waits five seconds")
	sawblade._physics_process(0.2)
	_expect(sawblade._cds.size() == 1, "automatic cooldown GC prunes freed enemies")
	_expect(sawblade._cds.has(live_enemy), "automatic cooldown GC preserves live enemies")
	_expect(is_equal_approx(float(sawblade._cds.get(live_enemy, 0.0)), 0.7), "automatic cooldown GC does not reset live cooldowns")

	sawblade.queue_free()
	live_enemy.queue_free()
	holder.queue_free()
	await process_frame
	if _failures.is_empty():
		print("SAWBLADE_COOLDOWN_OK")
		quit(0)
	else:
		for failure in _failures:
			push_error("SAWBLADE_COOLDOWN_FAIL: %s" % failure)
		quit(1)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
