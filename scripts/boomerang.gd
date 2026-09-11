extends Node2D
# 回旋镖：飞出减速段 → 折返飞回持有者，可二次命中
# 子步进移动与命中检查与 bullet.gd 同款，防高速穿模

var dir := Vector2.RIGHT
var speed := 420.0
var dmg := 9.0
var owner_player: Node2D = null

const OUT_TIME := 0.5
const RETURN_SPEED := 500.0

var _phase := 0  # 0 飞出 1 折返
var _t := OUT_TIME
var _hits := {}  # 敌人 -> 已命中的阶段（换阶段后可二次命中）
var _life := 5.0

func _ready() -> void:
	add_to_group("bullets")
	z_index = 4
	var size_mult := 1.0
	if owner_player != null and is_instance_valid(owner_player) and owner_player.get("boom_size_mult") != null:
		size_mult = float(owner_player.get("boom_size_mult"))
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(11 * size_mult, 0), Vector2(0, 4 * size_mult), Vector2(-11 * size_mult, 0), Vector2(0, -4 * size_mult)])
	var evolved: bool = owner_player != null and is_instance_valid(owner_player) and owner_player.get("weapon_level") != null and int(owner_player.get("weapon_level")) >= 4
	poly.color = Color(1.0, 0.8, 0.25) if evolved else Color(0.7, 0.95, 1.0)
	add_child(poly)
	set_meta("hit_r", 6.0 * size_mult)

func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if _phase == 0:
		_t -= delta
		if _t <= 0.0:
			_phase = 1
			_hits.clear()  # 折返后允许二次命中
	if _phase == 1 and owner_player != null and is_instance_valid(owner_player):
		dir = (owner_player.position - position).normalized()
	rotation += 18.0 * delta
	# 子步进移动：单帧位移可能大于命中半径（高倍速下尤甚），分步检查命中
	var remaining := (speed if _phase == 0 else RETURN_SPEED) * delta
	while remaining > 0.0:
		var step := minf(remaining, 10.0)
		position += dir * step
		remaining -= step
		if _check_hit():
			return
	if _phase == 1 and owner_player != null and is_instance_valid(owner_player):
		if position.distance_to(owner_player.position) <= 18.0:
			queue_free()

func _check_hit() -> bool:
	# 穿透式判定：命中不拦截弹道，同一阶段每个敌人只结算一次
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if position.distance_to(e.position) <= e.radius + float(get_meta("hit_r", 6.0)):
			if _hits.get(e, -1) == _phase:
				continue
			_hits[e] = _phase
			e.take_damage(dmg, owner_player)
	return false
