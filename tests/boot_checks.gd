extends SceneTree
## Boot checks (headless): the main scene loads, Steve's animations match the Aseprite tags,
## the input map is complete, and the F12 report can describe the game.
##   godot --headless --path . -s res://tests/boot_checks.gd      -> prints "BOOT pass" or FAILs

## tag -> frame count, from art/source/stickysteve.aseprite. Change both together.
const STEVE := {
	"idle": 5, "jump_charge_1": 3, "jump_charge_2": 3, "jump_charge_3": 3,
	"jump": 4, "jump_stop": 4, "fall": 6, "land": 4, "walk_right": 3,
}
const ONE_SHOT := ["jump", "jump_stop", "land"]
const PLANT := {"raise_pole": 3, "spin_pole": 5, "plant_pole": 2}
const PLANT_ONE_SHOT := ["raise_pole", "plant_pole"]
const HAND_JSON := "res://art/flag/plant_flag_hand.json"
const INK := Color("08141e")  ## Steve's outline/limb colour: every hand point must be on it
const ACTIONS := ["move_left", "move_right", "jump", "pause", "toggle_fullscreen", "debug_report", "plant_flag", "respawn"]

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var frames := load("res://art/steve/steve_frames.tres") as SpriteFrames
	_check(frames != null, "steve_frames.tres loads")
	if frames:
		for anim: String in STEVE:
			_check(frames.has_animation(anim), "animation %s exists" % anim)
			if frames.has_animation(anim):
				_check(frames.get_frame_count(anim) == STEVE[anim], "%s has %d frames" % [anim, STEVE[anim]])
				_check(frames.get_animation_loop(anim) == not (anim in ONE_SHOT), "%s loop flag" % anim)
				_check(frames.get_frame_texture(anim, 0) != null, "%s texture imported" % anim)

	_check_plant_flag()

	for a: String in ACTIONS:
		_check(InputMap.has_action(a) and not InputMap.action_get_events(a).is_empty(), "input %s bound" % a)

	var packed := load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene
	_check(packed != null, "main scene loads")
	if packed:
		change_scene_to_packed(packed)
		await process_frame
		await process_frame
		_check(get_first_node_in_group("player") != null, "main scene has a player")
		var debug := root.get_node_or_null("Debug")
		_check(debug != null, "Debug autoload present")
		if debug:
			var info: Dictionary = debug.report_info()
			for k in ["commit", "godot", "scene", "player"]:
				_check(info.has(k), "report info has %s" % k)

	print("BOOT pass" if _fails == 0 else "BOOT fail (%d)" % _fails)
	quit(1 if _fails else 0)


## The planting animations, and the hand-picked points the pole attaches to: one per frame, each
## on a limb pixel of that exact frame, so a redrawn frame fails here instead of in a playtest.
func _check_plant_flag() -> void:
	var frames := load("res://art/flag/plant_flag_frames.tres") as SpriteFrames
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(HAND_JSON))
	_check(frames != null, "plant_flag_frames.tres loads")
	_check(data is Dictionary and data.has("hand"), "%s parses" % HAND_JSON)
	if frames == null or not data is Dictionary:
		return
	for anim: String in PLANT:
		_check(frames.has_animation(anim) and frames.get_frame_count(anim) == PLANT[anim], "plant_flag %s has %d frames" % [anim, PLANT[anim]])
		if not frames.has_animation(anim):
			continue
		_check(frames.get_animation_loop(anim) == not (anim in PLANT_ONE_SHOT), "plant_flag %s loop flag" % anim)
		var points: Array = data["hand"].get(anim, [])
		_check(points.size() == frames.get_frame_count(anim), "hand points for every %s frame" % anim)
		for i in mini(points.size(), frames.get_frame_count(anim)):
			var tex := frames.get_frame_texture(anim, i) as AtlasTexture
			var img := tex.atlas.get_image() if tex else null
			if img == null:
				_check(false, "%s frame %d image" % [anim, i])
				continue
			if img.is_compressed():
				img.decompress()
			var p := Vector2i(tex.region.position) + Vector2i(int(points[i][0]), int(points[i][1]))
			var c := img.get_pixelv(p)
			_check(c.a > 0.0 and c.is_equal_approx(INK), "%s frame %d hand (%d,%d) is on Steve's arm" % [anim, i, points[i][0], points[i][1]])


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what)
