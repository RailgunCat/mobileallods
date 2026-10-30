extends SceneTree
func data(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))
func _initialize() -> void:
	var checks = preload("res://tests/gameplay_checks.gd").new()
	preload("res://tests/map_seven_checks.gd").new().run(checks, data("world.json"), data("legacy/gameplay.json"), data("tables/abilities.txt.json"), data("tables/rewards.txt.json"), data("campaign.json"))
	print("Map seven: ", checks.count, " checks, ", checks.failures, " failures")
	quit(1 if checks.failures else 0)
