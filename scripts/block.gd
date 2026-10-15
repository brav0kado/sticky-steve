@tool
class_name Block
extends StaticBody2D
## Greybox terrain: a rectangle `size` big with its origin at the top-left corner. It builds its
## own collision shape and draws itself, so a level is just Blocks dragged around in the editor.
##
## SOLID walls bounce Steve back. STICKY walls can be slapped (once per airtime) and also sit on
## physics layer 3 "sticky". BOUNCY pads fling him up at bounce_speed (and ricochet him off their
## sides). CRUMBLE ledges shake once stood on, drop away after crumble_delay and come back after
## regrow_delay. Colours come only from Nyx8.BACKGROUND: backgrounds never use
## Steve's colours (tests/palette_checks.gd checks FILL/EDGE against his sheet).
##
## Skin: with `skin` set (the zone's tile sheet, art/world/zone<N>_tiles.png) the block draws as a
## nine-slice from 8 px tiles: each surface owns a 24x24 slot (3x3 tiles: corners, edges, centre)
## at x = SLOT_X[surface]; edges and centre repeat to fill any size >= 16x16. Without a skin it
## draws the greybox look. Art spec: Hub sticky-steve-art-spec.
##
## route_step >= 0 marks the intended climb in order; tests/route_checks.gd proves every step can
## be reached from the one before with real jumps, so a level edit can't silently break the climb.

enum Surface { SOLID, STICKY, BOUNCY, CRUMBLE }

const FILL := {Surface.SOLID: Nyx8.SLATE, Surface.STICKY: Nyx8.MAUVE, Surface.BOUNCY: Nyx8.NAVY, Surface.CRUMBLE: Nyx8.SLATE}
const EDGE := {Surface.SOLID: Nyx8.NAVY, Surface.STICKY: Nyx8.SLATE, Surface.BOUNCY: Nyx8.MAUVE, Surface.CRUMBLE: Nyx8.DUSK}
const STICKY_LAYER := 1 << 2  ## physics layer 3
const TILE := 8
const SLOT_X := {Surface.SOLID: 0, Surface.STICKY: 32, Surface.BOUNCY: 64, Surface.CRUMBLE: 96}

@export var size := Vector2(64, 16):
	set(v):
		size = v.max(Vector2.ONE)
		_rebuild()
@export var surface := Surface.SOLID:
	set(v):
		surface = v
		_rebuild()
@export var route_step := -1
@export var bounce_speed := 600.0  ## BOUNCY: launch speed straight up (~200 px with apex hang)
@export var crumble_delay := 1.2  ## CRUMBLE: seconds from first touch to falling away
@export var regrow_delay := 3.0  ## CRUMBLE: seconds gone before it comes back

## The zone's tile sheet (main.gd assigns it by zone); null = greybox.
var skin: Texture2D:
	set(v):
		skin = v
		queue_redraw()

var _crumble_t := -1.0  # >= 0 while counting down to falling
var _gone_t := -1.0  # >= 0 while gone

var _shape: CollisionShape2D


func _init() -> void:
	add_to_group("background")


func _ready() -> void:
	_rebuild()


func is_sticky() -> bool:
	return surface == Surface.STICKY


func is_solid_now() -> bool:
	return _gone_t < 0.0


## Steve landed on it: a CRUMBLE block starts its countdown (once; standing longer changes nothing).
func stood_on() -> void:
	if surface == Surface.CRUMBLE and _crumble_t < 0.0 and _gone_t < 0.0:
		_crumble_t = crumble_delay


## Called every physics frame in the game; tests call it directly to step time.
func tick(delta: float) -> void:
	if _crumble_t >= 0.0:
		_crumble_t -= delta
		queue_redraw()  # the shake
		if _crumble_t < 0.0:
			_set_gone(true)
	elif _gone_t >= 0.0:
		_gone_t -= delta
		if _gone_t < 0.0:
			if _player_inside():
				_gone_t = 0.25  # don't regrow around him: he'd be stuck inside it
			else:
				_set_gone(false)


func _physics_process(delta: float) -> void:
	if not Engine.is_editor_hint() and surface == Surface.CRUMBLE:
		tick(delta)


func _set_gone(gone: bool) -> void:
	_gone_t = regrow_delay if gone else -1.0
	_crumble_t = -1.0
	_shape.disabled = gone  # immediate: tests step this by hand and must see the same world
	visible = not gone


func _player_inside() -> bool:
	if not is_inside_tree():
		return false
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = _shape.shape
	q.transform = global_transform.translated_local(_shape.position)
	q.collision_mask = 1 << 1  # player layer
	return not get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


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
	# A crumbling ledge shudders by whole pixels while it counts down (no blending, stays on palette).
	var shake := Vector2.ZERO
	if _crumble_t >= 0.0:
		shake.x = float((Time.get_ticks_msec() / 50) % 3 - 1)
	draw_set_transform(shake)
	if skin:
		_draw_skin()
		return
	draw_rect(Rect2(Vector2.ZERO, size), FILL[surface])
	var edge: Color = EDGE[surface]
	draw_rect(Rect2(0, 0, size.x, minf(2.0, size.y)), edge)  # lit top: reads as a ledge
	if surface == Surface.BOUNCY:
		# A zigzag spring along the top.
		var x := 0.0
		while x + 4.0 <= size.x:
			draw_rect(Rect2(x, 2, 2, 2), edge)
			draw_rect(Rect2(x + 2, 4, 2, 2), edge)
			x += 4.0
	elif surface == Surface.CRUMBLE:
		# Cracks: short diagonal dashes.
		var cx := 3.0
		while cx + 3.0 <= size.x:
			draw_rect(Rect2(cx, 5, 1, 1), edge)
			draw_rect(Rect2(cx + 1, 6, 1, 1), edge)
			draw_rect(Rect2(cx + 2, 7, 1, 1), edge)
			cx += 9.0
	if is_sticky():
		# Studs down both faces: you can tell a slappable wall from a plain one at a glance.
		var y := 4.0
		while y + 2.0 <= size.y:
			draw_rect(Rect2(1, y, 2, 2), edge)
			draw_rect(Rect2(size.x - 3, y, 2, 2), edge)
			y += 6.0


## Nine-slice from the surface's 24x24 slot: 8 px corners stay put, edges and centre repeat; a
## run that doesn't divide by 8 ends on a cropped tile (left/top part of it).
func _draw_skin() -> void:
	var ox: int = SLOT_X[surface]
	var cols := _spans(size.x)
	var rows := _spans(size.y)
	for c: Array in cols:
		for r: Array in rows:
			var src := Rect2(ox + c[2] * TILE, r[2] * TILE, c[1], r[1])
			draw_texture_rect_region(skin, Rect2(c[0], r[0], c[1], r[1]), src)


## [[offset, length, tile index 0/1/2], ...] covering `length`: an 8 px start tile, repeated 8 px
## middles (the last one cropped) and an 8 px end tile.
static func _spans(length: float) -> Array:
	var n := int(length)
	var out := [[0, mini(TILE, n), 0]]
	var x := TILE
	while x < n - TILE:
		out.append([x, mini(TILE, n - TILE - x), 1])
		x += TILE
	if n > TILE:
		out.append([n - TILE, TILE, 2])
	return out
