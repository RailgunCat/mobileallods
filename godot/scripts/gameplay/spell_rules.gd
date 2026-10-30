extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Spell = Ids.Spell
const Stat = Ids.Stat
const PayloadKind = Ids.PayloadKind
const StatusIcon = Ids.StatusIcon
## Spell id 0..14 => s.action_table[2..16] => command 3..17.
const Rules = preload("res://scripts/gameplay/combat_rules.gd")
const Effects = preload("res://scripts/gameplay/status_effects.gd")

static func rank(actor, spell_id: int, definitions: Dictionary) -> int:
	var spell: Dictionary = definitions["spell_definitions"][spell_id]
	return int((actor.stats[int(spell["school_stat"])] - 1) / float(spell["rank_step"]))


static func learned(actor, spell_id: int, definitions: Dictionary, ai: bool = false) -> bool:
	if spell_id < 0 or spell_id >= Spell.COUNT: return false
	var spell: Dictionary = definitions["spell_definitions"][spell_id]
	# m.boolean_b() admits equality; the player spell menu keeps its own gate.
	if ai: return actor.stats[int(spell["school_stat"])] >= int(spell["rank_step"])
	return actor.stats[int(spell["school_stat"])] > int(spell["rank_step"])


static func cost(actor, spell_id: int, definitions: Dictionary) -> int:
	var base_mana: int = int(definitions["spell_definitions"][spell_id]["base_mana"])
	return base_mana + int(base_mana / 2.0) * rank(actor, spell_id, definitions)


static func payload(actor, spell_id: int, definitions: Dictionary) -> PackedInt32Array:
	var spell: Dictionary = definitions["spell_definitions"][spell_id]
	var result := PackedInt32Array()
	result.resize(Stat.COUNT)
	var power: int = int(spell["base_power"])
	if int(spell["payload_kind"]) == PayloadKind.DARK_MAGIC:
		result[Stat.DARK_FIRE_MAGIC] = 1
		power += int(power * rank(actor, spell_id, definitions) / 2.0)
		result[Stat.DARK_DAMAGE] = (actor.stats[Stat.DARK_DAMAGE] + power) * actor.stats[Stat.DARK_POWER]
	elif int(spell["payload_kind"]) == PayloadKind.LIGHT_MAGIC:
		result[Stat.LIGHT_FIRE_MAGIC] = 1
		if spell_id == Spell.HEAL: power += int(power * rank(actor, spell_id, definitions) / 2.0)
		result[Stat.LIGHT_DAMAGE] = (actor.stats[Stat.LIGHT_ABSORPTION] + power) * actor.stats[Stat.LIGHT_POWER]
	return result


static func target_valid(battle, actor, spell_id: int, cell: Vector2i) -> bool:
	if not battle.arena.has_point(cell) or absi(cell.x - actor.cell.x) + absi(cell.y - actor.cell.y) > actor.stats[Stat.ATTACK_RANGE]: return false
	if spell_id == Spell.FIRE_WALL and cell == actor.cell: return false # Avoid the source's zero-distance division.
	var target = battle.actor_at(cell)
	if target != null and target.shattered: return false
	if spell_id == Spell.HEAL: return target != null and (target.side_id == actor.side_id or target.unit_type in Ids.UNDEAD_TYPES)
	if spell_id in [Spell.VAMPIRISM, Spell.HASTE, Spell.BLESS, Spell.STONE_SKIN]: return target != null and not target.dead and target.side_id == actor.side_id
	if spell_id in [Spell.SLOW, Spell.PETRIFY]: return target != null and not target.dead and target.side_id != actor.side_id
	if spell_id in [Spell.FIRE_ARROW, Spell.SPARK]: return target != null and target.side_id != actor.side_id
	return target != null or not battle.session.collision.is_terrain_blocked(cell)


static func damage_cells(actor, spell_id: int, cell: Vector2i, definitions: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if spell_id == Spell.LIGHTNING:
		# Preserve the source's Frost-school radius and center/arm hit order.
		cells.append(cell)
		for distance in range(1, rank(actor, Spell.FROST, definitions)):
			for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]: cells.append(cell + direction * distance)
	elif spell_id == Spell.FIREBALL:
		var extent: int = rank(actor, spell_id, definitions)
		for y in range(cell.y - extent - 1, cell.y + extent + 1):
			for x in range(cell.x - extent - 1, cell.x + extent + 1):
				if absi(x - cell.x) + absi(y - cell.y) <= extent: cells.append(Vector2i(x, y))
	return cells


static func frost_pair(battle, actor, point: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [point, point + Vector2i.RIGHT]
	for cell in cells:
		var occupant = battle.actor_at(cell)
		if (occupant != null and occupant.side_id == actor.side_id) or (occupant == null and battle.session.collision.is_terrain_blocked(cell)): return []
	return cells


static func miasma_cells(anchor: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var left: int = int((anchor.x * 16 - 25) / 16.0)
	var top: int = int((anchor.y * 16 - 20) / 16.0)
	for y in range(top, top + 4):
		for x in range(left, left + 4): cells.append(Vector2i(x, y))
	return cells


static func fire_wall_cells(battle, actor, cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for pixels: Vector2i in wall_positions(actor, cell, battle.session.definitions):
		var point := Vector2i(int(pixels.x / 16.0), int((pixels.y - 8) / 16.0))
		if battle.actor_at(point) == null:
			if battle.session.collision.is_terrain_blocked(point): continue
			if point.y * 16 < pixels.y - 8 and battle.session.collision.is_terrain_blocked(point + Vector2i.DOWN): continue
			if point.x * 16 < pixels.x - 8 and battle.session.collision.is_terrain_blocked(point + Vector2i.RIGHT): continue
		cells.append(point)
	return cells


static func area_preview(battle, actor, spell_id: int, cell: Vector2i) -> Dictionary:
	var cells: Array[Vector2i] = []
	var possible: Array[Vector2i] = []
	var caption: String = ""
	match spell_id:
		Spell.LIGHTNING, Spell.FIREBALL:
			cells = damage_cells(actor, spell_id, cell, battle.session.definitions)
			caption = "Молния · область удара" if spell_id == Spell.LIGHTNING else "Огненный шар · область взрыва"
		Spell.FROST:
			cells = frost_pair(battle, actor, cell)
			if rank(actor, spell_id, battle.session.definitions) > 1:
				for y in [-2, 0, 2]:
					for x in [-2, 0, 2]:
						for point in frost_pair(battle, actor, cell + Vector2i(x, y)):
							if point not in cells and point not in possible: possible.append(point)
			caption = "Мороз · пунктир: случайные осколки"
		Spell.MIASMA:
			cells = miasma_cells(cell)
			caption = "Миазмы · 4×4 · урон каждый раунд"
		Spell.FIRE_WALL:
			cells = fire_wall_cells(battle, actor, cell)
			caption = "Стена огня · урон каждый раунд"
		_: return {}
	var visible: Array[Vector2i] = []
	var uncertain: Array[Vector2i] = []
	var allies: Array[Vector2i] = []
	for point in cells:
		if battle.session.collision.contains(point) and point not in visible: visible.append(point)
	for point in possible:
		if battle.session.collision.contains(point) and point not in uncertain: uncertain.append(point)
	if spell_id in [Spell.MIASMA, Spell.FIRE_WALL]:
		for point in visible:
			var victim = battle.actor_at(point)
			if victim != null and not victim.dead and victim.side_id == actor.side_id: allies.append(point)
	if not allies.is_empty(): caption += " · союзник в зоне!"
	return {"cells": visible, "possible": uncertain, "allies": allies, "target": cell, "spell": spell_id, "caption": caption}


static func impact(battle, actor, spell_id: int, cell: Vector2i) -> void:
	var target = battle.actor_at(cell)
	if battle.session.god_mode and target in battle.session.party and actor.side_id != target.side_id: return
	var spell_rank: int = rank(actor, spell_id, battle.session.definitions)
	var table: Dictionary = battle.session.ability_table
	match spell_id:
		Spell.FIRE_ARROW, Spell.HEAL, Spell.SPARK, Spell.METEOR:
			if target != null: battle.apply_payload(actor, target, payload(actor, spell_id, battle.session.definitions), spell_id)
		Spell.LIGHTNING:
			for point in damage_cells(actor, spell_id, cell, battle.session.definitions):
				var victim = battle.actor_at(point)
				if victim != null and victim.side_id != actor.side_id: battle.apply_payload(actor, victim, payload(actor, spell_id, battle.session.definitions), spell_id)
		Spell.SLOW:
			Effects.add(target, table, Stat.MAX_ACTION_POINTS, -spell_rank, spell_rank, StatusIcon.SLOW)
		Spell.FROST:
			var cells: Array[Vector2i] = [cell]
			for i in range(1, spell_rank): cells.append(cell + Vector2i((battle.rng.bounded(3) - 1) * 2, (battle.rng.bounded(3) - 1) * 2))
			for point in cells:
				var seen: Array[int] = []
				for hit_cell in frost_pair(battle, actor, point):
					var victim = battle.actor_at(hit_cell)
					if victim != null and victim.side_id != actor.side_id and victim.instance_id not in seen:
						battle.apply_payload(actor, victim, payload(actor, spell_id, battle.session.definitions), spell_id)
						seen.append(victim.instance_id)
		Spell.VAMPIRISM: Effects.add(target, table, Stat.VAMPIRISM_PERCENT, 10 * spell_rank, -1, StatusIcon.VAMPIRISM)
		Spell.MIASMA:
			var duration: int = int(actor.stats[Stat.DARK_AIR_MAGIC] / 3.0) / 2 + 1
			battle.hazards.append({"spell": spell_id, "actor": actor.instance_id, "cell": cell, "duration": duration})
		Spell.FIRE_WALL:
			for point in fire_wall_cells(battle, actor, cell):
				battle.hazards.append({"spell": spell_id, "actor": actor.instance_id, "cell": point, "duration": 4})
		Spell.FIREBALL:
			# ag(): loops cells, so large footprints can receive repeated hits.
			for point in damage_cells(actor, spell_id, cell, battle.session.definitions):
				var victim = battle.actor_at(point)
				if victim != null and victim.side_id != actor.side_id: battle.apply_payload(actor, victim, payload(actor, spell_id, battle.session.definitions), spell_id)
		Spell.PETRIFY:
			if int(2000 * spell_rank / float(maxi(1, target.stats[Stat.DARK_RESISTANCE]))) > battle.rng.bounded(100):
				Effects.add(target, table, Stat.PHYSICAL_RESISTANCE, target.base_stats[Stat.PHYSICAL_RESISTANCE], spell_rank, StatusIcon.PETRIFY)
				target.petrify_rounds = spell_rank
		Spell.HASTE: Effects.add(target, table, Stat.MAX_ACTION_POINTS, spell_rank, spell_rank, StatusIcon.HASTE)
		Spell.BLESS:
			Effects.add(target, table, Stat.LUCK, 10 * spell_rank, 5, StatusIcon.BLESS)
			Effects.add(target, table, Stat.STRENGTH, 5 * spell_rank, 5, StatusIcon.NONE)
		Spell.STONE_SKIN:
			# m.J() reads rank from blessing row 15, not stone row 16.
			var blessing: int = rank(actor, Spell.BLESS, battle.session.definitions)
			Effects.add(target, table, Stat.PHYSICAL_RESISTANCE, blessing * 10, blessing, StatusIcon.STONE_SKIN)
			Effects.add(target, table, Stat.DARK_RESISTANCE, blessing * 10, blessing, StatusIcon.NONE)
	battle._record("spell_impact", {"actor": actor.instance_id, "spell": spell_id, "cell": [cell.x, cell.y]})


static func _trig(degrees: int, definitions: Dictionary, cosine: bool) -> int:
	var angle: int = posmod(degrees, 360)
	var quadrant: int = int(angle / 90.0)
	var key: String = "cos" if (quadrant % 2 == 0) == cosine else "sin"
	var negative: bool = quadrant in [1, 2] if cosine else quadrant in [2, 3]
	return int(definitions["trig"][key][angle % 90]) * (-1 if negative else 1)


static func wall_positions(actor, cell: Vector2i, definitions: Dictionary) -> Array[Vector2i]:
	# n.void_a() + o.b(int), including its first-quadrant angle lookup and
	# exclusive loop bounds (rank 3 still creates only the center segment).
	var pixels := Vector2i(cell * 16 + Vector2i(8, 8))
	var delta := pixels - Vector2i(actor.position_pixels)
	var length: int = maxi(1, integer_root(delta.length_squared()))
	var cosine: int = int(delta.x * 10000 / float(length))
	var angle: int = 0
	var best: int = 100000
	for index in range(90):
		var distance: int = absi(cosine - int(definitions["trig"]["cos"][index]))
		if distance < best:
			angle = index
			best = distance
	var points: Array[Vector2i] = [pixels]
	var count: int = rank(actor, Spell.FIRE_WALL, definitions)
	for sign in [1, -1]:
		var limit: int = int((count if sign > 0 else count - 1) / 2.0)
		for i in range(1, limit):
			points.append(pixels + Vector2i(int(i * 16 * _trig(angle + sign * 90, definitions, true) / 10000.0), int(i * 16 * _trig(angle + sign * 90, definitions, false) / 10000.0)))
	return points


static func integer_root(value: int) -> int:
	# Exact m.int_c(), whose integer Newton rounding is not floor(sqrt()).
	if value <= 0: return 0
	var result: int = value
	var guess: int = (16383 if (value & 0xff000000) > 0 else 1023) if (value & 0xffff0000) > 0 else (63 if (value & 0xff00) > 0 else (7 if value > 4 else value))
	while true:
		var total: int = int(value / float(guess)) + guess
		guess = int(total / 2.0) + (total & 1)
		if result <= guess: break
		result = guess
	if int(value / float(result)) == result - 1 and value % result == 0: result -= 1
	return result
