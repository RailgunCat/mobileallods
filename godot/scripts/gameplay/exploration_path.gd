extends RefCounted
## Fallback for passages that the 16px center graph cannot represent. Search
## the motor's real lattice; every edge uses the same collision check as walking.
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const FACINGS: Array[int] = [2, 3, 0, 1]


static func find(game, actor, target: Vector2i) -> Dictionary:
	var cells: Array[Vector2i] = []
	var pixels: Array[Vector2] = []
	var result := {"requested": target, "resolved": actor.cell, "reachable": false, "path": cells, "pixel_path": pixels, "cost": 0}
	if not game.collision.contains(target): return result
	var start: Vector2 = actor.position_pixels
	var goal: Vector2 = Vector2(target) * 16 + Vector2(actor.footprint) * 8
	var speed: float = float(game.definitions["exploration"]["pixels_per_tick"])
	var frontier: Array[Vector2] = [start]
	var parents: Dictionary = {start: start}
	var closest: Vector2 = start
	var tail: Array[Vector2] = []
	var head: int = 0
	while head < frontier.size():
		var point: Vector2 = frontier[head]
		head += 1
		if point.distance_squared_to(goal) < closest.distance_squared_to(goal): closest = point
		var delta: Vector2 = goal - point
		# A saved/scripted position need not share the target center's phase.
		# Join it with at most two checked cardinal steps, never a diagonal snap.
		if absf(delta.x) <= speed and absf(delta.y) <= speed:
			var corner := Vector2(goal.x, point.y)
			var x_safe: bool = delta.x == 0 or game.can_move_pixels(actor, corner, 0 if delta.x < 0 else 1)
			var y_safe: bool = delta.y == 0 or game.can_move_pixels(actor, goal, 2 if delta.y < 0 else 3)
			if x_safe and y_safe:
				closest = point
				if delta.x != 0: tail.append(corner)
				if delta.y != 0: tail.append(goal)
				result["reachable"] = true
				break
		for index in range(DIRECTIONS.size()):
			var next: Vector2 = point + Vector2(DIRECTIONS[index]) * speed
			if parents.has(next) or not game.can_move_pixels(actor, next, FACINGS[index]): continue
			parents[next] = point
			frontier.append(next)
	var cursor: Vector2 = closest
	while cursor != start:
		pixels.append(cursor)
		cursor = parents[cursor]
	pixels.reverse()
	pixels.append_array(tail)
	var last_cell: Vector2i = actor.cell
	for point: Vector2 in pixels:
		var cell := Vector2i((point - Vector2(actor.footprint) * 8) / 16.0)
		if cell != last_cell:
			cells.append(cell)
			last_cell = cell
	if not pixels.is_empty():
		result["resolved"] = Vector2i((pixels.back() - Vector2(actor.footprint) * 8) / 16.0)
		if cells.is_empty(): cells.append(result["resolved"])
	result["cost"] = cells.size()
	return result
