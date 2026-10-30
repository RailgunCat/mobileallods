extends Control
signal finished
const Credits = preload("res://scripts/gameplay/credits.gd")
const DESIGN := Vector2(1280, 800)
const SPEED: float = 38.0
var travel: float = 0
var content_height: float = 0
var text: String = ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	text = "АЛЛОДЫ\n\nКонец игры\n\nОригинальная мобильная игра" + Credits.TEXT.get_slice("Оригинальная мобильная игра", 1).get_slice("Дополнительные материалы", 0) + "\nФанатское восстановление на Godot\n\n" + Credits.PORT_AUTHORS + "\n\nСпасибо за игру!"
	content_height = text.split("\n").size() * 42.0
	hide()

func open() -> void:
	travel = 0
	show()
	queue_redraw()

func advance(delta: float) -> void:
	if not visible: return
	travel += maxf(0, delta) * SPEED
	queue_redraw()
	if travel > DESIGN.y * 0.7 + content_height + 80: finish()

func finish() -> void:
	if not visible: return
	hide()
	finished.emit()

func _process(delta: float) -> void:
	advance(delta)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var scale: float = minf(size.x / DESIGN.x, size.y / DESIGN.y)
	var origin: Vector2 = (size - DESIGN * scale) * 0.5
	draw_set_transform(origin, 0, Vector2.ONE * scale)
	var font: Font = get_theme_default_font()
	var lines: PackedStringArray = text.split("\n")
	for index in range(lines.size()):
		var y: float = DESIGN.y * 0.7 + index * 42 - travel
		if y < -40 or y > DESIGN.y - 50: continue
		var heading: bool = index < 3
		draw_string(font, Vector2(100, y), lines[index], HORIZONTAL_ALIGNMENT_CENTER, 1080, 34 if heading else 26, Color("f2c973") if heading else Color("d5dfcd"))
	draw_string(font, Vector2(40, 774), "Enter / Esc — в меню", HORIZONTAL_ALIGNMENT_CENTER, 1200, 16, Color("92a08b"))
	draw_set_transform(Vector2.ZERO)
