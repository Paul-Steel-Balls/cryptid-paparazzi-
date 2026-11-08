extends Node3D
class_name Forest
## Builds the world on top of a Terrain: tree stands and meadows, boulders,
## bushes (hiding spots), flowers, camp with fence lights and campfire.
## Repeated props are MultiMeshes so a phone can draw hundreds of them.

var rng:= RandomNumberGenerator.new()
var terrain: Terrain
var bushes: Array[Dictionary] = []
var tree_spots: Array[Vector2] = []
var rock_spots: Array[Vector2] = []

var _density:= FastNoiseLite.new()
var _colliders: StaticBody3D
var map_id:= "woods"
## Named spots other systems need (e.g. "methman_camp" -> Vector2).
var landmarks: Dictionary = {}
var style: Dictionary = {}


func _init(p_seed: int = 0, p_map: String = "woods") -> void:
	if p_seed != 0:
		rng.seed = p_seed
	else:
		rng.randomize()
	map_id = p_map
	style = Species.style(p_map)
	# Bigger maps (Terrain.SCALE): keep the same density of plants and rocks.
	for k in ["trees", "bushes", "ferns", "mushrooms", "flowers", "rocks"]:
		if style.has(k):
			style[k] = int(round(float(style[k]) * Terrain.SCALE * Terrain.SCALE))
	terrain = Terrain.new(rng.randi(), p_map)
	terrain.name = "Terrain"


func _dry(p: Vector2, margin: float = 0.6) -> bool:
	return terrain.water_level < -100.0 or terrain.height_at(p.x, p.y) > terrain.water_level + margin


func _near_landmark(p: Vector2, r: float) -> bool:
	for k in landmarks:
		if p.distance_to(landmarks[k]) < r:
			return true
	return false


## Cryptids with a "home" (Methman's camp, the Jersey Devil's tailgate) get one on any map
## they live on: away from camp, away from each other, on level ground.
func _pick_landmarks() -> void:
	if terrain.is_city:
		return   # the City (CityBlocks) has its own spots
	var homes: Array = []
	var m: Dictionary = Species.MAPS.get(map_id, {})
	for t in Species.TIERS:
		for id in m.get(t, []):
			var h: String = str(Species.info(id).get("home", ""))
			if h != "" and h not in homes:
				homes.append(h)
	for h in homes:
		for _i in 400:
			var p:= Vector2(rng.randf_range(-Terrain.SPAN * 0.94, Terrain.SPAN * 0.94), rng.randf_range(-Terrain.SPAN * 0.94, Terrain.SPAN * 0.6))
			if p.distance_to(Terrain.CAMP) < 55.0 or terrain.normal_at(p.x, p.y).y < 0.93 or not _dry(p, 1.5):
				continue
			if _near_landmark(p, 60.0):
				continue
			landmarks[h] = p
			break


func _ready() -> void:
	add_child(terrain)
	_density.seed = terrain.seed_value + 5
	_density.frequency = 0.02
	_colliders = StaticBody3D.new()
	_colliders.name = "PropColliders"
	add_child(_colliders)
	_pick_landmarks()
	_build_trees()
	_build_rocks()
	_build_bushes()
	_build_flowers()
	if int(style["ferns"]) > 0:
		_build_ferns(int(style["ferns"]))
	if int(style["mushrooms"]) > 0:
		_build_mushrooms(int(style["mushrooms"]))
	_build_camp_fence()
	_build_campfire()
	if terrain.water_level > -100.0 and not terrain.is_city:
		_build_shore()


func ground(x: float, z: float) -> Vector3:
	return Vector3(x, terrain.height_at(x, z), z)


func _rand_spot(margin: float = 8.0) -> Vector2:
	var lim:= Terrain.RIM_START + 10.0 - margin
	return Vector2(rng.randf_range(-lim, lim), rng.randf_range(-lim, lim))


func _near_camp(p: Vector2, r: float) -> bool:
	return p.distance_to(Terrain.CAMP) < r


func _new_multimesh(mesh: Mesh, count: int, colored: bool) -> MultiMesh:
	var mm:= MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colored
	mm.mesh = mesh
	mm.instance_count = count
	return mm


func _add_mm(mm: MultiMesh, mat: Material, node_name: String) -> MultiMeshInstance3D:
	var mmi:= MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	return mmi


func _vc_mat() -> StandardMaterial3D:
	var m:= StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	return m


# ------------------------------------------------------------------ v0.17: detail up close
## The world is cut into CHUNK-metre squares. Each square draws its plants twice: detailed
## meshes out to `near` metres, the old low-poly ones beyond (or nothing, for small stuff).
## Distances are measured to the middle of each square, so detail always reaches a good
## way past you.
const CHUNK:= 64.0
const TREE_NEAR:= 85.0
const ROCK_NEAR:= 90.0
const BUSH_NEAR:= 70.0
const SMALL_NEAR:= 48.0     # flowers, ferns, mushrooms
const GRASS_NEAR:= 40.0

static var _foliage_shader: Shader


## Leaves, needles, grass: vertex colour x instance colour, both sides lit, a gentle sway that
## grows with height (and a flutter for small stuff).
static func foliage_mat(sway: float, sway_height: float, flutter: float = 0.0) -> ShaderMaterial:
	if _foliage_shader == null:
		_foliage_shader = Shader.new()
		_foliage_shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform float sway = 0.05;
uniform float sway_height = 6.0;
uniform float flutter = 0.0;
uniform float emission = 0.0;
void vertex() {
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = clamp(VERTEX.y / sway_height, 0.0, 1.0);
	float t = TIME * 1.1 + o.x * 0.21 + o.z * 0.17;
	vec2 off = vec2(sin(t), cos(t * 0.8 + 1.3)) * sway * h * h;
	off += vec2(sin(TIME * 5.0 + VERTEX.x * 9.0 + o.z), cos(TIME * 4.3 + VERTEX.z * 9.0 + o.x)) * flutter * h;
	VERTEX.xz += off;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	EMISSION = COLOR.rgb * emission;
}
"""
	var m:= ShaderMaterial.new()
	m.shader = _foliage_shader
	m.set_shader_parameter("sway", sway)
	m.set_shader_parameter("sway_height", sway_height)
	m.set_shader_parameter("flutter", flutter)
	return m


## items: [[Transform3D (world), Color], ...]. hi out to `near`, lo beyond (lo may be null).
func _add_lod(group: String, hi: Mesh, lo: Mesh, hi_mat: Material, lo_mat: Material, items: Array, near: float,
		shadows: bool = true) -> void:
	if items.is_empty():
		return
	var holder:= get_node_or_null(group) as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = group
		add_child(holder)
	var cells:= {}
	for it in items:
		var o: Vector3 = (it[0] as Transform3D).origin
		var key:= Vector2i(floori(o.x / CHUNK), floori(o.z / CHUNK))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(it)
	for key: Vector2i in cells:
		var list: Array = cells[key]
		var ysum:= 0.0
		for it in list:
			ysum += (it[0] as Transform3D).origin.y
		var centre:= Vector3((key.x + 0.5) * CHUNK, ysum / list.size(), (key.y + 0.5) * CHUNK)
		for lod in 2:
			var mesh: Mesh = hi if lod == 0 else lo
			if mesh == null:
				continue
			var mm:= _new_multimesh(mesh, list.size(), true)
			for i in list.size():
				var xf: Transform3D = list[i][0]
				mm.set_instance_transform(i, Transform3D(xf.basis, xf.origin - centre))
				mm.set_instance_color(i, list[i][1])
			var mmi:= MultiMeshInstance3D.new()
			mmi.name = "%s_%d_%d_%s" % [group, key.x, key.y, "hi" if lod == 0 else "lo"]
			mmi.multimesh = mm
			mmi.material_override = hi_mat if lod == 0 else lo_mat
			mmi.position = centre
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			if lod == 0:
				mmi.visibility_range_end = near
				mmi.visibility_range_end_margin = 8.0
			else:
				mmi.visibility_range_begin = near
				mmi.visibility_range_begin_margin = 8.0
			if not shadows:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(mmi)


func _build_trees() -> void:
	# Forest stands where density noise is high; meadows elsewhere.
	var attempts:= 0
	var want:= int(style["trees"])
	var gap2:= float(style["tree_gap"]) * float(style["tree_gap"])
	while tree_spots.size() < want and attempts < want * 15:
		attempts += 1
		var p:= _rand_spot()
		if _near_camp(p, 24.0):
			continue
		var dn:= _density.get_noise_2d(p.x, p.y)
		if dn < -0.05 and rng.randf() > 0.08:
			continue
		if terrain.normal_at(p.x, p.y).y < 0.8 or not _dry(p, 0.8) or _near_landmark(p, 8.0):
			continue
		var crowded:= false
		for q in tree_spots:
			if q.distance_squared_to(p) < gap2:
				crowded = true
				break
		if not crowded:
			tree_spots.append(p)
	# Each tree: a variant mesh (3 pines, 3 broadleafs), its own size, spin and colours.
	var greens: Array = style["greens"]
	var trunk_c: Color = style["trunk"]
	var autumn_chance:= float(style["autumn"])
	var pine_share:= float(style["pine_share"])
	var birch:= trunk_c.v > 0.7    # pale trunks (Lakeside): birches, with their black markings
	var autumns:= [Color(0.9, 0.5, 0.1), Color(0.85, 0.3, 0.1), Color(0.95, 0.75, 0.2)]
	var groups:= {}   # "pine0" -> [[transform, canopy colour, trunk colour], ...]
	for p in tree_spots:
		var pine:= rng.randf() < pine_share
		var key:= ("pine%d" if pine else "leaf%d") % rng.randi_range(0, 2)
		var sc:= rng.randf_range(0.8, 1.45)
		var base:= ground(p.x, p.y)
		var rot:= Basis(Vector3.UP, rng.randf() * TAU)
		var lean:= Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.05))
		var xf:= Transform3D(lean * rot.scaled(Vector3(sc, sc * rng.randf_range(0.92, 1.1), sc)), base)
		var autumn:= rng.randf() < autumn_chance
		var pal: Array = autumns if autumn else greens
		var cc: Color = pal[rng.randi_range(0, pal.size() - 1)]
		cc = cc.lightened(rng.randf_range(-0.08, 0.08))
		if not groups.has(key):
			groups[key] = []
		# Broadleafs get the map's trunk colour (pale birch at Lakeside); pines stay brown.
		var tc: Color = trunk_c if not pine else Color(0.45, 0.3, 0.15)
		groups[key].append([xf, cc, tc.darkened(rng.randf() * 0.2)])
		var cs:= CollisionShape3D.new()
		var cyl:= CylinderShape3D.new()
		cyl.radius = maxf(0.6, 0.8 * sc * 0.75)
		cyl.height = 4.0 * sc
		cs.shape = cyl
		cs.position = base + Vector3(0, 2.0 * sc, 0)
		_colliders.add_child(cs)
	var bark_mat:= _vc_mat()
	var needle_mat:= foliage_mat(0.07, 7.0)
	var leaf_mat:= foliage_mat(0.09, 7.0, 0.015)
	var lo_leaf:= _vc_mat()
	lo_leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	for key in groups:
		var list: Array = groups[key]
		var variant:= int(str(key).right(1))
		var is_pine:= str(key).begins_with("pine")
		var canopy_hi: Mesh = PlantMeshes.pine_hi(variant) if is_pine else PlantMeshes.broadleaf_hi(variant)
		var canopy_lo: Mesh = PlantMeshes.pine_canopy(variant) if is_pine else PlantMeshes.broadleaf_canopy(variant)
		var trunk_hi: Mesh = PlantMeshes.trunk_hi(variant, 5.6, 0.32, 0.1, false, 0, 5) if is_pine \
			else PlantMeshes.trunk_hi(variant + 3, 4.6, 0.26, 0.12, birch, 3, 0)
		var trunk_lo: Mesh = PlantMeshes.trunk(variant) if is_pine else PlantMeshes.trunk(variant + 3, 5.2, 0.24, 0.08)
		var trunks: Array = []
		var crowns: Array = []
		for it in list:
			trunks.append([it[0], it[2]])
			crowns.append([it[0], it[1]])
		_add_lod("TreeTrunks_" + str(key), trunk_hi, trunk_lo, bark_mat, bark_mat, trunks, TREE_NEAR)
		_add_lod("TreeCanopy_" + str(key), canopy_hi, canopy_lo, needle_mat if is_pine else leaf_mat, lo_leaf, crowns, TREE_NEAR)


func _build_rocks() -> void:
	# Boulders: real cover that breaks line of sight.
	var spots: Array[Dictionary] = []
	for _c in int(style["rocks"]):
		var center:= _rand_spot(12.0)
		if _near_camp(center, 22.0) or not _dry(center, 0.3) or _near_landmark(center, 8.0):
			continue
		for _k in rng.randi_range(1, 4):
			var p:= center + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
			spots.append({"p": p, "r": rng.randf_range(0.6, 1.9)})
	var rock_tint: Color = style["rock_tint"]
	var by_variant:= [[], [], []]
	for i in spots.size():
		by_variant[rng.randi_range(0, 2)].append(i)
	for v in 3:
		var idx: Array = by_variant[v]
		var hi_items: Array = []
		var lo_items: Array = []
		for k in idx.size():
			var i: int = idx[k]
			var p: Vector2 = spots[i]["p"]
			var r: float = spots[i]["r"]
			var g:= ground(p.x, p.y)
			# Keep the visual within the collider so cameras can't end up inside a rock.
			var b:= Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r * rng.randf_range(0.9, 1.0), r * 0.68, r * 0.95))
			var xf:= Transform3D(b, g + Vector3(0, r * 0.3, 0))
			var grey:= rng.randf_range(0.48, 0.66)
			lo_items.append([xf, Color(grey, grey, grey + 0.04).lerp(rock_tint, 0.35)])
			# Up close the colours are in the mesh (stone, moss, lichen): just vary brightness and tint a little.
			var bright:= rng.randf_range(0.85, 1.12)
			hi_items.append([xf, Color(bright, bright, bright).lerp(rock_tint * 1.6, 0.18)])
		# Same transforms, two colourings: hi and lo go in as separate groups with the same split.
		_add_lod("Boulders%d" % v, PlantMeshes.rock_hi(v), null, _vc_mat(), null, hi_items, ROCK_NEAR)
		_add_lod_far("Boulders%d" % v, PlantMeshes.rock(v), _vc_mat(), lo_items, ROCK_NEAR)
	for i in spots.size():
		var p: Vector2 = spots[i]["p"]
		var r: float = spots[i]["r"]
		var g:= ground(p.x, p.y)
		rock_spots.append(p)
		var cs:= CollisionShape3D.new()
		var sh:= SphereShape3D.new()
		sh.radius = r * 1.05
		cs.shape = sh
		cs.position = g + Vector3(0, r * 0.35, 0)
		_colliders.add_child(cs)


## The far half of _add_lod on its own (when near and far need different instance colours).
func _add_lod_far(group: String, lo: Mesh, lo_mat: Material, items: Array, near: float) -> void:
	if items.is_empty():
		return
	var holder:= get_node_or_null(group) as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = group
		add_child(holder)
	var cells:= {}
	for it in items:
		var o: Vector3 = (it[0] as Transform3D).origin
		var key:= Vector2i(floori(o.x / CHUNK), floori(o.z / CHUNK))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(it)
	for key: Vector2i in cells:
		var list: Array = cells[key]
		var ysum:= 0.0
		for it in list:
			ysum += (it[0] as Transform3D).origin.y
		var centre:= Vector3((key.x + 0.5) * CHUNK, ysum / list.size(), (key.y + 0.5) * CHUNK)
		var mm:= _new_multimesh(lo, list.size(), true)
		for i in list.size():
			var xf: Transform3D = list[i][0]
			mm.set_instance_transform(i, Transform3D(xf.basis, xf.origin - centre))
			mm.set_instance_color(i, list[i][1])
		var mmi:= MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d_lo" % [group, key.x, key.y]
		mmi.multimesh = mm
		mmi.material_override = lo_mat
		mmi.position = centre
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.visibility_range_begin = near
		mmi.visibility_range_begin_margin = 8.0
		holder.add_child(mmi)


func _build_bushes() -> void:
	var bush_colors:= [Color(0.2, 0.65, 0.2), Color(0.5, 0.2, 0.7), Color(0.15, 0.55, 0.35), Color(0.3, 0.6, 0.15)]
	var spots: Array[Vector2] = []
	var attempts:= 0
	var want_b:= int(style["bushes"])
	while spots.size() < want_b and attempts < want_b * 20:
		attempts += 1
		var p:= _rand_spot()
		if _near_camp(p, 12.0) or not _dry(p, 0.4) or _near_landmark(p, 5.0):
			continue
		# Bushes like forest edges and valley floors.
		var dn:= _density.get_noise_2d(p.x, p.y)
		if absf(dn + 0.05) > 0.25 and rng.randf() > 0.35:
			continue
		spots.append(p)
	var groups:= [[], [], []]
	for i in spots.size():
		var p:= spots[i]
		var r:= rng.randf_range(0.75, 1.2)
		var g:= ground(p.x, p.y) - Vector3(0, 0.08, 0)
		var b:= Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r, r * rng.randf_range(0.75, 0.95), r))
		groups[rng.randi_range(0, 2)].append([Transform3D(b, g), bush_colors[rng.randi_range(0, bush_colors.size() - 1)]])
		bushes.append({"pos": p, "radius": r})
	var lo_mat:= _vc_mat()
	var hi_mat:= foliage_mat(0.025, 1.6, 0.012)
	for v in 3:
		_add_lod("Bushes%d" % v, PlantMeshes.bush_hi(v), PlantMeshes.bush(v), hi_mat, lo_mat, groups[v], BUSH_NEAR)


## Deep Woods undergrowth: fern clumps with arching, leafy fronds, mostly under the trees.
func _build_ferns(n: int) -> void:
	var cols:= [Color(0.12, 0.42, 0.16), Color(0.18, 0.5, 0.2), Color(0.1, 0.35, 0.18)]
	var groups:= [[], []]
	for i in n:
		var p:= _rand_spot()
		# Near trees if possible.
		if not tree_spots.is_empty() and rng.randf() < 0.75:
			var t: Vector2 = tree_spots[rng.randi_range(0, tree_spots.size() - 1)]
			p = t + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5))
		if _near_camp(p, 14.0) or not _dry(p, 0.3):
			continue
		var s:= rng.randf_range(0.8, 1.5)
		var b:= Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.15), s))
		groups[rng.randi_range(0, 1)].append([Transform3D(b, ground(p.x, p.y)), cols[rng.randi_range(0, cols.size() - 1)].lightened(rng.randf_range(-0.05, 0.1))])
	var mat:= foliage_mat(0.04, 0.8, 0.02)
	for v in 2:
		_add_lod("Ferns", PlantMeshes.fern_clump(v), null, mat, null, groups[v], SMALL_NEAR, false)


## Little glowing blue toadstools (spotted caps) around tree roots.
func _build_mushrooms(n: int) -> void:
	var caps: Array = []
	var stems: Array = []
	for i in n:
		if tree_spots.is_empty():
			break
		var t: Vector2 = tree_spots[rng.randi_range(0, tree_spots.size() - 1)]
		var a:= rng.randf() * TAU
		var p:= t + Vector2(cos(a), sin(a)) * rng.randf_range(0.8, 1.6)
		var g:= ground(p.x, p.y)
		# Mushrooms grow in little rings of 2-4.
		for k in rng.randi_range(2, 4):
			var q:= g + Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
			var s:= rng.randf_range(0.7, 1.6)
			var xf:= Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), q)
			stems.append([xf, Color(0.85, 0.85, 0.8)])
			caps.append([xf, Color(0.3, 0.75, 1.0).lerp(Color(0.6, 0.4, 1.0), rng.randf())])
	_add_lod("MushroomStems", PlantMeshes.toadstool("stem"), null, _vc_mat(), null, stems, SMALL_NEAR, false)
	var glow:= _vc_mat()
	glow.emission_enabled = true
	glow.emission = Color(0.25, 0.6, 1.0)
	glow.emission_energy_multiplier = 1.6
	_add_lod("MushroomCaps", PlantMeshes.toadstool("cap"), null, glow, null, caps, SMALL_NEAR + 20.0, false)


func _build_flowers() -> void:
	var n:= int(style["flowers"])
	var kinds:= PlantMeshes.FLOWER_COLS.size()
	var groups: Array = []
	for k in kinds:
		groups.append([])
	for i in n:
		var p:= _rand_spot()
		for _t in 10:
			if _dry(p, 0.2):
				break
			p = _rand_spot()
		var s:= rng.randf_range(1.15, 1.7)
		var xf:= Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), ground(p.x, p.y))
		var b:= rng.randf_range(0.9, 1.1)
		groups[rng.randi_range(0, kinds - 1)].append([xf, Color(b, b, b)])
	var mat:= foliage_mat(0.0, 0.5, 0.025)
	mat.set_shader_parameter("emission", 0.12)   # a little glow so they read at night
	for k in kinds:
		_add_lod("Flowers", PlantMeshes.flower_clump(k), null, mat, null, groups[k], SMALL_NEAR, false)
	_build_grass()


## Grass tufts over the meadows and under the trees (not in water, not on the camp clearing).
func _build_grass() -> void:
	if terrain.is_city:
		return
	var n:= 28000
	var base: Color = style["grass"]
	var groups:= [[], []]
	for i in n:
		var p:= _rand_spot()
		if not _dry(p, 0.25) or terrain.normal_at(p.x, p.y).y < 0.85:
			continue
		var s:= rng.randf_range(0.8, 1.5)
		var xf:= Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), ground(p.x, p.y) - Vector3(0, 0.02, 0))
		var c:= base.lightened(rng.randf_range(-0.05, 0.12)).lerp(Color(0.45, 0.5, 0.2), rng.randf() * 0.3)
		groups[rng.randi_range(0, 1)].append([xf, c])
	var mat:= foliage_mat(0.04, 0.5, 0.015)
	for v in 2:
		_add_lod("Grass", PlantMeshes.grass_tuft(v), null, mat, null, groups[v], GRASS_NEAR, false)


## Lakeside extras: cattails along the waterline, lily pads, and a dock.
func _build_shore() -> void:
	var wl:= terrain.water_level
	var reeds: Array[Vector3] = []
	var pads: Array[Vector3] = []
	var tries:= 0
	while (reeds.size() < 260 or pads.size() < 90) and tries < 20000:
		tries += 1
		var p:= _rand_spot(4.0)
		var h:= terrain.height_at(p.x, p.y)
		if h > wl - 0.45 and h < wl + 0.25 and reeds.size() < 260:
			reeds.append(Vector3(p.x, h, p.y))
		elif h < wl - 0.8 and h > wl - 3.5 and pads.size() < 90 and rng.randf() < 0.3:
			pads.append(Vector3(p.x, wl + 0.02, p.y))
	var stalk:= CylinderMesh.new()
	stalk.top_radius = 0.012
	stalk.bottom_radius = 0.02
	stalk.height = 1.0
	stalk.radial_segments = 4
	var head:= CylinderMesh.new()
	head.top_radius = 0.035
	head.bottom_radius = 0.035
	head.height = 0.22
	head.radial_segments = 6
	var mm_s:= _new_multimesh(stalk, reeds.size() * 3, true)
	var mm_h:= _new_multimesh(head, reeds.size(), true)
	for i in reeds.size():
		var base:= reeds[i]
		for k in 3:
			var off:= Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
			var hgt:= rng.randf_range(1.1, 1.7)
			var tilt:= Basis(Vector3(rng.randf() - 0.5, 0, rng.randf() - 0.5).normalized(), rng.randf_range(0.0, 0.18))
			mm_s.set_instance_transform(i * 3 + k, Transform3D(tilt.scaled(Vector3(1, hgt, 1)), base + off + tilt * Vector3(0, hgt * 0.5, 0)))
			mm_s.set_instance_color(i * 3 + k, Color(0.3, 0.5, 0.2).lerp(Color(0.5, 0.55, 0.25), rng.randf()))
			if k == 0:
				mm_h.set_instance_transform(i, Transform3D(tilt, base + off + tilt * Vector3(0, hgt * 0.92, 0)))
				mm_h.set_instance_color(i, Color(0.4, 0.24, 0.12))
	_add_mm(mm_s, _vc_mat(), "Reeds")
	_add_mm(mm_h, _vc_mat(), "Cattails")
	var pad:= CylinderMesh.new()
	pad.top_radius = 0.4
	pad.bottom_radius = 0.4
	pad.height = 0.02
	pad.radial_segments = 10
	var mm_p:= _new_multimesh(pad, pads.size(), true)
	for i in pads.size():
		var sc:= rng.randf_range(0.6, 1.3)
		mm_p.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(sc, 1, sc)), pads[i]))
		mm_p.set_instance_color(i, Color(0.18, 0.5, 0.2).lerp(Color(0.3, 0.6, 0.25), rng.randf()))
	_add_mm(mm_p, _vc_mat(), "LilyPads")
	# Dock: walk from camp toward the lake until we hit water, then build out.
	var dir:= (Terrain.LAKE_C - Terrain.CAMP).normalized()
	var start:= Terrain.CAMP
	for i in 200:
		var q:= Terrain.CAMP + dir * float(i)
		if terrain.height_at(q.x, q.y) < wl + 0.4:
			start = q - dir * 3.0
			break
	landmarks["dock"] = start
	var wood:= StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.36, 0.22)
	var plank:= BoxMesh.new()
	plank.size = Vector3(2.2, 0.08, 0.32)
	var yaw:= atan2(dir.x, dir.y)
	for i in 34:
		var c:= start + dir * (float(i) * 0.36)
		var pm:= MeshInstance3D.new()
		pm.mesh = plank
		pm.material_override = wood
		pm.position = Vector3(c.x, wl + 0.55, c.y)
		pm.rotation.y = yaw
		add_child(pm)
	for i in 4:
		for sx in [-1.0, 1.0]:
			var c: Vector2 = start + dir * (2.0 + i * 3.6) + Vector2(dir.y, -dir.x) * sx * 1.0
			var post:= MeshInstance3D.new()
			var cm:= CylinderMesh.new()
			cm.top_radius = 0.09
			cm.bottom_radius = 0.09
			cm.height = 3.0
			post.mesh = cm
			post.material_override = wood
			post.position = Vector3(c.x, wl - 0.8, c.y)
			add_child(post)
	# Walkable: a thin box collider along the dock.
	var cs:= CollisionShape3D.new()
	var box:= BoxShape3D.new()
	box.size = Vector3(2.2, 0.1, 34 * 0.36)
	cs.shape = box
	var mid:= start + dir * (34 * 0.36 * 0.5)
	cs.position = Vector3(mid.x, wl + 0.55, mid.y)
	cs.rotation.y = yaw
	_colliders.add_child(cs)


## v0.17: the ring of lamp posts round camp is gone; camp itself is the safe zone now
## (Terrain.SAFE_R). Kept as a no-op so older code paths still call something harmless.
func _build_camp_fence() -> void:
	pass


func _build_campfire() -> void:
	var base:= ground(Terrain.CAMP.x + 4.5, Terrain.CAMP.y - 4.0)
	for i in 6:
		var ang:= float(i) / 6.0 * TAU
		var stone:= MeshInstance3D.new()
		var sm:= SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		stone.mesh = sm
		var mat:= StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.5, 0.55)
		stone.material_override = mat
		stone.position = base + Vector3(cos(ang) * 0.7, 0.15, sin(ang) * 0.7)
		add_child(stone)
	var log_mat:= StandardMaterial3D.new()
	log_mat.albedo_color = Color(0.4, 0.25, 0.1)
	for a in [0.0, PI / 2.0]:
		var log_mesh:= MeshInstance3D.new()
		var cm:= CylinderMesh.new()
		cm.top_radius = 0.12
		cm.bottom_radius = 0.12
		cm.height = 0.9
		log_mesh.mesh = cm
		log_mesh.material_override = log_mat
		log_mesh.rotation.z = PI / 2.0
		log_mesh.rotation.y = a
		log_mesh.position = base + Vector3(0, 0.25, 0)
		add_child(log_mesh)
	var flame:= MeshInstance3D.new()
	flame.name = "CampfireFlame"
	var fm:= CylinderMesh.new()
	fm.top_radius = 0.0
	fm.bottom_radius = 0.4
	fm.height = 0.9
	flame.mesh = fm
	var fmat:= StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.6, 0.1)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.5, 0.0)
	flame.material_override = fmat
	flame.position = base + Vector3(0, 0.6, 0)
	add_child(flame)
	var light:= OmniLight3D.new()
	light.name = "CampfireLight"
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 2.0
	light.omni_range = 13.0
	light.omni_attenuation = 1.4
	light.position = base + Vector3(0, 1.2, 0)
	add_child(light)


func _process(_delta: float) -> void:
	var f:= get_node_or_null("CampfireFlame") as MeshInstance3D
	if f:
		var t:= Time.get_ticks_msec() / 1000.0
		f.scale = Vector3(1.0, 1.0 + 0.15 * sin(t * 11.0) + 0.08 * sin(t * 23.0), 1.0)
	var l:= get_node_or_null("CampfireLight") as OmniLight3D
	if l:
		var tt:= Time.get_ticks_msec() / 1000.0
		l.light_energy = 2.0 + 0.25 * sin(tt * 14.0) + 0.15 * sin(tt * 31.0 + 1.0)
