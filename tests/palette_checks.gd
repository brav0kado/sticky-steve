extends SceneTree
## Palette gate: the whole game is NYX8. Fails on any visible PNG pixel under res://art, or any
## opaque Color(...) in a .tscn/.tres, that isn't one of the 8 colours in art/palette/nyx8.hex.
##   godot --headless --path . -s res://tests/palette_checks.gd   -> "PALETTE pass" or FAILs

const MAX_REPORTED := 5  ## per file: one bad export would otherwise flood the log

var _fails := 0
var _palette: Array[Color] = []


func _initialize() -> void:
	# Read the hex file, not Nyx8: it's the source of truth and also checks Nyx8 agrees with it.
	for line in FileAccess.get_file_as_string("res://art/palette/nyx8.hex").split("\n", false):
		_palette.append(Color(line.strip_edges()))
	_check(_palette.size() == 8, "nyx8.hex has 8 colours")
	var nyx8: GDScript = load("res://scripts/nyx8.gd")
	for c: Color in nyx8.ALL:
		_check(_in_palette(c), "Nyx8 constant %s is in nyx8.hex" % c.to_html(false))
	for path in _files("res://art", ".png"):
		_check_png(path)
	for path in _files("res://scenes", ".tscn") + _files("res://art", ".tres"):
		_check_colors(path)
	print("PALETTE pass" if _fails == 0 else "PALETTE fail (%d)" % _fails)
	quit(1 if _fails else 0)


func _check_png(path: String) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		_check(false, "%s loads" % path)
		return
	img.convert(Image.FORMAT_RGBA8)
	var seen := {}  # colour -> true; sheets repeat a handful of colours thousands of times
	var bad := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a == 0.0 or seen.has(c):
				continue
			seen[c] = true
			if not _in_palette(c):
				bad += 1
				if bad <= MAX_REPORTED:
					print("FAIL %s pixel (%d,%d) #%s is not NYX8" % [path, x, y, c.to_html(false)])
	_fails += mini(bad, 1)


func _check_colors(path: String) -> void:
	var re := RegEx.create_from_string("Color\\(([0-9.e-]+), ([0-9.e-]+), ([0-9.e-]+), ([0-9.e-]+)\\)")
	for m in re.search_all(FileAccess.get_file_as_string(path)):
		var c := Color(float(m.get_string(1)), float(m.get_string(2)), float(m.get_string(3)), float(m.get_string(4)))
		# Fully transparent or pure white are tints/modulates (no colour of their own), not paint.
		if c.a == 0.0 or c == Color.WHITE:
			continue
		_check(_in_palette(c), "%s: %s is not NYX8" % [path, m.get_string(0)])


func _in_palette(c: Color) -> bool:
	for p in _palette:
		if absf(p.r - c.r) < 0.005 and absf(p.g - c.g) < 0.005 and absf(p.b - c.b) < 0.005:
			return true
	return false


func _files(dir: String, ext: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(ext):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir.path_join(d), ext))
	return out


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what)
