class_name SummonerBoss
extends "res://scripts/bosses/boss_base.gd"

const SUMMON_INTERVAL := 3.2
const MAX_MINIONS := 8
const INITIAL_SUMMON_DELAY := 2.0

# 第三关加强：陨石——红圈预警后范围高伤害
const METEOR_INTERVAL := 5.0
const METEOR_WARN := 1.0
const METEOR_RADIUS := 90.0
const METEOR_DAMAGE := 38.0
const INITIAL_METEOR_DELAY := 5.0

var _summon_t := INITIAL_SUMMON_DELAY
var _summon_n := 0

var _meteor_cd := INITIAL_METEOR_DELAY
var _meteor_warn_t := -1.0
var _meteor_pos := Vector2.ZERO
var _meteor_marker: Node2D = null
var _meteor_impacts := 0  # 测试计数


func _ready() -> void:
	super()


func required_services() -> Array[StringName]:
	return [&"spawn_minion", &"living_minion_count"]


func _physics_process(delta: float) -> void:
	_summon_t -= delta
	if _summon_t <= 0.0:
		_summon_t = SUMMON_INTERVAL
		_summon()
	_tick_meteor(delta)
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


# ---- 陨石 ----

static func meteor_hits(player_pos: Vector2, impact_pos: Vector2, impact_radius: float, player_radius: float) -> bool:
	return player_pos.distance_to(impact_pos) < impact_radius + player_radius


static func pick_meteor_position(arena: Rect2, impact_radius: float, rng: RandomNumberGenerator) -> Vector2:
	var margin := impact_radius
	var x := rng.randf_range(arena.position.x + margin, arena.end.x - margin)
	var y := rng.randf_range(arena.position.y + margin, arena.end.y - margin)
	return Vector2(x, y)


func _tick_meteor(delta: float) -> void:
	if _meteor_warn_t >= 0.0:
		_meteor_warn_t -= delta
		_sync_marker()
		if _meteor_warn_t <= 0.0:
			_impact_meteor()
			_clear_meteor_marker()
			_meteor_warn_t = -1.0
			_meteor_cd = METEOR_INTERVAL
		return
	_meteor_cd -= delta
	if _meteor_cd <= 0.0:
		_begin_meteor_warning()


func _begin_meteor_warning() -> void:
	_meteor_pos = pick_meteor_position(arena, METEOR_RADIUS, encounter_context.rng)
	_meteor_warn_t = METEOR_WARN
	_ensure_meteor_marker()
	_sync_marker()


func _impact_meteor() -> void:
	_meteor_impacts += 1
	if player != null and is_instance_valid(player) and player.has_method("take_damage"):
		var pr := float(player.get("radius")) if player.get("radius") != null else 16.0
		if meteor_hits(player.position, _meteor_pos, METEOR_RADIUS, pr):
			player.take_damage(METEOR_DAMAGE, self)
	FX.shake(8.0)


func is_meteor_warning() -> bool:
	return _meteor_warn_t >= 0.0


func meteor_warning_position() -> Vector2:
	return _meteor_pos


func meteor_warning_remaining() -> float:
	return _meteor_warn_t


func _ensure_meteor_marker() -> void:
	if _meteor_marker != null and is_instance_valid(_meteor_marker):
		return
	_meteor_marker = Node2D.new()
	_meteor_marker.z_index = 8
	_meteor_marker.draw.connect(_draw_meteor_marker)
	# 挂到与 boss 同层的父节点，避免随 boss 位移
	var host: Node = get_parent() if get_parent() != null else self
	host.add_child(_meteor_marker)


func _sync_marker() -> void:
	if _meteor_marker == null or not is_instance_valid(_meteor_marker):
		return
	_meteor_marker.global_position = _meteor_pos
	# 预警闪烁：剩余时间越短越亮
	_meteor_marker.queue_redraw()


func _draw_meteor_marker() -> void:
	if _meteor_marker == null:
		return
	var pulse := 0.35 + 0.35 * (1.0 - clampf(_meteor_warn_t / METEOR_WARN, 0.0, 1.0))
	_meteor_marker.draw_circle(Vector2.ZERO, METEOR_RADIUS, Color(1.0, 0.15, 0.1, pulse))
	_meteor_marker.draw_arc(Vector2.ZERO, METEOR_RADIUS, 0.0, TAU, 48, Color(1.0, 0.4, 0.2, 0.9), 3.0)


func _clear_meteor_marker() -> void:
	if _meteor_marker != null and is_instance_valid(_meteor_marker):
		_meteor_marker.queue_free()
	_meteor_marker = null


func _exit_tree() -> void:
	_clear_meteor_marker()
