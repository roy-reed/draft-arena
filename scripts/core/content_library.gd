class_name ContentLibrary
extends Resource
## 内容总表：唯一入口 content/library.tres。导出包内不依赖目录枚举。
const CardDefS := preload("res://scripts/core/card_def.gd")
const WeaponDefS := preload("res://scripts/core/weapon_def.gd")
const PATH := "res://content/library.tres"

@export var weapons: Array[WeaponDefS] = []
@export var cards: Array[CardDefS] = []
@export var unlock_order: PackedStringArray = PackedStringArray()

static var _cached: ContentLibrary = null

static func get_default() -> ContentLibrary:
	if _cached == null:
		_cached = load(PATH)
	return _cached

func weapon(id: StringName) -> WeaponDefS:
	for w in weapons:
		if w.id == id:
			return w
	return null
