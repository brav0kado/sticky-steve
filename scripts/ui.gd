class_name UI
## Shared menu look and widgets, NYX8 only: INK panels with a CREAM frame, buttons that light up
## SLATE with a CREAM outline when focused (keyboard/pad) or hovered. Built in code (greybox UI).
##
## Focus is drawn as an outline only: an opaque focus fill is drawn OVER the button text and hides
## it (404 pitfall), so the fill change lives in hover/normal and focus just frames it.


static func theme() -> Theme:
	var t := Theme.new()
	t.set_stylebox("normal", "Button", _box(Nyx8.INK, Nyx8.SHADOW, 1))
	t.set_stylebox("pressed", "Button", _box(Nyx8.SLATE, Nyx8.SAND, 1))
	t.set_stylebox("hover", "Button", _box(Nyx8.SLATE, Nyx8.SHADOW, 1))
	t.set_stylebox("disabled", "Button", _box(Nyx8.INK, Nyx8.INK, 1))
	var focus := _box(Nyx8.INK, Nyx8.CREAM, 2)
	focus.draw_center = false
	t.set_stylebox("focus", "Button", focus)
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", Nyx8.CREAM)
	t.set_color("font_pressed_color", "Button", Nyx8.SAND)
	t.set_color("font_disabled_color", "Button", Nyx8.SHADOW)
	t.set_stylebox("panel", "PanelContainer", _box(Nyx8.INK, Nyx8.CREAM, 2, 12))
	t.set_color("font_color", "Label", Nyx8.CREAM)
	t.set_color("font_outline_color", "Label", Nyx8.INK)
	t.set_constant("outline_size", "Label", 4)
	t.set_constant("separation", "VBoxContainer", 6)
	return t


## "m:ss.d", the one time format everywhere (HUD, summit card, title).
static func clock(t: float) -> String:
	return "%d:%02d.%d" % [int(t) / 60, int(t) % 60, int(t * 10.0) % 10]


static func _box(fill: Color, border: Color, width: int, margin := 4) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.border_color = border
	b.set_border_width_all(width)
	b.set_content_margin_all(margin)
	b.content_margin_left = margin + 8
	b.content_margin_right = margin + 8
	return b


static func button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func() -> void:
		Sfx.play("charge_tick", 1.3, -6.0)
		on_press.call())
	b.focus_entered.connect(func() -> void: Sfx.play("charge_tick", 1.0, -12.0))
	return b


static func label(text: String, size := 16) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	return l


## A centred PanelContainer holding a VBox; returns [panel, vbox].
static func panel() -> Array:
	var p := PanelContainer.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	p.add_child(v)
	return [p, v]


## Wires up/down focus through the buttons (wrapping), so keyboard and pad never lose focus.
static func chain_focus(buttons: Array) -> void:
	for i in buttons.size():
		var b: Control = buttons[i]
		b.focus_neighbor_top = b.get_path_to(buttons[(i - 1 + buttons.size()) % buttons.size()])
		b.focus_neighbor_bottom = b.get_path_to(buttons[(i + 1) % buttons.size()])
