extends RefCounted
## Original image/spell IDs map to independent HD resources; legacy data stays intact.
const Ids = preload("res://scripts/gameplay/game_ids.gd")
var preferences
var originals: Dictionary
var portraits: Dictionary = {}
var spells: Dictionary = {}
var revision: int = 0

func configure(settings, textures: Dictionary) -> void:
	preferences = settings
	originals = textures
	var file: String = "res://data/hd/icons/manifest.json"
	if FileAccess.file_exists(file):
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file))
		for group: String in ["portraits", "spells"]:
			var target: Dictionary = portraits if group == "portraits" else spells
			for id: String in manifest[group]:
				var path: String = manifest[group][id]
				if ResourceLoader.exists(path): target[int(id)] = load(path) as Texture2D
	preferences.changed.connect(_settings_changed)

func _settings_changed(key: String) -> void:
	if key in ["", "hd_icons"]: revision += 1

func shutdown() -> void:
	if preferences != null and preferences.changed.is_connected(_settings_changed): preferences.changed.disconnect(_settings_changed)
	preferences = null
	originals = {}
	portraits.clear()
	spells.clear()

static func fit_rect(texture: Texture2D, bounds: Rect2) -> Rect2:
	if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0: return bounds
	var scale: float = minf(bounds.size.x / texture.get_width(), bounds.size.y / texture.get_height())
	var size: Vector2 = texture.get_size() * scale
	return Rect2(bounds.position + (bounds.size - size) * 0.5, size)

func portrait(id: int) -> Texture2D:
	return portraits[id] if preferences.values["hd_icons"] and portraits.has(id) else originals.get(id)

func actor_portrait(unit_type: int, definitions: Dictionary) -> Texture2D:
	var dialogue_id: int = int(definitions["portrait_images"][unit_type])
	if not preferences.values["hd_icons"] or unit_type in Ids.HERO_TYPES:
		return portrait(dialogue_id)
	# Many original dialogue IDs are shared by unrelated creatures (e.g. 23).
	# The unit portrait table preserves their actual species and appearance.
	var unit_id: int = int(definitions["unit_portrait_images"][unit_type])
	return portraits.get(unit_id, originals.get(unit_id, originals.get(dialogue_id)))

func spell(frame: int) -> Texture2D:
	if preferences.values["hd_icons"] and spells.has(frame): return spells[frame]
	var texture := AtlasTexture.new()
	texture.atlas = originals[189]
	texture.region = Rect2(frame * 21, 0, 21, 20)
	return texture
