extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Op = Ids.ScriptOp
const OPERANDS = {
	Op.SET_TRIGGER: ["flag", "state"], Op.SET_QUEST: ["quest", "state"],
	Op.MOVE_ACTOR: ["group", "relative_group", "axis", "tile_x", "tile_y", "ticks_per_cell", "options"],
	Op.DIALOGUE: ["dialogue_id"], Op.QUAKE: ["duration_units"], Op.RECRUIT: ["group"],
	Op.IF_FLAG: ["bank", "flag", "state"], Op.DETACH: ["group"], Op.CHANGE_MAP: ["map", "entry"],
	Op.SET_SPAWN: ["spawn_flag", "state"], Op.SET_ITEM: ["item_flag", "state"], Op.SET_PROGRESS: ["progress_flag", "state"],
	Op.TUTORIAL: ["tutorial_id"], Op.FACE_ACTOR: ["group", "direction"], Op.TELEPORT_PARTY: ["tile_x", "tile_y"],
	Op.GROUP_COLLISION: ["group", "blocked", "include_shattered"],
	Op.REVIVE_GROUP: ["group", "include_shattered"], Op.MARK_ENCOUNTER: ["group"],
}


static func scripts(programs: Array, lengths: Array) -> Array:
	var result: Array = []
	for program: Array in programs:
		if program.is_empty(): continue
		var cursor: int = 1
		var instructions: Array = []
		while cursor < program.size():
			var op: int = int(program[cursor])
			var args: Array = program.slice(cursor + 1, cursor + int(lengths[op]))
			var names: Array = OPERANDS.get(op, [])
			var operands: Dictionary = {}
			for i in range(names.size()): operands[names[i]] = args[i]
			instructions.append({"offset": cursor, "opcode": op, "args": args, "operands": operands})
			cursor += int(lengths[op])
		result.append({"script_id": int(program[0]), "instructions": instructions})
	return result
## Only this adapter knows the positional scene-record layout from scenes.pak.

static func spawn(record: Array) -> Dictionary:
	return {
		"spawn_flag": int(record[0]),
		"position_pixels": Vector2(float(record[1]), float(record[2])),
		"unit_type": int(record[3]), "story_group": int(record[4]),
		"encounter_enabled": int(record[5]) != 0,
		"story_refs": [int(record[6]), int(record[7]), int(record[8])],
		"facing": int(record[9]) if record.size() > 9 else (Ids.Facing.DOWN if int(record[3]) == Ids.UnitKind.HERMIT else Ids.Facing.LEFT),
	}


static func trigger(record: Array) -> Dictionary:
	return {"script_id": int(record[0]), "left": float(record[1]), "top": float(record[2]), "right": float(record[3]), "bottom": float(record[4])}
