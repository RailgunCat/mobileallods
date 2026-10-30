extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Fixtures = preload("res://tests/battle_checks.gd")
const Unit = preload("res://scripts/gameplay/unit_state.gd")
const Encounter = preload("res://scripts/gameplay/encounter_builder.gd")
const SpellVisuals = preload("res://scripts/gameplay/spell_presentation.gd")

func run(root, checks) -> void:
	_detour(root, checks)
	_blocked_approach(root, checks)
	_corpse_obstructions(root, checks)
	_enemy_magic(root, checks)
	_journal_notice(root, checks)
	_presentation(root, checks)

func place(game, actor, cell: Vector2i) -> void:
	game.collision.remove(actor.instance_id)
	actor.move_to(cell)
	actor.reset_interpolation()
	game.collision.occupy(actor.instance_id, cell, actor.footprint)

func _detour(root, checks) -> void:
	var pair: Array = Fixtures.new().fixture(root.world, root.metadata, root.table)
	var game = pair[0]
	var battle = pair[1]
	var enemy = game.units[2]
	place(game, game.hero, Vector2i(20, 12))
	place(game, game.party[1], Vector2i(19, 12))
	place(game, enemy, Vector2i(24, 12))
	for y in range(23): game.collision.terrain[y * game.collision.width + 22] = 1
	var source: Dictionary = Encounter.build(game, [enemy.instance_id])
	checks.check(not source["arena"].has_point(Vector2i(22, 23)), "regression wall detour lies outside the original camera-based arena")
	checks.check(battle.begin(game, [enemy.instance_id]) and battle.arena.has_point(Vector2i(22, 23)), "battle arena includes the real corridor around an intervening wall")
	battle.enemy_policy = &"combat"
	var before: Vector2i = enemy.cell
	battle.end_side()
	for tick in range(300):
		battle.advance(0.062)
		if battle.round_number > 1: break
	checks.check(enemy.cell != before and enemy.cell.y > before.y, "distant enemy walks toward the open detour instead of waiting behind the wall")
	checks.check(battle.events.any(func(event): return event["event"] == "command_started" and event.get("actor", -1) == enemy.instance_id and event.get("action", "") == "move"), "aggressive enemy actually executes a movement command")

func _blocked_approach(root, checks) -> void:
	var pair: Array = Fixtures.new().fixture(root.world, root.metadata, root.table)
	var game = pair[0]
	var battle = pair[1]
	var enemy = game.units[2]
	battle.begin(game, [enemy.instance_id])
	battle.arena = Rect2i(0, 0, game.collision.width, game.collision.height)
	game.collision.terrain.fill(1)
	for y in [10, 11]:
		for x in range(3, 26): game.collision.terrain[y * game.collision.width + x] = 0
	for actor in game.units: game.collision.remove(actor.instance_id)
	place(game, game.hero, Vector2i(5, 10))
	place(game, game.party[1], Vector2i(4, 10))
	place(game, enemy, Vector2i(20, 10))
	var obstruction := Unit.new()
	obstruction.configure({"instance_id": 5000, "unit_type": Ids.UnitKind.PEASANT, "story_group": 8, "spawn_flag": 0, "side_id": Ids.Side.HOSTILE}, root.metadata, root.table)
	game.units.append(obstruction)
	place(game, obstruction, Vector2i(10, 10))
	battle._start_side(Ids.Side.HOSTILE)
	var plan: Dictionary = battle._approach(enemy, game.hero, true)
	checks.check(not plan["reachable"] and not plan["path"].is_empty(), "occupied corridor has a valid partial approach but no complete attack path")
	battle._enemy_action(enemy)
	checks.check(not battle.queue.is_empty() and battle.queue[0]["action"] == "move", "blocked distant enemy advances along the reachable path instead of defending immediately")

func _corpse_obstructions(root, checks) -> void:
	for scenario in [{"friendly": false, "distant": false}, {"friendly": true, "distant": false}, {"friendly": true, "distant": true}]:
		var friendly_body: bool = scenario["friendly"]
		var pair: Array = Fixtures.new().fixture(root.world, root.metadata, root.table)
		var game = pair[0]
		var battle = pair[1]
		var enemy = game.units[2]
		battle.begin(game, [enemy.instance_id])
		battle.enemy_policy = &"combat"
		battle.arena = Rect2i(0, 0, game.collision.width, game.collision.height)
		game.collision.terrain.fill(1)
		for y in [10, 11]:
			for x in range(3, 24): game.collision.terrain[y * game.collision.width + x] = 0
		for actor in game.units: game.collision.remove(actor.instance_id)
		place(game, game.hero, Vector2i(5, 10))
		place(game, enemy, Vector2i(21 if scenario["distant"] else 12, 10))
		var body = game.party[1]
		body.side_id = Ids.Side.HOSTILE if friendly_body else Ids.Side.PARTY
		body.dead = true
		body.stats[Ids.Stat.HP] = 0
		place(game, body, Vector2i(11, 10))
		battle._start_side(Ids.Side.HOSTILE)
		checks.check(not battle.attack_plan(enemy, game.hero)["valid"], "corpse blocks the enemy's attack route")
		if scenario["distant"]:
			var start: Vector2i = enemy.cell
			battle._enemy_action(enemy)
			checks.check(not battle.queue.is_empty() and battle.queue[0]["action"] == "move", "distant enemy approaches the blocking corpse within its AP budget")
			for tick in range(200):
				battle.advance(0.062)
				if battle.current_side == Ids.Side.PARTY: break
			checks.check(enemy.cell.x < start.x and not body.shattered, "approaching a corpse moves the enemy without prematurely clearing collision")
			for turn in range(10):
				battle._start_side(Ids.Side.HOSTILE)
				battle._enemy_action(enemy)
				if not battle.queue.is_empty() and battle.queue[0]["action"] == "attack" and battle.queue[0].get("target", -1) == body.instance_id: break
				for tick in range(200):
					battle.advance(0.062)
					if battle.current_side == Ids.Side.PARTY: break
		if not battle.busy(): battle._enemy_action(enemy)
		checks.check(not battle.queue.is_empty() and battle.queue[0]["action"] == "attack" and battle.queue[0].get("target", -1) == body.instance_id, "enemy orders clearing attack on a blocking corpse (same side: %s)" % friendly_body)
		for tick in range(150):
			battle.advance(0.062)
			if battle.current_side == Ids.Side.PARTY: break
		checks.check(body.shattered and not game.collision.units.has(body.instance_id), "enemy clearing attack destroys the corpse and frees the corridor")
		battle._start_side(Ids.Side.HOSTILE)
		battle._enemy_action(enemy)
		checks.check(not battle.queue.is_empty() and battle.queue[0]["action"] in ["attack", "move"], "enemy resumes pursuit after clearing the corpse")
		battle.queue.clear()
		place(game, game.hero, enemy.cell + Vector2i.LEFT)
		body.shattered = false
		place(game, body, Vector2i(3, 10))
		battle._start_side(Ids.Side.HOSTILE)
		battle._enemy_action(enemy)
		checks.check(not battle.queue.is_empty() and battle.queue[0].get("target", -1) == game.hero.instance_id, "available living target takes priority over an unrelated corpse")

func _enemy_magic(root, checks) -> void:
	for kind in [Ids.UnitKind.SQUIRREL, Ids.UnitKind.SKELETON_MAGE, Ids.UnitKind.MAGE, Ids.UnitKind.DRAGON]:
		var pair: Array = Fixtures.new().fixture(root.world, root.metadata, root.table)
		var game = pair[0]
		var battle = pair[1]
		var enemy = game.units[2]
		enemy.configure({"instance_id": enemy.instance_id, "unit_type": kind, "story_group": Ids.StoryGroup.HOSTILES, "spawn_flag": enemy.spawn_flag, "side_id": Ids.Side.HOSTILE}, root.metadata, root.table)
		enemy.encounter_enabled = true
		place(game, game.hero, Vector2i(20, 20))
		place(game, game.party[1], Vector2i(19, 20))
		place(game, enemy, Vector2i(23, 20))
		battle.begin(game, [enemy.instance_id])
		battle._start_side(Ids.Side.HOSTILE)
		if kind == Ids.UnitKind.SQUIRREL:
			checks.check(enemy.stats[Ids.Stat.MANA] > 0 and not battle._magic_action(enemy), "noncaster has derived mana but cannot cast without a learned magic school")
			continue
		battle._enemy_action(enemy)
		var casting: bool = not battle.queue.is_empty() and battle.queue[0]["action"] == "cast"
		checks.check(casting, "natural monster stats select a spell for unit type %d" % kind)
		if not casting: continue
		var mana: int = enemy.stats[Ids.Stat.MANA]
		var spell: int = battle.queue[0]["spell"]
		var cost: int = battle.cast_plan(enemy, spell, battle.queue[0]["cell"])["cost"]
		Fixtures.new()._drain(battle, 150)
		checks.check(enemy.stats[Ids.Stat.MANA] == mana - cost and battle.events.any(func(event): return event["event"] == "spell_impact" and event.get("actor", -1) == enemy.instance_id), "monster spell reaches impact and consumes mana for unit type %d" % kind)

func _journal_notice(root, checks) -> void:
	root._restart(false)
	var notice = root.journal_notice
	notice.advance(0.0)
	checks.check(not notice.visible, "new game establishes journal baseline without a notification")
	root.session.quests[Ids.Quest.WAY_HOME] = Ids.QuestState.ACTIVE
	notice.advance(0.0)
	checks.check(notice.visible and notice.caption.text == "Журнал обновлён" and notice.mouse_filter == Control.MOUSE_FILTER_IGNORE, "new journal entry shows a nonblocking notification above the game")
	notice.advance(2.0)
	root.session.quests[Ids.Quest.WAY_HOME] = Ids.QuestState.COMPLETED
	notice.advance(0.0)
	checks.check(notice.remaining == notice.DURATION, "quest completion renews the journal notification")
	notice.advance(5.0)
	checks.check(not notice.visible, "journal notification expires without repeating for unchanged quests")
	root.session.quests[Ids.Quest.WAY_HOME] = Ids.QuestState.FAILED
	notice.configure(root.session)
	notice.advance(0.0)
	checks.check(not notice.visible, "restored quest states establish a silent baseline when loading")
	root._restart(false)

func _presentation(root, checks) -> void:
	root._demo_battle()
	root.battle_overlay.acknowledge()
	root._choose_action("move", -1)
	var cell: Vector2i = root.session.hero.cell + Vector2i.LEFT
	var point: Vector2 = root.view.cell_center(cell)
	var before: Dictionary = root.battle.snapshot()
	var state: Dictionary = root.cursors.resolve(root, point, true)
	root.view.set_movement_preview(state)
	checks.check(not root.view.movement_preview.is_empty() and root.view.movement_preview.back() == cell and not root.view.show_debug_markers, "normal movement mode previews green route dots without enabling debug")
	checks.check(root.battle.snapshot() == before, "hover route dots do not spend AP, move units or advance combat RNG")
	root.view.set_movement_preview({"kind": "default"})
	checks.check(root.view.movement_preview.is_empty(), "leaving the map or movement mode clears preview dots")
	var size: Vector2 = root.view.textures[199].get_size()
	var first: Array = SpellVisuals.fire_wall_strips(cell, 0.0, size)
	checks.check(first != SpellVisuals.fire_wall_strips(cell, 0.248, size), "firewall flames change shape over time instead of displaying a static texture")
	checks.check(SpellVisuals.fire_wall_sparks(cell, 0.0) != SpellVisuals.fire_wall_sparks(cell, 0.248), "firewall embers rise and expire over time")
	for fps in [30, 60, 144]:
		var clock: float = 0.0
		for frame in range(fps): clock += 1.0 / fps
		checks.check(SpellVisuals.fire_wall_strips(cell, clock, size) == SpellVisuals.fire_wall_strips(cell, 1.0, size), "fire animation agrees at equal elapsed time at %d FPS" % fps)
	checks.check(root.battle.snapshot() == before, "fire animation sampling leaves damage, hazard duration and RNG unchanged")
	root._restart(false)
