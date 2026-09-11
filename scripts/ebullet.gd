extends Node2D
# 敌方子弹：直线飞行，命中玩家造成伤害；子步进命中检查防高速穿模
# 加入 "bullets" 组，供主流程结算时统一清理

var dir := Vector2.RIGHT
var speed := 240.0
var dmg := 8.0
var player: Node2D = null

var _life := 4.0

func _ready() -> void:
	add_to_group("bullets")
	z_index = 4
	var poly := Polygon2D.new()
	# 怪物弹：红色圆珠（与玩家黄色箭形弹形成颜色+形状双重区分）
	poly.polygon = _circle_points(5.0, 10)
	poly.color = Color(0.95, 0.3, 0.28)
	add_child(poly)
	var ring := Polygon2D.new()
	ring.polygon = _circle_points(6.5, 12)
	ring.color = Color(0.55, 0.12, 0.14)
	ring.show_behind_parent = true
	add_child(ring)

func _circle_points(r: float, n := 10) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		pts.append(Vector2.RIGHT.rotated(TAU * i / n) * r)
	return pts

func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	# 子步进移动：单帧位移可能大于命中半径（高倍速下尤甚），分步检查命中
	var remaining := speed * delta
	while remaining > 0.0:
		var step := minf(remaining, 8.0)
		position += dir * step
		remaining -= step
		if _check_hit():
			return

func _check_hit() -> bool:
	if player == null or not is_instance_valid(player) or player.get("dead"):
		return false
	if position.distance_to(player.position) <= player.radius + 5.0:
		player.take_damage(dmg, self)
		queue_free()
		return true
	return false
