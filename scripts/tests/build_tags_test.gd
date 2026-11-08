extends SceneTree

const TagsS := preload("res://scripts/core/build_tags.gd")
const CardsS := preload("res://scripts/cards.gd")
const PlayerS := preload("res://scripts/player.gd")
const UIS := preload("res://scripts/ui.gd")

var failures := PackedStringArray()

func _init() -> void:
	_run.call_deferred()

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _run() -> void:
	var cards := CardsS.all_cards()
	expect(TagsS.passive_summary([], cards) == "被动标签（按层）：无", "空构筑无标签")
	var owned := ["p_fang", "p_ammo_belt", "p_fang", "missing", "u_dragon_2"]
	expect(TagsS.passive_counts(owned, cards) == {"survival": 2, "tempo": 1}, "重复被动计层，未知牌和武器升级不计")
	expect(TagsS.passive_summary(owned, cards) == "被动标签（按层）：生存×2、节奏×1", "固定顺序中文展示")
	owned.reverse()
	expect(TagsS.passive_summary(owned, cards) == "被动标签（按层）：生存×2、节奏×1", "选取顺序不影响展示")
	var custom := [{"id": "test", "kind": "passive", "tags": PackedStringArray(["crit", "crit", "survival"])}]
	expect(TagsS.passive_counts(["test", "test"], custom) == {"crit": 2, "survival": 2}, "多标签每层分别计数，单卡去重")
	expect(TagsS.card_labels(custom[0]) == "暴击 / 生存", "卡片显示多标签")
	expect(TagsS.card_labels({}).is_empty(), "兼容无标签旧字典")
	var p := PlayerS.new()
	p.active = false
	root.add_child(p)
	p.owned_passives = ["p_fang", "p_fang", "p_ammo_belt"]
	var before := p.damage_mult
	var ui := UIS.new()
	root.add_child(ui)
	ui.update_stats(p.combat_summary())
	for label in [ui.stats_label, ui.draft_stats, ui.pause_stats]:
		expect(label.text.contains("被动标签（按层）：生存×2、节奏×1"), "三个属性入口均展示标签")
	ui.show_draft([CardsS.get_card("p_fang"), CardsS.get_card("p_ammo_belt"), CardsS.get_card("u_dragon_2")], func(_i): pass)
	expect(ui.draft_buttons[0].text.contains("[生存]"), "被动选项显示标签")
	expect(ui.draft_buttons[2].text.contains("[投射物]"), "武器选项显示标签")
	expect(p.damage_mult == before and p.owned_passives.size() == 3, "展示不改变属性或已选牌")
	ui.free()
	p.free()
	if failures.is_empty():
		print("BUILD_TAGS_OK")
		quit(0)
	else:
		for failure in failures:
			push_error("BUILD_TAGS_FAIL: " + failure)
		quit(1)
