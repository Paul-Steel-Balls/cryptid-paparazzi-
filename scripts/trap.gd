extends Area3D
class_name Trap
## Bear trap. Arms after a short delay, then snaps on the first thing that
## steps in: cryptid OR photographer. Friendly fire is very much on.

signal sprung(victim: Node3D)

enum TrapState {ARMING, ARMED, SPRUNG}

const ARM_TIME:= 1.2
const CRYPTID_HOLD:= 6.0
const PLAYER_HOLD:= 3.0
const LINGER_AFTER_SPRUNG:= 12.0

var state:= TrapState.ARMING
## Online, on a joining PC: just the look of the host's trap (the host decides who it catches).
var visual_only:= false
var _t:= 0.0
var _jaw_l: Node3D
var _jaw_r: Node3D
var _led: MeshInstance3D
var _led_mat: StandardMaterial3D


func _ready() -> void:
	monitoring = not visual_only
	var cs:= CollisionShape3D.new()
	var cyl:= CylinderShape3D.new()
	cyl.radius = 0.6
	cyl.height = 1.6
	cs.shape = cyl
	cs.position = Vector3(0, 0.8, 0)
	add_child(cs)
	body_entered.connect(_on_body)
	_build_visual()


func _build_visual() -> void:
	var steel:= StandardMaterial3D.new()
	steel.albedo_color = Color(0.42, 0.42, 0.45)
	steel.metallic = 0.6
	steel.roughness = 0.4
	var base:= MeshInstance3D.new()
	var bm:= CylinderMesh.new()
	bm.top_radius = 0.12
	bm.bottom_radius = 0.14
	bm.height = 0.05
	base.mesh = bm
	base.material_override = steel
	base.position = Vector3(0, 0.03, 0)
	add_child(base)
	var spring:= MeshInstance3D.new()
	var sp:= BoxMesh.new()
	sp.size = Vector3(1.1, 0.04, 0.08)
	spring.mesh = sp
	spring.material_override = steel
	spring.position = Vector3(0, 0.03, 0)
	add_child(spring)
	_jaw_l = _make_jaw(steel, -1.0)
	_jaw_r = _make_jaw(steel, 1.0)
	_led_mat = StandardMaterial3D.new()
	_led_mat.albedo_color = Color(1, 0.3, 0.1)
	_led_mat.emission_enabled = true
	_led_mat.emission = Color(1, 0.3, 0.1)
	_led = MeshInstance3D.new()
	var lm:= SphereMesh.new()
	lm.radius = 0.04
	lm.height = 0.08
	_led.mesh = lm
	_led.material_override = _led_mat
	_led.position = Vector3(0, 0.09, 0)
	add_child(_led)
	_set_jaws(0.0)


func _make_jaw(mat: Material, side: float) -> Node3D:
	# Hinge along X at the centre; jaw lies flat towards +/-Z when open.
	var hinge:= Node3D.new()
	hinge.position = Vector3(0, 0.04, 0)
	add_child(hinge)
	var bar:= MeshInstance3D.new()
	var bm:= BoxMesh.new()
	bm.size = Vector3(0.8, 0.03, 0.04)
	bar.mesh = bm
	bar.material_override = mat
	bar.position = Vector3(0, 0, 0.4 * side)
	hinge.add_child(bar)
	for s2 in [-1.0, 1.0]:
		var arm:= MeshInstance3D.new()
		var am:= BoxMesh.new()
		am.size = Vector3(0.03, 0.03, 0.4)
		arm.mesh = am
		arm.material_override = mat
		arm.position = Vector3(0.4 * s2, 0, 0.2 * side)
		hinge.add_child(arm)
	for i in 7:
		var tooth:= MeshInstance3D.new()
		var tm:= CylinderMesh.new()
		tm.top_radius = 0.0
		tm.bottom_radius = 0.025
		tm.height = 0.08
		tm.radial_segments = 4
		tooth.mesh = tm
		tooth.material_override = mat
		tooth.position = Vector3(-0.33 + i * 0.11, 0.04, 0.4 * side)
		hinge.add_child(tooth)
	hinge.set_meta("side", side)
	return hinge


func _set_jaws(closed: float) -> void:
	# 0 = flat open, 1 = snapped upright.
	_jaw_l.rotation.x = closed * (PI / 2.0)
	_jaw_r.rotation.x = -closed * (PI / 2.0)


func _process(delta: float) -> void:
	_t += delta
	match state:
		TrapState.ARMING:
			_led.visible = fmod(_t, 0.25) < 0.125
			if _t >= ARM_TIME:
				state = TrapState.ARMED
				_led.visible = true
				_led_mat.emission = Color(0.5, 0.15, 0.05)
				# Anyone already standing in it gets it.
				if not visual_only:
					for b in get_overlapping_bodies():
						_on_body(b)
		TrapState.SPRUNG:
			_set_jaws(minf(1.0, (_t) * 12.0))
			if _t > LINGER_AFTER_SPRUNG:
				queue_free()


func is_armed() -> bool:
	return state == TrapState.ARMED


func _on_body(body: Node3D) -> void:
	if state != TrapState.ARMED or visual_only:
		return
	if body.has_method("trap"):
		body.trap(CRYPTID_HOLD)
	elif body.has_method("snare"):
		body.snare(PLAYER_HOLD)
	else:
		return
	spring_on(body)


func spring_on(body: Node3D) -> void:
	if state == TrapState.SPRUNG:
		return
	state = TrapState.SPRUNG
	_t = 0.0
	_led.visible = false
	Audio.play_3d("trap_snap", global_position, 6.0)
	sprung.emit(body)


## Test helper: skip the arming delay.
func force_arm() -> void:
	state = TrapState.ARMED
	_t = 0.0
