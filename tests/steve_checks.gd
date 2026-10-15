extends SceneTree
## Steve's rules, stepped frame by frame in a built arena (floor, plain wall, sticky wall, ledge),
## with a bot standing in for the player. One check per decided design rule.
##   godot --headless --path . -s res://tests/steve_checks.gd   -> "STEVE pass" or FAILs

const DT := 1.0 / 60.0
const STEVE := "res://scenes/steve.tscn"
const BLOCK := "res://scripts/block.gd"
const CAMERA := "res://scripts/game_camera.gd"

var _fails := 0
var arena: Node2D
var steve: CharacterBody2D
var cam: Camera2D
var crumble: StaticBody2D
var _events: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_build_arena()
	await physics_frame  # shapes enter the physics space
	await physics_frame

	# Charge sets the height: more charge, higher apex; full charge = v_max²/2g.
	var apexes: Array[float] = []
	for c in [0.0, 0.33, 0.66, 1.0]:
		apexes.append(_apex_for(c))
	_check(apexes[0] > 4.0, "a tap still jumps (%.1f px)" % apexes[0])
	_check(apexes[0] < apexes[1] and apexes[1] < apexes[2] and apexes[2] < apexes[3], "apex rises with charge %s" % [apexes])
	# Apex hang: normal gravity until |vy| < apex_band, then apex_gravity times it.
	var vb: float = steve.apex_band
	var full: float = (steve.jump_v_max * steve.jump_v_max - vb * vb) / (2.0 * steve.gravity) \
			+ vb * vb / (2.0 * steve.gravity * steve.apex_gravity)
	_check(absf(apexes[3] - full) < 6.0, "full charge apex %.1f ~ %.1f" % [apexes[3], full])

	# Perfect release: let go within perfect_window of the charge filling = full jump + bonus.
	# Before full, or after hovering past the window = no bonus.
	var v_full: float = steve.jump_v_max
	var window_ticks := int(steve.perfect_window / DT)
	for case in [["before full", -10, false], ["as it fills", 2, true], ["hovered past", window_ticks + 6, false]]:
		_reset(Vector2(0, 0))
		var perfect_before: int = steve.stats.perfect
		steve.bot = {"dir": 0.0, "jump": true}
		var full_at := roundi(steve.charge_time / DT)
		for i in maxi(1, full_at + int(case[1])):
			_step()
		var c_released: float = steve.charge
		steve.bot = {"dir": 0.0, "jump": false}
		_step()
		var expect_v: float = lerpf(steve.jump_v_min, v_full, c_released) * (steve.perfect_bonus if case[2] else 1.0)
		_check(steve.is_airborne(), "%s: released = jumped" % case[0])
		_check((steve.stats.perfect > perfect_before) == case[2], "%s: perfect=%s" % [case[0], case[2]])
		_check(absf(-steve.velocity.y - expect_v) < 25.0, "%s: launch %.0f ~ %.0f" % [case[0], -steve.velocity.y, expect_v])
	_check(steve.perfect_bonus > 1.0, "a perfect jump beats a plain full jump")

	# Edge landing: a sliver of foot on a ledge fires edge_landed; a centred landing doesn't.
	for case in [[-102.0, true], [-60.0, false]]:  # ledge spans x -100..-20, Steve is 8 px wide
		_reset(Vector2(case[0], -130))
		steve.state = 2  # AIR: falls onto the ledge
		_run_until(func() -> bool: return not steve.is_airborne(), 120)
		_check(("edge" in _events) == case[1] and steve.last_floor != null and steve.global_position.y < -79.0,
			"landing at x %.0f on the ledge: edge=%s" % [case[0], case[1]])

	# Stages: each lasts stage_seconds with its animation looping. Full charge hovers on stage 3
	# with no auto-release; charging stops walking.
	_reset(Vector2(0, 0))
	steve.bot = {"dir": 1.0, "jump": true}
	var stage_ticks := roundi(steve.stage_seconds / DT)
	var seen := {}
	for i in stage_ticks * 3 + 240:  # three stages, then 4 s of hovering
		_step()
		if i == 5:
			_check(absf(steve.velocity.x) < 0.01, "charging stops walking")
		if i == stage_ticks / 2:
			seen[1] = steve.sprite.animation
		if i == stage_ticks + stage_ticks / 2:
			seen[2] = steve.sprite.animation
		if i == stage_ticks * 2 + stage_ticks / 2:
			seen[3] = steve.sprite.animation
	_check(seen.get(1) == &"jump_charge_1" and seen.get(2) == &"jump_charge_2" and seen.get(3) == &"jump_charge_3",
		"each stage lasts %.1f s with its own animation %s" % [steve.stage_seconds, seen])
	_check(steve.state == 1 and steve.charge >= 1.0 and steve.sprite.animation == &"jump_charge_3" and steve.sprite.is_playing(),
		"full charge hovers on stage 3, looping, no auto-release")

	# Cancel drops the charge without jumping: back to standing, or back to hanging on a wall.
	steve.request_cancel()
	_step()
	_check(steve.state == 0 and steve.charge == 0.0 and not steve.is_airborne(), "cancel on the ground: standing, no jump")
	steve.bot = {"dir": 0.0, "jump": false}
	_step()

	# Walking uses walk_right (drawn facing right) mirrored for left; idle then faces the same way.
	_reset(Vector2(0, 0))
	steve.bot = {"dir": 1.0, "jump": false}
	for i in 4:
		_step()
	_check(steve.sprite.animation == &"walk_right" and not steve.sprite.flip_h, "walking right plays walk_right as drawn")
	_check(absf(steve.velocity.x - steve.walk_speed) < 0.01, "walks at walk_speed (%.0f)" % steve.velocity.x)
	_check(is_equal_approx(steve.sprite.speed_scale, steve.walk_speed / 70.0), "walk cycle speeds up with the walk (no foot sliding)")
	steve.bot = {"dir": 0.0, "jump": false}
	_step()
	_check(steve.sprite.animation == &"idle" and steve.sprite.flip_h, "stopping after walking right: idle faces right (flipped)")
	steve.bot = {"dir": -1.0, "jump": false}
	for i in 4:
		_step()
	_check(steve.sprite.animation == &"walk_right" and steve.sprite.flip_h, "walking left mirrors walk_right")
	steve.bot = {"dir": 0.0, "jump": false}
	_step()
	_check(steve.sprite.animation == &"idle" and not steve.sprite.flip_h, "stopping after walking left: idle as drawn")

	# Air control is an acceleration, not a set: reversing takes time.
	_reset(Vector2(0, 0))
	_charge_and_release(1.0, 0.0)
	steve.bot = {"dir": 1.0, "jump": false}
	for i in 6:
		_step()
	_check(steve.velocity.x > 0.0 and steve.velocity.x < 0.3 * steve.air_speed, "air control ramps (vx %.1f after 0.1 s)" % steve.velocity.x)

	# A plain wall bounces him back.
	_reset(Vector2(-150, 0))  # plain wall's face is at x = -200
	_charge_and_release(0.5, -1.0)
	var bounced := _run_until(func() -> bool: return steve.velocity.x > 0.0 and steve.is_airborne(), 90)
	_check(bounced and "bonked" in _events, "plain wall bounces him back")

	# Sticky wall: holding toward it on contact slaps on; one slap per airtime; landing restores it.
	_reset(Vector2(150, 0))  # sticky wall's face is at x = 200
	_charge_and_release(0.6, 1.0)
	steve.bot = {"dir": 1.0, "jump": false}
	var clung := _run_until(func() -> bool: return steve.state == 3, 90)  # State.CLING
	_check(clung and "slapped" in _events, "holding toward a sticky wall slaps on")
	_check(steve.velocity == Vector2.ZERO and not steve.slap_ready, "slap kills momentum and uses the slap")
	var y_cling := steve.global_position.y
	for i in 30:
		_step()
	_check(absf(steve.global_position.y - y_cling) < 0.5, "he hangs without sliding")
	steve.bot = {"dir": 0.0, "jump": true}
	for i in 20:
		_step()
	steve.request_cancel()
	_step()
	_check(steve.state == 3 and steve.charge == 0.0, "cancel on a wall: back to hanging")
	steve.bot = {"dir": 0.0, "jump": false}
	_step()
	steve.bot = {"dir": 0.0, "jump": true}
	for i in 15:
		_step()
	steve.bot = {"dir": 1.0, "jump": false}  # holding INTO the wall doesn't change the launch
	_step()
	_check(steve.velocity.x < 0.0 and steve.velocity.y < 0.0, "wall jump goes up and away from the wall")
	_run_until(func() -> bool: return not steve.is_airborne(), 240)
	_check(steve.slap_ready, "landing restores the slap")

	# One slap per airtime: let go of the wall, steer straight back into it: no second slap.
	_reset(Vector2(150, 0))
	_charge_and_release(1.0, 1.0)
	steve.bot = {"dir": 1.0, "jump": false}
	_run_until(func() -> bool: return steve.state == 3, 90)
	steve.bot = {"dir": -1.0, "jump": false}  # push away: let go
	_step()
	_events.clear()
	steve.bot = {"dir": 1.0, "jump": false}  # and straight back in
	var second := _run_until(func() -> bool: return steve.state == 3 or "bonked" in _events or not steve.is_airborne(), 120)
	_check(second and steve.state != 3 and steve.is_airborne(), "second sticky contact in one airtime doesn't slap (state %d)" % steve.state)

	# Without holding toward it, a sticky wall is just a wall.
	_reset(Vector2(150, 0))
	_charge_and_release(0.6, 1.0)
	steve.bot = {"dir": 0.0, "jump": false}
	_run_until(func() -> bool: return "bonked" in _events or steve.state == 3, 90)
	_check(steve.state != 3 and "bonked" in _events, "no hold toward the wall = no slap")

	# Flag: plant on the ledge -> checkpoint + cooldown; can't plant again until it runs out.
	_reset(Vector2(-60, -80))  # on the ledge (top y = -80)
	_run_until(func() -> bool: return steve.is_on_floor(), 30)
	steve.request_plant()
	_step()
	_check(steve.state == 6, "F on the ground starts the plant")  # State.PLANT
	var pole_seen := false
	var spin_angles := {}
	for i in 200:
		_step()
		if steve.pole.visible:
			pole_seen = true
			if steve.plant_sprite.animation == &"spin_pole":
				spin_angles[roundi(steve.pole.rotation_degrees)] = true
		if steve.state == 0:
			break
	_check(pole_seen and spin_angles.size() >= 5, "the pole is shown and twirls (%d angles)" % spin_angles.size())
	_check("planted" in _events and steve.has_checkpoint, "planting sets the checkpoint")
	_check(absf(steve.cooldown - (steve.flag_cooldown - 0.2)) < 0.25, "cooldown starts at %.0f s" % steve.flag_cooldown)
	steve.request_plant()
	_step()
	_check(steve.state != 6, "can't plant during the cooldown")
	steve.cooldown = DT
	_events.clear()
	_step()
	_check("flag_ready" in _events, "flag_ready fires when the cooldown ends")

	# Landing below the flag sends him back to it.
	var flag_at: Vector2 = steve.checkpoint
	_events.clear()
	steve.global_position = Vector2(60, -40)
	steve.reset_physics_interpolation()
	steve.state = 2  # State.AIR, falling onto the floor below the ledge
	steve.bot = {"dir": 0.0, "jump": false}
	_run_until(func() -> bool: return "respawned" in _events, 120)
	_check("respawned" in _events and steve.global_position.distance_to(flag_at) < 0.5, "landing below the flag respawns at it")

	_forgiveness_checks()
	_surface_checks()
	_streak_checks()
	_camera_checks()

	print("STEVE pass" if _fails == 0 else "STEVE fail (%d)" % _fails)
	quit(1 if _fails else 0)


## Celeste-style forgiveness: buffered charge, the hang at the apex, the heavier fall, corners.
func _forgiveness_checks() -> void:
	# Holding jump as he lands starts the charge on the landing frame (no dead land-lock).
	_reset(Vector2(0, -60))
	steve.state = 2  # AIR, a short drop
	steve.bot = {"dir": 0.0, "jump": true}
	_run_until(func() -> bool: return steve.state != 2, 120)
	_step()
	_check(steve.state == 1, "jump held while landing: the charge starts at once (state %d)" % steve.state)
	steve.bot = {"dir": 0.0, "jump": false}
	_run_until(func() -> bool: return not steve.is_airborne() and steve.state in [0, 5], 200)

	# Gravity: half near the apex, more on the way down.
	_reset(Vector2(0, 0))
	_charge_and_release(1.0, 0.0)
	var dv_rise := 0.0
	var dv_apex := 0.0
	var dv_fall := 0.0
	for i in 200:
		var v0: float = steve.velocity.y
		_step()
		if not steve.is_airborne():
			break
		var dv: float = steve.velocity.y - v0
		if v0 < -100.0:
			dv_rise = dv
		elif absf(v0) < steve.apex_band * 0.8:
			dv_apex = dv
		elif v0 > 100.0 and v0 < steve.max_fall - 30.0:
			dv_fall = dv
	_check(dv_apex > 0.0 and dv_apex < dv_rise * 0.6, "apex hang: gravity eases at the top (%.1f vs %.1f per tick)" % [dv_apex, dv_rise])
	_check(dv_fall > dv_rise * 1.15, "falling is heavier than rising (%.1f vs %.1f per tick)" % [dv_fall, dv_rise])

	# Corner correction: clipping a ceiling corner by 2 px slides him round it, the jump goes on.
	_reset(Vector2(98, 0))  # his right edge (x+4) is 2 px under the ceiling block's left corner
	var y0 := steve.global_position.y
	_charge_and_release(1.0, 0.0)
	var top := y0
	for i in 120:
		_step()
		top = minf(top, steve.global_position.y)
	# Blocked, he would stop at ~74 px (head on the ceiling); corrected, he keeps the full jump.
	_check(y0 - top > 110.0 and steve.global_position.x < 97.0, "clipped corner: nudged round it, rose %.0f px" % (y0 - top))
	_run_until(func() -> bool: return not steve.is_airborne(), 200)


## Bounce pads, crumbling ledges, the save.
func _surface_checks() -> void:
	# Bouncy: landing on the pad flings him up at bounce_speed and refreshes the slap.
	_reset(Vector2(255, -80))
	steve.slap_ready = false
	steve.state = 2
	var bounced := _run_until(func() -> bool: return "bounced" in _events, 120)
	_check(bounced and steve.is_airborne() and steve.velocity.y < -500.0, "pad flings him up (vy %.0f)" % steve.velocity.y)
	_check(steve.slap_ready, "a bounce refreshes the slap")
	_run_until(func() -> bool: return not steve.is_airborne() and "landed" in _events, 300)

	# Crumble: stand on it, it shakes for crumble_delay, then he drops; it comes back later.
	_reset(Vector2(360, -100))
	steve.state = 2
	_run_until(func() -> bool: return steve.state in [0, 5], 30)
	_check(steve.last_floor == crumble, "standing on the crumble ledge")
	var drop_tick := -1
	for i in roundi((crumble.crumble_delay + 0.5) / DT):
		_step()
		if drop_tick < 0 and steve.is_airborne():
			drop_tick = i
	_check(drop_tick > 0 and absf(drop_tick * DT - crumble.crumble_delay) < 0.1, "the ledge drops after %.1f s (%.2f)" % [crumble.crumble_delay, drop_tick * DT])
	_run_until(func() -> bool: return not steve.is_airborne(), 200)
	_reset(Vector2(0, 0))  # out of the way so it may regrow
	for i in roundi((crumble.regrow_delay + 0.3) / DT):
		_step()
	_check(crumble.is_solid_now() and crumble.visible, "the crumble ledge regrows")

	# The save: a slap that catches a real fall.
	_reset(Vector2(150, -300))
	steve.state = 2
	steve.bot = {"dir": 1.0, "jump": false}
	_run_until(func() -> bool: return steve.state == 3, 120)
	_check("clutch_save" in _events, "slapping a wall mid-fall counts as a SAVE")
	steve.bot = {"dir": -1.0, "jump": false}
	_run_until(func() -> bool: return not steve.is_airborne(), 200)


## Streak: back-to-back perfects count up; a short jump doesn't touch it; a late full one breaks it.
func _streak_checks() -> void:
	_reset(Vector2(0, 0))
	steve.stats.streak = 0
	for k in 2:
		steve.bot = {"dir": 0.0, "jump": true}
		_run_until(func() -> bool: return steve.charge >= 1.0, 120)
		steve.bot = {"dir": 0.0, "jump": false}
		_step()
		_run_until(func() -> bool: return not steve.is_airborne() and steve.state == 0, 200)
	_check(steve.stats.streak == 2 and "perfect2" in _events, "two perfects in a row: streak 2")
	_charge_and_release(0.5, 0.0)
	_run_until(func() -> bool: return not steve.is_airborne() and steve.state == 0, 200)
	_check(steve.stats.streak == 2, "a short jump leaves the streak alone")
	_charge_and_release(1.0, 0.0)  # held past the flash
	_run_until(func() -> bool: return not steve.is_airborne() and steve.state == 0, 200)
	_check(steve.stats.streak == 0 and "streak_broken" in _events, "a late full jump breaks the streak")


## The camera spec: widens more for a bigger jump, never zooms in mid-air, rests at exactly 1.0.
func _camera_checks() -> void:
	cam = Camera2D.new()
	cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS  # what physics interpolation needs
	cam.set_script(load(CAMERA))
	cam.target_path = steve.get_path()
	arena.add_child(cam)
	var widest := {}
	for c in [0.3, 1.0]:
		_reset(Vector2(0, 0))
		cam.zoom = Vector2.ONE
		cam.air_zoom = 1.0
		_charge_and_release(c, 0.0)
		var lowest := 1.0
		var zoomed_in_midair := false
		var prev := cam.zoom.x
		for i in 240:
			_step()
			if steve.is_airborne():
				zoomed_in_midair = zoomed_in_midair or cam.zoom.x > prev + 0.0001
				lowest = minf(lowest, cam.zoom.x)
			prev = cam.zoom.x
		widest[c] = lowest
		_check(not zoomed_in_midair, "charge %.1f: never zooms in while airborne" % c)
		_check(cam.zoom.x == 1.0, "charge %.1f: rests at exactly 1.0 after landing (%.4f)" % [c, cam.zoom.x])
	_check(widest[1.0] < widest[0.3] - 0.1, "a full jump widens the view more (%.2f vs %.2f)" % [widest[1.0], widest[0.3]])


# ---------------------------------------------------------------- helpers
func _build_arena() -> void:
	arena = Node2D.new()
	root.add_child(arena)
	_block(Vector2(-400, 0), Vector2(800, 40), 0)  # floor, top at y = 0
	_block(Vector2(-220, -400), Vector2(20, 400), 0)  # plain wall, face at x = -200
	_block(Vector2(200, -400), Vector2(20, 400), 1)  # sticky wall, face at x = 200
	_block(Vector2(-100, -80), Vector2(80, 16), 0)  # ledge for the flag
	_block(Vector2(240, -12), Vector2(30, 12), 2)  # bouncy pad, top at y = -12
	crumble = _block(Vector2(330, -100), Vector2(60, 16), 3)  # crumble ledge, top at y = -100
	_block(Vector2(100, -110), Vector2(40, 16), 0)  # ceiling, bottom at y = -94: left corner at x = 100
	steve = (load(STEVE) as PackedScene).instantiate()
	steve.set_physics_process(false)  # stepped by hand
	arena.add_child(steve)
	for sig in ["bonked", "slapped", "planted", "flag_ready", "respawned", "landed", "clutch_save", "fell", "streak_broken"]:
		steve.connect(sig, func(_a = null, _b = null) -> void: _events.append(sig))
	steve.edge_landed.connect(func(_o: float) -> void: _events.append("edge"))
	steve.bounced.connect(func(_b: Node) -> void: _events.append("bounced"))
	steve.perfect_release.connect(func(n: int) -> void: _events.append("perfect%d" % n))


func _block(pos: Vector2, size: Vector2, surface: int) -> StaticBody2D:
	var b := StaticBody2D.new()
	b.set_script(load(BLOCK))
	b.position = pos
	b.size = size
	b.surface = surface
	arena.add_child(b)
	b.set_physics_process(false)  # stepped with Steve
	return b


func _reset(pos: Vector2) -> void:
	steve.global_position = pos
	steve.velocity = Vector2.ZERO
	steve.state = 0
	steve.charge = 0.0
	steve.slap_ready = true
	steve.cooldown = 0.0
	steve.has_checkpoint = false
	steve.bot = {"dir": 0.0, "jump": false}
	crumble._set_gone(false)
	_events.clear()
	for i in 3:
		_step()


## A full charge is held past the perfect window, so helpers never get the perfect bonus.
func _charge_and_release(charge: float, dir: float) -> void:
	steve.bot = {"dir": dir, "jump": true}
	var ticks := maxi(1, roundi(charge * steve.charge_time / DT))
	if charge >= 1.0:
		ticks += ceili(steve.perfect_window / DT) + 2
	for i in ticks:
		_step()
	steve.bot = {"dir": dir, "jump": false}
	_step()


func _apex_for(charge: float) -> float:
	_reset(Vector2(0, 0))
	var y0 := steve.global_position.y
	_charge_and_release(charge, 0.0)
	var top := y0
	for i in 200:
		_step()
		top = minf(top, steve.global_position.y)
		if not steve.is_airborne():
			break
	return y0 - top


func _run_until(cond: Callable, max_ticks: int) -> bool:
	for i in max_ticks:
		_step()
		if cond.call():
			return true
	return false


func _step() -> void:
	steve.tick(DT)
	crumble.tick(DT)
	if cam:
		cam.tick(DT)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what)
