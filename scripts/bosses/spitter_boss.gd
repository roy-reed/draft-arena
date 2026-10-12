class_name SpitterBoss
extends BossBase

## Region 2 member behavior. The encounter owns twin/revival rules.

@export var preferred_distance := 240.0
@export var initial_fire_delay := 1.6
@export var volley_interval := 2.1
@export var projectile_damage := 9.0

var _fire_time := 0.0
var _volley_count := 0
var _attack_visual_time := 0.0


func required_services() -> Array[StringName]:
	return [&"spawn_enemy_projectile"]


func _ready() -> void:
	super()
	if not _configured:
		return
	_fire_time = initial_fire_delay
	change_state(&"move")


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var to_player := player.position - position
	if to_player.length() > preferred_distance:
		var direction := to_player.normalized()
		position += direction * speed * delta
		position = position.clamp(arena.position + Vector2.ONE * radius, arena.end - Vector2.ONE * radius)
		EnemyGrid.moved(self)
		face_direction(direction)
	if _spawn_guard <= 0.0:
		_try_touch(delta)

	_fire_time -= delta
	if _fire_time <= 0.0:
		_fire_time = volley_interval
		_fire_volley()
		_attack_visual_time = 0.2
		change_state(&"attack")
	if _attack_visual_time > 0.0:
		_attack_visual_time -= delta
		if _attack_visual_time <= 0.0:
			change_state(&"move")


func _fire_volley() -> void:
	_volley_count += 1
	var origin := anchor_global_position(&"ProjectileOrigin")
	if _volley_count % 2 == 1:
		var offset := encounter_context.rng.randf() * TAU
		for i in 10:
			var direction := Vector2.RIGHT.rotated(offset + TAU * i / 10.0)
			services.spawn_enemy_projectile.call(origin, direction, 200.0, projectile_damage)
	else:
		var base := (player.global_position - origin).normalized()
		for i in 3:
			services.spawn_enemy_projectile.call(origin, base.rotated((i - 1) * 0.25), 260.0, projectile_damage)


func _visual_cue_for_state(state_id: StringName) -> StringName:
	match state_id:
		&"move":
			return &"move"
		&"attack":
			return &"attack"
		_:
			return state_id
