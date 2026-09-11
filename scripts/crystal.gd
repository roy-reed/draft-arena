extends Node2D
# 经验晶体（纯视觉反馈）：击杀点弹出 → 减速悬停 → 追向玩家，到达即消失（XP 已在击杀时入账）

var target: Node2D = null
var vel := Vector2.ZERO
var _t := 0.0

func _ready() -> void:
	z_index = 7
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(0, -4), Vector2(3, 0), Vector2(0, 4), Vector2(-3, 0)])
	poly.color = Color(0.4, 0.9, 1.0)
	add_child(poly)
	vel = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(30.0, 70.0)

func _physics_process(delta: float) -> void:
	_t += delta
	if _t < 0.22:
		position += vel * delta
		vel = vel.move_toward(Vector2.ZERO, 220.0 * delta)
		return
	if target != null and is_instance_valid(target):
		var d := target.position - position
		position += d.normalized() * (260.0 + _t * 200.0) * delta
		if d.length() < 14.0:
			queue_free()
	else:
		queue_free()
