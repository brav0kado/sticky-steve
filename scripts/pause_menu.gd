extends CanvasLayer
## Pause menu (Esc / pad Start) over the climb: Resume, Restart run, Settings, Quit to title.
## Pausing freezes the tree (Steve, timer, crumble ledges); this layer keeps running. Esc again or
## pad B resumes. It won't open over the summit card (the run is over there).

const TITLE := "res://scenes/title.tscn"

var blocked := false  ## set when the run is finished

var _panel: PanelContainer
var _buttons: Array[Button] = []
var _settings: SettingsPanel


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var parts := UI.panel()
	_panel = parts[0]
	_panel.theme = UI.theme()
	var v: VBoxContainer = parts[1]
	v.add_child(UI.label("PAUSED", 20))
	_buttons.append(UI.button("Resume", resume))
	_buttons.append(UI.button("Restart run", func() -> void:
		get_tree().paused = false
		get_tree().reload_current_scene()))
	_buttons.append(UI.button("Settings", _open_settings))
	_buttons.append(UI.button("Quit to title", func() -> void:
		get_tree().paused = false
		get_tree().change_scene_to_file(TITLE)))
	for b in _buttons:
		v.add_child(b)
	add_child(_panel)
	UI.chain_focus(_buttons)
	_panel.hide()
	_settings = SettingsPanel.new()
	_settings.hide()
	add_child(_settings)
	_settings.closed.connect(func() -> void:
		_panel.show()
		_buttons[2].grab_focus())


func is_open() -> bool:
	return _panel.visible or _settings.visible


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or (is_open() and event.is_action_pressed("ui_cancel") and not _settings.visible):
		get_viewport().set_input_as_handled()
		if is_open():
			resume()
		elif not blocked:
			open()


func open() -> void:
	get_tree().paused = true
	_panel.show()
	_buttons[0].grab_focus()
	Sfx.play("charge_tick", 0.7, -4.0)


func resume() -> void:
	_settings.hide()
	_panel.hide()
	get_tree().paused = false


func _open_settings() -> void:
	_panel.hide()
	_settings.open()
