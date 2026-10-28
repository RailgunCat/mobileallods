extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Side = Ids.Side
const Stat = Ids.Stat

const Fixtures = preload("res://tests/battle_checks.gd")
const Unit = preload("res://scripts/gameplay/unit_state.gd")
const Item = preload("res://scripts/gameplay/item_instance.gd")
const LegacyRandom = preload("res://scripts/gameplay/legacy_random.gd")
const Rules = preload("res://scripts/gameplay/combat_rules.gd")
const Rewards = preload("res://scripts/gameplay/battle_rewards.gd")

# This oracle supplies already-aggregated vectors, exactly like its Java stub.
# Production actors recalculate from base stats/equipment in UnitState.
class FrozenStatsActor:
	extends "res://scripts/gameplay/unit_state.gd"
	func recalculate(_table: Dictionary) -> void: pass


func _fixture(world: Dictionary, metadata: Dictionary, table: Dictionary, rewards: Dictionary) -> Array:
	var pair: Array = Fixtures.new().fixture(world, metadata, table)
	pair[0].reward_table = rewards
	pair[0].hero.move_to(Vector2i(21, 20))
	pair[0].hero.reset_interpolation()
	pair[0].collision.occupy(pair[0].hero.instance_id, pair[0].hero.cell, pair[0].hero.footprint)
	pair[1].enemy_policy = &"combat"
	pair[1].begin(pair[0], [1001])
	return pair


func drive(battle, limit: int = 1200) -> bool:
	for tick in range(limit):
		if battle.outcome != &"": return true
		if battle.can_input() and battle.selected_id >= 0:
			battle._enemy_action(battle.unit(battle.selected_id))
		battle.advance(0.062)
	return false


func run(checks, world: Dictionary, metadata: Dictionary, table: Dictionary, rewards: Dictionary) -> void:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/legacy/combat_reference.json"))
	var random := LegacyRandom.new(int(reference["rng_seed"]))
	for value: float in reference["rng"]:
		checks.check(random.next_signed() == int(value), "Java Random.nextInt signed stream")
	for case: Dictionary in reference["cases"]:
		var attacker := FrozenStatsActor.new()
		var defender := FrozenStatsActor.new()
		attacker.stats = PackedInt32Array(case["attacker"])
		attacker.base_stats = attacker.stats.duplicate()
		defender.stats = PackedInt32Array(case["defender"])
		if int(case["weapon"]) >= 0: attacker.weapon = Item.new(1, int(case["weapon"]))
		random = LegacyRandom.new(int(case["seed"]))
		var payload := PackedInt32Array()
		payload.resize(Stat.COUNT)
		payload[Stat.PHYSICAL_DAMAGE] = attacker.stats[Stat.PHYSICAL_DAMAGE]
		payload[Stat.ARCHERY if bool(case["ranged"]) else Stat.ATTACK] = 1
		var hit: Dictionary = Rules.apply(attacker, defender, payload, random, table, int(case["moved"]))
		checks.check(hit["damage"] == int(case["damage"]), "physical damage matches original q.a(q)")
		checks.check(random.next_signed() == int(case["next_int"]), "physical damage preserves original RNG call order")
	var pair := _fixture(world, metadata, table, rewards)
	var game = pair[0]
	var battle = pair[1]
	var enemy = battle.unit(1001)
	var original_hp: int = enemy.stats[Stat.HP]
	var actor = game.hero
	var start: Vector2i = actor.cell
	checks.check(not battle.attack(game.party[1].instance_id), "friendly fire rejected")
	checks.check(battle.attack(enemy.instance_id), "melee queues approach and hit as one action")
	checks.check(not battle.attack(enemy.instance_id), "double attack while busy rejected")
	battle.advance(0.062)
	checks.check(actor.stats[Stat.ACTION_POINTS] > 0 and actor.stats[Stat.ACTION_POINTS] < actor.stats[Stat.MAX_ACTION_POINTS] and enemy.stats[Stat.HP] == original_hp, "approach spends movement AP, reserves remaining AP for damage")
	for i in range(40): battle.advance(0.062)
	checks.check(enemy.stats[Stat.HP] < original_hp and actor.cell != start and battle.state[actor.instance_id]["ended"], "melee approaches, damages and ends actor")
	checks.check(battle.current_side == Side.PARTY and battle.selected_id == game.party[1].instance_id, "attack preserves ally's remaining turn")
	checks.check(battle.attack(enemy.instance_id), "archer can shoot target in original range")
	for i in range(9): battle.advance(0.062)
	checks.check(battle.current.get("phase") == "flight", "ranged shot has explicit simulation flight phase")
	var hp_during_flight: int = enemy.stats[Stat.HP]
	for i in range(40): battle.advance(0.062)
	checks.check(enemy.stats[Stat.HP] < hp_during_flight, "ranged impact deals damage after flight")
	checks.check(actor.stats[Stat.HP] < actor.stats[Stat.MAX_HP], "enemy AI approaches and damages an ally")
	checks.check(drive(battle) and battle.outcome == &"victory", "unmodified test battle reaches victory")
	checks.check(battle.reward["xp_each"] == 13 and battle.reward["gold"] >= 5 and battle.reward["gold"] <= 30, "source squirrel reward: 13 XP each and 5–30 gold")
	var gold: int = game.gold
	var xp: int = game.hero.base_stats[Stat.EXPERIENCE]
	var events: int = battle.events.size()
	battle.advance(50.0)
	checks.check(game.gold == gold and game.hero.base_stats[Stat.EXPERIENCE] == xp and battle.events.size() == events, "victory freezes simulation and cannot duplicate reward")
	checks.check(battle.return_to_exploration() and game.mode == &"exploration", "victory returns to exploration")
	checks.check(game.hero.stats[Stat.HP] == game.hero.stats[Stat.MAX_HP] and not game.hero.dead and enemy.dead and not game.collision.units.has(enemy.instance_id), "recovery restores party and clears defeated enemy occupancy")
	checks.check(not battle.return_to_exploration() and game.gold == gold, "continue result is idempotent")
	_defeat_and_revive(checks, world, metadata, table, rewards)
	_fps(checks, world, metadata, table, rewards)
	checks.check(Rewards.threshold(0) == 50 and Rewards.threshold(1) == 125 and Rewards.threshold(2) == 237, "original XP thresholds use accumulated integer 3/2 growth")
	game.hero.base_stats[Stat.EXPERIENCE] = 49
	var points: int = game.hero.attribute_points
	Rewards.award(game, [enemy], LegacyRandom.new(7))
	checks.check(game.hero.base_stats[Stat.LEVEL] == 1 and game.hero.attribute_points == points + 5 and game.hero.skill_points == 1, "level up awards five attribute points and one skill point")


func _defeat_and_revive(checks, world: Dictionary, metadata: Dictionary, table: Dictionary, rewards: Dictionary) -> void:
	var pair := _fixture(world, metadata, table, rewards)
	var game = pair[0]
	var battle = pair[1]
	for ally in game.party:
		ally.stats[Stat.HP] = 0
		ally.dead = true
	battle._check_outcome()
	checks.check(battle.outcome == &"defeat" and game.gold == 0 and battle.reward.is_empty(), "defeat gives no gold or XP")
	checks.check(not battle.return_to_exploration() and not battle.can_input(), "defeat cannot resume exploration or issue commands")
	pair = _fixture(world, metadata, table, rewards)
	game = pair[0]
	battle = pair[1]
	game.hero.stats[Stat.HP] = 1
	game.party[1].dead = true
	game.party[1].stats[Stat.HP] = 0
	battle.wait_unit()
	for i in range(120):
		if battle.outcome != &"": break
		battle.advance(0.062)
	checks.check(battle.outcome == &"defeat" and game.hero.dead and game.gold == 0, "actual enemy attack can defeat last surviving ally without reward")
	pair = _fixture(world, metadata, table, rewards)
	game = pair[0]
	battle = pair[1]
	game.hero.dead = true
	game.hero.stats[Stat.HP] = 0
	var enemy = battle.unit(1001)
	enemy.dead = true
	enemy.stats[Stat.HP] = 0
	battle._check_outcome()
	checks.check(battle.outcome == &"victory" and battle.return_to_exploration() and not game.hero.dead and game.hero.stats[Stat.HP] > 0, "surviving ally's victory revives fallen leader")


func _fps(checks, world: Dictionary, metadata: Dictionary, table: Dictionary, rewards: Dictionary) -> void:
	var baseline: Dictionary = {}
	for fps in [30, 60, 144]:
		var pair := _fixture(world, metadata, table, rewards)
		var game = pair[0]
		var battle = pair[1]
		for frame in range(fps * 50):
			if battle.outcome != &"": break
			if battle.can_input(): battle._enemy_action(battle.unit(battle.selected_id))
			battle.advance(1.0 / fps)
		var hits: Array = []
		for event: Dictionary in battle.events:
			if event["event"] == "hit": hits.append([event["actor"], event["target"], event["damage"], event["hp"], event["multiplier"]])
		var result := {"outcome": str(battle.outcome), "reward": battle.reward, "gold": game.gold, "hero": game.hero.snapshot(), "ally": game.party[1].snapshot(), "rng": battle.rng.snapshot(), "hits": hits}
		if baseline.is_empty(): baseline = result
		checks.check(result == baseline and battle.outcome == &"victory", "whole battle and reward match at %d FPS" % fps)
