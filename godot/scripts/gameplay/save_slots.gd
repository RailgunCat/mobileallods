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

func _ready() -> void:
	super._ready()
	hd_screen = preload("res://scripts/gameplay/hd_menu_screen.gd").new()
	hd_screen.kind = &"slots"
	hd_screen.controller = self
	add_child(hd_screen)

func open(saves, textures: Dictionary, metadata: Dictionary, write_save: bool) -> void:
	service = saves
	saving = write_save
	selected = 0
	message = ""
	setup(textures, metadata)
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

func slot_label(slot: int) -> String:
	if slot == service.AUTOSAVE_SLOT:
		return "Автосохранение" if service.exists(slot) else "Автосохранение (пусто)"
	return "%d. %s" % [slot + 1, "Сохранённая игра" if service.exists(slot) else "Пусто"]

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
		write(slot_label(slot), Vector2(45, ROW_TOP + 3 + slot * ROW_STEP))
	selection_arrow(Vector2(22, ROW_TOP + 1 + selected * ROW_STEP))
	var lines: PackedStringArray = wrap_lines(message, 200)
	for i in range(mini(3, lines.size())): write(lines[i], Vector2(20, 245 + i * 14))
	footer(true, true)
	finish_draw()

func _gui_input(event: InputEvent) -> void:
	if hd_screen.active(): return
	super._gui_input(event)
