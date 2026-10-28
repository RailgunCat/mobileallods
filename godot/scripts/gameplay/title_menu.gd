extends "res://scripts/gameplay/legacy_ui_screen.gd"
const Choice = preload("res://scripts/gameplay/game_ids.gd").TitleChoice
const Controls = preload("res://scripts/gameplay/controls_help.gd")
const Credits = preload("res://scripts/gameplay/credits.gd")
signal new_game_requested
signal settings_requested
signal load_requested
signal resume_requested
var selected: int = 0
var has_game: bool = false
var help_text: String
var body: PackedStringArray = []
var scroll: int = 0


func open(textures: Dictionary, metadata: Dictionary, can_resume: bool) -> void:
	logical_size = Vector2(176, 208)
	setup(textures, metadata)
	literal_latin = false
	help_text = str(metadata["legacy_ui"]["help"])
	has_game = can_resume
	body = []
	selected = 0
	visible = true
	clear_regions()
	region(Rect2(8, 178, 25, 24), func(): navigate(-1))
	region(Rect2(143, 178, 25, 24), func(): navigate(1))
	region(Rect2(34, 178, 108, 24), confirm)
	queue_redraw()


func navigate(step: int) -> void:
	if not body.is_empty(): scroll = clampi(scroll + step, 0, maxi(0, body.size() - 12))
	else: selected = posmod(selected + step, Choice.COUNT)
	queue_redraw()


func confirm() -> void:
	if not body.is_empty():
		body = []
		literal_latin = false
		queue_redraw()
		return
	match selected:
		Choice.NEW_GAME: new_game_requested.emit()
		Choice.CONTINUE:
			if has_game: resume_requested.emit()
			else: load_requested.emit()
		Choice.LOAD: load_requested.emit()
		Choice.NETWORK: body = wrap_lines("Сеть недоступна.", 148)
		Choice.CONTROLS:
			literal_latin = true
			body = wrap_lines(Controls.TEXT, 148)
		Choice.HELP: body = wrap_lines(help_text, 148)
		Choice.CREDITS:
			literal_latin = true
			body = wrap_lines(Credits.TEXT, 148)
		Choice.SETTINGS: settings_requested.emit()
		Choice.EXIT: get_tree().quit()
	scroll = 0
	queue_redraw()


func back() -> void:
	if not body.is_empty():
		body = []
		literal_latin = false
		queue_redraw()
	elif has_game: resume_requested.emit()


func _draw() -> void:
	if images.is_empty(): return
	begin_draw(body.is_empty())
	if body.is_empty():
		var atlas: Texture2D = images[UiImage.TITLE_CAPTIONS]
		var width: float = atlas.get_width()
		var rect := Rect2(0, selected * 20, width, 20)
		if selected == Choice.SETTINGS: write("Настройки", Vector2(88, 184), HORIZONTAL_ALIGNMENT_CENTER)
		else: draw_texture_rect_region(atlas, Rect2(Vector2(floorf((176 - width) / 2), 180), rect.size), rect)
		var arrow_width: int = int(images[UiImage.SMALL_ARROWS].get_width() / 2.0)
		icon(UiImage.SMALL_ARROWS, 0, Vector2(12, 187), arrow_width, 8)
		icon(UiImage.SMALL_ARROWS, 1, Vector2(158, 187), arrow_width, 8)
	else:
		for i in range(scroll, mini(body.size(), scroll + 12)): write(body[i], Vector2(14, 15 + (i - scroll) * 14))
		footer(false, true)
	finish_draw()
