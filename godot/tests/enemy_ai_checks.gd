extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Stat = Ids.Stat
const Unit = preload("res://scripts/gameplay/unit_state.gd")
const Random = preload("res://scripts/gameplay/legacy_random.gd")
const Fixtures = preload("res://tests/battle_checks.gd")
const Battle = preload("res://scripts/gameplay/battle_controller.gd")


func fixture(world, metadata, table) -> Array:
	var pair: Array = Fixtures.new().fixture(world, metadata, table)
	var game = pair[0]
	var battle = pair[1]
	var mage = game.units[2]
	mage.configure({"instance_id": mage.instance_id, "unit_type": Ids.UnitKind.MAGE, "story_group": 8, "spawn_flag": 0, "side_id": 1}, metadata, table)
	mage.encounter_enabled = true
	game.collision.units.clear()
	for index in range(game.units.size()):
		var actor = game.units[index]
		actor.move_to([Vector2i(20, 20), Vector2i(19, 20), Vector2i(23, 20)][index])
		game.collision.occupy(actor.instance_id, actor.cell, actor.footprint)
	battle.begin(game, [mage.instance_id])
	battle.enemy_policy = &"combat"
	battle._start_side(Ids.Side.HOSTILE)
	return pair


func run(checks, world, metadata, table) -> void:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/reference/enemy_ai/cases.json"))
	for sample: Dictionary in reference["cases"]:
		var pair: Array = fixture(world, metadata, table)
		var game = pair[0]
		var battle = pair[1]
		var mage = game.units[2]
		for slot in range(Stat.LIGHT_FIRE_MAGIC, Stat.RESERVED): mage.stats[slot] = 7
		mage.stats[Stat.MANA] = 1000
		mage.stats[Stat.ACTION_POINTS] = 10
		mage.stats[Stat.ATTACK_RANGE] = 40
		match sample["scenario"]:
			"low_mana": mage.stats[Stat.MANA] = 3
			"rank_one":
				for slot in range(Stat.LIGHT_FIRE_MAGIC, Stat.RESERVED): mage.stats[slot] = 0
				mage.stats[Stat.DARK_FIRE_MAGIC] = 1
			"no_magic":
				for slot in range(Stat.LIGHT_FIRE_MAGIC, Stat.RESERVED): mage.stats[slot] = 0
			"out_of_range": mage.stats[Stat.ATTACK_RANGE] = 1
			"dead_target": game.hero.dead = true; game.hero.stats[Stat.HP] = 0
			"only_friendly":
				for actor in game.party: actor.side_id = Ids.Side.HOSTILE
		battle.rng = Random.new(int(sample["seed"]))
		var cast: bool = battle._magic_action(mage)
		var spell: int = int(battle.queue[0]["spell"]) if cast else -1
		var target: int = battle.actor_at(battle.queue[0]["cell"]).instance_id if cast else -1
		var label: String = "%s / seed %d" % [sample["scenario"], int(sample["seed"])]
		checks.check(cast == sample["cast"] and spell == int(sample["spell"]) and target == int(sample["target"]), "original Java spell and target choice: " + label)
		checks.check(battle.rng.next_signed() == int(sample["next_int"]), "original Java AI random draw order: " + label)
	_roles(checks, world, metadata, table)
	_threshold(checks, world, metadata, table)
	_seeds(checks, world, metadata, table)


func _roles(checks, world, metadata, table) -> void:
	var pair: Array = fixture(world, metadata, table)
	var game = pair[0]
	var battle = pair[1]
	var actor = game.units[2]
	actor.stats[Stat.ATTACK] = 1
	actor.stats[Stat.ACTION_POINTS] = 10
	actor.stats[Stat.MANA] = 1000
	actor.stats[Stat.ATTACK_RANGE] = 40
	for slot in range(Stat.LIGHT_FIRE_MAGIC, Stat.RESERVED): actor.stats[slot] = 7
	battle._enemy_action(actor)
	checks.check(not battle.queue.is_empty() and battle.queue[0]["action"] == "attack", "source fighter with magic retains physical attack priority")
	for slot in range(Stat.LIGHT_FIRE_MAGIC, Stat.RESERVED): actor.stats[slot] = 0
	var targets: Dictionary = {}
	for seed in range(12):
		battle.queue.clear()
		battle.rng = Random.new(seed)
		battle._enemy_action(actor)
		if not battle.queue.is_empty() and battle.queue[0]["action"] == "attack": targets[battle.queue[0]["target"]] = true
	checks.check(targets.has(game.hero.instance_id) and targets.has(game.party[1].instance_id), "fighter chooses among valid targets instead of always taking the closest")
	actor.stats[Stat.ATTACK] = 0
	actor.stats[Stat.DEFENSE] = 0
	actor.stats[Stat.TACTICS] = 0
	actor.stats[Stat.MANA] = 0
	battle.queue.clear()
	battle._enemy_action(actor)
	checks.check(not battle.queue.is_empty() and battle.queue[0]["action"] == "move", "caster without mana uses movement before defense")


func _threshold(checks, world, metadata, table) -> void:
	var pair: Array = fixture(world, metadata, table)
	var game = pair[0]
	var battle = pair[1]
	var actor = game.units[2]
	for slot in range(Stat.LIGHT_FIRE_MAGIC, Stat.RESERVED): actor.base_stats[slot] = 0
	actor.base_stats[Stat.DARK_FIRE_MAGIC] = 1
	actor.recalculate(table)
	actor.stats[Stat.MANA] = actor.stats[Stat.MAX_MANA]
	var mana: int = actor.stats[Stat.MANA]
	var cast: bool = battle._magic_action(actor)
	checks.check(cast, "source AI can cast at school value equal to rank_step")
	if not cast: return
	for tick in range(150):
		if not battle.busy(): break
		battle.advance(0.062)
	checks.check(actor.stats[Stat.MANA] == mana - 2 and battle.events.any(func(event): return event["event"] == "spell_impact" and event.get("actor", -1) == actor.instance_id), "AI threshold spell survives command validation and reaches impact")


func _seeds(checks, world, metadata, table) -> void:
	var pair: Array = fixture(world, metadata, table)
	var game = pair[0]
	var battle := Battle.new()
	game.mode = &"exploration"
	battle.begin(game, [game.units[2].instance_id])
	var first: int = battle.snapshot()["seed"]
	battle.reset()
	battle.begin(game, [game.units[2].instance_id])
	checks.check(first != int(battle.snapshot()["seed"]), "ordinary battles use a fresh random seed")
	battle.reset()
	battle.seed_value = 42
	battle.begin(game, [game.units[2].instance_id])
	var state: Dictionary = battle.rng.snapshot()
	battle.reset()
	battle.begin(game, [game.units[2].instance_id])
	checks.check(battle.rng.snapshot() == state and battle.snapshot()["seed"] == 42, "explicit test seed reproduces battle randomness")
