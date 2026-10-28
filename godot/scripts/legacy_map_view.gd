extends Control
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const StoryGroup = Ids.StoryGroup
const UnitKind = Ids.UnitKind
const Facing = Ids.Facing
const RenderField = Ids.RenderField
## Original pixel coordinates, sprite regions and terrain layers reconstructed
## from m.g/j/k(), n.a/c() and the s tables. No campaign state is simulated here.

signal cell_selected(cell: Vector2i, source_id: int)
signal zoom_changed(value: float)

var world: Dictionary = {}
var graphics: Dictionary = {}
var current_map: Dictionary = {}
var current_scene: Dictionary = {}
var textures: Dictionary[int, Texture2D] = {}
var show_units: bool = true
var show_triggers: bool = false
var show_grid: bool = false
var animate_water: bool = true
var selection := Vector2i(-1, -1)
var pixel_scale: float = 1.0
var map_origin := Vector2.ZERO
var zoom_factor: float = 1.0
var pan := Vector2.ZERO
var _depth_items: Array[Dictionary] = []
var _object_offsets: Dictionary = {}
var _last_tick: int = 0
var _dragging: bool = false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	resized.connect(queue_redraw)


func configure(data: Dictionary, render_data: Dictionary) -> void:
	world = data
	graphics = render_data
	for key: String in graphics["images"]:
		var path: String = "res://data/" + str(graphics["images"][key]["path"])
		textures[int(key)] = load(path) as Texture2D
	for object: Dictionary in graphics["objects"]:
		_object_offsets[int(object["image_id"])] = Vector2(float(object["offset"][0]), float(object["offset"][1]))


func select_map(map: Dictionary, scene: Dictionary) -> void:
	current_map = map
	current_scene = scene
	selection = Vector2i(-1, -1)
	fit_map()
	_depth_items.clear()
	var width: int = int(map["width"])
	for y in range(int(map["height"])):
		for x in range(width):
			var image_id: int = _image_at(x, y)
			if _object_offsets.has(image_id):
				_depth_items.append({"kind": "object", "image": image_id, "position": Vector2(x, y) * 16.0, "order": (y * width + x) * 2})
	update_units(scene.get("units", []))


func update_units(records: Array) -> void:
	current_scene = current_scene.duplicate()
	current_scene["units"] = records
	_depth_items = _depth_items.filter(func(item: Dictionary) -> bool: return item["kind"] == "object")
	var width: int = int(current_map["width"])
	for unit: Array in records:
		var point := Vector2(float(unit[RenderField.PIXEL_X]), float(unit[RenderField.PIXEL_Y]))
		# Original sort cell: (H-1)/16, (I-1)/16, after the object at that cell.
		_depth_items.append({"kind": "unit", "unit": unit, "position": point, "order": (int((point.y - 1) / 16.0) * width + int((point.x - 1) / 16.0)) * 2 + 1})
	_depth_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["order"] != b["order"]:
			return a["order"] < b["order"]
		var first: Vector2 = a["position"]
		var second: Vector2 = b["position"]
		return first.x < second.x if first.y == second.y else first.y < second.y
	)
	queue_redraw()


func fit_map() -> void:
	zoom_factor = 1.0
	pan = Vector2.ZERO
	zoom_changed.emit(zoom_factor)
	queue_redraw()


func _image_at(x: int, y: int) -> int:
	var id: int = int(current_map["source_tile_ids"][y][x])
	return int(world["constants"]["tile_image_ids"][id])


func _process(_delta: float) -> void:
	var tick: int = int(Time.get_ticks_msec() / 62)
	if animate_water and tick != _last_tick:
		_last_tick = tick
		queue_redraw()


func _draw_image(id: int, position: Vector2, modulate: Color = Color.WHITE) -> void:
	draw_texture(textures[id], position, modulate)


func sprite_pose(unit: Array) -> Dictionary:
	var type: int = int(unit[RenderField.UNIT_TYPE])
	var definition: Dictionary = graphics["units"][type]
	# Most original non-party constructors choose a random facing; use a stable
	# default for the inspector unless scenes.pak supplies an explicit direction.
	var direction: int = int(unit[RenderField.FACING]) if unit.size() > RenderField.FACING else (Facing.DOWN if type == UnitKind.HERMIT else Facing.LEFT)
	direction = clampi(direction, Facing.LEFT, Facing.ATTACK_DOWN)
	var frame_size := Vector2(float(definition["frame_sizes"][direction][0]), float(definition["frame_sizes"][direction][1]))
	var origin := Vector2(float(definition["origins"][direction][0]), float(definition["origins"][direction][1]))
	var frame_index: int = int(definition["idle_frame"])
	var walking: bool = unit.size() > RenderField.WALKING and bool(unit[RenderField.WALKING])
	if unit.size() > RenderField.FRAME:
		frame_index = int(unit[RenderField.FRAME]) % definition["frame_columns"][direction].size()
	elif type == UnitKind.BAT and animate_water:
		frame_index = int(_last_tick / int(definition["frame_ticks"][direction])) % definition["frame_columns"][direction].size()
	var column: int = int(definition["frame_columns"][direction][frame_index])
	var row: int = int(definition["frame_rows"][direction][frame_index])
	if type in [UnitKind.TAGRIM, UnitKind.PEASANT, UnitKind.GUARD] and direction == Facing.DOWN and not walking:
		column = 0
		row = 0
	return {"direction": direction, "frame": frame_index, "column": column, "row": row, "frame_size": frame_size, "origin": origin, "image": int(definition["images"][direction])}


func _draw_unit(unit: Array) -> void:
	if unit.size() > RenderField.SHATTERED and bool(unit[RenderField.SHATTERED]): return
	if unit.size() > RenderField.DEAD and bool(unit[RenderField.DEAD]):
		var corpse: int = int(graphics["corpse_images"][int(unit[RenderField.UNIT_TYPE])])
		_draw_image(corpse, Vector2(float(unit[RenderField.PIXEL_X]), float(unit[RenderField.PIXEL_Y])) - textures[corpse].get_size() * 0.5)
		return
	var pose := sprite_pose(unit)
	var direction: int = pose["direction"]
	var column: int = pose["column"]
	var row: int = pose["row"]
	var frame_size: Vector2 = pose["frame_size"]
	var origin: Vector2 = pose["origin"]
	var texture: Texture2D = textures[pose["image"]]
	var mirrored: bool = direction in [Facing.RIGHT, Facing.ATTACK_RIGHT]
	var source_x: float = texture.get_width() - (column + 1) * frame_size.x if mirrored else column * frame_size.x
	var region := Rect2(Vector2(source_x, row * frame_size.y), frame_size)
	# Some original atlases omit empty pixels at the last frame's edge. Java's
	# graphics clip leaves those pixels transparent; intersect before sampling so
	# Godot never clamps/stretches the edge texel into the omitted area.
	var visible: Rect2 = region.intersection(Rect2(Vector2.ZERO, texture.get_size()))
	if not visible.has_area():
		return
	var crop_offset: Vector2 = visible.position - region.position
	var destination := Rect2(Vector2(float(unit[RenderField.PIXEL_X]), float(unit[RenderField.PIXEL_Y])) - origin + Vector2(0, crop_offset.y), visible.size)
	if mirrored:
		# Godot flips a negative-width texture rectangle inside its absolute
		# extent; its position stays at the left edge. Only offset missing pixels
		# from a trimmed frame, not the whole frame width (which shifts the sprite).
		destination.position.x += frame_size.x - crop_offset.x - visible.size.x
		destination.size.x = -visible.size.x
	else:
		destination.position.x += crop_offset.x
	draw_texture_rect_region(texture, destination, visible)


func _update_transform() -> void:
	if current_map.is_empty():
		return
	var pixels := Vector2(float(current_map["width"]), float(current_map["height"])) * 16.0
	pixel_scale = maxf(0.1, minf((size.x - 48.0) / pixels.x, (size.y - 48.0) / pixels.y)) * zoom_factor
	map_origin = ((size - pixels * pixel_scale) * 0.5 + pan).floor()


func _draw() -> void:
	if current_map.is_empty():
		return
	var width: int = int(current_map["width"])
	var height: int = int(current_map["height"])
	var pixels := Vector2(width, height) * 16.0
	_update_transform()
	draw_set_transform(map_origin, 0.0, Vector2.ONE * pixel_scale)
	_draw_tiled_background(int(graphics["background_image"]), pixels)
	for y in range(height):
		for x in range(width):
			var image_id: int = _image_at(x, y)
			var point := Vector2(x, y) * 16.0
			if image_id >= 27 and image_id <= 43:
				if image_id >= 36 and animate_water:
					image_id = 36 + (image_id - 36 + _last_tick) % 8
				_draw_image(image_id, point + (Vector2(-45, -35) if image_id == 35 else Vector2.ZERO))
			elif image_id in [49, 50]:
				_draw_image(62, point + Vector2(-15, -22))
	_draw_ground_overlay()
	_draw_unit_shadows()
	for item: Dictionary in _depth_items:
		if item["kind"] == "object":
			_draw_image(int(item["image"]), item["position"] + _object_offsets[int(item["image"])])
		elif show_units:
			_draw_unit(item["unit"])
	# Original canopy pass draws above characters and all other objects.
	for y in range(height):
		for x in range(width):
			var image_id: int = _image_at(x, y)
			for canopy: Dictionary in graphics["canopies"]:
				if image_id == int(canopy["tile_image_id"]):
					_draw_image(int(canopy["image_id"]), Vector2(x, y) * 16 + Vector2(float(canopy["offset"][0]), float(canopy["offset"][1])))
	_draw_grid(width, height)
	if show_triggers:
		for trigger: Array in current_scene.get("triggers", []):
			var start := Vector2(float(trigger[1]), float(trigger[2]))
			var end := Vector2(float(trigger[3]), float(trigger[4]))
			draw_rect(Rect2(start, end - start), Color(1, 0.76, 0.25, 0.85), false, 1.5 / pixel_scale)
	_draw_selection()
	_draw_foreground_overlay()
	draw_set_transform(Vector2.ZERO)


func _draw_tiled_background(image_id: int, pixels: Vector2) -> void:
	var base: Texture2D = textures[image_id]
	for y in range(0, int(pixels.y), base.get_height()):
		for x in range(0, int(pixels.x), base.get_width()):
			# Crop the final repeat to the map boundary, preserving texture phase.
			var extent := Vector2(mini(base.get_width(), int(pixels.x) - x), mini(base.get_height(), int(pixels.y) - y))
			draw_texture_rect_region(base, Rect2(Vector2(x, y), extent), Rect2(Vector2.ZERO, extent))


func _draw_unit_shadows() -> void:
	if not show_units: return
	for unit: Array in current_scene.get("units", []):
		if unit.size() > RenderField.DEAD and bool(unit[RenderField.DEAD]): continue
		var shadow: int = int(graphics["units"][int(unit[RenderField.UNIT_TYPE])]["shadow_type"])
		if shadow in [0, 2]:
			var id: int = 167 if shadow == 0 else 168
			_draw_image(id, Vector2(float(unit[RenderField.PIXEL_X]) - textures[id].get_width() / 2.0, float(unit[RenderField.PIXEL_Y]) - 3 + (16 if shadow == 2 else 0)), Color(1, 1, 1, 0.4))


func _draw_grid(width: int, height: int) -> void:
	if not show_grid: return
	for x in range(width + 1):
		draw_line(Vector2(x * 16, 0), Vector2(x * 16, height * 16), Color(1, 1, 1, 0.18), 1.0 / pixel_scale)
	for y in range(height + 1):
		draw_line(Vector2(0, y * 16), Vector2(width * 16, y * 16), Color(1, 1, 1, 0.18), 1.0 / pixel_scale)


func _draw_selection() -> void:
	if selection.x >= 0:
		draw_rect(Rect2(Vector2(selection) * 16, Vector2.ONE * 16), Color.WHITE, false, 2.0 / pixel_scale)


func _draw_ground_overlay() -> void:
	pass


func _draw_foreground_overlay() -> void:
	pass


func cell_center(cell: Vector2i) -> Vector2:
	_update_transform()
	return map_origin + (Vector2(cell) * 16 + Vector2.ONE * 8) * pixel_scale


func _gui_input(event: InputEvent) -> void:
	if current_map.is_empty():
		return
	_update_transform()
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_dragging = event.pressed
			accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var map_point: Vector2 = (event.position - map_origin) / pixel_scale
			var old_scale: float = pixel_scale
			var previous_zoom: float = zoom_factor
			zoom_factor = clampf(zoom_factor * (1.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), 0.5, 8.0)
			var new_scale: float = old_scale * zoom_factor / previous_zoom
			var map_size := Vector2(float(current_map["width"]), float(current_map["height"])) * 16
			pan = event.position - map_point * new_scale - (size - map_size * new_scale) * 0.5
			zoom_changed.emit(zoom_factor)
			queue_redraw()
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var cell := Vector2i(((event.position - map_origin) / pixel_scale / 16.0).floor())
			if cell.x >= 0 and cell.y >= 0 and cell.x < int(current_map["width"]) and cell.y < int(current_map["height"]):
				selection = cell
				cell_selected.emit(cell, int(current_map["source_tile_ids"][cell.y][cell.x]))
				queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		pan += event.relative
		queue_redraw()
		accept_event()
