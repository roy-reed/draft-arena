extends Node
# 快捷键钩子：PROCESS_MODE_ALWAYS，保证 get_tree().paused 时 ESC/R/Q/F11 仍可响应

var main: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	if main != null:
		main.hotkey(event)
