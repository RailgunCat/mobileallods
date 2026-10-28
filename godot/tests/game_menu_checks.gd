extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Choice = Ids.GameMenuChoice
const Inventory = preload("res://scripts/gameplay/inventory_rules.gd")


func run(root, checks) -> void:
	root._restart(false)
	var hero = root.session.hero
	var position: Vector2 = hero.position_pixels
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	root.held_keys[KEY_D] = true
	root._input(escape)
	checks.check(root.game_menu.visible and root.session.mode == &"game_menu" and root.held_keys.is_empty(), "Escape opens original in-game menu and clears walking input")
	root._process(3)
	checks.check(hero.position_pixels == position, "in-game menu freezes exploration")
	hero.attribute_points = 2
	var strength: int = hero.base_stats[Ids.Stat.STRENGTH]
	root.game_menu.navigate(Choice.CHARACTER)
	root.game_menu.confirm()
	checks.check(root.legacy_management.visible and root.legacy_management.page == Ids.ManagementPage.CHARACTER and not root.game_menu.visible and not root.management.visible, "source-style Character opens directly from the field menu")
	root.legacy_management.confirm()
	root.legacy_management.selected = 2
	root.legacy_management.adjust(1)
	root.legacy_management.apply_training()
	checks.check(hero.base_stats[Ids.Stat.STRENGTH] == strength + 1 and hero.attribute_points == 1, "field-menu training applies immediately without visiting town")
	root._input(escape)
	checks.check(root.game_menu.visible and root.session.mode == &"game_menu" and root.game_menu.selected == Choice.CHARACTER, "closing Character returns to the selected in-game menu row")
	var upgrade = Inventory.add(root.session, 13)
	root.game_menu.navigate(Choice.INVENTORY - Choice.CHARACTER)
	root.game_menu.confirm()
	checks.check(root.legacy_management.visible and root.legacy_management.screen == &"party" and not root.management.visible, "Inventory opens the source party selector from the field menu")
	root.legacy_management.confirm()
	for index in range(root.legacy_management.candidates.size()):
		if root.legacy_management.candidates[index] == upgrade:
			root.legacy_management.selected = index
			root.legacy_management._refresh()
			break
	root.legacy_management.confirm()
	checks.check(hero.weapon == upgrade, "field-menu inventory immediately equips selected gear")
	root._input(escape)
	checks.check(root.legacy_management.screen == &"party", "back from an inventory item returns to the party selector")
	root._input(escape)
	root.game_menu.navigate(Choice.JOURNAL - Choice.INVENTORY)
	root.game_menu.confirm()
	checks.check(root.legacy_management.visible and root.legacy_management.screen == &"journal" and not root.management.visible, "source-style Journal opens from the same in-game menu")
	root._input(escape)
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = root.game_menu.screen_origin + Vector2(120, 24 + Choice.HELP * 21 + 5) * root.game_menu.screen_scale
	root.game_menu._gui_input(click)
	checks.check(not root.game_menu.body.is_empty(), "mouse selection opens recovered Help within game menu")
	root._input(escape)
	checks.check(root.game_menu.visible and root.game_menu.body.is_empty(), "Escape from Help returns to game menu")
	var original_directory: String = root.saves.directory
	root.saves.directory = "user://stage8-ui-%d" % Time.get_ticks_usec()
	root.campaign.enabled = true
	root.game_menu.navigate(Choice.SAVE - Choice.HELP)
	root.game_menu.confirm()
	checks.check(root.save_slots.visible and root.save_slots.saving, "Save opens five native slots")
	root.save_slots.confirm()
	checks.check(root.saves.exists(0) and root.save_slots.message.contains("сохранена"), "menu saves the current campaign")
	root._input(escape)
	root.game_menu.selected = Choice.LOAD
	root.game_menu.confirm()
	var previous_gold: int = root.session.gold
	root.session.gold += 500
	root.save_slots.confirm()
	checks.check(root.session.gold == previous_gold and not root.save_slots.visible and root.session.mode == &"exploration", "menu load restores the saved campaign")
	# The session has been replaced with restored objects.
	hero = root.session.hero
	root._show_game_menu()
	DirAccess.remove_absolute(root.saves.path(0))
	DirAccess.remove_absolute(root.saves.directory)
	root.saves.directory = original_directory
	root._input(escape)
	checks.check(not root.game_menu.visible and root.session.mode == &"exploration" and root.session.hero == hero, "Escape resumes the same party after management")
	root._show_game_menu()
	root.game_menu.navigate(Choice.MAIN_MENU)
	root.game_menu.confirm()
	checks.check(root.main_menu.visible and not root.game_menu.visible, "Main menu opens the title screen from game menu")
	root.main_menu.navigate(Ids.TitleChoice.CONTINUE)
	root.main_menu.confirm()
	checks.check(root.session.hero == hero and root.session.mode == &"exploration", "Continue after title preserves field-menu equipment and progression")
	root._restart(false)
	original_directory = root.saves.directory
	root.saves.directory = "user://combat-menu-%d" % Time.get_ticks_usec()
	root.campaign.enabled = true
	root.session.gold = 432
	checks.check(root.saves.save_slot(0, root.session, root.campaign, root.exploration), "combat-load fixture saves exploration before entering battle")
	root._demo_battle()
	root._input(escape)
	checks.check(root.game_menu.visible and root.battle_overlay.phase == &"intro", "Escape opens the menu during battle introduction")
	var intro_time: float = root.battle_overlay.elapsed
	root._process(3)
	checks.check(root.battle_overlay.elapsed == intro_time, "battle menu pauses the introduction")
	root._input(escape)
	checks.check(root.session.mode == &"battle_intro" and not root.game_menu.visible, "closing menu restores the battle introduction")
	root.battle_overlay.acknowledge()
	root.battle.attack(root.battle.unit(1004).instance_id)
	root._process(0.062)
	var command: Dictionary = root.battle.current.duplicate(true)
	var tick: int = root.battle.tick_count
	root._input(escape)
	checks.check(root.game_menu.visible and root.session.mode == &"game_menu" and not command.is_empty(), "Escape opens the combat menu while an attack is executing")
	root._process(3)
	checks.check(root.battle.tick_count == tick and root.battle.current == command, "combat menu freezes the current command and simulation tick")
	for choice in [Choice.SAVE, Choice.CHARACTER, Choice.INVENTORY, Choice.JOURNAL]:
		root.game_menu.selected = choice
		root.game_menu.confirm()
		root._game_menu_chosen(choice)
		checks.check(not root.game_menu.choice_enabled(choice) and root.game_menu.regions[choice].disabled and root.game_menu.visible and not root.management.visible and not root.legacy_management.visible and not root.save_slots.visible, "combat blocks restricted menu choice %d through keyboard, mouse region and dispatcher" % choice)
	root._open_save_slots(true, &"game_menu")
	root._open_management(Ids.ManagementPage.CHARACTER)
	checks.check(not root.save_slots.visible and not root.management.visible, "direct shortcuts cannot save or train during combat")
	checks.check(root.game_menu.choice_enabled(Choice.EXIT) and root.game_menu.choice_enabled(Choice.LOAD), "combat allows exit and load choices")
	root.game_menu.selected = Choice.MAIN_MENU
	root.game_menu.confirm()
	checks.check(root.main_menu.visible and root.battle.active, "combat can return to the title menu")
	root.main_menu.selected = Ids.TitleChoice.CONTINUE
	root.main_menu.confirm()
	checks.check(root.session.mode == &"battle" and root.battle.current == command, "Continue from title restores the paused combat command")
	root._show_game_menu()
	root.game_menu.selected = Choice.LOAD
	root.game_menu.confirm()
	checks.check(root.save_slots.visible and not root.save_slots.saving, "combat menu opens load slots")
	root.save_slots.selected = 4
	root.save_slots.confirm()
	checks.check(root.battle.current == command and root.save_slots.visible, "empty load slot preserves the paused battle")
	root.save_slots.back()
	root._input(escape)
	checks.check(root.session.mode == &"battle" and root.battle.current == command, "cancelling load and closing the menu resumes the same battle")
	root._show_game_menu()
	root.game_menu.selected = Choice.LOAD
	root.game_menu.confirm()
	root.save_slots.confirm()
	checks.check(root.session.gold == 432 and root.session.mode == &"exploration" and not root.battle.active and root.battle.current.is_empty() and not root.save_slots.visible and not root.battle_overlay.visible, "loading in combat replaces the battle with saved exploration and clears combat UI")
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(root.saves.path(0) + suffix): DirAccess.remove_absolute(root.saves.path(0) + suffix)
	DirAccess.remove_absolute(root.saves.directory)
	root.saves.directory = original_directory
	root._restart(false)
