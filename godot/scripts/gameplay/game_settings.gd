extends RefCounted
## User preferences are independent of campaign saves.
signal changed(key: String)
const FPS_LIMITS = [0, 30, 60, 75, 90, 120, 144, 165, 240, 360]
const DEFAULTS = {"music_enabled": true, "music_volume": 32, "sfx_enabled": true, "sfx_volume": 65, "hd_icons": false, "crt_enabled": false, "vsync_enabled": true, "fps_limit": 0}
var path: String = "user://settings.cfg"
var values: Dictionary = DEFAULTS.duplicate()

func load_settings() -> void:
	values = DEFAULTS.duplicate()
	var config := ConfigFile.new()
	if config.load(path) != OK: return
	for key: String in DEFAULTS:
		values[key] = _validated(key, config.get_value(_section(key), key, DEFAULTS[key]))
	changed.emit("")

func _section(key: String) -> String:
	return "graphics" if key in ["hd_icons", "crt_enabled", "vsync_enabled", "fps_limit"] else "audio"

func _validated(key: String, value):
	if key == "fps_limit":
		return value if value is int and value in FPS_LIMITS else DEFAULTS[key]
	if key.ends_with("_volume"):
		if (value is int or value is float) and is_finite(float(value)): return clampi(roundi(value), 0, 100)
		return DEFAULTS[key]
	return value if value is bool else DEFAULTS[key]

func update(key: String, value, persist: bool = true) -> Error:
	if not DEFAULTS.has(key): return ERR_INVALID_PARAMETER
	values[key] = _validated(key, value)
	changed.emit(key)
	if not persist: return OK
	var config := ConfigFile.new()
	config.load(path)
	for name: String in DEFAULTS: config.set_value(_section(name), name, values[name])
	return config.save(path)

func apply_display() -> void:
	Engine.max_fps = int(values["fps_limit"])
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values["vsync_enabled"] else DisplayServer.VSYNC_DISABLED)
