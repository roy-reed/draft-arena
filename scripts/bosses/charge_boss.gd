class_name ChargeBoss
extends BossBase

## Region 1 behavior canary: chase -> windup -> dash -> recovery.
## Combat values are supplied by BossBase.configure before this node enters tree.

@export var chase_duration_min := 2.2
@export var chase_duration_max := 3.2
@export var initial_chase_duration := 3.0
@export var windup_duration := 0.7
@export var dash_duration := 0.55
@export var recovery_duration := 1.2
@export var dash_speed := 520.0

var _state_time := 0.0
var _dash_direction := Vector2.ZERO


func _ready() -> void:
	super()
	if not _configured:
		return
	_state_time = initial_chase_duration
	change_state(&"chase")


func _physics_process(delta: float) -> void:
	_state_time -= delta
	match get_state_id():
		&"chase":
			super(delta)
			if player != null and is_instance_valid(player):
				face_direction(player.position - position)
			if _state_time <= 0.0:
				_enter_state(&"aim", windup_duration)
				modulate = Color(1.0, 0.9, 0.3)
		&"aim":
			if player != null and is_instance_valid(player):
				_dash_direction = (player.position - position).normalized()
				face_direction(_dash_direction)
			if _state_time <= 0.0:
				_enter_state(&"dash", dash_duration)
				modulate = Color.WHITE
				FX.shake(6.0)
				SFX.play("dash")
		&"dash":
			position += _dash_direction * dash_speed * delta
			position = position.clamp(arena.position + Vector2.ONE * radius, arena.end - Vector2.ONE * radius)
			EnemyGrid.moved(self)
			_try_touch(delta)
			if _state_time <= 0.0:
				_enter_state(&"rest", recovery_duration)
		&"rest":
			if _state_time <= 0.0:
				var next_chase := encounter_context.rng.randf_range(chase_duration_min, chase_duration_max)
				_enter_state(&"chase", next_chase)


func _enter_state(next_state: StringName, duration: float) -> void:
	_state_time = duration
	change_state(next_state)


func _visual_cue_for_state(state_id: StringName) -> StringName:
	match state_id:
		&"chase":
			return &"move"
		&"aim":
			return &"windup"
		&"dash":
			return &"attack"
		&"rest":
			return &"idle"
		_:
			return state_id
