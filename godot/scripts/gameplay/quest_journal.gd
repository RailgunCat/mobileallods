extends RefCounted
const State = preload("res://scripts/gameplay/game_ids.gd").QuestState

static func entries(source: Array, states: Array) -> Array[Dictionary]:
	var pending: Array[Dictionary] = []
	var completed: Array[Dictionary] = []
	for quest: Dictionary in source:
		var state: int = int(states[int(quest["id"])])
		if state == State.NOT_STARTED: continue
		if state == State.COMPLETED: completed.append(quest)
		else: pending.append(quest)
	pending.append_array(completed)
	return pending
