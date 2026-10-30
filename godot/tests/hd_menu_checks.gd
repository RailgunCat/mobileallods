extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
var captures: bool = false

func _frame(root) -> void:
	await root.get_tree().process_frame
	await root.get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func _capture(root, name: String) -> void:
	await _frame(root)
	if captures: root.get_viewport().get_texture().get_image().save_png("res://../build/hd-menu-%s.png" % name)

func _action(ui, id: String) -> Dictionary:
	for action: Dictionary in ui.actions:
		if action["id"] == id: return action
	return {}

func _click(root, ui, id: String, checks) -> void:
	var action: Dictionary = _action(ui, id)
	checks.check(not action.is_empty(), "HD menu has action " + id)
	if action.is_empty(): return
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = root.get_viewport().get_final_transform() * (ui.global_position + ui.origin + action["rect"].get_center() * ui.ui_scale)
	root.get_viewport().push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.get_viewport().push_input(event)
	await _frame(root)

func run(root, checks) -> void:
	# Keep exploration from starting an entrance script in the two render frames
	# immediately after loading; this suite drives only menu input explicitly.
	var processing: bool = root.is_processing()
	root.set_process(false)
	var old_values: Dictionary = root.preferences.values.duplicate(true)
	var old_path: String = root.preferences.path
	var old_saves: String = root.saves.directory
	var stamp: int = Time.get_ticks_usec()
	var build_directory: String = ProjectSettings.globalize_path("res://").path_join("../build").simplify_path()
	root.preferences.path = build_directory.path_join("hd-menu-settings-%d.cfg" % stamp)
	root.saves.directory = build_directory.path_join("hd-menu-saves-%d" % stamp)
	root.preferences.update("hd_icons", true, false)
	root._restart(false)
	root._has_started = true
	root._show_main_menu()
	var title = root.main_menu.hd_screen
	var pause = root.game_menu.hd_screen
	var slots = root.save_slots.hd_screen
	await _capture(root, "title")
	checks.check(title.active() and title.visible and title.painting.get_size() == Vector2(1672, 941), "HD title loads the existing text-free painting")
	checks.check(title.project_font == root.theme.default_font and title.project_frame.texture != null, "HD menu uses the same project font and frame as management")
	checks.check(not _action(title, "title_3")["enabled"], "HD title does not present the unavailable network as playable")
	root.main_menu.navigate(1)
	checks.check(root.main_menu.selected == Ids.TitleChoice.LOAD, "HD title keyboard navigation follows the visible button order")
	await _click(root, title, "title_4", checks)
	await _capture(root, "controls")
	checks.check(not root.main_menu.body.is_empty() and _action(title, "title_0").is_empty(), "HD controls page blocks title buttons")
	root.main_menu.navigate(1)
	await _frame(root)
	checks.check(title.body_scroll == mini(1, title.body_limit), "HD keyboard scroll follows reflowed help text")
	await _click(root, title, "back", checks)
	await _click(root, title, "title_8", checks)
	await _capture(root, "settings")
	checks.check(root.game_menu.settings_open and pause.title_background and not root.main_menu.visible, "HD title settings keep their painted background")
	var was_music: bool = root.preferences.values["music_enabled"]
	await _click(root, pause, "setting_0", checks)
	checks.check(root.preferences.values["music_enabled"] != was_music and FileAccess.file_exists(root.preferences.path), "HD settings use the existing persistent preferences")
	await _click(root, pause, "slider_1", checks)
	checks.check(root.preferences.values["music_volume"] == 50, "HD volume click maps to the actual 50 percent value")
	# Drag uses the same transformed viewport input as ordinary pointer events.
	var slider: Dictionary = _action(pause, "slider_1")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = root.get_viewport().get_final_transform() * (pause.global_position + pause.origin + slider["rect"].get_center() * pause.ui_scale)
	root.get_viewport().push_input(press)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = root.get_viewport().get_final_transform() * (pause.global_position + pause.origin + (slider["rect"].end + Vector2(50, -15)) * pause.ui_scale)
	root.get_viewport().push_input(motion)
	press.pressed = false
	press.position = motion.position
	root.get_viewport().push_input(press)
	await _frame(root)
	checks.check(root.preferences.values["music_volume"] == 100 and pause.drag_setting == -1, "HD slider drag clamps at 100 percent and stops on release")
	await _click(root, pause, "slider_3", checks)
	checks.check(root.preferences.values["sfx_volume"] == 50 and root.preferences.values["music_volume"] == 100, "HD SFX slider uses its own independent volume")
	root.preferences.update("fps_limit", 0, false)
	await _click(root, pause, "setting_7", checks)
	checks.check(root.preferences.values["fps_limit"] == 30 and Engine.max_fps == 30, "HD frame limit changes actual engine pacing")
	root.preferences.update("fps_limit", 0, false)
	await _click(root, pause, "setting_4", checks)
	checks.check(not pause.active() and not pause.visible and root.game_menu.settings_open, "turning HD off immediately restores legacy settings")
	root.preferences.update("hd_icons", true, false)
	await _frame(root)
	await _click(root, pause, "back", checks)
	checks.check(root.main_menu.visible and not root.game_menu.visible, "back from title settings returns to the title")
	await _click(root, title, "title_2", checks)
	await _capture(root, "load")
	checks.check(root.save_slots.visible and not root.save_slots.saving and slots.title_background and root.save_slots.slot_count() == 6, "HD title load shows manual slots and autosave")
	await _click(root, slots, "slot_1", checks)
	checks.check(root.save_slots.selected == 1 and root.save_slots.visible, "HD slot selection waits for the load action")
	await _click(root, slots, "slot_confirm", checks)
	checks.check(root.save_slots.visible and not root.save_slots.message.is_empty(), "HD empty save reports the existing validation error")
	await _click(root, slots, "back", checks)
	await _click(root, title, "title_1", checks)
	checks.check(root.session.mode == &"exploration" and not root.main_menu.visible, "HD Continue resumes the current game")
	root.campaign.enabled = true
	root.session.gold = 432
	root._show_game_menu()
	await _capture(root, "pause")
	checks.check(root.game_menu.visible and pause.active() and not pause.title_background, "HD pause overlays the frozen game")
	await _click(root, pause, "pause_3", checks)
	checks.check(root.legacy_management.visible and root.legacy_management.hd_screen.active(), "HD pause inventory opens the HD management window")
	root.legacy_management.hd_screen.handle_key(KEY_ESCAPE)
	await _frame(root)
	checks.check(root.game_menu.visible and root.game_menu.selected == Ids.GameMenuChoice.INVENTORY, "closing HD inventory returns to its pause menu row")
	await _click(root, pause, "pause_4", checks)
	await _capture(root, "save")
	checks.check(root.save_slots.saving and root.save_slots.slot_count() == 5 and not slots.title_background, "HD save shows five writable slots over the world")
	await _click(root, slots, "slot_1", checks)
	await _click(root, slots, "slot_confirm", checks)
	checks.check(root.saves.exists(1) and root.save_slots.message.contains("сохранена"), "HD save writes through the real save service")
	await _click(root, slots, "back", checks)
	root.session.gold = 987
	await _click(root, pause, "pause_5", checks)
	await _click(root, slots, "slot_1", checks)
	await _click(root, slots, "slot_confirm", checks)
	checks.check(root.session.gold == 432 and not root.save_slots.visible and root.session.mode == &"exploration", "HD load restores the actual saved campaign: gold=%d mode=%s" % [root.session.gold, root.session.mode])
	root._demo_battle()
	root._show_game_menu()
	await _capture(root, "combat")
	var tick: int = root.battle.tick_count
	root._process(2)
	checks.check(root.battle.tick_count == tick, "HD combat menu freezes the battle")
	for choice in [Ids.GameMenuChoice.SAVE, Ids.GameMenuChoice.CHARACTER, Ids.GameMenuChoice.INVENTORY, Ids.GameMenuChoice.JOURNAL]:
		checks.check(not _action(pause, "pause_%d" % choice)["enabled"], "HD combat menu disables restricted choice %d" % choice)
	await _click(root, pause, "pause_4", checks)
	checks.check(root.game_menu.visible and not root.save_slots.visible, "disabled HD Save cannot open a slot during battle")
	await _click(root, pause, "pause_0", checks)
	checks.check(not root.game_menu.visible and root.session.mode == &"battle_intro", "HD Continue restores the paused battle introduction")
	root._restart(false)
	root._show_main_menu()
	await _frame(root)
	if captures:
		var old_size: Vector2i = DisplayServer.window_get_size()
		DisplayServer.window_set_size(Vector2i(1600, 900))
		await _frame(root)
		await _click(root, title, "title_8", checks)
		checks.check(root.game_menu.settings_open, "HD title mouse input follows resized and letterboxed windows")
		await _capture(root, "resized")
		DisplayServer.window_set_size(old_size)
		root.game_menu.back()
		await _frame(root)
	await _click(root, title, "title_0", checks)
	checks.check(root.campaign.enabled and root.campaign.script_id == Ids.StoryScript.EXPLORATION_TUTORIAL, "HD New Game starts the actual original opening")
	root._restart(false)
	for slot in range(root.saves.TOTAL_SLOT_COUNT):
		for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(root.saves.path(slot) + suffix)
	DirAccess.remove_absolute(root.saves.directory)
	DirAccess.remove_absolute(root.preferences.path)
	root.saves.directory = old_saves
	root.preferences.path = old_path
	for key: String in old_values: root.preferences.update(key, old_values[key], false)
	await _frame(root)
	root.set_process(processing)
