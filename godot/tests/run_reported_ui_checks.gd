extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = load("res://gameplay.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.preferences.update("music_enabled", false, false)
	game.preferences.update("sfx_enabled", false, false)
	var checks = preload("res://tests/gameplay_checks.gd").new()
	preload("res://tests/reported_ui_checks.gd").new().run(game, checks)
	print("Reported UI: ", checks.count, " checks, ", checks.failures, " failures")
	var failures: int = checks.failures
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
