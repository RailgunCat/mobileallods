extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const StatusIcon = Ids.StatusIcon
const Stat = Ids.Stat
## q.a(q): all HP changes and random draws belong to simulation, never drawing.
const Effects = preload("res://scripts/gameplay/status_effects.gd")

static func change_hp(actor, amount: int) -> int:
	var before: int = actor.stats[Stat.HP]
	actor.stats[Stat.HP] = clampi(before + amount, 0, actor.stats[Stat.MAX_HP])
	return actor.stats[Stat.HP] - before


static func physical_payload(actor, ranged: bool, table: Dictionary) -> PackedInt32Array:
	var payload := PackedInt32Array()
	payload.resize(Stat.COUNT)
	payload[Stat.ARCHERY if ranged else Stat.ATTACK] = 1
	payload[Stat.PHYSICAL_DAMAGE] = actor.stats[Stat.PHYSICAL_DAMAGE]
	for slot in Ids.HIT_PROC_STATS: payload[slot] = actor.stats[slot]
	Effects.remove_slot(actor, table, Stat.VAMPIRISM_PERCENT)
	return payload


static func apply(attacker, defender, payload: PackedInt32Array, rng, table: Dictionary, moved: int = 0) -> Dictionary:
	defender.recalculate(table)
	var before: int = defender.stats[Stat.HP]
	var result := {"damage": 0, "blocked": false, "instant": false, "multiplier": 1, "counter": false, "revived": false, "shattered": false, "reset_movement": false}
	var attacker_stats: PackedInt32Array = attacker.stats
	var defender_stats: PackedInt32Array = defender.stats
	var undead: bool = defender.unit_type in Ids.UNDEAD_TYPES
	var black: int = payload[Stat.DARK_DAMAGE] - rng.bounded(1 + int(int(payload[Stat.DARK_DAMAGE] * 10 / 2.0) / float(10 + attacker_stats[Stat.LUCK])))
	if black != 0:
		if defender.dead:
			defender.shattered = true
			result["shattered"] = true
			return result
		change_hp(defender, -maxi(1, int(black / float(maxi(1, defender_stats[Stat.DARK_RESISTANCE])))))
	var white: int = payload[Stat.LIGHT_DAMAGE] - rng.bounded(1 + int(int(payload[Stat.LIGHT_DAMAGE] * 10 / 2.0) / float(10 + attacker_stats[Stat.LUCK])))
	if white != 0:
		if defender.dead:
			if undead:
				defender.shattered = true
				result["shattered"] = true
			else:
				defender.stats[Stat.HP] = 1
				defender.dead = false
				result["revived"] = true
			return result
		change_hp(defender, -maxi(1, int(white / float(maxi(1, defender_stats[Stat.LIGHT_RESISTANCE])))) if undead else maxi(1, int(white / 20.0)))
	var damage: int = payload[Stat.PHYSICAL_DAMAGE]
	if damage > 0:
		if defender.dead:
			defender.shattered = true
			result["shattered"] = true
			return result
		damage -= int(rng.bounded(damage + 1) / 4.0) + int(rng.bounded(int(damage * (attacker_stats[Stat.MAX_ACTION_POINTS] - attacker_stats[Stat.ACTION_POINTS]) / float(maxi(1, attacker_stats[Stat.MAX_ACTION_POINTS]))) + 1) / 2.0)
		damage = int(damage / 4.0)
		var rank: int = defender_stats[Stat.TACTICS] - 1
		if payload[Stat.ATTACK] != 0 and rank > 0: result["counter"] = rng.bounded(100) < rank * 4
		for skill in Ids.DEFENSE_SKILLS:
			rank = defender_stats[skill] - 1
			if rank > 0 and int(rank / 2.0) * 5 > rng.bounded(100):
				result["blocked"] = true
				return result
		rank = attacker_stats[Stat.ATTACK] - 1
		if payload[Stat.ATTACK] != 0 and rank > 0 and int(20 * 3 * int(rank / 2.0) / float(maxi(1, defender_stats[Stat.DARK_RESISTANCE]))) > rng.bounded(100):
			result["instant"] = true
		rank = attacker_stats[Stat.ASSASSINATION] - 1
		if payload[Stat.ARCHERY] != 0 and rank > 0 and int(20 * int(rank / 3.0) / float(maxi(1, defender_stats[Stat.DARK_RESISTANCE]))) > rng.bounded(100):
			result["instant"] = true
		if result["instant"]:
			result["damage"] = defender.stats[Stat.HP]
			defender.stats[Stat.HP] = 0
			return result
		if payload[Stat.SLOW_ON_HIT] != 0 and int(2000 * attacker.base_stats[Stat.LEVEL] / float(maxi(1, defender_stats[Stat.DARK_RESISTANCE]))) > rng.bounded(100):
			Effects.add(defender, table, Stat.MAX_ACTION_POINTS, -payload[Stat.SLOW_ON_HIT], 3, StatusIcon.SLOW)
			Effects.add(defender, table, Stat.ACTION_POINTS, -payload[Stat.SLOW_ON_HIT], 3, StatusIcon.NONE)
		if payload[Stat.STUN_CHANCE] > 0 and int(20 * payload[Stat.STUN_CHANCE] / float(maxi(1, defender_stats[Stat.DARK_RESISTANCE]))) > rng.bounded(100): Effects.add(defender, table, Stat.STUN, 1, 3, StatusIcon.STUN)
		rank = attacker_stats[Stat.TACTICS] - 1
		if payload[Stat.ATTACK] != 0 and rank > 0: damage += int(damage * int(rank / 2.0) * 3 * moved / 100.0)
		result["reset_movement"] = true
		damage = maxi(1, int(damage / float(maxi(1, defender_stats[Stat.PHYSICAL_RESISTANCE]))))
		result["physical_base"] = damage
		var critical: int = 10 if attacker.weapon != null and attacker.weapon.definition_id >= Ids.ItemId.FIRST_SWORD and attacker.weapon.definition_id <= Ids.ItemId.LAST_SWORD else 5
		var luck: int = attacker_stats[Stat.LUCK]
		while luck > 0:
			if rng.bounded(100) < (int(luck * critical / 5.0) if luck < 5 else critical): result["multiplier"] += 1
			luck -= 5
		var dealt: int = -change_hp(defender, -damage * int(result["multiplier"]))
		if payload[Stat.VAMPIRISM_PERCENT] != 0:
			var healing: int = maxi(1, int(dealt * payload[Stat.VAMPIRISM_PERCENT] / 100.0))
			change_hp(attacker, -healing if undead else healing)
		if dealt > 1 and payload[Stat.POISON_CHANCE] != 0 and rng.bounded(100) < payload[Stat.POISON_CHANCE]:
			var poison: int = dealt - 1
			var endurance: int = defender.stats[Stat.ENDURANCE]
			while endurance > 0:
				if rng.bounded(100) < mini(5, endurance): poison -= 1
				endurance -= 5
			if poison > 0: Effects.add(defender, table, Stat.POISON_DAMAGE, poison, 2 * poison, StatusIcon.POISON)
	defender.recalculate(table)
	result["damage"] = before - defender.stats[Stat.HP]
	return result
