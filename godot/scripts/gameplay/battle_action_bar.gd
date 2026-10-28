extends PanelContainer
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Spell = Ids.Spell
const MenuAction = Ids.MenuAction
const ImageId = Ids.ImageId
const Stat = Ids.Stat
signal chosen(action: String, spell: int)
const Spells = preload("res://scripts/gameplay/spell_rules.gd")
var ui_icons
var submenu: bool = false
var buttons: Dictionary = {}
var caption: Label
var flow: HFlowContainer
var actor_id: int = -1
var _signature: String = ""


func _ready() -> void:

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 20)
	caption.add_theme_color_override("font_color", Color("27e82a"))
	column.add_child(caption)
	flow = HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	column.add_child(flow)
	visible = false


func reset_menu() -> void:
	submenu = false
	actor_id = -1
	_signature = ""
	visible = false


func _add(key: String, title: String, atlas: Texture2D, frame: int, action: String, spell: int = -1) -> void:
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = Rect2(frame * 21, 0, 21, 20)
	var button := Button.new()
	button.icon = ui_icons.spell(frame) if ui_icons != null and action == "spell" else texture
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.custom_minimum_size = Vector2(66, 62)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.tooltip_text = title
	button.mouse_entered.connect(func(): caption.text = title)
	button.focus_entered.connect(func(): caption.text = title)
	button.pressed.connect(func(): chosen.emit(action, spell))
	flow.add_child(button)
	buttons[key] = button


func refresh(battle, ui: Dictionary, images: Dictionary) -> void:
	visible = battle.active and battle.outcome == &"" and battle.session.mode == &"battle"
	if not visible: return
	var actor = battle.unit(battle.selected_id) if battle.selected_id >= 0 else battle.session.hero
	if actor_id != actor.instance_id:
		submenu = false
		actor_id = actor.instance_id
	var signature := "%d:%s:%s:%d" % [actor_id, submenu, str(Array(actor.stats.slice(Stat.ATTACK, Stat.DARK_ASTRAL_MAGIC + 1))), ui_icons.revision if ui_icons != null else 0]
	if signature != _signature:
		_signature = signature
		for child in flow.get_children():
			flow.remove_child(child)
			child.queue_free()
		buttons.clear()
		if submenu:
			for id in range(Spell.COUNT):
				if Spells.learned(actor, id, battle.session.definitions): _add(str(id), "%s%d%s" % [ui["spells"][id], Spells.cost(actor, id, battle.session.definitions), ui["mana_suffix"]], images[ImageId.SPELL_ATLAS], id, "spell", id)
			_add("back", ui["actions"][MenuAction.BACK], images[ImageId.ACTION_ATLAS], MenuAction.BACK, "back")
			caption.text = buttons.values()[0].tooltip_text if buttons.size() > 1 else "Нет доступных заклинаний"
		else:
			if actor.stats[Stat.ATTACK] != 0 or actor.stats[Stat.DEFENSE] != 0 or actor.stats[Stat.TACTICS] != 0: _add("attack", ui["actions"][MenuAction.ATTACK], images[ImageId.ACTION_ATLAS], MenuAction.ATTACK, "attack")
			if actor.stats[Stat.ARCHERY] != 0 or actor.stats[Stat.ASSASSINATION] != 0 or actor.stats[Stat.ATHLETICS] != 0: _add("shoot", ui["actions"][MenuAction.SHOOT], images[ImageId.ACTION_ATLAS], MenuAction.SHOOT, "attack")
			var magic: bool = false
			for id in range(Spell.COUNT): magic = magic or Spells.learned(actor, id, battle.session.definitions)
			if magic: _add("magic", ui["actions"][MenuAction.MAGIC], images[ImageId.ACTION_ATLAS], MenuAction.MAGIC, "magic")
			_add("move", ui["actions"][MenuAction.MOVE], images[ImageId.ACTION_ATLAS], MenuAction.MOVE, "move")
			_add("defend", ui["actions"][MenuAction.DEFEND], images[ImageId.ACTION_ATLAS], MenuAction.DEFEND, "defend")
			caption.text = "Действия · " + str(battle.round_number) + " ход"
	for key: String in buttons:
		buttons[key].disabled = not battle.can_input()
		if key.is_valid_int() and not (battle.session.god_mode and actor in battle.session.party): buttons[key].disabled = buttons[key].disabled or actor.stats[Stat.MANA] < Spells.cost(actor, int(key), battle.session.definitions)
