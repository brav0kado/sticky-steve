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
	var full: float = steve.jump_v_max * steve.jump_v_max / (2.0 * steve.gravity)
	_check(absf(apexes[3] - full) < 6.0, "full charge apex %.1f ~ %.1f" % [apexes[3], full])

	# Perfect release: inside the window = bonus launch speed; before it or a full auto-release = none.
	var v_at := func(c: float) -> float: return lerpf(steve.jump_v_min, steve.jump_v_max, c)
	for case in [[0.70, false], [(steve.perfect_from + steve.perfect_to) / 2.0, true], [1.0, false]]:
		_reset(Vector2(0, 0))
		var perfect_before: int = steve.stats.perfect
		steve.bot = {"dir": 0.0, "jump": true}
		var released := false
		for i in 200:
			var c_now: float = steve.charge
			if c_now >= case[0] and not released:
				steve.bot = {"dir": 0.0, "jump": false}
				released = true
			_step()
			if steve.is_airborne():
				var expect_v: float = v_at.call(c_now if case[0] < 1.0 else 1.0) * (steve.perfect_bonus if case[1] else 1.0)
				var got_perfect: bool = steve.stats.perfect > perfect_before
				_check(got_perfect == case[1], "release at %.2f: perfect=%s" % [case[0], case[1]])
				_check(absf(-steve.velocity.y - expect_v) < 25.0, "release at %.2f: launch %.0f ~ %.0f" % [case[0], -steve.velocity.y, expect_v])
				break
	_check(steve.perfect_to < 1.0, "the window closes before full charge, so auto-release is never perfect")

	# Edge landing: a sliver of foot on a ledge fires edge_landed; a centred landing doesn't.
	for case in [[-102.0, true], [-60.0, false]]:  # ledge spans x -100..-20, Steve is 8 px wide
		_reset(Vector2(case[0], -130))
		steve.state = 2  # AIR: falls onto the ledge
		_run_until(func() -> bool: return not steve.is_airborne(), 120)
		_check(("edge" in _events) == case[1] and steve.last_floor != null and steve.global_position.y < -79.0,
			"landing at x %.0f on the ledge: edge=%s" % [case[0], case[1]])

	# A full charge releases by itself (Jump King), and charging stops walking.
	_reset(Vector2(0, 0))
	steve.bot = {"dir": 1.0, "jump": true}
	var launched_at := -1
	for i in 120:
		_step()
		if i == 5:
			_check(absf(steve.velocity.x) < 0.01, "charging stops walking")
		if launched_at < 0 and steve.is_airborne():
			launched_at = i
	var expect := int(steve.charge_time / DT)
	_check(absi(launched_at - expect) <= 2, "full charge auto-releases (tick %d ~ %d)" % [launched_at, expect])

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

	_camera_checks()

	print("STEVE pass" if _fails == 0 else "STEVE fail (%d)" % _fails)
	quit(1 if _fails else 0)


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
	steve = (load(STEVE) as PackedScene).instantiate()
	steve.set_physics_process(false)  # stepped by hand
	arena.add_child(steve)
	for sig in ["bonked", "slapped", "planted", "flag_ready", "respawned", "landed"]:
		steve.connect(sig, func(_a = null, _b = null) -> void: _events.append(sig))
	steve.edge_landed.connect(func(_o: float) -> void: _events.append("edge"))


func _block(pos: Vector2, size: Vector2, surface: int) -> void:
	var b := StaticBody2D.new()
	b.set_script(load(BLOCK))
	b.position = pos
	b.size = size
	b.surface = surface
	arena.add_child(b)


func _reset(pos: Vector2) -> void:
	steve.global_position = pos
	steve.velocity = Vector2.ZERO
	steve.state = 0
	steve.charge = 0.0
	steve.slap_ready = true
	steve.cooldown = 0.0
	steve.has_checkpoint = false
	steve.bot = {"dir": 0.0, "jump": false}
	_events.clear()
	for i in 3:
		_step()


func _charge_and_release(charge: float, dir: float) -> void:
	steve.bot = {"dir": dir, "jump": true}
	var ticks := maxi(1, roundi(charge * steve.charge_time / DT))
	for i in ticks:
		_step()
		if steve.is_airborne():
			return  # full charge released itself
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
	if cam:
		cam.tick(DT)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what)
