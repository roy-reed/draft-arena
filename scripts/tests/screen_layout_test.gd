extends SceneTree
# 手游版 M2：HUD 锚点与安全区、非 16:9 时竞技场居中、移动端字号、按输入方式切换文案。
# 期望坐标为手算的字面值（原绝对坐标 / 按锚点手推的结果），不调用被测代码生成期望。

const UIS := preload("res://scripts/ui.gd")
const TouchControlsS := preload("res://scripts/touch_controls.gd")
const LayoutS := preload("res://scripts/screen_layout.gd")

var _failures := PackedStringArray()


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_pure_functions()
	await _test_desktop_identical()
	await _test_expand_with_safe_area()
	await _test_mobile_fonts_and_texts()
	UIS.font_scale_override = -1.0
	TouchControlsS.force_touch = -1
	if _failures.is_empty():
		print("SCREEN_LAYOUT_OK")
		quit(0)
	else:
		for f in _failures:
			push_error("SCREEN_LAYOUT_FAIL: %s" % f)
		quit(1)


func _test_pure_functions() -> void:
	_eq(LayoutS.world_offset(Vector2(1280, 720)), Vector2(0, 0), "16:9 has no offset")
	_eq(LayoutS.world_offset(Vector2(1600, 720)), Vector2(160, 0), "20:9 centers horizontally")
	_eq(LayoutS.world_offset(Vector2(1280, 960)), Vector2(0, 120), "4:3 centers vertically")
	_eq(LayoutS.world_offset(Vector2(1560, 720)), Vector2(140, 0), "19.5:9 centers")
	# 2400×1080 屏，左 120px 挖孔、右 60px 圆角、顶部 30px、底部 40px 手势条；视口 1600×720 → 系数 2/3
	var m: Vector4 = LayoutS.safe_margins(Vector2(2400, 1080), Rect2(120, 30, 2220, 1010), Vector2(1600, 720))
	_eq4(m, Vector4(80, 20, 40, 27), "asymmetric safe area converted to viewport px")
	# 非等比（窗口 2560×1080 → 视口 1280×720：x 系数 0.5、y 系数 2/3），确认横纵轴各用各的系数
	_eq4(LayoutS.safe_margins(Vector2(2560, 1080), Rect2(100, 60, 2400, 990), Vector2(1280, 720)), Vector4(50, 40, 30, 20), "per-axis scale factors")
	_eq4(LayoutS.safe_margins(Vector2(1280, 720), Rect2(0, 0, 1280, 720), Vector2(1280, 720)), Vector4.ZERO, "full safe area -> zero margins")
	_eq4(LayoutS.safe_margins(Vector2(0, 0), Rect2(), Vector2(1280, 720)), Vector4.ZERO, "zero window is safe")


func _make_ui(size: Vector2i, font_scale: float, touch: int) -> Array:
	UIS.font_scale_override = font_scale
	TouchControlsS.force_touch = touch
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	root.add_child(vp)
	var ui = UIS.new()
	vp.add_child(ui)
	await process_frame
	await process_frame
	return [vp, ui]


func _test_desktop_identical() -> void:
	var made := await _make_ui(Vector2i(1280, 720), 1.0, 0)
	var vp: SubViewport = made[0]
	var ui = made[1]
	# 原 _build_hud 的绝对坐标（main 分支 scripts/ui.gd）
	_eq(ui.hp_fill.get_parent().global_position, Vector2(24, 20), "hp bar")
	_eq(ui.hp_fill.get_parent().size, Vector2(260, 22), "hp bar size")
	_eq(ui.hp_label.global_position, Vector2(24, 46), "hp label")
	_eq(ui.xp_fill.global_position, Vector2(24, 64), "xp fill")
	_eq(ui.xp_label.global_position, Vector2(24, 74), "xp label")
	_eq(ui.wave_label.global_position, Vector2(24, 96), "wave label")
	_eq(ui.coin_label.global_position, Vector2(24, 124), "coin label")
	_eq(ui.boss_bar.global_position, Vector2(340, 24), "boss bar")
	_eq(ui.boss_bar.size, Vector2(600, 20), "boss bar size")
	_eq(ui.hud_hint.global_position, Vector2(24, 690), "controls hint")
	_eq(ui.combo_label.global_position, Vector2(1030, 60), "combo label")
	_eq(ui.banner_label.global_position, Vector2(0, 120), "banner")
	# Label 会撑到最小高度：在 main 分支原实现上实测 banner 为 1280×102、hint 为 1280×54
	_eq(ui.banner_label.size, Vector2(1280, 102), "banner size (legacy measured)")
	_eq(ui.hint_label.global_position, Vector2(0, 178), "hint label")
	_eq(ui.hint_label.size, Vector2(1280, 54), "hint label size (legacy measured)")
	_txt(ui.hud_hint.text, "WASD / 方向键移动 · 攻击全自动 · ESC 暂停 · Tab 属性 · F11 全屏", "desktop controls hint unchanged")
	_txt(ui.menu_hint.text, "选择角色（按 1 / 2 / 3 或点击），Space 或按钮开始", "desktop menu hint unchanged")
	_txt(ui.start_btn.text, "开始（Space）", "desktop start button unchanged")
	_txt(ui.pause_buttons["resume"].text, "继续（ESC / Space）", "desktop resume unchanged")
	_txt(ui.text("press_restart"), "按 R 重开", "desktop restart hint unchanged")
	_eq(float(ui.hp_label.get_theme_font_size("font_size")), 14.0, "desktop font size unchanged")
	ui.update_hp(50, 100)
	_eq(ui.hp_fill.size.x, 128.0, "hp fill half = 128 on desktop")
	vp.queue_free()
	await process_frame


func _test_expand_with_safe_area() -> void:
	var made := await _make_ui(Vector2i(1600, 720), 1.0, 0)
	var vp: SubViewport = made[0]
	var ui = made[1]
	ui.apply_safe_area(Vector4(80, 10, 80, 40))
	await process_frame
	_eq(ui.hp_fill.get_parent().global_position, Vector2(104, 30), "hp bar inside safe area")
	_eq(ui.boss_bar.global_position, Vector2(500, 34), "boss bar centered in safe width (80 + (1440-600)/2)")
	_eq(ui.combo_label.global_position, Vector2(1270, 70), "combo anchored to safe right edge (1600-80-250)")
	_eq(ui.hud_hint.global_position, Vector2(104, 650), "hint anchored to safe bottom (720-40-30)")
	_eq(ui.banner_label.global_position, Vector2(80, 130), "banner inside safe area")
	_eq(ui.banner_label.size.x, 1440.0, "banner spans safe width")
	vp.queue_free()
	# 暂停按钮锚在安全区右上
	TouchControlsS.force_touch = 1
	var vp2 := SubViewport.new()
	vp2.size = Vector2i(1600, 720)
	root.add_child(vp2)
	var tc: TouchControls = TouchControlsS.new()
	vp2.add_child(tc)
	await process_frame
	_eq(tc.pause_button.global_position, Vector2(1512, 16), "pause button top-right (1600-16-72)")
	tc.apply_safe_area(Vector4(80, 10, 80, 40))
	await process_frame
	_eq(tc.pause_button.global_position, Vector2(1432, 26), "pause button avoids safe area")
	vp2.queue_free()
	await process_frame


func _test_mobile_fonts_and_texts() -> void:
	var made := await _make_ui(Vector2i(1280, 720), 1.3, 1)
	var vp: SubViewport = made[0]
	var ui = made[1]
	_eq(float(ui.hp_label.get_theme_font_size("font_size")), 18.0, "mobile hp font 14*1.3 -> 18")
	_eq(float(ui.wave_label.get_theme_font_size("font_size")), 26.0, "mobile wave font 20*1.3 -> 26")
	_eq(ui.hp_fill.get_parent().size, Vector2(338, 29), "mobile hp bar scaled")
	_eq(ui.coin_label.global_position, Vector2(24, 161), "mobile left column spaced (124*1.3)")
	_eq(ui.draft_buttons[0].custom_minimum_size, Vector2(299, 169), "mobile card size scaled")
	_txt(ui.hud_hint.text, "任意位置按下呼出摇杆移动 · 攻击全自动 · 右上角 II 暂停", "mobile starts with touch hint")
	_txt(ui.start_btn.text, "开始", "mobile start button has no key hint")
	ui.set_text_touch(false)  # 接了手柄/键盘
	_txt(ui.hud_hint.text, "WASD / 方向键移动 · 攻击全自动 · ESC 暂停 · Tab 属性 · F11 全屏", "switches to keyboard hint")
	_txt(ui.pause_buttons["quit"].text, "退出到桌面（Q，保存金币）", "pause quit shows key")
	ui.set_text_touch(true)
	_txt(ui.pause_buttons["quit"].text, "退出到桌面（保存金币）", "back to touch text")
	_txt(ui.text("press_restart"), "点“重开”按钮再来一局", "touch restart hint")
	vp.queue_free()
	# TouchControls 根据输入种类发信号
	TouchControlsS.force_touch = 0
	var tc: TouchControls = TouchControlsS.new()
	root.add_child(tc)
	await process_frame
	var kinds := []
	tc.input_kind_changed.connect(func(t): kinds.append(t))
	var touch_ev := InputEventScreenTouch.new()
	touch_ev.pressed = true
	touch_ev.position = Vector2(900, 300)
	tc._input(touch_ev)
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_W
	tc._input(key)
	tc._input(key)
	_expect(kinds == [true, false], "input kind signals touch then keyboard once (got %s)" % [kinds])
	tc.queue_free()
	await process_frame


func _eq(a, b, label: String) -> void:
	var ok: bool = a.is_equal_approx(b) if a is Vector2 else is_equal_approx(a, b)
	if not ok:
		_failures.append("%s (got %s, expected %s)" % [label, a, b])


func _eq4(a: Vector4, b: Vector4, label: String) -> void:
	if not a.is_equal_approx(b):
		_failures.append("%s (got %s, expected %s)" % [label, a, b])


func _txt(a: String, b: String, label: String) -> void:
	if a != b:
		_failures.append("%s (got '%s')" % [label, a])


func _expect(c: bool, label: String) -> void:
	if not c:
		_failures.append(label)
