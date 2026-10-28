extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Random = preload("res://scripts/gameplay/legacy_random.gd")
## m.int_a / byte_arr_arr_a / af / c: integer arithmetic and random draw order
## are retained. Room slots have names; only the source record layout is packed.
enum Room { EXISTS, LEFT, RIGHT, TOP, BOTTOM, WEST, NORTH, EAST, SOUTH, REACHED, VISITED, EXIT, DECOR, LOOT, COUNT }
const DIRECTIONS = [[Room.WEST, Vector2i.LEFT], [Room.EAST, Vector2i.RIGHT], [Room.NORTH, Vector2i.UP], [Room.SOUTH, Vector2i.DOWN]]
var rng
var rooms: Array = []
var rows: int
var columns: int
var offset := Vector2i.ZERO
var collision: Array = []
var tiles: Array = []
var scene: Dictionary
var entry := Vector2i.ZERO
var facing: int
var population_counts: Array[int] = []


static func matrix(width: int, height: int, fill: int = 0) -> Array:
	var result: Array = []
	for y in range(height):
		var row: Array = []
		row.resize(width)
		row.fill(fill)
		result.append(row)
	return result


func generate(map_id: int, entry_id: int, seed_value: int, definitions: Dictionary, pickup_flags: Array) -> Dictionary:
	var index: int = -map_id - 1
	if index < 0 or index >= 12: return {}
	rng = Random.new(seed_value)
	scene = {"scripts": [], "triggers": [], "units": [], "pickups": []}
	var travel: Dictionary = definitions["travel"]
	if index == 11:
		_final_chamber()
	else:
		var spec: Dictionary = travel["dungeon_specs"][index]
		rows = int(spec["room_rows"])
		columns = int(spec["room_columns"])
		if not _rooms(int(spec["minimum_rooms"])): return {}
		var base: Array = _carve()
		_expand(base)
		_exits(travel["dungeon_exits"][index], entry_id)
		_decorate()
		_loot(definitions["economy"]["pickups"][index + 12], pickup_flags)
		_populate(travel["dungeon_population"][index], definitions["unit_footprints"])
	_object_masks()
	for script: Array in travel["dungeon_scripts"][index]:
		if not script.is_empty(): scene["scripts"].append(script.duplicate())
	return {"map": {"name": str(map_id), "width": tiles[0].size(), "height": tiles.size(), "source_tile_ids": tiles, "collision_rows": collision, "dungeon": true, "seed": seed_value}, "scene": scene, "entry": {"position_pixels": [entry.x * 16, entry.y * 16], "facing": facing}, "rng": rng.snapshot()}


func _rooms(minimum: int) -> bool:
	for attempt in range(10000):
		rooms = []
		for y in range(rows):
			var row: Array = []
			for x in range(columns):
				var room := PackedInt32Array()
				room.resize(Room.COUNT)
				row.append(room)
			rooms.append(row)
		for y in range(rows):
			for x in range(columns):
				if rng.bounded(100) >= 60: continue
				var room: PackedInt32Array = rooms[y][x]
				room[Room.EXISTS] = 1
				room[Room.LEFT] = rng.bounded(3)
				room[Room.RIGHT] = room[Room.LEFT] + 2 + rng.bounded(3 - room[Room.LEFT]) + x * 6
				room[Room.LEFT] += x * 6
				room[Room.TOP] = rng.bounded(1) + 1 # The draw for modulo 1 is intentional.
				room[Room.BOTTOM] = room[Room.TOP] + 3 + rng.bounded(2 - room[Room.TOP]) + y * 6
				room[Room.TOP] += y * 6
				room[Room.WEST] = -1
				for previous_x in range(x - 1, -1, -1):
					var other: PackedInt32Array = rooms[y][previous_x]
					if other[Room.EXISTS] == 0: continue
					room[Room.WEST] = room[Room.TOP] + rng.bounded(room[Room.BOTTOM] - room[Room.TOP] - 1)
					other[Room.EAST] = room[Room.WEST]
					other[Room.TOP] = mini(other[Room.TOP], other[Room.EAST])
					other[Room.BOTTOM] = maxi(other[Room.BOTTOM], other[Room.EAST] + 2)
					rooms[y][previous_x] = other
					break
				room[Room.NORTH] = -1
				for previous_y in range(y - 1, -1, -1):
					var other: PackedInt32Array = rooms[previous_y][x]
					if other[Room.EXISTS] == 0: continue
					room[Room.NORTH] = room[Room.LEFT] + rng.bounded(room[Room.RIGHT] - room[Room.LEFT])
					other[Room.SOUTH] = room[Room.NORTH]
					other[Room.LEFT] = mini(other[Room.LEFT], other[Room.SOUTH])
					other[Room.RIGHT] = maxi(other[Room.RIGHT], other[Room.SOUTH] + 1)
					rooms[previous_y][x] = other
					break
				room[Room.EAST] = -1
				room[Room.SOUTH] = -1
				rooms[y][x] = room
		for y in range(rows - 1):
			for x in range(columns - 1):
				var room: PackedInt32Array = rooms[y][x]
				if room[Room.EXISTS] == 0: continue
				if room[Room.WEST] < 0 and room[Room.NORTH] < 0 and room[Room.EAST] < 0 and room[Room.SOUTH] < 0:
					rooms[y][x][Room.EXISTS] = 0
		for y in range(rows - 1):
			for x in range(columns - 1):
				var room: PackedInt32Array = rooms[y][x]
				if room[Room.EXISTS] == 0 or room[Room.EAST] < 0 or room[Room.SOUTH] < 0 or rng.bounded(100) >= 40: continue
				if rng.bounded(2) != 0:
					var other := _neighbor(y, x, Vector2i.RIGHT)
					rooms[y][x][Room.EAST] = -1
					rooms[other.y][other.x][Room.WEST] = -1
				else:
					var other := _neighbor(y, x, Vector2i.DOWN)
					rooms[y][x][Room.SOUTH] = -1
					rooms[other.y][other.x][Room.NORTH] = -1
		var found: bool = false
		for y in range(rows):
			if found: break
			for x in range(columns):
				if rooms[y][x][Room.EXISTS] == 0: continue
				rooms[y][x][Room.REACHED] = 1
				found = true
				break
		var changed: bool = true
		while changed:
			changed = false
			for y in range(rows):
				for x in range(columns):
					if rooms[y][x][Room.EXISTS] == 0 or rooms[y][x][Room.REACHED] == 0 or rooms[y][x][Room.VISITED] != 0: continue
					rooms[y][x][Room.VISITED] = 1
					changed = true
					for link in DIRECTIONS:
						if rooms[y][x][link[0]] < 0: continue
						var other := _neighbor(y, x, link[1])
						rooms[other.y][other.x][Room.REACHED] = 1
		var count: int = 0
		for y in range(rows):
			for x in range(columns):
				if rooms[y][x][Room.REACHED] == 0: rooms[y][x][Room.EXISTS] = 0
				if y < rows - 1 and x < columns - 1 and rooms[y][x][Room.EXISTS] != 0: count += 1
		if count >= minimum: return true
	return false


func _neighbor(y: int, x: int, direction: Vector2i) -> Vector2i:
	var point := Vector2i(x, y) + direction
	while rooms[point.y][point.x][Room.EXISTS] == 0: point += direction
	return point


func _carve() -> Array:
	var far := Vector2i.ZERO
	offset = Vector2i(columns * 6, rows * 6)
	for row in rooms:
		for room: PackedInt32Array in row:
			if room[Room.EXISTS] == 0: continue
			offset.x = mini(offset.x, room[Room.LEFT])
			offset.y = mini(offset.y, room[Room.TOP])
			far.x = maxi(far.x, room[Room.RIGHT])
			far.y = maxi(far.y, room[Room.BOTTOM])
	offset -= Vector2i(2, 2)
	far += Vector2i(3, 3)
	var base: Array = matrix(far.x - offset.x, far.y - offset.y, 1)
	for y in range(rows):
		for x in range(columns):
			var room: PackedInt32Array = rooms[y][x]
			if room[Room.EXISTS] == 0: continue
			for py in range(room[Room.TOP], room[Room.BOTTOM] + 1):
				for px in range(room[Room.LEFT], room[Room.RIGHT] + 1): base[py - offset.y][px - offset.x] = 0
			if room[Room.WEST] >= 0:
				var other := _neighbor(y, x, Vector2i.LEFT)
				for py in range(2):
					for px in range((other.x + 1) * 6, room[Room.LEFT]): base[room[Room.WEST] + py - offset.y][px - offset.x] = 0
			if room[Room.NORTH] >= 0:
				var other := _neighbor(y, x, Vector2i.UP)
				for py in range((other.y + 1) * 6, room[Room.TOP]): base[py - offset.y][room[Room.NORTH] - offset.x] = 0
			if room[Room.EAST] >= 0:
				for py in range(2):
					for px in range(room[Room.RIGHT], (x + 1) * 6): base[room[Room.EAST] + py - offset.y][px - offset.x] = 0
			if room[Room.SOUTH] >= 0:
				for py in range(room[Room.BOTTOM], (y + 1) * 6): base[py - offset.y][room[Room.SOUTH] - offset.x] = 0
	return base


func _expand(base: Array) -> void:
	var height: int = base.size()
	var width: int = base[0].size()
	var edges: Array = matrix(width, height)
	for y in range(1, height - 1):
		for x in range(1, width - 1):
			if base[y][x] == 0:
				if base[y + 1][x] == 0: edges[y][x] = 32
				continue
			if base[y + 1][x] == 0: edges[y][x] |= 8
			if base[y][x + 1] == 0: edges[y][x] |= 1
			if base[y][x - 1] == 0: edges[y][x] |= 4
			if base[y - 1][x] == 0: edges[y][x] |= 16
	collision = matrix(width * 3, height * 3)
	tiles = matrix(width * 3, height * 3)
	for y in range(height):
		for x in range(width):
			for dy in range(3):
				for dx in range(3): collision[y * 3 + dy][x * 3 + dx] = base[y][x]
			var edge: int = edges[y][x]
			if edge == 32:
				tiles[y * 3 + 1][x * 3 + 1] = 10
				continue
			if edge & 8:
				tiles[y * 3 + 1][x * 3 + 1] = (5 if rng.next_signed() > 0 else 6) if rng.bounded(100) < 20 else maxi(0, rng.bounded(3) - 1) + 3
				tiles[(y - 1) * 3 + 2][x * 3 + 1] = 7
			if edge & 1: tiles[(y - 1) * 3 + 1][x * 3 + 2] = 1
			if edge & 4: tiles[(y - 1) * 3 + 1][x * 3] = 2
			if edge & 16: tiles[(y - 1) * 3][x * 3 + 1] = 8
	# Source raises the collision silhouette three pixels-of-grid rows upward.
	for y in range(3, (height - 1) * 3 + 1):
		for x in range((width - 1) * 3 + 1):
			if collision[y][x] == 0: continue
			for dy in range(1, 4): collision[y - dy][x] = collision[y][x]


func _row_counts() -> Array[int]:
	var counts: Array[int] = []
	for y in range(rows):
		var count: int = 0
		for room: PackedInt32Array in rooms[y]:
			if room[Room.EXISTS] != 0 and room[Room.EXIT] == 0: count += 1
		counts.append(count)
	return counts


func _exits(table: Array, entry_id: int) -> void:
	var counts: Array[int] = _row_counts()
	var cursor: int = 0
	var ordinal: int = 0
	while int(table[cursor]) != 0:
		var kind: int = int(table[cursor])
		var bottom: bool = int(table[cursor + 1]) != 0
		cursor += 2
		var chosen := Vector2i.ZERO
		var order: Array = range(rows - 1, -1, -1) if bottom else range(rows)
		for y: int in order:
			if counts[y] <= 0: continue
			var nth: int = rng.bounded(counts[y]) + 1
			for x in range(columns):
				if rooms[y][x][Room.EXISTS] != 0 and rooms[y][x][Room.EXIT] == 0: nth -= 1
				if nth != 0: continue
				chosen = Vector2i(x, y)
				rooms[y][x][Room.EXIT] = 1
				counts[y] -= 1
				break
			break
		var room: PackedInt32Array = rooms[chosen.y][chosen.x]
		var px: int = 3 * (room[Room.LEFT] + int((room[Room.RIGHT] - room[Room.LEFT]) / 2.0) - offset.x)
		var py: int = 3 * (room[Room.BOTTOM if bottom else Room.TOP] - offset.y)
		var trigger_y: int = py - 1 if bottom else py
		tiles[py - 2][px + 1] = 15 if bottom else 9
		if ordinal == entry_id:
			entry = Vector2i(px + 1, py - 2 if bottom else py + 3)
			facing = Ids.Facing.UP if bottom else Ids.Facing.DOWN
		var script_id: int = 300 + ordinal
		if kind == 1:
			scene["scripts"].append([script_id, Ids.ScriptOp.CHANGE_MAP, int(table[cursor]), int(table[cursor + 1])])
			cursor += 2
		elif kind == -1:
			scene["scripts"].append([script_id, Ids.ScriptOp.OPEN_MENU])
			cursor += 1
		scene["triggers"].append([script_id, px * 16, trigger_y * 16, (px + 3) * 16, (trigger_y + 1) * 16])
		ordinal += 1


func _decorate() -> void:
	for y in range(rows - 1, -1, -1):
		for x in range(columns):
			var room: PackedInt32Array = rooms[y][x]
			if room[Room.EXISTS] == 0 or room[Room.EXIT] != 0 or room[Room.DECOR] != 0: continue
			if rng.bounded(100) < 20:
				rooms[y][x][Room.DECOR] = 1
				var px: int = 3 * (room[Room.LEFT] - offset.x) + 3 * rng.bounded(room[Room.RIGHT] - room[Room.LEFT] - 1) + 2
				var py: int = 3 * (room[Room.TOP] - offset.y) + 3 * rng.bounded(room[Room.BOTTOM] - room[Room.TOP] - 1) + 2
				tiles[py][px] = 18
			elif rng.bounded(100) < 20:
				rooms[y][x][Room.DECOR] = 1
				var px: int = 3 * (room[Room.LEFT] - offset.x) + int(3 * (room[Room.RIGHT] - room[Room.LEFT] + 1) / 2.0) + 2
				var py: int = 3 * (room[Room.TOP] - offset.y) + int(3 * (room[Room.BOTTOM] - room[Room.TOP]) / 2.0) + 3
				tiles[py][px] = 16


func _loot(table: Array, flags: Array) -> void:
	var counts: Array[int] = _row_counts()
	for original: Dictionary in table:
		if counts.max() <= 0: break
		var y: int = rng.bounded(rows)
		while counts[y] <= 0: y = rng.bounded(rows)
		var nth: int = rng.bounded(counts[y]) + 1
		for x in range(columns):
			var room: PackedInt32Array = rooms[y][x]
			if room[Room.EXISTS] != 0 and room[Room.EXIT] == 0 and room[Room.LOOT] == 0: nth -= 1
			if nth != 0: continue
			rooms[y][x][Room.LOOT] = 1
			counts[y] -= 1
			if int(flags[int(original["pickup_id"])]) == 0:
				var px: int = 3 * (room[Room.LEFT] + int((room[Room.RIGHT] - room[Room.LEFT]) / 2.0) - offset.x)
				var py: int = 3 * (room[Room.TOP] + int((room[Room.BOTTOM] - room[Room.TOP]) / 2.0) - offset.y)
				var pickup: Dictionary = original.duplicate(true)
				pickup["position_pixels"] = [px * 16, py * 16]
				scene["pickups"].append(pickup)
			break
	population_counts = counts


func _populate(table: Array, footprints: Array) -> void:
	var blocked: Array = collision.duplicate(true)
	for pickup: Dictionary in scene["pickups"]:
		var p: Array = pickup["position_pixels"]
		for dy in range(2):
			for dx in range(2): blocked[int(p[1] / 16.0) + dy][int(p[0] / 16.0) + dx] = 1
	var counts: Array[int] = population_counts
	for y in range(rows):
		var available: int = counts[y]
		for x in range(columns):
			var room: PackedInt32Array = rooms[y][x]
			if available <= 0: break
			if room[Room.EXISTS] == 0 or room[Room.EXIT] != 0: continue
			available -= 1
			for py in range(room[Room.TOP], room[Room.BOTTOM]):
				for px in range(room[Room.LEFT], room[Room.RIGHT] + 1):
					for spec: Dictionary in table:
						if rng.bounded(100) >= int(spec["chance"]): continue
						var type: int = int(spec["unit_type"])
						var shape: Array = footprints[type]
						var cell := nearest(blocked, Vector2i(3 * (px - offset.x) + 1, 3 * (py - offset.y) + 1), Vector2i(int(shape[0]), int(shape[1])))
						for dy in range(int(shape[1])):
							for dx in range(int(shape[0])): blocked[cell.y + dy][cell.x + dx] = 1
						scene["units"].append([0, cell.x * 16 + int(shape[0]) * 8, cell.y * 16 + int(shape[1]) * 8, type, Ids.StoryGroup.HOSTILES, 1, Ids.NO_STORY_HOOK, Ids.NO_STORY_HOOK, Ids.NO_STORY_HOOK])
						break


static func nearest(blocked: Array, target: Vector2i, shape: Vector2i) -> Vector2i:
	for distance in range(100):
		for y in range(maxi(0, target.y - distance), mini(blocked.size(), target.y + distance + 1)):
			for x in range(maxi(0, target.x - distance), mini(blocked[0].size(), target.x + distance + 1)):
				if absi(y - target.y) + absi(x - target.x) != distance: continue
				if y + shape.y > blocked.size() or x + shape.x > blocked[0].size(): continue
				var free: bool = true
				for dy in range(shape.y):
					for dx in range(shape.x):
						if blocked[y + dy][x + dx] != 0: free = false
				if free: return Vector2i(x, y)
	return Vector2i.ZERO


func _object_masks() -> void:
	var masks := {17: Rect2i(-3, -4, 4, 5), 19: Rect2i(-1, -3, 2, 4), 20: Rect2i(-2, -2, 3, 3), 22: Rect2i(-2, -2, 3, 3)}
	for y in range(tiles.size()):
		for x in range(tiles[0].size()):
			var kind: int = tiles[y][x]
			if not masks.has(kind): continue
			var rect: Rect2i = masks[kind]
			for dy in range(rect.position.y, rect.end.y):
				for dx in range(rect.position.x, rect.end.x):
					if y + dy >= 0 and y + dy < collision.size() and x + dx >= 0 and x + dx < collision[0].size(): collision[y + dy][x + dx] = 1
			if kind == 22: collision[y - 2][x - 2] = 0


func _final_chamber() -> void:
	var base: Array = matrix(11, 18, 1)
	for rect in [Rect2i(4, 2, 3, 3), Rect2i(2, 5, 7, 7), Rect2i(4, 12, 3, 4)]:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x): base[y][x] = 0
	_expand(base)
	entry = Vector2i(16, 43)
	facing = Ids.Facing.UP
	scene["units"].append([0, 264, 176, Ids.UnitKind.DRAGON, Ids.StoryGroup.HOSTILES, 1, Ids.NO_STORY_HOOK, Ids.NO_STORY_HOOK, Ids.NO_STORY_HOOK])
	scene["triggers"].append([153, 240, 704, 288, 720])
	tiles[43][16] = 15
	tiles[30][18] = 16
	for x in [13, 20]:
		for y in [44, 41, 38, 35]: tiles[y][x] = 19
	for point in [Vector2i(20, 10), Vector2i(16, 14), Vector2i(20, 22), Vector2i(17, 28), Vector2i(16, 32)]: tiles[point.y][point.x] = 18
	for point in [Vector2i(10, 26), Vector2i(25, 26), Vector2i(10, 20), Vector2i(25, 20), Vector2i(14, 11), Vector2i(21, 11)]: tiles[point.y][point.x] = 17
	for y in range(12):
		for x in range(4, 25): collision[y][x] = 1
	for point in [Vector2i(16, 23), Vector2i(23, 31)]: tiles[point.y][point.x] = 22
	for point in [Vector2i(11, 30), Vector2i(18, 28)]: tiles[point.y][point.x] = 21
