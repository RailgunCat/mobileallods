extends RefCounted
## Read-only presentation events. Lifetime does not depend on calls to _draw().
const STEP: float = 0.062
const LIFETIME: float = 20 * STEP
const SpellVisuals = preload("res://scripts/gameplay/spell_presentation.gd")
var clock: float = 0
var entries: Array[Dictionary] = []
var meteor_impacts: Array[Dictionary] = []

func clear() -> void:
	clock = 0
	entries.clear()
	meteor_impacts.clear()

func add_text(point: Vector2, message: String, born: float = -1) -> void:
	var time: float = clock if born < 0 else born
	if clock - time >= LIFETIME: return
	entries.append({"origin": point, "text": message, "born": time})

func advance(delta: float) -> void:
	clock += maxf(0, delta)
	for i in range(entries.size() - 1, -1, -1):
		if clock - float(entries[i]["born"]) + 0.000000001 >= LIFETIME: entries.remove_at(i)
	for i in range(meteor_impacts.size() - 1, -1, -1):
		if clock - float(meteor_impacts[i]["born"]) >= SpellVisuals.DEBRIS_LIFETIME: meteor_impacts.remove_at(i)


func add_meteor(cell: Vector2i, born: float) -> void:
	meteor_impacts.append({"cell": cell, "born": born})


func meteor_shards() -> PackedVector2Array:
	var result := PackedVector2Array()
	for impact: Dictionary in meteor_impacts:
		var cell: Vector2i = impact["cell"]
		result.append_array(SpellVisuals.meteor_shards(cell, clock - float(impact["born"]), cell.x * 173 + cell.y * 317 + int(float(impact["born"]) / STEP)))
	return result

func records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in entries:
		var rise: int = maxi(0, int((clock - float(entry["born"]) + 0.000000001) / STEP))
		result.append({"point": Vector2(entry["origin"]) - Vector2(0, rise), "text": entry["text"]})
	return result
