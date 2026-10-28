extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const ItemKind = Ids.ItemKind
const Item = preload("res://scripts/gameplay/item_instance.gd")
const Stats = preload("res://scripts/gameplay/unit_stats.gd")
## One inventory owns gear and crystals, including mounted crystals. A socket
## stores its crystal identity alongside the legacy definition used by UnitStats.

static func definition(game, id: int) -> Dictionary:
	var items: Array = game.definitions["economy"]["items"]
	return items[id] if id >= 0 and id < items.size() else {}


static func find(game, id: int):
	for item in game.inventory:
		if item.instance_id == id: return item
	return null


static func add(game, definition_id: int):
	if definition(game, definition_id).is_empty(): return null
	var item := Item.new(game.next_item_id, definition_id)
	game.next_item_id += 1
	game.inventory.append(item)
	return item


static func sync_party(game) -> void:
	for actor in game.units:
		for item in [actor.weapon, actor.armor]:
			if item == null: continue
			if actor in game.party:
				if item not in game.inventory: game.inventory.append(item)
			elif item in game.inventory:
				for id in item.socket_instance_ids:
					var crystal = find(game, id)
					if crystal != null: game.inventory.erase(crystal)
				game.inventory.erase(item)


static func owner(game, item):
	for actor in game.party:
		if item != null and item in [actor.weapon, actor.armor]: return actor
	return null


static func mounted(game, crystal) -> bool:
	for item in game.inventory:
		if crystal.instance_id in item.socket_instance_ids: return true
	return false


## Inventory order is preserved; each screen owns its display sorting.
static func available(game, actor = null, kind: int = -1) -> Array:
	var result: Array = []
	for item in game.inventory:
		var spec: Dictionary = definition(game, item.definition_id)
		if mounted(game, item): continue
		if kind >= 0 and int(spec["kind"]) != kind: continue
		if actor != null and int(spec["kind"]) != ItemKind.CRYSTAL and int(spec["hero_type"]) != actor.unit_type: continue
		result.append(item)
	return result


## Calculate an equipment preview without mutating items, stats or resources.
static func preview_stats(game, actor, item, removing: bool = false) -> PackedInt32Array:
	var kind: int = int(definition(game, item.definition_id)["kind"])
	var replacement = null if removing else item
	return Stats.calculate(actor.base_stats, game.ability_table, replacement if kind == ItemKind.WEAPON else actor.weapon, replacement if kind == ItemKind.ARMOR else actor.armor, actor.stats)


static func can_manage(game) -> bool:
	return game.mode in [&"exploration", &"management"]


static func equip(game, actor, item_id: int) -> bool:
	var item = find(game, item_id)
	if not can_manage(game) or actor not in game.party or item == null: return false
	var spec: Dictionary = definition(game, item.definition_id)
	if spec["hero_type"] != actor.unit_type or spec["kind"] == ItemKind.CRYSTAL: return false
	var other = owner(game, item)
	if other != null and other != actor: return false
	if int(spec["kind"]) == ItemKind.WEAPON: actor.weapon = item
	else: actor.armor = item
	actor.recalculate(game.ability_table)
	game.changed.emit()
	return true


static func unequip(game, actor, kind: int) -> bool:
	if not can_manage(game) or actor not in game.party or kind not in [ItemKind.WEAPON, ItemKind.ARMOR]: return false
	if kind == ItemKind.WEAPON: actor.weapon = null
	else: actor.armor = null
	actor.recalculate(game.ability_table)
	game.changed.emit()
	return true


static func insert(game, item_id: int, crystal_id: int, slot: int) -> bool:
	var item = find(game, item_id)
	var crystal = find(game, crystal_id)
	if not can_manage(game) or item == null or crystal == null or slot < 0 or slot >= item.sockets.size(): return false
	if item.sockets[slot] != -1 or mounted(game, crystal) or definition(game, crystal.definition_id)["kind"] != ItemKind.CRYSTAL: return false
	item.sockets[slot] = crystal.definition_id
	item.socket_instance_ids[slot] = crystal.instance_id
	var actor = owner(game, item)
	if actor != null: actor.recalculate(game.ability_table)
	game.changed.emit()
	return true


static func remove(game, item_id: int, slot: int) -> bool:
	var item = find(game, item_id)
	if not can_manage(game) or item == null or slot < 0 or slot >= item.sockets.size() or item.sockets[slot] < 0: return false
	item.sockets[slot] = -1
	item.socket_instance_ids[slot] = -1
	var actor = owner(game, item)
	if actor != null: actor.recalculate(game.ability_table)
	game.changed.emit()
	return true


static func progress(game) -> int:
	var result: int = 0
	for i in range(1, game.flags["e"].size()):
		if int(game.flags["e"][i]) != 0: result = i
	return result


static func stock(game) -> Array[int]:
	var result: Array[int] = []
	for spec: Dictionary in game.definitions["economy"]["items"]:
		if int(spec["unlock_progress"]) <= progress(game): result.append(int(spec["definition_id"]))
	return result


static func price(game, item) -> int:
	var result: int = int(definition(game, item.definition_id)["price"])
	for crystal in item.sockets:
		if crystal >= 0: result += int(definition(game, crystal)["price"])
	return result


static func buy(game, definition_id: int) -> bool:
	var spec: Dictionary = definition(game, definition_id)
	if not can_manage(game) or spec.is_empty() or definition_id not in stock(game) or game.gold < int(spec["price"]): return false
	game.gold -= int(spec["price"])
	add(game, definition_id)
	game.changed.emit()
	return true


static func sell(game, item_id: int) -> bool:
	var item = find(game, item_id)
	if not can_manage(game) or item == null or mounted(game, item): return false
	game.gold += int(price(game, item) / 2.0)
	var actor = owner(game, item)
	if actor != null:
		if actor.weapon == item: actor.weapon = null
		if actor.armor == item: actor.armor = null
	for id in item.socket_instance_ids:
		var crystal = find(game, id)
		if crystal != null: game.inventory.erase(crystal)
	game.inventory.erase(item)
	if actor != null: actor.recalculate(game.ability_table)
	game.changed.emit()
	return true
