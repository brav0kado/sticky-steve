class_name SettingsPanel
extends PanelContainer
## Settings menu, shared by the title screen and the pause menu. Volume rows change with
## left/right (or press to step up, wrapping), so it works the same on keyboard and pad.
## Esc / pad B / Back closes it.

signal closed

const ROWS := [["Volume", "Master"], ["Sound effects", "SFX"], ["Music", "Music"]]

var _buttons: Array[Button] = []


func _ready() -> void:
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	process_mode = Node.PROCESS_MODE_ALWAYS  # it opens over a paused game
	var v := VBoxContainer.new()
	add_child(v)
	v.add_child(UI.label("SETTINGS", 20))
	for row: Array in ROWS:
		var bus: String = row[1]
		var b := UI.button("", func() -> void: _step(bus, 1, true))
		b.set_meta("bus", bus)
		b.set_meta("title", row[0])
		b.gui_input.connect(func(e: InputEvent) -> void: _on_row_input(e, bus))
		v.add_child(b)
		_buttons.append(b)
	var full := UI.button("", func() -> void: Settings.set_fullscreen(not Settings.fullscreen))
	full.set_meta("title", "Fullscreen")
	v.add_child(full)
	_buttons.append(full)
	var back := UI.button("Back", close)
	v.add_child(back)
	_buttons.append(back)
	UI.chain_focus(_buttons)
	Settings.changed.connect(_refresh)
	_refresh()


func open() -> void:
	show()
	_buttons[0].grab_focus()


func close() -> void:
	hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _on_row_input(e: InputEvent, bus: String) -> void:
	if e.is_action_pressed("ui_left"):
		_step(bus, -1, false)
		accept_event()
	elif e.is_action_pressed("ui_right"):
		_step(bus, 1, false)
		accept_event()


func _step(bus: String, by: int, wrap: bool) -> void:
	var v: int = Settings.volume[bus] + by
	if wrap and v > Settings.VOLUME_STEPS:
		v = 0
	Settings.set_volume(bus, v)
	Sfx.play("charge_tick", 0.8 + 0.08 * Settings.volume[bus], -4.0)  # hear the new level


func _refresh() -> void:
	for b in _buttons:
		if b.has_meta("bus"):
			var steps: int = Settings.volume[b.get_meta("bus")]
			b.text = "%s   < %s >" % [b.get_meta("title"), "off" if steps == 0 else str(steps * 10) + "%"]
		elif b.get_meta("title", "") == "Fullscreen":
			b.text = "Fullscreen   %s" % ("on" if Settings.fullscreen else "off")
