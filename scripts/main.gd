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
@onready var sparkle: CPUParticles2D = $Steve/Sparkle  ## local coords: the burst travels with him
@onready var summit: Area2D = $Tower/Summit

## Edge-landing slow-mo: how slow, and for how long in real seconds.
const EDGE_SLOWMO_SCALE := 0.25
const EDGE_SLOWMO_SECONDS := 0.5

var _won := false
## Active time effects: [scale, until_msec]. The slowest active one wins, so a hitstop inside a
## slow-mo (or the reverse) never ends the other early. Real time: they must run while time is slow.
var _time_fx: Array = []


func _ready() -> void:
	hud.bind(steve)
	steve.jumped.connect(_on_jumped)
	steve.landed.connect(_on_landed)
	steve.bonked.connect(func() -> void: Sfx.play("bonk", randf_range(0.95, 1.1)))
	steve.slapped.connect(_on_slapped)
	steve.charge_stage.connect(func(stage: int) -> void: Sfx.play("charge_tick", 0.9 + 0.25 * stage, -6.0))
	steve.planted.connect(_on_planted)
	steve.flag_ready.connect(func() -> void: Sfx.play("flag_ready", 1.0, -4.0))
	steve.perfect_release.connect(_on_perfect)
	steve.charge_full.connect(func() -> void: Sfx.play("charge_tick", 1.9, -2.0))  # "now!": the window opens
	steve.charge_cancelled.connect(func() -> void: Sfx.play("charge_tick", 0.6, -6.0))
	steve.edge_landed.connect(_on_edge)
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


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	_time_fx = _time_fx.filter(func(fx: Array) -> bool: return fx[1] > now)
	var scale := 1.0
	for fx: Array in _time_fx:
		scale = minf(scale, fx[0])
	Engine.time_scale = scale


## Freeze the world for a beat on impacts.
func hitstop(seconds: float) -> void:
	slow_time(0.05, seconds)


## Run the world at `scale` for `seconds` of real time.
func slow_time(scale: float, seconds: float) -> void:
	_time_fx.append([scale, Time.get_ticks_msec() + int(seconds * 1000.0)])
	Engine.time_scale = minf(Engine.time_scale, scale)


func _on_perfect() -> void:
	Sfx.play("perfect", 1.0, -2.0)
	sparkle.restart()
	sparkle.emitting = true
	camera.shake(1.5, 0.1)


## A sliver of foot on the ledge: time drops to a crawl so the player sees how close it was.
func _on_edge(_overlap: float) -> void:
	Sfx.play("edge", 1.0, -2.0)
	slow_time(EDGE_SLOWMO_SCALE, EDGE_SLOWMO_SECONDS)


func _exit_tree() -> void:
	Engine.time_scale = 1.0  # never leave the next scene in slow motion


func _puff(at: Vector2, amount: int) -> void:
	dust.global_position = at
	dust.amount = maxi(amount, 1)
	dust.restart()
	dust.emitting = true
