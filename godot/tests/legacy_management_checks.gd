extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Stat = Ids.Stat
const Page = Ids.ManagementPage
const Inventory = preload("res://scripts/gameplay/inventory_rules.gd")
const Unit = preload("res://scripts/gameplay/unit_state.gd")


func key(root, code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	root._input(event)
	event.pressed = false
	root._input(event)


func select_item(ui, entry) -> void:
	for index in range(ui.candidates.size()):
		if ui.candidates[index] == entry:
			ui.selected = index
			ui._refresh()
			return


func run(root, checks) -> void:
	root._demo_party()
	var ui = root.legacy_management
	var third := Unit.new()
	third.configure({"instance_id": 3000, "unit_type": Ids.UnitKind.KURT, "story_group": Ids.StoryGroup.KURT, "spawn_flag": 0, "side_id": 0}, root.metadata, root.table)
	third.set_pixel_position(root.session.hero.position_pixels + Vector2(0, 40))
	root.session.units.append(third)
	root.session.party.append(third)
	key(root, KEY_C)
	checks.check(ui.visible and ui.screen == &"character" and not root.management.visible and ui.world_background, "normal C opens the source character screen over the monochrome world")
	var position: Vector2 = root.session.hero.position_pixels
	var tick: int = root.exploration.tick_count
	root._process(4)
	checks.check(root.session.hero.position_pixels == position and root.exploration.tick_count == tick, "source management screens pause exploration")
	key(root, KEY_RIGHT)
	checks.check(ui.actor() == root.session.party[1], "character portrait arrows switch to Li")
	var previous_level: int = ui.actor().base_stats[Stat.LEVEL]
	var previous_experience: int = ui.actor().base_stats[Stat.EXPERIENCE]
	ui.actor().base_stats[Stat.LEVEL] = 1
	ui.actor().base_stats[Stat.EXPERIENCE] = 96
	var progress: Dictionary = ui.experience_progress()
	checks.check(progress["experience"] == 96 and progress["next"] == 125 and progress["level"] == 2 and is_equal_approx(float(progress["ratio"]), 46.0 / 75), "source character header shows 96/125 XP, level two and progress within the current level")
	ui.actor().base_stats[Stat.LEVEL] = previous_level
	ui.actor().base_stats[Stat.EXPERIENCE] = previous_experience
	key(root, KEY_RIGHT)
	checks.check(ui.actor() == third, "character portrait arrows reach the third party member")
	key(root, KEY_LEFT)
	var actor = ui.actor()
	actor.attribute_points = 2
	actor.skill_points = 1
	ui.draft = {}
	ui._refresh()
	var intellect: int = actor.base_stats[Stat.INTELLECT]
	key(root, KEY_ENTER)
	key(root, KEY_DOWN)
	key(root, KEY_RIGHT)
	checks.check(ui.draft["base"][Stat.INTELLECT] == intellect + 1 and actor.base_stats[Stat.INTELLECT] == intellect and actor.attribute_points == 2, "source attribute controls preview an increase without consuming points")
	key(root, KEY_ESCAPE)
	checks.check(ui.visible and not ui.editing and actor.base_stats[Stat.INTELLECT] == intellect, "Escape cancels pending training and returns to portrait browsing")
	key(root, KEY_ENTER)
	ui.selected = 1
	key(root, KEY_RIGHT)
	key(root, KEY_ENTER)
	checks.check(actor.base_stats[Stat.INTELLECT] == intellect + 1 and actor.attribute_points == 1 and not ui.editing, "confirm commits a character draft once")
	key(root, KEY_ENTER)
	ui.selected = 1
	key(root, KEY_RIGHT)
	ui.choose_actor(2)
	checks.check(actor.attribute_points == 1 and actor.base_stats[Stat.INTELLECT] == intellect + 1 and ui.actor() == third, "switching portraits discards unconfirmed edits")
	ui.choose_actor(1)
	ui._change_training_page(true)
	var stat: int = ui.slots()[0]
	var skill: int = actor.base_stats[stat]
	key(root, KEY_ENTER)
	key(root, KEY_RIGHT)
	key(root, KEY_ENTER)
	checks.check(actor.base_stats[stat] == skill + 1 and actor.skill_points == 0, "source school page retains training and its separate point pool")
	key(root, KEY_ESCAPE)
	checks.check(not ui.visible and root.session.mode == &"exploration", "closing Character restores exploration")
	var upgrade = Inventory.add(root.session, 19)
	var crystal = Inventory.add(root.session, 36)
	key(root, KEY_I)
	checks.check(ui.screen == &"party" and ui.game.party.size() == 3 and not root.management.visible, "normal I opens the complete source inventory party list")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = ui.screen_origin + Vector2(65, 24 + 17 + 5) * ui.screen_scale
	ui._gui_input(click)
	checks.check(ui.screen == &"items" and ui.actor() == actor and ui.candidates[0].definition_id < 36, "clicking Li opens her item carousel with equipment first")
	select_item(ui, upgrade)
	var old_weapon = actor.weapon
	var comparison: Array = ui.comparison()
	checks.check(actor.weapon == old_weapon and comparison.size() >= 2 and comparison[0][0] == "Урон" and comparison[1][0] == "Дальность" and comparison[1][1] == actor.stats[Stat.ATTACK_RANGE], "item comparison previews damage and range without equipping")
	key(root, KEY_ENTER)
	checks.check(actor.weapon == upgrade, "source item action equips the selected bow")
	key(root, KEY_ENTER)
	checks.check(actor.weapon == null and Inventory.find(root.session, upgrade.instance_id) == upgrade, "source remove action unequips without deleting the item")
	key(root, KEY_ENTER)
	key(root, KEY_DOWN)
	key(root, KEY_ENTER)
	checks.check(ui.screen == &"sockets", "source inventory keeps crystal sockets accessible")
	key(root, KEY_ENTER)
	checks.check(ui.screen == &"crystals" and crystal in ui.crystals, "an empty socket opens available crystal instances")
	ui.action_index = ui.crystals.find(crystal)
	key(root, KEY_ENTER)
	checks.check(ui.screen == &"sockets" and upgrade.socket_instance_ids[0] == crystal.instance_id and Inventory.mounted(root.session, crystal), "source socket selection inserts the exact crystal identity")
	key(root, KEY_ENTER)
	checks.check(upgrade.socket_instance_ids[0] == -1 and not Inventory.mounted(root.session, crystal) and Inventory.find(root.session, crystal.instance_id) == crystal, "source socket removal returns the same crystal to inventory")
	key(root, KEY_ESCAPE)
	key(root, KEY_ESCAPE)
	checks.check(ui.screen == &"party", "back from items returns to party selection")
	key(root, KEY_ESCAPE)
	checks.check(not ui.visible and root.session.mode == &"exploration", "back from party selection closes Inventory")
	for quest: Dictionary in root.campaign_data["quests"]: root.session.quests[int(quest["id"])] = Ids.QuestState.NOT_STARTED
	for index in range(3): root.session.quests[int(root.campaign_data["quests"][index]["id"])] = [Ids.QuestState.ACTIVE, Ids.QuestState.COMPLETED, Ids.QuestState.FAILED][index]
	key(root, KEY_J)
	checks.check(ui.visible and ui.screen == &"journal" and ui.quests.size() == 3 and not root.management.visible, "normal J opens known active, completed and failed quests without unstarted quests")
	key(root, KEY_ENTER)
	var expected: String = str(ui.quests[0]["text"]).replace("\n", "").replace(" ", "")
	checks.check(ui.screen == &"quest" and "".join(ui.quest_lines()).replace(" ", "").contains(expected), "journal detail retains the entire recovered quest description")
	ui.quests[0] = ui.quests[0].duplicate(true)
	ui.quests[0]["text"] = "Длинное описание задания для проверки прокрутки. ".repeat(100)
	ui.navigate(10000)
	checks.check(ui.scroll == ui.quest_lines().size() - 14 and ui.scroll > 0, "long journal descriptions scroll to their final line")
	key(root, KEY_ESCAPE)
	checks.check(ui.screen == &"journal", "back from quest detail returns to the journal list")
	key(root, KEY_ESCAPE)
	checks.check(root.session.mode == &"exploration", "back from Journal restores exploration")
	root._open_management(Page.INVENTORY)
	var original_size: Vector2 = ui.size
	for extent: Vector2 in [Vector2(800, 600), Vector2(1280, 800), Vector2(900, 1100)]:
		ui.size = extent
		ui._position_regions()
		var fits: bool = true
		for region in ui.regions:
			fits = fits and Rect2(Vector2.ZERO, extent).encloses(Rect2(ui.screen_origin + region.logical_rect.position * ui.screen_scale, region.logical_rect.size * ui.screen_scale))
		checks.check(fits, "source management input regions remain inside %s" % extent)
	ui.size = original_size
	click.position = Vector2(ui.size.x - 30, ui.size.y - 30)
	ui._gui_input(click)
	checks.check(not ui.visible and root.session.mode == &"exploration", "the source Back softkey in the window corner closes the party selector")
	root._demo_battle()
	for page in [Page.CHARACTER, Page.INVENTORY, Page.JOURNAL]: root._open_management(page)
	checks.check(not ui.visible and not root.management.visible and root.battle.active, "combat still blocks source character, inventory and journal")
	root._restart(false)
