extends RefCounted
## Godot-native saves. Decode into a detached session; publish only after validation.
const Session = preload("res://scripts/gameplay/game_session.gd")
const Unit = preload("res://scripts/gameplay/unit_state.gd")
const Item = preload("res://scripts/gameplay/item_instance.gd")
const Collision = preload("res://scripts/gameplay/map_collision.gd")
const Gates = preload("res://scripts/gameplay/campaign_gates.gd")
const VERSION: int = 1
const SLOT_COUNT: int = 5
const AUTOSAVE_SLOT: int = SLOT_COUNT
const TOTAL_SLOT_COUNT: int = SLOT_COUNT + 1
const MAX_BYTES: int = 8 * 1024 * 1024
var directory: String = "user://saves"
var error: String = ""

func path(slot: int) -> String:
	return directory.path_join("autosave.json" if slot == AUTOSAVE_SLOT else "slot_%d.json" % (slot + 1))

func exists(slot: int) -> bool:
	return slot >= 0 and slot < TOTAL_SLOT_COUNT and (FileAccess.file_exists(path(slot)) or FileAccess.file_exists(path(slot) + ".bak"))

func slot_info(slot: int) -> Dictionary:
	if not exists(slot): return {}
	var target: String = path(slot) if FileAccess.file_exists(path(slot)) else path(slot) + ".bak"
	var file := FileAccess.open(target, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES: return {"invalid": true}
	var document = JSON.parse_string(file.get_as_text())
	file.close()
	if document is not Dictionary or document.get("format") != "allods-godot-save" or document.get("version") != VERSION or document.get("payload") is not String: return {"invalid": true}
	if document.get("sha256") != document["payload"].sha256_text(): return {"invalid": true}
	var payload = JSON.parse_string(document["payload"])
	if payload is not Dictionary or payload.get("world") is not Dictionary: return {"invalid": true}
	var location = payload["world"].get("location_id")
	if not _integer(location) or location < -12 or location > 11: return {"invalid": true}
	# Old version-one saves have no timestamp; their file date remains usable.
	var saved_at = document.get("saved_at", FileAccess.get_modified_time(target))
	if not _integer(saved_at) or saved_at <= 0: saved_at = FileAccess.get_modified_time(target)
	return {"location_id": int(location), "saved_at": int(saved_at)}

func capture(game, story, exploration) -> Dictionary:
	if game.mode not in [&"exploration", &"game_menu"] or story.busy() or not story.enabled or game.campaign_completed:
		error = "Сохранение доступно при исследовании, вне боя и сюжетной сцены."
		return {}
	error = ""
	var state: Dictionary = game.snapshot(false)
	for key in ["commands", "hero", "format", "demo_party"]: state.erase(key)
	state["mode"] = "exploration"
	state["scene_triggers"] = game.current_scene["triggers"].duplicate(true)
	state["pending_scripts"] = Array(story.pending)
	return {"world": state, "exploration": exploration.snapshot()}

func save_slot(slot: int, game, story, exploration) -> bool:
	if slot < 0 or slot >= SLOT_COUNT:
		error = "Выберите ручной слот сохранения."
		return false
	return _write_slot(slot, game, story, exploration)

func save_autosave(game, story, exploration) -> bool:
	return _write_slot(AUTOSAVE_SLOT, game, story, exploration)

func _write_slot(slot: int, game, story, exploration) -> bool:
	var state: Dictionary = capture(game, story, exploration)
	if state.is_empty(): return false
	var payload: String = JSON.stringify(state, "", true, true)
	var document := {"format": "allods-godot-save", "version": VERSION, "payload": payload, "sha256": payload.sha256_text(), "saved_at": int(Time.get_unix_time_from_system())}
	var encoded: String = JSON.stringify(document)
	if encoded.to_utf8_buffer().size() > MAX_BYTES:
		error = "Сохранение превышает допустимый размер."
		return false
	var result: Error = DirAccess.make_dir_recursive_absolute(directory)
	if result != OK:
		error = "Не удалось создать каталог сохранений: " + error_string(result)
		return false
	var target: String = path(slot)
	var temporary: String = target + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		error = "Не удалось записать сохранение: " + error_string(FileAccess.get_open_error())
		return false
	file.store_string(encoded)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		error = "Ошибка записи: " + error_string(write_error)
		return false
	# Keep the previous slot until the completed temporary file has been installed.
	var backup: String = target + ".bak"
	var had_previous: bool = FileAccess.file_exists(target)
	if had_previous and FileAccess.file_exists(backup):
		result = DirAccess.remove_absolute(backup)
		if result != OK:
			error = "Не удалось обновить резервную копию."
			return false
	if had_previous:
		result = DirAccess.rename_absolute(target, backup)
		if result != OK:
			error = "Не удалось обновить слот."
			return false
	result = DirAccess.rename_absolute(temporary, target)
	if result != OK:
		if had_previous: DirAccess.rename_absolute(backup, target)
		error = "Не удалось завершить сохранение: " + error_string(result)
		return false
	error = ""
	return true

func read_slot(slot: int, world: Dictionary, definitions: Dictionary, table: Dictionary, rewards: Dictionary) -> Dictionary:
	error = ""
	if not exists(slot):
		error = "Слот пуст."
		return {}
	var target: String = path(slot) if FileAccess.file_exists(path(slot)) else path(slot) + ".bak"
	var file := FileAccess.open(target, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		error = "Не удалось прочитать сохранение."
		return {}
	var parser := JSON.new()
	var parse_result: Error = parser.parse(file.get_as_text())
	var document = parser.data if parse_result == OK else null
	file.close()
	if document is not Dictionary or document.get("format") != "allods-godot-save": return _invalid()
	if document.get("version") != VERSION:
		error = "Версия сохранения не поддерживается."
		return {}
	if document.get("payload") is not String or document.get("sha256") is not String: return _invalid()
	if document["payload"].sha256_text() != document["sha256"]: return _invalid()
	if parser.parse(document["payload"]) != OK: return _invalid()
	return restore(parser.data, world, definitions, table, rewards)

func _invalid() -> Dictionary:
	error = "Сохранение повреждено или несовместимо. Текущая игра сохранена."
	return {}

static func _integer(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == float(int(value)) and absf(float(value)) <= 9007199254740991.0

static func _integers(value, count: int, low: int, high: int) -> bool:
	if value is not Array or value.size() != count: return false
	for number in value:
		if not _integer(number) or number < low or number > high: return false
	return true

static func _point(value) -> bool:
	if value is not Array or value.size() != 2: return false
	for number in value:
		if (number is not int and number is not float) or not is_finite(float(number)) or absf(float(number)) > 100000: return false
	return true

static func _item(record, definitions: Dictionary):
	if record is not Dictionary: return null
	if not _integer(record.get("instance_id")) or int(record["instance_id"]) < 0: return null
	if not _integer(record.get("definition_id")): return null
	var id: int = int(record["definition_id"])
	if id < 0 or id >= definitions["economy"]["items"].size(): return null
	var item := Item.new(int(record["instance_id"]), id)
	if not _integers(record.get("sockets"), item.sockets.size(), -1, 50): return null
	if not _integers(record.get("socket_instance_ids"), item.sockets.size(), -1, 9007199254740991): return null
	item.sockets.assign(record["sockets"])
	item.socket_instance_ids.assign(record["socket_instance_ids"])
	return item

func restore(payload, world: Dictionary, definitions: Dictionary, table: Dictionary, rewards: Dictionary) -> Dictionary:
	error = ""
	if payload is not Dictionary or payload.get("world") is not Dictionary or payload.get("exploration") is not Dictionary: return _invalid()
	var state: Dictionary = payload["world"]
	for key in ["location_id", "entry_id", "gold", "next_item_id", "last_rumour", "simulation_tick"]:
		if not _integer(state.get(key)): return _invalid()
	if int(state["location_id"]) < -12 or int(state["location_id"]) > 11 or int(state["entry_id"]) < 0 or int(state["entry_id"]) > 20 or int(state["gold"]) < 0: return _invalid()
	if state.get("mode") != "exploration" or state.get("campaign_completed") != false: return _invalid()
	if state.get("flags") is not Dictionary or not _integers(state.get("dungeon_seeds"), 12, 0, 9007199254740991): return _invalid()
	for bank in definitions["new_game"]["flags"]:
		if not _integers(state["flags"].get(bank), definitions["new_game"]["flags"][bank].size(), 0, 3): return _invalid()
	var choices = state.get("gate_choices")
	if choices is not Array or choices.size() not in [0, 5]: return _invalid()
	for i in range(choices.size()):
		if not _integer(choices[i]) or choices[i] < 0 or choices[i] >= Gates.BOUNDS[i]: return _invalid()
	if int(state["location_id"]) == 6 and choices.size() != 5: return _invalid()
	if state.get("world_rng") is not Dictionary: return _invalid()
	var rng: Dictionary = state["world_rng"]
	if not _integer(rng.get("state")) or not _integer(rng.get("draws")) or rng["state"] < 0 or rng["state"] > 0xffffffffffff or rng["draws"] < 0: return _invalid()
	var game := Session.new()
	if not game.start(world, definitions, table, rewards): return _invalid()
	game.flags = state["flags"].duplicate(true)
	game.dungeon_seeds = state["dungeon_seeds"].duplicate()
	game.gate_choices = choices.duplicate()
	if int(state["location_id"]) < 0 and int(game.dungeon_seeds[-int(state["location_id"]) - 1]) == 0: return _invalid()
	if not game.travel(int(state["location_id"]), int(state["entry_id"])): return _invalid()
	if state.get("inventory") is not Array or state["inventory"].size() > 10000: return _invalid()
	var items: Dictionary = {}
	game.inventory.clear()
	for record in state["inventory"]:
		var item = _item(record, definitions)
		if item == null or items.has(item.instance_id) or item.instance_id >= int(state["next_item_id"]): return _invalid()
		items[item.instance_id] = item
		game.inventory.append(item)
	var mounted: Dictionary = {}
	for item in game.inventory:
		for i in range(item.sockets.size()):
			var crystal_id: int = item.socket_instance_ids[i]
			if item.sockets[i] == -1:
				if crystal_id != -1: return _invalid()
			elif not items.has(crystal_id) or mounted.has(crystal_id) or items[crystal_id].definition_id != item.sockets[i] or item.sockets[i] < 36: return _invalid()
			else: mounted[crystal_id] = true
	if state.get("party_ids") is not Array: return _invalid()
	if state.get("units") is not Array or state["units"].size() > 1000 or not _integers(state.get("party_ids"), state.get("party_ids", []).size(), 0, 1000000): return _invalid()
	if state["party_ids"].is_empty() or state["party_ids"].size() > 5: return _invalid()
	var party_ids: Array[int] = []
	party_ids.assign(state["party_ids"])
	game.units.clear()
	game.party.clear()
	var actors: Dictionary = {}
	var equipped: Dictionary = {}
	for record in state["units"]:
		if record is not Dictionary: return _invalid()
		for key in ["instance_id", "unit_type", "story_group", "spawn_flag", "side_id", "facing", "animation_frame", "attribute_points", "skill_points", "petrify_rounds"]:
			if not _integer(record.get(key)): return _invalid()
		if int(record["unit_type"]) not in range(18) or int(record["spawn_flag"]) not in range(game.spawn_states.size()) or int(record["facing"]) not in range(8): return _invalid()
		if actors.has(int(record["instance_id"])): return _invalid()
		for key in ["dead", "shattered", "encounter_enabled", "collision_enabled", "story_marked"]:
			if record.get(key) is not bool: return _invalid()
		if not _point(record.get("position_pixels")) or not _integers(record.get("base_stats"), 57, -2147483648, 2147483647) or not _integers(record.get("stats"), 57, -2147483648, 2147483647) or not _integers(record.get("story_refs"), 3, 0, 10000): return _invalid()
		if record.get("effects") is not Array: return _invalid()
		for effect in record["effects"]:
			if effect is not Dictionary: return _invalid()
			for key in ["slot", "value", "duration", "icon"]:
				if not _integer(effect.get(key)): return _invalid()
			if int(effect["slot"]) not in range(57): return _invalid()
		var actor := Unit.new()
		actor.configure(record, definitions, table)
		actor.base_stats = PackedInt32Array(record["base_stats"])
		actor.stats = PackedInt32Array(record["stats"])
		actor.story_refs.assign(record["story_refs"])
		actor.effects.assign(record["effects"])
		for key in ["dead", "shattered", "encounter_enabled", "collision_enabled", "story_marked", "facing", "animation_frame", "attribute_points", "skill_points", "petrify_rounds"]: actor.set(key, record[key])
		for key in ["weapon", "armor"]:
			if record.get(key) is not Dictionary: return _invalid()
			if record[key].is_empty(): actor.set(key, null)
			else:
				var item = _item(record[key], definitions)
				if item == null: return _invalid()
				if int(record["instance_id"]) in party_ids:
					if not items.has(item.instance_id) or equipped.has(item.instance_id) or items[item.instance_id].snapshot() != item.snapshot(): return _invalid()
					item = items[item.instance_id]
					equipped[item.instance_id] = true
				actor.set(key, item)
		actor.set_pixel_position(Vector2(float(record["position_pixels"][0]), float(record["position_pixels"][1])))
		actor.reset_interpolation()
		if not game.collision.contains(actor.cell) or not game.collision.contains(actor.cell + actor.footprint - Vector2i.ONE): return _invalid()
		actors[actor.instance_id] = actor
		game.units.append(actor)
	for id in state["party_ids"]:
		if not actors.has(int(id)) or actors[int(id)] in game.party: return _invalid()
		game.party.append(actors[int(id)])
	game.hero = game.party[0]
	if game.hero.unit_type != 0: return _invalid()
	game.collision = Collision.new()
	game.collision.configure(game.map, world["constants"]["tile_image_ids"], definitions)
	for actor in game.units:
		if game.is_active(actor) and not actor.dead and actor.collision_enabled: game.collision.occupy(actor.instance_id, actor.cell, actor.footprint)
	if state.get("scene_triggers") is not Array: return _invalid()
	for trigger in state["scene_triggers"]:
		if not _integers(trigger, 5, -100000, 100000): return _invalid()
	game.current_scene["triggers"] = state["scene_triggers"].duplicate(true)
	if state.get("pending_scripts") is not Array: return _invalid()
	if not _integers(state.get("pending_scripts"), state.get("pending_scripts", []).size(), 0, 168): return _invalid()
	var movement: Dictionary = payload["exploration"]
	if not _integer(movement.get("tick_count")) or not _point([movement.get("accumulator"), 0]) or movement.get("trails") is not Dictionary: return _invalid()
	for actor in game.party:
		var trail = movement["trails"].get(str(actor.instance_id))
		if trail is not Dictionary: return _invalid()
		for key in ["history", "pending"]:
			if trail.get(key) is not Array or trail[key].size() > 10000: return _invalid()
			for point in trail[key]:
				if not _point(point): return _invalid()
	if state.has("weather"):
		var weather = state["weather"]
		if weather is not Dictionary or not _finite_nonnegative(weather.get("remaining")) or not _finite_nonnegative(weather.get("elapsed")) or not _integer(weather.get("layers")): return _invalid()
		if weather["remaining"] < 0 or weather["elapsed"] < 0 or weather["layers"] < 0 or weather["layers"] > 2: return _invalid()
		game.rain_remaining = float(weather["remaining"])
		game.rain_elapsed = float(weather["elapsed"])
		game.rain_layers = int(weather["layers"])
	game.world_rng.state = int(rng["state"])
	game.world_rng.draws = int(rng["draws"])
	game.last_rumour = int(state["last_rumour"])
	game.gold = int(state["gold"])
	game.next_item_id = int(state["next_item_id"])
	game.simulation_tick = int(state["simulation_tick"])
	game.commands.clear()
	game.rebuild_paths()
	return {"session": game, "exploration": movement, "pending": state["pending_scripts"]}


static func _finite_nonnegative(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) <= 180000
