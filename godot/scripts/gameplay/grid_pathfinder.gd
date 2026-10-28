extends RefCounted
## Legacy m.b / m.byte_arr_a: 4 neighbors, blocked-cell penalty 1000,
## descending fallback for blocked targets, original reverse tie order.

const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const INFINITY_COST: int = 30000
var collision
var distances := PackedInt32Array()
var start := Vector2i.ZERO
var _frontier: Array[Vector2i] = [] # (cost, row-major index), binary min heap.


func _less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


func _push(value: Vector2i) -> void:
	_frontier.append(value)
	var i: int = _frontier.size() - 1
	while i > 0:
		var parent: int = int((i - 1) / 2.0)
		if not _less(value, _frontier[parent]):
			break
		_frontier[i] = _frontier[parent]
		i = parent
	_frontier[i] = value


func _pop() -> Vector2i:
	var result: Vector2i = _frontier[0]
	var tail: Vector2i = _frontier.pop_back()
	if _frontier.is_empty():
		return result
	var i: int = 0
	while i * 2 + 1 < _frontier.size():
		var child: int = i * 2 + 1
		if child + 1 < _frontier.size() and _less(_frontier[child + 1], _frontier[child]):
			child += 1
		if not _less(_frontier[child], tail):
			break
		_frontier[i] = _frontier[child]
		i = child
	_frontier[i] = tail
	return result


func build(grid, origin: Vector2i, footprint := Vector2i.ONE, ignore_id: int = -1) -> void:
	collision = grid
	start = origin
	distances.resize(grid.width * grid.height)
	distances.fill(INFINITY_COST)
	_frontier.clear()
	if not grid.can_stand(origin, footprint, ignore_id):
		return
	distances[_index(origin)] = 0
	_push(Vector2i(0, _index(origin)))
	while not _frontier.is_empty():
		var item := _pop()
		if distances[item.y] != item.x:
			continue
		var cell := Vector2i(item.y % grid.width, int(item.y / float(grid.width)))
		for direction in DIRECTIONS:
			var next: Vector2i = cell + direction
			if not grid.contains(next):
				continue
			var cost: int = item.x + (1 if grid.can_stand(next, footprint, ignore_id) else 1001)
			if cost < distance(next):
				distances[_index(next)] = cost
				_push(Vector2i(cost, _index(next)))


func _index(cell: Vector2i) -> int:
	return cell.y * collision.width + cell.x


func distance(cell: Vector2i) -> int:
	return distances[_index(cell)] if collision != null and collision.contains(cell) else INFINITY_COST


func route(target: Vector2i) -> Dictionary:
	var path: Array[Vector2i] = []
	var result := {"requested": target, "resolved": start, "reachable": false, "path": path, "cost": 0}
	if collision == null or not collision.contains(target) or distance(start) != 0:
		return result
	var cursor := target
	while distance(cursor) >= 1000:
		var best := cursor
		for direction in DIRECTIONS:
			var next := cursor + direction
			if distance(next) < distance(best):
				best = next
		if best == cursor:
			return result
		cursor = best
	result["resolved"] = cursor
	result["reachable"] = cursor == target
	result["cost"] = distance(cursor)
	while cursor != start:
		path.append(cursor)
		var found: bool = false
		for direction in DIRECTIONS:
			var next := cursor + direction
			if distance(next) == distance(cursor) - 1:
				cursor = next
				found = true
				break
		if not found:
			path.clear()
			return result
	path.reverse()
	return result
