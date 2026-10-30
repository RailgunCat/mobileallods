extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Side = Ids.Side
const Stat = Ids.Stat

const Session = preload("res://scripts/gameplay/game_session.gd")
const Unit = preload("res://scripts/gameplay/unit_state.gd")
const Battle = preload("res://scripts/gameplay/battle_controller.gd")
const Encounter = preload("res://scripts/gameplay/encounter_builder.gd")
const Exploration = preload("res://scripts/gameplay/exploration_controller.gd")


func fixture(world: Dictionary, metadata: Dictionary, table: Dictionary) -> Array:
	var rows: Array = []
	for y in range(38):
		var row: Array = []
		row.resize(38)
		row.fill(0)
		rows.append(row)
	var map := {"name": "1", "width": 38, "height": 38, "source_tile_ids": rows}
	var defs: Dictionary = metadata.duplicate(true)
	defs["map_1_entries"][0]["position_pixels"] = [328, 328]
	var game := Session.new()
	game.start({"maps": [map], "constants": world["constants"], "scenes": [{"units": [[2, 56, 216, 1, 1, 0, 0, 0, 0], [0, 352, 272, 14, 8, 1, 0, 0, 0]]}]}, defs, table)
	game.add_demo_companion()
	var battle := Battle.new()
	battle.seed_value = 20261026
	battle.enemy_policy = &"defend" # Regression fixture for the stage-three runner.
	return [game, battle]


func _drain(battle, limit: int = 100) -> void:
	for i in range(limit):
		if not battle.busy(): return
		battle.advance(0.062)


func run(checks, world: Dictionary, metadata: Dictionary, table: Dictionary) -> void:
	_arena_reference(checks, metadata, table)
	var pair := fixture(world, metadata, table)
	var game = pair[0]
	var battle = pair[1]
	var enemy = game.units[2]
	var radius: float = enemy.stats[Stat.SIGHT] * 16
	game.hero.set_pixel_position(enemy.position_pixels + Vector2(radius, 0))
	checks.check(Encounter.detected(game).is_empty(), "detection excludes exact sight-radius boundary")
	game.hero.set_pixel_position(enemy.position_pixels + Vector2(radius - 4, 0))
	checks.check(Encounter.detected(game) == [enemy.instance_id], "detection uses strict squared pixel distance")
	enemy.encounter_enabled = false
	checks.check(Encounter.detected(game).is_empty(), "noncombat NPC never triggers encounter")
	enemy.encounter_enabled = true
	game.set_spawn_state(0, 1)
	checks.check(Encounter.detected(game).is_empty(), "hidden hostile never triggers encounter")
	game.set_spawn_state(0, 0)
	enemy.dead = true
	checks.check(Encounter.detected(game).is_empty(), "dead hostile never triggers encounter")
	enemy.dead = false
	game.hero.set_pixel_position(Vector2(328, 328))
	game.collision.occupy(game.hero.instance_id, game.hero.cell, game.hero.footprint)
	checks.check(battle.begin(game, [enemy.instance_id]), "encounter creates battle")
	checks.check(not battle.begin(game, [enemy.instance_id]) and game.mode == &"battle", "battle cannot start twice")
	checks.check(battle.current_side == Side.PARTY and battle.round_number == 1 and battle.participants.size() == 3, "player side starts round one with full roster")
	checks.check(game.hero.stats[Stat.ACTION_POINTS] == game.hero.stats[Stat.MAX_ACTION_POINTS] and game.hero.stats[Stat.PHYSICAL_RESISTANCE] == battle.state[game.hero.instance_id]["physical"], "own-side entry protection expires and AP resets")
	checks.check(enemy.stats[Stat.PHYSICAL_RESISTANCE] == int(battle.state[enemy.instance_id]["physical"]) * 5, "opposing side retains entry protection until its first turn")
	checks.check(not game.move_pixels(game.hero, Vector2(-4, 0)), "exploration motor cannot mutate combat")
	checks.check(not game.step(game.hero.cell + Vector2i.LEFT), "old grid prototype API cannot mutate combat")
	for id: int in battle.participants:
		var actor = battle.unit(id)
		checks.check(battle.arena.encloses(Rect2i(actor.cell, actor.footprint)), "whole footprint fits arena")
	checks.check(not battle.select(enemy.instance_id), "cannot select enemy during player side")
	checks.check(battle.select(game.party[1].instance_id) and battle.select(game.hero.instance_id), "freely select either allied actor")
	var start: Vector2i = game.hero.cell
	var ap: int = game.hero.stats[Stat.ACTION_POINTS]
	checks.check(not battle.submit_move(start + Vector2i.LEFT * (ap + 1)) and game.hero.stats[Stat.ACTION_POINTS] == ap, "unaffordable route rejected without AP mutation")
	checks.check(not battle.submit_move(battle.arena.position - Vector2i.ONE), "arena boundary rejects destination")
	checks.check(battle.submit_move(start + Vector2i.LEFT), "one-cell move is queued")
	checks.check(not battle.select(game.party[1].instance_id) and not battle.defend() and not battle.end_side(), "queued command locks actor/action/side input")
	battle.advance(0.062)
	checks.check(game.hero.stats[Stat.ACTION_POINTS] == ap - 1 and battle.busy(), "movement charges AP once at command start")
	checks.check(game.hero.position_pixels != Vector2(game.hero.cell) * 16 + Vector2.ONE * 8, "battle movement interpolates six simulation ticks")
	_drain(battle)
	checks.check(game.hero.cell == start + Vector2i.LEFT and game.hero.stats[Stat.ACTION_POINTS] == ap - 1 and battle.current_side == Side.PARTY, "move completes without ending remaining actor actions")
	var remaining: int = game.hero.stats[Stat.ACTION_POINTS]
	var physical: int = game.hero.stats[Stat.PHYSICAL_RESISTANCE]
	checks.check(battle.defend(), "defense queues")
	_drain(battle)
	checks.check(battle.state[game.hero.instance_id]["ended"] and game.hero.stats[Stat.ACTION_POINTS] == remaining, "defense ends eligibility while retaining original remaining AP")
	checks.check(game.hero.stats[Stat.PHYSICAL_RESISTANCE] == physical + int(physical * 4 * remaining / float(game.hero.stats[Stat.MAX_ACTION_POINTS])), "defense scales resistance by remaining AP")
	checks.check(battle.current_side == Side.PARTY and battle.selected_id == game.party[1].instance_id, "defense transfers selection within same side")
	checks.check(not battle.select(game.hero.instance_id), "ended actor cannot act again this side")
	checks.check(battle.end_side() and not battle.end_side(), "side end is queued once")
	battle.advance(0.062)
	checks.check(battle.current_side == Side.HOSTILE and battle.round_number == 1 and not battle.can_input(), "enemy side begins in same round")
	checks.check(enemy.stats[Stat.PHYSICAL_RESISTANCE] == battle.state[enemy.instance_id]["physical"], "enemy entry protection expires on enemy turn")
	checks.check(not battle.submit_move(game.hero.cell) and not battle.wait_unit(), "player cannot command enemy side")
	for i in range(12): battle.advance(0.062)
	checks.check(battle.current_side == Side.PARTY and battle.round_number == 2 and game.hero.stats[Stat.ACTION_POINTS] == game.hero.stats[Stat.MAX_ACTION_POINTS], "enemy placeholder defense advances exactly one round and restores AP")
	checks.check(game.hero.stats[Stat.PHYSICAL_RESISTANCE] == physical, "defense expires at next own-side start")
	var rounds: int = battle.round_number
	for i in range(30): battle.advance(0.062)
	checks.check(battle.round_number == rounds and battle.current_side == Side.PARTY, "idle frames do not advance player rounds")
	_stale_command(checks, world, metadata, table)
	_fps(checks, world, metadata, table)
	_entry(checks, world, metadata, table)
	_extra_cases(checks, world, metadata, table)


func _stale_command(checks, world: Dictionary, metadata: Dictionary, table: Dictionary) -> void:
	var pair := fixture(world, metadata, table)
	var game = pair[0]
	var battle = pair[1]
	battle.begin(game, [1001])
	var target: Vector2i = game.hero.cell + Vector2i.LEFT
	var ap: int = game.hero.stats[Stat.ACTION_POINTS]
	battle.submit_move(target)
	game.collision.terrain[target.y * game.collision.width + target.x] = 1
	battle.advance(0.062)
	checks.check(not battle.busy() and game.hero.stats[Stat.ACTION_POINTS] == ap and game.hero.cell != target, "execution revalidates newly obstructed route without spending AP")
	game.collision.terrain[target.y * game.collision.width + target.x] = 0
	battle.submit_move(target)
	battle.queue[0]["turn"] = -1
	battle.advance(0.062)
	checks.check(not battle.busy() and game.hero.stats[Stat.ACTION_POINTS] == ap, "stale side-token command is rejected")
	game.hero.stats[Stat.STUN] = 1
	checks.check(not battle.select(game.hero.instance_id), "stunned actor is ineligible")
	game.hero.stats[Stat.STUN] = 0
	game.hero.dead = true
	checks.check(not battle.select(game.hero.instance_id), "dead actor is ineligible")
	game.hero.dead = false
	game.party[1].set_pixel_position(game.hero.position_pixels)
	game.collision.occupy(game.party[1].instance_id, game.party[1].cell, Vector2i.ONE)
	battle.reset()
	game.mode = &"exploration"
	checks.check(battle.begin(game, [1001]) and game.hero.cell != game.party[1].cell, "entry separates overlapping exploration party footprints")


func _fps(checks, world: Dictionary, metadata: Dictionary, table: Dictionary) -> void:
	var baseline: Dictionary = {}
	for fps in [30, 60, 144]:
		var pair := fixture(world, metadata, table)
		var game = pair[0]
		var battle = pair[1]
		battle.begin(game, [1001])
		battle.submit_move(game.hero.cell + Vector2i.LEFT * 2)
		for i in range(fps): battle.advance(1.0 / fps)
		var snapshot: Dictionary = battle.snapshot()
		snapshot.erase("accumulator")
		var state := {"battle": snapshot, "hero": game.hero.snapshot()}
		if baseline.is_empty(): baseline = state
		checks.check(state == baseline, "same movement/AP/queue/turn state at %d FPS" % fps)


func _entry(checks, world: Dictionary, metadata: Dictionary, table: Dictionary) -> void:
	var pair := fixture(world, metadata, table)
	var game = pair[0]
	var battle = pair[1]
	var exploration := Exploration.new()
	exploration.configure(game)
	var count := [0]
	exploration.encounter_detected.connect(func(ids: Array[int]):
		if battle.begin(game, ids): count[0] += 1
	)
	exploration.advance(2.0)
	checks.check(count[0] == 1 and game.mode == &"battle" and exploration.tick_count == 1, "exploration enters encounter once and stops remaining catch-up ticks")
	var before: Vector2 = game.hero.position_pixels
	exploration.set_direction(Vector2i.LEFT)
	exploration.advance(5.0)
	checks.check(game.hero.position_pixels == before and count[0] == 1, "exploration and encounter detection remain suspended in battle")


func _arena_reference(checks, metadata: Dictionary, table: Dictionary) -> void:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/legacy/battle_reference.json"))
	for case: Dictionary in reference["cases"]:
		var game := Session.new()
		game.definitions = metadata
		game.flags = metadata["new_game"]["flags"].duplicate(true)
		game.collision.width = int(case["width"])
		game.collision.height = int(case["height"])
		var triggers: Array[int] = []
		for entry: Dictionary in case["units"]:
			var actor := Unit.new()
			actor.configure({"instance_id": int(entry["id"]), "unit_type": 0, "story_group": 0, "spawn_flag": int(entry["flag"]), "side_id": 0 if entry["party"] else 1}, metadata, table)
			actor.footprint = Vector2i(int(entry["footprint"][0]), int(entry["footprint"][1]))
			actor.set_pixel_position(Vector2(float(entry["position"][0]), float(entry["position"][1])))
			game.units.append(actor)
			if entry["party"]: game.party.append(actor)
			if entry["triggered"]: triggers.append(actor.instance_id)
			game.spawn_states[actor.spawn_flag] = int(entry["state"])
		game.hero = game.party[0]
		var result: Dictionary = Encounter.build(game, triggers)
		var expected: Array = case["arena"]
		checks.check(result["arena"] == Rect2i(int(expected[0]), int(expected[1]), int(expected[2]), int(expected[3])), "Java arena bounds: " + str(case["name"]))
		checks.check(PackedInt32Array(result["unit_ids"]) == PackedInt32Array(case["participants"]), "Java arena membership: " + str(case["name"]))


func _extra_cases(checks, world: Dictionary, metadata: Dictionary, table: Dictionary) -> void:
	var pair := fixture(world, metadata, table)
	var game = pair[0]
	var battle = pair[1]
	checks.check(not battle.begin(game, [99999]) and game.mode == &"exploration", "invalid encounter trigger cannot start battle")
	var original: Vector2 = game.hero.position_pixels
	game.collision.terrain.fill(1)
	checks.check(not battle.begin(game, [1001]) and game.hero.position_pixels == original and game.mode == &"exploration", "failed placement leaves session and positions unchanged")
	game.collision.terrain.fill(0)
	battle.begin(game, [1001])
	var start: Vector2i = game.hero.cell
	var ap: int = game.hero.stats[Stat.ACTION_POINTS]
	battle.submit_move(start + Vector2i.LEFT * 2)
	for i in range(6): battle.advance(0.062)
	var blocked: Vector2i = start + Vector2i.LEFT * 2
	game.collision.terrain[blocked.y * game.collision.width + blocked.x] = 1
	battle.advance(0.062)
	checks.check(game.hero.cell == start + Vector2i.LEFT and game.hero.stats[Stat.ACTION_POINTS] == ap - 1 and not battle.busy(), "mid-route obstruction stops safely and refunds unwalked steps")
	checks.check(battle.state[game.hero.instance_id]["movement_spent"] == 1, "interrupted route keeps actual movement accounting")
	game.collision.terrain[blocked.y * game.collision.width + blocked.x] = 0
	battle.submit_move(game.hero.cell + Vector2i.LEFT * game.hero.stats[Stat.ACTION_POINTS])
	_drain(battle)
	checks.check(game.hero.stats[Stat.ACTION_POINTS] == 0 and battle.selected_id == game.party[1].instance_id and battle.current_side == Side.PARTY, "exhausting AP selects another ally without ending side")
	battle.reset()
	checks.check(not battle.active and game.mode == &"exploration" and battle.state.is_empty(), "battle reset clears mode, queue and temporary turn state")
	battle.begin(game, [1001])
	battle.end_side()
	checks.check(battle.queue.size() == 2, "end side queues each eligible ally exactly once")
	for i in range(2): battle.advance(0.062)
	checks.check(battle.current_side == Side.HOSTILE and battle.turn_serial == 2 and battle.round_number == 1, "multi-actor end-side queue advances side once")
	for i in range(10): battle.advance(0.062)
	game.units[2].stats[Stat.STUN] = 1
	battle.end_side()
	for i in range(2): battle.advance(0.062)
	checks.check(battle.current_side == Side.PARTY and battle.round_number == 3, "empty/stunned opposing side is skipped once per round")
	for id: int in battle.participants: battle.unit(id).stats[Stat.STUN] = 1
	battle.advance(0.062)
	var event_count: int = battle.events.size()
	for i in range(20): battle.advance(0.062)
	checks.check(battle.stalled and battle.events.size() == event_count, "no eligible actors stalls without recursion or repeated turn events")
