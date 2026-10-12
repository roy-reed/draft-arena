extends RefCounted
class_name EnemyGrid
# 手游版 M3：子弹 ↔ 敌人命中检测用的均匀空间网格（静态、全局唯一）。
#
# 等价性约定（与原 bullet._check_hit 逐帧逐子步一致）：
# - 原实现按 get_nodes_in_group("enemies") 的顺序（即场景树顺序）找第一个满足
#   distance(pos, e.position) <= e.radius + 4 且不在 hit_list 中的敌人。
# - 这里只检查覆盖 pos ± (max_radius + 4) 的格子。敌人每次自己移动后立即调用 EnemyGrid.moved
#   （enemy.gd / charge_boss.gd / spitter_boss.gd 的全部位置写入点），出入场景树时登记/注销，
#   与组成员资格同步。Godot 4.4 的 TRANSFORM_CHANGED 是延迟到帧末统一下发的，只作为兜底：
#   其它代码若在树内直接改敌人 position，须同帧调用 EnemyGrid.moved(e)，否则要到下一帧才换格。
#   命中多个时按场景树顺序取最前者，因此结果与线性扫描完全相同。
# - verify=true 时每次查询同时跑原线性扫描并统计不一致次数（smoke/soak 用 --grid-verify 打开）。
# - enabled=false（--legacy-collision）退回原线性扫描，用于 A/B 对比。

const CELL := 64.0
const HIT_PAD := 4.0  # 与原实现的 e.radius + 4.0 一致

static var enabled := true
static var verify := false
static var checks := 0          # 实际做了距离判定的次数（性能统计）
static var queries := 0
static var mismatches := 0
static var max_radius := 0.0
static var _cells := {}          # Vector2i -> Array[Node2D]
static var _cell_of := {}        # instance_id -> Vector2i


static func reset_stats() -> void:
	checks = 0
	queries = 0
	mismatches = 0


static func clear() -> void:
	_cells.clear()
	_cell_of.clear()
	max_radius = 0.0


static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


static func tracked_count() -> int:
	return _cell_of.size()


static func track(e: Node2D) -> void:
	var id := e.get_instance_id()
	if _cell_of.has(id):
		moved(e)
		return
	var c := cell_of(e.position)
	_cell_of[id] = c
	if not _cells.has(c):
		_cells[c] = []
	_cells[c].append(e)
	max_radius = maxf(max_radius, float(e.get("radius")))


static func untrack(e: Node2D) -> void:
	var id := e.get_instance_id()
	if not _cell_of.has(id):
		return
	var c: Vector2i = _cell_of[id]
	_cell_of.erase(id)
	var arr: Array = _cells.get(c, [])
	arr.erase(e)
	if arr.is_empty():
		_cells.erase(c)
	if _cell_of.is_empty():
		max_radius = 0.0  # 场上清空（如波次间、首领死后）时收回查询半径


static func moved(e: Node2D) -> void:
	var id := e.get_instance_id()
	if not _cell_of.has(id):
		return
	max_radius = maxf(max_radius, float(e.get("radius")))
	var c := cell_of(e.position)
	var old: Vector2i = _cell_of[id]
	if c == old:
		return
	var arr: Array = _cells.get(old, [])
	arr.erase(e)
	if arr.is_empty():
		_cells.erase(old)
	_cell_of[id] = c
	if not _cells.has(c):
		_cells[c] = []
	_cells[c].append(e)


# 返回本子步命中的敌人（没有则 null）。
static func first_hit(tree: SceneTree, pos: Vector2, exclude: Array) -> Node2D:
	queries += 1
	if not enabled:
		return _linear_first_hit(tree, pos, exclude, true)
	var best: Node2D = null
	var reach := max_radius + HIT_PAD
	var lo := cell_of(pos - Vector2(reach, reach))
	var hi := cell_of(pos + Vector2(reach, reach))
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var arr = _cells.get(Vector2i(cx, cy))
			if arr == null:
				continue
			for e in arr:
				if not is_instance_valid(e) or e in exclude:
					continue
				checks += 1
				if pos.distance_to(e.position) <= e.radius + HIT_PAD:
					if best == null or best.is_greater_than(e):
						best = e
	if verify:
		var legacy := _linear_first_hit(tree, pos, exclude, false)
		if legacy != best:
			mismatches += 1
			if mismatches <= 5:
				push_warning("GRID_MISMATCH pos=%s grid=%s linear=%s" % [pos, best, legacy])
	return best


# 原实现（逐个遍历 enemies 组）。count=true 时计入性能统计。
static func _linear_first_hit(tree: SceneTree, pos: Vector2, exclude: Array, count: bool) -> Node2D:
	for e in tree.get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e in exclude:
			continue
		if count:
			checks += 1
		if pos.distance_to(e.position) <= e.radius + HIT_PAD:
			return e
	return null
