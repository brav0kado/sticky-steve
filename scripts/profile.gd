extends Node
## Autoload "Profile": what survives between runs. This is the progress layer: each run is measured
## against the player's own past, which is what makes "one more go" pull.
##
## Shared across modes: runs, best streak, every gem ever found, the last mode picked.
## Per mode ("flags", "noflag"), each with its own bests: best time, best height, best split per
## zone. A no-flag climb is a different challenge, so it never competes with a flagged one.
## `mode` is the current run's mode (set by the title's mode picker); every record_* writes to it.
##
## Saved as JSON at `path` (tests point it elsewhere). Loading validates every field and falls back
## to defaults, so a hand-edited or old file can't crash the game; a v1 file (one set of bests)
## becomes the "flags" bests. Writes go to a temp file then rename: a crash can't corrupt it.

const VERSION := 2
const MODES := ["flags", "noflag"]

var path := "user://profile.json"
var data := {}
var mode := "flags"  ## this run's mode (not saved; data.last_mode is)


func _ready() -> void:
	load_profile()
	mode = data.last_mode


func defaults() -> Dictionary:
	var modes := {}
	for m: String in MODES:
		modes[m] = _mode_defaults()
	return {"version": VERSION, "runs": 0, "best_streak": 0, "gems": [], "last_mode": "flags", "modes": modes}


func _mode_defaults() -> Dictionary:
	return {"best_time": -1.0, "best_height_m": 0.0, "best_splits": {}}


func load_profile() -> void:
	data = defaults()
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()  # parse() reports by return value; parse_string() also logs an engine ERROR
	var ok := json.parse(FileAccess.get_file_as_string(path)) == OK
	var parsed: Variant = json.data if ok else null
	if not parsed is Dictionary:
		push_warning("Profile: %s is not valid JSON; starting fresh" % path)
		return
	_merge(data, parsed, ["runs", "best_streak", "gems", "last_mode"])
	data.gems = data.gems.filter(func(g: Variant) -> bool: return g is String)
	if data.last_mode not in MODES:
		data.last_mode = "flags"
	var saved_modes: Variant = parsed.get("modes")
	if saved_modes is Dictionary:
		for m: String in MODES:
			if saved_modes.get(m) is Dictionary:
				_merge(data.modes[m], saved_modes[m], ["best_time", "best_height_m", "best_splits"])
	elif parsed.has("best_time"):
		# v1: one set of bests, from before modes existed: they were flagged climbs.
		_merge(data.modes.flags, parsed, ["best_time", "best_height_m", "best_splits"])


## Copies each key from `src` that has the same type as the default (JSON floats -> ints allowed).
func _merge(dst: Dictionary, src: Dictionary, keys: Array) -> void:
	for key: String in keys:
		var v: Variant = src.get(key)
		if v != null and typeof(v) == typeof(dst[key]):
			dst[key] = v
		elif v is float and dst[key] is int:
			dst[key] = int(v)


func save() -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Profile: cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("Profile: cannot replace %s (%s)" % [path, error_string(err)])


## Wipe all progress (title screen, after a second press).
func reset() -> void:
	data = defaults()
	save()


func set_mode(m: String) -> void:
	mode = m if m in MODES else "flags"
	data.last_mode = mode
	save()


## A mode's bests (this run's mode by default).
func bests(m := "") -> Dictionary:
	return data.modes[m if m != "" else mode]


func has_gem(id: String) -> bool:
	return id in data.gems


## Returns true if this gem is new to the profile.
func add_gem(id: String) -> bool:
	if has_gem(id):
		return false
	data.gems.append(id)
	return true


## Records a height; returns true if it's a new best (for this mode).
func record_height(m: float) -> bool:
	if m <= bests().best_height_m:
		return false
	bests().best_height_m = m
	return true


## Records a zone split (seconds from run start); returns the delta to the old best (0 if none).
func record_split(zone: int, t: float) -> float:
	var key := str(zone)
	var splits: Dictionary = bests().best_splits
	var best: float = splits.get(key, -1.0)
	if best < 0.0 or t < best:
		splits[key] = t
	return 0.0 if best < 0.0 else t - best


func best_split(zone: int) -> float:
	return bests().best_splits.get(str(zone), -1.0)


## Records a finished run; returns true if the time is a new best (for this mode).
func record_finish(t: float, streak: int) -> bool:
	data.runs += 1
	data.best_streak = maxi(data.best_streak, streak)
	var b := bests()
	var best: bool = b.best_time < 0.0 or t < b.best_time
	if best:
		b.best_time = t
	save()
	return best
