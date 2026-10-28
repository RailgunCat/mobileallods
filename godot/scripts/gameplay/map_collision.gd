extends RefCounted
## Static terrain and unit occupancy are separate: removing a unit never erases
## a rock/water mask. Bounds are checked even on malformed modded maps.

var width: int
var height: int
var terrain := PackedByteArray()
var occupants: Dictionary[Vector2i, int] = {}
var units: Dictionary[int, Rect2i] = {}


func configure(map: Dictionary, image_ids: Array, metadata: Dictionary) -> void:
	width = int(map["width"])
	height = int(map["height"])
	terrain.resize(width * height)
	terrain.fill(0)
	occupants.clear()
	units.clear()
	if map.get("dungeon", false):
		for y in range(height):
			for x in range(width): terrain[y * width + x] = int(map["collision_rows"][y][x])
		return
	for y in range(height):
		for x in range(width):
			var source: int = int(map["source_tile_ids"][y][x])
			var image: int = int(image_ids[source])
			for offset: Array in metadata["collision_image_masks"].get(str(image), []):
				var point := Vector2i(x + int(offset[0]), y + int(offset[1]))
				if image == 48 and ((int(offset[1]) == 0 and y <= 0) or (int(offset[1]) == -1 and y <= 1)):
					continue
				if not contains(point):
					if image == 35: # Original try/catch aborts remaining writes.
						break
					continue
				terrain[point.y * width + point.x] = 1
			if source == 42:
				terrain[y * width + x] = 1


func contains(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func is_terrain_blocked(cell: Vector2i) -> bool:
	return not contains(cell) or terrain[cell.y * width + cell.x] != 0


func can_stand(cell: Vector2i, footprint := Vector2i.ONE, ignore_id: int = -1) -> bool:
	if footprint.x < 1 or footprint.y < 1:
		return false
	for y in range(cell.y, cell.y + footprint.y):
		for x in range(cell.x, cell.x + footprint.x):
			var point := Vector2i(x, y)
			if is_terrain_blocked(point):
				return false
	var proposed := Rect2i(cell, footprint)
	for id: int in units:
		if id != ignore_id and proposed.intersects(units[id]):
			return false
	return true


func place(id: int, cell: Vector2i, footprint := Vector2i.ONE) -> bool:
	if not can_stand(cell, footprint, id):
		return false
	return occupy(id, cell, footprint)


func occupy(id: int, cell: Vector2i, footprint := Vector2i.ONE) -> bool:
	# Legacy NPC spawn placement can overlap terrain. Party members may overlap
	# each other during exploration. The caller validates pixel movement first.
	if not contains(cell) or not contains(cell + footprint - Vector2i.ONE):
		return false
	units[id] = Rect2i(cell, footprint)
	_rebuild_occupants()
	return true


func _rebuild_occupants() -> void:
	occupants.clear()
	for id: int in units:
		var rect: Rect2i = units[id]
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				occupants[Vector2i(x, y)] = id


func remove(id: int) -> void:
	if not units.has(id):
		return
	units.erase(id)
	_rebuild_occupants()
