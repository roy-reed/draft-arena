extends SceneTree
# Android 导出配置守卫：包名、仅 arm64、横屏、ETC2/ASTC、仓库内不得出现任何 keystore 路径或口令。
# 期望值取自手游版决策（横屏 Android、包名 com.royreed.draftarena），不读取被测文件里的值作为期望。

const EXPECTED_PACKAGE := "com.royreed.draftarena"
const LANDSCAPE_ORIENTATIONS := [0, 2, 4]  # Godot: 0 landscape / 2 reverse landscape / 4 sensor landscape

var _failures := PackedStringArray()


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var cfg := ConfigFile.new()
	_expect(cfg.load("res://export_presets.cfg") == OK, "export_presets.cfg loads")
	var android := ""
	var windows := ""
	for section in cfg.get_sections():
		if not section.ends_with(".options") and section.begins_with("preset."):
			match str(cfg.get_value(section, "platform", "")):
				"Android": android = section
				"Windows Desktop": windows = section
	_expect(windows != "", "Windows preset still present")
	_expect(android != "", "Android preset present")
	if android != "":
		var opt := android + ".options"
		_expect(str(cfg.get_value(android, "name")) == "Android", "Android preset is named 'Android' (CI 按名称导出)")
		_expect(cfg.get_value(opt, "package/unique_name", "") == EXPECTED_PACKAGE, "package name is %s" % EXPECTED_PACKAGE)
		_expect(cfg.get_value(opt, "architectures/arm64-v8a", false) == true, "arm64-v8a enabled")
		for arch in ["armeabi-v7a", "x86", "x86_64"]:
			_expect(cfg.get_value(opt, "architectures/" + arch, false) == false, "%s disabled" % arch)
		_expect(cfg.get_value(opt, "gradle_build/use_gradle_build", true) == false, "no gradle build (预编译模板即可)")
		_expect(cfg.get_value(opt, "package/signed", false) == true, "APK is signed")
		for key in ["keystore/debug", "keystore/debug_user", "keystore/debug_password",
				"keystore/release", "keystore/release_user", "keystore/release_password"]:
			_expect(str(cfg.get_value(opt, key, "")) == "", "%s must stay empty (keystore 经环境变量/Secrets 传入)" % key)
		var code: int = cfg.get_value(opt, "version/code", 0)
		_expect(code >= 1, "version/code >= 1")
	_expect(ProjectSettings.get_setting("rendering/textures/vram_compression/import_etc2_astc", false) == true,
		"ETC2/ASTC import enabled (Android 导出必需)")
	_expect(int(ProjectSettings.get_setting("display/window/handheld/orientation", -1)) in LANDSCAPE_ORIENTATIONS,
		"handheld orientation is landscape")
	_expect(str(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile", "")) == "gl_compatibility",
		"mobile renderer is Compatibility")

	if _failures.is_empty():
		print("ANDROID_CONFIG_OK package=%s arch=arm64-v8a" % EXPECTED_PACKAGE)
		quit(0)
	else:
		for failure in _failures:
			push_error("ANDROID_CONFIG_FAIL: %s" % failure)
		quit(1)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
