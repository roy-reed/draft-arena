extends RefCounted
class_name ScreenLayout
# 手游版 M2：非 16:9 屏幕与安全区的纯计算（无副作用，便于测试）。
# 移动端把根窗口 stretch aspect 改为 expand：视口按屏幕比例扩展，竞技场（1280×720 设计坐标）
# 通过 canvas_transform 平移到可见区域正中；HUD 用锚点贴边并按安全区内缩。
# 桌面端不调用这些逻辑，保持 keep（16:9 黑边）原行为。

const BASE_SIZE := Vector2(1280, 720)
const BG_COLOR := Color(0.07, 0.07, 0.1)  # 与 main._draw 的底色一致，填充扩展区域


# 世界层平移量：让 BASE_SIZE 的设计画面在可见区域居中（只会向右/下平移，不缩放）。
static func world_offset(visible_size: Vector2, base := BASE_SIZE) -> Vector2:
	return ((visible_size - base) * 0.5).max(Vector2.ZERO).round()


# 把屏幕像素下的安全区换算为视口像素的四边边距 (left, top, right, bottom)。
static func safe_margins(window_size: Vector2, safe: Rect2, viewport_size: Vector2) -> Vector4:
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return Vector4.ZERO
	var k := viewport_size / window_size
	var left := safe.position.x * k.x
	var top := safe.position.y * k.y
	var right := (window_size.x - safe.end.x) * k.x
	var bottom := (window_size.y - safe.end.y) * k.y
	return Vector4(maxf(left, 0.0), maxf(top, 0.0), maxf(right, 0.0), maxf(bottom, 0.0)).round()
