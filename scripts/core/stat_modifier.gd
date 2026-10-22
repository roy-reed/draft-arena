extends Resource
## 数据化的属性修饰：作用于目标对象（玩家）的一个脚本变量或一个方法。
## 新内容只组合这些原语，不写代码。

enum Op { ADD, SCALE, SET_TRUE, CALL, CALL_ARG }

@export var stat: StringName
@export var op: Op = Op.ADD
@export var value: float = 0.0

func apply_to(target: Object) -> void:
	match op:
		Op.ADD:
			var cur = target.get(stat)
			if typeof(cur) == TYPE_INT:
				target.set(stat, cur + int(value))
			else:
				target.set(stat, float(cur) + value)
		Op.SCALE:
			target.set(stat, float(target.get(stat)) * value)
		Op.SET_TRUE:
			target.set(stat, true)
		Op.CALL:
			target.call(stat)
		Op.CALL_ARG:
			target.call(stat, value)

## 供 lint 使用：目标上是否存在该属性/方法
func is_valid_for(target: Object) -> bool:
	if op == Op.CALL or op == Op.CALL_ARG:
		return target.has_method(stat)
	return stat in target
