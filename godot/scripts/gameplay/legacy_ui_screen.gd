extends Control
const UiImage = preload("res://scripts/gameplay/game_ids.gd").ImageId
const Hotspot = preload("res://scripts/gameplay/legacy_hotspot.gd")
const UiTheme = preload("res://scripts/gameplay/legacy_theme.gd")
## Original bitmap font, frame pieces and logical pixel layout. Scaling remains
## integral; pointer regions and keyboard focus share the same logical rectangles.
signal ui_action(kind: String)
var ui_icons
var literal_latin: bool = false
var images: Dictionary
var font_data: Dictionary
var green_font: Texture2D
var logical_size := Vector2(240, 320)
var screen_origin := Vector2.ZERO
var screen_scale: float = 1
var regions: Array[Hotspot] = []
var background_color := Color.BLACK
var world_background: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_position_regions)
	visible = false


func enable_world_background() -> void:
	if world_background: return
	world_background = true
	var shade := UiTheme.world_shade()
	shade.show_behind_parent = true
	add_child(shade)


func setup(textures: Dictionary, metadata: Dictionary) -> void:
	images = textures
	font_data = metadata["legacy_ui"]["font"]
	if green_font == null:
		var pixels: Image = UiTheme.font_pixels(images[UiImage.BITMAP_FONT], Color.GREEN)
		green_font = ImageTexture.create_from_image(pixels)
	_position_regions()


func clear_regions() -> void:
	regions.clear()


func region(rect: Rect2, callback: Callable, title: String = "") -> Hotspot:
	var button := Hotspot.new()
	button.tooltip_text = title
	button.logical_rect = rect
	button.pressed.connect(func():
		ui_action.emit("confirm")
		callback.call()
	)
	regions.append(button)
	_position_regions()
	return button


func _position_regions() -> void:
	screen_scale = maxf(1, floorf(minf(size.x / logical_size.x, size.y / logical_size.y)))
	screen_origin = ((size - logical_size * screen_scale) * 0.5).floor()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton or not event.pressed: return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		accept_event()
		call("navigate", -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		return
	if world_background and event.button_index == MOUSE_BUTTON_LEFT:
		if Rect2(12, size.y - 52, 112, 40).has_point(event.position):
			accept_event()
			call("confirm")
			return
		if Rect2(size.x - 124, size.y - 52, 112, 40).has_point(event.position):
			accept_event()
			call("back")
			return
	var point: Vector2 = (event.position - screen_origin) / screen_scale
	for button in regions:
		if not button.disabled and button.logical_rect.has_point(point):
			accept_event()
			button._gui_input(event)
			return


func begin_draw(title_art: bool = false) -> void:
	if world_background:
		_position_transform()
		return
	draw_rect(Rect2(Vector2.ZERO, size), background_color)
	_position_transform()
	if title_art:
		draw_texture(images[UiImage.TITLE_ART], Vector2(9, 9))
		draw_texture(images[UiImage.FRAME_HORIZONTAL], Vector2(9, 0))
		draw_texture_rect_region(images[UiImage.FRAME_LEFT], Rect2(0, 0, 9, logical_size.y), Rect2(0, 0, 9, logical_size.y))
		draw_texture_rect_region(images[UiImage.FRAME_RIGHT], Rect2(logical_size.x - 9, 0, 9, logical_size.y), Rect2(0, 0, 9, logical_size.y))
		draw_texture(images[UiImage.TITLE_FOOTER], Vector2(0, logical_size.y - images[UiImage.TITLE_FOOTER].get_height()))
	else:
		draw_texture_rect(images[UiImage.FRAME_LEFT], Rect2(0, 0, 9, logical_size.y), false)
		draw_texture_rect(images[UiImage.FRAME_RIGHT], Rect2(logical_size.x - 9, 0, 9, logical_size.y), false)
		draw_texture_rect(images[UiImage.FRAME_HORIZONTAL], Rect2(9, 0, logical_size.x - 18, images[UiImage.FRAME_HORIZONTAL].get_height()), true)
		draw_texture_rect(images[UiImage.FRAME_HORIZONTAL], Rect2(9, logical_size.y - 5, logical_size.x - 18, 5), true)
		draw_texture_rect(images[UiImage.FRAME_HORIZONTAL], Rect2(9, logical_size.y - 25, logical_size.x - 18, 1), true)


func _position_transform() -> void:
	draw_set_transform(screen_origin, 0, Vector2.ONE * screen_scale)


func finish_draw() -> void:
	draw_set_transform(Vector2.ZERO)


func glyph_index(character: String) -> int:
	# Match the native bitmap font aliases in LegacyTheme.
	if character == "ё": character = "е"
	elif character == "Ё": character = "Е"
	var index: int = str(font_data["characters"]).find(character)
	return index if index >= 0 else str(font_data["characters"]).length() - 1


func text_width(text: String) -> int:
	var total: int = 0
	for character in text:
		if _literal_letter(character):
			total += ceili(ThemeDB.fallback_font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
			continue
		var index: int = glyph_index(character)
		total += int(font_data["widths"][index]) - 1
	return total


func _literal_letter(character: String) -> bool:
	var code: int = character.unicode_at(0)
	return literal_latin and (code in range(65, 91) or code in range(97, 123) or str(font_data["characters"]).find(character) < 0)

func write(text: String, point: Vector2, align: int = HORIZONTAL_ALIGNMENT_LEFT, color: Color = Color.WHITE) -> void:
	if align == HORIZONTAL_ALIGNMENT_CENTER: point.x -= int(text_width(text) / 2.0)
	elif align == HORIZONTAL_ALIGNMENT_RIGHT: point.x -= text_width(text)
	for character in text:
		if _literal_letter(character):
			draw_string(ThemeDB.fallback_font, point.floor() + Vector2(0, 10), character, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.GREEN * color)
			point.x += ceili(ThemeDB.fallback_font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
			continue
		var index: int = glyph_index(character)
		var width: int = int(font_data["widths"][index])
		var source: Rect2 = UiTheme.glyph_region(font_data, index)
		draw_texture_rect_region(green_font, Rect2(point.floor(), source.size), source, color)
		point.x += width - 1


func wrap_lines(text: String, width: int) -> PackedStringArray:
	var result: PackedStringArray = []
	for paragraph in text.split("\n"):
		var line: String = ""
		for word in paragraph.split(" "):
			var candidate: String = word if line.is_empty() else line + " " + word
			if text_width(candidate) > width and not line.is_empty():
				result.append(line)
				line = word
			else: line = candidate
		result.append(line)
	return result


func icon(image_id: int, frame: int, point: Vector2, frame_width: int, frame_height: int = -1) -> void:
	if image_id == 189 and ui_icons != null:
		draw_texture_rect(ui_icons.spell(frame), Rect2(point, Vector2(frame_width, frame_height if frame_height >= 0 else images[image_id].get_height())), false)
		return
	var texture: Texture2D = images[image_id]
	var rect := Rect2(frame * frame_width, 0, frame_width, texture.get_height() if frame_height < 0 else frame_height)
	draw_texture_rect_region(texture, Rect2(point, rect.size), rect)


func portrait_texture(id: int) -> Texture2D:
	return ui_icons.portrait(id) if ui_icons != null else images[id]

func draw_portrait_rect(id: int, bounds: Rect2) -> void:
	var texture: Texture2D = portrait_texture(id)
	var destination: Rect2 = preload("res://scripts/gameplay/ui_icons.gd").fit_rect(texture, bounds)
	draw_texture_rect(texture, destination, false)

func draw_portrait(id: int, point: Vector2) -> void:
	draw_portrait_rect(id, Rect2(point, images[id].get_size()))

func footer(confirm: bool = true, back: bool = true) -> void:
	if world_background:
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * screen_scale)
		if confirm: icon(UiImage.SOFTKEYS, 0, Vector2(12, size.y / screen_scale - 18), 12)
		if back: icon(UiImage.SOFTKEYS, 1, Vector2(size.x / screen_scale - 24, size.y / screen_scale - 18), 12)
		_position_transform()
		return
	if confirm: icon(UiImage.SOFTKEYS, 0, Vector2(12, logical_size.y - 18), 12)
	if back: icon(UiImage.SOFTKEYS, 1, Vector2(logical_size.x - 24, logical_size.y - 18), 12)


func selection_arrow(point: Vector2) -> void:
	draw_texture(images[UiImage.SELECTION_POINTER], point)
