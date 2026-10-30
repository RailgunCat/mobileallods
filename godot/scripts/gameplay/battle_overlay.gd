extends Control
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const ImageId = Ids.ImageId
const UiTheme = preload("res://scripts/gameplay/legacy_theme.gd")
## Presentation owns no combat rules. The caller pauses the simulation in intro.
signal intro_finished
signal continue_requested
signal restart_requested
var phase: StringName = &""
var elapsed: float = 0
var textures: Dictionary
var heading: Label
var body: Label
var creature: TextureRect
var footer: Button
var monochrome: ColorRect
var progress: ProgressBar
var body_scroll: ScrollContainer
var ui_icons
var hd_screen: Control
var border_panel: PanelContainer
var reward: Dictionary = {}
var reward_names: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	monochrome = UiTheme.world_shade(0.6)
	add_child(monochrome)
	var border := PanelContainer.new()
	border_panel = border
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.offset_left = 20
	border.offset_right = -20
	border.offset_top = 20
	border.offset_bottom = -20
	add_child(border)
	border.theme_type_variation = "BattleNotice"
	var margin := MarginContainer.new()
	border.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 48)
	for side in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 48)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 24)
	margin.add_child(column)
	heading = Label.new()
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 39)
	heading.add_theme_color_override("font_color", Color("27e82a"))
	column.add_child(heading)
	creature = TextureRect.new()
	creature.custom_minimum_size = Vector2(0, 130)
	creature.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	creature.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	creature.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	column.add_child(creature)
	body = Label.new()
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 26)
	body.add_theme_color_override("font_color", Color("27e82a"))
	body_scroll = ScrollContainer.new()
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(body_scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(body)
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 16
	progress.show_percentage = false
	column.add_child(progress)
	footer = Button.new()
	footer.custom_minimum_size.y = 46
	footer.pressed.connect(acknowledge)
	column.add_child(footer)
	hd_screen = preload("res://scripts/gameplay/hd_remaining_screen.gd").new()
	hd_screen.kind = &"battle"
	hd_screen.controller = self
	add_child(hd_screen)
	visible = false


func show_intro(actor, definitions: Dictionary, ui: Dictionary, images: Dictionary) -> void:
	textures = images
	phase = &"intro"
	reward = {}
	hd_screen.reset()
	body_scroll.scroll_vertical = 0
	elapsed = 0
	heading.text = "Начало боя"
	var encounter: Dictionary = ui["encounters"][actor.unit_type]
	body.text = "%s\n\n%s" % [encounter["title"], encounter["description"]]
	creature.texture = images[int(definitions["unit_notice_images"][actor.unit_type])]
	creature.visible = false
	progress.visible = true
	progress.value = 0
	footer.text = "Начать бой · Пробел / Enter"
	(monochrome.material as ShaderMaterial).set_shader_parameter("brightness", 0.6)
	visible = true
	queue_redraw()


func show_result(won: bool, reward: Dictionary, ui: Dictionary, images: Dictionary, item_names: Array = []) -> void:
	self.reward = reward.duplicate(true)
	reward_names = item_names
	hd_screen.reset()
	textures = images
	phase = &"victory" if won else &"defeat"
	body_scroll.scroll_vertical = 0
	heading.text = "Победа!" if won else "Поражение"
	body.text = "%s\n\n%s  %d\n%s  %d" % [ui["received"], ui["xp"], reward.get("xp_total", 0), ui["gold"], reward.get("gold", 0)] if won else "Отряд повержен."
	if won and not reward.get("items", []).is_empty():
		var counts: Dictionary = {}
		for id in reward["items"]: counts[int(id)] = int(counts.get(int(id), 0)) + 1
		var loot: PackedStringArray = []
		for id in counts: loot.append("%s ×%d" % [item_names[id] if id < item_names.size() else str(id), counts[id]])
		body.text += "\n\n" + "\n".join(loot)
	creature.visible = false
	progress.visible = false
	footer.text = "Продолжить · Пробел / Enter" if won else "Начать заново · Enter"
	(monochrome.material as ShaderMaterial).set_shader_parameter("brightness", 0.7)
	visible = true
	queue_redraw()


func advance(delta: float) -> void:
	if phase != &"intro": return
	elapsed += maxf(0, delta)
	progress.value = minf(100, elapsed * 50)
	if elapsed >= 2: acknowledge()


func acknowledge() -> void:
	var previous: StringName = phase
	hide_screen()
	if previous == &"intro": intro_finished.emit()
	elif previous == &"victory": continue_requested.emit()
	elif previous == &"defeat": restart_requested.emit()


func hide_screen() -> void:
	phase = &""
	visible = false


func _draw() -> void:
	if textures.is_empty(): return
	if hd_screen != null and hd_screen.active(): return
	# Original frame pieces, scaled at a fixed 2x rather than stretched corner art.
	var border: float = 18
	draw_texture_rect(textures[ImageId.FRAME_LEFT], Rect2(0, 0, border, size.y), false)
	draw_texture_rect(textures[ImageId.FRAME_RIGHT], Rect2(size.x - border, 0, border, size.y), false)
	draw_texture_rect(textures[ImageId.FRAME_HORIZONTAL], Rect2(border, 0, size.x - border * 2, border), true)
	draw_texture_rect(textures[ImageId.FRAME_HORIZONTAL], Rect2(border, size.y - border, size.x - border * 2, border), true)
