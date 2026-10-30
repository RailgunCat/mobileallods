extends Control
## HD presentation only; title, pause, settings and saves keep their controllers.
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const UiTheme = preload("res://scripts/gameplay/legacy_theme.gd")
const Controls = preload("res://scripts/gameplay/controls_help.gd")
const Credits = preload("res://scripts/gameplay/credits.gd")
const DESIGN = Vector2(1280, 800)
const GOLD = UiTheme.GOLD
const INK = Color("d5dfcd")
const MUTED = Color("92a08b")
const TITLE_NAMES = ["Новая игра", "Продолжить", "Загрузить игру", "Сеть недоступна", "Управление", "Помощь", "Авторы и права", "Выход из игры", "Настройки"]
const SETTINGS_NAMES = ["Музыка", "Громкость музыки", "Звуки", "Громкость звуков", "HD-режим", "CRT-фильтр", "Вертикальная синхронизация", "Лимит кадров"]
const TITLE_ORDER = [Ids.TitleChoice.CONTINUE, Ids.TitleChoice.NEW_GAME, Ids.TitleChoice.LOAD, Ids.TitleChoice.SETTINGS, Ids.TitleChoice.HELP, Ids.TitleChoice.CONTROLS, Ids.TitleChoice.CREDITS, Ids.TitleChoice.NETWORK, Ids.TitleChoice.EXIT]
var controller
var kind: StringName = &"title"
var title_background: bool = false
var painting: Texture2D
var actions: Array[Dictionary] = []
var sliders: Array[Dictionary] = []
var project_font: Font
var project_frame: StyleBoxTexture
var ui_scale: float = 1.0
var origin := Vector2.ZERO
var hover := Vector2(-1, -1)
var signature: String = ""
var body_key: String = ""
var body_scroll: int = 0
var body_limit: int = 0
var drag_setting: int = -1
var background: TextureRect

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var path: String = "res://art/ui/hd-menu-v1/title-v1.png"
	if ResourceLoader.exists(path): painting = load(path)
	background = TextureRect.new()
	background.texture = painting
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.show_behind_parent = true
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	visible = false

func active() -> bool:
	return controller != null and controller.ui_icons != null and controller.ui_icons.preferences.values["hd_icons"] and (painting != null or (kind != &"title" and not title_background))

func reset() -> void:
	body_key = ""
	body_scroll = 0
	drag_setting = -1
	signature = ""
	queue_redraw()

func _process(_delta: float) -> void:
	var enabled: bool = active()
	if visible != enabled:
		visible = enabled
		controller.queue_redraw()
	if not enabled or not controller.visible: return
	background.visible = kind == &"title" or title_background
	var state: Array = [controller.selected, controller.ui_icons.revision, title_background]
	if kind == &"slots": state.append_array([controller.saving, controller.message])
	else:
		state.append(controller.body)
		if kind == &"pause": state.append_array([controller.settings_open, controller.settings_selected, controller.preferences.values, controller.combat_locked])
	var next: String = str(state)
	if signature != next:
		signature = next
		queue_redraw()

func _panel(rect: Rect2, emerald: bool = false) -> void:
	draw_rect(rect, Color(0.05, 0.12, 0.10, 0.96) if emerald else Color(0.035, 0.055, 0.045, 0.96))
	draw_style_box(project_frame, rect.grow(6))
	draw_rect(rect.grow(-3), Color("756b42"), false, 1)

func _text(value: String, point: Vector2, pixels: int = 23, color: Color = INK, width: float = -1) -> void:
	draw_string(project_font, point + Vector2(1, 2), value, HORIZONTAL_ALIGNMENT_LEFT, width, pixels, Color.BLACK)
	draw_string(project_font, point, value, HORIZONTAL_ALIGNMENT_LEFT, width, pixels, color)

func _button(id: String, rect: Rect2, title: String, callback: Callable, enabled: bool = true, selected: bool = false) -> void:
	draw_style_box(controller.get_theme_stylebox("disabled" if not enabled else "hover" if selected or rect.has_point(hover) else "normal", "Button"), rect)
	_text(title, rect.position + Vector2(16, rect.size.y * 0.5 + 8), 23, GOLD if selected else INK if enabled else MUTED, rect.size.x - 28)
	actions.append({"id": id, "rect": rect, "call": callback, "enabled": enabled})

func _lines(value: String, width: float, pixels: int = 22) -> PackedStringArray:
	var result := PackedStringArray()
	for paragraph in value.split("\n"):
		var line := ""
		for word in paragraph.split(" "):
			var next: String = word if line.is_empty() else line + " " + word
			if not line.is_empty() and project_font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x > width:
				result.append(line)
				line = word
			else: line = next
		result.append(line)
	return result

func _draw() -> void:
	if not active() or controller.images.is_empty(): return
	project_font = controller.get_theme_font("font", "Label")
	if project_frame == null:
		project_frame = UiTheme.frame(controller.images)
		project_frame.draw_center = false
	ui_scale = minf(size.x / DESIGN.x, size.y / DESIGN.y)
	if ui_scale <= 0: return
	origin = ((size - DESIGN * ui_scale) * 0.5).floor()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.14 if kind == &"title" or title_background else 0.55))
	draw_set_transform(origin, 0, Vector2.ONE * ui_scale)
	actions.clear()
	sliders.clear()
	if kind == &"slots": _slots()
	elif kind == &"pause" and controller.settings_open: _settings()
	elif not controller.body.is_empty(): _body()
	elif kind == &"title": _title()
	else: _pause()
	_text("↑ ↓  выбор   ·   Enter  подтвердить   ·   Esc  назад", Vector2(40, 773), 17, MUTED)
	draw_set_transform(Vector2.ZERO)

func _choose(choice: int) -> void:
	controller.selected = choice
	controller.confirm()
	reset()

func _title() -> void:
	_text("АЛЛОДЫ", Vector2(62, 113), 62, GOLD)
	_text("Приключение продолжается", Vector2(66, 150), 21, INK)
	_panel(Rect2(44, 180, 440, 551), true)
	for i in range(TITLE_ORDER.size()):
		var choice: int = TITLE_ORDER[i]
		_button("title_%d" % choice, Rect2(66, 199 + i * 57, 396, 46), TITLE_NAMES[choice], _choose.bind(choice), choice != Ids.TitleChoice.NETWORK, controller.selected == choice)

func navigate_title(step: int) -> void:
	var index: int = posmod(TITLE_ORDER.find(controller.selected) + step, TITLE_ORDER.size())
	if TITLE_ORDER[index] == Ids.TitleChoice.NETWORK: index = posmod(index + (1 if step >= 0 else -1), TITLE_ORDER.size())
	controller.selected = TITLE_ORDER[index]
	queue_redraw()

func _pause() -> void:
	_panel(Rect2(220, 132, 840, 570), true)
	_text("Меню игры", Vector2(250, 181), 36, GOLD)
	_text("Бой приостановлен" if controller.combat_locked else "Путешествие приостановлено", Vector2(250, 213), 21, MUTED)
	for choice in range(Ids.GameMenuChoice.COUNT):
		_button("pause_%d" % choice, Rect2(248 + int(choice / 6.0) * 400, 241 + (choice % 6) * 70, 384, 54), controller.TITLES[choice], _choose.bind(choice), controller.choice_enabled(choice), controller.selected == choice)

func _settings() -> void:
	_panel(Rect2(156, 80, 968, 652), true)
	_text("Настройки", Vector2(188, 130), 36, GOLD)
	_text("Звук", Vector2(192, 176), 24, GOLD)
	_text("Изображение", Vector2(660, 176), 24, GOLD)
	for index in range(controller.SETTING_KEYS.size()):
		var key: String = controller.SETTING_KEYS[index]
		var value = controller.preferences.values[key]
		var rect := Rect2(188 + int(index / 4.0) * 468, 193 + (index % 4) * 105, 436, 91)
		draw_rect(rect, Color("17241b"))
		_text(SETTINGS_NAMES[index], rect.position + Vector2(14, 28), 21, INK, 410)
		if key.ends_with("_volume"):
			_text("%d%%" % value, rect.position + Vector2(345, 57), 18, GOLD)
			var track := Rect2(rect.position + Vector2(16, 64), Vector2(395, 10))
			draw_rect(track, Color("354536"))
			draw_rect(Rect2(track.position, Vector2(track.size.x * value / 100.0, track.size.y)), Color("669f46"))
			draw_rect(Rect2(track.position + Vector2(track.size.x * value / 100.0 - 4, -5), Vector2(8, 20)), GOLD)
			sliders.append({"index": index, "rect": track.grow(14), "track": track})
			actions.append({"id": "slider_%d" % index, "rect": track.grow(14), "call": _setting.bind(index), "enabled": true})
		else:
			var caption: String = "Включено" if value else "Выключено"
			if key == "fps_limit": caption = "Без лимита" if value == 0 else "%d кадров/с" % value
			_button("setting_%d" % index, Rect2(rect.position + Vector2(14, 41), Vector2(405, 40)), caption, _setting.bind(index), true, controller.settings_selected == index)
	_button("back", Rect2(858, 655, 234, 48), "Назад", controller.back)
	_text("Настройки сохраняются сразу", Vector2(188, 688), 20, MUTED)

func _setting(index: int) -> void:
	controller.settings_selected = index
	controller.adjust(1)
	queue_redraw()

func _set_volume(index: int, x: float) -> void:
	for slider: Dictionary in sliders:
		if int(slider["index"]) != index: continue
		controller.settings_selected = index
		var track: Rect2 = slider["track"]
		var value: int = clampi(roundi((x - track.position.x) / track.size.x * 20) * 5, 0, 100)
		var key: String = controller.SETTING_KEYS[index]
		if controller.preferences.values[key] != value: controller.setting_requested.emit(key, value)
		queue_redraw()
		return

func _body_text() -> String:
	var controls: int = Ids.TitleChoice.CONTROLS if kind == &"title" else Ids.GameMenuChoice.CONTROLS
	var credits: int = Ids.TitleChoice.CREDITS if kind == &"title" else Ids.GameMenuChoice.CREDITS
	var help: int = Ids.TitleChoice.HELP if kind == &"title" else Ids.GameMenuChoice.HELP
	if controller.selected == controls: return Controls.TEXT
	if controller.selected == credits: return Credits.TEXT
	if controller.selected == help: return controller.help_text
	return "\n".join(controller.body)

func _body() -> void:
	_panel(Rect2(180, 90, 920, 640), true)
	var text: String = _body_text()
	if body_key != text:
		body_key = text
		body_scroll = 0
	_text(TITLE_NAMES[controller.selected] if kind == &"title" else controller.TITLES[controller.selected], Vector2(212, 142), 34, GOLD)
	var lines := _lines(text, 856)
	body_limit = maxi(0, lines.size() - 14)
	body_scroll = clampi(body_scroll, 0, body_limit)
	for i in range(body_scroll, mini(body_scroll + 14, lines.size())): _text(lines[i], Vector2(212, 195 + (i - body_scroll) * 31), 22, INK, 856)
	_button("body_up", Rect2(212, 658, 144, 46), "Выше", scroll_body.bind(-10), body_scroll > 0)
	_button("body_down", Rect2(370, 658, 144, 46), "Ниже", scroll_body.bind(10), body_scroll < body_limit)
	_button("back", Rect2(838, 658, 230, 46), "Назад", controller.back)

func scroll_body(step: int) -> void:
	body_scroll = clampi(body_scroll + step, 0, body_limit)
	queue_redraw()

func _slots() -> void:
	_panel(Rect2(220, 90, 840, 640), true)
	_text("Сохранить игру" if controller.saving else "Загрузить игру", Vector2(250, 142), 34, GOLD)
	for slot in range(controller.slot_count()):
		var rect := Rect2(248, 180 + slot * 68, 784, 54)
		_button("slot_%d" % slot, rect, "", _select_slot.bind(slot), true, controller.selected == slot)
		var location: String = controller.slot_location(slot)
		_text(controller.slot_title(slot), rect.position + Vector2(16, 24 if not location.is_empty() else 35), 23, GOLD if controller.selected == slot else INK, rect.size.x - 28)
		if not location.is_empty(): _text(location, rect.position + Vector2(16, 46), 18, MUTED, rect.size.x - 28)
	var lines := _lines(controller.message, 784, 19)
	for i in range(mini(2, lines.size())): _text(lines[i], Vector2(248, 612 + i * 25), 19, GOLD)
	_button("slot_confirm", Rect2(248, 663, 310, 46), "Сохранить" if controller.saving else "Загрузить", controller.confirm)
	_button("back", Rect2(804, 663, 228, 46), "Назад", controller.back)

func _select_slot(slot: int) -> void:
	controller.selected = slot
	controller.message = ""
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not active() or ui_scale <= 0: return
	if event is InputEventMouseMotion:
		hover = (event.position - origin) / ui_scale
		if drag_setting >= 0:
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT: _set_volume(drag_setting, hover.x)
			else: drag_setting = -1
		queue_redraw()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			drag_setting = -1
			return
		if not event.pressed: return
		accept_event()
		var point: Vector2 = (event.position - origin) / ui_scale
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			controller.navigate(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			for slider: Dictionary in sliders:
				if slider["rect"].has_point(point):
					drag_setting = int(slider["index"])
					_set_volume(drag_setting, point.x)
					return
			for action: Dictionary in actions:
				if action["enabled"] and action["rect"].has_point(point):
					controller.ui_action.emit("confirm")
					action["call"].call()
					break
		queue_redraw()
