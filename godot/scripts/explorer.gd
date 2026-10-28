extends Control
## Inspect original art and source spawns; campaign state is not simulated yet.

const MapView = preload("res://scripts/gameplay/game_map_view.gd")
const Dungeon = preload("res://scripts/gameplay/dungeon_generator.gd")
var gameplay: Dictionary
var dungeon_cache: Dictionary = {}
const SIDEBAR: float = 290.0
var world: Dictionary = {}
var current_map: Dictionary = {}
var current_scene: Dictionary = {}
var map_view: MapView
var map_picker: OptionButton
var info: Label
var status: Label
var zoom_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_interface()
	if not FileAccess.file_exists("res://data/legacy/graphics.json"):
		info.text = "Сначала экспортируйте ресурсы:\npython tools/allods_tool.py export-godot analysis/extracted godot/data"
		if "--smoke-test" in OS.get_cmdline_user_args():
			push_error("Original artwork export is missing")
			get_tree().quit(1)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var render_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/legacy/graphics.json"))
	if not parsed is Dictionary or not render_data is Dictionary:
		info.text = "Не удалось прочитать данные карт. Повторите экспорт."
		if "--smoke-test" in OS.get_cmdline_user_args():
			push_error("Invalid original artwork data")
			get_tree().quit(1)
		return
	world = parsed
	map_view.configure(world, render_data)
	for item: Dictionary in world["maps"]:
		map_picker.add_item("Карта %s · %d×%d" % [item["name"], int(item["width"]), int(item["height"])])
	gameplay = JSON.parse_string(FileAccess.get_file_as_string("res://data/legacy/gameplay.json"))
	for dungeon in range(12): map_picker.add_item("Подземелье %d%s" % [dungeon + 1, " · дракон" if dungeon == 11 else ""])
	var initial_index: int = 0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--preview-map="):
			for i in range(world["maps"].size()):
				if str(world["maps"][i]["name"]) == argument.trim_prefix("--preview-map="):
					initial_index = i
	select_map(initial_index)
	map_picker.select(initial_index)
	if "--smoke-test" in OS.get_cmdline_user_args():
		call_deferred("smoke_test")
	elif "--capture-previews" in OS.get_cmdline_user_args():
		call_deferred("capture_previews")


func _label(text: String, muted: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 242
	if muted:
		label.modulate = Color("a0b7bd")
	return label


func _toggle(column: VBoxContainer, text: String, property: StringName, enabled: bool) -> void:
	var toggle := CheckButton.new()
	toggle.text = text
	toggle.button_pressed = enabled
	toggle.toggled.connect(func(value: bool): map_view.set(property, value); map_view.queue_redraw())
	column.add_child(toggle)


func _build_interface() -> void:
	var panel := ColorRect.new()
	panel.color = Color("18272d")
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_right = SIDEBAR
	map_view = MapView.new()
	map_view.show_debug_markers = true
	map_view.name = "LegacyMapView"
	add_child(map_view)
	map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_view.offset_left = SIDEBAR
	map_view.cell_selected.connect(_inspect_cell)
	map_view.zoom_changed.connect(func(value: float): zoom_label.text = "Масштаб: %.0f%%" % (value * 100))
	var column := VBoxContainer.new()
	column.position = Vector2(24, 24)
	column.size = Vector2(242, 740)
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	var title: Label = _label("АЛЛОДЫ\nПросмотр карт")
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)
	column.add_child(_label("Оригинальная графика · Java ME", true))
	var play_button := Button.new()
	play_button.text = "Игровой режим · этап 1"
	play_button.pressed.connect(func(): get_tree().change_scene_to_file("res://gameplay.tscn"))
	column.add_child(play_button)
	map_picker = OptionButton.new()
	map_picker.item_selected.connect(select_map)
	column.add_child(map_picker)
	_toggle(column, "Персонажи", &"show_units", true)
	_toggle(column, "Зоны событий", &"show_triggers", false)
	_toggle(column, "Сетка", &"show_grid", false)
	_toggle(column, "Анимация", &"animate_water", true)
	var fit_button := Button.new()
	fit_button.text = "Показать карту целиком"
	fit_button.pressed.connect(map_view.fit_map)
	column.add_child(fit_button)
	zoom_label = _label("Масштаб: 100%", true)
	column.add_child(zoom_label)
	info = _label("")
	column.add_child(info)
	status = _label("Нажмите на клетку для просмотра.", true)
	column.add_child(status)
	column.add_child(_label("Колесо — масштаб\nПКМ / СКМ — перемещение\n\nПоказаны исходные спавны.\nСценарии ещё не выполняются.", true))


func select_map(index: int) -> void:
	if index >= world["maps"].size():
		var dungeon: int = index - world["maps"].size()
		if not dungeon_cache.has(dungeon): dungeon_cache[dungeon] = Dungeon.new().generate(-dungeon - 1, 0, 20261027, gameplay, gameplay["new_game"]["flags"]["c"])
		current_map = dungeon_cache[dungeon]["map"]
		current_scene = dungeon_cache[dungeon]["scene"]
		map_view.select_map(current_map, current_scene)
		info.text = "%d × %d клеток\nПодземелье %d · seed 20261027\n%d персонажей · %d сценариев" % [current_map["width"], current_map["height"], dungeon + 1, current_scene["units"].size(), current_scene["scripts"].size()]
		return
	current_map = world["maps"][index]
	current_scene = {}
	var map_name: String = current_map["name"]
	if map_name.is_valid_int():
		var scene_index: int = int(map_name) - 1
		if scene_index >= 0 and scene_index < world["scenes"].size():
			current_scene = world["scenes"][scene_index]
	map_view.select_map(current_map, current_scene)
	info.text = "%d × %d клеток\n%d персонажей · %d сценариев" % [int(current_map["width"]), int(current_map["height"]), current_scene.get("units", []).size(), current_scene.get("scripts", []).size()]
	status.text = "Карта %s\nОригинальные спрайты и объекты" % map_name


func _inspect_cell(cell: Vector2i, source_id: int) -> void:
	status.text = "Клетка (%d, %d)\nТайл: %d · изображение: #%d" % [cell.x, cell.y, source_id, int(world["constants"]["tile_image_ids"][source_id])]
	if current_map.get("dungeon", false): status.text = "Клетка (%d, %d) · тайл подземелья %d" % [cell.x, cell.y, source_id]
	var matches: int = 0
	for unit: Array in current_scene.get("units", []):
		if Vector2i(floori(float(unit[1]) / 16.0), floori(float(unit[2]) / 16.0)) == cell:
			matches += 1
			if matches <= 2:
				status.text += "\n%s · спавн %d" % [world["constants"]["unit_names"][int(unit[3])], int(unit[0])]
	if matches > 2:
		status.text += "\nЕщё спавнов: %d" % (matches - 2)


func _assets_valid() -> bool:
	if map_view.textures.size() != 279:
		push_error("Expected all 279 recovered PNGs")
		return false
	for id: int in map_view.textures:
		var texture: Texture2D = map_view.textures[id]
		var metadata: Dictionary = map_view.graphics["images"][str(id)]
		if texture == null or texture.get_width() != int(metadata["width"]) or texture.get_height() != int(metadata["height"]):
			push_error("Invalid original texture %d" % id)
			return false
	return true


func smoke_test() -> void:
	if not _assets_valid():
		get_tree().quit(1)
		return
	map_view.show_triggers = true
	map_view.show_grid = true
	for i in range(world["maps"].size()):
		select_map(i)
		await get_tree().process_frame
		await get_tree().process_frame
		var click := InputEventMouseButton.new()
		click.position = map_view.position + map_view.cell_center(Vector2i.ZERO)
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		get_viewport().push_input(click, true)
		if map_view.selection != Vector2i.ZERO:
			push_error("Cell inspection input failed for map %s" % current_map["name"])
			get_tree().quit(1)
			return
		var wheel := InputEventMouseButton.new()
		wheel.position = map_view.position + map_view.size * 0.5
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		get_viewport().push_input(wheel, true)
		if map_view.zoom_factor <= 1.0:
			push_error("Map zoom input failed")
			get_tree().quit(1)
			return
		var before_pan: Vector2 = map_view.pan
		var drag := InputEventMouseButton.new()
		drag.position = wheel.position
		drag.button_index = MOUSE_BUTTON_MIDDLE
		drag.pressed = true
		get_viewport().push_input(drag, true)
		var motion := InputEventMouseMotion.new()
		motion.position = wheel.position + Vector2(24, 12)
		motion.relative = Vector2(24, 12)
		motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
		get_viewport().push_input(motion, true)
		drag.position = motion.position
		drag.pressed = false
		get_viewport().push_input(drag, true)
		if not map_view.pan.is_equal_approx(before_pan + motion.relative):
			push_error("Map pan input failed")
			get_tree().quit(1)
			return
	for dungeon in range(12):
		select_map(world["maps"].size() + dungeon)
		await get_tree().process_frame
		if not current_map.get("dungeon", false) or current_scene["units"].is_empty():
			push_error("Dungeon preview missing: %d" % dungeon)
			get_tree().quit(1)
			return
	select_map(world["maps"].size() + 11)
	if int(current_scene["units"][0][3]) != 7:
		push_error("Final preview has no dragon")
		get_tree().quit(1)
		return
	print("PASS: 279 original textures; 18 maps + 12 dungeon previews with legacy art, spawn sprites, layers, cell input, zoom and pan")
	get_tree().quit()


func capture_previews() -> void:
	if not _assets_valid():
		get_tree().quit(1)
		return
	var directory: String = ProjectSettings.globalize_path("res://../build/legacy-previews")
	DirAccess.make_dir_recursive_absolute(directory)
	for name: String in ["1", "7", "12", "101", "dungeon-12"]:
		if name == "dungeon-12":
			select_map(world["maps"].size() + 11)
			map_picker.select(world["maps"].size() + 11)
		for i in range(world["maps"].size()):
			if str(world["maps"][i]["name"]) == name:
				select_map(i)
				map_picker.select(i)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var error: Error = get_viewport().get_texture().get_image().save_png(directory.path_join("map-%s.png" % name))
		if error != OK:
			push_error("Failed to save map preview: %s" % error)
			get_tree().quit(1)
			return
	print("PASS: rendered map previews saved to " + directory)
	get_tree().quit()
