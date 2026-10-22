extends SceneTree
# arch-v2 M1：数据底座回归。
# 1) 39 张牌经 .tres 打出后，玩家属性变化与迁移前旧 lambda 的快照（fixtures/card_effects.json）逐值一致；
# 2) 内容 lint：id 唯一、修饰符目标存在、武器卡引用的武器与等级存在、标签合法、解锁表有效；
# 3) 「新增武器只需数据」：内存里新建一把 WeaponDef，不改代码即可被 upgrade_weapon 查表升级；
# 4) EventBus：emit_safe 在无 Autoload 时空安全，有总线时信号送达。

const CardsS := preload("res://scripts/cards.gd")
const Probe := preload("res://scripts/tests/card_effect_probe.gd")
const LibraryS := preload("res://scripts/core/content_library.gd")
const WeaponDefS := preload("res://scripts/core/weapon_def.gd")
const WeaponLevelS := preload("res://scripts/core/weapon_level.gd")
const StatModifierS := preload("res://scripts/core/stat_modifier.gd")
const EventBusS := preload("res://scripts/core/event_bus.gd")
const PlayerS := preload("res://scripts/player.gd")

const ALLOWED_TAGS := ["bullet", "boomerang", "arc", "melee", "crit", "survival", "fury", "tempo", "greed", "control", "blast"]

var failures := PackedStringArray()

func _init() -> void:
	_run.call_deferred()

func expect(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _run() -> void:
	_check_equivalence()
	_check_lint()
	_check_new_weapon_is_data_only()
	_check_event_bus()
	if failures.is_empty():
		print("CONTENT_DATA_OK")
		quit(0)
	else:
		for f in failures:
			push_error("CONTENT_DATA_FAIL: " + f)
		quit(1)

func _check_equivalence() -> void:
	var fx = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/tests/fixtures/card_effects.json"))
	expect(fx is Dictionary and fx.size() == 39, "fixture 应有 39 张牌")
	var cards := CardsS.all_cards()
	expect(cards.size() == fx.size(), "牌数 %d 与快照 %d 不一致" % [cards.size(), fx.size()])
	for c in cards:
		var id: String = c["id"]
		if not fx.has(id):
			failures.append("快照缺少 " + id)
			continue
		var got := Probe.probe(root, c)
		var want: Dictionary = fx[id]
		for k in want:
			expect(got.has(k) and is_equal_approx(float(got[k]), float(want[k])), "%s.%s 期望 %s 实得 %s" % [id, k, want[k], got.get(k)])
		for k in got:
			expect(want.has(k), "%s 多改了 %s" % [id, k])

func _check_lint() -> void:
	var lib := LibraryS.get_default()
	var p := PlayerS.new()
	var ids := {}
	for def in lib.cards:
		expect(not ids.has(def.id), "重复 id " + def.id)
		ids[def.id] = true
		expect(not def.display_name.is_empty() and not def.desc.is_empty(), "%s 缺名称或描述" % def.id)
		expect(not def.modifiers.is_empty(), "%s 无效果" % def.id)
		for m in def.modifiers:
			expect(m.is_valid_for(p), "%s 的修饰目标 %s 不存在" % [def.id, m.stat])
		for t in def.tags:
			expect(t in ALLOWED_TAGS, "%s 标签 %s 不在标签表" % [def.id, t])
		if def.kind == "weapon":
			var w = lib.weapon(def.weapon)
			expect(w != null, "%s 引用不存在的武器 %s" % [def.id, def.weapon])
			if w != null:
				expect(w.level_def(def.tier) != null, "%s 的武器 %s 缺 Lv%d 数据" % [def.id, def.weapon, def.tier])
				expect(w.owner_char == def.owner_char, "%s 归属与武器不一致" % def.id)
	for w in lib.weapons:
		for lv in w.levels:
			for m in lv.modifiers:
				expect(m.is_valid_for(p), "%s Lv%d 修饰目标 %s 不存在" % [w.id, lv.level, m.stat])
	for uid in lib.unlock_order:
		expect(ids.has(StringName(uid)), "解锁表引用不存在的牌 " + uid)
		var c := CardsS.get_card(uid)
		expect(not c.get("m0", false), "解锁表中的 %s 不应是初始牌" % uid)
	p.free()

func _check_new_weapon_is_data_only() -> void:
	var lib := LibraryS.get_default()
	var w := WeaponDefS.new()
	w.id = &"w_test_lance"
	w.display_name = "测试长枪"
	var lv := WeaponLevelS.new()
	lv.level = 2
	var m := StatModifierS.new()
	m.stat = &"damage_mult"
	m.value = 0.5
	lv.modifiers.append(m)
	w.levels.append(lv)
	lib.weapons.append(w)
	var p := PlayerS.new()
	p.active = false
	root.add_child(p)
	p.weapon_id = "w_test_lance"
	p.weapon_level = 1
	var before: float = p.damage_mult
	p.upgrade_weapon()
	expect(is_equal_approx(p.damage_mult, before + 0.5), "纯数据武器升级未生效")
	lib.weapons.erase(w)
	root.remove_child(p)
	p.free()

func _check_event_bus() -> void:
	if root.get_node_or_null("EventBus") == null:
		EventBusS.emit_safe(&"card_picked", ["x", "passive"])  # 无总线：不应报错
		var bus := EventBusS.new()
		bus.name = "EventBus"
		root.add_child(bus)
	var got := []
	root.get_node("EventBus").card_picked.connect(func(id, kind): got.append([id, kind]))
	EventBusS.emit_safe(&"card_picked", ["p_crit", "passive"])
	expect(got == [["p_crit", "passive"]], "EventBus 信号未送达：%s" % [got])
