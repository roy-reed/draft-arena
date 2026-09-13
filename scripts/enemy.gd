extends Node2D
# 灰盒敌人：追击 + 接触伤害，无物理引擎

signal killed(coin_value: int, pos: Vector2, xp_value: int)

var max_hp := 20.0
var hp := 20.0
var speed := 80.0
var contact_damage := 10.0
var coin := 1
var xp := 0  # 击杀经验（由刷怪侧按难度档位写入；0 = 测试假人不产经验）
var tier := 0  # 难度档位 0..5（白绿蓝橙红金），死亡粒子数量随档位
var armor := 0.0  # 护甲：玩家每次伤害先减护甲（至少 1）
var tint := Color(1, 1, 1)  # 精灵染色 = 难度档位色
var radius := 14.0
var is_elite := false
var body_color := Color(1.0, 0.35, 0.3)
var player: Node2D = null
var arena := Rect2(40, 40, 1200, 640)

var slow_factor := 1.0
var kb := Vector2.ZERO
var _slow_time := 0.0
var _touch_cd := 0.0
var _spawn_guard := 0.35  # 刷入保护：淡入完成前不造成接触伤害，防偷袭
var _poly: Polygon2D = null
var _dead := false  # 死亡守卫：hp<=0 后拒绝再次受伤/再发击杀信号（防爆裂弹等再入递归）

func _ready() -> void:
	add_to_group("enemies")
	z_index = 3
	hp = max_hp
	var pts := PackedVector2Array()
	for i in 8:
		pts.append(Vector2.RIGHT.rotated(TAU * i / 8.0) * radius)
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = body_color
	add_child(poly)
	_poly = poly
	var tex := ArtS.skin(_skin_name())
	if tex != null:
		poly.visible = false
		var spr := Sprite2D.new()
		spr.texture = tex
		var s := radius * 2.0 / float(tex.get_width())
		spr.scale = Vector2(s, s)
		spr.modulate = tint  # 中性灰白底图按难度档位染色
		add_child(spr)
	_poly.self_modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_poly, "self_modulate:a", 1.0, 0.35)

func _skin_name() -> String:
	return "enemy_chaser"

func apply_slow(f: float, t: float) -> void:
	slow_factor = f
	_slow_time = t

func _physics_process(delta: float) -> void:
	if _slow_time > 0.0:
		_slow_time -= delta
	else:
		slow_factor = 1.0
	if player == null or not is_instance_valid(player):
		return
	var dir := (player.position - position).normalized()
	position += dir * speed * slow_factor * delta + kb * delta
	kb = kb.move_toward(Vector2.ZERO, 900.0 * delta)
	if _spawn_guard > 0.0:
		_spawn_guard -= delta
	else:
		_try_touch(delta)

func _try_touch(delta: float) -> void:
	_touch_cd -= delta
	if _touch_cd <= 0.0 and position.distance_to(player.position) < radius + player.radius:
		_touch_cd = 0.5
		player.take_damage(contact_damage, self)

func take_damage(amount: float, from: Node2D) -> void:
	if _dead or hp <= 0.0 or amount <= 0.0:
		return  # 零伤（选牌冻结期）直接跳过，不触发护甲地板
	amount = maxf(amount - armor, 1.0)  # 护甲减伤（至少 1 点）
	hp -= amount
	var crit: bool = from != null and is_instance_valid(from) and from.get("last_crit") == true
	FX.hit_spark(position, Color(1.0, 0.9, 0.4))
	FX.float_number(self, amount, is_elite or crit)
	if from != null and is_instance_valid(from):
		FX.knockback(self, (position - from.position).normalized())
	if from != null and from.get("slow_on_hit"):
		apply_slow(0.75, 1.2)
	modulate = Color(1, 1, 1, 0.6)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, 0.12)
	if hp <= 0.0:
		_dead = true
		FX.death_burst(position, body_color, 14 + tier * 5)  # 粒子量随难度档位
		SFX.play("kill")
		killed.emit(coin, position, xp)
		queue_free()
