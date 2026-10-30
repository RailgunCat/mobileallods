extends Control
## Optional HD presentation. All transactions and tavern actions stay in their
## original controllers; the generated paintings contain no baked-in UI.
const Inventory = preload("res://scripts/gameplay/inventory_rules.gd")
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const UiTheme = preload("res://scripts/gameplay/legacy_theme.gd")
const GOLD := UiTheme.GOLD
const CREAM := UiTheme.GREEN
const MUTED := UiTheme.MUTED
const GREEN := UiTheme.GREEN
const DESIGN := Vector2(1280, 800)
var controller
var is_shop: bool = false
var painting: Texture2D
var actions: Array[Dictionary] = []
var project_font: Font
var project_frame: StyleBoxTexture
var ui_scale: float = 1.0
var origin := Vector2.ZERO
var hover := Vector2(-1, -1)
var signature: String = ""
var body_scroll: int = 0
var body_key: String = ""
var body_limit: int = 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var path: String = "res://art/ui/hd-town-v1/%s-v1.png" % ("shop" if is_shop else "tavern")
	if ResourceLoader.exists(path): painting = load(path)
	var background := TextureRect.new()
	background.texture = painting
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.show_behind_parent = true
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	visible = active()

func active() -> bool:
	if controller == null or controller.ui_icons == null or painting == null or project_frame == null: return false
	if not controller.ui_icons.preferences.values["hd_icons"]: return false
	return is_shop or controller.screen in [&"tavern", &"body"]

func _process(_delta: float) -> void:
	# Controllers are built before gameplay installs the shared legacy theme.
	# Resolve it only after setup, when the original atlases are available.
	if project_frame == null and not controller.images.is_empty():
		project_font = controller.get_theme_font("font", "Label")
		project_frame = UiTheme.frame(controller.images)
		project_frame.draw_center = false
	var enabled: bool = active()
	if visible != enabled:
		visible = enabled
		controller.queue_redraw()
	if not enabled or not controller.visible: return
	var next: String = str([controller.screen, controller.selected if is_shop else controller.town_selected, controller.message, controller.game.gold, controller.candidates.size() if is_shop else controller.lines, controller.ui_icons.revision])
	if next != signature:
		signature = next
		queue_redraw()

func _text(text: String, point: Vector2, pixels: int = 20, color: Color = CREAM, _heading: bool = false, width: float = -1) -> void:
	draw_string(project_font, point + Vector2(1, 2), text, HORIZONTAL_ALIGNMENT_LEFT, width, pixels, Color(0, 0, 0, 0.8))
	draw_string(project_font, point, text, HORIZONTAL_ALIGNMENT_LEFT, width, pixels, color)

func _panel(rect: Rect2) -> void:
	draw_rect(rect, Color(0, 0, 0, 0.92))
	draw_style_box(project_frame, rect.grow(12))

func _button(rect: Rect2, title: String, callback: Callable, selected: bool = false, enabled: bool = true) -> void:
	var lit: bool = enabled and (selected or rect.has_point(hover))
	draw_style_box(controller.get_theme_stylebox("disabled" if not enabled else "hover" if lit else "normal", "Button"), rect)
	_text(title, rect.position + Vector2(18, rect.size.y * 0.5 + 7), 21, GOLD if lit else CREAM if enabled else MUTED, true, rect.size.x - 32)
	if enabled: actions.append({"rect": rect, "call": callback})

func _paragraph(text: String, point: Vector2, width: float, max_lines: int, pixels: int = 21, first: int = 0) -> int:
	var wrapped := PackedStringArray()
	var font: Font = project_font
	for paragraph in text.split("\n"):
		var line: String = ""
		for word in paragraph.split(" "):
			var candidate: String = word if line.is_empty() else line + " " + word
			if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x > width and not line.is_empty():
				wrapped.append(line)
				line = word
			else: line = candidate
		wrapped.append(line)
	for i in range(first, mini(wrapped.size(), first + max_lines)):
		_text(wrapped[i], point + Vector2(0, (i - first) * (pixels + 9)), pixels)
	return wrapped.size()

func _draw() -> void:
	if not active() or controller.game == null: return
	actions.clear()
	ui_scale = minf(size.x / DESIGN.x, size.y / DESIGN.y)
	origin = (size - DESIGN * ui_scale) * 0.5
	draw_set_transform(origin, 0, Vector2.ONE * ui_scale)
	# Subtle edge shade keeps the scene visible behind the live interface.
	draw_rect(Rect2(-origin / ui_scale, size / ui_scale), Color(0.015, 0.02, 0.015, 0.12))
	_panel(Rect2(38, 28, 488, 88))
	_text("Оружейная лавка" if is_shop else "Таверна", Vector2(62, 70), 32, GOLD, true)
	_text("Снаряжение для дальних дорог" if is_shop else "Слухи и поручения", Vector2(63, 98), 16, MUTED)
	if is_shop: _shop()
	else: _tavern()
	_text("↑ ↓  выбор     Enter  подтвердить     Esc  назад", Vector2(42, 776), 15, CREAM)
	draw_set_transform(Vector2.ZERO)

func _choose(index: int) -> void:
	if is_shop: controller.selected = index
	else: controller.town_selected = index
	controller.confirm()

func _tavern() -> void:
	_panel(Rect2(38, 150, 488, 542))
	if controller.screen == &"body":
		var text: String = "\n".join(controller.lines)
		if body_key != text:
			body_key = text
			body_scroll = 0
		_text("Хозяин таверны", Vector2(64, 191), 24, GOLD, true)
		# Reflow the source text for the HD panel, without its legacy line breaks.
		text = text.replace("\n\n", "\t").replace("\n", " ").replace("\t", "\n\n")
		var count: int = _paragraph(text, Vector2(64, 235), 434, 11, 20, body_scroll)
		body_limit = maxi(0, count - 11)
		_button(Rect2(64, 601, 100, 44), "Выше", _scroll_body.bind(-8), false, body_scroll > 0)
		_button(Rect2(174, 601, 100, 44), "Ниже", _scroll_body.bind(8), false, body_scroll + 11 < count)
		_button(Rect2(290, 601, 208, 44), "К разговору", controller.back)
	else:
		_text("Добро пожаловать, путник.", Vector2(64, 197), 24, GOLD, true)
		_paragraph("Здесь всегда найдутся свежие вести и работа для смелых.", Vector2(64, 235), 425, 3, 20)
		_button(Rect2(64, 340, 436, 66), "Слухи", _choose.bind(0), controller.town_selected == 0)
		_text("Послушать, о чём говорят в городе", Vector2(82, 433), 16, MUTED)
		_button(Rect2(64, 467, 436, 66), "Работа", _choose.bind(1), controller.town_selected == 1)
		_text("Узнать о новых поручениях", Vector2(82, 560), 16, MUTED)
		_button(Rect2(64, 601, 436, 50), "В город", _choose.bind(2), controller.town_selected == 2)

func _scroll_body(step: int) -> void:
	body_scroll = clampi(body_scroll + step, 0, body_limit)
	queue_redraw()

func _shop() -> void:
	_panel(Rect2(974, 28, 268, 66))
	_text("Золото:  %d" % controller.game.gold, Vector2(997, 69), 24, GOLD, true)
	if controller.screen == &"choice":
		_panel(Rect2(38, 150, 488, 452))
		_text("Чем могу помочь?", Vector2(64, 202), 28, GOLD, true)
		_paragraph("Доброе оружие и крепкая броня пригодятся в любом походе.", Vector2(64, 243), 423, 3, 20)
		_button(Rect2(64, 340, 436, 64), "Купить снаряжение", _choose.bind(0), controller.selected == 0)
		_button(Rect2(64, 422, 436, 64), "Продать вещи", _choose.bind(1), controller.selected == 1)
		_button(Rect2(64, 523, 436, 50), "В город", controller.back)
		return
	_panel(Rect2(38, 142, 488, 544))
	_text("Ваши вещи" if controller.selling else "Товары торговца", Vector2(62, 180), 25, GOLD, true)
	var first: int = int(controller.selected / 12.0) * 12
	for i in range(first, mini(first + 12, controller.candidates.size())):
		var cell := Rect2(62 + ((i - first) % 4) * 110, 204 + int((i - first) / 4.0) * 116, 102, 106)
		var item = controller.candidates[i]
		var chosen: bool = i == controller.selected
		draw_rect(cell, Color("253e2a") if chosen else Color("141a16"))
		draw_rect(cell, GOLD if chosen else Color("665b40"), false, 2 if chosen else 1)
		_item_icon(item, Rect2(cell.position + Vector2(19, 8), Vector2(64, 64)))
		_text(str(_price(item)), cell.position + Vector2(12, 94), 17, GOLD)
		actions.append({"rect": cell, "call": _select_item.bind(i)})
	if controller.candidates.is_empty(): _text("Нет предметов для продажи", Vector2(64, 254), 20, MUTED)
	_button(Rect2(62, 566, 84, 42), "<", controller.navigate.bind(-1), false, controller.selected > 0)
	_text("%d / %d" % [0 if controller.candidates.is_empty() else controller.selected + 1, controller.candidates.size()], Vector2(168, 594), 18, MUTED)
	_button(Rect2(418, 566, 84, 42), ">", controller.navigate.bind(1), false, controller.selected < controller.candidates.size() - 1)
	_button(Rect2(62, 624, 210, 42), "Продать" if controller.selling else "Купить", controller.confirm, false, not controller.candidates.is_empty())
	_button(Rect2(290, 624, 212, 42), "Назад", controller.back)
	if not controller.candidates.is_empty(): _item_details(controller.candidates[controller.selected])
	if not controller.message.is_empty():
		_panel(Rect2(38, 706, 488, 40))
		_text(controller.message, Vector2(62, 733), 19, GOLD)
	if controller.screen == &"confirm": _confirmation()

func _select_item(index: int) -> void:
	controller.selected = index
	controller.message = ""
	controller.queue_redraw()

func _price(item) -> int:
	var price: int = Inventory.price(controller.game, item)
	return int(price / 2.0) if controller.selling else price

func _item_icon(item, bounds: Rect2) -> void:
	var texture: Texture2D
	if item.definition_id < Ids.ItemId.FIRST_CRYSTAL:
		texture = controller.images[Ids.EconomyImage.ITEM_BASE + item.definition_id]
	else:
		var atlas := AtlasTexture.new()
		atlas.atlas = controller.images[Ids.EconomyImage.CRYSTAL_ATLAS]
		atlas.region = Rect2((item.definition_id - Ids.ItemId.FIRST_CRYSTAL) * 16, 0, 16, 16)
		texture = atlas
	draw_texture_rect(texture, preload("res://scripts/gameplay/ui_icons.gd").fit_rect(texture, bounds), false)

func _item_details(item) -> void:
	_panel(Rect2(720, 446, 522, 300))
	var title: String = str(controller.game.definitions["economy"]["item_names"][item.definition_id])
	_paragraph(title, Vector2(744, 482), 472, 2, 24)
	_text("Цена: %d зол." % _price(item), Vector2(744, 548), 21, GOLD)
	var actor = controller._actor(item)
	if actor != null:
		var id: int = int(controller.game.definitions["unit_portrait_images"][actor.unit_type])
		var portrait: Texture2D = controller.portrait_texture(id)
		draw_texture_rect(portrait, preload("res://scripts/gameplay/ui_icons.gd").fit_rect(portrait, Rect2(1152, 526, 56, 56)), false)
	var y: int = 600
	for row: Array in controller._comparison(item):
		_text(str(row[0]), Vector2(744, y), 16, MUTED, false, 330)
		_text("%s → %s" % [row[1], row[2]], Vector2(1090, y), 16, GREEN if row[2] >= row[1] else Color("e08b73"))
		y += 17
	_text("Надето" if Inventory.owner(controller.game, item) != null else "", Vector2(744, 727), 16, GREEN)

func _confirmation() -> void:
	actions.clear()
	draw_rect(Rect2(Vector2.ZERO, DESIGN), Color(0, 0, 0, 0.7))
	_panel(Rect2(390, 270, 500, 250))
	_text("Продать предмет?" if controller.selling else "Купить предмет?", Vector2(420, 322), 30, GOLD, true)
	_text("Стоимость: %d зол." % _price(controller.candidates[controller.selected]), Vector2(420, 373), 23)
	_button(Rect2(420, 430, 210, 56), "Да", controller.confirm, true)
	_button(Rect2(650, 430, 210, 56), "Назад", controller.back)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover = (event.position - origin) / ui_scale
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		accept_event()
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var step: int = -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			if controller.screen == &"body":
				_scroll_body(step * 3)
			elif controller.screen != &"confirm": controller.navigate(step)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var point: Vector2 = (event.position - origin) / ui_scale
			for action in actions:
				if action["rect"].has_point(point):
					controller.ui_action.emit("confirm")
					action["call"].call()
					break
		queue_redraw()
