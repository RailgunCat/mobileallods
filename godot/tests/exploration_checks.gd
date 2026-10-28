extends RefCounted

const Session = preload("res://scripts/gameplay/game_session.gd")
const Controller = preload("res://scripts/gameplay/exploration_controller.gd")


func _fixture(world: Dictionary, metadata: Dictionary, table: Dictionary, point := Vector2(400, 160), map: Dictionary = {}) -> Array:
	var data: Dictionary = metadata.duplicate(true)
	data["map_1_entries"][0]["position_pixels"] = [point.x, point.y]
	if map.is_empty():
		map = _empty_map()
	var fixture_world := {"maps": [map], "constants": world["constants"], "scenes": [{"units": [[2, 56, 216, 1, 1, 0, 10000, 10000, 10000]]}]}
	var session := Session.new()
	if not session.start(fixture_world, data, table):
		push_error("Exploration fixture could not start")
	var controller := Controller.new()
	controller.configure(session)
	return [session, controller]


func _empty_map() -> Dictionary:
	var rows: Array = []
	for y in range(38):
		var row: Array = []
		row.resize(38)
		row.fill(0)
		rows.append(row)
	return {"name": "1", "width": 38, "height": 38, "source_tile_ids": rows}


func run(checks, world: Dictionary, metadata: Dictionary, table: Dictionary) -> void:
	var initial := Session.new()
	checks.check(initial.start(world, metadata, table), "exploration starts with source spawns")
	checks.check(initial.units.size() == 7 and initial.render_records().size() == 5, "6 source NPC records, only 4 NPCs initially visible")
	checks.check(not initial.is_active(initial.units[3]) and not initial.is_active(initial.units[4]), "archer and bat are initially hidden")
	checks.check(not initial.collision.units.has(1002) and not initial.collision.units.has(1003), "hidden NPCs do not obstruct")
	checks.check(initial.collision.units.has(1000) and initial.collision.units[1000].size == Vector2i(3, 3), "active dragon keeps 3x3 occupancy")
	initial.set_spawn_state(0, 1)
	checks.check(initial.render_records().size() == 2 and not initial.collision.units.has(1000) and not initial.collision.units.has(1004), "shared spawn flag hides all matching units and clears occupancy")
	initial.set_spawn_state(0, 0)
	checks.check(initial.render_records().size() == 5 and initial.collision.units.has(1004), "spawn flag reactivation restores occupancy")
	var ally = initial.add_demo_companion()
	checks.check(ally != null and initial.party.size() == 2 and initial.demo_party, "explicit party fixture adds recovered archer")
	checks.check(initial.render_records().size() == 6 and initial.party[1].instance_id == 1002, "fixture reuses archer identity and leaves bat hidden")
	_pixel_reference(checks, world, metadata, table)
	var fixture := _fixture(world, metadata, table)
	var game = fixture[0]
	var motor = fixture[1]
	var start: Vector2 = game.hero.position_pixels
	motor.set_direction(Vector2i.LEFT)
	motor.advance(0.061)
	checks.check(game.hero.position_pixels == start, "no simulation step before 62ms")
	motor.advance(0.001)
	checks.check(game.hero.position_pixels == start + Vector2(-4, 0) and motor.tick_count == 1, "source speed: 4 pixels per 62ms")
	motor.advance(0.031)
	var interpolated: Array = game.render_records(motor.alpha())[0]
	checks.check(is_equal_approx(float(interpolated[1]), start.x - 2.0) and game.hero.position_pixels.x == start.x - 4, "render interpolation does not mutate simulation")
	motor.advance(0.031)
	checks.check(game.hero.animation_frame == 1 and game.hero.walking, "source two-tick walk frame duration")
	motor.advance(0.062)
	var stopped: Vector2 = game.hero.position_pixels
	checks.check(stopped != Vector2(game.hero.cell) * 16 + Vector2.ONE * 8, "stop fixture is between cell centers")
	motor.stop()
	motor.advance(0.062)
	checks.check(game.hero.position_pixels == stopped and not game.hero.walking and game.hero.animation_frame == 0, "stop retains subcell position and restores idle")
	checks.check(not game.can_move_pixels(game.hero, Vector2(22, 60), 0) and game.can_move_pixels(game.hero, Vector2(23, 60), 0), "sprite origin constrains left map boundary")
	checks.check(not game.can_move_pixels(game.hero, Vector2(591, 60), 0) and game.can_move_pixels(game.hero, Vector2(590, 60), 0), "sprite extent constrains right map boundary")
	var baseline: Dictionary = {}
	for fps in [30, 60, 144]:
		fixture = _fixture(world, metadata, table)
		game = fixture[0]
		motor = fixture[1]
		game.add_demo_companion()
		motor.configure(game)
		motor.set_direction(Vector2i.LEFT)
		for frame in range(fps * 2):
			motor.advance(1.0 / fps)
		var state := {"hero": game.hero.snapshot(), "ally": game.party[1].snapshot(), "ticks": motor.tick_count, "commands": game.commands}
		if baseline.is_empty(): baseline = state
		checks.check(state == baseline and motor.tick_count == 32, "same simulation and animation at %d FPS" % fps)
		checks.check(game.party[1].position_pixels.x - game.hero.position_pixels.x == 40, "follower retains 10-tick / 40px delay at %d FPS" % fps)
	var map := _empty_map()
	map["source_tile_ids"][7][10] = 42
	fixture = _fixture(world, metadata, table, Vector2(128, 112), map)
	game = fixture[0]
	motor = fixture[1]
	checks.check(game.can_move_pixels(game.hero, Vector2(148, 112), 1) and not game.can_move_pixels(game.hero, Vector2(150, 112), 1), "inclusive 20px collision box reaches neighboring cell")
	motor.set_direction(Vector2i.RIGHT)
	motor.advance(1.0)
	checks.check(game.hero.position_pixels.x == 148 and not game.hero.walking, "keyboard stops at hidden blocker without tunneling")
	checks.check(not game.move_pixels(game.hero, Vector2(40, 0)) and not game.move_pixels(game.hero, Vector2(1, 1)), "pixel commands reject teleports and diagonals")
	_corner_follow(checks, world, metadata, table)
	_split_follow(checks, world, metadata, table)
	_recovery_variants(checks, world, metadata, table)
	_source_rock_follow(checks, world, metadata, table)


func _split_fixture(world: Dictionary, metadata: Dictionary, table: Dictionary) -> Array:
	var map := _empty_map()
	for y in range(11, 14):
		for x in range(18, 20): map["source_tile_ids"][y][x] = 42
	var fixture := _fixture(world, metadata, table, Vector2(320, 240), map)
	var game = fixture[0]
	var motor = fixture[1]
	var follower = game.add_demo_companion()
	follower.set_pixel_position(Vector2(280, 160))
	follower.reset_interpolation()
	game.collision.occupy(follower.instance_id, follower.cell, follower.footprint)
	motor.configure(game)
	return fixture


func _split_follow(checks, world: Dictionary, metadata: Dictionary, table: Dictionary) -> void:
	var fixture := _split_fixture(world, metadata, table)
	var game = fixture[0]
	var motor = fixture[1]
	var follower = game.party[1]
	var safe: bool = true
	var start: Vector2 = follower.position_pixels
	motor.set_direction(Vector2i.DOWN)
	for tick in range(20):
		motor.advance(0.062)
		safe = safe and game.can_move_pixels(follower, follower.position_pixels, follower.facing)
	motor.stop()
	for tick in range(100):
		motor.advance(0.062)
		safe = safe and game.can_move_pixels(follower, follower.position_pixels, follower.facing)
	checks.check(safe and game.hero.position_pixels == Vector2(320, 320), "split-party fixture keeps both bodies outside the rock")
	checks.check(follower.position_pixels != start and follower.position_pixels.x == 320 and follower.position_pixels.y >= 280, "follower reconnects around a rock after party positions are reseeded")


func _recovery_variants(checks, world: Dictionary, metadata: Dictionary, table: Dictionary) -> void:
	var short_fixture := _split_fixture(world, metadata, table)
	var short_game = short_fixture[0]
	var short_motor = short_fixture[1]
	short_motor.set_direction(Vector2i.DOWN)
	for tick in range(3): short_motor.advance(0.062)
	short_motor.stop()
	for tick in range(100): short_motor.advance(0.062)
	var short_follower = short_game.party[1]
	var gap: Vector2 = short_game.hero.position_pixels - short_follower.position_pixels
	checks.check(short_follower.position_pixels.y >= 234 and short_game.can_move_pixels(short_follower, short_follower.position_pixels, short_follower.facing) and absf(gap.x) + absf(gap.y) == 40, "follower recovers and retains spacing when the leader stops after only three steps")
	var baseline: Dictionary = {}
	for fps in [30, 60, 144]:
		var fixture := _split_fixture(world, metadata, table)
		var game = fixture[0]
		var motor = fixture[1]
		motor.set_direction(Vector2i.DOWN)
		for frame in range(fps): motor.advance(1.0 / fps)
		motor.stop()
		for frame in range(fps * 4): motor.advance(1.0 / fps)
		var state := {"leader": game.hero.position_pixels, "follower": game.party[1].position_pixels, "trail": motor.snapshot()["trails"]}
		if baseline.is_empty(): baseline = state
		checks.check(state == baseline and game.party[1].position_pixels.x == 320 and game.party[1].position_pixels.y > 240, "follower recovery agrees at %d FPS" % fps)
	var fixture := _split_fixture(world, metadata, table)
	var game = fixture[0]
	var motor = fixture[1]
	var third = preload("res://scripts/gameplay/unit_state.gd").new()
	third.configure({"instance_id": 3000, "unit_type": 1, "story_group": 1, "spawn_flag": 0, "side_id": 0}, metadata, table)
	third.set_pixel_position(Vector2(240, 160))
	game.units.append(third)
	game.party.append(third)
	game.collision.occupy(third.instance_id, third.cell, third.footprint)
	motor.configure(game)
	motor.set_direction(Vector2i.DOWN)
	for tick in range(20): motor.advance(0.062)
	motor.stop()
	var saved: Dictionary = motor.snapshot()
	checks.check(not saved["trails"][str(game.party[1].instance_id)]["pending"].is_empty(), "mid-detour snapshot retains the recovery waypoints")
	# Reconfigure as loading does: positions and the existing trail format are
	# enough to resume the recovery; no transient pathfinder state is needed.
	var restored := Controller.new()
	restored.configure(game)
	restored.restore_trails(saved)
	checks.check(restored.snapshot() == saved, "loading restores an in-progress follower detour exactly")
	var safe: bool = true
	for tick in range(140):
		restored.advance(0.062)
		for actor in game.party: safe = safe and game.can_move_pixels(actor, actor.position_pixels, actor.facing)
	var spacing: Vector2 = game.party[1].position_pixels - third.position_pixels
	var trail_gap: float = absf(spacing.x) + absf(spacing.y)
	# Rejoining a rounded synthetic point can include a final 1..3-pixel step.
	checks.check(safe and game.party[1].position_pixels.x == 320 and third.position_pixels.y >= 240 and trail_gap >= 36 and trail_gap <= 40, "all three party members safely reconnect and retain trail spacing after restoring a detour")
	fixture = _split_fixture(world, metadata, table)
	game = fixture[0]
	motor = fixture[1]
	for x in range(game.collision.width): game.collision.terrain[11 * game.collision.width + x] = 1
	motor.set_direction(Vector2i.DOWN)
	for tick in range(20): motor.advance(0.062)
	motor.stop()
	checks.check(game.party[1].position_pixels.y < 166 and game.can_move_pixels(game.party[1], game.party[1].position_pixels, game.party[1].facing), "an impassable barrier makes the follower wait safely without teleporting")
	for x in range(game.collision.width): game.collision.terrain[11 * game.collision.width + x] = 0
	for tick in range(140): motor.advance(0.062)
	checks.check(game.party[1].position_pixels.x == 320 and game.party[1].position_pixels.y >= 280, "follower recovers after a temporary barrier is removed")


func _source_rock_follow(checks, world: Dictionary, metadata: Dictionary, table: Dictionary) -> void:
	var map: Dictionary = {}
	for candidate: Dictionary in world["maps"]:
		if str(candidate["name"]) == "1": map = candidate
	# Source image 44 at (25, 19), with the leader south of the rock and
	# follower northwest, matching the supplied screenshot's arrangement.
	var fixture := _fixture(world, metadata, table, Vector2(420, 360), map)
	var game = fixture[0]
	var motor = fixture[1]
	var follower = game.add_demo_companion()
	follower.set_pixel_position(Vector2(384, 288))
	follower.reset_interpolation()
	game.collision.occupy(follower.instance_id, follower.cell, follower.footprint)
	motor.configure(game)
	var safe: bool = game.can_move_pixels(follower, follower.position_pixels, follower.facing)
	motor.set_direction(Vector2i.DOWN)
	for tick in range(20):
		motor.advance(0.062)
		safe = safe and game.can_move_pixels(follower, follower.position_pixels, follower.facing)
	motor.stop()
	for tick in range(120):
		motor.advance(0.062)
		safe = safe and game.can_move_pixels(follower, follower.position_pixels, follower.facing)
	checks.check(safe and follower.position_pixels.x == 420 and follower.position_pixels.y >= 400, "follower recovers around the original map-one rock without entering its source collision mask")


func _pixel_reference(checks, world: Dictionary, metadata: Dictionary, table: Dictionary) -> void:
	var map: Dictionary = {}
	for candidate: Dictionary in world["maps"]:
		if str(candidate["name"]) == "1": map = candidate
	var game = _fixture(world, metadata, table, Vector2(544, 384), map)[0]
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/legacy/gameplay_reference.json"))["exploration_map1"]
	var samples := PackedByteArray()
	for direction in range(4):
		for y in range(0, game.collision.height * 16, int(reference["sample_step"])):
			for x in range(0, game.collision.width * 16, int(reference["sample_step"])):
				samples.append(1 if game.can_move_pixels(game.hero, Vector2(x, y), direction) else 0)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(samples)
	checks.check(hash.finish().hex_encode() == reference["sha256"], "23,104 pixel poses match original Java collision in 4 directions")


func _corner_follow(checks, world: Dictionary, metadata: Dictionary, table: Dictionary) -> void:
	var map := _empty_map()
	for y in range(6, 13):
		for x in range(11, 19):
			map["source_tile_ids"][y][x] = 42
	var fixture := _fixture(world, metadata, table, Vector2(320, 224), map)
	var game = fixture[0]
	var motor = fixture[1]
	game.add_demo_companion()
	motor.configure(game)
	var safe: bool = true
	motor.set_direction(Vector2i.LEFT)
	for i in range(40):
		motor.advance(0.062)
		for actor in game.party:
			safe = safe and game.can_move_pixels(actor, actor.position_pixels, actor.facing)
	motor.set_direction(Vector2i.UP)
	for i in range(24):
		motor.advance(0.062)
		for actor in game.party:
			safe = safe and game.can_move_pixels(actor, actor.position_pixels, actor.facing)
	motor.stop()
	for i in range(20): motor.advance(0.062)
	checks.check(safe, "party follows an L-shaped trail without crossing the obstacle corner")
	checks.check(game.hero.position_pixels == Vector2(160, 128) and game.party[1].position_pixels.x == 160 and game.party[1].position_pixels.y > 128, "follower completes turn and keeps trail spacing")
	# A newly blocked trail can be bypassed without crossing the obstacle.
	motor.set_direction(Vector2i.UP)
	for i in range(3): motor.advance(0.062)
	motor.stop()
	var follower = game.party[1]
	var before: Vector2 = follower.position_pixels
	var cell: Vector2i = Vector2i(int(before.x / 16), int((before.y - 10) / 16) - 1)
	game.collision.terrain[cell.y * game.collision.width + cell.x] = 1
	checks.check(game.can_move_pixels(follower, before, follower.facing) and game.can_move_pixels(game.hero, game.hero.position_pixels, game.hero.facing), "new obstruction is between party members, outside both bodies")
	motor.set_direction(Vector2i.UP)
	for i in range(16): motor.advance(0.062)
	checks.check(follower.position_pixels != before and game.can_move_pixels(follower, follower.position_pixels, follower.facing), "follower safely detours when a delayed trail becomes obstructed: before=%s after=%s trail=%s" % [before, follower.position_pixels, motor.snapshot()["trails"][str(follower.instance_id)]["pending"]])
	game.collision.terrain[cell.y * game.collision.width + cell.x] = 0
	for i in range(16): motor.advance(0.062)
	checks.check(follower.position_pixels.y < before.y, "follower resumes retained trail after obstruction is removed")
