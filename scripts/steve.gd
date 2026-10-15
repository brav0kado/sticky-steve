class_name Steve
extends CharacterBody2D
## Steve, the player. Jump King model: on the ground he walks or charges; the jump is committed at
## release (charge sets the height, the direction held sets the launch), then air control is slow
## (an acceleration, never a direct set). Plain walls bounce him back. A sticky wall can be slapped
## once per airtime by holding toward it on contact: he hangs there and charges a jump away from
## it. Landing restores the slap. Planting a flag (20 s cooldown) sets the checkpoint; landing
## below it sends him back to it.
##
## Charging runs through three stages of stage_seconds each (each stage's animation loops). At
## full charge he holds (hovers on stage 3) until released: there is no auto-release. Cancel
## (C / pad B) drops the charge without jumping.
## Perfect release: letting go within perfect_window seconds of the charge filling adds a height
## bonus on top of a full jump. Hold longer and it's a plain full jump. The meter over his head
## (only while charging) shows the stages and turns cream for the perfect window.
## Edge landing: landing with only a sliver of his feet on the ledge fires edge_landed (slow-mo).
##
## All movement runs from tick(delta), so tests step him deterministically without the engine
## clock. `bot` replaces player input when non-empty (tests only): {"dir": -1..1, "jump": bool}.

signal jumped(charge: float)
signal landed(fall: float, hard: bool)
signal bonked
signal slapped
signal charge_stage(stage: int)
signal planted(flag_base: Vector2, faces_right: bool)
signal flag_ready
signal respawned
signal perfect_release
signal charge_full
signal charge_cancelled
signal edge_landed(overlap: float)

enum State { GROUND, CHARGE, AIR, CLING, CLING_CHARGE, LAND, PLANT }

@export_group("Ground")
@export var walk_speed := 105.0
@export_group("Jump")
@export var stage_seconds := 1.0  ## each of the three charge stages; full charge = 3x this
@export var jump_v_min := 170.0
@export var jump_v_max := 480.0  ## full charge: ~128 px (6 Steves)
@export var jump_vx := 115.0
@export var gravity := 900.0
@export var max_fall := 520.0
@export_group("Perfect release")
@export var perfect_window := 0.15  ## seconds after the charge fills: ~9 frames
@export var perfect_bonus := 1.06  ## launch speed multiplier over a full jump: ~12% more height
@export_group("Air")
@export var air_speed := 115.0
@export var air_accel := 180.0  ## px/s²: a full reversal takes ~1.3 s, so the launch still matters
@export var wall_bounce := 0.55
@export_group("Landing")
@export var hard_fall := 160.0  ## px fallen from the apex that counts as a hard landing
@export var land_lock := 0.1
@export var hard_land_lock := 0.35
@export var fall_stat := 64.0  ## landing this far below the take-off counts as a fall (stats)
@export var edge_px := 3.0  ## landing with this much foot (or less) on the ledge is an edge landing
@export_group("Flag")
@export var flag_cooldown := 20.0
@export var respawn_margin := 24.0  ## landing this far below the flag sends him back to it

## Steve is drawn facing left (headband trailing right; the plant frames reach to screen-left), so
## facing right = flip. walk_right is the exception: drawn facing right, mirrored for walking left.
const ART_FACES_LEFT := true
const DRAWN_FACING_RIGHT := [&"walk_right"]
## walk_right's 3 frames at 10 fps match this pace; faster walking plays them faster so the feet
## don't slide.
const WALK_ANIM_PACE := 70.0
const HAND_DATA := "res://art/flag/plant_flag_hand.json"
## The planting performance: [animation, times played]. The spin plays twice: a half-turn each.
const PLANT_SEQUENCE := [["raise_pole", 1], ["spin_pole", 2], ["plant_pole", 1]]
const PLANT_HOLD_FRAMES := 2  ## extra frames on the planted pose before control returns
const SPIN_STEP_DEG := 36.0
const CELL := 64.0
const SPRITE_OFFSET_Y := -11.0  ## feet row: see README (art pipeline)

var state := State.GROUND
var charge := 0.0
var facing := -1.0
var slap_ready := true
var wall_normal := 0.0
var cling_block: Block
var last_floor: Node
var has_checkpoint := false
var checkpoint := Vector2.ZERO
var cooldown := 0.0
var bot: Dictionary = {}
var charge_time: float:  ## seconds from empty to full
	get:
		return stage_seconds * 3.0
var stats := {"jumps": 0, "falls": 0, "flags": 0, "perfect": 0, "edges": 0}

var _start := Vector2.ZERO
var _apex_y := 0.0
var _takeoff_y := 0.0
var _lock := 0.0
var _respawn_pending := false
var _plant_requested := false
var _respawn_requested := false
var _cancel_requested := false
var _full_t := 0.0  # seconds spent at full charge (the perfect window is the start of this)
var _plant_t := 0.0
var _plant_frames: Array = []  # [[anim, frame], ...] one entry per 1/fps of the performance
var _impact_done := false
var _spin_start := 0  # index in _plant_frames of the first spin frame
var _hand: Dictionary = {}
var _grip: Dictionary = {}

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var plant_sprite: AnimatedSprite2D = $PlantSprite
@onready var pole: Sprite2D = $Pole
@onready var shape: CollisionShape2D = $Shape
var _meter: Node2D


func _ready() -> void:
	add_to_group("player")
	_start = global_position
	var data := load(HAND_DATA) as JSON
	if data and data.data is Dictionary:
		_hand = data.data.get("hand", {})
		_grip = data.data.get("pole_grip", {})
	else:
		push_error("Steve: can't read %s; planting will skip the pole" % HAND_DATA)
	for step: Array in PLANT_SEQUENCE:
		var anim: String = step[0]
		if not plant_sprite.sprite_frames.has_animation(anim):
			push_error("Steve: plant_flag has no %s animation" % anim)
			continue
		if anim == "spin_pole":
			_spin_start = _plant_frames.size()
		for _loop in int(step[1]):
			for f in plant_sprite.sprite_frames.get_frame_count(anim):
				_plant_frames.append([anim, f])
	plant_sprite.hide()
	pole.hide()
	_meter = Node2D.new()
	_meter.position = Vector2(0, -30)  # just over his head
	_meter.draw.connect(_draw_meter)
	add_child(_meter)


func _physics_process(delta: float) -> void:
	tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("plant_flag"):
		_plant_requested = true
	elif event.is_action_pressed("respawn"):
		_respawn_requested = true
	elif event.is_action_pressed("cancel_charge"):
		_cancel_requested = true


func request_plant() -> void:
	_plant_requested = true


func request_respawn() -> void:
	_respawn_requested = true


func request_cancel() -> void:
	_cancel_requested = true


func is_airborne() -> bool:
	return state in [State.AIR, State.CLING, State.CLING_CHARGE]


func in_perfect_window() -> bool:
	return charge >= 1.0 and _full_t <= perfect_window


func can_plant() -> bool:
	return state == State.GROUND and is_on_floor() and cooldown <= 0.0 and not _plant_frames.is_empty()


## For the F12 report (Debug autoload).
func debug_state() -> Dictionary:
	return {
		"state": State.keys()[state], "velocity": [velocity.x, velocity.y], "charge": charge,
		"facing": facing, "slap_ready": slap_ready, "cooldown": cooldown,
		"checkpoint": [checkpoint.x, checkpoint.y] if has_checkpoint else null, "stats": stats,
	}


func tick(delta: float) -> void:
	if cooldown > 0.0:
		cooldown = maxf(cooldown - delta, 0.0)
		if cooldown == 0.0:
			flag_ready.emit()
	if _respawn_requested:
		_respawn_requested = false
		if state != State.PLANT:
			respawn()
	match state:
		State.GROUND: _ground(delta)
		State.CHARGE, State.CLING_CHARGE: _charge(delta)
		State.AIR: _air(delta)
		State.CLING: _cling_tick()
		State.LAND: _land_tick(delta)
		State.PLANT: _plant_tick(delta)
	_meter.queue_redraw()
	_plant_requested = false  # only honoured on the tick it was pressed, in GROUND
	_cancel_requested = false
	_animate()


# ---------------------------------------------------------------- states
func _ground(delta: float) -> void:
	if _plant_requested and can_plant():
		_start_plant()
		return
	var d := signf(_dir())
	velocity.x = d * walk_speed
	if d != 0.0:
		facing = d
	if _jump_held():
		_begin_charge(State.CHARGE)
		velocity.x = 0.0
	_fall_and_slide(delta)
	if not is_on_floor():
		_leave_ground()


func _charge(delta: float) -> void:
	if _cancel_requested:
		charge = 0.0
		state = State.CLING if state == State.CLING_CHARGE else State.GROUND
		charge_cancelled.emit()
		return
	var before := _stage()
	if charge >= 1.0:
		_full_t += delta  # hovering at full: the perfect window runs out
	else:
		charge = minf(charge + delta / charge_time, 1.0)
		if charge >= 1.0:
			charge_full.emit()
	if _stage() != before:
		charge_stage.emit(_stage())
	if state == State.CHARGE:
		velocity.x = 0.0
		var d := signf(_dir())
		if d != 0.0:
			facing = d  # aim while charging
		_fall_and_slide(delta)
		if not is_on_floor():  # the ground went away mid-charge: the charge is lost
			charge = 0.0
			_leave_ground()
			return
	if not _jump_held():
		# From a wall the jump always goes away from it; from the ground, where he's pointing.
		_launch(wall_normal if state == State.CLING_CHARGE else signf(_dir()))


func _air(delta: float) -> void:
	var d := _dir()
	if d != 0.0:
		velocity.x = move_toward(velocity.x, signf(d) * air_speed, air_accel * delta)
	velocity.y = minf(velocity.y + gravity * delta, max_fall)
	var before := velocity
	move_and_slide()
	_apex_y = minf(_apex_y, global_position.y)
	if is_on_floor():
		_land()
		return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		if absf(n.x) < 0.7 or signf(before.x) != -signf(n.x):
			continue  # not a wall, or a wall he's moving away from
		var block := col.get_collider() as Block
		if block and block.is_sticky() and slap_ready and signf(d) == -signf(n.x):
			_cling(n.x, block)
			return
		if absf(before.x) > 1.0:
			velocity.x = -before.x * wall_bounce
			bonked.emit()
		break


func _cling_tick() -> void:
	velocity = Vector2.ZERO
	if _jump_held():
		_begin_charge(State.CLING_CHARGE)
	elif signf(_dir()) == wall_normal:
		# Pushing away without a jump lets go: a small drop off the wall.
		state = State.AIR
		velocity.x = wall_normal * 30.0
		cling_block = null


func _land_tick(delta: float) -> void:
	_lock -= delta
	_fall_and_slide(delta)
	if not is_on_floor():
		_leave_ground()
		return
	if _lock <= 0.0:
		state = State.GROUND
		if _respawn_pending:
			_respawn_pending = false
			respawn()


func _plant_tick(delta: float) -> void:
	_fall_and_slide(delta)
	_plant_t += delta
	var fps := plant_sprite.sprite_frames.get_animation_speed("raise_pole")
	var i := int(_plant_t * fps)
	if i >= _plant_frames.size() + PLANT_HOLD_FRAMES:
		_end_plant()
		return
	i = mini(i, _plant_frames.size() - 1)
	var anim: String = _plant_frames[i][0]
	var frame: int = _plant_frames[i][1]
	plant_sprite.animation = anim
	plant_sprite.frame = frame
	var last := i == _plant_frames.size() - 1
	if last and not _impact_done:
		_impact_done = true
		_plant_impact()
	pole.visible = not last
	if not last:
		_place_pole(anim, frame, i)


# ---------------------------------------------------------------- transitions
func _launch(dir: float) -> void:
	var perfect := in_perfect_window()
	velocity = Vector2(dir * jump_vx, -lerpf(jump_v_min, jump_v_max, charge) * (perfect_bonus if perfect else 1.0))
	if dir != 0.0:
		facing = dir
	jumped.emit(charge)
	if perfect:
		stats.perfect += 1
		perfect_release.emit()
	charge = 0.0
	state = State.AIR
	cling_block = null
	_apex_y = global_position.y
	_takeoff_y = global_position.y
	stats.jumps += 1
	sprite.play("jump")
	_squash(Vector2(0.8, 1.25))


func _begin_charge(to: State) -> void:
	state = to
	charge = 0.0
	_full_t = 0.0


func _leave_ground() -> void:
	state = State.AIR
	_apex_y = global_position.y
	_takeoff_y = global_position.y


func _cling(normal_x: float, block: Block) -> void:
	state = State.CLING
	wall_normal = normal_x
	cling_block = block
	velocity = Vector2.ZERO
	slap_ready = false
	facing = -normal_x
	slapped.emit()
	_squash(Vector2(0.75, 1.2))


func _land() -> void:
	var fall := global_position.y - _apex_y
	var hard := fall >= hard_fall
	last_floor = _floor_collider()
	velocity = Vector2.ZERO
	slap_ready = true
	state = State.LAND
	_lock = hard_land_lock if hard else land_lock
	if global_position.y - _takeoff_y >= fall_stat:
		stats.falls += 1
	_respawn_pending = has_checkpoint and global_position.y > checkpoint.y + respawn_margin
	sprite.play("land")
	_squash(Vector2(1.3, 0.75) if hard else Vector2(1.15, 0.88))
	landed.emit(fall, hard)
	var overlap := _foot_overlap()
	if overlap <= edge_px:
		stats.edges += 1
		edge_landed.emit(overlap)


func respawn() -> void:
	global_position = checkpoint if has_checkpoint else _start
	velocity = Vector2.ZERO
	state = State.GROUND
	charge = 0.0
	slap_ready = true
	cling_block = null
	reset_physics_interpolation()
	respawned.emit()


func _start_plant() -> void:
	state = State.PLANT
	velocity = Vector2.ZERO
	_plant_t = 0.0
	_impact_done = false
	sprite.hide()
	plant_sprite.flip_h = sprite.flip_h
	plant_sprite.show()
	pole.show()


func _plant_impact() -> void:
	has_checkpoint = true
	checkpoint = global_position
	cooldown = flag_cooldown
	stats.flags += 1
	# The flag goes where the pole tip hits the ground: under the hand of the last frame.
	var hand: Array = _hand.get("plant_pole", [[32, 32]]).back()
	var x := (float(hand[0]) + 0.5 - CELL / 2.0) * _mirror()
	planted.emit(Vector2(global_position.x + x, global_position.y), facing > 0.0)


func _end_plant() -> void:
	state = State.GROUND
	plant_sprite.hide()
	pole.hide()
	sprite.show()


# ---------------------------------------------------------------- helpers
func _fall_and_slide(delta: float) -> void:
	velocity.y = minf(velocity.y + gravity * delta, max_fall)
	move_and_slide()


## How many px of his feet are on the block he landed on (INF if it isn't a Block).
func _foot_overlap() -> float:
	var block := last_floor as Block
	if block == null:
		return INF
	var half: float = (shape.shape as RectangleShape2D).size.x / 2.0
	var left := maxf(global_position.x - half, block.global_position.x)
	var right := minf(global_position.x + half, block.global_position.x + block.size.x)
	return maxf(right - left, 0.0)


func _floor_collider() -> Node:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_normal().y < -0.7:
			return col.get_collider() as Node
	return null


## The pole sits in the hand of each plant frame (hand-picked points, plant_flag_hand.json):
## held low while raising and planting, twirled about its middle while spinning.
func _place_pole(anim: String, frame: int, i: int) -> void:
	var points: Array = _hand.get(anim, [])
	if frame >= points.size():
		pole.hide()
		return
	var spin := anim == "spin_pole"
	var grip: Array = _grip.get("spin" if spin else "plant", [16, 16])
	var tex_center := pole.texture.get_size() / 2.0
	pole.offset = tex_center - Vector2(float(grip[0]), float(grip[1]))
	var hand := Vector2(float(points[frame][0]) + 0.5, float(points[frame][1]) + 0.5)
	pole.position = Vector2((hand.x - CELL / 2.0) * _mirror(), hand.y - CELL / 2.0 + SPRITE_OFFSET_Y)
	# Step the twirl per frame (no smooth rotation) so it stays pixel-art; mirror when facing right.
	var steps := i - _spin_start if spin else 0
	pole.rotation_degrees = steps * SPIN_STEP_DEG * _mirror()


func _mirror() -> float:
	return -1.0 if (facing > 0.0) == ART_FACES_LEFT else 1.0


## Charge meter: INK frame, SAND fill, stage ticks at 1/3 and 2/3. The moment it fills, the bar
## turns CREAM for the perfect window, then back to SAND (a plain full jump). Pixel rects only
## (no tinting), so it stays on the NYX8 palette.
func _draw_meter() -> void:
	if state not in [State.CHARGE, State.CLING_CHARGE]:
		return
	const W := 18.0
	var x0 := -W / 2.0
	_meter.draw_rect(Rect2(x0 - 1, -1, W + 2, 4), Nyx8.INK)
	_meter.draw_rect(Rect2(x0, 0, roundf(W * charge), 2), Nyx8.CREAM if in_perfect_window() else Nyx8.SAND)
	for k in [1, 2]:
		_meter.draw_rect(Rect2(x0 + roundf(W * k / 3.0), 0, 1, 2), Nyx8.INK)


func _stage() -> int:
	return clampi(int(charge * 3.0) + 1, 1, 3)


func _dir() -> float:
	if not bot.is_empty():
		return float(bot.get("dir", 0.0))
	return Input.get_axis("move_left", "move_right")


func _jump_held() -> bool:
	if not bot.is_empty():
		return bool(bot.get("jump", false))
	return Input.is_action_pressed("jump")


func _animate() -> void:
	match state:
		State.GROUND:
			_play("walk_right" if absf(velocity.x) > 0.0 else "idle")
		State.CHARGE, State.CLING_CHARGE:
			_play("jump_charge_%d" % _stage())
		State.CLING:
			_play("jump_charge_1")  # placeholder until slap/cling frames exist
			sprite.pause()
			sprite.frame = 0
		State.LAND:
			_play("land")
		State.AIR:
			if velocity.y < 0.0:
				_play("jump")
			elif sprite.animation == &"jump":
				sprite.play("jump_stop")
			elif sprite.animation != &"jump_stop" or not sprite.is_playing() or velocity.y > 200.0:
				_play("fall")
	sprite.speed_scale = absf(velocity.x) / WALK_ANIM_PACE if sprite.animation == &"walk_right" else 1.0
	var drawn_left := ART_FACES_LEFT and not sprite.animation in DRAWN_FACING_RIGHT
	sprite.flip_h = (facing > 0.0) == drawn_left


func _play(anim: StringName) -> void:
	if sprite.animation != anim or not sprite.is_playing():
		if sprite.animation == anim and not sprite.sprite_frames.get_animation_loop(anim):
			return  # a finished one-shot holds its last frame
		sprite.play(anim)


func _squash(s: Vector2) -> void:
	if not is_inside_tree():
		return
	sprite.scale = s
	create_tween().tween_property(sprite, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
