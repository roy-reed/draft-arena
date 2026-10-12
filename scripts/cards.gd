extends RefCounted
# 牌池：每张牌 = 字典 {id, kind, name, desc, m0, owner, apply}（武器升级卡另有 weapon/tier 字段）
# kind: "weapon" 当前武器的专属升级卡（玩家武器开局即定，永不换武器）；"passive" 可叠加被动
# owner: 升级卡的专属角色；选牌池只出「当前武器 && 下一等级」的升级卡
# m0: true 初始即在牌池；其余按 UNLOCK_ORDER 花金币解锁（仅被动）
# 武器线：每把武器 2 级强化（u2/u3），完整牌表见 docs/GDD.md 第 5 节

const WEAPONS := {
	"w_dragon": {"name": "龙狙", "interval_mult": 1.55},
	"w_shotgun": {"name": "散弹枪", "interval_mult": 1.25},
	"w_sniper": {"name": "狙击枪", "interval_mult": 1.7},
	"w_boomerang": {"name": "回旋镖", "interval_mult": 1.2},
	"w_arc": {"name": "电弧", "interval_mult": 1.4},
	"w_sawblade": {"name": "环刃", "interval_mult": 1.0},
}

# 武器机制标签：卡池纯净过滤用（被动 req 需包含当前武器标签才会进池）
const WEAPON_TAGS := {
	"w_dragon": "bullet",
	"w_sniper": "bullet",
	"w_shotgun": "bullet",
	"w_boomerang": "boomerang",
	"w_arc": "arc",
	"w_sawblade": "melee",
}

# 解锁线：锁定被动按此固定顺序花金币进牌池（每张 30）
const UNLOCK_ORDER := ["p_berserk", "p_giantslayer", "p_regen", "p_revenge", "p_swift", "p_lens", "p_armor", "p_golden", "p_grit", "p_burst", "p_glass"]

static func get_card(id: String) -> Dictionary:
	for c in all_cards():
		if c["id"] == id:
			return c
	return {}

static func unlock_cost(_id: String) -> int:
	return 30

static func m0_count() -> int:
	var n := 0
	for c in all_cards():
		if c.get("m0", false):
			n += 1
	return n

static func all_cards() -> Array:
	return [
		# ---- 武器升级卡（12 张，开局即可抽，只出当前武器的下一级） ----
		{"id": "u_dragon_2", "kind": "weapon", "owner": "ranger", "weapon": "w_dragon", "tier": 2, "name": "龙狙·穿龙", "desc": "穿透 +2。", "m0": true, "apply": func(p): p.upgrade_weapon()},
		{"id": "u_dragon_3", "kind": "weapon", "owner": "ranger", "weapon": "w_dragon", "tier": 3, "name": "龙狙·龙威", "desc": "伤害 +45%，对精英/首领 +15%。", "m0": true, "apply": func(p): p.upgrade_weapon()},
		{"id": "u_sniper_2", "kind": "weapon", "owner": "ranger", "weapon": "w_sniper", "tier": 2, "name": "狙击·穿甲弹", "desc": "穿透 +2。", "m0": true, "apply": func(p): p.upgrade_weapon()},
		{"id": "u_sniper_3", "kind": "weapon", "owner": "ranger", "weapon": "w_sniper", "tier": 3, "name": "狙击·逐灭", "desc": "伤害 +45%，对精英/首领额外 +15%。", "m0": true, "apply": func(p): p.upgrade_weapon()},
		{"id": "u_saw_2", "kind": "weapon", "owner": "brute", "weapon": "w_sawblade", "tier": 2, "name": "环刃·第二刃", "desc": "再生成一把绕体环刃。", "m0": true, "apply": func(p): p.upgrade_weapon()},
		{"id": "u_saw_3", "kind": "weapon", "owner": "brute", "weapon": "w_sawblade", "tier": 3, "name": "环刃·风暴", "desc": "转速 +45%，环刃伤害 +30%。", "m0": true, "apply": func(p): p.upgrade_weapon()},
		{"id": "u_boom_2", "kind": "weapon", "owner": "brute", "weapon": "w_boomerang", "tier": 2, "name": "回旋镖·配重铁", "desc": "伤害 +35%，镖体 +40%。", "m0": true, "apply": func(p): p.upgrade_weapon()},
		{"id": "u_boom_3", "kind": "weapon", "owner": "brute", "weapon": "w_boomerang", "tier": 3, "name": "回旋镖·分裂", "desc": "每次投掷出 2 把回旋镖。", "m0": true, "apply": func(p): p.upgrade_weapon()},
		{"id": "u_shotgun_2", "kind": "weapon", "owner": "gunner", "weapon": "w_shotgun", "tier": 2, "name": "散弹·扩容", "desc": "每次喷出 5 发（原 3 发）。", "m0": true, "apply": func(p): p.upgrade_weapon()},
		{"id": "u_shotgun_3", "kind": "weapon", "owner": "gunner", "weapon": "w_shotgun", "tier": 3, "name": "散弹·独头弹", "desc": "单发伤害 +80%。", "m0": true, "apply": func(p): p.upgrade_weapon()},
		{"id": "u_arc_2", "kind": "weapon", "owner": "gunner", "weapon": "w_arc", "tier": 2, "name": "电弧·导电体", "desc": "同时电击 3 个敌人（原 2 个）。", "m0": true, "apply": func(p): p.upgrade_weapon()},
		{"id": "u_arc_3", "kind": "weapon", "owner": "gunner", "weapon": "w_arc", "tier": 3, "name": "电弧·过载", "desc": "电弧伤害 +50%。", "m0": true, "apply": func(p): p.upgrade_weapon()},
		{"id": "u_dragon_4", "kind": "weapon", "owner": "ranger", "weapon": "w_dragon", "tier": 4, "name": "进化：龙狙·灭世", "desc": "伤害 +50%，穿透 +3，攻速 +20%。", "m0": true, "apply": func(p): p.upgrade_weapon()},
		{"id": "u_sniper_4", "kind": "weapon", "owner": "ranger", "weapon": "w_sniper", "tier": 4, "name": "进化：狙击·湮灭射线", "desc": "伤害 +50%，穿透 +3，对精英 +20%。", "m0": true, "apply": func(p): p.upgrade_weapon()},
		{"id": "u_saw_4", "kind": "weapon", "owner": "brute", "weapon": "w_sawblade", "tier": 4, "name": "进化：环刃·千刃风暴", "desc": "再 +2 把环刃，转速 +30%。", "m0": true, "apply": func(p): p.upgrade_weapon()},
		{"id": "u_boom_4", "kind": "weapon", "owner": "brute", "weapon": "w_boomerang", "tier": 4, "name": "进化：回旋镖·裂空", "desc": "每次 3 把，镖体 +60%，伤害 +30%。", "m0": true, "apply": func(p): p.upgrade_weapon()},
		{"id": "u_shotgun_4", "kind": "weapon", "owner": "gunner", "weapon": "w_shotgun", "tier": 4, "name": "进化：散弹·龙息", "desc": "一次 8 发，单发伤害 +40%。", "m0": true, "apply": func(p): p.upgrade_weapon()},
		{"id": "u_arc_4", "kind": "weapon", "owner": "gunner", "weapon": "w_arc", "tier": 4, "name": "进化：电弧·雷暴", "desc": "同时电击 4 个敌人，伤害 +50%。", "m0": true, "apply": func(p): p.upgrade_weapon()},
		# ---- 被动（m0 9 张 + 解锁 11 张 = 20 张） ----
		{"id": "p_whetstone", "kind": "passive", "name": "磨刀石", "desc": "伤害 +15%。", "m0": true, "apply": func(p): p.damage_mult += 0.15},
		{"id": "p_ammo_belt", "kind": "passive", "name": "弹药带", "desc": "攻速 +15%。", "m0": true, "apply": func(p): p.attack_speed_mult += 0.15},
		{"id": "p_anvil", "kind": "passive", "name": "铁砧", "desc": "最大生命 +15。", "m0": true, "apply": func(p): p.add_max_hp(15.0)},
		{"id": "p_sneakers", "kind": "passive", "name": "跑鞋", "desc": "移动速度 +12%。", "m0": true, "apply": func(p): p.speed *= 1.12},
		{"id": "p_thorns", "kind": "passive", "name": "荆棘", "desc": "受击时对来源反弹 3 点伤害。", "m0": true, "apply": func(p): p.thorns += 3.0},
		{"id": "p_fang", "kind": "passive", "name": "吸血獠牙", "desc": "击杀回复 2 点生命。", "m0": true, "apply": func(p): p.lifesteal += 2.0},
		{"id": "p_magnet", "kind": "passive", "name": "磁石", "desc": "每次清波额外 +1 金币。", "m0": true, "apply": func(p): p.magnet += 1},
		{"id": "p_frost", "kind": "passive", "name": "冰霜符文", "desc": "命中使敌人减速 25%，持续 1.2 秒。", "m0": true, "apply": func(p): p.slow_on_hit = true},
		{"id": "p_double", "kind": "passive", "name": "二连发", "desc": "攻击有 25% 概率追加一发。", "m0": true, "req": ["bullet", "boomerang", "arc"], "apply": func(p): p.double_chance += 0.25},
		{"id": "p_crit", "kind": "passive", "name": "致命一击", "desc": "15% 概率造成 2 倍伤害。", "m0": true, "apply": func(p): p.crit_chance += 0.15},
		{"id": "p_berserk", "kind": "passive", "name": "狂暴", "desc": "生命低于 30% 时攻速 +30%。", "apply": func(p): p.berserk = true},
		{"id": "p_giantslayer", "kind": "passive", "name": "巨人杀手", "desc": "对精英与首领伤害 +25%。", "apply": func(p): p.giant_slayer += 0.25},
		{"id": "p_regen", "kind": "passive", "name": "再生", "desc": "每秒回复 0.8 点生命。", "apply": func(p): p.regen += 0.8},
		{"id": "p_revenge", "kind": "passive", "name": "复仇", "desc": "每损失 10% 最大生命，伤害 +4%。", "apply": func(p): p.revenge = true},
		{"id": "p_swift", "kind": "passive", "name": "疾风", "desc": "击杀后 1.5 秒内移速 +25%。", "apply": func(p): p.swift = true},
		{"id": "p_lens", "kind": "passive", "name": "弹射透镜", "desc": "子弹命中后向最近敌人弹射 1 次。", "req": ["bullet"], "apply": func(p): p.bounce += 1},
		{"id": "p_armor", "kind": "passive", "name": "板甲", "desc": "每次受到的伤害 -2（至少 1）。", "apply": func(p): p.armor += 2.0},
		{"id": "p_golden", "kind": "passive", "name": "黄金子弹", "desc": "击杀有 20% 概率额外掉 1 金币。", "apply": func(p): p.gold_chance += 0.2},
		{"id": "p_grit", "kind": "passive", "name": "背水", "desc": "生命低于 50% 时伤害 +20%。", "apply": func(p): p.grit = true},
		{"id": "p_burst", "kind": "passive", "name": "爆裂弹", "desc": "击杀时对周围敌人造成 12 点爆炸伤害。", "apply": func(p): p.burst = true},
		{"id": "p_glass", "kind": "passive", "name": "玻璃大炮", "desc": "伤害 +40%，最大生命 -20。", "apply": func(p): p.glass_cannon()},
	]
