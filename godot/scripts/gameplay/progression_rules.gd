extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Stat = Ids.Stat
const Stats = preload("res://scripts/gameplay/unit_stats.gd")
const ATTRIBUTES = [Stat.ENDURANCE, Stat.INTELLECT, Stat.STRENGTH, Stat.DEXTERITY, Stat.LUCK]
## g case 12: only already-known schools, one point per rank, cap 25.
## Edits remain a draft until confirmation; cancel never mutates the actor.

static func available(game, actor) -> bool:
	return actor != null and actor in game.party and game.mode in [&"exploration", &"management"]


static func begin(game, actor) -> Dictionary:
	if not available(game, actor): return {}
	return {"actor": actor.instance_id, "original": actor.base_stats.duplicate(), "base": actor.base_stats.duplicate(), "attribute_points": actor.attribute_points, "skill_points": actor.skill_points, "original_attribute_points": actor.attribute_points, "original_skill_points": actor.skill_points}


static func editable(draft: Dictionary, slot: int) -> bool:
	return slot in ATTRIBUTES or (slot >= Stat.ATTACK and slot < Stat.RESERVED and draft["original"][slot] > 0)


static func adjust(draft: Dictionary, slot: int, delta: int) -> bool:
	if draft.is_empty() or delta not in [-1, 1] or not editable(draft, slot): return false
	var key: String = "attribute_points" if slot in ATTRIBUTES else "skill_points"
	if delta > 0 and (int(draft[key]) <= 0 or (slot not in ATTRIBUTES and draft["base"][slot] >= 25)): return false
	if delta < 0 and draft["base"][slot] <= draft["original"][slot]: return false
	draft["base"][slot] += delta
	draft[key] -= delta
	return true


static func preview(game, actor, draft: Dictionary) -> PackedInt32Array:
	return Stats.calculate(draft["base"], game.ability_table, actor.weapon, actor.armor, actor.stats)


static func commit(game, actor, draft: Dictionary) -> bool:
	if draft.is_empty() or not available(game, actor) or actor.instance_id != draft["actor"]: return false
	if actor.base_stats != draft["original"] or actor.attribute_points != draft["original_attribute_points"] or actor.skill_points != draft["original_skill_points"]: return false
	var attributes: int = 0
	var skills: int = 0
	for slot in range(Stat.COUNT):
		var change: int = draft["base"][slot] - actor.base_stats[slot]
		if change < 0 or (change != 0 and not editable(draft, slot)): return false
		if slot in ATTRIBUTES: attributes += change
		else:
			if change > 0 and draft["base"][slot] > 25: return false
			skills += change
	if attributes > actor.attribute_points or skills > actor.skill_points: return false
	actor.base_stats = draft["base"].duplicate()
	actor.attribute_points -= attributes
	actor.skill_points -= skills
	actor.recalculate(game.ability_table)
	game.changed.emit()
	return true
