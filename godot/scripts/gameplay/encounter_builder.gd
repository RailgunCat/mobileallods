extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Stat = Ids.Stat
## m.s() arena growth uses inclusive legacy bounds. The initial view is the
## original logical camera, so desktop zoom never changes encounter membership.


static func detected(game) -> Array[int]:
	var ids: Array[int] = []
	if game.mode != &"exploration":
		return ids
	for unit in game.units:
		if unit in game.party or not game.is_active(unit) or unit.dead or not unit.encounter_enabled:
			continue
		var sight: int = unit.stats[Stat.SIGHT]
		if unit.position_pixels.distance_squared_to(game.hero.position_pixels) < 256 * sight * sight:
			ids.append(unit.instance_id)
	return ids


static func needs_regroup(game, unit) -> bool:
	if unit == game.hero or unit not in game.party: return false
	var trail_span: float = float(game.definitions["exploration"]["history_length"]) * float(game.definitions["exploration"]["pixels_per_tick"]) * maxi(1, game.party.size() - 1) + 64.0
	var separation: Vector2 = (unit.position_pixels - game.hero.position_pixels).abs()
	return separation.x + separation.y > trail_span

static func build(game, triggered: Array[int], local_party: bool = false) -> Dictionary:
	var hero = game.hero
	var left: int = int((hero.position_pixels.x - 79) / 16.0)
	var top: int = int((hero.position_pixels.y - 95) / 16.0)
	var right: int = left + 10
	var bottom: int = top + 12
	var marked: Array[int] = triggered.duplicate()
	for unit in game.party:
		# Checked following can leave a companion behind an NPC or a maze wall.
		# Combat already places the whole party; use the encounter's local space
		# for these outliers rather than pulling remote enemy waves into battle.
		# The default remains the exact source calculation for reference audits.
		if local_party and needs_regroup(game, unit): continue
		var x: int = int(unit.position_pixels.x / 16.0)
		var y: int = int(unit.position_pixels.y / 16.0)
		left = mini(left, x - int(unit.footprint.x / 2.0) - 2)
		top = mini(top, y - int(unit.footprint.y / 2.0) - 2)
		right = maxi(right, x + int(unit.footprint.x / 2.0) + 2)
		bottom = maxi(bottom, y + int(unit.footprint.y / 2.0) + 2)
	var expanding: bool = true
	while expanding:
		expanding = false
		for unit in game.units:
			if unit in game.party or unit.instance_id not in marked or unit.dead or not game.is_active(unit):
				continue
			left = mini(left, unit.cell.x - 2)
			top = mini(top, unit.cell.y - 2)
			right = maxi(right, unit.cell.x + unit.footprint.x + 2)
			bottom = maxi(bottom, unit.cell.y + unit.footprint.y + 2)
		for unit in game.units:
			if unit in game.party or unit.instance_id in marked or unit.dead or not game.is_active(unit):
				continue
			if unit.cell.x + unit.footprint.x < left or unit.cell.x > right or unit.cell.y + unit.footprint.y < top or unit.cell.y > bottom:
				continue
			marked.append(unit.instance_id)
			expanding = true
	if left < 1:
		left = 1
		right = maxi(left + 11, right)
	if top < 1:
		top = 1
		bottom = maxi(top + 13, bottom)
	if right >= game.collision.width:
		right = game.collision.width - 1
		left = mini(right - 11, left)
	if bottom >= game.collision.height:
		bottom = game.collision.height - 1
		top = mini(bottom - 13, top)
	# The legacy campaign maps fit the minima. Tiny mod/test maps are clamped.
	left = maxi(0, left)
	top = maxi(0, top)
	right = mini(game.collision.width - 1, right)
	bottom = mini(game.collision.height - 1, bottom)
	var ids: Array[int] = []
	for unit in game.party:
		if not unit.dead: ids.append(unit.instance_id)
	for unit in game.units:
		if unit not in game.party and unit.instance_id in marked and not unit.dead and game.is_active(unit): ids.append(unit.instance_id)
	return {"arena": Rect2i(left, top, right - left + 1, bottom - top + 1), "unit_ids": ids}
