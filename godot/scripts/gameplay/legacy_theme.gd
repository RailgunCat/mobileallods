extends RefCounted
## Reuse the Java ME atlas and stone frame in desktop-sized native controls.
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const GREEN = Color(0, 1, 0)
const MUTED = Color(0.32, 0.67, 0.20)
const GOLD = Color("f2c973")
const WORLD_SHADE = preload("res://scripts/gameplay/world_shade.gdshader")


static func world_shade(brightness: float = 0.45) -> ColorRect:
	var shade := ColorRect.new()
	var material := ShaderMaterial.new()
	material.shader = WORLD_SHADE
	material.set_shader_parameter("brightness", brightness)
	shade.material = material
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return shade


static func font_pixels(texture: Texture2D, tint: Color = Color.WHITE) -> Image:
	var pixels: Image = texture.get_image()
	pixels.convert(Image.FORMAT_RGBA8)
	for y in range(pixels.get_height()):
		for x in range(pixels.get_width()):
			var color: Color = pixels.get_pixel(x, y)
			var light: float = maxf(color.r, maxf(color.g, color.b))
			pixels.set_pixel(x, y, Color(light * tint.r, light * tint.g, light * tint.b, color.a))
	return pixels


static func glyph_region(descriptor: Dictionary, index: int) -> Rect2:
	var columns: int = int(descriptor["columns"])
	var height: int = int(descriptor["cell_height"])
	return Rect2((index % columns) * int(descriptor["cell_width"]), int(index / float(columns)) * height, int(descriptor["widths"][index]), height)

static func bitmap_font(images: Dictionary, descriptor: Dictionary) -> FontFile:
	var font := FontFile.new()
	var height: int = int(descriptor["cell_height"])
	font.font_name = "Allods original bitmap"
	font.fixed_size = height
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.modulate_color_glyphs = true
	font.fallbacks = [ThemeDB.fallback_font]
	var pixels: Image = font_pixels(images[Ids.ImageId.BITMAP_FONT])
	font.set_texture_image(0, Vector2i(height, 0), 0, pixels)
	font.set_cache_ascent(0, height, height - 2)
	font.set_cache_descent(0, height, 2)
	var characters: String = descriptor["characters"]
	for index in range(characters.length()):
		var code: int = characters.unicode_at(index)
		if code in range(65, 91) or code in range(97, 123): continue
		_glyph(font, descriptor, index, characters.unicode_at(index))
	# Modern punctuation uses existing pixels; no replacement art/font is required.
	var aliases := {"ё": "е", "Ё": "Е", "—": "-", "–": "-", "−": "-", "·": ".", "×": "х", "…": "."}
	for character: String in aliases:
		var index: int = characters.find(aliases[character])
		if index >= 0: _glyph(font, descriptor, index, character.unicode_at(0))
	return font

static func _glyph(font: FontFile, descriptor: Dictionary, index: int, code: int) -> void:
	var height: int = int(descriptor["cell_height"])
	var width: int = int(descriptor["widths"][index])
	var cache := Vector2i(height, 0)
	font.set_glyph_advance(0, height, code, Vector2(width - 1, 0))
	font.set_glyph_offset(0, cache, code, Vector2(0, -(height - 2)))
	font.set_glyph_size(0, cache, code, Vector2.ZERO if code == 32 else Vector2(width, height))
	font.set_glyph_texture_idx(0, cache, code, 0)
	font.set_glyph_uv_rect(0, cache, code, glyph_region(descriptor, index))

static func frame(images: Dictionary) -> StyleBoxTexture:
	var pixels := Image.create(36, 36, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.BLACK)
	var left: Image = images[Ids.ImageId.FRAME_LEFT].get_image()
	var right: Image = images[Ids.ImageId.FRAME_RIGHT].get_image()
	var horizontal: Image = images[Ids.ImageId.FRAME_HORIZONTAL].get_image()
	for source in [left, right, horizontal]: source.convert(Image.FORMAT_RGBA8)
	pixels.blit_rect(left, Rect2i(0, 0, 9, 27), Vector2i.ZERO)
	pixels.blit_rect(left, Rect2i(0, left.get_height() - 9, 9, 9), Vector2i(0, 27))
	pixels.blit_rect(right, Rect2i(0, 0, 9, 27), Vector2i(27, 0))
	pixels.blit_rect(right, Rect2i(0, right.get_height() - 9, 9, 9), Vector2i(27, 27))
	pixels.blit_rect(horizontal, Rect2i(0, 0, 18, 9), Vector2i(9, 0))
	var bottom: Image = horizontal.duplicate()
	bottom.flip_y()
	pixels.blit_rect(bottom, Rect2i(0, 0, 18, 9), Vector2i(9, 27))
	pixels.resize(72, 72, Image.INTERPOLATE_NEAREST)
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(pixels)
	style.set_texture_margin_all(18)
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.set_content_margin_all(24)
	return style

static func _box(background: Color, border: Color, thickness: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(thickness)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

static func create(images: Dictionary, metadata: Dictionary) -> Theme:
	var result := Theme.new()
	result.default_font = bitmap_font(images, metadata["legacy_ui"]["font"])
	result.default_font_size = 26
	for type: String in ["Label", "Button", "OptionButton", "CheckButton", "CheckBox", "ItemList", "PopupMenu", "RichTextLabel", "LineEdit"]:
		result.set_color("font_color", type, GREEN)
		result.set_color("font_hover_color", type, GOLD)
		result.set_color("font_focus_color", type, GOLD)
		result.set_color("font_pressed_color", type, GREEN)
		result.set_color("font_disabled_color", type, MUTED)
		result.set_color("font_selected_color", type, GREEN)
	for type: String in ["Panel", "PanelContainer", "PopupPanel", "PopupMenu", "TooltipPanel"]:
		result.set_stylebox("panel", type, frame(images))
	for type: String in ["Button", "OptionButton", "CheckButton", "CheckBox"]:
		result.set_stylebox("normal", type, _box(Color.BLACK, Color("3f392a")))
		result.set_stylebox("hover", type, _box(Color("061606"), GOLD))
		result.set_stylebox("pressed", type, _box(Color("0b2405"), GREEN))
		result.set_stylebox("disabled", type, _box(Color.BLACK, Color("27251c")))
		result.set_stylebox("focus", type, _box(Color.TRANSPARENT, GOLD))
	result.set_stylebox("panel", "ItemList", _box(Color.BLACK, Color("5b5033")))
	for key in ["selected", "selected_focus", "hovered"]: result.set_stylebox(key, "ItemList", _box(Color("0b2405"), GOLD))
	result.set_stylebox("background", "ProgressBar", _box(Color("161609"), Color("534b31")))
	result.set_stylebox("fill", "ProgressBar", _box(Color("7b7a52"), Color("7b7a52"), 0))
	for type: String in ["HScrollBar", "VScrollBar"]:
		result.set_stylebox("scroll", type, _box(Color.BLACK, Color("332c20")))
		for key in ["grabber", "grabber_highlight", "grabber_pressed"]: result.set_stylebox(key, type, _box(Color("50452e"), GOLD))
	result.set_type_variation("WorldOverlay", "PanelContainer")
	var world_overlay: StyleBoxTexture = frame(images)
	world_overlay.draw_center = false
	result.set_stylebox("panel", "WorldOverlay", world_overlay)
	result.set_type_variation("BattleNotice", "PanelContainer")
	var notice: StyleBoxTexture = frame(images)
	notice.draw_center = false
	result.set_stylebox("panel", "BattleNotice", notice)
	return result
