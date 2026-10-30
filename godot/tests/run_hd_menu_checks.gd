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
	game.preferences.update("crt_enabled", false, false)
	var checks = preload("res://tests/gameplay_checks.gd").new()
	var suite = preload("res://tests/hd_menu_checks.gd").new()
	suite.captures = "--capture" in OS.get_cmdline_user_args()
	await suite.run(game, checks)
	print("HD menu: ", checks.count, " checks, ", checks.failures, " failures")
	var failures: int = checks.failures
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
