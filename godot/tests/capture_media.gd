extends SceneTree
func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var scene = load("res://gameplay.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.preferences.update("music_enabled", false, false)
	scene.preferences.update("sfx_enabled", false, false)
	scene._demo_battle(true)
	scene.battle_overlay.acknowledge()
	scene.battle.select(1001)
	scene._choose_action("magic", -1)
	for hd: bool in [false, true]:
		scene.preferences.update("hd_icons", hd, false)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../build/media-%s.png" % ("hd" if hd else "legacy"))
	scene._show_game_menu()
	scene.game_menu.selected = 6
	scene.game_menu.confirm()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../build/media-settings.png")
	scene.game_menu.back()
	scene.game_menu.back()
	scene._restart(false)
	scene._show_main_menu(true)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../build/media-title.png")
	scene.main_menu.navigate(-1)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../build/media-title-settings.png")
	print("Media previews captured")
	scene.queue_free()
	await process_frame
	quit()
