extends Node
## Nival cursor artwork plus the selected game's action/spell icon.
const Ids = preload("res://scripts/gameplay/game_ids.gd")
var assets: Dictionary = {}
var hotspots: Dictionary = {}
var applied_key: String = ""
var current_texture: Texture2D
var current_hotspot := Vector2.ZERO
var _cache: Dictionary = {}
var _resolve_key: String = ""
var _resolved: Dictionary = {}

func configure() -> void:
	var path: String = "res://data/hd/cursors/manifest.json"
	if not FileAccess.file_exists(path): return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	for kind: String in manifest:
		assets[kind] = load(manifest[kind]["file"]) as Texture2D
		hotspots[kind] = Vector2(float(manifest[kind]["hotspot"][0]), float(manifest[kind]["hotspot"][1]))

func invalidate() -> void:
	_resolve_key = ""
	_resolved.clear()

func resolve(game, point: Vector2, on_map: bool) -> Dictionary:
	var normal := {"kind": "default", "spell": -1, "blocked": false}
	if not on_map or game.session.mode != &"battle" or not game.battle.active: return normal
	if game.campaign.busy() or game.game_menu.visible or game.save_slots.visible or game.main_menu.visible or game.management.visible or game.legacy_management.visible or game.world_panel.visible or game.shop.visible: return normal
	for index in range(game.session.party.size()):
		if game.view._portrait_rect(index).grow(4).has_point(point): return normal
	if not game.battle.can_input(): return {"kind": "wait", "spell": -1, "blocked": false}
	var kind: String = "spell" if game.selected_spell >= 0 else str(game.battle_cursor_action)
	if kind.is_empty(): return normal
	var actor = game.battle.unit(game.battle.selected_id)
	if actor == null: return normal
	game.view._update_transform()
	var cell := Vector2i(((point - game.view.map_origin) / (16.0 * game.view.pixel_scale)).floor())
	var key := "%s:%s:%d:%d:%d:%d:%d:%d:%d" % [kind, cell, game.battle.tick_count, game.battle.turn_serial, game.battle.selected_id, game.selected_spell, actor.stats[Ids.Stat.MANA], actor.stats[Ids.Stat.ACTION_POINTS], game.session.location_id]
	if key == _resolve_key: return _resolved.duplicate()
	_resolve_key = key
	var blocked: bool = not game.battle.arena.has_point(cell)
	var path: Array = []
	if not blocked:
		match kind:
			"spell": blocked = not game.battle.cast_plan(actor, game.selected_spell, cell)["valid"]
			"attack", "shoot":
				var target = game.battle.actor_at(cell)
				blocked = target == null or target.side_id == actor.side_id
				if not blocked: blocked = not game.battle.attack_plan(actor, target)["valid"]
			"move":
				var plan: Dictionary = game.battle.preview(cell)
				blocked = not plan["affordable"] or plan["path"].is_empty()
				path = plan["path"]
	_resolved = {"kind": kind, "spell": game.selected_spell, "cell": cell, "blocked": blocked, "path": path}
	return _resolved.duplicate()

func _pixels(texture: Texture2D) -> Image:
	var pixels := texture.get_image()
	if pixels.is_compressed(): pixels.decompress()
	pixels.convert(Image.FORMAT_RGBA8)
	return pixels

func apply(state: Dictionary, icons) -> void:
	var kind: String = state.get("kind", "default")
	var spell: int = int(state.get("spell", -1))
	var blocked: bool = bool(state.get("blocked", false))
	var hd: bool = bool(icons.preferences.values["hd_icons"])
	var key := "%s:%d:%s:%s" % [kind, spell, blocked, hd]
	if applied_key == key: return
	if not _cache.has(key):
		var texture: Texture2D = assets.get(kind, assets.get("default"))
		var hotspot: Vector2 = hotspots.get(kind, hotspots.get("default", Vector2.ZERO))
		if texture == null: return
		if kind in ["move", "shoot", "spell"]:
			var image := Image.create(48, 48, false, Image.FORMAT_RGBA8)
			image.fill(Color.TRANSPARENT)
			var arrow: Image = _pixels(assets["default"])
			arrow.resize(24, 24, Image.INTERPOLATE_NEAREST)
			image.blend_rect(arrow, Rect2i(Vector2i.ZERO, arrow.get_size()), Vector2i.ZERO)
			var symbol: Image
			if kind == "spell": symbol = _pixels(icons.spell(spell))
			else:
				var atlas: Image = _pixels(icons.originals[188])
				symbol = atlas.get_region(Rect2i((1 if kind == "move" else 5) * 21, 0, 21, 20))
			var scale: float = minf(32.0 / symbol.get_width(), 32.0 / symbol.get_height())
			symbol.resize(maxi(1, roundi(symbol.get_width() * scale)), maxi(1, roundi(symbol.get_height() * scale)), Image.INTERPOLATE_NEAREST)
			image.blend_rect(symbol, Rect2i(Vector2i.ZERO, symbol.get_size()), Vector2i(14, 14))
			texture = ImageTexture.create_from_image(image)
			hotspot = (Vector2(hotspots["default"]) * 0.75).round()
		if blocked:
			var image: Image = _pixels(texture)
			var mark: Image = _pixels(assets["blocked"])
			mark.resize(14, 14, Image.INTERPOLATE_NEAREST)
			image.blend_rect(mark, Rect2i(Vector2i.ZERO, mark.get_size()), image.get_size() - Vector2i(14, 14))
			texture = ImageTexture.create_from_image(image)
		_cache[key] = {"texture": texture, "hotspot": hotspot}
	applied_key = key
	current_texture = _cache[key]["texture"]
	current_hotspot = _cache[key]["hotspot"]
	if DisplayServer.get_name() != "headless":
		Input.set_custom_mouse_cursor(current_texture, Input.CURSOR_ARROW, current_hotspot)

func shutdown() -> void:
	if DisplayServer.get_name() != "headless": Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	current_texture = null
	assets.clear()
	_cache.clear()
