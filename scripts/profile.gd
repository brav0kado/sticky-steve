extends Node
## Autoload "Profile": what survives between runs: best time, best height, best streak, best split
## per zone, every gem ever found, run count. This is the progress layer: each run is measured
## against the player's own past, which is what makes "one more go" pull.
##
## Saved as JSON at `path` (tests point it elsewhere). Loading validates every field and falls back
## to defaults, so a hand-edited or old file can't crash the game. Writes go to a temp file first,
## then rename, so a crash mid-save can't corrupt the profile.

const VERSION := 1

var path := "user://profile.json"
var data := {}


func _ready() -> void:
	load_profile()


func defaults() -> Dictionary:
	return {"version": VERSION, "runs": 0, "best_time": -1.0, "best_height_m": 0.0,
		"best_streak": 0, "gems": [], "best_splits": {}}


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
	for key: String in data:
		var v: Variant = parsed.get(key)
		if v != null and typeof(v) == typeof(data[key]):
			data[key] = v
		elif v is float and data[key] is int:
			data[key] = int(v)  # JSON numbers come back as floats
	data.gems = data.gems.filter(func(g: Variant) -> bool: return g is String)


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


func has_gem(id: String) -> bool:
	return id in data.gems


## Returns true if this gem is new to the profile.
func add_gem(id: String) -> bool:
	if has_gem(id):
		return false
	data.gems.append(id)
	return true


## Records a height; returns true if it's a new best.
func record_height(m: float) -> bool:
	if m <= data.best_height_m:
		return false
	data.best_height_m = m
	return true


## Records a zone split (seconds from run start); returns the delta to the old best (0 if none).
func record_split(zone: int, t: float) -> float:
	var key := str(zone)
	var best: float = data.best_splits.get(key, -1.0)
	if best < 0.0 or t < best:
		data.best_splits[key] = t
	return 0.0 if best < 0.0 else t - best


func best_split(zone: int) -> float:
	return data.best_splits.get(str(zone), -1.0)


## Records a finished run; returns true if the time is a new best.
func record_finish(t: float, streak: int) -> bool:
	data.runs += 1
	data.best_streak = maxi(data.best_streak, streak)
	var best: bool = data.best_time < 0.0 or t < data.best_time
	if best:
		data.best_time = t
	save()
	return best
