extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Stat = Ids.Stat
const Kind = Ids.ItemKind
const Session = preload("res://scripts/gameplay/game_session.gd")
const Inventory = preload("res://scripts/gameplay/inventory_rules.gd")
const Progression = preload("res://scripts/gameplay/progression_rules.gd")
const Stats = preload("res://scripts/gameplay/unit_stats.gd")
const Item = preload("res://scripts/gameplay/item_instance.gd")
const Rewards = preload("res://scripts/gameplay/battle_rewards.gd")
const Random = preload("res://scripts/gameplay/legacy_random.gd")


func run(checks, world: Dictionary, metadata: Dictionary, table: Dictionary, rewards: Dictionary) -> void:
	var game := Session.new()
	game.start(world, metadata, table, rewards)
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/legacy/economy_reference.json"))
	for sample: Dictionary in reference["items"]:
		var item := Item.new(50000, int(sample["definition_id"]))
		item.sockets.fill(int(sample["crystal"]))
		var spec: Dictionary = Inventory.definition(game, item.definition_id)
		checks.check(int(spec["kind"]) == int(sample["kind"]) and int(spec["hero_type"]) == int(sample["hero_type"]) and item.sockets.size() == int(sample["sockets"]) and Inventory.price(game, item) == int(sample["price"]), "Java item class, sockets and price: %d / %d" % [item.definition_id, sample["crystal"]])
	for sample: Dictionary in reference["equipment"]:
		var weapon := Item.new(50001, int(sample["weapon"]))
		var armor := Item.new(50002, int(sample["armor"]))
		weapon.sockets.fill(int(sample["crystal"]))
		armor.sockets.fill(int(sample["crystal"]))
		var previous := PackedInt32Array()
		previous.resize(Stat.COUNT)
		var actual: PackedInt32Array = Stats.calculate(PackedInt32Array(sample["base"]), table, weapon, armor, previous)
		checks.check(actual == PackedInt32Array(sample["stats"]), "Java equipped stats with crystal %d, weapon %d" % [sample["crystal"], sample["weapon"]])
	checks.check(game.inventory.size() == 2 and Inventory.owner(game, game.hero.weapon) == game.hero, "new-game inventory owns existing starting gear")
	game.hero.base_stats[Stat.EXPERIENCE] = 49
	var enemy = game.units[5]
	enemy.unit_type = Ids.UnitKind.SQUIRREL
	Rewards.award(game, [enemy], Random.new(20261026))
	checks.check(game.hero.base_stats[Stat.LEVEL] == 1 and game.hero.attribute_points == 5 and game.hero.skill_points == 1, "battle reward crosses level and grants original five plus one points")
	game.hero.stats[Stat.HP] = 5
	game.hero.stats[Stat.MANA] = 1
	var original: PackedInt32Array = game.hero.base_stats.duplicate()
	var draft: Dictionary = Progression.begin(game, game.hero)
	checks.check(Progression.adjust(draft, Stat.STRENGTH, 1) and Progression.adjust(draft, Stat.ATTACK, 1), "draft spends separate attribute and school budgets")
	checks.check(not Progression.adjust(draft, Stat.INTELLECT, -1) and not Progression.adjust(draft, Stat.DARK_FIRE_MAGIC, 1), "cannot refund original ranks or train an unavailable school")
	checks.check(game.hero.base_stats == original and game.hero.attribute_points == 5, "draft cancellation leaves character untouched")
	checks.check(Progression.commit(game, game.hero, draft) and game.hero.attribute_points == 4 and game.hero.skill_points == 0 and game.hero.stats[Stat.HP] == 5 and game.hero.stats[Stat.MANA] == 1, "confirmed training spends once without refilling HP or MP")
	checks.check(not Progression.commit(game, game.hero, draft), "stale training draft cannot spend twice")
	game.hero.skill_points = 1
	game.hero.base_stats[Stat.ATTACK] = 25
	checks.check(not Progression.adjust(Progression.begin(game, game.hero), Stat.ATTACK, 1), "school rank capped at source 25")
	var upgrade = Inventory.add(game, 13)
	var crystal = Inventory.add(game, 36)
	var second_crystal = Inventory.add(game, 36)
	checks.check(crystal.instance_id != second_crystal.instance_id, "same crystal definition creates distinct instances")
	var wrong_class = Inventory.add(game, 18)
	checks.check(not Inventory.equip(game, game.hero, wrong_class.instance_id) and Inventory.equip(game, game.hero, upgrade.instance_id), "equipment respects hero class")
	var before: PackedInt32Array = game.hero.stats.duplicate()
	checks.check(Inventory.insert(game, upgrade.instance_id, crystal.instance_id, 0) and game.hero.stats != before, "socket insertion updates equipped stats")
	checks.check(not Inventory.insert(game, upgrade.instance_id, crystal.instance_id, 1) and not Inventory.sell(game, crystal.instance_id), "mounted crystal cannot be duplicated or separately sold")
	checks.check(Inventory.insert(game, upgrade.instance_id, second_crystal.instance_id, 1), "two equal crystals can occupy two sockets as distinct instances")
	checks.check(Inventory.remove(game, upgrade.instance_id, 0) and not Inventory.mounted(game, crystal) and Inventory.find(game, crystal.instance_id) == crystal, "removal returns the same crystal identity")
	checks.check(not Inventory.remove(game, upgrade.instance_id, 0), "empty socket cannot produce another crystal")
	var gold: int = game.gold
	var sale: int = int(Inventory.price(game, upgrade) / 2.0)
	checks.check(Inventory.sell(game, upgrade.instance_id) and game.gold == gold + sale and game.hero.weapon == null and Inventory.find(game, second_crystal.instance_id) == null and Inventory.find(game, crystal.instance_id) == crystal, "sale unequips gear and consumes only its mounted crystals at half total price")
	checks.check(not Inventory.sell(game, upgrade.instance_id), "sold instance cannot be sold twice")
	game.gold = 0
	var size: int = game.inventory.size()
	var next_id: int = game.next_item_id
	checks.check(not Inventory.buy(game, 0) and game.inventory.size() == size and game.next_item_id == next_id, "failed purchase is atomic")
	game.gold = 100000
	checks.check(not Inventory.buy(game, 14) and Inventory.buy(game, 0) and game.gold == 100000 - int(Inventory.definition(game, 0)["price"]), "shop respects unlock progress and exact source price")
	game.flags["e"][10] = 1
	checks.check(Inventory.buy(game, 14), "campaign progress unlocks higher shop tier")
	game.mode = &"battle"
	checks.check(not Inventory.buy(game, 0) and not Inventory.sell(game, crystal.instance_id) and not Inventory.equip(game, game.hero, wrong_class.instance_id) and Progression.begin(game, game.hero).is_empty(), "management commands reject battle state")
	game.start(world, metadata, table, rewards)
	game.hero.set_pixel_position(Vector2(560, 80))
	var receipt: Dictionary = game.collect_nearby()
	checks.check(int(receipt.get("gold", 0)) == 200 and PackedInt32Array(receipt.get("items", [])) == PackedInt32Array([21, 39]) and game.gold == 200 and game.inventory.size() == 4, "original first-map pickup grants bow, crystal and 200 gold")
	checks.check(game.collect_nearby().is_empty() and game.pickups().is_empty() and game.gold == 200, "pickup flag prevents duplicate collection")
	var saved: Dictionary = game.snapshot()
	checks.check(saved["inventory"].size() == 4 and saved["flags"]["c"][0] == 1, "snapshot includes inventory identities and pickup state")
	game.reward_table = rewards.duplicate(true)
	for row: Dictionary in game.reward_table["rows"]:
		if int(row["row_id"]) == Ids.UnitKind.SQUIRREL:
			row["reward"]["drops"] = [{"definition_id": 14, "chance": -1}, {"definition_id": 36, "chance": 10000}]
	var result: Dictionary = Rewards.award(game, [game.units[5]], Random.new(73))
	checks.check(result["items"] == [14, 36] and game.inventory.size() == 6, "negative drop bypasses tier gate; guaranteed normal chance grants a separate inventory instance")
