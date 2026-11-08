extends SceneTree
## Style previews: one street corner (brick building with a shopfront, sidewalk, road, a parked
## sedan, a street lamp, a tree, a swing set and a slide, a photographer and a cryptid for
## scale) built in a chosen style, rendered to a PNG.
##   godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tools/style_preview.gd
##   env: STYLE=b (stylized HD) | c (realistic)   TIME=day|night   CAM=1|2   OUT=/tmp/x.png

var style:= "b"
var night:= false
var frames:= 0
var root3d: Node3D
var rng:= RandomNumberGenerator.new()


func _initialize() -> void:
	style = OS.get_environment("STYLE") if OS.get_environment("STYLE") != "" else "b"
	night = OS.get_environment("TIME") == "night"
	rng.seed = 7
	root3d = Node3D.new()
	root.add_child(root3d)
	_environment()
	_ground()
	_building()
	_street_props()
	_playground()
	_car()
	_people()
	_camera()


func _process(_d: float) -> bool:
	frames += 1
	if frames == 30:
		var out:= OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/preview.png"
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		quit()
	return false


# ------------------------------------------------------------------ helpers

func _box(size: Vector3, pos: Vector3, mat: Material, basis: Basis = Basis.IDENTITY) -> MeshInstance3D:
	var mi:= MeshInstance3D.new()
	var bm:= BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	root3d.add_child(mi)
	return mi


func _cyl(r: float, h: float, pos: Vector3, mat: Material, basis: Basis = Basis.IDENTITY, segs: int = 24, r_top: float = -1.0) -> MeshInstance3D:
	var mi:= MeshInstance3D.new()
	var cm:= CylinderMesh.new()
	cm.top_radius = r if r_top < 0.0 else r_top
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
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
	we.environment = e
	root3d.add_child(we)
	var sun:= DirectionalLight3D.new()
	sun.shadow_enabled = true
	if night:
		sun.light_color = Color(0.55, 0.62, 0.9)
		sun.light_energy = 0.25
		sun.rotation_degrees = Vector3(-50, 35, 0)
	else:
		sun.light_color = Color(1.0, 0.95, 0.85) if style == "b" else Color(1.0, 0.96, 0.9)
		sun.light_energy = 1.25 if style == "b" else 1.6
		sun.rotation_degrees = Vector3(-38, 35, 0)
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
	var floor_h:= 3.3
	var floors:= 4
	var top:= 0.15 + floor_h * floors
	var wall_t:= 0.4
	# Back mass (behind the facade).
	_box(Vector3(x1 - x0, top, depth - wall_t), Vector3((x0 + x1) * 0.5, top * 0.5, front + wall_t + (depth - wall_t) * 0.5), brick)
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
	var bays:= 6
	var bay_w:= (x1 - x0) / bays
	var win_w:= 1.15
	var win_h:= 1.7
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
				_box(Vector3(0.07, win_h, 0.08), Vector3(cx + fx * (win_w * 0.5 - 0.035), sill_y + win_h * 0.5, front + 0.22), trim)
			for fy: float in [0.035, win_h - 0.035, win_h * 0.55]:
				_box(Vector3(win_w, 0.06, 0.08), Vector3(cx, sill_y + fy, front + 0.22), trim)
			_box(Vector3(win_w + 0.25, 0.08, 0.22), Vector3(cx, sill_y - 0.04, front - 0.06), stone)
			_box(Vector3(win_w + 0.2, 0.18, 0.06), Vector3(cx, sill_y + win_h + 0.09, front - 0.01), stone)
			if lit:
				var wl:= OmniLight3D.new()
				wl.light_color = Color(1.0, 0.8, 0.55)
				wl.light_energy = 0.5
				wl.omni_range = 3.0
				wl.position = Vector3(cx, sill_y + 1.0, front - 0.8)
				root3d.add_child(wl)
	# Cornice with dentils.
	_box(Vector3(x1 - x0 + 0.5, 0.35, wall_t + 0.5), Vector3((x0 + x1) * 0.5, top + 0.1, front + 0.1), trim)
	_box(Vector3(x1 - x0 + 0.3, 0.6, wall_t + 0.2), Vector3((x0 + x1) * 0.5, top - 0.3, front + 0.2), brick)
	var dx:= x0 + 0.2
	while dx < x1:
		_box(Vector3(0.12, 0.14, 0.12), Vector3(dx, top - 0.12, front - 0.05), trim)
		dx += 0.32
	# Fire escape on the right bays.
	var iron:= _pbr(Color(0.08, 0.08, 0.09), 0.5, 0.6)
	for f in range(1, floors):
		var y:= 0.15 + floor_h * f + 0.8
		var cx:= x1 - 2.7
		_box(Vector3(3.2, 0.05, 1.1), Vector3(cx, y, front - 0.55), iron)
		for gx in 13:
			_tube(Vector3(cx - 1.6 + gx * 0.266, y, front - 1.1), Vector3(cx - 1.6 + gx * 0.266, y + 0.95, front - 1.1), 0.012, iron, 6)
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
	cm.albedo_color = Color(0.32, 0.5, 0.2) if style == "c" else Color(0.4, 0.72, 0.3)
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	crown.material_override = cm
	crown.position = tp
	crown.scale = Vector3.ONE * 0.85
	root3d.add_child(crown)
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
	var scene:= load("res://preview/car_sedan.glb") as PackedScene
	if scene == null:
		return
	var car:= scene.instantiate() as Node3D
	root3d.add_child(car)
	car.position = Vector3(-1.5, 0.0, 3.6)
	car.rotation.y = PI * 0.5
	var real:= style == "c"
	var paint:= StandardMaterial3D.new()
	paint.albedo_color = Color(0.45, 0.04, 0.05) if real else Color(0.1, 0.55, 0.65)
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
	var ph:= CharacterModel.load_model("res://models/photographer.glb", 0.012)
	root3d.add_child(ph)
	ph.position = Vector3(0.6, 0.15, 6.4)
	ph.rotation.y = -0.4
	ph.play("idle")
	var cr:= CharacterModel.load_model("res://models/methman.glb", 0.014)
	root3d.add_child(cr)
	cr.position = Vector3(6.8, 0.15, 7.6)
	cr.rotation.y = -2.4
	cr.play("idle")


func _camera() -> void:
	var cam:= Camera3D.new()
	cam.fov = 62
	root3d.add_child(cam)
	if OS.get_environment("CAM") == "3":
		cam.look_at_from_position(Vector3(-5.5, 1.6, 0.0), Vector3(-1.5, 0.7, 3.6))
	elif OS.get_environment("CAM") == "4":
		cam.look_at_from_position(Vector3(3.5, 2.0, 0.5), Vector3(-1.5, 0.7, 3.6))
	elif OS.get_environment("CAM") == "2":
		cam.look_at_from_position(Vector3(5.5, 1.5, 0.6), Vector3(-1.0, 1.0, 5.4))
	else:
		cam.look_at_from_position(Vector3(1.0, 1.7, -8.5), Vector3(2.5, 3.2, 8.0))
	cam.current = true
