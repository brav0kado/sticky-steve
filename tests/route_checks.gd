extends SceneTree
## Proves the tower can be climbed, and every gem can be collected, with real jumps.
##
## Route: from each route block (Block.route_step) a bot searches jumps (start spot, charge, launch
## direction, air steering) with the game's own physics until one ends on the next step: standing
## on it (SOLID, CRUMBLE), slapped onto it (STICKY: standing on top doesn't count, the slap is the
## point) or bounced off it (BOUNCY: the next step then starts mid-flight from that bounce). The
## climb must never need a perfect jump: full charges are held past the window.
## Gems: from every state the route reached (and every route block), a bot tries jumps, perfect
## ones included (some gems are meant to need one), until Steve touches the gem.
## Reachable is not the same as fun: this only guarantees it can be done.
##   godot --headless --path . -s res://tests/route_checks.gd   -> "ROUTE pass" or FAILs

const DT := 1.0 / 60.0
const TOWER := "res://scenes/tower.tscn"
const STEVE := "res://scenes/steve.tscn"
const CHARGES := [0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0]
const MAX_AIR_TICKS := 360
const GROUND := 0
const AIR := 2
const CLING := 3

var _fails := 0
var steve: CharacterBody2D
var tower: Node2D
var blocks: Array = []
var _bounced_on: Node = null
var _gem: Area2D = null
var _gem_hit := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	tower = (load(TOWER) as PackedScene).instantiate()
	root.add_child(tower)
	steve = (load(STEVE) as PackedScene).instantiate()
	steve.set_physics_process(false)
	tower.add_child(steve)
	steve.bounced.connect(func(b: Node) -> void: _bounced_on = b)
	blocks = tower.get_children().filter(func(n: Node) -> bool: return n is StaticBody2D)
	for b: Node in blocks:
		b.set_physics_process(false)  # crumble timers are stepped with Steve
	await physics_frame
	await physics_frame

	var route: Array = blocks.filter(func(n: Node) -> bool: return n.route_step >= 0)
	route.sort_custom(func(a: Node, b: Node) -> bool: return a.route_step < b.route_step)
	var steps: Array[int] = []
	for b: Node in route:
		steps.append(b.route_step)
	_check(route.size() >= 2, "tower has a route (%d steps)" % route.size())
	_check(steps == range(steps.size()), "route steps are 0..%d with no gaps or repeats: %s" % [steps.size() - 1, steps])

	var t0 := Time.get_ticks_msec()
	var start := {"kind": "ground", "pos": Vector2(80, 0), "block": route[0]}
	var reached: Array = [start]
	for i in range(1, route.size()):
		var found := _search(start, route[i], false)
		if found.is_empty():
			_check(false, "step %d (%s) reachable from step %d" % [i, route[i].name, i - 1])
			break
		print("step %2d %-10s from %-6s (%4.0f,%5.0f)  charge %.2f dir %+d air %+d" % [
			i, route[i].name, start.kind, start.pos.x, start.pos.y, found.charge, found.dir, found.air])
		start = found.end
		reached.append(start)

	var summit := tower.get_node_or_null("Summit") as Area2D
	var top: Node = route.back()
	_check(summit != null, "tower has a Summit area")
	if summit:
		var zone := summit.get_child(0) as CollisionShape2D
		var rect := Rect2(summit.global_position - zone.shape.size / 2.0, zone.shape.size)
		_check(rect.has_point(top.global_position + Vector2(top.size.x / 2.0, -1.0)), "summit zone covers the top of the last route block")

	# Gems: from any reached state, or standing on any route block.
	var starts: Array = reached.duplicate()
	for b: Node in route:
		if b.surface in [0, 3]:  # SOLID, CRUMBLE
			starts.append({"kind": "ground", "pos": b.global_position + Vector2(b.size.x / 2.0, 0), "block": b})
	var gems: Array = tower.find_children("*", "Area2D", true, false).filter(func(n: Node) -> bool: return n.has_method("gem_id"))
	_check(gems.size() > 0, "tower has gems")
	for g: Area2D in gems:
		g.monitoring = false  # the test checks overlap itself; a real pickup would hide it
		var got := {}
		starts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.pos.distance_to(g.global_position) < b.pos.distance_to(g.global_position))
		for s: Dictionary in starts.slice(0, 6):
			got = _search(s, g, true)
			if not got.is_empty():
				print("gem  %-12s from %-6s (%4.0f,%5.0f)  charge %.2f%s dir %+d air %+d" % [
					g.name, s.kind, s.pos.x, s.pos.y, got.charge, " perfect" if got.perfect else "", got.dir, got.air])
				break
		_check(not got.is_empty(), "gem %s at %s reachable" % [g.name, g.global_position])

	print("route + gem search %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("ROUTE pass" if _fails == 0 else "ROUTE fail (%d)" % _fails)
	quit(1 if _fails else 0)


## Tries jumps from `start` until one reaches `target` (a block, or a gem if `gem`).
## Returns {charge, dir, air, perfect, end: state} or {}.
func _search(start: Dictionary, target: Node, gem: bool) -> Dictionary:
	var best := {}
	if start.kind == "air":  # mid-bounce: only the steering is a choice
		for air in [0.0, 1.0, -1.0]:
			var end := _try(start, 0.0, 0.0, air, false, target, gem)
			if not end.is_empty():
				return {"charge": 0.0, "dir": 0, "air": int(air), "perfect": false, "end": end}
		return {}
	var spots: Array[Vector2] = []
	var tx: float = target.global_position.x + (target.size.x / 2.0 if not gem else 0.0)
	if start.kind == "cling":
		spots = [start.pos]
	else:
		var from: Node = start.block
		var x0: float = maxf(from.global_position.x + 5.0, tx - 260.0)
		var x1: float = minf(from.global_position.x + from.size.x - 5.0, tx + 260.0)
		for k in 10:
			var p := Vector2(lerpf(x0, x1, k / 9.0), from.global_position.y)
			if not _embedded(p):
				spots.append(p)
		spots.sort_custom(func(a: Vector2, b: Vector2) -> bool: return absf(a.x - tx) < absf(b.x - tx))
	var perfects := [false, true] if gem else [false]
	for spot in spots:
		var dirs: Array = [start.normal] if start.kind == "cling" else [signf(tx - spot.x), 0.0, -signf(tx - spot.x)]
		for d: float in dirs:
			for c: float in CHARGES:
				for pf: bool in perfects:
					if pf and c < 1.0:
						continue
					for air in [d, 0.0, -d, 1.0, -1.0]:
						var s := start.duplicate()
						s.pos = spot
						var end := _try(s, c, d, air, pf, target, gem)
						if end.is_empty():
							continue
						var hit := {"charge": c, "dir": int(d), "air": int(air), "perfect": pf, "end": end}
						# Onto a sticky wall keep the highest slap: the next jump starts there.
						if gem or not target.is_sticky():
							return hit
						if best.is_empty() or end.pos.y < best.end.pos.y:
							best = hit
	return best


func _try(start: Dictionary, charge: float, dir: float, air: float, perfect: bool, target: Node, gem: bool) -> Dictionary:
	for b: Node in blocks:
		b._set_gone(false)
	steve.global_position = start.pos
	steve.velocity = Vector2.ZERO
	steve.charge = 0.0
	steve.cooldown = 0.0
	steve.has_checkpoint = false
	steve.stats.streak = 0
	_bounced_on = null
	_gem = target if gem else null
	_gem_hit = false
	match start.kind:
		"cling":
			steve.state = CLING
			steve.wall_normal = start.normal
			steve.slap_ready = false
		"air":
			steve.state = AIR
			steve.velocity = start.vel
			steve.slap_ready = true
			steve.bot = {"dir": air, "jump": false}
		_:
			steve.state = GROUND
			steve.slap_ready = true
			steve.bot = {"dir": 0.0, "jump": false}
			if start.block.surface == 3:
				start.block.stood_on()  # a crumble ledge is already counting down under him
			for i in 2:
				_tick()
			if not steve.is_on_floor():
				return {}
	if start.kind != "air":
		steve.bot = {"dir": dir, "jump": true}
		var ticks := maxi(1, roundi(charge * steve.charge_time / DT))
		if charge >= 1.0:
			ticks += 2 if perfect else ceili(steve.perfect_window / DT) + 2
		for i in ticks:
			_tick()
			if steve.state == AIR:
				break  # the ground crumbled away under the charge
		steve.bot = {"dir": air, "jump": false}
	for i in MAX_AIR_TICKS:
		_tick()
		if gem and _gem_hit:
			return {"pos": steve.global_position}
		if _bounced_on != null:
			if not gem and _bounced_on == target:
				return {"kind": "air", "pos": steve.global_position, "vel": steve.velocity}
			_bounced_on = null  # bounced off something else: keep flying
		if steve.state == CLING:
			if not gem and steve.cling_block == target:
				return {"kind": "cling", "pos": steve.global_position, "normal": steve.wall_normal}
			if not gem:
				return {}
		if not steve.is_airborne() and steve.state not in [1, 4]:
			if gem:
				return {}
			var ok: bool = steve.last_floor == target and target.surface in [0, 3]
			return {"kind": "ground", "pos": steve.global_position, "block": target} if ok else {}
	return {}


func _tick() -> void:
	steve.tick(DT)
	for b: Node in blocks:
		if b.surface == 3:
			b.tick(DT)
	if _gem and not _gem_hit:
		var r := Rect2(steve.global_position + Vector2(-4, -20), Vector2(8, 20))
		_gem_hit = r.grow(_gem.RADIUS).has_point(_gem.global_position)


func _embedded(pos: Vector2) -> bool:
	return steve.test_move(Transform2D(0.0, pos + Vector2(0, -1)), Vector2(0, -0.5))


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what)
