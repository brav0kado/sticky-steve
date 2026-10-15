@tool
class_name Gem
extends Area2D
## A collectible placed off the main route, in spots that take a risky or skilful jump: the
## optional reward that makes a run worth replaying. Gems found on any earlier run draw hollow
## (`known`), so the player can see what's left. Its id is its node name (unique in the tower).
## tests/route_checks.gd proves every gem can be reached with real jumps.

signal collected(gem: Gem)

const RADIUS := 8.0

var known := false:  ## found on an earlier run (Profile)
	set(v):
		known = v
		queue_redraw()
var taken := false

var _t := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 << 1  # Steve
	monitorable = false
	if get_child_count() == 0:
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = RADIUS
		shape.shape = circle
		add_child(shape, false, Node.INTERNAL_MODE_FRONT)
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body)


func gem_id() -> String:
	return String(name)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _on_body(body: Node) -> void:
	if taken or not body.is_in_group("player"):
		return
	taken = true
	set_deferred("monitoring", false)
	hide()
	collected.emit(self)


## A diamond, bobbing by whole pixels. INK outline; CREAM/SAND fill, or hollow if already known.
func _draw() -> void:
	var bob := roundf(sin(_t * 3.0) * 1.5)
	var rows := [1, 3, 5, 7, 9, 7, 5, 3, 1]  # widths of a 9x9 diamond
	for i in rows.size():
		var w: int = rows[i]
		var y := float(i) - 4.0 + bob
		var x := -float(w) / 2.0
		draw_rect(Rect2(x - 1, y, w + 2, 1), Nyx8.INK)
		if not known or i == 0 or i == rows.size() - 1:
			draw_rect(Rect2(x, y, w, 1), Nyx8.CREAM if i < 4 else Nyx8.SAND)
	if known:
		for i in range(1, rows.size() - 1):
			var w2: int = rows[i] - 2
			if w2 > 0:
				draw_rect(Rect2(-float(w2) / 2.0, float(i) - 4.0 + bob, w2, 1), Nyx8.DUSK)
