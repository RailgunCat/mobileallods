extends SceneTree

func data(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var checks = preload("res://tests/gameplay_checks.gd").new()
	preload("res://tests/map_five_checks.gd").new().run(checks, data("world.json"), data("legacy/gameplay.json"), data("tables/abilities.txt.json"), data("tables/rewards.txt.json"))
	print("Map five: ", checks.count, " checks, ", checks.failures, " failures")
	quit(1 if checks.failures else 0)
