extends CanvasLayer
class_name TouchControls
# 触屏操作层（手游版 M1）：浮动虚拟摇杆 + 暂停按钮。
# - 摇杆在触摸事件里直接写入 move_vector，player 经 movement_dir() 读取，不经 InputMap，
#   避免 deadzone 重映射造成的跟手延迟；桌面端 move_active=false，仍走原 Input.get_vector。
# - 呼出位置自由：左半屏按下处即为摇杆中心，松手后隐藏并清零移动；仅触屏显示。
# - 仅在触屏设备上显示：移动端导出（OS feature "mobile"）启动即启用；桌面端只有真的收到
#   InputEventScreenTouch 才启用，因此没有触屏的桌面行为与原来完全一致。

signal touch_mode_changed(enabled: bool)
# 最近一次输入来自触屏(true)还是键盘/手柄(false)，用于切换提示文案（M2）
signal input_kind_changed(touch: bool)

const ACTIONS := ["move_left", "move_right", "move_up", "move_down"]
const STICK_RADIUS := 90.0        # 摇杆最大偏移（视口像素，基准 1280×720）
const STICK_ZONE_X := 0.5         # 左半屏按下才启动摇杆
const PAUSE_BTN_SIZE := Vector2(72, 72)
const GAMEPLAY_STATES := ["inter", "wave"]  # 允许摇杆与暂停按钮的状态
# 摇杆视觉位置变化超过该平方距离才 queue_redraw（约 0.5px），避免无意义重绘
const REDRAW_EPS2 := 0.25

static var force_touch := -1  # 测试用：-1 自动，0 强制关，1 强制开
# 触摸直接写入的移动向量；move_active 时 movement_dir() 优先返回它，绕过 InputMap
static var move_active := false
static var move_vector := Vector2.ZERO

var main: Node = null             # 需提供 state、paused 与 request_pause()
var touch_enabled := false
var pause_button: Button
var _stick_index := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _stick_draw: Node2D
var _draw_dirty := false
var _last_knob := Vector2(INF, INF)
var safe_root: Control
var last_input_touch := false


static func detect_touch_device() -> bool:
	if force_touch >= 0:
		return force_touch == 1
	return OS.has_feature("mobile")


# 纯函数：触点相对摇杆中心的偏移 → 归一化摇杆向量（长度 ≤ 1）。无 InputMap deadzone。
static func stick_vector(offset: Vector2, radius: float) -> Vector2:
	if radius <= 0.0:
		return Vector2.ZERO
	var v := offset / radius
	return v.limit_length(1.0)


# 玩家移动读取入口：触屏摇杆激活时用直接向量，否则与桌面一致走 Input.get_vector。
static func movement_dir() -> Vector2:
	if move_active:
		return move_vector
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


static func _clear_move() -> void:
	move_active = false
	move_vector = Vector2.ZERO


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_stick_draw = Node2D.new()
	_stick_draw.draw.connect(_draw_stick)
	add_child(_stick_draw)
	safe_root = Control.new()
	safe_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(safe_root)
	pause_button = Button.new()
	pause_button.text = "II"
	pause_button.add_theme_font_size_override("font_size", 28)
	pause_button.custom_minimum_size = PAUSE_BTN_SIZE
	pause_button.size = PAUSE_BTN_SIZE
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.pressed.connect(_on_pause_pressed)
	safe_root.add_child(pause_button)
	# 锚在安全区右上角（基准 1280×720 时 x=1192, y=16）
	pause_button.anchor_left = 1.0
	pause_button.anchor_right = 1.0
	pause_button.offset_left = -PAUSE_BTN_SIZE.x - 16
	pause_button.offset_right = -16
	pause_button.offset_top = 16
	pause_button.offset_bottom = 16 + PAUSE_BTN_SIZE.y
	last_input_touch = detect_touch_device()
	set_touch_enabled(detect_touch_device())


func apply_safe_area(m: Vector4) -> void:
	safe_root.offset_left = m.x
	safe_root.offset_top = m.y
	safe_root.offset_right = -m.z
	safe_root.offset_bottom = -m.w


func _note_input_kind(touch: bool) -> void:
	if touch != last_input_touch:
		last_input_touch = touch
		input_kind_changed.emit(touch)


func set_touch_enabled(v: bool) -> void:
	var changed := v != touch_enabled
	touch_enabled = v
	if not v:
		_end_stick()
	_refresh()
	if changed:
		touch_mode_changed.emit(v)


func gameplay_active() -> bool:
	return main != null and str(main.get("state")) in GAMEPLAY_STATES and not bool(main.get("paused"))


func _process(_delta: float) -> void:
	_refresh()
	if _draw_dirty:
		_draw_dirty = false
		_stick_draw.queue_redraw()


func _refresh() -> void:
	var active := touch_enabled and gameplay_active()
	if pause_button != null:
		pause_button.visible = active
	if not active and _stick_index >= 0:
		_end_stick()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_note_input_kind(true)
		if not touch_enabled and force_touch != 0:
			set_touch_enabled(true)
	elif (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed():
		_note_input_kind(false)
	if not touch_enabled:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _stick_index < 0 and gameplay_active() and _in_stick_zone(t.position):
			_stick_index = t.index
			_stick_origin = t.position  # 按下处即为中心（自由呼出）
			_stick_pos = t.position
			_last_knob = Vector2(INF, INF)  # 强制重绘新中心
			_update_stick()
			get_viewport().set_input_as_handled()
		elif not t.pressed and t.index == _stick_index:
			_end_stick()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_index:
			_stick_pos = d.position
			_update_stick()
			get_viewport().set_input_as_handled()


func _in_stick_zone(p: Vector2) -> bool:
	var vp := get_viewport().get_visible_rect().size
	return p.x <= vp.x * STICK_ZONE_X


func _update_stick() -> void:
	if not gameplay_active():
		_end_stick()
		return
	# 触摸事件内直接写向量，保证早于同帧 _physics_process 的玩家读取
	move_vector = stick_vector(_stick_pos - _stick_origin, STICK_RADIUS)
	move_active = true
	var knob := _stick_origin + move_vector * STICK_RADIUS
	if knob.distance_squared_to(_last_knob) > REDRAW_EPS2:
		_last_knob = knob
		_draw_dirty = true


func _end_stick() -> void:
	_stick_index = -1
	_clear_move()
	_last_knob = Vector2(INF, INF)
	if _stick_draw != null:
		_draw_dirty = true


func is_stick_active() -> bool:
	return _stick_index >= 0


func stick_origin() -> Vector2:
	return _stick_origin


func _draw_stick() -> void:
	if _stick_index < 0:
		return
	var knob := _stick_origin + stick_vector(_stick_pos - _stick_origin, STICK_RADIUS) * STICK_RADIUS
	_stick_draw.draw_circle(_stick_origin, STICK_RADIUS, Color(1, 1, 1, 0.12))
	_stick_draw.draw_arc(_stick_origin, STICK_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0)
	_stick_draw.draw_circle(knob, 34.0, Color(1, 1, 1, 0.35))


func _on_pause_pressed() -> void:
	if main != null and main.has_method("request_pause"):
		main.request_pause()


func _exit_tree() -> void:
	if move_active:
		_clear_move()
