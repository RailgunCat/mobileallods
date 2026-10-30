extends SceneTree
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const NAMES = ["Огненная стрела", "Лечение", "Молния", "Искра", "Замедление", "Мороз", "Вампиризм", "Метеор", "Миазмы", "Стена огня", "Огненный шар", "Окаменение", "Ускорение", "Благословение", "Каменная кожа"]

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var game = load("res://gameplay.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.battle.seed_value = 42
	game.preferences.update("music_enabled", false, false)
	game.preferences.update("sfx_enabled", false, false)
	game.preferences.update("crt_enabled", false, false)
	game._demo_battle(true)
	game.battle_overlay.acknowledge()
	var caster = game.battle.unit(1001)
	for school in Ids.MAGIC_SCHOOLS: caster.base_stats[school] = 9
	caster.base_stats[Ids.Stat.MAX_MANA] = 1000
	caster.recalculate(game.table)
	caster.stats[Ids.Stat.MANA] = caster.stats[Ids.Stat.MAX_MANA]
	game.view.set_process(false)
	game.view.camera_follow = false
	var prefix: String = "before" if "--before" in OS.get_cmdline_user_args() else "after"
	var failures: int = 0
	var animated: int = 0
	var gallery := Image.create(1280, 960, false, Image.FORMAT_RGBA8)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 20)
	label.position = Vector2(484, 212)
	game.add_child(label)
	for phase in ["cast", "impact"]:
		for spell in range(15):
			game.view.combat_feedback.clear()
			game.battle.hazards.clear()
			var friendly: bool = spell in [1, 6, 12, 13, 14]
			var recipient = game.battle.unit(1001 if friendly else 1004)
			var from: Vector2 = game.battle.unit(1001).position_pixels + Vector2(0, -12)
			var to: Vector2 = Vector2(recipient.cell) * 16 + Vector2(8, -4)
			var ticks: int = Ids.SPELL_EFFECT_TICKS.get(spell, 12)
			game.battle.current = {"action": "cast", "actor": 1001, "spell": spell, "cell": recipient.cell, "phase": "flight", "clock": int(ticks * 0.55), "flight_ticks": ticks, "flight_from": from, "flight_to": to}
			game.view.session_view_alpha = 0.5
			game.view.combat_feedback.clock = 0.42
			if phase == "impact":
				game.battle.current = {}
				if game.view.combat_feedback.has_method("add_spell"): game.view.combat_feedback.call("add_spell", spell, recipient.cell, 0.0)
				if spell == 7: game.view.combat_feedback.add_meteor(recipient.cell, 0.0)
				if spell in [8, 9]: game.battle.hazards.append({"spell": spell, "cell": recipient.cell, "actor": 1001, "duration": 3})
			label.text = "%02d  %s" % [spell + 1, NAMES[spell]]
			game.view._update_transform()
			game.view.pan += Vector2(640, 370) - game.view.cell_center(recipient.cell)
			game.view.queue_redraw()
			var state: Dictionary = game.battle.snapshot()
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var frame: Image = root.get_texture().get_image()
			gallery.blit_rect(frame, Rect2i(480, 200, 320, 240), Vector2i((spell % 4) * 320, int(spell / 4.0) * 240))
			if state != game.battle.snapshot():
				push_error("Drawing changed battle state")
				failures += 1
			if prefix == "after" and phase == "cast" and spell in [1, 3, 4, 6, 8, 9, 10, 11, 12, 14]:
				game.battle.current["clock"] += 2
				game.view.combat_feedback.clock += 0.124
				game.view.queue_redraw()
				var simulation: Dictionary = game.battle.snapshot()
				await process_frame
				await RenderingServer.frame_post_draw
				var next: Image = root.get_texture().get_image()
				if next.get_region(Rect2i(480, 200, 320, 240)).get_data() != frame.get_region(Rect2i(480, 200, 320, 240)).get_data(): animated += 1
				else: failures += 1; push_error("Spell %d did not animate" % spell)
				if simulation != game.battle.snapshot(): failures += 1; push_error("Animated drawing changed simulation")
		var path: String = "res://../build/spells-%s-%s.png" % [prefix, phase]
		var error: Error = gallery.save_png(path)
		print("Spell gallery: ", path, " ", error_string(error))
	if prefix == "after":
		label.hide()
		game.battle.current = {}
		game.battle.hazards.clear()
		game.view.combat_feedback.clear()
		game.battle.select(caster.instance_id)
		game._choose_action("magic", -1)
		for spell in [Ids.Spell.FIREBALL, Ids.Spell.LIGHTNING, Ids.Spell.FROST, Ids.Spell.MIASMA, Ids.Spell.FIRE_WALL]:
			game._choose_action("spell", spell)
			var cell: Vector2i = game.session.hero.cell + Vector2i.UP if spell == Ids.Spell.MIASMA else game.battle.unit(1004).cell
			game.action_bar.caption.text = game.action_bar.buttons[str(spell)].tooltip_text
			game.view._update_transform()
			game.view.pan += Vector2(640, 320) - game.view.cell_center(cell)
			var state: Dictionary = game.cursors.resolve(game, game.view.cell_center(cell), true)
			game.view.set_spell_preview(state)
			game.view.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var frame: Image = root.get_texture().get_image()
			frame.save_png("res://../build/aoe-%02d.png" % spell)
			print("AOE preview: ", spell, " ", game.view.spell_preview.get("cells", []).size(), " fixed / ", game.view.spell_preview.get("possible", []).size(), " possible cells")
	game.queue_free()
	await process_frame
	print("Spell visual QA: ", animated, " animated casts; ", failures, " failures")
	quit(1 if failures else 0)
