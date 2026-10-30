extends RefCounted
const Session = preload("res://scripts/gameplay/game_session.gd")
const WorldPanel = preload("res://scripts/gameplay/world_map_panel.gd")
const Ids = preload("res://scripts/gameplay/game_ids.gd")

func run(root, checks) -> void:
	var game := Session.new()
	game.start(root.world, root.metadata, root.table, root.rewards)
	game.quests[Ids.Quest.CITY_CERTIFICATE] = Ids.QuestState.COMPLETED
	game.triggers[159] = Ids.TriggerState.ENABLED
	var panel := WorldPanel.new()
	root.add_child(panel)
	panel.ui_icons = root.ui_icons
	panel.open(game, root.campaign_data, root.view.textures)
	panel.show_town(true)
	panel.show_tavern()
	panel.take_quest()
	var pages: Array = root.campaign_data["dialogues"][82]["pages"]
	checks.check(panel.body_pages == pages and panel.body_page == 0, "tavern keeps source dialogue pages and speaker identities")
	checks.check(panel.current_body_page()["portrait"] == 23 and panel.current_body_page()["speaker"] == pages[0]["speaker"], "first tavern page shows the father's source portrait and name")
	var flags: String = JSON.stringify(game.flags)
	var count: int = game.inventory.size()
	panel.confirm()
	checks.check(panel.body_page == 1 and panel.current_body_page()["portrait"] == 16 and panel.scroll == 0, "confirm changes the tavern portrait to Tagrim with his reply")
	panel.change_body_page(-1)
	checks.check(panel.body_page == 0 and panel.current_body_page() == pages[0], "previous reply restores the matching text and portrait")
	for index in range(pages.size()):
		checks.check(panel.current_body_page() == pages[index] and panel.portrait_texture(int(pages[index]["portrait"])) != null, "tavern reply %d retains its source text and a usable speaker portrait" % index)
		panel.confirm()
	checks.check(panel.screen == &"tavern" and panel.body_pages.is_empty(), "last dialogue reply returns to tavern actions")
	checks.check(JSON.stringify(game.flags) == flags and game.inventory.size() == count, "paging a tavern conversation never grants its quest or reward twice")
	panel._show_dialogue(pages)
	panel.back()
	checks.check(panel.screen == &"tavern" and panel.body_pages.is_empty(), "Escape can leave a tavern conversation")
	panel.show_rumour()
	checks.check(panel.screen == &"body" and panel.current_body_page().is_empty() and not panel.lines.is_empty(), "anonymous rumours remain scrollable without an invented speaker portrait")
	panel.confirm()
	checks.check(panel.screen == &"tavern", "confirm closes an anonymous rumour")
	panel.queue_free()
