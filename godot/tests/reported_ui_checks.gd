extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Unit = preload("res://scripts/gameplay/unit_state.gd")
const Inventory = preload("res://scripts/gameplay/inventory_rules.gd")

func click(screen, logical_point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = screen.screen_origin + logical_point * screen.screen_scale
	screen._gui_input(event)

func enemy_fixture(root) -> Dictionary:
	root._demo_battle(true)
	root.battle_overlay.acknowledge()
	var bat = root.battle.unit(1004)
	var hermit = root.battle.unit(1001)
	root.session.collision.remove(bat.instance_id)
	for y in range(hermit.cell.y - 1, hermit.cell.y + 4):
		for x in range(hermit.cell.x - 4, hermit.cell.x + 4):
			root.session.collision.terrain[y * root.session.collision.width + x] = 0
	var bats: Array = [bat, Unit.new()]
	for index in range(bats.size()):
		var actor = bats[index]
		actor.configure({"instance_id": 1004 if index == 0 else 9002, "unit_type": Ids.UnitKind.BAT, "story_group": Ids.StoryGroup.HOSTILES, "spawn_flag": bat.spawn_flag, "side_id": Ids.Side.HOSTILE}, root.metadata, root.table)
		actor.encounter_enabled = true
		# Isolate physical AI attacks on the nearby bearded hermit.
		for skill in range(Ids.Stat.LIGHT_FIRE_MAGIC, Ids.Stat.RESERVED): actor.base_stats[skill] = 0
		actor.recalculate(root.table)
		actor.move_to(hermit.cell + Vector2i(0 if index == 0 else -3, 1))
		actor.reset_interpolation()
		root.session.collision.occupy(actor.instance_id, actor.cell, actor.footprint)
		if index > 0:
			root.session.units.append(actor)
			root.battle.participants.append(actor.instance_id)
			root.battle.state[actor.instance_id] = root.battle.state[bat.instance_id].duplicate(true)
	root.battle.enemy_policy = &"combat"
	root._refresh_battle()
	return {"bat": bat, "hermit": hermit}

func enemy_hit(root) -> bool:
	for tick in range(250):
		root._process(0.062)
		if not root.battle.feedback.is_empty(): return true
	return false

func run(root, checks) -> void:
	_enemy_turn(root, checks)
	_shop_mouse(root, checks)
	_tavern_return(root, checks)
	_journal(root, checks)
	root._restart(false)

func _enemy_turn(root, checks) -> void:
	var original_hd: bool = root.preferences.values["hd_icons"]
	var fixture: Dictionary = enemy_fixture(root)
	root.preferences.update("hd_icons", true, false)
	checks.check(root.battle.end_side(), "portrait fixture ends the party turn through the real command queue")
	for tick in range(100):
		root._process(0.062)
		if root.battle.current_side == Ids.Side.HOSTILE: break
	checks.check(root.battle.current_side == Ids.Side.HOSTILE and root.view.battle_hud_actor().unit_type == Ids.UnitKind.BAT, "enemy turn initially shows the acting bat")
	var hit: bool = enemy_hit(root)
	checks.check(hit and int(root.battle.feedback["target"]) == fixture["hermit"].instance_id, "actual enemy AI hits the bearded hermit")
	checks.check(root.battle.current_side == Ids.Side.HOSTILE, "second bat keeps the enemy side active after the first impact")
	var focused = root.view.battle_hud_actor()
	checks.check(focused != null and focused.unit_type == Ids.UnitKind.BAT, "enemy hit feedback must not replace the acting bat portrait with the bearded victim")
	checks.check(root.view.actor_portrait_texture(focused) == root.ui_icons.portraits[212], "enemy-turn HUD draws the bat HD texture after a real hit")
	root.preferences.update("hd_icons", false, false)
	checks.check(root.view.battle_hud_actor() == focused, "HD toggle does not change which enemy is displayed")
	root.preferences.update("hd_icons", true, false)
	for tick in range(250):
		root._process(0.062)
		if root.battle.current_side == Ids.Side.PARTY: break
	checks.check(root.battle.current_side == Ids.Side.PARTY and root.view.battle_hud_actor() in root.session.party, "portrait returns to a party member on the next player turn")
	root.preferences.update("hd_icons", original_hd, false)
	root._restart(false)

func town_fixture(root) -> void:
	root._restart(false)
	root.session.quests[Ids.Quest.CITY_CERTIFICATE] = Ids.QuestState.COMPLETED
	root.session.tutorial_seen[Ids.Tutorial.TOWN] = 1
	root._show_world(false)
	root.world_panel.show_town()

func _shop_mouse(root, checks) -> void:
	town_fixture(root)
	root.session.gold = 10000
	root._open_town_shop()
	root.shop.confirm()
	var original_size: Vector2 = root.shop.size
	for dimensions: Vector2 in [Vector2(1280, 800), Vector2(960, 1280)]:
		root.shop.size = dimensions
		root.shop._position_regions()
		root.shop.confirm()
		var gold: int = root.session.gold
		var before: int = root.session.inventory.size()
		click(root.shop, Vector2(160, 260))
		checks.check(root.shop.screen == &"items" and root.session.gold == gold and root.session.inventory.size() == before, "visible shop Back label cancels a purchase at " + str(dimensions))
		if root.shop.screen == &"confirm": root.shop.back()
		root.shop.confirm()
		var price: int = Inventory.price(root.session, root.shop.candidates[root.shop.selected])
		click(root.shop, Vector2(80, 260))
		checks.check(root.shop.screen == &"items" and root.session.gold == gold - price and root.session.inventory.size() == before + 1, "visible shop Yes label buys once at " + str(dimensions))
		if root.shop.screen == &"confirm": root.shop.back()
	root.shop.size = original_size
	root.shop.back()
	root.shop.selected = 1
	root.shop.confirm()
	root.shop.confirm()
	var count: int = root.session.inventory.size()
	click(root.shop, Vector2(80, 260))
	checks.check(root.shop.screen == &"items" and root.session.inventory.size() == count - 1, "visible Yes label also confirms selling")
	root._restart(false)

func _tavern_return(root, checks) -> void:
	town_fixture(root)
	root.world_panel.show_tavern()
	click(root.world_panel, Vector2(130, 110))
	checks.check(root.world_panel.screen == &"body" and root.session.quests[15] == Ids.QuestState.ACTIVE, "clicking Work opens the actual quest offer")
	var rumour: int = root.session.last_rumour
	var world_rng: Dictionary = root.session.world_rng.snapshot()
	click(root.world_panel, Vector2(50, 305))
	checks.check(root.world_panel.screen == &"body" and root.world_panel.body_page == 1, "mouse confirm advances the tavern reply and its speaker")
	while root.world_panel.screen == &"body": click(root.world_panel, Vector2(50, 305))
	checks.check(root.world_panel.screen == &"tavern" and root.world_panel.town_selected == 1, "acknowledging Work with the mouse returns to tavern choices with Work selected")
	checks.check(root.session.last_rumour == rumour and root.session.world_rng.snapshot() == world_rng, "acknowledging a job never generates a rumour or consumes its RNG")
	root.world_panel.show_tavern()
	root.world_panel.town_selected = 1
	root.world_panel.confirm()
	root.world_panel.back()
	checks.check(root.world_panel.screen == &"tavern" and root.world_panel.town_selected == 1, "Escape from a job message returns to tavern choices")
	root.world_panel.show_tavern()
	root.world_panel.town_selected = 1
	root.world_panel.confirm()
	root.world_panel.confirm()
	checks.check(root.world_panel.screen == &"tavern" and root.world_panel.town_selected == 1, "Enter from a job message returns to tavern choices")

func _journal(root, checks) -> void:
	root._restart(false)
	root.session.quests.fill(Ids.QuestState.NOT_STARTED)
	var rows: Array = root.campaign_data["quests"]
	var ids: Array = []
	for index in range(4):
		var id: int = int(rows[index]["id"])
		ids.append(id)
		root.session.quests[id] = [Ids.QuestState.COMPLETED, Ids.QuestState.ACTIVE, Ids.QuestState.COMPLETED, Ids.QuestState.FAILED][index]
	root._open_management(Ids.ManagementPage.JOURNAL)
	var journal = root.legacy_management
	checks.check(journal.quests.map(func(quest): return int(quest["id"])) == [ids[1], ids[3], ids[0], ids[2]], "journal places completed quests last and preserves source order within each group")
	journal.selected = 0
	journal.confirm()
	checks.check(int(journal.quests[journal.selected]["id"]) == ids[1] and journal.screen == &"quest", "first sorted journal entry opens the active quest")
	journal.back()
	click(journal, Vector2(100, 183))
	checks.check(journal.screen == &"quest" and int(journal.quests[journal.selected]["id"]) == ids[2], "completed quest at the bottom still opens through its visible mouse row")
