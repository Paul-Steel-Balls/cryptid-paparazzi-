extends Node
class_name MicListener
## Your microphone, if you turn it on in the pause menu. Talk (or shout) and cryptids within
## earshot come to investigate: quiet talk carries ~8m, yelling ~35m.
##
## Online it's also proximity voice chat: while you're talking (hold T, or open mic in the pause
## menu) your voice goes out as 16 kHz mono chunks and plays from your character on everyone
## else's PC, fading with distance (scripts/remote_player.gd). Cryptids hear you then, too.

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

signal voice_chunk(data: PackedByteArray)

const VOICE_RATE:= 16000
const VOICE_CHUNK:= 320          # samples per packet (20 ms)

## Online: is your voice going out right now?
var transmitting:= false
var _capture: AudioEffectCapture
var _phase:= 0.0
var _pending:= PackedFloat32Array()
var _hear_timer:= 0.0
## The microphone stream lives on the Audio autoload so it survives map changes. Godot's mic
## input is a ring buffer: if the game stalls (a map loading) it can wrap and replay the same
## second of audio over and over. So after any long frame we restart the stream and throw the
## captured backlog away, and say nothing until it has settled.
static var _mic_player: AudioStreamPlayer
var _needs_restart:= true
var _settle:= 0.0


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
	if _mic_player == null or not is_instance_valid(_mic_player):
		_mic_player = AudioStreamPlayer.new()
		_mic_player.name = "Microphone"
		_mic_player.stream = AudioStreamMicrophone.new()
		_mic_player.bus = BUS
		_mic_player.process_mode = Node.PROCESS_MODE_ALWAYS
		Audio.add_child(_mic_player)
	active = true
	_needs_restart = true


## Fresh start for the mic: stop, drop everything captured so far, play again, then a short
## quiet spell before anything counts as your voice.
func restart_stream() -> void:
	if _mic_player == null or not is_instance_valid(_mic_player):
		return
	_mic_player.stop()
	if _capture:
		_capture.clear_buffer()
	_pending.clear()
	_phase = 0.0
	level = 0.0
	_mic_player.play()
	_settle = 0.35
	_needs_restart = false


func _stop() -> void:
	if _mic_player and is_instance_valid(_mic_player):
		_mic_player.stop()
	if _capture:
		_capture.clear_buffer()
	_pending.clear()
	active = false
	transmitting = false
	level = 0.0
	radius = 0.0


func _voice(buf: PackedVector2Array) -> void:
	var was:= transmitting
	if not Net.online() or GameState.menu_open:
		transmitting = false
	elif bool(GameState.settings.get("voice_open", false)):
		transmitting = level > GATE
	else:
		transmitting = Input.is_action_pressed("voice_ptt")
	if not transmitting:
		if was and _pending.size() > 0:
			voice_chunk.emit(encode(_pending))
		_pending.clear()
		return
	var ratio:= AudioServer.get_mix_rate() / float(VOICE_RATE)
	var sens:= clampf(float(GameState.settings.get("mic_sens", 1.0)), 0.2, 3.0)
	var pos:= _phase
	var n:= buf.size()
	while pos < n:
		var i:= int(pos)
		# Crude low-pass: average the neighbourhood we're skipping over.
		var a:= buf[maxi(i - 1, 0)]
		var b:= buf[i]
		var c:= buf[mini(i + 1, n - 1)]
		_pending.append(((a.x + a.y) * 0.25 + (b.x + b.y) * 0.5 + (c.x + c.y) * 0.25) * 0.5 * sens)
		pos += ratio
	_phase = pos - n
	while _pending.size() >= VOICE_CHUNK:
		voice_chunk.emit(encode(_pending.slice(0, VOICE_CHUNK)))
		_pending = _pending.slice(VOICE_CHUNK)


## Samples (-1..1) -> 16-bit little-endian bytes.
static func encode(samples: PackedFloat32Array) -> PackedByteArray:
	var out:= PackedByteArray()
	out.resize(samples.size() * 2)
	for i in samples.size():
		out.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	return out


static func decode(data: PackedByteArray) -> PackedFloat32Array:
	var out:= PackedFloat32Array()
	out.resize(data.size() / 2)
	for i in out.size():
		out[i] = data.decode_s16(i * 2) / 32768.0
	return out


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
	# A long frame (map loading, a hitch): the mic buffer may have wrapped. Start clean once
	# frames are back to normal.
	if delta > 0.25:
		_needs_restart = true
	if _needs_restart:
		if delta < 0.1:
			restart_stream()
		return
	if _settle > 0.0:
		_settle -= delta
		_capture.clear_buffer()
		return
	var n:= _capture.get_frames_available()
	if n > 0:
		var buf:= _capture.get_buffer(n)
		var l:= loudness(buf, float(GameState.settings.get("mic_sens", 1.0)))
		# Fast attack, slow release, like a VU meter.
		level = l if l > level else lerpf(level, l, clampf(delta * 4.0, 0.0, 1.0))
		_voice(buf)
	# Online, cryptids only hear you while your voice is going out (push-to-talk / open mic).
	radius = hear_radius(level) if (not Net.online() or transmitting) else 0.0
	if get_tree().paused or player == null or player.indoors:
		return
	_hear_timer -= delta
	if radius > 0.0 and _hear_timer <= 0.0:
		_hear_timer = HEAR_EVERY
		for c in cryptids:
			if is_instance_valid(c):
				c.hear_noise(player.global_position, radius)
