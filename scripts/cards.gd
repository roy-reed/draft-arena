extends RefCounted
# 牌池适配层（arch-v2 M1）：数据全部来自 content/library.tres（CardDef / WeaponDef .tres）。
# 对外仍提供旧字典接口 {id, kind, name, desc, m0, owner, weapon, tier, req, tags, apply}，main/ui/player 无需改动。
# 新增牌 = 新建 content/cards/<id>.tres 并登记到 content/library.tres；不写代码。牌表说明见 docs/GDD.md 第 5 节。

const LibraryS := preload("res://scripts/core/content_library.gd")

# 武器表：{id: {name, interval_mult}}；机制标签表：{id: tag}；解锁顺序（每张 30 币）
static var WEAPONS: Dictionary = _build_weapons()
static var WEAPON_TAGS: Dictionary = _build_weapon_tags()
static var UNLOCK_ORDER: Array = Array(LibraryS.get_default().unlock_order)

static var _cards_cache: Array = []

static func _build_weapons() -> Dictionary:
	var d := {}
	for w in LibraryS.get_default().weapons:
		d[String(w.id)] = {"name": w.display_name, "interval_mult": w.interval_mult}
	return d

static func _build_weapon_tags() -> Dictionary:
	var d := {}
	for w in LibraryS.get_default().weapons:
		d[String(w.id)] = String(w.mech_tag)
	return d

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
	if _cards_cache.is_empty():
		for def in LibraryS.get_default().cards:
			_cards_cache.append(def.to_dict())
	# 每次返回新数组 + 新字典，保持旧实现「调用方可随意修改返回值」的语义
	return _cards_cache.map(func(c): return c.duplicate())
