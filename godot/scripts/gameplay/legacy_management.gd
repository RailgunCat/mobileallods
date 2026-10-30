extends "res://scripts/gameplay/legacy_ui_screen.gd"
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Stat = Ids.Stat
const Page = Ids.ManagementPage
const Kind = Ids.ItemKind
const Inventory = preload("res://scripts/gameplay/inventory_rules.gd")
const Progression = preload("res://scripts/gameplay/progression_rules.gd")
const Rewards = preload("res://scripts/gameplay/battle_rewards.gd")
const Journal = preload("res://scripts/gameplay/quest_journal.gd")
signal closed
var game
var data: Dictionary
var page: int = Page.CHARACTER
var screen: StringName = &"character"
var party_index: int = 0
var selected: int = 0
var action_index: int = 0
var slot_index: int = 0
var schools: bool = false
var editing: bool = false
var draft: Dictionary = {}
var candidates: Array = []
var crystals: Array = []
var message: String = ""
var quests: Array[Dictionary] = []
var scroll: int = 0
var hd_screen: Control


func _ready() -> void:
	super._ready()
	enable_world_background()
	hd_screen = preload("res://scripts/gameplay/hd_management_screen.gd").new()
	hd_screen.controller = self
	add_child(hd_screen)


func open(session, campaign: Dictionary, textures: Dictionary, initial_page: int) -> void:
	game = session
	data = campaign
	page = initial_page
	setup(textures, game.definitions)
	Inventory.sync_party(game)
	party_index = 0
	selected = 0
	action_index = 0
	schools = false
	editing = false
	draft = {}
	message = ""
	screen = &"character" if page == Page.CHARACTER else (&"journal" if page == Page.JOURNAL else &"party")
	scroll = 0
	show()
	_refresh()
	hd_screen.reset()


func actor():
	return game.party[party_index]


func item():
	return candidates[selected] if not candidates.is_empty() else null


func slots() -> Array[int]:
	var result: Array[int] = []
	if not schools:
		result.assign(Progression.ATTRIBUTES)
	else:
		for stat in range(Stat.ATTACK, Stat.RESERVED):
			if actor().base_stats[stat] > 0: result.append(stat)
	return result


func choose_actor(index: int) -> void:
	party_index = clampi(index, 0, game.party.size() - 1)
	selected = 0
	action_index = 0
	editing = false
	draft = {}
	message = ""
	_refresh()


func _refresh() -> void:
	clear_regions()
	if screen == &"party":
		for index in range(game.party.size()):
			region(Rect2(35, 24 + index * 17, 170, 17), func(): party_index = index; confirm())
	elif screen == &"journal":
		quests.assign(Journal.entries(data["quests"], game.quests))
		selected = clampi(selected, 0, maxi(0, quests.size() - 1))
		var first: int = maxi(0, selected - 4)
		for index in range(first, mini(first + 5, quests.size())):
			region(Rect2(20, 35 + (index - first) * 46, 200, 44), func(): selected = index; confirm())
	elif screen == &"quest":
		region(Rect2(20, 44, 200, 95), func(): navigate(-10))
		region(Rect2(20, 140, 200, 120), func(): navigate(10))
	elif screen == &"character":
		if draft.is_empty(): draft = Progression.begin(game, actor())
		region(Rect2(8, 20, 15, 40), func(): choose_actor(party_index - 1))
		region(Rect2(68, 20, 15, 40), func(): choose_actor(party_index + 1))
		var rows: Array[int] = slots()
		selected = clampi(selected, 0, maxi(0, rows.size() - 1))
		var first: int = maxi(0, selected - 6) if schools else 0
		for index in range(first, mini(first + 7, rows.size())):
			var y: int = 74 + (index - first) * 16
			region(Rect2(20, y, 95 if schools else 70, 16), func(): selected = index; editing = true; _refresh())
			region(Rect2(116 if schools else 90, y, 13, 16), func(): selected = index; editing = true; adjust(-1))
			region(Rect2(140 if schools else 116, y, 13, 16), func(): selected = index; editing = true; adjust(1))
		region(Rect2(16, 242, 125, 17), func(): _change_training_page(false))
		region(Rect2(150, 242, 75, 17), func(): _change_training_page(true))
		if editing:
			region(Rect2(20, 264, 105, 17), apply_training)
			region(Rect2(140, 264, 80, 17), back)
	else:
		if screen == &"items":
			candidates = Inventory.available(game, actor())
			candidates.sort_custom(func(a, b):
				var a_kind: int = int(Inventory.definition(game, a.definition_id)["kind"])
				var b_kind: int = int(Inventory.definition(game, b.definition_id)["kind"])
				var order := {Kind.WEAPON: 0, Kind.ARMOR: 1, Kind.CRYSTAL: 2}
				return order[a_kind] < order[b_kind] if a_kind != b_kind else a.instance_id < b.instance_id
			)
			selected = clampi(selected, 0, maxi(0, candidates.size() - 1))
			region(Rect2(44, 6, 16, 16), func(): navigate(-1))
			region(Rect2(74, 6, 16, 16), func(): navigate(1))
			if item() != null and item().definition_id < Ids.ItemId.FIRST_CRYSTAL:
				var y: int = _action_y()
				region(Rect2(45, y, 160, 18), func(): action_index = 0; confirm())
				region(Rect2(45, y + 20, 160, 18), func(): action_index = 1; confirm())
		elif screen == &"sockets":
			for index in range(item().sockets.size()):
				region(Rect2(25, 100 + index * 20, 190, 20), func(): slot_index = index; confirm())
		elif screen == &"crystals":
			crystals = Inventory.available(game, null, Kind.CRYSTAL)
			action_index = clampi(action_index, 0, maxi(0, crystals.size() - 1))
			var first: int = maxi(0, action_index - 7)
			for index in range(first, mini(first + 8, crystals.size())):
				region(Rect2(25, 100 + (index - first) * 18, 190, 18), func(): action_index = index; confirm())
	queue_redraw()


func _change_training_page(value: bool) -> void:
	schools = value
	selected = 0
	_refresh()


func navigate(step: int) -> void:
	message = ""
	match screen:
		&"party": party_index = posmod(party_index + step, game.party.size())
		&"journal": selected = clampi(selected + step, 0, maxi(0, quests.size() - 1))
		&"quest": scroll = clampi(scroll + step, 0, maxi(0, quest_lines().size() - 14))
		&"character":
			if editing: selected = posmod(selected + step, maxi(1, slots().size()))
			else: choose_actor(party_index + step)
		&"items": selected = clampi(selected + step, 0, maxi(0, candidates.size() - 1)); action_index = 0
		&"sockets": slot_index = posmod(slot_index + step, item().sockets.size())
		&"crystals": action_index = posmod(action_index + step, maxi(1, crystals.size()))
	_refresh()


func handle_key(key: int) -> void:
	if hd_screen != null and hd_screen.active():
		hd_screen.handle_key(key)
		return
	if key == KEY_ESCAPE: back()
	elif key in [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER]: confirm()
	elif screen == &"character" and key == KEY_TAB: _change_training_page(not schools)
	elif screen == &"character" and editing and key in [KEY_LEFT, KEY_RIGHT, KEY_A, KEY_D]: adjust(-1 if key in [KEY_LEFT, KEY_A] else 1)
	elif screen == &"items" and key in [KEY_UP, KEY_DOWN, KEY_W, KEY_S]: action_index = 1 - action_index; queue_redraw()
	elif key in [KEY_LEFT, KEY_UP, KEY_A, KEY_W]: navigate(-1)
	elif key in [KEY_RIGHT, KEY_DOWN, KEY_D, KEY_S]: navigate(1)


func adjust(delta: int) -> void:
	var rows: Array[int] = slots()
	if not rows.is_empty(): Progression.adjust(draft, rows[selected], delta)
	_refresh()


func apply_training() -> void:
	if Progression.commit(game, actor(), draft):
		draft = {}
		editing = false
		message = "Изменения применены"
	else: message = "Не удалось применить изменения"
	_refresh()


func confirm() -> void:
	message = ""
	match screen:
		&"party": screen = &"items"; selected = 0
		&"journal":
			if not quests.is_empty(): screen = &"quest"; scroll = 0
		&"quest": screen = &"journal"
		&"character":
			if editing: apply_training(); return
			editing = true
		&"items":
			if item() == null or item().definition_id >= Ids.ItemId.FIRST_CRYSTAL: return
			if action_index == 1: screen = &"sockets"; slot_index = 0
			else:
				var kind: int = int(Inventory.definition(game, item().definition_id)["kind"])
				var ok: bool = Inventory.unequip(game, actor(), kind) if Inventory.owner(game, item()) == actor() else Inventory.equip(game, actor(), item().instance_id)
				if not ok: message = "Предмет недоступен этому герою"
		&"sockets":
			if item().sockets[slot_index] >= 0: Inventory.remove(game, item().instance_id, slot_index)
			else: screen = &"crystals"; action_index = 0
		&"crystals":
			if not crystals.is_empty():
				Inventory.insert(game, item().instance_id, crystals[action_index].instance_id, slot_index)
				screen = &"sockets"
	_refresh()


func back() -> void:
	message = ""
	match screen:
		&"quest": screen = &"journal"
		&"crystals": screen = &"sockets"
		&"sockets": screen = &"items"; action_index = 0
		&"items": screen = &"party"; selected = 0
		&"character":
			if editing: editing = false; draft = {}
			else: dismiss(); return
		_: dismiss(); return
	_refresh()


func dismiss() -> void:
	draft = {}
	hide()
	closed.emit()


func comparison() -> Array:
	if item() == null or item().definition_id >= Ids.ItemId.FIRST_CRYSTAL: return []
	var kind: int = int(Inventory.definition(game, item().definition_id)["kind"])
	var unit = actor()
	var next: PackedInt32Array = Inventory.preview_stats(game, unit, item())
	var fields: Array = [[Stat.PHYSICAL_DAMAGE, "Урон"], [Stat.ATTACK_RANGE, "Дальность"]] if kind == Kind.WEAPON else [[Stat.PHYSICAL_RESISTANCE, "Защита"], [Stat.DARK_RESISTANCE, "Маг.защита"]]
	for extra in [[Stat.DARK_DAMAGE, "Тёмн.урон"], [Stat.LIGHT_DAMAGE, "Светл.урон"], [Stat.MAX_HP, "Здоровье"], [Stat.MAX_MANA, "Мана"]]:
		if next[extra[0]] != unit.stats[extra[0]]: fields.append(extra)
	var result: Array = []
	for field: Array in fields:
		var stat: int = field[0]
		var scale: float = 20.0 if stat in [Stat.PHYSICAL_DAMAGE, Stat.DARK_DAMAGE, Stat.LIGHT_DAMAGE] else 1.0
		result.append([field[1], int(unit.stats[stat] / scale), int(next[stat] / scale)])
	return result


func _action_y() -> int:
	return maxi(170, 96 + comparison().size() * 17 + 12)


func _arrow(point: Vector2, color: Color) -> void:
	draw_line(point, point + Vector2(10, 0), color, 2)
	draw_line(point + Vector2(6, -3), point + Vector2(10, 0), color, 2)
	draw_line(point + Vector2(10, 0), point + Vector2(6, 3), color, 2)


func _draw() -> void:
	if images.is_empty(): return
	if hd_screen != null and hd_screen.active(): return
	begin_draw()
	match screen:
		&"party":
			for index in range(game.party.size()): write(str(data["unit_names"][game.party[index].unit_type]), Vector2(48, 24 + index * 17))
			selection_arrow(Vector2(20, 22 + party_index * 17))
		&"character": _draw_character()
		&"journal", &"quest": _draw_journal()
		_: _draw_inventory()
	if not message.is_empty(): write(message, Vector2(120, 282), HORIZONTAL_ALIGNMENT_CENTER)
	footer()
	finish_draw()

func _gui_input(event: InputEvent) -> void:
	if hd_screen != null and hd_screen.active(): return
	super._gui_input(event)


func quest_state(quest: Dictionary) -> String:
	return {Ids.QuestState.ACTIVE: "Выполняется", Ids.QuestState.COMPLETED: "Завершено", Ids.QuestState.FAILED: "Провалено"}.get(int(game.quests[int(quest["id"])]), "")


func quest_lines() -> PackedStringArray:
	if quests.is_empty(): return []
	return wrap_lines(str(quests[selected]["title"]) + "\n" + quest_state(quests[selected]) + "\n\n" + str(quests[selected]["text"]), 200)


func _draw_journal() -> void:
	write("Журнал", Vector2(120, 9), HORIZONTAL_ALIGNMENT_CENTER)
	if quests.is_empty():
		write("Нет заданий", Vector2(120, 90), HORIZONTAL_ALIGNMENT_CENTER)
		return
	if screen == &"quest":
		var lines: PackedStringArray = quest_lines()
		for index in range(scroll, mini(scroll + 14, lines.size())): write(lines[index], Vector2(20, 44 + (index - scroll) * 14))
		if lines.size() > 14: write("%d/%d" % [scroll + 1, maxi(1, lines.size() - 13)], Vector2(210, 264), HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		var first: int = maxi(0, selected - 4)
		for index in range(first, mini(first + 5, quests.size())):
			var y: int = 35 + (index - first) * 46
			var title: PackedStringArray = wrap_lines(str(quests[index]["title"]), 185)
			for line in range(mini(2, title.size())): write(title[line], Vector2(30, y + line * 13))
			write(quest_state(quests[index]), Vector2(30, y + 27), HORIZONTAL_ALIGNMENT_LEFT, Color(0.6, 0.6, 0.6))
		selection_arrow(Vector2(9, 33 + (selected - first) * 46))


func experience_progress() -> Dictionary:
	var level: int = actor().base_stats[Stat.LEVEL]
	var experience: int = actor().base_stats[Stat.EXPERIENCE]
	var lower: int = Rewards.threshold(level - 1) if level > 0 else 0
	var upper: int = Rewards.threshold(level)
	return {"experience": experience, "next": upper, "level": level + 1, "ratio": clampf(float(experience - lower) / maxi(1, upper - lower), 0, 1)}


func _draw_character() -> void:
	var unit = actor()
	draw_portrait_rect(int(game.definitions["portrait_images"][unit.unit_type]), Rect2(20, 9, 48, 52))
	var arrow_width: int = int(images[UiImage.SMALL_ARROWS].get_width() / 2.0)
	if party_index > 0: icon(UiImage.SMALL_ARROWS, 0, Vector2(10, 30), arrow_width, 8)
	if party_index + 1 < game.party.size(): icon(UiImage.SMALL_ARROWS, 1, Vector2(70, 30), arrow_width, 8)
	var progress: Dictionary = experience_progress()
	write("%d/%d" % [progress["experience"], progress["next"]], Vector2(82, 7))
	var bar := Rect2(82, 23, 105, 11)
	draw_rect(bar, Color("ffe8a0"), false, 1)
	draw_rect(Rect2(bar.position + Vector2.ONE, Vector2(103 * float(progress["ratio"]), 9)), Color("ffe8a0"))
	write("Ур.: %d" % int(progress["level"]), Vector2(82, 39))
	write("Школы" if schools else "Характеристики", Vector2(80, 57))
	var effective: PackedInt32Array = Progression.preview(game, unit, draft)
	var rows: Array[int] = slots()
	var first: int = maxi(0, selected - 6) if schools else 0
	var short_names := {Stat.ENDURANCE: "Слож", Stat.INTELLECT: "Инт.", Stat.STRENGTH: "Сила", Stat.DEXTERITY: "Ловк", Stat.LUCK: "Удач"}
	short_names.merge({Stat.ATTACK: "Атака", Stat.DEFENSE: "Защита", Stat.TACTICS: "Тактика", Stat.ARCHERY: "Стрельба", Stat.ASSASSINATION: "Убийца", Stat.ATHLETICS: "Атлетика", Stat.LIGHT_FIRE_MAGIC: "Свет.огонь", Stat.LIGHT_EARTH_MAGIC: "Земля", Stat.LIGHT_WATER_MAGIC: "Вода", Stat.LIGHT_AIR_MAGIC: "Свет.воздух", Stat.LIGHT_ASTRAL_MAGIC: "Астрал", Stat.DARK_FIRE_MAGIC: "Огонь", Stat.DARK_EARTH_MAGIC: "Тёмн.земля", Stat.DARK_WATER_MAGIC: "Тёмн.вода", Stat.DARK_AIR_MAGIC: "Воздух", Stat.DARK_ASTRAL_MAGIC: "Тёмн.астрал"})
	for index in range(first, mini(first + 7, rows.size())):
		var stat: int = rows[index]
		var y: int = 74 + (index - first) * 16
		var title: String = short_names.get(stat, str(game.definitions["economy"]["stat_names"][stat]).left(13))
		write(title, Vector2(20 if schools else 30, y))
		write(str(draft["base"][stat] - (1 if schools else 0)), Vector2(138 if schools else 112, y), HORIZONTAL_ALIGNMENT_RIGHT)
		write("/", Vector2(154 if schools else 130, y))
		write(str(effective[stat] - (1 if schools else 0)), Vector2(181 if schools else 158, y))
		if editing and index == selected:
			selection_arrow(Vector2(1 if schools else 9, y - 2))
			if int(draft["skill_points" if schools else "attribute_points"]) > 0 and (not schools or draft["base"][stat] < 25):
				var x: int = 143 if schools else 119
				draw_colored_polygon(PackedVector2Array([Vector2(x, y + 3), Vector2(x + 4, y + 7), Vector2(x, y + 11)]), Color("f2c973"))
	var points_y: int = 190 if schools else 158
	write("Очки повыш.:", Vector2(20, points_y))
	write(str(draft["skill_points" if schools else "attribute_points"]), Vector2(185, points_y), HORIZONTAL_ALIGNMENT_RIGHT)
	var help: String = "Ввод - выбор характеристики" if not editing else "Влево/вправо - изменить"
	if editing and not schools:
		help = {Stat.ENDURANCE: "Повышает здоровье и броню", Stat.INTELLECT: "Повышает ману и мощь заклятий", Stat.STRENGTH: "Повышает броню и мощь удара", Stat.DEXTERITY: "Влияет на подвижность", Stat.LUCK: "Влияет на удачу в бою"}[rows[selected]]
	elif editing and schools and not rows.is_empty():
		var hints: Array = game.definitions["economy"]["skill_help"]
		var start: int = (rows[selected] - Stat.ATTACK + 1) * 6
		if start < hints.size(): help = str(hints[start])
	var lines: PackedStringArray = wrap_lines(help, 200)
	for index in range(mini(2, lines.size())): write(lines[index], Vector2(120, points_y + (22 if schools else 27) + index * 14), HORIZONTAL_ALIGNMENT_CENTER)
	write("Характеристики", Vector2(20, 242), HORIZONTAL_ALIGNMENT_LEFT, Color.WHITE if not schools else Color(0.5, 0.5, 0.5))
	write("Школы", Vector2(155, 242), HORIZONTAL_ALIGNMENT_LEFT, Color.WHITE if schools else Color(0.5, 0.5, 0.5))
	if editing:
		write("Применить", Vector2(20, 264))
		write("Отменить", Vector2(140, 264))


func _draw_inventory() -> void:
	if item() == null:
		write("Инвентарь пуст", Vector2(120, 80), HORIZONTAL_ALIGNMENT_CENTER)
		return
	var entry = item()
	write("%d/%d" % [selected + 1, candidates.size()], Vector2(18, 8))
	var title: String = str(game.definitions["economy"]["item_names"][entry.definition_id])
	var lines: PackedStringArray = wrap_lines(title, 132)
	for index in range(mini(2, lines.size())): write(lines[index], Vector2(100, 8 + index * 14))
	var arrow_width: int = int(images[UiImage.SMALL_ARROWS].get_width() / 2.0)
	if selected > 0: icon(UiImage.SMALL_ARROWS, 0, Vector2(48, 10), arrow_width, 8)
	if selected + 1 < candidates.size(): icon(UiImage.SMALL_ARROWS, 1, Vector2(78, 10), arrow_width, 8)
	draw_rect(Rect2(34, 23, 50, 50), Color.BLACK)
	draw_rect(Rect2(34, 23, 50, 50), Color.GREEN if Inventory.owner(game, entry) == actor() else Color("bd9438"), false, 1)
	if entry.definition_id < Ids.ItemId.FIRST_CRYSTAL: draw_texture(images[Ids.EconomyImage.ITEM_BASE + entry.definition_id], Vector2(35, 24))
	else: icon(Ids.EconomyImage.CRYSTAL_ATLAS, entry.definition_id - Ids.ItemId.FIRST_CRYSTAL, Vector2(51, 40), 16)
	draw_portrait(int(game.definitions["unit_portrait_images"][actor().unit_type]), Vector2(95, 39))
	for slot in range(entry.sockets.size()): icon(UiImage.ITEM_SOCKETS, 0 if entry.sockets[slot] < 0 else entry.sockets[slot] - Ids.ItemId.FIRST_CRYSTAL + 1, Vector2(78, 25 + slot * 5), 5)
	if screen == &"items":
		if entry.definition_id >= Ids.ItemId.FIRST_CRYSTAL:
			var description: String = str(game.definitions["economy"]["crystal_descriptions"][entry.definition_id - Ids.ItemId.FIRST_CRYSTAL])
			var detail: PackedStringArray = wrap_lines(description, 200)
			for index in range(mini(8, detail.size())): write(detail[index], Vector2(20, 96 + index * 15))
		else:
			var y: int = 96
			for row: Array in comparison():
				write(str(row[0]) + ":", Vector2(20, y))
				write(str(row[1]), Vector2(128, y), HORIZONTAL_ALIGNMENT_RIGHT)
				_arrow(Vector2(136, y + 6), Color("159bff"))
				write(str(row[2]), Vector2(156, y))
				y += 17
			var kind: int = int(Inventory.definition(game, entry.definition_id)["kind"])
			var action: String = ("Убрать" if kind == Kind.WEAPON else "Снять") if Inventory.owner(game, entry) == actor() else "Надеть"
			write(action, Vector2(54, _action_y()))
			write("Кристаллы", Vector2(54, _action_y() + 20))
			selection_arrow(Vector2(29, _action_y() - 2 + action_index * 20))
	elif screen == &"sockets":
		for index in range(entry.sockets.size()):
			write("Гнездо %d: %s" % [index + 1, "пусто" if entry.sockets[index] < 0 else str(game.definitions["economy"]["item_names"][entry.sockets[index]])], Vector2(27, 100 + index * 20))
		selection_arrow(Vector2(8, 98 + slot_index * 20))
		write("Ввод - вставить / извлечь", Vector2(20, 240))
	elif screen == &"crystals":
		if crystals.is_empty(): write("Нет свободных кристаллов", Vector2(20, 100))
		var first: int = maxi(0, action_index - 7)
		for index in range(first, mini(first + 8, crystals.size())): write(str(game.definitions["economy"]["item_names"][crystals[index].definition_id]), Vector2(27, 100 + (index - first) * 18))
		if not crystals.is_empty(): selection_arrow(Vector2(8, 98 + (action_index - first) * 18))
