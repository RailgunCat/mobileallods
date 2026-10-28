extends RefCounted
const Session = preload("res://scripts/gameplay/game_session.gd")
const Story = preload("res://scripts/gameplay/campaign_runner.gd")
const Exploration = preload("res://scripts/gameplay/exploration_controller.gd")
const Saves = preload("res://scripts/gameplay/save_service.gd")
const Inventory = preload("res://scripts/gameplay/inventory_rules.gd")

func _same(a, b) -> bool:
	# JSON decodes integers as floats; compare values after the same conversion.
	return JSON.parse_string(JSON.stringify(a, "", true, true)) == JSON.parse_string(JSON.stringify(b, "", true, true))

func run(checks, world: Dictionary, metadata: Dictionary, table: Dictionary, rewards: Dictionary, data: Dictionary) -> void:
	var game := Session.new()
	game.start(world, metadata, table, rewards)
	for actor in game.units:
		if actor.unit_type == 1:
			game.party.append(actor)
			actor.side_id = 0
			game.spawn_states[actor.spawn_flag] = 2
			break
	Inventory.sync_party(game)
	game.demo_party = false
	var story := Story.new()
	var exploration := Exploration.new()
	story.configure(game, world, data)
	exploration.configure(game)
	var saves := Saves.new()
	saves.directory = "user://stage8-test-%d" % Time.get_ticks_usec()
	game.gold = 1234
	game.hero.attribute_points = 8
	game.hero.skill_points = 2
	game.hero.stats[0] -= 3
	var crystal = Inventory.add(game, 36)
	checks.check(Inventory.insert(game, game.hero.weapon.instance_id, crystal.instance_id, 0), "save fixture mounts a uniquely identified crystal")
	story.pending.append(8)
	game.commands.append({"command": "diagnostic_history_is_not_save_data"})
	var state: Dictionary = saves.capture(game, story, exploration)
	checks.check(not state["world"].has("commands") and not state["world"].has("format"), "save omits unbounded diagnostic history and debug format")
	checks.check(saves.save_slot(0, game, story, exploration), "native save writes a slot")
	var loaded: Dictionary = saves.read_slot(0, world, metadata, table, rewards)
	checks.check(not loaded.is_empty(), "native save loads a detached validated session: " + saves.error)
	if not loaded.is_empty():
		var restored = loaded["session"]
		checks.check(restored.gold == 1234 and restored.hero.stats == game.hero.stats and restored.hero.base_stats == game.hero.base_stats and restored.hero.attribute_points == 8 and restored.hero.skill_points == 2, "save preserves health, growth and money")
		checks.check(restored.party.size() == 2 and restored.hero == restored.party[0] and restored.hero in restored.units and restored.hero.weapon == Inventory.find(restored, game.hero.weapon.instance_id), "loaded party and equipment share canonical object identities")
		checks.check(restored.hero.weapon.socket_instance_ids[0] == crystal.instance_id and Inventory.mounted(restored, Inventory.find(restored, crystal.instance_id)), "mounted crystal identity survives load")
		checks.check(_same(restored.flags, game.flags) and restored.world_rng.snapshot() == game.world_rng.snapshot() and _same(loaded["pending"], [8]), "flags, RNG and pending death hooks survive load")
		var movement := Exploration.new()
		movement.configure(restored)
		movement.restore_trails(loaded["exploration"])
		checks.check(movement.snapshot() == exploration.snapshot(), "save restores follower history and simulation clock")
	checks.check(saves.save_slot(0, game, story, exploration) and FileAccess.file_exists(saves.path(0) + ".bak"), "overwriting a slot retains the previous completed save")
	DirAccess.remove_absolute(saves.path(0))
	checks.check(saves.exists(0) and not saves.read_slot(0, world, metadata, table, rewards).is_empty(), "backup loads if an interrupted replacement left no primary file")
	checks.check(saves.save_slot(0, game, story, exploration), "slot can be saved again after backup recovery")
	var checksum_file := FileAccess.open(saves.path(0), FileAccess.READ)
	var document: Dictionary = JSON.parse_string(checksum_file.get_as_text())
	checksum_file.close()
	document["payload"] += " "
	checksum_file = FileAccess.open(saves.path(0), FileAccess.WRITE)
	checksum_file.store_string(JSON.stringify(document))
	checksum_file.close()
	checks.check(saves.read_slot(0, world, metadata, table, rewards).is_empty(), "checksum rejects a changed payload before restore")
	saves.save_slot(0, game, story, exploration)
	for mode in [&"battle", &"battle_intro", &"victory", &"defeat", &"dialogue", &"script", &"travel"]:
		game.mode = mode
		checks.check(not saves.save_slot(0, game, story, exploration), "save prohibited in " + str(mode))
	game.mode = &"exploration"
	checks.check(saves.read_slot(0, world, metadata, table, rewards).size() > 0, "rejected writes preserve the previous slot")
	var broken: Dictionary = state.duplicate(true)
	broken["world"]["party_ids"] = [999999]
	checks.check(saves.restore(broken, world, metadata, table, rewards).is_empty(), "unknown party ID rejects entire save")
	for key in ["flags", "inventory", "units", "world_rng", "gate_choices", "pending_scripts", "party_ids"]:
		broken = state.duplicate(true)
		broken["world"][key] = 42
		checks.check(saves.restore(broken, world, metadata, table, rewards).is_empty(), "malformed " + key + " is rejected")
	broken = state.duplicate(true)
	broken["world"]["location_id"] = -999
	checks.check(saves.restore(broken, world, metadata, table, rewards).is_empty(), "invalid location is rejected before indexing seeds")
	var file := FileAccess.open(saves.path(0), FileAccess.WRITE)
	file.store_string("{truncated")
	file.close()
	checks.check(saves.read_slot(0, world, metadata, table, rewards).is_empty() and game.gold == 1234, "truncated save leaves live state untouched")
	file = FileAccess.open(saves.path(0), FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": "allods-godot-save", "version": 999}))
	file.close()
	checks.check(saves.read_slot(0, world, metadata, table, rewards).is_empty() and saves.error.contains("Версия"), "future save version is rejected explicitly")
	for location in range(-12, 12):
		game.dungeon_seeds.fill(20261027)
		checks.check(game.travel(location, 0), "save fixture reaches location %d" % location)
		story.configure(game, world, data)
		exploration.configure(game)
		state = saves.capture(game, story, exploration)
		loaded = saves.restore(JSON.parse_string(JSON.stringify(state, "", true, true)), world, metadata, table, rewards)
		checks.check(not loaded.is_empty(), "save roundtrip location %d: %s" % [location, saves.error])
		if loaded.is_empty(): continue
		var restored = loaded["session"]
		checks.check(restored.map == game.map and _same(restored.current_scene["triggers"], game.current_scene["triggers"]) and _same(restored.dungeon_seeds, game.dungeon_seeds) and _same(restored.gate_choices, game.gate_choices) and restored.world_rng.snapshot() == game.world_rng.snapshot(), "location %d preserves geometry, dynamic triggers and RNG" % location)
		for i in range(game.units.size()):
			checks.check(restored.units[i].snapshot() == game.units[i].snapshot(), "location %d unit %d restores exact simulation state" % [location, i])
	for slot in range(saves.TOTAL_SLOT_COUNT):
		for suffix in ["", ".tmp", ".bak"]:
			if FileAccess.file_exists(saves.path(slot) + suffix): DirAccess.remove_absolute(saves.path(slot) + suffix)
	DirAccess.remove_absolute(saves.directory)


func run_ui(root, checks) -> void:
	var directory: String = root.saves.directory
	root.saves.directory = "user://stage8-title-%d" % Time.get_ticks_usec()
	root._restart(false)
	root.campaign.enabled = true
	root.session.gold = 321
	checks.check(root.saves.save_slot(0, root.session, root.campaign, root.exploration), "title-load fixture writes real campaign")
	root._has_started = false
	root._restart(true, false)
	root._show_main_menu(true)
	checks.check(root.campaign.busy(), "fresh title has a suspended opening script")
	root.main_menu.selected = 2
	root.main_menu.confirm()
	checks.check(root.save_slots.visible and not root.main_menu.visible, "Load from fresh title opens slots despite suspended opening script")
	root.save_slots.confirm()
	checks.check(root.session.gold == 321 and root._has_started and not root.save_slots.visible and not root.main_menu.visible, "fresh title loads saved game and clears stale title UI")
	var original_hero = root.session.hero
	root._show_game_menu()
	root.game_menu.selected = 5
	root.game_menu.confirm()
	root.save_slots.selected = 4
	root.save_slots.confirm()
	checks.check(root.save_slots.visible and root.session.hero == original_hero and root.session.gold == 321 and not root.save_slots.message.is_empty(), "empty slot leaves live session and load picker intact")
	root.save_slots.back()
	checks.check(root.game_menu.visible, "cancel load returns to game menu")
	root.game_menu.back()
	# Reproduce the last battle through the real gameplay/result/dialogue UI.
	root._restart(false)
	root.session.add_demo_companion()
	root.campaign.enabled = true
	root.session.tutorial_seen[2] = 1
	root.session.dungeon_seeds[11] = 20261027
	root._travel(-12, 0)
	root.campaign.configure(root.session, root.world, root.campaign_data, true)
	root.session.mode = &"exploration"
	var dragon
	for actor in root.session.units:
		if actor.unit_type == 7: dragon = actor
	checks.check(dragon != null and root.session.party.size() == 2, "ending UI fixture has dragon and Li")
	if dragon != null:
		var dragon_ids: Array[int] = [dragon.instance_id]
		root._begin_battle(dragon_ids)
		root._finish_battle_intro()
		dragon.dead = true
		dragon.stats[0] = 0
		root.battle._check_outcome()
		root._refresh()
		checks.check(root.dialogue_layer.visible and root.campaign.modal.get("kind") == "ending" and not root.battle.active and root.battle_overlay.phase == &"", "dragon outcome shows original ending pages without ordinary victory overlay")
		for page in range(20):
			if root.campaign.modal.is_empty(): break
			root.campaign.acknowledge()
		root._process(0.062)
		checks.check(root.main_menu.visible and not root._has_started and root.session.campaign_completed, "acknowledging final pages returns to title without reviving Li")
	for slot in range(root.saves.TOTAL_SLOT_COUNT):
		for suffix in ["", ".tmp", ".bak"]:
			if FileAccess.file_exists(root.saves.path(slot) + suffix): DirAccess.remove_absolute(root.saves.path(slot) + suffix)
	DirAccess.remove_absolute(root.saves.directory)
	root.saves.directory = directory
	root._restart(false)

func run_autosave_ui(root, checks) -> void:
	var original_directory: String = root.saves.directory
	root.saves.directory = "user://autosave-test-%d" % Time.get_ticks_usec()
	var auto: int = root.saves.AUTOSAVE_SLOT
	root._restart(false)
	root.campaign.enabled = true
	root.session.gold = 700
	checks.check(root.saves.save_slot(0, root.session, root.campaign, root.exploration), "autosave fixture retains a separate manual slot")
	root._show_main_menu(true)
	root.main_menu.selected = 0
	root.main_menu.confirm()
	var loaded: Dictionary = root.saves.read_slot(auto, root.world, root.metadata, root.table, root.rewards)
	checks.check(not loaded.is_empty() and loaded["session"].location_id == 0 and loaded["session"].gold == 0 and root.campaign.busy(), "New Game autosaves map one before its entrance story")
	var previous: String = FileAccess.get_file_as_string(root.saves.path(auto))
	root._restart(true, false)
	root._show_main_menu(true)
	checks.check(FileAccess.get_file_as_string(root.saves.path(auto)) == previous and not FileAccess.file_exists(root.saves.path(auto) + ".bak"), "title initialization preserves the existing autosave")
	root.main_menu.selected = 2
	root.main_menu.confirm()
	checks.check(root.save_slots.slot_count() == 6 and root.save_slots.regions.size() == 8 and root.save_slots.slot_label(auto) == "Автосохранение", "load picker exposes five manual slots and the named autosave")
	root.save_slots.navigate(-1)
	checks.check(root.save_slots.selected == auto, "keyboard navigation reaches the autosave")
	root.save_slots.confirm()
	checks.check(root.session.location_id == 0 and root.session.gold == 0 and not root.save_slots.visible and FileAccess.get_file_as_string(root.saves.path(auto)) == previous, "title loads autosave without overwriting it")
	root.session.gold = 123
	root.session.dungeon_seeds[0] = 20261027
	root._travel(-1, 0)
	loaded = root.saves.read_slot(auto, root.world, root.metadata, root.table, root.rewards)
	checks.check(not loaded.is_empty() and loaded["session"].location_id == -1 and loaded["session"].entry_id == 0 and loaded["session"].gold == 123, "dungeon entrance automatically replaces the autosave")
	if not loaded.is_empty():
		checks.check(loaded["session"].map == root.session.map and _same(loaded["session"].dungeon_seeds, root.session.dungeon_seeds) and loaded["session"].hero.position_pixels == root.session.hero.position_pixels, "dungeon autosave preserves generated geometry, seed and entry position")
	var manual: Dictionary = root.saves.read_slot(0, root.world, root.metadata, root.table, root.rewards)
	checks.check(not manual.is_empty() and manual["session"].gold == 700, "automatic saving preserves manual slots")
	previous = FileAccess.get_file_as_string(root.saves.path(auto))
	root._travel(99, 0)
	checks.check(FileAccess.get_file_as_string(root.saves.path(auto)) == previous, "failed travel preserves the autosave")
	root._show_game_menu()
	root.game_menu.selected = 4
	root.game_menu.confirm()
	checks.check(root.save_slots.saving and root.save_slots.slot_count() == 5 and root.save_slots.regions.size() == 7, "manual save picker excludes the autosave")
	root.save_slots.navigate(-1)
	checks.check(root.save_slots.selected == 4, "manual save navigation wraps within five slots")
	root._save_slot_selected(auto)
	checks.check(FileAccess.get_file_as_string(root.saves.path(auto)) == previous and not root.saves.error.is_empty(), "manual save dispatch cannot overwrite autosave")
	root.save_slots.back()
	root.game_menu.back()
	root._travel(0, 0)
	loaded = root.saves.read_slot(auto, root.world, root.metadata, root.table, root.rewards)
	checks.check(not loaded.is_empty() and loaded["session"].location_id == 0 and loaded["session"].gold == 123 and FileAccess.get_file_as_string(root.saves.path(auto) + ".bak") == previous, "return to surface autosaves destination and backs up previous entrance")
	previous = FileAccess.get_file_as_string(root.saves.path(auto))
	root._show_main_menu(true)
	root.main_menu.selected = 2
	root.main_menu.confirm()
	root.save_slots.confirm()
	checks.check(root.session.gold == 700 and FileAccess.get_file_as_string(root.saves.path(auto)) == previous, "loading a manual slot preserves the latest autosave")
	root._show_game_menu()
	root.game_menu.selected = 5
	root.game_menu.confirm()
	root.save_slots.selected = auto
	var row: Rect2 = root.save_slots.regions[auto].logical_rect
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = root.save_slots.screen_origin + row.get_center() * root.save_slots.screen_scale
	root.save_slots._gui_input(click)
	checks.check(root.session.gold == 123 and not root.save_slots.visible and FileAccess.get_file_as_string(root.saves.path(auto)) == previous, "mouse loads autosave from in-game menu without overwriting it")
	for slot in range(root.saves.TOTAL_SLOT_COUNT):
		for suffix in ["", ".tmp", ".bak"]:
			if FileAccess.file_exists(root.saves.path(slot) + suffix): DirAccess.remove_absolute(root.saves.path(slot) + suffix)
	DirAccess.remove_absolute(root.saves.directory)
	root.saves.directory = original_directory
	root._restart(false)
