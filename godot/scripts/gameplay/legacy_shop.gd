extends "res://scripts/gameplay/legacy_ui_screen.gd"
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Stat = Ids.Stat
const Inventory = preload("res://scripts/gameplay/inventory_rules.gd")
const Item = preload("res://scripts/gameplay/item_instance.gd")
const YES_RECT := Rect2(52, 249, 56, 24)
const BACK_RECT := Rect2(132, 249, 66, 24)
signal closed
var game
var selected: int = 0
var selling: bool = false
var screen: StringName = &"choice"
var candidates: Array = []
var message: String = ""
var buy_button: Hotspot
var sell_button: Hotspot


func open(session, textures: Dictionary) -> void:
	game = session
	setup(textures, game.definitions)
	visible = true
	screen = &"choice"
	selected = 0
	_refresh()


func _refresh() -> void:
	clear_regions()
	if screen == &"choice":
		for i in range(2): region(Rect2(70, 88 + i * 18, 110, 18), func(): selected = i; confirm())
	else:
		candidates.clear()
		if selling:
			candidates = Inventory.available(game)
		else:
			for id in Inventory.stock(game): candidates.append(Item.new(-id - 1, id))
		selected = clampi(selected, 0, maxi(0, candidates.size() - 1))
		region(Rect2(10, 24, 40, 16), func(): navigate(-1))
		region(Rect2(195, 24, 35, 16), func(): navigate(1))
		if screen == &"confirm":
			region(YES_RECT, confirm, "Да")
			region(BACK_RECT, back, "Назад")
		var action: Hotspot = region(Rect2(10, 294, 100, 25), confirm)
		buy_button = action
		sell_button = action
	region(Rect2(130, 294, 100, 25), back)
	queue_redraw()


func navigate(step: int) -> void:
	message = ""
	if screen == &"choice": selected = posmod(selected + step, 2)
	elif not candidates.is_empty(): selected = clampi(selected + step, 0, candidates.size() - 1)
	queue_redraw()


func confirm() -> void:
	if screen == &"choice":
		selling = selected == 1
		selected = 0
		screen = &"items"
	elif screen == &"confirm":
		var item = candidates[selected]
		var ok: bool = Inventory.sell(game, item.instance_id) if selling else Inventory.buy(game, item.definition_id)
		message = "Продано" if ok and selling else "Куплено" if ok else "Недостаточно денег"
		screen = &"items"
	elif not candidates.is_empty():
		if not selling and game.gold < Inventory.price(game, candidates[selected]): message = "Недостаточно денег"
		else: screen = &"confirm"
	_refresh()


func back() -> void:
	message = ""
	if screen == &"confirm": screen = &"items"
	elif screen == &"items":
		screen = &"choice"
		selected = 1 if selling else 0
	else:
		visible = false
		closed.emit()
	_refresh()


func _actor(item):
	var owner = Inventory.owner(game, item)
	if owner != null: return owner
	var type: int = int(Inventory.definition(game, item.definition_id)["hero_type"])
	for actor in game.party:
		if actor.unit_type == type: return actor
	return null


func _comparison(item) -> Array:
	var actor = _actor(item)
	if actor == null or item.definition_id >= Ids.ItemId.FIRST_CRYSTAL: return []
	var empty: PackedInt32Array = Inventory.preview_stats(game, actor, item, true)
	var equipped: PackedInt32Array = Inventory.preview_stats(game, actor, item)
	var rows: Array = []
	for slot in [Stat.PHYSICAL_DAMAGE, Stat.DARK_DAMAGE, Stat.LIGHT_DAMAGE, Stat.PHYSICAL_RESISTANCE, Stat.DARK_RESISTANCE, Stat.LIGHT_RESISTANCE, Stat.MAX_HP, Stat.MAX_MANA]:
		if equipped[slot] == empty[slot]: continue
		var current: int = actor.stats[slot]
		var next: int = empty[slot] if selling and Inventory.owner(game, item) == actor else equipped[slot]
		if slot in [Stat.PHYSICAL_DAMAGE, Stat.DARK_DAMAGE, Stat.LIGHT_DAMAGE]:
			current = int(current / 20.0)
			next = int(next / 20.0)
		rows.append([str(game.definitions["economy"]["stat_names"][slot]), current, next])
	return rows


func _draw() -> void:
	if images.is_empty(): return
	begin_draw()
	if screen == &"choice":
		write("Магазин", Vector2(120, 28), HORIZONTAL_ALIGNMENT_CENTER)
		write("Покупка", Vector2(108, 88))
		write("Продажа", Vector2(108, 106))
		selection_arrow(Vector2(67, 88 + selected * 18))
	elif candidates.is_empty(): write("Нет предметов", Vector2(120, 100), HORIZONTAL_ALIGNMENT_CENTER)
	else:
		var item = candidates[selected]
		write("%d/%d" % [selected + 1, candidates.size()], Vector2(38, 9), HORIZONTAL_ALIGNMENT_RIGHT)
		write("Продажа" if selling else "Покупка", Vector2(120, 9), HORIZONTAL_ALIGNMENT_CENTER)
		write(str(game.definitions["economy"]["item_names"][item.definition_id]), Vector2(120, 22), HORIZONTAL_ALIGNMENT_CENTER)
		var arrow_width: int = int(images[UiImage.SMALL_ARROWS].get_width() / 2.0)
		if selected > 0: icon(UiImage.SMALL_ARROWS, 0, Vector2(23, 30), arrow_width, 8)
		if selected < candidates.size() - 1: icon(UiImage.SMALL_ARROWS, 1, Vector2(214, 30), arrow_width, 8)
		var equipped: bool = Inventory.owner(game, item) != null
		draw_rect(Rect2(16, 38, 50, 50), Color.GREEN if equipped else Color("9d6e0c"), false, 1)
		if item.definition_id < Ids.ItemId.FIRST_CRYSTAL: draw_texture(images[Ids.EconomyImage.ITEM_BASE + item.definition_id], Vector2(17, 39))
		else: icon(Ids.EconomyImage.CRYSTAL_ATLAS, item.definition_id - Ids.ItemId.FIRST_CRYSTAL, Vector2(33, 55), 16)
		for slot in range(item.sockets.size()):
			icon(UiImage.ITEM_SOCKETS, 0 if item.sockets[slot] < 0 else item.sockets[slot] - Ids.ItemId.FIRST_CRYSTAL + 1, Vector2(59, 39 + slot * 5), 5)
		var actor = _actor(item)
		if actor != null: draw_portrait(int(game.definitions["unit_portrait_images"][actor.unit_type]), Vector2(69, 68))
		write("Деньги:", Vector2(88, 40))
		write("Цена:", Vector2(88, 54))
		write(str(game.gold), Vector2(221, 40), HORIZONTAL_ALIGNMENT_RIGHT)
		var price: int = Inventory.price(game, item)
		write(str(int(price / 2.0) if selling else price), Vector2(221, 54), HORIZONTAL_ALIGNMENT_RIGHT)
		var row_y: int = 102
		for row: Array in _comparison(item):
			write(str(row[0]) + ":", Vector2(20, row_y))
			write(str(row[1]), Vector2(158, row_y), HORIZONTAL_ALIGNMENT_RIGHT)
			var color := Color("ff3333") if row[2] < row[1] else Color("27c7ff") if row[2] == row[1] else Color.GREEN
			var tilt: int = 4 if row[2] < row[1] else -4 if row[2] > row[1] else 0
			draw_line(Vector2(166, row_y + 6 - tilt), Vector2(177, row_y + 6 + tilt), color, 2)
			draw_line(Vector2(172, row_y + 2 + tilt), Vector2(177, row_y + 6 + tilt), color, 2)
			draw_line(Vector2(177, row_y + 6 + tilt), Vector2(172, row_y + 10 + tilt), color, 2)
			write(str(row[2]), Vector2(194, row_y))
			row_y += 15
		if screen == &"confirm":
			draw_rect(Rect2(18, 226, 204, 47), Color.BLACK)
			write("Продать?" if selling else "Купить?", Vector2(120, 236), HORIZONTAL_ALIGNMENT_CENTER)
			write("Да", Vector2(YES_RECT.get_center().x, 254), HORIZONTAL_ALIGNMENT_CENTER)
			write("Назад", Vector2(BACK_RECT.get_center().x, 254), HORIZONTAL_ALIGNMENT_CENTER)
	if not message.is_empty(): write(message, Vector2(120, 278), HORIZONTAL_ALIGNMENT_CENTER)
	footer()
	finish_draw()
