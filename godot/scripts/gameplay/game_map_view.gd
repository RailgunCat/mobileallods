extends "res://scripts/legacy_map_view.gd"
const ImageId = Ids.ImageId
const Spell = Ids.Spell
const Side = Ids.Side
const Stat = Ids.Stat
const Feedback = preload("res://scripts/gameplay/combat_feedback.gd")
const Rain = preload("res://scripts/gameplay/rain_presentation.gd")
const SpellVisuals = preload("res://scripts/gameplay/spell_presentation.gd")
var ui_icons
var combat_feedback := Feedback.new()
var zone_action: StringName = &"none"
var zone_turn: int = -1
var ui_frame: StyleBoxTexture
var hud_obstruction: Control
var session
var show_collision: bool = false
var show_reachable: bool = false
var show_debug_markers: bool = false
var route_cells: Array[Vector2i] = []
var route_exact: bool = true
signal camera_follow_changed(enabled: bool)
var camera_follow: bool = true
var follow_point := Vector2.ZERO
var _camera_point := Vector2.ZERO
var _camera_initialized: bool = false
var session_view_alpha: float = 1.0
var battle
var shake_offset := Vector2.ZERO
var _stone_textures: Dictionary[int, Texture2D] = {}
var _fire_glow: Texture2D
var _ice_glow: Texture2D
var unit_names: Array = []
var enemy_hint: PanelContainer
var _enemy_hint_label: Label
var _hover_masks: Dictionary[int, BitMap] = {}


func _ready() -> void:
	super._ready()
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	enemy_hint = PanelContainer.new()
	enemy_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_hint.z_index = 50
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.94)
	style.border_color = Color("bba061")
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	enemy_hint.add_theme_stylebox_override("panel", style)
	add_child(enemy_hint)
	_enemy_hint_label = Label.new()
	_enemy_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_hint_label.add_theme_font_size_override("font_size", 20)
	_enemy_hint_label.add_theme_color_override("font_color", Color("c9efcf"))
	enemy_hint.add_child(_enemy_hint_label)
	enemy_hint.hide()


func enemy_hover_info(point: Vector2) -> Dictionary:
	if session == null or current_map.is_empty() or not show_units or _dragging: return {}
	if session.mode not in [&"exploration", &"battle"] or not Rect2(Vector2.ZERO, size).has_point(point): return {}
	if hud_obstruction != null and hud_obstruction.visible and hud_obstruction.get_global_rect().has_point(global_position + point): return {}
	if battle != null and battle.active:
		for index in range(session.party.size()):
			if _portrait_rect(index).grow(12).has_point(point): return {}
	_update_transform()
	var world_point: Vector2 = (point - map_origin) / pixel_scale
	var enemies: Dictionary = {}
	for actor in session.units:
		if actor in session.party or actor.dead or actor.shattered or not actor.encounter_enabled or not session.is_active(actor): continue
		if actor.side_id == Side.PARTY: continue
		if battle != null and battle.active and actor.instance_id not in battle.participants: continue
		enemies[actor.instance_id] = actor
	# Match the renderer's front-to-back order and test sprite alpha rather
	# than the small ground footprint or transparent corners of the atlas.
	for index in range(_depth_items.size() - 1, -1, -1):
		var item: Dictionary = _depth_items[index]
		if item["kind"] != "unit": continue
		var record: Array = item["unit"]
		var id: int = int(record[RenderField.INSTANCE_ID])
		if not enemies.has(id): continue
		var pose: Dictionary = sprite_pose(record)
		var offset: Vector2 = world_point - Vector2(float(record[RenderField.PIXEL_X]), float(record[RenderField.PIXEL_Y])) + Vector2(pose["origin"])
		var frame_size: Vector2 = pose["frame_size"]
		if not Rect2(Vector2.ZERO, frame_size).has_point(offset): continue
		var image_id: int = int(pose["image"])
		var texture: Texture2D = textures[image_id]
		if not _hover_masks.has(image_id):
			var mask := BitMap.new()
			mask.create_from_image_alpha(texture.get_image())
			_hover_masks[image_id] = mask
		var source := Vector2i(int(pose["column"]) * int(frame_size.x) + int(offset.x), int(pose["row"]) * int(frame_size.y) + int(offset.y))
		if int(pose["direction"]) in [Facing.RIGHT, Facing.ATTACK_RIGHT]:
			source.x = texture.get_width() - int(pose["column"]) * int(frame_size.x) - 1 - int(offset.x)
		if not Rect2i(Vector2i.ZERO, _hover_masks[image_id].get_size()).has_point(source) or not _hover_masks[image_id].get_bitv(source): continue
		var actor = enemies[id]
		var names: Array = unit_names if not unit_names.is_empty() else world["constants"]["unit_names"]
		var caption: String = str(names[actor.unit_type])
		var hp: int = int(actor.stats[Stat.HP])
		var max_hp: int = int(actor.stats[Stat.MAX_HP])
		var mana: int = int(actor.stats[Stat.MANA])
		var max_mana: int = int(actor.stats[Stat.MAX_MANA])
		var text: String = "%s\nЗдоровье: %d / %d" % [caption, hp, max_hp]
		if max_mana > 0: text += "\nМана: %d / %d" % [mana, max_mana]
		return {"id": id, "text": text, "hp": hp, "max_hp": max_hp, "mana": mana, "max_mana": max_mana}
	return {}


func _update_enemy_hint(point: Vector2) -> void:
	var info: Dictionary = enemy_hover_info(point)
	if info.is_empty():
		enemy_hint.hide()
		return
	_enemy_hint_label.text = str(info["text"])
	enemy_hint.reset_size()
	var extent: Vector2 = enemy_hint.get_combined_minimum_size()
	var position: Vector2 = point + Vector2(18, 22)
	if position.x + extent.x > size.x - 12: position.x = point.x - extent.x - 18
	if position.y + extent.y > size.y - 12: position.y = point.y - extent.y - 18
	enemy_hint.position = Vector2(clampf(position.x, 12, maxf(12, size.x - extent.x - 12)), clampf(position.y, 12, maxf(12, size.y - extent.y - 12))).floor()
	enemy_hint.show()


func _image_at(x: int, y: int) -> int:
	if current_map.get("dungeon", false): return -1
	return super._image_at(x, y)


func _draw() -> void:
	if not current_map.get("dungeon", false):
		super._draw()
		_draw_battle_hud()
		return
	_update_transform()
	draw_set_transform(map_origin, 0, Vector2.ONE * pixel_scale)
	var width: int = int(current_map["width"])
	var height: int = int(current_map["height"])
	_draw_tiled_background(64, Vector2(width, height) * 16)
	var ground := {3: [69, -16, -16], 4: [70, -16, -16], 9: [74, -16, -16], 10: [65, -16, -16], 15: [75, -16, -16], 16: [80, -72, -80], 17: [78, -44, -64], 18: [81, -16, -16], 19: [79, -16, -48], 20: [82, -32, -36], 21: [76, -40, -40], 22: [77, -22, -28], 23: [35, -80, -56]}
	for y in range(height):
		for x in range(width):
			var tile: int = int(current_map["source_tile_ids"][y][x])
			if tile in [5, 6]:
				var frame: int = 71 + (int(_last_tick) % 2 if animate_water else tile - 5)
				_draw_image(frame, Vector2(x - 1, y - 1) * 16)
			elif ground.has(tile):
				var image: Array = ground[tile]
				_draw_image(int(image[0]), Vector2(x * 16 + int(image[1]), y * 16 + int(image[2])))
	_draw_ground_overlay()
	_draw_unit_shadows()
	if show_units:
		for item: Dictionary in _depth_items:
			if item["kind"] == "unit": _draw_unit(item["unit"])
	for y in range(height):
		for x in range(width):
			match int(current_map["source_tile_ids"][y][x]):
				1: _draw_image(66, Vector2((x + 1) * 16 - textures[66].get_width(), (y - 1) * 16))
				2: _draw_image(67, Vector2(x, y - 1) * 16)
				8: _draw_image(68, Vector2(x - 1, y) * 16)
				7: _draw_image(73, Vector2((x - 1) * 16, (y + 1) * 16 - textures[73].get_height()))
	_draw_grid(width, height)
	_draw_selection()
	_draw_foreground_overlay()
	draw_set_transform(Vector2.ZERO)
	_draw_battle_hud()


func _draw_selection() -> void:
	if show_debug_markers: super._draw_selection()


func _draw_unit(record: Array) -> void:
	if record.size() > RenderField.PETRIFIED and bool(record[RenderField.PETRIFIED]) and not bool(record[RenderField.DEAD]):
		var pose: Dictionary = sprite_pose(record)
		var id: int = int(pose["image"])
		if not _stone_textures.has(id):
			var pixels: Image = textures[id].get_image()
			pixels.convert(Image.FORMAT_RGBA8)
			for y in range(pixels.get_height()):
				for x in range(pixels.get_width()):
					var c: Color = pixels.get_pixel(x, y)
					var gray: float = minf(1, (c.r + c.g + c.b) / 3 + 1.0 / 15)
					pixels.set_pixel(x, y, Color(gray, gray, gray, c.a))
			_stone_textures[id] = ImageTexture.create_from_image(pixels)
		var original: Texture2D = textures[id]
		textures[id] = _stone_textures[id]
		super._draw_unit(record)
		textures[id] = original
	else: super._draw_unit(record)


func focus_arena(bounds: Rect2i) -> void:
	camera_follow = false
	camera_follow_changed.emit(false)
	var full_pixels := Vector2(float(current_map["width"]), float(current_map["height"])) * 16
	var base: float = maxf(0.1, minf((size.x - 48) / full_pixels.x, (size.y - 48) / full_pixels.y))
	var scale: float = minf((size.x - 64) / (bounds.size.x * 16.0), (size.y - 80) / (bounds.size.y * 16.0))
	zoom_factor = clampf(scale / base, 0.5, 8)
	pan = size * 0.5 - (Vector2(bounds.position) + Vector2(bounds.size) * 0.5) * 16 * scale - (size - full_pixels * scale) * 0.5
	queue_redraw()


func follow_hero(immediate: bool = false) -> void:
	camera_follow = true
	zoom_factor = maxf(zoom_factor, 2.5)
	if immediate or not _camera_initialized:
		_camera_point = follow_point
		_camera_initialized = true
	camera_follow_changed.emit(true)
	queue_redraw()


func fit_map() -> void:
	camera_follow = false
	camera_follow_changed.emit(false)
	super.fit_map()


func _process(delta: float) -> void:
	super._process(delta)
	if camera_follow and session != null:
		if not _camera_initialized:
			_camera_point = follow_point
			_camera_initialized = true
		_camera_point = _camera_point.lerp(follow_point, 1.0 - exp(-12.0 * delta))
		queue_redraw()
	_update_enemy_hint(get_local_mouse_position())


func _update_transform() -> void:
	super._update_transform()
	if not camera_follow or session == null:
		map_origin += shake_offset
		return
	var map_pixels := Vector2(float(current_map["width"]), float(current_map["height"])) * 16 * pixel_scale
	var desired: Vector2 = size * 0.5 - _camera_point * pixel_scale
	for axis in range(2):
		desired[axis] = clampf(desired[axis], size[axis] - map_pixels[axis], 0) if map_pixels[axis] > size[axis] else (size[axis] - map_pixels[axis]) * 0.5
	map_origin = desired.floor()
	pan = map_origin - (size - map_pixels) * 0.5
	map_origin += shake_offset


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and not show_debug_markers:
		accept_event()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and battle != null and battle.can_input():
		for i in range(session.party.size()):
			if _portrait_rect(i).has_point(event.position):
				battle.select(session.party[i].instance_id)
				zone_action = &"none"
				accept_event()
				return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_update_transform()
		camera_follow = false
		camera_follow_changed.emit(false)
	super._gui_input(event)


func _draw_ground_overlay() -> void:
	if session == null:
		super._draw_ground_overlay()
		return
	for point: Vector2 in combat_feedback.meteor_shards():
		draw_texture(textures[ImageId.STONE_SHARDS], point)
	for pickup: Dictionary in session.pickups():
		var position: Array = pickup["position_pixels"]
		draw_texture(textures[Ids.EconomyImage.PICKUP], Vector2(float(position[0]) + 2, float(position[1]) + 3))
	for y in range(session.collision.height):
		for x in range(session.collision.width):
			var cell := Vector2i(x, y)
			var rect := Rect2(Vector2(cell) * 16, Vector2.ONE * 16)
			if show_collision and session.collision.is_terrain_blocked(cell):
				draw_rect(rect, Color(0.95, 0.2, 0.2, 0.40))
			elif show_reachable and (battle == null or not battle.active) and session.pathfinder.distance(cell) < 1000:
				draw_rect(rect.grow(-1), Color(0.2, 0.9, 0.6, 0.16))
			var zone: int = zone_image(cell)
			if zone >= 0: draw_texture(textures[zone], rect.position)
	if not show_debug_markers: return
	var points := PackedVector2Array([follow_point])
	for cell in route_cells:
		points.append(Vector2(cell) * 16 + Vector2.ONE * 8)
	if points.size() > 1:
		var color := Color("77ffd2") if route_exact else Color("ffc76c")
		draw_polyline(points, color, 2.0 / pixel_scale)
		for i in range(1, points.size()):
			draw_circle(points[i], 2.0, color)


func _draw_foreground_overlay() -> void:
	if session == null:
		super._draw_foreground_overlay()
		return
	if battle != null and battle.active:
		var pixels := Vector2(session.collision.width, session.collision.height) * 16
		var rect := Rect2(Vector2(battle.arena.position) * 16, Vector2(battle.arena.size) * 16)
		var shade := Color(0.02, 0.04, 0.05, 0.55)
		draw_rect(Rect2(Vector2.ZERO, Vector2(pixels.x, rect.position.y)), shade)
		draw_rect(Rect2(Vector2(0, rect.end.y), Vector2(pixels.x, pixels.y - rect.end.y)), shade)
		draw_rect(Rect2(Vector2(0, rect.position.y), Vector2(rect.position.x, rect.size.y)), shade)
		draw_rect(Rect2(Vector2(rect.end.x, rect.position.y), Vector2(pixels.x - rect.end.x, rect.size.y)), shade)

		for id: int in battle.participants:
			var actor = battle.unit(id)
			var point: Vector2 = actor.previous_position.lerp(actor.position_pixels, session_view_alpha)
			if id == battle.selected_id and not actor.dead:
				var extent := Vector2(32, 16) if actor.footprint.x == 1 else Vector2(actor.footprint) * Vector2(16, 8)
				for arc in range(3):
					var line := PackedVector2Array()
					for step in range(9):
						var angle: float = combat_feedback.clock * 2.25 + deg_to_rad(arc * 120 + step * 7.5)
						line.append(point + Vector2(cos(angle), sin(angle)) * extent * 0.5)
					draw_polyline(line, Color.GREEN, 1.0)
			if not actor.dead:
				var icons: Array[int] = []
				for effect in actor.effects:
					var icon: int = int(effect["icon"])
					if icon >= 0 and icon not in icons: icons.append(icon)
				for i in range(icons.size()):
					var icon: int = icons[i]
					var sprite: Dictionary = Ids.status_icon(icon)
					var destination := Rect2(point + Vector2(i * 9 - 12, -54), Vector2(9, 9))
					if int(sprite["atlas"]) == 189 and ui_icons != null: draw_texture_rect(ui_icons.spell(int(sprite["frame"])), destination, false)
					else: draw_texture_rect_region(textures[sprite["atlas"]], destination, Rect2(int(sprite["frame"]) * 21, 0, 21, 20))
		for hazard: Dictionary in battle.hazards:
			var point: Vector2 = Vector2(hazard["cell"]) * 16 + Vector2(8, 8)
			var id: int = ImageId.FIRE_WALL if int(hazard["spell"]) == Spell.FIRE_WALL else ImageId.MIASMA
			if textures.has(id): draw_texture_rect(textures[id], Rect2(point - Vector2(12, 20), Vector2(24, 24)), false)
		if not battle.current.is_empty() and battle.current.get("phase") == "flight":
			var command: Dictionary = battle.current
			var from: Vector2 = command["flight_from"]
			var to: Vector2 = command["flight_to"]
			var progress: float = clampf((float(command["clock"]) + session_view_alpha) / float(command["flight_ticks"]), 0, 1)
			var arrow: Vector2 = from.lerp(to, progress)
			var direction: Vector2 = (to - from).normalized()
			if command.get("action") == "cast":
				var spell: int = int(command["spell"])
				var image_id: int = Ids.SPELL_EFFECT_IMAGES.get(spell, -1)
				var target: Vector2 = arrow if spell in [Spell.FIRE_ARROW, Spell.SPARK, Spell.FIREBALL] else to
				var frame: int = SpellVisuals.projectile_frame(direction)
				if spell == Spell.METEOR:
					var point: Vector2 = SpellVisuals.meteor_position(command["cell"], float(command["clock"]) + session_view_alpha)
					draw_texture(textures[ImageId.METEOR], point)
				elif spell == Spell.FIRE_ARROW:
					if _fire_glow == null: _fire_glow = SpellVisuals.fire_glow()
					var clock: float = float(command["clock"]) + session_view_alpha
					for spark: Dictionary in SpellVisuals.fire_sparks(from, to, clock, int(command["flight_ticks"])):
						draw_rect(Rect2(spark["point"], Vector2.ONE * int(spark["size"])), Color(1, 0.85, 0.4, float(spark["alpha"])))
					draw_texture(_fire_glow, (target - Vector2(20, 20)).floor())
					draw_texture_rect_region(textures[ImageId.FIRE_PROJECTILE], Rect2((target - Vector2(10, 10)).floor(), Vector2(20, 20)), Rect2(frame * 20, 0, 20, 20))
				elif spell == Spell.LIGHTNING:
					var elapsed: float = (float(command["clock"]) + session_view_alpha) * 0.062
					_draw_lightning(command["cell"], elapsed)
				elif spell == Spell.BLESS:
					var elapsed: float = (float(command["clock"]) + session_view_alpha) * 0.062
					var recipient = battle.actor_at(command["cell"])
					if recipient != null: _draw_blessing(recipient.position_pixels, elapsed)
				elif spell == Spell.FROST:
					if _ice_glow == null: _ice_glow = SpellVisuals.ice_glow()
					draw_texture_rect(_ice_glow, Rect2((target - Vector2(24, 40)).floor(), Vector2(48, 56)), false)
					draw_texture_rect(textures[ImageId.FROST_PILLAR], Rect2(target - Vector2(12, 24), Vector2(24, 32)), false)
				elif image_id in [ImageId.FIRE_PROJECTILE, ImageId.SPARK_PROJECTILE]: draw_texture_rect_region(textures[image_id], Rect2(target - Vector2(10, 10), Vector2(20, 20)), Rect2(frame * 20, 0, 20, 20))
				elif image_id >= 0: draw_texture_rect(textures[image_id], Rect2(target - Vector2(12, 24), Vector2(24, 32)), false)
				elif spell == Spell.HEAL:
					# u/v use procedural green crosses rather than a sprite sheet.
					for i in range(4):
						var cross := target + Vector2((i - 1.5) * 7, -progress * 24 + sin(i + progress * TAU) * 3)
						draw_rect(Rect2(cross - Vector2(1, 3), Vector2(2, 6)), Color(0.2, 1, 0.3, 1 - progress * 0.5))
						draw_rect(Rect2(cross - Vector2(3, 1), Vector2(6, 2)), Color(0.2, 1, 0.3, 1 - progress * 0.5))
				else:
					var radius: float = 24 * (1 - progress if spell == Spell.SLOW else progress)
					for i in range(8): draw_circle(target + Vector2.RIGHT.rotated(i * TAU / 8 + progress * TAU) * radius, 2, Color("b1cfff"))
			else:
				draw_line(arrow - direction * 8, arrow, Color("ffe8a5"), 1.2)
				draw_line(arrow - direction.rotated(0.5) * 3, arrow, Color("ffe8a5"), 1.2)
				draw_line(arrow - direction.rotated(-0.5) * 3, arrow, Color("ffe8a5"), 1.2)
		_draw_weather()
		var font: Font = get_theme_default_font()
		for popup: Dictionary in combat_feedback.records():
			var text: String = popup["text"]
			var point: Vector2 = popup["point"]
			point.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x * 0.5
			draw_string(font, point.floor() + Vector2(0, font.get_ascent(13)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.GREEN)

		return
	_draw_weather()
	if not show_debug_markers: return
	# Debug markers remain visible when a canopy covers a party sprite.
	draw_arc(follow_point, 9, 0, TAU, 24, Color("ffe8a5"), 1.5 / pixel_scale)
	for index in range(1, session.party.size()):
		var actor = session.party[index]
		var point: Vector2 = actor.previous_position.lerp(actor.position_pixels, session_view_alpha)
		draw_arc(point, 8, 0, TAU, 24, Color("77ffd2"), 1.0 / pixel_scale)


func _draw_lightning(cell: Vector2i, elapsed: float) -> void:
	# i.a(Graphics): two unscaled image-192 copies, revealed top to bottom
	# in half-image steps every 100 ms. Anchor to the cell's feet, not flight_to.
	var texture: Texture2D = textures[ImageId.LIGHTNING]
	var width: int = texture.get_width()
	var height: int = texture.get_height()
	var point := Vector2(cell * 16 + Vector2i(8, 8))
	var top: float = point.y - height * 2
	var revealed: int = (int(floor((elapsed + 0.000000001) / 0.1)) + 1) * int(height / 2.0)
	for index in range(2):
		var visible_height: int = clampi(revealed - index * height, 0, height)
		if visible_height == 0: continue
		var position := Vector2(point.x - int(width / 2.0) + 12 - 6 * index, top + index * height)
		var region := Rect2(0, 0, width, visible_height)
		draw_texture_rect_region(texture, Rect2(position, region.size), region)


func _draw_blessing(point: Vector2, elapsed: float) -> void:
	# x.a(Graphics): a 48x32 foot section and repeated top 48x23 strips.
	# m.a(image, 0x7fff) retains 7/15 alpha in the original ARGB4444 pixels.
	var texture: Texture2D = textures[ImageId.BLESS_BEAM]
	var base := (point - Vector2(24, 23)).floor()
	var bounds := Rect2(-map_origin / pixel_scale, size / pixel_scale)
	var clip: Rect2 = bounds
	if elapsed < 1.0:
		var step: int = int(elapsed / 0.1)
		clip = clip.intersection(Rect2(base.x + 25 - step * 5, bounds.position.y, step * 10, bounds.size.y))
	elif elapsed > 1.5:
		var step: int = int((elapsed - 1.5) / 0.1)
		clip = clip.intersection(Rect2(base.x + step * 5, bounds.position.y, maxi(0, 48 - step * 10), bounds.size.y))
	var y: float = base.y
	var section_height: int = 32
	while y + section_height > bounds.position.y:
		var section := Rect2(base.x, y, 48, section_height)
		var visible_section: Rect2 = section.intersection(clip)
		if visible_section.has_area():
			draw_texture_rect_region(texture, visible_section, Rect2(visible_section.position - section.position, visible_section.size), Color(1, 1, 1, 7.0 / 15.0))
		y -= 23
		section_height = 23


func zone_image(cell: Vector2i) -> int:
	if battle == null or not battle.can_input() or battle.selected_id < 0 or zone_action == &"none" or not battle.arena.has_point(cell): return -1
	var actor = battle.unit(battle.selected_id)
	if zone_action == &"ranged":
		var distance: int = absi(cell.x - actor.cell.x) + absi(cell.y - actor.cell.y)
		return 202 if distance <= actor.stats[Stat.ATTACK_RANGE] and not session.collision.is_terrain_blocked(cell) else -1
	var cost: int = battle.pathfinder.distance(cell)
	var ap: int = actor.stats[Stat.ACTION_POINTS]
	if cost < ap: return 202
	if cost == ap: return 203
	return -1

func _draw_weather() -> void:
	if session == null or session.rain_remaining <= 0 or session.rain_layers <= 0: return
	var visible_world := Rect2(-map_origin / pixel_scale, size / pixel_scale)
	for drop: Dictionary in Rain.samples(visible_world, session.rain_elapsed, session.rain_layers):
		var point: Vector2 = drop["point"]
		if not Rect2(Vector2.ZERO, Vector2(session.collision.width, session.collision.height) * 16).has_point(point): continue
		if drop["splash"]:
			if session.collision.is_terrain_blocked(Vector2i(point / 16)): draw_texture(textures[63], point)
		else: draw_line(point, drop["end"], Color(1, 1, 1, 0.85), 1)

func _portrait_rect(index: int) -> Rect2:
	return Rect2(28, 62 + index * 58, 40, 52)

func actor_portrait_texture(actor) -> Texture2D:
	if ui_icons != null: return ui_icons.actor_portrait(actor.unit_type, session.definitions)
	return textures[int(session.definitions["portrait_images"][actor.unit_type])]

func _draw_actor_portrait(actor, bounds: Rect2, tint: Color = Color.WHITE) -> void:
	var texture: Texture2D = actor_portrait_texture(actor)
	var destination: Rect2 = preload("res://scripts/gameplay/ui_icons.gd").fit_rect(texture, bounds)
	draw_texture_rect(texture, destination, false, tint)

func battle_hud_actor():
	var focused = battle.unit(battle.selected_id)
	# On the enemy side this panel identifies the acting enemy. Hit feedback
	# describes its victim and must not replace the attacker's identity.
	if battle.current_side == Side.HOSTILE: return focused
	if not battle.feedback.is_empty() and battle.tick_count - int(battle.feedback["tick"]) < 20:
		focused = battle.unit(int(battle.feedback["target"]))
	return focused

func _draw_battle_hud() -> void:
	if ui_frame != null: ui_frame.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	if session == null or battle == null or not battle.active or session.mode != &"battle" or battle.outcome != &"": return
	var font: Font = get_theme_default_font()
	draw_string(font, Vector2(28, 48), "Ход:%d" % battle.round_number, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.GREEN)
	for i in range(session.party.size()):
		var actor = session.party[i]
		var rect: Rect2 = _portrait_rect(i)
		_draw_actor_portrait(actor, rect, Color(0.4, 0.4, 0.4) if actor.dead else Color.WHITE)
		if actor.instance_id == battle.selected_id: draw_rect(rect.grow(2), Color.GREEN, false, 2)
		var ap: float = float(actor.stats[Stat.HP]) / maxi(1, actor.stats[Stat.MAX_HP])
		draw_rect(Rect2(rect.end + Vector2(4, -rect.size.y * ap), Vector2(3, rect.size.y * ap)), Color.GREEN)
		if actor.unit_type not in [Ids.UnitKind.TAGRIM, Ids.UnitKind.LI] and actor.stats[Stat.MAX_MANA] > 0:
			var mana: float = float(actor.stats[Stat.MANA]) / actor.stats[Stat.MAX_MANA]
			draw_rect(Rect2(rect.end + Vector2(9, -rect.size.y), Vector2(3, rect.size.y)), Color("000032"))
			draw_rect(Rect2(rect.end + Vector2(9, -rect.size.y * mana), Vector2(3, rect.size.y * mana)), Color.BLUE)
	var focused = battle_hud_actor()
	if focused != null:
		var bottom: float = hud_obstruction.get_global_rect().position.y - global_position.y if hud_obstruction != null and hud_obstruction.visible else size.y - 20
		var point := Vector2(size.x * 0.25, bottom - 80)
		_draw_actor_portrait(focused, Rect2(point, Vector2(40, 52)))
		var bar := Rect2(point + Vector2(72, 23), Vector2(150, 12))
		draw_rect(bar, Color("003200"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * focused.stats[Stat.HP] / float(maxi(1, focused.stats[Stat.MAX_HP])), bar.size.y)), Color.GREEN)
		if focused.unit_type not in [Ids.UnitKind.TAGRIM, Ids.UnitKind.LI] and focused.stats[Stat.MAX_MANA] > 0:
			bar.position.y += 17
			draw_rect(bar, Color("000032"))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * focused.stats[Stat.MANA] / float(focused.stats[Stat.MAX_MANA]), bar.size.y)), Color.BLUE)
	if battle.current_side == Side.HOSTILE:
		var text: String = "Ход противника"
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		draw_string(font, Vector2((size.x - width) * 0.5, size.y * 0.7), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.GREEN)
