extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const ScriptOp = Ids.ScriptOp
const QuestState = Ids.QuestState
const TriggerState = Ids.TriggerState
const SpawnState = Ids.SpawnState
const StoryGroup = Ids.StoryGroup
const Side = Ids.Side
const MoveAxis = Ids.MoveAxis
const SceneData = preload("res://scripts/gameplay/legacy_scene_data.gd")
const Inventory = preload("res://scripts/gameplay/inventory_rules.gd")
## Source scene VM. Story text, portraits, instruction offsets and trigger order
## are recovered data. Unknown instructions stop with an explicit diagnostic.

signal changed
signal party_changed
signal travel_requested(map_id: int, entry_id: int)
signal encounter_requested(ids: Array[int])
signal party_repositioned
signal world_map_requested
const Pathfinder = preload("res://scripts/gameplay/grid_pathfinder.gd")

class MotionGrid:
	extends RefCounted
	var game
	var actor
	var bounds: Rect2i
	var width: int
	var height: int
	func contains(cell: Vector2i) -> bool: return bounds.has_point(cell)
	func can_stand(cell: Vector2i, footprint := Vector2i.ONE, _ignore: int = -1) -> bool:
		if not bounds.encloses(Rect2i(cell, footprint)): return false
		for y in range(cell.y, cell.y + footprint.y):
			for x in range(cell.x, cell.x + footprint.x):
				if game.collision.is_terrain_blocked(Vector2i(x, y)): return false
		for other in game.units:
			if other == actor or other.dead or not other.collision_enabled or not game.is_active(other): continue
			if other in game.party and (actor in game.party or cell == actor.cell): continue
			if Rect2i(cell, footprint).intersects(Rect2i(other.cell, other.footprint)): return false
		return true

var game
var enabled: bool = false
var data: Dictionary
var triggers: Array = []
var scripts: Dictionary[int, Array] = {}
var missing_scripts: Array[int] = []
var script_id: int = -1
var pc: int = 0
var modal: Dictionary = {}
var fault: Dictionary = {}
var motion: Dictionary = {}
var events: Array[Dictionary] = []
var pending: Array[int] = []
var accumulator: float = 0.0
var ticks: int = 0
var wait_ms: int = 0
var shaking: bool = false
var encounter_ids: Array[int] = []
var force_encounter: bool = false
var _resume_mode: StringName = &"exploration"


func configure(session, world: Dictionary, campaign_data: Dictionary, activate: bool = true) -> void:
	game = session
	data = campaign_data
	enabled = activate
	triggers = []
	for record: Array in game.current_scene["triggers"]: triggers.append(SceneData.trigger(record))
	scripts.clear()
	missing_scripts.clear()
	var entries: Array = SceneData.scripts(game.current_scene["scripts"], game.definitions["travel"]["opcode_lengths"])
	# Original m.void_d scans in source order and stops at the first match.
	# Map four contains two records numbered 45; the first is the hermit talk.
	for entry: Dictionary in entries:
		var id: int = int(entry["script_id"])
		if not scripts.has(id): scripts[id] = entry["instructions"]
	script_id = -1
	pc = 0
	modal = {}
	fault = {}
	motion = {}
	events.clear()
	pending.clear()
	accumulator = 0
	ticks = 0
	wait_ms = 0
	shaking = false
	encounter_ids.clear()
	force_encounter = false
	_repair_skipped_hermit_conversation()
	_repair_survivor_collision()
	changed.emit()

func _repair_survivor_collision() -> void:
	# Older saves retain the map-eleven survivor's footprint after scene 139.
	# m.M(), case 2 ends with n.j(): the NPC stays visible but no longer blocks.
	if not enabled or game.location_id != 10 or int(game.triggers[139]) != TriggerState.DISABLED: return
	var actor = _actor(11)
	if actor == null or actor in game.party or not actor.collision_enabled or not game.is_active(actor): return
	_release_motion_collision(actor)
	_record("collision_repaired", {"actor": actor.instance_id, "reason": "completed_survivor_scene"})

func _repair_skipped_hermit_conversation() -> void:
	# Old builds ran the later duplicate, disabled 45 and left the hermit
	# standing silently. Repair this exact incomplete state when loading/traveling.
	var id: int = Ids.StoryScript.CONFRONT_HERMIT
	if not enabled or game.location_id != 3 or int(game.triggers[id]) != TriggerState.DISABLED: return
	if int(game.quests[Ids.Quest.HERMIT_SEARCH]) == QuestState.COMPLETED or int(game.spawn_states[18]) != SpawnState.HIDDEN: return
	for actor in game.units:
		if actor.unit_type == Ids.UnitKind.HERMIT and actor.spawn_flag == 17 and not actor.dead and game.is_active(actor) and actor not in game.party:
			game.triggers[id] = TriggerState.ENABLED
			_record("conversation_repaired", {"script_id": id, "reason": "old_duplicate_script_lookup"})
			return


func busy() -> bool:
	return enabled and (script_id >= 0 or not modal.is_empty() or not fault.is_empty())


func _record(kind: String, detail: Dictionary = {}) -> void:
	var event := {"event": kind, "tick": ticks, "script": script_id, "pc": pc}
	event.merge(detail)
	events.append(event)


func _fail(message: String) -> void:
	fault = {"message": message, "script": script_id, "pc": pc}
	game.mode = &"campaign_error"
	_record("script_error", fault)
	changed.emit()


func start_script(id: int, reason: String = "trigger") -> bool:
	if not enabled or busy() or game.mode != &"exploration": return false
	if not scripts.has(id):
		# Original m.void_d(int) leaves exploration unchanged when lookup finds
		# no program. Recovered regions include 57 (map 5), 99/100 (map 7).
		# Keep the flags and first-region polling order, and diagnose once per
		# scene so standing inside a dangling region does not grow the event log.
		if id not in missing_scripts:
			missing_scripts.append(id)
			_record("script_missing", {"requested_id": id, "reason": reason})
		return false
	script_id = id
	pc = 0
	accumulator = 0
	game.mode = &"script"
	for actor in game.units:
		actor.walking = false
		actor.reset_interpolation()
	_record("script_started", {"reason": reason})
	changed.emit()
	return true


func check_triggers() -> void:
	if not enabled or busy() or game.mode != &"exploration": return
	if not pending.is_empty():
		var id: int = pending.pop_front()
		if int(game.triggers[id]) == TriggerState.ENABLED: start_script(id, "death_hook")
		return
	var point: Vector2 = game.hero.position_pixels
	for region: Dictionary in triggers:
		var id: int = int(region["script_id"])
		if id < 300 and int(game.triggers[id]) != TriggerState.ENABLED: continue
		if point.x >= region["left"] and point.x <= region["right"] and point.y >= region["top"] and point.y <= region["bottom"]:
			start_script(id)
			return


func after_battle(participants: Array[int]) -> void:
	if not enabled: return
	var index: int = game.location_id if game.location_id >= 0 else -game.location_id - 1 + 13
	var hooks: Array = game.definitions["travel"]["group_death_hooks"][index]
	for i in range(0, hooks.size(), 2):
		var group: int = int(hooks[i])
		var hook: int = int(hooks[i + 1])
		if hook == Ids.NO_STORY_HOOK or int(game.triggers[hook]) != TriggerState.ENABLED: continue
		var alive: bool = false
		for actor in game.units:
			if actor not in game.party and actor.story_group == group and not actor.dead: alive = true
		if not alive and hook not in pending: pending.append(hook)
	for actor in game.units:
		var hook: int = actor.death_script
		if actor.instance_id in participants and actor.dead and actor not in game.party and actor.encounter_enabled and hook != Ids.NO_STORY_HOOK and int(game.triggers[hook]) == TriggerState.ENABLED and hook not in pending:
			pending.append(hook)
	check_triggers()


func _show_pages(kind: String, id: int, pages: Array) -> void:
	_resume_mode = &"script" if script_id >= 0 else game.mode
	modal = {"kind": kind, "id": id, "page": 0, "pages": pages}
	game.mode = &"dialogue"
	for actor in game.units: actor.reset_interpolation()
	_record("modal_opened", {"kind": kind, "id": id})
	changed.emit()


func show_tutorial(id: int) -> void:
	if not enabled or not modal.is_empty() or int(game.tutorial_seen[id]) != 0: return
	game.tutorial_seen[id] = 1
	_show_pages("tutorial", id, [{"speaker": "Обучение", "portrait": -1, "text": data["tutorials"][id]}])


func acknowledge() -> void:
	if modal.is_empty(): return
	var page: int = int(modal["page"])
	_record("page_read", {"kind": modal["kind"], "id": modal["id"], "page": page})
	if page + 1 < modal["pages"].size():
		modal["page"] = page + 1
	else:
		modal = {}
		game.mode = _resume_mode
	changed.emit()


func _actor(group: int):
	for actor in game.units:
		if actor.story_group == group: return actor
	return null


func advance(delta: float) -> void:
	if not enabled or not modal.is_empty() or not fault.is_empty() or script_id < 0: return
	accumulator += maxf(0, delta)
	while accumulator + 0.000000001 >= 0.062:
		accumulator -= 0.062
		ticks += 1
		_tick()
		if script_id < 0 or not modal.is_empty() or not fault.is_empty():
			accumulator = 0
			break
	accumulator = maxf(0, accumulator)


func _finish() -> void:
	_record("script_finished")
	script_id = -1
	game.mode = &"exploration"
	shaking = false
	changed.emit()
	if force_encounter and not encounter_ids.is_empty():
		force_encounter = false
		encounter_requested.emit(encounter_ids.duplicate())
		encounter_ids.clear()


func _tick() -> void:
	for actor in game.units: actor.previous_position = actor.position_pixels
	if not motion.is_empty():
		_tick_motion()
		return
	if wait_ms > 0:
		wait_ms -= 62
		if wait_ms <= 0:
			if shaking: game.start_rain(180.0)
			shaking = false
			pc += 1
		changed.emit()
		return
	if pc >= scripts[script_id].size():
		_finish()
		return
	var instruction: Dictionary = scripts[script_id][pc]
	var op: int = int(instruction["opcode"])
	var operands: Dictionary = instruction.get("operands", {})
	_record("instruction", {"opcode": op, "offset": int(instruction["offset"]), "operands": operands.duplicate()})
	match op:
		ScriptOp.SET_TRIGGER: game.triggers[int(operands["flag"])] = int(operands["state"])
		ScriptOp.SET_QUEST:
			var index: int = int(operands["quest"])
			if int(game.quests[index]) not in [QuestState.COMPLETED, QuestState.FAILED]: game.quests[index] = int(operands["state"])
		ScriptOp.SET_ITEM: game.pickup_flags[int(operands["item_flag"])] = int(operands["state"])
		ScriptOp.SET_PROGRESS: game.flags["e"][int(operands["progress_flag"])] = int(operands["state"])
		ScriptOp.IF_FLAG:
			var bank: Array = game.quests if int(operands["bank"]) == 1 else game.triggers
			if int(bank[int(operands["flag"])]) != int(operands["state"]):
				pc += 1
				while pc < scripts[script_id].size() and int(scripts[script_id][pc]["opcode"]) not in [ScriptOp.ELSE, ScriptOp.END_IF]: pc += 1
		ScriptOp.ELSE:
			pc += 1
			while pc < scripts[script_id].size() and int(scripts[script_id][pc]["opcode"]) != ScriptOp.END_IF: pc += 1
		ScriptOp.END_IF: pass
		ScriptOp.MOVE_ACTOR:
			_start_motion(operands)
			return
		ScriptOp.DIALOGUE:
			var id: int = int(operands["dialogue_id"])
			if id >= data["dialogues"].size():
				_fail("Нет диалога %d" % id)
				return
			pc += 1
			_show_pages("dialogue", id, data["dialogues"][id]["pages"])
			return
		ScriptOp.QUAKE:
			wait_ms = int(operands["duration_units"]) * 100
			shaking = true
			changed.emit()
			return
		ScriptOp.RECRUIT:
			var actor = _actor(int(operands["group"]))
			if actor == null:
				_fail("Нет персонажа группы %d" % int(operands["group"]))
				return
			if actor not in game.party:
				actor.side_id = Side.PARTY
				if actor.story_group == StoryGroup.RADIUS: game.party.insert(mini(2, game.party.size()), actor)
				else: game.party.append(actor)
				game.spawn_states[actor.spawn_flag] = SpawnState.REMOVED
				_record("recruited", {"instance_id": actor.instance_id, "group": actor.story_group})
				Inventory.sync_party(game)
				party_changed.emit()
		ScriptOp.DETACH:
			var actor = _actor(int(operands["group"]))
			if actor != null and actor in game.party:
				game.party.erase(actor)
				actor.side_id = Side.HOSTILE
				game.set_spawn_state(actor.spawn_flag, SpawnState.VISIBLE)
				_record("detached", {"instance_id": actor.instance_id})
				Inventory.sync_party(game)
				party_changed.emit()
		ScriptOp.DISABLE_SELF: game.triggers[script_id] = TriggerState.DISABLED
		ScriptOp.SET_SPAWN:
			var flag: int = int(operands["spawn_flag"])
			if int(game.spawn_states[flag]) != SpawnState.REMOVED: game.set_spawn_state(flag, int(operands["state"]))
		ScriptOp.TUTORIAL:
			pc += 1
			show_tutorial(int(operands["tutorial_id"]))
			return
		ScriptOp.FACE_ACTOR:
			var actor = _actor(int(operands["group"]))
			if actor != null: actor.facing = int(operands["direction"])
		ScriptOp.TELEPORT_PARTY:
			var Dungeon = preload("res://scripts/gameplay/dungeon_generator.gd")
			for actor in game.party: game.collision.remove(actor.instance_id)
			for actor in game.party:
				var blocked: Array = Dungeon.matrix(game.collision.width, game.collision.height)
				for y in range(game.collision.height):
					for x in range(game.collision.width): blocked[y][x] = int(game.collision.is_terrain_blocked(Vector2i(x, y)))
				for rect: Rect2i in game.collision.units.values():
					for y in range(rect.position.y, rect.end.y):
						for x in range(rect.position.x, rect.end.x): blocked[y][x] = 1
				var facing: int = actor.facing
				actor.move_to(Dungeon.nearest(blocked, Vector2i(int(operands["tile_x"]), int(operands["tile_y"])), actor.footprint))
				actor.facing = facing
				actor.walking = false
				actor.reset_interpolation()
				game.collision.occupy(actor.instance_id, actor.cell, actor.footprint)
			game.rebuild_paths()
			party_repositioned.emit()
		ScriptOp.GROUP_COLLISION, ScriptOp.REVIVE_GROUP:
			for actor in game.units:
				if actor.story_group != int(operands["group"]) or (actor.shattered and int(operands["include_shattered"]) != 1): continue
				if op == ScriptOp.GROUP_COLLISION:
					actor.collision_enabled = int(operands["blocked"]) == 1
				else:
					actor.shattered = false
					actor.dead = false
				if actor.collision_enabled and not actor.dead and game.is_active(actor): game.collision.occupy(actor.instance_id, actor.cell, actor.footprint)
				else: game.collision.remove(actor.instance_id)
		ScriptOp.MARK_ENCOUNTER:
			for actor in game.units:
				if actor.story_group != int(operands["group"]): continue
				actor.story_marked = true
				actor.encounter_enabled = true
				if actor.instance_id not in encounter_ids: encounter_ids.append(actor.instance_id)
		ScriptOp.FORCE_ENCOUNTER: force_encounter = true
		ScriptOp.CHANGE_MAP:
			game.mode = &"travel"
			travel_requested.emit(int(operands["map"]), int(operands["entry"]))
			return
		ScriptOp.OPEN_MENU:
			pc += 1
			game.mode = &"world_map"
			world_map_requested.emit()
			return
		_:
			_fail("Не реализована инструкция %d (сценарий %d, offset %d)" % [op, script_id, int(instruction["offset"])])
			return
	pc += 1
	changed.emit()


func _start_motion(operands: Dictionary) -> void:
	var actor = _actor(int(operands["group"]))
	if actor == null:
		_fail("Не найден участник движения группы %d" % int(operands["group"]))
		return
	var target := Vector2(float(operands["tile_x"]), float(operands["tile_y"])) * 16
	var relative = _actor(int(operands["relative_group"]))
	if relative != null: target += relative.position_pixels
	if int(operands["axis"]) == MoveAxis.X_ONLY: target.y = actor.position_pixels.y
	if int(operands["axis"]) == MoveAxis.Y_ONLY: target.x = actor.position_pixels.x
	var goal := Vector2i(int(target.x / 16.0), int(target.y / 16.0))
	var begin: Vector2i = actor.cell
	var low := Vector2i(maxi(mini(begin.x, goal.x) - 5, 0), maxi(mini(begin.y, goal.y) - 5, 0))
	var high := Vector2i(mini(maxi(begin.x, goal.x) + 5, game.collision.width), mini(maxi(begin.y, goal.y) + 5, game.collision.height))
	var grid := MotionGrid.new()
	grid.game = game
	grid.actor = actor
	grid.bounds = Rect2i(low, high - low)
	grid.width = game.collision.width
	grid.height = game.collision.height
	var finder := Pathfinder.new()
	finder.build(grid, begin, actor.footprint, actor.instance_id)
	var result: Dictionary = finder.route(goal)
	var cells: Array[Vector2i] = []
	cells.assign(result["path"])
	if cells.is_empty():
		_release_motion_collision(actor)
		_record("movement_no_path", {"actor": actor.instance_id, "goal": [goal.x, goal.y]})
		pc += 1
		return
	motion = {"actor": actor.instance_id, "path": cells, "index": 0, "step": 0, "duration": maxi(1, int(operands["ticks_per_cell"])), "flags": int(operands["options"])}
	_record("movement_started", {"actor": actor.instance_id, "goal": [goal.x, goal.y], "resolved": [cells.back().x, cells.back().y]})
	changed.emit()


func _tick_motion() -> void:
	var actor
	for candidate in game.units:
		if candidate.instance_id == int(motion["actor"]): actor = candidate
	var camera := Rect2i(Vector2i((game.hero.position_pixels - Vector2(79, 95)) / 16.0) - actor.footprint, Vector2i(10, 12) + actor.footprint * 2 + Vector2i(0, 2))
	if (int(motion["flags"]) & Ids.MotionOption.SKIP_OFFSCREEN_TAIL) != 0 and not camera.has_point(actor.cell):
		actor.move_to(motion["path"].back())
		_finish_motion(actor)
		return
	if int(motion["step"]) == 0:
		motion["from"] = actor.position_pixels
		actor.move_to(motion["path"][int(motion["index"])])
		motion["to"] = actor.position_pixels
		actor.position_pixels = motion["from"]
		game.collision.occupy(actor.instance_id, actor.cell, actor.footprint)
	motion["step"] += 1
	actor.position_pixels = Vector2(motion["from"]).lerp(motion["to"], float(motion["step"]) / float(motion["duration"]))
	actor.walking = true
	actor.animate_tick(game.definitions["exploration"]["units"][actor.unit_type])
	if int(motion["step"]) >= int(motion["duration"]):
		motion["index"] += 1
		motion["step"] = 0
		if int(motion["index"]) >= motion["path"].size(): _finish_motion(actor)
	changed.emit()


func _finish_motion(actor) -> void:
	actor.walking = false
	actor.reset_interpolation()
	_release_motion_collision(actor)
	motion = {}
	pc += 1
	changed.emit()

func _release_motion_collision(actor) -> void:
	# Source m.M(), MOVE_ACTOR releases occupancy even for an empty route.
	# Party members already ignore each other during exploration; retain their
	# normal state. GROUP_COLLISION can explicitly block an NPC again later.
	if actor in game.party: return
	actor.collision_enabled = false
	game.collision.remove(actor.instance_id)


func snapshot() -> Dictionary:
	var movement := motion.duplicate(true)
	if not motion.is_empty():
		movement["path"] = []
		for cell: Vector2i in motion["path"]: movement["path"].append([cell.x, cell.y])
		for key in ["from", "to"]:
			if motion.has(key): movement[key] = [motion[key].x, motion[key].y]
	return {"enabled": enabled, "script": script_id, "pc": pc, "modal": modal.duplicate(true), "fault": fault.duplicate(true), "motion": movement, "tick": ticks, "pending": Array(pending), "events": events.duplicate(true), "wait_ms": wait_ms}
