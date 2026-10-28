extends RefCounted
## Full-map indices preserve the legacy pathfinder's row-major tie order.

var collision
var arena: Rect2i
var width: int
var height: int


func _init(grid, bounds: Rect2i) -> void:
	collision = grid
	arena = bounds
	width = grid.width
	height = grid.height


func contains(cell: Vector2i) -> bool:
	return arena.has_point(cell)


func can_stand(cell: Vector2i, footprint := Vector2i.ONE, ignore_id: int = -1) -> bool:
	return arena.encloses(Rect2i(cell, footprint)) and collision.can_stand(cell, footprint, ignore_id)
