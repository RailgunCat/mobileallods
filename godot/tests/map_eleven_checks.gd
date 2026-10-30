extends RefCounted
const Session = preload("res://scripts/gameplay/game_session.gd")
const Story = preload("res://scripts/gameplay/campaign_runner.gd")
const Motor = preload("res://scripts/gameplay/exploration_controller.gd")
const Unit = preload("res://scripts/gameplay/unit_state.gd")
const Saves = preload("res://scripts/gameplay/save_service.gd")
const Settle = preload("res://tests/campaign_checks.gd")
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Inventory = preload("res://scripts/gameplay/inventory_rules.gd")

func run(checks, world, metadata, table, rewards, data) -> void:
	for party_size in [1, 4]:
		var game := Session.new()
		game.start(world, metadata, table, rewards)
		for kind in range(1, party_size):
			var actor := Unit.new()
			actor.configure({"instance_id": kind + 1, "unit_type": kind, "story_group": kind, "spawn_flag": kind + 1, "side_id": 0}, metadata, table)
			game.party.append(actor)
			game.units.append(actor)
		Inventory.sync_party(game)
		game.set_spawn_state(27, Ids.SpawnState.VISIBLE)
		game.travel(10, 0)
		var story := Story.new()
		story.configure(game, world, data)
		var survivor
		for actor in game.units:
			if actor.story_group == 11: survivor = actor
		checks.check(survivor != null and survivor.collision_enabled, "map eleven survivor blocks normally before the entrance scene")
		story.check_triggers()
		checks.check(story.script_id == 138 and Settle.new().settle(story), "map eleven arrival dialogue finishes")
		var motor := Motor.new()
		motor.configure(game)
		motor.set_direction(Vector2i.LEFT)
		for tick in range(40):
			motor.advance(0.062)
			story.check_triggers()
			if story.busy(): break
		checks.check(story.script_id == 139, "keyboard approach starts the survivor scene at the entrance")
		checks.check(Settle.new().settle(story) and game.quests[22] == Ids.QuestState.ACTIVE and game.triggers[139] == Ids.TriggerState.DISABLED, "survivor dialogue activates the rescue quest once")
		checks.check(game.is_active(survivor) and survivor.position_pixels == Vector2(768, 848), "survivor stays visible at the original scripted endpoint")
		checks.check(not survivor.collision_enabled and not game.collision.units.has(survivor.instance_id), "completed source movement releases survivor collision")
		var terrain: PackedByteArray = game.collision.terrain.duplicate()
		var position: Vector2 = game.hero.position_pixels
		motor.set_direction(Vector2i.LEFT)
		for tick in range(24): motor.advance(0.062)
		checks.check(game.hero.position_pixels.x <= position.x - 80, "keyboard movement passes the survivor after dialogue with party size %d" % party_size)
		var plan: Dictionary = motor.preview(Vector2i(43, 50))
		checks.check(plan["reachable"] and not plan["path"].is_empty(), "mouse route can leave the map-eleven entrance")
		motor.start_route(plan["path"], plan.get("pixel_path", []))
		for tick in range(300):
			if not motor.following_route: break
			motor.advance(0.062)
		checks.check(game.hero.cell == Vector2i(43, 50) and not motor.following_route and game.collision.terrain == terrain, "mouse route completes without changing terrain")
		# Simulate a native save from the affected build, after the dialogue.
		survivor.collision_enabled = true
		game.collision.occupy(survivor.instance_id, survivor.cell, survivor.footprint)
		game.hero.set_pixel_position(Vector2(784, 832))
		game.collision.occupy(game.hero.instance_id, game.hero.cell, game.hero.footprint)
		motor.configure(game)
		var saves := Saves.new()
		var flags: Dictionary = game.flags.duplicate(true)
		var actors: Array = game.units.map(func(actor): return actor.position_pixels)
		var restored: Dictionary = saves.restore(JSON.parse_string(JSON.stringify(saves.capture(game, story, motor))), world, metadata, table, rewards)
		checks.check(not restored.is_empty(), "native map-eleven save made after the broken scene restores")
		if restored.is_empty(): continue
		game = restored["session"]
		story.configure(game, world, data)
		checks.check(JSON.stringify(game.flags) == JSON.stringify(JSON.parse_string(JSON.stringify(flags))) and game.units.map(func(actor): return actor.position_pixels) == actors, "repair preserves dialogue progress and all actor positions")
		motor.configure(game)
		motor.set_direction(Vector2i.LEFT)
		for tick in range(24): motor.advance(0.062)
		checks.check(game.hero.position_pixels.x <= 704, "loading an affected save repairs the blocked entrance")
