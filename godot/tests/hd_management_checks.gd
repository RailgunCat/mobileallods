extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Inventory = preload("res://scripts/gameplay/inventory_rules.gd")
const Stat = Ids.Stat
var captures: bool = false

func _frame(root) -> void:
	await root.get_tree().process_frame
	await root.get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func _capture(root, name: String) -> void:
	await _frame(root)
	if captures: root.get_viewport().get_texture().get_image().save_png("res://../build/hd-management-%s.png" % name)

func _action(ui, id: String) -> Dictionary:
	for action: Dictionary in ui.actions:
		if action["id"] == id: return action
	return {}

func _click(root, ui, id: String, checks) -> void:
	var action: Dictionary = _action(ui, id)
	checks.check(not action.is_empty(), "HD management has action " + id)
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
	var previous_hd: bool = root.preferences.values["hd_icons"]
	root.preferences.update("hd_icons", true, false)
	root._demo_party()
	root.session.hero.attribute_points = 3
	root.session.hero.skill_points = 2
	var ui = root.legacy_management.hd_screen
	var hero = root.session.hero
	var original: PackedInt32Array = hero.base_stats.duplicate()
	root._open_management(Ids.ManagementPage.CHARACTER)
	await _capture(root, "character")
	checks.check(ui.active() and ui.visible and root.legacy_management.visible and not root.management.visible, "HD character uses the normal gameplay entry")
	checks.check(ui.project_font == root.theme.default_font and ui.project_frame.texture != null, "HD management reuses the project font and stone frame")
	await _click(root, ui, "plus_%d" % Stat.STRENGTH, checks)
	checks.check(hero.base_stats == original and root.legacy_management.draft["attribute_points"] == 2, "HD training previews without spending the real attribute budget")
	await _capture(root, "training-preview")
	await _click(root, ui, "cancel", checks)
	checks.check(hero.base_stats == original and root.legacy_management.draft["attribute_points"] == 3, "HD cancel restores both draft budgets")
	await _click(root, ui, "plus_%d" % Stat.STRENGTH, checks)
	await _click(root, ui, "apply", checks)
	checks.check(hero.base_stats[Stat.STRENGTH] == original[Stat.STRENGTH] + 1 and hero.attribute_points == 2, "HD apply commits exactly one attribute point")
	var trained: PackedInt32Array = hero.base_stats.duplicate()
	await _click(root, ui, "plus_%d" % Stat.ENDURANCE, checks)
	await _click(root, ui, "actor_1", checks)
	checks.check(hero.base_stats == trained and root.legacy_management.actor() == root.session.party[1], "HD switching hero discards the uncommitted draft")
	await _click(root, ui, "actor_0", checks)
	hero.base_stats[Stat.ATTACK] = 25
	hero.recalculate(root.table)
	root.legacy_management.draft = {}
	await _frame(root)
	checks.check(not _action(ui, "plus_%d" % Stat.ATTACK)["enabled"], "HD training disables skills at displayed rank 24")
	checks.check(_action(ui, "plus_%d" % Stat.DARK_AIR_MAGIC).is_empty(), "HD training does not invent unknown schools")
	var endurance: int = hero.base_stats[Stat.ENDURANCE]
	await _click(root, ui, "plus_%d" % Stat.ENDURANCE, checks)
	var sword = Inventory.add(root.session, 15)
	var bow = Inventory.add(root.session, 22)
	var crystal = Inventory.add(root.session, 39)
	for i in range(19): Inventory.add(root.session, 0)
	await _click(root, ui, "tab_1", checks)
	checks.check(hero.base_stats[Stat.ENDURANCE] == endurance and root.legacy_management.draft.is_empty(), "HD switching tabs discards uncommitted training")
	await _capture(root, "inventory")
	checks.check(root.legacy_management.page == Ids.ManagementPage.INVENTORY and ui.items().size() > 16, "HD inventory shows the shared bag without a capacity limit")
	await _click(root, ui, "bag_next", checks)
	checks.check(ui.bag_page == 1, "HD bag next page works")
	await _click(root, ui, "bag_prev", checks)
	checks.check(ui.bag_page == 0, "HD bag previous page works")
	await _click(root, ui, "filter_1", checks)
	await _click(root, ui, "item_%d" % bow.instance_id, checks)
	checks.check(not _action(ui, "equip")["enabled"], "HD inventory explains and blocks equipment for another class")
	await _click(root, ui, "item_%d" % sword.instance_id, checks)
	var old_weapon = hero.weapon
	await _capture(root, "item-preview")
	checks.check(hero.weapon == old_weapon, "HD item selection leaves actual equipment unchanged")
	await _click(root, ui, "equip", checks)
	checks.check(hero.weapon == sword, "HD equip changes the actual weapon")
	await _click(root, ui, "socket_0", checks)
	await _capture(root, "crystals")
	checks.check(ui.socket == 0 and _action(ui, "tab_0").is_empty(), "HD crystal picker blocks underlying tabs and equipment actions")
	ui.handle_key(KEY_TAB)
	checks.check(ui.socket == 0 and root.legacy_management.page == Ids.ManagementPage.INVENTORY, "HD crystal picker also blocks background keyboard navigation")
	await _click(root, ui, "crystal_%d" % crystal.instance_id, checks)
	checks.check(sword.socket_instance_ids[0] == crystal.instance_id and Inventory.mounted(root.session, crystal), "HD socket insert keeps crystal identity and removes it from the free bag")
	await _capture(root, "equipped")
	await _click(root, ui, "socket_0", checks)
	checks.check(sword.socket_instance_ids[0] == -1 and not Inventory.mounted(root.session, crystal), "HD extracting a crystal returns the same item to the bag")
	await _click(root, ui, "equip", checks)
	checks.check(hero.weapon == null, "HD remove clears the actual equipment slot")
	await _click(root, ui, "tab_3", checks)
	root.session.quests[1] = Ids.QuestState.ACTIVE
	root.session.quests[2] = Ids.QuestState.COMPLETED
	await _capture(root, "journal")
	checks.check(not _action(ui, "quest_0").is_empty(), "HD journal shows real campaign quests")
	await _click(root, ui, "quest_1", checks)
	checks.check(ui.quest_index == 1, "HD journal selects a real quest description")
	var previous_window: Vector2i = DisplayServer.window_get_size()
	if captures:
		DisplayServer.window_set_size(Vector2i(1600, 900))
		await _frame(root)
		await _click(root, ui, "tab_1", checks)
		checks.check(root.legacy_management.page == Ids.ManagementPage.INVENTORY, "HD mouse coordinates follow resized and letterboxed windows")
		await _capture(root, "resized")
		DisplayServer.window_set_size(previous_window)
	root.preferences.update("hd_icons", false, false)
	await _frame(root)
	checks.check(not ui.active() and not ui.visible and root.legacy_management.visible, "disabling HD returns to the original management window")
	root.preferences.update("hd_icons", true, false)
	await _frame(root)
	await _click(root, ui, "tab_0", checks)
	await _click(root, ui, "plus_%d" % Stat.ENDURANCE, checks)
	ui.handle_key(KEY_ESCAPE)
	checks.check(not root.legacy_management.visible and root.session.mode == &"exploration" and hero.base_stats[Stat.ENDURANCE] == endurance, "HD Escape discards uncommitted training and resumes exploration")
	# Empty bags and journals should still allow closing and switching tabs.
	for actor in root.session.party:
		actor.weapon = null
		actor.armor = null
	root.session.inventory.clear()
	root._open_management(Ids.ManagementPage.INVENTORY)
	await _frame(root)
	checks.check(ui.items().is_empty() and _action(ui, "equip").is_empty() and not _action(ui, "bag_next")["enabled"], "HD empty inventory has no stale equipment actions")
	root.session.quests.fill(Ids.QuestState.NOT_STARTED)
	await _click(root, ui, "tab_3", checks)
	checks.check(_action(ui, "quest_0").is_empty() and not _action(ui, "close").is_empty(), "HD empty journal keeps navigation available")
	ui.handle_key(KEY_ESCAPE)
	root.preferences.update("hd_icons", previous_hd, false)
