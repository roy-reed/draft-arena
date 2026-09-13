extends Node2D
# 主流程：主菜单（角色三选一 + meta 商店）→ 刷怪 → 清波三选一 → 区域首领 → 结算金币入档
# smoke 自测：godot --headless --path . -- --smoke
# 6 倍速自动：选角色 1 → 发 500 币买满三条 meta 线 → 新武器命中自检 → 打通 3 区域 → SMOKE_OK

const Cards := preload("res://scripts/cards.gd")
const MetaS := preload("res://scripts/meta.gd")
const PlayerS := preload("res://scripts/player.gd")
const EnemyS := preload("res://scripts/enemy.gd")
const SpitterS := preload("res://scripts/spitter.gd")
const BossS := preload("res://scripts/boss.gd")
const BossSpitterS := preload("res://scripts/boss_spitter.gd")
const BossSummonerS := preload("res://scripts/boss_summoner.gd")
const BulletS := preload("res://scripts/bullet.gd")
const EBulletS := preload("res://scripts/ebullet.gd")
const BoomerangS := preload("res://scripts/boomerang.gd")
const UIS := preload("res://scripts/ui.gd")
const PauseHookS := preload("res://scripts/pause_hook.gd")
const CrystalS := preload("res://scripts/crystal.gd")

const ARENA := Rect2(40, 40, 1200, 640)
const CHAR_LEVEL_MAX := 5
const CHAR_LEVEL_COST := 25
const START_PICK_COST := 40
const PITY_PER_WAVE := 12   # 死亡保底：每个已清普通波
const PITY_PER_BOSS := 18   # 死亡保底：每个已击杀首领
const PITY_CAP := 40        # 保底上限：防后期死亡收益超过通关（刷币无激励）
const SOAK_CYCLES := 5      # --soak 长跑：完整重载场景的循环次数
const ELITE_CHANCE := 0.12  # 第 2 波起精英概率（--sim 与刷怪共用，勿只改一处）
const R1_HP_RAMP := 0.15    # 区域 1 逐波爬坡：每波敌人 HP +15%（负值即减压，方向待 playtest 校准）
const R1_SPD_RAMP := 0.05   # 区域 1 逐波爬坡：每波移速 +5%
const WAVE_TIME := 30.0     # 普通波固定时长（秒）；首领波无计时，打完首领才进下一地图
const BOSS_XP := 120        # 击杀首领经验
const REFINE_COST := 30     # 卡牌精研基础价（递增）
const FORGE_COST := 45      # 锻体基础价（递增）
const COMBO_WINDOW := 1.7   # 连杀窗口（秒）：窗口内连续击杀累积，每 10 连递增奖励

# 难度档位（白绿蓝橙红金）：外观同款，血/护甲/伤害/经验随档位；区域各跨两档
const TIERS := [
	{"name": "白", "color": Color(0.93, 0.93, 0.96), "hp": 1.0, "armor": 0.0, "dmg": 1.0, "xp": 2},
	{"name": "绿", "color": Color(0.42, 0.83, 0.44), "hp": 1.3, "armor": 1.0, "dmg": 1.1, "xp": 3},
	{"name": "蓝", "color": Color(0.36, 0.6, 0.95), "hp": 1.6, "armor": 2.0, "dmg": 1.25, "xp": 4},
	{"name": "橙", "color": Color(0.96, 0.62, 0.2), "hp": 2.0, "armor": 3.0, "dmg": 1.4, "xp": 5},
	{"name": "红", "color": Color(0.9, 0.26, 0.26), "hp": 2.5, "armor": 4.5, "dmg": 1.6, "xp": 6},
	{"name": "金", "color": Color(0.98, 0.8, 0.28), "hp": 3.2, "armor": 6.0, "dmg": 1.85, "xp": 8},
]

const CHARS := [
	{"id": "ranger", "name": "狙神", "hp": 100.0, "speed": 220.0, "weapon": "w_dragon", "dmg_mult": 1.0, "radius": 16.0, "shape": "circle", "color": Color(0.35, 0.75, 1.0)},
	{"id": "brute", "name": "蛮兵", "hp": 140.0, "speed": 190.0, "weapon": "w_sawblade", "dmg_mult": 1.0, "radius": 19.0, "shape": "square", "color": Color(1.0, 0.55, 0.25)},
	{"id": "gunner", "name": "炮手", "hp": 80.0, "speed": 230.0, "weapon": "w_shotgun", "dmg_mult": 1.1, "radius": 13.0, "shape": "triangle", "color": Color(0.95, 0.85, 0.3)},
]

var regions := [
	{"name": "灰盒平原", "waves": 3, "speed": 90.0, "boss_hp": 420.0},
	{"name": "碎石荒地", "waves": 4, "speed": 108.0, "boss_hp": 790.0},
	{"name": "熔渣深窟", "waves": 5, "speed": 125.0, "boss_hp": 1400.0},
]

var state := "menu"  # menu | startpick | inter | wave | draft | over | win
var meta_d := {}
var char_i := 0
var region_i := 0
var wave_i := 0
var is_boss_wave := false
var run_coins := 0
var kills := 0
var player: Node2D = null
var ui: CanvasLayer = null
var fx: Node = null
var sfx: Node = null
var paused := false
var enemies_alive := 0
var to_spawn := 0
var mob_cap := 10
var spawn_t := 0.0
var spawn_interval := 0.65
var time_left := 0.0
var _last_time_shown := -1
var inter_t := 0.0
var boss_ref: Node2D = null
var _offer: Array = []

var smoke := false
var soak := false
var _shot := false          # --shot：窗口化真实渲染自截（主菜单+战斗各一帧），诊断渲染问题用
var _shot_phase := 0
var _shot_t := 0.0
var xp_accum := 0
var player_level := 1
var pending_picks := 0
var _post_boss_advance := false
var combo_n := 0
var combo_t := 0.0
var current_elite_chance := ELITE_CHANCE
var _floor_node: Node = null
var _border_node: Node = null
var _endless := false
var _endless_boss_n := 0
var _boss_refs: Array = []
static var _soak_done := 0  # 跨场景重载持久（实例变量会被 reload 重置）
var _smoke_pick_t := 0.0
var _smoke_buys := {"card": false, "level": false, "pick": false}
var _smoke_wtest_done := false
var _hint_draft := false
var _hint_boss := false
var _first_draft_done := false
var _wtest_phase := 0
var _wtest_t := 0.0
var _wtest_base := 0.0
var _wtest_dummies: Array = []
var _t0 := 0

func _ready() -> void:
	_add_floor()
	smoke = "--smoke" in OS.get_cmdline_user_args() or "--soak" in OS.get_cmdline_user_args()
	soak = "--soak" in OS.get_cmdline_user_args()
	_shot = "--shot" in OS.get_cmdline_user_args()
	if "--sim" in OS.get_cmdline_user_args():
		_run_sim()
		return
	if smoke:
		Engine.time_scale = 6.0
		_t0 = Time.get_ticks_msec()
		MetaS.persist = false  # 测试不落盘，见 meta.gd persist
		meta_d = MetaS.default_data()  # smoke 用全新存档，保证购买路径可重复验证
	else:
		meta_d = MetaS.load_data()
	ui = UIS.new()
	add_child(ui)
	fx = FX.new()
	fx.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(fx)
	FX.I.enabled = not smoke
	sfx = SFX.new()
	sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(sfx)
	SFX.I.enabled = not smoke
	SFX.set_volume(float(meta_d.get("volume", 0.8)))
	var hook := PauseHookS.new()
	hook.main = self
	add_child(hook)
	_enter_menu()
	if smoke:
		meta_d["coins"] = 500
		_menu_select(0)
		_buy_card()
		_buy_level()
		_buy_startpick()
		MetaS.save_data(meta_d)
		if not (_smoke_buys["card"] and _smoke_buys["level"] and _smoke_buys["pick"]):
			_smoke_finish("buy_fail")
			return
		_menu_start()

func _spawn_xp_crystal(pos: Vector2) -> void:
	# 经验晶体（纯视觉）：XP 在击杀时已入账，晶体从尸体弹射后飞向玩家，提供拾取反馈
	var c := CrystalS.new()
	c.target = player
	c.position = pos
	add_child(c)

func _add_floor() -> void:
	# 有地砖贴图时按区域铺色（r1 蓝灰 / r2 绿褐 / r3 红紫），覆盖 _draw 的纯色底；边框用 Line2D
	if _floor_node != null and is_instance_valid(_floor_node):
		_floor_node.queue_free()
		_floor_node = null
	if _border_node != null and is_instance_valid(_border_node):
		_border_node.queue_free()
		_border_node = null
	var floor_tex := ArtS.skin("floor_tile_r%d" % (region_i + 1))
	if floor_tex == null:
		return
	var tr := TextureRect.new()
	tr.texture = floor_tex
	tr.position = ARENA.position
	tr.size = ARENA.size
	tr.stretch_mode = TextureRect.STRETCH_TILE
	add_child(tr)
	_floor_node = tr
	var border := Line2D.new()
	border.points = PackedVector2Array([
		ARENA.position, Vector2(ARENA.end.x, ARENA.position.y),
		ARENA.end, Vector2(ARENA.position.x, ARENA.end.y), ARENA.position,
	])
	border.width = 2.0
	border.default_color = Color(0.42, 0.42, 0.58)
	add_child(border)
	_border_node = border

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.07, 0.07, 0.1))
	draw_rect(ARENA, Color(0.13, 0.13, 0.17))
	for x in range(64, 1280, 64):
		draw_line(Vector2(x, ARENA.position.y), Vector2(x, ARENA.end.y), Color(1, 1, 1, 0.03))
	for y in range(64, 720, 64):
		draw_line(Vector2(ARENA.position.x, y), Vector2(ARENA.end.x, y), Color(1, 1, 1, 0.03))
	draw_rect(ARENA, Color(0.35, 0.35, 0.45), false, 2.0)

func _process(delta: float) -> void:
	if _shot:
		_shot_t += delta
		if (state == "draft" or state == "startpick") and _shot_t > 0.6:
			_on_card_picked(_smoke_pick_index())  # 截图模式自动选卡，进入波次以便目视小怪
		if _shot_phase == 0 and _shot_t > 1.2:
			_shot_phase = 1
			_save_shot("shot_menu.png")
			_menu_start()
			_shot_t = 0.0
		elif _shot_phase == 1 and _shot_t > 4.5:
			_shot_phase = 2
			_save_shot("shot_game.png")
			print("SHOT_OK")
			get_tree().quit()
			return
	if player != null:
		ui.update_hp(player.hp, player.max_hp)
	if boss_ref != null and is_instance_valid(boss_ref):
		ui.set_boss(boss_ref.hp, boss_ref.max_hp)
	match state:
		"menu":
			if Input.is_physical_key_pressed(KEY_1):
				_menu_select(0)
			elif Input.is_physical_key_pressed(KEY_2):
				_menu_select(1)
			elif Input.is_physical_key_pressed(KEY_3):
				_menu_select(2)
			elif Input.is_physical_key_pressed(KEY_SPACE):
				_menu_start()
		"inter":
			inter_t -= delta
			if smoke and not _smoke_wtest_done and wave_i == 0:
				_smoke_weapon_test(delta)
			if inter_t <= 0.0:
				_start_wave()
		"wave":
			if combo_t > 0.0:
				combo_t -= delta
				if combo_t <= 0.0 and combo_n > 0:
					combo_n = 0
					ui.update_combo(0)
			if not is_boss_wave:
				time_left -= delta
				var shown := maxi(int(ceilf(time_left)), 0)
				if shown != _last_time_shown:
					_last_time_shown = shown
					var reg2: Dictionary = _safe_reg()
					ui.update_wave("区域 %s · 第 %d/%d 波 · %ds" % [reg2["name"], wave_i, int(reg2["waves"]), shown])
			if not is_boss_wave:  # 补刷仅限普通波；首领波只打首领与召唤物（修复首领波无限刷怪）
				if to_spawn > 0 or enemies_alive < mob_cap:
					spawn_t -= delta
					if spawn_t <= 0.0:
						spawn_t = spawn_interval
						if to_spawn > 0:
							to_spawn -= 1
						if enemies_alive < mob_cap + 4:
							_spawn_enemy()
					if time_left <= 0.0:
						_wave_time_up()
			# 首领波无计时：由 _on_boss_killed 推进
		"draft", "startpick":
			if smoke:
				_smoke_pick_t -= delta
				if _smoke_pick_t <= 0.0:
					_smoke_pick_t = 0.8
					_on_card_picked(_smoke_pick_index())
		"over", "win":
			pass
	if smoke and Time.get_ticks_msec() - _t0 > 180000:
		_smoke_finish("timeout")

# ---- 主菜单与 meta 商店 ----

func _enter_menu() -> void:
	state = "menu"
	ui.show_menu({
		"select": _menu_select,
		"start": _menu_start,
		"buy_card": _buy_card,
		"buy_level": _buy_level,
		"buy_pick": _buy_startpick,
	})
	_refresh_menu()

func _menu_select(i: int) -> void:
	if state != "menu":
		return
	char_i = clampi(i, 0, CHARS.size() - 1)
	_refresh_menu()

func _menu_start() -> void:
	if state != "menu":
		return
	ui.hide_menu()
	_start_run()

func _refresh_menu() -> void:
	var texts := []
	for c in CHARS:
		var lvl := MetaS.char_level(meta_d, c["id"])
		var lvl_text := "未强化"
		if lvl > 0:
			lvl_text = "强化 Lv%d（每级 +5HP +2%%伤害）" % lvl
		texts.append("%s\nHP %d · 速度 %d · 专属武器：%s（2 级强化）\n%s" % [c["name"], int(c["hp"]) + 5 * lvl, int(c["speed"]), Cards.WEAPONS[c["weapon"]]["name"], lvl_text])
	var pool_n: int = Cards.m0_count() + meta_d["cards"].size()
	var next_id := _next_locked_card()
	var card_text := ""
	if next_id != "":
		var c: Dictionary = Cards.get_card(next_id)
		card_text = "解锁牌「%s」（%d 币）： %s · 牌池 %d/%d" % [c["name"], Cards.unlock_cost(next_id), c["desc"], pool_n, Cards.all_cards().size()]
	else:
		var rl := int(meta_d.get("refines", 0))
		card_text = "卡牌精研 Lv%d→%d：下一局每层 +4%% 伤害、+6 HP（%d 币）" % [rl, rl + 1, _next_refine_cost()]
	var cid: String = CHARS[char_i]["id"]
	var clvl := MetaS.char_level(meta_d, cid)
	var level_text: String
	if clvl >= CHAR_LEVEL_MAX:
		level_text = "%s 已满级 Lv%d" % [CHARS[char_i]["name"], clvl]
	else:
		level_text = "%s 永久强化 Lv%d→%d：+5 HP 上限、+2%% 伤害（%d 币）" % [CHARS[char_i]["name"], clvl, clvl + 1, CHAR_LEVEL_COST * (clvl + 1)]
	var pick_text := ""
	if not bool(meta_d.get("start_pick", false)):
		pick_text = "解锁「开局免费三选一」（%d 币）：开局从被动池 3 选 1 免费拿" % START_PICK_COST
	else:
		var fg := int(meta_d.get("forging", 0))
		pick_text = "锻体 Lv%d→%d：下一局每层 +8 HP、+3%% 伤害（%d 币）" % [fg, fg + 1, _next_forge_cost()]
	ui.refresh_menu(texts, card_text, level_text, pick_text, int(meta_d["coins"]), char_i)

func _next_locked_card() -> String:
	var unlocked: Array = meta_d.get("cards", [])
	for id in Cards.UNLOCK_ORDER:
		if not (id in unlocked):
			return id
	return ""

func _buy_card() -> void:
	if state != "menu":
		return
	var id := _next_locked_card()
	if id == "":
		_buy_refine()  # 牌池集齐后，解锁位替换为「卡牌精研」
		return
	var cost := Cards.unlock_cost(id)
	if int(meta_d["coins"]) < cost:
		return
	meta_d["coins"] = int(meta_d["coins"]) - cost
	meta_d["cards"].append(id)
	_smoke_buys["card"] = true
	MetaS.save_data(meta_d)
	_refresh_menu()

func _next_refine_cost() -> int:
	return REFINE_COST * (int(meta_d.get("refines", 0)) + 1)

func _buy_refine() -> void:
	# 卡牌精研（占位基础版）：每层下一局 +4% 伤害、+6 HP，后续换独立机制
	var cost := _next_refine_cost()
	if int(meta_d["coins"]) < cost:
		return
	meta_d["coins"] = int(meta_d["coins"]) - cost
	meta_d["refines"] = int(meta_d.get("refines", 0)) + 1
	_smoke_buys["card"] = true
	MetaS.save_data(meta_d)
	_refresh_menu()

func _buy_level() -> void:
	if state != "menu":
		return
	var cid: String = CHARS[char_i]["id"]
	var lvl := MetaS.char_level(meta_d, cid)
	if lvl >= CHAR_LEVEL_MAX:
		return
	var cost := CHAR_LEVEL_COST * (lvl + 1)
	if int(meta_d["coins"]) < cost:
		return
	meta_d["coins"] = int(meta_d["coins"]) - cost
	meta_d["char_level"][cid] = lvl + 1
	_smoke_buys["level"] = true
	MetaS.save_data(meta_d)
	_refresh_menu()

func _buy_startpick() -> void:
	if state != "menu":
		return
	if bool(meta_d.get("start_pick", false)):
		_buy_forging()  # 已解锁开局三选一后，此位替换为「锻体」
		return
	if int(meta_d["coins"]) < START_PICK_COST:
		return
	meta_d["coins"] = int(meta_d["coins"]) - START_PICK_COST
	meta_d["start_pick"] = true
	_smoke_buys["pick"] = true
	MetaS.save_data(meta_d)
	_refresh_menu()

func _next_forge_cost() -> int:
	return FORGE_COST * (int(meta_d.get("forging", 0)) + 1)

func _buy_forging() -> void:
	# 锻体（占位基础版，参考斗魂竞技场属性强化）：每层下一局 +8 HP、+3% 伤害
	var cost := _next_forge_cost()
	if int(meta_d["coins"]) < cost:
		return
	meta_d["coins"] = int(meta_d["coins"]) - cost
	meta_d["forging"] = int(meta_d.get("forging", 0)) + 1
	_smoke_buys["pick"] = true
	MetaS.save_data(meta_d)
	_refresh_menu()

# ---- 单局流程 ----

func _start_run() -> void:
	run_coins = 0
	kills = 0
	region_i = 0
	wave_i = 0
	is_boss_wave = false
	enemies_alive = 0
	boss_ref = null
	_first_draft_done = false
	xp_accum = 0
	player_level = 1
	pending_picks = 0
	_post_boss_advance = false
	combo_n = 0
	combo_t = 0.0
	ui.update_combo(0)
	ui.update_xp(1, 0, _xp_needed())
	var cfg: Dictionary = CHARS[char_i]
	player = PlayerS.new()
	player.setup(cfg, MetaS.char_level(meta_d, cfg["id"]))
	# meta 商店加成：卡牌精研（+4% 伤/+6 HP 每层）与锻体（+8 HP/+3% 伤每层）
	var rl := int(meta_d.get("refines", 0))
	var fg := int(meta_d.get("forging", 0))
	if rl > 0:
		player.damage_mult += 0.04 * rl
		player.add_max_hp(6.0 * rl)
	if fg > 0:
		player.add_max_hp(8.0 * fg)
		player.damage_mult += 0.03 * fg
	player.arena = ARENA
	player.bullet_spawner = _spawn_bullet
	player.boomerang_spawner = _spawn_boomerang
	player.position = ARENA.get_center()
	player.died.connect(_on_player_died)
	add_child(player)
	if smoke:
		player.max_hp = 1000000.0
		player.hp = 1000000.0
		player.damage_mult += 60.0
		player.attack_speed_mult += 5.0
	ui.update_coins(0)
	if bool(meta_d.get("start_pick", false)):
		_enter_startpick()
	else:
		_start_inter(0.8)
	if not meta_d.get("tutorial_done", false):
		ui.show_hint("移动：WASD / 方向键 · 攻击全自动 · ESC 暂停", 6.0)

func _save_shot(fname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "user://" + fname  # 导出后 res:// 不可写，统一存 AppData
	img.save_png(path)
	print("SHOT_SAVED ", ProjectSettings.globalize_path(path), " ", img.get_width(), "x", img.get_height())

func _start_inter(t: float) -> void:
	inter_t = t
	player.active = true
	player.drafting = false  # 选牌冻结的玩家在波间恢复（_finish 不经此处）
	state = "inter"

# ---- 暂停与快捷键（输入经 pause_hook 转发，树暂停时仍生效） ----

func hotkey(event: InputEvent) -> void:
	if smoke:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				if paused:
					_set_paused(false)
				elif state in ["inter", "wave", "draft", "startpick"]:
					_set_paused(true)
				else:
					get_tree().quit()
			KEY_SPACE:
				if paused:
					_set_paused(false)
			KEY_R:
				if paused or state in ["over", "win"]:
					_set_paused(false)
					get_tree().reload_current_scene()
			KEY_Q:
				if paused:
					get_tree().quit()
			KEY_F11:
				var mode := DisplayServer.window_get_mode()
				DisplayServer.window_set_mode(
					DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN
					else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _set_paused(v: bool) -> void:
	paused = v
	get_tree().paused = v
	if v:
		ui.show_pause(_pause_cbs())
	else:
		ui.hide_pause()

func _pause_cbs() -> Dictionary:
	return {"resume": _cb_resume, "restart": _cb_restart, "quit": _cb_quit, "volume": _cb_volume}

func _cb_resume() -> void:
	_set_paused(false)

func _cb_restart() -> void:
	_set_paused(false)
	get_tree().reload_current_scene()

func _cb_quit() -> void:
	get_tree().quit()

func _cb_volume(v: float) -> void:
	SFX.set_volume(v)
	meta_d["volume"] = v
	MetaS.save_data(meta_d)

func _safe_reg() -> Dictionary:
	return regions[mini(region_i, regions.size() - 1)]

func _start_wave() -> void:
	var reg: Dictionary = _safe_reg()
	_set_mobs_frozen(false)
	player.active = true
	wave_i += 1
	var boss := false
	if not _endless and wave_i > int(reg["waves"]):
		boss = true
	elif _endless and wave_i % 6 == 0:
		boss = true  # 无尽：每 6 波一只随机增强首领
	if boss:
		is_boss_wave = true
		_spawn_boss(reg)
		ui.update_wave(("无尽 · " if _endless else "") + "区域 %s · 首领！" % reg["name"])
		ui.flash_banner("首领来袭！")
	else:
		is_boss_wave = false
		# 威胁预算：刷怪数与精英率随玩家等级上浮（杀得越多怪越多，强度跟随的机制化）
		var budget_mult := minf(1.0 + 0.12 * (player_level - 1), 1.8)
		mob_cap = clampi(int(round((4 + wave_i * 2) * budget_mult)), 8, 32)
		to_spawn = mob_cap
		var spawn_window := 10.0 + wave_i * 2.0  # 出怪提速：波前段密集刷完，前期节奏明显加快
		spawn_interval = maxf(spawn_window / to_spawn, 0.3)
		spawn_t = 0.3
		current_elite_chance = minf(ELITE_CHANCE + 0.012 * (player_level - 1), 0.22)
		time_left = WAVE_TIME
		_last_time_shown = -1
		ui.update_wave(("无尽 · " if _endless else "") + "第 %d 波 · %ds" % [wave_i, int(WAVE_TIME)])
		if wave_i == 1:
			_add_floor()
			ui.flash_banner("区域 %d · %s" % [region_i + 1, reg["name"]])
	state = "wave"

func _set_mobs_frozen(f: bool) -> void:
	# 选牌期间冻结场上敌人与飞行物；波次开始解冻（残怪保留到首领战，绝不跨地图）
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.set_physics_process(not f)
	for b in get_tree().get_nodes_in_group("bullets"):
		if is_instance_valid(b):
			b.set_physics_process(not f)

func _edge_point() -> Vector2:
	match randi() % 4:
		0:
			return Vector2(randf_range(ARENA.position.x, ARENA.end.x), ARENA.position.y + 10)
		1:
			return Vector2(randf_range(ARENA.position.x, ARENA.end.x), ARENA.end.y - 10)
		2:
			return Vector2(ARENA.position.x + 10, randf_range(ARENA.position.y, ARENA.end.y))
		_:
			return Vector2(ARENA.end.x - 10, randf_range(ARENA.position.y, ARENA.end.y))

func _spawn_enemy() -> void:
	var reg: Dictionary = _safe_reg()
	var e
	if (region_i >= 1 or _endless) and randf() < (0.2 if region_i == 1 else 0.3):
		e = SpitterS.new()
		e.ebullet_spawner = _spawn_ebullet
	else:
		e = EnemyS.new()
	e.player = player
	e.arena = ARENA
	var tier := _wave_tier()
	var t: Dictionary = TIERS[tier]
	var elite: bool = wave_i >= 2 and randf() < current_elite_chance
	var hp_mult := 1.0
	var spd_mult := 1.0
	if region_i == 0:
		hp_mult = 1.0 + R1_HP_RAMP * (wave_i - 1)
		spd_mult = 1.0 + R1_SPD_RAMP * (wave_i - 1)
	if _endless:
		hp_mult *= 1.0 + 0.08 * _waves_cleared()  # 无尽：每清一波全体 +8%
	e.tier = tier
	e.is_elite = elite
	e.body_color = t["color"]
	e.tint = t["color"].lightened(0.25) if elite else t["color"]
	e.max_hp = 24.0 * float(t["hp"]) * hp_mult * (2.5 if elite else 1.0)
	e.armor = float(t["armor"]) * (2.0 if elite else 1.0)
	e.contact_damage = 10.0 * float(t["dmg"])
	e.speed = float(reg["speed"]) * spd_mult * (0.9 if elite else 1.0)
	e.xp = int(t["xp"]) * (3 if elite else 1)
	e.coin = 3 if elite else 1
	e.radius = 20.0 if elite else 14.0
	e.position = _edge_point()
	e.killed.connect(_on_enemy_killed)
	add_child(e)
	enemies_alive += 1
	to_spawn -= 1

func _wave_tier() -> int:
	# 区域各跨两档：波次前半低档、后半高档（白白绿 → 蓝蓝橙橙 → 红红红金金）
	var base := region_i * 2
	var waves := int(_safe_reg()["waves"])
	var sub := 0
	if waves > 1:
		sub = int(float(wave_i - 1) * 2.0 / float(waves))
	return clampi(base + sub, 0, TIERS.size() - 1)

func _summon_minion(pos: Vector2, kind: String, elite: bool) -> void:
	# 末图首领召唤：最高难度（金）档位，近战/远程成对，每三次召唤为精英对
	if player == null or player.dead:
		return
	var e
	if kind == "ranged":
		e = SpitterS.new()
		e.ebullet_spawner = _spawn_ebullet
	else:
		e = EnemyS.new()
	var t: Dictionary = TIERS[TIERS.size() - 1]
	e.player = player
	e.arena = ARENA
	e.tier = TIERS.size() - 1
	e.is_elite = elite
	e.body_color = t["color"]
	e.tint = t["color"].lightened(0.25) if elite else t["color"]
	e.max_hp = 24.0 * float(t["hp"]) * (2.5 if elite else 1.0)
	e.armor = float(t["armor"]) * (2.0 if elite else 1.0)
	e.contact_damage = 10.0 * float(t["dmg"])
	e.speed = float(regions[regions.size() - 1]["speed"]) * (0.9 if elite else 1.0)
	e.xp = int(t["xp"]) * (3 if elite else 1)
	e.coin = 3 if elite else 1
	e.radius = 20.0 if elite else 14.0
	e.position = pos.clamp(ARENA.position + Vector2.ONE * 30.0, ARENA.end - Vector2.ONE * 30.0)
	e.killed.connect(_on_enemy_killed)
	e.add_to_group("minions")
	add_child(e)
	enemies_alive += 1

func _spawn_boss(reg: Dictionary) -> void:
	_boss_refs = []
	if _endless:
		# 无尽：随机三首领之一，血量随次数增强
		var b0
		match randi() % 3:
			0:
				b0 = BossS.new()
			1:
				b0 = BossSpitterS.new()
				b0.ebullet_spawner = _spawn_ebullet
				b0.twin_cb = _revive_twin
			_:
				b0 = BossSummonerS.new()
				b0.summon_cb = _summon_minion
		_endless_boss_n += 1
		b0.max_hp = float(reg["boss_hp"]) * (1.6 + 0.8 * _endless_boss_n)
		b0.coin = 25
		_setup_boss(b0)
	else:
		match region_i:
			1:
				# 区域 2：双吐弹首领（10s 内相继击杀，否则复活连锁）
				var b1 := _setup_boss(BossSpitterS.new())
				b1.ebullet_spawner = _spawn_ebullet
				b1.twin_cb = _revive_twin
				b1.position = ARENA.get_center() + Vector2(-160, 0)
				var b2 := _setup_boss(BossSpitterS.new())
				b2.ebullet_spawner = _spawn_ebullet
				b2.twin_cb = _revive_twin
				b2.position = ARENA.get_center() + Vector2(160, 0)
				b1.other = b2
				b2.other = b1
			2:
				# 区域 3：激光×2、生命 ×1.5
				var b3 := _setup_boss(BossSummonerS.new())
				b3.summon_cb = _summon_minion
				b3.laser_mult = 2.0
			_:
				# 区域 1：冲锋首领 血×1.5 / 防×1.5 / 攻×2
				var b4 := _setup_boss(BossS.new())
				b4.contact_damage *= 2.0  # 统一乘区之外的攻击特化
	ui.show_boss()

func _setup_boss(b) -> Node2D:
	# 全首领统一强化乘区（第八轮 playtest）：血×2、护甲×1.5、移速×1.2
	b.player = player
	b.arena = ARENA
	b.max_hp *= 2.0
	b.hp = b.max_hp
	b.armor = b.armor * 1.5 + 2.0
	b.speed *= 1.2
	if b.position == Vector2.ZERO:
		b.position = _edge_point()
	b.killed.connect(_on_boss_killed)
	add_child(b)
	_boss_refs.append(b)
	boss_ref = b
	enemies_alive += 1
	return b

func _revive_twin(pos: Vector2) -> void:
	# 存活者复活搭档（满血）；两只同在则连锁结束
	var alive_twins := 0
	for b in _boss_refs:
		if is_instance_valid(b) and not b._dead:
			alive_twins += 1
	if alive_twins >= 2 or alive_twins == 0:
		return
	var nb := _setup_boss(BossSpitterS.new())
	nb.ebullet_spawner = _spawn_ebullet
	nb.twin_cb = _revive_twin
	nb.max_hp = float(regions[1]["boss_hp"])
	nb.position = pos.clamp(ARENA.position + Vector2.ONE * 40.0, ARENA.end - Vector2.ONE * 40.0)
	ui.flash_banner("吐弹首领复活了！")
	SFX.play("boss")
	if not meta_d.get("tutorial_done", false) and not _hint_boss:
		_hint_boss = true
		ui.show_hint("首领蓄力变黄时，躲开它的冲锋直线", 4.0)

func _spawn_bullet(pos: Vector2, dir: Vector2, dmg: float, pierce: int, bounce: int, from_player: Node2D) -> void:
	var b := BulletS.new()
	b.position = pos
	b.dir = dir
	b.dmg = dmg
	b.pierce_left = pierce
	b.bounce_left = bounce
	b.owner_player = from_player
	if from_player.get("weapon_level") != null and int(from_player.get("weapon_level")) >= 4:
		b.bullet_color = Color(1.0, 0.82, 0.25)  # 进化形态金色弹道
	add_child(b)

func _spawn_boomerang(pos: Vector2, dir: Vector2, dmg: float, from_player: Node2D) -> void:
	var b := BoomerangS.new()
	b.position = pos
	b.dir = dir
	b.dmg = dmg
	b.owner_player = from_player
	add_child(b)

func _spawn_ebullet(pos: Vector2, dir: Vector2, spd: float, dmg: float) -> void:
	var b := EBulletS.new()
	b.position = pos
	b.dir = dir
	b.speed = spd
	b.dmg = dmg
	b.player = player
	add_child(b)

func _card_pool() -> Array:
	var unlocked: Array = meta_d.get("cards", [])
	return Cards.all_cards().filter(func(c): return bool(c.get("m0", false)) or c["id"] in unlocked)

func _on_enemy_killed(coin_value: int, pos: Vector2, xp_value: int) -> void:
	enemies_alive -= 1
	kills += 1
	player.on_kill()
	add_xp(xp_value)
	combo_n += 1
	combo_t = COMBO_WINDOW
	if combo_n % 10 == 0:
		var bonus := 3 + combo_n / 10  # 连杀奖励递增：10 连+4、20 连+5……
		run_coins += bonus
		ui.show_hint("连杀 ×%d！+%d 金币" % [combo_n, bonus], 1.0)
	ui.update_combo(combo_n)
	var gain := coin_value
	if randf() < player.gold_chance:
		gain += 1
	if player.lifesteal > 0.0:
		player.hp = minf(player.hp + player.lifesteal, player.max_hp)
	run_coins += gain
	ui.update_coins(run_coins)
	if xp_value > 0 and get_tree().get_node_count() < 800:
		_spawn_xp_crystal(pos)
	if player.burst:
		# 爆裂弹：击杀点小范围爆炸（仅伤害，不计币防连锁刷钱）
		for e in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(e) and e.position.distance_to(pos) <= 90.0:
				e.take_damage(12.0, player)
		FX.hit_spark(pos, Color(1.0, 0.6, 0.2))

# ---- 经验升级 ----

func _xp_needed() -> int:
	# 二次曲线：前期快（开场快速成型），后期慢（靠构筑质量），参考同类节奏
	var l := player_level - 1
	return 12 + 6 * l + 2 * l * l

func add_xp(n: int) -> void:
	if n <= 0:
		return
	xp_accum += n
	while xp_accum >= _xp_needed():
		xp_accum -= _xp_needed()
		player_level += 1
		pending_picks += 1
	ui.update_xp(player_level, xp_accum, _xp_needed())
	if pending_picks > 0 and state == "wave":
		_enter_draft()  # 升级瞬间弹卡（冻结全场含玩家）

func _wave_time_up() -> void:
	# 普通波固定时长到点：清波奖励照发，残怪保留，直接进入下一波（升级选卡由经验驱动）
	run_coins += 2 + player.magnet
	ui.update_coins(run_coins)
	_start_inter(0.5)

func _on_boss_killed(coin_value: int, _pos: Vector2, _xp_value: int) -> void:
	# 首领波唯一出口：打完首领才换图/推进无尽；残怪随首领死亡清空，绝不跨地图带入
	kills += 1
	run_coins += coin_value
	ui.update_coins(run_coins)
	add_xp(BOSS_XP)
	# 多首领门禁（区域 2 双吐弹）：仍有存活首领 → 只结算此只，不清场不推进，等连锁击杀
	var survivor: Node2D = null
	for b in _boss_refs:
		if b != null and is_instance_valid(b) and not b._dead:
			survivor = b
			break
	if survivor != null:
		boss_ref = survivor  # HUD 血条跟随存活者
		ui.show_boss()
		ui.flash_banner("双首领：10 秒内击杀另一只！")
		return
	boss_ref = null
	ui.hide_boss()
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.queue_free()
	for b in get_tree().get_nodes_in_group("bullets"):
		if is_instance_valid(b):
			b.queue_free()
	enemies_alive = 0
	wave_i = 0
	if _endless:
		region_i = regions.size() - 1  # 无尽钳在最后一图，防 region_i 无限自增越界
	elif region_i + 1 >= regions.size():
		_endless = true  # 通关转无尽：金档怪每波增强，每 6 波随机首领，刷金币
		ui.flash_banner("无尽模式！越刷越强，金币拿到手软！")
		SFX.play("win")
		if smoke:  # smoke 以通关三图为 win 终止（无尽不进自测）
			_smoke_finish("win")
			return
	else:
		region_i += 1
	SFX.play("wave")
	if pending_picks > 0:
		_post_boss_advance = true
		_enter_draft()
	else:
		_start_inter(0.8)

func _enter_draft() -> void:
	state = "draft"
	_set_mobs_frozen(true)  # 升级选卡冻结全场：敌人、飞行物与玩家（防白嫖无伤清怪）
	player.active = false
	player.drafting = true  # 冻结期间玩家伤害强制为 0（环刃等持续源同样归零）
	_smoke_pick_t = 0.6
	if not meta_d.get("tutorial_done", false) and not _hint_draft:
		_hint_draft = true
		ui.show_hint("打怪攒经验，升级就能三选一", 4.0)
	# 升级卡只出「当前武器 && 下一等级」；被动通用
	var pool := _draft_pool()
	_offer = _weighted_offer(pool, not _first_draft_done)
	_first_draft_done = true
	ui.show_draft(_offer, _on_card_picked, "升级 Lv%d！选择一张牌" % player_level)

func _draft_pool() -> Array:
	var wtag: String = Cards.WEAPON_TAGS[player.weapon_id]
	var out: Array = []
	for c in _card_pool():
		if c["kind"] == "passive":
			var req: Array = c.get("req", [])
			if req.is_empty() or wtag in req:
				out.append(c)
		elif c["weapon"] == player.weapon_id and int(c["tier"]) == player.weapon_level + 1:
			out.append(c)
	return out

func _card_weight(c: Dictionary) -> float:
	if c["kind"] == "weapon":
		return 2.5  # 武器升级线优先成型
	return 2.5 if player.has_passive(c["id"]) else 1.0

func _weighted_offer(pool: Array, first: bool) -> Array:
	var offer: Array = []
	var work := pool.duplicate()
	if first:
		for i in work.size():
			if work[i]["kind"] == "weapon":
				offer.append(work[i])
				work.remove_at(i)
				break
	while offer.size() < 3 and not work.is_empty():
		var total := 0.0
		for c in work:
			total += _card_weight(c)
		var roll := randf() * total
		var pick_i := work.size() - 1
		for i in work.size():
			roll -= _card_weight(work[i])
			if roll <= 0.0:
				pick_i = i
				break
		offer.append(work[pick_i])
		work.remove_at(pick_i)
	return offer

func _enter_startpick() -> void:
	state = "startpick"
	_set_mobs_frozen(true)
	player.active = false
	player.drafting = true
	_smoke_pick_t = 0.6
	var pool := _card_pool().filter(func(c): return c["kind"] == "passive")
	pool.shuffle()
	_offer = pool.slice(0, 3)
	ui.show_draft(_offer, _on_card_picked, "开局免费三选一（被动）")

func _on_card_picked(i: int) -> void:
	if state != "draft" and state != "startpick":
		return
	if i >= _offer.size():
		return
	_offer[i]["apply"].call(player)
	if _offer[i]["kind"] == "passive":
		player.owned_passives.append(_offer[i]["id"])
	ui.hide_draft()
	SFX.play("pick")
	if state == "startpick":
		player.drafting = false
		_start_inter(1.0)
		return
	# 升级选卡：一次波内连升则继续弹卡，选完解冻回波次（计时不动，波时长仍固定）
	pending_picks -= 1
	if pending_picks > 0:
		_enter_draft()
		return
	player.drafting = false
	player.active = true
	if _post_boss_advance:
		_post_boss_advance = false
		_start_inter(0.8)
		return
	state = "wave"
	_set_mobs_frozen(false)

func _on_player_died() -> void:
	_finish("over")

func _finish(result: String) -> void:
	state = result
	player.active = false
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.set_physics_process(false)
	for b in get_tree().get_nodes_in_group("bullets"):
		if is_instance_valid(b):
			b.queue_free()
	var pity := 0
	if result != "win":
		pity = _death_pity()
		run_coins += pity
	var total_after := 0
	if not smoke:  # smoke/soak 不污染真实存档（金币与教学标记都在此分支内）
		var d := MetaS.load_data()
		total_after = int(d.get("coins", 0)) + run_coins
		d["coins"] = total_after
		if not d.get("tutorial_done", false):
			d["tutorial_done"] = true
		MetaS.save_data(d)
	if result == "win":
		ui.show_over("通关！击杀 %d · 本局 +%d 金币（累计 %d）\n%s\n按 R 重开" % [kills, run_coins, total_after, _next_unlock_hint(total_after)])
		SFX.play("win")
	else:
		var where := ("无尽第 %d 波" % wave_i) if _endless else ("区域 %d 第 %d 波" % [region_i + 1, wave_i])
		ui.show_over("你在%s倒下了。击杀 %d\n战斗收益 %d + 进度保底 %d = 本局 +%d（累计 %d）\n%s\n按 R 重开" % [where, kills, run_coins - pity, pity, run_coins, total_after, _next_unlock_hint(total_after)])
		SFX.play("lose")
	if smoke:
		_smoke_finish(result)

func _next_unlock_hint(coins_now: int) -> String:
	var id := _next_locked_card()
	if id == "":
		return "牌池已集齐——金币可投入角色强化"
	var c: Dictionary = Cards.get_card(id)
	return "下一解锁「%s」还差 %d 币" % [c["name"], maxi(Cards.unlock_cost(id) - coins_now, 0)]

func _waves_cleared() -> int:
	var n := 0
	for i in region_i:
		n += int(regions[i]["waves"])
	if region_i < regions.size():
		n += maxi(wave_i - 1, 0)
	return n

func _expected_win_coins() -> float:
	# 通关期望收益（与 --sim 同一组公式）：击杀期望 + 清波 +2 + 首领 15
	var total := 15.0 * regions.size()
	for ri in regions.size():
		var reg: Dictionary = regions[ri]
		for w in range(1, int(reg["waves"]) + 1):
			var n := 4 + w * 2
			var elites := ELITE_CHANCE * n if w >= 2 else 0.0
			total += (n - elites) + elites * 3.0 + 2.0
	return total

func _death_pity() -> int:
	# 保底 = min(每波/首领补偿, 固定上限, 通关期望 90% - 已赚)：保证区域 2 起死局 ≥ 40% 通关期望，
	# 且死局永远不超通关的 90%（死亡刷币无激励）。不变量由 --sim 校验。
	var base := mini(PITY_PER_WAVE * _waves_cleared() + PITY_PER_BOSS * region_i, PITY_CAP)
	var cap := maxi(int(_expected_win_coins() * 0.9) - run_coins, 0)
	return mini(base, cap)

func _smoke_finish(result: String) -> void:
	if soak:
		_soak_done += 1
		print("SOAK cycle=%d/%d result=%s nodes=%d" % [_soak_done, SOAK_CYCLES, result, get_tree().get_node_count()])
		if _soak_done >= SOAK_CYCLES:
			print("SOAK_OK")
			get_tree().quit()
			return
		get_tree().reload_current_scene()
		return
	print("SMOKE_OK result=%s region=%d wave=%d kills=%d run_coins=%d buy_card=%s buy_level=%s buy_pick=%s wtest=%s meta_coins=%d t_ms=%d" % [
		result, region_i, wave_i, kills, run_coins,
		str(_smoke_buys["card"]), str(_smoke_buys["level"]), str(_smoke_buys["pick"]),
		str(_smoke_wtest_done), int(meta_d.get("coins", 0)), Time.get_ticks_msec() - _t0])
	get_tree().quit()

# ---- 平衡模拟（--sim）：与刷怪/经济共用同一组常量的解析模型 ----
# 假设：已清波全杀、死亡波击杀 50%、未计召唤物/磁石/黄金子弹（基线）
# 不变量：区域 2 起任意死亡点收益 ≥ 通关期望的 40%；任意死亡点 ≤ 通关期望的 105%
func _run_sim() -> void:
	var win := _expected_win_coins()
	var min_r2 := 1e9
	var max_ratio := 0.0
	var earned := 0.0
	var bosses := 0
	var waves_done := 0
	for ri in regions.size():
		var reg: Dictionary = regions[ri]
		for w in range(1, int(reg["waves"]) + 1):
			var n := 4 + w * 2
			var elites := ELITE_CHANCE * n if w >= 2 else 0.0
			var wc := (n - elites) + elites * 3.0
			var part := earned + 0.5 * wc
			var pity := minf(minf(PITY_PER_WAVE * waves_done + PITY_PER_BOSS * bosses, PITY_CAP), maxf(0.9 * win - part, 0.0))
			var ratio := (part + pity) / win
			if bosses >= 1:
				min_r2 = minf(min_r2, ratio)
			max_ratio = maxf(max_ratio, ratio)
			print("SIM die R%dW%d earned=%.1f pity=%d total=%.1f ratio=%.2f" % [ri + 1, w, part, int(pity), part + pity, ratio])
			earned += wc + 2.0
			waves_done += 1
		var part_b := earned
		var pity_b := minf(minf(PITY_PER_WAVE * waves_done + PITY_PER_BOSS * bosses, PITY_CAP), maxf(0.9 * win - part_b, 0.0))
		var ratio_b := (part_b + pity_b) / win
		if bosses >= 1:
			min_r2 = minf(min_r2, ratio_b)
		max_ratio = maxf(max_ratio, ratio_b)
		print("SIM die R%dBOSS earned=%.1f pity=%d total=%.1f ratio=%.2f" % [ri + 1, part_b, int(pity_b), part_b + pity_b, ratio_b])
		earned += 15.0
		bosses += 1
	var ok := min_r2 >= 0.4 and max_ratio <= 1.05
	print("SIM win=%.1f min_r2_ratio=%.2f max_ratio=%.2f invariants=%s" % [win, min_r2, max_ratio, "pass" if ok else "FAIL"])
	print("SIM_OK" if ok else "SIM_FAIL")
	get_tree().quit()

# ---- smoke 自检：静止假人依次验证 回旋镖/电弧/环刃 可造成伤害，敌弹可命中玩家 ----

func _smoke_pick_index() -> int:
	# smoke 自动选牌优先被动：避免抽到低射速武器拖慢通关
	for i in _offer.size():
		if _offer[i]["kind"] == "passive":
			return i
	return randi_range(0, _offer.size() - 1)

func _smoke_weapon_test(delta: float) -> void:
	if _wtest_phase == 0:
		inter_t = 999.0  # 自检期间挂起倒计时
		# 升级卡路径自检：龙狙 u2/u3 逐级生效（u3：伤害 +45%、对精英 +15%）
		player.set_weapon("w_dragon")
		player.upgrade_weapon()
		player.upgrade_weapon()
		if player.weapon_level != 3 or player.dragon_dmg_mult < 1.45 or player.giant_slayer < 0.15:
			_smoke_finish("upg_fail")
			return
		# 卡池纯净自检：蛮兵（环刃 Lv1）视角——只允许环刃升级卡，且不得出现弹射透镜/二连发
		var saved_weapon: String = player.weapon_id
		player.weapon_id = "w_sawblade"
		player.weapon_level = 1
		var saw_pool_ids := []
		for c in _draft_pool():
			saw_pool_ids.append(str(c["id"]))
			if c["kind"] == "weapon" and c["weapon"] != "w_sawblade":
				_smoke_finish("pool_fail")
				return
			if c["id"] == "p_lens" or c["id"] == "p_double":
				_smoke_finish("pool_fail")
				return
		if not ("u_saw_2" in saw_pool_ids):
			_smoke_finish("pool_fail")
			return
		player.weapon_id = saved_weapon
		player.weapon_level = 1
		_wtest_spawn(150.0)
		player.set_weapon("w_boomerang")
		_wtest_base = _wtest_hp_sum()
		_wtest_t = 0.0
		_wtest_phase = 1
		return
	_wtest_t += delta
	var hit := false
	match _wtest_phase:
		1, 2, 3:
			hit = _wtest_hp_sum() < _wtest_base - 0.5
		4:
			hit = player.hp < _wtest_base - 0.5
		5:
			hit = true
			for d in _wtest_dummies:
				if is_instance_valid(d) and not d._dead:
					hit = false
	if hit:
		_wtest_next_phase()
	elif _wtest_t > 6.0:
		_smoke_finish("wtest_fail_phase%d" % _wtest_phase)

func _wtest_next_phase() -> void:
	_wtest_phase += 1
	_wtest_t = 0.0
	_wtest_clear()  # 每阶段独立假人并清空飞行物，杜绝跨阶段伤害污染造成的假阳性
	match _wtest_phase:
		2:
			_wtest_spawn(150.0)
			player.set_weapon("w_arc")
			_wtest_base = _wtest_hp_sum()
		3:
			_wtest_spawn(60.0)  # 假人放在环刃轨道（56px）可达处
			player.set_weapon("w_sawblade")
			_wtest_base = _wtest_hp_sum()
		4:
			_wtest_spawn(150.0)
			player.set_weapon("w_dragon")
			var eb := EBulletS.new()
			eb.dir = Vector2.RIGHT
			eb.speed = 200.0
			eb.dmg = 8.0
			eb.player = player
			eb.position = player.position + Vector2(-100, 0)
			add_child(eb)
			_wtest_base = player.hp
		5:
			# 爆裂弹链式自检：相邻两低血假人，杀其一波及另一个；死亡守卫失效会递归卡死并被超时暴露
			_wtest_clear()
			player.burst = true
			for off in [Vector2(30, 0), Vector2(30, 30)]:
				var d := EnemyS.new()
				d.player = player
				d.arena = ARENA
				d.max_hp = 5.0
				d.speed = 0.0
				d.position = ARENA.get_center() + off
				add_child(d)
				_wtest_dummies.append(d)
			_wtest_dummies[0].take_damage(999.0, player)
		6:
			player.burst = false
			_wtest_end()

func _wtest_spawn(off_x: float) -> void:
	for off in [Vector2(off_x, 0), Vector2(-off_x * 0.8, 40)]:
		var d := EnemyS.new()
		d.player = player
		d.arena = ARENA
		d.max_hp = 1000000000.0
		d.speed = 0.0
		d.position = ARENA.get_center() + off
		add_child(d)
		_wtest_dummies.append(d)

func _wtest_clear() -> void:
	for d in _wtest_dummies:
		if is_instance_valid(d):
			d.queue_free()
	_wtest_dummies = []
	for b in get_tree().get_nodes_in_group("bullets"):
		if is_instance_valid(b):
			b.queue_free()

func _wtest_hp_sum() -> float:
	var s := 0.0
	for d in _wtest_dummies:
		if is_instance_valid(d):
			s += d.hp
	return s

func _wtest_end() -> void:
	_wtest_clear()
	_smoke_wtest_done = true
	inter_t = 0.4
