extends Node3D
class_name Tripod
## Single-use trail camera on a tripod. Faces the way you were looking when you set it.
## After a moment to arm, it snaps the FIRST thing that walks right past it (within 6 m):
## a cryptid (scored like any photo) or you (a lovely, worthless selfie).
## Either way it's used up. Pair it with bait.

signal fired(result: Dictionary, target: Node3D)

const RANGE:= 6.0          # it only trips when something walks right past it
const HALF_ANGLE_DEG:= 26.0
const ARM_TIME:= 2.5
const EYE_H:= 1.15

var player: Player
var used:= false
var _arm:= ARM_TIME
var _led_mat: StandardMaterial3D
var _flash: OmniLight3D


func _ready() -> void:
	var dark:= StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.13)
	var metal:= StandardMaterial3D.new()
	metal.albedo_color = Color(0.6, 0.6, 0.62)
	metal.metallic = 0.7
	metal.roughness = 0.3
	for i in 3:
		var a:= TAU * i / 3.0 + 0.5
		var leg:= MeshInstance3D.new()
		var bm:= BoxMesh.new()
		bm.size = Vector3(0.025, 1.2, 0.025)
		leg.mesh = bm
		leg.material_override = metal
		var foot:= Vector3(cos(a) * 0.42, 0.0, sin(a) * 0.42)
		var top:= Vector3(0, EYE_H - 0.08, 0)
		leg.position = (foot + top) * 0.5
		leg.basis = Basis(Quaternion(Vector3.UP, (top - foot).normalized()))
		add_child(leg)
	var body:= MeshInstance3D.new()
	var b:= BoxMesh.new()
	b.size = Vector3(0.2, 0.15, 0.12)
	body.mesh = b
	var camo:= StandardMaterial3D.new()
	camo.albedo_color = Color(0.32, 0.36, 0.2)
	body.material_override = camo
	body.position = Vector3(0, EYE_H, 0)
	add_child(body)
	var lens:= MeshInstance3D.new()
	var cm:= CylinderMesh.new()
	cm.top_radius = 0.045
	cm.bottom_radius = 0.05
	cm.height = 0.08
	lens.mesh = cm
	lens.material_override = dark
	lens.rotation.x = PI / 2
	lens.position = Vector3(0, EYE_H, -0.09)
	add_child(lens)
	var led:= MeshInstance3D.new()
	var sm:= SphereMesh.new()
	sm.radius = 0.015
	sm.height = 0.03
	led.mesh = sm
	_led_mat = StandardMaterial3D.new()
	_led_mat.albedo_color = Color(1, 0.1, 0.05)
	_led_mat.emission_enabled = true
	_led_mat.emission = Color(1, 0.1, 0.05)
	led.material_override = _led_mat
	led.position = Vector3(0.07, EYE_H + 0.05, -0.062)
	add_child(led)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1, 0.97, 0.9)
	_flash.omni_range = 16.0
	_flash.light_energy = 0.0
	_flash.position = Vector3(0, EYE_H, -0.3)
	add_child(_flash)


func eye() -> Vector3:
	return to_global(Vector3(0, EYE_H, -0.1))


func facing() -> Vector3:
	return -global_transform.basis.z


func is_armed() -> bool:
	return not used and _arm <= 0.0


## Is this point in front of the lens, close enough, and not hidden behind something?
func sees(p: Vector3, target: Node3D) -> bool:
	var to:= p - eye()
	var d:= to.length()
	if d > RANGE or d < 0.6:
		return false
	# Wide-ish horizontally, generous vertically (it sits on slopes).
	var f:= facing()
	var flat_to:= Vector3(to.x, 0, to.z)
	var flat_f:= Vector3(f.x, 0, f.z)
	if flat_to.length() < 0.01 or rad_to_deg(flat_f.angle_to(flat_to)) > HALF_ANGLE_DEG:
		return false
	if absf(rad_to_deg(atan2(to.y, flat_to.length()))) > 40.0:
		return false
	if not is_inside_tree():
		return true
	var q:= PhysicsRayQueryParameters3D.create(eye(), p)
	var hit:= get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.get("collider") == target


func _physics_process(delta: float) -> void:
	if used:
		return
	if _arm > 0.0:
		_arm -= delta
		_led_mat.emission_energy_multiplier = 3.0 if fmod(_arm, 0.4) < 0.2 else 0.2
		return
	_led_mat.emission_energy_multiplier = 3.0 if fmod(Time.get_ticks_msec() / 1000.0, 1.5) < 0.1 else 0.4
	if player == null:
		return
	for c in player.cryptids:
		if is_instance_valid(c) and sees(c.photo_point(), c):
			fire(c)
			return
	for b in player.bystanders:
		if is_instance_valid(b) and sees((b as Node3D).global_position + Vector3(0, 1.5, 0), b):
			fire(b)
			return
	if sees(player.global_position + Vector3(0, 0.3, 0), player):
		fire(player)


func fire(target: Node3D) -> void:
	if used:
		return
	used = true
	_led_mat.emission_energy_multiplier = 0.0
	_flash.light_energy = 6.0
	var tw:= create_tween()
	tw.tween_property(_flash, "light_energy", 0.0, 0.3)
	var result:= {"in_frame": false, "reason": "Nice selfie." if target == player else "Just some guy. Worthless.", "value": 0}
	if target is Cryptid and player:
		result = player.evaluate_from(eye(), facing())   # an ordinary photo, no bonus for being a tripod
	if is_inside_tree():
		Audio.play_3d("shutter", eye(), 4.0)
		# Everyone nearby notices the flash and comes to look (or runs).
		if player:
			for c in player.cryptids:
				if is_instance_valid(c):
					c.on_device_flash(global_position)
	fired.emit(result, target)
