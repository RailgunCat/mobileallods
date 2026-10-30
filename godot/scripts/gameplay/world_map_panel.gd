extends "res://scripts/gameplay/legacy_ui_screen.gd"
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Tavern = preload("res://scripts/gameplay/tavern_rules.gd")
signal destination_chosen(map_id: int, entry_id: int)
signal closed
signal shop_requested
var game
var data: Dictionary
var buttons: Dictionary[int, Hotspot] = {}
var in_town: bool = false
var required: bool = false
var selected: int = 0
var town_selected: int = 0
var screen: StringName = &"world"
var lines: PackedStringArray = []
var scroll: int = 0
var message: String = ""
var map_position := Vector2(41, 48)
var hd_interior: Control
var hd_remaining: Control

func _ready() -> void:
	super._ready()
	hd_interior = preload("res://scripts/gameplay/hd_town_screen.gd").new()
	hd_interior.controller = self
	add_child(hd_interior)
	hd_remaining = preload("res://scripts/gameplay/hd_remaining_screen.gd").new()
	hd_remaining.kind = &"world"
	hd_remaining.controller = self
	add_child(hd_remaining)

func open(session, campaign_data: Dictionary, textures: Dictionary, must_choose: bool = false) -> void:
	game = session
	if not game.world_travel_unlocked():
		visible = false
		return
	data = campaign_data
	setup(textures, game.definitions)
	required = must_choose
	selected = game.location_id + 1 if game.location_id >= 0 else 0
	visible = true
	show_world()
	hd_remaining.reset()

func show_world() -> void:
	if game == null or not game.world_travel_unlocked(): return
	in_town = false
	screen = &"world"
	game.mode = &"world_map"
	visible = true
	message = ""
	var destination: int = _quest_destination()
	if destination > 0: selected = destination
	_world_message()
	clear_regions()
	buttons.clear()
	for node: Dictionary in game.definitions["travel"]["world_nodes"]:
		var index: int = int(node["world_index"])
		var point := map_position + Vector2(float(node["position"][0]), float(node["position"][1]))
		var choice: Hotspot = region(Rect2(point - Vector2(7, 7), Vector2(14, 14)), func():
			if selected == index: confirm()
			else:
				selected = index
				_world_message()
				queue_redraw()
		, str(game.definitions["travel"]["location_names"][index]))
		choice.disabled = int(game.flags["e"][index]) == 0
		buttons[index] = choice
	region(Rect2(9, 294, 100, 25), confirm)
	region(Rect2(130, 294, 100, 25), dismiss)
	queue_redraw()

func _quest_destination() -> int:
	var destination: int = 0
	for offer: Dictionary in game.definitions["travel"]["tavern_offers"]:
		var index: int = int(offer["unlock"])
		if index <= game.location_id + 1 or int(game.flags["e"][index]) == 0: continue
		if int(game.quests[int(offer["quest"])]) == Ids.QuestState.ACTIVE:
			destination = maxi(destination, index)
	return destination

func _world_message() -> void:
	message = "Цель задания: локация %d" % selected if selected > 0 and selected == _quest_destination() else ""

func show_town(skip_help: bool = false) -> void:
	if game == null or not game.world_travel_unlocked(): return
	if not skip_help and int(game.tutorial_seen[Ids.Tutorial.TOWN]) == 0:
		_show_town_help()
		return
	in_town = true
	screen = &"town"
	game.mode = &"town"
	visible = true
	town_selected = 0
	_menu_regions()
	queue_redraw()

func _show_town_help() -> void:
	game.tutorial_seen[Ids.Tutorial.TOWN] = 1
	game.mode = &"town"
	in_town = true
	screen = &"town_help"
	lines = wrap_lines(str(data["tutorials"][Ids.Tutorial.TOWN]), 198)
	scroll = 0
	visible = true
	clear_regions()
	region(Rect2(130, 294, 100, 25), func(): show_town(true))
	queue_redraw()

func _menu_regions() -> void:
	clear_regions()
	for index in range(3):
		region(Rect2(78, 88 + index * 16, 110, 16), func():
			town_selected = index
			confirm()
		)
	region(Rect2(9, 294, 100, 25), confirm)
	region(Rect2(130, 294, 100, 25), back)

func _show_body(text: String) -> void:
	screen = &"body"
	lines = wrap_lines(text, 200)
	scroll = 0
	clear_regions()
	region(Rect2(9, 294, 100, 25), show_tavern.bind(true))
	region(Rect2(130, 294, 100, 25), show_tavern.bind(true))
	queue_redraw()

func show_rumour() -> void:
	_show_body(Tavern.rumour(game))

func take_quest() -> void:
	var offer: Dictionary = Tavern.take_quest(game)
	if offer.is_empty():
		_show_body("Новой работы пока нет.")
		return
	var text: PackedStringArray = []
	for page: Dictionary in data["dialogues"][int(offer["dialogue_id"])]["pages"]:
		text.append(str(page["speaker"]) + "\n" + str(page["text"]))
	_show_body("\n\n".join(text))

func navigate(step: int) -> void:
	if screen == &"world":
		for i in range(13):
			selected = posmod(selected + step, 13)
			if int(game.flags["e"][selected]) != 0: break
		_world_message()
	elif screen in [&"town", &"tavern"]: town_selected = posmod(town_selected + step, 3)
	elif screen == &"body" and hd_interior.active(): hd_interior._scroll_body(step)
	else: scroll = clampi(scroll + step, 0, maxi(0, lines.size() - 18))
	queue_redraw()

func confirm() -> void:
	if not game.world_travel_unlocked(): return
	if screen == &"town_help":
		show_town(true)
		return
	if screen == &"world":
		if selected == 0: show_town()
		elif int(game.flags["e"][selected]) != 0:
			var node: Dictionary = game.definitions["travel"]["world_nodes"][selected]
			destination_chosen.emit(selected - 1, int(node["entry"]))
	elif screen == &"town":
		match town_selected:
			0: show_tavern()
			1: shop_requested.emit()
			2: show_world()
	elif screen == &"tavern":
		if town_selected == 0: show_rumour()
		elif town_selected == 1: take_quest()
		else: show_town()
	elif screen == &"body": show_tavern(true)
	else: show_town()

func show_tavern(keep_selection: bool = false) -> void:
	screen = &"tavern"
	if not keep_selection: town_selected = 0
	_menu_regions()
	queue_redraw()

func back() -> void:
	if screen == &"town_help": show_town(true)
	elif screen == &"world": dismiss()
	elif screen == &"town": show_world()
	elif screen == &"body": show_tavern(true)
	else: show_town()

func dismiss() -> void:
	if not visible or required: return
	visible = false
	closed.emit()

func _draw() -> void:
	if images.is_empty(): return
	if hd_interior != null and hd_interior.active(): return
	if hd_remaining != null and hd_remaining.active(): return
	begin_draw()
	if screen == &"world":
		draw_texture(images[UiImage.WORLD_MAP], map_position)
		for node: Dictionary in game.definitions["travel"]["world_nodes"]:
			var index: int = int(node["world_index"])
			if int(game.flags["e"][index]) == 0: continue
			var point := map_position + Vector2(float(node["position"][0]), float(node["position"][1]))
			draw_texture(images[UiImage.WORLD_SELECTED_NODE] if index == selected else images[UiImage.WORLD_NODE], point - Vector2(2, 2))
			if index == selected:
				draw_arc(point + Vector2(0.5, 0.5), 6, 0, TAU, 16, Color("f2c973"), 1, false)
				draw_texture(images[UiImage.WORLD_CURSOR], point + Vector2(9, -9))
				if index > 0: write(str(index), point + Vector2(-3, -20), HORIZONTAL_ALIGNMENT_LEFT, Color("f2c973"))
			if index == game.location_id + 1: draw_texture(images[UiImage.PARTY_FLAG], point - Vector2(11, 12))
		var title: String = str(game.definitions["travel"]["location_names"][selected])
		write("%d. %s" % [selected, title] if selected > 0 else title, Vector2(120, 284), HORIZONTAL_ALIGNMENT_CENTER)
	elif screen in [&"town", &"tavern"]:
		write("Город" if screen == &"town" else "Таверна", Vector2(120, 28), HORIZONTAL_ALIGNMENT_CENTER)
		var titles: Array = ["Таверна", "Магазин", "Выход"] if screen == &"town" else ["Слухи", "Работа", "Выход"]
		for i in range(3): write(titles[i], Vector2(108, 88 + i * 16))
		selection_arrow(Vector2(67, 88 + town_selected * 16))
	else:
		for i in range(scroll, mini(lines.size(), scroll + 18)): write(lines[i], Vector2(120 if screen == &"town_help" else 20, 30 + (i - scroll) * 14), HORIZONTAL_ALIGNMENT_CENTER if screen == &"town_help" else HORIZONTAL_ALIGNMENT_LEFT)
	if not message.is_empty(): write(message, Vector2(120, 267), HORIZONTAL_ALIGNMENT_CENTER)
	footer(screen != &"town_help", not required or screen != &"world")
	finish_draw()

func _gui_input(event: InputEvent) -> void:
	if hd_remaining != null and hd_remaining.active(): return
	super._gui_input(event)
