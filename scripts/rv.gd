extends StaticBody3D
class_name RV




var player_in_zone:= false
var _door_hinge: Node3D
var _outside_decor: Node3D
var _beacon_mat: StandardMaterial3D
var _beacon_light: OmniLight3D


func _ready() -> void:
	_build_visuals()
	_build_beacon()
	refresh_decor()
	var area:= Area3D.new()
	area.name = "DoorZone"
	area.position = Vector3(0, 1.2, -2.8)
	var col:= CollisionShape3D.new()
	var box:= BoxShape3D.new()
	box.size = Vector3(3.0, 2.5, 2.5)
	col.shape = box
	area.add_child(col)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	add_child(area)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		player_in_zone = true


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		player_in_zone = false


func _build_visuals() -> void:
	# Sculpted 70s motorhome (tools/characters.py rv_exterior). +X front, door on -Z.
	var body:= CharacterModel.load_model("res://models/rv_exterior.glb", 0.014)
	body.name = "Body"
	add_child(body)
	# Collision matches the new body.
	var cs:= get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs:
		var bs:= BoxShape3D.new()
		bs.size = Vector3(5.75, 2.75, 2.3)
		cs.shape = bs
		cs.position = Vector3(0.52, 1.4, 0)
	var yellow:= StandardMaterial3D.new()
	yellow.albedo_color = Color(1.0, 0.8, 0.1)
	var door_mat:= StandardMaterial3D.new()
	door_mat.albedo_color = Color(0.1, 0.55, 0.55)
	# The door swings on a hinge at its left edge (sits just proud of the body: no z-fighting).
	_door_hinge = Node3D.new()
	_door_hinge.position = Vector3(-0.45, 0, -1.17)
	add_child(_door_hinge)
	var door:= MeshInstance3D.new()
	var dm:= BoxMesh.new()
	dm.size = Vector3(0.9, 1.6, 0.06)
	door.mesh = dm
	door.material_override = door_mat
	door.position = Vector3(0.45, 1.33, -0.02)
	_door_hinge.add_child(door)
	var window:= MeshInstance3D.new()
	var wm:= BoxMesh.new()
	wm.size = Vector3(0.4, 0.45, 0.02)
	window.mesh = wm
	var glass:= StandardMaterial3D.new()
	glass.albedo_color = Color(0.12, 0.16, 0.24)
	glass.roughness = 0.2
	window.material_override = glass
	window.position = Vector3(0.45, 1.72, -0.06)
	_door_hinge.add_child(window)
	var knob:= MeshInstance3D.new()
	var km:= SphereMesh.new()
	km.radius = 0.04
	km.height = 0.08
	knob.mesh = km
	knob.material_override = yellow
	knob.position = Vector3(0.78, 1.2, -0.07)
	_door_hinge.add_child(knob)
	var dark_in:= StandardMaterial3D.new()
	dark_in.albedo_color = Color(0.25, 0.12, 0.05)
	dark_in.emission_enabled = true
	dark_in.emission = Color(0.5, 0.25, 0.1)
	_add_box(Vector3(0.9, 1.6, 0.004), dark_in, Vector3(0, 1.33, -1.152))   # warm glow behind the door

	# Little enamel sign over the door, in the RV's own 70s colours.
	var plate_mat:= StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.95, 0.9, 0.78)
	var rim_mat:= StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.95, 0.52, 0.12)
	_add_box(Vector3(1.14, 0.3, 0.025), rim_mat, Vector3(0, 2.33, -1.16))
	_add_box(Vector3(1.06, 0.23, 0.03), plate_mat, Vector3(0, 2.33, -1.165))
	var sign:= Label3D.new()
	sign.text = "PHOTO LAB"
	sign.font = load("res://fonts/Oswald.ttf")
	sign.font_size = 64
	sign.pixel_size = 0.0028
	sign.modulate = Color(0.42, 0.22, 0.1)
	sign.outline_size = 0
	sign.position = Vector3(0, 2.345, -1.183)
	sign.rotation.y = PI
	add_child(sign)
	var sub:= Label3D.new()
	sub.text = "·  DARKROOM  ·  SINCE 1974  ·"
	sub.font = load("res://fonts/Oswald.ttf")
	sub.font_size = 28
	sub.pixel_size = 0.0018
	sub.modulate = Color(0.1, 0.5, 0.5)
	sub.outline_size = 0
	sub.position = Vector3(0, 2.245, -1.183)
	sub.rotation.y = PI
	add_child(sub)

	# Party lights strung along the door side, under the roof line.
	var light_colors:= [Color(1, 0.9, 0.2), Color(1, 0.4, 0.7), Color(0.2, 0.9, 1.0), Color(1, 0.6, 0.1)]
	for i in 11:
		var m:= MeshInstance3D.new()
		var sm:= SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		m.mesh = sm
		var lmat:= StandardMaterial3D.new()
		lmat.albedo_color = light_colors[i % light_colors.size()]
		lmat.emission_enabled = true
		lmat.emission = light_colors[i % light_colors.size()]
		lmat.emission_energy_multiplier = 2.0
		m.material_override = lmat
		var x:= -2.1 + i * 0.42
		m.position = Vector3(x, 2.62 - 0.08 * sin(PI * fposmod(x + 2.1, 1.26) / 1.26), -1.2)
		add_child(m)


## Trinkets that live outside (the lawn flamingo).
func refresh_decor() -> void:
	if _outside_decor:
		_outside_decor.free()
	_outside_decor = Node3D.new()
	add_child(_outside_decor)
	if Catalog.owned("flamingo"):
		var f:= Decor.flamingo()
		f.position = Vector3(1.25, 0, -1.75)
		f.rotation.y = PI + 0.5
		_outside_decor.add_child(f)


## Where you stand outside the door (global), and the direction away from the RV.
func door_front() -> Vector3:
	return to_global(Vector3(0, 0, -2.3))


func door_out_dir() -> Vector3:
	return -global_transform.basis.z


func open_door(open: bool, seconds: float = 0.35) -> void:
	if _door_hinge == null:
		return
	var tw:= create_tween()
	tw.tween_property(_door_hinge, "rotation:y", 1.75 if open else 0.0, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _process(_delta: float) -> void:
	var on:= fmod(Time.get_ticks_msec() / 1000.0, 1.6) < 0.25
	if _beacon_mat:
		_beacon_mat.emission_energy_multiplier = 6.0 if on else 0.4
	if _beacon_light:
		_beacon_light.light_energy = 1.2 if on else 0.0


func _build_beacon() -> void:
	var pole_mat:= StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.7, 0.7, 0.7)
	var pole:= MeshInstance3D.new()
	var pm:= CylinderMesh.new()
	pm.top_radius = 0.04
	pm.bottom_radius = 0.05
	pm.height = 2.4
	pole.mesh = pm
	pole.material_override = pole_mat
	pole.position = Vector3(-1.6, 3.95, 0.6)
	add_child(pole)
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color(1, 0.15, 0.1)
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1, 0.15, 0.1)
	_beacon_mat.disable_fog = true
	var bulb:= MeshInstance3D.new()
	var bm:= SphereMesh.new()
	bm.radius = 0.22
	bm.height = 0.44
	bulb.mesh = bm
	bulb.material_override = _beacon_mat
	bulb.position = Vector3(-1.6, 5.2, 0.6)
	add_child(bulb)
	_beacon_light = OmniLight3D.new()
	_beacon_light.light_color = Color(1, 0.2, 0.15)
	_beacon_light.omni_range = 12.0
	_beacon_light.position = bulb.position
	add_child(_beacon_light)
	var porch:= OmniLight3D.new()
	porch.light_color = Color(1.0, 0.85, 0.55)
	porch.light_energy = 1.1
	porch.omni_range = 8.0
	porch.omni_attenuation = 1.4
	porch.position = Vector3(0, 2.4, -2.0)
	add_child(porch)


func _add_box(size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m:= MeshInstance3D.new()
	var mesh:= BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	add_child(m)
	return m
