extends RefCounted
## java.util.Random.nextInt() + abs(signed % bound), as m.int_b / m.int_a.
## Split the multiplication to keep intermediates inside signed int64.

const MASK24: int = 0xffffff
const MULTIPLIER: int = 0x5deece66d
var state: int
var draws: int = 0


func _init(seed_value: int = 0) -> void:
	state = (seed_value ^ MULTIPLIER) & 0xffffffffffff


func next_signed() -> int:
	var product: int = (state & MASK24) * MULTIPLIER + 11
	var high: int = ((product >> 24) + (state >> 24) * (MULTIPLIER & MASK24)) & MASK24
	state = (high << 24) | (product & MASK24)
	draws += 1
	var value: int = state >> 16
	return value - 0x100000000 if value >= 0x80000000 else value


func bounded(bound: int) -> int:
	assert(bound > 0)
	return absi(next_signed() % bound)


func snapshot() -> Dictionary:
	return {"state": state, "draws": draws}
