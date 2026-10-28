extends "res://scripts/gameplay/legacy_ui_screen.gd"
const Choice = preload("res://scripts/gameplay/game_ids.gd").GameMenuChoice
const Controls = preload("res://scripts/gameplay/controls_help.gd")
const Credits = preload("res://scripts/gameplay/credits.gd")
const SETTINGS_TOP: int = 54
const SETTINGS_ROW: int = 34
const TITLES = ["Продолжить", "Журнал", "Персонаж", "Инвентарь", "Сохранить игру", "Загрузить игру", "Настройки", "Помощь", "Главное меню", "Выход из игры", "Управление", "Авторы и права"]
const FIRST_ROW_Y: int = 24
const ROW_HEIGHT: int = 21
const SETTING_KEYS = ["music_enabled", "music_volume", "sfx_enabled", "sfx_volume", "hd_icons", "crt_enabled"]
signal chosen(choice: int)
signal setting_requested(key: String, value)
signal settings_closed
var preferences
var settings_open: bool = false
var settings_selected: int = 0
var music_enabled: bool = true
var selected: int = Choice.CONTINUE
var body: PackedStringArray = []
var scroll: int = 0
var help_text: String = ""
var combat_locked: bool = false
var _drag_setting: int = -1

func _ready() -> void:
	super._ready()
	enable_world_background()

func open(textures: Dictionary, metadata: Dictionary, in_combat: bool = false) -> void:
	combat_locked = in_combat
	setup(textures, metadata)
	background_color = Color(0, 0, 0, 0.72)
	help_text = str(metadata["legacy_ui"]["help"])
	selected = Choice.CONTINUE
	settings_open = false
	literal_latin = false
	settings_selected = 0
	body = []
	scroll = 0
	visible = true
	_build_regions()
	queue_redraw()

func open_settings() -> void:
	settings_open = true
	settings_selected = 0
	_build_regions()
	queue_redraw()

func _build_regions() -> void:
	clear_regions()
	if settings_open:
		for index in range(SETTING_KEYS.size()):
			region(Rect2(28, SETTINGS_TOP - 4 + index * SETTINGS_ROW, 192, SETTINGS_ROW - 2), func():
				settings_selected = index
				confirm()
			)
	elif body.is_empty():
		for choice in range(Choice.COUNT):
			region(Rect2(24, FIRST_ROW_Y + choice * ROW_HEIGHT, 192, ROW_HEIGHT), func():
				selected = choice
				confirm()
			, TITLES[choice])
			regions.back().disabled = not choice_enabled(choice)

func choice_enabled(choice: int) -> bool:
	return not combat_locked or choice not in [Choice.SAVE, Choice.CHARACTER, Choice.INVENTORY, Choice.JOURNAL]

func navigate(step: int) -> void:
	if settings_open: settings_selected = posmod(settings_selected + step, SETTING_KEYS.size())
	elif body.is_empty(): selected = posmod(selected + step, Choice.COUNT)
	else: scroll = clampi(scroll + step, 0, maxi(0, body.size() - 18))
	queue_redraw()

func adjust(step: int) -> void:
	if preferences == null: return
	var key: String = SETTING_KEYS[settings_selected]
	var value = preferences.values[key]
	if key.ends_with("_volume"): value = clampi(int(value) + step * 5, 0, 100)
	else: value = not value
	setting_requested.emit(key, value)
	music_enabled = bool(preferences.values["music_enabled"])
	queue_redraw()

func handle_settings_key(key: int) -> void:
	if key == KEY_ESCAPE: back()
	elif key in [KEY_UP, KEY_W]: navigate(-1)
	elif key in [KEY_DOWN, KEY_S]: navigate(1)
	elif key in [KEY_LEFT, KEY_A]: adjust(-1)
	elif key in [KEY_RIGHT, KEY_D]: adjust(1)
	elif key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]: confirm()

func _slider_at(point: Vector2) -> int:
	for index in [1, 3]:
		if Rect2(28, SETTINGS_TOP - 4 + index * SETTINGS_ROW, 192, SETTINGS_ROW - 2).has_point(point): return index
	return -1

func _set_slider(index: int, x: float) -> void:
	settings_selected = index
	var key: String = SETTING_KEYS[index]
	var value: int = clampi(roundi((x - 40) / 160 * 20) * 5, 0, 100)
	if int(preferences.values[key]) != value: setting_requested.emit(key, value)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if settings_open and preferences != null:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed:
				_drag_setting = -1
			else:
				var point: Vector2 = (event.position - screen_origin) / screen_scale
				var index: int = _slider_at(point)
				if index >= 0:
					_drag_setting = index
					_set_slider(index, point.x)
					accept_event()
					return
		elif event is InputEventMouseMotion and _drag_setting >= 0:
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
				_set_slider(_drag_setting, (event.position.x - screen_origin.x) / screen_scale)
				accept_event()
				return
			_drag_setting = -1
	super._gui_input(event)

func confirm() -> void:
	if settings_open:
		adjust(1)
		return
	if not body.is_empty():
		back()
		return
	if not choice_enabled(selected): return
	match selected:
		Choice.SETTINGS: open_settings()
		Choice.HELP:
			literal_latin = false
			body = wrap_lines(help_text, 198)
		Choice.CONTROLS:
			literal_latin = true
			body = wrap_lines(Controls.TEXT, 198)
		Choice.CREDITS:
			literal_latin = true
			body = wrap_lines(Credits.TEXT, 198)
		_: chosen.emit(selected)
	scroll = 0
	_build_regions()
	queue_redraw()

func back() -> void:
	_drag_setting = -1
	if settings_open:
		settings_open = false
		_build_regions()
		queue_redraw()
		settings_closed.emit()
	elif body.is_empty(): chosen.emit(Choice.CONTINUE)
	else:
		body = []
		literal_latin = false
		_build_regions()
		queue_redraw()

func _draw() -> void:
	if images.is_empty(): return
	begin_draw()
	if settings_open:
		write("Настройки", Vector2(120, 28), HORIZONTAL_ALIGNMENT_CENTER)
		if preferences != null:
			var labels := ["Музыка", "Громкость музыки", "Звуки", "Громкость звуков", "HD-иконки", "CRT-фильтр"]
			for index in range(SETTING_KEYS.size()):
				var key: String = SETTING_KEYS[index]
				var value = preferences.values[key]
				var suffix: String = "%d%%" % int(value) if key.ends_with("_volume") else ("вкл." if value else "выкл.")
				var point := Vector2(40, SETTINGS_TOP + index * SETTINGS_ROW)
				if key in ["hd_icons", "crt_enabled"]:
					var font: Font = ThemeDB.fallback_font
					draw_string(font, point + Vector2(0, 10), "HD" if key == "hd_icons" else "CRT", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.GREEN)
					write(("-иконки: " if key == "hd_icons" else "-фильтр: ") + suffix, point + Vector2(ceilf(font.get_string_size("HD" if key == "hd_icons" else "CRT", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x), 0))
				else: write(labels[index] + ": " + suffix, point)
				if key.ends_with("_volume"):
					draw_rect(Rect2(40, SETTINGS_TOP + 20 + index * SETTINGS_ROW, 160, 5), Color("343434"))
					draw_rect(Rect2(40, SETTINGS_TOP + 20 + index * SETTINGS_ROW, 160 * float(value) / 100, 5), Color("27b82a"))
					draw_rect(Rect2(38 + 160 * float(value) / 100, SETTINGS_TOP + 17 + index * SETTINGS_ROW, 4, 11), Color("ffe8a0"))
		selection_arrow(Vector2(16, SETTINGS_TOP - 2 + settings_selected * SETTINGS_ROW))
		write("Влево/вправо: изменить", Vector2(120, 268), HORIZONTAL_ALIGNMENT_CENTER)
	elif body.is_empty():
		for choice in range(Choice.COUNT):
			var color := Color.WHITE if choice_enabled(choice) else Color(0.35, 0.35, 0.35)
			write(TITLES[choice], Vector2(120, FIRST_ROW_Y + choice * ROW_HEIGHT), HORIZONTAL_ALIGNMENT_CENTER, color)
		var pointer_x: float = maxf(12, (logical_size.x - text_width(TITLES[selected])) * 0.5 - 24)
		selection_arrow(Vector2(pointer_x, FIRST_ROW_Y + selected * ROW_HEIGHT - 2))
	else:
		for row in range(scroll, mini(body.size(), scroll + 18)): write(body[row], Vector2(20, 24 + (row - scroll) * 14))
	footer(body.is_empty(), true)
	finish_draw()
