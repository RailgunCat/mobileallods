extends RefCounted
## ad/a: diagonal white streaks, then the original ripple. Visual hash is separate
## from all game RNG streams; camera movement never changes combat outcomes.
static func _hash(value: int) -> int:
	return (value * 1103515245 + 12345) & 0x7fffffff

static func samples(bounds: Rect2, elapsed: float, layers: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var tick: int = int((elapsed + 0.000000001) / 0.062)
	for sy in range(int(floor(bounds.position.y / 192)) - 1, int(ceil(bounds.end.y / 192)) + 1):
		for sx in range(int(floor(bounds.position.x / 160)) - 1, int(ceil(bounds.end.x / 160)) + 1):
			for i in range(35 * layers):
				var cycle: int = int((tick + i % 8) / 8.0)
				var stage: int = (tick + i % 8) % 8
				var seed_value: int = _hash(sx * 173 + sy * 317 + i * 997 + cycle * 65537)
				var start := Vector2(sx * 160 + seed_value % 160, sy * 192 + _hash(seed_value) % 192)
				var point := start + Vector2(4, 8) * (mini(stage, 6) + 1)
				if not bounds.grow(16).has_point(point): continue
				var length: int = maxi(0, int((1600 - (stage + 1) * 250) / 200.0))
				result.append({"point": point, "end": point + Vector2(length, length * 2), "splash": stage >= 6})
	return result
