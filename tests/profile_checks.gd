extends SceneTree
## The Profile (what survives between runs): defaults, round trip, bad files, records.
## Uses its own file, never the player's profile.
##   godot --headless --path . -s res://tests/profile_checks.gd   -> "PROFILE pass" or FAILs

const TEST_PATH := "user://test_profile.json"

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var p: Node = root.get_node("Profile")
	p.path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	p.load_profile()
	_check(p.data == p.defaults(), "no file: defaults")

	# Records.
	_check(p.add_gem("GemA") and not p.add_gem("GemA") and p.has_gem("GemA"), "a gem is new once, then known")
	_check(p.record_height(40.0) and not p.record_height(30.0) and p.data.best_height_m == 40.0, "height keeps the best")
	_check(p.record_split(2, 50.0) == 0.0, "first split: no delta")
	_check(is_equal_approx(p.record_split(2, 45.0), -5.0) and p.best_split(2) == 45.0, "faster split: negative delta, new best")
	_check(is_equal_approx(p.record_split(2, 47.0), 2.0) and p.best_split(2) == 45.0, "slower split: positive delta, best kept")
	_check(p.record_finish(120.0, 3) and not p.record_finish(130.0, 1), "finish: only a faster time is a best")
	_check(p.data.runs == 2 and p.data.best_time == 120.0 and p.data.best_streak == 3, "runs counted, best time and streak kept")

	# Round trip through the file.
	p.load_profile()
	_check(p.has_gem("GemA") and p.data.best_time == 120.0 and p.best_split(2) == 45.0 and p.data.runs == 2,
		"saved and loaded back (runs %s, best %s)" % [p.data.runs, p.data.best_time])
	_check(not FileAccess.file_exists(TEST_PATH + ".tmp"), "the temp file was renamed into place")

	# Bad files can't crash it or poison it.
	_write(TEST_PATH, "{ not json")
	p.load_profile()
	_check(p.data == p.defaults(), "garbage file: defaults")
	_write(TEST_PATH, JSON.stringify({"runs": "lots", "best_time": 99.5, "gems": ["GemB", 7, null], "best_splits": []}))
	p.load_profile()
	_check(p.data.runs == 0 and p.data.best_time == 99.5 and p.data.gems == ["GemB"] and p.data.best_splits == {},
		"wrong types dropped field by field, good ones kept: %s" % p.data)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	print("PROFILE pass" if _fails == 0 else "PROFILE fail (%d)" % _fails)
	quit(1 if _fails else 0)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what)
