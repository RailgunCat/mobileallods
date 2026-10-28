extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Stat = Ids.Stat

const Stats = preload("res://scripts/gameplay/unit_stats.gd")
const Inventory = preload("res://scripts/gameplay/inventory_rules.gd")


static func award(game, defeated: Array, rng) -> Dictionary:
	var xp: int = 0
	var gold: int = 0
	var scale: int = 100
	var items: Array[int] = []
	var party_luck: int = 0
	for actor in game.party: party_luck += actor.stats[Stat.LUCK]
	var loot_progress: int = Inventory.progress(game) - 1
	var map_index: int = game.location_id if game.location_id >= 0 else -game.location_id - 1
	for level in range(maxi(0, map_index)): scale = int(scale * 11 / 10.0)
	for actor in defeated:
		for row: Dictionary in game.reward_table.get("rows", []):
			if int(row["row_id"]) != actor.unit_type: continue
			var reward: Dictionary = row["reward"]
			xp += int(int(reward["base_experience"]) * scale / 100.0)
			var minimum_gold: int = int(reward["minimum_gold"])
			var maximum_gold: int = int(reward["maximum_gold"])
			gold += int((minimum_gold + rng.bounded(maximum_gold - minimum_gold + 1)) * scale / 100.0)
			for drop: Dictionary in reward.get("drops", []):
				var id: int = int(drop["definition_id"])
				var chance: int = int(drop["chance"])
				if chance >= 0:
					if int(Inventory.definition(game, id)["unlock_progress"]) > loot_progress: continue
					if rng.bounded(10000) >= int(chance * scale * (100 + party_luck) / 10000.0): continue
				Inventory.add(game, id)
				items.append(id)
	game.gold += gold
	var levels: Dictionary = {}
	for actor in game.party:
		var before: int = actor.base_stats[Stat.LEVEL]
		actor.base_stats[Stat.EXPERIENCE] += xp
		while actor.base_stats[Stat.EXPERIENCE] >= threshold(actor.base_stats[Stat.LEVEL]):
			actor.base_stats[Stat.LEVEL] += 1
			actor.attribute_points += 5
			actor.skill_points += 1
		actor.stats = Stats.calculate(actor.base_stats, game.ability_table, actor.weapon, actor.armor, actor.stats)
		levels[str(actor.instance_id)] = actor.base_stats[Stat.LEVEL] - before
	return {"xp_each": xp, "xp_total": xp * game.party.size(), "gold": gold, "levels": levels, "items": items}


static func threshold(level: int) -> int:
	var total: int = 50
	var step: int = 50
	for i in range(level):
		step = int(step * 3 / 2.0)
		total += step
	return total
