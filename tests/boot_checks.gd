extends SceneTree
## Boot checks (headless): the main scene loads, Steve's animations match the Aseprite tags,
## the input map is complete, and the F12 report can describe the game.
##   godot --headless --path . -s res://tests/boot_checks.gd      -> prints "BOOT pass" or FAILs

## tag -> frame count, from art/source/stickysteve.aseprite. Change both together.
const STEVE := {
	"idle": 5, "jump_charge_1": 3, "jump_charge_2": 3, "jump_charge_3": 3,
	"jump": 4, "jump_stop": 4, "fall": 6, "land": 4,
}
const ONE_SHOT := ["jump", "jump_stop", "land"]
const ACTIONS := ["move_left", "move_right", "jump", "pause", "toggle_fullscreen", "debug_report"]

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


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what)
