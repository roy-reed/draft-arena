class_name TwinBossEncounterController
extends BossEncounterController

## Two logical slots. A first defeat opens a revive window; expiry replaces the
## defeated slot instead of growing the roster or aggregate HUD maximum.

signal revive_window_started(duration: float)
signal member_revived()

@export var revive_delay := 10.0

var _definition: BossDefinition
var _services: BossServices
var _policy: BossScalingPolicy
var _pending_member_id := 0
var _revive_time := -1.0


func start_twins(
		definition: BossDefinition,
		contexts: Array[BossEncounterContext],
		services: BossServices,
		policy: BossScalingPolicy = null
) -> Error:
	if contexts.size() != 2:
		return ERR_INVALID_PARAMETER
	_definition = definition
	_services = services
	_policy = policy if policy != null else BossScalingPolicy.new()
	member_defeated.connect(_on_member_defeated)
	var definitions: Array[BossDefinition] = [definition, definition]
	return start(definitions, contexts, services, _policy)


func _process(delta: float) -> void:
	if _revive_time < 0.0:
		return
	if living_count() != 1:
		_cancel_revive()
		return
	_revive_time -= delta
	if _revive_time > 0.0:
		return

	var survivor := primary_boss()
	if survivor == null:
		_cancel_revive()
		return
	var context := _copy_context(survivor.encounter_context)
	context.spawn_position = (survivor.position + Vector2(90.0, 0.0)).clamp(
		context.arena.position + Vector2.ONE * 40.0,
		context.arena.end - Vector2.ONE * 40.0
	)
	var result := replace_defeated_member(_definition, context, _services, _pending_member_id, _policy)
	if result == OK:
		survivor.change_phase(&"default")
		member_revived.emit()
	else:
		push_error("Twin boss revive failed with error %s" % result)
	_cancel_revive()


func _on_member_defeated(boss: BossBase, _reward_coin: int, _reward_xp: int) -> void:
	if living_count() != 1:
		_cancel_revive()
		return
	_pending_member_id = boss.get_instance_id()
	_revive_time = revive_delay
	var survivor := primary_boss()
	if survivor != null:
		survivor.change_phase(&"revive_window")
	revive_window_started.emit(revive_delay)


func _cancel_revive() -> void:
	_pending_member_id = 0
	_revive_time = -1.0


func _copy_context(source: BossEncounterContext) -> BossEncounterContext:
	var result := BossEncounterContext.new()
	result.mode = source.mode
	result.region_index = source.region_index
	result.endless_rank = source.endless_rank
	result.arena = source.arena
	result.player = source.player
	result.base_hp_override = source.base_hp_override
	result.rng.seed = source.rng.randi()
	return result
