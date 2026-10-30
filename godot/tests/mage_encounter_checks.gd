extends RefCounted
const Session = preload("res://scripts/gameplay/game_session.gd")
const Battle = preload("res://scripts/gameplay/battle_controller.gd")
const Story = preload("res://scripts/gameplay/campaign_runner.gd")
const Unit = preload("res://scripts/gameplay/unit_state.gd")
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Settle = preload("res://tests/campaign_checks.gd")
const Rewards = preload("res://scripts/gameplay/battle_rewards.gd")
const Random = preload("res://scripts/gameplay/legacy_random.gd")

func run(checks, world, metadata, table, rewards, campaign) -> void:
	_loot_reference(checks, world, metadata, table, rewards)
	for scattered in [false, true]:
		var game := Session.new()
		game.start(world, metadata, table, rewards)
		for kind in range(1, 4):
			var actor := Unit.new()
			actor.configure({"instance_id": kind + 1, "unit_type": kind, "story_group": kind, "spawn_flag": kind + 1, "side_id": 0}, metadata, table)
			game.units.append(actor)
			game.party.append(actor)
		game.flags["e"][7] = 1
		game.travel(6, 0)
		game.set_spawn_state(36, Ids.SpawnState.VISIBLE)
		for i in range(game.party.size()):
			var actor = game.party[i]
			game.collision.remove(actor.instance_id)
			actor.set_pixel_position(Vector2(80, 128) if scattered and i > 0 else Vector2(800 - i * 32, 560))
			game.collision.occupy(actor.instance_id, actor.cell, actor.footprint)
		var story := Story.new()
		story.configure(game, world, campaign)
		var before: Array = game.party.map(func(actor): return actor.position_pixels)
		checks.check(story.start_script(106) and Settle.new().settle(story), "red mage dialogue 51 completes")
		checks.check(game.party.map(func(actor): return actor.position_pixels) == before, "red mage dialogue does not teleport any party member")
		game.collision.remove(game.hero.instance_id)
		game.hero.set_pixel_position(Vector2(848, 560))
		game.collision.occupy(game.hero.instance_id, game.hero.cell, game.hero.footprint)
		var battle := Battle.new()
		battle.seed_value = 42
		checks.check(battle.begin(game, [7000]), "red mage battle begins with scattered=%s" % scattered)
		var enemies: Array = []
		for id in battle.participants:
			if battle.unit(id) not in game.party: enemies.append(id)
		checks.check(enemies == [7000], "red mage encounter excludes remote labyrinth waves with scattered=%s" % scattered)
		checks.check(battle.arena.size.x <= 20 and battle.arena.size.y <= 20, "red mage arena stays local with scattered=%s" % scattered)
		checks.check(game.hero.position_pixels.distance_to(Vector2(848, 560)) <= 16, "red mage battle keeps the leader at the encounter")
		for actor in game.party: checks.check(battle.arena.encloses(Rect2i(actor.cell, actor.footprint)), "party member fits the local red-mage arena")
		if scattered:
			for actor in game.party:
				if actor != game.hero: checks.check(actor.position_pixels.distance_to(game.hero.position_pixels) <= 64, "lagging companion joins close to the leader rather than an arena corner")

func _loot_reference(checks, world, metadata, table, rewards) -> void:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/reference/mage_loot/cases.json"))
	for sample: Dictionary in reference["cases"]:
		var game := Session.new()
		game.start(world, metadata, table, rewards)
		game.location_id = 6
		game.flags["e"][7] = 1
		game.hero.stats[Ids.Stat.LUCK] = int(sample["luck"])
		var mage := Unit.new()
		mage.configure({"instance_id": 7000, "unit_type": Ids.UnitKind.MAGE, "spawn_flag": 48, "story_group": 8, "side_id": 1}, metadata, table)
		var rng := Random.new(int(sample["seed"]))
		var result: Dictionary = Rewards.award(game, [mage], rng)
		var label: String = "luck=%d seed=%d" % [sample["luck"], sample["seed"]]
		checks.check(PackedInt32Array(result["items"]) == PackedInt32Array(sample["items"]), "mage loot item sequence matches independent Java: " + label)
		checks.check(result["gold"] == int(sample["gold"]), "mage loot gold matches independent Java: " + label)
		checks.check(rng.next_signed() == int(sample["next_int"]), "mage loot consumes the original RNG draws: " + label)
