extends Node
## Native playback of offline renders of the two original MIDI resources.
const Settings = preload("res://scripts/gameplay/game_settings.gd")
var preferences
var enabled: bool = true
var settings_path: String:
	get: return preferences.path if preferences != null else "user://settings.cfg"
	set(value):
		if preferences != null: preferences.path = value
var available: bool = false
var error: String = ""
var current_track: int = -1
var player: AudioStreamPlayer
var streams: Array[AudioStreamOggVorbis] = []

func configure(settings = null) -> void:
	preferences = settings if settings != null else Settings.new()
	if settings == null: preferences.load_settings()
	player = AudioStreamPlayer.new()
	player.bus = &"Music"
	add_child(player)
	preferences.changed.connect(_apply_settings)
	for name: String in ["bgsound", "bgsound1"]:
		var path: String = "res://data/audio/%s.ogg" % name
		var stream := AudioStreamOggVorbis.load_from_file(path)
		if stream == null:
			error = "Не удалось прочитать музыкальную композицию."
			return
		stream.loop = true
		streams.append(stream)
	available = streams.size() == 2
	_apply_settings("")

func _apply_settings(_key: String) -> void:
	enabled = bool(preferences.values["music_enabled"])
	player.volume_linear = float(preferences.values["music_volume"]) / 100.0
	if not enabled: player.stop()
	elif available and current_track >= 0 and not player.playing: player.play()

func play_track(index: int) -> void:
	if not available or index < 0 or index >= streams.size(): return
	if current_track != index:
		current_track = index
		player.stream = streams[index]
		if enabled: player.play()
	elif enabled and not player.playing: player.play()

func set_enabled(value: bool, persist: bool = true) -> Error:
	return preferences.update("music_enabled", value, persist)

func shutdown() -> void:
	if preferences != null and preferences.changed.is_connected(_apply_settings): preferences.changed.disconnect(_apply_settings)
	preferences = null
	if player != null:
		player.stop()
		player.stream = null
	streams.clear()
	available = false
