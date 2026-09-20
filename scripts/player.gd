extends Node2D
# 灰盒玩家：纯 Node2D + 距离判定，不使用物理引擎
# 三角色共享本脚本，只差数值/体型/起始武器（配置见 main.gd CHARS）

signal died

var char_id := "ranger"
var owned_passives: Array = []  # 本局已选被动 id（选牌聚焦加权用）
var max_hp := 100.0
var hp := 100.0
var speed := 220.0
var damage_mult := 1.0
var attack_speed_mult := 1.0
var base_interval := 0.85
var weapon_id := "w_dragon"
var weapon_level := 1
var thorns := 0.0
var lifesteal := 0.0
var magnet := 0
var berserk := false
var slow_on_hit := false
var giant_slayer := 0.0
var revenge := false
var bounce := 0
var gold_chance := 0.0
var double_chance := 0.0

# 武器线参数（升级卡驱动；基线与 GDD §5 一致）
var bullet_pierce_bonus := 0
var dragon_dmg_mult := 1.0
var sniper_pierce := 2
var sniper_dmg_mult := 1.0
var saw_count := 1
var saw_speed_mult := 1.0
var saw_dmg_mult := 1.0
var boom_count := 1
var boom_dmg_mult := 1.0
var boom_size_mult := 1.0
var pellet_count := 3
var pellet_dmg_mult := 1.0
var arc_targets := 2
var arc_dmg_mult := 1.0

# 天赋参数
var regen := 0.0
var swift := false
var swift_t := 0.0
var armor := 0.0
var grit := false
var burst := false
var crit_chance := 0.0
var drafting := false  # 升级选卡期间 true：伤害强制为 0（防冻结白嫖）
var last_crit := false  # 最近一次伤害计算是否暴击（用于大字号显示）

var arena := Rect2(40, 40, 1200, 640)
var bullet_spawner := Callable()
var boomerang_spawner := Callable()
var active := true
var dead := false
var invuln := 0.0
var radius := 16.0
var shape := "circle"
var body_color := Color(0.35, 0.75, 1.0)

var _cd := 0.6
var _sawblade: Node2D = null
var _vis: Node2D = null
var _anim_t := 0.0

const CardsS := preload("res://scripts/cards.gd")
const SawbladeS := preload("res://scripts/sawblade.gd")
const BASE_HIT_KNOCKBACK := 130.0
const SHOTGUN_HIT_KNOCKBACK := 155.0

func setup(cfg: Dictionary, level: int) -> void:
	char_id = cfg["id"]
	max_hp = float(cfg["hp"]) + 5.0 * level
	hp = max_hp
	speed = float(cfg["speed"])
	damage_mult = float(cfg.get("dmg_mult", 1.0)) + 0.02 * level
	radius = float(cfg["radius"])
	shape = cfg["shape"]
	body_color = cfg["color"]
	set_weapon(cfg["weapon"])

func _ready() -> void:
	z_index = 5
	var poly := Polygon2D.new()
	poly.polygon = _shape_points()
	poly.color = body_color
	add_child(poly)
	_vis = poly
	var tex := ArtS.skin("player_" + char_id)
	if tex != null:
		poly.visible = false
		var spr := Sprite2D.new()
		spr.texture = tex
		var s := radius * 2.0 / float(tex.get_width())
		spr.scale = Vector2(s, s)
		add_child(spr)
		_vis = spr

func _shape_points() -> PackedVector2Array:
	var n := 16
	var off := 0.0
	match shape:
		"square":
			n = 4
			off = PI / 4.0
		"triangle":
			n = 3
	var pts := PackedVector2Array()
	for i in n:
		pts.append(Vector2.RIGHT.rotated(TAU * i / n - PI / 2.0 + off) * radius)
	return pts

func set_weapon(id: String) -> void:
	weapon_id = id
	weapon_level = 1
	if id == "w_sawblade":
		_ensure_sawblade()
	else:
		_remove_sawblade()


func hit_knockback_strength() -> float:
	return SHOTGUN_HIT_KNOCKBACK if weapon_id == "w_shotgun" else BASE_HIT_KNOCKBACK

func upgrade_weapon() -> void:
	weapon_level += 1
	match [weapon_id, weapon_level]:
		["w_dragon", 2]:
			sniper_pierce += 2
			dragon_dmg_mult += 0.15  # 穿透配套小幅增伤
		["w_dragon", 3]:
			dragon_dmg_mult += 0.45
			giant_slayer += 0.15
		["w_dragon", 4]:  # 进化：灭世
			dragon_dmg_mult += 0.5
			sniper_pierce += 3
			attack_speed_mult += 0.2
		["w_sniper", 2]:
			sniper_pierce += 2
		["w_sniper", 3]:
			sniper_dmg_mult += 0.45
			giant_slayer += 0.15
		["w_sniper", 4]:  # 进化：湮灭射线
			sniper_dmg_mult += 0.5
			sniper_pierce += 3
			giant_slayer += 0.2
		["w_sawblade", 2]:
			saw_count += 1
		["w_sawblade", 3]:
			saw_speed_mult += 0.45
			saw_dmg_mult += 0.3
		["w_sawblade", 4]:  # 进化：千刃风暴
			saw_count += 2
			saw_speed_mult += 0.3
		["w_boomerang", 2]:
			boom_dmg_mult += 0.35
			boom_size_mult += 0.4
		["w_boomerang", 3]:
			boom_count += 1
		["w_boomerang", 4]:  # 进化：裂空
			boom_count += 2
			boom_size_mult += 0.6
			boom_dmg_mult += 0.3
		["w_shotgun", 2]:
			pellet_count += 2
		["w_shotgun", 3]:
			pellet_dmg_mult += 0.8
		["w_shotgun", 4]:  # 进化：龙息
			pellet_count += 3
			pellet_dmg_mult += 0.4
		["w_arc", 2]:
			arc_targets += 1
		["w_arc", 3]:
			arc_dmg_mult += 0.5
		["w_arc", 4]:  # 进化：雷暴
			arc_targets += 2
			arc_dmg_mult += 0.5

func glass_cannon() -> void:
	damage_mult += 0.4
	add_max_hp(-20.0)

func on_kill() -> void:
	if swift:
		swift_t = 1.5

func _ensure_sawblade() -> void:
	if _sawblade != null and is_instance_valid(_sawblade):
		return
	var blade := SawbladeS.new()
	blade.holder = self
	blade.dmg_cb = func(base, target): return current_damage(base, target)
	_sawblade = blade
	add_child(blade)

func _remove_sawblade() -> void:
	if _sawblade != null and is_instance_valid(_sawblade):
		_sawblade.queue_free()
	_sawblade = null

func has_passive(id: String) -> bool:
	return id in owned_passives

func add_max_hp(v: float) -> void:
	max_hp = maxf(max_hp + v, 1.0)
	hp = minf(hp + maxf(v, 0.0), max_hp)  # 负值（玻璃大炮）只压上限，不扣当前血

func _physics_process(delta: float) -> void:
	if not active or dead:
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var move_mult := 1.25 if swift_t > 0.0 else 1.0
	position += dir * speed * move_mult * delta
	position = position.clamp(arena.position + Vector2.ONE * radius, arena.end - Vector2.ONE * radius)
	invuln = maxf(invuln - delta, 0.0)
	swift_t = maxf(swift_t - delta, 0.0)
	_anim_t += delta * (6.0 if dir != Vector2.ZERO else 3.0)
	if _vis != null and is_instance_valid(_vis):
		_vis.position.y = sin(_anim_t) * 1.5  # 待机/移动浮动，让灰盒也有生命感
	if regen > 0.0 and hp < max_hp:
		hp = minf(hp + regen * delta, max_hp)
	var rate := attack_speed_mult
	if berserk and hp < max_hp * 0.3:
		rate *= 1.3
	_cd -= delta * rate
	if _cd <= 0.0:
		_shoot()

func current_damage(base: float, target: Node2D) -> float:
	if drafting:
		last_crit = false
		return 0.0
	var dmg := base * damage_mult
	if revenge:
		dmg *= 1.0 + 0.04 * floorf((max_hp - hp) / max_hp * 10.0)
	if grit and hp < max_hp * 0.5:
		dmg *= 1.2
	if target != null and target.get("is_elite"):
		dmg *= 1.0 + giant_slayer
	last_crit = false
	if crit_chance > 0.0 and randf() < crit_chance:
		dmg *= 2.0
		last_crit = true
	return dmg

func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_d := 1e9
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var d: float = position.distance_to(e.position)
		if d < best_d:
			best_d = d
			best = e
	return best

func _nearest_enemies(n: int, max_dist: float) -> Array:
	var list := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and position.distance_to(e.position) <= max_dist:
			list.append(e)
	list.sort_custom(func(a, b): return position.distance_squared_to(a.position) < position.distance_squared_to(b.position))
	return list.slice(0, n)

func _shoot() -> void:
	var mult: float = CardsS.WEAPONS.get(weapon_id, {"interval_mult": 1.0})["interval_mult"]
	match weapon_id:
		"w_sawblade":
			_cd = 0.3  # 持续接触伤害由环刃节点结算
			return
		"w_arc":
			var targets := _nearest_enemies(arc_targets, 340.0)
			if targets.is_empty():
				_cd = 0.15
				return
			_cd = base_interval * mult
			for t in targets:
				if is_instance_valid(t):
					t.take_damage(current_damage(12.0 * arc_dmg_mult, t), self)
			SFX.play("hit")
			if randf() < double_chance:  # fx: 电弧表现接入点
				for t in targets:
					if is_instance_valid(t):
						t.take_damage(current_damage(12.0 * arc_dmg_mult, t), self)
			return
	var target := _nearest_enemy()
	if target == null:
		_cd = 0.15
		return
	_cd = base_interval * mult
	var base_dir: Vector2 = (target.position - position).normalized()
	match weapon_id:
		"w_dragon":
			_fire(target, 18.0 * dragon_dmg_mult, 2 + bullet_pierce_bonus)
		"w_shotgun":
			for i in pellet_count:
				_fire_dir(base_dir.rotated((i - (pellet_count - 1) / 2.0) * 0.22), 6.0 * pellet_dmg_mult, 0, target)
		"w_sniper":
			_fire(target, 26.0 * sniper_dmg_mult, sniper_pierce)
		"w_boomerang":
			for i in boom_count:
				_fire_dir(base_dir.rotated((i - (boom_count - 1) / 2.0) * 0.35), 9.0 * boom_dmg_mult, 0, target)
	if randf() < double_chance:
		if weapon_id == "w_shotgun":
			_fire_dir(base_dir, 6.0 * pellet_dmg_mult, 0, target)
		elif weapon_id == "w_boomerang":
			_fire_dir(base_dir.rotated(0.35), 9.0 * boom_dmg_mult, 0, target)
		elif weapon_id == "w_dragon":
			_fire(target, 18.0 * dragon_dmg_mult, 4 + bullet_pierce_bonus)
		else:
			_fire(target, 26.0 * sniper_dmg_mult, sniper_pierce)

func _fire(target: Node2D, base_dmg: float, pierce: int) -> void:
	_fire_dir((target.position - position).normalized(), base_dmg, pierce, target)

func _fire_dir(dir: Vector2, base_dmg: float, pierce: int, target: Node2D) -> void:
	if weapon_id == "w_boomerang":
		if boomerang_spawner.is_valid():
			boomerang_spawner.call(position, dir, current_damage(base_dmg, target), self)
			SFX.play("shoot")
		return
	if not bullet_spawner.is_valid():
		return
	bullet_spawner.call(position, dir, current_damage(base_dmg, target), pierce, bounce, self)
	SFX.play("shoot")

func take_damage(amount: float, source: Node2D) -> void:
	if dead or invuln > 0.0:
		return
	amount = maxf(amount - armor, 1.0)
	hp -= amount
	invuln = 0.6
	FX.shake(5.0)
	FX.hit_stop(0.05)
	FX.hurt_vignette()
	SFX.play("hurt")
	modulate = Color(1, 0.4, 0.4)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, 0.25)
	if thorns > 0.0 and source != null and is_instance_valid(source) and source.has_method("take_damage"):
		source.take_damage(thorns, self)
	if hp <= 0.0:
		hp = 0.0
		dead = true
		died.emit()
