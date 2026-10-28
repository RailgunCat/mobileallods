extends RefCounted
const Dungeon = preload("res://scripts/gameplay/dungeon_generator.gd")
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Session = preload("res://scripts/gameplay/game_session.gd")
const Inventory = preload("res://scripts/gameplay/inventory_rules.gd")
const Campaign = preload("res://scripts/gameplay/campaign_runner.gd")
const Tavern = preload("res://scripts/gameplay/tavern_rules.gd")


func equal_rows(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size(): return false
	for i in range(actual.size()):
		if PackedInt32Array(actual[i]) != PackedInt32Array(expected[i]): return false
	return true


func generation(checks, metadata: Dictionary) -> void:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/legacy/travel_reference.json"))
	for sample: Dictionary in reference["dungeons"]:
		var generator := Dungeon.new()
		var output: Dictionary = generator.generate(int(sample["map_id"]), 0, int(sample["seed"]), metadata, metadata["new_game"]["flags"]["c"])
		var label: String = "map %d seed %d" % [sample["map_id"], sample["seed"]]
		checks.check(not output.is_empty(), "dungeon generated: " + label)
		if output.is_empty(): continue
		checks.check(equal_rows(output["map"]["source_tile_ids"], sample["tiles"]), "Java dungeon tiles: " + label)
		checks.check(equal_rows(output["map"]["collision_rows"], sample["collision"]), "Java dungeon collision: " + label)
		var scripts: Array = sample["scripts"].filter(func(row: Array): return not row.is_empty())
		checks.check(equal_rows(output["scene"]["scripts"], scripts) and equal_rows(output["scene"]["triggers"], sample["triggers"]), "Java dungeon exits/scripts: " + label)
		var positions: Array = []
		for spawn: Array in output["scene"]["units"]: positions.append([spawn[1], spawn[2], spawn[3]])
		checks.check(equal_rows(positions, sample["units"]), "Java dungeon population placement: " + label)
		var pickups: Array = []
		for pickup: Dictionary in output["scene"]["pickups"]:
			var record: Array = [pickup["pickup_id"], pickup["position_pixels"][0], pickup["position_pixels"][1], pickup["script_id"]]
			record.append_array(pickup["items"])
			if int(pickup["gold"]) != 0: record.append(-int(pickup["gold"]))
			pickups.append(record)
		checks.check(equal_rows(pickups, sample["pickups"]), "Java dungeon pickup positions: " + label)
		var e: Array = output["entry"]["position_pixels"]
		checks.check(int(e[0]) == int(sample["entry"][0]) * 16 and int(e[1]) == int(sample["entry"][1]) * 16 and output["entry"]["facing"] == int(sample["entry"][2]), "Java dungeon entrance: " + label)
		checks.check(generator.rng.next_signed() == int(sample["next_int"]), "Java complete dungeon RNG stream: " + label)


func travel(checks, world: Dictionary, metadata: Dictionary, table: Dictionary, rewards: Dictionary, data: Dictionary) -> void:
	var game := Session.new()
	game.start(world, metadata, table, rewards)
	game.add_demo_companion()
	Inventory.sync_party(game)
	var hero = game.hero
	var ally = game.party[1]
	var weapon = hero.weapon
	var crystal = Inventory.add(game, 39)
	Inventory.insert(game, weapon.instance_id, crystal.instance_id, 0)
	hero.attribute_points = 3
	hero.skill_points = 2
	game.gold = 731
	game.quests[Ids.Quest.LETTER] = Ids.QuestState.COMPLETED
	game.dungeon_seeds[0] = 20261027
	var items: int = game.inventory.size()
	checks.check(game.travel(-1, 0), "first dungeon loads from source destination")
	checks.check(game.hero == hero and game.party[1] == ally and hero.weapon == weapon and game.inventory.size() == items and weapon.socket_instance_ids[0] == crystal.instance_id and game.gold == 731 and hero.attribute_points == 3 and hero.skill_points == 2, "travel retains party objects, item identity, sockets, gold and progression")
	checks.check(game.location_id == -1 and int(game.quests[Ids.Quest.LETTER]) == Ids.QuestState.COMPLETED and game.dungeon_seeds[0] == 20261027, "travel retains global quest flags and dungeon seed")
	var tiles: Array = game.map["source_tile_ids"].duplicate(true)
	var vm := Campaign.new()
	vm.configure(game, world, data)
	var destinations: Array = []
	vm.travel_requested.connect(func(map_id: int, entry_id: int): destinations.append([map_id, entry_id]))
	checks.check(vm.start_script(301), "generated forward exit is executable")
	vm.advance(0.062)
	checks.check(destinations == [[1, 2]], "first dungeon forward exit leads to second overworld map entry two")
	checks.check(game.travel(1, 2) and game.location_id == 1 and str(game.map["name"]) == "2", "second map loads original entry")
	checks.check(hero.position_pixels == Vector2(528, 448) and game.party[1] == ally, "second map uses U() entry and keeps companion")
	for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
		game.travel(1, 2)
		var motor = preload("res://scripts/gameplay/exploration_controller.gd").new()
		motor.configure(game)
		motor.set_direction(direction)
		for tick in range(40): motor.advance(0.062)
		checks.check(ally.position_pixels.distance_to(Vector2(528, 448)) >= 40 and hero.position_pixels.distance_to(ally.position_pixels) <= 40, "companion follows from second-map dungeon entry toward %s" % direction)
	checks.check(game.travel(-1, 1) and equal_rows(game.map["source_tile_ids"], tiles), "return to dungeon reconstructs identical geometry from retained seed")
	vm.configure(game, world, data)
	destinations.clear()
	vm.start_script(300)
	vm.advance(0.062)
	checks.check(destinations == [[0, 1]], "first dungeon back exit returns to map one entry one")
	checks.check(game.travel(0, 1) and hero.position_pixels == Vector2(352, 80) and game.gold == 731, "return to first map preserves wealth and exact original entry")
	var previous: Dictionary = game.map
	var position: Vector2 = hero.position_pixels
	checks.check(not game.travel(100, 0) and game.map == previous and hero.position_pixels == position and not game.travel_error.is_empty(), "unresolved special-map entry rejects atomically")
	for map_id in range(12):
		for entrance: Dictionary in metadata["travel"]["entries"][map_id]:
			checks.check(game.travel(map_id, int(entrance["entry"])), "campaign map %d entry %d loads safely: %s" % [map_id, entrance["entry"], game.travel_error])
	for dungeon in range(12):
		game.dungeon_seeds[dungeon] = 987654321
		checks.check(game.travel(-dungeon - 1, 0), "campaign dungeon %d loads safely: %s" % [dungeon + 1, game.travel_error])
	game.quests[Ids.Quest.CITY_CERTIFICATE] = Ids.QuestState.COMPLETED
	game.mode = &"town"
	var offer: Dictionary = Tavern.take_quest(game)
	checks.check(int(offer.get("dialogue_id", -1)) == 82 and int(game.quests[15]) == Ids.QuestState.ACTIVE and int(game.flags["e"][3]) == 1 and int(game.triggers[159]) == Ids.TriggerState.DISABLED, "tavern grants source opening job and unlocks its map")
	checks.check(Tavern.take_quest(game).is_empty(), "locked later jobs cannot be granted twice or early")
	game.triggers[165] = Ids.TriggerState.ENABLED
	var count: int = game.inventory.size()
	checks.check(int(Tavern.take_quest(game).get("gift", -1)) == 29 and game.inventory.size() == count + 1 and int(game.flags["e"][9]) == 1, "source tavern job can grant its original equipment reward")
	var last: String = ""
	var unique: bool = true
	for i in range(30):
		var next: String = Tavern.rumour(game)
		if next.is_empty() or next == last: unique = false
		last = next
	checks.check(unique, "tavern uses original rumour pool without immediate repeats")
