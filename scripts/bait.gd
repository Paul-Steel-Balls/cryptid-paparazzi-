extends Node3D
class_name Bait
## A hunk of meat on the bone. Cryptids within smell range come and eat it,
## standing still and distracted while they do: prime photo time.

const LIFETIME:= 150.0

var claimed_by: Node = null
var _age:= 0.0
var _meat: MeshInstance3D
var _stink: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("bait")
	var meat_mat:= StandardMaterial3D.new()
	meat_mat.albedo_color = Color(0.62, 0.22, 0.14)
	var bone_mat:= StandardMaterial3D.new()
	bone_mat.albedo_color = Color(0.95, 0.92, 0.82)
	_meat = MeshInstance3D.new()
	var sm:= SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	_meat.mesh = sm
	_meat.scale = Vector3(1.0, 0.8, 1.4)
	_meat.material_override = meat_mat
	_meat.position = Vector3(0, 0.18, 0)
	add_child(_meat)
	var bone:= MeshInstance3D.new()
	var cm:= CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 0.04
	cm.height = 0.5
	bone.mesh = cm
	bone.material_override = bone_mat
	bone.rotation.x = PI / 2.0
	bone.position = Vector3(0, 0.18, 0.2)
	add_child(bone)
	for dx in [-0.05, 0.05]:
		var knob:= MeshInstance3D.new()
		var km:= SphereMesh.new()
		km.radius = 0.06
		km.height = 0.12
		knob.mesh = km
		knob.material_override = bone_mat
		knob.position = Vector3(dx, 0.18, 0.46)
		add_child(knob)
	# Cartoon stink wisps so you can find your bait in the dark.
	var wisp_mat:= StandardMaterial3D.new()
	wisp_mat.albedo_color = Color(0.6, 1.0, 0.3, 0.6)
	wisp_mat.emission_enabled = true
	wisp_mat.emission = Color(0.4, 0.9, 0.2)
	wisp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in 3:
		var w:= MeshInstance3D.new()
		var wm:= SphereMesh.new()
		wm.radius = 0.05
		wm.height = 0.1
		w.mesh = wm
		w.material_override = wisp_mat
		add_child(w)
		_stink.append(w)


func _process(delta: float) -> void:
	_age += delta
	for i in _stink.size():
		var t:= fmod(_age * 0.6 + i / 3.0, 1.0)
		_stink[i].position = Vector3(sin(t * 9.0 + i) * 0.12, 0.3 + t * 0.9, 0)
		_stink[i].scale = Vector3.ONE * (1.0 - t)
	if _age > LIFETIME and claimed_by == null:
		queue_free()


func set_eaten_fraction(f: float) -> void:
	if _meat:
		var s:= clampf(1.0 - f, 0.15, 1.0)
		_meat.scale = Vector3(1.0, 0.8, 1.4) * s
