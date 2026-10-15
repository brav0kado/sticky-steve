extends Camera2D
## Follows Steve and zooms out with his jump (Hub: sticky-steve-design, camera spec).
##
## The air zoom is set at launch from the charge, because in a Jump King arc speed falls to zero
## at the apex: a camera keyed to live speed would zoom back IN exactly when the player needs to
## see the landing. So while Steve is airborne the view only ever widens (a fast fall widens it
## further); after landing it eases back in, slower than it went out, and settles on exactly 1.0
## so the resting view is whole-pixel (fractional zoom only ever happens in motion).

@export var target_path: NodePath
@export var zoom_full_jump := 0.55  ## zoom at a full charge (smaller = wider view)
@export var fall_widen_from := 260.0  ## fall speed (px/s) where falling starts widening the view
@export var zoom_out_rate := 7.0  ## ~0.4 s to settle
@export var zoom_in_rate := 2.6  ## ~0.9 s: breathes back in instead of snapping
@export var follow_rate := 6.0
@export var lead := 0.25  ## seconds of horizontal velocity to look ahead
@export var lead_max := 40.0
@export var look_up := 24.0  ## Steve sits a little below centre: the climb is upward
## The tower is exactly one screen wide, so the camera holds this x and only follows vertically
## (following sideways just showed half a screen of wall). NAN = follow x as well.
@export var lock_x := 320.0

var air_zoom := 1.0
var _shake := 0.0
var _shake_time := 0.0
var _target: Node2D


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node2D
	if _target == null:
		push_error("GameCamera: no target at %s" % target_path)
		return
	if _target.has_signal("jumped"):
		_target.jumped.connect(_on_jumped)
	global_position = _goal()
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if _target == null:
		return
	var airborne: bool = _target.is_airborne()
	if airborne:
		var vy: float = _target.velocity.y
		if vy > fall_widen_from:
			var t := clampf((vy - fall_widen_from) / maxf(_target.max_fall - fall_widen_from, 1.0), 0.0, 1.0)
			air_zoom = minf(air_zoom, lerpf(1.0, zoom_full_jump, t))
	else:
		air_zoom = 1.0
	var want := air_zoom
	var rate := zoom_out_rate if want < zoom.x else zoom_in_rate
	var z := lerpf(zoom.x, want, 1.0 - exp(-rate * delta))
	if absf(z - want) < 0.002:
		z = want
	zoom = Vector2(z, z)
	global_position = global_position.lerp(_goal(), 1.0 - exp(-follow_rate * delta))
	if _shake_time > 0.0:
		_shake_time -= delta
		var a := _shake * clampf(_shake_time / 0.25, 0.0, 1.0)
		offset = Vector2(randf_range(-a, a), randf_range(-a, a)).round()
	else:
		offset = Vector2.ZERO


func shake(strength: float, time := 0.25) -> void:
	_shake = maxf(_shake if _shake_time > 0.0 else 0.0, strength)
	_shake_time = maxf(_shake_time, time)


func _on_jumped(charge: float) -> void:
	# Never zoom in mid-air: a wall jump after a big leap keeps the wider of the two.
	air_zoom = minf(air_zoom, lerpf(1.0, zoom_full_jump, charge))


func _goal() -> Vector2:
	var vx: float = _target.velocity.x
	var goal: Vector2 = _target.global_position + Vector2(clampf(vx * lead, -lead_max, lead_max), -look_up)
	if not is_nan(lock_x):
		goal.x = lock_x
	return goal
