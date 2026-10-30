extends "res://scripts/gameplay/legacy_ui_screen.gd"
signal selected_slot(slot: int)
signal closed
const ROW_TOP: int = 60
const ROW_STEP: int = 28
var service
var saving: bool = false
var selected: int = 0
var message: String = ""
var hd_screen: Control
var slot_details: Array[Dictionary] = []
var location_names: Array = []

func _ready() -> void:
	super._ready()
	hd_screen = preload("res://scripts/gameplay/hd_menu_screen.gd").new()
	hd_screen.kind = &"slots"
	hd_screen.controller = self
	add_child(hd_screen)

func open(saves, textures: Dictionary, metadata: Dictionary, write_save: bool) -> void:
	service = saves
	location_names = metadata["travel"]["location_names"]
	saving = write_save
	selected = 0
	message = ""
	setup(textures, metadata)
	refresh_slots()
	visible = true
	hd_screen.reset()
	clear_regions()
	for slot in range(slot_count()):
		region(Rect2(20, ROW_TOP + slot * ROW_STEP, 200, ROW_STEP - 2), func():
			selected = slot
			confirm()
		)
	region(Rect2(9, 294, 100, 25), confirm)
	region(Rect2(130, 294, 100, 25), back)
	queue_redraw()

func slot_count() -> int:
	return service.SLOT_COUNT if saving else service.TOTAL_SLOT_COUNT

func refresh_slots() -> void:
	slot_details.clear()
	for slot in range(service.TOTAL_SLOT_COUNT): slot_details.append(service.slot_info(slot))
	queue_redraw()
	if hd_screen != null: hd_screen.queue_redraw()

func slot_title(slot: int, compact: bool = false) -> String:
	var prefix: String = ("Авто: " if compact else "Автосохранение: ") if slot == service.AUTOSAVE_SLOT else "%d. " % (slot + 1)
	var info: Dictionary = slot_details[slot]
	if info.is_empty(): return prefix + "Пусто"
	if info.get("invalid", false): return prefix + "Повреждено"
	var local_time: int = int(info["saved_at"]) + int(Time.get_time_zone_from_system()["bias"]) * 60
	var date: Dictionary = Time.get_datetime_dict_from_unix_time(local_time)
	return prefix + "%02d.%02d.%04d %02d:%02d" % [date.day, date.month, date.year, date.hour, date.minute]

func slot_location(slot: int) -> String:
	var info: Dictionary = slot_details[slot]
	if info.is_empty() or info.get("invalid", false): return ""
	var location: int = int(info["location_id"])
	if location < 0: return "Подземелье %d" % -location
	return "%d. %s" % [location + 1, location_names[location + 1]]

func slot_label(slot: int) -> String:
	var location: String = slot_location(slot)
	return slot_title(slot) + (" · " + location if not location.is_empty() else "")

func navigate(step: int) -> void:
	selected = posmod(selected + step, slot_count())
	message = ""
	queue_redraw()

func confirm() -> void:
	selected_slot.emit(selected)

func back() -> void:
	hide()
	closed.emit()

func _draw() -> void:
	if images.is_empty(): return
	if hd_screen.active(): return
	begin_draw()
	write("Сохранить игру" if saving else "Загрузить игру", Vector2(120, 28), HORIZONTAL_ALIGNMENT_CENTER)
	for slot in range(slot_count()):
		write(slot_title(slot, true), Vector2(40, ROW_TOP + slot * ROW_STEP))
		write(slot_location(slot), Vector2(40, ROW_TOP + 13 + slot * ROW_STEP))
	selection_arrow(Vector2(22, ROW_TOP + 1 + selected * ROW_STEP))
	var lines: PackedStringArray = wrap_lines(message, 200)
	for i in range(mini(3, lines.size())): write(lines[i], Vector2(20, 245 + i * 14))
	footer(true, true)
	finish_draw()

func _gui_input(event: InputEvent) -> void:
	if hd_screen.active(): return
	super._gui_input(event)
