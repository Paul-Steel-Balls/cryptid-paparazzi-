extends Node3D
class_name FlashTrap
## A cheap prank: a little hidden flash unit. The first OTHER player who walks within RANGE gets
## blinded (main sends the flash to their PC). Cryptids, bystanders and its owner never set it off,
## so it can't waste anybody's real gear. Single use.

signal fired(peer_id: int)

const RANGE:= 2.6
const ARM_TIME:= 2.0
const STUN:= 2.5

var owner_player: Node3D
## Returns {peer_id: Node3D} of the other players that can set it off (set by main).
var targets: Callable
var used:= false
var _arm:= ARM_TIME
var _led_mat: StandardMaterial3D
var _flash: OmniLight3D


func _ready() -> void:
	var body:= MeshInstance3D.new()
	var bm:= BoxMesh.new()
	bm.size = Vector3(0.2, 0.14, 0.12)
	body.mesh = bm
	var dark:= StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.14)
	dark.roughness = 0.6
	body.material_override = dark
	body.position.y = 0.07
	add_child(body)
	var lens:= MeshInstance3D.new()
	var lm:= BoxMesh.new()
	lm.size = Vector3(0.14, 0.06, 0.02)
	lens.mesh = lm
	var glass:= StandardMaterial3D.new()
	glass.albedo_color = Color(0.9, 0.9, 0.95)
	glass.emission_enabled = true
	glass.emission = Color(1, 1, 1)
	glass.emission_energy_multiplier = 0.3
	lens.material_override = glass
	lens.position = Vector3(0, 0.1, -0.065)
	add_child(lens)
	var led:= MeshInstance3D.new()
	var sm:= SphereMesh.new()
	sm.radius = 0.012
	sm.height = 0.024
	led.mesh = sm
	_led_mat = StandardMaterial3D.new()
	_led_mat.albedo_color = Color(0.2, 1, 0.3)
	_led_mat.emission_enabled = true
	_led_mat.emission = Color(0.2, 1, 0.3)
	led.material_override = _led_mat
	led.position = Vector3(0.07, 0.15, -0.06)
	add_child(led)
	_flash = OmniLight3D.new()
	_flash.omni_range = 9.0
	_flash.light_energy = 0.0
	_flash.position = Vector3(0, 0.3, -0.2)
	add_child(_flash)


func is_armed() -> bool:
	return not used and _arm <= 0.0


func _physics_process(delta: float) -> void:
	if used:
		return
	if _arm > 0.0:
		_arm -= delta
		_led_mat.emission_energy_multiplier = 2.0 if fmod(_arm, 0.4) < 0.2 else 0.1
		return
	_led_mat.emission_energy_multiplier = 1.5 if fmod(Time.get_ticks_msec() / 1000.0, 2.0) < 0.08 else 0.05
	if not targets.is_valid():
		return
	var who: Dictionary = targets.call()
	for peer in who:
		var n: Node3D = who[peer]
		if is_instance_valid(n) and n != owner_player and n.global_position.distance_to(global_position) <= RANGE:
			fire(int(peer))
			return


func fire(peer_id: int) -> void:
	if used:
		return
	used = true
	_led_mat.emission_energy_multiplier = 0.0
	_flash.light_energy = 8.0
	if is_inside_tree():
		Audio.play_3d("shutter", global_position, 6.0)
		var tw:= create_tween()
		tw.tween_property(_flash, "light_energy", 0.0, 0.35)
		tw.tween_interval(1.0)
		tw.tween_callback(queue_free)
	fired.emit(peer_id)
