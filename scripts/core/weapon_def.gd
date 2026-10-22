class_name WeaponDef
extends Resource
## 武器定义。content/weapons/*.tres。等级成长全部是数据（levels），player.upgrade_weapon 只做查表。
const WeaponLevelS := preload("res://scripts/core/weapon_level.gd")
@export var id: StringName
@export var display_name: String
@export var interval_mult: float = 1.0
## 机制标签：bullet / boomerang / arc / melee（被动 req 过滤用）
@export var mech_tag: StringName
@export var owner_char: StringName
@export var levels: Array[WeaponLevelS] = []

func level_def(lv: int) -> WeaponLevelS:
	for l in levels:
		if l.level == lv:
			return l
	return null
