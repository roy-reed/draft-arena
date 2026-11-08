extends Resource
## 内容总表：唯一入口 content/library.tres。导出包内不依赖目录枚举。
const CardDefS := preload("res://scripts/core/card_def.gd")
const WeaponDefS := preload("res://scripts/core/weapon_def.gd")
const PATH := "res://content/library.tres"

@export var weapons: Array[Resource] = []
@export var cards: Array[Resource] = []
@export var unlock_order: PackedStringArray = PackedStringArray()

static var _cached: Resource = null

static func get_default() -> Resource:
	if _cached == null:
		_cached = load(PATH)
	return _cached

func weapon(id: StringName) -> Resource:
	for w in weapons:
		if w.id == id:
			return w
	return null
