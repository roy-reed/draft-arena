extends Node2D
# 主流程：主菜单（角色三选一 + meta 商店）→ 刷怪 → 清波三选一 → 区域首领 → 结算金币入档
# smoke 自测：godot --headless --path . -- --smoke
# 6 倍速自动：选角色 1 → 发 500 币买满三条 meta 线 → 新武器命中自检 → 打通 3 区域 → SMOKE_OK

const Cards := preload("res://scripts/cards.gd")
const EventBusS := preload("res://scripts/core/event_bus.gd")
const MetaS := preload("res://scripts/meta.gd")
const PlayerS := preload("res://scripts/player.gd")
const EnemyS := preload("res://scripts/enemy.gd")
const SpitterS := preload("res://scripts/spitter.gd")
const BulletS := preload("res://scripts/bullet.gd")
const EBulletS := preload("res://scripts/ebullet.gd")
const BoomerangS := preload("res://scripts/boomerang.gd")
const UIS := preload("res://scripts/ui.gd")
const PauseHookS := preload("res://scripts/pause_hook.gd")
const TouchControlsS := preload("res://scripts/touch_controls.gd")
const CrystalS := preload("res://scripts/crystal.gd")
const BossEncounterS := preload("res://scripts/bosses/boss_encounter_controller.gd")
const TwinBossEncounterS := preload("res://scripts/bosses/twin_boss_encounter_controller.gd")
const ChargeBossDefinition := preload("res://resources/bosses/charge_boss.tres")
const SpitterBossDefinition := preload("res://resources/bosses/spitter_boss.tres")
const SummonerBossDefinition := preload("res://resources/bosses/summoner_boss.tres")
const BossTestRunnerS := preload("res://scripts/tests/boss_test_runner.gd")
const SpawnCurveS := preload("res://scripts/spawn_curve.gd")

const ARENA := Rect2(40, 40, 1200, 640)
const CHAR_LEVEL_MAX := 5
const CHAR_LEVEL_COST := 25
const START_PICK_COST := 40
const PITY_PER_WAVE := 12   # 死亡保底：每个已清普通波
const PITY_PER_BOSS := 24   # 死亡保底：每个已击杀首领
const PITY_CAP := 60        # 保底上限：配合通关期望 90% 总上限防止死亡刷币
const SOAK_CYCLES := 5      # --soak 长跑：完整重载场景的循环次数
const ELITE_CHANCE := 0.12  # 第 2 波起精英概率（--sim 与刷怪共用，勿只改一处）
const R1_HP_RAMP := 0.15    # 区域 1 逐波爬坡：每波敌人 HP +15%（负值即减压，方向待 playtest 校准）
const R1_SPD_RAMP := 0.05   # 区域 1 逐波爬坡：每波移速 +5%
const WAVE_TIME := 30.0     # 普通波固定时长（秒）；首领波无计时，打完首领才进下一地图
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
var _banked_run_coins := 0
static var _retry_char := -1
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
var current_spawn_multiplier := 1.0
var peak_enemies_alive := 0
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
var _boss_encounter: BossEncounterController = null
static var _soak_done := 0  # 跨场景重载持久（实例变量会被 reload 重置）
var _smoke_pick_t := 0.0
var _smoke_buys := {"card": false, "level": false, "pick": false}
var _smoke_wtest_done := false
var _hint_draft := false
var _first_draft_done := false
var _wtest_phase := 0
var _wtest_t := 0.0
var _wtest_base := 0.0
var _wtest_dummies: Array = []
var _t0 := 0
var touch: TouchControls = null
var _mobile_preview := false
# M3 性能/等价性对比：--seed=N 固定随机序列；--legacy-collision 退回线性扫描；--grid-verify 逐次比对
var _seed := -1
var _digest := 0
var _frame0 := 0
var _phys_samples := PackedFloat32Array()
var _preview_inset := Vector4.ZERO

func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	_parse_perf_args(user_args)
	if "--boss-test" in user_args:
		get_tree().quit(BossTestRunnerS.run())
		return
	get_tree().auto_accept_quit = false
	_add_floor()
	smoke = "--smoke" in user_args or "--soak" in user_args
	soak = "--soak" in user_args
	_shot = "--shot" in user_args
	# 桌面上预览手游版：强制触屏模式 + expand；可用 --safe-inset=左,上,右,下（屏幕像素）模拟挖孔/手势条
	if "--mobile-preview" in user_args:
		TouchControls.force_touch = 1
		_mobile_preview = true
		for a in user_args:
			if a.begins_with("--safe-inset="):
				var p := a.trim_prefix("--safe-inset=").split(",")
				if p.size() == 4:
					_preview_inset = Vector4(float(p[0]), float(p[1]), float(p[2]), float(p[3]))
	if "--sim" in user_args:
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
	touch = TouchControlsS.new()
	touch.main = self
	add_child(touch)
	ui.over_restart_cb = _cb_restart
	ui.set_touch_mode(touch.touch_enabled)
	touch.touch_mode_changed.connect(Callable(ui, "set_touch_mode"))
	touch.input_kind_changed.connect(Callable(ui, "set_text_touch"))
	if TouchControls.detect_touch_device():
		_setup_mobile_screen()
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

	elif _retry_char >= 0:
		var retry := _retry_char
		_retry_char = -1
		_menu_select(retry)
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

func _parse_perf_args(user_args: PackedStringArray) -> void:
	_frame0 = Engine.get_physics_frames()
	EnemyGrid.enabled = not ("--legacy-collision" in user_args)
	EnemyGrid.verify = "--grid-verify" in user_args
	EnemyGrid.reset_stats()  # soak 每轮重载场景时按轮统计
	for a in user_args:
		if a.begins_with("--seed="):
			_seed = int(a.trim_prefix("--seed="))
			seed(_seed)

func _perf_summary() -> String:
	var n := _phys_samples.size()
	var avg := 0.0
	var p95 := 0.0
	if n > 0:
		var sorted := _phys_samples.duplicate()
		sorted.sort()
		for v in sorted:
			avg += v
		avg /= n
		p95 = sorted[mini(n - 1, int(n * 0.95))]
	return "seed=%d collision=%s checks=%d queries=%d mismatches=%d frames=%d digest=%08x phys_avg_us=%d phys_p95_us=%d" % [
		_seed, "grid" if EnemyGrid.enabled else "linear", EnemyGrid.checks, EnemyGrid.queries, EnemyGrid.mismatches,
		Engine.get_physics_frames() - _frame0, _digest & 0xffffffff, int(avg * 1e6), int(p95 * 1e6)]

func _process(delta: float) -> void:
	if smoke:
		_phys_samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
	if _shot:
		_shot_t += delta
		if (state == "draft" or state == "startpick") and _shot_t > 0.6:
			_on_card_picked(_smoke_pick_index())  # 截图模式自动选卡，进入波次以便目视小怪
		if _shot_phase == 0 and _shot_t > 1.2:
			_shot_phase = 1
			if not _save_shot("shot_menu.png"):
				get_tree().quit(1)
				return
			_menu_start()
			_shot_t = 0.0
		elif _shot_phase == 1 and _shot_t > 4.5:
			_shot_phase = 2
			if not _save_shot("shot_game.png"):
				get_tree().quit(1)
				return
			print("SHOT_OK")
			get_tree().quit()
			return
	if player != null:
		ui.update_hp(player.hp, player.max_hp)
		ui.update_stats(player.combat_summary())
	if _boss_encounter == null and boss_ref != null and is_instance_valid(boss_ref):
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
						if enemies_alive < mob_cap:
							_spawn_enemy()
					if time_left <= 0.0:
						_wave_time_up()
			# 首领波无计时：由统一 encounter 完成信号推进
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
	var stale_encounter := _boss_encounter
	_boss_encounter = null
	if stale_encounter != null and is_instance_valid(stale_encounter):
		stale_encounter.abort("run_restarted")
		stale_encounter.queue_free()
	run_coins = 0
	_banked_run_coins = 0
	kills = 0
	region_i = 0
	wave_i = 0
	is_boss_wave = false
	enemies_alive = 0
	boss_ref = null
	_endless = false
	_endless_boss_n = 0
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
		ui.show_hint(_ui_text("tutorial"), 6.0)

func _save_shot(fname: String) -> bool:
	if DisplayServer.get_name() == "headless":
		push_error("SHOT_FAILED: --shot requires a real display; do not combine it with --headless")
		return false
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("SHOT_FAILED: viewport image is unavailable")
		return false
	var path := "user://" + fname  # 导出后 res:// 不可写，统一存 AppData
	var error := img.save_png(path)
	if error != OK:
		push_error("SHOT_FAILED: cannot save %s (error %d)" % [path, error])
		return false
	print("SHOT_SAVED ", ProjectSettings.globalize_path(path), " ", img.get_width(), "x", img.get_height())
	return true

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
					_cb_quit()
			KEY_SPACE:
				if paused:
					_set_paused(false)
			KEY_R:
				if paused or state in ["over", "win"]:
					_cb_restart()
			KEY_TAB:
				if player != null:
					ui.toggle_stats()
			KEY_Q:
				if paused:
					_cb_quit()
			KEY_F11:
				var mode := DisplayServer.window_get_mode()
				DisplayServer.window_set_mode(
					DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN
					else DisplayServer.WINDOW_MODE_FULLSCREEN)

# 提示文案按输入方式取键鼠版/触屏版；没有 text() 的替身 UI（测试）回退到键鼠原文
func _ui_text(key: String) -> String:
	if ui != null and ui.has_method("text"):
		return ui.text(key)
	return UIS.TEXTS[key][0]

# ---- 移动端屏幕适配（M2）：expand + 竞技场居中 + 安全区；桌面端不调用 ----

func _setup_mobile_screen() -> void:
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	RenderingServer.set_default_clear_color(ScreenLayout.BG_COLOR)
	get_viewport().size_changed.connect(_apply_screen_layout)
	_apply_screen_layout()

func _apply_screen_layout() -> void:
	var vp := get_viewport()
	var visible := vp.get_visible_rect().size
	vp.canvas_transform = Transform2D(0.0, ScreenLayout.world_offset(visible))
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if _mobile_preview:  # 桌面的“安全区”是去掉任务栏的工作区，预览时改用窗口内的模拟边距
		safe = Rect2(_preview_inset.x, _preview_inset.y, win.x - _preview_inset.x - _preview_inset.z, win.y - _preview_inset.y - _preview_inset.w)
	var m := ScreenLayout.safe_margins(win, safe, visible)
	ui.apply_safe_area(m)
	touch.apply_safe_area(m)

# ---- 移动端：暂停按钮、Android 返回键、切到后台（桌面端不会收到这些通知） ----

const PAUSABLE_STATES := ["inter", "wave", "draft", "startpick"]

# 纯函数：返回键在当前状态下的动作。暂停中→继续；对局中→暂停；结算→重开（回主菜单）；主菜单→退出。
static func back_action(cur_state: String, is_paused: bool) -> String:
	if is_paused:
		return "resume"
	if cur_state in PAUSABLE_STATES:
		return "pause"
	if cur_state in ["over", "win"]:
		return "restart"
	return "quit"

func request_pause() -> void:
	if not paused and state in PAUSABLE_STATES:
		_set_paused(true)

func handle_back() -> void:
	if smoke:
		return
	match back_action(state, paused):
		"resume": _set_paused(false)
		"pause": _set_paused(true)
		"restart": _cb_restart()
		"quit": _cb_quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_cb_quit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		handle_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		if not smoke and ui != null:
			request_pause()

func _set_paused(v: bool) -> void:
	paused = v
	get_tree().paused = v
	if v:
		if player != null:
			ui.update_stats(player.combat_summary())
		ui.show_pause(_pause_cbs())
	else:
		ui.hide_pause()

func _pause_cbs() -> Dictionary:
	return {"resume": _cb_resume, "restart": _cb_restart, "menu": _cb_menu, "quit": _cb_quit, "volume": _cb_volume}

func _cb_resume() -> void:
	_set_paused(false)

func _cb_restart() -> void:
	if state in PAUSABLE_STATES:
		_retry_char = char_i
	_bank_run_coins()
	_set_paused(false)
	get_tree().reload_current_scene()

func _cb_menu() -> void:
	_retry_char = -1
	_bank_run_coins()
	_set_paused(false)
	get_tree().reload_current_scene()

func _cb_quit() -> void:
	_bank_run_coins()
	get_tree().quit()

func _bank_run_coins() -> int:
	# 只保存已赚金币，不把主动退出当死亡发保底；重复调用不会重复入账。
	if smoke:
		return 0
	var data := MetaS.load_data()
	var pending := maxi(run_coins - _banked_run_coins, 0)
	data["coins"] = int(data["coins"]) + pending
	if pending > 0:
		MetaS.save_data(data)
		_banked_run_coins = run_coins
	return int(data["coins"])

func _cb_volume(v: float) -> void:
	SFX.set_volume(v)
	meta_d["volume"] = v
	MetaS.save_data(meta_d)

func _safe_reg() -> Dictionary:
	return regions[mini(region_i, regions.size() - 1)]


func _campaign_regular_wave_count() -> int:
	var total := 0
	for reg in regions:
		total += int(reg["waves"])
	return total


func _spawn_density_multiplier() -> float:
	if _endless:
		return SpawnCurveS.ENDLESS_MULTIPLIER
	return SpawnCurveS.campaign_multiplier(_waves_cleared() + 1, _campaign_regular_wave_count())


func _register_enemy_spawned() -> void:
	enemies_alive += 1
	peak_enemies_alive = maxi(peak_enemies_alive, enemies_alive)


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
		var boss_result := _spawn_boss(reg)
		if boss_result != OK:
			_abort_boss_start(boss_result)
			return
		ui.update_wave(("无尽 · " if _endless else "") + "区域 %s · 首领！" % reg["name"])
		ui.flash_banner("首领来袭！")
	else:
		is_boss_wave = false
		# 威胁预算先跟随玩家等级，再叠加全局战役密度曲线；最终由 SpawnCurve 硬上限保护。
		var budget_mult := minf(1.0 + 0.12 * (player_level - 1), 1.8)
		var base_mob_cap := clampi(int(round((4 + wave_i * 2) * budget_mult)), 8, 32)
		current_spawn_multiplier = _spawn_density_multiplier()
		if _endless:
			mob_cap = SpawnCurveS.scaled_density(base_mob_cap, current_spawn_multiplier)
		else:
			mob_cap = SpawnCurveS.campaign_density(base_mob_cap, _waves_cleared() + 1, _campaign_regular_wave_count())
		to_spawn = mob_cap
		var spawn_window := 10.0 + wave_i * 2.0  # 出怪提速：波前段密集刷完，前期节奏明显加快
		spawn_interval = SpawnCurveS.interval_for(spawn_window, to_spawn)
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
	if is_instance_valid(_boss_encounter):
		_boss_encounter.set_process(not f)

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
	_register_enemy_spawned()

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
	var local_pos := to_local(pos)
	e.position = local_pos.clamp(ARENA.position + Vector2.ONE * 30.0, ARENA.end - Vector2.ONE * 30.0)
	e.killed.connect(_on_enemy_killed)
	e.add_to_group("minions")
	add_child(e)
	_register_enemy_spawned()


func _living_minion_count() -> int:
	var count := 0
	for minion in get_tree().get_nodes_in_group("minions"):
		if is_instance_valid(minion) and not minion.is_queued_for_deletion():
			count += 1
	return count

func _spawn_boss(reg: Dictionary) -> Error:
	if _endless:
		return _spawn_endless_boss(reg)
	match region_i:
		0:
			return _spawn_region_one_boss()
		1:
			return _spawn_region_two_boss()
		2:
			return _spawn_region_three_boss()
	return ERR_INVALID_DATA


func _make_boss_context(
		spawn_position: Vector2,
		mode: BossEncounterContext.Mode = BossEncounterContext.Mode.CAMPAIGN,
		endless_rank: int = 0,
		base_hp_override: float = -1.0
) -> BossEncounterContext:
	var context := BossEncounterContext.new()
	context.mode = mode
	context.region_index = region_i
	context.endless_rank = endless_rank
	context.arena = ARENA
	context.spawn_position = spawn_position
	context.player = player
	context.base_hp_override = base_hp_override
	context.rng.seed = randi()
	return context


func _make_boss_services() -> BossServices:
	var services := BossServices.new()
	services.spawn_enemy_projectile = _spawn_ebullet
	services.spawn_minion = _summon_minion
	services.living_minion_count = _living_minion_count
	return services


func _connect_boss_encounter(encounter: BossEncounterController) -> void:
	encounter.boss_spawned.connect(_on_encounter_boss_spawned)
	encounter.primary_changed.connect(_on_encounter_primary_changed)
	encounter.health_changed.connect(_on_encounter_health_changed)
	encounter.member_defeated.connect(_on_encounter_member_defeated)
	encounter.completed.connect(_on_boss_encounter_completed)
	encounter.aborted.connect(_on_boss_encounter_aborted)


func _start_single_boss_encounter(definition: BossDefinition, context: BossEncounterContext) -> Error:
	var encounter := BossEncounterS.new() as BossEncounterController
	_connect_boss_encounter(encounter)
	add_child(encounter)
	var result := encounter.start_single(definition, context, _make_boss_services())
	if result != OK:
		encounter.queue_free()
		push_error("Boss encounter failed to start: %s" % error_string(result))
		return result
	_boss_encounter = encounter
	ui.show_boss()
	return OK

func _spawn_region_one_boss() -> Error:
	return _start_single_boss_encounter(ChargeBossDefinition, _make_boss_context(_edge_point()))


func _spawn_region_two_boss() -> Error:
	var contexts: Array[BossEncounterContext] = []
	for offset_x in [-160.0, 160.0]:
		contexts.append(_make_boss_context(ARENA.get_center() + Vector2(offset_x, 0.0)))

	var encounter := TwinBossEncounterS.new() as TwinBossEncounterController
	_connect_boss_encounter(encounter)
	encounter.revive_window_started.connect(_on_twin_revive_window_started)
	encounter.member_revived.connect(_on_twin_member_revived)
	add_child(encounter)
	var result := encounter.start_twins(SpitterBossDefinition, contexts, _make_boss_services())
	if result != OK:
		encounter.queue_free()
		push_error("Region 2 boss encounter failed to start: %s" % error_string(result))
		return result
	_boss_encounter = encounter
	ui.show_boss()
	return OK


func _spawn_region_three_boss() -> Error:
	return _start_single_boss_encounter(SummonerBossDefinition, _make_boss_context(_edge_point()))


func _endless_boss_definitions() -> Array[BossDefinition]:
	return [
		ChargeBossDefinition,
		SpitterBossDefinition,
		SummonerBossDefinition,
	]


func _start_endless_boss(definition: BossDefinition, reg: Dictionary) -> Error:
	if definition == null or not reg.has("boss_hp"):
		return ERR_INVALID_PARAMETER
	var next_rank := _endless_boss_n + 1
	var context := _make_boss_context(
		_edge_point(),
		BossEncounterContext.Mode.ENDLESS,
		next_rank,
		float(reg["boss_hp"])
	)
	var result := _start_single_boss_encounter(definition, context)
	if result == OK:
		_endless_boss_n = next_rank
	return result


func _spawn_endless_boss(reg: Dictionary) -> Error:
	var definitions := _endless_boss_definitions()
	return _start_endless_boss(definitions[randi() % definitions.size()], reg)


func _abort_boss_start(result: Error) -> void:
	is_boss_wave = false
	player.active = false
	state = "over"
	ui.hide_boss()
	ui.show_over("首领加载失败（%s）。\n%s" % [error_string(result), _ui_text("press_retry")])
	push_error("Boss wave aborted because encounter startup failed: %s" % error_string(result))
	if smoke:
		_smoke_finish("boss_start_fail")

func _on_encounter_boss_spawned(_boss: BossBase) -> void:
	_register_enemy_spawned()

func _on_encounter_primary_changed(boss: BossBase) -> void:
	boss_ref = boss

func _on_encounter_health_changed(current: float, maximum: float) -> void:
	ui.set_boss(current, maximum)


func _on_encounter_member_defeated(_boss: BossBase, _reward_coin: int, _reward_xp: int) -> void:
	enemies_alive = maxi(0, enemies_alive - 1)


func _on_twin_revive_window_started(duration: float) -> void:
	ui.flash_banner("双首领：%.0f 秒内击杀另一只！" % duration)


func _on_twin_member_revived() -> void:
	ui.flash_banner("吐弹首领复活了！")
	SFX.play("boss")


func _on_boss_encounter_completed(defeated_count: int, reward_coin: int, reward_xp: int) -> void:
	kills += defeated_count
	run_coins += reward_coin + defeated_count * player.magnet * 3
	ui.update_coins(run_coins)
	add_xp(reward_xp, false)
	boss_ref = null
	if _boss_encounter != null:
		_boss_encounter.queue_free()
		_boss_encounter = null
	_finish_boss_wave()


func _on_boss_encounter_aborted(reason: String) -> void:
	_fail_boss_encounter(reason)


func _fail_boss_encounter(reason: String, report_error := true) -> void:
	if _boss_encounter == null or state in ["over", "win"]:
		return
	var aborted_encounter := _boss_encounter
	_boss_encounter = null
	boss_ref = null
	is_boss_wave = false
	player.active = false
	state = "over"
	ui.hide_boss()
	ui.show_over("首领战异常中止（%s）。\n%s" % [reason, _ui_text("press_retry")])
	if report_error:
		push_error("Boss encounter aborted: %s" % reason)
	aborted_encounter.queue_free()
	_clear_boss_wave_nodes()
	if smoke:
		_smoke_finish("boss_abort")


func _clear_boss_wave_nodes() -> void:
	for group_name in ["enemies", "bullets"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(node):
				node.queue_free()
	enemies_alive = 0

func _spawn_bullet(pos: Vector2, dir: Vector2, dmg: float, pierce: int, bounce: int, from_player: Node2D) -> void:
	var b := BulletS.new()
	b.position = to_local(pos)
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
	b.position = to_local(pos)
	b.dir = dir
	b.speed = spd
	b.dmg = dmg
	b.player = player
	add_child(b)

func _card_pool() -> Array:
	var unlocked: Array = meta_d.get("cards", [])
	return Cards.all_cards().filter(func(c): return bool(c.get("m0", false)) or c["id"] in unlocked)

func _on_enemy_killed(coin_value: int, pos: Vector2, xp_value: int) -> void:
	EventBusS.emit_safe(&"enemy_killed", [pos, xp_value, coin_value])
	enemies_alive = maxi(0, enemies_alive - 1)
	kills += 1
	_digest = hash([_digest, Engine.get_physics_frames() - _frame0, pos.round(), coin_value, xp_value])
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

func add_xp(n: int, enter_draft_immediately := true) -> void:
	if n <= 0:
		return
	xp_accum += n
	while xp_accum >= _xp_needed():
		xp_accum -= _xp_needed()
		player_level += 1
		pending_picks += 1
	ui.update_xp(player_level, xp_accum, _xp_needed())
	if enter_draft_immediately and pending_picks > 0 and state == "wave":
		_enter_draft()  # 升级瞬间弹卡（冻结全场含玩家）

func _wave_time_up() -> void:
	# 普通波固定时长到点：清波奖励照发，残怪保留，直接进入下一波（升级选卡由经验驱动）
	run_coins += 2
	ui.update_coins(run_coins)
	_start_inter(0.5)

func _finish_boss_wave() -> void:
	# 首领战的单一推进出口；所有 Boss 共享相同的清场与区域流转。
	boss_ref = null
	ui.hide_boss()
	_clear_boss_wave_nodes()
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
	EventBusS.emit_safe(&"card_picked", [_offer[i]["id"], _offer[i]["kind"]])
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
	EventBusS.emit_safe(&"player_died")
	_finish("over")

func _finish(result: String) -> void:
	state = result
	var active_encounter := _boss_encounter
	_boss_encounter = null
	if active_encounter != null and is_instance_valid(active_encounter):
		active_encounter.abort("run_finished")
		active_encounter.queue_free()
	boss_ref = null
	ui.hide_boss()
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
		total_after = _bank_run_coins()
		var d := MetaS.load_data()
		if not d.get("tutorial_done", false):
			d["tutorial_done"] = true
		MetaS.save_data(d)
	if result == "win":
		ui.show_over("通关！击杀 %d · 本局 +%d 金币（累计 %d）\n%s\n%s" % [kills, run_coins, total_after, _next_unlock_hint(total_after), _ui_text("press_restart")])
		SFX.play("win")
	else:
		var where := ("无尽第 %d 波" % wave_i) if _endless else ("区域 %d 第 %d 波" % [region_i + 1, wave_i])
		ui.show_over("你在%s倒下了。击杀 %d\n战斗收益 %d + 进度保底 %d = 本局 +%d（累计 %d）\n%s\n%s" % [where, kills, run_coins - pity, pity, run_coins, total_after, _next_unlock_hint(total_after), _ui_text("press_restart")])
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
	var campaign_wave := 0
	for ri in regions.size():
		var reg: Dictionary = regions[ri]
		for w in range(1, int(reg["waves"]) + 1):
			campaign_wave += 1
			var n := _baseline_campaign_density(w, campaign_wave)
			var elites := ELITE_CHANCE * n if w >= 2 else 0.0
			total += (n - elites) + elites * 3.0 + 2.0
	return total

func _baseline_campaign_density(region_wave: int, campaign_wave: int) -> int:
	# 解析经济模型固定玩家等级为 1，但与实战共用基础下限、战役乘区、取整与硬上限。
	var base_mob_cap := clampi(4 + region_wave * 2, 8, 32)
	return SpawnCurveS.campaign_density(base_mob_cap, campaign_wave, _campaign_regular_wave_count())

func _death_pity() -> int:
	# 保底 = min(每波/首领补偿, 固定上限, 通关期望 90% - 已赚)：保证区域 2 起死局 ≥ 40% 通关期望，
	# 且死局永远不超通关的 90%（死亡刷币无激励）。不变量由 --sim 校验。
	var base := mini(PITY_PER_WAVE * _waves_cleared() + PITY_PER_BOSS * region_i, PITY_CAP)
	var cap := maxi(int(_expected_win_coins() * 0.9) - run_coins, 0)
	return mini(base, cap)

func _smoke_finish(result: String) -> void:
	if result == "win" and EnemyGrid.verify and EnemyGrid.mismatches > 0:
		result = "grid_mismatch"
	if soak:
		if result != "win":
			print("SOAK_FAIL cycle=%d/%d result=%s nodes=%d" % [_soak_done + 1, SOAK_CYCLES, result, get_tree().get_node_count()])
			_soak_done = 0
			get_tree().quit(1)
			return
		_soak_done += 1
		print("SOAK cycle=%d/%d result=%s nodes=%d %s" % [_soak_done, SOAK_CYCLES, result, get_tree().get_node_count(), _perf_summary()])
		if _soak_done >= SOAK_CYCLES:
			print("SOAK_OK")
			_soak_done = 0
			get_tree().quit(0)
			return
		get_tree().reload_current_scene()
		return
	print("PERF ", _perf_summary())
	var marker := "SMOKE_OK" if result == "win" else "SMOKE_FAIL"
	print("%s result=%s region=%d wave=%d kills=%d peak_enemies=%d spawn_mult=%.2f run_coins=%d buy_card=%s buy_level=%s buy_pick=%s wtest=%s meta_coins=%d t_ms=%d" % [marker,
		result, region_i, wave_i, kills, peak_enemies_alive, current_spawn_multiplier, run_coins,
		str(_smoke_buys["card"]), str(_smoke_buys["level"]), str(_smoke_buys["pick"]),
		str(_smoke_wtest_done), int(meta_d.get("coins", 0)), Time.get_ticks_msec() - _t0])
	get_tree().quit(0 if result == "win" else 1)

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
	var campaign_wave := 0
	for ri in regions.size():
		var reg: Dictionary = regions[ri]
		for w in range(1, int(reg["waves"]) + 1):
			campaign_wave += 1
			var n := _baseline_campaign_density(w, campaign_wave)
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
	get_tree().quit(0 if ok else 1)

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
