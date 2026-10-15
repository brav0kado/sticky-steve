extends Node2D
## The prototype world: wires Steve's signals to everything that reacts to him (camera shake,
## hitstop, dust, sound, the planted flag, the HUD, the summit). Steve and the camera don't know
## about each other's juice; this is the one place that decides how a moment feels.

const FLAG_FRAMES := "res://art/flag/flag_frames.tres"
const FLAG_BASE := Vector2(25, 31)  ## flag.png: pixel at the bottom of its pole (32x32 cell)

@onready var steve: Steve = $Steve
@onready var camera: Camera2D = $Camera
@onready var hud: CanvasLayer = $HUD
@onready var flags: Node2D = $Flags
@onready var dust: CPUParticles2D = $Dust
@onready var summit: Area2D = $Tower/Summit

var _won := false
var _stop_until := 0


func _ready() -> void:
	hud.bind(steve)
	steve.jumped.connect(_on_jumped)
	steve.landed.connect(_on_landed)
	steve.bonked.connect(func() -> void: Sfx.play("bonk", randf_range(0.95, 1.1)))
	steve.slapped.connect(_on_slapped)
	steve.charge_stage.connect(func(stage: int) -> void: Sfx.play("charge_tick", 0.9 + 0.25 * stage, -6.0))
	steve.planted.connect(_on_planted)
	steve.flag_ready.connect(func() -> void: Sfx.play("flag_ready", 1.0, -4.0))
	steve.respawned.connect(func() -> void:
		Sfx.play("respawn", 1.0, -4.0)
		camera.reset_physics_interpolation())
	summit.body_entered.connect(_on_summit)


func _unhandled_input(event: InputEvent) -> void:
	if _won and event.is_action_pressed("ui_accept"):
		get_tree().reload_current_scene()


func _on_jumped(charge: float) -> void:
	Sfx.play("jump", 0.85 + 0.35 * charge, -3.0)
	_puff(steve.global_position, 4 + int(6 * charge))


func _on_landed(fall: float, hard: bool) -> void:
	if hard:
		Sfx.play("land_hard")
		camera.shake(clampf(fall / 80.0, 2.0, 5.0))
		hitstop(0.06)
		_puff(steve.global_position, 14)
	else:
		Sfx.play("land", randf_range(0.95, 1.1), -4.0)
		_puff(steve.global_position, 5)


func _on_slapped() -> void:
	Sfx.play("slap", randf_range(0.95, 1.08))
	camera.shake(2.0, 0.12)
	hitstop(0.05)


func _on_planted(base: Vector2, faces_right: bool) -> void:
	# Planting moves the checkpoint, so only the newest flag stands.
	for old in flags.get_children():
		old.queue_free()
	var flag := AnimatedSprite2D.new()
	flag.sprite_frames = load(FLAG_FRAMES)
	flag.centered = false
	flag.flip_h = faces_right
	var bx := (31.0 - FLAG_BASE.x) if faces_right else FLAG_BASE.x
	flag.position = base - Vector2(bx, FLAG_BASE.y + 1.0)
	flags.add_child(flag)
	flag.play("flag_wave")
	Sfx.play("plant")
	Sfx.play("plant_ring", 1.0, -8.0)
	camera.shake(4.0, 0.3)
	hitstop(0.09)
	_puff(base, 16)


func _on_summit(body: Node2D) -> void:
	if body != steve or _won:
		return
	_won = true
	Sfx.play("summit")
	hud.show_summit()


## Freeze the world for a beat on impacts. Overlapping calls extend one shared end time, so an
## early one can't unfreeze a later one. Waits on render frames: they keep coming while time is slow.
func hitstop(seconds: float) -> void:
	_stop_until = maxi(_stop_until, Time.get_ticks_msec() + int(seconds * 1000.0))
	Engine.time_scale = 0.05
	while is_inside_tree() and Time.get_ticks_msec() < _stop_until:
		await get_tree().process_frame
	Engine.time_scale = 1.0


func _exit_tree() -> void:
	Engine.time_scale = 1.0  # never leave the next scene in slow motion


func _puff(at: Vector2, amount: int) -> void:
	dust.global_position = at
	dust.amount = maxi(amount, 1)
	dust.restart()
	dust.emitting = true
