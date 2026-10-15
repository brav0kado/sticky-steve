extends Control
## Title screen (the main scene): Climb, Settings, Reset progress, Quit, with the player's bests
## under the name so every return here says "you can beat this". Reset asks twice: the first
## press arms it for a few seconds, the second wipes the Profile.
## Climb opens the mode picker: with flags or without, each with an explainer that follows the
## focus (so the rules are read at the moment of choosing) and that mode's best.

const GAME := "res://scenes/main.tscn"
const STEVE_FRAMES := "res://art/steve/steve_frames.tres"
const RESET_ARM_SECONDS := 3.0
const EXPLAIN := {
	"flags": "Press F on solid ground to plant a flag: your checkpoint.\nFall below it and you land back on it. R takes you back any time.\nOne flag every 20 seconds; a new flag replaces the old one.",
	"noflag": "No checkpoints. Every fall costs all the height you lose.\nOne mistake can send you back to the bottom.\nThe real climb: bests and ranks are kept apart from flagged climbs.",
}

var _menu: VBoxContainer
var _title: Label
var _buttons: Array[Button] = []
var _reset: Button
var _bests: Label
var _settings: SettingsPanel
var _reset_armed_until := 0
var _modes: Control  # the mode picker panel
var _mode_buttons: Array[Button] = []
var _explain: Label


func _ready() -> void:
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sky := ColorRect.new()
	sky.color = Nyx8.DUSK
	sky.add_to_group("background")
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sky)

	_title = UI.label("STICKY STEVE", 40)
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title.offset_top = 28
	add_child(_title)

	# Steve idling beside the menu, three times size: the game's face.
	var steve := AnimatedSprite2D.new()
	steve.sprite_frames = load(STEVE_FRAMES)
	steve.play("idle")
	steve.scale = Vector2(3, 3)
	steve.position = Vector2(150, 230)
	add_child(steve)

	_menu = VBoxContainer.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu.offset_top = 30
	_menu.custom_minimum_size.x = 200
	add_child(_menu)
	_buttons.append(UI.button("Climb", _climb))
	_buttons.append(UI.button("Settings", _open_settings))
	_reset = UI.button("Reset progress", _press_reset)
	_buttons.append(_reset)
	_buttons.append(UI.button("Quit", func() -> void: get_tree().quit()))
	for b in _buttons:
		_menu.add_child(b)
	UI.chain_focus(_buttons)

	_bests = UI.label("", 13)
	_bests.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_bests.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bests.offset_top = -40
	add_child(_bests)
	_refresh_bests()

	_build_mode_picker()

	_settings = SettingsPanel.new()
	_settings.hide()
	add_child(_settings)
	_settings.closed.connect(func() -> void:
		_menu.show()
		_title.show()
		_buttons[1].grab_focus())
	_buttons[0].grab_focus()


func _process(_delta: float) -> void:
	if _reset_armed_until > 0 and Time.get_ticks_msec() > _reset_armed_until:
		_reset_armed_until = 0
		_reset.text = "Reset progress"


func _climb() -> void:
	_menu.hide()
	_bests.hide()
	_title.hide()  # the picker is taller than the gap under the title
	_modes.show()
	_mode_buttons[0 if Profile.data.last_mode == "flags" else 1].grab_focus()


func _start(mode: String) -> void:
	Profile.set_mode(mode)
	get_tree().change_scene_to_file(GAME)


func _build_mode_picker() -> void:
	var parts := UI.panel()
	var panel: PanelContainer = parts[0]
	var box: VBoxContainer = parts[1]
	panel.offset_top = 20
	add_child(panel)
	box.add_child(UI.label("HOW WILL YOU CLIMB?", 18))
	for m: String in ["flags", "noflag"]:
		var b := UI.button("With flags" if m == "flags" else "No flags", func() -> void: _start(m))
		b.focus_entered.connect(func() -> void: _explain_mode(m))
		box.add_child(b)
		_mode_buttons.append(b)
	var back := UI.button("Back", _close_modes)
	back.focus_entered.connect(func() -> void: _explain.text = "")
	box.add_child(back)
	_mode_buttons.append(back)
	_explain = UI.label("", 12)
	_explain.custom_minimum_size = Vector2(420, 78)
	_explain.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	box.add_child(_explain)
	UI.chain_focus(_mode_buttons)
	_modes = panel
	panel.hide()


func _explain_mode(m: String) -> void:
	var best: float = Profile.bests(m).best_time
	var tail := "\nYour best: %s" % UI.clock(best) if best > 0.0 else "\nNo climb finished yet."
	_explain.text = EXPLAIN[m] + tail


func _close_modes() -> void:
	_modes.hide()
	_title.show()
	_menu.show()
	_bests.show()
	_buttons[0].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _modes.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_modes()


func _open_settings() -> void:
	_menu.hide()
	_title.hide()  # the panel is taller than the gap under the title
	_settings.open()


func _press_reset() -> void:
	if _reset_armed_until == 0:
		_reset_armed_until = Time.get_ticks_msec() + int(RESET_ARM_SECONDS * 1000.0)
		_reset.text = "Press again to erase"
		return
	_reset_armed_until = 0
	Profile.reset()
	_reset.text = "Progress erased"
	_refresh_bests()


func _refresh_bests() -> void:
	var d: Dictionary = Profile.data
	var f: Dictionary = Profile.bests("flags")
	var n: Dictionary = Profile.bests("noflag")
	if d.runs == 0 and f.best_height_m <= 0.0 and n.best_height_m <= 0.0:
		_bests.text = "Charge. Commit. Climb."
		return
	_bests.text = "flags %s     no flags %s     gems %d     best streak %d     climbs %d" % [
		_best_text(f), _best_text(n), d.gems.size(), d.best_streak, d.runs]


func _best_text(b: Dictionary) -> String:
	if b.best_time > 0.0:
		return UI.clock(b.best_time)
	return "%d m" % roundi(b.best_height_m) if b.best_height_m > 0.0 else "-"
