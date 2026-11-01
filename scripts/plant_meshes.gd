extends RefCounted
class_name PlantMeshes
## Procedural low-poly meshes for the scenery: layered pines with ragged, drooping branch
## skirts, broadleaf trees with lumpy canopies, clumpy bushes and faceted boulders.
## Vertex colours carry the shading detail (darker undersides and crevices, lighter tips);
## each MultiMesh instance colour tints on top of that.
## Every mesh is built once per variant and cached.
## Winding: Godot treats triangles whose (b-a)x(c-a) points INTO the shape as front-facing.

static var _cache:= {}


static func _noise(seed_value: int, freq: float) -> FastNoiseLite:
	var n:= FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return n


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)


static func _finish(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	return st.commit()


static func _grey(v: float) -> Color:
	v = clampf(v, 0.0, 1.0)
	return Color(v, v, v)


# ------------------------------------------------------------------ pine

## Canopy only (the trunk is separate so it can be tinted brown). Ground at y = 0.
static func pine_canopy(variant: int) -> ArrayMesh:
	var key:= "pine%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng:= RandomNumberGenerator.new()
	rng.seed = 1000 + variant
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tiers:= 5 + variant % 2
	var y0:= 1.4
	var top:= 6.6 + rng.randf_range(-0.4, 0.4)
	for t in tiers:
		var f:= float(t) / float(tiers - 1)
		var base_y:= lerpf(y0, top - 1.6, f)
		var r:= lerpf(2.1, 0.55, f) * rng.randf_range(0.92, 1.08)
		var h:= lerpf(2.0, 1.5, f)
		var apex:= Vector3(rng.randf_range(-0.05, 0.05), base_y + h, rng.randf_range(-0.05, 0.05))
		var inner:= Vector3(0, base_y + h * 0.3, 0)
		var n:= 16
		var ring: Array[Vector3] = []
		var tip: Array[bool] = []
		var twist:= rng.randf() * TAU
		for i in n:
			var a:= twist + TAU * i / n
			var long:= i % 2 == 0
			var rr:= r * (1.0 if long else 0.7) * rng.randf_range(0.9, 1.1)
			var droop:= (0.22 if long else 0.05) * r * rng.randf_range(0.7, 1.2)
			ring.append(Vector3(cos(a) * rr, base_y - droop, sin(a) * rr))
			tip.append(long)
		for i in n:
			var j:= (i + 1) % n
			var ci:= _grey(0.98 if tip[i] else 0.78)
			var cj:= _grey(0.98 if tip[j] else 0.78)
			# outer skirt: light tips, a bit darker toward the crown's shadowed core
			_tri(st, apex, ring[i], ring[j], _grey(0.9), ci, cj)
			# underside: dark
			_tri(st, inner, ring[j], ring[i], _grey(0.5), _grey(0.62), _grey(0.62))
	# little spike on top
	var tip_base:= top - 0.1
	var spike:= Vector3(0, top + 0.7, 0)
	for i in 6:
		var a:= TAU * i / 6.0
		var b:= TAU * (i + 1) / 6.0
		_tri(st, spike, Vector3(cos(a) * 0.18, tip_base, sin(a) * 0.18), Vector3(cos(b) * 0.18, tip_base, sin(b) * 0.18),
			_grey(1.0), _grey(0.85), _grey(0.85))
	var m:= _finish(st)
	_cache[key] = m
	return m


## Tapered trunk with a root flare and a few bark facets. Ground at y = 0.
static func trunk(variant: int, height: float = 5.6, r_base: float = 0.32, r_top: float = 0.1) -> ArrayMesh:
	var key:= "trunk%d_%.1f_%.2f" % [variant, height, r_base]
	if _cache.has(key):
		return _cache[key]
	var rng:= RandomNumberGenerator.new()
	rng.seed = 2000 + variant
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides:= 8
	var rows:= 6
	var rings: Array = []
	for k in rows + 1:
		var f:= float(k) / rows
		var y:= f * height - 0.25
		var r:= lerpf(r_base, r_top, f)
		if k == 0:
			r *= 1.6   # roots flare into the ground
		elif k == 1:
			r *= 1.15
		var bend:= Vector3(sin(f * 2.0 + variant) * 0.08, 0, cos(f * 1.7 + variant) * 0.08) * f
		var ring: Array[Vector3] = []
		for i in sides:
			var a:= TAU * i / sides
			var rr:= r * rng.randf_range(0.85, 1.12)
			ring.append(Vector3(cos(a) * rr, y, sin(a) * rr) + bend)
		rings.append(ring)
	for k in rows:
		var shade_lo:= lerpf(0.55, 0.95, float(k) / rows)
		var shade_hi:= lerpf(0.55, 0.95, float(k + 1) / rows)
		for i in sides:
			var j:= (i + 1) % sides
			var a: Vector3 = rings[k][i]
			var b: Vector3 = rings[k][j]
			var c: Vector3 = rings[k + 1][j]
			var d: Vector3 = rings[k + 1][i]
			# alternate darker "grooves" in the bark
			var g:= 0.82 if i % 2 == 0 else 1.0
			_tri(st, a, b, c, _grey(shade_lo * g), _grey(shade_lo * g), _grey(shade_hi * g))
			_tri(st, a, c, d, _grey(shade_lo * g), _grey(shade_hi * g), _grey(shade_hi * g))
	var m:= _finish(st)
	_cache[key] = m
	return m


# ------------------------------------------------------------------ lumpy shapes

static func _icosphere(subdiv: int) -> Array:
	var t:= (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in verts.size():
		verts[i] = verts[i].normalized()
	var faces:= [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for _s in subdiv:
		var mid:= {}
		var nf: Array = []
		for f in faces:
			var m: Array = []
			for e in [[f[0], f[1]], [f[1], f[2]], [f[2], f[0]]]:
				var k:= "%d_%d" % [mini(e[0], e[1]), maxi(e[0], e[1])]
				if not mid.has(k):
					verts.append(((verts[e[0]] + verts[e[1]]) * 0.5).normalized())
					mid[k] = verts.size() - 1
				m.append(mid[k])
			nf.append([f[0], m[0], m[2]])
			nf.append([f[1], m[1], m[0]])
			nf.append([f[2], m[2], m[1]])
			nf.append([m[0], m[1], m[2]])
		faces = nf
	return [verts, faces]


## Adds a noisy lump. shade(p_world_dir_y) gives the vertex brightness.
static func _lump(st: SurfaceTool, centre: Vector3, radius: Vector3, subdiv: int, noise: FastNoiseLite, amp: float,
		dark_bottom: float, flat_bottom: float = -99.0) -> void:
	var ico:= _icosphere(subdiv)
	var verts: Array = ico[0]
	var pts: Array[Vector3] = []
	var cols: Array[Color] = []
	for v: Vector3 in verts:
		var p:= centre + v * radius * (1.0 + amp * noise.get_noise_3dv(centre + v * 2.0))
		if p.y < flat_bottom:
			p.y = flat_bottom
		pts.append(p)
		# light from above, dark underneath, a bit of noise for mottling
		var lit:= lerpf(dark_bottom, 1.0, clampf(v.y * 0.5 + 0.5, 0.0, 1.0)) * (0.92 + 0.16 * noise.get_noise_3dv(p * 3.0))
		cols.append(_grey(lit))
	for f in ico[1]:
		_tri(st, pts[f[0]], pts[f[2]], pts[f[1]], cols[f[0]], cols[f[2]], cols[f[1]])


## Broadleaf canopy (Lakeside birches): a cluster of lumps up on top. Ground at y = 0.
static func broadleaf_canopy(variant: int) -> ArrayMesh:
	var key:= "leaf%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng:= RandomNumberGenerator.new()
	rng.seed = 3000 + variant
	var nz:= _noise(3100 + variant, 0.9)
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count:= 6 + variant
	for i in count:
		var a:= TAU * i / count + rng.randf_range(-0.3, 0.3)
		var d:= rng.randf_range(0.5, 1.2) if i > 0 else 0.0
		var c:= Vector3(cos(a) * d, rng.randf_range(4.3, 5.6) if i > 0 else 5.9, sin(a) * d)
		var r:= rng.randf_range(0.9, 1.35)
		_lump(st, c, Vector3(r, r * 0.85, r), 1, nz, 0.22, 0.5)
	var m:= _finish(st)
	_cache[key] = m
	return m


## Bush: a few overlapping lumps, sitting on the ground (y = 0), about 2 m across.
static func bush(variant: int) -> ArrayMesh:
	var key:= "bush%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng:= RandomNumberGenerator.new()
	rng.seed = 4000 + variant
	var nz:= _noise(4100 + variant, 1.2)
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count:= 4 + variant
	for i in count:
		var a:= TAU * i / count + rng.randf_range(-0.4, 0.4)
		var d:= rng.randf_range(0.35, 0.6) if i > 0 else 0.0
		var r:= rng.randf_range(0.5, 0.75) if i > 0 else 0.85
		var c:= Vector3(cos(a) * d, r * 0.75, sin(a) * d)
		_lump(st, c, Vector3(r, r * 0.9, r), 1, nz, 0.25, 0.45, 0.0)
	var m:= _finish(st)
	_cache[key] = m
	return m


## Boulder: a faceted, noise-carved rock about 2 m across, centred on the origin.
## Darker crevices, a slightly lighter, mossy-ready top.
static func rock(variant: int) -> ArrayMesh:
	var key:= "rock%d" % variant
	if _cache.has(key):
		return _cache[key]
	var nz:= _noise(5000 + variant, 0.7)
	nz.fractal_octaves = 3
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	var ico:= _icosphere(2)
	var verts: Array = ico[0]
	var pts: Array[Vector3] = []
	for v: Vector3 in verts:
		var squash:= Vector3(1.0 + 0.15 * sin(variant * 1.7), 1.0, 1.0 - 0.12 * cos(variant * 2.3))
		var d:= 1.0 + 0.32 * nz.get_noise_3dv(v * 1.6) + 0.1 * nz.get_noise_3dv(v * 5.0)
		pts.append(v * squash * d)
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # flat-shaded facets
	for f in ico[1]:
		var a: Vector3 = pts[f[0]]
		var b: Vector3 = pts[f[2]]
		var c: Vector3 = pts[f[1]]
		var cen:= (a + b + c) / 3.0
		var nrm:= -(b - a).cross(c - a).normalized()   # Godot's front faces wind the other way
		# crevices (pulled-in faces) darker, up-facing faces lighter
		var depth:= clampf(cen.length() - 0.85, -0.3, 0.3)
		var g:= clampf(0.78 + depth * 0.9 + nrm.y * 0.12, 0.45, 1.0)
		_tri(st, a, b, c, _grey(g), _grey(g), _grey(g))
	var m:= _finish(st)
	_cache[key] = m
	return m
