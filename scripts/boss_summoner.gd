extends "res://scripts/enemy.gd"
# 区域 3 / 无尽首领（召唤型）：缓慢追击 + 周期召唤金级小怪（近战+远程成对，每三次精英对）
# 激光：每 5s 从法杖释放——0.5s 暗色预警线（方向锁定给反应窗口）→ 0.3s 亮绿主激光（16 伤）

var summon_cb := Callable()  # func(pos, kind, elite)，由主流程按最高难度档位生成

const SUMMON_INTERVAL := 3.2
const MAX_MINIONS := 8
const LASER_COOLDOWN := 3.5
const LASER_WARN := 0.4
const LASER_FIRE := 0.3
const LASER_RANGE := 900.0
const LASER_DMG := 16.0
var laser_mult := 1.0  # 区域 3 为 2.0（无尽随机也可调）

var _summon_t := 2.0
var _summon_n := 0
var laser_t := 5.0
var _laser_phase := 0  # 0 冷却 1 预警 2 发射
var _laser_dir := Vector2.RIGHT
var _laser_line: Line2D = null
var _laser_t2 := 0.0

func _ready() -> void:
	radius = 34.0
	contact_damage = 16.0
	coin = 15
	is_elite = true
	speed = 38.0
	body_color = Color(0.3, 0.8, 0.45)
	super()

func _skin_name() -> String:
	return "boss_summoner"

func _physics_process(delta: float) -> void:
	_summon_t -= delta
	if _summon_t <= 0.0:
		_summon_t = SUMMON_INTERVAL
		_summon()
	_tick_laser(delta)
	super(delta)

func _summon() -> void:
	if not summon_cb.is_valid():
		return
	var alive := 0
	for m in get_tree().get_nodes_in_group("minions"):
		if is_instance_valid(m):
			alive += 1
	if alive >= MAX_MINIONS:
		return
	_summon_n += 1
	var elite := _summon_n % 3 == 0
	summon_cb.call(position + Vector2.RIGHT.rotated(randf() * TAU) * 70.0, "melee", elite)
	summon_cb.call(position + Vector2.RIGHT.rotated(randf() * TAU) * 70.0, "ranged", elite)

func _tick_laser(delta: float) -> void:
	if laser_t > 0.0:
		laser_t -= delta
		return
	var staff := position + Vector2(14, -15)  # 法杖宝珠：贴图 40px 中 disc(34,5)，居中锚点偏移 (34-20, 5-20)
	match _laser_phase:
		0:
			if player == null or not is_instance_valid(player):
				return
			_laser_phase = 1
			_laser_dir = (player.position - staff).normalized()  # 瞄准瞬间锁定方向，给 0.5s 反应窗口
			_laser_line = _make_laser_line(Color(0.5, 1.0, 0.6, 0.3), 2.0)
			_laser_t2 = LASER_WARN
		1:
			_laser_t2 -= delta
			if _laser_t2 <= 0.0:
				_laser_phase = 2
				if _laser_line != null and is_instance_valid(_laser_line):
					_laser_line.queue_free()
				_laser_line = _make_laser_line(Color(0.6, 1.0, 0.7), 7.0)
				_laser_t2 = LASER_FIRE
				if player != null and is_instance_valid(player):
					# 点到线段距离判定（线段起点法杖，长 LASER_RANGE）
					var to_p: Vector2 = player.position - staff
					var proj: float = clampf(to_p.dot(_laser_dir), 0.0, LASER_RANGE)
					var perp: float = (to_p - _laser_dir * proj).length()
					if perp <= 12.0 + player.radius:
						player.take_damage(LASER_DMG * laser_mult, self)
		2:
			_laser_t2 -= delta
			if _laser_t2 <= 0.0:
				if _laser_line != null and is_instance_valid(_laser_line):
					_laser_line.queue_free()
				_laser_line = null
				_laser_phase = 0
				laser_t = LASER_COOLDOWN

func _make_laser_line(c: Color, w: float) -> Line2D:
	var line := Line2D.new()
	var staff := position + Vector2(14, -15)
	line.points = PackedVector2Array([staff, staff + _laser_dir * LASER_RANGE])
	line.width = w
	line.default_color = c
	add_child(line)
	return line
