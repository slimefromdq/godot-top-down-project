extends RefCounted
class_name UserSettings

# The player's settings (volumes, fullscreen), saved to user://settings.cfg
# and applied at startup by GameState. The settings screen edits them.

const PATH := "user://settings.cfg"
const BUSES := {&"master": &"Master", &"music": &"Music", &"sfx": &"SFX"}

static var volumes := {&"master": 1.0, &"music": 1.0, &"sfx": 1.0}
static var fullscreen := true


static func load_and_apply() -> void:
	var file := ConfigFile.new()
	if file.load(PATH) == OK:
		for key in volumes:
			volumes[key] = clampf(float(file.get_value("audio", str(key), 1.0)), 0.0, 1.0)
		fullscreen = bool(file.get_value("video", "fullscreen", fullscreen))
	else:
		fullscreen = DisplayServer.window_get_mode() >= DisplayServer.WINDOW_MODE_FULLSCREEN
	apply()


static func apply() -> void:
	for key in volumes:
		set_volume(key, volumes[key])
	set_fullscreen(fullscreen)


static func set_volume(key: StringName, linear: float) -> void:
	volumes[key] = clampf(linear, 0.0, 1.0)
	var bus := AudioServer.get_bus_index(BUSES[key])
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volumes[key], 0.0001)))
		AudioServer.set_bus_mute(bus, volumes[key] <= 0.0)


static func set_fullscreen(on: bool) -> void:
	fullscreen = on
	if DisplayServer.get_name() == "headless":
		return
	var is_full := DisplayServer.window_get_mode() >= DisplayServer.WINDOW_MODE_FULLSCREEN
	if on and not is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not on and is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


static func save() -> void:
	var file := ConfigFile.new()
	for key in volumes:
		file.set_value("audio", str(key), volumes[key])
	file.set_value("video", "fullscreen", fullscreen)
	file.save(PATH)
