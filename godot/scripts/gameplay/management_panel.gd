extends Control
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Stat = Ids.Stat
const Page = Ids.ManagementPage
const Kind = Ids.ItemKind
const Inventory = preload("res://scripts/gameplay/inventory_rules.gd")
const Progression = preload("res://scripts/gameplay/progression_rules.gd")
const UiTheme = preload("res://scripts/gameplay/legacy_theme.gd")
const Journal = preload("res://scripts/gameplay/quest_journal.gd")
signal closed

var ui_icons
var game
var campaign_data: Dictionary
var images: Dictionary
var page: int = Page.CHARACTER
var actor_id: int = -1
var selected_item_id: int = -1
var selected_crystal_id: int = -1
var selected_definition_id: int = -1
var draft: Dictionary = {}
var receipt: Dictionary = {}
var content: VBoxContainer
var tabs: HBoxContainer
var party_select: OptionButton
var heading: Label
var notice: Label
var attribute_buttons: Dictionary = {}
var apply_button: Button
var item_list: ItemList
var buy_button: Button
var equip_button: Button
var close_button: Button
var commerce_enabled: bool = false
var panel: PanelContainer
var character_header: HBoxContainer
var portrait: TextureRect
var resources: Label
var hd_loot: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := UiTheme.world_shade()
	add_child(shade)
	panel = PanelContainer.new()
	panel.theme_type_variation = "WorldOverlay"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 320
	panel.offset_right = -24
	panel.offset_top = 24
	panel.offset_bottom = -24
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	character_header = HBoxContainer.new()
	character_header.add_theme_constant_override("separation", 20)
	column.add_child(character_header)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(80, 104)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	character_header.add_child(portrait)
	resources = label(character_header, "")
	resources.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading = label(column, "")
	heading.add_theme_font_size_override("font_size", 26)
	tabs = HBoxContainer.new()
	column.add_child(tabs)
	var titles := {Page.CHARACTER: "Персонаж", Page.INVENTORY: "Снаряжение", Page.SHOP: "Лавка", Page.JOURNAL: "Журнал"}
	for id in titles:
		button(tabs, titles[id], func(): switch_page(id))
	party_select = OptionButton.new()
	column.add_child(party_select)
	party_select.item_selected.connect(func(index: int):
		actor_id = party_select.get_item_id(index)
		draft = {}
		selected_item_id = -1
		render()
	)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	notice = label(column, "")
	notice.add_theme_color_override("font_color", Color("d8be80"))
	close_button = button(column, "Закрыть · Esc", dismiss)
	hd_loot = preload("res://scripts/gameplay/hd_remaining_screen.gd").new()
	hd_loot.kind = &"loot"
	hd_loot.controller = self
	add_child(hd_loot)
	visible = false


func label(parent: Node, text: String) -> Label:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(node)
	return node


func button(parent: Node, text: String, action: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.pressed.connect(action)
	parent.add_child(node)
	return node


func open(session, data: Dictionary, textures: Dictionary, initial_page: int, loot: Dictionary = {}, town: bool = false) -> void:
	game = session
	campaign_data = data
	images = textures
	commerce_enabled = town
	tabs.get_child(Page.SHOP).visible = town
	Inventory.sync_party(game)
	actor_id = game.hero.instance_id
	receipt = loot
	hd_loot.reset()
	party_select.clear()
	for actor in game.party: party_select.add_item(str(data["unit_names"][actor.unit_type]), actor.instance_id)
	notice.text = ""
	visible = true
	switch_page(initial_page)


func dismiss() -> void:
	if not visible: return
	draft = {}
	visible = false
	closed.emit()


func switch_page(next: int) -> void:
	if next == Page.SHOP and not commerce_enabled: return
	draft = {}
	page = next
	selected_definition_id = -1
	notice.text = ""
	render()


func actor():
	for unit in game.party:
		if unit.instance_id == actor_id: return unit
	return game.hero


func render() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	attribute_buttons.clear()
	party_select.visible = page in [Page.CHARACTER, Page.INVENTORY]
	character_header.visible = party_select.visible
	if character_header.visible:
		var hero = actor()
		portrait.texture = ui_icons.portrait(int(game.definitions["portrait_images"][hero.unit_type])) if ui_icons != null else images[int(game.definitions["portrait_images"][hero.unit_type])]
		resources.text = "%s\nЗдоровье %d / %d\nМана %d / %d · уровень %d" % [campaign_data["unit_names"][hero.unit_type], hero.stats[Stat.HP], hero.stats[Stat.MAX_HP], hero.stats[Stat.MANA], hero.stats[Stat.MAX_MANA], hero.base_stats[Stat.LEVEL]]
	tabs.visible = page != Page.LOOT
	heading.visible = page != Page.LOOT
	notice.visible = page != Page.LOOT
	var titles := {Page.CHARACTER: "Развитие персонажа", Page.INVENTORY: "Снаряжение и кристаллы", Page.SHOP: "Лавка", Page.JOURNAL: "Журнал заданий", Page.LOOT: "Получено"}
	heading.text = "%s · золото %d" % [titles[page], game.gold]
	close_button.text = "Принять · Enter" if page == Page.LOOT else ("Закрыть без применения · Esc" if page == Page.CHARACTER else "Закрыть · Esc")
	match page:
		Page.CHARACTER: render_character()
		Page.INVENTORY: render_inventory()
		Page.SHOP: render_shop()
		Page.JOURNAL: render_journal()
		Page.LOOT: render_loot()


func stat_name(slot: int) -> String:
	var names: Array = game.definitions["economy"]["stat_names"]
	return str(names[slot]) if slot < names.size() else "Резерв"


func render_character() -> void:
	var unit = actor()
	if draft.is_empty(): draft = Progression.begin(game, unit)
	var effective: PackedInt32Array = Progression.preview(game, unit, draft)
	label(content, "Уровень %d · опыт %d · очки: %d характеристик / %d школ\nПредпросмотр: HP %d · MP %d · ОД %d · защита %d" % [unit.base_stats[Stat.LEVEL], unit.base_stats[Stat.EXPERIENCE], draft["attribute_points"], draft["skill_points"], effective[Stat.MAX_HP], effective[Stat.MAX_MANA], effective[Stat.MAX_ACTION_POINTS], effective[Stat.PHYSICAL_RESISTANCE]])
	for slot in Progression.ATTRIBUTES: training_row(slot, false)
	label(content, "Доступные школы")
	for slot in range(Stat.ATTACK, Stat.RESERVED):
		if Progression.editable(draft, slot): training_row(slot, true)
	apply_button = button(content, "Применить развитие", func():
		if Progression.commit(game, unit, draft):
			draft = {}
			notice.text = "Очки распределены."
		else: notice.text = "Состояние изменилось. Откройте персонажа заново."
		render()
	)


func training_row(slot: int, school: bool) -> void:
	var row := HBoxContainer.new()
	content.add_child(row)
	var preview: PackedInt32Array = Progression.preview(game, actor(), draft)
	var title := label(row, "%s: %d" % [stat_name(slot), draft["base"][slot] - 1] if school else "%s: %d / %d" % [stat_name(slot), draft["base"][slot], preview[slot]])
	if not school:
		var help := {Stat.ENDURANCE: "Повышает здоровье и броню", Stat.INTELLECT: "Повышает ману и мощь заклятий", Stat.STRENGTH: "Повышает броню и мощь удара", Stat.DEXTERITY: "Влияет на подвижность", Stat.LUCK: "Влияет на удачу в бою"}
		row.mouse_entered.connect(func(): notice.text = help[slot])
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var minus := button(row, "−", func():
		Progression.adjust(draft, slot, -1)
		render()
	)
	minus.disabled = draft["base"][slot] <= draft["original"][slot]
	var plus := button(row, "+", func():
		Progression.adjust(draft, slot, 1)
		render()
	)
	plus.disabled = int(draft["skill_points" if school else "attribute_points"]) <= 0 or (school and draft["base"][slot] >= 25)
	attribute_buttons[slot] = plus
	if school:
		var help: Array = game.definitions["economy"]["skill_help"]
		var start: int = (slot - Stat.ATTACK + 1) * 6
		var lines: PackedStringArray = []
		for i in range(start, mini(start + 6, help.size())):
			if str(help[i]) not in [".", ".."]: lines.append(str(help[i]))
		plus.tooltip_text = "\n".join(lines)


func icon(id: int) -> Texture2D:
	if id < Ids.ItemId.FIRST_CRYSTAL: return images[Ids.EconomyImage.ITEM_BASE + id]
	var texture := AtlasTexture.new()
	texture.atlas = images[Ids.EconomyImage.CRYSTAL_ATLAS]
	texture.region = Rect2((id - Ids.ItemId.FIRST_CRYSTAL) * 16, 0, 16, 16)
	return texture


func item_name(id: int) -> String:
	return str(game.definitions["economy"]["item_names"][id])


func render_inventory() -> void:
	var unit = actor()
	label(content, "Надето: %s / %s" % [item_name(unit.weapon.definition_id) if unit.weapon != null else "без оружия", item_name(unit.armor.definition_id) if unit.armor != null else "без брони"])
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	content.add_child(body)
	item_list = ItemList.new()
	item_list.custom_minimum_size = Vector2(320, 360)
	item_list.fixed_icon_size = Vector2i(40, 40)
	item_list.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.add_child(item_list)
	var candidates: Array = Inventory.ordered_available(game, unit)
	for item in candidates:
		item_list.add_item(item_name(item.definition_id) + (" · надето" if Inventory.owner(game, item) != null else ""), icon(item.definition_id))
		item_list.set_item_metadata(item_list.item_count - 1, item.instance_id)
	if candidates.is_empty():
		label(body, "Инвентарь пуст.")
		return
	var item = Inventory.find(game, selected_item_id)
	if item == null or item not in candidates:
		item = candidates[0]
		selected_item_id = item.instance_id
	for i in range(item_list.item_count):
		if item_list.get_item_metadata(i) == selected_item_id: item_list.select(i)
	item_list.item_selected.connect(func(index: int):
		selected_item_id = int(item_list.get_item_metadata(index))
		render()
	)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(detail)
	label(detail, item_name(item.definition_id))
	label(detail, "Цена %d · продажа %d" % [Inventory.price(game, item), int(Inventory.price(game, item) / 2.0)])
	var spec: Dictionary = Inventory.definition(game, item.definition_id)
	if int(spec["kind"]) == Kind.CRYSTAL:
		label(detail, str(game.definitions["economy"]["crystal_descriptions"][item.definition_id - Ids.ItemId.FIRST_CRYSTAL]))
		return
	var wearer = Inventory.owner(game, item)
	equip_button = button(detail, "Снять" if wearer == unit else "Надеть", func():
		if wearer == unit: Inventory.unequip(game, unit, int(spec["kind"]))
		else: Inventory.equip(game, unit, item.instance_id)
		render()
	)
	equip_button.disabled = wearer != null and wearer != unit
	var prospective: PackedInt32Array = Inventory.preview_stats(game, unit, item)
	label(detail, "Если надеть:\nЗащита %d → %d\nФиз. урон %d → %d\nHP %d → %d · MP %d → %d" % [unit.stats[Stat.PHYSICAL_RESISTANCE], prospective[Stat.PHYSICAL_RESISTANCE], int(unit.stats[Stat.PHYSICAL_DAMAGE] / 20.0), int(prospective[Stat.PHYSICAL_DAMAGE] / 20.0), unit.stats[Stat.MAX_HP], prospective[Stat.MAX_HP], unit.stats[Stat.MAX_MANA], prospective[Stat.MAX_MANA]])
	var crystals := OptionButton.new()
	detail.add_child(crystals)
	for crystal in Inventory.available(game, null, Kind.CRYSTAL):
		crystals.add_item(item_name(crystal.definition_id), crystal.instance_id)
		if crystal.instance_id == selected_crystal_id: crystals.select(crystals.item_count - 1)
	if crystals.item_count > 0: selected_crystal_id = crystals.get_selected_id()
	else:
		selected_crystal_id = -1
		crystals.add_item("Нет свободных кристаллов", -1)
		crystals.disabled = true
	crystals.item_selected.connect(func(index: int): selected_crystal_id = crystals.get_item_id(index))
	for slot in range(item.sockets.size()):
		var filled: bool = item.sockets[slot] >= 0
		var action := button(detail, "Гнездо %d: %s · извлечь" % [slot + 1, item_name(item.sockets[slot])] if filled else "Гнездо %d: вставить выбранный кристалл" % (slot + 1), func():
			if filled: Inventory.remove(game, item.instance_id, slot)
			else: Inventory.insert(game, item.instance_id, selected_crystal_id, slot)
			render()
		)
		action.disabled = not filled and selected_crystal_id < 0


func render_shop() -> void:
	label(content, "Продажа — половина цены вместе с вставленными кристаллами. Надетую вещь сначала нужно снять.")
	var stock := OptionButton.new()
	content.add_child(stock)
	for id in Inventory.stock(game):
		stock.add_item("%s · %d зол." % [item_name(id), Inventory.definition(game, id)["price"]], id)
		if id == selected_definition_id: stock.select(stock.item_count - 1)
	selected_definition_id = stock.get_selected_id()
	stock.item_selected.connect(func(index: int):
		selected_definition_id = stock.get_item_id(index)
		render()
	)
	buy_button = button(content, "Купить", func():
		notice.text = "Предмет куплен." if Inventory.buy(game, selected_definition_id) else "Недостаточно золота или товар недоступен."
		render()
	)
	buy_button.disabled = game.gold < int(Inventory.definition(game, selected_definition_id)["price"])
	label(content, "Продажа имущества отряда")
	for item in Inventory.available(game):
		var row := HBoxContainer.new()
		content.add_child(row)
		var text: String = "%s · %d зол." % [item_name(item.definition_id), int(Inventory.price(game, item) / 2.0)]
		var wearer = Inventory.owner(game, item)
		if wearer != null: text += " · надето: " + str(campaign_data["unit_names"][wearer.unit_type])
		var title := label(row, text)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sell := button(row, "Продать", func():
			notice.text = "Предмет продан." if Inventory.sell(game, item.instance_id) else "Продажа недоступна."
			render()
		)
		# Equipped gear requires explicit removal in the equipment page first.
		sell.disabled = wearer != null


func render_journal() -> void:
	var states := {Ids.QuestState.ACTIVE: "Выполняется", Ids.QuestState.COMPLETED: "Завершено", Ids.QuestState.FAILED: "Провалено"}
	for quest: Dictionary in Journal.entries(campaign_data["quests"], game.quests):
		var state: int = int(game.quests[int(quest["id"])])
		label(content, "%s · %s" % [states[state], quest["title"]]).add_theme_color_override("font_color", Color("82e191") if state == Ids.QuestState.COMPLETED else Color("e9d8aa"))
		label(content, str(quest["text"]))


func render_loot() -> void:
	var gold_row := HBoxContainer.new()
	content.add_child(gold_row)
	var gold_title := label(gold_row, "Золото:")
	gold_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var amount := label(gold_row, str(int(receipt.get("gold", 0))))
	amount.autowrap_mode = TextServer.AUTOWRAP_OFF
	amount.custom_minimum_size.x = 80
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for id in receipt.get("items", []):
		var row := HBoxContainer.new()
		content.add_child(row)
		var picture := TextureRect.new()
		picture.texture = icon(int(id))
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.custom_minimum_size = Vector2(48, 48)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(picture)
		var title := label(row, item_name(int(id)))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
