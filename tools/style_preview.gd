extends SceneTree
## Style previews: one street corner (brick building with a shopfront, sidewalk, road, a parked
## sedan, a street lamp, a tree, a swing set and a slide, a photographer and a cryptid for
## scale) built in a chosen style, rendered to a PNG.
##   godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tools/style_preview.gd
##   env: STYLE=b (stylized HD) | c (realistic)   TIME=day|night   CAM=1|2   OUT=/tmp/x.png

var style:= "b"
var look:= "b"   # b, c, cartoon, lowpoly, clay, comic, storybook, ps1, voxel, paper, hyper
const K:= preload("res://tools/style_kit.gd")
## Proportions and detail per look (chunky styles: fewer, bigger windows and fatter trim).
var P:= {"floors": 4, "floor_h": 3.3, "bays": 6, "win_w": 1.15, "win_h": 1.7, "trim": 1.0, "detail": true}
var sun_dir:= Vector3.UP
var scene:= "city"   # city | woods | lake
var holder: Node     # where root3d lives (the root, or a low-res SubViewport for ps1)
var night:= false
var frames:= 0
var root3d: Node3D
var rng:= RandomNumberGenerator.new()


func _initialize() -> void:
	look = OS.get_environment("STYLE") if OS.get_environment("STYLE") != "" else "b"
	style = "c" if look in ["c", "hyper", "voxel", "ps1"] else "b"
	night = OS.get_environment("TIME") == "night"
	scene = OS.get_environment("SCENE") if OS.get_environment("SCENE") != "" else "city"
	rng.seed = 7
	match look:
		"cartoon", "clay":
			P = {"floors": 3, "floor_h": 3.8, "bays": 4, "win_w": 1.6, "win_h": 2.0, "trim": 2.2, "detail": false}
		"storybook":
			P = {"floors": 3, "floor_h": 3.7, "bays": 4, "win_w": 1.35, "win_h": 1.9, "trim": 1.7, "detail": false}
		"lowpoly", "ps1", "voxel":
			P = {"floors": 4, "floor_h": 3.3, "bays": 5, "win_w": 1.3, "win_h": 1.8, "trim": 1.4, "detail": false}
		"paper":
			P = {"floors": 3, "floor_h": 3.6, "bays": 5, "win_w": 1.3, "win_h": 1.9, "trim": 1.5, "detail": false}
	root3d = Node3D.new()
	holder = root
	if look == "ps1":
		# The PS1 drew at about 320x240 with no smoothing: sample the frame on a 400x225 grid.
		var layer:= CanvasLayer.new()
		root.add_child(layer)
		var rect:= ColorRect.new()
		rect.size = Vector2(1600, 900)
		rect.material = _shader_mat("""
shader_type canvas_item;
uniform sampler2D scr : hint_screen_texture, filter_nearest;
void fragment() {
	vec2 res = vec2(400.0, 225.0);
	COLOR = vec4(texture(scr, (floor(SCREEN_UV * res) + 0.5) / res).rgb, 1.0);
}
""")
		layer.add_child(rect)
	holder.add_child(root3d)
	_environment()
	match scene:
		"woods":
			_woods()
		"lake":
			_lake()
		_:
			_ground()
			_building()
			_street_props()
			_playground()
			_car()
	_people()
	_camera()
	if look == "hyper":
		if scene == "city":
			_hyper_details()
		else:
			_hyper_wild()


func _process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		_restyle_geometry()
		_restyle_materials()
	if frames == 4 and look == "voxel":
		_voxelize()
	if frames == 30:
		var out:= OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/preview.png"
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		quit()
	return false


# ------------------------------------------------------------------ helpers

func _box(size: Vector3, pos: Vector3, mat: Material, basis: Basis = Basis.IDENTITY) -> MeshInstance3D:
	var mi:= MeshInstance3D.new()
	if look == "paper" and size.y >= 0.3 and basis == Basis.IDENTITY:
		size.z = minf(size.z, 0.03)   # paper: every upright piece is a card
	mi.mesh = _box_mesh(size)
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	root3d.add_child(mi)
	return mi


var _box_cache:= {}
func _box_mesh(size: Vector3) -> Mesh:
	var key:= str(size)
	if _box_cache.has(key):
		return _box_cache[key]
	var lo:= minf(size.x, minf(size.y, size.z))
	var m: Mesh
	match look:
		"cartoon": m = K.rounded_box(size, minf(0.14, lo * 0.3), 1.0)
		"clay": m = K.rounded_box(size, minf(0.4, lo * 0.45), 0.4)
		"storybook": m = K.rounded_box(size, minf(0.08, lo * 0.2), 0.5)
		"comic": m = K.rounded_box(size, minf(0.02, lo * 0.15), 4.0)
		"paper": m = K.rounded_box(size, 0.0, 50.0)
		"lowpoly": m = K.rounded_box(size, 0.0, 1.5)
		_:
			var bm:= BoxMesh.new()
			bm.size = size
			m = bm
	_box_cache[key] = m
	return m


func _cyl(r: float, h: float, pos: Vector3, mat: Material, basis: Basis = Basis.IDENTITY, segs: int = 24, r_top: float = -1.0) -> MeshInstance3D:
	match look:
		"lowpoly": segs = mini(segs, 6)
		"ps1": segs = mini(segs, 7)
		"cartoon", "clay":
			r *= 1.25
			r_top = r_top * 1.25 if r_top >= 0.0 else -1.0
	var mi:= MeshInstance3D.new()
	var cm:= CylinderMesh.new()
	cm.top_radius = r if r_top < 0.0 else r_top
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = segs
	cm.rings = maxi(1, int(h / 0.3)) if look in ["storybook", "clay", "lowpoly"] else 1
	mi.mesh = cm
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	root3d.add_child(mi)
	return mi


## A tube between two points.
func _tube(a: Vector3, b: Vector3, r: float, mat: Material, segs: int = 20) -> MeshInstance3D:
	var d:= b - a
	var y:= d.normalized()
	var x:= y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z:= x.cross(y)
	return _cyl(r, d.length(), (a + b) * 0.5, mat, Basis(x, y, z), segs)


func _pbr(col: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m:= StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


func _shader_mat(code: String, params: Dictionary = {}) -> ShaderMaterial:
	var sh:= Shader.new()
	sh.code = code
	var m:= ShaderMaterial.new()
	m.shader = sh
	for k in params:
		m.set_shader_parameter(k, params[k])
	m.set_meta("params", params)
	return m


const NOISE_FN:= """
float hash12(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float a = 0.5; float s = 0.0; for (int i = 0; i < 4; i++) { s += a * vnoise(p); p *= 2.03; a *= 0.5; } return s; }
"""


## Brick walls (world-space, so pieces line up). realistic: small real bricks with recessed
## mortar, colour variation, burnt headers and grime near the ground; stylized: chunky soft
## bricks in warm, even colours.
func _brick_mat(base: Color) -> ShaderMaterial:
	var real:= style == "c"
	var code:= """
shader_type spatial;
uniform vec3 base_col;
uniform float bw;
uniform float bh;
uniform float mortar;
uniform float bump;
uniform float vary;
uniform float grime;
varying vec3 wpos;
varying vec3 wnrm;
""" + NOISE_FN + """
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz); }
float brick_h(vec2 q, out vec2 id) {
	float row = floor(q.y / bh);
	float u = q.x / bw + mod(row, 2.0) * 0.5;
	id = vec2(floor(u), row);
	float eu = min(fract(u), 1.0 - fract(u)) * bw;
	float ev = min(fract(q.y / bh), 1.0 - fract(q.y / bh)) * bh;
	return smoothstep(mortar * 0.5, mortar * 1.6, min(eu, ev));
}
void fragment() {
	bool side = abs(wnrm.x) > 0.5;
	bool top = abs(wnrm.y) > 0.5;
	vec2 q = top ? wpos.xz : vec2(side ? wpos.z : wpos.x, wpos.y);
	vec2 id;
	float fw = max(length(fwidth(q)), 1e-5);
	float fade = 1.0 - smoothstep(mortar * 0.35, mortar * 1.3, fw);
	float h = mix(0.88, brick_h(q, id), fade);
	float e = 0.004;
	vec2 i2;
	float hx = brick_h(q + vec2(e, 0.0), i2);
	float hy = brick_h(q + vec2(0.0, e), i2);
	vec3 A = top ? vec3(1, 0, 0) : (side ? vec3(0, 0, 1) : vec3(1, 0, 0));
	vec3 B = top ? vec3(0, 0, 1) : vec3(0, 1, 0);
	vec3 nw = normalize(wnrm - (A * (hx - h) / e + B * (hy - h) / e) * bump * fade);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float r = hash12(id);
	vec3 c = base_col * (1.0 - vary * 0.5 * fade + vary * mix(0.5, r, fade));
	c = mix(c, base_col * vec3(0.55, 0.45, 0.42), step(0.92, hash12(id + 9.0)) * vary * 1.5);   // burnt bricks
	c *= 0.92 + 0.16 * vnoise(q * 9.0) * vary * 2.0;
	vec3 m = vec3(0.62, 0.6, 0.56) * (0.9 + 0.2 * vnoise(q * 30.0));
	vec3 col = mix(m, c, h);
	// grime near the ground and streaks
	float g = grime * (smoothstep(1.6, 0.0, q.y) * 0.5 + smoothstep(0.55, 0.85, fbm(vec2(q.x * 3.0, q.y * 0.4))) * 0.35);
	col *= 1.0 - g;
	ALBEDO = col;
	ROUGHNESS = mix(0.97, 0.82, h) + 0.05 * vnoise(q * 20.0);
}
"""
	if real:
		return _shader_mat(code, {"base_col": base, "bw": 0.225, "bh": 0.075, "mortar": 0.009, "bump": 0.012, "vary": 0.28, "grime": 0.55})
	return _shader_mat(code, {"base_col": base, "bw": 0.5, "bh": 0.19, "mortar": 0.022, "bump": 0.025, "vary": 0.14, "grime": 0.12})


func _ground_mat(kind: String) -> ShaderMaterial:
	var real:= style == "c"
	var code:= """
shader_type spatial;
uniform vec3 base_col;
uniform float kind;     // 0 asphalt, 1 concrete slabs, 2 grass, 3 rubber matting
uniform float realism;
varying vec3 wpos;
""" + NOISE_FN + """
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 q = wpos.xz;
	vec3 c = base_col;
	float rough = 0.9;
	float n = fbm(q * 0.7);
	if (kind < 0.5) {
		float speck = hash12(floor(q * 60.0));
		c *= 0.85 + 0.25 * n + (speck > 0.93 ? 0.25 : 0.0) * realism;
		float crack = smoothstep(0.006, 0.0, abs(fbm(q * 2.6 + 3.0) - 0.5)) * realism
			* smoothstep(0.45, 0.65, fbm(q * 0.35 + 1.7));
		c *= 1.0 - crack * 0.35;
		c = mix(c, c * 0.7, smoothstep(0.6, 0.8, fbm(q * 0.25)) * realism * 0.6);  // patches / oil
		rough = mix(0.92, 0.55, realism * smoothstep(0.55, 0.75, fbm(q * 0.3 + 8.0)));
	} else if (kind < 1.5) {
		vec2 s = fract(q / 1.5);
		float joint = 1.0 - smoothstep(0.0, 0.012, min(min(s.x, 1.0 - s.x), min(s.y, 1.0 - s.y)));
		c *= (0.9 + 0.15 * vnoise(floor(q / 1.5) * 3.7)) * (1.0 - joint * 0.45);
		c *= 1.0 - realism * 0.25 * smoothstep(0.55, 0.8, fbm(q * 0.8));   // stains
		c *= 0.95 + 0.1 * vnoise(q * 25.0);
	} else if (kind < 2.5) {
		c *= 0.75 + 0.4 * fbm(q * 2.0);
		c = mix(c, vec3(0.45, 0.42, 0.22), smoothstep(0.6, 0.85, fbm(q * 0.5)) * 0.4);
	} else {
		c *= 0.88 + 0.15 * vnoise(q * 40.0);
	}
	ALBEDO = c;
	ROUGHNESS = rough;
}
"""
	var params:= {"realism": 1.0 if real else 0.0}
	match kind:
		"asphalt":
			params["kind"] = 0.0
			params["base_col"] = Color(0.16, 0.16, 0.17) if real else Color(0.2, 0.21, 0.26)
		"concrete":
			params["kind"] = 1.0
			params["base_col"] = Color(0.58, 0.57, 0.54) if real else Color(0.72, 0.7, 0.68)
		"grass":
			params["kind"] = 2.0
			params["base_col"] = Color(0.24, 0.36, 0.14) if real else Color(0.3, 0.62, 0.25)
		"dirt":
			params["kind"] = 3.0
			params["base_col"] = Color(0.3, 0.22, 0.15) if real else Color(0.5, 0.36, 0.22)
		"rubber":
			params["kind"] = 3.0
			params["base_col"] = Color(0.55, 0.22, 0.16) if real else Color(0.85, 0.4, 0.3)
	return _shader_mat(code, params)


# ------------------------------------------------------------------ scene

func _environment() -> void:
	var we:= WorldEnvironment.new()
	var e:= Environment.new()
	var sky:= Sky.new()
	var sm:= ProceduralSkyMaterial.new()
	if night:
		sm.sky_top_color = Color(0.02, 0.03, 0.08)
		sm.sky_horizon_color = Color(0.08, 0.08, 0.14)
		sm.ground_horizon_color = Color(0.05, 0.05, 0.08)
		sm.ground_bottom_color = Color(0.01, 0.01, 0.02)
		sm.sky_energy_multiplier = 0.4
	else:
		sm.sky_top_color = Color(0.25, 0.45, 0.85) if style == "b" else Color(0.32, 0.5, 0.78)
		sm.sky_horizon_color = Color(0.7, 0.8, 0.92)
		sm.sun_angle_max = 20.0
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = (0.6 if night else 1.0) * (1.15 if style == "b" else 0.9)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC if style == "b" else Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = (1.25 if night else 1.0) if style == "b" else (1.4 if night else 1.1)
	e.glow_enabled = night
	e.glow_intensity = 0.8
	e.glow_bloom = 0.1
	e.adjustment_enabled = true
	if style == "b":
		e.adjustment_saturation = 1.35
		e.adjustment_contrast = 1.05
		e.adjustment_brightness = 1.05
	else:
		e.adjustment_saturation = 0.92
		e.adjustment_contrast = 1.08
	e.fog_enabled = true
	e.fog_light_color = Color(0.08, 0.08, 0.14) if night else Color(0.7, 0.78, 0.9)
	e.fog_density = 0.006 if night else (0.0015 if style == "b" else 0.004)
	e.fog_sky_affect = 0.0
	_look_env(e, sm)
	if scene == "woods":
		e.fog_density += 0.012 if not night else 0.02
		e.fog_light_color = e.fog_light_color.lerp(Color(0.45, 0.6, 0.5) if not night else Color(0.04, 0.09, 0.08), 0.6)
		e.fog_sky_affect = 0.3
	if scene != "city" and night:
		e.ambient_light_energy *= 1.8 if look != "ps1" else 3.0
	if scene == "lake" and night:
		sm.sky_top_color = Color(0.03, 0.05, 0.14)
		sm.sky_horizon_color = Color(0.12, 0.16, 0.32)
	we.environment = e
	root3d.add_child(we)
	var sun:= DirectionalLight3D.new()
	sun.shadow_enabled = true
	if night:
		sun.light_color = Color(0.55, 0.62, 0.9)
		sun.light_energy = 0.25 if scene == "city" else 0.5
		sun.rotation_degrees = Vector3(-50, 35, 0)
	else:
		sun.light_color = Color(1.0, 0.95, 0.85) if style == "b" else Color(1.0, 0.96, 0.9)
		sun.light_energy = 1.25 if style == "b" else 1.6
		sun.rotation_degrees = Vector3(-38, 35, 0)
	_look_sun(sun)
	sun_dir = sun.basis.z
	root3d.add_child(sun)


func _ground() -> void:
	# Road along x (z -5..5), curb, sidewalk (z 5..9.4), the building from 9.4, playground lawn.
	var road:= MeshInstance3D.new()
	var pm:= PlaneMesh.new()
	pm.size = Vector2(80, 10)
	pm.subdivide_width = 40
	road.mesh = pm
	road.material_override = _ground_mat("asphalt")
	road.position = Vector3(0, 0, 0)
	root3d.add_child(road)
	var far:= MeshInstance3D.new()
	var fm:= PlaneMesh.new()
	fm.size = Vector2(80, 30)
	far.mesh = fm
	far.material_override = _ground_mat("concrete")
	far.position = Vector3(0, 0.15, -20)
	root3d.add_child(far)
	_box(Vector3(80, 0.15, 4.4), Vector3(0, 0.075, 7.2), _ground_mat("concrete"))
	_box(Vector3(80, 0.15, 4.4), Vector3(0, 0.075, -7.2), _ground_mat("concrete"))
	var curb:= _pbr(Color(0.62, 0.6, 0.56) if style == "c" else Color(0.78, 0.76, 0.72), 0.85)
	for z: float in [5.0, -5.0]:
		_box(Vector3(80, 0.17, 0.2), Vector3(0, 0.085, z), curb)
	# Lane paint (worn a bit on the realistic one) and a zebra crossing.
	var white:= _pbr(Color(0.85, 0.85, 0.8) if style == "c" else Color(0.95, 0.95, 0.92), 0.7)
	var yellow:= _pbr(Color(0.8, 0.65, 0.15) if style == "c" else Color(1.0, 0.82, 0.2), 0.7)
	var x:= -38.0
	while x < 38.0:
		if absf(x - 11.0) > 3.0:
			_box(Vector3(2.6, 0.01, 0.14), Vector3(x, 0.005, -0.1), yellow)
			_box(Vector3(2.6, 0.01, 0.14), Vector3(x, 0.005, 0.1), yellow)
		x += 6.0
	for k in 9:
		_box(Vector3(0.55, 0.01, 9.2), Vector3(9.0 + k * 0.9, 0.006, 0), white)
	# Lawn and rubber matting for the playground (in front of the building's right end).
	_box(Vector3(12, 0.16, 4.2), Vector3(17, 0.08, 7.3), _ground_mat("grass"))


func _building() -> void:
	# 16 m wide, 4 storeys, brick, real window openings (piers + spandrels), white frames,
	# sills and lintels, a cornice; ground floor shopfront with a striped awning and sign.
	var brick:= _brick_mat(Color(0.55, 0.26, 0.19) if style == "c" else Color(0.78, 0.36, 0.26))
	var trim:= _pbr(Color(0.86, 0.84, 0.78) if style == "c" else Color(0.95, 0.92, 0.85), 0.75)
	var stone:= _pbr(Color(0.62, 0.6, 0.55), 0.85)
	var glass:= _pbr(Color(0.06, 0.08, 0.1), 0.04, 0.85)
	var x0:= -10.0
	var x1:= 6.0
	var front:= 9.4
	var depth:= 10.0
	var floor_h: float = P.floor_h
	var floors: int = P.floors
	var tk: float = P.trim
	var top:= 0.15 + floor_h * floors
	var wall_t:= 0.4
	# Back mass (behind the facade). Hyperreal leaves the front 3.3 m hollow for rooms you can see into.
	var hollow:= 3.3 if look == "hyper" else wall_t
	_box(Vector3(x1 - x0, top, depth - hollow), Vector3((x0 + x1) * 0.5, top * 0.5, front + hollow + (depth - hollow) * 0.5), brick)
	if look == "hyper":
		for sx: float in [x0 + 0.2, x1 - 0.2]:
			_box(Vector3(0.4, top, hollow), Vector3(sx, top * 0.5, front + hollow * 0.5), brick)
		for f in floors + 1:
			_box(Vector3(x1 - x0 - 0.4, 0.2, hollow - 0.3), Vector3((x0 + x1) * 0.5, 0.15 + floor_h * f - 0.1, front + 0.3 + (hollow - 0.3) * 0.5), _pbr(Color(0.85, 0.83, 0.78), 0.9))
	# Ground floor: stone base, piers, big shop windows, door.
	var gf:= 0.15 + floor_h
	_box(Vector3(x1 - x0, 0.6, wall_t + 0.05), Vector3((x0 + x1) * 0.5, 0.45, front + wall_t * 0.5), stone)
	for px: float in [x0 + 0.4, x0 + 6.0, x0 + 9.0, x1 - 0.4]:
		_box(Vector3(0.8, gf - 0.15, wall_t + 0.1), Vector3(px, 0.15 + (gf - 0.15) * 0.5, front + wall_t * 0.5), brick)
	for span: Array in [[x0 + 0.8, x0 + 5.6], [x0 + 9.4, x1 - 0.8]]:
		var w: float = span[1] - span[0]
		var cx: float = (span[0] + span[1]) * 0.5
		_box(Vector3(w, 2.2, 0.04), Vector3(cx, 1.85, front + 0.3), glass)
		_box(Vector3(w, 0.08, 0.12), Vector3(cx, 0.75, front + 0.28), trim)
		_box(Vector3(w, 0.08, 0.12), Vector3(cx, 2.95, front + 0.28), trim)
		for k in int(w / 1.2):
			_box(Vector3(0.06, 2.2, 0.1), Vector3(span[0] + (k + 1) * w / (int(w / 1.2) + 1), 1.85, front + 0.27), trim)
		if night:
			var l:= OmniLight3D.new()
			l.light_color = Color(1.0, 0.85, 0.6)
			l.light_energy = 1.6
			l.omni_range = 6.0
			l.position = Vector3(cx, 2.0, front - 0.6)
			root3d.add_child(l)
			_box(Vector3(w, 2.2, 0.02), Vector3(cx, 1.85, front + 0.36), _glow(Color(1.0, 0.85, 0.6), 0.9))
	# Door (recessed, with a transom).
	var door_x:= x0 + 7.5
	_box(Vector3(1.2, 2.3, 0.08), Vector3(door_x, 1.3, front + 0.38), _pbr(Color(0.2, 0.28, 0.22), 0.6))
	_box(Vector3(0.8, 1.2, 0.02), Vector3(door_x, 1.55, front + 0.33), glass)
	_box(Vector3(0.05, 0.25, 0.05), Vector3(door_x + 0.45, 1.25, front + 0.31), _pbr(Color(0.8, 0.7, 0.4), 0.3, 1.0))
	_box(Vector3(1.4, 0.15, 0.6), Vector3(door_x, 0.075, front + 0.1), stone)
	# Band and sign over the shop, then the striped awning.
	_box(Vector3(x1 - x0, gf - 3.0 + 0.2, wall_t + 0.12), Vector3((x0 + x1) * 0.5, 3.15 + (gf - 3.15) * 0.5, front + wall_t * 0.5 - 0.02), brick)
	_box(Vector3(6.0, 0.6, 0.1), Vector3(x0 + 3.2, 3.5, front - 0.08), _pbr(Color(0.12, 0.25, 0.18), 0.6))
	var sign:= Label3D.new()
	sign.text = "BODEGA  ·  DELI"
	sign.font_size = 110
	sign.pixel_size = 0.004
	sign.modulate = Color(0.95, 0.85, 0.5)
	sign.outline_size = 0
	sign.position = Vector3(x0 + 3.2, 3.5, front - 0.14)
	sign.rotation.y = PI
	sign.shaded = true
	root3d.add_child(sign)
	_awning(Vector3(x0 + 3.2, 3.05, front), 5.4)
	_awning(Vector3(x0 + 12.8, 3.05, front), 5.2)
	# Upper floors: bays of windows.
	var bays: int = P.bays
	var bay_w:= (x1 - x0) / bays
	var win_w: float = P.win_w
	var win_h: float = P.win_h
	for f in range(1, floors):
		var y0:= 0.15 + floor_h * f
		var sill_y:= y0 + 0.85
		# spandrel under and over the window band
		_box(Vector3(x1 - x0, 0.85, wall_t), Vector3((x0 + x1) * 0.5, y0 + 0.425, front + wall_t * 0.5), brick)
		_box(Vector3(x1 - x0, floor_h - 0.85 - win_h, wall_t), Vector3((x0 + x1) * 0.5, sill_y + win_h + (floor_h - 0.85 - win_h) * 0.5, front + wall_t * 0.5), brick)
		for b in bays + 1:
			var px:= x0 + b * bay_w
			var pw:= bay_w - win_w if b > 0 and b < bays else (bay_w - win_w) * 0.5
			var pcx:= px if b > 0 and b < bays else (px + pw * 0.5 if b == 0 else px - pw * 0.5)
			_box(Vector3(pw, win_h, wall_t), Vector3(pcx, sill_y + win_h * 0.5, front + wall_t * 0.5), brick)
		for b in bays:
			var cx:= x0 + (b + 0.5) * bay_w
			# glass set back in the opening, a white frame with a middle rail, sill and lintel
			var lit:= night and rng.randf() < 0.45
			_box(Vector3(win_w, win_h, 0.03), Vector3(cx, sill_y + win_h * 0.5, front + 0.24), _glow(Color(1.0, 0.8, 0.5), 1.2) if lit else glass)
			for fx: float in [-1.0, 1.0]:
				_box(Vector3(0.07 * tk, win_h, 0.08), Vector3(cx + fx * (win_w * 0.5 - 0.035 * tk), sill_y + win_h * 0.5, front + 0.22), trim)
			for fy: float in [0.035 * tk, win_h - 0.035 * tk, win_h * 0.55]:
				_box(Vector3(win_w, 0.06 * tk, 0.08), Vector3(cx, sill_y + fy, front + 0.22), trim)
			_box(Vector3(win_w + 0.25 * tk, 0.08 * tk, 0.22 * tk), Vector3(cx, sill_y - 0.04 * tk, front - 0.06 * tk), stone)
			_box(Vector3(win_w + 0.2 * tk, 0.18 * tk, 0.06 * tk), Vector3(cx, sill_y + win_h + 0.09 * tk, front - 0.01), stone)
			if lit:
				var wl:= OmniLight3D.new()
				wl.light_color = Color(1.0, 0.8, 0.55)
				wl.light_energy = 0.5
				wl.omni_range = 3.0
				wl.position = Vector3(cx, sill_y + 1.0, front - 0.8)
				root3d.add_child(wl)
	# Cornice with dentils.
	_box(Vector3(x1 - x0 + 0.5 * tk, 0.35 * tk, wall_t + 0.5 * tk), Vector3((x0 + x1) * 0.5, top + 0.1 * tk, front + 0.1), trim)
	_box(Vector3(x1 - x0 + 0.3, 0.6, wall_t + 0.2), Vector3((x0 + x1) * 0.5, top - 0.3, front + 0.2), brick)
	var dx:= x0 + 0.2
	while dx < x1 and P.detail:
		_box(Vector3(0.12, 0.14, 0.12), Vector3(dx, top - 0.12, front - 0.05), trim)
		dx += 0.32
	# Fire escape on the right bays.
	var iron:= _pbr(Color(0.08, 0.08, 0.09), 0.5, 0.6)
	for f in range(1, floors):
		var y:= 0.15 + floor_h * f + 0.8
		var cx:= x1 - 2.7
		_box(Vector3(3.2, 0.05, 1.1), Vector3(cx, y, front - 0.55), iron)
		var bars:= 13 if P.detail else 5
		for gx in bars:
			_tube(Vector3(cx - 1.6 + gx * 3.2 / (bars - 1), y, front - 1.1), Vector3(cx - 1.6 + gx * 3.2 / (bars - 1), y + 0.95, front - 1.1), 0.012, iron, 6)
		_tube(Vector3(cx - 1.6, y + 0.95, front - 1.1), Vector3(cx + 1.6, y + 0.95, front - 1.1), 0.02, iron, 8)
		if f < floors - 1:
			var dir:= 1.0 if f % 2 == 1 else -1.0
			var a:= Vector3(cx - dir * 1.2, y, front - 0.35)
			var b:= Vector3(cx + dir * 1.0, y + floor_h, front - 0.35)
			_tube(a, b, 0.02, iron, 8)
			_tube(a + Vector3(0, 0, -0.45), b + Vector3(0, 0, -0.45), 0.02, iron, 8)
			for k in 10:
				var t:= (k + 0.5) / 10.0
				_box(Vector3(0.12, 0.02, 0.5), a.lerp(b, t) + Vector3(0, 0, -0.22), iron)
	# AC unit and a couple of planters on the sills.
	_box(Vector3(0.75, 0.5, 0.6), Vector3(x0 + 1.35, 0.15 + floor_h * 2 + 1.1, front - 0.25), _pbr(Color(0.8, 0.8, 0.76), 0.5, 0.3))


func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m:= _pbr(c, 0.4)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


## Striped canvas awning with a scalloped valance.
func _awning(at: Vector3, w: float) -> void:
	var c1:= Color(0.12, 0.42, 0.24) if style == "c" else Color(0.15, 0.6, 0.35)
	var c2:= Color(0.88, 0.86, 0.8)
	var depth:= 1.4
	var stripes:= int(w / 0.35)
	var slope:= Basis(Vector3.RIGHT, 0.38)
	for i in stripes:
		var sx:= at.x - w * 0.5 + (i + 0.5) * w / stripes
		var col:= c1 if i % 2 == 0 else c2
		var m:= _pbr(col, 0.95)
		_box(Vector3(w / stripes, 0.03, depth), Vector3(sx, at.y + 0.25, at.z - depth * 0.5 + 0.05), m, slope)
		# scallop
		var sc:= MeshInstance3D.new()
		var cm:= CylinderMesh.new()
		cm.top_radius = w / stripes * 0.5
		cm.bottom_radius = w / stripes * 0.5
		cm.height = 0.02
		cm.radial_segments = 16
		sc.mesh = cm
		sc.material_override = m
		sc.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(sx, at.y - 0.2, at.z - depth + 0.02))
		root3d.add_child(sc)
		_box(Vector3(w / stripes, 0.22, 0.02), Vector3(sx, at.y - 0.12, at.z - depth + 0.02), m)
	# frame arms
	var iron:= _pbr(Color(0.1, 0.1, 0.1), 0.5, 0.6)
	for ex: float in [-w * 0.5, w * 0.5]:
		_tube(Vector3(at.x + ex, at.y - 0.3, at.z), Vector3(at.x + ex, at.y - 0.05, at.z - depth + 0.05), 0.015, iron, 8)


func _street_props() -> void:
	var iron:= _pbr(Color(0.12, 0.13, 0.14) if style == "c" else Color(0.15, 0.2, 0.28), 0.45, 0.6)
	# Lamp post: base, fluted tapered pole, curved arm, lantern head.
	var lp:= Vector3(2.0, 0.15, 5.6)
	_cyl(0.18, 0.5, lp + Vector3(0, 0.25, 0), iron, Basis.IDENTITY, 24, 0.12)
	_cyl(0.075, 5.6, lp + Vector3(0, 3.3, 0), iron, Basis.IDENTITY, 16, 0.05)
	var prev:= lp + Vector3(0, 6.0, 0)
	for k in range(1, 9):
		var a:= float(k) / 8.0 * PI * 0.5
		var p:= lp + Vector3(0, 6.0 + sin(a) * 0.6, -(1.0 - cos(a)) * 0.6 - sin(a) * 0.5)
		_tube(prev, p, 0.04, iron, 10)
		prev = p
	var head:= prev + Vector3(0, -0.15, -0.1)
	_cyl(0.32, 0.12, head + Vector3(0, 0.05, 0), iron, Basis.IDENTITY, 24, 0.12)
	_cyl(0.22, 0.25, head + Vector3(0, -0.12, 0), _glow(Color(1.0, 0.82, 0.55), 3.0 if night else 0.3), Basis.IDENTITY, 24, 0.28)
	if night:
		var sl:= SpotLight3D.new()
		sl.light_color = Color(1.0, 0.75, 0.45) if style == "c" else Color(1.0, 0.82, 0.55)
		sl.light_energy = 6.0
		sl.spot_range = 16.0
		sl.spot_angle = 60.0
		sl.shadow_enabled = true
		sl.position = head + Vector3(0, -0.3, 0)
		sl.rotation_degrees = Vector3(-90, 0, 0)
		root3d.add_child(sl)
	# Fire hydrant.
	var red:= _pbr(Color(0.7, 0.1, 0.08) if style == "c" else Color(0.9, 0.15, 0.1), 0.45, 0.2)
	var hp:= Vector3(4.6, 0.15, 5.7)
	_cyl(0.16, 0.12, hp + Vector3(0, 0.06, 0), red)
	_cyl(0.12, 0.55, hp + Vector3(0, 0.38, 0), red)
	_cyl(0.14, 0.08, hp + Vector3(0, 0.68, 0), red)
	var dome:= MeshInstance3D.new()
	var sm:= SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.12
	sm.is_hemisphere = true
	dome.mesh = sm
	dome.material_override = red
	dome.position = hp + Vector3(0, 0.72, 0)
	root3d.add_child(dome)
	for s: float in [-1.0, 1.0]:
		_tube(hp + Vector3(s * 0.1, 0.45, 0), hp + Vector3(s * 0.22, 0.45, 0), 0.05, red, 12)
	# Bench by the wall: cast iron ends, wooden slats.
	var wood:= _pbr(Color(0.42, 0.28, 0.16) if style == "c" else Color(0.6, 0.38, 0.2), 0.8)
	var bp:= Vector3(-4.0, 0.15, 8.6)
	for k in 4:
		_box(Vector3(1.8, 0.04, 0.09), bp + Vector3(0, 0.45, -0.2 + k * 0.11), wood)
	for k in 3:
		_box(Vector3(1.8, 0.09, 0.03), bp + Vector3(0, 0.62 + k * 0.12, 0.25), wood, Basis(Vector3.RIGHT, -0.15))
	for s: float in [-0.8, 0.8]:
		_box(Vector3(0.06, 0.45, 0.5), bp + Vector3(s, 0.22, 0), iron)
		_box(Vector3(0.06, 0.45, 0.06), bp + Vector3(s, 0.7, 0.24), iron)
	# Tree in a grated pit.
	var tp:= Vector3(-7.0, 0.15, 6.6)
	_box(Vector3(1.3, 0.02, 1.3), tp + Vector3(0, 0.01, 0), iron)
	_tree(tp)
	# Trash can.
	_cyl(0.28, 0.9, Vector3(0.3, 0.6, 8.9), _pbr(Color(0.15, 0.25, 0.18), 0.6, 0.4), Basis.IDENTITY, 28)


func _playground() -> void:
	var real:= style == "c"
	var mat_floor:= _ground_mat("rubber")
	_box(Vector3(8, 0.04, 3.4), Vector3(17.5, 0.17, 7.4), mat_floor)
	var blue:= _pbr(Color(0.15, 0.3, 0.55) if real else Color(0.2, 0.45, 0.9), 0.4, 0.5 if real else 0.2)
	var yel:= _pbr(Color(0.85, 0.65, 0.1) if real else Color(1.0, 0.82, 0.2), 0.5, 0.2)
	var steel:= _pbr(Color(0.7, 0.7, 0.72), 0.3, 1.0)
	var rubber:= _pbr(Color(0.06, 0.06, 0.06), 0.9)
	# Swing set: A-frames of tube, a top beam, two swings on chains of real links.
	var sp:= Vector3(15.0, 0.19, 7.4)
	var hgt:= 2.4
	for ex: float in [-1.6, 1.6]:
		for lean: float in [-1.0, 1.0]:
			_tube(sp + Vector3(ex, 0, lean * 0.9), sp + Vector3(ex, hgt, 0), 0.05, blue, 20)
	_tube(sp + Vector3(-1.75, hgt, 0), sp + Vector3(1.75, hgt, 0), 0.06, blue, 20)
	for sx: float in [-0.75, 0.75]:
		var seat_y:= 0.5
		for cz: float in [-0.2, 0.2]:
			var y:= hgt - 0.05
			var link:= 0
			if not P.detail or look in ["comic", "storybook"]:
				_tube(sp + Vector3(sx, y, cz), sp + Vector3(sx, seat_y, cz), 0.018 if look != "cartoon" else 0.03, steel, 8)
				y = -1.0
			while y > seat_y + 0.05:
				var tor:= MeshInstance3D.new()
				var tmesh:= TorusMesh.new()
				tmesh.inner_radius = 0.012
				tmesh.outer_radius = 0.026
				tmesh.rings = 10
				tmesh.ring_segments = 6
				tor.mesh = tmesh
				tor.material_override = steel
				tor.transform = Transform3D(Basis(Vector3.UP, PI * 0.5 * (link % 2)) * Basis(Vector3.RIGHT, PI * 0.5), sp + Vector3(sx, y, cz))
				root3d.add_child(tor)
				y -= 0.045
				link += 1
		# curved rubber strap seat
		for k in 7:
			var t:= (k - 3) / 3.0
			_box(Vector3(0.14, 0.02, 0.07), sp + Vector3(sx, seat_y + t * t * 0.06, t * 0.21), rubber, Basis(Vector3.RIGHT, -t * 0.4))
	# Slide: ladder, platform with rails and a curved chute.
	var sl:= Vector3(19.5, 0.19, 7.0)
	var ph:= 1.5
	for dx: float in [-0.35, 0.35]:
		for dz: float in [-0.35, 0.35]:
			_tube(sl + Vector3(dx, 0, dz), sl + Vector3(dx, ph + 0.9, dz), 0.04, yel, 16)
	_box(Vector3(0.8, 0.06, 0.8), sl + Vector3(0, ph, 0), _pbr(Color(0.35, 0.3, 0.25), 0.8))
	for k in 5:
		_tube(sl + Vector3(-0.35, 0.3 * k + 0.25, -0.35), sl + Vector3(-0.35, 0.3 * k + 0.25, 0.35), 0.022, yel, 10)
	_tube(sl + Vector3(0.35, ph + 0.85, -0.35), sl + Vector3(0.35, ph + 0.85, 0.35), 0.03, yel, 12)
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n:= 24
	var prof:= 12
	for i in n:
		for j in prof:
			var quad: Array[Vector3] = []
			for d in [[0, 0], [1, 0], [1, 1], [0, 1]]:
				var t:= float(i + d[0]) / n
				var a:= PI * (0.15 + 0.7 * float(j + d[1]) / prof)
				var along:= Vector3(0.4 + t * 2.6, ph - t * ph * 0.92 + sin(t * PI) * 0.15 - 0.0, 0)
				quad.append(sl + along + Vector3(0, -sin(a) * 0.22 + 0.22, cos(a) * 0.3))
			st.add_vertex(quad[0]); st.add_vertex(quad[1]); st.add_vertex(quad[2])
			st.add_vertex(quad[0]); st.add_vertex(quad[2]); st.add_vertex(quad[3])
	st.generate_normals()
	var chute:= MeshInstance3D.new()
	chute.mesh = st.commit()
	var cm:= _pbr(Color(0.75, 0.15, 0.12) if real else Color(0.95, 0.3, 0.2), 0.25, 0.1)
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	chute.material_override = cm
	root3d.add_child(chute)


func _car() -> void:
	var toon:= look in ["cartoon", "clay", "storybook", "paper"]
	var scene:= load("res://preview/car_toon.glb" if toon else "res://preview/car_sedan.glb") as PackedScene
	if scene == null:
		return
	var car:= scene.instantiate() as Node3D
	root3d.add_child(car)
	car.position = Vector3(-1.5, 0.0, 3.6)
	car.rotation.y = PI * 0.5
	car.set_meta("car", true)
	if toon:
		car.position.x += 0.4
	var real:= style == "c"
	var paint:= StandardMaterial3D.new()
	paint.albedo_color = Color(0.45, 0.04, 0.05) if real else Color(0.1, 0.55, 0.65)
	var paints:= {"cartoon": Color(1.0, 0.45, 0.1), "clay": Color(0.85, 0.2, 0.2), "storybook": Color(0.9, 0.7, 0.2),
		"paper": Color(0.25, 0.5, 0.85), "lowpoly": Color(0.95, 0.5, 0.2), "ps1": Color(0.5, 0.12, 0.1),
		"voxel": Color(0.15, 0.3, 0.6), "comic": Color(0.95, 0.75, 0.1)}
	if paints.has(look):
		paint.albedo_color = paints[look]
	paint.metallic = 0.55 if real else 0.15
	paint.roughness = 0.22 if real else 0.3
	paint.clearcoat_enabled = true
	paint.clearcoat = 1.0
	paint.clearcoat_roughness = 0.05
	paint.vertex_color_use_as_albedo = true
	var chrome:= _pbr(Color(0.85, 0.86, 0.88), 0.12, 1.0)
	chrome.vertex_color_use_as_albedo = true
	var glass:= _pbr(Color(0.9, 0.95, 1.0), 0.03, 0.6)
	glass.vertex_color_use_as_albedo = true
	var rubber:= _pbr(Color(1, 1, 1), 0.85)
	rubber.vertex_color_use_as_albedo = true
	for mi in car.find_children("*", "MeshInstance3D", true, false):
		var m:= mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var nm:= str(m.mesh.surface_get_material(i).resource_name) if m.mesh.surface_get_material(i) else ""
			var mat: Material = {"body": paint, "metal": chrome, "shiny": glass, "cloth": rubber}.get(nm, paint)
			m.set_surface_override_material(i, mat)
	if night:
		for s: float in [-1.0, 1.0]:
			var hl:= SpotLight3D.new()
			hl.light_energy = 0.0
			car.add_child(hl)


func _people() -> void:
	var ow:= {"cartoon": 0.014, "comic": 0.0, "b": 0.012, "c": 0.012}.get(look, 0.0) as float
	var ph:= CharacterModel.load_model("res://models/photographer.glb", ow)
	ph.set_meta("char", true)
	if scene != "city":
		_wild_people(ph, ow)
		return
	root3d.add_child(ph)
	ph.position = Vector3(0.6, 0.15, 6.4)
	ph.rotation.y = -0.4
	ph.play("idle")
	var cr:= CharacterModel.load_model("res://models/methman.glb", ow * 1.15)
	cr.set_meta("char", true)
	root3d.add_child(cr)
	cr.position = Vector3(6.8, 0.15, 7.6)
	cr.rotation.y = -2.4
	cr.play("idle")


func _camera() -> void:
	var cam:= Camera3D.new()
	cam.fov = 62
	root3d.add_child(cam)
	var views:= {"1": [Vector3(1.0, 1.7, -8.5), Vector3(2.5, 3.2, 8.0)], "2": [Vector3(5.5, 1.5, 0.6), Vector3(-1.0, 1.0, 5.4)],
		"3": [Vector3(-5.5, 1.6, 0.0), Vector3(-1.5, 0.7, 3.6)], "4": [Vector3(3.5, 2.0, 0.5), Vector3(-1.5, 0.7, 3.6)]}
	if scene == "woods":
		views = {"1": [Vector3(-0.5, 1.75, -10.0), Vector3(1.0, 1.6, 5.0)], "2": [Vector3(4.6, 1.3, -3.2), Vector3(-4.0, 1.8, 8.5)]}
	elif scene == "lake":
		views = {"1": [Vector3(5.5, 1.9, 9.5), Vector3(-1.5, 0.0, -12.0)], "2": [Vector3(2.4, 1.45, -11.2), Vector3(-3.0, 1.0, 5.0)]}
	var v: Array = views.get(OS.get_environment("CAM"), views["1"])
	cam.transform = Transform3D(Basis.looking_at(v[1] - v[0], Vector3.UP), v[0])
	cam.current = true



# ------------------------------------------------------------------ art styles

func _look_env(e: Environment, sm: ProceduralSkyMaterial) -> void:
	if night:
		match look:
			"ps1":
				e.fog_density = 0.07
				e.fog_light_color = Color(0.02, 0.02, 0.03)
			"lowpoly":
				e.fog_light_color = Color(0.1, 0.12, 0.25)
				e.fog_density = 0.02
			"clay", "cartoon", "paper", "storybook":
				e.ambient_light_energy *= 1.4
		return
	match look:
		"cartoon":
			sm.sky_top_color = Color(0.15, 0.45, 1.0)
			sm.sky_horizon_color = Color(0.6, 0.85, 1.0)
			e.adjustment_saturation = 1.3
			e.ambient_light_energy = 1.2
		"lowpoly":
			sm.sky_top_color = Color(0.3, 0.45, 0.7)
			sm.sky_horizon_color = Color(1.0, 0.68, 0.42)
			sm.ground_horizon_color = Color(0.9, 0.55, 0.35)
			e.fog_light_color = Color(1.0, 0.66, 0.42)
			e.fog_density = 0.006
			e.fog_sky_affect = 0.4
			e.adjustment_saturation = 1.15
		"clay":
			sm.sky_top_color = Color(0.45, 0.65, 0.95)
			sm.sky_horizon_color = Color(0.9, 0.93, 1.0)
			e.ambient_light_energy = 1.5
			e.adjustment_saturation = 1.1
		"comic":
			sm.sky_top_color = Color(0.1, 0.55, 0.9)
			sm.sky_horizon_color = Color(0.75, 0.92, 1.0)
			e.adjustment_saturation = 1.3
			e.ambient_light_energy = 1.5
			e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		"storybook":
			sm.sky_top_color = Color(0.4, 0.58, 0.88)
			sm.sky_horizon_color = Color(1.0, 0.88, 0.72)
			e.fog_light_color = Color(0.85, 0.8, 0.9)
			e.fog_density = 0.005
			e.fog_sky_affect = 0.2
			e.ambient_light_energy = 1.2
		"ps1":
			sm.sky_top_color = Color(0.45, 0.5, 0.58)
			sm.sky_horizon_color = Color(0.6, 0.62, 0.65)
			e.fog_light_color = Color(0.58, 0.6, 0.63)
			e.fog_density = 0.028
			e.fog_sky_affect = 0.8
			e.adjustment_saturation = 0.8
		"paper":
			sm.sky_top_color = Color(0.45, 0.7, 0.92)
			sm.sky_horizon_color = Color(0.98, 0.93, 0.8)
			e.ambient_light_energy = 1.1
			e.fog_enabled = false
		"voxel":
			e.adjustment_saturation = 1.05
		"hyper":
			e.tonemap_exposure = 1.0
			e.adjustment_contrast = 1.1
			e.fog_density = 0.006


func _look_sun(sun: DirectionalLight3D) -> void:
	if night:
		return
	match look:
		"lowpoly":
			sun.light_color = Color(1.0, 0.72, 0.48)
			sun.rotation_degrees = Vector3(-22, 55, 0)
			sun.light_energy = 1.5
		"storybook":
			sun.light_color = Color(1.0, 0.86, 0.66)
		"clay":
			sun.light_energy = 1.1
		"cartoon":
			sun.light_energy = 1.4
		"comic":
			sun.light_energy = 1.4
			sun.rotation_degrees = Vector3(-40, 150, 0)
		"ps1":
			sun.light_energy = 0.9
			sun.shadow_enabled = false


## One street tree, built the way each style would build it.
func _tree(tp: Vector3) -> void:
	var green:= Color(0.32, 0.5, 0.2) if style == "c" else Color(0.4, 0.72, 0.3)
	var bark:= _pbr(Color(0.42, 0.3, 0.2), 0.9)
	match look:
		"cartoon", "clay", "voxel":
			_cyl(0.16, 3.0, tp + Vector3(0, 1.5, 0), bark, Basis.IDENTITY, 16, 0.1)
			var leaf:= _pbr(Color(0.3, 0.75, 0.25) if look != "voxel" else Color(0.25, 0.45, 0.16), 0.8)
			for b: Array in [[Vector3(0, 3.6, 0), 1.25], [Vector3(-0.8, 3.2, 0.3), 0.85], [Vector3(0.75, 3.3, -0.2), 0.9], [Vector3(0.1, 4.3, 0.2), 0.8]]:
				_ball(tp + b[0], b[1], leaf, 32)
		"storybook":
			var prev:= tp
			for k in range(1, 8):
				var t:= k / 7.0
				var p:= tp + Vector3(sin(t * 3.0) * 0.45, t * 3.4, cos(t * 2.0) * 0.2 - 0.2)
				_tube(prev, p, lerpf(0.2, 0.09, t), bark, 12)
				prev = p
			var leaf:= _pbr(Color(0.42, 0.66, 0.3), 0.9)
			for k in 6:
				var a:= k * 1.1
				_ball(prev + Vector3(cos(a) * 0.7, 0.3 + sin(k * 1.7) * 0.4, sin(a) * 0.5), 0.75 - k * 0.05, leaf, 24)
		"lowpoly":
			_cyl(0.18, 3.0, tp + Vector3(0, 1.5, 0), bark, Basis.IDENTITY, 5, 0.1)
			var leaf:= _pbr(Color(0.35, 0.6, 0.25), 1.0)
			_ball(tp + Vector3(0, 3.5, 0), 1.3, leaf, 6)
			_ball(tp + Vector3(0.3, 4.5, 0.1), 0.9, _pbr(Color(0.45, 0.7, 0.28), 1.0), 6)
		"ps1":
			_cyl(0.16, 3.2, tp + Vector3(0, 1.6, 0), bark, Basis.IDENTITY, 6, 0.1)
			var lm:= StandardMaterial3D.new()
			lm.albedo_texture = K.pixel_tex("leaves")
			lm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			lm.cull_mode = BaseMaterial3D.CULL_DISABLED
			lm.roughness = 1.0
			lm.set_meta("keep", true)
			for k in 3:
				var q:= MeshInstance3D.new()
				var qm:= QuadMesh.new()
				qm.size = Vector2(3.2, 3.0)
				q.mesh = qm
				q.material_override = lm
				q.position = tp + Vector3(0, 3.8, 0)
				q.rotation.y = k * PI / 3.0
				root3d.add_child(q)
		"paper":
			_box(Vector3(0.35, 3.2, 0.03), tp + Vector3(0, 1.6, 0), bark)
			var shades: Array[Color] = [Color(0.3, 0.6, 0.3), Color(0.4, 0.72, 0.35), Color(0.5, 0.8, 0.4)]
			for k in 3:
				var disc:= _cyl(1.25 - k * 0.25, 0.03, tp + Vector3(k * 0.15 - 0.15, 3.7 + k * 0.35, -0.05 - k * 0.05), _pbr(shades[k], 0.9), Basis(Vector3.RIGHT, PI * 0.5), 32)
				disc.set_meta("flat", true)
		_:
			var trunk:= MeshInstance3D.new()
			trunk.mesh = PlantMeshes.trunk_hi(3, 4.6, 0.2, 0.09, false, 3, 0)
			var tm:= StandardMaterial3D.new()
			tm.vertex_color_use_as_albedo = true
			tm.albedo_color = Color(0.45, 0.33, 0.24)
			trunk.material_override = tm
			trunk.position = tp
			trunk.scale = Vector3.ONE * 0.85
			root3d.add_child(trunk)
			var crown:= MeshInstance3D.new()
			crown.mesh = PlantMeshes.broadleaf_hi(1)
			var cm:= StandardMaterial3D.new()
			cm.vertex_color_use_as_albedo = true
			cm.albedo_color = green
			cm.cull_mode = BaseMaterial3D.CULL_DISABLED
			crown.material_override = cm
			crown.position = tp
			crown.scale = Vector3.ONE * 0.85
			root3d.add_child(crown)


func _ball(at: Vector3, r: float, mat: Material, segs: int) -> MeshInstance3D:
	var mi:= MeshInstance3D.new()
	var sm:= SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = segs
	sm.rings = maxi(3, segs / 2)
	mi.mesh = sm
	mi.material_override = mat
	mi.position = at
	root3d.add_child(mi)
	return mi


func _is_char(n: Node) -> bool:
	while n != null:
		if n.has_meta("char"):
			return true
		n = n.get_parent()
	return false


func _is_car(n: Node) -> bool:
	while n != null:
		if n.has_meta("car"):
			return true
		n = n.get_parent()
	return false


var _noise:= FastNoiseLite.new()

## Shape changes: bent and wonky (storybook), lumpy (clay), faceted (low-poly), fewer polygons
## (PS1), flat cards (paper).
func _restyle_geometry() -> void:
	_noise.seed = 11
	_noise.frequency = 1.0
	var meshes:= root3d.find_children("*", "MeshInstance3D", true, false)
	for n in meshes:
		var mi:= n as MeshInstance3D
		if mi.mesh == null:
			continue
		var ch:= _is_char(mi)
		var car:= _is_car(mi)
		match look:
			"lowpoly":
				if ch or car:
					mi.mesh = K.decimate(mi.mesh, 0.08 if car else 0.2, true)
				elif mi.mesh.get_faces().size() < 60000:
					K.reshape(mi, func(p: Vector3, _n: Vector3) -> Vector3:
						return p + Vector3(_noise.get_noise_3dv(p * 0.9), _noise.get_noise_3dv(p * 0.9 + Vector3(40, 0, 0)), _noise.get_noise_3dv(p * 0.9 + Vector3(0, 0, 40))) * 0.08, true)
			"ps1":
				if ch or car:
					mi.mesh = K.decimate(mi.mesh, 0.06 if car else 0.15, false)
			"paper":
				if mi.has_meta("flat") or mi.has_meta("ground"):
					continue
				var aabb:= mi.global_transform * mi.get_aabb()
				if mi.mesh is ArrayMesh and not ch and not car and aabb.size.z <= 0.05:
					continue
				if aabb.size.y < 0.3 and not ch:
					continue
				if ch or car:
					continue
				mi.global_transform = Transform3D(Basis.from_scale(Vector3(1, 1, 0.06)) * mi.global_transform.basis, mi.global_transform.origin)
	if look == "paper":
		# Characters and the car become stand-up cut-outs.
		for n in root3d.get_children():
			if n.has_meta("char") or n.has_meta("car"):
				var n3:= n as Node3D
				n3.transform = Transform3D(Basis.from_scale(Vector3(1, 1, 0.07)) * n3.transform.basis, n3.transform.origin)


var _mat_cache:= {}

func _restyle_materials() -> void:
	if look in ["b", "c", "hyper", "voxel"]:
		return
	for n in root3d.find_children("*", "MeshInstance3D", true, false):
		var mi:= n as MeshInstance3D
		if mi.mesh == null:
			continue
		var ch:= _is_char(mi)
		for i in mi.mesh.get_surface_count():
			var m: Material = mi.material_override
			if m == null:
				m = mi.get_surface_override_material(i)
			if m == null:
				m = mi.mesh.surface_get_material(i)
			if m == null or m.has_meta("keep"):
				continue
			if not _mat_cache.has(m):
				_mat_cache[m] = _style_mat(m, ch)
			mi.set_surface_override_material(i, _mat_cache[m])
		if mi.material_override and not mi.material_override.has_meta("keep"):
			mi.material_override = null


func _style_mat(m: Material, ch: bool) -> Material:
	var col:= Color(1, 1, 1)
	var vc:= false
	var emit:= Color.BLACK
	var kind:= ""
	var rough:= 0.8
	var metal:= 0.0
	if m is BaseMaterial3D:
		var b:= m as BaseMaterial3D
		col = b.albedo_color
		vc = b.vertex_color_use_as_albedo
		rough = b.roughness
		metal = b.metallic
		if b.emission_enabled:
			emit = b.emission * b.emission_energy_multiplier
	elif m is ShaderMaterial:
		var params: Dictionary = m.get_meta("params", {})
		col = params.get("base_col", Color(0.6, 0.6, 0.6))
		kind = "brick" if params.has("bw") else ["asphalt", "slab", "grass", "rubber"][int(params.get("kind", 0.0))]
		if look == "cartoon":
			return m
	match look:
		"cartoon":
			var b:= (m as BaseMaterial3D).duplicate() as BaseMaterial3D
			b.albedo_color = Color.from_hsv(col.h, minf(col.s * 1.15, 1.0), minf(col.v * 1.05, 1.0))
			b.clearcoat_enabled = false
			b.metallic = metal * 0.4
			b.roughness = maxf(rough, 0.45)
			if not ch:
				b.rim_enabled = true
				b.rim = 0.3
				b.rim_tint = 0.4
				b.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
			return b
		"lowpoly":
			var b:= StandardMaterial3D.new()
			b.albedo_color = col if metal < 0.5 else col.darkened(0.3)
			b.vertex_color_use_as_albedo = vc
			b.roughness = 1.0
			b.metallic_specular = 0.2
			if emit != Color.BLACK:
				b.emission_enabled = true
				b.emission = emit
			return b
		"clay":
			var cc:= Color.from_hsv(col.h, minf(col.s * 1.2, 1.0), clampf(col.v * 1.1, 0.12, 1.0))
			return K.clay(cc if metal < 0.7 else cc.darkened(0.2), vc, emit, 0.0 if ch else 0.09)
		"comic":
			return K.comic(Color(minf(col.r * 1.35, 1.0), minf(col.g * 1.35, 1.0), minf(col.b * 1.35, 1.0)), vc, sun_dir, emit)
		"storybook":
			return K.painted(col, vc, emit, 0.0 if ch else 1.0)
		"paper":
			return K.paper(col, vc, emit)
		"ps1":
			var tex: Texture2D = null
			var tm:= 1.0
			match kind:
				"brick":
					tex = K.pixel_tex("brick")
					tm = 1.4
				"asphalt":
					tex = K.pixel_tex("asphalt")
					tm = 3.0
				"slab":
					tex = K.pixel_tex("slab")
					tm = 3.0
				"grass":
					tex = K.pixel_tex("grass")
					tm = 2.0
			return K.ps1(col, vc, tex, tm, emit)
	return m


## Voxel look: everything near the camera re-made from 10 cm cubes (posed characters too).
func _voxelize() -> void:
	var vox:= 0.1
	var clip:= AABB(Vector3(-24, -0.4, -10), Vector3(50, 16, 30))
	if scene == "woods":
		vox = 0.12
		clip = AABB(Vector3(-18, -4, -12), Vector3(36, 16, 40))
	elif scene == "lake":
		vox = 0.12
		clip = AABB(Vector3(-20, -4, -62), Vector3(40, 16, 78))
	for n in root3d.find_children("*", "MeshInstance3D", true, false):
		var mi:= n as MeshInstance3D
		if mi.skin != null or _is_char(mi):
			var baked:= mi.bake_mesh_from_current_skeleton_pose()
			if baked:
				mi.skeleton = NodePath()
				mi.skin = null
				mi.mesh = baked
	var cells:= K.voxelize(root3d, vox, clip, _vox_colour)
	for n in root3d.find_children("*", "MeshInstance3D", true, false):
		var mi:= n as MeshInstance3D
		var aabb:= mi.global_transform * mi.get_aabb()
		if clip.encloses(aabb):
			mi.visible = false
	root3d.add_child(K.voxel_nodes(cells, vox))
	print("voxels: ", cells.size())


func _vox_colour(mi: MeshInstance3D, s: int, p: Vector3, vcol: Color) -> Color:
	var m: Material = mi.material_override
	if m == null:
		m = mi.get_surface_override_material(s)
	if m == null:
		m = mi.mesh.surface_get_material(s)
	var h:= fposmod(sin(p.dot(Vector3(12.9898, 78.233, 37.719))) * 43758.5453, 1.0)
	if m is ShaderMaterial:
		var params: Dictionary = m.get_meta("params", {})
		var base: Color = params.get("base_col", Color(0.5, 0.5, 0.5))
		if params.has("bw"):
			var row:= floori(p.y / 0.1 + 0.01)
			var u:= floori((p.x + p.z) / 0.2 + 0.5 * (row % 2))
			var bh:= fposmod(sin(float(u * 131 + row * 71)) * 43758.5453, 1.0)
			var c:= base * (0.8 + 0.35 * bh)
			if bh > 0.93:
				c = base * Color(0.6, 0.5, 0.48)
			return Color(c.r, c.g, c.b, 1.0)
		var kd:= int(params.get("kind", 0.0))
		if kd == 1 and (fposmod(p.x, 1.5) < 0.1 or fposmod(p.z, 1.5) < 0.1):
			return Color(base.r * 0.75, base.g * 0.75, base.b * 0.75, 1.0)
		var v:= 0.85 + 0.3 * h if kd != 2 else 0.7 + 0.5 * h
		return Color(base.r * v, base.g * v, base.b * v, 1.0)
	if m is BaseMaterial3D:
		var b:= m as BaseMaterial3D
		var c:= b.albedo_color
		if b.vertex_color_use_as_albedo:
			c = Color(c.r * vcol.r, c.g * vcol.g, c.b * vcol.b)
		c = c * (0.93 + 0.12 * h)
		if b.emission_enabled and b.emission_energy_multiplier > 0.8:
			return Color(b.emission.r, b.emission.g, b.emission.b, 2.0)
		return Color(c.r, c.g, c.b, 1.0)
	return Color(0.6, 0.6, 0.6, 1.0)


## Hyperreal extras: rooms behind the windows, curtains and blinds, a gutter and downspout,
## real grass in the lawn, puddles, litter and leaves, a parking meter and street signs.
func _hyper_details() -> void:
	var front:= 9.4
	var floor_h: float = P.floor_h
	var bay_w: float = 16.0 / float(P.bays)
	var r2:= RandomNumberGenerator.new()
	r2.seed = 5
	var walls: Array[Color] = [Color(0.75, 0.68, 0.55), Color(0.55, 0.62, 0.6), Color(0.8, 0.76, 0.7), Color(0.6, 0.5, 0.45)]
	var cloth: Array[Color] = [Color(0.85, 0.82, 0.72), Color(0.5, 0.12, 0.12), Color(0.2, 0.3, 0.45), Color(0.9, 0.9, 0.88)]
	for f in range(1, P.floors):
		var sill_y:= 0.15 + floor_h * f + 0.85
		for b in P.bays:
			var cx: float = -10.0 + (b + 0.5) * bay_w
			# room: back wall, a dividing wall, a picture or a shelf, seen through the glass
			var wc:= walls[r2.randi() % 4]
			_box(Vector3(bay_w, floor_h - 0.2, 0.05), Vector3(cx, 0.15 + floor_h * f + floor_h * 0.5, front + 3.25), _pbr(wc, 0.9))
			if b % 2 == 0:
				_box(Vector3(0.1, floor_h - 0.2, 2.9), Vector3(cx - bay_w * 0.5, 0.15 + floor_h * f + floor_h * 0.5, front + 1.8), _pbr(wc.darkened(0.1), 0.9))
			if r2.randf() < 0.6:
				_box(Vector3(0.7, 0.5, 0.03), Vector3(cx + r2.randf_range(-0.4, 0.4), 0.15 + floor_h * f + 1.6, front + 3.21), _pbr(Color(r2.randf(), r2.randf() * 0.6, r2.randf() * 0.4), 0.6))
			else:
				_box(Vector3(1.0, 1.9, 0.35), Vector3(cx + 0.3, 0.15 + floor_h * f + 0.95, front + 3.05), _pbr(Color(0.35, 0.22, 0.14), 0.7))
			var kind:= r2.randi() % 3
			var c:= cloth[r2.randi() % 4]
			if kind == 0:
				for side: float in [-1.0, 1.0]:
					_box(Vector3(0.35, P.win_h - 0.1, 0.03), Vector3(cx + side * (P.win_w * 0.5 - 0.2), sill_y + P.win_h * 0.5, front + 0.3), _pbr(c, 0.95))
			elif kind == 1:
				var drop:= r2.randf_range(0.3, 1.2)
				for k in int(drop / 0.05):
					_box(Vector3(P.win_w - 0.1, 0.035, 0.02), Vector3(cx, sill_y + P.win_h - 0.06 - k * 0.05, front + 0.3), _pbr(Color(0.88, 0.86, 0.8), 0.7), Basis(Vector3.RIGHT, 0.5))
	# Shop interiors: shelves of goods, a counter, strip lights.
	for span: Array in [[-9.2, -4.4], [-0.6, 5.2]]:
		var w: float = span[1] - span[0]
		var cx2: float = (span[0] + span[1]) * 0.5
		_box(Vector3(w, 3.0, 0.05), Vector3(cx2, 1.65, front + 3.2), _pbr(Color(0.9, 0.88, 0.82), 0.8))
		for row in 4:
			_box(Vector3(w - 0.4, 0.04, 0.4), Vector3(cx2, 0.5 + row * 0.55, front + 2.95), _pbr(Color(0.75, 0.75, 0.75), 0.4, 0.6))
			var gx: float = span[0] + 0.3
			while gx < span[1] - 0.3:
				var gw:= r2.randf_range(0.08, 0.2)
				var gh:= r2.randf_range(0.15, 0.4)
				_box(Vector3(gw, gh, 0.15), Vector3(gx + gw * 0.5, 0.52 + row * 0.55 + gh * 0.5, front + 2.95), _pbr(Color.from_hsv(r2.randf(), r2.randf_range(0.4, 0.9), r2.randf_range(0.5, 0.95)), 0.6))
				gx += gw + 0.03
		_box(Vector3(1.6, 1.0, 0.6), Vector3(cx2 - 0.5, 0.65, front + 1.4), _pbr(Color(0.3, 0.2, 0.14), 0.6))
		_box(Vector3(w - 0.6, 0.04, 0.12), Vector3(cx2, 3.1, front + 1.6), _glow(Color(0.95, 0.97, 1.0), 2.0))
	# The glass becomes see-through with a reflective sheen.
	for n in root3d.find_children("*", "MeshInstance3D", true, false):
		var mi:= n as MeshInstance3D
		var gm:= mi.material_override as StandardMaterial3D
		if gm and gm.metallic > 0.8 and gm.albedo_color.v < 0.15 and gm.roughness < 0.1:
			var g2:= gm.duplicate() as StandardMaterial3D
			g2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			g2.albedo_color = Color(0.1, 0.12, 0.13, 0.35)
			g2.metallic = 0.3
			g2.roughness = 0.02
			mi.material_override = g2
	# Gutter and downspout at the building's right end.
	var zinc:= _pbr(Color(0.55, 0.56, 0.55), 0.5, 0.8)
	var top: float = 0.15 + floor_h * float(P.floors)
	_tube(Vector3(5.8, 0.2, front - 0.15), Vector3(5.8, top - 0.3, front - 0.15), 0.05, zinc, 12)
	for k in int(top / 1.5):
		_box(Vector3(0.14, 0.03, 0.18), Vector3(5.8, 0.6 + k * 1.5, front - 0.08), zinc)
	_box(Vector3(0.12, 0.08, 0.35), Vector3(5.8, 0.24, front - 0.32), zinc)
	# Grass blades in the lawn.
	var mm:= MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = PlantMeshes.grass_tuft(0)
	mm.instance_count = 2600
	for i in mm.instance_count:
		var p:= Vector3(r2.randf_range(11.2, 22.8), 0.16, r2.randf_range(5.3, 9.3))
		if p.x > 13.4 and p.x < 21.6 and p.z > 5.7 and p.z < 9.1:
			p.x = r2.randf_range(11.2, 13.3)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, r2.randf() * TAU).scaled(Vector3.ONE * r2.randf_range(0.5, 0.9)), p))
		mm.set_instance_color(i, Color(0.75, 0.85, 0.6).lerp(Color(1.0, 0.95, 0.7), r2.randf() * 0.4))
	var gmi:= MultiMeshInstance3D.new()
	gmi.multimesh = mm
	var gmat:= StandardMaterial3D.new()
	gmat.vertex_color_use_as_albedo = true
	gmat.albedo_color = Color(0.4, 0.55, 0.25)
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	gmat.roughness = 0.9
	gmi.material_override = gmat
	root3d.add_child(gmi)
	# Puddles along the gutter, mirror-smooth.
	var pud:= K.shader_mat("""
shader_type spatial;
render_mode cull_disabled;
varying vec3 wpos;
""" + K.NOISE + """
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float n = fbm(wpos.xz * 0.9) + 0.3 * fbm(wpos.xz * 4.0);
	if (n < 0.56) discard;
	ALBEDO = vec3(0.03, 0.035, 0.04);
	ROUGHNESS = 0.03;
	METALLIC = 0.0;
	SPECULAR = 0.9;
}
""")
	for px: float in [-12.0, -3.0, 8.0]:
		var q:= MeshInstance3D.new()
		var pm:= PlaneMesh.new()
		pm.size = Vector2(5.0, 1.8)
		q.mesh = pm
		q.material_override = pud
		q.position = Vector3(px, 0.012, 4.0)
		root3d.add_child(q)
	# Litter and fallen leaves.
	var leaf_cols: Array[Color] = [Color(0.55, 0.35, 0.12), Color(0.7, 0.5, 0.15), Color(0.4, 0.3, 0.12)]
	for i in 90:
		var a:= r2.randf() * TAU
		var d:= r2.randf_range(0.4, 3.5)
		var lp:= Vector3(-7.0 + cos(a) * d, 0.152, 6.6 + sin(a) * d * 0.6)
		if lp.z < 5.1:
			lp.y = 0.003
		_box(Vector3(0.07, 0.003, 0.05), lp, _pbr(leaf_cols[i % 3], 0.9), Basis(Vector3.UP, r2.randf() * TAU) * Basis(Vector3.RIGHT, r2.randf_range(-0.2, 0.2)))
	_cyl(0.033, 0.12, Vector3(1.4, 0.2, 7.9), _pbr(Color(0.75, 0.1, 0.1), 0.3, 0.9), Basis(Vector3.FORWARD, PI * 0.5), 16)
	_box(Vector3(0.22, 0.004, 0.28), Vector3(-1.8, 0.152, 6.2), _pbr(Color(0.92, 0.92, 0.88), 0.9), Basis(Vector3.UP, 0.4))
	# Parking meter and a no-parking sign.
	var steel:= _pbr(Color(0.35, 0.36, 0.38), 0.4, 0.8)
	_cyl(0.035, 1.15, Vector3(-4.0, 0.72, 5.45), steel, Basis.IDENTITY, 12)
	_box(Vector3(0.2, 0.32, 0.14), Vector3(-4.0, 1.42, 5.45), _pbr(Color(0.2, 0.22, 0.24), 0.4, 0.6))
	_box(Vector3(0.12, 0.1, 0.01), Vector3(-4.0, 1.48, 5.37), _pbr(Color(0.05, 0.08, 0.06), 0.05, 0.5))
	_cyl(0.03, 2.6, Vector3(-9.0, 1.45, 5.45), steel, Basis.IDENTITY, 12)
	_box(Vector3(0.45, 0.6, 0.01), Vector3(-9.0, 2.5, 5.43), _pbr(Color(0.92, 0.92, 0.9), 0.5))
	var ns:= Label3D.new()
	ns.text = "NO\nPARKING\n8AM-6PM"
	ns.font_size = 48
	ns.pixel_size = 0.0035
	ns.modulate = Color(0.75, 0.08, 0.08)
	ns.outline_size = 0
	ns.position = Vector3(-9.0, 2.5, 5.42)
	ns.rotation.y = PI
	ns.shaded = true
	root3d.add_child(ns)


# ------------------------------------------------------------------ woods and lakeside

var _hn:= FastNoiseLite.new()
const WATER_Y:= -0.25

func _h(x: float, z: float) -> float:
	if scene == "woods":
		var d:= Vector2(x, z - 2.0).length()
		var hills:= _hn.get_noise_2d(x * 1.2, z * 1.2) * 2.2 + _hn.get_noise_2d(x * 5.0 + 50.0, z * 5.0) * 0.25
		var dp:= absf(x - _path_x(z))
		return hills * smoothstep(6.0, 15.0, d) * lerpf(0.5, 1.0, smoothstep(0.0, 4.0, dp))
	var shore:= sin(x * 0.09) * 2.5 + sin(x * 0.23 + 1.0) * 0.8
	var dd:= z - shore
	var near:= -0.4 + dd * 0.12 + _hn.get_noise_2d(x * 1.5, z * 1.5) * 0.6 * smoothstep(0.0, 8.0, dd) if dd > 0.0 else -0.4 + dd * 0.3
	var far:= -0.4 + (-42.0 - z + sin(x * 0.07) * 3.0) * 0.14 + _hn.get_noise_2d(x * 2.0, z * 2.0) * 0.5
	return maxf(maxf(near, far), -3.0)


func _path_x(z: float) -> float:
	return sin(z * 0.14) * 2.2


func _terrain(cx: float, cz: float, size: float, step: float, mat: Material) -> void:
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n:= int(size / step)
	for j in n + 1:
		for i in n + 1:
			var x:= cx - size * 0.5 + i * step
			var z:= cz - size * 0.5 + j * step
			st.add_vertex(Vector3(x, _h(x, z), z))
	for j in n:
		for i in n:
			var a:= j * (n + 1) + i
			var b:= a + 1
			var c:= a + n + 2
			var d:= a + n + 1
			for k in [a, b, c, a, c, d]:
				st.add_index(k)
	st.generate_normals()
	var mi:= MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.set_meta("ground", true)
	root3d.add_child(mi)


var _vmats:= {}
func _vmat(col: Color, vc: bool = true, two_sided: bool = false, emit: float = 0.0) -> StandardMaterial3D:
	var key:= "%s|%s|%s|%s" % [col, vc, two_sided, emit]
	if not _vmats.has(key):
		var m:= StandardMaterial3D.new()
		m.albedo_color = col
		m.vertex_color_use_as_albedo = vc
		m.roughness = 0.9
		if two_sided:
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if emit > 0.0:
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = emit
		_vmats[key] = m
	return _vmats[key]


func _mesh_at(mesh: Mesh, p: Vector3, sc: float, yaw: float, mat: Material) -> MeshInstance3D:
	var mi:= MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), p)
	root3d.add_child(mi)
	return mi


var _ps1_cards:= {}
func _cards(p: Vector3, size: Vector2, tex: String, n: int = 3) -> void:
	if not _ps1_cards.has(tex):
		var lm:= StandardMaterial3D.new()
		lm.albedo_texture = K.pixel_tex(tex)
		lm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		lm.cull_mode = BaseMaterial3D.CULL_DISABLED
		lm.roughness = 1.0
		lm.set_meta("keep", true)
		_ps1_cards[tex] = lm
	for k in n:
		var q:= MeshInstance3D.new()
		var qm:= QuadMesh.new()
		qm.size = size
		q.mesh = qm
		q.material_override = _ps1_cards[tex]
		q.position = p + Vector3(0, size.y * 0.5, 0)
		q.rotation.y = k * PI / n + 0.3
		root3d.add_child(q)


func _disc(p: Vector3, r: float, col: Color, dz: float = 0.0) -> void:
	var d:= _cyl(r, 0.03, p + Vector3(0, 0, dz), _pbr(col, 0.9), Basis(Vector3.RIGHT, PI * 0.5), 32)
	d.set_meta("flat", true)


## One plant, made the way each style would make it.
func _plant(kind: String, p: Vector3, sc: float, col: Color) -> void:
	var blobby:= look in ["cartoon", "clay", "voxel", "lowpoly", "storybook"]
	var yaw:= rng.randf() * TAU
	var bark:= _pbr(Color(0.4, 0.28, 0.18), 0.9)
	var birch_bark:= _pbr(Color(0.9, 0.88, 0.82), 0.8)
	match kind:
		"pine":
			if blobby:
				_cyl(0.2 * sc, 1.8 * sc, p + Vector3(0, 0.9 * sc, 0), bark, Basis.IDENTITY, 12, 0.14 * sc)
				var m:= _pbr(col, 0.85)
				for k in 3:
					var r:= (1.7 - k * 0.42) * sc
					_cyl(r, 1.9 * sc, p + Vector3(0, (1.9 + k * 1.15) * sc, 0), m, Basis.IDENTITY, 20, 0.0)
			elif look == "paper":
				_box(Vector3(0.25 * sc, 1.5 * sc, 0.03), p + Vector3(0, 0.75 * sc, 0), bark)
				for k in 3:
					var t:= _cyl((1.6 - k * 0.4) * sc, 1.9 * sc, p + Vector3(0, (1.9 + k * 1.1) * sc, -0.04 * k), _pbr(col.lightened(k * 0.08), 0.9), Basis(Vector3.UP, PI * 0.5), 3, 0.0)
					t.set_meta("flat", false)
			elif look == "ps1":
				_cyl(0.18 * sc, 1.6 * sc, p + Vector3(0, 0.8 * sc, 0), bark, Basis.IDENTITY, 5, 0.12 * sc)
				_cards(p + Vector3(0, 0.6 * sc, 0), Vector2(3.2, 5.6) * sc, "pine", 2)
			else:
				var v:= rng.randi() % 3
				_mesh_at(PlantMeshes.trunk_hi(v, 5.6, 0.32, 0.1, false, 0, 5), p, sc, yaw, _vmat(Color(0.45, 0.3, 0.15)))
				_mesh_at(PlantMeshes.pine_hi(v), p, sc, yaw, _vmat(col, true, true))
		"broad", "birch":
			var trunk_m:= birch_bark if kind == "birch" else bark
			if blobby:
				_cyl(0.16 * sc, 3.0 * sc, p + Vector3(0, 1.5 * sc, 0), trunk_m, Basis.IDENTITY, 12, 0.1 * sc)
				if kind == "birch" and look != "lowpoly":
					for k in 4:
						_box(Vector3(0.12, 0.05, 0.02) * sc, p + Vector3(0.0, (0.7 + k * 0.55) * sc, -0.17 * sc), _pbr(Color(0.1, 0.1, 0.1), 0.9))
				var m:= _pbr(col, 0.85)
				for b: Array in [[Vector3(0, 3.5, 0), 1.25], [Vector3(-0.8, 3.1, 0.3), 0.9], [Vector3(0.75, 3.25, -0.2), 0.95], [Vector3(0.1, 4.2, 0.2), 0.85]]:
					_ball(p + (b[0] as Vector3) * sc, (b[1] as float) * sc, m, 6 if look == "lowpoly" else 28)
			elif look == "paper":
				_box(Vector3(0.22 * sc, 3.2 * sc, 0.03), p + Vector3(0, 1.6 * sc, 0), trunk_m)
				for k in 3:
					_disc(p + Vector3((k - 1) * 0.5 * sc, (3.4 + k * 0.35) * sc, 0), (1.15 - k * 0.2) * sc, col.lightened(k * 0.08), -0.05 - k * 0.04)
			elif look == "ps1":
				_cyl(0.15 * sc, 3.0 * sc, p + Vector3(0, 1.5 * sc, 0), trunk_m, Basis.IDENTITY, 5, 0.1 * sc)
				_cards(p + Vector3(0, 2.2 * sc, 0), Vector2(3.2, 3.0) * sc, "leaves", 3)
			else:
				var v:= rng.randi() % 3
				var tm:= _vmat(Color(0.86, 0.84, 0.78) if kind == "birch" else Color(0.45, 0.33, 0.24))
				_mesh_at(PlantMeshes.trunk_hi(v + 3, 4.6, 0.26, 0.12, kind == "birch", 3, 0), p, sc * 0.9, yaw, tm)
				_mesh_at(PlantMeshes.broadleaf_hi(v), p, sc * 0.9, yaw, _vmat(col, true, true))
		"bush":
			if blobby:
				var m:= _pbr(col, 0.9)
				for k in 3:
					_ball(p + Vector3(cos(k * 2.1) * 0.4, 0.45, sin(k * 2.1) * 0.35) * sc, 0.55 * sc, m, 6 if look == "lowpoly" else 20)
			elif look == "paper":
				_disc(p + Vector3(0, 0.45 * sc, 0), 0.6 * sc, col)
				_disc(p + Vector3(0.45 * sc, 0.35 * sc, 0), 0.45 * sc, col.lightened(0.1), -0.04)
			elif look == "ps1":
				_cards(p, Vector2(1.6, 1.2) * sc, "leaves", 2)
			else:
				_mesh_at(PlantMeshes.bush_hi(rng.randi() % 3), p, sc, yaw, _vmat(col, true, true))
		"fern":
			if look in ["b", "c", "hyper", "comic"]:
				_mesh_at(PlantMeshes.fern_clump(rng.randi() % 3), p, sc, yaw, _vmat(col, true, true))
			elif look == "ps1":
				_cards(p, Vector2(1.0, 0.7) * sc, "fern", 2)
			elif look != "paper":
				var m:= _pbr(col, 0.9)
				for k in 5:
					var a:= k * TAU / 5.0 + yaw
					var leaf:= _ball(p + Vector3(cos(a) * 0.32, 0.12, sin(a) * 0.32) * sc, 0.32 * sc, m, 6 if look == "lowpoly" else 12)
					leaf.scale = Vector3(0.35, 0.18, 1.0)
					leaf.rotation.y = -a + PI * 0.5
		"rock":
			if look in ["b", "c", "hyper", "comic"]:
				_mesh_at(PlantMeshes.rock_hi(rng.randi() % 3), p, sc, yaw, _vmat(Color(0.55, 0.55, 0.52)))
			elif look == "paper":
				_disc(p + Vector3(0, 0.2 * sc, 0), 0.5 * sc, Color(0.6, 0.6, 0.58))
			else:
				var r:= _ball(p + Vector3(0, 0.15 * sc, 0), 0.55 * sc, _pbr(Color(0.45, 0.45, 0.43) if scene == "woods" else Color(0.5, 0.49, 0.46), 0.9), 7 if look in ["lowpoly", "ps1"] else 20)
				r.scale = Vector3(1.0, 0.6, 0.85)
		"flower":
			if look in ["b", "c", "hyper", "comic"]:
				_mesh_at(PlantMeshes.flower_clump(rng.randi() % 4), p, sc, yaw, _vmat(Color(1, 1, 1), true, true))
			else:
				var stem:= _pbr(Color(0.3, 0.55, 0.2), 0.9)
				for k in 3:
					var q:= p + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
					var hh:= rng.randf_range(0.25, 0.45) * sc
					if look == "paper":
						_box(Vector3(0.02, hh, 0.01), q + Vector3(0, hh * 0.5, 0), stem)
						_disc(q + Vector3(0, hh, 0), 0.07 * sc, col)
					else:
						_cyl(0.012, hh, q + Vector3(0, hh * 0.5, 0), stem, Basis.IDENTITY, 5)
						_ball(q + Vector3(0, hh, 0), 0.07 * sc, _pbr(col, 0.7), 6 if look in ["lowpoly", "ps1"] else 12)
		"mushroom":
			var glow:= night
			var cap_c:= Color(0.3, 0.9, 0.85) if scene == "woods" else Color(0.85, 0.2, 0.15)
			_cyl(0.035 * sc, 0.16 * sc, p + Vector3(0, 0.08 * sc, 0), _pbr(Color(0.9, 0.88, 0.8), 0.8), Basis.IDENTITY, 8)
			var cap:= MeshInstance3D.new()
			var sm:= SphereMesh.new()
			sm.radius = 0.1 * sc
			sm.height = 0.1 * sc
			sm.is_hemisphere = true
			sm.radial_segments = 8 if look in ["lowpoly", "ps1"] else 16
			cap.mesh = sm
			cap.material_override = _glow(cap_c, 2.5) if glow else _pbr(cap_c, 0.6)
			cap.position = p + Vector3(0, 0.15 * sc, 0)
			root3d.add_child(cap)
			if look == "paper":
				cap.scale = Vector3(1, 1, 0.08)


func _scatter(kind: String, count: int, area: Rect2, ok: Callable, sc: Vector2, cols: Array, gap: float = 0.0) -> Array[Vector3]:
	var placed: Array[Vector3] = []
	var tries:= 0
	while placed.size() < count and tries < count * 40:
		tries += 1
		var x:= rng.randf_range(area.position.x, area.end.x)
		var z:= rng.randf_range(area.position.y, area.end.y)
		if not ok.call(x, z):
			continue
		var p:= Vector3(x, _h(x, z), z)
		var crowded:= false
		for q in placed:
			if Vector2(q.x - x, q.z - z).length() < gap:
				crowded = true
				break
		if crowded:
			continue
		placed.append(p)
		_plant(kind, p, rng.randf_range(sc.x, sc.y), cols[rng.randi() % cols.size()])
	return placed


func _fireflies(centre: Vector3, spread: Vector3, n: int) -> void:
	if not night:
		return
	var m:= _glow(Color(0.8, 1.0, 0.4), 4.0)
	for i in n:
		var b:= _ball(centre + Vector3(rng.randf_range(-1, 1) * spread.x, rng.randf_range(0.3, 1.0) * spread.y, rng.randf_range(-1, 1) * spread.z), 0.03, m, 6)
		b.set_meta("flat", true)


func _wild_people(ph: CharacterModel, ow: float) -> void:
	var at:= Vector3(1.8, 0, -1.2) if scene == "woods" else Vector3(0.0, 0.33, -8.2)
	if scene == "woods":
		at.y = _h(at.x, at.z)
	root3d.add_child(ph)
	ph.position = at
	ph.rotation.y = 2.6 if scene == "woods" else PI + 0.5
	ph.play("idle")
	var path:= "res://models/bigboobs.glb" if scene == "woods" else "res://models/fhairy.glb"
	var cr:= CharacterModel.load_model(path, ow * 1.15)
	cr.set_meta("char", true)
	root3d.add_child(cr)
	var cp:= Vector3(-5.2, 0, 9.5) if scene == "woods" else Vector3(-7.5, 0, 2.2)
	cp.y = _h(cp.x, cp.z)
	cr.position = cp
	cr.rotation.y = 0.5 if scene == "woods" else -0.6
	cr.play("idle")


func _woods() -> void:
	_hn.seed = 3
	var moss:= _ground_mat("grass")
	moss.set_shader_parameter("base_col", Color(0.16, 0.26, 0.1) if style == "c" else Color(0.2, 0.42, 0.18))
	var gp: Dictionary = moss.get_meta("params")
	gp["base_col"] = moss.get_shader_parameter("base_col")
	_terrain(0, 4, 70, 0.7, moss)
	# Dirt path from the clearing out toward the camera, and a ring of trampled earth.
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z:= -30.0
	while z < 2.0:
		var pts: Array[Vector3] = []
		for zz: float in [z, z + 0.5]:
			var cx:= _path_x(zz)
			for sx: float in [-0.8, 0.8]:
				pts.append(Vector3(cx + sx, _h(cx + sx, zz) + 0.04, zz))
		for k in [0, 1, 3, 0, 3, 2]:
			st.add_vertex(pts[k])
		z += 0.5
	st.generate_normals()
	var dirt:= MeshInstance3D.new()
	dirt.mesh = st.commit()
	dirt.material_override = _ground_mat("dirt")
	dirt.set_meta("ground", true)
	root3d.add_child(dirt)
	var clear:= MeshInstance3D.new()
	var cm:= CylinderMesh.new()
	cm.top_radius = 4.5
	cm.bottom_radius = 4.5
	cm.height = 0.04
	cm.radial_segments = 40
	clear.mesh = cm
	clear.material_override = _ground_mat("dirt")
	clear.position = Vector3(0, 0.02, 2.0)
	clear.set_meta("ground", true)
	root3d.add_child(clear)
	# Campfire: a ring of stones, crossed logs, flames.
	var fire:= Vector3(0, 0.0, 1.8)
	for k in 9:
		var a:= k * TAU / 9.0
		var r:= _ball(fire + Vector3(cos(a) * 0.62, 0.08, sin(a) * 0.62), 0.16, _pbr(Color(0.45, 0.44, 0.42), 0.9), 8 if look in ["lowpoly", "ps1"] else 16)
		r.scale = Vector3(1.0, 0.7, 0.9)
	for k in 3:
		var a:= k * PI / 3.0
		_tube(fire + Vector3(cos(a) * 0.45, 0.05, sin(a) * 0.45), fire + Vector3(-cos(a) * 0.45, 0.25, -sin(a) * 0.45), 0.07, _pbr(Color(0.3, 0.2, 0.12), 0.9), 10)
	var flame_c:= Color(1.0, 0.55, 0.15)
	for k in 3:
		_cyl(0.2 - k * 0.05, 0.45 + k * 0.15, fire + Vector3(0, 0.35 + k * 0.08, 0), _glow(flame_c.lerp(Color(1, 0.9, 0.4), k * 0.4), 3.0 if night else 1.5), Basis.IDENTITY, 10, 0.0)
	var fl:= OmniLight3D.new()
	fl.light_color = Color(1.0, 0.6, 0.3)
	fl.light_energy = 4.0 if night else 0.8
	fl.omni_range = 14.0
	fl.shadow_enabled = true
	fl.position = fire + Vector3(0, 0.9, 0)
	root3d.add_child(fl)
	# Log seats and a fallen trunk.
	_tube(Vector3(-2.2, 0.22, 0.6), Vector3(-2.0, 0.22, 3.0), 0.22, _pbr(Color(0.38, 0.27, 0.17), 0.9), 14)
	_tube(Vector3(-9.0, _h(-9, 3) + 0.3, 3.0), Vector3(-6.0, _h(-6, 6) + 0.25, 6.5), 0.32, _pbr(Color(0.33, 0.25, 0.17), 0.9), 14)
	# The RV parked at the clearing's edge.
	var rvs:= load("res://models/rv_exterior.glb") as PackedScene
	if rvs:
		var rv:= rvs.instantiate() as Node3D
		root3d.add_child(rv)
		rv.position = Vector3(6.8, 0.0, 4.0)
		rv.rotation.y = 0.35
		rv.set_meta("car", true)
		var lamp:= OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.85, 0.6)
		lamp.light_energy = 1.5 if night else 0.0
		lamp.omni_range = 8.0
		lamp.position = Vector3(4.6, 2.4, 2.6)
		root3d.add_child(lamp)
	# The forest.
	var greens: Array = [Color(0.12, 0.42, 0.2), Color(0.18, 0.5, 0.24), Color(0.1, 0.36, 0.18)] if style == "c" else \
		[Color(0.15, 0.55, 0.26), Color(0.22, 0.62, 0.3), Color(0.12, 0.48, 0.24)]
	var open:= func(x: float, zz: float) -> bool:
		return Vector2(x, zz - 2.0).length() > 7.5 and absf(x - _path_x(zz)) > 2.0 \
			and Vector2(x - 4.6, zz + 3.2).length() > 3.5 and Vector2(x + 0.5, zz + 10.0).length() > 3.0
	_scatter("pine", 95, Rect2(-30, -24, 60, 56), open, Vector2(0.8, 1.35), greens, 2.6)
	_scatter("broad", 14, Rect2(-30, -24, 60, 56), open, Vector2(0.8, 1.1), [Color(0.25, 0.55, 0.22), Color(0.35, 0.6, 0.25)], 3.0)
	var near:= func(x: float, zz: float) -> bool:
		return Vector2(x, zz - 2.0).length() > 5.5 and absf(x - _path_x(zz)) > 1.1
	_scatter("bush", 40, Rect2(-16, -14, 32, 30), near, Vector2(0.7, 1.2), [Color(0.15, 0.45, 0.2), Color(0.25, 0.5, 0.2)], 1.2)
	_scatter("fern", 70, Rect2(-14, -14, 28, 28), near, Vector2(0.8, 1.3), [Color(0.2, 0.55, 0.22), Color(0.3, 0.6, 0.25)], 0.6)
	_scatter("rock", 10, Rect2(-14, -12, 28, 26), near, Vector2(0.6, 1.4), [Color.GRAY], 2.0)
	_scatter("mushroom", 24, Rect2(-9, -6, 14, 18), near, Vector2(0.8, 1.6), [Color.WHITE], 0.3)
	_fireflies(Vector3(0, 0, 3), Vector3(9, 2.5, 8), 50)


func _lake() -> void:
	_hn.seed = 9
	var grass:= _ground_mat("grass")
	_terrain(0, -18, 110, 0.9, grass)
	# Water.
	var water:= MeshInstance3D.new()
	var pm:= PlaneMesh.new()
	pm.size = Vector2(200, 200)
	pm.subdivide_width = 60
	pm.subdivide_depth = 60
	water.mesh = pm
	var wm:= StandardMaterial3D.new()
	wm.albedo_color = Color(0.08, 0.2, 0.3, 0.8) if style == "c" else Color(0.08, 0.26, 0.45, 0.9)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.04
	wm.metallic = 0.3
	water.material_override = wm
	water.position = Vector3(0, WATER_Y, -30)
	water.set_meta("ground", true)
	root3d.add_child(water)
	# Dock: planks on posts, a lantern at the end, a rowboat tied alongside.
	var wood:= _pbr(Color(0.5, 0.36, 0.22) if style == "c" else Color(0.62, 0.42, 0.25), 0.85)
	var dock_y:= 0.28
	var zz:= 3.0
	while zz > -9.0:
		_box(Vector3(2.0, 0.07, 0.3), Vector3(0, dock_y, zz), wood, Basis(Vector3.UP, rng.randf_range(-0.02, 0.02)))
		zz -= 0.34
	for k in 5:
		for sx: float in [-0.95, 0.95]:
			_cyl(0.09, 2.4, Vector3(sx, dock_y - 0.9, 2.0 - k * 2.6), wood, Basis.IDENTITY, 10)
	_box(Vector3(0.12, 0.12, 12.2), Vector3(-0.95, dock_y - 0.1, -3.0), wood)
	_box(Vector3(0.12, 0.12, 12.2), Vector3(0.95, dock_y - 0.1, -3.0), wood)
	var lan:= Vector3(-0.85, dock_y + 0.04, -8.6)
	_cyl(0.06, 1.1, lan + Vector3(0, 0.55, 0), wood, Basis.IDENTITY, 8)
	_box(Vector3(0.2, 0.26, 0.2), lan + Vector3(0, 1.2, 0), _glow(Color(1.0, 0.8, 0.45), 3.0 if night else 0.3))
	if night:
		var ll:= OmniLight3D.new()
		ll.light_color = Color(1.0, 0.75, 0.45)
		ll.light_energy = 2.5
		ll.omni_range = 9.0
		ll.shadow_enabled = true
		ll.position = lan + Vector3(0, 1.2, 0.3)
		root3d.add_child(ll)
	var boat:= Vector3(2.2, WATER_Y + 0.12, -5.5)
	var hull:= _pbr(Color(0.75, 0.3, 0.2) if style != "c" else Color(0.55, 0.22, 0.16), 0.7)
	_box(Vector3(1.1, 0.12, 3.2), boat + Vector3(0, 0.0, 0), hull)
	for sx: float in [-0.55, 0.55]:
		_box(Vector3(0.08, 0.38, 3.0), boat + Vector3(sx, 0.18, 0), hull, Basis(Vector3.FORWARD, sx * 0.4))
	_box(Vector3(1.0, 0.36, 0.08), boat + Vector3(0, 0.18, -1.5), hull)
	_box(Vector3(1.0, 0.05, 0.3), boat + Vector3(0, 0.28, 0.2), wood)
	_tube(boat + Vector3(-0.4, 0.3, 0.6), boat + Vector3(-0.9, 0.05, 2.0), 0.03, wood, 6)
	# Shore: reeds and lily pads, birches and a few pines, a meadow of flowers.
	var reed_m:= _pbr(Color(0.42, 0.55, 0.25), 0.9)
	var head_m:= _pbr(Color(0.35, 0.22, 0.12), 0.9)
	for i in 160:
		var x:= rng.randf_range(-25, 25)
		var shore:= sin(x * 0.09) * 2.5 + sin(x * 0.23 + 1.0) * 0.8
		var z:= shore + 1.25 + rng.randf_range(-1.3, 0.7)
		if absf(x) < 1.6:
			continue
		var h:= rng.randf_range(0.9, 1.6)
		var base:= Vector3(x, maxf(_h(x, z), WATER_Y - 0.3), z)
		var top:= base + Vector3(rng.randf_range(-0.1, 0.1), h, rng.randf_range(-0.1, 0.1))
		_tube(base, top, 0.012, reed_m, 4)
		if i % 2 == 0:
			_tube(top - Vector3(0, 0.25, 0), top - Vector3(0, 0.05, 0), 0.035, head_m, 6)
	var pad_m:= _pbr(Color(0.2, 0.5, 0.22), 0.6)
	for i in 50:
		var x:= rng.randf_range(-16, -2) if i % 2 == 0 else rng.randf_range(3, 16)
		var z:= rng.randf_range(-12, -3)
		if _h(x, z) > WATER_Y - 0.2:
			continue
		var pad:= _cyl(rng.randf_range(0.18, 0.4), 0.02, Vector3(x, WATER_Y + 0.01, z), pad_m, Basis.IDENTITY, 14)
		pad.set_meta("flat", true)
		if i % 7 == 0:
			_ball(Vector3(x, WATER_Y + 0.08, z), 0.08, _pbr(Color(1.0, 0.8, 0.9), 0.6), 8).set_meta("flat", true)
	var autumn: Array = [Color(0.95, 0.55, 0.12), Color(0.9, 0.35, 0.12), Color(0.98, 0.78, 0.2), Color(0.45, 0.68, 0.28)]
	var land:= func(x: float, z: float) -> bool:
		return _h(x, z) > 0.1 and absf(x) > 3.0 and not (absf(x - 4.0) < 4.0 and z > 5.0 and z < 14.0)
	_scatter("birch", 30, Rect2(-35, 3, 70, 30), land, Vector2(0.85, 1.25), autumn, 3.2)
	_scatter("pine", 10, Rect2(-35, 8, 70, 26), land, Vector2(0.9, 1.3), [Color(0.18, 0.5, 0.26)], 3.5)
	var far:= func(x: float, z: float) -> bool:
		return _h(x, z) > 0.2
	_scatter("birch", 40, Rect2(-50, -70, 100, 26), far, Vector2(0.9, 1.4), autumn, 3.0)
	_scatter("pine", 45, Rect2(-50, -70, 100, 26), far, Vector2(1.0, 1.6), [Color(0.15, 0.45, 0.24), Color(0.2, 0.52, 0.28)], 3.0)
	var meadow:= func(x: float, z: float) -> bool:
		return _h(x, z) > 0.0 and absf(x) > 1.4
	_scatter("flower", 70, Rect2(-14, 1, 28, 14), meadow, Vector2(0.8, 1.2), [Color(1, 0.85, 0.2), Color(0.95, 0.4, 0.5), Color(0.6, 0.5, 0.95), Color(1, 1, 1)], 0.5)
	_scatter("rock", 8, Rect2(-15, -1, 30, 10), meadow, Vector2(0.6, 1.3), [Color.GRAY], 2.5)
	_scatter("bush", 14, Rect2(-20, 4, 40, 16), land, Vector2(0.7, 1.1), [Color(0.3, 0.55, 0.22), Color(0.6, 0.5, 0.2)], 2.0)
	_fireflies(Vector3(0, 0, 4), Vector3(14, 2.0, 6), 35)


## Hyperreal woods and lakeside: dense grass blades, fallen needles and twigs near the camera.
func _hyper_wild() -> void:
	var r2:= RandomNumberGenerator.new()
	r2.seed = 8
	var mm:= MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = PlantMeshes.grass_tuft(1)
	mm.instance_count = 9000
	var n:= 0
	for i in mm.instance_count:
		var x:= r2.randf_range(-16, 16)
		var z:= r2.randf_range(-12, 16)
		var h:= _h(x, z)
		var bare:= (scene == "woods" and (Vector2(x, z - 2.0).length() < 4.8 or absf(x - _path_x(z)) < 1.0)) or (scene == "lake" and (h < WATER_Y + 0.05 or absf(x) < 1.2 and z < 4.0))
		var p:= Vector3(x, h - (50.0 if bare else 0.0), z)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, r2.randf() * TAU).scaled(Vector3.ONE * r2.randf_range(0.5, 1.0)), p))
		mm.set_instance_color(i, Color(0.7, 0.8, 0.55).lerp(Color(0.95, 0.9, 0.6), r2.randf() * 0.5))
		n += 1
	var gmi:= MultiMeshInstance3D.new()
	gmi.multimesh = mm
	var gmat:= StandardMaterial3D.new()
	gmat.vertex_color_use_as_albedo = true
	gmat.albedo_color = Color(0.32, 0.45, 0.2) if scene == "woods" else Color(0.45, 0.6, 0.28)
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	gmat.roughness = 0.9
	gmi.material_override = gmat
	root3d.add_child(gmi)
	var twig:= _pbr(Color(0.3, 0.22, 0.14), 0.9)
	var needle:= _pbr(Color(0.45, 0.32, 0.16), 0.95)
	for i in 160:
		var x:= r2.randf_range(-8, 8)
		var z:= r2.randf_range(-8, 10)
		var p:= Vector3(x, _h(x, z) + 0.01, z)
		if i % 4 == 0:
			_tube(p, p + Vector3(r2.randf_range(-0.4, 0.4), 0.02, r2.randf_range(-0.4, 0.4)), 0.012, twig, 5)
		else:
			_box(Vector3(0.08, 0.004, 0.05), p, needle, Basis(Vector3.UP, r2.randf() * TAU))
