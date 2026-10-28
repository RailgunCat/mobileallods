extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")


func run(root, checks) -> void:
	# Continue from the natural opening episode after the troll victory.
	var hero = root.session.hero
	var ally = root.session.party[1]
	var gold: int = root.session.gold
	root.session.dungeon_seeds[0] = 20261027
	# The original doorway is off grid: its physical center is x=352, while
	# 16px path cells center at 344/360. Approach, then use checked pixel movement.
	var approached: bool = root._walk_story_to(Vector2(344, 72))
	root.held_keys[KEY_D] = true
	root._process(0.124)
	root.held_keys.clear()
	root.held_keys[KEY_W] = true
	for tick in range(12):
		root._process(0.062)
		if root.session.location_id == -1: break
	root.held_keys.clear()
	checks.check(approached and root.session.location_id == -1, "normal opening story walks into original dungeon transition")
	checks.check(root.session.hero == hero and root.session.party[1] == ally and root.session.gold == gold and root.view.current_map.get("dungeon", false), "story transition updates rendered map and retains party and gold")
	checks.check(root.route.is_empty() and root.held_keys.is_empty() and not root.battle.active, "transition clears old movement and combat input")
	# The back stairs are immediately south of the entry; use the real pixel motor.
	root.held_keys[KEY_S] = true
	for tick in range(20):
		root._process(0.062)
		if root.session.location_id == 0: break
	root.held_keys.clear()
	checks.check(root.session.location_id == 0 and root.session.party[1] == ally and root.session.gold == gold, "walking down dungeon stairs returns to original map entry without state reset")
	# Finish any original one-time tutorial on the return route.
	for i in range(100):
		if not root.campaign.busy(): break
		if not root.campaign.modal.is_empty(): root.campaign.acknowledge()
		else: root._process(0.062)
	root._show_world(false)
	checks.check(not root.world_panel.visible and root.session.mode == &"exploration", "world map stays locked before Kurt certificate")
	# Explicit unlocked fixture for the remaining world/town UI checks.
	root.session.quests[Ids.Quest.CITY_CERTIFICATE] = Ids.QuestState.COMPLETED
	root.session.tutorial_seen[Ids.Tutorial.TOWN] = 1
	root._show_world(false)
	checks.check(root.world_panel.visible and root.session.mode == &"world_map" and root.world_panel.buttons[3].disabled, "world map displays source locked destinations")
	var before: Vector2 = root.session.hero.position_pixels
	root._process(5)
	checks.check(root.session.hero.position_pixels == before, "world map pauses exploration")
	root.world_panel.buttons[2].pressed.emit()
	root.world_panel.confirm()
	checks.check(root.session.location_id == 1 and not root.world_panel.visible and root.session.party[1] == ally and not root.view.current_map.get("dungeon", false), "world-map choice loads second location with retained companion")
	# World-map entry may immediately start its source story; settle its pages.
	for i in range(300):
		if not root.campaign.busy(): break
		if not root.campaign.modal.is_empty(): root.campaign.acknowledge()
		else: root._process(0.062)
	root._show_world(false)
	root.world_panel.buttons[0].pressed.emit()
	root.world_panel.confirm()
	checks.check(root.session.mode == &"town" and root.world_panel.in_town, "city destination opens actual town menu")
	root.world_panel.take_quest()
	checks.check(int(root.session.flags["e"][3]) == 1 and int(root.session.quests[15]) == Ids.QuestState.ACTIVE, "tavern UI grants source job and unlocks next world destination")
	root.world_panel.show_world()
	checks.check(not root.world_panel.buttons[3].disabled, "newly unlocked destination becomes available on map")
	root.world_panel.dismiss()
	# Use the forward stairs physically, then alternate keyboard and mouse input.
	root._travel(-1, 1)
	for npc in root.session.units: npc.encounter_enabled = false
	root.held_keys[KEY_W] = true
	for tick in range(60):
		root._process(0.062)
		if root.session.location_id == 1: break
	root.held_keys.clear()
	checks.check(root.session.location_id == 1 and root.session.party[1] == ally, "walking up the forward dungeon stairs reaches map two with the same companion")
	for i in range(300):
		if not root.campaign.busy(): break
		if not root.campaign.modal.is_empty(): root.campaign.acknowledge()
		else: root._process(0.062)
	checks.check(root.campaign.fault.is_empty() and root.session.mode == &"exploration", "second-map entrance settles to exploration without a script fault")
	for npc in root.session.units: npc.encounter_enabled = false
	root.campaign.enabled = false
	root.held_keys[KEY_D] = true
	root._process(2.48)
	root.held_keys.clear()
	checks.check(ally.position_pixels == Vector2(576, 448) and hero.position_pixels == Vector2(616, 448), "keyboard movement after dungeon exit retains the source 40px follower delay")
	var follower_before: Vector2 = ally.position_pixels
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = root.view.cell_center(Vector2i(35, 30))
	root.view._gui_input(click)
	root.view._gui_input(click)
	root._process(5)
	checks.check(ally.position_pixels != follower_before and hero.position_pixels.distance_to(ally.position_pixels) <= 48, "mouse movement after keyboard movement keeps companion following on map two: hero=%s ally=%s" % [hero.position_pixels, ally.position_pixels])
