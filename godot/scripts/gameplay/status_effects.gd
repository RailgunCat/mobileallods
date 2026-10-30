extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Stat = Ids.Stat
## q.a(slot,value,duration,icon) merges by slot, never stacks weaker duplicates.

static func add(actor, table: Dictionary, slot: int, value: int, duration: int, icon: int) -> void:
	for effect: Dictionary in actor.effects:
		if int(effect["slot"]) != slot: continue
		effect["value"] = maxi(int(effect["value"]), value) if value > 0 else mini(int(effect["value"]), value)
		effect["duration"] = duration
		effect["icon"] = icon
		actor.recalculate(table)
		return
	actor.effects.append({"slot": slot, "value": value, "duration": duration, "icon": icon})
	actor.recalculate(table)


static func remove_slot(actor, table: Dictionary, slot: int) -> void:
	for i in range(actor.effects.size() - 1, -1, -1):
		if int(actor.effects[i]["slot"]) == slot: actor.effects.remove_at(i)
	actor.recalculate(table)


static func start_turn(actor, table: Dictionary, rng) -> Dictionary:
	if actor.dead: return {}
	var poison: Dictionary = {}
	for i in range(actor.effects.size() - 1, -1, -1):
		var effect: Dictionary = actor.effects[i]
		if int(effect["duration"]) > 0: effect["duration"] -= 1
		if int(effect["duration"]) == 0: actor.effects.remove_at(i)
		if int(effect["slot"]) == Stat.POISON_DAMAGE: poison = effect
	actor.recalculate(table)
	var damage: int = maxi(0, actor.stats[Stat.POISON_DAMAGE])
	actor.stats[Stat.HP] -= damage
	if damage > 0:
		var remaining: int = damage
		var endurance: int = actor.stats[Stat.ENDURANCE]
		while endurance > 0:
			if rng.bounded(100) < mini(5, endurance): remaining -= 1
			endurance -= 5
		remaining -= 1
		if remaining <= 0: actor.effects.erase(poison)
		elif not poison.is_empty():
			poison["value"] = remaining
			poison["duration"] = 2 * remaining
	actor.stats[Stat.MANA] = mini(actor.stats[Stat.MAX_MANA], actor.stats[Stat.MANA] + actor.stats[Stat.MANA_REGEN])
	var healing: int = maxi(0, int(actor.stats[Stat.MAX_HP] * actor.stats[Stat.HP_REGEN_PERCENT] / 100.0))
	healing = mini(healing, maxi(0, actor.stats[Stat.MAX_HP] - actor.stats[Stat.HP]))
	actor.stats[Stat.HP] = clampi(actor.stats[Stat.HP] + healing, 0, actor.stats[Stat.MAX_HP])
	return {"poison": damage, "regeneration": healing}
