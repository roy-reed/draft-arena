class_name BossEncounterController
extends Node2D

## Owns one encounter's roster, aggregate HUD snapshot, and exactly-once result.
## Boss behavior stays in BossBase subclasses; run progression stays in Main.

signal boss_spawned(boss: BossBase)
signal primary_changed(boss: BossBase)
signal health_changed(current: float, maximum: float)
signal member_defeated(boss: BossBase, reward_coin: int, reward_xp: int)
signal completed(defeated_count: int, reward_coin: int, reward_xp: int)

var _started := false
var _completed := false
var _members: Array[BossBase] = []
var _living_members: Array[BossBase] = []
var _health_snapshots := {}
var _defeated_count := 0
var _reward_coin := 0
var _reward_xp := 0


func start_single(
		definition: BossDefinition,
		context: BossEncounterContext,
		services: BossServices,
		policy: BossScalingPolicy = null
) -> Error:
	var definitions: Array[BossDefinition] = [definition]
	var contexts: Array[BossEncounterContext] = [context]
	return start(definitions, contexts, services, policy)


func start(
		definitions: Array[BossDefinition],
		contexts: Array[BossEncounterContext],
		services: BossServices,
		policy: BossScalingPolicy = null
) -> Error:
	if _started or is_queued_for_deletion():
		push_error("BossEncounterController can only be started once")
		return ERR_ALREADY_IN_USE
	if definitions.is_empty() or definitions.size() != contexts.size() or services == null:
		push_error("BossEncounterController requires matching non-empty definitions and contexts")
		return ERR_INVALID_PARAMETER
	if policy == null:
		policy = BossScalingPolicy.new()

	var prepared: Array[BossBase] = []
	for i in definitions.size():
		var definition := definitions[i]
		var context := contexts[i]
		if definition == null or context == null or definition.scene == null:
			_free_prepared(prepared)
			push_error("Boss encounter member %d has invalid inputs" % i)
			return ERR_INVALID_PARAMETER
		var instance := definition.scene.instantiate()
		var boss := instance as BossBase
		if boss == null:
			instance.free()
			_free_prepared(prepared)
			push_error("Boss scene %s must have a BossBase root" % definition.scene.resource_path)
			return ERR_INVALID_DATA
		var result := boss.configure(definition, context, policy.build_stats(definition, context), services)
		if result != OK:
			boss.free()
			_free_prepared(prepared)
			return result
		prepared.append(boss)

	_started = true
	for boss in prepared:
		_register_member(boss)
	return OK


func primary_boss() -> BossBase:
	for boss in _living_members:
		if is_instance_valid(boss) and not boss._dead:
			return boss
	return null


func living_count() -> int:
	return _living_members.size()


func total_count() -> int:
	return _members.size()


func _register_member(boss: BossBase) -> void:
	_members.append(boss)
	_living_members.append(boss)
	_health_snapshots[boss.get_instance_id()] = {
		"current": boss.hp,
		"maximum": boss.max_hp,
	}
	boss.health_changed.connect(_on_boss_health_changed.bind(boss))
	boss.defeated.connect(_on_boss_defeated)
	add_child(boss)
	boss_spawned.emit(boss)
	primary_changed.emit(primary_boss())
	_emit_health_snapshot()


func _on_boss_health_changed(current: float, maximum: float, boss: BossBase) -> void:
	var member_id := boss.get_instance_id()
	if not _health_snapshots.has(member_id):
		return
	_health_snapshots[member_id] = {
		"current": maxf(current, 0.0),
		"maximum": maximum,
	}
	_emit_health_snapshot()


func _on_boss_defeated(boss: BossBase, reward_coin: int, reward_xp: int) -> void:
	if _completed or not _living_members.has(boss):
		return
	_living_members.erase(boss)
	var member_id := boss.get_instance_id()
	if _health_snapshots.has(member_id):
		_health_snapshots[member_id]["current"] = 0.0
	_defeated_count += 1
	_reward_coin += reward_coin
	_reward_xp += reward_xp
	member_defeated.emit(boss, reward_coin, reward_xp)
	primary_changed.emit(primary_boss())
	_emit_health_snapshot()
	if _living_members.is_empty():
		_completed = true
		completed.emit(_defeated_count, _reward_coin, _reward_xp)


func _emit_health_snapshot() -> void:
	var current := 0.0
	var maximum := 0.0
	for snapshot in _health_snapshots.values():
		current += float(snapshot["current"])
		maximum += float(snapshot["maximum"])
	health_changed.emit(current, maximum)


func _free_prepared(prepared: Array[BossBase]) -> void:
	for boss in prepared:
		boss.free()
