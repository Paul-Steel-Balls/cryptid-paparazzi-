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


# ================================================================== v0.17: close-up detail
## The meshes above are now the far versions (Forest swaps to them past a few dozen metres).
## These are the near ones: pines made of drooping needle boughs, broadleafs with forked limbs
## and leafy crowns, layered mossy rocks, leafy bushes, real flowers, fern fronds, grass tufts.
## Vertex colours carry the real colours where a plant has more than one (flowers, moss, birch
## bark), and stay greyscale where the instance colour does the tinting (needles, leaves).

## Outward-facing triangle (a, b, c counter-clockwise seen from outside): flip for Godot.
static func _tri_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	_tri(st, a, c, b, ca, cc, cb)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_tri_out(st, a, b, c, ca, cb, cc)
	_tri_out(st, a, c, d, ca, cc, cd)


## A drooping needle bough: a tent-shaped spray (raised spine, drooping edges) with needle
## tufts along both edges. dir/side are horizontal unit vectors.
static func _bough(st: SurfaceTool, base: Vector3, dir: Vector3, side: Vector3, length: float, width: float,
		droop: float, shade: float, rng: RandomNumberGenerator) -> void:
	var segs:= 3
	var lefts: Array[Vector3] = []
	var mids: Array[Vector3] = []
	var rights: Array[Vector3] = []
	var cols: Array[float] = []
	for i in segs + 1:
		var s:= float(i) / segs
		var p:= base + dir * length * s + Vector3.UP * (length * 0.16 * s - droop * s * s)
		var w:= width * sin(PI * (0.14 + 0.86 * s)) * (1.0 - 0.25 * s) + 0.02
		lefts.append(p - side * w * 0.5 - Vector3.UP * w * 0.2)
		mids.append(p + Vector3.UP * w * 0.18)
		rights.append(p + side * w * 0.5 - Vector3.UP * w * 0.2)
		cols.append(lerpf(0.42, 1.0, s) * shade)
	for i in segs:
		var j:= i + 1
		var e:= 0.92
		_quad(st, lefts[i], mids[i], mids[j], lefts[j], _grey(cols[i] * e), _grey(cols[i]), _grey(cols[j]), _grey(cols[j] * e))
		_quad(st, mids[i], rights[i], rights[j], mids[j], _grey(cols[i]), _grey(cols[i] * e), _grey(cols[j] * e), _grey(cols[j]))
		# needle tufts poking out and down from each edge
		for edge in [[lefts, -1.0], [rights, 1.0]]:
			var pts: Array = edge[0]
			var sg: float = edge[1]
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[j]
			var w:= a.distance_to(b)
			var tip:= (a + b) * 0.5 + side * sg * w * rng.randf_range(0.35, 0.6) - Vector3.UP * w * 0.35 + dir * w * 0.2
			_tri(st, a, tip, b, _grey(cols[i] * 0.95), _grey(minf(1.0, cols[j] * 1.05)), _grey(cols[j] * 0.95))


static func pine_hi(variant: int) -> ArrayMesh:
	var key:= "pine_hi%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng:= RandomNumberGenerator.new()
	rng.seed = 7000 + variant
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var whorls:= 8 + variant
	var top:= 6.8 + rng.randf_range(-0.3, 0.4)
	# Dark core so you don't see sky straight through the middle.
	var core_n:= 7
	for i in core_n:
		var a0:= TAU * i / core_n
		var a1:= TAU * (i + 1) / core_n
		_tri_out(st, Vector3(cos(a0) * 0.55, 1.2, sin(a0) * 0.55), Vector3(cos(a1) * 0.55, 1.2, sin(a1) * 0.55), Vector3(0, top, 0),
			_grey(0.3), _grey(0.3), _grey(0.55))
	for w in whorls:
		var f:= float(w) / float(whorls - 1)
		var y:= lerpf(1.25, top - 0.9, f) + rng.randf_range(-0.08, 0.08)
		var length:= lerpf(2.45, 0.5, pow(f, 0.85)) * rng.randf_range(0.9, 1.1)
		var nb:= 9 if f < 0.45 else (7 if f < 0.8 else 5)
		var twist:= rng.randf() * TAU
		for b in nb:
			var a:= twist + TAU * b / nb + rng.randf_range(-0.18, 0.18)
			var dir:= Vector3(cos(a), 0, sin(a))
			var side:= Vector3(-sin(a), 0, cos(a))
			var shade:= lerpf(0.82, 1.0, f) * rng.randf_range(0.9, 1.05)
			_bough(st, Vector3(0, y, 0) + dir * 0.08, dir, side, length * rng.randf_range(0.85, 1.1), length * 0.5,
				length * lerpf(0.42, 0.18, f), shade, rng)
	# Leader: a little upright spray at the very top.
	for i in 4:
		var a:= TAU * i / 4.0 + 0.4
		var dir:= Vector3(cos(a), 0, sin(a))
		_bough(st, Vector3(0, top - 0.5, 0), (dir * 0.35 + Vector3.UP).normalized(), Vector3(-sin(a), 0, cos(a)), 0.9, 0.3, 0.0, 1.0, rng)
	var m:= _finish(st)
	_cache[key] = m
	return m


## Trunk with root buttresses, bark streaks (or birch markings), and optionally forked limbs
## up into a broadleaf crown, or dead stubs low down on a pine. Ground at y = 0.
static func trunk_hi(variant: int, height: float, r_base: float, r_top: float, birch: bool = false, limbs: int = 0,
		stubs: int = 0) -> ArrayMesh:
	var key:= "trunk_hi%d_%.1f_%.2f_%s_%d_%d" % [variant, height, r_base, birch, limbs, stubs]
	if _cache.has(key):
		return _cache[key]
	var rng:= RandomNumberGenerator.new()
	rng.seed = 8000 + variant
	var bark:= _noise(8100 + variant, 1.0)
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides:= 10
	var rows:= 9
	var rings: Array = []
	var cols: Array = []
	var phase:= rng.randf() * TAU
	for k in rows + 1:
		var f:= float(k) / rows
		var y:= f * height - 0.3
		var r:= lerpf(r_base, r_top, pow(f, 0.8))
		var flare:= clampf(1.0 - f * 4.0, 0.0, 1.0)
		var bend:= Vector3(sin(f * 2.0 + variant) * 0.1, 0, cos(f * 1.7 + variant) * 0.1) * f
		var ring: Array[Vector3] = []
		var cr: Array[Color] = []
		for i in sides:
			var a:= TAU * i / sides
			var roots:= 1.0 + flare * flare * (0.55 * maxf(0.0, cos(5.0 * a + phase)) + 0.25)
			var rr:= r * roots * (1.0 + 0.06 * bark.get_noise_2d(a * 3.0, y * 2.0))
			ring.append(Vector3(cos(a) * rr, y, sin(a) * rr) + bend)
			var g:= 0.72 + 0.28 * bark.get_noise_2d(a * 6.0, y * 0.6)
			if birch:
				g = 1.0
				var band:= fposmod(y * 2.4 + sin(a * 3.0 + variant) * 0.25, 1.0)
				if band < 0.13 and bark.get_noise_2d(a * 4.0, y * 3.0) > -0.25:
					g = 0.22
				if y < 0.4:
					g = 0.45   # dark base
			cr.append(_grey(g * lerpf(0.75, 1.0, f)))
		rings.append(ring)
		cols.append(cr)
	for k in rows:
		for i in sides:
			var j:= (i + 1) % sides
			_quad(st, rings[k][i], rings[k + 1][i], rings[k + 1][j], rings[k][j], cols[k][i], cols[k + 1][i], cols[k + 1][j], cols[k][j])
	# Forked limbs reaching up into the crown.
	for l in limbs:
		var a:= TAU * l / limbs + rng.randf_range(-0.3, 0.3)
		var from:= Vector3(0, height * rng.randf_range(0.62, 0.78), 0)
		var to:= from + Vector3(cos(a) * rng.randf_range(0.9, 1.4), rng.randf_range(1.0, 1.6), sin(a) * rng.randf_range(0.9, 1.4))
		_tube(st, from, to, r_top * 1.6, r_top * 0.5, 6, _grey(0.85 if not birch else 0.95))
	# Dead stubs on a pine's lower trunk.
	for s in stubs:
		var a:= rng.randf() * TAU
		var y:= rng.randf_range(0.9, 2.2)
		var from:= Vector3(0, y, 0)
		_tube(st, from, from + Vector3(cos(a) * 0.5, -0.15, sin(a) * 0.5), 0.05, 0.015, 4, _grey(0.5))
	var m:= _finish(st)
	_cache[key] = m
	return m


static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, sides: int, col: Color) -> void:
	var ax:= (b - a).normalized()
	var u:= ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
	var v:= ax.cross(u)
	for i in sides:
		var a0:= TAU * i / sides
		var a1:= TAU * (i + 1) / sides
		var d0:= u * cos(a0) + v * sin(a0)
		var d1:= u * cos(a1) + v * sin(a1)
		_quad(st, a + d0 * ra, a + d1 * ra, b + d1 * rb, b + d0 * rb, col, col, col.lightened(0.05), col.lightened(0.05))


## Broadleaf crown: a dome of leafy clumps, each its own shade, with small sprigs breaking the
## outline. Lit from above, dark inside. Ground at y = 0 (crown 4..7 m up).
static func broadleaf_hi(variant: int) -> ArrayMesh:
	var key:= "leaf_hi%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng:= RandomNumberGenerator.new()
	rng.seed = 9000 + variant
	var nz:= _noise(9100 + variant, 1.4)
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre:= Vector3(0, 4.95, 0)
	var count:= 13 + variant * 2
	var spots: Array[Vector3] = []
	for i in count:
		# Spread the clumps over a squashed dome.
		var u:= rng.randf()
		var a:= rng.randf() * TAU
		var elev:= lerpf(-0.35, 1.0, sqrt(u))
		var dirv:= Vector3(cos(a) * cos(elev), sin(elev) * 0.75, sin(a) * cos(elev))
		var c:= centre + dirv * rng.randf_range(0.85, 1.45)
		var r:= rng.randf_range(0.65, 1.0)
		spots.append(c)
		_lump_shaded(st, c, Vector3(r, r * 0.8, r), 1, nz, 0.32, 0.45, rng.randf_range(0.82, 1.05), centre)
	# Sprigs: little leaf clusters sticking out of the clumps.
	for i in 22:
		var c: Vector3 = spots[rng.randi_range(0, spots.size() - 1)]
		var out:= (c - centre).normalized()
		var p:= c + (out + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.2, 0.4), rng.randf_range(-0.5, 0.5))).normalized() * rng.randf_range(0.7, 1.0)
		_lump_shaded(st, p, Vector3.ONE * rng.randf_range(0.22, 0.35), 0, nz, 0.2, 0.6, rng.randf_range(0.95, 1.1), centre)
	var m:= _finish(st)
	_cache[key] = m
	return m


## Like _lump, but brightness also falls off toward the crown's centre (self-shadowing) and
## each lump gets its own shade.
static func _lump_shaded(st: SurfaceTool, c: Vector3, radius: Vector3, subdiv: int, noise: FastNoiseLite, amp: float,
		dark_bottom: float, shade: float, core: Vector3, flat_bottom: float = -99.0) -> void:
	var ico:= _icosphere(subdiv)
	var verts: Array = ico[0]
	var pts: Array[Vector3] = []
	var cols: Array[Color] = []
	for v: Vector3 in verts:
		var p:= c + v * radius * (1.0 + amp * noise.get_noise_3dv(c * 1.7 + v * 2.3))
		if p.y < flat_bottom:
			p.y = flat_bottom
		pts.append(p)
		var up:= clampf(v.y * 0.5 + 0.5, 0.0, 1.0)
		var outward:= clampf((p - core).normalized().dot(v) * 0.5 + 0.5, 0.0, 1.0)
		var lit:= lerpf(dark_bottom, 1.0, up) * lerpf(0.7, 1.0, outward) * shade * (0.9 + 0.2 * noise.get_noise_3dv(p * 4.0))
		cols.append(_grey(lit))
	for f in ico[1]:
		_tri(st, pts[f[0]], pts[f[2]], pts[f[1]], cols[f[0]], cols[f[2]], cols[f[1]])


## Bush: a mound of leafy clumps (flat underneath) with sprigs. About 2 m across, on y = 0.
static func bush_hi(variant: int) -> ArrayMesh:
	var key:= "bush_hi%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng:= RandomNumberGenerator.new()
	rng.seed = 9500 + variant
	var nz:= _noise(9600 + variant, 1.8)
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var core:= Vector3(0, 0.45, 0)
	var count:= 8 + variant * 2
	for i in count:
		var a:= rng.randf() * TAU
		var d:= rng.randf_range(0.0, 0.6)
		var r:= rng.randf_range(0.38, 0.58)
		var c:= Vector3(cos(a) * d, r * 0.7 + rng.randf_range(0.0, 0.35) * (1.0 - d), sin(a) * d)
		_lump_shaded(st, c, Vector3(r, r * 0.85, r), 1, nz, 0.35, 0.4, rng.randf_range(0.85, 1.05), core, 0.0)
	for i in 14:
		var a:= rng.randf() * TAU
		var p:= Vector3(cos(a) * rng.randf_range(0.5, 0.85), rng.randf_range(0.35, 0.95), sin(a) * rng.randf_range(0.5, 0.85))
		_lump_shaded(st, p, Vector3.ONE * rng.randf_range(0.14, 0.24), 0, nz, 0.2, 0.6, rng.randf_range(0.95, 1.1), core, 0.0)
	var m:= _finish(st)
	_cache[key] = m
	return m


## Boulder up close: finer facets, sedimentary layers, cracks, moss on top, lichen spots.
## Real colours in the vertices; the instance colour just shifts brightness/tint.
static func rock_hi(variant: int) -> ArrayMesh:
	var key:= "rock_hi%d" % variant
	if _cache.has(key):
		return _cache[key]
	var nz:= _noise(5000 + variant, 0.7)
	nz.fractal_octaves = 4
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	var moss_n:= _noise(5200 + variant, 2.2)
	var ico:= _icosphere(3)
	var verts: Array = ico[0]
	var pts: Array[Vector3] = []
	for v: Vector3 in verts:
		var squash:= Vector3(1.0 + 0.15 * sin(variant * 1.7), 1.0, 1.0 - 0.12 * cos(variant * 2.3))
		var d:= 1.0 + 0.32 * nz.get_noise_3dv(v * 1.6) + 0.1 * nz.get_noise_3dv(v * 5.0)
		d += 0.025 * sin(v.y * 16.0 + nz.get_noise_3dv(v * 2.0) * 4.0)   # layers
		d -= 0.06 * maxf(0.0, 1.0 - absf(nz.get_noise_3dv(v * 3.3 + Vector3(9, 9, 9))) * 14.0)   # cracks
		pts.append(v * squash * d)
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var stone:= Color(0.62, 0.61, 0.6)
	var moss:= Color(0.33, 0.5, 0.2)
	var lichen:= Color(0.78, 0.74, 0.45)
	for f in ico[1]:
		var a: Vector3 = pts[f[0]]
		var b: Vector3 = pts[f[2]]
		var c: Vector3 = pts[f[1]]
		var cen:= (a + b + c) / 3.0
		var nrm:= -(b - a).cross(c - a).normalized()
		var depth:= clampf(cen.length() - 0.85, -0.3, 0.3)
		var g:= clampf(0.8 + depth * 0.9 + nrm.y * 0.1, 0.45, 1.05)
		var col:= Color(stone.r * g, stone.g * g, stone.b * g * 1.02)
		col = col.lerp(Color(0.55, 0.5, 0.45) * g, clampf(0.5 + 0.5 * sin(cen.y * 16.0), 0.0, 1.0) * 0.25)   # banding
		var mossy:= clampf((nrm.y - 0.35) * 2.2 + moss_n.get_noise_3dv(cen * 2.0) * 0.8, 0.0, 1.0)
		col = col.lerp(moss * g, mossy)
		if moss_n.get_noise_3dv(cen * 9.0) > 0.55 and mossy < 0.3:
			col = col.lerp(lichen, 0.6)
		_tri(st, a, b, c, col, col, col)
	var m:= _finish(st)
	_cache[key] = m
	return m


const FLOWER_COLS:= [Color(0.95, 0.15, 0.15), Color(1.0, 0.85, 0.1), Color(1.0, 0.5, 0.78), Color(0.98, 0.98, 0.95),
	Color(1.0, 0.55, 0.1), Color(0.55, 0.4, 0.95)]


## A clump of 4-6 flowers: curved stems, leaves, a centre and a ring of cupped petals.
## kind = colour index into FLOWER_COLS (white ones get yellow centres: daisies).
static func flower_clump(kind: int) -> ArrayMesh:
	var key:= "flowers%d" % kind
	if _cache.has(key):
		return _cache[key]
	var rng:= RandomNumberGenerator.new()
	rng.seed = 6100 + kind
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var petal_c: Color = FLOWER_COLS[kind % FLOWER_COLS.size()]
	var centre_c:= Color(0.95, 0.75, 0.1) if kind in [3, 5] else Color(0.35, 0.22, 0.08)
	var stem_c:= Color(0.2, 0.5, 0.18)
	var leaf_c:= Color(0.25, 0.58, 0.2)
	for k in rng.randi_range(4, 6):
		var base:= Vector3(rng.randf_range(-0.22, 0.22), 0.0, rng.randf_range(-0.22, 0.22))
		var h:= rng.randf_range(0.28, 0.48)
		var lean:= Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08))
		var mid:= base + Vector3(0, h * 0.5, 0) + lean * 0.4
		var top:= base + Vector3(0, h, 0) + lean
		_tube(st, base, mid, 0.012, 0.01, 3, stem_c)
		_tube(st, mid, top, 0.01, 0.008, 3, stem_c)
		# two leaves on the stem
		for s: float in [-1.0, 1.0]:
			var a:= rng.randf() * TAU
			var d:= Vector3(cos(a), 0.35, sin(a)) * s
			var lp:= base.lerp(mid, rng.randf_range(0.3, 0.8))
			var side:= d.cross(Vector3.UP).normalized() * 0.025
			var tip:= lp + d * 0.12
			_tri(st, lp, lp + d * 0.06 + side, tip, leaf_c, leaf_c.lightened(0.1), leaf_c.lightened(0.15))
			_tri(st, lp, tip, lp + d * 0.06 - side, leaf_c, leaf_c.lightened(0.15), leaf_c.darkened(0.1))
		# head: centre button and petals
		var face:= (Vector3.UP * 1.0 + lean * 2.0).normalized()
		var u:= face.cross(Vector3.RIGHT).normalized()
		var v:= face.cross(u)
		var n_p:= rng.randi_range(5, 7)
		var pr:= rng.randf_range(0.055, 0.085)
		var pc:= petal_c.lightened(rng.randf_range(-0.05, 0.1))
		for i in n_p:
			var a:= TAU * i / n_p
			var dirp:= (u * cos(a) + v * sin(a))
			var perp:= (u * cos(a + PI * 0.5) + v * sin(a + PI * 0.5))
			var outp:= top + dirp * pr + face * pr * 0.35
			var w:= pr * 0.42
			var midp:= top + dirp * pr * 0.5 + face * pr * 0.1
			_tri(st, top, midp + perp * w, outp, pc.darkened(0.15), pc, pc.lightened(0.15))
			_tri(st, top, outp, midp - perp * w, pc.darkened(0.15), pc.lightened(0.15), pc)
		for i in 5:
			var a0:= TAU * i / 5.0
			var a1:= TAU * (i + 1) / 5.0
			var r:= pr * 0.32
			_tri(st, top + face * r * 0.8, top + (u * cos(a0) + v * sin(a0)) * r + face * 0.005,
				top + (u * cos(a1) + v * sin(a1)) * r + face * 0.005, centre_c.lightened(0.15), centre_c, centre_c)
	var m:= _finish(st)
	_cache[key] = m
	return m


## A fern: 7 arching fronds, each lined with tapering leaflets. About 1.4 m across, on y = 0.
static func fern_clump(variant: int) -> ArrayMesh:
	var key:= "fern%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng:= RandomNumberGenerator.new()
	rng.seed = 6300 + variant
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fronds:= 7
	for k in fronds:
		var a:= TAU * k / fronds + rng.randf_range(-0.25, 0.25)
		var dir:= Vector3(cos(a), 0, sin(a))
		var side:= Vector3(-sin(a), 0, cos(a))
		var length:= rng.randf_range(0.6, 0.85)
		var rise:= rng.randf_range(0.45, 0.65)
		var segs:= 8
		var prev:= Vector3(0, 0.02, 0)
		for i in range(1, segs + 1):
			var t:= float(i) / segs
			var p:= dir * length * t + Vector3.UP * (length * rise * sin(PI * t * 0.75) - length * 0.25 * t * t)
			var leaflet:= length * 0.2 * sin(PI * (0.08 + 0.92 * t)) + 0.01
			var g:= _grey(lerpf(0.55, 1.0, t))
			var gd:= _grey(lerpf(0.5, 0.9, t))
			for s: float in [-1.0, 1.0]:
				var tip:= (prev + p) * 0.5 + side * s * leaflet + dir * leaflet * 0.45 - Vector3.UP * leaflet * 0.25
				_tri(st, prev, tip, p, gd, g, g)
			prev = p
	var m:= _finish(st)
	_cache[key] = m
	return m


## Grass tuft: nine bent blades, dark at the root, light at the tip. On y = 0.
static func grass_tuft(variant: int) -> ArrayMesh:
	var key:= "grass%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng:= RandomNumberGenerator.new()
	rng.seed = 6500 + variant
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 9:
		var a:= rng.randf() * TAU
		var base:= Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.14)
		var h:= rng.randf_range(0.22, 0.5)
		var bend_dir:= Vector3(cos(a + rng.randf_range(-0.8, 0.8)), 0, sin(a + rng.randf_range(-0.8, 0.8)))
		var face:= Vector3(-bend_dir.z, 0, bend_dir.x)
		var w:= rng.randf_range(0.022, 0.035)
		var mid:= base + Vector3.UP * h * 0.55 + bend_dir * h * 0.12
		var tip:= base + Vector3.UP * h + bend_dir * h * 0.38
		var c0:= _grey(0.45)
		var c1:= _grey(0.78)
		var c2:= _grey(1.0)
		_quad(st, base - face * w, base + face * w, mid + face * w * 0.7, mid - face * w * 0.7, c0, c0, c1, c1)
		_tri(st, mid - face * w * 0.7, tip, mid + face * w * 0.7, c1, c2, c1)
	var m:= _finish(st)
	_cache[key] = m
	return m


## Spotted toadstool cap (dome with a gill underside) and a stem with a ring. On y = 0.
static func toadstool(part: String) -> ArrayMesh:
	var key:= "toad_" + part
	if _cache.has(key):
		return _cache[key]
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs:= 12
	if part == "cap":
		var rings_n:= 4
		var spots:= _noise(6700, 3.0)
		for r in rings_n:
			var e0:= PI * 0.5 * float(r) / rings_n
			var e1:= PI * 0.5 * float(r + 1) / rings_n
			for i in segs:
				var a0:= TAU * i / segs
				var a1:= TAU * (i + 1) / segs
				var pts:= []
				for pair in [[a0, e0], [a1, e0], [a1, e1], [a0, e1]]:
					var a: float = pair[0]
					var e: float = pair[1]
					pts.append(Vector3(cos(a) * cos(e) * 0.13, 0.17 + sin(e) * 0.08, sin(a) * cos(e) * 0.13))
				var cs: Array[Color] = []
				for p: Vector3 in pts:
					cs.append(_grey(1.0) if spots.get_noise_3dv(p * 10.0) > 0.45 else _grey(0.62 + 0.38 * (p.y - 0.17) / 0.08))
				_quad(st, pts[0], pts[1], pts[2], pts[3], cs[0], cs[1], cs[2], cs[3])
		# gills underneath
		for i in segs:
			var a0:= TAU * i / segs
			var a1:= TAU * (i + 1) / segs
			_tri_out(st, Vector3(0, 0.15, 0), Vector3(cos(a1) * 0.13, 0.17, sin(a1) * 0.13), Vector3(cos(a0) * 0.13, 0.17, sin(a0) * 0.13),
				_grey(0.25), _grey(0.4), _grey(0.4))
	else:
		_tube(st, Vector3(0, 0, 0), Vector3(0, 0.17, 0), 0.035, 0.028, 7, _grey(0.9))
		_tube(st, Vector3(0, 0.11, 0), Vector3(0, 0.125, 0), 0.05, 0.03, 7, _grey(0.8))
	var m:= _finish(st)
	_cache[key] = m
	return m
