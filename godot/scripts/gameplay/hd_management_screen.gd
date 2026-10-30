extends Control
## Desktop presentation of the existing inventory, progression and journal rules.
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Stat = Ids.Stat
const Page = Ids.ManagementPage
const Kind = Ids.ItemKind
const Inventory = preload("res://scripts/gameplay/inventory_rules.gd")
const Progression = preload("res://scripts/gameplay/progression_rules.gd")
const Journal = preload("res://scripts/gameplay/quest_journal.gd")
const UiTheme = preload("res://scripts/gameplay/legacy_theme.gd")
const Icons = preload("res://scripts/gameplay/ui_icons.gd")
const GOLD = UiTheme.GOLD
const INK = Color("d5dfcd")
const MUTED = Color("92a08b")
const GREEN = Color("8fe366")
const RED = Color("e59980")
const DESIGN = Vector2(1280, 800)
const PAGE_SIZE = 16
var controller
var actions: Array[Dictionary] = []
var project_font: Font
var project_frame: StyleBoxTexture
var ui_scale: float = 1.0
var origin := Vector2.ZERO
var hover := Vector2(-1, -1)
var filter_kind: int = -1
var bag_page: int = 0
var selected_item: int = -1
var skill_page: int = 0
var quest_index: int = 0
var quest_page: int = 0
var quest_scroll: int = 0
var quest_limit: int = 0
var socket: int = -1
var crystal_page: int = 0
var message: String = ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(queue_redraw)
	visible = false

func active() -> bool:
	return controller != null and controller.ui_icons != null and controller.ui_icons.preferences.values["hd_icons"]

func reset() -> void:
	filter_kind = -1
	bag_page = 0
	selected_item = -1
	skill_page = 0
	quest_index = 0
	quest_page = 0
	quest_scroll = 0
	socket = -1
	message = ""
	queue_redraw()

func _process(_delta: float) -> void:
	if visible != active():
		visible = active()
		controller.queue_redraw()
	if visible and controller.visible: queue_redraw()

func _panel(rect: Rect2, emerald: bool = false) -> void:
	draw_rect(rect, Color("10231e") if emerald else Color("111714"))
	draw_style_box(project_frame, rect.grow(6))
	draw_rect(rect.grow(-3), Color("756b42"), false, 1)

func _text(value: String, at: Vector2, pixels: int = 22, color: Color = INK, width: float = -1) -> void:
	draw_string(project_font, at + Vector2(1, 2), value, HORIZONTAL_ALIGNMENT_LEFT, width, pixels, Color.BLACK)
	draw_string(project_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, width, pixels, color)

func _button(id: String, rect: Rect2, title: String, callback: Callable, enabled: bool = true, selected: bool = false) -> void:
	draw_style_box(controller.get_theme_stylebox("disabled" if not enabled else "hover" if selected or rect.has_point(hover) else "normal", "Button"), rect)
	_text(title, rect.position + Vector2(12, rect.size.y * 0.5 + 7), 20, GOLD if selected else INK if enabled else MUTED, rect.size.x - 20)
	actions.append({"id": id, "rect": rect, "call": callback, "enabled": enabled})

func _lines(value: String, width: float, pixels: int = 22) -> PackedStringArray:
	var result := PackedStringArray()
	for paragraph in value.split("\n"):
		var line := ""
		for word in paragraph.split(" "):
			var next: String = word if line.is_empty() else line + " " + word
			if not line.is_empty() and project_font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x > width:
				result.append(line)
				line = word
			else: line = next
		result.append(line)
	return result

func _paragraph(value: String, at: Vector2, width: float, count: int, pixels: int = 22, color: Color = INK, first: int = 0) -> int:
	var lines := _lines(value, width, pixels)
	for i in range(first, mini(first + count, lines.size())): _text(lines[i], at + Vector2(0, (i - first) * (pixels + 7)), pixels, color, width)
	return lines.size()

func _icon(entry, bounds: Rect2) -> void:
	if entry == null: return
	var texture: Texture2D
	if entry.definition_id < Ids.ItemId.FIRST_CRYSTAL:
		texture = controller.images[Ids.EconomyImage.ITEM_BASE + entry.definition_id]
	else:
		var atlas := AtlasTexture.new()
		atlas.atlas = controller.images[Ids.EconomyImage.CRYSTAL_ATLAS]
		atlas.region = Rect2((entry.definition_id - Ids.ItemId.FIRST_CRYSTAL) * 16, 0, 16, 16)
		texture = atlas
	draw_texture_rect(texture, Icons.fit_rect(texture, bounds), false)

func _name(entry) -> String:
	return str(controller.game.definitions["economy"]["item_names"][entry.definition_id])

func items() -> Array:
	return Inventory.ordered_available(controller.game, controller.actor(), filter_kind)

func item():
	return Inventory.find(controller.game, selected_item)

func _changed() -> void:
	controller._refresh()
	queue_redraw()

func _choose_actor(index: int) -> void:
	controller.choose_actor(index)
	bag_page = 0
	selected_item = -1
	skill_page = 0
	socket = -1
	message = ""
	queue_redraw()

func switch_page(page: int) -> void:
	controller.page = page
	controller.screen = &"character" if page == Page.CHARACTER else &"journal" if page == Page.JOURNAL else &"items"
	controller.draft = {}
	controller.editing = false
	controller.selected = 0
	reset()
	_changed()

func _draw() -> void:
	if not active() or controller.game == null or controller.images.is_empty(): return
	project_font = controller.get_theme_font("font", "Label")
	if project_frame == null:
		project_frame = UiTheme.frame(controller.images)
		project_frame.draw_center = false
	ui_scale = minf(size.x / DESIGN.x, size.y / DESIGN.y)
	if ui_scale <= 0: return
	origin = ((size - DESIGN * ui_scale) * 0.5).floor()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.025, 0.02, 0.94))
	draw_set_transform(origin, 0, Vector2.ONE * ui_scale)
	actions.clear()
	_panel(Rect2(24, 24, 1232, 88), true)
	_text("Книга отряда", Vector2(44, 77), 30, GOLD)
	var pages: Array = [[Page.CHARACTER, "Персонаж"], [Page.INVENTORY, "Инвентарь"], [Page.JOURNAL, "Задания"]]
	for i in range(pages.size()): _button("tab_%d" % pages[i][0], Rect2(370 + i * 178, 43, 166, 48), pages[i][1], switch_page.bind(pages[i][0]), true, controller.page == pages[i][0])
	_text("Золото: %d" % controller.game.gold, Vector2(934, 78), 23, GOLD, 300)
	match controller.page:
		Page.CHARACTER: _character()
		Page.INVENTORY: _inventory()
		Page.JOURNAL: _journal()
	_button("close", Rect2(1040, 730, 216, 46), "Закрыть · Esc", controller.dismiss)
	if not message.is_empty(): _text(message, Vector2(32, 718 if controller.page == Page.CHARACTER else 756), 18, GOLD, 990)
	if socket >= 0: _crystals()
	draw_set_transform(Vector2.ZERO)

func _hero() -> void:
	var unit = controller.actor()
	_panel(Rect2(24, 140, 280, 560), true)
	_text(str(controller.data["unit_names"][unit.unit_type]), Vector2(48, 180), 28, GOLD, 230)
	var texture: Texture2D = controller.ui_icons.actor_portrait(unit.unit_type, controller.game.definitions)
	var inventory: bool = controller.page == Page.INVENTORY
	draw_texture_rect(texture, Icons.fit_rect(texture, Rect2(76, 199, 176, 150 if inventory else 210)), false)
	var progress: Dictionary = controller.experience_progress()
	_text("Уровень %d" % progress["level"], Vector2(48, 377 if inventory else 440), 22)
	if inventory:
		for i in range(2):
			var entry = unit.weapon if i == 0 else unit.armor
			var rect := Rect2(48 + i * 120, 393, 110, 95)
			_button("equipped_%d" % i, rect, "", _select.bind(entry.instance_id if entry != null else -1))
			_icon(entry, rect.grow(-10))
			_text("Оружие" if i == 0 else "Доспех", Vector2(48 + i * 120, 510), 18, MUTED)
	else:
		draw_rect(Rect2(48, 459, 232, 12), Color("293a29"))
		draw_rect(Rect2(48, 459, 232 * float(progress["ratio"]), 12), Color("65953c"))
		_text("Опыт: %d / %d" % [progress["experience"], progress["next"]], Vector2(48, 496), 17, MUTED, 232)
	_text("Здоровье %d / %d" % [unit.stats[Stat.HP], unit.stats[Stat.MAX_HP]], Vector2(48, 526), 19, GREEN)
	_text("Мана %d / %d" % [unit.stats[Stat.MANA], unit.stats[Stat.MAX_MANA]], Vector2(48, 554), 19, Color("94c8e8"))
	for i in range(controller.game.party.size()):
		var rect := Rect2(44 + i * 60, 603, 52, 70)
		var actor = controller.game.party[i]
		draw_rect(rect.grow(3), GOLD if i == controller.party_index else Color("374836"), false, 2)
		var portrait: Texture2D = controller.ui_icons.actor_portrait(actor.unit_type, controller.game.definitions)
		draw_texture_rect(portrait, Icons.fit_rect(portrait, rect), false)
		actions.append({"id": "actor_%d" % i, "rect": rect, "call": _choose_actor.bind(i), "enabled": true})

func _character() -> void:
	_hero()
	if controller.draft.is_empty(): controller.draft = Progression.begin(controller.game, controller.actor())
	var draft: Dictionary = controller.draft
	if draft.is_empty(): return
	var preview: PackedInt32Array = Progression.preview(controller.game, controller.actor(), draft)
	_panel(Rect2(324, 140, 450, 420))
	_text("Характеристики: %d" % draft["attribute_points"], Vector2(346, 182), 26, GOLD)
	for i in range(Progression.ATTRIBUTES.size()): _training_row(Progression.ATTRIBUTES[i], Rect2(344, 207 + i * 64, 410, 58), false, preview)
	_panel(Rect2(324, 584, 450, 116), true)
	_text("После применения", Vector2(344, 615), 21, GOLD)
	_text("Здоровье %d · Мана %d" % [preview[Stat.MAX_HP], preview[Stat.MAX_MANA]], Vector2(344, 647), 20)
	_text("ОД %d · Защита %d" % [preview[Stat.MAX_ACTION_POINTS], preview[Stat.PHYSICAL_RESISTANCE]], Vector2(344, 678), 20)
	_panel(Rect2(794, 140, 462, 560))
	_text("Навыки: %d" % draft["skill_points"], Vector2(816, 182), 26, GOLD)
	var skills: Array[int] = []
	for stat in range(Stat.ATTACK, Stat.RESERVED):
		if Progression.editable(draft, stat): skills.append(stat)
	skill_page = clampi(skill_page, 0, maxi(0, int((skills.size() - 1) / 7.0)))
	for i in range(skill_page * 7, mini(skill_page * 7 + 7, skills.size())): _training_row(skills[i], Rect2(814, 208 + (i % 7) * 56, 422, 50), true, preview)
	_text("Предел обучения: 24", Vector2(816, 633), 18, MUTED)
	_button("skills_prev", Rect2(816, 651, 88, 33), "Назад", _skill_page.bind(-1), skill_page > 0)
	_button("skills_next", Rect2(914, 651, 88, 33), "Далее", _skill_page.bind(1), (skill_page + 1) * 7 < skills.size())
	_button("apply", Rect2(324, 730, 190, 46), "Применить", _apply, draft["base"] != draft["original"])
	_button("cancel", Rect2(530, 730, 180, 46), "Отменить", _cancel)
	if message.is_empty(): _text("Минус возвращает только новые очки.", Vector2(32, 718), 16, MUTED)

func _training_row(stat: int, rect: Rect2, skill: bool, preview: PackedInt32Array) -> void:
	var draft: Dictionary = controller.draft
	draw_rect(rect, Color("1c251d"))
	var title: String = str(controller.game.definitions["economy"]["stat_names"][stat])
	_text(title, rect.position + Vector2(10, 23), 19, INK, rect.size.x - 118)
	var value: int = int(draft["base"][stat]) - (1 if skill else 0)
	_text("%d / 24" % value if skill else "%d → %d" % [draft["original"][stat], preview[stat]], rect.position + Vector2(10, 46), 17, GREEN if draft["base"][stat] != draft["original"][stat] else MUTED)
	var points: int = draft["skill_points" if skill else "attribute_points"]
	_button("minus_%d" % stat, Rect2(rect.end.x - 102, rect.position.y + 7, 43, 36), "−", _adjust.bind(stat, -1), draft["base"][stat] > draft["original"][stat])
	_button("plus_%d" % stat, Rect2(rect.end.x - 50, rect.position.y + 7, 43, 36), "+", _adjust.bind(stat, 1), points > 0 and (not skill or draft["base"][stat] < 25))
	if rect.has_point(hover): tooltip_text = "Достигнут предел обучения" if skill and value >= 24 else "Нет очков навыков" if skill and points <= 0 else "Нет очков характеристик" if points <= 0 else title
	if rect.has_point(hover) and points > 0 and (not skill or value < 24):
		var help: Dictionary = {Stat.ENDURANCE: "Повышает здоровье и броню", Stat.INTELLECT: "Повышает ману и мощь заклятий", Stat.STRENGTH: "Повышает броню и мощь удара", Stat.DEXTERITY: "Влияет на подвижность", Stat.LUCK: "Влияет на удачу в бою"}
		if skill:
			var hints: Array = controller.game.definitions["economy"]["skill_help"]
			var start: int = (stat - Stat.ATTACK + 1) * 6
			tooltip_text = str(hints[start]) if start < hints.size() else title
		else: tooltip_text = help.get(stat, title)

func _adjust(stat: int, delta: int) -> void:
	Progression.adjust(controller.draft, stat, delta)
	controller.editing = true
	message = ""
	queue_redraw()

func _apply() -> void:
	message = "Изменения применены" if Progression.commit(controller.game, controller.actor(), controller.draft) else "Состояние изменилось. Откройте персонажа заново."
	controller.draft = {}
	controller.editing = false
	_changed()

func _cancel() -> void:
	controller.draft = {}
	controller.editing = false
	message = "Изменения отменены"
	_changed()

func _skill_page(step: int) -> void:
	skill_page += step
	queue_redraw()

func _filter(kind: int) -> void:
	filter_kind = kind
	bag_page = 0
	selected_item = -1
	socket = -1
	queue_redraw()

func _bag_page(step: int) -> void:
	bag_page += step
	queue_redraw()

func _select(id: int) -> void:
	selected_item = id
	socket = -1
	message = ""
	queue_redraw()

func _inventory() -> void:
	_hero()
	_panel(Rect2(324, 140, 556, 560))
	_panel(Rect2(900, 140, 356, 560))
	var kinds: Array = [[-1, "Всё"], [Kind.WEAPON, "Оружие"], [Kind.ARMOR, "Доспехи"], [Kind.CRYSTAL, "Кристаллы"]]
	for i in range(4): _button("filter_%d" % kinds[i][0], Rect2(344 + i * 130, 160, 122, 44), kinds[i][1], _filter.bind(kinds[i][0]), true, filter_kind == kinds[i][0])
	var bag: Array = items()
	bag_page = clampi(bag_page, 0, maxi(0, int((bag.size() - 1) / float(PAGE_SIZE))))
	if item() not in bag: selected_item = bag[0].instance_id if not bag.is_empty() else -1
	for i in range(PAGE_SIZE):
		var rect := Rect2(344 + (i % 4) * 130, 226 + int(i / 4.0) * 98, 122, 90)
		draw_rect(rect, Color("0b100e"))
		draw_rect(rect, GOLD if bag_page * PAGE_SIZE + i < bag.size() and bag[bag_page * PAGE_SIZE + i].instance_id == selected_item else Color("394331"), false, 2)
		if bag_page * PAGE_SIZE + i >= bag.size(): continue
		var entry = bag[bag_page * PAGE_SIZE + i]
		_icon(entry, rect.grow(-12))
		var owner = Inventory.owner(controller.game, entry)
		if owner != null: _text("Надето", rect.position + Vector2(6, 82), 14, GREEN)
		actions.append({"id": "item_%d" % entry.instance_id, "rect": rect, "call": _select.bind(entry.instance_id), "enabled": true})
	_button("bag_prev", Rect2(344, 643, 98, 38), "Назад", _bag_page.bind(-1), bag_page > 0)
	_text("%d / %d · вещей %d" % [bag_page + 1, maxi(1, ceili(bag.size() / float(PAGE_SIZE))), bag.size()], Vector2(459, 669), 18, MUTED)
	_button("bag_next", Rect2(754, 643, 98, 38), "Далее", _bag_page.bind(1), (bag_page + 1) * PAGE_SIZE < bag.size())
	if bag.is_empty(): _text("В этой категории пусто", Vector2(358, 426), 22, MUTED)
	_item_details()

func _compatible(entry) -> bool:
	var spec: Dictionary = Inventory.definition(controller.game, entry.definition_id)
	var owner = Inventory.owner(controller.game, entry)
	return int(spec["kind"]) != Kind.CRYSTAL and int(spec["hero_type"]) == controller.actor().unit_type and (owner == null or owner == controller.actor())

func _item_details() -> void:
	var entry = item()
	if entry == null:
		_text("Выберите предмет", Vector2(922, 184), 24, GOLD)
		return
	_paragraph(_name(entry), Vector2(922, 180), 310, 2, 24, GOLD)
	_icon(entry, Rect2(1007, 235, 140, 132))
	var owner = Inventory.owner(controller.game, entry)
	var kind: int = int(Inventory.definition(controller.game, entry.definition_id)["kind"])
	if kind == Kind.CRYSTAL:
		var description: String = str(controller.game.definitions["economy"]["crystal_descriptions"][entry.definition_id - Ids.ItemId.FIRST_CRYSTAL])
		_paragraph(description, Vector2(922, 405), 310, 7, 19)
		_paragraph("Для вставки выберите пустое гнездо вещи.", Vector2(922, 638), 310, 2, 17, MUTED)
		return
	var compatible: bool = _compatible(entry)
	_paragraph("Надето: " + str(controller.data["unit_names"][owner.unit_type]) if owner != null else "Подходит выбранному герою" if compatible else "Предмет для другого героя", Vector2(922, 393), 310, 2, 19, GREEN if compatible else RED)
	if compatible:
		var unit = controller.actor()
		var removing: bool = owner == unit
		var preview: PackedInt32Array = Inventory.preview_stats(controller.game, unit, entry, removing)
		var fields: Array = [[Stat.PHYSICAL_DAMAGE, "Урон", 20.0], [Stat.ATTACK_RANGE, "Дальность", 1.0]] if kind == Kind.WEAPON else [[Stat.PHYSICAL_RESISTANCE, "Защита", 1.0], [Stat.DARK_RESISTANCE, "Маг. защита", 1.0]]
		for extra: Array in [[Stat.MAX_HP, "Здоровье", 1.0], [Stat.MAX_MANA, "Мана", 1.0], [Stat.DARK_DAMAGE, "Тёмн. урон", 20.0], [Stat.LIGHT_DAMAGE, "Светл. урон", 20.0]]:
			if preview[extra[0]] != unit.stats[extra[0]]: fields.append(extra)
		_text("После снятия" if removing else "После надевания", Vector2(922, 426), 17, MUTED)
		for i in range(mini(4, fields.size())):
			var f: Array = fields[i]
			_text(f[1], Vector2(922, 452 + i * 26), 20)
			_text("%d → %d" % [unit.stats[f[0]] / f[2], preview[f[0]] / f[2]], Vector2(1091, 452 + i * 26), 20, GREEN if preview[f[0]] >= unit.stats[f[0]] else RED)
	_text("Гнёзда · нажмите для изменения", Vector2(922, 554), 17, MUTED)
	for i in range(entry.sockets.size()):
		var rect := Rect2(922 + i * 94, 566, 80, 62)
		_button("socket_%d" % i, rect, "Пусто" if entry.sockets[i] < 0 else "", _socket.bind(i))
		if entry.sockets[i] >= 0: _icon(Inventory.find(controller.game, entry.socket_instance_ids[i]), rect.grow(-8))
	_button("equip", Rect2(922, 643, 310, 38), "Снять" if owner == controller.actor() else "Надеть", _equip, compatible)

func _equip() -> void:
	var entry = item()
	if entry == null: return
	var kind: int = int(Inventory.definition(controller.game, entry.definition_id)["kind"])
	var ok: bool = Inventory.unequip(controller.game, controller.actor(), kind) if Inventory.owner(controller.game, entry) == controller.actor() else Inventory.equip(controller.game, controller.actor(), entry.instance_id)
	message = "Экипировка изменена" if ok else "Предмет недоступен этому герою"
	_changed()

func _socket(index: int) -> void:
	var entry = item()
	if entry == null: return
	if entry.sockets[index] >= 0:
		Inventory.remove(controller.game, entry.instance_id, index)
		message = "Кристалл возвращён в сумку"
	else:
		socket = index
		crystal_page = 0
	_changed()

func _crystals() -> void:
	actions.clear()
	draw_rect(Rect2(Vector2.ZERO, DESIGN), Color(0, 0, 0, 0.8))
	_panel(Rect2(350, 190, 580, 420), true)
	_text("Выберите кристалл", Vector2(378, 233), 28, GOLD)
	var crystals: Array = Inventory.available(controller.game, null, Kind.CRYSTAL)
	crystal_page = clampi(crystal_page, 0, maxi(0, int((crystals.size() - 1) / 5.0)))
	for i in range(crystal_page * 5, mini(crystal_page * 5 + 5, crystals.size())):
		var entry = crystals[i]
		var rect := Rect2(378, 258 + (i % 5) * 49, 524, 43)
		_button("crystal_%d" % entry.instance_id, rect, "    " + _name(entry), _insert.bind(entry.instance_id))
		_icon(entry, Rect2(rect.position + Vector2(5, 4), Vector2(34, 34)))
	if crystals.is_empty(): _text("Нет свободных кристаллов", Vector2(378, 333), 23, MUTED)
	_button("crystal_prev", Rect2(378, 539, 114, 42), "Назад", _crystal_page.bind(-1), crystal_page > 0)
	_button("crystal_next", Rect2(506, 539, 114, 42), "Далее", _crystal_page.bind(1), (crystal_page + 1) * 5 < crystals.size())
	_button("crystal_close", Rect2(698, 539, 204, 42), "Отменить", _close_socket)

func _crystal_page(step: int) -> void:
	crystal_page += step
	queue_redraw()

func _close_socket() -> void:
	socket = -1
	queue_redraw()

func _insert(id: int) -> void:
	var entry = item()
	if entry != null: message = "Кристалл вставлен" if Inventory.insert(controller.game, entry.instance_id, id, socket) else "Не удалось вставить кристалл"
	socket = -1
	_changed()

func _journal() -> void:
	_panel(Rect2(24, 140, 450, 560))
	_panel(Rect2(496, 140, 760, 560), true)
	var quests: Array[Dictionary] = Journal.entries(controller.data["quests"], controller.game.quests)
	_text("История путешествия", Vector2(48, 184), 26, GOLD)
	if quests.is_empty():
		_text("Пока нет заданий", Vector2(48, 245), 22, MUTED)
		return
	quest_index = clampi(quest_index, 0, quests.size() - 1)
	quest_page = clampi(quest_page, 0, int((quests.size() - 1) / 6.0))
	for i in range(quest_page * 6, mini(quest_page * 6 + 6, quests.size())):
		var rect := Rect2(44, 211 + (i % 6) * 66, 410, 58)
		_button("quest_%d" % i, rect, "", _quest.bind(i), true, i == quest_index)
		_paragraph(str(quests[i]["title"]), rect.position + Vector2(10, 24), 390, 2, 18, GOLD if i == quest_index else INK)
	_button("quests_prev", Rect2(44, 643, 130, 38), "Назад", _quest_page.bind(-1), quest_page > 0)
	_button("quests_next", Rect2(320, 643, 134, 38), "Далее", _quest_page.bind(1), (quest_page + 1) * 6 < quests.size())
	var selected: Dictionary = quests[quest_index]
	_paragraph(str(selected["title"]), Vector2(526, 184), 690, 2, 28, GOLD)
	_text(controller.quest_state(selected), Vector2(526, 262), 20, GREEN)
	var body: String = str(selected["text"]).strip_edges()
	quest_limit = maxi(0, _lines(body, 690).size() - 10)
	quest_scroll = clampi(quest_scroll, 0, quest_limit)
	_paragraph(body, Vector2(526, 309), 690, 10, 22, INK, quest_scroll)
	_button("quest_up", Rect2(526, 643, 130, 38), "Выше", _quest_scroll.bind(-7), quest_scroll > 0)
	_button("quest_down", Rect2(670, 643, 130, 38), "Ниже", _quest_scroll.bind(7), quest_scroll < quest_limit)

func _quest(index: int) -> void:
	quest_index = index
	quest_scroll = 0
	queue_redraw()

func _quest_page(step: int) -> void:
	quest_page += step
	queue_redraw()

func _quest_scroll(step: int) -> void:
	quest_scroll = clampi(quest_scroll + step, 0, quest_limit)
	queue_redraw()

func handle_key(key: int) -> void:
	if socket >= 0:
		if key == KEY_ESCAPE: _close_socket()
		return
	if key == KEY_ESCAPE:
		if socket >= 0: _close_socket()
		else: controller.dismiss()
	elif key == KEY_TAB:
		var pages: Array = [Page.CHARACTER, Page.INVENTORY, Page.JOURNAL]
		switch_page(pages[(pages.find(controller.page) + 1) % pages.size()])
	elif key in [KEY_ENTER, KEY_KP_ENTER] and socket < 0:
		if controller.page == Page.CHARACTER: _apply()
		elif controller.page == Page.INVENTORY and item() != null and _compatible(item()): _equip()
	elif key in [KEY_LEFT, KEY_RIGHT] and socket < 0 and controller.page != Page.JOURNAL:
		_choose_actor(posmod(controller.party_index + (-1 if key == KEY_LEFT else 1), controller.game.party.size()))
	elif controller.page == Page.JOURNAL and key in [KEY_UP, KEY_DOWN]: _quest_scroll(-1 if key == KEY_UP else 1)

func _gui_input(event: InputEvent) -> void:
	if not active(): return
	if event is InputEventMouseMotion:
		hover = (event.position - origin) / ui_scale
		tooltip_text = ""
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		accept_event()
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var step: int = -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			if socket >= 0: _crystal_page(step)
			elif controller.page == Page.INVENTORY: _bag_page(step)
			elif controller.page == Page.JOURNAL: _quest_scroll(step * 3)
			elif controller.page == Page.CHARACTER: _skill_page(step)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var point: Vector2 = (event.position - origin) / ui_scale
			for action: Dictionary in actions:
				if action["enabled"] and action["rect"].has_point(point):
					controller.ui_action.emit("confirm")
					action["call"].call()
					break
		queue_redraw()
