extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Stat = Ids.Stat
## Indexed slots deliberately match q.i[57]. Integer divisions truncate as Java.
## Damage slot 30 retains its original fixed-point units, not displayed HP.

const SLOT_COUNT: int = Stat.COUNT


static func named(values: PackedInt32Array) -> Dictionary:
	var result: Dictionary = {}
	for key: String in Stat:
		var slot: int = Stat[key]
		if slot < values.size(): result[key.to_lower()] = values[slot]
	return result


static func row(table: Dictionary, id: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(SLOT_COUNT)
	for entry: Dictionary in table["rows"]:
		if int(entry["row_id"]) == id:
			for i in range(mini(SLOT_COUNT, entry["values"].size())):
				result[i] = int(entry["values"][i])
			return result
	push_error("Missing abilities row %d" % id)
	return result


static func _add(values: PackedInt32Array, extra: PackedInt32Array, weapon: bool = false) -> void:
	for i in range(SLOT_COUNT):
		if not weapon or i != Stat.PIERCING:
			values[i] += extra[i]


static func calculate(base: PackedInt32Array, table: Dictionary, weapon, armor, previous := PackedInt32Array(), effects: Array = []) -> PackedInt32Array:
	var values := base.duplicate()
	for effect: Dictionary in effects: values[int(effect["slot"])] += int(effect["value"])
	if armor != null:
		_add(values, row(table, Ids.AbilityRow.ITEM_BASE + armor.definition_id))
		for crystal: int in armor.sockets:
			if crystal >= Ids.ItemId.FIRST_CRYSTAL:
				_add(values, row(table, crystal - Ids.ItemId.FIRST_CRYSTAL))
	if weapon != null:
		_add(values, row(table, Ids.AbilityRow.ITEM_BASE + weapon.definition_id), true)
		for crystal: int in weapon.sockets:
			if crystal >= Ids.ItemId.FIRST_CRYSTAL:
				var weapon_family: int = int((weapon.definition_id - Ids.ItemId.FIRST_SWORD) / float(Ids.ItemId.STARTING_WEAPON_STRIDE))
				var crystal_row: int = Ids.AbilityRow.WEAPON_CRYSTAL_BASE + crystal - Ids.ItemId.FIRST_CRYSTAL + weapon_family * Ids.CRYSTALS_PER_WEAPON_FAMILY
				_add(values, row(table, crystal_row))
	var scale: int = 100
	for level in range(values[Stat.LEVEL]):
		scale = int(scale * 11 / 10.0)
	values[Stat.MAX_HP] = int((values[Stat.MAX_HP] + values[Stat.ENDURANCE]) * scale / 100.0)
	values[Stat.MAX_MANA] += values[Stat.INTELLECT] + values[Stat.LEVEL]
	values[Stat.MANA_REGEN] += 1 + values[Stat.LEVEL]
	values[Stat.MAX_ACTION_POINTS] += int(values[Stat.DEXTERITY] / 15.0) + int(values[Stat.LEVEL] / 5.0)
	values[Stat.ATTACK_RANGE] += int(values[Stat.DEXTERITY] / 10.0) + int(base[Stat.LEVEL] / 5.0)
	values[Stat.PHYSICAL_RESISTANCE] += 20 + values[Stat.DEXTERITY] + base[Stat.LEVEL] + int(values[Stat.ENDURANCE] / 2.0)
	values[Stat.DARK_RESISTANCE] += 20 + values[Stat.LUCK] + base[Stat.LEVEL] + int(values[Stat.ENDURANCE] / 2.0)
	values[Stat.LIGHT_RESISTANCE] = 20
	values[Stat.PHYSICAL_DAMAGE] += 10 + base[Stat.LEVEL] + base[Stat.STRENGTH]
	values[Stat.PHYSICAL_POWER] += 20 + int(base[Stat.DEXTERITY] / 5.0)
	values[Stat.DARK_DAMAGE] += base[Stat.LEVEL] + int(values[Stat.INTELLECT] / 10.0)
	values[Stat.DARK_POWER] += 20 + int(values[Stat.LUCK] / 5.0)
	values[Stat.LIGHT_DAMAGE] += base[Stat.LEVEL] + int(values[Stat.INTELLECT] / 10.0)
	values[Stat.LIGHT_POWER] += 20 + int(values[Stat.LUCK] / 5.0)
	var skill: int = maxi(0, values[Stat.ATTACK] - 1)
	values[Stat.PHYSICAL_POWER] += int(values[Stat.PHYSICAL_POWER] * 10 * skill / 100.0)
	for slot in Ids.DEFENSE_SKILLS:
		skill = maxi(0, values[slot] - 1)
		values[Stat.PHYSICAL_RESISTANCE] += int(values[Stat.PHYSICAL_RESISTANCE] * 10 * skill / 100.0)
		values[Stat.HP_REGEN_PERCENT] += 5 * int(skill / 3.0)
	values[Stat.MAX_ACTION_POINTS] += int(maxi(0, values[Stat.TACTICS] - 1) / 3.0)
	skill = maxi(0, values[Stat.ARCHERY] - 1)
	values[Stat.PHYSICAL_POWER] += int(values[Stat.PHYSICAL_POWER] * 10 * skill / 100.0)
	values[Stat.RANGE_ON_HIT] += int(skill / 2.0)
	skill = maxi(0, values[Stat.ASSASSINATION] - 1)
	values[Stat.MAX_ACTION_POINTS] += skill
	values[Stat.POISON_CHANCE] += 5 * int(skill / 2.0)
	for slot in Ids.MINIMUM_RESISTANCE_STATS:
		values[slot] = maxi(20, values[slot])
	values[Stat.PHYSICAL_DAMAGE] *= values[Stat.PHYSICAL_POWER]
	values[Stat.PHYSICAL_POWER] = 0
	values[Stat.MANA_REGEN] = mini(30, values[Stat.MANA_REGEN])
	values[Stat.MAX_ACTION_POINTS] = clampi(values[Stat.MAX_ACTION_POINTS], 1, 20)
	values[Stat.VAMPIRISM_PERCENT] = mini(100, values[Stat.VAMPIRISM_PERCENT])
	values[Stat.ATTACK_RANGE] = clampi(values[Stat.ATTACK_RANGE], 0, 40)
	if previous.size() == SLOT_COUNT:
		values[Stat.HP] = previous[Stat.HP]
		values[Stat.MANA] = previous[Stat.MANA]
		values[Stat.ACTION_POINTS] = clampi(values[Stat.MAX_ACTION_POINTS] - (previous[Stat.MAX_ACTION_POINTS] - previous[Stat.ACTION_POINTS]), 0, 40)
	else:
		# Stage-one ready-to-play snapshot: fill resources, as battle setup does.
		values[Stat.HP] = values[Stat.MAX_HP]
		values[Stat.MANA] = values[Stat.MAX_MANA]
		values[Stat.ACTION_POINTS] = values[Stat.MAX_ACTION_POINTS]
	return values
