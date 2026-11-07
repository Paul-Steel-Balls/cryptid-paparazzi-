extends Node3D
class_name CityBlocks
## The City map, built on a flat Terrain ("city" style): a street grid with skyscrapers and
## mid-rises, a park, a parking lot, an elevated highway with a homeless encampment under it,
## a river along the north with a bridge over it, and a skyline all round so it feels enclosed.
## Street furniture: lamps, sidewalk trees, parked cars, hot dog / pretzel / taco stands,
## a newspaper kiosk, dumpsters (hiding spots), benches, hydrants.
##
## Cryptids can't walk through buildings, so the city also provides a little road graph:
## blocked(p) for picking spots, and route(a, b) for walking round blocks.

const ROAD_HALF:= 5.0        # asphalt half-width
const WALK:= 2.5             # sidewalk width each side
const STREET_HALF:= ROAD_HALF + WALK
const NS_ROADS:= [-77.0, 0.0, 77.0]   # x of the north-south streets
const EW_ROADS:= [86.0, 26.0, -60.0]  # z of the east-west streets
const EDGE:= 114.0
const OUTER:= 139.0         # the skyline wall runs from EDGE out to here
const RIVER_Z:= -85.0        # river centre line (runs east-west)
const RIVER_BED_HALF:= 7.0
const RIVER_BANK:= 4.0
const WATER:= -1.6
const BRIDGE_HALF:= 6.0      # half-width of the bridge deck (on the x = 0 street)
const BRIDGE_Z0:= -104.0
const BRIDGE_Z1:= -67.0
const OVERPASS_Z:= -36.0
const OVERPASS_HALF:= 8.0
const OVERPASS_Y:= 7.0
const CAMP_LOT:= Rect2(-20, 98, 40, 40)

## Building footprints and other no-go areas for cryptids (x, z rects).
var blockers: Array[Rect2] = []
## Named spots for Species "home"s.
var landmarks: Dictionary = {}
## Hiding spots (same format as Forest.bushes).
var hides: Array[Dictionary] = []
var nav_nodes: Array[Vector2] = []
var _nav_edges: Dictionary = {}   # node index -> Array of [other, cost]
var terrain: Terrain
var rng:= RandomNumberGenerator.new()
var _building_mat: ShaderMaterial
var _concrete: StandardMaterial3D
var _colliders: StaticBody3D
## Street furniture (cars, trees, stands, pillars): solid for you, but cryptids slip past it
## (collision layer 2) so a chase never snags on a parked car or a sidewalk tree.
var _props: StaticBody3D
const PROPS_LAYER:= 2
var _sidewalk_trees: Array[Transform3D] = []
var _lamp_spots: Array[Vector3] = []


func _init(p_terrain: Terrain = null) -> void:
	terrain = p_terrain
	rng.seed = 4242
	_plan()


# ------------------------------------------------------------------ static plan (used by Terrain)

## Ground height for the city: flat, with the river cut along the north.
static func ground_height(x: float, z: float) -> float:
	var dz:= absf(z - RIVER_Z)
	if dz < RIVER_BED_HALF:
		return -4.5
	if dz < RIVER_BED_HALF + RIVER_BANK:
		var t:= (dz - RIVER_BED_HALF) / RIVER_BANK
		t = t * t * (3.0 - 2.0 * t)
		return lerpf(-4.5, 0.0, t)
	return 0.0


static func on_bridge(x: float, z: float) -> bool:
	return absf(x) < BRIDGE_HALF and z > BRIDGE_Z0 and z < BRIDGE_Z1


static func _near_street(x: float, z: float, half: float) -> bool:
	for rx: float in NS_ROADS:
		if absf(x - rx) < half and z > -EDGE and z < EDGE + 25.0:
			return true
	for rz: float in EW_ROADS:
		if absf(z - rz) < half:
			return true
	return false


## Base ground tint under the street meshes (parks are grass, banks are mud).
static func ground_color(x: float, z: float) -> Color:
	var dz:= absf(z - RIVER_Z)
	if dz < RIVER_BED_HALF + RIVER_BANK:
		return Color(0.26, 0.24, 0.2).lerp(Color(0.2, 0.3, 0.18), clampf((dz - RIVER_BED_HALF) / RIVER_BANK, 0.0, 1.0))
	if x > 7.5 and x < 69.5 and z > 33.5 and z < 78.5:
		return Color(0.18, 0.36, 0.17)   # the park
	if z < -67.5 and z > RIVER_Z + RIVER_BED_HALF + RIVER_BANK - 0.5:
		return Color(0.2, 0.34, 0.18)    # riverside lawn
	if z < RIVER_Z - RIVER_BED_HALF - RIVER_BANK:
		return Color(0.21, 0.33, 0.19)   # north bank
	return Color(0.17, 0.17, 0.18)


# ------------------------------------------------------------------ plan: blocks, nav

func _plan() -> void:
	var sh:= STREET_HALF
	var xs:= [[-EDGE, NS_ROADS[0] - sh], [NS_ROADS[0] + sh, NS_ROADS[1] - sh], [NS_ROADS[1] + sh, NS_ROADS[2] - sh], [NS_ROADS[2] + sh, EDGE]]
	# Rows: [z0, z1, [block type per column]]
	var rows:= [
		[EW_ROADS[0] + sh, OUTER, ["mid", "mid_camp", "mid_camp", "mid"]],
		[EW_ROADS[1] + sh, EW_ROADS[0] - sh, ["mid", "towers", "park", "mid"]],
		[OVERPASS_Z + OVERPASS_HALF, EW_ROADS[1] - sh, ["mid", "lot", "towers", "towers"]],
	]
	_block_list = []
	for row in rows:
		for i in 4:
			var bx: Array = xs[i]
			var r:= Rect2(bx[0], row[0], bx[1] - bx[0], row[1] - row[0])
			var kind: String = row[2][i]
			if kind == "mid_camp":
				# Leave the camp parking lot open.
				if i == 1:
					r = Rect2(r.position.x, r.position.y, (CAMP_LOT.position.x - 2.0) - r.position.x, r.size.y)
				else:
					var x0:= CAMP_LOT.end.x + 2.0
					r = Rect2(x0, r.position.y, r.end.x - x0, r.size.y)
				kind = "mid"
			_block_list.append({"rect": r, "kind": kind})
	# The skyline wall: east, west and north (beyond the river) edges.
	for side: float in [-1.0, 1.0]:
		_block_list.append({"rect": Rect2(EDGE if side > 0 else -OUTER, -OUTER, OUTER - EDGE, OUTER * 2.0), "kind": "wall"})
	_block_list.append({"rect": Rect2(-EDGE, -OUTER, EDGE * 2.0, OUTER - EDGE), "kind": "wall"})
	# The two blocks between the riverside street and the overpass are thin plazas: open.
	for b in _block_list:
		var r: Rect2 = b["rect"]
		if b["kind"] in ["mid", "towers", "wall"]:
			blockers.append(r.grow(0.6))
	# River (except where the bridge crosses).
	var rz0:= RIVER_Z - RIVER_BED_HALF - 3.5
	var rz1:= RIVER_Z + RIVER_BED_HALF + 3.5
	blockers.append(Rect2(-150.0, rz0, 150.0 - BRIDGE_HALF + 0.5, rz1 - rz0))
	blockers.append(Rect2(BRIDGE_HALF - 0.5, rz0, 150.0, rz1 - rz0))
	landmarks["methman_camp"] = Vector2(41, OVERPASS_Z + 1.5)
	landmarks["tailgate"] = Vector2(-38, -5)
	landmarks["park"] = Vector2(38.5, 56)
	_build_nav()


var _block_list: Array = []


func _build_nav() -> void:
	nav_nodes.clear()
	for rx: float in NS_ROADS:
		for rz: float in EW_ROADS:
			nav_nodes.append(Vector2(rx, rz))
		nav_nodes.append(Vector2(rx, OVERPASS_Z))
		nav_nodes.append(Vector2(rx, 106.0))
	for rz: float in EW_ROADS + [OVERPASS_Z]:
		nav_nodes.append(Vector2(-106.0, rz))
		nav_nodes.append(Vector2(106.0, rz))
	nav_nodes.append_array([Vector2(0, -71), Vector2(0, -105), Vector2(-48, -105), Vector2(48, -105),
		Vector2(38.5, 56), Vector2(-38, -5), Vector2(41, OVERPASS_Z), Vector2(-38, OVERPASS_Z), Vector2(0, 120),
		Vector2(-48, -71), Vector2(48, -71)])
	_nav_edges.clear()
	for i in nav_nodes.size():
		_nav_edges[i] = []
	for i in nav_nodes.size():
		for j in range(i + 1, nav_nodes.size()):
			var a:= nav_nodes[i]
			var b:= nav_nodes[j]
			var d:= a.distance_to(b)
			if d < 90.0 and not segment_blocked(a, b):
				_nav_edges[i].append([j, d])
				_nav_edges[j].append([i, d])


## Inside a building / the river?
func blocked(p: Vector2) -> bool:
	for r in blockers:
		if r.has_point(p):
			return true
	return false


## Does the straight line a->b pass through any blocker?
func segment_blocked(a: Vector2, b: Vector2) -> bool:
	for r in blockers:
		if _seg_hits_rect(a, b, r):
			return true
	return false


static func _seg_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	# Liang-Barsky clip of the segment against the rect.
	var d:= b - a
	var t0:= 0.0
	var t1:= 1.0
	var p:= [-d.x, d.x, -d.y, d.y]
	var q:= [a.x - r.position.x, r.end.x - a.x, a.y - r.position.y, r.end.y - a.y]
	for k in 4:
		var pk: float = p[k]
		var qk: float = q[k]
		if absf(pk) < 1e-6:
			if qk < 0.0:
				return false
		else:
			var t:= qk / pk
			if pk < 0.0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
			if t0 > t1:
				return false
	return true


## Waypoints from a to b round the buildings: [..., b]. Just [b] when there's a clear line.
func route(a: Vector2, b: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if not segment_blocked(a, b):
		out.append(b)
		return out
	# Dijkstra over the street graph, entering from any node a can see, leaving to b.
	var n:= nav_nodes.size()
	var dist: Array[float] = []
	var prev: Array[int] = []
	var done: Array[bool] = []
	dist.resize(n)
	prev.resize(n)
	done.resize(n)
	for i in n:
		dist[i] = INF
		prev[i] = -1
		done[i] = false
		if not segment_blocked(a, nav_nodes[i]):
			dist[i] = a.distance_to(nav_nodes[i])
	var best_end:= -1
	var best_total:= INF
	for _k in n:
		var u:= -1
		var du:= INF
		for i in n:
			if not done[i] and dist[i] < du:
				du = dist[i]
				u = i
		if u < 0:
			break
		done[u] = true
		if du >= best_total:
			break
		if not segment_blocked(nav_nodes[u], b):
			var tot:= du + nav_nodes[u].distance_to(b)
			if tot < best_total:
				best_total = tot
				best_end = u
		for e in _nav_edges[u]:
			var v: int = e[0]
			var nd:= du + float(e[1])
			if nd < dist[v]:
				dist[v] = nd
				prev[v] = u
	if best_end < 0:
		out.append(b)
		return out
	var chain: Array[Vector2] = []
	var cur:= best_end
	while cur >= 0:
		chain.push_front(nav_nodes[cur])
		cur = prev[cur]
	chain.append(b)
	return chain


## A random open spot on a street, plaza or in the park (for spawns and wandering).
func random_open_spot(r: RandomNumberGenerator) -> Vector2:
	for _i in 60:
		var p:= Vector2(r.randf_range(-108, 108), r.randf_range(-110, 90))
		if not blocked(p) and absf(p.y - RIVER_Z) > RIVER_BED_HALF + 2.0:
			return p
	return Vector2(0, 26)


# ------------------------------------------------------------------ build

func _ready() -> void:
	_concrete = _mat(Color(0.42, 0.41, 0.4), 0.95)
	_colliders = StaticBody3D.new()
	_colliders.name = "CityColliders"
	add_child(_colliders)
	_props = StaticBody3D.new()
	_props.name = "CityProps"
	_props.collision_layer = PROPS_LAYER
	_props.collision_mask = 0
	add_child(_props)
	_building_mat = ShaderMaterial.new()
	_building_mat.shader = _window_shader()
	_build_streets()
	for b in _block_list:
		match str(b["kind"]):
			"mid":
				_build_buildings(b["rect"], 9.0, 26.0, 3)
			"towers":
				_build_buildings(b["rect"], 32.0, 78.0, 2)
			"wall":
				_build_buildings(b["rect"], 26.0, 70.0, 4)
			"park":
				_build_park(b["rect"])
			"lot":
				_build_parking_lot(b["rect"])
	_build_river()
	_build_overpass()
	_build_sidewalk_trees()
	_build_lamps()
	_build_cars()
	_build_stands()
	_build_camp_lot()


func _mat(c: Color, rough: float = 0.8, emissive: float = 0.0) -> StandardMaterial3D:
	var m:= StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, collide: bool = false, parent: Node3D = null) -> MeshInstance3D:
	var mi:= MeshInstance3D.new()
	var bm:= BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	(parent if parent != null else self).add_child(mi)
	if collide:
		var cs:= CollisionShape3D.new()
		var bs:= BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.transform = Transform3D(Basis.IDENTITY, pos) if parent == null else parent.transform * Transform3D(Basis.IDENTITY, pos)
		_colliders.add_child(cs)
	return mi


func _cyl(r: float, h: float, pos: Vector3, mat: Material, parent: Node3D = null, r_top: float = -1.0) -> MeshInstance3D:
	var mi:= MeshInstance3D.new()
	var cm:= CylinderMesh.new()
	cm.top_radius = r if r_top < 0.0 else r_top
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 14
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	(parent if parent != null else self).add_child(mi)
	return mi


func _sign(text: String, pos: Vector3, size: int, col: Color, parent: Node3D, yaw: float = 0.0) -> Label3D:
	var l:= Label3D.new()
	l.text = text
	l.font = load("res://fonts/Oswald.ttf")
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = col
	l.outline_size = 8
	l.outline_modulate = Color(0.05, 0.03, 0.05)
	l.position = pos
	l.rotation.y = yaw
	l.shaded = false
	parent.add_child(l)
	return l


## Window grid by world position: dark glass, some lit warm, some cool TV-blue; storefronts glow.
func _window_shader() -> Shader:
	var sh:= Shader.new()
	sh.code = """
shader_type spatial;
instance uniform vec3 tint = vec3(0.3, 0.3, 0.33);
instance uniform float base_y = 0.0;
instance uniform float seed = 0.0;
varying vec3 wpos;
varying vec3 wnrm;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.17) * 43758.5453); }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	if (abs(wnrm.y) > 0.5) {
		ALBEDO = tint * 0.6;
		ROUGHNESS = 0.95;
	} else {
		float along = abs(wnrm.x) > 0.5 ? wpos.z : wpos.x;
		float up = wpos.y - base_y;
		vec2 cell = vec2(along / 2.6, (up - 4.2) / 3.3);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		float win = step(0.16, f.x) * step(f.x, 0.84) * step(0.22, f.y) * step(f.y, 0.82);
		float h = hash(id + vec2(floor(wnrm.x * 2.0 + 3.0), floor(wnrm.z * 2.0 + 3.0)) * 17.0);
		float lit = step(0.64, h);
		vec3 warm = mix(vec3(1.0, 0.78, 0.42), vec3(0.65, 0.8, 1.0), step(0.93, h));
		// Ground floor: shopfronts, mostly lit.
		float shop = 1.0 - step(4.0, up);
		float shop_win = shop * step(0.8, up) * step(up, 3.4) * step(0.1, fract(along / 6.0)) * step(fract(along / 6.0), 0.9);
		float any_win = mix(win * step(4.0, up), shop_win, shop);
		vec3 wall = tint * (0.85 + 0.15 * hash(vec2(floor(up / 3.3), 0.0)));
		ALBEDO = mix(wall, vec3(0.03, 0.04, 0.06), any_win);
		ROUGHNESS = mix(0.9, 0.12, any_win);
		METALLIC = any_win * 0.4;
		float on = mix(lit, step(0.25, hash(vec2(floor(along / 6.0), 7.0))), shop);
		EMISSION = warm * any_win * on * (0.9 + 1.2 * hash(id + 3.7)) * 1.4;
	}
}
"""
	return sh


func _building(r: Rect2, h: float) -> void:
	var mi:= _box(Vector3(r.size.x, h, r.size.y), Vector3(r.get_center().x, h * 0.5, r.get_center().y), _building_mat, true)
	var tints:= [Color(0.34, 0.33, 0.36), Color(0.42, 0.36, 0.3), Color(0.28, 0.3, 0.36), Color(0.45, 0.42, 0.38), Color(0.3, 0.24, 0.22)]
	var t: Color = tints[rng.randi() % tints.size()]
	mi.set_instance_shader_parameter("tint", Vector3(t.r, t.g, t.b))
	mi.set_instance_shader_parameter("base_y", 0.0)
	mi.set_instance_shader_parameter("seed", rng.randf() * 100.0)
	# Roof clutter: a water tower or AC units, a red aircraft light on the tall ones.
	var top:= Vector3(r.get_center().x, h, r.get_center().y)
	if h > 40.0:
		var red:= _mat(Color(1, 0.1, 0.05), 0.5, 4.0)
		_box(Vector3(0.5, 3.0, 0.5), top + Vector3(0, 1.5, 0), _concrete)
		_box(Vector3(0.5, 0.5, 0.5), top + Vector3(0, 3.2, 0), red)
	elif rng.randf() < 0.45:
		var wood:= _mat(Color(0.36, 0.25, 0.16))
		var tw:= _cyl(1.4, 2.2, top + Vector3(rng.randf_range(-2, 2), 2.9, rng.randf_range(-2, 2)), wood)
		_cyl(1.5, 0.6, tw.position + Vector3(0, 1.4, 0), wood, null, 0.1)
		for k in 4:
			var a:= TAU * k / 4.0
			_box(Vector3(0.12, 1.8, 0.12), tw.position + Vector3(cos(a) * 1.1, -2.0, sin(a) * 1.1), _concrete)
	else:
		for k in rng.randi_range(1, 3):
			_box(Vector3(1.6, 1.0, 1.2), top + Vector3(rng.randf_range(-r.size.x * 0.3, r.size.x * 0.3), 0.5, rng.randf_range(-r.size.y * 0.3, r.size.y * 0.3)), _concrete)
	# Cornice.
	_box(Vector3(r.size.x + 0.4, 0.5, r.size.y + 0.4), top + Vector3(0, -0.2, 0), _mat(t.darkened(0.3)))


## Fill a block with buildings shoulder to shoulder (no alleys: nothing to get stuck in).
func _build_buildings(block: Rect2, hmin: float, hmax: float, max_split: int) -> void:
	var r:= block.grow(-0.8)
	var along_x:= r.size.x >= r.size.y
	var n:= clampi(int((r.size.x if along_x else r.size.y) / 16.0), 1, max_split)
	var cuts: Array[float] = [0.0]
	for i in range(1, n):
		cuts.append(float(i) / n + rng.randf_range(-0.08, 0.08))
	cuts.append(1.0)
	for i in n:
		var a:= cuts[i]
		var b:= cuts[i + 1]
		var sub: Rect2
		if along_x:
			sub = Rect2(r.position.x + r.size.x * a, r.position.y, r.size.x * (b - a), r.size.y)
		else:
			sub = Rect2(r.position.x, r.position.y + r.size.y * a, r.size.x, r.size.y * (b - a))
		# Deep blocks: a front and back building at different heights.
		var deep:= (sub.size.y if along_x else sub.size.x) > 26.0
		if deep:
			if along_x:
				var mid:= sub.position.y + sub.size.y * rng.randf_range(0.4, 0.6)
				_building(Rect2(sub.position.x, sub.position.y, sub.size.x, mid - sub.position.y), rng.randf_range(hmin, hmax))
				_building(Rect2(sub.position.x, mid, sub.size.x, sub.end.y - mid), rng.randf_range(hmin, hmax))
			else:
				var midx:= sub.position.x + sub.size.x * rng.randf_range(0.4, 0.6)
				_building(Rect2(sub.position.x, sub.position.y, midx - sub.position.x, sub.size.y), rng.randf_range(hmin, hmax))
				_building(Rect2(midx, sub.position.y, sub.end.x - midx, sub.size.y), rng.randf_range(hmin, hmax))
		else:
			_building(sub, rng.randf_range(hmin, hmax))


func _flat(size: Vector2, pos: Vector3, mat: Material) -> void:
	var mi:= MeshInstance3D.new()
	var pm:= PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_streets() -> void:
	var asphalt:= _mat(Color(0.12, 0.12, 0.13), 0.75)
	var walk:= _mat(Color(0.44, 0.43, 0.41), 0.9)
	var curb:= _mat(Color(0.55, 0.54, 0.5), 0.9)
	var paint:= _mat(Color(0.95, 0.8, 0.2), 0.7, 0.25)
	var white:= _mat(Color(0.9, 0.9, 0.88), 0.7, 0.2)
	var span_z:= [-EDGE, OUTER]
	for rx: float in NS_ROADS:
		var len_z: float = span_z[1] - span_z[0]
		var cz: float = (span_z[0] + span_z[1]) * 0.5
		if rx != 0.0:
			# Side streets stop at the riverside road; only the middle one crosses the bridge.
			var south:= EW_ROADS[2] - STREET_HALF
			len_z = OUTER - south
			cz = (OUTER + south) * 0.5
		_flat(Vector2(ROAD_HALF * 2.0, len_z), Vector3(rx, 0.03, cz), asphalt)
		for s: float in [-1.0, 1.0]:
			_flat(Vector2(WALK, len_z), Vector3(rx + s * (ROAD_HALF + WALK * 0.5), 0.045, cz), walk)
			_box(Vector3(0.18, 0.12, len_z), Vector3(rx + s * ROAD_HALF, 0.06, cz), curb)
		# Dashed centre line.
		var z:= cz - len_z * 0.5 + 2.0
		while z < cz + len_z * 0.5:
			if not _near_ew(z, STREET_HALF):
				_flat(Vector2(0.18, 2.4), Vector3(rx, 0.05, z), paint)
			z += 5.0
	for rz: float in EW_ROADS:
		_flat(Vector2(EDGE * 2.0, ROAD_HALF * 2.0), Vector3(0, 0.035, rz), asphalt)
		for s: float in [-1.0, 1.0]:
			_flat(Vector2(EDGE * 2.0, WALK), Vector3(0, 0.05, rz + s * (ROAD_HALF + WALK * 0.5)), walk)
			_box(Vector3(EDGE * 2.0, 0.12, 0.18), Vector3(0, 0.06, rz + s * ROAD_HALF), curb)
		var x:= -EDGE + 2.0
		while x < EDGE - 2.0:
			if not _near_ns(x, STREET_HALF):
				_flat(Vector2(2.4, 0.18), Vector3(x, 0.055, rz), paint)
			x += 5.0
		# Crosswalk stripes at each intersection.
		for rx: float in NS_ROADS:
			for s: float in [-1.0, 1.0]:
				for k in 6:
					_flat(Vector2(0.6, 3.0), Vector3(rx - 3.2 + k * 1.3, 0.06, rz + s * (ROAD_HALF + 1.6)), white)
	# Under the overpass and the plazas: plain concrete.
	_flat(Vector2(EDGE * 2.0, OVERPASS_HALF * 2.0 + 2.0), Vector3(0, 0.02, OVERPASS_Z), _mat(Color(0.3, 0.3, 0.31), 0.95))


func _near_ew(z: float, half: float) -> bool:
	for rz: float in EW_ROADS:
		if absf(z - rz) < half:
			return true
	return false


func _near_ns(x: float, half: float) -> bool:
	for rx: float in NS_ROADS:
		if absf(x - rx) < half:
			return true
	return false


func _build_river() -> void:
	var stone:= _mat(Color(0.4, 0.38, 0.36), 0.9)
	var rail:= _mat(Color(0.18, 0.2, 0.24), 0.5)
	rail.metallic = 0.6
	# The bridge deck (flush with the street so you just walk on), railings, arches.
	var deck_len:= BRIDGE_Z1 - BRIDGE_Z0
	var deck_c:= (BRIDGE_Z0 + BRIDGE_Z1) * 0.5
	_box(Vector3(BRIDGE_HALF * 2.0, 0.6, deck_len), Vector3(0, -0.25, deck_c), stone, true)
	_flat(Vector2(ROAD_HALF * 2.0, deck_len), Vector3(0, 0.06, deck_c), _mat(Color(0.12, 0.12, 0.13), 0.75))
	for s: float in [-1.0, 1.0]:
		_box(Vector3(0.3, 1.1, deck_len), Vector3(s * (BRIDGE_HALF - 0.15), 0.55, deck_c), stone, true)
		_box(Vector3(0.12, 0.12, deck_len), Vector3(s * (BRIDGE_HALF - 0.15), 1.2, deck_c), rail)
		var z:= BRIDGE_Z0 + 3.0
		while z < BRIDGE_Z1:
			_box(Vector3(0.5, 2.2, 0.5), Vector3(s * (BRIDGE_HALF - 0.15), 1.1, z), stone)
			z += 7.75
	# Piers in the water.
	for z: float in [RIVER_Z - 4.0, RIVER_Z + 4.0]:
		_box(Vector3(BRIDGE_HALF * 1.6, 4.6, 1.6), Vector3(0, -2.6, z), stone, true)
	# Embankment walls along both banks, with a railing on the south (city) side.
	for s: float in [-1.0, 1.0]:
		var z:= RIVER_Z + s * (RIVER_BED_HALF + RIVER_BANK + 0.3)
		for side: float in [-1.0, 1.0]:
			var x0:= BRIDGE_HALF + 0.2
			var x1:= EDGE
			var cx:= side * (x0 + x1) * 0.5
			_box(Vector3(x1 - x0, 1.0, 0.25), Vector3(cx, 0.5, z), stone, true)
			_box(Vector3(x1 - x0, 0.1, 0.1), Vector3(cx, 1.05, z), rail)
	# Benches on the riverside lawn.
	for x: float in [-60.0, -31.0, 29.0, 58.0]:
		_bench(Vector3(x, 0, -72.6), PI)


func _build_overpass() -> void:
	var conc:= _mat(Color(0.5, 0.49, 0.47), 0.95)
	var dark:= _mat(Color(0.25, 0.25, 0.26), 0.95)
	# Deck, barriers, and the dark underside.
	_box(Vector3(OUTER * 2.0, 1.2, OVERPASS_HALF * 2.0), Vector3(0, OVERPASS_Y + 0.6, OVERPASS_Z), conc, true)
	_box(Vector3(OUTER * 2.0, 0.6, OVERPASS_HALF * 2.0 - 1.0), Vector3(0, OVERPASS_Y - 0.25, OVERPASS_Z), dark)
	for s: float in [-1.0, 1.0]:
		_box(Vector3(OUTER * 2.0, 1.0, 0.4), Vector3(0, OVERPASS_Y + 1.7, OVERPASS_Z + s * (OVERPASS_HALF - 0.2)), conc)
	var x:= -OUTER + 4.0
	while x < OUTER - 4.0:
		if not _near_ns(x, STREET_HALF + 1.0):
			for s: float in [-1.0, 1.0]:
				var p:= Vector3(x, OVERPASS_Y * 0.5, OVERPASS_Z + s * 3.2)
				_box(Vector3(1.2, OVERPASS_Y, 1.2), p, conc)
				var cs:= CollisionShape3D.new()
				var cyl:= CylinderShape3D.new()
				cyl.radius = 0.8
				cyl.height = OVERPASS_Y
				cs.shape = cyl
				cs.position = p
				_props.add_child(cs)
		x += 16.0
	# Sodium lights hung under the deck.
	for lx: float in [-58.0, -19.0, 24.0, 41.0, 58.0, -96.0, 96.0]:
		var l:= OmniLight3D.new()
		l.light_color = Color(1.0, 0.62, 0.25)
		l.light_energy = 2.2
		l.omni_range = 14.0
		l.position = Vector3(lx, OVERPASS_Y - 0.8, OVERPASS_Z)
		add_child(l)
		_box(Vector3(0.8, 0.2, 0.4), l.position + Vector3(0, 0.25, 0), _mat(Color(1.0, 0.7, 0.35), 0.5, 3.0))
	_build_encampment()


## Under the highway: tents, tarps, shopping carts, a burn barrel. Methman's tent is the main one.
func _build_encampment() -> void:
	var c:= Vector3(landmarks["methman_camp"].x, 0, landmarks["methman_camp"].y)
	var tarp_cols:= [Color(0.15, 0.3, 0.6), Color(0.55, 0.45, 0.2), Color(0.2, 0.45, 0.25), Color(0.6, 0.2, 0.15)]
	var spots:= [Vector3(-9, 0, -2), Vector3(-6, 0, 3), Vector3(7, 0, -3), Vector3(11, 0, 2), Vector3(15, 0, -1), Vector3(-13, 0, 1)]
	for i in spots.size():
		var p: Vector3 = c + spots[i]
		var tent:= MeshInstance3D.new()
		var pm:= PrismMesh.new()
		pm.size = Vector3(2.2, 1.3, 2.6)
		tent.mesh = pm
		tent.material_override = _mat(tarp_cols[i % tarp_cols.size()], 0.9)
		tent.position = p + Vector3(0, 0.65, 0)
		tent.rotation.y = rng.randf_range(-0.6, 0.6) + PI * 0.5
		add_child(tent)
	# Cardboard, a mattress, carts.
	var card:= _mat(Color(0.55, 0.42, 0.26), 1.0)
	for k in 5:
		var b:= _box(Vector3(rng.randf_range(0.6, 1.2), rng.randf_range(0.3, 0.8), rng.randf_range(0.5, 1.0)),
			c + Vector3(rng.randf_range(-14, 16), 0.3, rng.randf_range(-4, 4)), card)
		b.rotation.y = rng.randf() * TAU
	_box(Vector3(1.0, 0.25, 2.0), c + Vector3(3, 0.13, 4), _mat(Color(0.7, 0.65, 0.55), 1.0))
	var wire:= _mat(Color(0.6, 0.62, 0.65), 0.35)
	wire.metallic = 0.8
	for p in [c + Vector3(-3, 0, -4), c + Vector3(13, 0, 4)]:
		var cart:= Node3D.new()
		cart.position = p
		cart.rotation.y = rng.randf() * TAU
		add_child(cart)
		_box(Vector3(0.6, 0.5, 0.9), Vector3(0, 0.75, 0), wire, false, cart)
		_box(Vector3(0.5, 0.04, 0.8), Vector3(0, 0.35, 0), wire, false, cart)
		for wx: float in [-0.25, 0.25]:
			for wz: float in [-0.38, 0.38]:
				_cyl(0.06, 0.04, Vector3(wx, 0.06, wz), _mat(Color(0.1, 0.1, 0.1)), cart).rotation.z = PI * 0.5
		_box(Vector3(0.5, 0.4, 0.7), Vector3(0, 1.2, 0), card, false, cart)
	# Burn barrel with a flickery fire glow.
	var barrel_p:= c + Vector3(4, 0, -1)
	_cyl(0.35, 0.9, barrel_p + Vector3(0, 0.45, 0), _mat(Color(0.3, 0.18, 0.1), 0.6))
	_cyl(0.28, 0.2, barrel_p + Vector3(0, 0.95, 0), _mat(Color(1.0, 0.5, 0.1), 0.5, 5.0))
	var fire:= OmniLight3D.new()
	fire.light_color = Color(1.0, 0.55, 0.2)
	fire.light_energy = 3.0
	fire.omni_range = 10.0
	fire.position = barrel_p + Vector3(0, 1.5, 0)
	fire.set_script(load("res://scripts/flicker_light.gd"))
	add_child(fire)
	# Tents count as hiding spots.
	for i in spots.size():
		hides.append({"pos": Vector2(c.x + spots[i].x, c.z + spots[i].z), "radius": 1.3})


func _build_park(r: Rect2) -> void:
	var path:= _mat(Color(0.5, 0.45, 0.36), 1.0)
	var cx:= r.get_center()
	_flat(Vector2(r.size.x - 4.0, 2.4), Vector3(cx.x, 0.03, cx.y), path)
	_flat(Vector2(2.4, r.size.y - 4.0), Vector3(cx.x, 0.03, cx.y), path)
	# Fountain in the middle.
	var stone:= _mat(Color(0.55, 0.53, 0.5), 0.85)
	_cyl(3.0, 0.6, Vector3(cx.x, 0.3, cx.y), stone)
	var pool:= _cyl(2.7, 0.1, Vector3(cx.x, 0.58, cx.y), _mat(Color(0.12, 0.25, 0.35), 0.05))
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cyl(0.3, 1.6, Vector3(cx.x, 1.2, cx.y), stone)
	_cyl(0.9, 0.2, Vector3(cx.x, 2.0, cx.y), stone)
	var cs:= CollisionShape3D.new()
	var cyl:= CylinderShape3D.new()
	cyl.radius = 3.0
	cyl.height = 1.2
	cs.shape = cyl
	cs.position = Vector3(cx.x, 0.3, cx.y)
	_colliders.add_child(cs)
	blockers.append(Rect2(cx.x - 3.4, cx.y - 3.4, 6.8, 6.8))
	# Trees and bushes (the bushes are where you hide).
	var tree_xf: Array[Transform3D] = []
	var bush_xf: Array[Transform3D] = []
	for _i in 22:
		var p:= Vector2(rng.randf_range(r.position.x + 3, r.end.x - 3), rng.randf_range(r.position.y + 3, r.end.y - 3))
		if absf(p.x - cx.x) < 3.0 or absf(p.y - cx.y) < 3.0 or p.distance_to(cx) < 6.0:
			continue
		var s:= rng.randf_range(0.75, 1.0)
		tree_xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, 0, p.y)))
	for _i in 14:
		var p:= Vector2(rng.randf_range(r.position.x + 2, r.end.x - 2), rng.randf_range(r.position.y + 2, r.end.y - 2))
		if absf(p.x - cx.x) < 2.5 or absf(p.y - cx.y) < 2.5 or p.distance_to(cx) < 5.0:
			continue
		var s:= rng.randf_range(0.9, 1.3)
		bush_xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, 0, p.y)))
		hides.append({"pos": p, "radius": 1.0 * s})
	_add_trees(tree_xf)
	var bush_mesh:= PlantMeshes.bush(1)
	var mm:= MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bush_mesh
	mm.instance_count = bush_xf.size()
	for i in bush_xf.size():
		mm.set_instance_transform(i, bush_xf[i])
		mm.set_instance_color(i, Color(0.2, 0.42, 0.18).lerp(Color(0.3, 0.5, 0.2), rng.randf()))
	var mmi:= MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var vc:= StandardMaterial3D.new()
	vc.vertex_color_use_as_albedo = true
	vc.roughness = 0.9
	mmi.material_override = vc
	add_child(mmi)
	for k in 4:
		var a:= TAU * k / 4.0 + PI * 0.25
		_bench(Vector3(cx.x + cos(a) * 6.5, 0, cx.y + sin(a) * 6.5), -a + PI * 0.5)
	for corner: Vector2 in [Vector2(r.position.x + 1.5, r.position.y + 1.5), Vector2(r.end.x - 1.5, r.position.y + 1.5),
			Vector2(r.position.x + 1.5, r.end.y - 1.5), Vector2(r.end.x - 1.5, r.end.y - 1.5)]:
		_lamp_spots.append(Vector3(corner.x, 0, corner.y))


func _add_trees(xfs: Array[Transform3D]) -> void:
	if xfs.is_empty():
		return
	var vc:= StandardMaterial3D.new()
	vc.vertex_color_use_as_albedo = true
	vc.roughness = 0.9
	for part in 2:
		var mm:= MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = PlantMeshes.trunk(1, 4.6, 0.22, 0.08) if part == 0 else PlantMeshes.broadleaf_canopy(1)
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
			var c:= Color(0.4, 0.3, 0.22) if part == 0 else Color(0.22, 0.4, 0.2).lerp(Color(0.32, 0.46, 0.18), rng.randf())
			mm.set_instance_color(i, c)
		var mmi:= MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = vc
		add_child(mmi)
	for xf in xfs:
		var cs:= CollisionShape3D.new()
		var cyl:= CylinderShape3D.new()
		cyl.radius = 0.25
		cyl.height = 3.0
		cs.shape = cyl
		cs.position = xf.origin + Vector3(0, 1.5, 0)
		_props.add_child(cs)


func _bench(p: Vector3, yaw: float) -> void:
	var n:= Node3D.new()
	n.position = p
	n.rotation.y = yaw
	add_child(n)
	var wood:= _mat(Color(0.45, 0.3, 0.16))
	var iron:= _mat(Color(0.12, 0.12, 0.13), 0.5)
	_box(Vector3(1.8, 0.08, 0.45), Vector3(0, 0.45, 0), wood, false, n)
	_box(Vector3(1.8, 0.4, 0.06), Vector3(0, 0.75, -0.22), wood, false, n)
	for x: float in [-0.8, 0.8]:
		_box(Vector3(0.06, 0.45, 0.45), Vector3(x, 0.22, 0), iron, false, n)


func _build_parking_lot(r: Rect2) -> void:
	_flat(Vector2(r.size.x - 1.0, r.size.y - 1.0), Vector3(r.get_center().x, 0.025, r.get_center().y), _mat(Color(0.15, 0.15, 0.16), 0.8))
	var white:= _mat(Color(0.85, 0.85, 0.8), 0.7, 0.15)
	var x:= r.position.x + 3.0
	while x < r.end.x - 2.0:
		_flat(Vector2(0.15, 5.0), Vector3(x, 0.04, r.position.y + 4.0), white)
		_flat(Vector2(0.15, 5.0), Vector3(x, 0.04, r.end.y - 4.0), white)
		x += 3.0
	# Parked cars in a few bays (the tailgate party is in the middle).
	for k in 6:
		var bx:= r.position.x + 4.5 + float(rng.randi_range(0, int((r.size.x - 9.0) / 3.0))) * 3.0
		var bz:= r.position.y + 4.0 if k % 2 == 0 else r.end.y - 4.0
		_car(Vector3(bx, 0, bz), PI * 0.5 + (PI if k % 2 == 0 else 0.0))
	for corner: Vector2 in [Vector2(r.position.x + 1.0, r.position.y + 1.0), Vector2(r.end.x - 1.0, r.end.y - 1.0), Vector2(r.position.x + 1.0, r.end.y - 1.0)]:
		_lamp_spots.append(Vector3(corner.x, 0, corner.y))


func _car(p: Vector3, yaw: float) -> void:
	var cols:= [Color(0.6, 0.08, 0.08), Color(0.1, 0.2, 0.5), Color(0.75, 0.75, 0.72), Color(0.08, 0.08, 0.09), Color(0.2, 0.4, 0.25), Color(0.8, 0.65, 0.2)]
	var n:= Node3D.new()
	n.position = p
	n.rotation.y = yaw
	add_child(n)
	var paint:= _mat(cols[rng.randi() % cols.size()], 0.3)
	paint.metallic = 0.5
	var glass:= _mat(Color(0.08, 0.1, 0.13), 0.1)
	_box(Vector3(1.8, 0.7, 4.2), Vector3(0, 0.6, 0), paint, false, n)
	_box(Vector3(1.6, 0.6, 2.1), Vector3(0, 1.22, -0.2), glass, false, n)
	_box(Vector3(1.5, 0.08, 2.0), Vector3(0, 1.55, -0.2), paint, false, n)
	var tyre:= _mat(Color(0.06, 0.06, 0.06), 0.9)
	for wx: float in [-0.85, 0.85]:
		for wz: float in [-1.35, 1.35]:
			_cyl(0.33, 0.25, Vector3(wx, 0.33, wz), tyre, n).rotation.z = PI * 0.5
	_box(Vector3(1.5, 0.12, 0.05), Vector3(0, 0.75, 2.11), _mat(Color(1.0, 0.95, 0.8), 0.4, 1.5), false, n)
	_box(Vector3(1.5, 0.1, 0.05), Vector3(0, 0.75, -2.11), _mat(Color(0.9, 0.08, 0.05), 0.4, 1.5), false, n)
	var cs:= CollisionShape3D.new()
	var bs:= BoxShape3D.new()
	bs.size = Vector3(1.8, 1.4, 4.2)
	cs.shape = bs
	cs.transform = n.transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.7, 0))
	_props.add_child(cs)


## Cars parked along the curbs (both sides of the streets, with gaps).
func _build_cars() -> void:
	for rx: float in NS_ROADS:
		for side: float in [-1.0, 1.0]:
			var z:= -48.0
			while z < 80.0:
				if not _near_ew(z, STREET_HALF + 3.0) and absf(z - OVERPASS_Z) > OVERPASS_HALF + 2.0 and rng.randf() < 0.35:
					_car(Vector3(rx + side * (ROAD_HALF - 1.2), 0, z), 0.0 if side > 0 else PI)
				z += 6.0
	for rz: float in EW_ROADS:
		for side: float in [-1.0, 1.0]:
			var x:= -108.0
			while x < 108.0:
				if not _near_ns(x, STREET_HALF + 3.0) and rng.randf() < 0.3 and not (rz == EW_ROADS[0] and absf(x) < 22.0):
					_car(Vector3(x, 0, rz + side * (ROAD_HALF - 1.2)), PI * 0.5 if side > 0 else -PI * 0.5)
				x += 6.0


func _build_sidewalk_trees() -> void:
	var xfs: Array[Transform3D] = []
	for rx: float in NS_ROADS:
		for side: float in [-1.0, 1.0]:
			var z:= -48.0
			while z < 80.0:
				if not _near_ew(z, STREET_HALF + 2.0) and absf(z - OVERPASS_Z) > OVERPASS_HALF + 2.0:
					var p:= Vector3(rx + side * (ROAD_HALF + 1.4), 0, z)
					xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.62, 0.75)), p))
					_box(Vector3(1.3, 0.18, 1.3), p + Vector3(0, 0.09, 0), _mat(Color(0.25, 0.18, 0.12), 1.0))
				z += 14.0
	for rz: float in EW_ROADS:
		for side: float in [-1.0, 1.0]:
			var x:= -106.0
			while x < 108.0:
				if not _near_ns(x, STREET_HALF + 2.0) and not (rz == EW_ROADS[0] and absf(x) < 22.0 and side > 0):
					var p:= Vector3(x, 0, rz + side * (ROAD_HALF + 1.4))
					xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.62, 0.75)), p))
					_box(Vector3(1.3, 0.18, 1.3), p + Vector3(0, 0.09, 0), _mat(Color(0.25, 0.18, 0.12), 1.0))
				x += 16.0
	_add_trees(xfs)


func _build_lamps() -> void:
	for rx: float in NS_ROADS:
		for side: float in [-1.0, 1.0]:
			var z:= -48.0
			while z < 84.0:
				if not _near_ew(z, STREET_HALF) and absf(z - OVERPASS_Z) > OVERPASS_HALF:
					_lamp_spots.append(Vector3(rx + side * (ROAD_HALF + 0.4), 0, z))
				z += 28.0
	for rz: float in EW_ROADS:
		for side: float in [-1.0, 1.0]:
			var x:= -96.0
			while x < 108.0:
				if not _near_ns(x, STREET_HALF):
					_lamp_spots.append(Vector3(x, 0, rz + side * (ROAD_HALF + 0.4)))
				x += 32.0
	var pole_m:= _mat(Color(0.14, 0.15, 0.17), 0.5)
	pole_m.metallic = 0.6
	var bulb:= _mat(Color(1.0, 0.72, 0.4), 0.4, 5.0)
	for p in _lamp_spots:
		_cyl(0.08, 6.0, p + Vector3(0, 3.0, 0), pole_m)
		_box(Vector3(0.7, 0.18, 0.35), p + Vector3(0, 6.0, 0), pole_m)
		_box(Vector3(0.5, 0.06, 0.25), p + Vector3(0, 5.89, 0), bulb)
		var l:= OmniLight3D.new()
		l.light_color = Color(1.0, 0.68, 0.36)
		l.light_energy = 1.8
		l.omni_range = 13.0
		l.omni_attenuation = 1.3
		l.position = p + Vector3(0, 5.6, 0)
		add_child(l)
	# Fire hydrants on the corners.
	var red:= _mat(Color(0.75, 0.1, 0.08), 0.5)
	for rx: float in NS_ROADS:
		for rz: float in EW_ROADS:
			var hp:= Vector3(rx + ROAD_HALF + 0.6, 0, rz + ROAD_HALF + 0.9)
			_cyl(0.16, 0.6, hp + Vector3(0, 0.3, 0), red)
			_cyl(0.12, 0.12, hp + Vector3(0, 0.66, 0), red)


## Food stands, a taco truck and a newspaper kiosk ("THE DAILY CRYPTID"), dumpsters.
func _build_stands() -> void:
	_hotdog_cart(Vector3(11.0, 0, 35.5), 0.0)
	_kiosk(Vector3(-11.5, 0, 35.0), "PRETZELS", Color(0.85, 0.45, 0.1), PI)
	_newsstand(Vector3(10.0, 0, 16.0), 0.0)
	_food_truck(Vector3(-6.0, 0, -62.5), PI * 0.5)
	_hotdog_cart(Vector3(-12.0, 0, -48.5), PI)
	_kiosk(Vector3(NS_ROADS[2] - 11.0, 0, 16.5), "COFFEE", Color(0.35, 0.22, 0.15), 0.0)
	var green:= _mat(Color(0.12, 0.3, 0.18), 0.6)
	for p: Vector3 in [Vector3(-48, 0, OVERPASS_Z + 5.5), Vector3(26, 0, OVERPASS_Z - 5.5), Vector3(-84, 0, 19.5),
			Vector3(70, 0, 79.5), Vector3(-18, 0, 79.5), Vector3(90, 0, -48.5)]:
		if blocked(Vector2(p.x, p.z)):
			continue
		_box(Vector3(2.0, 1.3, 1.2), p + Vector3(0, 0.65, 0), green)
		_box(Vector3(2.05, 0.1, 1.25), p + Vector3(0, 1.32, 0), _mat(Color(0.08, 0.2, 0.12), 0.6))
		var cs:= CollisionShape3D.new()
		var bs:= BoxShape3D.new()
		bs.size = Vector3(2.0, 1.3, 1.2)
		cs.shape = bs
		cs.position = p + Vector3(0, 0.65, 0)
		_props.add_child(cs)
		hides.append({"pos": Vector2(p.x, p.z + (1.3 if p.z < 0 else -1.3)), "radius": 1.1})


func _hotdog_cart(p: Vector3, yaw: float) -> void:
	var n:= Node3D.new()
	n.position = p
	n.rotation.y = yaw
	add_child(n)
	var steel:= _mat(Color(0.75, 0.76, 0.78), 0.3)
	steel.metallic = 0.8
	_box(Vector3(1.8, 0.9, 0.9), Vector3(0, 0.75, 0), steel, false, n)
	for x: float in [-0.6, 0.6]:
		_cyl(0.28, 0.08, Vector3(x, 0.28, 0.48), _mat(Color(0.1, 0.1, 0.1)), n).rotation.x = PI * 0.5
	_cyl(0.03, 1.6, Vector3(0, 2.0, 0), steel, n)
	var red:= _mat(Color(0.9, 0.15, 0.1), 0.7)
	var yel:= _mat(Color(1.0, 0.85, 0.15), 0.7)
	_cyl(1.3, 0.5, Vector3(0, 2.85, 0), red, n, 0.05)
	_cyl(1.32, 0.06, Vector3(0, 2.6, 0), yel, n)
	_sign("HOT DOGS", Vector3(0, 1.05, 0.46), 70, Color(1.0, 0.9, 0.3), n)
	_box(Vector3(0.5, 0.05, 0.3), Vector3(0.4, 1.22, 0), _mat(Color(0.75, 0.35, 0.2), 0.6), false, n)
	var l:= OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.6)
	l.light_energy = 1.2
	l.omni_range = 5.0
	l.position = Vector3(0, 2.3, 0)
	n.add_child(l)
	_collide_box(n, Vector3(1.8, 1.4, 0.9), Vector3(0, 0.7, 0))


func _kiosk(p: Vector3, label: String, col: Color, yaw: float) -> void:
	var n:= Node3D.new()
	n.position = p
	n.rotation.y = yaw
	add_child(n)
	_box(Vector3(2.4, 2.2, 1.8), Vector3(0, 1.1, 0), _mat(col.darkened(0.2), 0.7), false, n)
	_box(Vector3(2.8, 0.12, 2.4), Vector3(0, 2.6, 0.3), _mat(Color(0.9, 0.88, 0.8), 0.7), false, n)
	_box(Vector3(2.0, 0.9, 0.05), Vector3(0, 1.4, 0.91), _mat(Color(1.0, 0.85, 0.55), 0.5, 1.6), false, n)
	_sign(label, Vector3(0, 2.32, 0.95), 80, Color(1, 1, 1), n)
	_collide_box(n, Vector3(2.4, 2.2, 1.8), Vector3(0, 1.1, 0))


func _newsstand(p: Vector3, yaw: float) -> void:
	var n:= Node3D.new()
	n.position = p
	n.rotation.y = yaw
	add_child(n)
	var green:= _mat(Color(0.15, 0.35, 0.22), 0.6)
	_box(Vector3(3.0, 2.4, 1.6), Vector3(0, 1.2, 0), green, false, n)
	_box(Vector3(3.4, 0.15, 2.2), Vector3(0, 2.5, 0.25), green.duplicate(), false, n)
	_sign("NEWS", Vector3(0, 2.75, 0.8), 90, Color(1.0, 0.95, 0.8), n)
	# Racks of magazines and today's front page.
	var mag_cols:= [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.9), Color(1.0, 0.85, 0.2), Color(0.9, 0.5, 0.8), Color(0.3, 0.8, 0.4), Color(0.95, 0.95, 0.9)]
	for row in 3:
		for k in 7:
			var m:= _box(Vector3(0.32, 0.42, 0.02), Vector3(-1.2 + k * 0.4, 0.65 + row * 0.48, 0.82), _mat(mag_cols[(row * 7 + k) % mag_cols.size()], 0.6), false, n)
			m.rotation.x = -0.25
	var front:= _box(Vector3(0.9, 1.1, 0.03), Vector3(1.7, 1.0, 0.5), _mat(Color(0.95, 0.93, 0.85), 0.8), false, n)
	front.rotation.y = -0.6
	_sign("THE DAILY\nCRYPTID", Vector3(1.72, 1.32, 0.53), 34, Color(0.1, 0.05, 0.05), n, -0.6).outline_size = 0
	_sign("BIGFOOT\nAT CITY\nHALL?!", Vector3(1.72, 0.85, 0.53), 26, Color(0.8, 0.05, 0.05), n, -0.6).outline_size = 0
	var l:= OmniLight3D.new()
	l.light_color = Color(1.0, 0.9, 0.7)
	l.light_energy = 1.0
	l.omni_range = 5.0
	l.position = Vector3(0, 2.2, 1.2)
	n.add_child(l)
	_collide_box(n, Vector3(3.0, 2.4, 1.6), Vector3(0, 1.2, 0))


func _food_truck(p: Vector3, yaw: float) -> void:
	var n:= Node3D.new()
	n.position = p
	n.rotation.y = yaw
	add_child(n)
	var body:= _mat(Color(0.95, 0.75, 0.15), 0.4)
	_box(Vector3(2.3, 2.6, 5.6), Vector3(0, 1.7, 0), body, false, n)
	_box(Vector3(2.2, 1.4, 1.4), Vector3(0, 1.1, 3.4), body, false, n)
	_box(Vector3(2.0, 0.6, 0.05), Vector3(0, 1.6, 4.11), _mat(Color(0.08, 0.1, 0.13), 0.1), false, n)
	_box(Vector3(0.05, 1.0, 2.8), Vector3(1.16, 2.0, -0.2), _mat(Color(1.0, 0.85, 0.55), 0.5, 1.8), false, n)
	_box(Vector3(0.7, 0.06, 3.0), Vector3(1.5, 2.65, -0.2), _mat(Color(0.8, 0.15, 0.1), 0.7), false, n)
	_sign("TACOS", Vector3(1.17, 3.1, -0.2), 110, Color(0.9, 0.15, 0.1), n, PI * 0.5)
	var tyre:= _mat(Color(0.06, 0.06, 0.06), 0.9)
	for wx: float in [-1.1, 1.1]:
		for wz: float in [-1.8, 3.0]:
			_cyl(0.42, 0.3, Vector3(wx, 0.42, wz), tyre, n).rotation.z = PI * 0.5
	var l:= OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.6)
	l.light_energy = 1.6
	l.omni_range = 7.0
	l.position = Vector3(2.0, 2.4, -0.2)
	n.add_child(l)
	_collide_box(n, Vector3(2.3, 3.0, 7.0), Vector3(0, 1.5, 0.7))


func _collide_box(n: Node3D, size: Vector3, local: Vector3) -> void:
	var cs:= CollisionShape3D.new()
	var bs:= BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = n.transform * Transform3D(Basis.IDENTITY, local)
	_props.add_child(cs)


func _build_camp_lot() -> void:
	# The RV's spot: a fenced gravel lot at the end of the middle street.
	_flat(Vector2(CAMP_LOT.size.x, CAMP_LOT.size.y), Vector3(CAMP_LOT.get_center().x, 0.02, CAMP_LOT.get_center().y), _mat(Color(0.3, 0.29, 0.27), 1.0))
	var fence:= _mat(Color(0.55, 0.57, 0.6), 0.4)
	fence.metallic = 0.7
	fence.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fence.albedo_color.a = 0.55
	_box(Vector3(CAMP_LOT.size.x, 2.2, 0.05), Vector3(CAMP_LOT.get_center().x, 1.1, 134.0), fence)
	for x in range(int(CAMP_LOT.position.x), int(CAMP_LOT.end.x) + 1, 4):
		_cyl(0.05, 2.3, Vector3(float(x), 1.15, 134.0), _mat(Color(0.5, 0.5, 0.52), 0.5))


# ------------------------------------------------------------------ pedestrians

## Ordinary people walking the sidewalks. They ignore cryptids (city folk have seen it all).
func spawn_pedestrians(parent: Node, player: Node3D) -> Array:
	var out: Array = []
	var r:= RandomNumberGenerator.new()
	r.seed = int(Time.get_ticks_usec())
	for i in 18:
		var ped:= Pedestrian.new()
		ped.city = self
		ped.model_path = "res://models/ped_suit.glb" if i % 2 == 0 else "res://models/ped_hoodie.glb"
		ped.player = player
		parent.add_child(ped)
		ped.start(r)
		out.append(ped)
	return out


## Sidewalk points along streets for pedestrians: [a, b] pairs.
func sidewalk_lines() -> Array:
	var lines: Array = []
	for rx: float in NS_ROADS:
		for side: float in [-1.0, 1.0]:
			var x: float = rx + side * (ROAD_HALF + 1.0)
			lines.append([Vector2(x, -54.0), Vector2(x, 94.0)])
	for rz: float in EW_ROADS:
		for side: float in [-1.0, 1.0]:
			var z: float = rz + side * (ROAD_HALF + 1.0)
			lines.append([Vector2(-106.0, z), Vector2(106.0, z)])
	return lines
