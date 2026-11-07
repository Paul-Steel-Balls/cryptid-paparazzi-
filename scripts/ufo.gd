extends PhotoSubject
class_name UFO
## The greys' ride. Get photographed by tourists ten times in one night and it comes for you.
## It doesn't give up: snapping it (worth a bit, once) won't send it away, and you can't outlast
## it. The only way out is the tractor beam itself: when it gets over you, mash A and D to
## wriggle free and it leaves you alone for the night. Fail and you're abducted: camera and
## undeveloped photos gone, dumped back at camp. (Hiding in the RV only makes it wait; it
## leaves at dawn.)

signal abducted
signal escaped_beam
signal left

enum Phase {ARRIVE, HUNT, BEAM, LEAVE}

const ALTITUDE:= 11.0
const SPEED:= 4.6            # a walking pace you can outrun when sprinting, not forever
const BEAM_RANGE:= 2.6       # horizontal distance before the beam locks on
const BEAM_DELAY:= 0.8
const LIFT_HEIGHT:= 7.5
const LIFT_TIME:= 6.0        # seconds of beam before you're inside
const MASH_GAIN:= 0.085      # per alternating A/D press
const MASH_DECAY:= 0.16      # per second
## A clear shot of it is worth a flat $500 (once per visit).
var flat_pay:= 500
## Already photographed this visit: further photos of it are worth nothing.
var paid_out:= false

var player: Player
var terrain: Terrain
## Online: a copy of another player's UFO (it isn't hunting you; you can still photograph it).
var ghost:= false
var ghost_owner:= 0
var _ghost_target:= Vector3.ZERO
var phase: int = Phase.ARRIVE
## 0..1 how close you are to breaking free.
var struggle:= 0.0
var lift:= 0.0
var _t:= 0.0
var _over:= 0.0
var _last_key:= ""
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _beam_light: SpotLight3D
var _lights: Array[MeshInstance3D] = []
var _hull: Node3D
var _hum: AudioStreamPlayer3D
var _beam_start:= Vector3.ZERO
var _leave_dir:= Vector3(1, 0, 0)


func _init() -> void:
	species_id = "ufo"
	display_name = "UFO"
	photo_offset = Vector3.ZERO
	state = PhotoScoring.CryptidState.CHASE   # it's coming for you: danger pay


func _ready() -> void:
	_build()
	_hum = AudioStreamPlayer3D.new()
	var st:= Audio.get_stream("ufo_hum")
	if st is AudioStreamWAV:
		var w:= (st as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
		st = w
	_hum.stream = st
	_hum.unit_size = 14.0
	_hum.max_distance = 140.0
	_hum.volume_db = 2.0
	add_child(_hum)
	_hum.play()


func _ground_y(x: float, z: float) -> float:
	return terrain.height_at(x, z) if terrain != null else 0.0


func get_facing() -> Vector3:
	# A saucer looks the same from every side: it's always "facing" you.
	if player == null:
		return face_dir
	var d:= player.global_position - global_position
	return d.normalized() if d.length() > 0.01 else face_dir


func is_beaming() -> bool:
	return phase == Phase.BEAM


## Photographed: worth something once, and it doesn't care. It keeps coming.
func photographed() -> void:
	paid_out = true


## Morning: it's gone with the dark.
func dawn() -> void:
	if phase == Phase.LEAVE:
		return
	if phase == Phase.BEAM:
		_release(true)
	_leave()


func _process(delta: float) -> void:
	_t += delta
	if _hull:
		_hull.rotation.y += delta * (2.4 if phase == Phase.BEAM else 1.1)
		_hull.position.y = sin(_t * 1.7) * 0.25
	for i in _lights.size():
		var m:= _lights[i].material_override as StandardMaterial3D
		var on:= int(_t * 6.0 + i) % 3 == 0
		m.emission_energy_multiplier = 4.0 if on else 0.6
	if ghost:
		global_position = global_position.lerp(_ghost_target, clampf(delta * 8.0, 0.0, 1.0))
		return
	if player == null or not is_instance_valid(player):
		return
	match phase:
		Phase.ARRIVE, Phase.HUNT:
			_hunt(delta)
		Phase.BEAM:
			_beam_tick(delta)
		Phase.LEAVE:
			global_position += (_leave_dir * 16.0 + Vector3(0, 9.0, 0)) * delta
			if _t > 6.0:
				left.emit()
				queue_free()


func _hunt(delta: float) -> void:
	var target:= player.global_position
	var to:= Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	var d:= to.length()
	# Indoors (the RV) you're safe: it circles and waits.
	if player.indoors:
		var ang:= _t * 0.4
		target = player.global_position + Vector3(cos(ang), 0, sin(ang)) * 14.0
		to = Vector3(target.x - global_position.x, 0, target.z - global_position.z)
		d = to.length()
		_over = 0.0
	if d > 0.05:
		global_position += to / d * minf(d, SPEED * (1.6 if phase == Phase.ARRIVE else 1.0) * delta)
	var want_y:= _ground_y(global_position.x, global_position.z) + ALTITUDE
	global_position.y = lerpf(global_position.y, want_y, clampf(delta * 1.5, 0.0, 1.0))
	if phase == Phase.ARRIVE and d < 30.0:
		phase = Phase.HUNT
	if not player.indoors and d < BEAM_RANGE and not GameState.game_over:
		_over += delta
		if _over > BEAM_DELAY:
			_start_beam()
	else:
		_over = 0.0


func _start_beam() -> void:
	phase = Phase.BEAM
	struggle = 0.0
	lift = 0.0
	_last_key = ""
	_beam_start = player.global_position
	player.set_aiming(false)
	player.controls_locked = true
	_beam.visible = true
	_beam_light.visible = true
	if is_inside_tree():
		Audio.play("tractor", -2.0)


func _beam_tick(delta: float) -> void:
	# Mash A / D (alternating) to wriggle out.
	if Input.is_action_just_pressed("move_left"):
		mash("a")
	elif Input.is_action_just_pressed("move_right"):
		mash("d")
	if struggle >= 1.0:
		_release(true)
		escaped_beam.emit()
		_leave()
		return
	struggle = clampf(struggle - MASH_DECAY * delta, 0.0, 1.0)
	lift += delta / LIFT_TIME
	# Hover over you and haul you up, spinning a little.
	var over:= Vector3(_beam_start.x, global_position.y, _beam_start.z)
	global_position = global_position.lerp(over, clampf(delta * 3.0, 0.0, 1.0))
	var h:= _beam_start.y + LIFT_HEIGHT * smoothstep(0.0, 1.0, lift)
	var wob:= Vector3(sin(_t * 9.0), 0, cos(_t * 7.0)) * 0.12 * struggle
	player.global_position = Vector3(_beam_start.x, h, _beam_start.z) + wob
	_beam.scale = Vector3.ONE * (1.0 + sin(_t * 12.0) * 0.04)
	_beam_mat.albedo_color.a = 0.22 + 0.08 * sin(_t * 10.0)
	if lift >= 1.0:
		_release(false)
		abducted.emit()
		_leave()


func ghost_apply(pos: Vector3, beaming: bool, leaving: bool, p_lift: float) -> void:
	_ghost_target = pos
	_beam.visible = beaming
	_beam_light.visible = beaming
	lift = p_lift
	if leaving and phase != Phase.LEAVE:
		phase = Phase.LEAVE
		state = PhotoScoring.CryptidState.FLEE
	elif not leaving:
		phase = Phase.BEAM if beaming else Phase.HUNT


## One press while in the beam. Only alternating presses count (A, D, A, D...).
func mash(key: String) -> void:
	if phase != Phase.BEAM or key == _last_key:
		return
	struggle = minf(1.0, struggle + MASH_GAIN)
	_last_key = key
	if player:
		player.shake(0.12)


func _release(drop: bool) -> void:
	_beam.visible = false
	_beam_light.visible = false
	player.controls_locked = false
	if drop:
		player.velocity = Vector3.ZERO   # gravity takes it from here


func _leave() -> void:
	phase = Phase.LEAVE
	_t = 0.0
	state = PhotoScoring.CryptidState.FLEE
	_beam.visible = false
	_beam_light.visible = false
	var away:= global_position - (player.global_position if player else Vector3.ZERO)
	away.y = 0.0
	_leave_dir = away.normalized() if away.length() > 0.1 else Vector3(1, 0, 0)
	if is_inside_tree():
		Audio.play_3d("ufo_zip", global_position, 6.0, 200.0)


func _build() -> void:
	_hull = Node3D.new()
	add_child(_hull)
	var metal:= StandardMaterial3D.new()
	metal.albedo_color = Color(0.62, 0.66, 0.72)
	metal.metallic = 0.85
	metal.roughness = 0.28
	var disc:= MeshInstance3D.new()
	var dm:= SphereMesh.new()
	dm.radius = 3.4
	dm.height = 1.1
	dm.radial_segments = 48
	dm.rings = 16
	disc.mesh = dm
	disc.material_override = metal
	_hull.add_child(disc)
	var rim:= MeshInstance3D.new()
	var rm:= TorusMesh.new()
	rm.inner_radius = 3.15
	rm.outer_radius = 3.5
	rm.rings = 48
	rim.mesh = rm
	var rim_mat:= metal.duplicate() as StandardMaterial3D
	rim_mat.albedo_color = Color(0.4, 0.43, 0.5)
	rim.material_override = rim_mat
	_hull.add_child(rim)
	# Underside: a glowing ring where the beam comes out.
	var belly:= MeshInstance3D.new()
	var bm:= CylinderMesh.new()
	bm.top_radius = 1.1
	bm.bottom_radius = 0.9
	bm.height = 0.25
	belly.mesh = bm
	var belly_mat:= StandardMaterial3D.new()
	belly_mat.albedo_color = Color(0.5, 1.0, 0.6)
	belly_mat.emission_enabled = true
	belly_mat.emission = Color(0.4, 1.0, 0.55)
	belly_mat.emission_energy_multiplier = 3.0
	belly.material_override = belly_mat
	belly.position = Vector3(0, -0.5, 0)
	_hull.add_child(belly)
	# Glass dome with a little grey at the controls.
	var dome:= MeshInstance3D.new()
	var dmm:= SphereMesh.new()
	dmm.radius = 1.35
	dmm.height = 1.6
	dome.mesh = dmm
	var glass:= StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.95, 0.75, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.emission_enabled = true
	glass.emission = Color(0.3, 0.8, 0.55)
	glass.emission_energy_multiplier = 0.6
	glass.roughness = 0.05
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	dome.material_override = glass
	dome.position = Vector3(0, 0.45, 0)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hull.add_child(dome)
	if ResourceLoader.exists("res://models/grey_tourist.glb"):
		var pilot:= CharacterModel.load_model("res://models/grey_tourist.glb", 0.01)
		pilot.scale = Vector3.ONE * 0.5
		pilot.position = Vector3(0, -0.1, 0)
		_hull.add_child(pilot)
	var colors:= [Color(1, 0.25, 0.2), Color(1, 0.9, 0.2), Color(0.3, 1, 0.4), Color(0.3, 0.6, 1)]
	for i in 12:
		var a:= TAU * float(i) / 12.0
		var b:= MeshInstance3D.new()
		var sm:= SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.32
		b.mesh = sm
		var m:= StandardMaterial3D.new()
		m.albedo_color = colors[i % colors.size()]
		m.emission_enabled = true
		m.emission = colors[i % colors.size()]
		b.material_override = m
		b.position = Vector3(cos(a) * 3.35, -0.05, sin(a) * 3.35)
		_hull.add_child(b)
		_lights.append(b)
	var glow:= OmniLight3D.new()
	glow.light_color = Color(0.5, 1.0, 0.6)
	glow.light_energy = 1.6
	glow.omni_range = 14.0
	glow.position = Vector3(0, -1.0, 0)
	add_child(glow)
	# Tractor beam: a soft green cone down to the ground.
	_beam = MeshInstance3D.new()
	var cm:= CylinderMesh.new()
	cm.top_radius = 0.9
	cm.bottom_radius = 2.4
	cm.height = ALTITUDE
	cm.cap_top = false
	cm.cap_bottom = false
	_beam.mesh = cm
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_color = Color(0.45, 1.0, 0.6, 0.25)
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position = Vector3(0, -ALTITUDE * 0.5 - 0.4, 0)
	_beam.visible = false
	add_child(_beam)
	_beam_light = SpotLight3D.new()
	_beam_light.light_color = Color(0.5, 1.0, 0.6)
	_beam_light.light_energy = 6.0
	_beam_light.spot_range = ALTITUDE + 4.0
	_beam_light.spot_angle = 14.0
	_beam_light.rotation = Vector3(-PI * 0.5, 0, 0)
	_beam_light.visible = false
	add_child(_beam_light)
