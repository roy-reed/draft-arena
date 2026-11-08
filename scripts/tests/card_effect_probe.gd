extends RefCounted
# 牌效果探针：在全新玩家上打出一张牌，返回脚本变量的变化（基础类型）。
# 迁移前用旧 lambda 生成快照（fixtures/card_effects.json），迁移后用 .tres 数据比对，保证行为逐值一致。

const PlayerS := preload("res://scripts/player.gd")

static func _snapshot(p: Object) -> Dictionary:
	var d := {}
	for prop in p.get_property_list():
		if not (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var v = p.get(prop["name"])
		if typeof(v) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT]:
			d[prop["name"]] = v
	return d

static func probe(tree_root: Node, card: Dictionary) -> Dictionary:
	var p := PlayerS.new()
	p.active = false
	tree_root.add_child(p)
	var w: String = card.get("weapon", "w_dragon")
	p.set_weapon(w)
	if card.get("kind", "") == "weapon":
		p.weapon_level = int(card["tier"]) - 1
	var before := _snapshot(p)
	card["apply"].call(p)
	var after := _snapshot(p)
	var diff := {}
	for k in after:
		if not before.has(k) or before[k] != after[k]:
			diff[k] = after[k]
	tree_root.remove_child(p)
	p.free()
	return diff
