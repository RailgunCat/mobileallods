extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const StoryGroup = Ids.StoryGroup
const UnitKind = Ids.UnitKind
const Facing = Ids.Facing
const StatusIcon = Ids.StatusIcon
const Spell = Ids.Spell
const Side = Ids.Side
const Stat = Ids.Stat
## Deterministic command runner. Damage and projectile impacts run on simulation
## ticks; rendering only reads the resulting state.

signal presentation_event(event: Dictionary)
signal combat_text(point: Vector2, message: String)
signal spell_impact(spell: int, cell: Vector2i, tick: int)
signal presentation_reset
signal changed
signal side_changed(side: int, round_number: int)
const Encounter = preload("res://scripts/gameplay/encounter_builder.gd")
const Grid = preload("res://scripts/gameplay/battle_grid.gd")
const Collision = preload("res://scripts/gameplay/map_collision.gd")
const Pathfinder = preload("res://scripts/gameplay/grid_pathfinder.gd")
const LegacyRandom = preload("res://scripts/gameplay/legacy_random.gd")
const Rules = preload("res://scripts/gameplay/combat_rules.gd")
const Spells = preload("res://scripts/gameplay/spell_rules.gd")
const Effects = preload("res://scripts/gameplay/status_effects.gd")
const Rewards = preload("res://scripts/gameplay/battle_rewards.gd")

var session
var active: bool = false
var arena := Rect2i()
var participants: Array[int] = []
var state: Dictionary[int, Dictionary] = {}
var current_side: int = 0
var round_number: int = 1
var turn_serial: int = 0
var selected_id: int = -1
var queue: Array[Dictionary] = []
var current: Dictionary = {}
var events: Array[Dictionary] = []
var pathfinder := Pathfinder.new()
var accumulator: float = 0.0
var tick_count: int = 0
var stalled: bool = false
var _tick_seconds: float = 0.062
var seed_value: int = -1 # Nonnegative values explicitly pin a test/replay seed.
var _battle_seed: int = 0
var rng := LegacyRandom.new()
var loot_rng := LegacyRandom.new()
var enemy_policy: StringName = &"combat"
var outcome: StringName = &""
var reward: Dictionary = {}
var feedback: Dictionary = {}
var hazards: Array[Dictionary] = []
var finale: Dictionary = {}
const FINALE_FALL_TICKS: int = 14
const FINALE_AFTER_TICKS: int = 12


func reset() -> void:
	if session != null:
		for id: int in state:
			var actor = unit(id)
			if actor != null:
				actor.effects.clear()
				actor.petrify_rounds = 0
				actor.recalculate(session.ability_table)
				actor.walking = false
		if active: session.mode = &"exploration"
	active = false
	queue.clear()
	current = {}
	participants.clear()
	state.clear()
	events.clear()
	presentation_reset.emit()
	selected_id = -1
	session = null
	pathfinder = Pathfinder.new()
	arena = Rect2i()
	round_number = 1
	current_side = Side.PARTY
	turn_serial = 0
	accumulator = 0
	tick_count = 0
	stalled = false
	outcome = &""
	reward = {}
	feedback = {}
	hazards.clear()
	finale.clear()


func unit(id: int):
	if session == null: return null
	for actor in session.units:
		if actor.instance_id == id: return actor
	return null


func busy() -> bool:
	return not finale.is_empty() or not queue.is_empty() or not current.is_empty()


func _record(kind: String, detail: Dictionary = {}) -> void:
	var event := {"event": kind, "tick": tick_count, "side": current_side, "round": round_number, "turn": turn_serial}
	event.merge(detail)
	events.append(event)
	presentation_event.emit(event)


func begin(game, triggers: Array) -> bool:
	if active or game.mode != &"exploration" or triggers.is_empty(): return false
	session = game
	var ids_triggered: Array[int] = []
	for id: Variant in triggers:
		if not id is int: continue
		var actor = unit(id)
		if actor != null and actor not in game.party and not actor.dead and actor.encounter_enabled and game.is_active(actor): ids_triggered.append(id)
	if ids_triggered.is_empty(): return false
	var description: Dictionary = Encounter.build(game, ids_triggered, true)
	var bounds: Rect2i = description["arena"]
	var ids: Array[int] = description["unit_ids"]
	var hostile: bool = false
	for id in ids:
		var actor = unit(id)
		if actor.side_id != Side.PARTY and actor.encounter_enabled: hostile = true
	if not hostile: return false
	# Plan all placements first. Exploration allows overlapping party members;
	# combat requires distinct, legal footprints. Failed setup changes nothing.
	var placement := Collision.new()
	placement.width = game.collision.width
	placement.height = game.collision.height
	placement.terrain = game.collision.terrain.duplicate()
	for id: int in game.collision.units:
		if id not in ids:
			var rect: Rect2i = game.collision.units[id]
			placement.occupy(id, rect.position, rect.size)
	var chosen: Dictionary[int, Vector2i] = {}
	for id in ids:
		var actor = unit(id)
		var anchor: Vector2i = game.hero.cell if Encounter.needs_regroup(game, actor) else actor.cell
		var best := Vector2i(-1, -1)
		var score: int = 2147483647
		for y in range(bounds.position.y, bounds.end.y):
			for x in range(bounds.position.x, bounds.end.x):
				var cell := Vector2i(x, y)
				if not bounds.encloses(Rect2i(cell, actor.footprint)) or not placement.can_stand(cell, actor.footprint): continue
				var distance: int = absi(x - anchor.x) + absi(y - anchor.y)
				if distance < score:
					score = distance
					best = cell
		if best.x < 0: return false
		chosen[id] = best
		placement.place(id, best, actor.footprint)
	arena = _connected_arena(bounds, placement, chosen, ids)
	participants.assign(ids)
	state.clear()
	queue.clear()
	current.clear()
	events.clear()
	presentation_reset.emit()
	tick_count = 0
	accumulator = 0
	turn_serial = 0
	round_number = 1
	stalled = false
	_tick_seconds = float(game.definitions["battle"]["tick_ms"]) / 1000.0
	outcome = &""
	reward = {}
	feedback = {}
	_battle_seed = seed_value if seed_value >= 0 else randi()
	rng = LegacyRandom.new(_battle_seed)
	loot_rng = LegacyRandom.new(_battle_seed ^ 0x1337)
	game.collision = placement
	for id in participants:
		var actor = unit(id)
		actor.move_to(chosen[id])
		actor.reset_interpolation()
		actor.walking = false
		actor.stats[Stat.HP] = actor.stats[Stat.MAX_HP]
		actor.stats[Stat.MANA] = actor.stats[Stat.MAX_MANA]
		state[id] = {"ended": false, "movement_spent": 0, "physical": actor.stats[Stat.PHYSICAL_RESISTANCE], "black": actor.stats[Stat.DARK_RESISTANCE], "defense_physical": 0, "defense_black": 0}
		_apply_defense(actor)
	active = true
	game.mode = &"battle"
	_record("battle_started", {"participants": Array(participants)})
	_start_side(0)
	changed.emit()
	return true


func _connected_arena(bounds: Rect2i, collision, positions: Dictionary, ids: Array[int]) -> Rect2i:
	# The legacy camera rectangle can cut the only corridor around a wall.
	# Include a terrain-valid approach for each hostile before fixing the arena.
	var terrain := Collision.new()
	terrain.width = collision.width
	terrain.height = collision.height
	terrain.terrain = collision.terrain
	var result: Rect2i = bounds
	for id: int in ids:
		var actor = unit(id)
		if actor in session.party or not actor.encounter_enabled: continue
		var finder := Pathfinder.new()
		finder.build(terrain, positions[id], actor.footprint)
		var best := Vector2i(-1, -1)
		var best_cost: int = 1000
		for ally in session.party:
			if not positions.has(ally.instance_id): continue
			var target := {"cell": positions[ally.instance_id], "footprint": ally.footprint}
			for y in range(target.cell.y - actor.footprint.y, target.cell.y + ally.footprint.y + 1):
				for x in range(target.cell.x - actor.footprint.x, target.cell.x + ally.footprint.x + 1):
					var cell := Vector2i(x, y)
					if _adjacent(cell, actor.footprint, target) and finder.distance(cell) < best_cost:
						best_cost = finder.distance(cell)
						best = cell
		if best.x < 0: continue
		var route: Dictionary = finder.route(best)
		if not route["reachable"]: continue
		for cell: Vector2i in route["path"]: result = result.merge(Rect2i(cell, actor.footprint))
	return result.intersection(Rect2i(0, 0, terrain.width, terrain.height))


func eligible(actor) -> bool:
	return actor != null and actor.instance_id in participants and not actor.dead and not actor.petrified() and session.is_active(actor) and actor.stats[Stat.HP] > 0 and actor.stats[Stat.STUN] == 0 and actor.stats[Stat.ACTION_POINTS] > 0 and not state[actor.instance_id]["ended"] and (actor in session.party or actor.encounter_enabled)


func can_input() -> bool:
	return active and session.mode == &"battle" and outcome == &"" and current_side == Side.PARTY and not busy() and not stalled


func select(id: int) -> bool:
	var actor = unit(id)
	if not can_input() or actor == null or actor.side_id != current_side or not eligible(actor): return false
	selected_id = id
	rebuild_paths()
	changed.emit()
	return true


func rebuild_paths() -> void:
	if selected_id < 0: return
	var actor = unit(selected_id)
	pathfinder.build(Grid.new(session.collision, arena), actor.cell, actor.footprint, actor.instance_id)


func preview(target: Vector2i) -> Dictionary:
	var result := {"reachable": false, "affordable": false, "path": [], "cost": 0, "requested": target}
	if not can_input() or selected_id < 0 or not arena.has_point(target): return result
	rebuild_paths()
	result = pathfinder.route(target)
	result["affordable"] = result["reachable"] and result["cost"] <= unit(selected_id).stats[Stat.ACTION_POINTS]
	return result


func submit_move(target: Vector2i) -> bool:
	var result := preview(target)
	if not result["affordable"] or result["path"].is_empty(): return false
	return _enqueue(selected_id, "move", result["path"])


func defend() -> bool:
	return can_input() and selected_id >= 0 and _enqueue(selected_id, "defend")


func wait_unit() -> bool:
	return can_input() and selected_id >= 0 and _enqueue(selected_id, "wait")


func end_side() -> bool:
	if not can_input(): return false
	for id in participants:
		var actor = unit(id)
		if actor.side_id == current_side and eligible(actor): _enqueue(id, "wait", [], true)
	return not queue.is_empty()


func _enqueue(id: int, action: String, path: Array = [], internal: bool = false) -> bool:
	var actor = unit(id)
	if (busy() and not internal) or actor == null or actor.side_id != current_side or not eligible(actor): return false
	var cells: Array[Vector2i] = []
	cells.assign(path)
	queue.append({"actor": id, "action": action, "path": cells, "turn": turn_serial, "start": actor.cell})
	_record("queued", {"actor": id, "action": action, "cost": path.size()})
	changed.emit()
	return true


func _apply_defense(actor) -> void:
	var data: Dictionary = state[actor.instance_id]
	var physical: int = int(actor.stats[Stat.PHYSICAL_RESISTANCE] * 4 * actor.stats[Stat.ACTION_POINTS] / float(maxi(1, actor.stats[Stat.MAX_ACTION_POINTS])))
	var black: int = int(actor.stats[Stat.DARK_RESISTANCE] * 4 * actor.stats[Stat.ACTION_POINTS] / float(maxi(1, actor.stats[Stat.MAX_ACTION_POINTS])))
	data["defense_physical"] = maxi(int(data["defense_physical"]), physical)
	data["defense_black"] = maxi(int(data["defense_black"]), black)
	actor.stats[Stat.PHYSICAL_RESISTANCE] = int(data["physical"]) + int(data["defense_physical"])
	actor.stats[Stat.DARK_RESISTANCE] = int(data["black"]) + int(data["defense_black"])
	# Persistent effects use the source stat aggregation, including skill scaling.
	Effects.add(actor, session.ability_table, Stat.PHYSICAL_RESISTANCE, physical, 1, StatusIcon.DEFEND)
	Effects.add(actor, session.ability_table, Stat.DARK_RESISTANCE, black, 1, StatusIcon.NONE)


func _start_side(side: int) -> void:
	current_side = side
	turn_serial += 1
	selected_id = -1
	for id in participants:
		var actor = unit(id)
		if actor.side_id != side or actor.dead: continue
		var data: Dictionary = state[id]
		var periodic: Dictionary = Effects.start_turn(actor, session.ability_table, rng)
		if session.god_mode and actor in session.party:
			actor.stats[Stat.HP] = actor.stats[Stat.MAX_HP]
			actor.stats[Stat.MANA] = actor.stats[Stat.MAX_MANA]
			periodic["poison"] = 0
		if periodic.get("poison", 0) > 0 or periodic.get("regeneration", 0) > 0: _record("periodic", {"actor": id, "result": periodic})
		if int(periodic.get("poison", 0)) > 0: _show_combat_text(actor, "-%d" % int(periodic["poison"]))
		if int(periodic.get("regeneration", 0)) > 0: _show_combat_text(actor, "+%d реген." % int(periodic["regeneration"]))
		if actor.stats[Stat.HP] <= 0:
			actor.dead = true
			_record("death", {"actor": id})
		data["defense_physical"] = 0
		data["defense_black"] = 0
		data["ended"] = false
		data["movement_spent"] = 0
		actor.stats[Stat.ACTION_POINTS] = actor.stats[Stat.MAX_ACTION_POINTS]
		if selected_id < 0 and eligible(actor): selected_id = id
	_record("side_started")
	if selected_id >= 0: rebuild_paths()
	side_changed.emit(current_side, round_number)


func _settle_side() -> void:
	if busy(): return
	for id in participants:
		var actor = unit(id)
		if actor.side_id == current_side and eligible(actor):
			if selected_id < 0 or not eligible(unit(selected_id)): selected_id = id
			rebuild_paths()
			return
	var next_side: int = 1 - current_side
	var has_actor: bool = false
	for id in participants:
		var actor = unit(id)
		if actor.side_id == next_side and session.is_active(actor) and not actor.dead and actor.stats[Stat.HP] > 0 and (actor.stats[Stat.STUN] == 0 or _has_timed_effect(actor)) and (actor in session.party or actor.encounter_enabled): has_actor = true
	if not has_actor:
		for id in participants:
			var actor = unit(id)
			if actor.side_id == current_side and session.is_active(actor) and not actor.dead and actor.stats[Stat.HP] > 0 and (actor.stats[Stat.STUN] == 0 or _has_timed_effect(actor)) and (actor in session.party or actor.encounter_enabled):
				_record("side_skipped", {"skipped_side": next_side})
				round_number += 1
				_start_side(current_side)
				return
		stalled = true
		selected_id = -1
		_record("stalled")
		return
	if next_side == 0:
		round_number += 1
		_tick_hazards()
		if _check_outcome(): return
	_start_side(next_side)


func alpha() -> float:
	return clampf(accumulator / _tick_seconds, 0, 1)


func advance(delta: float) -> void:
	if not active or session.mode != &"battle" or outcome != &"": return
	accumulator += maxf(0, delta)
	while accumulator + 0.000000001 >= _tick_seconds:
		accumulator -= _tick_seconds
		_tick()
		if outcome != &"":
			accumulator = 0
			return
	accumulator = maxf(0, accumulator)


func _start_command() -> void:
	current = queue.pop_front()
	var actor = unit(int(current["actor"]))
	if actor == null:
		current = {}
		return
	var reaction: bool = bool(current.get("reaction", false))
	var continuation: bool = bool(current.get("series", false))
	if current["turn"] != turn_serial or (not reaction and ((not continuation and not eligible(actor)) or actor.side_id != current_side)) or actor == null or actor.dead or actor.stats[Stat.STUN] != 0 or actor.petrified() or actor.cell != current["start"]:
		_record("rejected", {"reason": "stale actor/turn"})
		current = {}
		return
	if current["action"] in ["move", "attack"]:
		var previous: Vector2i = actor.cell
		var grid := Grid.new(session.collision, arena)
		for next: Vector2i in current["path"]:
			if (next - previous).length_squared() != 1 or not grid.can_stand(next, actor.footprint, actor.instance_id):
				_record("rejected", {"reason": "route obstructed"})
				current = {}
				return
			previous = next
		var cost: int = current["path"].size()
		if (not reaction and cost > actor.stats[Stat.ACTION_POINTS]) or (current["action"] == "attack" and ((not reaction and cost >= actor.stats[Stat.ACTION_POINTS]) or not _valid_target(actor, unit(int(current["target"])), true))):
			current = {}
			return
		actor.stats[Stat.ACTION_POINTS] -= cost
		state[actor.instance_id]["movement_spent"] += cost
		current["index"] = 0
		current["step_tick"] = 0
		if current["action"] == "attack":
			state[actor.instance_id]["ended"] = true
			current["phase"] = "move" if cost > 0 else "windup"
			current["clock"] = 0
			_face_target(actor, unit(int(current["target"])))
	elif current["action"] == "cast":
		var spell: int = int(current["spell"])
		var target: Vector2i = current["cell"]
		if not Spells.learned(actor, spell, session.definitions, bool(current.get("ai", false))) or actor.stats[Stat.MANA] < Spells.cost(actor, spell, session.definitions) or not Spells.target_valid(self, actor, spell, target):
			_record("rejected", {"reason": "spell no longer valid"})
			current = {}
			return
		state[actor.instance_id]["ended"] = true
		current["phase"] = "windup"
		current["clock"] = 0
		current["flight_from"] = actor.position_pixels + Vector2(0, -12)
		current["flight_to"] = Vector2(target) * 16 + Vector2(8, -4)
		_face_point(actor, current["flight_to"])
	else:
		state[actor.instance_id]["ended"] = true
		if current["action"] == "defend": _apply_defense(actor)
		current["delay"] = ceili(float(session.definitions["battle"]["defense_delay_ms"]) / float(session.definitions["battle"]["tick_ms"])) if current["action"] == "defend" else 1
	_record("command_started", {"actor": actor.instance_id, "action": current["action"], "reaction": reaction})


func _finish_command() -> void:
	var actor = unit(int(current["actor"]))
	actor.walking = false
	actor.facing %= Ids.WALK_DIRECTION_COUNT
	_record("command_finished", {"actor": actor.instance_id, "action": current["action"]})
	current = {}
	if not _check_outcome(): _settle_side()


func _tick_move(actor) -> void:
	var index: int = int(current["index"])
	if int(current["step_tick"]) == 0:
		var next: Vector2i = current["path"][index]
		if not Grid.new(session.collision, arena).can_stand(next, actor.footprint, actor.instance_id):
			var refund: int = current["path"].size() - index
			actor.stats[Stat.ACTION_POINTS] += refund
			state[actor.instance_id]["movement_spent"] -= refund
			_record("move_interrupted", {"actor": actor.instance_id})
			_finish_command()
			return
		var start: Vector2 = actor.position_pixels
		actor.move_to(next)
		current["from"] = start
		current["to"] = actor.position_pixels
		actor.position_pixels = start
		session.collision.place(actor.instance_id, next, actor.footprint)
	current["step_tick"] += 1
	actor.walking = true
	var previous: Vector2 = actor.position_pixels
	actor.position_pixels = Vector2(current["from"]).lerp(current["to"], float(current["step_tick"]) / float(session.definitions["battle"]["move_ticks_per_cell"]))
	if previous != actor.position_pixels:
		presentation_event.emit({"event": "walked", "actor": actor.instance_id, "distance": previous.distance_to(actor.position_pixels), "dungeon": session.location_id < 0})
	if int(current["step_tick"]) >= int(session.definitions["battle"]["move_ticks_per_cell"]):
		current["index"] += 1
		current["step_tick"] = 0
		if int(current["index"]) >= current["path"].size():
			if current["action"] == "attack":
				current["phase"] = "windup"
				current["clock"] = 0
				_face_target(actor, unit(int(current["target"])))
			else: _finish_command()


func _tick() -> void:
	tick_count += 1
	if not finale.is_empty():
		_tick_finale()
		changed.emit()
		return
	if _check_outcome(): return
	for id in participants:
		var actor = unit(id)
		actor.previous_position = actor.position_pixels
		actor.walking = false
	if not busy() and current_side == Side.HOSTILE and not stalled:
		if selected_id >= 0 and eligible(unit(selected_id)):
			if enemy_policy == &"defend": _enqueue(selected_id, "defend", [], true)
			else: _enemy_action(unit(selected_id))
		else: _settle_side()
	if current.is_empty() and not queue.is_empty(): _start_command()
	if not current.is_empty():
		var actor = unit(int(current["actor"]))
		if current["action"] == "move": _tick_move(actor)
		elif current["action"] == "attack":
			if current["phase"] == "move": _tick_move(actor)
			else: _tick_attack(actor)
		elif current["action"] == "cast": _tick_cast(actor)
		else:
			current["delay"] -= 1
			if current["delay"] <= 0: _finish_command()
	elif not busy() and not stalled:
		if selected_id < 0 or not eligible(unit(selected_id)): _settle_side()
	for id in participants:
		var actor = unit(id)
		if not actor.dead: actor.animate_tick(session.definitions["exploration"]["units"][actor.unit_type])
	if outcome == &"": _check_outcome()
	changed.emit()


func _has_timed_effect(actor) -> bool:
	if actor.petrify_rounds > 0: return true
	for effect in actor.effects:
		if int(effect["duration"]) > 0 and (int(effect["slot"]) in [Stat.STUN, Stat.MAX_ACTION_POINTS] or int(effect["icon"]) == StatusIcon.PETRIFY): return true
	return false


func snapshot() -> Dictionary:
	var pending: Array = []
	for command: Dictionary in queue: pending.append(_command_snapshot(command))
	return {"active": active, "hazards": hazards.map(func(hazard): return _command_snapshot(hazard)), "arena": [arena.position.x, arena.position.y, arena.size.x, arena.size.y], "participants": Array(participants), "side": current_side, "round": round_number, "turn_serial": turn_serial, "selected_id": selected_id, "state": state.duplicate(true), "queue": pending, "current": _command_snapshot(current), "events": events.duplicate(true), "tick": tick_count, "accumulator": accumulator, "stalled": stalled, "seed": _battle_seed, "rng": rng.snapshot(), "loot_rng": loot_rng.snapshot(), "outcome": str(outcome), "reward": reward.duplicate(true)}


func _command_snapshot(command: Dictionary) -> Dictionary:
	var result: Dictionary = command.duplicate(true)
	for key: String in result.keys():
		if result[key] is Vector2i or result[key] is Vector2:
			result[key] = [result[key].x, result[key].y]
		elif key == "path":
			var cells: Array = []
			for cell: Vector2i in result[key]: cells.append([cell.x, cell.y])
			result[key] = cells
	return result


func _valid_target(actor, target, allow_corpse: bool = false) -> bool:
	return target != null and target.instance_id in participants and not target.shattered and (allow_corpse or (not target.dead and target.stats[Stat.HP] > 0)) and session.is_active(target) and (target.side_id != actor.side_id or (allow_corpse and target.dead and actor.side_id != Side.PARTY)) and (target.encounter_enabled or target in session.party)


func _adjacent(cell: Vector2i, footprint: Vector2i, target) -> bool:
	var dx: int = maxi(0, maxi(target.cell.x - (cell.x + footprint.x - 1), cell.x - (target.cell.x + target.footprint.x - 1)))
	var dy: int = maxi(0, maxi(target.cell.y - (cell.y + footprint.y - 1), cell.y - (target.cell.y + target.footprint.y - 1)))
	return dx + dy == 1


func attack_plan(actor, target) -> Dictionary:
	var result := {"valid": false, "path": [], "ranged": false, "target": -1}
	if not _valid_target(actor, target, true): return result
	result["target"] = target.instance_id
	if actor.stats[Stat.ARCHERY] >= 1:
		result["ranged"] = true
		result["valid"] = absi(target.cell.x - actor.cell.x) + absi(target.cell.y - actor.cell.y) <= actor.stats[Stat.ATTACK_RANGE]
		return result
	if actor.stats[Stat.ATTACK] < 1: return result
	var route: Dictionary = _approach(actor, target)
	result["path"] = route["path"]
	result["valid"] = route["reachable"] and route["path"].size() < actor.stats[Stat.ACTION_POINTS]
	return result


func _approach(actor, target, allow_partial: bool = false, collision = null) -> Dictionary:
	var finder := Pathfinder.new()
	var grid := Grid.new(session.collision if collision == null else collision, arena)
	finder.build(grid, actor.cell, actor.footprint, actor.instance_id)
	var best := Vector2i(-1, -1)
	var cost: int = Pathfinder.INFINITY_COST if allow_partial else 1000
	for y in range(target.cell.y - actor.footprint.y, target.cell.y + target.footprint.y + 1):
		for x in range(target.cell.x - actor.footprint.x, target.cell.x + target.footprint.x + 1):
			var cell := Vector2i(x, y)
			if allow_partial and not grid.can_stand(cell, actor.footprint, actor.instance_id): continue
			if _adjacent(cell, actor.footprint, target) and finder.distance(cell) < cost:
				cost = finder.distance(cell)
				best = cell
	if best.x < 0: return {"reachable": false, "path": []}
	return finder.route(best)


func attack(target_id: int) -> bool:
	if not can_input() or selected_id < 0: return false
	return _order_attack(unit(selected_id), unit(target_id))


func attack_many(target_ids: Array) -> bool:
	if not can_input() or selected_id < 0 or target_ids.is_empty(): return false
	var actor = unit(selected_id)
	if actor.stats[Stat.ARCHERY] < 1: return false
	var maximum: int = int((actor.stats[Stat.ARCHERY] - 1) / 3.0) + 1
	if target_ids.size() > maximum: return false
	for id in target_ids:
		if not id is int: return false
		if not attack_plan(actor, unit(id))["valid"]: return false
	for index in range(maximum):
		var id: int = target_ids[mini(index, target_ids.size() - 1)]
		if not _enqueue(actor.instance_id, "attack", [], index > 0): return false
		queue.back().merge({"target": id, "ranged": true, "hits": 1, "series": index > 0})
	return true


func _order_attack(actor, target) -> bool:
	var plan: Dictionary = attack_plan(actor, target)
	if not plan["valid"] or not _enqueue(actor.instance_id, "attack", plan["path"]): return false
	var command: Dictionary = queue.back()
	command["target"] = target.instance_id
	command["ranged"] = plan["ranged"]
	var skill: int = actor.stats[Stat.ARCHERY] if plan["ranged"] else actor.stats[Stat.ATTACK]
	command["hits"] = int((skill - 1) / 3.0) + 1
	_record("attack_ordered", {"actor": actor.instance_id, "target": target.instance_id, "ranged": plan["ranged"]})
	return true


func _face_target(actor, target) -> void:
	_face_point(actor, target.position_pixels)


func _face_point(actor, point: Vector2) -> void:
	var delta: Vector2 = point - actor.position_pixels
	var direction: int = (Facing.LEFT if delta.x < 0 else Facing.RIGHT) if absf(delta.x) > absf(delta.y) else (Facing.UP if delta.y < 0 else Facing.DOWN)
	current["attack_direction"] = direction + Ids.WALK_DIRECTION_COUNT
	actor.facing = direction + Ids.WALK_DIRECTION_COUNT
	actor.animation_frame = 0


func _windup_pending(actor) -> bool:
	actor.facing = int(current["attack_direction"])
	actor.walking = true
	var definition: Dictionary = session.definitions["exploration"]["units"][actor.unit_type]
	var duration: int = int(definition["frame_ticks"][actor.facing]) * definition["frame_columns"][actor.facing].size()
	return int(current["clock"]) < duration


func _tick_attack(actor) -> void:
	var target = unit(int(current["target"]))
	if not _valid_target(actor, target, true):
		_finish_command()
		return
	current["clock"] += 1
	if current["phase"] == "windup":
		if _windup_pending(actor): return
		presentation_event.emit({"event": "attack_released", "actor": actor.instance_id, "ranged": current["ranged"]})
		if current["ranged"]:
			current["phase"] = "flight"
			current["clock"] = 0
			current["flight_from"] = actor.position_pixels + Vector2(0, -12)
			current["flight_to"] = target.position_pixels + Vector2(0, -12)
			current["flight_ticks"] = maxi(1, ceili(actor.position_pixels.distance_to(target.position_pixels) / 12.0))
			actor.walking = false
			actor.facing %= Ids.WALK_DIRECTION_COUNT
			return
	else:
		if int(current["clock"]) < int(current["flight_ticks"]): return
	# A target may move while future effects resolve; revalidate actual range at
	# impact as well as submission. There is no RNG draw for an invalid hit.
	if (not current["ranged"] and not _adjacent(actor.cell, actor.footprint, target)) or (current["ranged"] and absi(target.cell.x - actor.cell.x) + absi(target.cell.y - actor.cell.y) > actor.stats[Stat.ATTACK_RANGE]):
		_record("missed", {"actor": actor.instance_id, "target": target.instance_id})
		_finish_command()
		return
	var hit: Dictionary = apply_payload(actor, target, Rules.physical_payload(actor, bool(current["ranged"]), session.ability_table))
	if hit["reset_movement"]: state[actor.instance_id]["movement_spent"] = 0
	if hit["counter"] and not target.dead and not actor.dead:
		queue.push_front({"actor": target.instance_id, "action": "attack", "path": [], "turn": turn_serial, "start": target.cell, "reaction": true, "ranged": false, "target": actor.instance_id, "hits": 1})
	if _check_outcome(): return
	current["hits"] -= 1
	if int(current["hits"]) <= 0 or target.dead:
		_finish_command()
	else:
		current["phase"] = "windup"
		current["clock"] = 0
		actor.animation_frame = 0


func _enemy_action(actor) -> void:
	# m.I(): fighters attack/move/clear corpses; casters cast/move. Each
	# successful stage chooses one candidate with the original combat RNG.
	if not eligible(actor): return
	if actor.stats[Stat.ATTACK] > 0 or actor.stats[Stat.DEFENSE] > 0 or actor.stats[Stat.TACTICS] > 0:
		if _physical_action(actor) or _move_action(actor) or _corpse_action(actor): return
	else:
		if _magic_action(actor) or _move_action(actor): return
	_enqueue(actor.instance_id, "defend", [], true)


func _physical_action(actor) -> bool:
	var targets: Array = []
	for id in participants:
		var target = unit(id)
		if _valid_target(actor, target) and attack_plan(actor, target)["valid"]: targets.append(target)
	return not targets.is_empty() and _order_attack(actor, targets[rng.bounded(targets.size())])


func _move_action(actor) -> bool:
	var plans: Array[Dictionary] = []
	for id in participants:
		var target = unit(id)
		if not _valid_target(actor, target): continue
		var plan: Dictionary = _approach(actor, target, true)
		if not plan["path"].is_empty(): plans.append(plan)
	return not plans.is_empty() and _advance_toward(actor, plans[rng.bounded(plans.size())])


func _corpse_action(actor) -> bool:
	var bodies: Array = []
	for id in participants:
		var body = unit(id)
		if body.dead and not body.shattered and attack_plan(actor, body)["valid"]: bodies.append(body)
	return not bodies.is_empty() and _order_attack(actor, bodies[rng.bounded(bodies.size())])


func _advance_toward(actor, plan: Dictionary) -> bool:
	if plan["path"].is_empty(): return false
	var cells: Array[Vector2i] = []
	cells.assign(plan["path"].slice(0, actor.stats[Stat.ACTION_POINTS]))
	if not _enqueue(actor.instance_id, "move", cells): return false
	_enqueue(actor.instance_id, "wait", [], true)
	queue.back()["start"] = cells.back()
	return true


func _check_outcome() -> bool:
	if outcome != &"": return true
	if not finale.is_empty(): return true
	if session.location_id == -12 and not session.campaign_completed:
		for id in participants:
			var dragon = unit(id)
			if dragon.unit_type != Ids.UnitKind.DRAGON or (not dragon.dead and dragon.stats[Stat.HP] > 0): continue
			var companion
			for other_id in participants:
				if unit(other_id).unit_type == Ids.UnitKind.LI: companion = unit(other_id)
			if companion != null:
				# m.A()/ag.a(): the dragon's last meteor lands before Li dies.
				queue.clear()
				feedback = {}
				dragon.dead = false
				finale = {"dragon": dragon.instance_id, "target": companion.instance_id, "phase": "fall", "clock": 0}
				current = {"actor": dragon.instance_id, "action": "cast", "spell": Spell.METEOR, "phase": "flight", "clock": 0, "flight_ticks": FINALE_FALL_TICKS, "flight_from": dragon.position_pixels, "flight_to": companion.position_pixels, "cell": companion.cell, "path": []}
				selected_id = companion.instance_id
				_record("final_dragon_retaliation_started", {"actor": dragon.instance_id, "target": companion.instance_id})
				return true
			# Debug parties without Li still reach the epilogue safely.
			session.campaign_completed = true
			break
	var friendly: bool = false
	var hostile: bool = false
	for id in participants:
		var actor = unit(id)
		if actor.dead or actor.stats[Stat.HP] <= 0 or not session.is_active(actor): continue
		if actor in session.party: friendly = true
		elif actor.encounter_enabled: hostile = true
	if friendly and hostile and not session.campaign_completed: return false
	outcome = &"ending" if session.campaign_completed else (&"victory" if friendly else &"defeat")
	queue.clear()
	current = {}
	for id in participants:
		var actor = unit(id)
		actor.effects.clear()
		actor.petrify_rounds = 0
		actor.recalculate(session.ability_table)
		actor.walking = false
		actor.facing %= Ids.WALK_DIRECTION_COUNT
	if outcome == &"victory":
		var defeated: Array = []
		for id in participants:
			var actor = unit(id)
			if actor not in session.party and actor.encounter_enabled and actor.dead: defeated.append(actor)
		reward = Rewards.award(session, defeated, loot_rng)
		for actor in session.party:
			state[actor.instance_id]["physical"] = actor.stats[Stat.PHYSICAL_RESISTANCE]
			state[actor.instance_id]["black"] = actor.stats[Stat.DARK_RESISTANCE]
	session.mode = outcome
	_record(str(outcome), {"reward": reward.duplicate(true)})
	return true

func _tick_finale() -> void:
	finale["clock"] += 1
	if finale["phase"] == "fall":
		current["clock"] = int(finale["clock"])
		if int(finale["clock"]) < FINALE_FALL_TICKS: return
		var companion = unit(int(finale["target"]))
		companion.dead = true
		companion.stats[Stat.HP] = 0
		companion.walking = false
		companion.reset_interpolation()
		unit(int(finale["dragon"])).dead = true
		state[companion.instance_id]["ended"] = true
		spell_impact.emit(Spell.METEOR, companion.cell, tick_count)
		_record("final_dragon_retaliation", {"target_type": Ids.UnitKind.LI, "target": companion.instance_id})
		current = {}
		finale["phase"] = "aftermath"
		finale["clock"] = 0
	elif int(finale["clock"]) >= FINALE_AFTER_TICKS:
		finale.clear()
		session.campaign_completed = true
		_check_outcome()


func return_to_exploration() -> bool:
	if not active or outcome != &"victory": return false
	# Find a valid physical pose before committing recovery. Combat grid centers
	# can be too narrow for the original 20px exploration body.
	var origin: Vector2 = session.hero.position_pixels
	var best := Vector2(-1, -1)
	var distance: float = INF
	for y in range(session.collision.height * 2):
		for x in range(session.collision.width * 2):
			var point := Vector2(x * 8, y * 8)
			var cost: float = absf(point.x - origin.x) + absf(point.y - origin.y)
			if cost >= distance: continue
			var free: bool = true
			for actor in session.party:
				if not session.can_move_pixels(actor, point, actor.facing % Ids.WALK_DIRECTION_COUNT): free = false
			if free:
				best = point
				distance = cost
	if best.x < 0: return false
	for id in participants:
		var actor = unit(id)
		if actor.dead or actor in session.party: session.collision.remove(id)
	for actor in session.party:
		actor.dead = false
		actor.shattered = false
		actor.stats[Stat.HP] = actor.stats[Stat.MAX_HP]
		actor.stats[Stat.MANA] = actor.stats[Stat.MAX_MANA]
		actor.stats[Stat.ACTION_POINTS] = actor.stats[Stat.MAX_ACTION_POINTS]
		actor.facing %= Ids.WALK_DIRECTION_COUNT
		actor.set_pixel_position(best)
		actor.reset_interpolation()
		session.collision.occupy(actor.instance_id, actor.cell, actor.footprint)
	active = false
	session.mode = &"exploration"
	_record("returned_to_exploration")
	changed.emit()
	return true


func actor_at(cell: Vector2i):
	for id in participants:
		var actor = unit(id)
		if not actor.shattered and Rect2i(actor.cell, actor.footprint).has_point(cell): return actor
	return null


func cast_plan(actor, spell: int, cell: Vector2i, ai: bool = false) -> Dictionary:
	var valid: bool = actor != null and Spells.learned(actor, spell, session.definitions, ai)
	var cost: int = Spells.cost(actor, spell, session.definitions) if valid else 0
	if session.god_mode and actor in session.party: cost = 0
	return {"valid": valid and actor.stats[Stat.MANA] >= cost and Spells.target_valid(self, actor, spell, cell), "cost": cost, "spell": spell, "cell": cell}


func cast(spell: int, cell: Vector2i) -> bool:
	return can_input() and _order_cast(unit(selected_id), spell, cell)


func _order_cast(actor, spell: int, cell: Vector2i, ai: bool = false) -> bool:
	if not cast_plan(actor, spell, cell, ai)["valid"] or not _enqueue(actor.instance_id, "cast"): return false
	queue.back()["spell"] = spell
	queue.back()["cell"] = cell
	queue.back()["ai"] = ai
	return true


func _tick_cast(actor) -> void:
	var spell: int = int(current["spell"])
	var cell: Vector2i = current["cell"]
	current["clock"] += 1
	if current["phase"] == "windup":
		if _windup_pending(actor): return
		if not session.god_mode or actor not in session.party: actor.stats[Stat.MANA] -= Spells.cost(actor, spell, session.definitions)
		actor.walking = false
		actor.facing %= Ids.WALK_DIRECTION_COUNT
		current["phase"] = "flight"
		current["clock"] = 0
		# w/d projectiles take twice the integer grid distance. Other effects
		# retain their original delays where wall-clock durations were explicit.
		var target = actor_at(cell)
		var offset: Vector2i = cell - actor.cell
		if target != null: offset = target.cell + Vector2i(Vector2(target.footprint) / 2) - actor.cell - Vector2i(Vector2(actor.footprint) / 2)
		var distance: int = Spells.integer_root(offset.length_squared())
		current["flight_ticks"] = maxi(1, distance * 2) if spell in [Spell.FIRE_ARROW, Spell.SPARK] else Ids.SPELL_EFFECT_TICKS.get(spell, Ids.DEFAULT_SPELL_EFFECT_TICKS)
		_record("spell_launched", {"actor": actor.instance_id, "spell": spell, "mana": actor.stats[Stat.MANA]})
		return
	if int(current["clock"]) < int(current["flight_ticks"]): return
	Spells.impact(self, actor, spell, cell)
	spell_impact.emit(spell, cell, tick_count)
	if not _check_outcome(): _finish_command()


func apply_payload(actor, target, payload: PackedInt32Array, spell: int = -1) -> Dictionary:
	if session.god_mode and target in session.party and (payload[Stat.PHYSICAL_DAMAGE] > 0 or payload[Stat.DARK_DAMAGE] > 0):
		_show_combat_text(target, "Бессмертие")
		_record("god_mode_hit_ignored", {"actor": actor.instance_id, "target": target.instance_id})
		return {"damage": 0, "blocked": false, "instant": false, "multiplier": 1, "counter": false, "revived": false, "shattered": false, "reset_movement": false}
	var attacker_hp: int = actor.stats[Stat.HP]
	var was_dead: bool = target.dead
	var was_stone: bool = target.petrified()
	var hit: Dictionary = Rules.apply(actor, target, payload, rng, session.ability_table, int(state[actor.instance_id]["movement_spent"]))
	if session.god_mode and actor in session.party: actor.stats[Stat.HP] = actor.stats[Stat.MAX_HP]
	if hit["blocked"]: _show_combat_text(target, "Блок")
	elif hit["revived"]: _show_combat_text(target, "+1")
	elif int(hit["damage"]) != 0:
		var amount: int = int(hit["damage"])
		var message: String = "%+d" % -amount
		if amount > 0 and int(hit["multiplier"]) > 1: message = "-%d х%d" % [int(hit.get("physical_base", amount)), int(hit["multiplier"])]
		_show_combat_text(target, message)
	if actor != target and actor.stats[Stat.HP] != attacker_hp: _show_combat_text(actor, "%+d" % (actor.stats[Stat.HP] - attacker_hp))
	feedback = {"target": target.instance_id, "damage": hit["damage"], "blocked": hit["blocked"], "multiplier": hit["multiplier"], "tick": tick_count}
	_record("hit", {"actor": actor.instance_id, "target": target.instance_id, "damage": hit["damage"], "hp": target.stats[Stat.HP], "multiplier": hit["multiplier"], "blocked": hit["blocked"], "spell": spell})
	if hit["revived"]:
		state[target.instance_id]["ended"] = false
		_record("revived", {"actor": target.instance_id})
	if target.stats[Stat.HP] <= 0:
		target.dead = true
		target.walking = false
		state[target.instance_id]["ended"] = true
		if not was_dead: _record("death", {"actor": target.instance_id})
		if was_stone: target.shattered = true
	if target.shattered:
		session.collision.remove(target.instance_id)
		_record("shattered", {"actor": target.instance_id})
	if actor.stats[Stat.HP] <= 0:
		actor.dead = true
		state[actor.instance_id]["ended"] = true
		_record("death", {"actor": actor.instance_id})
	return hit


func _tick_hazards() -> void:
	for id in participants:
		var actor = unit(id)
		actor.petrify_rounds = maxi(0, actor.petrify_rounds - 1)
	for i in range(hazards.size() - 1, -1, -1):
		var hazard: Dictionary = hazards[i]
		hazard["duration"] -= 1
		var actor = unit(int(hazard["actor"]))
		var seen: Array[int] = []
		var anchor: Vector2i = hazard["cell"]
		var points: Array[Vector2i] = [anchor]
		if int(hazard["spell"]) == Spell.MIASMA:
			points = Spells.miasma_cells(anchor)
		for cell in points:
			var target = actor_at(cell)
			if target != null and target.instance_id not in seen:
				apply_payload(actor, target, Spells.payload(actor, int(hazard["spell"]), session.definitions), int(hazard["spell"]))
				seen.append(target.instance_id)
		if int(hazard["duration"]) <= 0: hazards.remove_at(i)


func _magic_action(actor) -> bool:
	# m.boolean_b(): draw a spell before checking its targets. Friendly spells
	# (flag 2) and dead targets are excluded by the original enemy policy.
	if actor.stats[Stat.ACTION_POINTS] <= 0: return false
	var spells: Array[int] = []
	for spell in range(Spell.COUNT):
		var definition: Dictionary = session.definitions["spell_definitions"][spell]
		if int(definition["target_flags"]) & 2: continue
		if Spells.learned(actor, spell, session.definitions, true) and actor.stats[Stat.MANA] >= Spells.cost(actor, spell, session.definitions): spells.append(spell)
	if spells.is_empty(): return false
	var selected_spell: int = spells[rng.bounded(spells.size())]
	var targets: Array = []
	for id in participants:
		var target = unit(id)
		if _valid_target(actor, target) and cast_plan(actor, selected_spell, target.cell, true)["valid"]: targets.append(target)
	return not targets.is_empty() and _order_cast(actor, selected_spell, targets[rng.bounded(targets.size())].cell, true)


func _show_combat_text(actor, message: String) -> void:
	var definition: Dictionary = session.definitions["exploration"]["units"][actor.unit_type]
	var height: int = int(definition["frame_sizes"][actor.facing][1])
	combat_text.emit(actor.position_pixels - Vector2(0, int(height / 2.0)), message)
