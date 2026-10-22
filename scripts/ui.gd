extends CanvasLayer
# 灰盒 UI：主菜单（角色三选一 + meta 商店）+ HUD + 选牌面板 + 结算面板，全部代码构建

var hp_fill: ColorRect
var hp_label: Label
var xp_fill: ColorRect
var xp_label: Label
var wave_label: Label
var coin_label: Label
var boss_bar: ColorRect
var boss_fill: ColorRect
var draft_center: CenterContainer
var draft_panel: PanelContainer
var draft_title: Label
var draft_buttons: Array = []
var draft_pick := Callable()
var over_center: CenterContainer
var over_label: Label
var menu_root: Control
var menu_char_buttons: Array = []
var menu_coin_label: Label
var shop_card_btn: Button
var shop_level_btn: Button
var shop_pick_btn: Button
var menu_cb := {}
var pause_root: Control
var pause_cb := {}
var banner_label: Label
var _banner_tw: Tween
var hint_label: Label
var _hint_tw: Tween
var combo_label: Label
# 触屏模式（M1）：由 TouchControls.touch_mode_changed 驱动；false 时与桌面原行为完全一致
var touch_mode := false
var draft_detail: Label
var _draft_cards: Array = []
var _draft_focus := -1
var over_restart_btn: Button
var over_restart_cb := Callable()
# 手游版 M2：HUD 锚点 + 安全区；移动端字号放大；提示文案随输入方式（触屏/键鼠）切换
const MOBILE_FONT_SCALE := 1.3
static var font_scale_override := -1.0  # 测试用；<0 时按设备自动决定
var font_scale := 1.0
var text_touch := false               # 当前提示文案是否为触屏版
var hud_root: Control
var hud_hint: Label
var menu_hint: Label
var start_btn: Button
var pause_buttons := {}
var _stats_requested := false
var stats_label: Label
var draft_stats: Label
var pause_stats: Label
# 每条提示的 [键鼠版, 触屏版]；键鼠版与原文完全一致
const TEXTS := {
	"hud_hint": ["WASD / 方向键移动 · 攻击全自动 · ESC 暂停 · F11 全屏", "任意位置按下呼出摇杆移动 · 攻击全自动 · 右上角 II 暂停"],
	"menu_hint": ["选择角色（按 1 / 2 / 3 或点击），Space 或按钮开始", "点选角色，再点“开始”"],
	"start": ["开始（Space）", "开始"],
	"resume": ["继续（ESC / Space）", "继续"],
	"restart": ["重开本局（R）", "重开本局"],
	"tutorial": ["移动：WASD / 方向键 · 攻击全自动 · ESC 暂停", "移动：任意位置按下呼出摇杆 · 攻击全自动 · 右上角 II 暂停"],
	"menu": ["回到主菜单（保存金币）", "回到主菜单（保存金币）"],
	"quit": ["退出到桌面（Q，保存金币）", "退出到桌面（保存金币）"],
	"press_restart": ["按 R 重开", "点“重开”按钮再来一局"],
	"press_retry": ["按 R 重试", "点“重开”按钮重试"],
}

func _ready() -> void:
	layer = 10
	if font_scale_override > 0.0:
		font_scale = font_scale_override
	else:
		font_scale = MOBILE_FONT_SCALE if TouchControls.detect_touch_device() else 1.0
	text_touch = TouchControls.detect_touch_device()
	_build_hud()
	_build_draft()
	_build_over()
	_build_menu()
	_build_banner()
	_build_hint()
	_build_pause()

func _fs(size: int) -> int:
	return int(round(size * font_scale))

func _sz(v: Vector2) -> Vector2:
	return (v * font_scale).round()

func text(key: String) -> String:
	return TEXTS[key][1 if text_touch else 0]

func set_text_touch(v: bool) -> void:
	text_touch = v
	if hud_hint != null:
		hud_hint.text = text("hud_hint")
	if menu_hint != null:
		menu_hint.text = text("menu_hint")
	if start_btn != null:
		start_btn.text = text("start")
	for k in pause_buttons:
		pause_buttons[k].text = text(k)

# 安全区边距（视口像素）：left/top/right/bottom。HUD 根节点与之对齐，锚点子元素随之避让。
func apply_safe_area(m: Vector4) -> void:
	hud_root.offset_left = m.x
	hud_root.offset_top = m.y
	hud_root.offset_right = -m.z
	hud_root.offset_bottom = -m.w

func _anchor(c: Control, ax: float, ay: float, pos: Vector2) -> void:
	# 把控件锚在 (ax, ay)，pos 为相对锚点的偏移（基准 1280×720 时与原绝对坐标一致）
	var sz := Vector2.ZERO if c is Label else c.size  # Label 随文字撑到最小尺寸（与原绝对定位一致）
	c.set_anchor(SIDE_LEFT, ax)
	c.set_anchor(SIDE_RIGHT, ax)
	c.set_anchor(SIDE_TOP, ay)
	c.set_anchor(SIDE_BOTTOM, ay)
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + sz.x
	c.offset_bottom = pos.y + sz.y

func _label(text: String, size := 18) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _fs(size))
	return l

func _build_hud() -> void:
	# 全部 HUD 挂在 hud_root（铺满视口、按安全区内缩）下，用锚点定位：
	# 左上（血/经验/波次/金币）、顶部居中（首领条）、右上（连杀）、左下（操作提示）。
	# 基准 1280×720、无安全区、字号倍率 1 时，各元素位置与原绝对坐标逐像素一致。
	hud_root = Control.new()
	hud_root.name = "HudRoot"
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(hud_root)
	var k := font_scale
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.5)
	hp_bg.size = _sz(Vector2(260, 22))
	hp_fill = ColorRect.new()
	hp_fill.color = Color(0.3, 0.9, 0.4)
	hp_fill.position = _sz(Vector2(2, 2))
	hp_fill.size = _sz(Vector2(256, 18))
	hp_bg.add_child(hp_fill)
	hud_root.add_child(hp_bg)
	_anchor(hp_bg, 0, 0, Vector2(24, 20 * k).round())
	hp_label = _label("", 14)
	hud_root.add_child(hp_label)
	_anchor(hp_label, 0, 0, Vector2(24, 46 * k).round())
	var xp_bg := ColorRect.new()
	xp_bg.color = Color(0, 0, 0, 0.4)
	xp_bg.size = _sz(Vector2(260, 8))
	hud_root.add_child(xp_bg)
	_anchor(xp_bg, 0, 0, Vector2(24, 64 * k).round())
	xp_fill = ColorRect.new()
	xp_fill.color = Color(0.3, 0.85, 0.9)
	xp_fill.size = Vector2(0, round(8 * k))
	hud_root.add_child(xp_fill)
	_anchor(xp_fill, 0, 0, Vector2(24, 64 * k).round())
	xp_label = _label("", 13)
	hud_root.add_child(xp_label)
	_anchor(xp_label, 0, 0, Vector2(24, 74 * k).round())
	wave_label = _label("", 20)
	hud_root.add_child(wave_label)
	_anchor(wave_label, 0, 0, Vector2(24, 96 * k).round())
	coin_label = _label("◉ 金币 0", 20)
	hud_root.add_child(coin_label)
	_anchor(coin_label, 0, 0, Vector2(24, 124 * k).round())
	stats_label = _label("", 14)
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_label.custom_minimum_size.x = 390 * k
	stats_label.visible = false
	hud_root.add_child(stats_label)
	_anchor(stats_label, 0, 0, Vector2(24, 160 * k).round())
	boss_bar = ColorRect.new()
	boss_bar.color = Color(0, 0, 0, 0.55)
	boss_bar.size = Vector2(600, 20)
	boss_bar.visible = false
	boss_fill = ColorRect.new()
	boss_fill.color = Color(0.95, 0.3, 0.3)
	boss_fill.position = Vector2(2, 2)
	boss_fill.size = Vector2(596, 16)
	boss_bar.add_child(boss_fill)
	hud_root.add_child(boss_bar)
	_anchor(boss_bar, 0.5, 0, Vector2(-300, 24))  # 原 x=340：640-300
	hud_hint = _label(text("hud_hint"), 14)
	hud_root.add_child(hud_hint)
	_anchor(hud_hint, 0, 1, Vector2(24, -30))  # 原 y=690：720-30
	combo_label = _label("", 20)
	combo_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.25))
	combo_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	combo_label.add_theme_constant_override("outline_size", 6)
	hud_root.add_child(combo_label)
	_anchor(combo_label, 1, 0, Vector2(-250, 60))  # 原 x=1030：1280-250
	combo_label.visible = false

func update_combo(n: int) -> void:
	if n < 2:
		combo_label.visible = false
		return
	combo_label.text = "连杀 ×%d" % n
	combo_label.add_theme_font_size_override("font_size", _fs(18 + mini(n / 5, 12)))
	combo_label.visible = true

func _build_banner() -> void:
	banner_label = _label("", 34)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	banner_label.add_theme_constant_override("outline_size", 8)
	banner_label.modulate.a = 0.0
	hud_root.add_child(banner_label)
	_span_width(banner_label, 120, 50)

func _span_width(c: Control, top: float, h: float) -> void:
	# 横向铺满 HUD 区域（基准 1280 宽时即原来的 x=0、宽 1280）
	c.anchor_left = 0
	c.anchor_right = 1
	c.anchor_top = 0
	c.anchor_bottom = 0
	c.offset_left = 0
	c.offset_right = 0
	c.offset_top = top
	c.offset_bottom = top + h

func flash_banner(text: String) -> void:
	banner_label.text = text
	if _banner_tw != null and _banner_tw.is_valid():
		_banner_tw.kill()
	banner_label.modulate.a = 1.0
	banner_label.scale = Vector2(1.1, 1.1)
	banner_label.pivot_offset = banner_label.size * 0.5
	_banner_tw = banner_label.create_tween()
	_banner_tw.tween_property(banner_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tw.tween_interval(0.9)
	_banner_tw.tween_property(banner_label, "modulate:a", 0.0, 0.6)

func _build_hint() -> void:
	hint_label = _label("", 18)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_color_override("font_color", Color(1, 1, 0.75))
	hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint_label.add_theme_constant_override("outline_size", 6)
	hint_label.modulate.a = 0.0
	hud_root.add_child(hint_label)
	_span_width(hint_label, 178, 30)

func show_hint(text: String, secs: float) -> void:
	hint_label.text = text
	if _hint_tw != null and _hint_tw.is_valid():
		_hint_tw.kill()
	hint_label.modulate.a = 1.0
	_hint_tw = hint_label.create_tween()
	_hint_tw.tween_interval(secs)
	_hint_tw.tween_property(hint_label, "modulate:a", 0.0, 0.5)

func _build_pause() -> void:
	pause_root = Control.new()
	pause_root.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_root.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	var title := _label("已暂停", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	pause_stats = _label("", 15)
	pause_stats.custom_minimum_size.x = 650 * font_scale
	pause_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(pause_stats)
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 8)
	vol_row.add_child(_label("音量", 15))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = _sz(Vector2(280, 24))
	slider.value_changed.connect(func(v: float): _fire_pause_arg("volume", v))
	vol_row.add_child(slider)
	vb.add_child(vol_row)
	pause_root.set_meta("slider", slider)
	for item in [[text("resume"), "resume"], [text("restart"), "restart"], [text("menu"), "menu"], [text("quit"), "quit"]]:
		var b := _menu_btn()
		b.text = item[0]
		pause_buttons[item[1]] = b
		b.custom_minimum_size = _sz(Vector2(420, 46))
		b.pressed.connect(func(): _fire_pause(item[1]))
		vb.add_child(b)
	panel.add_child(vb)
	center.add_child(panel)
	pause_root.add_child(center)
	add_child(pause_root)

func show_pause(cbs: Dictionary) -> void:
	pause_cb = cbs
	var s: HSlider = pause_root.get_meta("slider")
	s.set_value_no_signal(SFX.get_volume())
	pause_root.visible = true
	_sync_stats_visibility()

func hide_pause() -> void:
	pause_root.visible = false
	_sync_stats_visibility()
	pause_cb = {}

func _fire_pause(key: String) -> void:
	if pause_cb.has(key) and pause_cb[key] is Callable:
		pause_cb[key].call()

func _fire_pause_arg(key: String, v: float) -> void:
	if pause_cb.has(key) and pause_cb[key] is Callable:
		pause_cb[key].call(v)

func _build_draft() -> void:
	draft_center = CenterContainer.new()
	draft_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	draft_panel = PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	draft_title = _label("选择一张牌", 26)
	draft_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(draft_title)
	draft_stats = _label("", 15)
	draft_stats.custom_minimum_size.x = 722 * font_scale
	draft_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(draft_stats)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	draft_buttons = []
	for i in 3:
		var b := Button.new()
		b.custom_minimum_size = _sz(Vector2(230, 130))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", _fs(16))
		b.pivot_offset = b.custom_minimum_size / 2.0
		# 悬停放大只用于鼠标；触屏上由“点按聚焦”代替（触摸模拟的鼠标事件不触发悬停）
		b.mouse_entered.connect(func():
			if touch_mode:
				return
			b.scale = Vector2(1.06, 1.06)
			b.z_index = 1)
		b.mouse_exited.connect(func():
			if touch_mode:
				return
			b.scale = Vector2.ONE
			b.z_index = 0)
		b.pressed.connect(_on_draft_pressed.bind(i))
		hb.add_child(b)
		draft_buttons.append(b)
	vb.add_child(hb)
	draft_detail = _label("", 20)
	draft_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	draft_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	draft_detail.custom_minimum_size = _sz(Vector2(722, 0))
	draft_detail.visible = false
	vb.add_child(draft_detail)
	draft_panel.add_child(vb)
	draft_center.add_child(draft_panel)
	add_child(draft_center)
	draft_center.visible = false

func _build_over() -> void:
	over_center = CenterContainer.new()
	over_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	over_label = _label("", 22)
	over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(over_label)
	over_restart_btn = _menu_btn()
	over_restart_btn.text = "重开"
	over_restart_btn.add_theme_font_size_override("font_size", _fs(22))
	over_restart_btn.custom_minimum_size = _sz(Vector2(420, 64))
	over_restart_btn.visible = false
	over_restart_btn.pressed.connect(func():
		if over_restart_cb.is_valid():
			over_restart_cb.call())
	vb.add_child(over_restart_btn)
	panel.add_child(vb)
	over_center.add_child(panel)
	add_child(over_center)
	over_center.visible = false

# ---- 主菜单 ----

func _build_menu() -> void:
	menu_root = Control.new()
	menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(bg)
	var splash := ArtS.skin("menu_bg")
	if splash != null:
		var tr := TextureRect.new()
		tr.texture = splash
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.modulate = Color(0.6, 0.6, 0.68)
		menu_root.add_child(tr)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 8)
	var title := _label("DRAFT ARENA", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	menu_hint = _label(text("menu_hint"), 15)
	menu_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(menu_hint)
	var char_heading := _label("选择角色 / 专属武器", 20)
	char_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(char_heading)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	menu_char_buttons = []
	for i in 3:
		var b := Button.new()
		b.custom_minimum_size = _sz(Vector2(280, 130))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", _fs(15))
		b.pressed.connect(_on_char_btn.bind(i))
		hb.add_child(b)
		menu_char_buttons.append(b)
	vb.add_child(hb)
	var shop_heading := _label("永久成长 / 卡牌解锁（花费存档金币）", 20)
	shop_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_heading.modulate = Color(1.0, 0.85, 0.35)
	vb.add_child(shop_heading)
	menu_coin_label = _label("◉ 金币 0（永久存档）", 20)
	menu_coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(menu_coin_label)
	shop_card_btn = _menu_btn()
	shop_level_btn = _menu_btn()
	shop_pick_btn = _menu_btn()
	shop_card_btn.pressed.connect(func(): _fire_cb("buy_card"))
	shop_level_btn.pressed.connect(func(): _fire_cb("buy_level"))
	shop_pick_btn.pressed.connect(func(): _fire_cb("buy_pick"))
	vb.add_child(shop_card_btn)
	vb.add_child(shop_level_btn)
	vb.add_child(shop_pick_btn)
	var pad := Control.new()
	pad.custom_minimum_size = _sz(Vector2(0, 8))
	vb.add_child(pad)
	start_btn = _menu_btn()
	start_btn.text = text("start")
	start_btn.add_theme_font_size_override("font_size", _fs(22))
	start_btn.custom_minimum_size = _sz(Vector2(640, 54))
	start_btn.pressed.connect(func(): _fire_cb("start"))
	vb.add_child(start_btn)
	menu_root.add_child(vb)
	add_child(menu_root)
	menu_root.visible = false

func _menu_btn() -> Button:
	var b := Button.new()
	b.custom_minimum_size = _sz(Vector2(640, 44))
	b.add_theme_font_size_override("font_size", _fs(15))
	return b

func _fire_cb(key: String) -> void:
	SFX.play("click")
	if menu_cb.has(key) and menu_cb[key] is Callable:
		menu_cb[key].call()

func _on_char_btn(i: int) -> void:
	SFX.play("click")
	_fire_cb_arg("select", i)

func _fire_cb_arg(key: String, arg: int) -> void:
	if menu_cb.has(key) and menu_cb[key] is Callable:
		menu_cb[key].call(arg)

func show_menu(cb: Dictionary) -> void:
	menu_cb = cb
	menu_root.visible = true

func hide_menu() -> void:
	menu_root.visible = false

func refresh_menu(char_texts: Array, card_text: String, level_text: String, pick_text: String, coins: int, sel: int) -> void:
	for i in menu_char_buttons.size():
		var t: String = char_texts[i] if i < char_texts.size() else ""
		menu_char_buttons[i].text = t + ("\n【已选】" if i == sel else "")
	shop_card_btn.text = card_text
	shop_level_btn.text = level_text
	shop_pick_btn.text = pick_text
	menu_coin_label.text = "◉ 金币 %d（永久存档）" % coins

# ---- HUD 与面板 ----

func update_hp(hp: float, max_hp: float) -> void:
	hp_fill.size.x = round(256.0 * font_scale) * clampf(hp / max_hp, 0.0, 1.0)
	hp_label.text = "HP %d / %d" % [int(hp), int(max_hp)]

func update_xp(level: int, xp: int, needed: int) -> void:
	xp_fill.size.x = round(260.0 * font_scale) * clampf(float(xp) / float(needed), 0.0, 1.0)
	xp_label.text = "Lv %d · %d/%d XP" % [level, xp, needed]

func update_wave(text: String) -> void:
	wave_label.text = text

func update_coins(n: int) -> void:
	coin_label.text = "◉ 金币 %d" % n

func update_stats(summary: String) -> void:
	stats_label.text = summary
	draft_stats.text = "当前属性\n" + summary
	pause_stats.text = "当前属性\n" + summary

func toggle_stats() -> void:
	_stats_requested = not _stats_requested
	_sync_stats_visibility()

func _sync_stats_visibility() -> void:
	stats_label.visible = _stats_requested and not draft_center.visible and not pause_root.visible

func show_boss() -> void:
	boss_bar.visible = true

func hide_boss() -> void:
	boss_bar.visible = false

func set_boss(hp: float, max_hp: float) -> void:
	boss_fill.size.x = 596.0 * clampf(hp / max_hp, 0.0, 1.0)

func set_touch_mode(v: bool) -> void:
	touch_mode = v
	if over_restart_btn != null:
		over_restart_btn.visible = v
	_set_draft_focus(-1)

func _set_draft_focus(i: int) -> void:
	_draft_focus = i
	for j in draft_buttons.size():
		var b: Button = draft_buttons[j]
		b.scale = Vector2(1.06, 1.06) if j == i else Vector2.ONE
		b.z_index = 1 if j == i else 0
	if draft_detail == null:
		return
	if i >= 0 and i < _draft_cards.size():
		var c: Dictionary = _draft_cards[i]
		draft_detail.text = "%s：%s\n再次点按这张牌确认选择" % [c["name"], c["desc"]]
		draft_detail.visible = true
	else:
		draft_detail.text = ""
		draft_detail.visible = false

func show_draft(cards: Array, on_pick: Callable, title_text := "选择一张牌") -> void:
	_draft_cards = cards.duplicate()
	_set_draft_focus(-1)
	draft_pick = on_pick
	draft_title.text = title_text
	for i in mini(3, cards.size()):
		var c: Dictionary = cards[i]
		draft_buttons[i].text = "%s\n\n%s" % [c["name"], c["desc"]]
	draft_center.visible = true
	_sync_stats_visibility()
	FX.pop_in(draft_panel)

func hide_draft() -> void:
	draft_center.visible = false
	_sync_stats_visibility()
	draft_pick = Callable()
	_set_draft_focus(-1)

func _on_draft_pressed(i: int) -> void:
	if not draft_center.visible or not draft_pick.is_valid():
		return
	# 触屏：第一次点按只聚焦并显示详情，再点同一张才确认，避免误触；桌面端单击即选（原行为）
	if touch_mode and _draft_focus != i:
		_set_draft_focus(i)
		return
	_set_draft_focus(-1)
	draft_center.visible = false
	_sync_stats_visibility()
	SFX.play("click")
	var cb := draft_pick
	draft_pick = Callable()
	cb.call(i)

func show_over(text: String) -> void:
	over_label.text = text
	over_center.visible = true
	FX.pop_in(over_center)
