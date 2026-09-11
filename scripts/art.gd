class_name ArtS
extends RefCounted
# 美术接缝：res://art/<name>.png 存在则返回纹理（像素过滤由项目默认 Nearest 保证），否则 null 退回灰盒多边形

static func skin(name: String) -> Texture2D:
	var path := "res://art/%s.png" % name
	if ResourceLoader.exists(path, "Texture2D"):
		return load(path)
	return null
