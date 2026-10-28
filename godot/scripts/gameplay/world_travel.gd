extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Unit = preload("res://scripts/gameplay/unit_state.gd")
const Collision = preload("res://scripts/gameplay/map_collision.gd")
const SceneData = preload("res://scripts/gameplay/legacy_scene_data.gd")
const Dungeon = preload("res://scripts/gameplay/dungeon_generator.gd")
const Random = preload("res://scripts/gameplay/legacy_random.gd")
const Gates = preload("res://scripts/gameplay/campaign_gates.gd")
const RANDOM_MAGE_MAP: int = 8
const RANDOM_MAGE_GROUP: int = 10
const FIND_MAGE_SCRIPT: int = 119
## Prepare the destination before changing live state. The party is retained as
## the same objects; ordinary NPCs are reconstructed on travel, as m.void_a().

static func enter(game, map_id: int, entry_id: int) -> bool:
	game.travel_error = ""
	if map_id < -12 or map_id > 11:
		game.travel_error = "Переход %d не восстановлен: для специальной карты 101 не установлена корректная точка входа." % map_id
		return false
	var generated: Dictionary
	var destination: Dictionary = {}
	var scene: Dictionary
	var entrance: Dictionary = {}
	var seed_value: int = 0
	if map_id < 0:
		var index: int = -map_id - 1
		seed_value = int(game.dungeon_seeds[index])
		if seed_value == 0: seed_value = maxi(1, int(Time.get_unix_time_from_system() * 1000))
		generated = Dungeon.new().generate(map_id, entry_id, seed_value, game.definitions, game.pickup_flags)
		if generated.is_empty():
			game.travel_error = "Не удалось построить подземелье."
			return false
		destination = generated["map"]
		scene = generated["scene"]
		entrance = generated["entry"]
		# Every generated exit has a corresponding entrance; final chamber has one.
		if entry_id < 0 or entry_id >= maxi(1, scene["triggers"].size()):
			game.travel_error = "Нет входа %d в подземелье %d." % [entry_id, map_id]
			return false
	else:
		for candidate: Dictionary in game.world_data["maps"]:
			if str(candidate["name"]) == str(map_id + 1): destination = candidate
		for candidate: Dictionary in game.definitions["travel"]["entries"][map_id]:
			if int(candidate["entry"]) == entry_id: entrance = candidate
		if destination.is_empty() or entrance.is_empty():
			game.travel_error = "Не найдена локация %d или вход %d." % [map_id, entry_id]
			return false
		scene = game.world_data["scenes"][map_id].duplicate(true)
		scene["pickups"] = game.definitions["economy"]["pickups"][map_id].duplicate(true)
	var collision := Collision.new()
	scene["decoded_scripts"] = SceneData.scripts(scene["scripts"], game.definitions["travel"]["opcode_lengths"])
	collision.configure(destination, game.world_data["constants"]["tile_image_ids"], game.definitions)
	var incoming: Array = game.party.duplicate()
	var world_rng := Random.new()
	world_rng.state = game.world_rng.state
	world_rng.draws = game.world_rng.draws
	var gate_choices: Array = game.gate_choices.duplicate()
	if map_id == 6:
		if gate_choices.is_empty():
			for bound in Gates.BOUNDS: gate_choices.append(world_rng.bounded(bound))
		Gates.append_triggers(scene, gate_choices)
	var mage_target := Vector2i.ZERO
	if map_id == RANDOM_MAGE_MAP: mage_target = Vector2i(world_rng.bounded(30) + 5, world_rng.bounded(55) + 2)
	var position: Array = entrance["position_pixels"]
	var point := Vector2(float(position[0]), float(position[1]))
	for actor in game.party:
		var cell := Vector2i((point - Vector2(actor.footprint) * 8) / 16.0)
		if not collision.contains(cell) or not collision.contains(cell + actor.footprint - Vector2i.ONE):
			game.travel_error = "Точка входа за пределами карты."
			return false
	for index in range(scene["units"].size()):
		var spawn: Dictionary = SceneData.spawn(scene["units"][index])
		var flag: int = int(spawn["spawn_flag"])
		if int(game.spawn_states[flag]) == Ids.SpawnState.REMOVED: continue
		var unit := Unit.new()
		var namespace_id: int = map_id if map_id >= 0 else 20 - map_id
		unit.configure({"instance_id": 1000 + namespace_id * 1000 + index, "unit_type": spawn["unit_type"], "story_group": spawn["story_group"], "spawn_flag": flag, "side_id": Ids.Side.HOSTILE}, game.definitions, game.ability_table)
		unit.scale_for_location(map_id if map_id >= 0 else -map_id - 1, game.ability_table)
		unit.set_pixel_position(spawn["position_pixels"])
		if map_id == RANDOM_MAGE_MAP and unit.story_group == RANDOM_MAGE_GROUP:
			var blocked: Array = Dungeon.matrix(collision.width, collision.height)
			for y in range(collision.height):
				for x in range(collision.width): blocked[y][x] = int(collision.terrain[y * collision.width + x])
			for rect: Rect2i in collision.units.values():
				for y in range(rect.position.y, rect.end.y):
					for x in range(rect.position.x, rect.end.x): blocked[y][x] = 1
			unit.move_to(Dungeon.nearest(blocked, mage_target, unit.footprint))
			var center := Vector2i(unit.position_pixels / 16)
			scene["triggers"].append([FIND_MAGE_SCRIPT, (center.x - 10) * 16, (center.y - 12) * 16, (center.x + 10) * 16, (center.y + 12) * 16])
		unit.facing = int(spawn["facing"])
		unit.reset_interpolation()
		unit.encounter_enabled = bool(spawn["encounter_enabled"])
		unit.story_refs.assign(spawn["story_refs"])
		incoming.append(unit)
		if int(game.spawn_states[flag]) == Ids.SpawnState.VISIBLE and not collision.occupy(unit.instance_id, unit.cell, unit.footprint):
			game.travel_error = "Некорректная позиция NPC на новой карте."
			return false
	var previous_map: int = game.location_id
	# m.V/W/Z/aa/ab/ae construct one or two long-lived ad rain layers.
	var rain_count: int = 2 if map_id in [2, 3, 7] else (1 if map_id in [6, 8, 11] else 0)
	game.start_rain(180000.0 if rain_count > 0 else 0.0, rain_count)
	game.location_id = map_id
	game.entry_id = entry_id
	game.map = destination
	game.current_scene = scene
	game.collision = collision
	game.world_rng = world_rng
	game.gate_choices = gate_choices
	game.units.assign(incoming)
	if map_id < 0: game.dungeon_seeds[-map_id - 1] = seed_value
	for actor in game.party:
		actor.set_pixel_position(point)
		actor.facing = int(entrance["facing"])
		actor.walking = false
		actor.reset_interpolation()
		collision.occupy(actor.instance_id, actor.cell, actor.footprint)
	game.mode = &"exploration"
	game.commands.append({"command": "travel", "from": previous_map, "map": map_id, "entry": entry_id, "seed": seed_value})
	game.rebuild_paths()
	game.location_changed.emit()
	game.changed.emit()
	return true
