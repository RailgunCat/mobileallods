extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const InputChecks = preload("res://tests/hd_menu_checks.gd")
var captures: bool = false
var input := InputChecks.new()

func _capture(root, name: String) -> void:
	await input._frame(root)
	if captures: root.get_viewport().get_texture().get_image().save_png("res://../build/hd-extra-%s.png" % name)

func run(root, checks) -> void:
	var processing: bool = root.is_processing()
	root.set_process(false)
	var old_hd: bool = root.preferences.values["hd_icons"]
	var old_saves: String = root.saves.directory
	root.saves.directory = ProjectSettings.globalize_path("res://").path_join("../build/hd-extra-saves-%d" % Time.get_ticks_usec()).simplify_path()
	root.preferences.update("hd_icons", true, false)
	root._restart(false)
	root.session.quests[Ids.Quest.CITY_CERTIFICATE] = Ids.QuestState.COMPLETED
	root.session.quests[17] = Ids.QuestState.ACTIVE
	root.session.tutorial_seen[Ids.Tutorial.TOWN] = 1
	for i in range(8): root.session.flags["e"][i] = 1
	root._show_world(false)
	var world = root.world_panel.hd_remaining
	await _capture(root, "world")
	checks.check(world.active() and world.visible and root.world_panel.selected == 7, "HD world map highlights the active map-seven destination")
	checks.check(not input._action(world, "destination_7").is_empty() and input._action(world, "destination_8").is_empty(), "HD map lists open locations without unlocking later maps")
	root.world_panel.required = true
	await input._frame(root)
	checks.check(not input._action(world, "close")["enabled"], "required HD travel disables closing")
	root.world_panel.dismiss()
	checks.check(root.world_panel.visible, "required HD travel also rejects Escape dismissal")
	root.world_panel.required = false
	await input._click(root, world, "destination_0", checks)
	await input._click(root, world, "travel", checks)
	await _capture(root, "town")
	checks.check(world.active() and root.world_panel.screen == &"town" and world.painting.get_size() == Vector2(1672, 941), "HD city loads the existing town painting")
	await input._click(root, world, "town_0", checks)
	checks.check(root.world_panel.screen == &"tavern" and root.world_panel.hd_interior.active() and not world.active(), "HD town opens the existing HD tavern")
	root.world_panel.back()
	await input._frame(root)
	await input._click(root, world, "town_2", checks)
	await input._click(root, world, "destination_7", checks)
	await input._click(root, world, "travel", checks)
	checks.check(root.session.location_id == 6 and not root.world_panel.visible, "HD world destination enters the real seventh map")
	root.campaign.enabled = false
	var many_items: Array[int] = []
	for repeat in range(3):
		for id in range(41): many_items.append(id)
	var inventory_count: int = root.session.inventory.size()
	root._open_management(Ids.ManagementPage.LOOT, {"gold": 125, "items": many_items})
	var loot = root.management.hd_loot
	await _capture(root, "pickup")
	checks.check(loot.active() and loot.visible and not root.management.panel.visible, "HD pickup replaces the old receipt panel")
	await input._click(root, loot, "loot_next", checks)
	checks.check(loot.list_page == 1, "HD pickup paginates long item lists")
	await input._click(root, loot, "continue", checks)
	checks.check(not root.management.visible and root.session.inventory.size() == inventory_count, "closing an HD pickup does not award its presentation twice")
	root._demo_battle()
	var notice = root.battle_overlay.hd_screen
	await _capture(root, "intro")
	checks.check(notice.active() and root.battle_overlay.phase == &"intro", "HD battle introduction uses the new notice")
	await input._click(root, notice, "continue", checks)
	checks.check(root.session.mode == &"battle" and root.battle_overlay.phase == &"", "HD introduction starts the actual battle")
	for id in root.battle.participants:
		var actor = root.battle.unit(id)
		if actor not in root.session.party:
			actor.dead = true
			actor.stats[Ids.Stat.HP] = 0
	root.battle._check_outcome()
	root._refresh()
	var receipt: Dictionary = root.battle.reward.duplicate(true)
	receipt["items"] = many_items
	root.battle_overlay.show_result(true, receipt, root.campaign_data["battle_ui"], root.view.textures, root.metadata["economy"]["item_names"])
	await _capture(root, "victory")
	checks.check(notice.active() and input._action(notice, "continue")["rect"].end.y < 800, "HD victory keeps Continue visible with 123 item entries")
	await input._click(root, notice, "loot_next", checks)
	await input._click(root, notice, "continue", checks)
	checks.check(root.session.mode == &"exploration" and not root.battle.active and root.battle_overlay.phase == &"", "HD victory Continue closes the result and restores exploration")
	# The original presentation must also remain closable with long loot.
	root.preferences.update("hd_icons", false, false)
	root.battle_overlay.show_result(true, receipt, root.campaign_data["battle_ui"], root.view.textures, root.metadata["economy"]["item_names"])
	await _capture(root, "legacy-long-loot")
	checks.check(Rect2(Vector2.ZERO, root.get_viewport_rect().size).encloses(root.battle_overlay.footer.get_global_rect()), "legacy victory Continue stays inside the window with long loot")
	checks.check(root.battle_overlay.body_scroll.get_v_scroll_bar().max_value > root.battle_overlay.body_scroll.size.y, "legacy long loot scrolls instead of pushing its footer away")
	root.battle_overlay.acknowledge()
	checks.check(root.battle_overlay.phase == &"", "legacy long-loot result can close")
	root.preferences.update("hd_icons", true, false)
	root.battle_overlay.show_result(false, {}, root.campaign_data["battle_ui"], root.view.textures)
	await _capture(root, "defeat")
	checks.check(not input._action(notice, "continue").is_empty(), "HD defeat retains the restart action")
	root.battle_overlay.hide_screen()
	if captures:
		var old_size: Vector2i = DisplayServer.window_get_size()
		DisplayServer.window_set_size(Vector2i(1600, 900))
		root.session.quests[Ids.Quest.CITY_CERTIFICATE] = Ids.QuestState.COMPLETED
		root.session.tutorial_seen[Ids.Tutorial.TOWN] = 1
		root._show_world(false)
		await _capture(root, "resized-world")
		await input._click(root, world, "destination_0", checks)
		await input._click(root, world, "travel", checks)
		checks.check(root.world_panel.screen == &"town", "HD world-map pointer remains aligned after resizing")
		DisplayServer.window_set_size(old_size)
	root.world_panel.hide()
	root.session.mode = &"exploration"
	for slot in range(root.saves.TOTAL_SLOT_COUNT):
		for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(root.saves.path(slot) + suffix)
	DirAccess.remove_absolute(root.saves.directory)
	root.saves.directory = old_saves
	root.preferences.update("hd_icons", old_hd, false)
	root.set_process(processing)
