extends Resource
## 注：数组用 Array[Resource] 而非按脚本类型化，Godot 4.4.1 首次 --import 时按 preload 脚本类型化的导出数组会导致资源泄漏报错（CI 冷启动实测）。
## 一张构筑牌（武器升级卡或被动）。content/cards/*.tres。

const StatModifierS := preload("res://scripts/core/stat_modifier.gd")

@export var id: StringName
@export_enum("weapon", "passive") var kind: String = "passive"
@export var display_name: String
@export_multiline var desc: String
## 初始即在牌池；否则按 ContentLibrary.unlock_order 解锁
@export var m0: bool = false
## 武器升级卡专用
@export var owner_char: StringName
@export var weapon: StringName
@export var tier: int = 0
## 被动进池前置：当前武器机制标签需在此列表中（空 = 不限）
@export var req: PackedStringArray = PackedStringArray()
## 构筑标签（M2 共鸣用），见 docs/design/ARCH_V2.md 第 2 节
@export var tags: PackedStringArray = PackedStringArray()
@export var modifiers: Array[Resource] = []

func apply_to(target: Object) -> void:
	for m in modifiers:
		m.apply_to(target)

## 兼容旧牌字典接口（main/ui/player 仍按字典读取）
func to_dict() -> Dictionary:
	var d := {"id": String(id), "kind": kind, "name": display_name, "desc": desc, "m0": m0,
		"tags": tags, "def": self, "apply": apply_to}
	if kind == "weapon":
		d["owner"] = String(owner_char)
		d["weapon"] = String(weapon)
		d["tier"] = tier
	if not req.is_empty():
		d["req"] = Array(req)
	return d
