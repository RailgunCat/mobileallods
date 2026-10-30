extends RefCounted
const Session = preload("res://scripts/gameplay/game_session.gd")
const Controller = preload("res://scripts/gameplay/exploration_controller.gd")
const Battle = preload("res://scripts/gameplay/battle_controller.gd")
const Ids = preload("res://scripts/gameplay/game_ids.gd")


func fixture(world, metadata, table, rewards):
	var game := Session.new()
	game.start(world, metadata, table, rewards)
	game.travel(4, 1)
	game.hero.set_pixel_position(Vector2(140, 684))
	game.collision.occupy(game.hero.instance_id, game.hero.cell, game.hero.footprint)
	# The orc in the user's screenshot has already died in the preceding fight.
	for actor in game.units:
		if actor.instance_id == 5001:
			actor.dead = true
			actor.stats[Ids.Stat.HP] = 0
			actor.set_pixel_position(Vector2(224, 688))
			game.collision.remove(actor.instance_id)
	return game


func run(checks, world, metadata, table, rewards) -> void:
	for troll_id in [5017, 5018]:
		var game = fixture(world, metadata, table, rewards)
		var motor := Controller.new()
		motor.configure(game)
		var troll
		for actor in game.units:
			if actor.instance_id == troll_id: troll = actor
		var terrain: PackedByteArray = game.collision.terrain.duplicate()
		var position: Vector2 = game.hero.position_pixels
		var plan: Dictionary = motor.preview(troll.cell)
		checks.check(not plan["path"].is_empty() and not plan.get("pixel_path", []).is_empty(), "map five finds a physical approach to troll %d from the reported off-center position" % troll_id)
		if plan["path"].is_empty(): continue
		checks.check(game.hero.position_pixels == position and game.collision.terrain == terrain, "map five preview preserves the hero and source terrain")
		var safe: bool = true
		for point: Vector2 in plan["pixel_path"]:
			var delta: Vector2 = point - position
			var facing: int = (0 if delta.x < 0 else 1) if delta.x != 0 else (2 if delta.y < 0 else 3)
			safe = safe and absf(delta.x) + absf(delta.y) <= 4 and (delta.x == 0 or delta.y == 0) and game.can_move_pixels(game.hero, point, facing)
			position = point
		checks.check(safe, "map five fallback uses checked cardinal steps without crossing trees or living NPCs")
		var battle := Battle.new()
		var begin_battle := func(ids: Array[int]):
			if troll_id in ids and not battle.active:
				motor.stop()
				battle.begin(game, ids)
		motor.encounter_detected.connect(begin_battle)
		motor.start_route(plan["path"], plan.get("pixel_path", []))
		for tick in range(2000):
			if battle.active or not motor.following_route: break
			motor.advance(0.062)
		checks.check(battle.active and troll_id in battle.participants, "map five real movement enters the sight radius and starts troll %d's battle" % troll_id)
		checks.check(game.collision.terrain == terrain, "approaching the map-five troll never edits collision masks")
		motor.encounter_detected.disconnect(begin_battle)
	_ground_and_barrier(checks, world, metadata, table, rewards)


func _ground_and_barrier(checks, world, metadata, table, rewards) -> void:
	var game = fixture(world, metadata, table, rewards)
	var motor := Controller.new()
	motor.configure(game)
	var plan: Dictionary = motor.preview(Vector2i(2, 51))
	checks.check(plan["reachable"] and not plan["path"].is_empty(), "map five reaches free ground through off-center passages")
	motor.start_route(plan["path"], plan.get("pixel_path", []))
	for tick in range(2000):
		if not motor.following_route: break
		motor.advance(0.062)
	checks.check(not motor.following_route and motor.route.is_empty() and game.hero.position_pixels == Vector2(40, 824), "pixel route completes at the requested center and clears its preview")
	game = fixture(world, metadata, table, rewards)
	# A complete wall is an actual barrier, including on the finer lattice.
	for x in range(game.collision.width): game.collision.terrain[46 * game.collision.width + x] = 1
	motor.configure(game)
	plan = motor.preview(Vector2i(2, 51))
	checks.check(not plan["reachable"], "fine exploration search does not cross an impassable wall")
	var safe: bool = true
	for point: Vector2 in plan.get("pixel_path", []): safe = safe and point.y < 46 * 16 - game.hero.collision_half_extents.y
	checks.check(safe, "fallback for an unreachable goal remains on the original side of the wall")
	plan = motor.preview(Vector2i(-1, 51))
	checks.check(plan["path"].is_empty() and not plan["reachable"], "fine exploration search rejects targets outside the map")
