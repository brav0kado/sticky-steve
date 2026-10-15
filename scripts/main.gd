extends Node2D
## The world: wires Steve's signals to everything that reacts to him (camera, time, dust, sound,
## popups, the planted flag, gems, zones, records, the summit). Steve and the camera don't know
## about each other's juice; this is the one place that decides how a moment feels.
##
## Feel budget (research: medium juice beats none AND extreme): every effect answers a player
## action and says something (how big, how close, how good). Big moments stack effects; routine
## ones (a short hop, a normal landing) stay quiet so the big ones stand out.

const FLAG_FRAMES := "res://art/flag/flag_frames.tres"
const FLAG_BASE := Vector2(25, 31)  ## flag.png: pixel at the bottom of its pole (32x32 cell)
const PX_PER_M := 12.0
const ZONE_TILES := "res://art/world/zone%d_tiles.png"  ## Martin's tile sheet per zone (art spec)
## Edge-landing slow-mo: how slow, and for how long in real seconds.
const EDGE_SLOWMO_SCALE := 0.25
const EDGE_SLOWMO_SECONDS := 0.5
const SAVE_SLOWMO_SECONDS := 0.35
const GEM_CHAIN_SECONDS := 3.0  ## gems taken this close together climb in pitch

@export var par_seconds := 150.0  ## the rank's time target

@onready var steve: Steve = $Steve
@onready var camera: Camera2D = $Camera
@onready var hud: CanvasLayer = $HUD
@onready var flags: Node2D = $Flags
@onready var dust: CPUParticles2D = $Dust
@onready var sparkle: CPUParticles2D = $Steve/Sparkle  ## local coords: the burst travels with him
@onready var tower: Node2D = $Tower
@onready var summit: Area2D = $Tower/Summit
@onready var best_line: Node2D = $BestLine

var _won := false
## Active time effects: [scale, until_msec]. The slowest active one wins, so a hitstop inside a
## slow-mo (or the reverse) never ends the other early. Real time: they must run while time is slow.
var _time_fx: Array = []
var _zones: Array = []  # Zone nodes, lowest first
var _zone_reached := 1
var _gems_run := 0
var _gems_total := 0
var _gem_chain := 0
var _gem_chain_until := 0
var _new_best_shown := false
var _start_best_m := 0.0


func _ready() -> void:
	steve.flags_enabled = Profile.mode == "flags"
	hud.flags_enabled = steve.flags_enabled
	_start_best_m = Profile.bests().best_height_m
	for g in tower.find_children("*", "Area2D", true, false):
		if g is Gem:
			_gems_total += 1
			g.known = Profile.has_gem(g.gem_id())
			g.collected.connect(_on_gem)
	_zones = tower.find_children("*", "Node2D", true, false).filter(func(n: Node) -> bool: return n is Zone)
	_zones.sort_custom(func(a: Zone, b: Zone) -> bool: return a.index < b.index)
	_skin_blocks()
	hud.bind(steve, _gems_total, _start_best_m)
	best_line.set_meta("y", steve.global_position.y - _start_best_m * PX_PER_M)
	best_line.draw.connect(_draw_best_line)
	best_line.visible = _start_best_m > 2.0
	hud.best_m_at_start = _start_best_m
	if best_line.visible:
		hud.best_line_y = best_line.get_meta("y")
	steve.jumped.connect(_on_jumped)
	steve.landed.connect(_on_landed)
	steve.bonked.connect(func() -> void: Sfx.play("bonk", randf_range(0.95, 1.1)))
	steve.slapped.connect(_on_slapped)
	steve.charge_stage.connect(func(stage: int) -> void: Sfx.play("charge_tick", 0.9 + 0.25 * stage, -6.0))
	steve.charge_full.connect(func() -> void: Sfx.play("charge_tick", 1.9, -2.0))  # "now!": the window opens
	steve.charge_cancelled.connect(func() -> void: Sfx.play("charge_tick", 0.6, -6.0))
	steve.planted.connect(_on_planted)
	steve.flag_ready.connect(func() -> void: Sfx.play("flag_ready", 1.0, -4.0))
	steve.perfect_release.connect(_on_perfect)
	steve.streak_broken.connect(func(n: int) -> void:
		if n >= 2:
			popup("streak %d" % n, steve.global_position + Vector2(0, -40), 10))
	steve.edge_landed.connect(_on_edge)
	steve.bounced.connect(_on_bounced)
	steve.clutch_save.connect(_on_save)
	steve.fell.connect(_on_fell)
	steve.respawned.connect(func() -> void:
		Sfx.play("respawn", 1.0, -4.0)
		camera.reset_physics_interpolation())
	steve.plant_refused.connect(_on_plant_refused)
	summit.body_entered.connect(_on_summit)
	if _zones.size() > 0:
		hud.banner("%d  %s" % [_zones[0].index, _zones[0].title])


func _unhandled_input(event: InputEvent) -> void:
	if _won and event.is_action_pressed("ui_accept"):
		get_tree().reload_current_scene()
	elif _won and event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/title.tscn")


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	_time_fx = _time_fx.filter(func(fx: Array) -> bool: return fx[1] > now)
	var scale := 1.0
	for fx: Array in _time_fx:
		scale = minf(scale, fx[0])
	Engine.time_scale = scale
	_check_zones()
	_check_best()


# ---------------------------------------------------------------- moments
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


## A slap that catches a real fall: the rescue. Heavier slap, slow-mo, a word.
func _on_save(fall: float) -> void:
	Sfx.play("slap", 0.8)
	slow_time(0.3, SAVE_SLOWMO_SECONDS)
	camera.shake(3.0, 0.2)
	popup("SAVE!", steve.global_position + Vector2(0, -34), 16)
	_puff(steve.global_position + Vector2(-steve.wall_normal * 4.0, -10), 10)
	if fall > 200.0:
		popup("%d m" % roundi(fall / PX_PER_M), steve.global_position + Vector2(0, -20), 10)


## Each perfect in a row climbs a step in pitch and the word grows: the streak you don't want to break.
func _on_perfect(streak: int) -> void:
	Sfx.play("perfect", 1.0 + 0.08 * mini(streak - 1, 8), -2.0)
	sparkle.amount = 10 + 4 * mini(streak, 6)
	sparkle.restart()
	sparkle.emitting = true
	camera.shake(1.5, 0.1)
	var text := "PERFECT" if streak < 2 else "PERFECT x%d" % streak
	popup(text, steve.global_position + Vector2(0, -36), 12 + mini(streak, 5) * 2)


## A sliver of foot on the ledge: time drops to a crawl so the player sees how close it was.
func _on_edge(_overlap: float) -> void:
	Sfx.play("edge", 1.0, -2.0)
	slow_time(EDGE_SLOWMO_SCALE, EDGE_SLOWMO_SECONDS)
	popup("close!", steve.global_position + Vector2(0, -32), 10)


func _on_bounced(_block: Block) -> void:
	Sfx.play("jump", 1.4, -2.0)
	Sfx.play("bonk", 0.7, -6.0)
	camera.shake(1.5, 0.12)
	_puff(steve.global_position, 8)


## Falls are part of the show: say how far, so a disaster is at least a story.
func _on_fell(px: float) -> void:
	var m := roundi(px / PX_PER_M)
	if m >= 4:
		popup("-%d m" % m, steve.global_position + Vector2(0, -30), 10 + mini(m, 30) / 3)


func _on_gem(gem: Gem) -> void:
	_gems_run += 1
	hud.gems = _gems_run
	var now := Time.get_ticks_msec()
	_gem_chain = _gem_chain + 1 if now < _gem_chain_until else 1
	_gem_chain_until = now + int(GEM_CHAIN_SECONDS * 1000.0)
	var first := Profile.add_gem(gem.gem_id())
	Sfx.play("perfect", 1.3 + 0.1 * mini(_gem_chain - 1, 6), 0.0)
	Sfx.play("flag_ready", 1.2, -8.0)
	popup("NEW GEM!" if first else "gem", gem.global_position + Vector2(0, -12), 12 if first else 10)
	_puff(gem.global_position, 8)
	hitstop(0.04)


func _on_plant_refused(reason: String) -> void:
	var why: String = {"cooldown": "flag in %ds" % ceili(steve.cooldown), "air": "land to plant",
		"noflag": "no flags this climb"}.get(reason, "")
	popup(why, steve.global_position + Vector2(0, -34), 13)
	Sfx.play("charge_tick", 0.5, -6.0)


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
	Sfx.play("plant")  # locked by Martin (design note): don't change
	Sfx.play("plant_ring", 1.0, -8.0)
	camera.shake(4.0, 0.3)
	hitstop(0.09)
	_puff(base, 16)
	Profile.save()


func _on_summit(body: Node2D) -> void:
	if body != steve or _won:
		return
	_won = true
	$Pause.blocked = true  # the run is over: Esc means "to the title" on the card
	Sfx.play("summit")
	var t: float = hud.elapsed
	var s: Dictionary = steve.stats
	var best_before: float = Profile.bests().best_time
	var new_best: bool = Profile.record_finish(t, s.best_streak)
	var records := []
	if new_best:
		records.append("NEW BEST TIME" if best_before > 0.0 else "FIRST CLIMB")
	elif best_before > 0.0:
		records.append("best %s  (+%.1f s)" % [hud.clock(best_before), t - best_before])
	var checks := [
		["under %s" % hud.clock(par_seconds), t <= par_seconds],
		["no falls", s.falls == 0],
		["all %d gems this run" % _gems_total, _gems_run >= _gems_total and _gems_total > 0],
		["a streak of 3 perfects", s.best_streak >= 3],
	]
	var passed := checks.filter(func(c: Array) -> bool: return c[1]).size()
	if Profile.mode == "noflag":
		records.push_front("NO FLAGS")
	hud.show_summit(["D", "C", "B", "A", "S"][passed], checks, records)


## Each block wears its zone's tile sheet (the zone its centre is in); a zone without a sheet
## keeps the greybox look, so art can arrive one zone at a time.
func _skin_blocks() -> void:
	var sheets := {}
	for z: Zone in _zones:
		var path := ZONE_TILES % z.index
		if ResourceLoader.exists(path):
			sheets[z.index] = load(path)
	for b in tower.get_children():
		if b is Block:
			b.skin = sheets.get(zone_at(b.global_position.y + b.size.y / 2.0))


## The zone (index) a world y is in: the highest zone whose start line is at or below it.
func zone_at(y: float) -> int:
	var idx := 1
	for z: Zone in _zones:
		if y <= z.global_position.y:
			idx = z.index
	return idx


# ---------------------------------------------------------------- progress
## Crossing into a new zone: its banner, and the split against the best split for that zone.
func _check_zones() -> void:
	if _won:
		return
	for z: Zone in _zones:
		if z.index > _zone_reached and steve.global_position.y < z.global_position.y:
			_zone_reached = z.index
			var delta: float = Profile.record_split(z.index, hud.elapsed)  # 0 = first time here
			var split: String = hud.clock(hud.elapsed)
			if delta < 0.0:
				split += "   best!  %.1f s" % delta
			elif delta > 0.0:
				split += "   +%.1f s" % delta
			hud.banner("%d  %s\n%s" % [z.index, z.title, split])
			Sfx.play("flag_ready", 0.8, -2.0)
			Profile.save()


## Passing the best height ever: once per run, the line breaks and the banner says so.
func _check_best() -> void:
	var m: float = hud.height_m()
	if Profile.record_height(m) and not _new_best_shown and _start_best_m > 2.0:
		_new_best_shown = true
		best_line.hide()
		hud.best_line_y = NAN
		hud.banner("NEW BEST HEIGHT")
		Sfx.play("summit", 1.4, -6.0)
		camera.shake(2.0, 0.15)


func _draw_best_line() -> void:
	var y: float = best_line.get_meta("y")
	var x := -200.0
	while x < 840.0:
		best_line.draw_rect(Rect2(x, y, 6, 2), Nyx8.SAND)
		x += 10.0  # the label is the HUD's (screen space, readable at any zoom)


# ---------------------------------------------------------------- effects
## Floating text over the world (the HUD draws it in screen space: readable at any zoom).
func popup(text: String, at: Vector2, size: int) -> void:
	hud.popup(text, at, size)


func hitstop(seconds: float) -> void:
	slow_time(0.05, seconds)


## Run the world at `scale` for `seconds` of real time.
func slow_time(scale: float, seconds: float) -> void:
	_time_fx.append([scale, Time.get_ticks_msec() + int(seconds * 1000.0)])
	Engine.time_scale = minf(Engine.time_scale, scale)


func _exit_tree() -> void:
	Engine.time_scale = 1.0  # never leave the next scene in slow motion
	Profile.save()


func _puff(at: Vector2, amount: int) -> void:
	dust.global_position = at
	dust.amount = maxi(amount, 1)
	dust.restart()
	dust.emitting = true
	dust.reset_physics_interpolation()
