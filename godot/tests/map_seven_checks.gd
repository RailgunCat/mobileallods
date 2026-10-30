extends RefCounted
const Session = preload("res://scripts/gameplay/game_session.gd")
const Story = preload("res://scripts/gameplay/campaign_runner.gd")
const Motor = preload("res://scripts/gameplay/exploration_controller.gd")
const Ids = preload("res://scripts/gameplay/game_ids.gd")

func run(checks, world, metadata, table, rewards, data) -> void:
	var game := Session.new()
	game.start(world, metadata, table, rewards)
	checks.check(game.travel(6, 0), "map seven entrance loads")
	var story := Story.new()
	story.configure(game, world, data)
	var flags: Dictionary = game.flags.duplicate(true)
	var rng: Dictionary = game.world_rng.snapshot()
	var position: Vector2 = game.hero.position_pixels
	checks.check(position == Vector2(32, 304) and not story.scripts.has(100) and int(game.triggers[100]) == Ids.TriggerState.ENABLED, "source entrance lies in enabled trigger 100 without a matching program")
	story.check_triggers()
	checks.check(story.fault.is_empty() and not story.busy() and game.mode == &"exploration", "entering map seven ignores missing program 100 like original m.void_d")
	checks.check(game.flags == flags and game.hero.position_pixels == position and game.world_rng.snapshot() == rng, "missing program leaves story flags, position and RNG unchanged")
	if not story.fault.is_empty(): return
	var events: int = story.events.size()
	for tick in range(30): story.check_triggers()
	checks.check(story.events.size() == events and game.flags == flags, "standing in a dangling trigger neither spams diagnostics nor disables it")
	var motor := Motor.new()
	motor.configure(game)
	motor.set_direction(Vector2i.RIGHT)
	for tick in range(12):
		motor.advance(0.062)
		story.check_triggers()
	checks.check(game.hero.position_pixels.x > 64 and story.fault.is_empty() and not story.busy(), "checked movement leaves the map-seven entrance without a script fault")
	# Cover every dangling region reference in the recovered overworld scenes,
	# not only executable programs (the earlier campaign audit missed these).
	var missing: Array = []
	for location in range(12):
		game.travel(location, 0)
		story.configure(game, world, data)
		for region: Dictionary in story.triggers:
			var id: int = int(region["script_id"])
			if story.scripts.has(id): continue
			missing.append([location + 1, id])
			var before: Dictionary = game.flags.duplicate(true)
			checks.check(not story.start_script(id) and story.fault.is_empty() and not story.busy() and game.mode == &"exploration" and game.flags == before, "source map %d missing script %d is a harmless lookup miss" % [location + 1, id])
	checks.check(missing == [[5, 57], [7, 100], [7, 99]], "all three original dangling region references are covered")
	# Existing scripts still start, and malformed opcodes still fail explicitly.
	game.travel(6, 0)
	story.configure(game, world, data)
	checks.check(story.start_script(101), "existing map-seven barrier script still starts")
	story.advance(0.186)
	checks.check(story.fault.is_empty() and int(game.triggers[68]) == Ids.TriggerState.DISABLED, "existing barrier script retains its real side effect")
	story.configure(game, world, data)
	game.mode = &"exploration"
	story.scripts[999] = [{"opcode": 999, "offset": 1, "operands": {}}]
	story.start_script(999)
	story.advance(0.062)
	checks.check(not story.fault.is_empty() and game.mode == &"campaign_error", "unsupported instructions still report a real script error")
