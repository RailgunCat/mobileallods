extends RefCounted
const Session = preload("res://scripts/gameplay/game_session.gd")
const Story = preload("res://scripts/gameplay/campaign_runner.gd")
const Unit = preload("res://scripts/gameplay/unit_state.gd")
const Battle = preload("res://scripts/gameplay/battle_controller.gd")
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Gates = preload("res://scripts/gameplay/campaign_gates.gd")

func _party(game, metadata: Dictionary, table: Dictionary) -> void:
	for kind in range(1, 4):
		var actor := Unit.new()
		actor.configure({"instance_id": kind + 1, "unit_type": kind, "story_group": kind, "spawn_flag": kind + 1, "side_id": 0}, metadata, table)
		actor.set_pixel_position(game.hero.position_pixels)
		game.units.append(actor)
		game.party.append(actor)

func run(checks, world: Dictionary, metadata: Dictionary, table: Dictionary, rewards: Dictionary, data: Dictionary) -> void:
	var game := Session.new()
	game.start(world, metadata, table, rewards)
	checks.check(not game.world_travel_unlocked(), "new game locks world map and city")
	game.travel(1, 0)
	var certificate := Story.new()
	certificate.configure(game, world, data)
	certificate.start_script(22)
	for tick in range(1000):
		if not certificate.busy(): break
		if not certificate.modal.is_empty(): certificate.acknowledge()
		else: certificate.advance(0.062)
	checks.check(certificate.fault.is_empty() and game.world_travel_unlocked() and int(game.triggers[23]) == Ids.TriggerState.ENABLED and game.party.back().unit_type == Ids.UnitKind.KURT, "source Kurt recruitment completes certificate and unlocks city")
	game.start(world, metadata, table, rewards)
	_party(game, metadata, table)
	checks.check(int(game.triggers[15]) == Ids.TriggerState.LOCKED, "source special-map trigger starts locked")
	var unlocks_special: bool = false
	for scene: Dictionary in data["scenes"]:
		for program: Dictionary in scene["scripts"]:
			for instruction: Dictionary in program["instructions"]:
				if int(instruction["opcode"]) == 0 and int(instruction["args"][0]) == 15 and int(instruction["args"][1]) == 1: unlocks_special = true
	checks.check(not unlocks_special, "no recovered campaign script unlocks special transition 100")
	checks.check(game.travel(6, 0), "map seven loads randomized gates")
	var choices: Array = game.gate_choices.duplicate()
	var triggers: Array = game.current_scene["triggers"].duplicate(true)
	var draws: int = game.world_rng.draws
	checks.check(choices.size() == 5 and game.current_scene["triggers"].size() == world["scenes"][6]["triggers"].size() + 8, "map seven creates eight unsafe triggers and consumes five source draws")
	game.travel(0, 0)
	game.travel(6, 0)
	checks.check(game.gate_choices == choices and game.current_scene["triggers"] == triggers and game.world_rng.draws == draws, "gate choices remain fixed on revisit without extra RNG draws")
	for barrier in range(4):
		var safe: Array = Gates.REGIONS[barrier][int(choices[barrier])]
		checks.check(safe not in triggers, "barrier %d has the selected safe passage" % barrier)
	# Run every recovered scene program in isolation with its scene NPCs and four heroes.
	# Travel/menu instructions are terminal handoffs; combat balance is tested separately.
	var count: int = 0
	for location in range(12):
		for program: Dictionary in data["scenes"][location]["scripts"]:
			var fixture := Session.new()
			fixture.start(world, metadata, table, rewards)
			_party(fixture, metadata, table)
			fixture.spawn_states.fill(0)
			fixture.travel(location, 0)
			var story := Story.new()
			story.configure(fixture, world, data)
			var id: int = int(program["script_id"])
			var forced: Array = []
			story.encounter_requested.connect(func(ids: Array[int]): forced.append(ids.duplicate()))
			story.start_script(id)
			for tick in range(10000):
				if not story.fault.is_empty() or not story.busy() or fixture.mode in [&"travel", &"world_map"]: break
				if not story.modal.is_empty(): story.acknowledge()
				else: story.advance(0.062)
			checks.check(story.fault.is_empty() and (not story.busy() or fixture.mode in [&"travel", &"world_map"]), "campaign scene %d script %d executes or hands off: %s" % [location, id, story.fault])
			if id == 137: checks.check(forced.size() == 1 and not forced[0].is_empty(), "script 137 requests its marked encounter once after completion")
			count += 1
	checks.check(count == 147, "all 147 recovered scene program IDs checked through original first-match lookup")
	game.dungeon_seeds[11] = 20261027
	checks.check(game.travel(-12, 0), "final dragon chamber reachable")
	var dragon
	for actor in game.units:
		if actor.unit_type == Ids.UnitKind.DRAGON: dragon = actor
	checks.check(dragon != null, "final chamber contains recovered dragon")
	if dragon == null: return
	var battle := Battle.new()
	checks.check(battle.begin(game, [dragon.instance_id]), "final dragon battle begins")
	game.god_mode = true
	dragon.dead = true
	dragon.stats[Ids.Stat.HP] = 0
	var gold: int = game.gold
	checks.check(battle._check_outcome() and not battle.finale.is_empty() and battle.outcome == &"" and not game.party[1].dead and not battle.can_input(), "dragon defeat starts its final meteor before Li dies and blocks combat input")
	battle.advance(0.062 * (battle.FINALE_FALL_TICKS - 1))
	checks.check(not game.party[1].dead and not game.campaign_completed, "Li stays alive until the final stone lands")
	battle.advance(0.062)
	checks.check(game.party[1].dead and battle.outcome == &"", "Li dies at impact before the final dialogue")
	battle.advance(0.062 * battle.FINALE_AFTER_TICKS)
	checks.check(battle.outcome == &"ending" and game.campaign_completed, "final meteor aftermath enters the campaign ending")
	checks.check(game.party[1].dead and game.party[1].stats[Ids.Stat.HP] == 0 and game.gold == gold and battle.reward.is_empty(), "dragon retaliation kills Li and bypasses ordinary loot")
	checks.check(not battle.return_to_exploration(), "ending cannot revive Li through ordinary victory recovery")
