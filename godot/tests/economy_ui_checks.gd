extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Stat = Ids.Stat
const Page = Ids.ManagementPage
const Inventory = preload("res://scripts/gameplay/inventory_rules.gd")


func run(root, checks) -> void:
	root._restart(false)
	var unit = root.session.hero
	unit.attribute_points = 5
	unit.skill_points = 1
	var original_strength: int = unit.base_stats[Stat.STRENGTH]
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_C
	root.held_keys[KEY_D] = true
	root._open_management(Page.CHARACTER, {}, true)
	checks.check(root.management.visible and root.session.mode == &"management" and root.held_keys.is_empty(), "debug character panel opens and clears walking input")
	var position: Vector2 = unit.position_pixels
	var tick: int = root.exploration.tick_count
	root._process(10)
	checks.check(unit.position_pixels == position and root.exploration.tick_count == tick, "management pauses exploration simulation")
	root.management.attribute_buttons[Stat.STRENGTH].pressed.emit()
	checks.check(root.management.draft["base"][Stat.STRENGTH] == original_strength + 1 and unit.base_stats[Stat.STRENGTH] == original_strength, "character plus button changes draft before confirmation")
	key.physical_keycode = KEY_ESCAPE
	root._input(key)
	checks.check(not root.management.visible and root.session.mode == &"exploration" and unit.attribute_points == 5 and unit.base_stats[Stat.STRENGTH] == original_strength, "Escape cancels training and resumes exploration")
	root._open_management(Page.CHARACTER, {}, true)
	root.management.attribute_buttons[Stat.STRENGTH].pressed.emit()
	root.management.apply_button.pressed.emit()
	checks.check(unit.base_stats[Stat.STRENGTH] == original_strength + 1 and unit.attribute_points == 4, "apply button commits attribute once")
	root.management.attribute_buttons[Stat.DEXTERITY].pressed.emit()
	root.management.switch_page(Page.JOURNAL)
	checks.check(unit.attribute_points == 4 and root.management.draft.is_empty(), "switching tabs discards pending training")
	var journal: String = ""
	for child in root.management.content.get_children():
		if child is Label: journal += child.text
	checks.check(journal.contains(str(root.campaign_data["quests"][0]["title"])) and journal.contains(str(root.campaign_data["quests"][0]["text"])), "journal shows active quest title and full recovered text")
	var upgrade = Inventory.add(root.session, 13)
	var crystal = Inventory.add(root.session, 36)
	root.management.switch_page(Page.INVENTORY)
	for index in range(root.management.item_list.item_count):
		if root.management.item_list.get_item_metadata(index) == upgrade.instance_id:
			root.management.item_list.item_selected.emit(index)
			break
	root.management.equip_button.pressed.emit()
	checks.check(unit.weapon == upgrade, "inventory list selection and equip button change actual gear")
	var inserted: bool = false
	for button in root.management.content.find_children("*", "Button", true, false):
		if button.text.begins_with("Гнездо 1:"):
			button.pressed.emit()
			inserted = true
			break
	checks.check(inserted and upgrade.socket_instance_ids[0] == crystal.instance_id, "socket button inserts chosen crystal instance")
	root.session.gold = 1000
	root.management.dismiss()
	# Shop fixture starts after the source certificate milestone.
	root.session.quests[Ids.Quest.CITY_CERTIFICATE] = Ids.QuestState.COMPLETED
	root.session.tutorial_seen[Ids.Tutorial.TOWN] = 1
	root._show_world(false)
	root.world_panel.show_town()
	root._open_town_shop()
	root.shop.selected = 0
	root.shop.confirm()
	var before: int = root.session.inventory.size()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	root.shop.buy_button._gui_input(click)
	root.shop.buy_button._gui_input(click)
	checks.check(root.session.inventory.size() == before + 1 and root.session.gold == 851, "shop buy button uses original 149-gold armor price")
	root.shop.back()
	root.shop.back()
	checks.check(root.world_panel.visible and root.session.mode == &"town", "closing shop returns to town")
	# Exercise source pickup through the walking controller and real event/UI path.
	root._restart(false)
	root.campaign.enabled = true
	root.campaign.triggers.clear()
	# The chest is beside rocks: only its east edge is physically accessible.
	root.session.hero.set_pixel_position(Vector2(572, 80))
	root.session.collision.occupy(root.session.hero.instance_id, root.session.hero.cell, root.session.hero.footprint)
	root.exploration.configure(root.session)
	root.held_keys[KEY_A] = true
	root._process(0.186)
	checks.check(root.battle.active and root.session.gold == 0, "nearby guard starts battle before the chest can be collected")
	# Isolate collection after checking encounter priority; do not change balance.
	root._restart(false)
	root.campaign.enabled = true
	root.campaign.triggers.clear()
	for npc in root.session.units: npc.encounter_enabled = false
	root.session.hero.set_pixel_position(Vector2(572, 80))
	root.session.collision.occupy(root.session.hero.instance_id, root.session.hero.cell, root.session.hero.footprint)
	root.exploration.configure(root.session)
	root.held_keys[KEY_A] = true
	root._process(0.186)
	checks.check(root.management.visible and root.management.page == Page.LOOT and root.session.gold == 200 and root.session.inventory.size() == 4, "walking into original pickup opens received-items UI exactly once: position=%s mode=%s gold=%d" % [root.session.hero.position_pixels, root.session.mode, root.session.gold])
	# Reproduce the reported long chest-item name after real container layout.
	root.management.receipt = {"gold": 300, "items": [Ids.ItemId.LAST_SWORD]}
	root.management.render()
	var panel_size: Vector2 = root.management.size
	for width in [1000, 1280]:
		root.management.size.x = width
		for frame in range(3): await root.get_tree().process_frame
		var item_row: HBoxContainer = root.management.content.get_child(1)
		var item_title: Label = item_row.get_child(1)
		checks.check(item_title.get_line_count() == 1, "chest item name stays on one line at width %d: text=%s width=%s lines=%d" % [width, item_title.text, item_title.size.x, item_title.get_line_count()])
	root.management.size = panel_size
	root.management.dismiss()
	root._process(1)
	checks.check(root.session.gold == 200 and root.session.inventory.size() == 4, "closing pickup cannot award it again")
	root._demo_battle()
	root._open_management(Page.CHARACTER)
	checks.check(not root.management.visible, "battle intro rejects management menu")
	await root.get_tree().process_frame
	await root.get_tree().process_frame
