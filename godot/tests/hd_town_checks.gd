extends SceneTree
const Ids = preload("res://scripts/gameplay/game_ids.gd")
var checks
var game

func _initialize() -> void:
	call_deferred("_run")

func _frame() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func _capture(name: String) -> void:
	await _frame()
	root.get_texture().get_image().save_png("res://../build/hd-town-%s.png" % name)

func _click(panel: Control, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	# push_input receives window pixels; canvas_items stretch also adds letterbox
	# offsets. Exercise that real transform instead of sending viewport pixels.
	event.position = root.get_final_transform() * (panel.global_position + panel.origin + point * panel.ui_scale)
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await _frame()

func _run() -> void:
	checks = preload("res://tests/gameplay_checks.gd").new()
	game = load("res://gameplay.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.preferences.update("music_enabled", false, false)
	game.preferences.update("sfx_enabled", false, false)
	game.preferences.update("crt_enabled", false, false)
	game.preferences.update("hd_icons", true, false)
	game._restart(false)
	game.session.quests[Ids.Quest.CITY_CERTIFICATE] = Ids.QuestState.COMPLETED
	game.session.tutorial_seen[Ids.Tutorial.TOWN] = 1
	game.session.gold = 1000
	game._show_world(false)
	game.world_panel.show_town()
	game.world_panel.show_tavern()
	await _capture("tavern")
	var tavern = game.world_panel.hd_interior
	checks.check(tavern.visible and tavern.painting.get_size() == Vector2(1672, 940), "HD tavern loads generated art")
	checks.check(tavern.project_font == game.theme.default_font and tavern.project_frame.texture != null, "HD tavern uses project bitmap font and original stone frame")
	await _click(tavern, Vector2(250, 372))
	checks.check(game.world_panel.screen == &"body" and not game.world_panel.lines.is_empty(), "HD rumour click uses tavern rules")
	await _capture("rumour")
	game.world_panel._show_body("Длинный текст для проверки прокрутки. ".repeat(100))
	await _frame()
	game.world_panel.navigate(1)
	await _frame()
	checks.check(tavern.body_scroll == 1 and tavern.body_limit > 11, "keyboard scroll uses reflowed HD text")
	tavern._scroll_body(9999)
	checks.check(tavern.body_scroll == tavern.body_limit, "HD dialogue scroll clamps to final page")
	game.world_panel.back()
	await _frame()
	await _click(tavern, Vector2(250, 500))
	checks.check(game.world_panel.screen == &"body", "HD work action opens source quest dialogue")
	await _capture("work")
	game.world_panel.show_town(true)
	game._open_town_shop()
	await _capture("shop")
	var shop = game.shop.hd_interior
	checks.check(shop.visible and shop.painting.get_size() == Vector2(1672, 941), "HD shop loads generated art")
	checks.check(shop.project_font == game.theme.default_font and shop.project_frame.texture != null, "HD merchant uses the same project font and frame")
	await _click(shop, Vector2(250, 372))
	checks.check(game.shop.screen == &"items" and not game.shop.selling and game.shop.candidates.size() > 0, "HD buy choice opens actual stock")
	await _capture("stock")
	var count: int = game.session.inventory.size()
	await _click(shop, Vector2(160, 645))
	checks.check(game.shop.screen == &"confirm" and game.session.gold == 1000, "HD purchase requires original confirmation")
	await _capture("confirm")
	await _click(shop, Vector2(100, 240))
	checks.check(game.shop.screen == &"confirm" and game.shop.selected == 0, "confirmation blocks clicks on underlying stock")
	await _click(shop, Vector2(510, 455))
	checks.check(game.session.inventory.size() == count + 1 and game.session.gold == 851, "HD mouse purchase charges original 149 gold exactly once")
	game.shop.back()
	await _frame()
	await _click(shop, Vector2(250, 455))
	checks.check(game.shop.selling and game.shop.screen == &"items", "HD sell choice uses player inventory")
	var sale_price: int = shop._price(game.shop.candidates[game.shop.selected])
	count = game.session.inventory.size()
	await _click(shop, Vector2(160, 645))
	await _click(shop, Vector2(510, 455))
	checks.check(game.session.inventory.size() == count - 1 and game.session.gold == 851 + sale_price, "HD sale uses actual item and source half-price")
	game.preferences.update("hd_icons", false, false)
	await _capture("legacy")
	checks.check(not shop.visible and not shop.active(), "HD off restores original shop")
	var painting: Texture2D = shop.painting
	game.preferences.update("hd_icons", true, false)
	shop.painting = null
	await _frame()
	checks.check(not shop.active() and not shop.visible, "missing HD art falls back to original shop")
	shop.painting = painting
	for dimensions in [Vector2i(1000, 700), Vector2i(1600, 900), Vector2i(800, 1000)]:
		root.size = dimensions
		await _frame()
		game.shop.screen = &"choice"
		game.shop._refresh()
		await _frame()
		await _click(shop, Vector2(250, 372))
		checks.check(game.shop.screen == &"items" and not game.shop.selling, "HD click alignment at %s" % dimensions)
		if dimensions == Vector2i(1600, 900): await _capture("wide")
		if dimensions == Vector2i(800, 1000): await _capture("portrait")
	game.shop.back()
	game.shop.back()
	checks.check(game.world_panel.visible and game.world_panel.screen == &"town", "HD shop exit returns to source town")
	print("HD town: ", checks.count, " checks, ", checks.failures, " failures")
	var failures: int = checks.failures
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
