extends Node
## Autoload "Settings": volumes (master, sfx, music) and fullscreen, saved to user://settings.cfg
## and applied at startup. Volumes are 0..10 steps (what the menu shows), turned into decibels on
## the audio bus. A missing or broken file just means defaults.

signal changed

const VOLUME_STEPS := 10
const BUSES := ["Master", "SFX", "Music"]

var path := "user://settings.cfg"
var volume := {"Master": 8, "SFX": 8, "Music": 7}
var fullscreen := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return  # first run, or unreadable: keep the defaults
	for bus: String in BUSES:
		var v: Variant = cfg.get_value("audio", bus, volume[bus])
		if v is int or v is float:
			volume[bus] = clampi(int(v), 0, VOLUME_STEPS)
	var f: Variant = cfg.get_value("display", "fullscreen", fullscreen)
	if f is bool:
		fullscreen = f


func save() -> void:
	var cfg := ConfigFile.new()
	for bus: String in BUSES:
		cfg.set_value("audio", bus, volume[bus])
	cfg.set_value("display", "fullscreen", fullscreen)
	var err := cfg.save(path)
	if err != OK:
		push_error("Settings: cannot save %s (%s)" % [path, error_string(err)])


func apply() -> void:
	for bus: String in BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var steps: int = volume[bus]
		AudioServer.set_bus_mute(i, steps == 0)
		# Perceived loudness is logarithmic: linear steps -> dB.
		AudioServer.set_bus_volume_db(i, linear_to_db(float(steps) / VOLUME_STEPS))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	changed.emit()


func set_volume(bus: String, steps: int) -> void:
	volume[bus] = clampi(steps, 0, VOLUME_STEPS)
	apply()
	save()


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply()
	save()
