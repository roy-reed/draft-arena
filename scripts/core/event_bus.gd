extends Node
## 全局事件总线（Autoload：EventBus）。规则层只发信号，表现层/统计订阅。
## 在 --script 单测里 Autoload 可能不存在，发信号一律走 EventBus.emit_safe（静态、空安全）。

signal card_picked(card_id: String, kind: String)
signal enemy_killed(pos: Vector2, xp: int, coins: int)
signal level_up(new_level: int)
signal player_died()

static func bus() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("EventBus")
	return null

static func emit_safe(sig: StringName, args: Array = []) -> void:
	var b := bus()
	if b != null:
		b.callv("emit_signal", [sig] + args)
