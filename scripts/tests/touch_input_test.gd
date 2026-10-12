extends SceneTree
# 手游版 M1：虚拟摇杆直接写移动向量、触屏显示条件、选牌点按聚焦、返回键映射；并确认非触屏（桌面）行为不变。
# 期望值均为独立写出的数值/表格，不调用被测函数计算期望。

const TouchControlsS := preload("res://scripts/touch_controls.gd")
const UIS := preload("res://scripts/ui.gd")
const MainS := preload("res://scripts/main.gd")

class FakeMain extends Node:
	var state := "wave"
	var paused := false
	var pause_requests := 0
	func request_pause() -> void:
		pause_requests += 1

var _failures := PackedStringArray()
var _picked: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_stick_math()
	_test_direct_move()
	_test_back_action()
	await _test_touch_layer()
	await _test_draft_cards()
	TouchControlsS.force_touch = -1
	TouchControlsS._clear_move()
	if _failures.is_empty():
		print("TOUCH_INPUT_OK")
		quit(0)
	else:
		for f in _failures:
			push_error("TOUCH_INPUT_FAIL: %s" % f)
		quit(1)


func _test_stick_math() -> void:
	_expect_vec(TouchControlsS.stick_vector(Vector2(90, 0), 90.0), Vector2(1, 0), "full right")
	_expect_vec(TouchControlsS.stick_vector(Vector2(45, 0), 90.0), Vector2(0.5, 0), "half right")
	_expect_vec(TouchControlsS.stick_vector(Vector2(0, -300), 90.0), Vector2(0, -1), "beyond radius clamps to 1")
	_expect_vec(TouchControlsS.stick_vector(Vector2(300, 400), 90.0), Vector2(0.6, 0.8), "diagonal clamps keeping direction")
	_expect_vec(TouchControlsS.stick_vector(Vector2(10, 10), 0.0), Vector2.ZERO, "zero radius is safe")


func _test_direct_move() -> void:
	# 直接向量：无 InputMap deadzone 重映射；小偏转也必须跟手（变异：若仍走 get_vector 会死区归零）
	TouchControlsS.move_active = true
	TouchControlsS.move_vector = Vector2(0.6, -0.8)
	_expect_vec(TouchControlsS.movement_dir(), Vector2(0.6, -0.8), "full-tilt direct vector")
	TouchControlsS.move_vector = Vector2(-0.3, 0.4)
	_expect_vec(TouchControlsS.movement_dir(), Vector2(-0.3, 0.4), "partial tilt not remapped by deadzone")
	TouchControlsS.move_vector = Vector2(0.1, 0.0)
	_expect_vec(TouchControlsS.movement_dir(), Vector2(0.1, 0.0), "small deflection still moves (bypasses 0.2 deadzone)")
	# 未激活时与桌面一致：走 Input.get_vector，且不污染 move_* 动作
	TouchControlsS._clear_move()
	_expect(not TouchControlsS.move_active, "clear deactivates direct move")
	_expect_vec(TouchControlsS.movement_dir(), Vector2.ZERO, "inactive direct move falls through to empty Input")
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		_expect(not Input.is_action_pressed(a), "%s not injected" % a)
	# 桌面键盘路径：模拟 action 后 movement_dir 必须等于 get_vector（变异：若总是返回 move_vector 会失败）
	Input.action_press("move_right", 1.0)
	_expect_vec(TouchControlsS.movement_dir(), Input.get_vector("move_left", "move_right", "move_up", "move_down"), "desktop path matches get_vector")
	_expect_vec(TouchControlsS.movement_dir(), Vector2(1, 0), "keyboard right via movement_dir")
	# 摇杆优先：激活直接向量时忽略 InputMap（变异：若先读 Input 会得到 (1,0)）
	TouchControlsS.move_active = true
	TouchControlsS.move_vector = Vector2(0, -1)
	_expect_vec(TouchControlsS.movement_dir(), Vector2(0, -1), "direct stick overrides InputMap")
	TouchControlsS._clear_move()
	Input.action_release("move_right")


func _test_back_action() -> void:
	var table := {
		["wave", false]: "pause", ["inter", false]: "pause", ["draft", false]: "pause", ["startpick", false]: "pause",
		["wave", true]: "resume", ["draft", true]: "resume", ["menu", true]: "resume",
		["over", false]: "restart", ["win", false]: "restart",
		["menu", false]: "quit",
	}
	for k in table:
		var got: String = MainS.back_action(k[0], k[1])
		_expect(got == table[k], "back_action(%s, %s) = %s (got %s)" % [k[0], k[1], table[k], got])


func _test_touch_layer() -> void:
	var fake := FakeMain.new()
	root.add_child(fake)
	# 桌面（非触屏）：默认不显示，暂停按钮隐藏
	TouchControlsS.force_touch = -1
	TouchControlsS._clear_move()
	var desktop: TouchControls = TouchControlsS.new()
	desktop.main = fake
	root.add_child(desktop)
	await process_frame
	_expect(not desktop.touch_enabled, "desktop starts without touch mode")
	_expect(not desktop.pause_button.visible, "desktop hides pause button")
	# 真的收到触屏事件后自动切到触屏模式
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = true
	ev.position = Vector2(200, 400)
	desktop._input(ev)
	_expect(desktop.touch_enabled, "first screen touch enables touch mode")
	_expect(desktop.is_stick_active(), "touch in left half grabs the stick during gameplay")
	_expect_vec(desktop.stick_origin(), Vector2(200, 400), "stick center is press position A")
	# 松手后隐藏，再在另一处按下：中心必须跟新触点（自由呼出）
	var lift_a := InputEventScreenTouch.new()
	lift_a.index = 0
	lift_a.pressed = false
	lift_a.position = Vector2(200, 400)
	desktop._input(lift_a)
	_expect(not desktop.is_stick_active(), "release hides stick")
	var ev_b := InputEventScreenTouch.new()
	ev_b.index = 0
	ev_b.pressed = true
	ev_b.position = Vector2(120, 520)
	desktop._input(ev_b)
	_expect(desktop.is_stick_active(), "second press re-shows stick")
	_expect_vec(desktop.stick_origin(), Vector2(120, 520), "stick center follows press position B")
	# 从 B 拖到满偏右，仍直接写 move_vector
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(210, 520)  # 自 B 向右满偏
	desktop._input(drag)
	_expect(TouchControlsS.move_active, "drag activates direct move")
	_expect_vec(TouchControlsS.movement_dir(), Vector2(1, 0), "drag writes full right directly")
	_expect(not Input.is_action_pressed("move_right"), "drag does not inject InputMap")
	# 小偏转跟手：9px / 90 = 0.1，若仍走 InputMap deadzone 0.2 会得到 ZERO
	var micro := InputEventScreenDrag.new()
	micro.index = 0
	micro.position = Vector2(129, 520)  # 自 B 右偏 9px → 0.1
	desktop._input(micro)
	_expect_vec(TouchControlsS.movement_dir(), Vector2(0.1, 0), "micro drag follows without deadzone lag")
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = micro.position
	desktop._input(up)
	_expect(not desktop.is_stick_active(), "lift ends stick")
	_expect(not TouchControlsS.move_active, "lift clears direct move")
	_expect_vec(TouchControlsS.movement_dir(), Vector2.ZERO, "lift stops movement")
	# 右半屏触摸不启动摇杆
	var right := InputEventScreenTouch.new()
	right.index = 1
	right.pressed = true
	right.position = Vector2(1000, 400)
	desktop._input(right)
	_expect(not desktop.is_stick_active(), "right half does not grab stick")
	# 非对局状态（主菜单）不显示暂停按钮、也不启动摇杆
	fake.state = "menu"
	await process_frame
	_expect(not desktop.pause_button.visible, "pause button hidden in menu")
	desktop._input(ev)
	_expect(not desktop.is_stick_active(), "no stick in menu")
	fake.state = "wave"
	await process_frame
	_expect(desktop.pause_button.visible, "pause button visible in wave on touch")
	# 摇杆进行中暂停：必须清掉直接向量，避免恢复后角色自己走
	desktop._input(ev)
	desktop._input(drag)
	fake.paused = true
	await process_frame
	_expect(not desktop.is_stick_active(), "pausing ends stick")
	_expect(not TouchControlsS.move_active, "pausing clears direct move")
	_expect_vec(TouchControlsS.movement_dir(), Vector2.ZERO, "pausing stops movement")
	fake.paused = false
	desktop.pause_button.pressed.emit()
	_expect(fake.pause_requests == 1, "pause button requests pause")
	desktop.queue_free()
	# 强制触屏（模拟移动端导出）：启动即启用
	TouchControlsS.force_touch = 1
	var mobile: TouchControls = TouchControlsS.new()
	mobile.main = fake
	root.add_child(mobile)
	await process_frame
	_expect(mobile.touch_enabled and mobile.pause_button.visible, "mobile starts in touch mode")
	mobile.queue_free()
	fake.queue_free()
	await process_frame


func _test_draft_cards() -> void:
	var ui = UIS.new()
	root.add_child(ui)
	await process_frame
	var cards := [{"name": "A", "desc": "a"}, {"name": "B", "desc": "b"}, {"name": "C", "desc": "c"}]
	# 桌面：单击即选（原行为）
	ui.set_touch_mode(false)
	_picked.clear()
	ui.show_draft(cards, func(i): _picked.append(i))
	ui.draft_buttons[1].pressed.emit()
	_expect(_picked == [1], "desktop single click picks immediately (got %s)" % [_picked])
	_expect(not ui.draft_detail.visible, "desktop shows no detail line")
	_expect(not ui.over_restart_btn.visible, "desktop has no extra restart button")
	# 触屏：首次点按聚焦并显示详情，换一张改聚焦，再点同一张才确认
	ui.set_touch_mode(true)
	_picked.clear()
	ui.show_draft(cards, func(i): _picked.append(i))
	ui.draft_buttons[0].pressed.emit()
	_expect(_picked.is_empty(), "touch first tap does not pick")
	_expect(ui.draft_detail.visible and ui.draft_detail.text.begins_with("A："), "touch first tap shows detail of A")
	_expect(ui.draft_buttons[0].scale.x > 1.0, "focused card enlarged")
	ui.draft_buttons[2].pressed.emit()
	_expect(_picked.is_empty() and ui.draft_detail.text.begins_with("C："), "tapping another card moves focus")
	_expect(is_equal_approx(ui.draft_buttons[0].scale.x, 1.0), "previous focus restored")
	ui.draft_buttons[2].pressed.emit()
	_expect(_picked == [2], "second tap on same card picks (got %s)" % [_picked])
	_expect(not ui.draft_detail.visible, "detail hidden after pick")
	# 触摸模拟出的 mouse_entered 不应放大卡牌
	ui.show_draft(cards, func(i): _picked.append(i))
	ui.draft_buttons[1].mouse_entered.emit()
	_expect(is_equal_approx(ui.draft_buttons[1].scale.x, 1.0), "hover ignored in touch mode")
	ui.set_touch_mode(false)
	ui.draft_buttons[1].mouse_entered.emit()
	_expect(ui.draft_buttons[1].scale.x > 1.0, "hover still enlarges on desktop")
	# 结算面板：触屏有“重开”按钮
	var restarted := [0]
	ui.over_restart_cb = func(): restarted[0] += 1
	ui.set_touch_mode(true)
	_expect(ui.over_restart_btn.visible, "touch shows restart button on game over")
	ui.over_restart_btn.pressed.emit()
	_expect(restarted[0] == 1, "restart button calls callback")
	ui.queue_free()
	await process_frame


func _expect(c: bool, label: String) -> void:
	if not c:
		_failures.append(label)


func _expect_vec(a: Vector2, b: Vector2, label: String) -> void:
	if not a.is_equal_approx(b):
		_failures.append("%s (got %s, expected %s)" % [label, a, b])
