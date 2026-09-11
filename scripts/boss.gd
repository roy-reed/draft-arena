extends "res://scripts/enemy.gd"
# 灰盒首领：追击 → 蓄力示警 → 直线冲锋 → 硬直循环

var _state := "chase"
var _state_t := 3.0
var _dash_dir := Vector2.ZERO

func _ready() -> void:
	radius = 34.0
	contact_damage = 18.0
	coin = 15
	is_elite = true
	speed = 60.0
	body_color = Color(0.85, 0.25, 0.2)
	super()

func _skin_name() -> String:
	return "boss_charge"

func _physics_process(delta: float) -> void:
	_state_t -= delta
	match _state:
		"chase":
			super(delta)
			if _state_t <= 0.0:
				_state = "aim"
				_state_t = 0.7
				modulate = Color(1, 0.9, 0.3)
		"aim":
			if player != null and is_instance_valid(player):
				_dash_dir = (player.position - position).normalized()
			if _state_t <= 0.0:
				_state = "dash"
				_state_t = 0.55
				modulate = Color.WHITE
				FX.shake(6.0)
				SFX.play("dash")
		"dash":
			position += _dash_dir * 520.0 * delta
			position = position.clamp(arena.position + Vector2.ONE * radius, arena.end - Vector2.ONE * radius)
			_try_touch(delta)
			if _state_t <= 0.0:
				_state = "rest"
				_state_t = 1.2
		"rest":
			if _state_t <= 0.0:
				_state = "chase"
				_state_t = randf_range(2.2, 3.2)
