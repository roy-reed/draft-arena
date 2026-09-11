extends "res://scripts/enemy.gd"
# 区域 2 首领（吐弹型，成对）：缓慢逼近，交替环形弹幕与瞄准 3 连散射
# 连锁机制：双首领需 10s 内相继击杀；超时存活者复活已死的搭档（满血）

var ebullet_spawner := Callable()  # func(pos, dir, speed, dmg)
var twin_cb := Callable()          # func(pos)：超时复活搭档
const TWIN_WINDOW := 10.0

var _fire_t := 1.6
var _volley_n := 0
var _twin_t := 0.0
var _twin_dead := false  # 搭档已死：进入 10s 连锁倒计时
var other: Node2D = null  # 双首领搭档（死亡时通知其开启连锁倒计时）

func _ready() -> void:
	radius = 34.0
	contact_damage = 15.0
	coin = 15
	is_elite = true
	speed = 42.0
	body_color = Color(0.65, 0.35, 0.9)
	super()

func _skin_name() -> String:
	return "boss_spitter"

func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var d := position.distance_to(player.position)
	if d > 240.0:  # 保持中距压迫，不贴脸
		var dirv := (player.position - position).normalized()
		position += dirv * speed * delta
		position = position.clamp(arena.position + Vector2.ONE * radius, arena.end - Vector2.ONE * radius)
	if _spawn_guard <= 0.0:
		_try_touch(delta)
	_fire_t -= delta
	if _fire_t <= 0.0:
		_fire_t = 2.1
		_volley()
	if other != null and not _twin_dead:
		var twin_gone: bool = (not is_instance_valid(other)) or other._dead
		if twin_gone:
			_twin_dead = true
			_twin_t = TWIN_WINDOW  # 搭档阵亡：10s 内杀死本只即通关，否则复活搭档
	if _twin_dead:
		_twin_t -= delta
		if _twin_t <= 0.0 and twin_cb.is_valid():
			_twin_dead = false
			_twin_t = 0.0
			twin_cb.call(position + Vector2(90, 0))

func _volley() -> void:
	if not ebullet_spawner.is_valid() or player == null or not is_instance_valid(player):
		return
	_volley_n += 1
	if _volley_n % 2 == 1:
		var off := randf() * TAU
		for i in 10:
			ebullet_spawner.call(position, Vector2.RIGHT.rotated(off + TAU * i / 10.0), 200.0, 9.0)
	else:
		var base := (player.position - position).normalized()
		for i in 3:
			ebullet_spawner.call(position, base.rotated((i - 1) * 0.25), 260.0, 9.0)
