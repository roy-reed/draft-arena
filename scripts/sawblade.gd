extends Node2D
# 环刃：N 把刃绕持有者旋转，对接触敌人持续造成伤害（每个敌人独立结算间隔）
# 由 player.gd 在装备 w_sawblade 时创建；刃数/转速/伤害倍率实时读 holder（升级卡即时生效）
# 命中判定统一用 main 局部系（holder.position + 刃位 vs enemy.position），勿混用局部/世界坐标

var holder: Node2D = null
var dmg_cb := Callable()  # func(base, target) -> 最终伤害，由玩家提供
var dmg_base := 10.0
var orbit_r := 70.0  # 打击范围（第 3 轮 playtest 反馈加大）
var base_tick := 0.3
var tick := 0.3  # 实时=base_tick/(攻速×刃数)

var _angle := 0.0
var _cds := {}
var _visual_count := 0
var _visual_color := Color(0.85, 0.9, 1.0)
var _gc_t := 0.0

func _ready() -> void:
	z_index = 6

func _prune_invalid_cooldowns() -> void:
	for tracked_enemy in _cds.keys():
		if not is_instance_valid(tracked_enemy):
			_cds.erase(tracked_enemy)

func _sync_visual(count: int) -> void:
	var evolved: bool = holder != null and is_instance_valid(holder) and holder.get("weapon_level") != null and int(holder.get("weapon_level")) >= 4
	var blade_color := Color(1.0, 0.8, 0.25) if evolved else Color(0.85, 0.9, 1.0)
	if count == _visual_count and blade_color == _visual_color:
		return
	for c in get_children():
		c.queue_free()
	for i in count:
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([Vector2(14, 0), Vector2(4, 5), Vector2(-14, 0), Vector2(-4, -5)])
		poly.color = blade_color
		add_child(poly)
	_visual_count = count
	_visual_color = blade_color

func _physics_process(delta: float) -> void:
	var count := 1
	var speed_mult := 1.0
	var dmg_mult := 1.0
	var atk_mult := 1.0
	if holder != null and is_instance_valid(holder):
		count = maxi(int(holder.get("saw_count")), 1)
		speed_mult = float(holder.get("saw_speed_mult"))
		dmg_mult = float(holder.get("saw_dmg_mult"))
		atk_mult = float(holder.get("attack_speed_mult"))
	_sync_visual(count)
	_angle += 6.5 * speed_mult * delta
	# 伤害结算频率与视觉严格匹配：面板攻速×刃数→每刃结算间隔（转速加成同攻速源）
	tick = base_tick / maxf(atk_mult * count, 0.01)
	for i in count:
		var ang := _angle + TAU * i / count
		var blade_pos := Vector2.RIGHT.rotated(ang) * orbit_r
		var child := get_child(i)
		if child != null and is_instance_valid(child):
			child.position = blade_pos
			child.rotation = ang * 3.0
	if holder == null or not is_instance_valid(holder):
		return
	_gc_t += delta
	if _gc_t > 5.0:
		_prune_invalid_cooldowns()
		_gc_t = 0.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		_cds[e] = float(_cds.get(e, 0.0)) - delta
	for i in count:
		var blade_pos: Vector2 = Vector2.RIGHT.rotated(_angle + TAU * i / count) * orbit_r
		var wp: Vector2 = holder.position + blade_pos
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e) or float(_cds.get(e, 0.0)) > 0.0:
				continue
			if wp.distance_to(e.position) <= e.radius + 16.0:  # 判定=刃长，扫到即结算
				_cds[e] = tick
				var v: float = dmg_base * dmg_mult
				if dmg_cb.is_valid():
					v = dmg_cb.call(v, e)
				e.take_damage(v, holder)
