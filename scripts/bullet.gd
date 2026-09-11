extends Node2D
# 灰盒子弹：直线飞行 + 距离判定命中，可穿透/弹射

var dir := Vector2.RIGHT
var speed := 460.0
var dmg := 10.0
var pierce_left := 0
var bounce_left := 0
var owner_player: Node2D = null
var bullet_color := Color(1, 0.95, 0.6)  # 进化后由生成侧改金色

var _life := 1.6
var _hit_list: Array = []  # 已命中过的敌人，穿透/弹射时防重复结算

func _ready() -> void:
	add_to_group("bullets")
	z_index = 4
	rotation = dir.angle()
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(9, 0), Vector2(-6, 4), Vector2(-6, -4)])
	poly.color = bullet_color
	add_child(poly)

func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	# 子步进移动：单帧位移可能大于命中半径（高倍速/高攻速下尤甚），分步检查命中
	var remaining := speed * delta
	while remaining > 0.0:
		var step := minf(remaining, 10.0)
		position += dir * step
		remaining -= step
		if _check_hit():
			return

func _check_hit() -> bool:
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e in _hit_list:
			continue
		if position.distance_to(e.position) <= e.radius + 4.0:
			_hit(e)
			return true
	return false

func _hit(e: Node2D) -> void:
	e.take_damage(dmg, owner_player)
	_hit_list.append(e)
	if pierce_left > 0:
		pierce_left -= 1
		return  # 穿透：不销毁，继续直线飞行
	if bounce_left > 0:
		bounce_left -= 1
		var best: Node2D = null
		var best_d := 320.0
		for o in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(o) or o in _hit_list:
				continue
			var d: float = position.distance_to(o.position)
			if d < best_d:
				best_d = d
				best = o
		if best != null:
			dir = (best.position - position).normalized()
			rotation = dir.angle()
			return
	queue_free()
