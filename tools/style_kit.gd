extends RefCounted
## Helpers for tools/style_preview.gd: meshes, materials and whole-scene passes that turn the
## one street-corner scene into different art styles (not filters: the shapes change too).

const NOISE:= """
float hash12(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash13(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}
float vnoise3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}
float fbm(vec2 p) { float a = 0.5; float s = 0.0; for (int i = 0; i < 4; i++) { s += a * vnoise(p); p *= 2.03; a *= 0.5; } return s; }
"""


# ------------------------------------------------------------------ meshes

## Box with rounded edges (radius r), cut into cells no bigger than `step` so it can be bent
## afterwards. Every face gets UV = position on that face in metres and UV2 = the face's size,
## so shaders can find the face's edges (ink lines, card edges, painted edges).
static func rounded_box(size: Vector3, r: float, step: float) -> ArrayMesh:
	var h:= size * 0.5
	r = clampf(r, 0.0, minf(h.x, minf(h.y, h.z)) * 0.98)
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for a in 3:
		var u:= (a + 1) % 3
		var v:= (a + 2) % 3
		var cu:= _coords(h[u], r, step)
		var cv:= _coords(h[v], r, step)
		var uv2:= Vector2(size[u], size[v])
		for sgn: float in [-1.0, 1.0]:
			var fn: Vector3 = axes[a] * sgn
			for i in cu.size() - 1:
				for j in cv.size() - 1:
					var ps: Array[Vector3] = []
					var ns: Array[Vector3] = []
					var uvs: Array[Vector2] = []
					for d: Array in [[0, 0], [1, 0], [1, 1], [0, 1]]:
						var p:= Vector3()
						p[a] = sgn * h[a]
						p[u] = cu[i + d[0]]
						p[v] = cv[j + d[1]]
						uvs.append(Vector2(p[u] + h[u], p[v] + h[v]))
						var n:= fn
						if r > 0.0:
							var core:= Vector3(clampf(p.x, -h.x + r, h.x - r), clampf(p.y, -h.y + r, h.y - r), clampf(p.z, -h.z + r, h.z - r))
							var dv:= p - core
							if dv.length() > 1e-6:
								n = dv.normalized()
								p = core + n * r
						ps.append(p)
						ns.append(n)
					for tri: Array in [[0, 1, 2], [0, 2, 3]]:
						var A: Vector3 = ps[tri[0]]
						var B: Vector3 = ps[tri[1]]
						var C: Vector3 = ps[tri[2]]
						var order: Array = tri
						if (B - A).cross(C - A).dot(fn) > 0.0:
							order = [tri[0], tri[2], tri[1]]
						for k: int in order:
							st.set_normal(ns[k])
							st.set_uv(uvs[k])
							st.set_uv2(uv2)
							st.add_vertex(ps[k])
	return st.commit()


static func _coords(hh: float, r: float, step: float) -> PackedFloat32Array:
	var out:= PackedFloat32Array()
	var arc:= 3 if r > 0.0 else 0
	for i in arc:
		out.append(-hh + r * float(i) / arc)
	var a:= -hh + r
	var b:= hh - r
	var n:= maxi(1, ceili((b - a) / step)) if b - a > 1e-4 else 0
	for i in n + 1:
		out.append(lerpf(a, b, float(i) / maxf(n, 1)))
	if n == 0 and out.size() == arc:
		out.append(a)
	for i in range(1, arc + 1):
		out.append(hh - r + r * float(i) / arc)
	return out


## Runs every vertex of a mesh instance through `fn(world_pos, world_normal) -> world_pos`, then
## rebuilds normals (smooth, or flat for faceted looks). Works on any mesh (primitives too).
static func reshape(mi: MeshInstance3D, fn: Callable, flat: bool) -> void:
	if mi.mesh == null:
		return
	var xf:= mi.global_transform
	var inv:= xf.affine_inverse()
	var nb:= xf.basis.inverse().transposed()
	var out:= ArrayMesh.new()
	var mats: Array[Material] = []
	for s in mi.mesh.get_surface_count():
		mats.append(mi.get_surface_override_material(s) if mi.get_surface_override_material(s) else mi.mesh.surface_get_material(s))
		var arr:= mi.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		for k in vs.size():
			var n:= (nb * ns[k]).normalized() if k < ns.size() else Vector3.UP
			vs[k] = inv * (fn.call(xf * vs[k], n) as Vector3)
		arr[Mesh.ARRAY_VERTEX] = vs
		arr[Mesh.ARRAY_TANGENT] = null
		arr = flat_arrays(arr) if flat else smooth_arrays(arr)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mi.mesh = out
	for s in mats.size():
		if mats[s] and mi.material_override == null:
			mi.set_surface_override_material(s, mats[s])


## Normals averaged over the faces that share each vertex (by position, so seams stay smooth).
static func smooth_arrays(arr: Array) -> Array:
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx.resize(vs.size())
		for i in vs.size():
			idx[i] = i
	var acc:= {}
	for t in range(0, idx.size(), 3):
		var a:= vs[idx[t]]
		var b:= vs[idx[t + 1]]
		var c:= vs[idx[t + 2]]
		var fn:= (c - a).cross(b - a)
		for v in [a, b, c]:
			var key:= Vector3i((v * 2000.0).round())
			acc[key] = acc.get(key, Vector3.ZERO) + fn
	var ns:= PackedVector3Array()
	ns.resize(vs.size())
	for i in vs.size():
		var n: Vector3 = acc.get(Vector3i((vs[i] * 2000.0).round()), Vector3.UP)
		ns[i] = n.normalized() if n.length() > 1e-9 else Vector3.UP
	arr[Mesh.ARRAY_NORMAL] = ns
	return arr


## Splits every triangle off on its own with its face normal (faceted, low-poly shading).
static func flat_arrays(arr: Array) -> Array:
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx.resize(vs.size())
		for i in vs.size():
			idx[i] = i
	var out:= []
	out.resize(Mesh.ARRAY_MAX)
	var per_vertex:= [Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]
	var nv:= PackedVector3Array()
	var nn:= PackedVector3Array()
	for t in range(0, idx.size(), 3):
		var a:= vs[idx[t]]
		var b:= vs[idx[t + 1]]
		var c:= vs[idx[t + 2]]
		var fn:= (c - a).cross(b - a).normalized()
		for k in 3:
			nv.append(vs[idx[t + k]])
			nn.append(fn)
	out[Mesh.ARRAY_VERTEX] = nv
	out[Mesh.ARRAY_NORMAL] = nn
	for at: int in per_vertex:
		var src = arr[at]
		if src == null:
			continue
		var stride:= 1
		if at == Mesh.ARRAY_BONES or at == Mesh.ARRAY_WEIGHTS:
			stride = (src.size() / vs.size()) if vs.size() > 0 else 4
		var dst = src.duplicate()
		dst.resize(idx.size() * stride)
		for t in idx.size():
			for k in stride:
				dst[t * stride + k] = src[idx[t] * stride + k]
		out[at] = dst
	return out


## Fewer triangles (keeps roughly `keep` of them), optionally faceted. Skinned meshes keep
## their bones and weights, so they still animate.
static func decimate(mesh: Mesh, keep: float, flat: bool) -> ArrayMesh:
	var im:= ImporterMesh.new()
	for s in mesh.get_surface_count():
		var arr:= mesh.surface_get_arrays(s)
		arr[Mesh.ARRAY_TANGENT] = null
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, mesh.surface_get_material(s), "s%d" % s)
	im.generate_lods(25.0, 60.0, [])
	var out:= ArrayMesh.new()
	for s in im.get_surface_count():
		var arr:= im.get_surface_arrays(s)
		var full: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var want:= int(full.size() * keep)
		var best:= full
		for l in im.get_surface_lod_count(s):
			var li:= im.get_surface_lod_indices(s, l)
			if absi(li.size() - want) < absi(best.size() - want):
				best = li
		arr[Mesh.ARRAY_INDEX] = best
		if flat:
			arr = flat_arrays(arr)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(s, im.get_surface_material(s))
	return out


# ------------------------------------------------------------------ voxels

## Samples every mesh surface under `root` into a voxel grid. `colour_of(mi, surface, world_pos,
## vertex_colour) -> Color` (alpha > 1.5 marks glowing voxels). Returns {Vector3i: Color}.
static func voxelize(root: Node, vox: float, clip: AABB, colour_of: Callable) -> Dictionary:
	var cells:= {}
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi:= node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var xf:= mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arr:= mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var cs = arr[Mesh.ARRAY_COLOR]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				idx.resize(vs.size())
				for i in vs.size():
					idx[i] = i
			for t in range(0, idx.size(), 3):
				var a:= xf * vs[idx[t]]
				var b:= xf * vs[idx[t + 1]]
				var c:= xf * vs[idx[t + 2]]
				var lo:= a.min(b).min(c)
				var hi:= a.max(b).max(c)
				if not clip.intersects(AABB(lo, hi - lo + Vector3.ONE * 0.001)):
					continue
				var ca:= Color.WHITE
				if cs != null and cs.size() > 0:
					var c0: Color = cs[idx[t]]
					var c1: Color = cs[idx[t + 1]]
					var c2: Color = cs[idx[t + 2]]
					ca = Color((c0.r + c1.r + c2.r) / 3.0, (c0.g + c1.g + c2.g) / 3.0, (c0.b + c1.b + c2.b) / 3.0)
				var n:= int(ceil(maxf((b - a).length(), maxf((c - a).length(), (c - b).length())) / (vox * 0.5)))
				n = maxi(n, 1)
				for i in n + 1:
					for j in n + 1 - i:
						var p:= a + (b - a) * (float(i) / n) + (c - a) * (float(j) / n)
						if not clip.has_point(p):
							continue
						var key:= Vector3i(floori(p.x / vox), floori(p.y / vox), floori(p.z / vox))
						if cells.has(key):
							continue
						var cell_centre:= (Vector3(key) + Vector3.ONE * 0.5) * vox
						cells[key] = colour_of.call(mi, s, cell_centre, ca)
	return cells


static func voxel_nodes(cells: Dictionary, vox: float) -> Node3D:
	var holder:= Node3D.new()
	var normal: Array = []
	var glow: Array = []
	for key: Vector3i in cells:
		var c: Color = cells[key]
		if c.a > 1.5:
			glow.append(key)
		else:
			normal.append(key)
	for pass_i in 2:
		var list: Array = normal if pass_i == 0 else glow
		if list.is_empty():
			continue
		var mm:= MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var bm:= BoxMesh.new()
		bm.size = Vector3.ONE * vox
		mm.mesh = bm
		mm.instance_count = list.size()
		for i in list.size():
			var key: Vector3i = list[i]
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, (Vector3(key) + Vector3.ONE * 0.5) * vox))
			var c: Color = cells[key]
			mm.set_instance_color(i, Color(c.r, c.g, c.b, 1.0))
		var mmi:= MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var m:= StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.85
		if pass_i == 1:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mmi.material_override = m
		holder.add_child(mmi)
	return holder


# ------------------------------------------------------------------ materials

static var _shaders:= {}

static func shader_mat(code: String, params: Dictionary = {}) -> ShaderMaterial:
	# One Shader per distinct source: hundreds of materials then share one compiled program.
	if not _shaders.has(code):
		var nsh:= Shader.new()
		nsh.code = code
		_shaders[code] = nsh
	var sh: Shader = _shaders[code]
	var m:= ShaderMaterial.new()
	m.shader = sh
	for k in params:
		m.set_shader_parameter(k, params[k])
	m.set_meta("params", params)
	return m


## Soft modelling clay: wrap lighting, a satin sheen and fingerprint ridges pressed into it.
static func clay(col: Color, use_vc: bool, emit: Color = Color.BLACK, lump: float = 0.0) -> ShaderMaterial:
	return shader_mat("""
shader_type spatial;
render_mode diffuse_lambert_wrap;
uniform vec3 col;
uniform float use_vc;
uniform vec3 emit;
uniform float lump;
varying vec3 wpos;
""" + NOISE + """
float lumpd(vec3 p) { return (vnoise3(p * 0.9) - 0.5) * 2.0 * lump; }
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (lump > 0.0) {
		vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 t1 = normalize(cross(wn, abs(wn.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
		vec3 t2 = cross(wn, t1);
		float e = 0.08;
		vec3 p0 = wp + wn * lumpd(wp);
		vec3 p1 = wp + t1 * e + wn * lumpd(wp + t1 * e);
		vec3 p2 = wp + t2 * e + wn * lumpd(wp + t2 * e);
		vec3 nn = normalize(cross(p1 - p0, p2 - p0));
		if (dot(nn, wn) < 0.0) nn = -nn;
		mat4 inv = inverse(MODEL_MATRIX);
		VERTEX = (inv * vec4(p0, 1.0)).xyz;
		NORMAL = normalize((transpose(MODEL_MATRIX) * vec4(nn, 0.0)).xyz);
		wp = p0;
	}
	wpos = wp;
}
void fragment() {
	vec3 c = col * mix(vec3(1.0), COLOR.rgb, use_vc);
	float prints = vnoise3(wpos * 1.6);
	vec2 q = (wpos.xy + wpos.zz * 0.7) * 2.2;
	vec2 cell = floor(q);
	float ring = length(fract(q) - 0.5 + (vec2(hash12(cell), hash12(cell + 7.0)) - 0.5) * 0.3);
	float fade = 1.0 - smoothstep(0.3, 1.2, length(fwidth(q)) * 30.0);
	float ridge = sin(ring * 90.0) * smoothstep(0.6, 0.8, prints) * smoothstep(0.5, 0.2, ring) * fade;
	float h = ridge * 0.4 + vnoise3(wpos * 18.0) * 0.5 * fade + vnoise3(wpos * 3.0) * 0.6;
	vec3 dpx = dFdx(VERTEX); vec3 dpy = dFdy(VERTEX);
	float dhx = dFdx(h); float dhy = dFdy(h);
	vec3 r1 = cross(dpy, NORMAL); vec3 r2 = cross(NORMAL, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * 0.0015);
	ALBEDO = c * (0.96 + 0.06 * vnoise3(wpos * 4.0));
	ROUGHNESS = 0.5;
	SPECULAR = 0.35;
	EMISSION = emit;
}
""", {"col": col, "use_vc": 1.0 if use_vc else 0.0, "emit": emit, "lump": lump})


## Comic ink: hard light bands, hatching on the shadow side, ink along the face edges.
static func comic(col: Color, use_vc: bool, sun: Vector3, emit: Color = Color.BLACK) -> ShaderMaterial:
	var m:= shader_mat("""
shader_type spatial;
render_mode diffuse_toon, specular_toon;
uniform vec3 col;
uniform float use_vc;
uniform vec3 emit;
uniform vec3 sun;
varying vec3 wnrm;
void vertex() { wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz); }
void fragment() {
	vec3 c = col * mix(vec3(1.0), COLOR.rgb, use_vc);
	float ndl = dot(normalize(wnrm), normalize(sun));
	vec2 fc = FRAGCOORD.xy;
	float h1 = step(0.62, fract((fc.x + fc.y) / 7.0));
	float h2 = step(0.62, fract((fc.x - fc.y) / 7.0));
	float hatch = (ndl < 0.2 ? h1 : 0.0) + (ndl < -0.35 ? h2 : 0.0);
	c *= 1.0 - min(hatch, 1.0) * 0.6;
	if (UV2.x > 0.0) {
		float d = min(min(UV.x, UV2.x - UV.x), min(UV.y, UV2.y - UV.y));
		float w = 0.025 + 0.004 * length(VERTEX);
		c *= smoothstep(w * 0.6, w, d) * 0.92 + 0.08;
	}
	ALBEDO = c;
	ROUGHNESS = 0.7;
	SPECULAR = 0.25;
	EMISSION = emit;
}
""", {"col": col, "use_vc": 1.0 if use_vc else 0.0, "emit": emit, "sun": sun})
	m.next_pass = ink_outline(0.02)
	return m


static func ink_outline(width: float, colour: Color = Color(0.03, 0.02, 0.04)) -> ShaderMaterial:
	return shader_mat("""
shader_type spatial;
render_mode unshaded, cull_front;
uniform float width;
uniform vec3 ink;
void vertex() {
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 vn = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vp.xyz += vn * width * clamp(-vp.z * 0.1, 0.5, 3.0);
	POSITION = PROJECTION_MATRIX * vp;
}
void fragment() { ALBEDO = ink; }
""", {"width": width, "ink": colour})


## Hand-painted storybook: brushy colour variation, warm tops and cool bases, edges painted
## a shade darker, no shiny highlights.
static func painted(col: Color, use_vc: bool, emit: Color = Color.BLACK, warp: float = 0.0) -> ShaderMaterial:
	return shader_mat("""
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;
uniform vec3 col;
uniform float use_vc;
uniform vec3 emit;
uniform float warp;
varying vec3 wpos;
""" + NOISE + """
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (warp > 0.0) {
		float hgt = max(wp.y, 0.0);
		vec3 lean = vec3(sin(wp.x * 0.18 + 0.6) * 0.05 * pow(hgt, 1.3), -abs(sin(wp.x * 0.4)) * 0.02 * hgt, sin(wp.x * 0.3) * 0.02 * hgt);
		vec3 wob = (vec3(vnoise3(wp * 0.25), vnoise3(wp * 0.25 + 9.0) * 0.5, vnoise3(wp * 0.25 + 19.0)) - vec3(0.5, 0.25, 0.5)) * 0.24;
		wp += (lean + wob * min(hgt, 1.0)) * warp;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
	}
	wpos = wp;
}
void fragment() {
	vec3 c = col * mix(vec3(1.0), COLOR.rgb, use_vc);
	float stroke = vnoise(vec2(wpos.x * 2.5 + wpos.z * 2.5 + vnoise(wpos.xy * 1.5) * 2.0, wpos.y * 14.0));
	float blot = vnoise3(wpos * 0.9);
	c *= 0.86 + 0.24 * stroke;
	c = mix(c * vec3(0.78, 0.8, 1.05), c * vec3(1.08, 1.03, 0.9), smoothstep(0.2, 0.8, blot));
	c *= mix(0.8, 1.05, smoothstep(0.0, 2.5, wpos.y));
	if (UV2.x > 0.0) {
		float d = min(min(UV.x, UV2.x - UV.x), min(UV.y, UV2.y - UV.y));
		c *= mix(0.72, 1.0, smoothstep(0.0, 0.07 + 0.04 * stroke, d));
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	EMISSION = emit;
}
""", {"col": col, "use_vc": 1.0 if use_vc else 0.0, "emit": emit, "warp": warp})


## PS1: vertices snap to a coarse screen grid, lighting per vertex, textures warp (affine)
## and are tiny and pixelated. `tex` may be null (then a pixel-noise pattern stands in).
static func ps1(col: Color, use_vc: bool, tex: Texture2D, tex_m: float, emit: Color = Color.BLACK) -> ShaderMaterial:
	return shader_mat("""
shader_type spatial;
render_mode vertex_lighting, specular_disabled;
uniform vec3 col;
uniform float use_vc;
uniform vec3 emit;
uniform sampler2D tex : filter_nearest, repeat_enable;
uniform float has_tex;
uniform float tex_m;
varying vec3 auv;
varying vec3 wpos;
""" + NOISE + """
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = abs(normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz));
	vec2 tuv = wn.y > 0.6 ? wpos.xz : (wn.x > wn.z ? vec2(wpos.z, -wpos.y) : vec2(wpos.x, -wpos.y));
	vec4 p = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec2 res = vec2(200.0, 120.0);
	p.xy = floor(p.xy / p.w * res + 0.5) / res * p.w;
	POSITION = p;
	auv = vec3(tuv / tex_m * p.w, p.w);
}
void fragment() {
	vec2 uv = auv.xy / auv.z;
	vec3 c = col * mix(vec3(1.0), COLOR.rgb, use_vc);
	if (has_tex > 0.5) {
		c *= texture(tex, uv).rgb;
	} else {
		c *= 0.82 + 0.3 * hash12(floor(uv * 16.0));
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	EMISSION = emit;
}
""", {"col": col, "use_vc": 1.0 if use_vc else 0.0, "emit": emit, "tex": tex, "has_tex": 1.0 if tex else 0.0, "tex_m": tex_m})


## Paper craft: card stock fibres, a white cut edge on every card, soft and matte.
static func paper(col: Color, use_vc: bool, emit: Color = Color.BLACK) -> ShaderMaterial:
	return shader_mat("""
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;
uniform vec3 col;
uniform float use_vc;
uniform vec3 emit;
varying vec3 wpos;
""" + NOISE + """
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 c = col * mix(vec3(1.0), COLOR.rgb, use_vc);
	float fib = vnoise(wpos.xy * 90.0 + wpos.z * 40.0) * 0.5 + vnoise(wpos.xz * 70.0) * 0.5;
	c *= 0.88 + 0.18 * fib;
	if (UV2.x > 0.0) {
		if (min(UV2.x, UV2.y) < 0.05) {
			c = vec3(0.95, 0.93, 0.88) * (0.92 + 0.08 * fib);
		} else {
			float d = min(min(UV.x, UV2.x - UV.x), min(UV.y, UV2.y - UV.y));
			c = mix(vec3(0.97, 0.95, 0.9), c, smoothstep(0.035, 0.045, d));
		}
	}
	ALBEDO = c;
	ROUGHNESS = 0.95;
	EMISSION = emit;
}
""", {"col": col, "use_vc": 1.0 if use_vc else 0.0, "emit": emit})


## Tiny pixel-art textures for the PS1 look, drawn by hand in code (nearest-filtered).
static func pixel_tex(kind: String) -> ImageTexture:
	var n:= 32
	var img:= Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng:= RandomNumberGenerator.new()
	rng.seed = hash(kind)
	for y in n:
		for x in n:
			var c:= Color(1, 1, 1)
			var j:= rng.randf_range(-0.12, 0.12)
			match kind:
				"brick":
					var row:= y / 4
					var off:= 4 if row % 2 == 1 else 0
					var mortar:= y % 4 == 3 or (x + off) % 8 == 7
					c = Color(0.62, 0.62, 0.6) if mortar else Color(1.0 + j, 0.95 + j, 0.95 + j)
				"asphalt":
					c = Color(1, 1, 1) * (0.8 + rng.randf() * 0.35)
				"slab":
					c = Color(1, 1, 1) * ((0.7 if x % 16 == 0 or y % 16 == 0 else 0.95) + j * 0.5)
				"grass":
					c = Color(0.8 + j, 1.0 + j * 1.5, 0.7 + j) * (0.7 + rng.randf() * 0.5)
				"pine":
					var tier:= float(y % 11) / 11.0
					var half:= (2.0 + float(y) * 0.42) * (0.65 + 0.35 * tier)
					var on:= absf(x - 15.5) < half and rng.randf() < 0.92
					c = Color(0.2 + j, 0.45 + j, 0.25 + j, 1.0 if on else 0.0)
				"fern":
					var on2:= absf(x - 15.5) < float(y) * 0.5 and (x + y) % 3 != 0
					c = Color(0.3 + j, 0.6 + j, 0.25 + j, 1.0 if on2 else 0.0)
				"leaves":
					var d:= Vector2(x - 16, y - 16).length()
					var leafy:= rng.randf() < 0.85 - d / 22.0
					c = Color(0.35 + j, 0.62 + j, 0.25 + j, 1.0 if leafy else 0.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
