extends SceneTree
const Ids = preload("res://scripts/gameplay/game_ids.gd")

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var game = load("res://gameplay.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.preferences.update("music_enabled", false, false)
	game.preferences.update("sfx_enabled", false, false)
	game.preferences.update("crt_enabled", false, false)
	game._demo_battle()
	game.battle_overlay.acknowledge()
	var enemy = game.battle.unit(1004)
	var cell: Vector2i = enemy.cell
	game.session.collision.remove(enemy.instance_id)
	enemy.configure({"instance_id": 1004, "unit_type": Ids.UnitKind.BAT, "story_group": Ids.StoryGroup.HOSTILES, "spawn_flag": enemy.spawn_flag, "side_id": Ids.Side.HOSTILE}, game.metadata, game.table)
	enemy.encounter_enabled = true
	enemy.move_to(cell)
	enemy.reset_interpolation()
	game.session.collision.occupy(enemy.instance_id, cell, enemy.footprint)
	game._select_battle_cell(cell)
	# The lower HUD shows the most recently hit creature during combat feedback.
	game.battle.feedback = {"target": enemy.instance_id, "tick": game.battle.tick_count}
	game.view.queue_redraw()
	for hd in [false, true]:
		game.preferences.update("hd_icons", hd, false)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../build/bat-portrait-%s.png" % ("hd" if hd else "legacy"))
		print("Bat HD=", hd, "; portrait=", game.view.actor_portrait_texture(enemy).resource_path)
	game.queue_free()
	await process_frame
	quit()
