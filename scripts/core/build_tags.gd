extends RefCounted
## 标签只用于选牌分类展示；共鸣奖励与进化配方另行定稿。

const LABELS := {
	"bullet": "投射物", "boomerang": "回旋", "arc": "电弧", "melee": "近战",
	"crit": "暴击", "survival": "生存", "fury": "风险", "tempo": "节奏",
	"greed": "经济", "control": "控制", "blast": "爆炸",
}

static func card_labels(card: Dictionary) -> String:
	var labels := PackedStringArray()
	for tag in card.get("tags", []):
		var label: String = LABELS.get(String(tag), String(tag))
		if not labels.has(label):
			labels.append(label)
	return " / ".join(labels)

static func passive_counts(owned: Array, cards: Array) -> Dictionary:
	var by_id := {}
	for card in cards:
		if card.get("kind", "") == "passive":
			by_id[card["id"]] = card
	var counts := {}
	for id in owned:
		var unique := {}
		for tag in by_id.get(id, {}).get("tags", []):
			unique[String(tag)] = true
		for tag in unique:
			counts[tag] = int(counts.get(tag, 0)) + 1
	return counts

static func passive_summary(owned: Array, cards: Array) -> String:
	var counts := passive_counts(owned, cards)
	var parts := PackedStringArray()
	# 按标签表排序，选牌顺序不同也保持显示稳定。
	for tag in LABELS:
		if counts.has(tag):
			parts.append("%s×%d" % [LABELS[tag], counts[tag]])
	return "被动标签（按层）：" + ("、".join(parts) if not parts.is_empty() else "无")
