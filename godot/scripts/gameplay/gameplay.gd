extends Control
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Spell = Ids.Spell
const Side = Ids.Side
const Stat = Ids.Stat
## Exploration input/HUD; simulation and rendering are independent components.

const CursorService = preload("res://scripts/gameplay/cursor_service.gd")
const CRTFilter = preload("res://scripts/gameplay/crt_filter.gd")
const Preferences = preload("res://scripts/gameplay/game_settings.gd")
const SoundEffects = preload("res://scripts/gameplay/sound_effects.gd")
const UIIcons = preload("res://scripts/gameplay/ui_icons.gd")
const MusicPlayer = preload("res://scripts/gameplay/music_player.gd")
const LegacyTheme = preload("res://scripts/gameplay/legacy_theme.gd")
const SaveService = preload("res://scripts/gameplay/save_service.gd")
const SaveSlots = preload("res://scripts/gameplay/save_slots.gd")
const MediaSettingsChecks = preload("res://tests/media_settings_checks.gd")
const InteractionChecks = preload("res://tests/ui_interaction_checks.gd")
const CorpseTargetingChecks = preload("res://tests/corpse_targeting_checks.gd")
const ReportedUIChecks = preload("res://tests/reported_ui_checks.gd")
const MapFourChecks = preload("res://tests/map_four_checks.gd")
const CombatNavigationChecks = preload("res://tests/combat_navigation_checks.gd")
const PresentationChecks = preload("res://tests/presentation_checks.gd")
const SaveChecks = preload("res://tests/save_checks.gd")
const FullCampaignChecks = preload("res://tests/full_campaign_checks.gd")
const Session = preload("res://scripts/gameplay/game_session.gd")
const View = preload("res://scripts/gameplay/game_map_view.gd")
const Checks = preload("res://tests/gameplay_checks.gd")
const Exploration = preload("res://scripts/gameplay/exploration_controller.gd")
const ExplorationChecks = preload("res://tests/exploration_checks.gd")
const Battle = preload("res://scripts/gameplay/battle_controller.gd")
const BattleChecks = preload("res://tests/battle_checks.gd")
const Encounter = preload("res://scripts/gameplay/encounter_builder.gd")
const CombatChecks = preload("res://tests/combat_checks.gd")
const Campaign = preload("res://scripts/gameplay/campaign_runner.gd")
const CampaignChecks = preload("res://tests/campaign_checks.gd")
const BattleOverlay = preload("res://scripts/gameplay/battle_overlay.gd")
const ActionBar = preload("res://scripts/gameplay/battle_action_bar.gd")
const SpellRules = preload("res://scripts/gameplay/spell_rules.gd")
const MagicChecks = preload("res://tests/magic_checks.gd")
const ManagementPanel = preload("res://scripts/gameplay/management_panel.gd")
const LegacyManagement = preload("res://scripts/gameplay/legacy_management.gd")
const LegacyManagementChecks = preload("res://tests/legacy_management_checks.gd")
const Inventory = preload("res://scripts/gameplay/inventory_rules.gd")
const EconomyChecks = preload("res://tests/economy_checks.gd")
const EconomyUIChecks = preload("res://tests/economy_ui_checks.gd")
const Page = Ids.ManagementPage
const WorldMapPanel = preload("res://scripts/gameplay/world_map_panel.gd")
const TravelChecks = preload("res://tests/travel_checks.gd")
const TravelUIChecks = preload("res://tests/travel_ui_checks.gd")
const LegacyShop = preload("res://scripts/gameplay/legacy_shop.gd")
const TitleMenu = preload("res://scripts/gameplay/title_menu.gd")
const LegacyUIChecks = preload("res://tests/legacy_ui_checks.gd")
const GameMenu = preload("res://scripts/gameplay/game_menu.gd")
const GameMenuChoice = Ids.GameMenuChoice
const GameMenuChecks = preload("res://tests/game_menu_checks.gd")
var cursors: CursorService
var battle_cursor_action: StringName = &""
var crt_filter: CRTFilter
var preferences := Preferences.new()
var ui_icons := UIIcons.new()
var sound_effects: SoundEffects
var _settings_from_title: bool = false
var music: MusicPlayer
var debug_panel: VBoxContainer
var god_toggle: CheckButton
var debug_map_picker: OptionButton
var world_button: Button
var game_menu: GameMenu
var session := Session.new()
var exploration := Exploration.new()
var battle := Battle.new()
var campaign := Campaign.new()
var saves := SaveService.new()
var save_slots: SaveSlots
var _save_origin: StringName = &"game_menu"
var _loading_save: bool = false
var view: View
var sidebar_scroll: ScrollContainer
var sidebar_background: Panel
var dialogue_panel: PanelContainer
var debug_sidebar_visible: bool = false
var _dev_keys: Dictionary[int, bool] = {}
var _dev_chord_active: bool = false
var stats_label: Label
var status: Label
var move_button: Button
var stop_button: Button
var route: Array[Vector2i] = []
var moving: bool:
	get: return exploration.is_moving()
var metadata: Dictionary
var world: Dictionary
var table: Dictionary
var selected := Vector2i(-1, -1)
var held_keys: Dictionary[int, bool] = {}
var camera_toggle: CheckButton
var battle_controls: VBoxContainer
var battle_roster: VBoxContainer
var defend_button: Button
var wait_button: Button
var end_side_button: Button
var battle_banner: Label
var roster_buttons: Dictionary[int, Button] = {}
var mode_label: Label
var title_label: Label
var rewards: Dictionary
var attack_button: Button
var attack_target_id: int = -1
var result_controls: VBoxContainer
var result_label: Label
var continue_button: Button
var defeat_restart_button: Button
var campaign_data: Dictionary
var dialogue_layer: Control
var dialogue_title: Label
var dialogue_body: Label
var dialogue_counter: Label
var dialogue_portrait: TextureRect
var dialogue_next: Button
var dialogue_restart: Button
var dialogue_scroll: ScrollContainer
var quests_label: Label
var _script_locked: bool = false
var battle_overlay: BattleOverlay
var action_bar: ActionBar
var selected_spell: int = -1
var cast_cell := Vector2i(-1, -1)
var shot_targets: Array[int] = []
var management: ManagementPanel
var legacy_management: LegacyManagement
var world_panel: WorldMapPanel
var management_origin: StringName = &"exploration"
var shop: LegacyShop
var main_menu: TitleMenu
var _has_started: bool = false
var _menu_resume_mode: StringName = &"exploration"
var _game_menu_resume_mode: StringName = &"exploration"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_interface()
	var loaded: Dictionary = {}
	for path in ["world.json", "legacy/graphics.json", "legacy/gameplay.json", "tables/abilities.txt.json", "tables/rewards.txt.json", "campaign.json"]:
		if not FileAccess.file_exists("res://data/" + path):
			_fail("Нет данных %s. Выполните export-godot из README." % path)
			return
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))
		if not parsed is Dictionary:
			_fail("Повреждён JSON: %s. Повторите export-godot." % path)
			return
		loaded[path] = parsed
	world = loaded["world.json"]
	metadata = loaded["legacy/gameplay.json"]
	table = loaded["tables/abilities.txt.json"]
	rewards = loaded["tables/rewards.txt.json"]
	campaign_data = loaded["campaign.json"]
	view.unit_names = campaign_data["unit_names"]
	view.configure(world, loaded["legacy/graphics.json"])
	theme = LegacyTheme.create(view.textures, metadata)
	sidebar_scroll.theme = theme.duplicate()
	sidebar_scroll.theme.default_font_size = 20
	view.ui_frame = theme.get_stylebox("panel", "Panel").duplicate()
	view.ui_frame.draw_center = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	music = MusicPlayer.new()
	add_child(music)
	if "--gameplay-test" in OS.get_cmdline_user_args(): preferences.path = "user://media-run-%d.cfg" % Time.get_ticks_usec()
	preferences.load_settings()
	music.configure(preferences)
	sound_effects = SoundEffects.new()
	add_child(sound_effects)
	sound_effects.configure(preferences)
	ui_icons.configure(preferences, view.textures)
	crt_filter = CRTFilter.new()
	add_child(crt_filter)
	crt_filter.apply(bool(preferences.values["crt_enabled"]))
	cursors = CursorService.new()
	add_child(cursors)
	cursors.configure()
	for screen in [view, action_bar, management, legacy_management, shop]: screen.ui_icons = ui_icons
	preferences.changed.connect(_settings_changed)
	for screen in [main_menu, game_menu, legacy_management, shop, world_panel, save_slots]:
		screen.ui_action.connect(func(kind: String): sound_effects.play_clip("click_ok.wav" if kind == "confirm" else "back.wav", false))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-"): music.set_enabled(false, false)
	session.changed.connect(_refresh)
	session.location_changed.connect(_location_changed)
	exploration.walked.connect(func(actor_id: int, distance: float):
		if session.hero != null and actor_id == session.hero.instance_id: sound_effects.walk(actor_id, distance, session.location_id < 0)
	)
	exploration.route_finished.connect(_route_finished)
	exploration.encounter_detected.connect(_begin_battle)
	battle.changed.connect(_refresh)
	battle.presentation_event.connect(func(event: Dictionary): sound_effects.combat(event, battle))
	battle.combat_text.connect(func(point: Vector2, message: String): view.combat_feedback.add_text(point, message, battle.tick_count * 0.062))
	battle.spell_impact.connect(func(spell: int, cell: Vector2i, tick: int):
		sound_effects.spell_impact(spell)
		if spell == Spell.METEOR: view.combat_feedback.add_meteor(cell, tick * 0.062)
	)
	battle.presentation_reset.connect(func(): view.combat_feedback.clear(); view.zone_action = &"none")
	exploration.tick_finished.connect(_exploration_tick)
	campaign.changed.connect(_campaign_changed)
	campaign.travel_requested.connect(_travel)
	campaign.encounter_requested.connect(_begin_battle)
	campaign.party_repositioned.connect(func(): exploration.configure(session))
	campaign.world_map_requested.connect(func(): _show_world(true))
	_restart(true, false)
	if "--gameplay-test" in OS.get_cmdline_user_args():
		call_deferred("_run_checks")
	elif "--capture-story" in OS.get_cmdline_user_args():
		call_deferred("_capture_story")
	elif "--capture-intro" in OS.get_cmdline_user_args():
		call_deferred("_capture_combat_ui", "intro")
	elif "--capture-magic" in OS.get_cmdline_user_args():
		call_deferred("_capture_combat_ui", "magic")
	elif "--capture-magic-full" in OS.get_cmdline_user_args():
		call_deferred("_capture_combat_ui", "magic-full")
	elif "--capture-spell" in OS.get_cmdline_user_args():
		call_deferred("_capture_combat_ui", "spell")
	elif "--capture-frost" in OS.get_cmdline_user_args():
		call_deferred("_capture_combat_ui", "frost")
	elif "--capture-lightning" in OS.get_cmdline_user_args():
		call_deferred("_capture_combat_ui", "lightning")
	elif "--capture-blessing" in OS.get_cmdline_user_args():
		call_deferred("_capture_combat_ui", "blessing")
	elif "--capture-meteor" in OS.get_cmdline_user_args():
		call_deferred("_capture_combat_ui", "meteor")
	elif "--capture-meteor-shards" in OS.get_cmdline_user_args():
		call_deferred("_capture_combat_ui", "meteor-shards")
	elif "--capture-combat-menu" in OS.get_cmdline_user_args():
		call_deferred("_capture_combat_ui", "combat-menu")
	elif "--capture-battle" in OS.get_cmdline_user_args():
		call_deferred("_capture_battle")
	elif "--capture-victory" in OS.get_cmdline_user_args():
		call_deferred("_capture_victory")
	elif "--capture-gameplay" in OS.get_cmdline_user_args():
		call_deferred("_capture")
	elif "--capture-progression" in OS.get_cmdline_user_args():
		call_deferred("_capture_management", Page.CHARACTER)
	elif "--capture-inventory" in OS.get_cmdline_user_args():
		call_deferred("_capture_management", Page.INVENTORY)
	elif "--capture-loot" in OS.get_cmdline_user_args():
		call_deferred("_capture_management", Page.LOOT)
	elif "--capture-dungeon" in OS.get_cmdline_user_args():
		call_deferred("_capture_travel", "dungeon")
	elif "--capture-world" in OS.get_cmdline_user_args():
		call_deferred("_capture_travel", "world")
	elif "--capture-town" in OS.get_cmdline_user_args():
		call_deferred("_capture_travel", "town")
	elif "--capture-zones" in OS.get_cmdline_user_args():
		call_deferred("_capture_presentation", "zones")
	elif "--capture-gold" in OS.get_cmdline_user_args():
		call_deferred("_capture_presentation", "gold")
	elif "--capture-town-help" in OS.get_cmdline_user_args():
		call_deferred("_capture_presentation", "town-help")
	elif "--capture-rain" in OS.get_cmdline_user_args():
		call_deferred("_capture_presentation", "rain")
	elif "--capture-settings" in OS.get_cmdline_user_args():
		call_deferred("_capture_presentation", "settings")
	elif "--capture-damage" in OS.get_cmdline_user_args():
		call_deferred("_capture_presentation", "damage")
	elif "--capture-saves" in OS.get_cmdline_user_args():
		call_deferred("_capture_stage8", false)
	elif "--capture-ending" in OS.get_cmdline_user_args():
		call_deferred("_capture_stage8", true)
	elif "--capture-menu" in OS.get_cmdline_user_args():
		call_deferred("_capture_travel", "menu")
	elif "--capture-game-menu" in OS.get_cmdline_user_args():
		call_deferred("_capture_travel", "game-menu")
	elif "--capture-sale" in OS.get_cmdline_user_args():
		call_deferred("_capture_travel", "sale")
	else: _show_main_menu(true)


func _fail(message: String) -> void:
	status.text = message
	push_error(message)
	if "--gameplay-test" in OS.get_cmdline_user_args() or "--capture-gameplay" in OS.get_cmdline_user_args() or "--capture-battle" in OS.get_cmdline_user_args() or "--capture-victory" in OS.get_cmdline_user_args():
		get_tree().quit(1)


func _label(column: VBoxContainer, text: String, muted: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if muted:
		label.modulate = LegacyTheme.MUTED
	column.add_child(label)
	return label


func _build_dialogue() -> void:
	dialogue_layer = Control.new()
	add_child(dialogue_layer)
	dialogue_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialogue_layer.visible = false
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.76)
	dialogue_layer.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	dialogue_panel = panel
	dialogue_layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 320
	panel.offset_top = 240
	panel.offset_right = -24
	panel.offset_bottom = -24
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	dialogue_portrait = TextureRect.new()
	dialogue_portrait.custom_minimum_size = Vector2(160, 208)
	dialogue_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dialogue_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dialogue_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	dialogue_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(dialogue_portrait)
	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_column)
	dialogue_title = _label(text_column, "")
	dialogue_title.add_theme_font_size_override("font_size", 26)
	dialogue_counter = _label(text_column, "", true)
	dialogue_scroll = ScrollContainer.new()
	dialogue_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialogue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	text_column.add_child(dialogue_scroll)
	dialogue_body = Label.new()
	dialogue_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialogue_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_body.add_theme_font_size_override("font_size", 26)
	dialogue_scroll.add_child(dialogue_body)
	_label(column, "Пробел / Enter — дальше · колесо — прокрутка", true)
	dialogue_next = _button(column, "Далее", func(): campaign.acknowledge())
	dialogue_restart = _button(column, "Начать заново", _restart)


func _campaign_changed() -> void:
	var locked: bool = campaign.busy()
	if locked and not _script_locked:
		held_keys.clear()
		route.clear()
		view.route_cells.clear()
		exploration.stop()
	elif not locked and _script_locked and not battle.active:
		exploration.configure(session)
	_script_locked = locked
	view.shake_offset = Vector2((campaign.ticks * 3) % 9 - 4, (campaign.ticks * 5) % 9 - 4) if campaign.shaking else Vector2.ZERO
	dialogue_layer.visible = not campaign.modal.is_empty() or not campaign.fault.is_empty()
	if not campaign.fault.is_empty():
		dialogue_title.text = "Граница восстановленного эпизода"
		dialogue_counter.text = "Сценарий %d · инструкция %d" % [campaign.fault["script"], campaign.fault["pc"]]
		dialogue_body.text = campaign.fault["message"]
		dialogue_portrait.visible = false
		dialogue_next.visible = false
		dialogue_restart.visible = true
	elif not campaign.modal.is_empty():
		var modal: Dictionary = campaign.modal
		var page: Dictionary = modal["pages"][int(modal["page"])]
		dialogue_title.text = str(page["speaker"])
		dialogue_counter.text = "%d / %d" % [int(modal["page"]) + 1, modal["pages"].size()]
		dialogue_body.text = str(page["text"])
		dialogue_portrait.visible = int(page["portrait"]) >= 0
		if dialogue_portrait.visible: dialogue_portrait.texture = ui_icons.portrait(int(page["portrait"]))
		dialogue_scroll.scroll_vertical = 0
		dialogue_next.visible = true
		dialogue_next.text = "Закрыть" if int(modal["page"]) + 1 == modal["pages"].size() else "Далее"
		dialogue_restart.visible = false
	_refresh()
	view.queue_redraw()


func _button(column: VBoxContainer, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	column.add_child(button)
	return button


func _build_interface() -> void:
	var background := Panel.new()
	sidebar_background = background
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	background.offset_right = 300
	view = View.new()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.offset_left = 300
	view.cell_selected.connect(_select_cell)
	view.battle = battle
	battle_banner = Label.new()
	battle_banner.position = Vector2(320, 12)
	battle_banner.add_theme_font_size_override("font_size", 22)
	battle_banner.add_theme_color_override("font_shadow_color", Color.BLACK)
	battle_banner.add_theme_constant_override("shadow_offset_x", 2)
	battle_banner.add_theme_constant_override("shadow_offset_y", 2)
	battle_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(battle_banner)
	sidebar_scroll = ScrollContainer.new()
	var scroll: ScrollContainer = sidebar_scroll
	add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	scroll.offset_left = 20
	scroll.offset_top = 20
	scroll.offset_right = 280
	scroll.offset_bottom = -20
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 245
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	title_label = _label(column, "АЛЛОДЫ\nИсследование")
	title_label.add_theme_font_size_override("font_size", 26)
	mode_label = _label(column, "Этап 4 · базовый бой", true)
	stats_label = _label(column, "")
	quests_label = _label(column, "", true)
	_button(column, "Персонажи и школы · C", func(): _open_management(Page.CHARACTER))
	_button(column, "Снаряжение · I", func(): _open_management(Page.INVENTORY))
	_button(column, "Журнал заданий · J", func(): _open_management(Page.JOURNAL))
	world_button = _button(column, "Карта мира · M", func(): _show_world(false))
	_button(column, "Меню · Esc", _show_game_menu)
	battle_controls = VBoxContainer.new()
	battle_controls.add_theme_constant_override("separation", 8)
	column.add_child(battle_controls)
	battle_roster = VBoxContainer.new()
	battle_controls.add_child(battle_roster)
	attack_button = _button(battle_controls, "Атаковать цель", _attack_target)
	defend_button = _button(battle_controls, "Защита", func(): battle.defend())
	wait_button = _button(battle_controls, "Закончить бойца", func(): battle.wait_unit())
	end_side_button = _button(battle_controls, "Завершить сторону", func(): battle.end_side())
	result_controls = VBoxContainer.new()
	column.add_child(result_controls)
	result_label = _label(result_controls, "")
	continue_button = _button(result_controls, "Вернуться к исследованию", _continue_after_battle)
	defeat_restart_button = _button(result_controls, "Начать заново", _restart)
	move_button = _button(column, "Идти по маршруту", _begin_move)
	stop_button = _button(column, "Остановиться · Esc", _stop)
	status = _label(column, "")
	var debug_fold := _button(column, "Отладка ▸", func(): debug_panel.visible = not debug_panel.visible)
	debug_fold.tooltip_text = "Тестовые режимы и просмотр локаций"
	debug_panel = VBoxContainer.new()
	column.add_child(debug_panel)
	debug_panel.visible = false
	god_toggle = CheckButton.new()
	god_toggle.text = "God mode (тест)"
	god_toggle.toggled.connect(_set_god_mode)
	debug_panel.add_child(god_toggle)
	_button(debug_panel, "Тестовый бой · сброс", _demo_battle)
	_button(debug_panel, "Бой с магией · сброс", func(): _demo_battle(true))
	debug_map_picker = OptionButton.new()
	for location in range(12):
		debug_map_picker.add_item("Карта %d" % (location + 1))
		debug_map_picker.set_item_metadata(debug_map_picker.item_count - 1, location)
	for dungeon in range(12):
		debug_map_picker.add_item("Подземелье %d%s" % [dungeon + 1, " · дракон" if dungeon == 11 else ""])
		debug_map_picker.set_item_metadata(debug_map_picker.item_count - 1, -dungeon - 1)
	debug_panel.add_child(debug_map_picker)
	_button(debug_panel, "Перейти (тест)", func():
		if session.mode != &"exploration" or campaign.busy() or battle.active: return
		_travel(int(debug_map_picker.get_selected_metadata()), 0)
	)
	for option in [["Препятствия", "show_collision"], ["Доступные клетки", "show_reachable"], ["Сетка", "show_grid"]]:
		var toggle := CheckButton.new()
		toggle.text = option[0]
		var property: String = option[1]
		toggle.toggled.connect(func(value: bool): view.set(property, value); view.queue_redraw())
		debug_panel.add_child(toggle)
	camera_toggle = CheckButton.new()
	camera_toggle.text = "Камера за героем"
	camera_toggle.toggled.connect(func(enabled: bool):
		if enabled: view.follow_hero()
		else: view.camera_follow = false
	)
	view.camera_follow_changed.connect(func(enabled: bool): camera_toggle.set_pressed_no_signal(enabled))
	debug_panel.add_child(camera_toggle)
	_button(debug_panel, "Вернуться к герою · F", func(): view.follow_hero())
	_button(debug_panel, "Карта целиком", view.fit_map)
	_button(debug_panel, "Тестовый отряд · сброс", _demo_party)
	_button(debug_panel, "Начать заново", _restart)
	_button(debug_panel, "Снимок для отладки", _snapshot)
	_button(debug_panel, "Отладка персонажа", func(): _open_management(Page.CHARACTER, {}, true))
	_button(debug_panel, "Отладка инвентаря", func(): _open_management(Page.INVENTORY, {}, true))
	_button(debug_panel, "Просмотр всех карт", func(): get_tree().change_scene_to_file("res://main.tscn"))
	_label(column, "WASD / стрелки — ходить\nЛКМ — цель; повтор — идти\nКолесо — масштаб\nПКМ / СКМ — сдвиг карты", true)
	_label(column, "В бою: союзник — выбор; клетка — движение; противник — цель. Повторный клик атакует. Подход тратит ОД, атака завершает действия бойца.", true)
	action_bar = ActionBar.new()
	add_child(action_bar)
	view.hud_obstruction = action_bar
	action_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	action_bar.offset_left = 324
	action_bar.offset_right = -24
	action_bar.offset_top = -180
	action_bar.offset_bottom = -20
	action_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	action_bar.chosen.connect(_choose_action)
	battle_overlay = BattleOverlay.new()
	add_child(battle_overlay)
	battle_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battle_overlay.offset_left = 300
	battle_overlay.intro_finished.connect(_finish_battle_intro)
	battle_overlay.continue_requested.connect(_continue_after_battle)
	battle_overlay.restart_requested.connect(_restart)
	_build_dialogue()
	management = ManagementPanel.new()
	add_child(management)
	management.closed.connect(_management_closed)
	legacy_management = LegacyManagement.new()
	add_child(legacy_management)
	legacy_management.closed.connect(_management_closed)
	world_panel = WorldMapPanel.new()
	add_child(world_panel)
	world_panel.destination_chosen.connect(_travel)
	world_panel.shop_requested.connect(_open_town_shop)
	world_panel.closed.connect(func():
		session.mode = &"exploration"
		held_keys.clear()
		_refresh()
	)
	shop = LegacyShop.new()
	add_child(shop)
	shop.closed.connect(func(): world_panel.show_town())
	main_menu = TitleMenu.new()
	add_child(main_menu)
	main_menu.new_game_requested.connect(func():
		_has_started = true
		_restart()
	)
	main_menu.resume_requested.connect(func():
		main_menu.hide()
		session.mode = _menu_resume_mode
	)
	game_menu = GameMenu.new()
	add_child(game_menu)
	game_menu.chosen.connect(_game_menu_chosen)
	game_menu.preferences = preferences
	game_menu.setting_requested.connect(func(key: String, value):
		var result: Error = preferences.update(key, value)
		if result != OK: status.text = "Не удалось сохранить настройки: " + error_string(result)
	)
	game_menu.settings_closed.connect(func():
		if _settings_from_title:
			_settings_from_title = false
			game_menu.hide()
			main_menu.show()
	)
	main_menu.settings_requested.connect(func():
		_settings_from_title = true
		main_menu.hide()
		game_menu.open(view.textures, metadata, battle.active)
		game_menu.open_settings()
	)
	main_menu.load_requested.connect(func(): _open_save_slots(false, &"main_menu"))
	save_slots = SaveSlots.new()
	add_child(save_slots)
	save_slots.closed.connect(_close_save_slots)
	save_slots.selected_slot.connect(_save_slot_selected)
	_set_debug_sidebar_visible(false)


func _settings_changed(key: String) -> void:
	if crt_filter != null: crt_filter.apply(bool(preferences.values["crt_enabled"]))
	game_menu.queue_redraw()
	if key not in ["", "hd_icons"]: return
	action_bar._signature = ""
	for screen in [view, legacy_management, shop]: screen.queue_redraw()
	if management.visible: management.render()
	if not campaign.modal.is_empty():
		var page: Dictionary = campaign.modal["pages"][int(campaign.modal["page"])]
		if int(page["portrait"]) >= 0: dialogue_portrait.texture = ui_icons.portrait(int(page["portrait"]))
	_refresh()


func _set_debug_sidebar_visible(enabled: bool) -> void:
	debug_sidebar_visible = enabled
	view.show_debug_markers = enabled
	sidebar_background.visible = enabled
	sidebar_scroll.visible = enabled
	var inset: float = 300 if enabled else 0
	view.offset_left = inset
	action_bar.offset_left = inset + 24
	battle_overlay.offset_left = inset
	battle_banner.position.x = inset + 20
	dialogue_panel.offset_left = inset + (20 if enabled else 24)
	if battle.active and not view.current_map.is_empty(): view.focus_arena(battle.arena)
	view.queue_redraw()


func _dev_shortcut(event: InputEventKey, key: int) -> bool:
	if key not in [KEY_D, KEY_E, KEY_V]: return false
	if event.pressed: _dev_keys[key] = true
	else: _dev_keys.erase(key)
	var complete: bool = _dev_keys.has(KEY_D) and _dev_keys.has(KEY_E) and _dev_keys.has(KEY_V)
	if complete:
		if not _dev_chord_active:
			_set_debug_sidebar_visible(not debug_sidebar_visible)
			held_keys.clear()
			if exploration.session != null: exploration.set_direction(Vector2i.ZERO)
		_dev_chord_active = true
		return true
	_dev_chord_active = false
	if key in [KEY_E, KEY_V] or _dev_keys.has(KEY_E) or _dev_keys.has(KEY_V):
		held_keys.erase(KEY_D)
		if exploration.session != null: exploration.set_direction(_keyboard_direction())
		return true
	return false


func _restart(activate_campaign: bool = true, autosave_entry: bool = true) -> void:
	battle_cursor_action = &""
	if cursors != null: cursors.invalidate()
	if sound_effects != null: sound_effects.stop_all()
	if world.is_empty():
		return
	held_keys.clear()
	management.hide()
	legacy_management.hide()
	world_panel.hide()
	shop.hide()
	if save_slots != null: save_slots.hide()
	main_menu.hide()
	game_menu.hide()
	management_origin = &"exploration"
	management.draft = {}
	battle_overlay.hide_screen()
	action_bar.reset_menu()
	selected_spell = -1
	shot_targets.clear()
	cast_cell = Vector2i(-1, -1)
	campaign.enabled = false
	_script_locked = false
	battle.reset()
	battle.enemy_policy = &"combat"
	attack_target_id = -1
	roster_buttons.clear()
	for child in battle_roster.get_children(): child.queue_free()
	route.clear()
	selected = Vector2i(-1, -1)
	view.session = null
	if not session.start(world, metadata, table, rewards):
		_fail("Не удалось создать игровую сессию.")
		return
	view.session = session
	_configure_exploration_view()
	campaign.configure(session, world, campaign_data, activate_campaign)
	status.text = "Выберите клетку на карте.\nЗелёный путь — цель доступна. Жёлтый — подход к препятствию."
	_refresh()
	if activate_campaign:
		if autosave_entry: _autosave_entry()
		campaign.check_triggers()


func _refresh() -> void:
	if session.hero == null:
		return
	world_button.disabled = not session.world_travel_unlocked()
	god_toggle.set_pressed_no_signal(session.god_mode)
	if battle.active:
		_refresh_battle()
		return
	battle_controls.visible = false
	result_controls.visible = false
	battle_banner.visible = false
	action_bar.visible = false
	title_label.text = "АЛЛОДЫ\nИсследование"
	stop_button.visible = true
	var location: String = "Подземелье %d" % -session.location_id if session.location_id < 0 else str(metadata["travel"]["location_names"][session.location_id + 1])
	mode_label.text = "%s · золото %d" % [location, session.gold]
	move_button.visible = true
	move_button.text = "Идти по маршруту"
	var values: PackedInt32Array = session.hero.stats
	stats_label.text = "Тагрим · уровень %d\nЗдоровье %d / %d\nМана %d / %d · ОД %d / %d\nСИЛ %d · ЛОВ %d · ВЫН %d\nКлетка (%d, %d)\nОтряд: %d%s" % [values[Stat.LEVEL], values[Stat.HP], values[Stat.MAX_HP], values[Stat.MANA], values[Stat.MAX_MANA], values[Stat.ACTION_POINTS], values[Stat.MAX_ACTION_POINTS], values[Stat.STRENGTH], values[Stat.DEXTERITY], values[Stat.ENDURANCE], session.hero.cell.x, session.hero.cell.y, session.party.size(), " · тест следования" if session.demo_party else ""]
	if not view.current_map.is_empty():
		_refresh_visuals()
	move_button.disabled = moving or route.is_empty()
	stop_button.disabled = not moving
	quests_label.visible = campaign.enabled
	var active_quests: PackedStringArray = []
	for quest: Dictionary in campaign_data["quests"]:
		if int(session.quests[int(quest["id"])]) == 1: active_quests.append(str(quest["title"]))
	quests_label.text = "Задания: " + ", ".join(active_quests)
	if campaign.busy():
		move_button.disabled = true
		stop_button.disabled = true
		mode_label.text = "Землетрясение…" if campaign.shaking else "Сюжетная сцена"


func _unit_name(actor) -> String:
	return str(campaign_data["unit_names"][actor.unit_type])


func _begin_battle(ids: Array[int]) -> void:
	battle_cursor_action = &""
	if cursors != null: cursors.invalidate()
	if battle.active: return
	if not battle.begin(session, ids):
		status.text = "Не удалось разместить бойцов на арене."
		return
	held_keys.clear()
	exploration.stop()
	route.clear()
	selected = Vector2i(-1, -1)
	attack_target_id = -1
	view.selection = selected
	view.route_cells.clear()
	roster_buttons.clear()
	for child in battle_roster.get_children(): child.queue_free()
	for actor in session.party:
		var id: int = actor.instance_id
		var button: Button = _button(battle_roster, _unit_name(actor), func():
			if battle.select(id):
				selected_spell = -1
				shot_targets.clear()
				route.clear()
				attack_target_id = -1
				view.route_cells.clear()
				status.text = "Выберите клетку для движения."
		)
		roster_buttons[id] = button
	_refresh_battle()
	view.focus_arena(battle.arena)
	status.text = "Бой начался. Выберите бойца и клетку. Шаг стоит 1 ОД; защита завершает действия бойца."
	selected_spell = -1
	action_bar.reset_menu()
	session.mode = &"battle_intro"
	battle_overlay.show_intro(battle.unit(ids[0]), metadata, campaign_data["battle_ui"], view.textures)
	_refresh()


func _finish_battle_intro() -> void:
	if not battle.active: return
	session.mode = &"battle"
	_refresh()
	if campaign.enabled: campaign.show_tutorial(2)


func _choose_action(action: String, spell: int) -> void:
	if not battle.can_input(): return
	battle_cursor_action = &"" if action in ["back", "defend"] else StringName(action)
	if action == "attack" and battle.unit(battle.selected_id).stats[Stat.ARCHERY] > 0: battle_cursor_action = &"shoot"
	view.zone_turn = battle.turn_serial
	view.zone_action = &"ranged" if action == "spell" or (action == "attack" and battle.unit(battle.selected_id).stats[Stat.ARCHERY] > 0) else (&"move" if action in ["move", "attack"] else &"none")
	shot_targets.clear()
	if action == "magic" or action == "back":
		action_bar.submenu = action == "magic"
		action_bar._signature = ""
		selected_spell = -1
		cast_cell = Vector2i(-1, -1)
	elif action == "spell":
		shot_targets.clear()
		selected_spell = spell
		cast_cell = Vector2i(-1, -1)
		attack_target_id = -1
		route.clear()
		view.route_cells.clear()
		status.text = "Выберите цель для «%s». Повторный клик — применить." % str(campaign_data["battle_ui"]["spells"][spell]).strip_edges()
	elif action == "defend":
		selected_spell = -1
		battle.defend()
	else:
		selected_spell = -1
		status.text = "Выберите противника." if action == "attack" else "Выберите клетку для движения."
	_refresh()


func _refresh_battle() -> void:
	if battle.outcome != &"":
		_refresh_result()
		return
	if action_bar.actor_id != battle.selected_id or view.zone_turn != battle.turn_serial:
		battle_cursor_action = &""
		view.zone_action = &"none"
		view.zone_turn = battle.turn_serial
		selected_spell = -1
		shot_targets.clear()
		cast_cell = Vector2i(-1, -1)
	action_bar.refresh(battle, campaign_data["battle_ui"], view.textures)
	battle_controls.visible = true
	result_controls.visible = false
	battle_banner.visible = false
	title_label.text = "АЛЛОДЫ\nПошаговый бой"
	stop_button.visible = false
	var side_text: String = "Ваш ход" if battle.current_side == Side.PARTY else "Ход противника"
	if battle.stalled: side_text = "Нет доступных бойцов · сбросьте карту"
	battle_banner.text = "Раунд %d · %s%s" % [battle.round_number, side_text, " · выполняется команда" if battle.busy() else ""]
	mode_label.text = "Пошаговый бой · этапы 5–6"
	var actor = battle.unit(battle.selected_id) if battle.selected_id >= 0 else session.hero
	var values: PackedInt32Array = actor.stats
	stats_label.text = "%s\nЗдоровье %d / %d\nОД %d / %d · ход стороны %d\nСопротивление %d / %d\nКлетка (%d, %d) · %d×%d" % [_unit_name(actor), values[Stat.HP], values[Stat.MAX_HP], values[Stat.ACTION_POINTS], values[Stat.MAX_ACTION_POINTS], battle.current_side + 1, values[Stat.PHYSICAL_RESISTANCE], values[Stat.DARK_RESISTANCE], actor.cell.x, actor.cell.y, actor.footprint.x, actor.footprint.y]
	for id: int in roster_buttons:
		var ally = battle.unit(id)
		roster_buttons[id].text = "%s · %d ОД%s" % [_unit_name(ally), ally.stats[Stat.ACTION_POINTS], " ◀" if id == battle.selected_id else ""]
		roster_buttons[id].disabled = not battle.can_input() or not battle.eligible(ally)
	move_button.text = "Переместиться"
	move_button.visible = true
	move_button.disabled = not battle.can_input() or route.is_empty() or not view.route_exact or attack_target_id >= 0
	attack_button.disabled = not battle.can_input() or attack_target_id < 0
	attack_button.text = "Стрелять в цель" if actor.stats[Stat.ARCHERY] > 0 else "Ударить цель"
	if not attack_button.disabled:
		attack_button.disabled = not battle.attack_plan(actor, battle.unit(attack_target_id))["valid"]
		if battle.unit(attack_target_id).dead: attack_button.text = "Уничтожить тело"
	if selected_spell >= 0:
		attack_button.text = "Применить заклинание"
		attack_button.disabled = not battle.can_input() or not battle.cast_plan(actor, selected_spell, cast_cell)["valid"]
	stop_button.disabled = true
	defend_button.disabled = not battle.can_input() or battle.selected_id < 0
	wait_button.disabled = defend_button.disabled
	end_side_button.disabled = not battle.can_input()
	_refresh_visuals()


func _refresh_result() -> void:
	battle_cursor_action = &""
	if battle.outcome == &"ending":
		battle.active = false
		battle_overlay.hide_screen()
		_has_started = false
		var pages: Array = campaign_data["dialogues"][80]["pages"].duplicate(true)
		pages.append_array(campaign_data["dialogues"][81]["pages"].duplicate(true))
		campaign._show_pages("ending", 80, pages)
		campaign._resume_mode = &"ending"
		return
	var won: bool = battle.outcome == &"victory"
	action_bar.visible = false
	if battle_overlay.phase != battle.outcome:
		battle_overlay.show_result(won, battle.reward, campaign_data["battle_ui"], view.textures, metadata["economy"]["item_names"])
		if won:
			for actor in session.party:
				if int(battle.reward.get("levels", {}).get(str(actor.instance_id), 0)) > 0: battle_overlay.body.text += "\n%s: повышение уровня" % _unit_name(actor)
	battle_controls.visible = false
	result_controls.visible = true
	move_button.visible = false
	stop_button.visible = false
	battle_banner.visible = false
	title_label.text = "АЛЛОДЫ\nПобеда!" if won else "АЛЛОДЫ\nПоражение"
	battle_banner.text = "Победа · бой окончен" if won else "Поражение · отряд пал"
	mode_label.text = "Бой завершён · раунд %d" % battle.round_number
	stats_label.text = "Отряд победил противника." if won else "Все бойцы отряда повержены."
	result_label.text = "Золото: +%d (всего %d)\nОпыт каждому: +%d\n\nПосле продолжения отряд восстановится." % [battle.reward.get("gold", 0), session.gold, battle.reward.get("xp_each", 0)] if won else "Награда не выдана. Можно начать заново."
	continue_button.visible = won
	defeat_restart_button.visible = not won
	status.text = "Бой окончен."
	_refresh_visuals()


func _continue_after_battle() -> void:
	if not battle.return_to_exploration(): return
	battle_overlay.hide_screen()
	selected_spell = -1
	action_bar.reset_menu()
	held_keys.clear()
	attack_target_id = -1
	route.clear()
	view.route_cells.clear()
	exploration.configure(session)
	view.follow_point = session.hero.position_pixels
	view.follow_hero(true)
	campaign.after_battle(battle.participants)
	status.text = "Победа! Отряд восстановлен. Можно продолжать исследование."
	_refresh()


func _attack_target() -> void:
	if selected_spell >= 0:
		if battle.cast(selected_spell, cast_cell):
			battle_cursor_action = &""
			selected_spell = -1
			cast_cell = Vector2i(-1, -1)
			_refresh()
		return
	if not shot_targets.is_empty():
		if battle.attack_many(shot_targets):
			battle_cursor_action = &""
			shot_targets.clear()
			attack_target_id = -1
			_refresh()
		return
	if attack_target_id >= 0 and battle.attack(attack_target_id):
		battle_cursor_action = &""
		attack_target_id = -1
		route.clear()
		view.route_cells.clear()
		status.text = "Выполняется атака…"


func _select_battle_cell(cell: Vector2i, append_shot: bool = false) -> void:
	if not battle.can_input(): return
	view.zone_turn = battle.turn_serial
	view.zone_action = &"ranged" if selected_spell >= 0 or battle.unit(battle.selected_id).stats[Stat.ARCHERY] > 0 else &"move"
	if selected_spell >= 0:
		if cast_cell == cell:
			_attack_target()
			return
		cast_cell = cell
		view.selection = cell
		status.text = "Цель выбрана. Повторный клик или «Применить заклинание»." if battle.cast_plan(battle.unit(battle.selected_id), selected_spell, cell)["valid"] else "Недопустимая цель, дальность или не хватает маны."
		_refresh_battle()
		return
	for id: int in battle.participants:
		var actor = battle.unit(id)
		if Rect2i(actor.cell, actor.footprint).has_point(cell):
			if actor.shattered: continue
			if actor.dead and actor.side_id == Side.PARTY:
				status.text = "%s повержен. Тело пока занимает клетки." % _unit_name(actor)
				return
			if actor.side_id == Side.PARTY and battle.select(id):
				shot_targets.clear()
				attack_target_id = -1
				route.clear()
				view.route_cells.clear()
				_refresh_battle()
			else:
				var shooter = battle.unit(battle.selected_id)
				if append_shot and shooter.stats[Stat.ARCHERY] > 0 and battle.attack_plan(shooter, actor)["valid"]:
					var maximum: int = int((shooter.stats[Stat.ARCHERY] - 1) / 3.0) + 1
					if shot_targets.size() < maximum: shot_targets.append(id)
					attack_target_id = id
					status.text = "Серия: %d/%d целей. Shift + клик добавляет цель; кнопка атаки запускает серию." % [shot_targets.size(), maximum]
					_refresh_battle()
					return
				shot_targets.clear()
				if attack_target_id == id:
					_attack_target()
					return
				attack_target_id = id
				var plan: Dictionary = battle.attack_plan(battle.unit(battle.selected_id), actor)
				route.assign(plan["path"])
				view.route_cells = route.duplicate()
				view.route_exact = plan["valid"]
				status.text = "%s · HP %d/%d.\n%s" % [_unit_name(actor), actor.stats[Stat.HP], actor.stats[Stat.MAX_HP], "Повторный клик или кнопка — атаковать." if plan["valid"] else "Не хватает ОД для подхода или цель вне дальности."]
				if actor.dead and plan["valid"]: status.text = "Тело: %s. Повторный клик или «Уничтожить тело» освободит проход." % _unit_name(actor)
				_refresh_battle()
				attack_button.disabled = not plan["valid"]
			return
	if selected == cell and not route.is_empty():
		_begin_move()
		return
	selected = cell
	attack_target_id = -1
	var result: Dictionary = battle.preview(cell)
	route.assign(result["path"])
	view.route_cells = route.duplicate()
	view.route_exact = result["affordable"]
	status.text = "Стоимость: %d ОД. Повторный клик — переместиться." % route.size() if result["affordable"] else "Цель недоступна или не хватает ОД."
	_refresh_battle()


func _demo_battle(include_magic: bool = false) -> void:
	_demo_party()
	var enemy = battle.unit(1004) if battle.session != null else null
	for actor in session.units:
		if actor.instance_id == 1004: enemy = actor
	if enemy == null or session.party.size() < 2: return
	var actors: Array = [session.hero, session.party[1], enemy]
	var cells: Array[Vector2i] = [Vector2i(21, 20), Vector2i(23, 20), Vector2i(21, 16)]
	if include_magic:
		for actor in session.units:
			if actor.story_group == Ids.StoryGroup.HERMIT:
				actor.side_id = Side.PARTY
				session.party.append(actor)
				actors.append(actor)
				cells.append(Vector2i(23, 21))
	for actor in actors: session.collision.remove(actor.instance_id)
	for index in range(actors.size()):
		var actor = actors[index]
		if not session.collision.place(actor.instance_id, cells[index], actor.footprint):
			_fail("Не удалось разместить тестовый бой.")
			return
		actor.move_to(cells[index])
		actor.reset_interpolation()
	exploration.configure(session)
	_begin_battle(Encounter.detected(session))


func _select_cell(cell: Vector2i, _source_id: int) -> void:
	if campaign.busy(): return
	if battle.active:
		_select_battle_cell(cell, Input.is_physical_key_pressed(KEY_SHIFT))
		return
	if moving:
		_stop()
	if cell == selected and not route.is_empty():
		_begin_move()
		return
	selected = cell
	var result: Dictionary = exploration.preview(cell)
	route.assign(result["path"])
	view.route_cells = route.duplicate()
	view.route_exact = result["reachable"]
	if result["reachable"]:
		status.text = "Цель (%d, %d)\nМаршрут: %d шагов.\nПовторный клик или кнопка — идти." % [cell.x, cell.y, route.size()]
	else:
		var resolved: Vector2i = result["resolved"]
		status.text = "Цель недоступна.\nПодход: (%d, %d), %d шагов." % [resolved.x, resolved.y, route.size()]
	view.queue_redraw()
	_refresh()


func _begin_move() -> void:
	if campaign.busy(): return
	if battle.active:
		if battle.submit_move(selected):
			battle_cursor_action = &""
			route.clear()
			view.route_cells.clear()
			status.text = "Выполняется движение…"
		return
	if route.is_empty() or moving:
		return
	exploration.start_route(route)
	status.text = "Тагрим идёт по маршруту…"
	_refresh()


func _process(delta: float) -> void:
	if exploration.session == null:
		return
	if music != null: music.play_track(0 if main_menu.visible or _settings_from_title else 1)
	if sound_effects != null: sound_effects.pause_world(management.visible or legacy_management.visible or world_panel.visible or shop.visible or main_menu.visible or game_menu.visible or save_slots.visible or campaign.busy())
	if management.visible or legacy_management.visible or world_panel.visible or shop.visible or main_menu.visible or game_menu.visible or save_slots.visible:
		held_keys.clear()
		_refresh_visuals()
		return
	if battle_overlay.phase != &"":
		held_keys.clear()
		battle_overlay.advance(delta)
		_refresh_visuals()
		return
	if campaign.modal.is_empty(): session.advance_weather(delta)
	if battle.active and session.mode == &"battle" and not campaign.busy(): view.combat_feedback.advance(delta)
	if campaign.busy():
		held_keys.clear()
		campaign.advance(delta)
		_refresh_visuals()
		return
	if battle.active:
		held_keys.clear()
		battle.advance(delta)
		_refresh_visuals()
		return
	if session.mode == &"ending":
		_show_main_menu(true)
		return
	exploration.set_direction(_keyboard_direction())
	exploration.advance(delta)
	if moving:
		view.route_cells = exploration.route.duplicate()
	_refresh_visuals()
	move_button.disabled = moving or route.is_empty()
	stop_button.disabled = not moving


func _refresh_visuals() -> void:
	var alpha: float = clampf(campaign.accumulator / 0.062, 0, 1) if campaign.busy() else (battle.alpha() if battle.active else exploration.alpha())
	view.session_view_alpha = alpha
	var followed = battle.unit(battle.selected_id) if battle.active and battle.selected_id >= 0 else session.hero
	view.follow_point = followed.previous_position.lerp(followed.position_pixels, alpha)
	view.update_units(session.render_records(alpha))
	_update_cursor()


func _update_cursor() -> void:
	if cursors == null or ui_icons.preferences == null: return
	var hovered: Control = get_viewport().gui_get_hovered_control()
	var on_map: bool = hovered == view or (hovered != null and view.is_ancestor_of(hovered))
	var point: Vector2 = view.get_local_mouse_position()
	on_map = on_map and Rect2(Vector2.ZERO, view.size).has_point(point)
	var state: Dictionary = cursors.resolve(self, point, on_map)
	view.set_movement_preview(state)
	cursors.apply(state, ui_icons)


func _route_finished(blocked: bool) -> void:
	route.clear()
	view.route_cells.clear()
	status.text = "Путь прерван: впереди препятствие." if blocked else "Пришли. Выберите следующую цель."


func _demo_party() -> void:
	_restart(false)
	var companion = session.add_demo_companion()
	if companion == null:
		status.text = "Не найдено свободного места для теста отряда."
		return
	exploration.configure(session)
	_refresh()
	status.text = "Тест следования: лучница идёт за Тагримом. Это отдельная проверка отряда; сюжетное присоединение появится позже."


func _stop() -> void:
	held_keys.clear()
	if campaign.busy(): return
	if battle.active: return
	if exploration.session != null:
		exploration.stop()
	route.clear()
	view.route_cells.clear()
	if session.hero != null:
		_refresh()
		view.queue_redraw()
	status.text = "Движение остановлено."


func _keyboard_direction() -> Vector2i:
	if held_keys.has(KEY_A) or held_keys.has(KEY_LEFT): return Vector2i.LEFT
	if held_keys.has(KEY_D) or held_keys.has(KEY_RIGHT): return Vector2i.RIGHT
	if held_keys.has(KEY_W) or held_keys.has(KEY_UP): return Vector2i.UP
	if held_keys.has(KEY_S) or held_keys.has(KEY_DOWN): return Vector2i.DOWN
	return Vector2i.ZERO


func _location_changed() -> void:
	battle_cursor_action = &""
	if cursors != null: cursors.invalidate()
	if sound_effects != null: sound_effects.stop_all()
	held_keys.clear()
	route.clear()
	selected = Vector2i(-1, -1)
	attack_target_id = -1
	selected_spell = Spell.NONE
	shot_targets.clear()
	battle.reset()
	battle_overlay.hide_screen()
	action_bar.reset_menu()
	management.hide()
	legacy_management.hide()
	world_panel.hide()
	shop.hide()
	game_menu.hide()
	management_origin = &"exploration"
	_script_locked = false
	for child in battle_roster.get_children(): child.queue_free()
	roster_buttons.clear()
	_configure_exploration_view()
	campaign.configure(session, world, campaign_data, true)
	status.text = "Переход завершён."
	_refresh()
	if not _loading_save:
		_autosave_entry()
		campaign.check_triggers()


func _autosave_entry() -> void:
	# Save the prepared destination before entrance scripts start.
	if not saves.save_autosave(session, campaign, exploration):
		status.text = "Автосохранение не записано: " + saves.error


func _configure_exploration_view() -> void:
	exploration.configure(session)
	view.route_cells.clear()
	view.select_map(session.map, {"units": session.render_records()})
	view.follow_point = session.hero.position_pixels
	view.follow_hero(true)


func _travel(map_id: int, entry_id: int) -> void:
	if not session.travel(map_id, entry_id):
		if session.mode == &"travel": campaign._fail(session.travel_error)
		else:
			world_panel.message = session.travel_error
			world_panel.queue_redraw()


func _show_world(required: bool = false) -> void:
	if not session.world_travel_unlocked():
		status.text = "Сначала найдите лекаря и получите справку для входа в город."
		return
	if not required and (battle.active or campaign.busy() or management.visible or session.mode != &"exploration"): return
	held_keys.clear()
	exploration.stop()
	route.clear()
	view.route_cells.clear()
	world_panel.open(session, campaign_data, view.textures, required)


func _open_town_shop() -> void:
	if not world_panel.visible or not world_panel.in_town or world_panel.screen != &"town" or not session.world_travel_unlocked(): return
	world_panel.hide()
	management_origin = &"town"
	session.mode = &"management"
	shop.open(session, view.textures)


func _show_main_menu(initial: bool = false) -> void:
	if not initial and (campaign.busy() or management.visible or legacy_management.visible or shop.visible or world_panel.visible): return
	_menu_resume_mode = session.mode
	held_keys.clear()
	exploration.stop()
	session.mode = &"main_menu"
	main_menu.open(view.textures, metadata, _has_started)


func _show_game_menu() -> void:
	if campaign.busy() or management.visible or legacy_management.visible or main_menu.visible or world_panel.visible or shop.visible or save_slots.visible or game_menu.visible: return
	if not battle.active and session.mode != &"exploration": return
	_game_menu_resume_mode = session.mode
	held_keys.clear()
	exploration.stop()
	route.clear()
	view.route_cells.clear()
	session.mode = &"game_menu"
	_settings_from_title = false
	sound_effects.pause_world(true)
	game_menu.music_enabled = music.enabled
	game_menu.open(view.textures, metadata, battle.active)


func _game_menu_chosen(choice: int) -> void:
	if session.mode != &"game_menu" or not game_menu.choice_enabled(choice): return
	if battle.active and choice in [GameMenuChoice.SAVE, GameMenuChoice.CHARACTER, GameMenuChoice.INVENTORY, GameMenuChoice.JOURNAL]: return
	game_menu.hide()
	held_keys.clear()
	session.mode = _game_menu_resume_mode
	match choice:
		GameMenuChoice.CONTINUE: pass
		GameMenuChoice.JOURNAL, GameMenuChoice.CHARACTER, GameMenuChoice.INVENTORY:
			var pages := {GameMenuChoice.JOURNAL: Page.JOURNAL, GameMenuChoice.CHARACTER: Page.CHARACTER, GameMenuChoice.INVENTORY: Page.INVENTORY}
			_open_management(pages[choice])
			management_origin = &"game_menu"
		GameMenuChoice.SAVE: _open_save_slots(true, &"game_menu")
		GameMenuChoice.LOAD: _open_save_slots(false, &"game_menu")
		GameMenuChoice.MAIN_MENU: _show_main_menu()
		GameMenuChoice.EXIT: get_tree().quit()


func _open_save_slots(saving: bool, origin: StringName) -> void:
	if (saving and battle.active) or (campaign.busy() and origin != &"main_menu"): return
	_save_origin = origin
	held_keys.clear()
	exploration.stop()
	main_menu.hide()
	game_menu.hide()
	session.mode = &"game_menu" if origin == &"game_menu" else &"main_menu"
	save_slots.open(saves, view.textures, metadata, saving)

func _close_save_slots() -> void:
	if _save_origin == &"main_menu":
		session.mode = &"main_menu"
		main_menu.show()
	else:
		session.mode = &"game_menu"
		game_menu.show()

func _save_slot_selected(slot: int) -> void:
	if save_slots.saving:
		if battle.active: return
		if saves.save_slot(slot, session, campaign, exploration): save_slots.message = "Игра сохранена в слот %d." % (slot + 1)
		else: save_slots.message = saves.error
		save_slots.queue_redraw()
		return
	var loaded: Dictionary = saves.read_slot(slot, world, metadata, table, rewards)
	if loaded.is_empty():
		save_slots.message = saves.error
		save_slots.queue_redraw()
		return
	var restored = loaded["session"]
	_loading_save = true
	# Keep the live session object and its signal connections.
	for key in ["map", "current_scene", "location_id", "entry_id", "world_rng", "last_rumour", "gate_choices", "campaign_completed", "rain_remaining", "rain_elapsed", "rain_layers", "flags", "dungeon_seeds", "hero", "collision", "units", "party", "gold", "inventory", "next_item_id", "simulation_tick"]: session.set(key, restored.get(key))
	session.commands.clear()
	session.god_mode = false
	session.mode = &"exploration"
	session.rebuild_paths()
	main_menu.hide()
	save_slots.hide()
	_location_changed()
	exploration.restore_trails(loaded["exploration"])
	campaign.pending.assign(loaded["pending"])
	_loading_save = false
	_has_started = true
	status.text = "Автосохранение загружено." if slot == saves.AUTOSAVE_SLOT else "Игра загружена из слота %d." % (slot + 1)
	_refresh()


func _management_closed() -> void:
	if management_origin == &"town": world_panel.show_town()
	elif management_origin == &"game_menu":
		session.mode = &"game_menu"
		game_menu.show()
	else: session.mode = &"exploration"
	held_keys.clear()
	_refresh()


func _open_management(page: int, receipt: Dictionary = {}, debug: bool = false) -> void:
	if battle.active or campaign.busy() or session.mode != &"exploration" or management.visible or legacy_management.visible: return
	held_keys.clear()
	exploration.stop()
	route.clear()
	view.route_cells.clear()
	session.mode = &"management"
	management_origin = &"exploration"
	if not debug and page in [Page.CHARACTER, Page.INVENTORY, Page.JOURNAL]: legacy_management.open(session, campaign_data, view.textures, page)
	else: management.open(session, campaign_data, view.textures, page, receipt)
	_refresh()


func _exploration_tick() -> void:
	campaign.check_triggers()
	if campaign.busy() or session.mode != &"exploration" or not campaign.enabled: return
	var receipt: Dictionary = session.collect_nearby()
	if receipt.is_empty(): return
	sound_effects.play_clip("add.wav", false)
	var hook: int = int(receipt["script_id"])
	if hook >= 0: campaign.pending.append(hook)
	_open_management(Page.LOOT, receipt)


func _capture_management(page: int) -> void:
	_restart(false)
	session.hero.attribute_points = 5
	session.hero.skill_points = 1
	Inventory.add(session, 13)
	Inventory.add(session, 36)
	session.gold = 200
	_open_management(page, {"gold": 300, "items": [Ids.ItemId.LAST_SWORD]} if page == Page.LOOT else {})
	if page == Page.CHARACTER:
		legacy_management.confirm()
		legacy_management.selected = 2
		legacy_management.adjust(1)
	if page == Page.INVENTORY:
		legacy_management.confirm()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var name: String = "loot" if page == Page.LOOT else "progression" if page == Page.CHARACTER else "inventory"
	_save_capture("stage7-%s.png" % name, "Stage 7 management capture")


func _capture_travel(screen: String) -> void:
	_restart(false)
	# World/town captures represent the post-certificate stage.
	session.quests[Ids.Quest.CITY_CERTIFICATE] = Ids.QuestState.COMPLETED
	session.tutorial_seen[Ids.Tutorial.TOWN] = 1
	if screen == "dungeon":
		session.dungeon_seeds[0] = 20261027
		_travel(-1, 0)
		view.follow_hero(true)
	elif screen == "world": _show_world(false)
	elif screen == "menu": _show_main_menu(true)
	elif screen == "game-menu":
		session.dungeon_seeds[0] = 20261027
		_travel(-1, 0)
		campaign.enabled = false
		campaign.script_id = -1
		session.mode = &"exploration"
		_show_game_menu()
	else:
		_show_world(false)
		world_panel.show_town()
		if screen == "sale":
			_open_town_shop()
			shop.selected = 1
			shop.confirm()
	set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_capture("stage7-%s.png" % screen, "Stage 7 travel capture")


func _input(event: InputEvent) -> void:
	if event is not InputEventKey or event.echo:
		return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if _dev_shortcut(event, key):
		get_viewport().set_input_as_handled()
		return
	if legacy_management.visible:
		if event.pressed: legacy_management.handle_key(key)
		get_viewport().set_input_as_handled()
		return
	var legacy_screen = save_slots if save_slots.visible else game_menu if game_menu.visible else main_menu if main_menu.visible else shop if shop.visible else world_panel if world_panel.visible else null
	if legacy_screen != null:
		if event.pressed and legacy_screen == game_menu and game_menu.settings_open:
			game_menu.handle_settings_key(key)
			get_viewport().set_input_as_handled()
			return
		if event.pressed:
			if legacy_screen == main_menu and key == KEY_F2:
				main_menu.settings_requested.emit()
				get_viewport().set_input_as_handled()
				return
			sound_effects.play_clip("back.wav" if key == KEY_ESCAPE else "click_ok.wav", false)
			if key == KEY_ESCAPE: legacy_screen.back()
			elif key in [KEY_LEFT, KEY_UP, KEY_A, KEY_W]: legacy_screen.navigate(-1)
			elif key in [KEY_RIGHT, KEY_DOWN, KEY_D, KEY_S]: legacy_screen.navigate(1)
			elif key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]: legacy_screen.confirm()
		get_viewport().set_input_as_handled()
		return
	if management.visible:
		if event.pressed and (key == KEY_ESCAPE or (management.page == Page.LOOT and key in [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER])):
			management.dismiss()
			get_viewport().set_input_as_handled()
		return
	if event.pressed and key == KEY_ESCAPE and battle.active:
		if selected_spell >= 0 or action_bar.submenu:
			battle_cursor_action = &""
			selected_spell = -1
			shot_targets.clear()
			action_bar.submenu = false
			action_bar._signature = ""
			_refresh()
		else: _show_game_menu()
		get_viewport().set_input_as_handled()
		return
	if battle_overlay.phase != &"":
		if event.pressed and key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]: battle_overlay.acknowledge()
		get_viewport().set_input_as_handled()
		return
	if campaign.busy():
		if event.pressed and key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]: campaign.acknowledge()
		get_viewport().set_input_as_handled()
		return
	if event.pressed and key in [KEY_C, KEY_I, KEY_J]:
		_open_management({KEY_C: Page.CHARACTER, KEY_I: Page.INVENTORY, KEY_J: Page.JOURNAL}[key])
	elif event.pressed and key == KEY_M:
		_show_world(false)
	elif event.pressed and key == KEY_ESCAPE:
		_show_game_menu()
	elif event.pressed and key == KEY_F:
		view.follow_hero()
	elif key in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		if battle.active: return
		if event.pressed:
			held_keys[key] = true
			route.clear()
			view.route_cells.clear()
		else:
			held_keys.erase(key)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_dev_keys.clear()
		_dev_chord_active = false
		if exploration.session != null: _stop()


func _snapshot() -> void:
	if session.hero == null:
		return
	var path: String = ProjectSettings.globalize_path("res://../build/gameplay-snapshot.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Не удалось записать снимок.")
		return
	file.store_string(JSON.stringify({"world": session.snapshot(), "exploration": exploration.snapshot(), "battle": battle.snapshot(), "campaign": campaign.snapshot()}, "\t"))
	status.text = "Снимок записан:\nbuild/gameplay-snapshot.json"


func _run_checks() -> void:
	# Travel/new-game checks must never overwrite the player's autosave.
	var original_save_directory: String = saves.directory
	saves.directory = "user://gameplay-test-%d" % Time.get_ticks_usec()
	_restart(false)
	var checks := Checks.new()
	checks.run(world, metadata, table)
	ExplorationChecks.new().run(checks, world, metadata, table)
	BattleChecks.new().run(checks, world, metadata, table)
	CombatChecks.new().run(checks, world, metadata, table, rewards)
	MagicChecks.new().run(checks, world, metadata, table)
	EconomyChecks.new().run(checks, world, metadata, table, rewards)
	TravelChecks.new().generation(checks, metadata)
	TravelChecks.new().travel(checks, world, metadata, table, rewards, campaign_data)
	CampaignChecks.new().run(checks, world, metadata, table, rewards, campaign_data)
	SaveChecks.new().run(checks, world, metadata, table, rewards, campaign_data)
	FullCampaignChecks.new().run(checks, world, metadata, table, rewards, campaign_data)
	await get_tree().process_frame
	await get_tree().process_frame
	# Exercise actual cell input -> route -> movement -> occupancy and restart.
	var target := session.hero.cell + Vector2i.LEFT * 3
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = view.cell_center(target)
	view._gui_input(click)
	checks.check(not route.is_empty(), "UI click produces a route")
	var destination: Vector2i = route.back() if not route.is_empty() else session.hero.cell
	move_button.pressed.emit()
	_process(10.0)
	checks.check(not moving and session.hero.cell == destination, "UI route movement reaches destination")
	checks.check(session.collision.occupants.get(destination) == session.hero.instance_id, "movement updates occupancy")
	_snapshot()
	checks.check(FileAccess.file_exists("res://../build/gameplay-snapshot.json"), "debug snapshot written")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../build/gameplay-snapshot.json"))
	checks.check(saved["world"]["hero"]["cell"][0] == destination.x and saved["world"]["commands"].size() == session.commands.size(), "snapshot contains current position and commands")
	# Cancel midway and continue from the occupied cell, with a fresh distance field.
	_select_cell(session.hero.cell + Vector2i.LEFT * 3, 0)
	checks.check(route.size() >= 2, "cancellation fixture has multiple steps")
	_begin_move()
	_process(0.12)
	checks.check(moving and not route.is_empty(), "movement can be interrupted between steps")
	stop_button.pressed.emit()
	checks.check(not moving and route.is_empty() and session.pathfinder.start == session.hero.cell, "cancel rebuilds routes from current actor position")
	_restart(false)
	checks.check(session.hero.position_pixels == Vector2(544, 384) and session.commands.is_empty(), "restart resets state and log")
	# Actual keyboard event path, source priority, release, focus loss and camera.
	var key := InputEventKey.new()
	key.physical_keycode = KEY_A
	key.pressed = true
	_input(key)
	var start: Vector2 = session.hero.position_pixels
	_process(0.062)
	checks.check(session.hero.position_pixels == start + Vector2(-4, 0), "WASD event drives pixel motor")
	key.pressed = false
	_input(key)
	_process(0.062)
	checks.check(session.hero.position_pixels == start + Vector2(-4, 0), "key release stops movement")
	key.physical_keycode = KEY_RIGHT
	key.pressed = true
	_input(key)
	_process(0.062)
	checks.check(session.hero.position_pixels == start, "arrow key drives same cardinal motor")
	_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_process(0.062)
	checks.check(held_keys.is_empty() and not moving and session.hero.position_pixels == start, "focus loss clears held input")
	view.follow_hero(true)
	view._update_transform()
	var hero_screen: Vector2 = view.map_origin + view.follow_point * view.pixel_scale
	checks.check(view.camera_follow and view.zoom_factor >= 2.5 and Rect2(Vector2.ZERO, view.size).has_point(hero_screen), "following camera keeps hero visible at exploration zoom")
	var map_extent: Vector2 = Vector2(float(session.map["width"]), float(session.map["height"])) * 16 * view.pixel_scale
	checks.check(view.map_origin.x <= 0 and view.map_origin.y <= 0 and view.map_origin.x >= view.size.x - map_extent.x - 1 and view.map_origin.y >= view.size.y - map_extent.y - 1, "following camera clamps to map bounds")
	view.fit_map()
	checks.check(not view.camera_follow and view.zoom_factor == 1.0 and not camera_toggle.button_pressed, "fit map exits following mode")
	view.follow_hero(true)
	var drag := InputEventMouseButton.new()
	drag.button_index = MOUSE_BUTTON_RIGHT
	drag.pressed = true
	drag.position = view.size * 0.5
	view._gui_input(drag)
	checks.check(not view.camera_follow and not camera_toggle.button_pressed, "manual camera movement disables following")
	drag.pressed = false
	view._gui_input(drag)
	view.follow_hero(true)
	for direction in range(4):
		session.hero.facing = direction
		session.hero.walking = true
		session.hero.animation_frame = 1
		var pose: Dictionary = view.sprite_pose(session.hero.render_record())
		checks.check(pose["column"] == int(view.graphics["units"][0]["frame_columns"][direction][1]), "original walking atlas column in direction %d" % direction)
	session.hero.walking = false
	checks.check(view.sprite_pose(session.hero.render_record())["column"] == 0, "down-facing warrior restores special idle atlas frame")
	_demo_party()
	checks.check(session.party.size() == 2 and session.demo_party and view.current_scene["units"].size() == 6, "test-party button refreshes active render records")
	_demo_battle()
	checks.check(battle_overlay.phase == &"intro" and session.mode == &"battle_intro" and not battle.can_input(), "monochrome battle intro blocks command input")
	var intro_tick: int = battle.tick_count
	_process(0.5)
	checks.check(battle.tick_count == intro_tick and battle_overlay.visible, "intro holds combat simulation while presentation advances")
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	_input(key)
	checks.check(session.mode == &"battle" and not battle_overlay.visible and action_bar.visible, "Space dismisses intro and reveals action bar")
	battle.enemy_policy = &"defend" # Keep stage-three UI regression sequence stable.
	checks.check(battle.active and session.mode == &"battle" and battle.participants.size() == 3, "test battle enters combat with two allies and one enemy")
	view._update_transform()
	var arena_screen := Rect2(view.map_origin + Vector2(battle.arena.position) * 16 * view.pixel_scale, Vector2(battle.arena.size) * 16 * view.pixel_scale)
	checks.check(Rect2(Vector2.ZERO, view.size).encloses(arena_screen), "battle camera shows entire arena")
	checks.check(arena_screen.get_center().distance_to(view.size * 0.5) < 2, "battle camera centers arena using pixel coordinates")
	checks.check(battle_controls.visible and action_bar.visible and view.battle.active and not defend_button.disabled, "battle HUD exposes player commands")
	var before: Vector2 = session.hero.position_pixels
	key.physical_keycode = KEY_A
	key.pressed = true
	_input(key)
	_process(0.062)
	checks.check(session.hero.position_pixels == before and held_keys.is_empty(), "battle ignores exploration keyboard movement")
	_select_battle_cell(session.party[1].cell)
	checks.check(battle.selected_id == session.party[1].instance_id, "battle map click selects ally")
	defend_button.pressed.emit()
	checks.check(battle.busy() and defend_button.disabled, "defense button queues and locks command input")
	_process(1.0)
	checks.check(battle.current_side == Side.PARTY and battle.selected_id == session.hero.instance_id, "finishing archer keeps player side and selects hero")
	end_side_button.pressed.emit()
	_process(0.062)
	checks.check(battle.current_side == Side.HOSTILE and end_side_button.disabled, "end side hands control to enemy")
	_process(1.0)
	checks.check(battle.current_side == Side.PARTY and battle.round_number == 2, "enemy defense returns to player round two")
	_snapshot()
	_demo_battle()
	battle_overlay.acknowledge()
	_select_battle_cell(battle.unit(1004).cell)
	checks.check(attack_target_id == 1004 and not attack_button.disabled, "enemy click exposes valid melee approach action")
	attack_button.pressed.emit()
	checks.check(battle.busy() and attack_button.disabled, "attack button queues action and locks input")
	_process(2.0)
	checks.check(battle.unit(1004).stats[Stat.HP] < battle.unit(1004).stats[Stat.MAX_HP] and battle.selected_id == session.party[1].instance_id, "UI melee approach applies damage and selects archer")
	_select_battle_cell(battle.unit(1004).cell)
	checks.check(not attack_button.disabled and attack_button.text == "Стрелять в цель", "archer UI offers ranged action")
	_select_battle_cell(battle.unit(1004).cell)
	checks.check(battle.busy(), "repeated target click queues ranged attack")
	checks.check(CombatChecks.new().drive(battle), "UI battle can be completed with unmodified stats")
	_refresh()
	checks.check(battle.outcome == &"victory" and result_controls.visible and continue_button.visible and not battle_controls.visible, "victory screen replaces command HUD")
	checks.check(battle_overlay.phase == &"victory" and battle_overlay.body.text.contains(str(battle.reward["xp_total"])), "result window shows original total XP and gold over monochrome map")
	var earned: int = session.gold
	_snapshot()
	var result_saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../build/gameplay-snapshot.json"))
	checks.check(result_saved["battle"]["outcome"] == "victory" and result_saved["battle"]["rng"]["draws"] > 0 and result_saved["world"]["gold"] == earned, "debug snapshot includes result and RNG state")
	battle_overlay.footer.pressed.emit()
	checks.check(session.mode == &"exploration" and not battle.active and not result_controls.visible and session.gold == earned, "continue button restores exploration without changing awarded gold")
	checks.check(session.is_active(session.units[6]) and not session.units[6].dead, "defeating one shared-flag NPC preserves the other instance")
	_demo_battle(true)
	_process(2.01)
	checks.check(battle_overlay.phase == &"" and session.mode == &"battle", "intro can finish automatically without spending any combat tick")
	checks.check(not action_bar.buttons.has("magic"), "warrior action menu does not invent magic skills")
	checks.check(battle.select(1001) and action_bar.buttons.has("magic"), "selecting original hermit exposes magic action")
	action_bar.buttons["magic"].pressed.emit()
	checks.check(action_bar.submenu and action_bar.buttons.size() == 10 and action_bar.caption.text.contains("3 МП"), "spell submenu shows all nine learned spells, mana and Back without carousel")
	var caster_mana: int = battle.unit(1001).stats[Stat.MANA]
	action_bar.buttons["0"].pressed.emit()
	checks.check(selected_spell == 0 and not battle.busy(), "selecting a spell enters targeting without spending mana")
	key.physical_keycode = KEY_ESCAPE
	_input(key)
	checks.check(selected_spell == -1 and not action_bar.submenu and battle.unit(1001).stats[Stat.MANA] == caster_mana, "Escape exits spell targeting without spending resources")
	action_bar.buttons["magic"].pressed.emit()
	battle.unit(1001).stats[Stat.MANA] = 0
	_refresh()
	checks.check(action_bar.buttons["0"].disabled and not action_bar.buttons["back"].disabled, "insufficient mana disables spells while Back stays usable")
	battle.unit(1001).stats[Stat.MANA] = caster_mana
	_refresh()
	action_bar.buttons["0"].pressed.emit()
	_select_battle_cell(battle.unit(1004).cell)
	checks.check(not attack_button.disabled, "spell target enables confirmation button")
	attack_button.pressed.emit()
	checks.check(battle.busy() and attack_button.disabled, "spell confirmation queues exactly one command and locks input")
	for i in range(150):
		if not battle.busy(): break
		_process(0.062)
	checks.check(battle.unit(1001).stats[Stat.MANA] == caster_mana - 3 and battle.unit(1004).stats[Stat.HP] < battle.unit(1004).stats[Stat.MAX_HP], "UI fire arrow spends original three MP and damages target")
	await EconomyUIChecks.new().run(self, checks)
	_restart()
	checks.check(campaign.script_id == Ids.StoryScript.EXPLORATION_TUTORIAL and held_keys.is_empty(), "normal new game enters original tutorial")
	_process(0.062)
	var frozen: Vector2 = session.hero.position_pixels
	_process(2)
	checks.check(dialogue_layer.visible and session.hero.position_pixels == frozen and not dialogue_body.text.is_empty(), "story UI shows original text and freezes exploration")
	checks.check(_walk_story_to(Vector2(488, 200)), "walk through opening quake to clearing")
	checks.check(int(session.quests[Ids.Quest.WOLVES]) == Ids.QuestState.COMPLETED and int(session.quests[Ids.Quest.WAY_HOME]) == Ids.QuestState.ACTIVE, "walking triggers original opening quest changes")
	checks.check(_walk_story_to(Vector2(344, 104)) and session.party.size() == 2 and session.party[1].story_group == Ids.StoryGroup.HERMIT, "walking recruits hermit without debug reset")
	checks.check(_walk_story_to(Vector2(488, 440)), "walk to bat and finish first natural encounter")
	checks.check(int(session.triggers[Ids.StoryScript.BAT_DEFEATED]) == Ids.TriggerState.DISABLED and session.party.size() == 1, "natural bat victory executes hermit departure hook")
	checks.check(_walk_story_to(Vector2(344, 104)) and int(session.triggers[Ids.StoryScript.MEET_LI]) == Ids.TriggerState.ENABLED, "return to hermit enables original Li rescue")
	checks.check(_walk_story_to(Vector2(72, 72)) and session.party.size() == 2 and session.party[1].story_group == Ids.StoryGroup.LI, "original Li dialogue recruits companion through normal map triggers")
	checks.check(_walk_story_to(Vector2(168, 488)), "hero and Li reach troll and finish real combat")
	checks.check(int(session.triggers[Ids.StoryScript.TROLL_DEFEATED]) == Ids.TriggerState.DISABLED and int(session.quests[Ids.Quest.LETTER]) == Ids.QuestState.COMPLETED and int(session.triggers[Ids.StoryScript.ENTER_DUNGEON]) == Ids.TriggerState.ENABLED, "natural troll death completes letter quest once")
	TravelUIChecks.new().run(self, checks)
	LegacyUIChecks.new().run(self, checks)
	GameMenuChecks.new().run(self, checks)
	LegacyManagementChecks.new().run(self, checks)
	SaveChecks.new().run_ui(self, checks)
	SaveChecks.new().run_autosave_ui(self, checks)
	MediaSettingsChecks.new().run(self, checks)
	InteractionChecks.new().run(self, checks)
	CorpseTargetingChecks.new().run(self, checks)
	ReportedUIChecks.new().run(self, checks)
	MapFourChecks.new().run(checks, world, metadata, table, rewards, campaign_data)
	CombatNavigationChecks.new().run(self, checks)
	PresentationChecks.new().run(self, checks)
	await PresentationChecks.new().layout(self, checks)
	_snapshot()
	# Let the audio thread release stopped Ogg playback before the test quits.
	set_process(false)
	sound_effects.stop_all()
	music.shutdown()
	await get_tree().create_timer(0.05).timeout
	if checks.failures == 0:
		print("PASS: stages 1–8 — %d checks; Java references, exploration, combat, progression, travel, dungeons, campaign, saves and UI" % checks.count)
	for slot in range(saves.TOTAL_SLOT_COUNT):
		for suffix in ["", ".tmp", ".bak"]:
			if FileAccess.file_exists(saves.path(slot) + suffix): DirAccess.remove_absolute(saves.path(slot) + suffix)
	DirAccess.remove_absolute(saves.directory)
	saves.directory = original_save_directory
	if FileAccess.file_exists(preferences.path): DirAccess.remove_absolute(preferences.path)
	get_tree().quit(0 if checks.failures == 0 else 1)


func _walk_story_to(point: Vector2, limit: int = 4000, stop_at_dialogue: int = -1) -> bool:
	var original_location: int = session.location_id
	var goal := Vector2i((point - Vector2(session.hero.footprint) * 8) / 16.0)
	var destination := Vector2(goal) * 16 + Vector2(session.hero.footprint) * 8
	for i in range(limit):
		if session.location_id != original_location: return true
		if not campaign.fault.is_empty(): return false
		if management.visible:
			management.dismiss()
		elif legacy_management.visible:
			legacy_management.dismiss()
		elif battle_overlay.phase == &"intro":
			_process(0.062)
		elif campaign.busy():
			if campaign.modal.get("kind") == "dialogue" and int(campaign.modal["id"]) == stop_at_dialogue: return true
			if not campaign.modal.is_empty(): dialogue_next.pressed.emit()
			else: _process(0.062)
		elif battle.active:
			if not CampaignChecks.new().drive(battle) or battle.outcome != &"victory":
				print("Story battle failed: ", battle.participants, " outcome=", battle.outcome, " goal=", point)
				return false
			_continue_after_battle()
		elif session.hero.position_pixels == destination:
			return true
		else:
			if not moving:
				_select_cell(goal, 0)
				if route.is_empty():
					# The hermit's closest physical pose is 8px short of the
					# requested grid center; it is inside the inclusive trigger.
					if session.hero.position_pixels.distance_to(destination) <= 8: return true
					print("Story route unavailable: ", session.hero.position_pixels, " -> ", point)
					return false
				_begin_move()
			_process(0.062)
	print("Story route timeout: ", session.hero.position_pixels, " -> ", point, " script=", campaign.script_id)
	return false


func _capture_story() -> void:
	_restart()
	if not _walk_story_to(Vector2(488, 200)) or not _walk_story_to(Vector2(344, 104)) or not _walk_story_to(Vector2(488, 440)) or not _walk_story_to(Vector2(344, 104)) or not _walk_story_to(Vector2(72, 72), 4000, 5):
		get_tree().quit(1)
		return
	set_process(false)
	view.follow_point = session.hero.position_pixels
	view.follow_hero(true)
	_refresh_visuals()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_snapshot()
	_save_capture("stage5-dialogue.png", "Stage 5 dialogue")


func _capture() -> void:
	_demo_party()
	_select_cell(Vector2i(26, 22), 0)
	_begin_move()
	_process(0.85)
	set_process(false)
	view.follow_hero(true)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_capture("stage2-preview.png", "Stage 2 preview")


func _capture_battle() -> void:
	_demo_battle()
	battle_overlay.acknowledge()
	battle.attack(1004)
	_process(2.0)
	battle.attack(1004)
	_process(0.062 * 11)
	set_process(false)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_capture("stage6-battle.png", "Stage 6 preview")


func _capture_victory() -> void:
	_demo_battle()
	battle_overlay.acknowledge()
	if not CombatChecks.new().drive(battle):
		_fail("Тестовый бой не завершился.")
		get_tree().quit(1)
		return
	_refresh_battle()
	set_process(false)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_capture("stage6-result.png", "Stage 6 outcome: " + str(battle.outcome))


func _capture_combat_ui(screen: String) -> void:
	var spell_screens := {"spell": Spell.FIRE_ARROW, "frost": Spell.FROST, "lightning": Spell.LIGHTNING, "blessing": Spell.BLESS, "meteor": Spell.METEOR, "meteor-shards": Spell.METEOR}
	_demo_battle(screen.begins_with("magic") or spell_screens.has(screen))
	if screen.begins_with("magic") or spell_screens.has(screen):
		battle_overlay.acknowledge()
		if screen == "magic-full" or (spell_screens.has(screen) and screen != "spell"):
			var caster = battle.unit(1001)
			for school in Ids.MAGIC_SCHOOLS: caster.base_stats[school] = 9
			caster.recalculate(table)
		if screen.begins_with("meteor"):
			var target = battle.unit(1004)
			target.base_stats[Stat.MAX_HP] = 10000
			target.recalculate(table)
			target.stats[Stat.HP] = target.stats[Stat.MAX_HP]
		battle.select(1001)
		_choose_action("magic", -1)
		if spell_screens.has(screen):
			var spell: int = spell_screens[screen]
			_choose_action("spell", spell)
			_select_battle_cell(battle.unit(1001 if screen == "blessing" else 1004).cell)
			_attack_target()
			for i in range(40):
				_process(0.062)
				if battle.current.get("phase") == "flight": break
			var capture_time: float = {"blessing": 1.24, "lightning": 0.372, "meteor": 0.682, "meteor-shards": 0.992}.get(screen, 0.248)
			_process(capture_time)
			var valid_capture: bool = not view.combat_feedback.meteor_shards().is_empty() if screen == "meteor-shards" else battle.current.get("phase") == "flight" and int(battle.current.get("spell", -1)) == spell
			if not valid_capture:
				push_error("Spell capture did not reach the requested flight phase")
				get_tree().quit(1)
				return
			if screen == "lightning" or screen.begins_with("meteor"):
				view._update_transform()
				view.pan.y += view.size.y - (240 if screen == "lightning" else 300) - view.cell_center(battle.unit(1004).cell).y
	if screen == "combat-menu":
		battle_overlay.acknowledge()
		_show_game_menu()
	set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if screen == "magic-full":
		var viewport_rect := Rect2(Vector2.ZERO, get_viewport_rect().size)
		for button: Button in action_bar.buttons.values():
			if not viewport_rect.encloses(button.get_global_rect()):
				push_error("Spell button outside viewport: " + button.tooltip_text)
				get_tree().quit(1)
				return
	_save_capture("stage6-" + screen + ".png", "Battle UI capture")


func _capture_stage8(ending: bool) -> void:
	_restart(false)
	campaign.enabled = true
	if ending:
		session.add_demo_companion()
		session.dungeon_seeds[11] = 20261027
		session.tutorial_seen[2] = 1
		_travel(-12, 0)
		campaign.configure(session, world, campaign_data, true)
		session.mode = &"exploration"
		for actor in session.units:
			if actor.unit_type != Ids.UnitKind.DRAGON: continue
			var ids: Array[int] = [actor.instance_id]
			_begin_battle(ids)
			_finish_battle_intro()
			actor.dead = true
			actor.stats[Stat.HP] = 0
			battle._check_outcome()
			_refresh()
			break
	else:
		_has_started = true
		_open_save_slots(true, &"game_menu")
	set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_capture("stage8-%s.png" % ("ending" if ending else "saves"), "Stage 8 capture")


func _set_god_mode(enabled: bool) -> void:
	session.god_mode = enabled
	if enabled:
		for actor in session.party:
			actor.dead = false
			actor.shattered = false
			actor.effects.clear()
			actor.petrify_rounds = 0
			actor.recalculate(table)
			actor.stats[Stat.HP] = actor.stats[Stat.MAX_HP]
			actor.stats[Stat.MANA] = actor.stats[Stat.MAX_MANA]
	_refresh()


func _exit_tree() -> void:
	if cursors != null: cursors.shutdown()
	ui_icons.shutdown()
	if sound_effects != null: sound_effects.shutdown()
	if music != null: music.shutdown()


func _capture_presentation(screen: String) -> void:
	_restart(false)
	if screen in ["zones", "damage"]:
		_demo_battle(true)
		battle_overlay.acknowledge()
		if screen == "zones": _choose_action("move", -1)
		else:
			battle.apply_payload(session.hero, battle.unit(1004), preload("res://scripts/gameplay/combat_rules.gd").physical_payload(session.hero, false, table))
			view.combat_feedback.advance(0.248)
			battle.select(1001)
	elif screen == "gold":
		_open_management(Page.LOOT, {"gold": 500, "items": []})
	elif screen == "town-help":
		session.quests[Ids.Quest.CITY_CERTIFICATE] = Ids.QuestState.COMPLETED
		session.tutorial_seen[Ids.Tutorial.TOWN] = 0
		_show_world(false)
		world_panel.show_town()
	elif screen == "rain":
		session.start_rain(180, 1)
		session.advance_weather(2.48)
	elif screen == "settings":
		_show_game_menu()
		game_menu.selected = GameMenuChoice.SETTINGS
		game_menu.confirm()
	set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_capture("stage8-%s.png" % screen, "Presentation capture")


func _save_capture(filename: String, description: String) -> void:
	var path: String = ProjectSettings.globalize_path("res://../build/" + filename)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error: Error = get_viewport().get_texture().get_image().save_png(path)
	print("%s: %s (%s)" % [description, path, error_string(error)])
	get_tree().quit(0 if error == OK else 1)
