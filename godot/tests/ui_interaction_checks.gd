extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Settings = preload("res://scripts/gameplay/game_settings.gd")
const Icons = preload("res://scripts/gameplay/ui_icons.gd")
const Credits = preload("res://scripts/gameplay/credits.gd")

func run(root, checks) -> void:
	var original: Dictionary = root.preferences.values.duplicate()
	var original_path: String = root.preferences.path
	root.preferences.path = "user://interaction-check-%d.cfg" % Time.get_ticks_usec()
	root._restart(false)
	root.preferences.update("crt_enabled", false, false)
	root._show_game_menu()
	root.game_menu.selected = Ids.GameMenuChoice.SETTINGS
	root.game_menu.confirm()
	root.game_menu.settings_selected = 5
	root.game_menu.confirm()
	checks.check(root.preferences.values["crt_enabled"] and root.crt_filter.overlay.visible, "CRT setting enables the actual shader overlay immediately")
	checks.check(root.crt_filter.overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "CRT overlay passes mouse input through")
	var restored := Settings.new()
	restored.path = root.preferences.path
	restored.load_settings()
	checks.check(restored.values["crt_enabled"], "CRT preference survives reopening settings")
	root.game_menu.confirm()
	checks.check(not root.crt_filter.overlay.visible, "CRT can be disabled without changing scenes")
	root.game_menu.back()
	for choice in [Ids.GameMenuChoice.CONTROLS, Ids.GameMenuChoice.CREDITS]:
		root.game_menu.selected = choice
		root.game_menu.confirm()
		checks.check(root.game_menu.body.size() > 18 and root.game_menu.literal_latin, "in-game help/credits scroll and preserve Latin key and author names")
		root.game_menu.navigate(10000)
		checks.check(root.game_menu.scroll == root.game_menu.body.size() - 18, "in-game document can scroll to its final line")
		root.game_menu.back()
		checks.check(root.game_menu.body.is_empty() and not root.game_menu.literal_latin, "closing document restores original bitmap glyphs")
	root.game_menu.back()
	root._show_main_menu(true)
	for choice in [Ids.TitleChoice.CONTROLS, Ids.TitleChoice.CREDITS]:
		root.main_menu.selected = choice
		root.main_menu.confirm()
		checks.check(root.main_menu.body.size() > 12 and root.main_menu.literal_latin, "title help and credits share the complete documents")
		root.main_menu.navigate(10000)
		checks.check(root.main_menu.scroll == root.main_menu.body.size() - 12, "title document can scroll to its final line")
		root.main_menu.back()
	checks.check(Credits.TEXT.contains("2005") and Credits.TEXT.contains("Чикин Родион") and Credits.TEXT.contains("правообладателям"), "credits retain original attribution and fan-project rights notice")
	var bounds := Rect2(20, 9, 48, 52)
	var fitted: Rect2 = Icons.fit_rect(root.ui_icons.portraits[17], bounds)
	checks.check(fitted.is_equal_approx(Rect2(24, 9, 40, 52)), "Li portrait fits its Character slot without the reported horizontal stretch")
	for texture: Texture2D in root.ui_icons.portraits.values():
		fitted = Icons.fit_rect(texture, bounds)
		checks.check(bounds.encloses(fitted) and is_equal_approx(fitted.size.aspect(), texture.get_size().aspect()), "portrait fit preserves aspect and stays within the slot")
	root._demo_battle(true)
	root.battle_overlay.acknowledge()
	var point: Vector2 = root.view.cell_center(root.battle.unit(1004).cell)
	var state: Dictionary = root.cursors.resolve(root, point, true)
	checks.check(state["kind"] == "default", "battle begins with the ordinary cursor")
	root.action_bar.buttons["move"].pressed.emit()
	state = root.cursors.resolve(root, point, true)
	checks.check(state["kind"] == "move" and state["blocked"], "movement button selects its cursor and marks an occupied enemy cell invalid")
	root.action_bar.buttons["attack"].pressed.emit()
	state = root.cursors.resolve(root, point, true)
	checks.check(state["kind"] == "attack", "attack button selects the original sword cursor")
	root.battle.select(root.session.party[1].instance_id)
	root._refresh_battle()
	root.action_bar.buttons["shoot"].pressed.emit()
	state = root.cursors.resolve(root, point, true)
	checks.check(state["kind"] == "shoot", "archer's action selects the ranged icon cursor")
	root.battle.select(1001)
	root._refresh_battle()
	root.action_bar.buttons["magic"].pressed.emit()
	root.action_bar.buttons["0"].pressed.emit()
	state = root.cursors.resolve(root, point, true)
	checks.check(state["kind"] == "spell" and state["spell"] == 0, "real spell button selects the corresponding spell icon")
	root.preferences.update("hd_icons", false, false)
	root.cursors.apply(state, root.ui_icons)
	var legacy: Texture2D = root.cursors.current_texture
	root.preferences.update("hd_icons", true, false)
	root.cursors.apply(state, root.ui_icons)
	checks.check(root.cursors.current_texture != legacy and root.cursors.current_texture.get_size() == Vector2(48, 48), "selected spell cursor follows the HD icon toggle")
	var caster = root.battle.unit(1001)
	var mana: int = caster.stats[Ids.Stat.MANA]
	caster.stats[Ids.Stat.MANA] = 0
	checks.check(root.cursors.resolve(root, point, true)["blocked"], "spell cursor marks insufficient mana without advancing a simulation tick")
	caster.stats[Ids.Stat.MANA] = mana
	checks.check(root.cursors.resolve(root, point, false)["kind"] == "default", "moving over interface controls restores the ordinary cursor")
	root._show_game_menu()
	checks.check(root.cursors.resolve(root, point, true)["kind"] == "default", "opening a battle menu restores the ordinary cursor")
	root.game_menu.back()
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.physical_keycode = KEY_ESCAPE
	root._input(escape)
	checks.check(root.selected_spell == -1 and root.cursors.resolve(root, point, true)["kind"] == "default", "Escape cancels both spell selection and its cursor")
	for kind: String in root.cursors.assets:
		var texture: Texture2D = root.cursors.assets[kind]
		var hotspot: Vector2 = root.cursors.hotspots[kind]
		checks.check(Rect2(Vector2.ZERO, texture.get_size()).has_point(hotspot) and texture.get_image().detect_alpha() != Image.ALPHA_NONE, "original cursor has valid hotspot and real transparency: " + kind)
	root._restart(false)
	checks.check(root.battle_cursor_action == &"" and root.cursors.resolve(root, point, true)["kind"] == "default", "restart clears the selected combat cursor")
	DirAccess.remove_absolute(root.preferences.path)
	root.preferences.path = original_path
	for key: String in original: root.preferences.update(key, original[key], false)
