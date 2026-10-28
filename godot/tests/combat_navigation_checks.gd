extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Fixtures = preload("res://tests/battle_checks.gd")
const Unit = preload("res://scripts/gameplay/unit_state.gd")
const Encounter = preload("res://scripts/gameplay/encounter_builder.gd")
const SpellVisuals = preload("res://scripts/gameplay/spell_presentation.gd")

func run(root, checks) -> void:
	_detour(root, checks)
	_blocked_approach(root, checks)
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
