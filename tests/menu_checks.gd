extends SceneTree
## Menus: title flow, reset needing two presses, settings persisting and applying to the buses,
## pause freezing the game and resuming, the plant-refused message, and every menu control
## fitting on the 640x360 screen. Uses its own profile/settings files.
##   godot --headless --path . -s res://tests/menu_checks.gd   -> "MENU pass" or FAILs

const VIEW := Rect2(0, 0, 640, 360)

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var prof: Node = root.get_node("Profile")
	var settings: Node = root.get_node("Settings")
	prof.path = "user://test_menu_profile.json"
	settings.path = "user://test_menu_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings.path))
	prof.data = prof.defaults()
	prof.data.best_time = 99.0
	prof.data.runs = 1
	prof.add_gem("GemA")
	prof.save()

	# Title: boots with Climb focused, shows the bests, fits the screen.
	change_scene_to_file("res://scenes/title.tscn")
	await _frames(3)
	var title := current_scene
	var climb := _button(title, "Climb")
	_check(climb != null and climb.has_focus(), "title: Climb has focus (keyboard/pad ready)")
	_check(_text_in(title, "best 1:39.0"), "title shows the best time")
	_check_fits(title, "title")

	# Reset needs two presses.
	var reset := _button(title, "Reset progress")
	reset.pressed.emit()
	await _frames(1)
	_check(prof.data.runs == 1 and reset.text == "Press again to erase", "reset: first press only arms it")
	reset.pressed.emit()
	await _frames(1)
	_check(prof.data.runs == 0 and prof.data.gems.is_empty(), "reset: second press erases the profile")
	prof.load_profile()
	_check(prof.data.runs == 0, "reset: erased on disk too")

	# Settings: open, step a volume down with ui_left, it applies to the bus and persists.
	_button(title, "Settings").pressed.emit()
	await _frames(2)
	var panel := title.find_children("*", "PanelContainer", true, false)[0] as Control
	_check(panel.visible, "settings opens")
	_check_fits(title, "settings")
	var sfx_row := _button_prefix(panel, "Sound effects")
	var before: int = settings.volume["SFX"]
	sfx_row.grab_focus()
	var left := InputEventAction.new()
	left.action = "ui_left"
	left.pressed = true
	sfx_row.gui_input.emit(left)
	await _frames(1)
	_check(settings.volume["SFX"] == before - 1, "left on a volume row turns it down (%d -> %d)" % [before, settings.volume["SFX"]])
	var bus := AudioServer.get_bus_index("SFX")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db((before - 1) / 10.0)), "the SFX bus volume follows")
	settings.volume["SFX"] = 3
	settings.load_settings()
	_check(settings.volume["SFX"] == before - 1, "volume persisted to settings.cfg")
	_button(panel, "Back").pressed.emit()
	await _frames(1)
	_check(not panel.visible and _button(title, "Settings").has_focus(), "Back returns to the menu with focus")

	# Climb starts the game; Esc pauses (tree paused, menu up), Resume unpauses.
	climb.pressed.emit()
	await _frames(4)
	_check(current_scene.scene_file_path == "res://scenes/main.tscn", "Climb starts the climb")
	var game := current_scene
	var pause := game.get_node("Pause")
	_press("pause")
	await _frames(2)
	_check(paused and pause.is_open(), "Esc pauses the game and opens the menu")
	_check_fits(game, "pause menu")
	_check(_button(pause, "Resume").has_focus(), "pause: Resume has focus")
	var steve: Node2D = game.get_node("Steve")
	var hud: Node = game.get_node("HUD")
	var t0: float = hud.elapsed
	await _frames(10)
	_check(hud.elapsed == t0, "the timer stops while paused")
	_button(pause, "Resume").pressed.emit()
	await _frames(2)
	_check(not paused and not pause.is_open(), "Resume unpauses")

	# F during the flag cooldown says why nothing happened.
	steve.cooldown = 12.0
	var shown: int = hud.popup_count()
	steve.request_plant()
	await physics_frame
	await _frames(1)
	_check(hud.popup_count() > shown, "F during the cooldown shows 'flag in 12s'")

	# Quit to title.
	_press("pause")
	await _frames(2)
	_button(pause, "Quit to title").pressed.emit()
	await _frames(4)
	_check(not paused and current_scene.scene_file_path == "res://scenes/title.tscn", "Quit to title, unpaused")

	for p in [prof.path, settings.path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("MENU pass" if _fails == 0 else "MENU fail (%d)" % _fails)
	quit(1 if _fails else 0)


func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)


func _button(under: Node, text: String) -> Button:
	for b in under.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


func _button_prefix(under: Node, prefix: String) -> Button:
	for b in under.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with(prefix):
			return b
	return null


func _text_in(under: Node, s: String) -> bool:
	for l in under.find_children("*", "Label", true, false):
		if s in (l as Label).text:
			return true
	return false


## Every visible button and label sits fully on the 640x360 screen.
func _check_fits(under: Node, where: String) -> void:
	for c in under.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not ctl.is_visible_in_tree() or not (ctl is Button or ctl is Label) or ctl.size == Vector2.ZERO:
			continue
		var r := ctl.get_global_rect()
		_check(VIEW.encloses(r.grow(-0.5)), "%s: %s '%s' on screen (%s)" % [where, ctl.get_class(), ctl.get("text").left(24), r])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what)
