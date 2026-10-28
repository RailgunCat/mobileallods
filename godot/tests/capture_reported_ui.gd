extends SceneTree
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Reports = preload("res://tests/reported_ui_checks.gd")

func _initialize() -> void:
	call_deferred("_capture")

func save_frame(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../build/" + name + ".png")

func _capture() -> void:
	root.size = Vector2i(960, 1280)
	var game = load("res://gameplay.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.preferences.update("music_enabled", false, false)
	game.preferences.update("sfx_enabled", false, false)
	game.preferences.update("crt_enabled", false, false)
	var reports := Reports.new()
	reports.town_fixture(game)
	game.session.gold = 10000
	game._open_town_shop()
	game.shop.confirm()
	game.shop.selected = 11
	game.shop.confirm()
	await save_frame("shop-confirm-fixed")
	reports.click(game.shop, Vector2(160, 260))
	print("Shop Back returns to items: ", game.shop.screen == &"items")
	game.shop.confirm()
	var before: int = game.session.gold
	reports.click(game.shop, Vector2(80, 260))
	print("Shop Yes buys: ", game.shop.screen == &"items" and game.session.gold < before)
	await save_frame("shop-purchased-fixed")
	reports.town_fixture(game)
	game.world_panel.show_tavern()
	game.world_panel.town_selected = 1
	game.world_panel.confirm()
	await save_frame("tavern-work")
	reports.click(game.world_panel, Vector2(50, 305))
	print("Work returns to tavern choices: ", game.world_panel.screen == &"tavern")
	await save_frame("tavern-work-return")
	game._restart(false)
	game.session.quests.fill(Ids.QuestState.NOT_STARTED)
	for index in range(4):
		game.session.quests[int(game.campaign_data["quests"][index]["id"])] = [Ids.QuestState.COMPLETED, Ids.QuestState.ACTIVE, Ids.QuestState.COMPLETED, Ids.QuestState.FAILED][index]
	game._open_management(Ids.ManagementPage.JOURNAL)
	await save_frame("journal-completed-last")
	game.queue_free()
	await process_frame
	quit()
