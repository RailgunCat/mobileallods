extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Stat = Ids.Stat
## Goldens come from independently compiled recovered Java methods, not from
## these GDScript implementations. Tiny maps test rules and edge cases.

const Collision = preload("res://scripts/gameplay/map_collision.gd")
const Pathfinder = preload("res://scripts/gameplay/grid_pathfinder.gd")
const Unit = preload("res://scripts/gameplay/unit_state.gd")
const Stats = preload("res://scripts/gameplay/unit_stats.gd")
const Session = preload("res://scripts/gameplay/game_session.gd")
var failures: int = 0
var count: int = 0


func check(condition: bool, message: String) -> void:
	count += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _empty(width: int, height: int) -> Dictionary:
	var rows: Array = []
	for y in range(height):
		var row: Array = []
		row.resize(width)
		row.fill(0)
		rows.append(row)
	return {"name": "test", "width": width, "height": height, "source_tile_ids": rows}


func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func run(world: Dictionary, metadata: Dictionary, table: Dictionary) -> void:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/legacy/gameplay_reference.json"))
	var images: Array = world["constants"]["tile_image_ids"]
	for map: Dictionary in world["maps"]:
		var grid := Collision.new()
		grid.configure(map, images, metadata)
		var expected: Dictionary = reference["maps"][str(map["name"])]
		check(_hash(grid.terrain) == expected["sha256"], "Java collision grid on map " + str(map["name"]))
	for type in range(4):
		var unit := Unit.new()
		unit.configure({"instance_id": 7, "unit_type": type, "story_group": 100, "spawn_flag": 3, "side_id": 0}, metadata, table)
		check(unit.stats == PackedInt32Array(reference["starting_stats"][str(type)]), "57 Java stat slots + equipment for type %d" % type)
		check(unit.base_stats.size() == 57 and unit.base_stats[Stat.RESERVED] == 0, "implicit final slot is padded")
		check(unit.weapon.sockets.size() == 1 and unit.weapon.sockets[0] == -1, "starting sockets empty")
		check(unit.instance_id == 7 and unit.story_group == 100 and unit.spawn_flag == 3, "identity namespaces distinct")
		var previous := unit.stats.duplicate()
		previous[0] = 1
		previous[1] = 2
		previous[2] -= 1
		var changed := Stats.calculate(unit.base_stats, table, unit.weapon, null, previous)
		check(changed[0] == 1 and changed[1] == 2 and changed[2] == previous[2], "equipment recalculation preserves resources")
		check(changed[21] < unit.stats[Stat.PHYSICAL_RESISTANCE], "removing armor changes physical resistance")
		var upgraded := unit.base_stats.duplicate()
		upgraded[12] += 30
		changed = Stats.calculate(upgraded, table, unit.weapon, unit.armor, previous)
		check(changed[16] == unit.stats[Stat.MAX_ACTION_POINTS] + 2 and changed[2] == previous[2] + 2, "AP recalculation retains already spent points")
	var prototype := Session.new()
	check(prototype.start(world, metadata, table), "new game starts")
	check(prototype.hero.position_pixels == Vector2(544, 384) and prototype.hero.cell == Vector2i(33, 23), "m.T entry + n.i coordinate conversion")
	check(prototype.quests.size() == 24 and prototype.triggers.size() == 169 and prototype.spawn_states.size() == 50, "new game flag sizes")
	check(prototype.quests[Ids.Quest.WOLVES] == 1 and prototype.triggers[73] == 2 and prototype.spawn_states[1] == 0, "new game flag values")
	check(not prototype.step(prototype.hero.cell + Vector2i(1, 1)), "diagonal movement rejected")
	var hero_cell: Vector2i = prototype.hero.cell
	check(not prototype.step(Vector2i(-1, -1)) and prototype.hero.cell == hero_cell, "invalid command cannot mutate state")
	var visited: int = 0
	for y in range(prototype.collision.height):
		for x in range(prototype.collision.width):
			var target := Vector2i(x, y)
			var result: Dictionary = prototype.pathfinder.route(target)
			var last := hero_cell
			for step: Vector2i in result["path"]:
				if not prototype.collision.can_stand(step, Vector2i.ONE, prototype.hero.instance_id) or (step - last).length_squared() != 1:
					check(false, "real-map route entered obstacle / jumped")
					return
				last = step
			if result["reachable"]:
				visited += 1
				if last != target or result["path"].size() != prototype.pathfinder.distance(target):
					check(false, "real-map route length or endpoint inconsistent")
					return
	check(visited > 200, "all first-map destinations checked, %d reachable" % visited)
	_small_maps(images, metadata)


func _small_maps(images: Array, metadata: Dictionary) -> void:
	var map := _empty(9, 7)
	# A wall with one 1-cell opening: 1x1 can pass, 2x2 and 3x3 cannot.
	for y in range(7):
		if y != 3:
			map["source_tile_ids"][y][4] = 42
	var grid := Collision.new()
	grid.configure(map, images, metadata)
	var finder := Pathfinder.new()
	finder.build(grid, Vector2i(1, 3))
	check(finder.route(Vector2i(7, 3))["reachable"], "1x1 fits a one-cell gap")
	for extent in [Vector2i(2, 2), Vector2i(3, 3)]:
		finder.build(grid, Vector2i(1, 2), extent)
		check(not finder.route(Vector2i(6, 2))["reachable"], "%s cannot fit a one-cell gap" % extent)
		check(not grid.can_stand(Vector2i(8, 6), extent), "footprint must stay inside map")
	check(images[42] == images[0] and grid.is_terrain_blocked(Vector2i(4, 2)), "raw source 42 blocks grass-looking cell")
	check(grid.place(11, Vector2i(1, 1), Vector2i(2, 2)), "place 2x2 occupant")
	check(not grid.place(12, Vector2i(2, 2)), "overlapping unit rejected")
	check(grid.can_stand(Vector2i(1, 1), Vector2i(2, 2), 11), "pathfinder can ignore its own actor")
	check(not grid.place(11, Vector2i(4, 0)) and grid.occupants.get(Vector2i(1, 1)) == 11, "failed placement retains old footprint")
	grid.terrain[1 * grid.width + 1] = 1
	grid.remove(11)
	check(grid.occupants.is_empty() and grid.is_terrain_blocked(Vector2i(1, 1)), "removing actor preserves terrain layer")
	grid.configure(_empty(3, 3), images, metadata)
	grid.occupy(11, Vector2i.ONE)
	grid.occupy(12, Vector2i.ONE)
	grid.remove(12)
	check(grid.occupants.get(Vector2i.ONE) == 11 and grid.units.has(11), "overlapping party occupancy survives removal of one member")
	check(not grid.place(13, Vector2i.ONE), "combat footprint placement still rejects overlap")
	grid.remove(11)
	finder.build(grid, Vector2i.ZERO)
	check(finder.route(Vector2i(1, 1))["path"] == [Vector2i(1, 0), Vector2i(1, 1)], "legacy reverse tie order")
	check(finder.route(Vector2i.ZERO)["path"].is_empty() and finder.route(Vector2i.ZERO)["reachable"], "zero-length route")
	check(finder.route(Vector2i(-1, 0))["path"].is_empty(), "outside destination rejected")
	grid.terrain[1] = 1
	finder.build(grid, Vector2i.ZERO)
	var detour: Dictionary = finder.route(Vector2i(2, 0))
	check(detour["reachable"] and detour["path"].size() == 4, "route detours around obstruction")
	check(not finder.route(Vector2i(1, 0))["reachable"] and finder.route(Vector2i(1, 0))["resolved"] == Vector2i.ZERO, "blocked target resolves to reachable approach")
	grid.terrain.fill(1)
	grid.terrain[0] = 0
	finder.build(grid, Vector2i.ZERO)
	var isolated: Dictionary = finder.route(Vector2i(2, 2))
	check(not isolated["reachable"] and isolated["path"].is_empty(), "isolated actor never traverses blocked cells")
	# Water comes from a 2x2 anchor mask, not the currently animated PNG.
	map = _empty(4, 4)
	map["source_tile_ids"][1][1] = PackedInt32Array(images).find(36)
	grid.configure(map, images, metadata)
	check(grid.is_terrain_blocked(Vector2i(1, 1)) and grid.is_terrain_blocked(Vector2i(2, 2)) and not grid.is_terrain_blocked(Vector2i(3, 2)), "water anchor covers exactly 2x2")
	for type in range(18):
		var expected: int = 1 if type in [0, 1, 2, 3, 5, 16] else (3 if type in [4, 17] else 2)
		var extent: Array = metadata["unit_footprints"][type]
		check(Vector2i(int(extent[0]), int(extent[1])) == Vector2i(expected, expected), "constructor footprint type %d" % type)
