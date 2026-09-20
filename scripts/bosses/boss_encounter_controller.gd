class_name BossEncounterController
extends Node2D

## Owns one encounter's roster, aggregate HUD snapshot, and exactly-once result.
## Boss behavior stays in BossBase subclasses; run progression stays in Main.

signal boss_spawned(boss: BossBase)
signal primary_changed(boss: BossBase)
signal health_changed(current: float, maximum: float)
signal member_defeated(boss: BossBase, reward_coin: int, reward_xp: int)
signal completed(defeated_count: int, reward_coin: int, reward_xp: int)
signal aborted(reason: String)

var _started := false
var _completed := false
var _members: Array[BossBase] = []
var _living_members: Array[BossBase] = []
var _living_member_ids := {}
var _member_slots := {}
var _rewarded_slots := {}
var _slot_health: Array[float] = []
var _slot_max_health: Array[float] = []
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
		var boss := _prepare_member(definition, context, services, policy)
		if boss == null:
			_free_prepared(prepared)
			push_error("Boss encounter member %d could not be prepared" % i)
			return ERR_INVALID_DATA
		prepared.append(boss)

	_started = true
	for boss in prepared:
		_register_member(boss)
	return OK


func replace_defeated_member(
		definition: BossDefinition,
		context: BossEncounterContext,
		services: BossServices,
		defeated_member_id: int,
		policy: BossScalingPolicy = null
) -> Error:
	if not _started or _completed:
		return ERR_UNAVAILABLE
	if not _member_slots.has(defeated_member_id):
		return ERR_DOES_NOT_EXIST
	if policy == null:
		policy = BossScalingPolicy.new()
	var boss := _prepare_member(definition, context, services, policy)
	if boss == null:
		return ERR_INVALID_DATA
	var slot := int(_member_slots[defeated_member_id])
	_member_slots.erase(defeated_member_id)
	_register_member(boss, slot)
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


func abort(reason: String = "aborted") -> void:
	if _completed:
		return
	_completed = true
	set_process(false)
	for boss in _living_members:
		if is_instance_valid(boss):
			boss.queue_free()
	_living_members.clear()
	_living_member_ids.clear()
	for i in _slot_health.size():
		_slot_health[i] = 0.0
	primary_changed.emit(null)
	_emit_health_snapshot()
	aborted.emit(reason)


func _register_member(boss: BossBase, slot: int = -1) -> void:
	if slot < 0:
		slot = _members.size()
		_members.append(boss)
		_slot_health.append(boss.hp)
		_slot_max_health.append(boss.max_hp)
	else:
		_members[slot] = boss
		_slot_health[slot] = boss.hp
		_slot_max_health[slot] = boss.max_hp
	_living_members.append(boss)
	var member_id := boss.get_instance_id()
	_living_member_ids[member_id] = true
	_member_slots[member_id] = slot
	boss.health_changed.connect(_on_boss_health_changed.bind(boss))
	boss.defeated.connect(_on_boss_defeated)
	boss.tree_exited.connect(_on_boss_tree_exited.bind(boss.get_instance_id()))
	add_child(boss)
	boss_spawned.emit(boss)
	primary_changed.emit(primary_boss())
	_emit_health_snapshot()


func _on_boss_health_changed(current: float, maximum: float, boss: BossBase) -> void:
	var member_id := boss.get_instance_id()
	if not _member_slots.has(member_id):
		return
	var slot := int(_member_slots[member_id])
	_slot_health[slot] = maxf(current, 0.0)
	_slot_max_health[slot] = maximum
	_emit_health_snapshot()


func _on_boss_defeated(boss: BossBase, reward_coin: int, reward_xp: int) -> void:
	if _completed or not _living_members.has(boss):
		return
	_living_members.erase(boss)
	var member_id := boss.get_instance_id()
	_living_member_ids.erase(member_id)
	var slot := -1
	if _member_slots.has(member_id):
		slot = int(_member_slots[member_id])
		_slot_health[slot] = 0.0
	var paid_coin := 0
	var paid_xp := 0
	# A logical encounter slot pays once. Revived replacements may reopen the
	# fight, but cannot turn the revive loop into unlimited run rewards.
	if slot >= 0 and not _rewarded_slots.has(slot):
		_rewarded_slots[slot] = true
		_defeated_count += 1
		_reward_coin += reward_coin
		_reward_xp += reward_xp
		paid_coin = reward_coin
		paid_xp = reward_xp
	member_defeated.emit(boss, paid_coin, paid_xp)
	primary_changed.emit(primary_boss())
	_emit_health_snapshot()
	if _living_members.is_empty():
		_completed = true
		set_process(false)
		completed.emit(_defeated_count, _reward_coin, _reward_xp)


func _on_boss_tree_exited(member_id: int) -> void:
	if _completed or not _living_member_ids.has(member_id):
		return
	abort("boss_exited_unexpectedly")


func _emit_health_snapshot() -> void:
	var current := 0.0
	var maximum := 0.0
	for value in _slot_health:
		current += value
	for value in _slot_max_health:
		maximum += value
	health_changed.emit(current, maximum)


func _prepare_member(
		definition: BossDefinition,
		context: BossEncounterContext,
		services: BossServices,
		policy: BossScalingPolicy
) -> BossBase:
	if definition == null or context == null or definition.scene == null:
		return null
	var instance := definition.scene.instantiate()
	var boss := instance as BossBase
	if boss == null:
		instance.free()
		return null
	var result := boss.configure(definition, context, policy.build_stats(definition, context), services)
	if result != OK:
		boss.free()
		return null
	return boss


func _free_prepared(prepared: Array[BossBase]) -> void:
	for boss in prepared:
		boss.free()
