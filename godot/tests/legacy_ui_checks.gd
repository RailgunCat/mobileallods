extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")


func run(root, checks) -> void:
	root._restart(false)
	root._show_main_menu()
	checks.check(root.main_menu.glyph_index("ё") == root.main_menu.glyph_index("е") and root.main_menu.glyph_index("Ё") == root.main_menu.glyph_index("Е"), "legacy menus resolve yo letters to existing Cyrillic glyphs")
	checks.check(root.main_menu.text_width("Сохранённая игра") == root.main_menu.text_width("Сохраненная игра"), "save caption measures the same glyphs it renders")
	checks.check(root.main_menu.visible and root.session.mode == &"main_menu", "original title menu pauses gameplay")
	var position: Vector2 = root.session.hero.position_pixels
	root._process(3)
	checks.check(root.session.hero.position_pixels == position, "title menu freezes exploration")
	root.main_menu.navigate(5)
	root.main_menu.confirm()
	checks.check(root.main_menu.selected == 5 and not root.main_menu.body.is_empty(), "original Help item opens recovered help text")
	root.main_menu.back()
	root.main_menu.navigate(-5)
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_ENTER
	root._input(key)
	checks.check(not root.main_menu.visible and root.campaign.enabled and root.campaign.script_id == Ids.StoryScript.EXPLORATION_TUTORIAL, "title Enter starts original new-game story")
	for i in range(100):
		if not root.campaign.busy(): break
		if not root.campaign.modal.is_empty(): root.campaign.acknowledge()
		else: root._process(0.062)
	var hero = root.session.hero
	root.session.gold = 123
	root._show_main_menu()
	root.main_menu.navigate(1)
	root.main_menu.confirm()
	checks.check(root.session.hero == hero and root.session.gold == 123 and not root.main_menu.visible and root.session.mode == &"exploration", "Continue returns to the same active session")
	# Shop fixture starts after the source certificate milestone.
	root.session.quests[Ids.Quest.CITY_CERTIFICATE] = Ids.QuestState.COMPLETED
	root.session.tutorial_seen[Ids.Tutorial.TOWN] = 1
	root._show_world(false)
	root.world_panel.show_town()
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = root.world_panel.screen_origin + Vector2(130, 112) * root.world_panel.screen_scale
	root.world_panel._gui_input(click)
	checks.check(root.shop.visible and root.shop.screen == &"choice" and not root.world_panel.visible, "original city Shop item opens purchase-sale selection")
	root.shop.navigate(1)
	root.shop.confirm()
	checks.check(root.shop.selling and root.shop.candidates.size() == 2, "sale carousel shows actual starting inventory")
	var weapon = root.session.hero.weapon
	root.shop.confirm()
	checks.check(root.shop.screen == &"confirm" and root.session.gold == 123, "selling asks for confirmation before changing state")
	root.shop.back()
	checks.check(root.session.hero.weapon == weapon and root.session.gold == 123, "cancelled sale preserves equipped item")
	root.shop.confirm()
	root.shop.confirm()
	checks.check(root.session.hero.weapon == null and root.session.inventory.size() == 1 and root.session.gold == 183, "confirmed sale unequips original sword and grants exact half price")
	root.shop.back()
	root.shop.back()
	checks.check(root.world_panel.visible and root.world_panel.screen == &"town", "back returns from original shop to city menu")
	root._restart(false)
