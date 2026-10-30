extends "res://scripts/gameplay/hd_menu_screen.gd"
## Remaining desktop screens reuse the menu theme and existing game controllers.
const Icons = preload("res://scripts/gameplay/ui_icons.gd")
var list_page: int = 0
var world_rect := Rect2()
var last_screen: StringName = &""

func _ready() -> void:
	super._ready()
	if kind == &"world":
		var path: String = "res://art/ui/hd-town-v1/town-v1.png"
		painting = load(path) if ResourceLoader.exists(path) else null
		background.texture = painting

func active() -> bool:
	if controller == null or controller.ui_icons == null or not controller.ui_icons.preferences.values["hd_icons"]: return false
	if kind == &"world": return controller.screen in [&"world", &"town", &"town_help"] and (controller.screen == &"world" or painting != null)
	if kind == &"loot": return controller.page == Ids.ManagementPage.LOOT
	return kind == &"battle" and controller.phase != &""

func reset() -> void:
	super.reset()
	list_page = 0

func _process(_delta: float) -> void:
	var enabled: bool = active()
	if visible != enabled:
		visible = enabled
		controller.queue_redraw()
	if kind == &"loot": controller.panel.visible = not enabled
	elif kind == &"battle": controller.border_panel.visible = not enabled
	if not enabled or not controller.visible: return
	background.visible = kind == &"world" and controller.screen != &"world"
	if kind == &"world" and last_screen != controller.screen:
		last_screen = controller.screen
		list_page = 0
	queue_redraw()

func _images() -> Dictionary:
	return controller.textures if kind == &"battle" else controller.images

func _draw() -> void:
	if not active() or _images().is_empty(): return
	project_font = controller.get_theme_font("font", "Label")
	if project_frame == null:
		project_frame = UiTheme.frame(_images())
		project_frame.draw_center = false
	ui_scale = minf(size.x / DESIGN.x, size.y / DESIGN.y)
	if ui_scale <= 0: return
	origin = ((size - DESIGN * ui_scale) * 0.5).floor()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.025, 0.02, 0.25 if background.visible else 0.86))
	draw_set_transform(origin, 0, Vector2.ONE * ui_scale)
	actions.clear()
	sliders.clear()
	if kind == &"world":
		if controller.screen == &"world": _world()
		else: _town()
	else: _receipt()
	draw_set_transform(Vector2.ZERO)

func _town() -> void:
	_panel(Rect2(42, 42, 490, 102), true)
	_text("Город", Vector2(68, 89), 36, GOLD)
	_text("Золото: %d" % controller.game.gold, Vector2(68, 124), 21)
	_panel(Rect2(42, 190, 490, 510))
	if controller.screen == &"town_help":
		var lines := _lines(str(controller.data["tutorials"][Ids.Tutorial.TOWN]), 430, 21)
		body_limit = maxi(0, lines.size() - 12)
		body_scroll = clampi(body_scroll, 0, body_limit)
		for i in range(body_scroll, mini(body_scroll + 12, lines.size())): _text(lines[i], Vector2(68, 228 + (i - body_scroll) * 30), 21, INK, 430)
		_button("town_help_done", Rect2(68, 626, 438, 48), "Понятно", controller.show_town.bind(true))
	else:
		var titles: Array = ["Таверна", "Магазин", "Карта мира"]
		var hints: Array = ["Слухи и новые задания", "Оружие, доспехи и кристаллы", "Продолжить путешествие"]
		for i in range(3):
			_button("town_%d" % i, Rect2(68, 226 + i * 139, 438, 62), titles[i], _choose_town.bind(i), true, controller.town_selected == i)
			_text(hints[i], Vector2(80, 323 + i * 139), 19, MUTED, 415)
	_text("↑ ↓  выбор · Enter  открыть · Esc  карта мира", Vector2(48, 765), 17, MUTED)

func _choose_town(index: int) -> void:
	controller.town_selected = index
	controller.confirm()

func _world() -> void:
	_panel(Rect2(24, 24, 1232, 92), true)
	_text("Карта мира", Vector2(48, 79), 36, GOLD)
	_text("Выберите место путешествия", Vector2(410, 79), 22, MUTED)
	_panel(Rect2(24, 140, 746, 560))
	_panel(Rect2(794, 140, 462, 560), true)
	var texture: Texture2D = controller.images[Ids.ImageId.WORLD_MAP]
	world_rect = Icons.fit_rect(texture, Rect2(48, 160, 698, 520))
	draw_texture_rect(texture, world_rect, false)
	var available: Array[int] = []
	for node: Dictionary in controller.game.definitions["travel"]["world_nodes"]:
		var index: int = int(node["world_index"])
		if int(controller.game.flags["e"][index]) == 0: continue
		available.append(index)
		var point: Vector2 = world_rect.position + Vector2(node["position"][0], node["position"][1]) * world_rect.size / texture.get_size()
		var selected: bool = controller.selected == index
		draw_circle(point, 7 if selected else 5, GOLD if selected else Color("6fd54f"))
		draw_circle(point, 2, Color("162615"))
		if selected: draw_arc(point, 13, 0, TAU, 24, GOLD, 2)
		_text(str(index), point + Vector2(10, -9), 20, GOLD)
		if index == controller.game.location_id + 1: _text("Отряд", point + Vector2(-18, 28), 16, INK)
		actions.append({"id": "map_%d" % index, "rect": Rect2(point - Vector2(14, 14), Vector2(28, 28)), "call": _choose_destination.bind(index), "enabled": true})
	_text("Открытые локации", Vector2(818, 180), 27, GOLD)
	list_page = clampi(list_page, 0, maxi(0, int((available.size() - 1) / 8.0)))
	for i in range(list_page * 8, mini(list_page * 8 + 8, available.size())):
		var index: int = available[i]
		var title: String = str(controller.game.definitions["travel"]["location_names"][index])
		_button("destination_%d" % index, Rect2(818, 207 + (i % 8) * 49, 414, 42), "%d. %s" % [index, title], _select_destination.bind(index), true, controller.selected == index)
	_button("world_prev", Rect2(818, 626, 120, 46), "Назад", _page.bind(-1), list_page > 0)
	_button("world_next", Rect2(1110, 626, 122, 46), "Далее", _page.bind(1), (list_page + 1) * 8 < available.size())
	_button("travel", Rect2(794, 730, 270, 46), "Войти в город" if controller.selected == 0 else "Путешествовать", controller.confirm)
	_button("close", Rect2(1080, 730, 176, 46), "Закрыть", controller.dismiss, not controller.required)
	_text(controller.message, Vector2(32, 760), 20, GOLD, 730)

func _select_destination(index: int) -> void:
	controller.selected = index
	controller._world_message()
	controller.queue_redraw()

func _choose_destination(index: int) -> void:
	if controller.selected == index: controller.confirm()
	else: _select_destination(index)

func _page(step: int) -> void:
	list_page += step
	queue_redraw()

func _receipt() -> void:
	_panel(Rect2(180, 70, 920, 662), true)
	var battle: bool = kind == &"battle"
	var intro: bool = battle and controller.phase == &"intro"
	var defeat: bool = battle and controller.phase == &"defeat"
	_text(controller.heading.text if battle else "Получено", Vector2(212, 125), 36, GOLD)
	if intro or defeat:
		var lines := _lines(controller.body.text, 856)
		body_limit = maxi(0, lines.size() - 12)
		body_scroll = clampi(body_scroll, 0, body_limit)
		for i in range(body_scroll, mini(body_scroll + 12, lines.size())): _text(lines[i], Vector2(212, 190 + (i - body_scroll) * 31), 22, INK, 856)
		if intro:
			draw_rect(Rect2(212, 625, 856, 12), Color("354536"))
			draw_rect(Rect2(212, 625, 856 * minf(1, controller.elapsed / 2.0), 12), GOLD)
	else:
		var receipt: Dictionary = controller.reward if battle else controller.receipt
		var gold: int = receipt.get("gold", 0)
		_text("Золото: +%d" % gold, Vector2(212, 174), 24, GOLD)
		if battle: _text("Опыт каждому: +%d" % receipt.get("xp_each", 0), Vector2(570, 174), 24)
		var counts: Dictionary = {}
		for id in receipt.get("items", []): counts[int(id)] = counts.get(int(id), 0) + 1
		var ids: Array = counts.keys()
		list_page = clampi(list_page, 0, maxi(0, int((ids.size() - 1) / 8.0)))
		for i in range(list_page * 8, mini(list_page * 8 + 8, ids.size())):
			var id: int = ids[i]
			var rect := Rect2(212, 206 + (i % 8) * 50, 856, 44)
			draw_rect(rect, Color("1b281f"))
			var texture: Texture2D
			if id < Ids.ItemId.FIRST_CRYSTAL: texture = _images()[Ids.EconomyImage.ITEM_BASE + id]
			else:
				var atlas := AtlasTexture.new()
				atlas.atlas = _images()[Ids.EconomyImage.CRYSTAL_ATLAS]
				atlas.region = Rect2((id - Ids.ItemId.FIRST_CRYSTAL) * 16, 0, 16, 16)
				texture = atlas
			draw_texture_rect(texture, Icons.fit_rect(texture, Rect2(rect.position + Vector2(6, 3), Vector2(38, 38))), false)
			var names: Array = controller.reward_names if battle else controller.game.definitions["economy"]["item_names"]
			_text(str(names[id]) if id < names.size() else str(id), rect.position + Vector2(58, 29), 22, INK, 690)
			_text("×%d" % counts[id], rect.position + Vector2(766, 29), 22, GOLD)
		if ids.is_empty(): _text("Предметов нет", Vector2(212, 258), 23, MUTED)
		_button("loot_prev", Rect2(212, 620, 136, 38), "Назад", _page.bind(-1), list_page > 0)
		_button("loot_next", Rect2(362, 620, 136, 38), "Далее", _page.bind(1), (list_page + 1) * 8 < ids.size())
		_text("Предметы уже в общей сумке", Vector2(600, 648), 19, MUTED)
	_button("continue", Rect2(762, 674, 306, 42), "Начать бой" if intro else "Начать заново" if defeat else "Продолжить", controller.acknowledge if battle else controller.dismiss)
	_text("Enter / Пробел — продолжить", Vector2(212, 703), 18, MUTED)

func _gui_input(event: InputEvent) -> void:
	if not active() or ui_scale <= 0: return
	if event is InputEventMouseMotion:
		hover = (event.position - origin) / ui_scale
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		accept_event()
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var step: int = -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			if kind == &"world" and controller.screen == &"town_help": scroll_body(step * 3)
			else: _page(step)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var point: Vector2 = (event.position - origin) / ui_scale
			for action: Dictionary in actions:
				if action["enabled"] and action["rect"].has_point(point):
					if controller.has_signal("ui_action"): controller.emit_signal("ui_action", "confirm")
					action["call"].call()
					break
		queue_redraw()
