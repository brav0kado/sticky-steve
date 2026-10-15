extends Node
## Autoload "Debug": the playtest loop's in-game half.
##
## F12 (works anywhere, even paused) writes user://reports/<time>/ with screenshot.png, log.txt
## (tail of the Godot log) and info.json (commit, renderer, scene, Steve's state).
## tools/send-report.sh copies the newest one to julia. F11 toggles fullscreen.
##
## Steve's state comes from the first node in group "player": its position, plus whatever its
## optional debug_state() -> Dictionary returns (velocity, charge, on_floor...), so the report
## grows with the player script without touching this file.

const REPORTS_DIR := "user://reports"
const REPORT_LOG_LINES := 200
const TOAST_SECONDS := 2.5

var _toast: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # F12 must work while paused / in menus
	var layer := CanvasLayer.new()
	layer.layer = 100  # above any game UI
	add_child(layer)
	_toast = Label.new()
	_toast.position = Vector2(8, 36)  # under the HUD's timer line, not on top of it
	_toast.add_theme_color_override("font_color", Nyx8.CREAM)
	_toast.add_theme_color_override("font_outline_color", Nyx8.INK)
	_toast.add_theme_constant_override("outline_size", 4)
	_toast.hide()
	layer.add_child(_toast)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		Settings.set_fullscreen(not Settings.fullscreen)  # remembered, and the settings menu follows
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_report"):
		get_viewport().set_input_as_handled()
		write_report()


## Saves a report folder and returns its absolute path ("" on failure).
func write_report() -> String:
	await RenderingServer.frame_post_draw  # the frame with the bug, not a half-drawn one
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var dir := "%s/%s" % [REPORTS_DIR, stamp]
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		push_error("Debug: cannot create %s (%s)" % [dir, error_string(err)])
		return ""
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(dir + "/screenshot.png")
	_write_text(dir + "/log.txt", _log_tail(REPORT_LOG_LINES))
	_write_text(dir + "/info.json", JSON.stringify(report_info(), "\t"))
	var abs_dir := ProjectSettings.globalize_path(dir)
	print("Debug: bug report saved to ", abs_dir)
	_show_toast("Bug report saved (F12)\nSend it: tools/send-report.sh")
	return abs_dir


func report_info() -> Dictionary:
	var info := {
		"time": Time.get_datetime_string_from_system(),
		"commit": _git_commit(),
		"godot": Engine.get_version_info().string,
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"renderer": "%s / %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name()],
		"gpu": RenderingServer.get_video_adapter_name(),
		"window": DisplayServer.window_get_size(),
		"fps": Engine.get_frames_per_second(),
		"paused": get_tree().paused,
		"scene": get_tree().current_scene.scene_file_path if get_tree().current_scene else "",
	}
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player:
		info["player"] = [player.global_position.x, player.global_position.y]
		if player.has_method("debug_state"):
			info["player_state"] = player.debug_state()
	return info


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.show()
	await get_tree().create_timer(TOAST_SECONDS, true, false, true).timeout
	_toast.hide()


## HEAD's commit, so a report says which build Martin was running. Reads .git directly: the
## game can't run git, and exported builds have no .git ("unknown").
func _git_commit() -> String:
	var git := ProjectSettings.globalize_path("res://.git/")
	if not FileAccess.file_exists(git + "HEAD"):
		return "unknown"
	var head := FileAccess.get_file_as_string(git + "HEAD").strip_edges()
	if not head.begins_with("ref: "):
		return head  # detached HEAD is the hash itself
	var ref := head.substr(5)
	if FileAccess.file_exists(git + ref):
		return FileAccess.get_file_as_string(git + ref).strip_edges()
	# After `git gc` the branch tip lives in packed-refs as "<hash> <ref>".
	if FileAccess.file_exists(git + "packed-refs"):
		for line in FileAccess.get_file_as_string(git + "packed-refs").split("\n"):
			if line.ends_with(" " + ref):
				return line.get_slice(" ", 0)
	return ref


func _log_tail(n: int) -> String:
	var path := str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))
	if not FileAccess.file_exists(path):
		return "(no log file at %s: file logging off?)" % path
	var lines := FileAccess.get_file_as_string(path).split("\n")
	return "\n".join(lines.slice(maxi(0, lines.size() - n)))


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Debug: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(text)
	f.close()
