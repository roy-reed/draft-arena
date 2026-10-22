class_name WeaponLevel
extends Resource
## 武器某一等级的增量修饰（Lv2/Lv3/Lv4=进化）。
const StatModifierS := preload("res://scripts/core/stat_modifier.gd")
@export var level: int = 2
@export var modifiers: Array[StatModifierS] = []
