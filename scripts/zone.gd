@tool
class_name Zone
extends Node2D
## A zone of the tower starts at this node's y: crossing it upward shows the zone's banner and the
## split time against the best (Profile). Zones are the progress beats of a climb: each one teaches
## one idea, then the next combines it with something new (design note: Tower).

@export var index := 1
@export var title := "Zone"
@export var width := 640.0  ## only for the editor line


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_line(Vector2.ZERO, Vector2(width, 0), Nyx8.CREAM, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(4, -4), "%d  %s" % [index, title], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Nyx8.CREAM)
