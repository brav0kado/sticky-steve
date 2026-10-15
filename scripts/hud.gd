extends CanvasLayer
## Prototype HUD: climb timer and height (top left), the flag and its cooldown (top right), a
## controls hint for the first seconds, and the summit card. Built in code: greybox UI that will
## be replaced by real art. Colours from Nyx8 only.

const FLAG_ICON := "res://art/flag/flag.png"
const PX_PER_M := 12.0  ## Steve is ~21 px tall: call him 1.75 m
const HINT_SECONDS := 8.0

var steve: Node2D
var elapsed := 0.0
var running := true

var _info: Label
var _flag_label: Label
var _hint: Label
var _card: Label
var _meter: Control
var _icon: TextureRect
var _panel: PanelContainer
var _ground_y := 0.0


func _ready() -> void:
	layer = 10
	_info = _label(Vector2(8, 6))
	_flag_label = _label(Vector2(0, 6))
	_flag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_flag_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_flag_label.offset_left = -150
	_flag_label.offset_right = -42
	_meter = Control.new()
	_meter.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_meter.offset_left = -38
	_meter.offset_top = 4
	_meter.draw.connect(_draw_meter)
	add_child(_meter)
	var atlas := AtlasTexture.new()
	atlas.atlas = load(FLAG_ICON)
	atlas.region = Rect2(0, 0, 32, 32)  # first frame of flag_wave
	_icon = TextureRect.new()
	_icon.texture = atlas
	_meter.add_child(_icon)
	_hint = _label(Vector2.ZERO)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -52
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.text = "Hold SPACE to charge, let go to jump: on the cream flash = perfect\nC cancel   A/D move   F plant flag   R back to flag"
	# The summit card sits on a solid panel: over the level its text was unreadable.
	_panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Nyx8.INK
	box.border_color = Nyx8.CREAM
	box.set_border_width_all(2)
	box.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", box)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)
	_card = _label(Vector2.ZERO)
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.reparent(_panel)
	_panel.hide()


func bind(player: Node2D) -> void:
	steve = player
	_ground_y = player.global_position.y


func _process(delta: float) -> void:
	if steve == null:
		return
	if running:
		elapsed += delta
	var m := maxf((_ground_y - steve.global_position.y) / PX_PER_M, 0.0)
	_info.text = "%s   %d m" % [clock(elapsed), roundi(m)]
	var cd: float = steve.cooldown
	_flag_label.text = "F" if cd <= 0.0 else "%ds" % ceili(cd)
	_meter.queue_redraw()
	if _hint.visible and elapsed > HINT_SECONDS:
		_hint.hide()


func show_summit() -> void:
	running = false
	var s: Dictionary = steve.stats
	_card.text = "THE TOP\n\n%s\n%d jumps   %d falls   %d flags\n%d perfect   %d edge landings\n\nEnter: climb again" % [
		clock(elapsed), s.jumps, s.falls, s.flags, s.perfect, s.edges]
	_panel.show()


static func clock(t: float) -> String:
	return "%d:%02d.%d" % [int(t) / 60, int(t) % 60, int(t * 10.0) % 10]


func _label(pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_color_override("font_color", Nyx8.CREAM)
	l.add_theme_color_override("font_outline_color", Nyx8.INK)
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	return l


## The flag icon over a refill bar: icon + full bar = ready; while cooling, the bar refills.
func _draw_meter() -> void:
	var ready: bool = steve != null and steve.cooldown <= 0.0
	# Shown only when ready: dimming it with a tint would mix colours off the NYX8 palette.
	_icon.visible = ready
	var frac := 1.0
	if steve and not ready:
		frac = 1.0 - steve.cooldown / maxf(steve.flag_cooldown, 0.001)
	_meter.draw_rect(Rect2(2, 33, 28, 4), Nyx8.INK)
	_meter.draw_rect(Rect2(3, 34, roundf(26.0 * frac), 2), Nyx8.CREAM if ready else Nyx8.SAND)
