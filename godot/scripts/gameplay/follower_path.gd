extends RefCounted
## Local recovery for a follower disconnected from its delayed trail. Search
## the motor's four-pixel lattice using the actual body, including off-center
## passages. Ordinary following still consumes its original ordered waypoints.
const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const MAX_EXPANDED: int = 4096


static func can_reach_pose(game, actor, point: Vector2) -> bool:
	for facing in range(4):
		if game.can_move_pixels(actor, point, facing): return true
	return false


static func _enqueue(frontier: Array[Dictionary], entry: Dictionary) -> void:
	var low: int = 0
	var high: int = frontier.size()
	while low < high:
		var middle: int = int((low + high) / 2.0)
		if float(frontier[middle]["score"]) >= float(entry["score"]): low = middle + 1
		else: high = middle
	frontier.insert(low, entry)


static func _distance(a: Vector2, b: Vector2) -> float:
	return absf(a.x - b.x) + absf(a.y - b.y)


static func find(game, actor, target: Vector2) -> Array[Vector2]:
	var empty: Array[Vector2] = []
	if not can_reach_pose(game, actor, target): return empty
	var start: Vector2 = actor.position_pixels
	var speed: float = float(game.definitions["exploration"]["pixels_per_tick"])
	var frontier: Array[Dictionary] = [{"point": start, "cost": 0.0, "score": _distance(start, target)}]
	var costs: Dictionary = {start: 0.0}
	var parents: Dictionary = {}
	var expanded: int = 0
	while not frontier.is_empty() and expanded < MAX_EXPANDED:
		var entry: Dictionary = frontier.pop_back()
		var point: Vector2 = entry["point"]
		if float(entry["cost"]) != float(costs[point]): continue
		expanded += 1
		var delta: Vector2 = target - point
		# Connect an arbitrary old breadcrumb to the four-pixel lattice using
		# two checked cardinal steps, each no longer than the normal speed.
		if absf(delta.x) <= speed and absf(delta.y) <= speed:
			var corner := Vector2(target.x, point.y)
			var x_safe: bool = delta.x == 0 or game.can_move_pixels(actor, corner, 0 if delta.x < 0 else 1)
			var y_safe: bool = delta.y == 0 or game.can_move_pixels(actor, target, 2 if delta.y < 0 else 3)
			if x_safe and y_safe:
				var result: Array[Vector2] = []
				var cursor: Vector2 = point
				while cursor != start:
					result.append(cursor)
					cursor = parents[cursor]
				result.reverse()
				if delta.x != 0: result.append(corner)
				if delta.y != 0: result.append(target)
				return result
		for facing in range(DIRECTIONS.size()):
			var next: Vector2 = point + Vector2(DIRECTIONS[facing]) * speed
			var cost: float = float(entry["cost"]) + speed
			if cost >= float(costs.get(next, INF)): continue
			if not game.can_move_pixels(actor, next, facing): continue
			costs[next] = cost
			parents[next] = point
			_enqueue(frontier, {"point": next, "cost": cost, "score": cost + _distance(next, target)})
	return empty
