extends Node
## Autoload "Sfx": fire-and-forget sound effects, res://audio/sfx/<name>.ogg (Kenney, CC0; see
## KENNEY-LICENSE.txt there). A small pool of players so overlapping sounds don't cut each other.

const DIR := "res://audio/sfx/"
const NAMES := [
	"jump", "charge_tick", "land", "land_hard", "bonk", "slap",
	"plant", "plant_ring", "flag_ready", "respawn", "summit", "perfect", "edge",
]
const POOL := 8

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # hitstop slows time, not sound
	for n: String in NAMES:
		var s := load(DIR + n + ".ogg") as AudioStream
		if s == null:
			push_warning("Sfx: missing %s%s.ogg" % [DIR, n])
		_streams[n] = s
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)


func play(sound: String, pitch := 1.0, volume_db := 0.0) -> void:
	var s: AudioStream = _streams.get(sound)
	if s == null:
		return
	# Prefer an idle player; if all are busy, steal the oldest-started one (round robin).
	var p := _pool[_next]
	for q in _pool:
		if not q.playing:
			p = q
			break
	_next = (_pool.find(p) + 1) % POOL
	p.stream = s
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()
