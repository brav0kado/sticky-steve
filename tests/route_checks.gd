extends SceneTree
## Proves the tower can be climbed: from each route block (Block.route_step) a bot searches real
## jumps (start spot, charge, launch direction, air steering) with the game's own physics until
## one ends standing on the next block, or slapped onto it if it's sticky (standing on top of a
## sticky block doesn't count: the slap is what's being proven). A level edit that makes a step
## impossible fails here, not in a playtest. It also checks the summit zone sits on the top block.
## Reachable is not the same as fun: this only guarantees the climb can be done.
##   godot --headless --path . -s res://tests/route_checks.gd   -> "ROUTE pass" or FAILs

const DT := 1.0 / 60.0
const TOWER := "res://scenes/tower.tscn"
const STEVE := "res://scenes/steve.tscn"
const CHARGES := [0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0]
const MAX_AIR_TICKS := 300

var _fails := 0
var steve: CharacterBody2D
var tower: Node2D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	tower = (load(TOWER) as PackedScene).instantiate()
	root.add_child(tower)
	steve = (load(STEVE) as PackedScene).instantiate()
	steve.set_physics_process(false)
	tower.add_child(steve)
	await physics_frame
	await physics_frame

	var route: Array = tower.get_children().filter(func(n: Node) -> bool: return n is StaticBody2D and n.route_step >= 0)
	route.sort_custom(func(a: Node, b: Node) -> bool: return a.route_step < b.route_step)
	_check(route.size() >= 2, "tower has a route (%d steps)" % route.size())
	var steps: Array[int] = []
	for b: Node in route:
		steps.append(b.route_step)
	_check(steps == range(steps.size()), "route steps are 0..%d with no gaps or repeats: %s" % [steps.size() - 1, steps])

	# Start: standing on step 0 where the main scene puts Steve.
	var start := {"pos": Vector2(80, 0), "cling": 0.0, "block": route[0]}
	var t0 := Time.get_ticks_msec()
	for i in range(1, route.size()):
		var found := _search(start, route[i])
		if found.is_empty():
			_check(false, "step %d (%s) reachable from step %d" % [i, route[i].name, i - 1])
			break
		print("step %2d %-11s from (%4.0f,%5.0f)%s charge %.2f dir %+d air %+d" % [
			i, route[i].name, start.pos.x, start.pos.y, " wall" if start.cling != 0.0 else "     ",
			found.charge, found.dir, found.air])
		start = found.end

	var summit := tower.get_node_or_null("Summit") as Area2D
	var top: Node = route.back()
	_check(summit != null, "tower has a Summit area")
	if summit:
		var zone := (summit.get_child(0) as CollisionShape2D)
		var rect := Rect2(summit.global_position - zone.shape.size / 2.0, zone.shape.size)
		var on_top: Vector2 = top.global_position + Vector2(top.size.x / 2.0, -1.0)
		_check(rect.has_point(on_top), "summit zone covers the top of the last route block")
	print("route search %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("ROUTE pass" if _fails == 0 else "ROUTE fail (%d)" % _fails)
	quit(1 if _fails else 0)


## Tries jumps from `start` until one lands on (or slaps onto) `target`. Returns
## {charge, dir, air, end: {pos, cling}} or {} if nothing works.
func _search(start: Dictionary, target: Node) -> Dictionary:
	var spots: Array[Vector2] = []
	var dirs: Array[float] = []
	if start.cling != 0.0:
		spots = [start.pos]
		dirs = [start.cling]  # a wall jump always goes away from the wall
	else:
		var from: Node = start.block  # the block he actually landed on (he can stand on its lip)
		var tx: float = target.global_position.x + target.size.x / 2.0
		# Start spots across the standing block near the target, nearest first. Spots where Steve
		# would be inside a wall are skipped (the ground block runs under the tower's walls).
		var x0: float = from.global_position.x + 5.0 if from else start.pos.x
		var x1: float = from.global_position.x + from.size.x - 5.0 if from else start.pos.x
		x0 = maxf(x0, tx - 260.0)
		x1 = minf(x1, tx + 260.0)
		var n := 10
		for k in n:
			var p := Vector2(lerpf(x0, x1, float(k) / (n - 1)), from.global_position.y if from else start.pos.y)
			if not _embedded(p):
				spots.append(p)
		spots.sort_custom(func(a: Vector2, b: Vector2) -> bool: return absf(a.x - tx) < absf(b.x - tx))
	# Onto a sticky wall, keep the highest slap found: the next jump starts from there, and a
	# player aims high too. Onto a ledge, the first landing that works is enough.
	var best := {}
	for spot in spots:
		if start.cling == 0.0:
			var toward := signf(target.global_position.x + target.size.x / 2.0 - spot.x)
			dirs = [toward, 0.0, -toward]
		for d in dirs:
			for c in CHARGES:
				for air in [d, 0.0, -d, 1.0, -1.0]:
					var end := _try(spot, start.cling, c, d, air, target)
					if end.is_empty():
						continue
					var hit := {"charge": c, "dir": int(d), "air": int(air), "end": end}
					if not target.is_sticky():
						return hit
					if best.is_empty() or end.pos.y < best.end.pos.y:
						best = hit
	return best


func _try(spot: Vector2, cling: float, charge: float, dir: float, air: float, target: Node) -> Dictionary:
	steve.global_position = spot
	steve.velocity = Vector2.ZERO
	steve.slap_ready = cling == 0.0  # a wall jump has already used this airtime's slap
	steve.charge = 0.0
	steve.cooldown = 0.0
	steve.has_checkpoint = false
	if cling != 0.0:
		steve.state = 3  # CLING
		steve.wall_normal = cling
	else:
		steve.state = 0  # GROUND
		steve.bot = {"dir": 0.0, "jump": false}
		for i in 2:
			steve.tick(DT)
		if not steve.is_on_floor():
			return {}
	steve.bot = {"dir": dir, "jump": true}
	for i in maxi(1, roundi(charge * steve.charge_time / DT)):
		steve.tick(DT)
		if steve.is_airborne() and steve.state == 2:
			break
	steve.bot = {"dir": air, "jump": false}
	for i in MAX_AIR_TICKS:
		steve.tick(DT)
		if steve.state == 3:  # slapped onto something
			return {"pos": steve.global_position, "cling": steve.wall_normal, "block": target} if steve.cling_block == target else {}
		if not steve.is_airborne() and steve.state != 1:
			# A sticky step is there to be slapped: standing on top of it doesn't prove the slap.
			var landed_on: bool = steve.last_floor == target and not target.is_sticky()
			return {"pos": steve.global_position, "cling": 0.0, "block": target} if landed_on else {}
	return {}


func _embedded(pos: Vector2) -> bool:
	return steve.test_move(Transform2D(0.0, pos + Vector2(0, -1)), Vector2(0, -0.5))


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what)
