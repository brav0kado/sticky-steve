@tool
class_name Block
extends StaticBody2D
## Greybox terrain: a rectangle `size` big with its origin at the top-left corner. It builds its
## own collision shape and draws itself, so a level is just Blocks dragged around in the editor.
##
## SOLID walls bounce Steve back. STICKY walls can be slapped (once per airtime) and also sit on
## physics layer 3 "sticky". Colours come only from Nyx8.BACKGROUND: backgrounds never use
## Steve's colours (tests/palette_checks.gd checks FILL/EDGE against his sheet).
##
## route_step >= 0 marks the intended climb in order; tests/route_checks.gd proves every step can
## be reached from the one before with real jumps, so a level edit can't silently break the climb.

enum Surface { SOLID, STICKY }

const FILL := {Surface.SOLID: Nyx8.SLATE, Surface.STICKY: Nyx8.MAUVE}
const EDGE := {Surface.SOLID: Nyx8.NAVY, Surface.STICKY: Nyx8.SLATE}
const STICKY_LAYER := 1 << 2  ## physics layer 3

@export var size := Vector2(64, 16):
	set(v):
		size = v.max(Vector2.ONE)
		_rebuild()
@export var surface := Surface.SOLID:
	set(v):
		surface = v
		_rebuild()
@export var route_step := -1

var _shape: CollisionShape2D


func _init() -> void:
	add_to_group("background")


func _ready() -> void:
	_rebuild()


func is_sticky() -> bool:
	return surface == Surface.STICKY


## World-space top edge centre: where Steve stands on it.
func top_center() -> Vector2:
	return global_position + Vector2(size.x / 2.0, 0.0)


func _rebuild() -> void:
	if _shape == null:
		# Built in code, never saved into the scene: the size export is the single source of truth.
		_shape = CollisionShape2D.new()
		_shape.shape = RectangleShape2D.new()
		add_child(_shape, false, Node.INTERNAL_MODE_FRONT)
	(_shape.shape as RectangleShape2D).size = size
	_shape.position = size / 2.0
	collision_layer = 1 | (STICKY_LAYER if is_sticky() else 0)
	collision_mask = 0
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), FILL[surface])
	var edge: Color = EDGE[surface]
	draw_rect(Rect2(0, 0, size.x, minf(2.0, size.y)), edge)  # lit top: reads as a ledge
	if is_sticky():
		# Studs down both faces: you can tell a slappable wall from a plain one at a glance.
		var y := 4.0
		while y + 2.0 <= size.y:
			draw_rect(Rect2(1, y, 2, 2), edge)
			draw_rect(Rect2(size.x - 3, y, 2, 2), edge)
			y += 6.0
