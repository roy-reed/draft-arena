extends RefCounted
# 元进度持久化：user://meta.json（Windows 为 %APPDATA%/Godot/app_userdata/Draft Arena/）
# schema: {coins:int, cards:Array[String]已解锁牌id, char_level:Dictionary 角色id->0..5, start_pick:bool, volume:float 0..1, tutorial_done:bool}
# 缺字段给默认值，旧文件（只有 coins）也能正常读取

const PATH := "user://meta.json"
const CHAR_IDS := ["ranger", "brute", "gunner"]

static var persist := true  # smoke/soak 置 false：所有 save_data 静默丢弃，杜绝测试污染真实存档

static func default_data() -> Dictionary:
	return {"coins": 0, "cards": [], "char_level": {}, "start_pick": false, "volume": 0.8, "tutorial_done": false, "refines": 0, "forging": 0}

static func load_data() -> Dictionary:
	var d := default_data()
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return d
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return d
	d["coins"] = int(parsed.get("coins", 0))
	if parsed.get("cards") is Array:
		for c in parsed["cards"]:
			if c is String:
				d["cards"].append(c)
	if parsed.get("char_level") is Dictionary:
		for k in parsed["char_level"]:
			if k in CHAR_IDS:
				d["char_level"][k] = clampi(int(parsed["char_level"][k]), 0, 5)
	d["start_pick"] = bool(parsed.get("start_pick", false))
	d["volume"] = clampf(float(parsed.get("volume", 0.8)), 0.0, 1.0)
	d["tutorial_done"] = bool(parsed.get("tutorial_done", false))
	d["refines"] = maxi(int(parsed.get("refines", 0)), 0)
	d["forging"] = maxi(int(parsed.get("forging", 0)), 0)
	return d

static func char_level(d: Dictionary, id: String) -> int:
	return int(d.get("char_level", {}).get(id, 0))

static func save_data(d: Dictionary) -> void:
	if not persist:
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d, "  "))
