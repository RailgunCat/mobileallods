extends SceneTree
const Ids = preload("res://scripts/gameplay/game_ids.gd")

func _initialize() -> void:
	call_deferred("_capture")

func save_frame(name: String) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png("res://../build/" + name + ".png")
	return image

func _capture() -> void:
	var game = load("res://gameplay.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.preferences.update("music_enabled", false, false)
	game.preferences.update("sfx_enabled", false, false)
	game.preferences.update("crt_enabled", false, false)
	game.preferences.update("hd_icons", true, false)
	game._demo_party()
	game._open_management(Ids.ManagementPage.CHARACTER)
	game.legacy_management.choose_actor(1)
	await save_frame("portrait-li-fixed")
	game._restart(false)
	game._show_main_menu(true)
	game.main_menu.selected = Ids.TitleChoice.CONTROLS
	game.main_menu.confirm()
	await save_frame("controls-title")
	game.main_menu.back()
	game.main_menu.selected = Ids.TitleChoice.CREDITS
	game.main_menu.confirm()
	await save_frame("credits-title")
	game._demo_battle(true)
	game.battle_overlay.acknowledge()
	game.battle.select(1001)
	game._refresh_battle()
	game.action_bar.buttons["magic"].pressed.emit()
	game.action_bar.buttons["0"].pressed.emit()
	game.view.set_process(false)
	var point: Vector2 = game.view.cell_center(game.battle.unit(1004).cell)
	var state: Dictionary = game.cursors.resolve(game, point, true)
	game.cursors.apply(state, game.ui_icons)
	# Hardware cursors are absent from viewport screenshots. Preview the same
	# native texture/hotspot with an input-transparent software copy for QA.
	var cursor_layer := CanvasLayer.new()
	cursor_layer.layer = 200
	game.add_child(cursor_layer)
	var cursor := TextureRect.new()
	cursor.texture = game.cursors.current_texture
	cursor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor.position = game.view.global_position + point - game.cursors.current_hotspot
	cursor_layer.add_child(cursor)
	await save_frame("cursor-spell")
	cursor.hide()
	var before: Image = await save_frame("crt-off")
	game.preferences.update("crt_enabled", true, false)
	var after: Image = await save_frame("crt-on")
	var different: bool = before.get_data() != after.get_data()
	print("CRT render differs: ", different, "; spell cursor: ", state)
	game.preferences.update("crt_enabled", false, false)
	game._show_game_menu()
	game.game_menu.selected = Ids.GameMenuChoice.SETTINGS
	game.game_menu.confirm()
	await save_frame("settings-crt")
	game.game_menu.back()
	game.game_menu.selected = Ids.GameMenuChoice.CREDITS
	game.game_menu.confirm()
	await save_frame("credits-game")
	game.queue_free()
	await process_frame
	quit(0 if different else 1)
