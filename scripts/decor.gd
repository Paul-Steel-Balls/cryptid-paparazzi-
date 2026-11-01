extends RefCounted
class_name Decor
## 3D builders for the stuff you buy at the stand: posters and trinkets.

const POSTER_W:= 0.52
const POSTER_H:= 0.72


static func _mat(c: Color, unshaded: bool = false, glow: float = 0.0) -> StandardMaterial3D:
	var m:= StandardMaterial3D.new()
	m.albedo_color = c
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi:= MeshInstance3D.new()
	var bm:= BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _sphere(parent: Node3D, r: float, pos: Vector3, m: Material, h: float = -1.0) -> MeshInstance3D:
	var mi:= MeshInstance3D.new()
	var sm:= SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0 if h < 0.0 else h
	mi.mesh = sm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi:= MeshInstance3D.new()
	var cm:= CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


## A poster, facing local +Z, centred on the origin.
static func poster(id: String) -> Node3D:
	var it:= Catalog.item(id)
	var root:= Node3D.new()
	root.name = "Poster_" + id
	var bg: Color = it.get("bg", Color(0.2, 0.2, 0.2))
	var ink: Color = it.get("ink", Color(1, 1, 1))
	_box(root, Vector3(POSTER_W + 0.03, POSTER_H + 0.03, 0.006), Vector3(0, 0, -0.002), _mat(Color(0.95, 0.93, 0.86)))
	_box(root, Vector3(POSTER_W, POSTER_H, 0.006), Vector3(0, 0, 0.001), _mat(bg))
	# sunburst stripes behind the cryptid
	for i in 6:
		var ray:= _box(root, Vector3(0.03, POSTER_H * 0.9, 0.002), Vector3(0, 0.06, 0.006), _mat(bg.lightened(0.18)))
		ray.rotation.z = i * PI / 6.0
	var pic:= Sprite3D.new()
	var path:= "res://ui/portraits/%s.png" % str(it.get("portrait", "bigboobs"))
	if ResourceLoader.exists(path):
		pic.texture = load(path)
	pic.pixel_size = POSTER_H * 0.68 / 440.0
	pic.position = Vector3(0, 0.1, 0.01)
	pic.shaded = true
	root.add_child(pic)
	var cap:= Label3D.new()
	cap.text = str(it.get("caption", it.get("name", "")))
	cap.font = UIStyle.western()
	cap.font_size = 28
	cap.pixel_size = 0.0021
	cap.width = 235.0
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.modulate = ink
	cap.outline_size = 6
	cap.outline_modulate = bg.darkened(0.6)
	cap.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	cap.position = Vector3(0, -POSTER_H * 0.27, 0.012)
	root.add_child(cap)
	# tape corners
	for c in [Vector2(-1, 1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1)]:
		var t:= _box(root, Vector3(0.07, 0.025, 0.002), Vector3(c.x * POSTER_W * 0.47, c.y * POSTER_H * 0.47, 0.012), _mat(Color(0.95, 0.9, 0.7, 1.0)))
		t.rotation.z = 0.7 * c.x * c.y
	return root


## Pair of fuzzy dice on a string, hanging down from the origin.
static func fuzzy_dice() -> Node3D:
	var root:= Node3D.new()
	root.name = "FuzzyDice"
	_box(root, Vector3(0.006, 0.18, 0.006), Vector3(0, -0.09, 0), _mat(Color(0.9, 0.9, 0.9)))
	var dot:= _mat(Color(1, 1, 1))
	for i in 2:
		var d:= _box(root, Vector3(0.08, 0.08, 0.08), Vector3(-0.04 + i * 0.08, -0.22 - i * 0.03, 0), _mat(Color(0.95, 0.2, 0.55) if i == 0 else Color(0.2, 0.75, 0.95)))
		d.rotation = Vector3(0.3 * i, 0.5 + i, 0.2)
		for k in 3:
			_sphere(d, 0.011, Vector3(-0.02 + k * 0.02, -0.02 + k * 0.02, 0.041), dot)
	return root


## Lava lamp standing on the origin (glows; the blobs drift up and down).
static func lava_lamp() -> Node3D:
	var root:= Node3D.new()
	root.name = "LavaLamp"
	var chrome:= _mat(Color(0.75, 0.75, 0.8))
	chrome.metallic = 0.8
	chrome.roughness = 0.25
	_cyl(root, 0.045, 0.07, 0.1, Vector3(0, 0.05, 0), chrome)
	var glass:= _mat(Color(0.9, 0.35, 0.6, 0.55), false, 0.6)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cyl(root, 0.035, 0.055, 0.26, Vector3(0, 0.23, 0), glass)
	_cyl(root, 0.02, 0.035, 0.05, Vector3(0, 0.385, 0), chrome)
	var blob_m:= _mat(Color(1.0, 0.55, 0.15), true)
	for i in 3:
		var b:= _sphere(root, 0.018 + i * 0.006, Vector3(0, 0.15 + i * 0.07, 0), blob_m)
		b.name = "Blob%d" % i
	var l:= OmniLight3D.new()
	l.light_color = Color(1.0, 0.45, 0.6)
	l.light_energy = 0.8
	l.omni_range = 1.6
	l.position = Vector3(0, 0.25, 0)
	root.add_child(l)
	return root


## Toe Rogan bobblehead for the dashboard: little body, giant wobbling toe head.
static func toe_bobblehead() -> Node3D:
	var root:= Node3D.new()
	root.name = "ToeBobblehead"
	_cyl(root, 0.035, 0.035, 0.015, Vector3(0, 0.008, 0), _mat(Color(0.1, 0.1, 0.12)))
	_box(root, Vector3(0.05, 0.05, 0.03), Vector3(0, 0.04, 0), _mat(Color(0.12, 0.12, 0.12)))
	var head:= Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.07, 0)
	root.add_child(head)
	var skin:= _mat(Color(0.95, 0.75, 0.62))
	var h:= _sphere(head, 0.03, Vector3(0, 0.035, 0), skin, 0.085)
	h.scale = Vector3(1, 1, 0.9)
	_sphere(head, 0.02, Vector3(0, 0.06, 0.012), _mat(Color(0.98, 0.9, 0.85)), 0.016)  # nail
	for x in [-0.01, 0.01]:
		_sphere(head, 0.004, Vector3(x, 0.035, 0.027), _mat(Color(0.05, 0.05, 0.05)))
	return root


## Plastic lawn flamingo standing on the origin.
static func flamingo() -> Node3D:
	var root:= Node3D.new()
	root.name = "Flamingo"
	var pink:= _mat(Color(1.0, 0.42, 0.65))
	var leg:= _mat(Color(0.2, 0.2, 0.2))
	_box(root, Vector3(0.012, 0.5, 0.012), Vector3(-0.03, 0.25, 0), leg)
	_box(root, Vector3(0.012, 0.5, 0.012), Vector3(0.03, 0.25, 0), leg)
	var body:= _sphere(root, 0.13, Vector3(0, 0.6, -0.03), pink)
	body.scale = Vector3(0.8, 0.75, 1.3)
	var neck:= _box(root, Vector3(0.035, 0.32, 0.035), Vector3(0, 0.8, 0.1), pink)
	neck.rotation.x = -0.35
	_sphere(root, 0.05, Vector3(0, 0.96, 0.16), pink)
	var beak:= _box(root, Vector3(0.025, 0.025, 0.08), Vector3(0, 0.94, 0.23), _mat(Color(0.12, 0.12, 0.12)))
	beak.rotation.x = 0.5
	for x in [-0.03, 0.03]:
		_sphere(root, 0.008, Vector3(x, 0.975, 0.19), _mat(Color(0.05, 0.05, 0.05)))
	return root
