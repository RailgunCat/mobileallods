extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Feedback = preload("res://scripts/gameplay/combat_feedback.gd")
const Rain = preload("res://scripts/gameplay/rain_presentation.gd")
const Music = preload("res://scripts/gameplay/music_player.gd")
const Rules = preload("res://scripts/gameplay/combat_rules.gd")
const SpellVisuals = preload("res://scripts/gameplay/spell_presentation.gd")

func run(root, checks) -> void:
	_enemy_hover(root, checks)
	var stone_start: Vector2 = SpellVisuals.meteor_position(Vector2i(10, 20), 0)
	var stone_mid: Vector2 = SpellVisuals.meteor_position(Vector2i(10, 20), 6)
	var stone_end: Vector2 = SpellVisuals.meteor_position(Vector2i(10, 20), 12)
	checks.check(stone_start.x == stone_end.x and stone_mid.y - stone_start.y < stone_end.y - stone_mid.y, "Meteor falls vertically and accelerates over equal time intervals")
	var shard_reference := PackedVector2Array()
	var fire_reference: Array[Dictionary] = []
	for fps in [30, 60, 144]:
		var debris := Feedback.new()
		debris.add_meteor(Vector2i(10, 20), 0)
		for frame in range(int(fps / 2.0)): debris.advance(1.0 / fps)
		var shards: PackedVector2Array = debris.meteor_shards()
		var sparks: Array[Dictionary] = SpellVisuals.fire_sparks(Vector2(100, 100), Vector2(200, 100), debris.clock / 0.062, 12)
		checks.check(shards.size() == 10 and not sparks.is_empty(), "Meteor debris and fire sparks remain visible at %d FPS" % fps)
		if fps == 30:
			shard_reference = shards
			fire_reference = sparks
		else: checks.check(shards == shard_reference and sparks == fire_reference, "spell particle positions agree across FPS")
		debris.advance(2)
		checks.check(debris.meteor_shards().is_empty() and debris.meteor_impacts.is_empty(), "Meteor debris expires after settling")
		debris.add_meteor(Vector2i.ZERO, debris.clock)
		debris.clear()
		checks.check(debris.meteor_shards().is_empty(), "reset and load clear old Meteor particles")
	for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2(1, -1), Vector2(1, 1)]:
		checks.check(SpellVisuals.projectile_frame(direction) == [Vector2.RIGHT, Vector2.DOWN, Vector2(1, -1), Vector2(1, 1)].find(direction), "projectile uses its original horizontal, vertical and two diagonal atlas frames")
	checks.check(root.theme.default_font is FontFile and root.theme.default_font.has_char("А".unicode_at(0)), "native menus use original Cyrillic bitmap glyphs")
	checks.check(root.management.panel.get_theme_stylebox("panel") is StyleBoxTexture, "large management panels inherit the source stone frame")
	var expected: Array = []
	for fps in [30, 60, 144]:
		var feedback := Feedback.new()
		feedback.add_text(Vector2(100, 100), "-5 х2")
		for frame in range(int(fps / 2.0)): feedback.advance(1.0 / fps)
		feedback.add_text(Vector2(100, 100), "-7")
		for frame in range(int(fps / 2.0)): feedback.advance(1.0 / fps)
		var records: Array = feedback.records()
		checks.check(records.size() == 2 and records[0]["point"].y < records[1]["point"].y and records[0]["text"] == "-5 х2", "independent floating hits rise and coexist at %d FPS" % fps)
		if expected.is_empty(): expected = records
		else: checks.check(records == expected, "floating text positions agree across FPS")
		feedback.advance(0.24)
		checks.check(feedback.records().size() == 1, "first hit expires after twenty source ticks")
		feedback.advance(0.5)
		checks.check(feedback.records().is_empty(), "second hit expires independently")
	root._demo_battle()
	root.battle_overlay.acknowledge()
	checks.check(root.view.zone_image(root.session.hero.cell) == -1, "no movement overlay before choosing an action")
	root._choose_action("move", -1)
	var green: int = 0
	var red: int = 0
	for y in range(root.battle.arena.position.y, root.battle.arena.end.y):
		for x in range(root.battle.arena.position.x, root.battle.arena.end.x):
			var image: int = root.view.zone_image(Vector2i(x, y))
			if image == 202: green += 1
			if image == 203: red += 1
	checks.check(green > 0 and red > 0, "move action uses original green interior and red last-AP cells")
	root.battle.select(root.session.party[1].instance_id)
	root._choose_action("attack", -1)
	checks.check(root.view.zone_action == &"ranged", "archer uses a separate range overlay")
	var ranged_red: bool = false
	for y in range(root.battle.arena.position.y, root.battle.arena.end.y):
		for x in range(root.battle.arena.position.x, root.battle.arena.end.x):
			if root.view.zone_image(Vector2i(x, y)) == 203: ranged_red = true
	checks.check(not ranged_red, "ranged overlay does not borrow the red movement boundary")
	checks.check(root.debug_panel.is_ancestor_of(root.god_toggle) and not root.debug_panel.visible and not root.session.god_mode, "God mode starts off inside collapsed debug controls")
	root.god_toggle.button_pressed = true
	var enemy = root.battle.unit(1004)
	var hero = root.session.hero
	var payload := PackedInt32Array()
	payload.resize(57)
	payload[Ids.Stat.PHYSICAL_DAMAGE] = 1000
	var hp: int = hero.stats[Ids.Stat.HP]
	root.battle.apply_payload(enemy, hero, payload)
	checks.check(root.session.god_mode and hero.stats[Ids.Stat.HP] == hp and not hero.dead, "debug God mode prevents a lethal incoming hit")
	root.god_toggle.button_pressed = false
	root.battle.apply_payload(enemy, hero, payload)
	checks.check(hero.stats[Ids.Stat.HP] < hp, "turning God mode off restores ordinary damage")
	root._demo_battle(true)
	root.battle_overlay.acknowledge()
	root.god_toggle.button_pressed = true
	var caster = root.battle.unit(1001)
	caster.stats[Ids.Stat.MANA] = 0
	var cast: Dictionary = root.battle.cast_plan(caster, Ids.Spell.FIRE_ARROW, root.battle.unit(1004).cell)
	checks.check(int(cast["cost"]) == 0 and cast["valid"], "God mode allows a learned spell without mana")
	checks.check(root.debug_map_picker.item_count == 24 and int(root.debug_map_picker.get_item_metadata(23)) == -12, "debug travel includes all twelve dungeons and final chamber")
	root._restart(false)
	checks.check(not root.session.god_mode and not root.god_toggle.button_pressed, "new game clears debug God mode")
	root.session.start_rain(180, 1)
	var rng: Dictionary = root.session.world_rng.snapshot()
	root.session.advance_weather(1.0)
	var drops: Array = Rain.samples(Rect2(0, 0, 320, 384), root.session.rain_elapsed, 1)
	checks.check(not drops.is_empty() and root.session.world_rng.snapshot() == rng and root.session.rain_remaining == 179, "rain advances independently without using gameplay RNG")
	var reference: Array = []
	for fps in [30, 60, 144]:
		var elapsed: float = 0
		for frame in range(fps): elapsed += 1.0 / fps
		var samples: Array = Rain.samples(Rect2(0, 0, 320, 384), elapsed, 1)
		if reference.is_empty(): reference = samples
		else: checks.check(samples == reference, "rain positions agree at %d FPS" % fps)
	root.campaign.enabled = true
	var state: Dictionary = root.saves.capture(root.session, root.campaign, root.exploration)
	var restored: Dictionary = root.saves.restore(state, root.world, root.metadata, root.table, root.rewards)
	checks.check(not restored.is_empty() and restored["session"].rain_remaining == 179 and restored["session"].rain_elapsed == 1, "save restores active rain and its clock")
	root.session.quests[Ids.Quest.CITY_CERTIFICATE] = Ids.QuestState.COMPLETED
	root.session.tutorial_seen[Ids.Tutorial.TOWN] = 0
	root._show_world(false)
	root.world_panel.show_town()
	checks.check(root.world_panel.screen == &"town_help" and int(root.session.tutorial_seen[15]) == 1, "first city visit shows recovered town tutorial once")
	root.world_panel.back()
	checks.check(root.world_panel.screen == &"town", "town tutorial returns to actual town menu")
	root.world_panel.show_town()
	checks.check(root.world_panel.screen == &"town", "town tutorial is not repeated")
	root._restart(false)
	var old_path: String = root.music.settings_path
	var old_enabled: bool = root.music.enabled
	root.music.settings_path = "user://music-check-%d.cfg" % Time.get_ticks_usec()
	checks.check(root.music.available and root.music.streams.size() == 2 and root.music.streams[0].get_length() > 90 and root.music.streams[1].get_length() > 20, "both original MIDI renders decode as native audio")
	root.music.set_enabled(true, false)
	root.music.play_track(1)
	checks.check(root.music.player.playing and root.music.player.stream.loop, "gameplay music starts and loops")
	root._show_game_menu()
	root.game_menu.selected = Ids.GameMenuChoice.SETTINGS
	root.game_menu.confirm()
	checks.check(root.game_menu.settings_open, "Settings opens the real music toggle")
	root.game_menu.confirm()
	checks.check(not root.music.enabled and not root.music.player.playing, "settings toggle stops music")
	var config := ConfigFile.new()
	checks.check(config.load(root.music.settings_path) == OK and config.get_value("audio", "music_enabled", true) == false, "music off setting persists")
	root.game_menu.confirm()
	checks.check(root.music.enabled and root.music.player.playing, "settings toggle restarts music")
	config.load(root.music.settings_path)
	checks.check(config.get_value("audio", "music_enabled", false) == true, "music on setting persists")
	root.game_menu.back()
	checks.check(not root.game_menu.settings_open and root.game_menu.visible, "back from Settings stays in the game menu")
	DirAccess.remove_absolute(root.music.settings_path)
	root.music.settings_path = old_path
	root.music.set_enabled(old_enabled, false)
	root._restart(false)


func layout(root, checks) -> void:
	await _debug_sidebar(root, checks)
	root._restart(false)
	root._open_management(Ids.ManagementPage.CHARACTER, {}, true)
	var original_size: Vector2 = root.management.size
	for width in [1000, 1280]:
		root.management.size.x = width
		for frame in range(3): await root.get_tree().process_frame
		checks.check(root.management.resources.size.x > 300 and root.management.resources.get_line_count() <= 5, "character heading remains horizontal at width %d" % width)
		checks.check(root.management.panel.get_global_rect().encloses(root.management.character_header.get_global_rect()), "character portrait/header stays within the large frame")
	root.management.size = original_size
	root.management.dismiss()
	root._open_management(Ids.ManagementPage.LOOT, {"gold": 500, "items": []})
	for frame in range(3): await root.get_tree().process_frame
	var gold_row: HBoxContainer = root.management.content.get_child(0)
	var amount: Label = gold_row.get_child(1)
	checks.check(amount.text == "500" and amount.size.x >= 80 and amount.get_line_count() == 1, "gold-only chest receipt shows its right-aligned amount")
	checks.check(not root.management.tabs.visible and not root.management.character_header.visible, "chest receipt contains no character tabs/header")
	root.management.dismiss()
	root._restart(false)


func _debug_key(root, code: int, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	root._input(event)


func _debug_sidebar(root, checks) -> void:
	root._restart(false)
	for frame in range(2): await root.get_tree().process_frame
	checks.check(not root.sidebar_scroll.visible and not root.sidebar_background.visible and root.view.position.x == 0 and root.view.size.x == root.size.x, "debug sidebar starts hidden and map fills the window")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = root.view.size * 0.5
	var normal_zoom: float = root.view.zoom_factor
	root.view._gui_input(wheel)
	checks.check(root.view.zoom_factor == normal_zoom and root.view.camera_follow, "normal play ignores wheel zoom without releasing the hero camera")
	var point: Vector2 = root.session.hero.position_pixels
	_debug_key(root, KEY_E, true)
	_debug_key(root, KEY_D, true)
	root._process(0.062)
	checks.check(not root.sidebar_scroll.visible and root.session.hero.position_pixels == point, "partial DEV chord suppresses D movement without toggling")
	_debug_key(root, KEY_V, true)
	_debug_key(root, KEY_V, true, true)
	for frame in range(2): await root.get_tree().process_frame
	checks.check(root.sidebar_scroll.visible and root.sidebar_background.visible and root.view.position.x == 300 and root.action_bar.offset_left == 324 and root.dialogue_panel.offset_left == 320, "complete DEV chord reveals sidebar once and reflows map and overlays")
	root.view._gui_input(wheel)
	checks.check(root.view.zoom_factor > normal_zoom and not root.view.camera_follow, "debug mode retains wheel zoom for inspection")
	for code in [KEY_D, KEY_E, KEY_V]: _debug_key(root, code, false)
	for code in [KEY_D, KEY_E, KEY_V]: _debug_key(root, code, true)
	for code in [KEY_V, KEY_E, KEY_D]: _debug_key(root, code, false)
	root._process(0.062)
	checks.check(not root.sidebar_scroll.visible and root.view.offset_left == 0 and root.action_bar.offset_left == 24 and root.session.hero.position_pixels == point and root.held_keys.is_empty(), "second chord hides sidebar and releasing it does not leave movement held")
	_debug_key(root, KEY_E, true)
	root._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_debug_key(root, KEY_D, true)
	checks.check(root.held_keys.has(KEY_D) and not root.sidebar_scroll.visible, "focus loss clears a partial DEV chord so ordinary D still works")
	_debug_key(root, KEY_D, false)
	root._demo_battle()
	var phase: StringName = root.battle_overlay.phase
	for code in [KEY_V, KEY_D, KEY_E]: _debug_key(root, code, true)
	for code in [KEY_E, KEY_D, KEY_V]: _debug_key(root, code, false)
	checks.check(root.sidebar_scroll.visible and root.battle_overlay.offset_left == 300 and root.battle_overlay.phase == phase, "DEV toggles during battle introduction without dismissing it")
	for code in [KEY_E, KEY_V, KEY_D]: _debug_key(root, code, true)
	for code in [KEY_D, KEY_E, KEY_V]: _debug_key(root, code, false)
	checks.check(not root.sidebar_scroll.visible and root.battle_overlay.offset_left == 0, "battle overlay fills the freed sidebar space")
	root._restart(false)


func enemy_hover_point(view, actor, opaque: bool = true) -> Vector2:
	var pose: Dictionary = view.sprite_pose(actor.render_record())
	var frame: Vector2i = Vector2i(pose["frame_size"])
	var image: Image = view.textures[int(pose["image"])].get_image()
	var mirrored: bool = actor.facing in [Ids.Facing.RIGHT, Ids.Facing.ATTACK_RIGHT]
	view._update_transform()
	for y in range(frame.y):
		for x in range(frame.x):
			var sx: int = image.get_width() - int(pose["column"]) * frame.x - 1 - x if mirrored else int(pose["column"]) * frame.x + x
			var sy: int = int(pose["row"]) * frame.y + y
			if sx < 0 or sx >= image.get_width() or sy >= image.get_height(): continue
			if (image.get_pixel(sx, sy).a > 0.1) != opaque: continue
			return view.map_origin + (actor.position_pixels - Vector2(pose["origin"]) + Vector2(x + 0.5, y + 0.5)) * view.pixel_scale
	return Vector2(-1000, -1000)


func _enemy_hover(root, checks) -> void:
	root._demo_battle()
	root.battle_overlay.acknowledge()
	var enemy = root.battle.unit(1004)
	var selected: int = root.battle.selected_id
	for facing in range(8):
		enemy.facing = facing
		root.view.update_units(root.session.render_records(1))
		var point: Vector2 = enemy_hover_point(root.view, enemy)
		var info: Dictionary = root.view.enemy_hover_info(point)
		checks.check(info.get("id", -1) == enemy.instance_id and int(info.get("hp", -1)) == enemy.stats[Ids.Stat.HP], "enemy sprite hover resolves the visible atlas pixels in facing %d" % facing)
	var point: Vector2 = enemy_hover_point(root.view, enemy)
	enemy.stats[Ids.Stat.HP] = 23
	enemy.stats[Ids.Stat.MAX_MANA] = 31
	enemy.stats[Ids.Stat.MANA] = 17
	root.view._update_enemy_hint(point)
	var info: Dictionary = root.view.enemy_hover_info(point)
	checks.check(root.view.enemy_hint.visible and int(info["hp"]) == 23 and int(info["mana"]) == 17 and str(info["text"]).contains("17 / 31"), "enemy hint shows current health and mana while the cursor stays still")
	checks.check(root.battle.selected_id == selected and root.battle.queue.is_empty(), "hovering never selects a fighter or queues an attack")
	checks.check(root.view.enemy_hover_info(enemy_hover_point(root.view, enemy, false)).is_empty(), "transparent sprite pixels do not produce an enemy hint")
	checks.check(root.view.enemy_hover_info(enemy_hover_point(root.view, root.session.hero)).is_empty(), "party members do not show hostile hints")
	enemy.stats[Ids.Stat.MAX_MANA] = 0
	checks.check(not str(root.view.enemy_hover_info(point).get("text", "")).contains("Мана"), "enemy without mana omits the mana row")
	enemy.dead = true
	checks.check(root.view.enemy_hover_info(point).is_empty(), "dead enemies do not retain a hover hint")
	enemy.dead = false
	var old_spawn: int = int(root.session.spawn_states[enemy.spawn_flag])
	root.session.spawn_states[enemy.spawn_flag] = 1
	checks.check(root.view.enemy_hover_info(point).is_empty(), "hidden source spawns cannot leak health through hover")
	root.session.spawn_states[enemy.spawn_flag] = old_spawn
	root.session.mode = &"exploration"
	checks.check(root.view.enemy_hover_info(point).get("id", -1) == enemy.instance_id, "enemy hover is available outside combat")
	root.session.mode = &"game_menu"
	root.view._update_enemy_hint(point)
	checks.check(not root.view.enemy_hint.visible, "modal menus hide enemy hints")
	root.session.mode = &"battle"
	var edge_point := Vector2(root.view.size.x - 12, point.y)
	root.view.pan.x += edge_point.x - point.x
	root.view._update_enemy_hint(edge_point)
	checks.check(root.view.enemy_hint.visible and Rect2(Vector2.ZERO, root.view.size).encloses(root.view.enemy_hint.get_rect()), "enemy hint flips away from the window edge and remains inside the map")
	root._restart(false)
