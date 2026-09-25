class_name SummonerBoss
extends "res://scripts/bosses/boss_base.gd"

const SUMMON_INTERVAL := 3.2
const MAX_MINIONS := 8
const INITIAL_SUMMON_DELAY := 2.0

var _summon_t := INITIAL_SUMMON_DELAY
var _summon_n := 0

func _ready() -> void:
	super()

func required_services() -> Array[StringName]:
	return [&"spawn_minion", &"living_minion_count"]

func _physics_process(delta: float) -> void:
	_summon_t -= delta
	if _summon_t <= 0.0:
		_summon_t = SUMMON_INTERVAL
		_summon()
	super(delta)

func _summon() -> void:
	if not services.living_minion_count.is_valid():
		push_error("SummonerBoss: living_minion_count service not available")
		return

	var alive_count := maxi(0, int(services.living_minion_count.call()))
	# Summons are an atomic melee/ranged pair. Wait until both slots are free so
	# MAX_MINIONS remains a hard cap even when seven minions are alive.
	if alive_count + 2 > MAX_MINIONS:
		return

	_summon_n += 1
	var elite := _summon_n % 3 == 0

	if services.spawn_minion.is_valid():
		_spawn_minion_at_random_offset(&"melee", elite)
		_spawn_minion_at_random_offset(&"ranged", elite)


func _spawn_minion_at_random_offset(kind: StringName, elite: bool) -> void:
	var angle := encounter_context.rng.randf() * TAU
	var offset := Vector2.RIGHT.rotated(angle) * 70.0
	services.spawn_minion.call(global_position + offset, kind, elite)
