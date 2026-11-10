extends Node3D
class_name RVInterior
## Inside the RV. Built away from the map; the player is moved in and out through the door.
## Three stations: the driver's seat (travel), the bed (sleep), the red-light darkroom (develop).
## Local axes: +X toward the cab/windshield, -X toward the bed, the door is on the -Z wall.

const ORIGIN:= Vector3(400, 60, 400)
## Roomier inside than out (it's that kind of RV): sleeps four, seats four at the dinette.
const HALF_L:= 4.6
const HALF_W:= 1.9
const HEIGHT:= 2.35
## How far the cab end / bed end and the side walls moved out from the original 7.2 x 2.4 m layout.
const DX:= HALF_L - 3.6
const DZ:= HALF_W - 1.2
const ENTRY:= Vector3(0.6, 0.0, -0.55)
## Render layer for everything in here, so the moon (which skips this layer) can't light it.
const LAYER:= 1 << 9

## id -> {pos (local), label}
var hotspots:= {
	"drive": {"pos": Vector3(2.25 + DX, 1.0, -0.45), "label": "Driver's seat — travel"},
	"sleep": {"pos": Vector3(-2.5 - DX, 0.7, 0.35 + DZ), "label": "Bed — sleep until next night"},
	"develop": {"pos": Vector3(-0.55, 1.05, 0.85 + DZ), "label": "Darkroom — develop film"},
	"exit": {"pos": Vector3(0.6, 1.1, -1.15 - DZ), "label": "Leave the RV"},
	"posters": {"pos": Vector3(-1.9, 1.55, -1.15 - DZ), "label": "Poster wall — rearrange"},
	"closet": {"pos": Vector3(1.85, 1.2, -HALF_W + 0.62), "label": "Closet — change outfit"},
}
## Where the six posters hang: [local position, facing yaw]. Four along the kitchen wall, two over the bed.
const POSTER_SLOTS:= [
	[Vector3(-0.6, 1.62, -1.188 - DZ), 0.0], [Vector3(-1.35, 1.62, -1.188 - DZ), 0.0], [Vector3(-2.1, 1.62, -1.188 - DZ), 0.0],
	[Vector3(-2.85, 1.62, -1.188 - DZ), 0.0], [Vector3(-3.588 - DX, 1.65, -0.35), PI / 2], [Vector3(-3.588 - DX, 1.65, 0.65), PI / 2],
]
const SLOT_NAMES:= ["By the door", "Over the counter", "Kitchen wall", "Beside the bed", "Over the bed (left)", "Over the bed (right)"]
var _decor: Node3D
var _line_y:= 1.78
var _line_x0:= -1.45
var _line_x1:= 0.35
var _line_z:= 0.62 + DZ
var _prints: Array[MeshInstance3D] = []
var _windshield_mat: StandardMaterial3D
var _safelight: OmniLight3D


func _ready() -> void:
	position = ORIGIN
	_build_shell()
	_build_props()
	refresh_decor()
	_set_layers(self)


## Rebuild posters and trinkets from what you own (called on entry and after changes).
func refresh_decor() -> void:
	if _decor:
		_decor.free()
	_decor = Node3D.new()
	_decor.name = "Decor"
	add_child(_decor)
	for i in POSTER_SLOTS.size():
		var id: String = str(GameState.poster_slots[i]) if i < GameState.poster_slots.size() else ""
		if id == "" or not Catalog.owned(id):
			continue
		var pn:= Decor.poster(id)
		pn.position = POSTER_SLOTS[i][0]
		pn.rotation.y = POSTER_SLOTS[i][1]
		pn.rotation.z = sin(i * 2.3) * 0.03   # never quite straight
		_decor.add_child(pn)
	if Catalog.owned("fuzzy_dice"):
		var d:= Decor.fuzzy_dice()
		d.position = Vector3(3.3 + DX, 1.86, -0.3)
		_decor.add_child(d)
	if Catalog.owned("lava_lamp"):
		var l:= Decor.lava_lamp()
		l.position = Vector3(-0.55, 0.96, -HALF_W + 0.3)
		_decor.add_child(l)
	if Catalog.owned("toe_bobblehead"):
		var b:= Decor.toe_bobblehead()
		b.position = Vector3(3.35 + DX, 1.06, 0.3)
		b.rotation.y = -PI / 2
		_decor.add_child(b)
	_set_layers(_decor)


func _process(delta: float) -> void:
	if _road_scroll and _windshield_mat:
		_windshield_mat.uv1_offset.y -= delta * 0.9   # the road rushes by
	if _decor == null:
		return
	var t:= Time.get_ticks_msec() / 1000.0
	var lamp:= _decor.get_node_or_null("LavaLamp")
	if lamp:
		for i in 3:
			var b:= lamp.get_node_or_null("Blob%d" % i) as Node3D
			if b:
				b.position.y = 0.2 + 0.08 * sin(t * (0.4 + i * 0.17) + i * 2.0)
	var bob:= _decor.get_node_or_null("ToeBobblehead/Head") as Node3D
	if bob:
		bob.rotation = Vector3(0.18 * sin(t * 7.0), 0.0, 0.14 * sin(t * 5.3 + 1.0))
	var dice:= _decor.get_node_or_null("FuzzyDice") as Node3D
	if dice:
		dice.rotation.z = 0.12 * sin(t * 1.7)


func _set_layers(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = LAYER
	for c in n.get_children():
		_set_layers(c)


func entry_point() -> Vector3:
	return to_global(ENTRY)


## The station the player is looking at (or standing right next to), or "".
func focus_hotspot(eye: Vector3, forward: Vector3) -> String:
	var best:= ""
	var best_score:= -1.0
	for id in hotspots:
		var p: Vector3 = to_global(hotspots[id]["pos"])
		var to:= p - eye
		var d:= to.length()
		if d > 3.2:
			continue
		var dot:= forward.dot(to / maxf(d, 0.01))
		var score:= dot - d * 0.15
		if (dot > 0.55 or d < 0.9) and score > best_score:
			best_score = score
			best = id
	return best


func hotspot_label(id: String) -> String:
	return str(hotspots.get(id, {}).get("label", ""))


func hotspot_global(id: String) -> Vector3:
	return to_global(hotspots[id]["pos"])


# ------------------------------------------------------------------ cutscene camera spots

## Lying in bed, looking up.
func bed_view() -> Transform3D:
	var eye:= to_global(Vector3(-3.0 - DX, 0.85, 0.35 + DZ))
	return Transform3D(Basis.looking_at(to_global(Vector3(-2.0 - DX, 2.2, 0.35 + DZ)) - eye, Vector3(-1, 0, 0)), eye)


## Behind the wheel, looking out the windshield.
func drive_view() -> Transform3D:
	var eye:= to_global(Vector3(2.3 + DX, 1.35, -0.45))
	return Transform3D(Basis.looking_at(to_global(Vector3(4.5 + DX, 1.2, -0.45)) - eye), eye)


## Standing at the darkroom bench, looking at the clothesline.
func develop_view() -> Transform3D:
	var eye:= to_global(Vector3(-0.55, 1.6, -0.45 + DZ))
	return Transform3D(Basis.looking_at(to_global(Vector3(-0.55, 1.45, _line_z)) - eye), eye)


## You, behind the wheel (for the drive cutscene).
var _driver: CharacterModel
var _road_scroll:= false

func seat_driver() -> void:
	if _driver == null:
		_driver = CharacterModel.load_model(Skins.model_path(GameState.skin), 0.012)
		_driver.scale = Vector3.ONE * 0.9
		_driver.position = Vector3(2.6 + DX, 0.04, -0.45)
		_driver.rotation.y = PI / 2
		add_child(_driver)
		_set_layers(_driver)
		Skins.add_springs(_driver)
	_driver.visible = true
	_driver.play("drive")


## A camera "left on the passenger seat", looking up at the driver.
func seat_cam_view() -> Transform3D:
	var eye:= to_global(Vector3(2.82 + DX, 0.64, 0.58))
	return Transform3D(Basis.looking_at(to_global(Vector3(2.68 + DX, 1.32, -0.45)) - eye), eye)


func start_road(on: bool) -> void:
	_road_scroll = on


func headlights(on: bool) -> void:
	if _windshield_mat:
		var tw:= create_tween()
		tw.tween_property(_windshield_mat, "emission_energy_multiplier", 0.9 if on else 0.35, 0.6)


# ------------------------------------------------------------------ darkroom prints

## Hang a print on the line. tex may be null (blank print). Returns the mesh so it can be animated.
func hang_print(index: int, total: int, tex: Texture2D, caption: String) -> MeshInstance3D:
	var slots:= maxi(total, 4)
	# Left to right as seen from the aisle (looking +Z, +X is on the left).
	var x:= lerpf(_line_x1 - 0.15, _line_x0 + 0.15, (index + 0.5) / float(slots)) if slots > 1 else (_line_x0 + _line_x1) * 0.5
	var w:= minf(0.34, (_line_x1 - _line_x0) / float(slots) - 0.04)
	var h:= w * 0.62
	var m:= MeshInstance3D.new()
	var q:= QuadMesh.new()
	q.size = Vector2(w, h)
	m.mesh = q
	# Unshaded: the print shows the photo's own colours, not washed out by the red light.
	var mat:= StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.04, 0.02, 0.02)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material_override = mat
	m.position = Vector3(x, _line_y - h * 0.5 - 0.02, _line_z)
	m.rotation = Vector3(0, PI, randf_range(-0.06, 0.06))
	add_child(m)
	m.layers = LAYER
	var pin:= MeshInstance3D.new()
	pin.layers = LAYER
	var pb:= BoxMesh.new()
	pb.size = Vector3(0.018, 0.05, 0.012)
	pin.mesh = pb
	var pm:= StandardMaterial3D.new()
	pm.albedo_color = Color(0.75, 0.6, 0.4)
	pin.material_override = pm
	pin.position = Vector3(0, h * 0.5 + 0.01, 0)
	m.add_child(pin)
	if caption != "":
		var l:= Label3D.new()
		l.text = caption
		l.font = UIStyle.typewriter()
		l.font_size = 22
		l.pixel_size = 0.0016
		l.modulate = Color(1, 0.75, 0.7)
		l.outline_size = 0
		l.position = Vector3(0, -h * 0.5 - 0.04, 0)
		l.double_sided = true
		l.layers = LAYER
		m.add_child(l)
	_prints.append(m)
	return m


## Fade a print up from black, the way it comes up in the developer tray.
func develop_print(m: MeshInstance3D, seconds: float) -> void:
	var mat:= m.material_override as StandardMaterial3D
	var target:= Color(1, 1, 1) if mat.albedo_texture else Color(0.85, 0.82, 0.78)
	var tw:= create_tween()
	tw.tween_property(mat, "albedo_color", target, seconds)


func print_count() -> int:
	return _prints.size()


# ------------------------------------------------------------------ build

func _mat(c: Color, rough: float = 0.8) -> StandardMaterial3D:
	var m:= StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _tex(w: int, h: int, f: Callable) -> ImageTexture:
	var img:= Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, f.call(x, y))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _box(size: Vector3, pos: Vector3, mat: Material, collide: bool = true) -> MeshInstance3D:
	var mi:= MeshInstance3D.new()
	var bm:= BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	if collide:
		var sb:= StaticBody3D.new()
		var cs:= CollisionShape3D.new()
		var sh:= BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		sb.position = pos
		add_child(sb)
	return mi


func _build_shell() -> void:
	var rng:= RandomNumberGenerator.new()
	rng.seed = 42
	# 70s checker linoleum
	var floor_mat:= _mat(Color(1, 1, 1), 0.6)
	floor_mat.albedo_texture = _tex(64, 64, func(x: int, y: int) -> Color:
		return Color(0.82, 0.74, 0.55) if ((x / 16) + (y / 16)) % 2 == 0 else Color(0.55, 0.36, 0.2))
	floor_mat.uv1_scale = Vector3(6, 3, 1)
	floor_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	# wood paneling
	var wall_mat:= _mat(Color(1, 1, 1), 0.85)
	wall_mat.albedo_texture = _tex(128, 8, func(x: int, _y: int) -> Color:
		var k:= x % 32
		return Color(0.3, 0.19, 0.1) if k < 2 else Color(0.52, 0.34, 0.19).lerp(Color(0.6, 0.41, 0.23), 0.5 + 0.5 * sin(x * 0.7)))
	wall_mat.uv1_triplanar = true
	wall_mat.uv1_scale = Vector3(0.9, 0.9, 0.9)
	var ceil_mat:= _mat(Color(0.88, 0.85, 0.76))
	_box(Vector3(HALF_L * 2, 0.1, HALF_W * 2), Vector3(0, -0.05, 0), floor_mat)
	_box(Vector3(HALF_L * 2, 0.1, HALF_W * 2), Vector3(0, HEIGHT + 0.05, 0), ceil_mat)
	_box(Vector3(HALF_L * 2, HEIGHT, 0.1), Vector3(0, HEIGHT * 0.5, HALF_W + 0.05), wall_mat)
	# door wall, with the door opening
	_box(Vector3(HALF_L - 0.15, HEIGHT, 0.1), Vector3(-(HALF_L + 0.15) * 0.5, HEIGHT * 0.5, -HALF_W - 0.05), wall_mat)
	_box(Vector3(HALF_L - 1.05, HEIGHT, 0.1), Vector3((HALF_L + 1.05) * 0.5, HEIGHT * 0.5, -HALF_W - 0.05), wall_mat)
	var door_mat:= _mat(Color(0.12, 0.55, 0.55))
	_box(Vector3(0.92, HEIGHT, 0.06), Vector3(0.6, HEIGHT * 0.5, -HALF_W - 0.02), door_mat)
	var knob:= _box(Vector3(0.05, 0.05, 0.08), Vector3(0.95, 1.0, -HALF_W + 0.04), _mat(Color(0.8, 0.75, 0.5), 0.3), false)
	knob.name = "DoorKnob"
	var exit_sign:= Label3D.new()
	exit_sign.text = "EXIT  [E]"
	exit_sign.font = UIStyle.western()
	exit_sign.font_size = 40
	exit_sign.pixel_size = 0.004
	exit_sign.modulate = Color(1, 0.85, 0.4)
	exit_sign.position = Vector3(0.6, 2.0, -HALF_W + 0.02)
	add_child(exit_sign)
	# back wall (bed end) and the cab end
	_box(Vector3(0.1, HEIGHT, HALF_W * 2), Vector3(-HALF_L - 0.05, HEIGHT * 0.5, 0), wall_mat)
	_box(Vector3(0.1, 0.9, HALF_W * 2), Vector3(HALF_L + 0.05, 0.45, 0), _mat(Color(0.15, 0.15, 0.17)))
	_box(Vector3(0.1, 0.35, HALF_W * 2), Vector3(HALF_L + 0.05, HEIGHT - 0.17, 0), _mat(Color(0.15, 0.15, 0.17)))
	# windshield: the night outside, lit up when the headlights come on
	var ws:= MeshInstance3D.new()
	var q:= QuadMesh.new()
	q.size = Vector2(HALF_W * 2, 0.95)
	ws.mesh = q
	_windshield_mat = StandardMaterial3D.new()
	_windshield_mat.albedo_color = Color(0.03, 0.05, 0.12)
	_windshield_mat.emission_enabled = true
	_windshield_mat.emission_texture = _tex(96, 40, func(x: int, y: int) -> Color:
		var road:= y > 26 and absf(x - 48) < (y - 26) * 2.6
		var tree:= y > 8 and y < 30 and (sin(x * 0.55) + sin(x * 1.3)) > 0.6 + (y - 8) * 0.03
		if road:
			return Color(0.35, 0.33, 0.28) if absf(x - 48) > 1 or y % 4 < 2 else Color(1, 0.85, 0.3)
		if tree:
			return Color(0.06, 0.13, 0.08)
		return Color(0.06, 0.08, 0.2) if rng.randf() > 0.015 else Color(1, 1, 1))
	_windshield_mat.emission = Color(0.6, 0.65, 0.8)
	_windshield_mat.emission_energy_multiplier = 0.35
	ws.material_override = _windshield_mat
	ws.position = Vector3(HALF_L + 0.06, 1.38, 0)
	ws.rotation.y = -PI / 2
	add_child(ws)
	# side windows with curtains drawn
	var curtain:= _mat(Color(0.75, 0.45, 0.15))
	for x in [-2.0, 1.6]:
		_box(Vector3(0.7, 0.45, 0.03), Vector3(x, 1.45, HALF_W - 0.01), curtain, false)
	# lights: a warm dome light, plus the darkroom's red safelight
	var dome:= OmniLight3D.new()
	dome.light_color = Color(1.0, 0.82, 0.55)
	dome.light_energy = 0.75
	dome.omni_range = 6.0
	dome.position = Vector3(1.8, HEIGHT - 0.15, 0)
	dome.shadow_enabled = false
	add_child(dome)
	var dome2:= dome.duplicate() as OmniLight3D
	dome2.position = Vector3(-3.2, HEIGHT - 0.15, 0)
	dome2.light_energy = 0.5
	add_child(dome2)
	var dome3:= dome.duplicate() as OmniLight3D
	dome3.position = Vector3(-1.0, HEIGHT - 0.15, -0.8)
	dome3.light_energy = 0.4
	add_child(dome3)
	for bx: float in [1.8, -3.2]:
		var bulb:= _box(Vector3(0.3, 0.05, 0.3), Vector3(bx, HEIGHT - 0.03, 0), _mat(Color(1, 0.95, 0.8)), false)
		var bm:= bulb.material_override as StandardMaterial3D
		bm.emission_enabled = true
		bm.emission = Color(1, 0.9, 0.7)
	_safelight = OmniLight3D.new()
	_safelight.light_color = Color(1.0, 0.1, 0.05)
	_safelight.light_energy = 1.5
	_safelight.omni_range = 2.6
	_safelight.position = Vector3(-0.9, 1.95, 0.8 + DZ)
	add_child(_safelight)


func _build_props() -> void:
	var cab:= CharacterModel.load_model("res://models/rv_cab.glb", 0.008)
	cab.position = Vector3(2.65 + DX, 0, 0)
	cab.rotation.y = PI / 2
	add_child(cab)
	var bed:= CharacterModel.load_model("res://models/rv_bed.glb", 0.008)
	bed.position = Vector3(-2.6 - DX, 0, 0.42 + DZ)
	bed.rotation.y = PI / 2
	add_child(bed)
	_box(Vector3(1.9, 0.6, 1.4), Vector3(-2.6 - DX, 0.3, 0.42 + DZ), _mat(Color(0, 0, 0, 0)), true).visible = false
	_build_bunks()
	_build_dinette()
	var dark:= CharacterModel.load_model("res://models/rv_darkroom.glb", 0.008)
	dark.position = Vector3(-0.55, 0, 0.88 + DZ)
	dark.rotation.y = PI
	add_child(dark)
	_box(Vector3(1.9, 0.95, 0.65), Vector3(-0.55, 0.47, 0.88 + DZ), _mat(Color(0, 0, 0, 0)), true).visible = false
	# blackout curtain on a rail between the darkroom and the cab half
	var red:= _mat(Color(0.35, 0.05, 0.05))
	_box(Vector3(0.05, 2.0, 0.75), Vector3(0.48, 1.05, 0.82 + DZ), red, false)
	_box(Vector3(2.2, 0.03, 0.03), Vector3(-0.55, 2.12, 0.5 + DZ), _mat(Color(0.6, 0.6, 0.6), 0.3), false)
	# clothesline for prints
	var line:= _box(Vector3(_line_x1 - _line_x0, 0.006, 0.006), Vector3((_line_x0 + _line_x1) * 0.5, _line_y, _line_z), _mat(Color(0.9, 0.9, 0.85)), false)
	line.name = "Clothesline"
	# kitchenette on the door side: counter, little stove, coffee pot, cryptid poster
	_box(Vector3(1.5, 0.92, 0.55), Vector3(-1.1, 0.46, -HALF_W + 0.28), _mat(Color(0.55, 0.42, 0.25)))
	_box(Vector3(1.52, 0.04, 0.58), Vector3(-1.1, 0.94, -HALF_W + 0.28), _mat(Color(0.85, 0.82, 0.7), 0.4), false)
	_box(Vector3(0.4, 0.04, 0.3), Vector3(-1.05, 0.97, -HALF_W + 0.28), _mat(Color(0.15, 0.15, 0.15), 0.4), false)
	_box(Vector3(0.12, 0.18, 0.12), Vector3(-1.5, 1.05, -HALF_W + 0.3), _mat(Color(0.2, 0.2, 0.22), 0.3), false)
	# A tall closet between the door and the cab (outfits from DRIP CITY live in here).
	var cw:= _mat(Color(0.62, 0.45, 0.28))
	_box(Vector3(1.0, 2.0, 0.55), Vector3(1.85, 1.0, -HALF_W + 0.28), cw)
	for sx: float in [-0.245, 0.245]:
		_box(Vector3(0.47, 1.85, 0.03), Vector3(1.85 + sx, 1.0, -HALF_W + 0.565), _mat(Color(0.7, 0.52, 0.33)), false)
		_box(Vector3(0.03, 0.18, 0.04), Vector3(1.85 + sx * 0.15, 1.05, -HALF_W + 0.6), _mat(Color(0.85, 0.75, 0.4), 0.3), false)
	_box(Vector3(0.3, 1.2, 0.01), Vector3(1.85 + 0.245, 1.15, -HALF_W + 0.585), _mat(Color(0.75, 0.82, 0.88), 0.05), false)   # mirror
	# a feather boa hanging off the closet door, because of course
	for k in 6:
		_box(Vector3(0.09, 0.09, 0.09), Vector3(1.85 - 0.2 + sin(k * 0.9) * 0.05, 1.9 - k * 0.14, -HALF_W + 0.63), _mat(Color(1.0, 0.35, 0.75), 0.9), false)
	# the cab is narrower than the coach: dark side panels fill in either side of the dash
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.9, 1.0, DZ + 0.05), Vector3(HALF_L - 0.45, 0.5, side * (HALF_W - (DZ + 0.05) * 0.5)), _mat(Color(0.15, 0.15, 0.17)))


## Bunk beds on the door side of the bed end: two more berths (the double sleeps two).
func _build_bunks() -> void:
	var frame:= _mat(Color(0.45, 0.3, 0.17))
	var mattress:= _mat(Color(0.8, 0.75, 0.62))
	var blanket:= _mat(Color(0.25, 0.4, 0.55))
	var x:= -2.75 - DX + 0.15
	var z:= -HALF_W + 0.5
	for y: float in [0.35, 1.35]:
		_box(Vector3(1.9, 0.12, 0.9), Vector3(x, y, z), frame)
		_box(Vector3(1.85, 0.14, 0.85), Vector3(x, y + 0.13, z), mattress, false)
		_box(Vector3(1.2, 0.05, 0.86), Vector3(x + 0.3, y + 0.22, z), blanket, false)
		_box(Vector3(0.35, 0.1, 0.5), Vector3(x - 0.7, y + 0.25, z), _mat(Color(0.92, 0.9, 0.85)), false)
	for px: float in [x - 0.92, x + 0.92]:
		_box(Vector3(0.06, 1.75, 0.06), Vector3(px, 0.87, z + 0.42), frame, false)
	# ladder
	for k in 4:
		_box(Vector3(0.04, 0.03, 0.4), Vector3(x + 0.95, 0.5 + k * 0.28, z + 0.2), frame, false)
	hotspots["bunk"] = {"pos": Vector3(x, 0.8, z), "label": "Bunk — sleep until next night"}


## Dinette opposite the door: a table and two bench seats, room for four.
func _build_dinette() -> void:
	var vinyl:= _mat(Color(0.55, 0.28, 0.12), 0.6)
	var wood:= _mat(Color(0.6, 0.45, 0.28), 0.5)
	var z:= HALF_W - 0.55
	_box(Vector3(0.8, 0.05, 1.0), Vector3(2.0, 0.74, z), wood)
	_box(Vector3(0.08, 0.72, 0.08), Vector3(2.0, 0.37, z), _mat(Color(0.7, 0.7, 0.72), 0.3), false)
	for bx: float in [1.3, 2.7]:
		var back:= 1.0 if bx > 2.0 else -1.0
		_box(Vector3(0.5, 0.45, 1.0), Vector3(bx, 0.23, z), vinyl)
		_box(Vector3(0.12, 0.6, 1.0), Vector3(bx + back * 0.22, 0.75, z), vinyl, false)
	# the photo book: a fat scrapbook with a red cover
	_box(Vector3(0.34, 0.07, 0.26), Vector3(2.05, 0.8, z + 0.1), _mat(Color(0.65, 0.12, 0.1), 0.7), false)
	_box(Vector3(0.32, 0.055, 0.245), Vector3(2.06, 0.8, z + 0.1), _mat(Color(0.95, 0.93, 0.85), 0.9), false)
	_box(Vector3(0.12, 0.004, 0.08), Vector3(2.05, 0.837, z + 0.1), _mat(Color(0.95, 0.85, 0.5), 0.5), false)
	hotspots["photobook"] = {"pos": Vector3(2.05, 0.9, z + 0.1), "label": "Photo book — keep your best shots"}
	# a mug and a deck of cards for atmosphere
	_box(Vector3(0.08, 0.1, 0.08), Vector3(1.85, 0.82, z - 0.2), _mat(Color(0.85, 0.2, 0.15)), false)
	_box(Vector3(0.09, 0.03, 0.13), Vector3(2.1, 0.785, z + 0.15), _mat(Color(0.9, 0.9, 0.95)), false)
