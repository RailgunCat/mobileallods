extends RefCounted
## Pathfinding adapter for the legacy pixel collision body. Combat still uses
## MapCollision's footprint rules; exploration centers need extra clearance.

var _session: WeakRef
var session:
	get: return _session.get_ref()
var unit
var width: int
var height: int


func _init(game, actor) -> void:
	_session = weakref(game)
	unit = actor
	width = game.collision.width
	height = game.collision.height


func contains(cell: Vector2i) -> bool:
	return session.collision.contains(cell)


func can_stand(cell: Vector2i, _footprint := Vector2i.ONE, _ignore_id: int = -1) -> bool:
	# A leader can start between grid centers. Seed the real current cell so the
	# route's initial alignment can be checked by the pixel motor, without a snap.
	if cell == unit.cell:
		return session.can_move_pixels(unit, unit.position_pixels, unit.facing)
	return session.can_move_pixels(unit, Vector2(cell) * 16 + Vector2(unit.footprint) * 8, unit.facing)
