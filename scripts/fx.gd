class_name FX
extends Node
# 打击感表现层（自包含）：屏震 / 顿帧 / 伤害数字 / 命中火花 / 死亡爆裂 / 击退 / 面板弹入 / 受击红晕。
# 用法：main 把本节点 add_child 进树后，任何脚本直接调用静态方法（如 FX.shake(5.0)），无需 preload。
# 未挂载（I == null）或 enabled == false 时所有调用静默跳过，headless 与 smoke 自测零副作用。
# 不含音频、不引用外部素材、不使用物理引擎；伤害数字用完即回收，爆裂粒子走对象池复用。

static var I: FX = null

var enabled := true

const SHAKE_MAX := 9.0         # trauma 累积上限
const SHAKE_DECAY := 16.0      # trauma 每秒衰减量
const SHAKE_STRENGTH := 0.2    # 偏移像素 = trauma * trauma * 该系数
const STOP_SCALE := 0.05       # 顿帧期间的 Engine.time_scale
const STOP_COOLDOWN_MS := 100  # 顿帧真实时间冷却

var _trauma := 0.0
var _shaking := false
var _shake_base := Vector2.ZERO
var _stop_active := false
var _stop_end_ms := 0
var _stop_scale_backup := 1.0
var _last_stop_ms := -1000000
var _vig_layer: CanvasLayer = null
var _vig_rect: ColorRect = null
var _vig_tw: Tween = null


func _ready() -> void:
	I = self


func _exit_tree() -> void:
	# 兜底：节点被移除时恢复 time_scale 与父节点位置，避免场景重载残留
	if _stop_active:
		Engine.time_scale = _stop_scale_backup
		_stop_active = false
	if _shaking and get_parent() is Node2D:
		(get_parent() as Node2D).position = _shake_base
		_shaking = false
	if I == self:
		I = null


func _process(delta: float) -> void:
	_tick_hit_stop()
	_tick_shake(delta)
	_tick_bursts(delta)


# ---- 静态入口：调用点无需判空 ----


static func shake(amount: float) -> void:
	if I == null or not I.enabled:
		return
	I._trauma = minf(I._trauma + maxf(amount, 0.0), SHAKE_MAX)


static func hit_stop(duration: float) -> void:
	if I == null or not I.enabled:
		return
	I._start_hit_stop(duration)


static func float_number(host: Node2D, amount: float, big := false) -> void:
	if I == null or not I.enabled:
		return
	I._spawn_float_number(host, amount, big)


static func hit_spark(pos: Vector2, color: Color) -> void:
	if I == null or not I.enabled:
		return
	I._spawn_burst(pos, color, 10, 0.28, 70.0, 200.0, 3.0, 5.0, Vector2.ZERO)


static func death_burst(pos: Vector2, color: Color, amount := 26) -> void:
	if I == null or not I.enabled:
		return
	I._spawn_burst(pos, color, amount, 0.5, 140.0, 340.0, 5.0, 9.0, Vector2(0.0, 260.0))
	shake(1.5)


static func knockback(host: Node2D, dir: Vector2, strength := 130.0) -> void:
	if I == null or not I.enabled:
		return
	if host == null or not is_instance_valid(host) or dir == Vector2.ZERO:
		return
	var cur: Variant = host.get("kb")
	if cur is Vector2:
		host.set("kb", cur + dir.normalized() * maxf(strength, 0.0))


static func pop_in(control: Control) -> void:
	if I == null or not I.enabled:
		return
	I._pop_in(control)


static func hurt_vignette() -> void:
	if I == null or not I.enabled:
		return
	I._hurt_vignette()


# ---- 内部实现 ----


func _start_hit_stop(duration: float) -> void:
	if duration <= 0.0:
		return
	var now := Time.get_ticks_msec()
	if now - _last_stop_ms < STOP_COOLDOWN_MS:
		return
	_last_stop_ms = now
	if not _stop_active:
		_stop_scale_backup = Engine.time_scale
	Engine.time_scale = STOP_SCALE
	_stop_end_ms = now + roundi(duration * 1000.0)
	_stop_active = true


func _tick_hit_stop() -> void:
	# 用真实时间恢复：time_scale 会缩放 SceneTreeTimer 与 delta，不能拿来计时
	if _stop_active and Time.get_ticks_msec() >= _stop_end_ms:
		Engine.time_scale = _stop_scale_backup
		_stop_active = false


func _tick_shake(delta: float) -> void:
	if _trauma > 0.0:
		_trauma = maxf(_trauma - SHAKE_DECAY * delta, 0.0)
	var p := get_parent()
	if not (p is Node2D):
		return
	var p2d := p as Node2D
	if _trauma > 0.0:
		if not _shaking:
			_shaking = true
			_shake_base = p2d.position
		var s := _trauma * _trauma * SHAKE_STRENGTH
		p2d.position = _shake_base + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * s
	elif _shaking:
		p2d.position = _shake_base
		_shaking = false


func _spawn_float_number(host: Node2D, amount: float, big: bool) -> void:
	if host == null or not is_instance_valid(host):
		return
	var w := 120.0 if big else 80.0
	var l := Label.new()
	l.text = str(roundi(amount))
	l.top_level = true  # 脱离父变换，按世界坐标摆放，不随屏震漂移
	l.z_index = 50
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.custom_minimum_size = Vector2(w, 0.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 30 if big else 17)
	l.add_theme_color_override("font_color", Color(1.0, 0.8, 0.15) if big else Color(1.0, 1.0, 1.0))
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.02, 0.85))
	l.add_theme_constant_override("outline_size", 6 if big else 4)
	add_child(l)
	l.global_position = host.global_position + Vector2(randf_range(-10.0, 10.0) - w * 0.5, -26.0)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y - 24.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)


# ---- 粒子对象池（M3）：一次性爆裂粒子复用 CPUParticles2D，避免每次命中/击杀都 new + queue_free ----
# 参数与原实现逐项相同；回收条件同原实现（finished 或 lifetime + 1s 兜底）。
const POOL_MAX_IDLE := 48          # 空闲上限，超出的回收节点直接释放
static var bursts_created := 0     # 统计：累计新建的粒子节点数
static var bursts_spawned := 0     # 统计：累计发射次数
var _idle: Array[CPUParticles2D] = []
var _busy := {}                    # CPUParticles2D -> 剩余兜底时间（秒，受 time_scale 影响，同原 Timer）


func _spawn_burst(pos: Vector2, color: Color, amount: int, lifetime: float, v_min: float, v_max: float, s_min: float, s_max: float, gravity: Vector2) -> void:
	var p: CPUParticles2D = null
	while p == null and not _idle.is_empty():
		var cand: CPUParticles2D = _idle.pop_back()
		if is_instance_valid(cand):
			p = cand
	var fresh := p == null
	if fresh:
		p = CPUParticles2D.new()
		bursts_created += 1
		p.one_shot = true
		p.explosiveness = 1.0
		p.spread = 180.0
		p.z_index = 20
		p.finished.connect(_recycle_burst.bind(p))
	p.amount = amount
	p.lifetime = lifetime
	p.gravity = gravity
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.scale_amount_min = s_min
	p.scale_amount_max = s_max
	p.color = color
	if fresh:
		add_child(p)
	p.visible = true
	p.global_position = pos
	if fresh:
		p.emitting = true
	else:
		p.restart()
	_busy[p] = lifetime + 1.0
	bursts_spawned += 1


func _tick_bursts(delta: float) -> void:
	if _busy.is_empty():
		return
	for p in _busy.keys():
		_busy[p] -= delta
		if _busy[p] <= 0.0:
			_recycle_burst(p)


func _recycle_burst(p: CPUParticles2D) -> void:
	if not _busy.has(p):
		return
	_busy.erase(p)
	if not is_instance_valid(p):
		return
	p.emitting = false
	p.visible = false
	if _idle.size() < POOL_MAX_IDLE:
		_idle.append(p)
	else:
		p.queue_free()


func pool_idle_count() -> int:
	return _idle.size()


func pool_busy_count() -> int:
	return _busy.size()


func _pop_in(control: Control) -> void:
	if control == null or not is_instance_valid(control) or not control.is_inside_tree():
		return
	control.pivot_offset = control.size * 0.5
	control.modulate.a = 0.0
	control.scale = Vector2(0.9, 0.9)
	var tw := control.create_tween()
	tw.tween_method(_pop_step.bind(control), 0.9, 1.0, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(control, "modulate:a", 1.0, 0.15)


func _pop_step(s: float, control: Control) -> void:
	# 每步刷新 pivot：容器首帧尺寸未定型时也能保持居中缩放
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2(s, s)


func _hurt_vignette() -> void:
	if _vig_layer == null or not is_instance_valid(_vig_layer):
		_vig_layer = CanvasLayer.new()
		_vig_layer.layer = 8
		_vig_rect = ColorRect.new()
		_vig_rect.color = Color(0.85, 0.08, 0.08, 0.0)
		_vig_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_vig_layer)
		_vig_layer.add_child(_vig_rect)
		_vig_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _vig_tw != null and is_instance_valid(_vig_tw) and _vig_tw.is_valid():
		_vig_tw.kill()
	_vig_rect.color.a = 0.25
	_vig_tw = _vig_rect.create_tween()
	_vig_tw.tween_property(_vig_rect, "color:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
