extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Inventory = preload("res://scripts/gameplay/inventory_rules.gd")


static func rumour(game) -> String:
	if game.mode != &"town" or not game.world_travel_unlocked(): return ""
	var texts: Array = game.definitions["travel"]["rumours"]
	var local: int = (Inventory.progress(game) - 1) * 2
	var selected: int = game.last_rumour
	while selected == game.last_rumour:
		selected = local + game.world_rng.bounded(2) if game.world_rng.bounded(10) < 3 else game.world_rng.bounded(14) + 24
	game.last_rumour = selected
	return str(texts[selected])


static func take_quest(game) -> Dictionary:
	if game.mode != &"town" or not game.world_travel_unlocked(): return {}
	for offer: Dictionary in game.definitions["travel"]["tavern_offers"]:
		var flag: int = int(offer["trigger"])
		if int(game.triggers[flag]) != Ids.TriggerState.ENABLED: continue
		game.triggers[flag] = Ids.TriggerState.DISABLED
		game.quests[int(offer["quest"])] = Ids.QuestState.ACTIVE
		game.flags["e"][int(offer["unlock"])] = 1
		if int(offer["gift"]) >= 0: Inventory.add(game, int(offer["gift"]))
		game.changed.emit()
		return offer.duplicate(true)
	return {}
