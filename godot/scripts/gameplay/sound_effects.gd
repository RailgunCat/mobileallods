extends Node
## Bounded native WAV players. Selection uses its own counter, never game RNG.
signal played(clip: String)
const MAX_VOICES: int = 12
const SPELL_CLIPS = ["arrow", "heal", "lightning", "light", "slow", "freeze", "drain", "explosion", "poison", "firewall", "fireball", "stone", "haste", "bless", "pearth"]
const MONSTER_GROUPS = {4: "troll", 6: "orc", 7: "dragon", 9: "goblin", 10: "mage_skel", 12: "bat", 13: "skeleton", 14: "squirrel", 15: "turtle", 17: "troll"}
var preferences
var streams: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var paused: bool = false
var serial: int = 0
var _last: Dictionary = {}
var manifest: Dictionary = {}
const STEP_DISTANCE: float = 20.0
var _walk_distance: Dictionary[int, float] = {}
var _walk_phase: Dictionary[int, int] = {}

func configure(settings) -> void:
	preferences = settings
	var file: String = "res://data/hd/audio/sfx/manifest.json"
	if FileAccess.file_exists(file):
		manifest = JSON.parse_string(FileAccess.get_file_as_string(file))
		for clip: String in manifest.get("clips", {}):
			var stream := load("res://data/hd/audio/sfx/" + clip) as AudioStreamWAV
			if stream != null: streams[clip] = stream
	for index in range(MAX_VOICES):
		var voice := AudioStreamPlayer.new()
		voice.bus = &"SFX"
		add_child(voice)
		voices.append(voice)
	preferences.changed.connect(_apply_settings)
	_apply_settings("")

func _apply_settings(_key: String) -> void:
	for voice in voices: voice.volume_linear = float(preferences.values["sfx_volume"]) / 100.0 * float(voice.get_meta("gain", 1.0))
	if not preferences.values["sfx_enabled"]: stop_all()

func play_clip(clip: String, world: bool = true, gain: float = 1.0) -> bool:
	if not preferences.values["sfx_enabled"] or int(preferences.values["sfx_volume"]) == 0 or not streams.has(clip): return false
	var now: int = Time.get_ticks_msec()
	if now - int(_last.get(clip, -1000)) < 45: return false
	for voice in voices:
		if voice.playing: continue
		voice.stream = streams[clip]
		voice.set_meta("world", world)
		voice.set_meta("gain", clampf(gain, 0, 1))
		voice.volume_linear = float(preferences.values["sfx_volume"]) / 100.0 * clampf(gain, 0, 1)
		voice.play()
		voice.stream_paused = paused and world
		_last[clip] = now
		played.emit(clip)
		return true
	return false

func variants(prefix: String, world: bool = true) -> void:
	var matches: Array[String] = []
	for clip: String in streams:
		if not clip.begins_with(prefix): continue
		var suffix: String = clip.substr(prefix.length())
		if suffix.begins_with(".") or (not suffix.is_empty() and suffix.substr(0, 1).is_valid_int()): matches.append(clip)
	if matches.is_empty(): return
	matches.sort()
	serial += 1
	play_clip(matches[serial % matches.size()], world)

func walk(actor_id: int, distance: float, dungeon: bool) -> void:
	if distance <= 0 or not is_finite(distance) or distance > 16 or paused or not preferences.values["sfx_enabled"] or int(preferences.values["sfx_volume"]) == 0: return
	var travelled: float = float(_walk_distance.get(actor_id, 0.0)) + distance
	if travelled >= STEP_DISTANCE:
		travelled = fmod(travelled, STEP_DISTANCE)
		var surface: String = "dungeon" if dungeon else "surface"
		var clips: Array = manifest.get("footsteps", {}).get(surface, [])
		if not clips.is_empty():
			var phase: int = int(_walk_phase.get(actor_id, 0))
			play_clip(str(clips[phase % clips.size()]), true, 0.6)
			_walk_phase[actor_id] = phase + 1
	_walk_distance[actor_id] = travelled

func spell_impact(spell: int) -> void:
	if spell >= 0 and spell < SPELL_CLIPS.size(): play_clip("magic/%s.wav" % SPELL_CLIPS[spell])

func combat(event: Dictionary, battle) -> void:
	var kind: String = str(event["event"])
	var actor = battle.unit(int(event.get("actor", -1)))
	match kind:
		"walked":
			if actor != null and actor.unit_type in [0, 1, 2, 3, 5, 8, 11, 16]: walk(actor.instance_id, float(event["distance"]), bool(event["dungeon"]))
		"attack_released":
			var clip: String = "bow" if event.get("ranged", false) else "sword"
			if actor != null and actor.unit_type not in [0, 1, 2, 3, 5, 8, 11, 16]:
				var group: String = MONSTER_GROUPS.get(actor.unit_type, "")
				if not group.is_empty():
					variants("monsters/" + group + "/attack")
					return
			play_clip("units/" + clip + ".wav")
		"hit":
			if int(event.get("spell", -1)) >= 0: return
			variants("units/metal" if event.get("blocked", false) else "units/soft")
			if int(event.get("damage", 0)) > 0:
				var target = battle.unit(int(event.get("target", -1)))
				var group: String = MONSTER_GROUPS.get(target.unit_type, "") if target != null else ""
				if group.is_empty(): variants("units/easyf" if target != null and target.unit_type == 1 else "units/easy")
				else: variants("monsters/" + group + "/easy")
		"death":
			var group: String = MONSTER_GROUPS.get(actor.unit_type, "") if actor != null else ""
			if group.is_empty(): variants("units/deadf" if actor != null and actor.unit_type == 1 else "units/dead")
			else: variants("monsters/" + group + "/dead")
		"victory": play_clip("mcomplet.wav")
		"defeat": play_clip("mfailed.wav")

func pause_world(value: bool) -> void:
	if paused == value: return
	paused = value
	for voice in voices:
		if voice.get_meta("world", false): voice.stream_paused = paused

func stop_all() -> void:
	for voice in voices:
		voice.stop()
		voice.stream_paused = false
		voice.stream = null
	_last.clear()
	_walk_distance.clear()
	_walk_phase.clear()

func shutdown() -> void:
	stop_all()
	streams.clear()
	if preferences != null and preferences.changed.is_connected(_apply_settings): preferences.changed.disconnect(_apply_settings)
	preferences = null
