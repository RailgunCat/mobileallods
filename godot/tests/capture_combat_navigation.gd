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
	game.preferences.update("hd_icons", false, false)
	game._demo_battle(true)
	game.battle_overlay.acknowledge()
	game.view.set_process(false)
	game.battle.hazards.append({"spell": Ids.Spell.FIRE_WALL, "actor": 1001, "cell": Vector2i(22, 18), "duration": 4})
	var simulation: Dictionary = game.battle.snapshot()
	game.view.combat_feedback.clock = 0.0
	game.view.queue_redraw()
	var first: Image = await save_frame("firewall-animated-a")
	game.view.combat_feedback.clock = 0.248
	game.view.queue_redraw()
	var second: Image = await save_frame("firewall-animated-b")
	var animated: bool = first.get_data() != second.get_data()
	var unchanged: bool = simulation == game.battle.snapshot()
	print("Firewall rendered animation: ", animated, "; simulation unchanged: ", unchanged)
	game.battle.hazards.clear()
	game._choose_action("move", -1)
	var target: Vector2i = game.session.hero.cell + Vector2i.LEFT * 2
	var state: Dictionary = game.cursors.resolve(game, game.view.cell_center(target), true)
	game.view.set_movement_preview(state)
	await save_frame("movement-green-dots")
	print("Normal movement route dots: ", game.view.movement_preview)
	game.saves.directory = ProjectSettings.globalize_path("res://../build/map-four-capture-saves").simplify_path()
	game._restart(false)
	game.session.quests[Ids.Quest.HERMIT_SEARCH] = Ids.QuestState.ACTIVE
	game._travel(3, 0)
	preload("res://tests/map_four_checks.gd").new().approach(game.session)
	game.campaign.check_triggers()
	game.campaign.advance(0.062)
	await save_frame("map-four-hermit-dialogue")
	print("Map four dialogue: ", game.campaign.modal.get("id", -1))
	game.queue_free()
	await process_frame
	quit(0 if animated and unchanged else 1)
