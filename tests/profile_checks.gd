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
	p.mode = "flags"
	_check(p.record_height(40.0) and not p.record_height(30.0) and p.bests().best_height_m == 40.0, "height keeps the best")
	_check(p.record_split(2, 50.0) == 0.0, "first split: no delta")
	_check(is_equal_approx(p.record_split(2, 45.0), -5.0) and p.best_split(2) == 45.0, "faster split: negative delta, new best")
	_check(is_equal_approx(p.record_split(2, 47.0), 2.0) and p.best_split(2) == 45.0, "slower split: positive delta, best kept")
	_check(p.record_finish(120.0, 3) and not p.record_finish(130.0, 1), "finish: only a faster time is a best")
	_check(p.data.runs == 2 and p.bests().best_time == 120.0 and p.data.best_streak == 3, "runs counted, best time and streak kept")

	# Modes keep separate bests; gems, runs and streak are shared.
	p.mode = "noflag"
	_check(p.bests().best_time < 0.0 and p.best_split(2) < 0.0, "a no-flag climb starts with no bests")
	_check(p.record_finish(300.0, 1) and p.bests("flags").best_time == 120.0 and p.bests("noflag").best_time == 300.0,
		"a no-flag finish never touches the flagged best")
	_check(p.has_gem("GemA") and p.data.runs == 3, "gems and runs are shared across modes")
	p.mode = "flags"

	# Round trip through the file.
	p.load_profile()
	_check(p.has_gem("GemA") and p.bests("flags").best_time == 120.0 and p.best_split(2) == 45.0 and p.data.runs == 3
		and p.bests("noflag").best_time == 300.0, "saved and loaded back, both modes (runs %s)" % p.data.runs)
	_check(not FileAccess.file_exists(TEST_PATH + ".tmp"), "the temp file was renamed into place")

	# Bad files can't crash it or poison it.
	_write(TEST_PATH, "{ not json")
	p.load_profile()
	_check(p.data == p.defaults(), "garbage file: defaults")
	# A v1 file (one set of bests, from before modes) becomes the flagged bests; wrong types dropped.
	_write(TEST_PATH, JSON.stringify({"version": 1, "runs": "lots", "best_time": 99.5, "best_height_m": 80,
		"gems": ["GemB", 7, null], "best_splits": []}))
	p.load_profile()
	_check(p.data.runs == 0 and p.bests("flags").best_time == 99.5 and p.bests("flags").best_height_m == 80.0
		and p.data.gems == ["GemB"] and p.bests("flags").best_splits == {} and p.bests("noflag").best_time < 0.0,
		"v1 file migrated into flags, wrong types dropped field by field: %s" % p.data)
	_write(TEST_PATH, JSON.stringify({"last_mode": "sideways"}))
	p.load_profile()
	_check(p.data.last_mode == "flags", "an unknown mode falls back to flags")

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
