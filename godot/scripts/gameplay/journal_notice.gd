extends PanelContainer
## Observe quest state rather than one source of changes: story and tavern
## both write to the journal. Loading a session establishes a silent baseline.

const DURATION: float = 4.0
var game
var previous: Array = []
var remaining: float = 0.0
var caption: Label

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50
	visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color("241d16ee")
	style.border_color = Color("bba16c")
	style.set_border_width_all(2)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)
	caption = Label.new()
	caption.text = "Журнал обновлён"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_size_override("font_size", 24)
	caption.add_theme_color_override("font_color", Color("f2d99c"))
	add_child(caption)

func configure(session) -> void:
	game = session
	previous = game.quests.duplicate()
	remaining = 0.0
	hide()

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if game == null: return
	remaining = maxf(0.0, remaining - delta)
	if previous != game.quests:
		previous = game.quests.duplicate()
		remaining = DURATION
	visible = remaining > 0.0
