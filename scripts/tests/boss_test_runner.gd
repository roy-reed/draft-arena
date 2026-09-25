extends RefCounted

const CASES := [
	{"script": "res://scripts/tests/boss_foundation_test.gd", "marker": "BOSS_FOUNDATION_OK"},
	{"script": "res://scripts/tests/charge_boss_test.gd", "marker": "CHARGE_BOSS_OK"},
	{"script": "res://scripts/tests/boss_encounter_test.gd", "marker": "BOSS_ENCOUNTER_OK"},
	{"script": "res://scripts/tests/twin_boss_encounter_test.gd", "marker": "TWIN_BOSS_ENCOUNTER_OK"},
	{"script": "res://scripts/tests/summoner_boss_test.gd", "marker": "SUMMONER_BOSS_OK"},
	{"script": "res://scripts/tests/endless_boss_encounter_test.gd", "marker": "ENDLESS_BOSS_OK"},
	{"script": "res://scripts/tests/main_boss_integration_test.gd", "marker": "MAIN_BOSS_INTEGRATION_OK"},
]


static func run() -> int:
	var executable := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")
	for case_data: Dictionary in CASES:
		var output: Array = []
		var args := PackedStringArray([
			"--headless",
			"--path",
			project_path,
			"--script",
			str(case_data["script"]),
		])
		var exit_code := OS.execute(executable, args, output, true)
		var combined := ""
		for chunk in output:
			var chunk_text := str(chunk)
			combined += chunk_text
			print(chunk_text.trim_suffix("\n"))
		var marker := str(case_data["marker"])
		if exit_code != 0 or not combined.contains(marker):
			push_error("Boss test failed: %s (exit=%d marker=%s)" % [
				case_data["script"],
				exit_code,
				marker,
			])
			return 1
	print("BOSS_TEST_OK")
	return 0
