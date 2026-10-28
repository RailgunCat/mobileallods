extends RefCounted
## Deterministic 62ms simulation + interpolated rendering. Followers consume
## delayed, ordered positions, retaining corners instead of cutting diagonals
## through scenery as the old unchecked n.b(n) could do.

signal route_finished(blocked: bool)
signal encounter_detected(ids: Array[int])
signal walked(actor_id: int, distance: float)
signal tick_finished
const Encounter = preload("res://scripts/gameplay/encounter_builder.gd")
const Pathfinder = preload("res://scripts/gameplay/grid_pathfinder.gd")
const PixelGrid = preload("res://scripts/gameplay/exploration_grid.gd")
const FollowerPath = preload("res://scripts/gameplay/follower_path.gd")
var session
var accumulator: float = 0.0
var tick_seconds: float = 0.062
var tick_count: int = 0
var keyboard_direction := Vector2i.ZERO
var route: Array[Vector2i] = []
var following_route: bool = false
var _targets: Array[Vector2] = []
var _history: Dictionary[int, Array] = {}
var _pending: Dictionary[int, Array] = {}
var _retry_after: Dictionary[int, int] = {}


func configure(game) -> void:
	session = game
	tick_seconds = float(game.definitions["exploration"]["tick_ms"]) / 1000.0
	accumulator = 0
	tick_count = 0
	game.simulation_tick = 0
	keyboard_direction = Vector2i.ZERO
	route.clear()
	_targets.clear()
	following_route = false
	_history.clear()
	_pending.clear()
	_retry_after.clear()
	for unit in game.units:
		unit.reset_interpolation()
		unit.walking = false
		unit.animate_tick(game.definitions["exploration"]["units"][unit.unit_type])
	for index in range(game.party.size()):
		seed_history(game.party[index], game.party[mini(index + 1, game.party.size() - 1)].position_pixels)
	_rebuild_paths()


func seed_history(unit, tail: Vector2) -> void:
	var history: Array = []
	var length: int = int(session.definitions["exploration"]["history_length"])
	var speed: float = float(session.definitions["exploration"]["pixels_per_tick"])
	# Synthetic prehistory is only needed by the explicit test-party fixture.
	for i in range(length):
		history.append(tail.move_toward(unit.position_pixels, speed * (i + 1)).round())
	_history[unit.instance_id] = history
	_pending[unit.instance_id] = []


func _rebuild_paths() -> void:
	session.pathfinder.build(PixelGrid.new(session, session.hero), session.hero.cell, session.hero.footprint, session.hero.instance_id)


func preview(target: Vector2i) -> Dictionary:
	_rebuild_paths()
	return session.pathfinder.route(target)


func start_route(cells: Array[Vector2i]) -> void:
	route.assign(cells)
	_targets.clear()
	keyboard_direction = Vector2i.ZERO
	if route.is_empty():
		return
	var hero = session.hero
	# Bring the original off-center pixel entry to its route's center using the
	# same checked cardinal motor. No diagonal first segment or instant snap.
	var center: Vector2 = Vector2(hero.cell) * 16 + Vector2(hero.footprint) * 8
	if hero.position_pixels != center:
		_targets.append(center)
	for cell in route:
		_targets.append(Vector2(cell) * 16 + Vector2(hero.footprint) * 8)
	following_route = true


func set_direction(direction: Vector2i) -> void:
	if direction == keyboard_direction:
		return
	keyboard_direction = direction
	if direction != Vector2i.ZERO:
		following_route = false
		_targets.clear()
		route.clear()


func stop() -> void:
	keyboard_direction = Vector2i.ZERO
	following_route = false
	route.clear()
	_targets.clear()
	_rebuild_paths()


func is_moving() -> bool:
	return following_route or keyboard_direction != Vector2i.ZERO


func alpha() -> float:
	return clampf(accumulator / tick_seconds, 0, 1)


func advance(delta: float) -> void:
	if session.mode != &"exploration": return
	accumulator += maxf(delta, 0)
	while accumulator + 0.000000001 >= tick_seconds:
		accumulator -= tick_seconds
		_tick()
		if session.mode != &"exploration":
			accumulator = 0
			return
	accumulator = maxf(0, accumulator)


func _toward(unit, target: Vector2) -> bool:
	var delta: Vector2 = target - unit.position_pixels
	var speed: float = float(session.definitions["exploration"]["pixels_per_tick"])
	if delta.x != 0:
		return session.move_pixels(unit, Vector2(clampf(delta.x, -speed, speed), 0))
	if delta.y != 0:
		return session.move_pixels(unit, Vector2(0, clampf(delta.y, -speed, speed)))
	return true


func _record_move(unit, previous: Vector2, party_index: int) -> void:
	if previous == unit.position_pixels:
		return
	walked.emit(unit.instance_id, previous.distance_to(unit.position_pixels))
	var history: Array = _history[unit.instance_id]
	history.append(unit.position_pixels)
	var delayed: Vector2 = history.pop_front()
	if party_index + 1 < session.party.size():
		var next_id: int = session.party[party_index + 1].instance_id
		var queue: Array = _pending[next_id]
		if queue.is_empty() or queue.back() != delayed:
			queue.append(delayed)


func _repair_follower_trail(follower, predecessor, pending: Array) -> void:
	if tick_count < _retry_after.get(follower.instance_id, 0): return
	for index in range(pending.size()):
		var target: Vector2 = pending[index]
		# Reseeding separated party members can put synthetic breadcrumbs
		# inside scenery. Reconnect to the first physically valid breadcrumb.
		if not FollowerPath.can_reach_pose(session, follower, target): continue
		_retry_after[follower.instance_id] = tick_count + 8
		var path: Array[Vector2] = FollowerPath.find(session, follower, target)
		if path.is_empty(): return # An unreachable/temporarily blocked trail waits.
		for i in range(index + 1): pending.pop_front()
		path.reverse()
		for point: Vector2 in path: pending.push_front(point)
		_toward(follower, pending[0])
		return
	# A short move can release only invalid synthetic points before the leader
	# stops. Reconnect toward the predecessor, stopping one normal trail delay
	# short, so recovery does not depend on the leader walking ten more ticks.
	_retry_after[follower.instance_id] = tick_count + 8
	var path: Array[Vector2] = FollowerPath.find(session, follower, predecessor.position_pixels)
	var gap: float = float(session.definitions["exploration"]["history_length"]) * float(session.definitions["exploration"]["pixels_per_tick"])
	while not path.is_empty() and gap > 0:
		var last: Vector2 = path.pop_back()
		var previous: Vector2 = path.back() if not path.is_empty() else follower.position_pixels
		gap -= absf(last.x - previous.x) + absf(last.y - previous.y)
	if path.is_empty(): return
	pending.clear()
	path.reverse()
	for point: Vector2 in path: pending.push_front(point)
	_toward(follower, pending[0])


func _tick() -> void:
	tick_count += 1
	session.simulation_tick = tick_count
	for unit in session.units:
		unit.previous_position = unit.position_pixels
		unit.walking = false
	var hero = session.hero
	var previous: Vector2 = hero.position_pixels
	if keyboard_direction != Vector2i.ZERO:
		session.move_pixels(hero, Vector2(keyboard_direction) * float(session.definitions["exploration"]["pixels_per_tick"]))
	elif following_route:
		while not _targets.is_empty() and hero.position_pixels == _targets[0]:
			_targets.pop_front()
			if not route.is_empty() and hero.position_pixels == Vector2(route[0]) * 16 + Vector2(hero.footprint) * 8:
				route.pop_front()
		if _targets.is_empty():
			following_route = false
			route_finished.emit(false)
		elif not _toward(hero, _targets[0]):
			following_route = false
			_targets.clear()
			route.clear()
			route_finished.emit(true)
	_record_move(hero, previous, 0)
	for index in range(1, session.party.size()):
		var follower = session.party[index]
		var pending: Array = _pending[follower.instance_id]
		while not pending.is_empty() and follower.position_pixels == pending[0]:
			pending.pop_front()
		var old: Vector2 = follower.position_pixels
		if not pending.is_empty():
			if not _toward(follower, pending[0]): _repair_follower_trail(follower, session.party[index - 1], pending)
		_record_move(follower, old, index)
	for unit in session.units:
		if session.is_active(unit):
			unit.animate_tick(session.definitions["exploration"]["units"][unit.unit_type])
	session.changed.emit()
	var detected: Array[int] = Encounter.detected(session)
	if not detected.is_empty(): encounter_detected.emit(detected)
	tick_finished.emit()


func snapshot() -> Dictionary:
	var trails: Dictionary = {}
	for id: int in _history:
		var tail: Array = []
		var pending: Array = []
		for point: Vector2 in _history[id]:
			tail.append([point.x, point.y])
		for point: Vector2 in _pending[id]:
			pending.append([point.x, point.y])
		trails[str(id)] = {"history": tail, "pending": pending}
	var targets: Array = []
	var cells: Array = []
	for target in _targets:
		targets.append([target.x, target.y])
	for cell in route:
		cells.append([cell.x, cell.y])
	return {"tick_count": tick_count, "accumulator": accumulator, "direction": [keyboard_direction.x, keyboard_direction.y], "following_route": following_route, "targets": targets, "route": cells, "trails": trails}


func restore_trails(saved: Dictionary) -> void:
	_retry_after.clear()
	tick_count = int(saved["tick_count"])
	session.simulation_tick = tick_count
	accumulator = float(saved["accumulator"])
	for actor in session.party:
		var trail: Dictionary = saved["trails"][str(actor.instance_id)]
		_history[actor.instance_id] = []
		_pending[actor.instance_id] = []
		for point: Array in trail["history"]: _history[actor.instance_id].append(Vector2(float(point[0]), float(point[1])))
		for point: Array in trail["pending"]: _pending[actor.instance_id].append(Vector2(float(point[0]), float(point[1])))
