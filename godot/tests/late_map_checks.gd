extends RefCounted
const Session = preload("res://scripts/gameplay/game_session.gd")
const Story = preload("res://scripts/gameplay/campaign_runner.gd")
const WorldPanel = preload("res://scripts/gameplay/world_map_panel.gd")
const CampaignChecks = preload("res://tests/campaign_checks.gd")
const Ids = preload("res://scripts/gameplay/game_ids.gd")

func run(root, checks) -> void:
	# Source state after the first council mage: the next job is available,
	# but its destination must stay hidden until the player takes it in town.
	var game := Session.new()
	game.start(root.world, root.metadata, root.table, root.rewards)
	game.quests[Ids.Quest.CITY_CERTIFICATE] = Ids.QuestState.COMPLETED
	game.quests[12] = Ids.QuestState.COMPLETED
	for flag in range(159, 163): game.triggers[flag] = Ids.TriggerState.DISABLED
	game.triggers[163] = Ids.TriggerState.ENABLED
	for index in range(7): game.flags["e"][index] = 1
	game.travel(5, 1)
	var panel := WorldPanel.new()
	root.add_child(panel)
	panel.open(game, root.campaign_data, root.view.textures)
	for index in range(7, 10):
		checks.check(panel.buttons[index].disabled, "unaccepted map %d job keeps its world point locked" % index)
	var destinations: Array = []
	panel.destination_chosen.connect(func(map_id: int, entry_id: int): destinations.append([map_id, entry_id]))
	var story := Story.new()
	for index in range(7, 10):
		panel.show_town(true)
		panel.show_tavern(true)
		panel.take_quest()
		checks.check(int(game.flags["e"][index]) == 1, "tavern job unlocks map %d" % index)
		if index < 9: checks.check(int(game.flags["e"][index + 1]) == 0, "map %d job preserves later locks" % index)
		panel.show_world()
		checks.check(not panel.buttons[index].disabled, "map %d becomes selectable after taking its job" % index)
		checks.check(panel.selected == index, "returning from the tavern highlights newly unlocked map %d" % index)
		panel.buttons[index].pressed.emit()
		panel.confirm()
		checks.check(not destinations.is_empty() and destinations.back() == [index - 1, 0], "map %d UI emits its original destination and entry" % index)
		checks.check(game.travel(index - 1, 0) and str(game.map["name"]) == str(index), "map %d loads its own geometry and scene" % index)
		story.configure(game, root.world, root.campaign_data)
		if index == 8:
			# The steel quest completes at the weapon chest in dungeon eight,
			# not by killing the guards on the surface.
			game.dungeon_seeds[7] = 20261027
			checks.check(game.travel(-8, 0), "map eight dungeon loads")
			story.configure(game, root.world, root.campaign_data)
			var chest: Dictionary = {}
			for pickup: Dictionary in game.pickups():
				if int(pickup["script_id"]) == 116: chest = pickup
			checks.check(not chest.is_empty(), "map eight dungeon contains the steel quest chest")
			if chest.is_empty(): break
			game.hero.set_pixel_position(Vector2(chest["position_pixels"][0], chest["position_pixels"][1]))
			var receipt: Dictionary = game.collect_nearby()
			checks.check(int(receipt.get("script_id", -1)) == 116, "collecting the real chest requests original completion script 116")
			checks.check(story.start_script(116) and CampaignChecks.new().settle(story), "steel quest completion runs without a fault")
		else:
			var completion: int = 107 if index == 7 else 120
			checks.check(story.start_script(completion) and CampaignChecks.new().settle(story), "map %d mage completion runs without a fault" % index)
		var quest: int = 17 if index == 7 else 13 if index == 8 else 18
		checks.check(int(game.quests[quest]) == Ids.QuestState.COMPLETED and int(game.triggers[164 + index - 7]) == Ids.TriggerState.ENABLED, "map %d completion enables the next tavern job" % index)
	# A save made after accepting work must also focus its unlocked destination.
	game.travel(5, 0)
	game.quests[17] = Ids.QuestState.ACTIVE
	game.quests[13] = Ids.QuestState.NOT_STARTED
	game.quests[18] = Ids.QuestState.NOT_STARTED
	game.flags["e"][8] = 0
	game.flags["e"][9] = 0
	panel.open(game, root.campaign_data, root.view.textures)
	checks.check(panel.selected == 7 and not panel.buttons[7].disabled, "an accepted map-seven job is highlighted when reopening the world map")
	game.quests[17] = Ids.QuestState.COMPLETED
	panel.open(game, root.campaign_data, root.view.textures)
	checks.check(panel.selected == 6, "completed jobs do not redirect the map from the current location")
	panel.free()
