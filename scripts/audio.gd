extends Node
## Autoload "Audio": one-shot sounds (2D and positional), music crossfades,
## night ambience. Sounds named foo_1..foo_n are variants of "foo".

const SFX:= [
	"rooster", "bait_drop", "bent_alert", "bent_grunt", "bigfoot_grunt", "bigfoot_munch", "bigfoot_roar",
	"bigstep_1", "bigstep_2", "bigstep_3", "bigstep_4", "boing", "camera_crash",
	"cash", "cash_tick", "coins", "corn_alert", "corn_grunt", "crackin_alert",
	"crackin_grunt", "develop", "door", "dry_click", "engine", "escaped",
	"fhairy_alert", "fhairy_grunt", "flash_charge", "grey_alert", "grey_grunt", "hoof_1",
	"hoof_2", "hoof_3", "hoof_4", "jersey_alert", "jersey_grunt", "land",
	"leper_alert", "leper_grunt", "loon", "lose", "methman_alert", "methman_grunt",
	"midstep_1", "midstep_2", "midstep_3", "midstep_4", "ouch", "owl",
	"pogo_alert", "pogo_grunt", "rake_alert", "rake_grunt", "reload", "run_1",
	"run_2", "run_3", "run_4", "run_5", "run_6", "santa_ho",
	"shop_laugh", "shop_talk_1", "shop_talk_2", "shop_talk_3", "shutter", "sleigh_bells",
	"sneak_1", "sneak_2", "sneak_3", "sneak_4", "snore", "step_1",
	"step_2", "step_3", "step_4", "step_5", "step_6", "stun_ring",
	"toe_talk_1", "toe_talk_2", "toe_talk_3", "toe_whoa", "tractor", "trap_set",
	"trap_snap", "ufo_hum", "ufo_zip", "ui_click", "wade_1", "wade_2",
	"wade_3", "wade_4", "whoosh", "win", "wolf_alert", "wolf_grunt"]
const LOOPS:= {"explore": "music_explore", "chase": "music_chase", "woods": "amb_woods", "lake": "amb_lake", "city": "amb_city"}
const MUSIC_DB:= -9.0
const AMB_DB:= -12.0

var _streams:= {}
var _variants:= {}
var _pool: Array[AudioStreamPlayer] = []
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _amb: AudioStreamPlayer
var _current_music:= ""
var _owl_timer:= 25.0
var muted:= false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in SFX:
		var st = load("res://audio/%s.wav" % n)
		if st != null:
			_streams[n] = st
			var base: String = n.rsplit("_", true, 1)[0] if n.rsplit("_", true, 1).size() == 2 and n.rsplit("_", true, 1)[1].is_valid_int() else ""
			if base != "":
				if not _variants.has(base):
					_variants[base] = []
				_variants[base].append(n)
	for key in LOOPS:
		var st = load("res://audio/%s.ogg" % LOOPS[key])
		if st is AudioStreamOggVorbis:
			st.loop = true
		_streams[key] = st
	for i in 10:
		var p:= AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	_amb = AudioStreamPlayer.new()
	for p in [_music_a, _music_b, _amb]:
		add_child(p)


func get_stream(n: String) -> AudioStream:
	if _variants.has(n):
		var v: Array = _variants[n]
		return _streams[v[randi() % v.size()]]
	return _streams.get(n, null)


func play(n: String, vol_db: float = 0.0, pitch_var: float = 0.0) -> void:
	if muted:
		return
	var st:= get_stream(n)
	if st == null:
		return
	var player: AudioStreamPlayer = null
	for p in _pool:
		if not p.playing:
			player = p
			break
	if player == null:
		player = _pool[0]
	player.stream = st
	player.volume_db = vol_db
	player.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	player.play()


func play_3d(n: String, pos: Vector3, vol_db: float = 0.0, max_dist: float = 80.0) -> void:
	if muted:
		return
	var st:= get_stream(n)
	var scene:= get_tree().current_scene if is_inside_tree() else null
	if st == null or scene == null:
		return
	var p:= AudioStreamPlayer3D.new()
	p.stream = st
	p.volume_db = vol_db
	p.unit_size = 6.0
	p.max_distance = max_dist
	if max_dist > 80.0:
		p.unit_size = 14.0
	scene.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func set_music(track: String, fade: float = 1.2) -> void:
	if track == _current_music:
		return
	_current_music = track
	var old:= _music_a if _music_a.playing else _music_b
	var nxt:= _music_b if old == _music_a else _music_a
	if is_inside_tree():
		if old.playing:
			var tw:= create_tween()
			tw.tween_property(old, "volume_db", -60.0, fade)
			tw.tween_callback(old.stop)
		if track != "" and _streams.get(track) != null and not muted:
			nxt.stream = _streams[track]
			nxt.volume_db = -40.0
			nxt.play()
			var tw2:= create_tween()
			tw2.tween_property(nxt, "volume_db", MUSIC_DB + (2.0 if track == "chase" else 0.0), fade)


var _amb_key:= "woods"


## Night sounds for the current map: "woods" or "lake".
func start_ambience(map_id: String = "woods") -> void:
	_amb_key = map_id if _streams.get(map_id) != null else "woods"
	if muted or _streams.get(_amb_key) == null:
		return
	if not _amb.playing or _amb.stream != _streams[_amb_key]:
		_amb.stream = _streams[_amb_key]
		_amb.volume_db = AMB_DB
		_amb.play()


func stop_all() -> void:
	set_music("")
	_amb.stop()


func _process(delta: float) -> void:
	# The odd owl in the woods, loon or bullfrog-free wail at the lake.
	if _amb.playing:
		_owl_timer -= delta
		if _owl_timer <= 0.0:
			_owl_timer = randf_range(30.0, 60.0)
			play("loon" if _amb_key == "lake" else "owl", -16.0, 0.05)
