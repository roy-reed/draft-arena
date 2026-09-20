extends "res://scripts/enemy.gd"
# 吐弹敌人：接近到中距后停驻，周期向玩家发射敌弹（ebullet.gd）

var ebullet_spawner := Callable()  # func(pos, dir, speed, dmg)
var fire_interval := 1.9
const HOLD_RANGE := 300.0

var _fire_t := 1.4

func _ready() -> void:
	if not is_elite:
		contact_damage = 7.0
		radius = 15.0
	super()

func _skin_name() -> String:
	return "enemy_spitter"

func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if position.distance_to(player.position) > HOLD_RANGE + 60.0:
		super(delta)  # 远距追击（含接触判定）
	else:
		_try_touch(delta)
	_fire_t -= delta
	if _fire_t <= 0.0:
		_fire_t = fire_interval
		_fire()

func _fire() -> void:
	if not ebullet_spawner.is_valid():
		return
	ebullet_spawner.call(global_position, (player.global_position - global_position).normalized(), 240.0, 8.0)
