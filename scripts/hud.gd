extends CanvasLayer
## HUD: timer, height (with the best) and gems top left; the flag meter top right; a zone banner
## with the split against the best; the controls hint for the first seconds; the summit card with
## its rank and the checklist that says how to rank higher. Greybox UI built in code, NYX8 only.

const FLAG_ICON := "res://art/flag/flag.png"
const PX_PER_M := 12.0  ## Steve is ~21 px tall: call him 1.75 m
const HINT_SECONDS := 10.0
const BANNER_SECONDS := 2.6

var steve: Node2D
var elapsed := 0.0
var running := true
var gems := 0
var gems_total := 0
var best_m := 0.0

var _info: Label
var _gem_label: Label
var _flag_label: Label
var _hint: Label
var _banner: Label
var _card: Label
var _meter: Control
var _icon: TextureRect
var _panel: PanelContainer
var _ground_y := 0.0
var _banner_until := 0
var _popups: Array = []  # [label, world_pos, born_msec]
var _best_label: Label
var best_line_y := NAN  ## world y of the BEST line (NAN = hidden)
var best_m_at_start := 0.0

const POPUP_SECONDS := 0.9
const POPUP_RISE := 28.0  ## screen px


func _ready() -> void:
	layer = 10
	_info = _label(Vector2(8, 6))
	_gem_label = _label(Vector2(8, 24))
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
	_hint = _centered(-52, Control.PRESET_CENTER_BOTTOM)
	_hint.text = "Hold SPACE to charge, let go to jump: on the cream flash = perfect\nC cancel   A/D move   F plant flag   R back to flag"
	_best_label = _label(Vector2.ZERO)
	_best_label.add_theme_color_override("font_color", Nyx8.SAND)
	_best_label.hide()
	_banner = _centered(48, Control.PRESET_CENTER_TOP)
	_banner.add_theme_font_size_override("font_size", 22)
	_banner.hide()
	# The summit card sits on a solid panel: over the level its text was unreadable.
	_panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Nyx8.INK
	box.border_color = Nyx8.CREAM
	box.set_border_width_all(2)
	box.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", box)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)
	_card = _label(Vector2.ZERO)
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_theme_font_size_override("font_size", 13)  # the whole card fits a 360 px screen
	_card.reparent(_panel)
	_panel.hide()


func bind(player: Node2D, total_gems: int, best_height_m: float) -> void:
	steve = player
	_ground_y = player.global_position.y
	gems_total = total_gems
	best_m = best_height_m


func height_m() -> float:
	return maxf((_ground_y - steve.global_position.y) / PX_PER_M, 0.0) if steve else 0.0


func _process(delta: float) -> void:
	if steve == null:
		return
	if running:
		elapsed += delta
	var m := height_m()
	best_m = maxf(best_m, m)
	_info.text = "%s   %d m   best %d m" % [clock(elapsed), roundi(m), roundi(best_m)]
	_gem_label.text = "gems %d / %d" % [gems, gems_total]
	var cd: float = steve.cooldown
	_flag_label.text = "F" if cd <= 0.0 else "%ds" % ceili(cd)
	_meter.queue_redraw()
	if _hint.visible and elapsed > HINT_SECONDS:
		_hint.hide()
	if _banner.visible and Time.get_ticks_msec() > _banner_until:
		_banner.hide()
	_update_popups()
	_update_best_label()


## Floating text at a world point, drawn in screen space so it stays crisp and readable at any
## camera zoom. Pops in big, settles, rises, goes (no fade: fading would blend colours off NYX8).
func popup(text: String, world_pos: Vector2, size: int) -> void:
	var l := _label(Vector2.ZERO)
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.reset_size()
	l.pivot_offset = l.size / 2.0
	l.scale = Vector2(1.6, 1.6)
	l.create_tween().tween_property(l, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_popups.append([l, world_pos, Time.get_ticks_msec()])
	_update_popups()


func popup_count() -> int:
	return _popups.size()


func _update_popups() -> void:
	var xf := get_viewport().get_canvas_transform()
	var now := Time.get_ticks_msec()
	for p: Array in _popups.duplicate():
		var l: Label = p[0]
		var age := (now - int(p[2])) / 1000.0
		if age > POPUP_SECONDS:
			l.queue_free()
			_popups.erase(p)
			continue
		var at: Vector2 = xf * (p[1] as Vector2)
		l.position = (at - l.size / 2.0 - Vector2(0, POPUP_RISE * age / POPUP_SECONDS)).round()


func _update_best_label() -> void:
	if is_nan(best_line_y):
		_best_label.hide()
		return
	var y := (get_viewport().get_canvas_transform() * Vector2(0, best_line_y)).y
	var h := get_viewport().get_visible_rect().size.y
	_best_label.visible = y > 40.0 and y < h - 10.0
	_best_label.text = "BEST %d m" % roundi(best_m_at_start)
	_best_label.position = Vector2(8, y - 20)



## Big centred text for a moment: zone names, NEW BEST.
func banner(text: String) -> void:
	_banner.text = text
	_banner.show()
	_banner_until = Time.get_ticks_msec() + int(BANNER_SECONDS * 1000.0)


## `checks`: [[label, passed], ...] for the rank checklist; `records`: lines like "NEW BEST TIME".
func show_summit(rank: String, checks: Array, records: Array) -> void:
	running = false
	var s: Dictionary = steve.stats
	var lines := PackedStringArray(["THE TOP", "RANK %s     %s" % [rank, clock(elapsed)]])
	for r: String in records:
		lines.append(r)
	for c: Array in checks:
		lines.append("%s  %s" % ["[x]" if c[1] else "[ ]", c[0]])
	lines.append("")
	lines.append("%d jumps   %d perfect   best streak %d" % [s.jumps, s.perfect, s.best_streak])
	lines.append("%d saves   %d edge landings   %d m fallen" % [s.saves, s.edges, roundi(s.fallen_px / PX_PER_M)])
	lines.append("Enter: climb again     Esc: title")
	_card.text = "\n".join(lines)
	_panel.show()


static func clock(t: float) -> String:
	return UI.clock(t)


func _label(pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_color_override("font_color", Nyx8.CREAM)
	l.add_theme_color_override("font_outline_color", Nyx8.INK)
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	return l


func _centered(offset_y: float, preset: Control.LayoutPreset) -> Label:
	var l := _label(Vector2.ZERO)
	l.set_anchors_and_offsets_preset(preset)
	l.offset_top = offset_y
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
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
