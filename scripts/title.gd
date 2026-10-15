extends Control
## Title screen (the main scene): Climb, Settings, Reset progress, Quit, with the player's bests
## under the name so every return here says "you can beat this". Reset asks twice: the first
## press arms it for a few seconds, the second wipes the Profile.

const GAME := "res://scenes/main.tscn"
const STEVE_FRAMES := "res://art/steve/steve_frames.tres"
const RESET_ARM_SECONDS := 3.0

var _menu: VBoxContainer
var _title: Label
var _buttons: Array[Button] = []
var _reset: Button
var _bests: Label
var _settings: SettingsPanel
var _reset_armed_until := 0


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
	get_tree().change_scene_to_file(GAME)


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
	if d.runs == 0 and d.best_height_m <= 0.0:
		_bests.text = "Charge. Commit. Climb."
		return
	var t := "best %s" % UI.clock(d.best_time) if d.best_time > 0.0 else "best height %d m" % roundi(d.best_height_m)
	_bests.text = "%s     gems found %d     best streak %d     climbs %d" % [t, d.gems.size(), d.best_streak, d.runs]
