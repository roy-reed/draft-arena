class_name BossBase
extends "res://scripts/enemy.gd"

signal health_changed(current: float, maximum: float)
signal state_changed(state_id: StringName)
signal phase_changed(phase_id: StringName)
signal defeated(boss: BossBase, reward_coin: int, reward_xp: int)

var definition: BossDefinition
var encounter_context: BossEncounterContext
var services: BossServices

var _configured := false
var _state_id: StringName = &"idle"
var _phase_id: StringName = &"default"


func configure(
		new_definition: BossDefinition,
		context: BossEncounterContext,
		stats: BossRuntimeStats,
		new_services: BossServices
) -> Error:
	if _configured or is_inside_tree():
		push_error("BossBase can only be configured once before entering the scene tree")
		return ERR_ALREADY_IN_USE
	if new_definition == null or context == null or stats == null or new_services == null:
		push_error("BossBase.configure received a null dependency")
		return ERR_INVALID_PARAMETER
	var errors := new_definition.validate()
	errors.append_array(context.validate())
	errors.append_array(stats.validate())
	errors.append_array(new_services.validate(required_services()))
	if not errors.is_empty():
		push_error("Invalid Boss configuration: %s" % "; ".join(errors))
		return ERR_INVALID_DATA

	definition = new_definition
	encounter_context = context
	services = new_services
	max_hp = stats.max_hp
	hp = stats.max_hp
	armor = stats.armor
	speed = stats.speed
	contact_damage = stats.contact_damage
	radius = stats.gameplay_radius
	coin = stats.reward_coin
	xp = stats.reward_xp
	player = context.player
	arena = context.arena
	position = context.spawn_position
	is_elite = true
	_configured = true
	return OK


func _ready() -> void:
	if not _configured:
		push_error("BossBase entered the scene tree before configure()")
		set_physics_process(false)
		return
	super()
	health_changed.emit(hp, max_hp)
	state_changed.emit(_state_id)
	phase_changed.emit(_phase_id)


func take_damage(amount: float, from: Node2D) -> void:
	var previous_hp := hp
	super(amount, from)
	if not is_equal_approx(previous_hp, hp):
		health_changed.emit(maxf(hp, 0.0), max_hp)
	if previous_hp > 0.0 and hp <= 0.0:
		defeated.emit(self, coin, xp)


func change_state(next_state: StringName) -> void:
	if next_state == _state_id:
		return
	_state_id = next_state
	state_changed.emit(_state_id)


func change_phase(next_phase: StringName) -> void:
	if next_phase == _phase_id:
		return
	_phase_id = next_phase
	phase_changed.emit(_phase_id)


func get_state_id() -> StringName:
	return _state_id


func get_phase_id() -> StringName:
	return _phase_id


func required_services() -> Array[StringName]:
	return []
