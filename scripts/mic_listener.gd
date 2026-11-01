extends Node
class_name MicListener
## Your microphone, if you turn it on in the pause menu. Talk (or shout) and cryptids within
## earshot come to investigate: quiet talk carries ~8m, yelling ~35m.
##
## This is the groundwork for proximity chat: the same captured audio (the "Mic" bus with an
## AudioEffectCapture on it) is what a multiplayer build would send to nearby players.

const BUS:= "Mic"
const GATE:= 0.08          # below this it's room noise, not you
const NEAR:= 8.0
const FAR:= 35.0
const HEAR_EVERY:= 0.5

var player: Player
var cryptids: Array = []
var active:= false
## 0..1 loudness (after the sensitivity slider), and how far you can currently be heard.
var level:= 0.0
var radius:= 0.0

var _capture: AudioEffectCapture
var _stream_player: AudioStreamPlayer
var _hear_timer:= 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the pause-menu meter works while paused
	_sync()


func _sync() -> void:
	var want:= bool(GameState.settings.get("mic_enabled", false)) and DisplayServer.get_name() != "headless"
	if want == active:
		return
	if want:
		_start()
	else:
		_stop()


func _start() -> void:
	var idx:= AudioServer.get_bus_index(BUS)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS)
		_capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(idx, _capture, 0)
	else:
		_capture = AudioServer.get_bus_effect(idx, 0) as AudioEffectCapture
	# Captured before the bus volume is applied, so you hear none of yourself.
	AudioServer.set_bus_volume_db(idx, -80.0)
	_stream_player = AudioStreamPlayer.new()
	_stream_player.stream = AudioStreamMicrophone.new()
	_stream_player.bus = BUS
	add_child(_stream_player)
	_stream_player.play()
	active = true


func _stop() -> void:
	if _stream_player:
		_stream_player.stop()
		_stream_player.queue_free()
		_stream_player = null
	active = false
	level = 0.0
	radius = 0.0


## Loudness 0..1 from a block of stereo frames.
static func loudness(frames: PackedVector2Array, sens: float) -> float:
	if frames.is_empty():
		return 0.0
	var sum:= 0.0
	for f in frames:
		sum += (f.x * f.x + f.y * f.y) * 0.5
	var rms:= sqrt(sum / float(frames.size()))
	var db:= linear_to_db(maxf(rms, 0.00001))
	return clampf((db + 52.0) / 40.0 * sens, 0.0, 1.0)


## How far away a cryptid can hear you at a given loudness (0 = can't).
static func hear_radius(l: float) -> float:
	return 0.0 if l < GATE else lerpf(NEAR, FAR, (l - GATE) / (1.0 - GATE))


func _process(delta: float) -> void:
	_sync()
	if not active or _capture == null:
		return
	var n:= _capture.get_frames_available()
	if n > 0:
		var l:= loudness(_capture.get_buffer(n), float(GameState.settings.get("mic_sens", 1.0)))
		# Fast attack, slow release, like a VU meter.
		level = l if l > level else lerpf(level, l, clampf(delta * 4.0, 0.0, 1.0))
	radius = hear_radius(level)
	if get_tree().paused or player == null or player.indoors:
		return
	_hear_timer -= delta
	if radius > 0.0 and _hear_timer <= 0.0:
		_hear_timer = HEAR_EVERY
		for c in cryptids:
			if is_instance_valid(c):
				c.hear_noise(player.global_position, radius)
