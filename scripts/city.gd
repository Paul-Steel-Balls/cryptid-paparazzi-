extends Node3D
class_name CityBlocks
## The City map, built on a flat Terrain ("city" style). v0.16 grew it 50% and gave it more
## character: a 5x5 street grid of colourful low-rises, NYC-style brick walk-ups with fire
## escapes and green awnings, pitched-roof rowhouses, glass towers, a police station,
## a hospital, a garage, City Hall with its dome, a park with a fountain, a playground,
## two parking lots, an elevated highway with a homeless encampment under it, a river along
## the north with a bridge, and a skyline all round so it feels enclosed.
## Streets: parking lanes, painted bike lanes, wide zebra crossings, traffic lights that
## really cycle, moving traffic (Traffic), power lines, bollards, a pedestrian footbridge.
##
## Cryptids can't walk through buildings, so the city also provides a little road graph:
## blocked(p) for picking spots, and route(a, b) for walking round blocks.
##
## Repeated small things (curbs, paint, AC units, fire escapes, parked cars...) are drawn as
## MultiMeshes (see _bx / _flush_batches) so the bigger city stays cheap to render.

const ROAD_HALF:= 6.5        # asphalt half-width (two lanes + bike lane + parking each way)
const WALK:= 3.0             # sidewalk width each side
const STREET_HALF:= ROAD_HALF + WALK
const LANE:= 1.8             # moving cars drive this far right of the centre line
const PARK_LANE:= 5.3        # parked cars sit this far out
const NS_ROADS:= [-114.0, -57.0, 0.0, 57.0, 114.0]    # x of the north-south streets
const EW_ROADS:= [146.0, 90.0, 34.0, -24.0, -100.0]   # z of the east-west streets (-100: riverside drive)
const BIKE_ROADS:= [90.0, 34.0]                        # EW streets with a green bike lane
const EDGE:= 171.0
const OUTER:= 208.0          # the skyline wall runs from EDGE out to here
const SOUTH_WALL:= 200.0     # tall buildings close off the street ends behind the camp
const RIVER_Z:= -132.0       # river centre line (runs east-west)
const RIVER_BED_HALF:= 8.0
const RIVER_BANK:= 4.5
const WATER:= -1.6
const BRIDGE_HALF:= STREET_HALF   # the bridge deck carries the street and both sidewalks
const BRIDGE_Z0:= -156.0
const BRIDGE_Z1:= -108.0
const OVERPASS_Z:= -62.0
const OVERPASS_HALF:= 8.0
const OVERPASS_Y:= 7.0
const CAMP_LOT:= Rect2(-22, 158, 44, 38)
const FENCE_Z:= 193.0
const PARK_MAIN:= Rect2(9.5, 43.5, 38, 37)
const PLAYGROUND:= Rect2(-47.5, 99.5, 38, 37)
## The pedestrian footbridge over the z = 34 street.
const FOOTBRIDGE_X:= -85.0
const FOOTBRIDGE_Y:= 5.6

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
var traffic: Traffic
var _building_mat: ShaderMaterial
var _concrete: StandardMaterial3D
var _colliders: StaticBody3D
## Street furniture (cars, trees, stands, pillars): solid for you, but cryptids slip past it
## (collision layer 2) so a chase never snags on a parked car or a sidewalk tree.
var _props: StaticBody3D
const PROPS_LAYER:= 2
var _sidewalk_trees: Array[Transform3D] = []
var _lamp_spots: Array[Vector3] = []
var _block_list: Array = []
var _block_rects: Array[Rect2] = []
## Strips of sidewalk to keep clear of trees/lamps (footbridge stairs, bus stop...).
var _keep_clear: Array[Rect2] = []
var _batches: Dictionary = {}
## Kerb space taken by the police cars, ambulance etc. (no random parked car there).
var _reserved: Array[Rect2] = []
var _mats: Dictionary = {}
var _font: Font


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
		if absf(x - rx) < half and z > -EDGE and z < OUTER:
			return true
	for rz: float in EW_ROADS:
		if absf(z - rz) < half and absf(x) < EDGE:
			return true
	return false


## Base ground tint under the street meshes (parks are grass, banks are mud).
static func ground_color(x: float, z: float) -> Color:
	var dz:= absf(z - RIVER_Z)
	if dz < RIVER_BED_HALF + RIVER_BANK:
		return Color(0.26, 0.24, 0.2).lerp(Color(0.2, 0.3, 0.18), clampf((dz - RIVER_BED_HALF) / RIVER_BANK, 0.0, 1.0))
	if PARK_MAIN.grow(-0.5).has_point(Vector2(x, z)) or PLAYGROUND.grow(-0.5).has_point(Vector2(x, z)):
		return Color(0.18, 0.36, 0.17)   # the parks
	var lawn_z:= EW_ROADS[4] - STREET_HALF
	if z < lawn_z + 0.5 and z > RIVER_Z + RIVER_BED_HALF + RIVER_BANK - 0.5:
		return Color(0.2, 0.34, 0.18)    # riverside lawn
	if z < RIVER_Z - RIVER_BED_HALF - RIVER_BANK:
		return Color(0.21, 0.33, 0.19)   # north bank
	return Color(0.17, 0.17, 0.18)


## Every street crossing (both streets exist there). Side streets run from the riverside
## drive south; the middle one also crosses the bridge.
static func intersections() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for rx: float in NS_ROADS:
		for rz: float in EW_ROADS:
			out.append(Vector2(rx, rz))
	return out


static func ns_extent(rx: float) -> Vector2:
	if rx == 0.0:
		return Vector2(-EDGE, CAMP_LOT.position.y)
	return Vector2(EW_ROADS[4] - STREET_HALF, SOUTH_WALL)


# ------------------------------------------------------------------ plan: blocks, nav

func _plan() -> void:
	var sh:= STREET_HALF
	var xs:= []
	var edges:= [-EDGE] + NS_ROADS + [EDGE]
	for i in edges.size() - 1:
		var x0: float = edges[i] + (sh if i > 0 else 0.0)
		var x1: float = edges[i + 1] - (sh if i + 1 < edges.size() - 1 else 0.0)
		xs.append([x0, x1])
	# Rows, camp side (south) to river side: [z0, z1, [block type per column]]
	var rows:= [
		[EW_ROADS[0] + sh, SOUTH_WALL, ["mid", "row", "mid_camp", "mid_camp", "row", "mid"]],
		[EW_ROADS[1] + sh, EW_ROADS[0] - sh, ["brick", "police", "playground", "brick", "lot", "garage"]],
		[EW_ROADS[2] + sh, EW_ROADS[1] - sh, ["towers", "brick", "hospital", "park", "scaffold", "towers"]],
		[EW_ROADS[3] + sh, EW_ROADS[2] - sh, ["mid", "brick", "tailgate_lot", "cityhall", "towers", "brick"]],
		[OVERPASS_Z + OVERPASS_HALF, EW_ROADS[3] - sh, ["mid", "brick", "mid", "mid", "brick", "mid"]],
	]
	_block_list = []
	for row in rows:
		for i in xs.size():
			var bx: Array = xs[i]
			var r:= Rect2(bx[0], row[0], bx[1] - bx[0], row[1] - row[0])
			var kind: String = row[2][i]
			if kind == "mid_camp":
				# Leave the camp parking lot open.
				if r.get_center().x < 0.0:
					r = Rect2(r.position.x, r.position.y, (CAMP_LOT.position.x - 2.0) - r.position.x, r.size.y)
				else:
					var x0:= CAMP_LOT.end.x + 2.0
					r = Rect2(x0, r.position.y, r.end.x - x0, r.size.y)
				kind = "mid"
			_block_list.append({"rect": r, "kind": kind})
	# The skyline wall: east, west, north (beyond the river) and a strip behind the camp.
	for side: float in [-1.0, 1.0]:
		_block_list.append({"rect": Rect2(EDGE if side > 0 else -OUTER, -OUTER, OUTER - EDGE, OUTER * 2.0), "kind": "wall"})
	_block_list.append({"rect": Rect2(-EDGE, -OUTER, EDGE * 2.0, OUTER - EDGE), "kind": "wall"})
	for b in _block_list:
		var r: Rect2 = b["rect"]
		_block_rects.append(r)
		if b["kind"] not in ["park", "playground", "lot", "tailgate_lot"]:
			blockers.append(r.grow(0.6))
	# Behind the camp: the street ends are closed by the south wall (the lot itself stays open).
	for xr: Array in [[-EDGE, CAMP_LOT.position.x], [CAMP_LOT.end.x, EDGE]]:
		var r:= Rect2(xr[0], SOUTH_WALL, xr[1] - xr[0], OUTER - SOUTH_WALL)
		_block_list.append({"rect": r, "kind": "wall"})
		_block_rects.append(r)
		blockers.append(r.grow(0.6))
	# River (except where the bridge crosses).
	var rz0:= RIVER_Z - RIVER_BED_HALF - 3.5
	var rz1:= RIVER_Z + RIVER_BED_HALF + 3.5
	blockers.append(Rect2(-OUTER, rz0, OUTER - BRIDGE_HALF + 0.5, rz1 - rz0))
	blockers.append(Rect2(BRIDGE_HALF - 0.5, rz0, OUTER, rz1 - rz0))
	# The fountain in the park.
	blockers.append(Rect2(PARK_MAIN.get_center() - Vector2(4.4, 4.4), Vector2(8.8, 8.8)))
	landmarks["methman_camp"] = Vector2(85, OVERPASS_Z + 1.5)
	landmarks["tailgate"] = Vector2(-28.5, 5)
	landmarks["park"] = PARK_MAIN.get_center() + Vector2(0, 9)
	_keep_clear.append(Rect2(FOOTBRIDGE_X - 2.5, EW_ROADS[2] - STREET_HALF, 17.0, STREET_HALF * 2.0))
	_build_nav()


func _build_nav() -> void:
	nav_nodes.clear()
	for p in intersections():
		nav_nodes.append(p)
	for rx: float in NS_ROADS:
		nav_nodes.append(Vector2(rx, OVERPASS_Z))
		nav_nodes.append(Vector2(rx, 175.0))
		nav_nodes.append(Vector2(rx, -82.0))
	for rz: float in EW_ROADS + [OVERPASS_Z, -82.0]:
		nav_nodes.append(Vector2(-162.0, rz))
		nav_nodes.append(Vector2(162.0, rz))
	for x: float in [-142.0, -85.0, -28.0, 28.0, 85.0, 142.0]:
		nav_nodes.append(Vector2(x, OVERPASS_Z))
		nav_nodes.append(Vector2(x, -82.0))
		nav_nodes.append(Vector2(x, -114.0))
	nav_nodes.append_array([Vector2(0, -114), Vector2(0, -150), Vector2(0, -162), Vector2(-60, -160), Vector2(60, -160),
		PARK_MAIN.get_center() + Vector2(0, 9), PARK_MAIN.get_center() - Vector2(0, 9), PLAYGROUND.get_center(),
		landmarks["tailgate"], landmarks["methman_camp"], Vector2(0, 165), Vector2(0, 180)])
	_nav_edges.clear()
	for i in nav_nodes.size():
		_nav_edges[i] = []
	for i in nav_nodes.size():
		for j in range(i + 1, nav_nodes.size()):
			var a:= nav_nodes[i]
			var b:= nav_nodes[j]
			var d:= a.distance_to(b)
			if d < 125.0 and not segment_blocked(a, b):
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
	var lo:= Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi:= Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	for r in blockers:
		# Cheap bounding-box reject before the real clip test.
		if r.position.x > hi.x or r.end.x < lo.x or r.position.y > hi.y or r.end.y < lo.y:
			continue
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
	# Dijkstra over the street graph, entering from any nearby node a can see, leaving to b.
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
		if a.distance_to(nav_nodes[i]) < 95.0 and not segment_blocked(a, nav_nodes[i]):
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
		var to_b:= nav_nodes[u].distance_to(b)
		if du + to_b < best_total and to_b < 125.0 and not segment_blocked(nav_nodes[u], b):
			best_total = du + to_b
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


## A random open spot on a street, plaza or in a park (for spawns and wandering).
func random_open_spot(r: RandomNumberGenerator) -> Vector2:
	for _i in 60:
		var p:= Vector2(r.randf_range(-160, 160), r.randf_range(-165, 150))
		if not blocked(p) and absf(p.y - RIVER_Z) > RIVER_BED_HALF + 2.0:
			return p
	return Vector2(0, EW_ROADS[2])


func _in_block(p: Vector2) -> bool:
	for r in _block_rects:
		if r.has_point(p):
			return true
	return false


func _clear(p: Vector2) -> bool:
	for r in _keep_clear:
		if r.has_point(p):
			return false
	return true


# ------------------------------------------------------------------ build

func _ready() -> void:
	_font = load("res://fonts/Oswald.ttf")
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
	traffic = Traffic.new()
	traffic.name = "Traffic"
	traffic.city = self
	_build_streets()
	for b in _block_list:
		var r: Rect2 = b["rect"]
		match str(b["kind"]):
			"mid":
				_build_buildings(r, 9.0, 24.0, 3, "colour")
			"brick":
				_build_buildings(r, 11.0, 22.0, 3, "brick")
			"towers":
				_build_buildings(r, 34.0, 82.0, 2, "glass")
			"row":
				_build_rowhouses(r)
			"wall":
				_build_buildings(r, 26.0, 72.0, 5, "wall")
			"park":
				_build_park(r)
			"playground":
				_build_playground(r)
			"lot", "tailgate_lot":
				_build_parking_lot(r, b["kind"] == "tailgate_lot")
			"police":
				_build_police(r)
			"garage":
				_build_garage(r)
			"hospital":
				_build_hospital(r)
			"cityhall":
				_build_city_hall(r)
			"scaffold":
				_build_buildings(r, 12.0, 20.0, 3, "brick", true)
	_build_river()
	_build_overpass()
	_build_footbridge()
	_build_sidewalk_trees()
	_build_lamps()
	_build_traffic_lights()
	_build_power_lines()
	_build_cars()
	_build_stands()
	_build_camp_lot()
	_flush_batches()
	add_child(traffic)
	traffic.build_loops()


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
	l.font = _font
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


## Solid for the player (a building-like thing): an invisible box on the main collider.
func _solid(size: Vector3, xf: Transform3D, props: bool = false) -> void:
	var cs:= CollisionShape3D.new()
	var bs:= BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = xf
	(_props if props else _colliders).add_child(cs)


# ------------------------------------------------------------------ batched instances

const _UNIT_KEYS:= ["box", "iron", "glass", "paint", "white", "green", "bulb", "cyl", "tyre", "plane", "wood", "chrome", "red_lamp", "blue_lamp", "tail", "head"]


func _batch_mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m:= StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	match key:
		"iron":
			m.roughness = 0.5
			m.metallic = 0.55
		"chrome", "paint":
			m.roughness = 0.3
			m.metallic = 0.5
		"glass":
			m.roughness = 0.08
			m.metallic = 0.3
		"bulb", "head":
			m.emission_enabled = true
			m.emission = Color(1.0, 0.85, 0.6)
			m.emission_energy_multiplier = 3.0
		"tail", "red_lamp":
			m.emission_enabled = true
			m.emission = Color(0.9, 0.08, 0.05)
			m.emission_energy_multiplier = 1.5
		"white":
			m.emission_enabled = true
			m.emission = Color(0.9, 0.9, 0.88)
			m.emission_energy_multiplier = 0.12
		"green":
			m.roughness = 0.75
	_mats[key] = m
	return m


func _batch_mesh(key: String) -> Mesh:
	match key:
		"cyl", "tyre":
			var cm:= CylinderMesh.new()
			cm.top_radius = 0.5
			cm.bottom_radius = 0.5
			cm.height = 1.0
			cm.radial_segments = 10
			cm.rings = 1
			return cm
		"plane", "white", "green":
			var pm:= PlaneMesh.new()
			pm.size = Vector2.ONE
			return pm
	var bm:= BoxMesh.new()
	bm.size = Vector3.ONE
	return bm


## Queue one instance of a unit mesh: xf already carries the size as scale.
func _inst(key: String, xf: Transform3D, col: Color) -> void:
	if not _batches.has(key):
		_batches[key] = {"xf": [], "col": []}
	_batches[key]["xf"].append(xf)
	_batches[key]["col"].append(col)


## A batched box: size, centre, colour, optional rotation; key picks the material.
func _bx(size: Vector3, center: Vector3, col: Color, key: String = "box", basis: Basis = Basis.IDENTITY) -> void:
	_inst(key, Transform3D(basis * Basis.from_scale(size), center), col)


## A batched upright cylinder (radius, height) at its centre.
func _cy(r: float, h: float, center: Vector3, col: Color, key: String = "cyl", basis: Basis = Basis.IDENTITY) -> void:
	_inst(key, Transform3D(basis * Basis.from_scale(Vector3(r * 2.0, h, r * 2.0)), center), col)


## A batched flat strip on the ground (paint, lawns...).
func _fl(size: Vector2, center: Vector3, col: Color, key: String = "plane", yaw: float = 0.0) -> void:
	_inst(key, Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(size.x, 1.0, size.y)), center), col)


func _flush_batches() -> void:
	for key in _batches:
		var b: Dictionary = _batches[key]
		var mm:= MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _batch_mesh(key)
		mm.instance_count = b["xf"].size()
		for i in mm.instance_count:
			mm.set_instance_transform(i, b["xf"][i])
			mm.set_instance_color(i, b["col"][i])
		var mmi:= MultiMeshInstance3D.new()
		mmi.name = "Batch_" + key
		mmi.multimesh = mm
		mmi.material_override = _batch_mat(key)
		if key in ["plane", "white", "green"]:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	_batches.clear()


## A facade frame: origin on the wall at ground level, t along the wall, n out of it.
## Box size is (along, up, out) and local centre (u, y, o).
func _fbox(f: Dictionary, size: Vector3, local: Vector3, col: Color, key: String = "box", roll: float = 0.0) -> void:
	var t: Vector3 = f["t"]
	var n: Vector3 = f["n"]
	var basis:= Basis(t, Vector3.UP, n)
	if roll != 0.0:
		basis = Basis(n, roll) * basis
	var c: Vector3 = f["o"] + t * local.x + Vector3.UP * local.y + n * local.z
	_inst(key, Transform3D(basis * Basis.from_scale(size), c), col)


# ------------------------------------------------------------------ buildings

## Window grid by world position. style: 0 colourful stucco, 1 brick (with mortar and white
## window frames), 2 glass tower, 3 residential (windows from the ground up, no shopfront).
func _window_shader() -> Shader:
	var sh:= Shader.new()
	sh.code = """
shader_type spatial;
instance uniform vec3 tint = vec3(0.3, 0.3, 0.33);
instance uniform float base_y = 0.0;
instance uniform float seed = 0.0;
instance uniform float style = 0.0;
varying vec3 wpos;
varying vec3 wnrm;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.17) * 43758.5453); }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	if (abs(wnrm.y) > 0.5) {
		ALBEDO = tint * 0.55;
		ROUGHNESS = 0.95;
	} else {
		bool brick = style > 0.5 && style < 1.5;
		bool glass = style > 1.5 && style < 2.5;
		bool resi = style > 2.5;
		float along = abs(wnrm.x) > 0.5 ? wpos.z : wpos.x;
		float up = wpos.y - base_y;
		float f0 = resi ? 0.9 : 4.2;
		vec2 cell = vec2(along / 2.6, (up - f0) / 3.3);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		vec4 w = vec4(0.16, 0.84, 0.22, 0.82);
		if (brick) w = vec4(0.27, 0.73, 0.18, 0.86);
		if (glass) w = vec4(0.04, 0.96, 0.1, 0.94);
		if (resi) w = vec4(0.24, 0.76, 0.24, 0.8);
		float win = step(w.x, f.x) * step(f.x, w.y) * step(w.z, f.y) * step(f.y, w.w);
		float frame = step(w.x - 0.06, f.x) * step(f.x, w.y + 0.06) * step(w.z - 0.08, f.y) * step(f.y, w.w + 0.05) - win;
		float h = hash(id + vec2(floor(wnrm.x * 2.0 + 3.0), floor(wnrm.z * 2.0 + 3.0)) * 17.0);
		float lit = step(glass ? 0.7 : 0.62, h);
		vec3 warm = mix(vec3(1.0, 0.78, 0.42), vec3(0.65, 0.8, 1.0), step(0.93, h));
		// Ground floor: shopfronts, mostly lit (not on houses).
		float shop = resi ? 0.0 : 1.0 - step(4.0, up);
		float shop_win = shop * step(0.8, up) * step(up, 3.4) * step(0.1, fract(along / 6.0)) * step(fract(along / 6.0), 0.9);
		float any_win = mix(win * step(f0, up), shop_win, shop);
		float any_frame = glass ? 0.0 : frame * step(f0, up) * (1.0 - shop);
		vec3 wall = tint * (0.86 + 0.14 * hash(vec2(floor(up / 3.3), 0.0)));
		if (brick) {
			float row = floor(up / 0.26);
			float bu = fract(up / 0.26);
			float bv = fract(along / 0.62 + mod(row, 2.0) * 0.5);
			float aa = clamp(1.0 - max(fwidth(up), fwidth(along)) * 5.0, 0.0, 1.0);
			float mortar = max(step(bu, 0.13), step(bv, 0.05)) * aa;
			float bvar = (hash(vec2(floor(along / 0.62 + mod(row, 2.0) * 0.5), row)) - 0.5) * 0.18 * aa;
			wall = tint * (0.9 + bvar);
			wall = mix(wall, vec3(0.52, 0.49, 0.45), mortar * 0.55);
		}
		if (glass) {
			// Spandrel bands between floors.
			wall = tint * (0.7 + 0.3 * step(0.5, fract(up / 3.3)));
		}
		vec3 glass_col = glass ? vec3(0.06, 0.09, 0.13) : vec3(0.03, 0.04, 0.06);
		ALBEDO = mix(mix(wall, vec3(0.86, 0.84, 0.78), any_frame), glass_col, any_win);
		ROUGHNESS = mix(0.9, 0.1, any_win);
		METALLIC = any_win * (glass ? 0.6 : 0.4);
		float on = mix(lit, step(0.25, hash(vec2(floor(along / 6.0), 7.0))), shop);
		EMISSION = warm * any_win * on * (0.9 + 1.2 * hash(id + 3.7)) * 1.4;
	}
}
"""
	return sh


const COLOUR_TINTS:= [Color(0.24, 0.58, 0.6), Color(0.72, 0.26, 0.22), Color(0.9, 0.84, 0.68), Color(0.3, 0.45, 0.72),
	Color(0.86, 0.64, 0.26), Color(0.5, 0.74, 0.6), Color(0.9, 0.56, 0.46), Color(0.6, 0.5, 0.76), Color(0.84, 0.84, 0.8)]
const BRICK_TINTS:= [Color(0.56, 0.25, 0.18), Color(0.64, 0.33, 0.22), Color(0.46, 0.22, 0.17), Color(0.7, 0.46, 0.33), Color(0.52, 0.3, 0.24)]
const GLASS_TINTS:= [Color(0.36, 0.43, 0.52), Color(0.52, 0.52, 0.54), Color(0.3, 0.34, 0.42), Color(0.62, 0.6, 0.54)]
const WALL_TINTS:= [Color(0.34, 0.33, 0.36), Color(0.42, 0.36, 0.3), Color(0.28, 0.3, 0.36), Color(0.45, 0.42, 0.38)]
const ROW_TINTS:= [Color(0.9, 0.62, 0.64), Color(0.72, 0.3, 0.27), Color(0.94, 0.86, 0.6), Color(0.62, 0.76, 0.86), Color(0.64, 0.74, 0.56), Color(0.92, 0.9, 0.86)]
const AWNING_COLS:= [Color(0.12, 0.42, 0.24), Color(0.75, 0.15, 0.12), Color(0.15, 0.3, 0.6), Color(0.9, 0.6, 0.12), Color(0.45, 0.2, 0.45), Color(0.1, 0.1, 0.12)]
const SHOP_NAMES:= ["DINER", "PIZZA", "LAUNDROMAT", "PHARMACY", "BODEGA", "BAGELS", "DONUTS", "PAWN SHOP", "STORE",
	"DELI", "VINYL", "TATTOO", "NOODLES", "NESSIE'S FISH & CHIPS", "MOTHMAN LIGHTING", "24 HR STORE", "HARDWARE", "BOOKS"]
const STYLE_ID:= {"colour": 0.0, "brick": 1.0, "glass": 2.0, "row": 3.0, "wall": 0.0}


## One building: a shaded box plus the details its style calls for on street-facing sides.
func _building(r: Rect2, h: float, style: String = "colour", tint: Color = Color(-1, 0, 0), details: bool = true) -> MeshInstance3D:
	var mi:= _box(Vector3(r.size.x, h, r.size.y), Vector3(r.get_center().x, h * 0.5, r.get_center().y), _building_mat, true)
	var t:= tint
	if t.r < 0.0:
		var pal: Array = {"colour": COLOUR_TINTS, "brick": BRICK_TINTS, "glass": GLASS_TINTS, "wall": WALL_TINTS, "row": ROW_TINTS}[style]
		t = pal[rng.randi() % pal.size()]
	mi.set_instance_shader_parameter("tint", Vector3(t.r, t.g, t.b))
	mi.set_instance_shader_parameter("base_y", 0.0)
	mi.set_instance_shader_parameter("seed", rng.randf() * 100.0)
	mi.set_instance_shader_parameter("style", STYLE_ID[style])
	# Roof clutter: a water tower or AC units, a red aircraft light on the tall ones.
	var top:= Vector3(r.get_center().x, h, r.get_center().y)
	if h > 40.0:
		_bx(Vector3(0.5, 3.0, 0.5), top + Vector3(0, 1.5, 0), Color(0.42, 0.41, 0.4))
		_bx(Vector3(0.5, 0.5, 0.5), top + Vector3(0, 3.2, 0), Color(1, 0.15, 0.1), "tail")
	elif style == "brick" and rng.randf() < 0.55 or style != "brick" and rng.randf() < 0.3:
		var wood:= Color(0.36, 0.25, 0.16)
		var tw:= top + Vector3(rng.randf_range(-2, 2), 2.9, rng.randf_range(-2, 2))
		_cy(1.4, 2.2, tw, wood)
		_inst("cyl", Transform3D(Basis.from_scale(Vector3(3.0, 0.6, 3.0)), tw + Vector3(0, 1.4, 0)), wood.darkened(0.2))
		for k in 4:
			var a:= TAU * k / 4.0
			_bx(Vector3(0.12, 1.8, 0.12), tw + Vector3(cos(a) * 1.1, -2.0, sin(a) * 1.1), Color(0.3, 0.3, 0.3), "iron")
	else:
		for k in rng.randi_range(1, 3):
			_bx(Vector3(1.6, 1.0, 1.2), top + Vector3(rng.randf_range(-r.size.x * 0.3, r.size.x * 0.3), 0.5, rng.randf_range(-r.size.y * 0.3, r.size.y * 0.3)), Color(0.6, 0.6, 0.58), "chrome")
	# Cornice.
	_bx(Vector3(r.size.x + 0.4, 0.5, r.size.y + 0.4), top + Vector3(0, -0.2, 0), t.darkened(0.35))
	if style != "wall" and details:
		_facade_details(r, h, style)
	return mi


## The sides of r that face a street or plaza: [{o, t, n, len}] (o = left end on the wall).
func _street_sides(r: Rect2) -> Array:
	var out: Array = []
	var c:= r.get_center()
	for nrm: Vector2 in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
		var half:= r.size * 0.5
		var mid:= c + nrm * (half.y if nrm.x == 0.0 else half.x)
		var probe:= mid + nrm * 4.0
		if _in_block(probe) or absf(probe.x) > EDGE or probe.y > SOUTH_WALL or probe.y < -EDGE:
			continue
		var n3:= Vector3(nrm.x, 0, nrm.y)
		var t3:= Vector3.UP.cross(n3)
		var length:= r.size.x if nrm.x == 0.0 else r.size.y
		var o:= Vector3(mid.x, 0, mid.y) - t3 * length * 0.5 + n3 * 0.02
		out.append({"o": o, "t": t3, "n": n3, "len": length})
	return out


## Window column k on a facade: its centre (along-the-wall distance from f.o).
func _win_cols(f: Dictionary) -> Array[float]:
	var t: Vector3 = f["t"]
	var o: Vector3 = f["o"]
	var len_: float = f["len"]
	# The shader's window grid runs on world x (or z); find where it falls on this wall.
	var along0:= o.x if absf(t.x) > 0.5 else o.z
	var sgn:= signf(t.x if absf(t.x) > 0.5 else t.z)
	var out: Array[float] = []
	for k in range(-200, 200):
		var world:= (k + 0.5) * 2.6
		var u:= (world - along0) * sgn
		if u > 1.0 and u < len_ - 1.0:
			out.append(u)
	return out


func _facade_details(r: Rect2, h: float, style: String) -> void:
	var sides:= _street_sides(r)
	var f0:= 0.9 if style == "row" else 4.2
	var floors:= int((h - f0 - 0.8) / 3.3)
	var did_escape:= false
	for f: Dictionary in sides:
		var cols:= _win_cols(f)
		var len_: float = f["len"]
		# Shopfronts with awnings and signs (not on glass towers or houses).
		if style in ["colour", "brick"] and len_ > 7.0:
			var aw: Color = AWNING_COLS[0] if style == "brick" and rng.randf() < 0.7 else AWNING_COLS[rng.randi() % AWNING_COLS.size()]
			var w:= minf(len_ - 2.0, rng.randf_range(6.0, 11.0))
			var u0:= rng.randf_range(1.0, maxf(1.0, len_ - w - 1.0))
			_awning(f, u0 + w * 0.5, w, aw)
			if rng.randf() < 0.75:
				_shop_sign(f, u0 + w * 0.5, SHOP_NAMES[rng.randi() % SHOP_NAMES.size()], aw)
			if style == "brick" and len_ > w + 9.0 and rng.randf() < 0.6:
				var u1:= fmod(u0 + w + 2.0 + rng.randf() * 3.0, len_ - 6.0) + 3.0
				_awning(f, u1, 4.5, AWNING_COLS[0])
		# Window AC units.
		if style != "glass":
			for u in cols:
				for fl in floors:
					if rng.randf() < 0.1:
						var y:= f0 + 3.3 * fl + 0.55
						_fbox(f, Vector3(0.8, 0.5, 0.55), Vector3(u, y, 0.28), Color(0.78, 0.78, 0.74), "chrome")
		# Fire escapes on the brick walk-ups.
		if style == "brick" and not did_escape and floors >= 2 and cols.size() >= 4 and rng.randf() < 0.85:
			did_escape = true
			var k0:= rng.randi_range(0, cols.size() - 3)
			_fire_escape(f, (cols[k0] + cols[k0 + 2]) * 0.5, floors)


func _awning(f: Dictionary, u: float, w: float, col: Color) -> void:
	# Sloped canopy with lighter stripes, and a valance along the front edge.
	var t: Vector3 = f["t"]
	var n: Vector3 = f["n"]
	var c: Vector3 = f["o"] + t * u + Vector3.UP * 3.55 + n * 0.72
	var b:= Basis(t, Vector3.UP, n)
	b = Basis(t, -0.32) * b
	_inst("box", Transform3D(b * Basis.from_scale(Vector3(w, 0.06, 1.55)), c + Vector3.UP * 0.02), col)
	var stripes:= int(w / 0.9)
	for s in stripes:
		if s % 2 == 0:
			_inst("box", Transform3D(b * Basis.from_scale(Vector3(w / stripes, 0.065, 1.56)), c + Vector3.UP * 0.025 + t * ((s + 0.5) * w / stripes - w * 0.5)), col.lightened(0.45))
	_fbox(f, Vector3(w, 0.32, 0.04), Vector3(u, 3.18, 1.46), col.darkened(0.15))


func _shop_sign(f: Dictionary, u: float, text: String, col: Color) -> void:
	var t: Vector3 = f["t"]
	var n: Vector3 = f["n"]
	var w:= clampf(text.length() * 0.42 + 0.8, 2.5, 9.0)
	_fbox(f, Vector3(w, 0.62, 0.12), Vector3(u, 4.15, 0.06), col.darkened(0.45))
	var l:= _sign(text, f["o"] + t * u + Vector3.UP * 4.15 + n * 0.14, 90, Color(1.0, 0.95, 0.82), self)
	l.rotation.y = atan2(n.x, n.z)
	l.outline_size = 4


## Black iron fire escape: a platform per floor, railings, zig-zag stairs, a drop ladder.
func _fire_escape(f: Dictionary, u: float, floors: int) -> void:
	var iron:= Color(0.09, 0.09, 0.1)
	var w:= 7.0
	for fl in floors:
		var y:= 4.2 + 3.3 * fl + 0.62
		_fbox(f, Vector3(w, 0.07, 1.25), Vector3(u, y, 0.64), iron, "iron")
		_fbox(f, Vector3(w, 0.05, 0.05), Vector3(u, y + 1.0, 1.25), iron, "iron")
		_fbox(f, Vector3(w, 0.04, 0.04), Vector3(u, y + 0.5, 1.25), iron, "iron")
		for su: float in [-w * 0.5, 0.0, w * 0.5]:
			_fbox(f, Vector3(0.05, 1.0, 0.05), Vector3(u + su, y + 0.5, 1.25), iron, "iron")
		for su: float in [-w * 0.5, w * 0.5]:
			_fbox(f, Vector3(0.05, 0.05, 1.25), Vector3(u + su, y + 1.0, 0.64), iron, "iron")
		# Stairs up to the next platform, alternating direction.
		if fl < floors - 1:
			var dir:= 1.0 if fl % 2 == 0 else -1.0
			var run:= w * 0.7
			var ang:= atan2(3.3, run) * dir
			_fbox(f, Vector3(sqrt(run * run + 3.3 * 3.3), 0.06, 0.6), Vector3(u, y + 1.65, 0.4), iron, "iron", ang)
	# Drop ladder hanging from the bottom platform.
	var y0:= 4.2 + 0.62
	for su: float in [-0.25, 0.25]:
		_fbox(f, Vector3(0.04, 2.4, 0.04), Vector3(u + w * 0.3 + su, y0 - 1.2, 1.1), iron, "iron")
	for k in 6:
		_fbox(f, Vector3(0.5, 0.03, 0.03), Vector3(u + w * 0.3, y0 - 0.2 - k * 0.4, 1.1), iron, "iron")


## Pipe scaffolding with planks and green safety netting up one facade.
func _scaffolding(f: Dictionary, h: float) -> void:
	var pipe:= Color(0.6, 0.62, 0.64)
	var len_: float = f["len"]
	var top:= minf(h - 1.0, 16.0)
	var u:= 1.0
	while u < len_ - 0.5:
		for o: float in [0.3, 1.6]:
			_fbox(f, Vector3(0.07, top, 0.07), Vector3(u, top * 0.5, o), pipe, "chrome")
		u += 2.6
	var y:= 2.2
	while y < top:
		for o: float in [0.3, 1.6]:
			_fbox(f, Vector3(len_ - 1.0, 0.07, 0.07), Vector3(len_ * 0.5, y + 1.0, o), pipe, "chrome")
		_fbox(f, Vector3(len_ - 1.0, 0.06, 1.4), Vector3(len_ * 0.5, y, 0.95), Color(0.55, 0.42, 0.25), "wood")
		y += 3.3
	# Netting on the upper part (the sidewalk shed below stays open).
	_fbox(f, Vector3(len_ - 0.8, top - 4.0, 0.03), Vector3(len_ * 0.5, 4.0 + (top - 4.0) * 0.5, 1.68), Color(0.12, 0.42, 0.2), "green_net")
	# Sidewalk shed roof.
	_fbox(f, Vector3(len_ - 0.6, 0.18, 2.6), Vector3(len_ * 0.5, 3.2, 1.3), Color(0.2, 0.32, 0.22))


## Fill a block with buildings shoulder to shoulder (no alleys: nothing to get stuck in).
func _build_buildings(block: Rect2, hmin: float, hmax: float, max_split: int, style: String, scaffold: bool = false) -> void:
	var r:= block.grow(-0.8)
	var along_x:= r.size.x >= r.size.y
	var n:= clampi(int((r.size.x if along_x else r.size.y) / 13.0), 1, max_split)
	var cuts: Array[float] = [0.0]
	for i in range(1, n):
		cuts.append(float(i) / n + rng.randf_range(-0.08, 0.08))
	cuts.append(1.0)
	var subs: Array[Rect2] = []
	for i in n:
		var a:= cuts[i]
		var b:= cuts[i + 1]
		var sub: Rect2
		if along_x:
			sub = Rect2(r.position.x + r.size.x * a, r.position.y, r.size.x * (b - a), r.size.y)
		else:
			sub = Rect2(r.position.x, r.position.y + r.size.y * a, r.size.x, r.size.y * (b - a))
		# Deep blocks: a front and back building at different heights.
		var deep:= (sub.size.y if along_x else sub.size.x) > 24.0
		if deep:
			if along_x:
				var mid:= sub.position.y + sub.size.y * rng.randf_range(0.4, 0.6)
				subs.append(Rect2(sub.position.x, sub.position.y, sub.size.x, mid - sub.position.y))
				subs.append(Rect2(sub.position.x, mid, sub.size.x, sub.end.y - mid))
			else:
				var midx:= sub.position.x + sub.size.x * rng.randf_range(0.4, 0.6)
				subs.append(Rect2(sub.position.x, sub.position.y, midx - sub.position.x, sub.size.y))
				subs.append(Rect2(midx, sub.position.y, sub.end.x - midx, sub.size.y))
		else:
			subs.append(sub)
	for i in subs.size():
		var st:= style
		# Mixed streets: a brick walk-up among the colourful ones and vice versa.
		if style == "colour" and rng.randf() < 0.22:
			st = "brick"
		elif style == "brick" and rng.randf() < 0.18:
			st = "colour"
		var h:= rng.randf_range(hmin, hmax)
		_building(subs[i], h, st)
		if scaffold and i == 0:
			for f: Dictionary in _street_sides(subs[i]):
				_scaffolding(f, h)
				break


## Pitched-roof rowhouses along the street side(s), plain low buildings filling the back.
func _build_rowhouses(block: Rect2) -> void:
	var r:= block.grow(-0.8)
	var depth:= 13.0
	# The street the houses face: the north side of the block (towards the city).
	var front:= Rect2(r.position.x, r.position.y, r.size.x, depth)
	var back:= Rect2(r.position.x, r.position.y + depth, r.size.x, r.size.y - depth)
	_building(back, rng.randf_range(7.0, 11.0), "colour", Color(0.5, 0.48, 0.45))
	var x:= front.position.x
	while x < front.end.x - 3.0:
		var w:= minf(rng.randf_range(6.0, 8.0), front.end.x - x)
		var h:= rng.randf_range(7.0, 10.5)
		var t: Color = ROW_TINTS[rng.randi() % ROW_TINTS.size()]
		var house:= Rect2(x, front.position.y, w, depth)
		_building(house, h, "row", t)
		# Pitched roof (ridge along the street), dark shingles, a chimney.
		var roof:= MeshInstance3D.new()
		var pm:= PrismMesh.new()
		pm.size = Vector3(depth + 0.6, 3.0, w + 0.3)
		roof.mesh = pm
		roof.material_override = _mat([Color(0.3, 0.16, 0.14), Color(0.22, 0.22, 0.25), Color(0.35, 0.25, 0.2)][rng.randi() % 3], 0.9)
		roof.position = Vector3(house.get_center().x, h + 1.5, house.get_center().y)
		roof.rotation.y = PI * 0.5
		add_child(roof)
		if rng.randf() < 0.6:
			_bx(Vector3(0.8, 2.4, 0.8), Vector3(x + w * 0.75, h + 2.2, house.get_center().y + 2.0), Color(0.5, 0.28, 0.22))
		# Front stoop and door.
		var dz:= front.position.y
		_bx(Vector3(1.6, 0.25, 1.0), Vector3(x + w * 0.3, 0.12, dz - 0.5), Color(0.6, 0.58, 0.55))
		_bx(Vector3(1.6, 0.25, 0.5), Vector3(x + w * 0.3, 0.37, dz - 0.25), Color(0.6, 0.58, 0.55))
		_bx(Vector3(1.0, 2.1, 0.06), Vector3(x + w * 0.3, 1.55, dz - 0.03), t.darkened(0.55))
		x += w


# ------------------------------------------------------------------ named buildings

func _named_sign(text: String, f: Dictionary, u: float, y: float, col: Color, size: int = 260) -> void:
	var t: Vector3 = f["t"]
	var n: Vector3 = f["n"]
	var l:= _sign(text, f["o"] + t * u + Vector3.UP * y + n * 0.16, size, col, self)
	l.rotation.y = atan2(n.x, n.z)


func _build_police(block: Rect2) -> void:
	var r:= block.grow(-0.8)
	var front:= Rect2(r.position.x, r.position.y, r.size.x, r.size.y * 0.55)
	_building(front, 13.0, "colour", Color(0.28, 0.38, 0.6), false)
	_building(Rect2(r.position.x, front.end.y, r.size.x, r.end.y - front.end.y), 18.0, "brick")
	for f: Dictionary in _street_sides(front):
		_fbox(f, Vector3(8.5, 1.6, 0.1), Vector3(f["len"] * 0.5, 9.0, 0.06), Color(0.08, 0.12, 0.3))
		_named_sign("POLICE", f, f["len"] * 0.5, 9.0, Color(1, 1, 1))
		# Blue-and-white band and a blue lamp over the door.
		_fbox(f, Vector3(f["len"] - 0.4, 0.6, 0.08), Vector3(f["len"] * 0.5, 7.4, 0.05), Color(0.9, 0.92, 0.95))
		_fbox(f, Vector3(0.5, 0.6, 0.5), Vector3(f["len"] * 0.5, 3.6, 0.4), Color(0.2, 0.4, 1.0), "blue_lamp")
		break
	# Two patrol cars out front.
	for k in 2:
		_parked_car(Vector3(r.position.x + 10.0 + k * 6.0, 0, EW_ROADS[1] + PARK_LANE), PI * 0.5, "police")


func _build_garage(block: Rect2) -> void:
	var r:= block.grow(-0.8)
	var front:= Rect2(r.position.x, r.position.y, r.size.x, 16.0)
	_building(front, 7.0, "colour", Color(0.82, 0.8, 0.74), false)
	_building(Rect2(r.position.x, front.end.y, r.size.x, r.end.y - front.end.y), 15.0, "colour")
	for f: Dictionary in _street_sides(front):
		if (f["n"] as Vector3).z > -0.5:
			continue
		_named_sign("GARAGE", f, f["len"] * 0.5, 5.6, Color(0.95, 0.3, 0.15))
		# Roll-up doors with ribs.
		for k in 3:
			var u: float = float(f["len"]) * (0.22 + 0.28 * k)
			_fbox(f, Vector3(4.2, 3.8, 0.1), Vector3(u, 1.9, 0.05), Color(0.62, 0.64, 0.66), "chrome")
			for rib in 9:
				_fbox(f, Vector3(4.2, 0.05, 0.13), Vector3(u, 0.3 + rib * 0.42, 0.06), Color(0.45, 0.46, 0.48), "chrome")
		break
	_parked_car(Vector3(block.get_center().x - 4.0, 0, EW_ROADS[1] + PARK_LANE), PI * 0.5, "")


func _build_hospital(block: Rect2) -> void:
	var r:= block.grow(-0.8)
	_building(Rect2(r.position.x, r.position.y + 8.0, r.size.x, r.size.y - 8.0), 26.0, "colour", Color(0.9, 0.9, 0.88), false)
	# Low wing with the ambulance bay along the street.
	var wing:= Rect2(r.position.x, r.position.y, r.size.x * 0.6, 8.0)
	_building(wing, 6.0, "colour", Color(0.85, 0.86, 0.86), false)
	for f: Dictionary in _street_sides(Rect2(r.position.x, r.position.y + 8.0, r.size.x, r.size.y - 8.0)):
		if (f["n"] as Vector3).x > 0.5 or (f["n"] as Vector3).x < -0.5:
			_fbox(f, Vector3(10.0, 1.6, 0.1), Vector3(f["len"] * 0.5, 20.0, 0.06), Color(0.95, 0.95, 0.95))
			_named_sign("HOSPITAL", f, f["len"] * 0.5, 20.0, Color(0.85, 0.1, 0.1))
			break
	for f: Dictionary in _street_sides(wing):
		_named_sign("EMERGENCY", f, f["len"] * 0.5, 4.6, Color(0.9, 0.12, 0.1), 160)
		# Red cross.
		_fbox(f, Vector3(1.6, 0.5, 0.1), Vector3(f["len"] * 0.85, 4.6, 0.06), Color(0.9, 0.1, 0.1), "tail")
		_fbox(f, Vector3(0.5, 1.6, 0.1), Vector3(f["len"] * 0.85, 4.6, 0.06), Color(0.9, 0.1, 0.1), "tail")
		break
	var bay:= Vector2(r.end.x - r.size.x * 0.2, r.position.y + 4.0)
	_fl(Vector2(r.size.x * 0.4 - 1.0, 7.5), Vector3(bay.x, 0.03, bay.y), Color(0.25, 0.25, 0.26))
	_parked_car(Vector3(bay.x, 0, bay.y), 0.0, "ambulance")


func _build_city_hall(block: Rect2) -> void:
	var r:= block.grow(-0.8)
	var core:= Rect2(r.position.x + 4.0, r.position.y + 6.0, r.size.x - 8.0, r.size.y - 10.0)
	var cream:= Color(0.9, 0.86, 0.74)
	_building(core, 14.0, "colour", cream, false)
	# Plaza and steps in front, columns along the portico.
	_fl(Vector2(r.size.x, 6.0), Vector3(r.get_center().x, 0.03, r.position.y + 3.0), Color(0.55, 0.53, 0.5))
	for k in 3:
		_bx(Vector3(core.size.x * 0.6, 0.2, 1.0), Vector3(core.get_center().x, 0.1 + k * 0.2, core.position.y - 2.5 + k * 0.9), Color(0.72, 0.7, 0.66))
	for k in 8:
		var x:= core.get_center().x - core.size.x * 0.3 + core.size.x * 0.6 * k / 7.0
		_cy(0.45, 8.5, Vector3(x, 4.25 + 0.6, core.position.y - 0.4), Color(0.92, 0.9, 0.84))
	_bx(Vector3(core.size.x * 0.68, 1.2, 2.2), Vector3(core.get_center().x, 9.6, core.position.y - 0.3), cream.darkened(0.1))
	# Pediment.
	var ped:= MeshInstance3D.new()
	var pm:= PrismMesh.new()
	pm.size = Vector3(core.size.x * 0.7, 2.6, 2.2)
	ped.mesh = pm
	ped.material_override = _mat(cream, 0.85)
	ped.position = Vector3(core.get_center().x, 11.5, core.position.y - 0.3)
	add_child(ped)
	# The dome: drum, hemisphere, lantern.
	var c:= core.get_center()
	_cy(6.5, 4.0, Vector3(c.x, 16.0, c.y), cream.darkened(0.05))
	var dome:= MeshInstance3D.new()
	var sm:= SphereMesh.new()
	sm.radius = 6.6
	sm.height = 6.6
	sm.is_hemisphere = true
	sm.radial_segments = 24
	sm.rings = 10
	dome.mesh = sm
	var dm:= _mat(Color(0.32, 0.52, 0.45), 0.4)
	dm.metallic = 0.6
	dome.material_override = dm
	dome.position = Vector3(c.x, 18.0, c.y)
	add_child(dome)
	_cy(0.8, 2.4, Vector3(c.x, 25.6, c.y), cream)
	_cy(0.05, 4.0, Vector3(c.x, 28.5, c.y), Color(0.3, 0.3, 0.3), "iron")
	_named_sign("CITY HALL", {"o": Vector3(core.end.x, 0, core.position.y - 1.45), "t": Vector3(-1, 0, 0), "n": Vector3(0, 0, -1), "len": core.size.x},
		core.size.x * 0.5, 9.6, Color(0.25, 0.2, 0.12), 200)
	# Flagpoles at the corners of the plaza.
	for x: float in [r.position.x + 2.0, r.end.x - 2.0]:
		_cy(0.07, 9.0, Vector3(x, 4.5, r.position.y + 2.0), Color(0.75, 0.75, 0.78), "chrome")
		_bx(Vector3(1.8, 1.1, 0.03), Vector3(x + 0.95, 8.3, r.position.y + 2.0), Color(0.2, 0.35, 0.7))


# ------------------------------------------------------------------ streets

func _build_streets() -> void:
	var asphalt:= _mat(Color(0.12, 0.12, 0.13), 0.75)
	var walk_m:= _mat(Color(0.46, 0.45, 0.43), 0.9)
	var yellow:= Color(0.95, 0.78, 0.2)
	var white:= Color(0.9, 0.9, 0.88)
	var curb:= Color(0.58, 0.57, 0.53)
	for rx: float in NS_ROADS:
		var ext:= ns_extent(rx)
		var len_z:= ext.y - ext.x
		var cz:= (ext.x + ext.y) * 0.5
		_flat_mesh(Vector2(ROAD_HALF * 2.0, len_z), Vector3(rx, 0.03, cz), asphalt)
		for s: float in [-1.0, 1.0]:
			_flat_mesh(Vector2(WALK, len_z), Vector3(rx + s * (ROAD_HALF + WALK * 0.5), 0.045, cz), walk_m)
			_bx(Vector3(0.22, 0.14, len_z), Vector3(rx + s * ROAD_HALF, 0.07, cz), curb)
		var z:= ext.x + 2.0
		while z < ext.y - 1.0:
			if not _near_ew(z, STREET_HALF + 1.0):
				_fl(Vector2(0.18, 2.6), Vector3(rx, 0.05, z), yellow, "white")
				# Parking-lane edge ticks.
				for s: float in [-1.0, 1.0]:
					if not on_bridge(rx, z) and absf(z - OVERPASS_Z) > OVERPASS_HALF:
						_fl(Vector2(0.12, 1.2), Vector3(rx + s * (PARK_LANE - 1.0), 0.05, z), white, "white")
			z += 6.0
	for rz: float in EW_ROADS:
		_flat_mesh(Vector2(EDGE * 2.0, ROAD_HALF * 2.0), Vector3(0, 0.035, rz), asphalt)
		for s: float in [-1.0, 1.0]:
			_flat_mesh(Vector2(EDGE * 2.0, WALK), Vector3(0, 0.05, rz + s * (ROAD_HALF + WALK * 0.5)), walk_m)
			_bx(Vector3(EDGE * 2.0, 0.14, 0.22), Vector3(0, 0.07, rz + s * ROAD_HALF), curb)
		var x:= -EDGE + 2.0
		while x < EDGE - 2.0:
			if not _near_ns(x, STREET_HALF + 1.0):
				_fl(Vector2(2.6, 0.18), Vector3(x, 0.055, rz), yellow, "white")
				for s: float in [-1.0, 1.0]:
					_fl(Vector2(1.2, 0.12), Vector3(x, 0.055, rz + s * (PARK_LANE - 1.0)), white, "white")
			x += 6.0
		# Green bike lanes (between the traffic and the parked cars).
		if rz in BIKE_ROADS:
			for s: float in [-1.0, 1.0]:
				var seg_x:= -EDGE
				for rx: float in NS_ROADS + [EDGE]:
					var x0:= seg_x + (STREET_HALF + 2.0 if seg_x > -EDGE else 0.0)
					var x1:= rx - STREET_HALF - 2.0 if rx < EDGE else EDGE
					if x1 > x0 + 2.0:
						_fl(Vector2(x1 - x0, 1.1), Vector3((x0 + x1) * 0.5, 0.052, rz + s * 3.6), Color(0.2, 0.6, 0.3), "green")
						var bx_:= x0 + 6.0
						while bx_ < x1 - 3.0:
							_bike_symbol(Vector3(bx_, 0.058, rz + s * 3.6))
							bx_ += 24.0
					seg_x = rx
	# Wide zebra crossings on every leg of every crossing, stop lines, manholes.
	for p in intersections():
		var ext:= ns_extent(p.x)
		var legs:= []
		for dz: float in [-1.0, 1.0]:
			var lz:= p.y + dz * (ROAD_HALF + 2.2)
			if lz > ext.x and lz < ext.y:
				legs.append(["ns", dz])
		for dx: float in [-1.0, 1.0]:
			legs.append(["ew", dx])
		for leg: Array in legs:
			var s: float = leg[1]
			for k in 10:
				var lat:= -ROAD_HALF + 0.65 + k * 1.3
				if leg[0] == "ns":
					_fl(Vector2(0.7, 3.6), Vector3(p.x + lat, 0.058, p.y + s * (ROAD_HALF + 2.2)), white, "white")
				else:
					_fl(Vector2(3.6, 0.7), Vector3(p.x + s * (ROAD_HALF + 2.2), 0.058, p.y + lat), white, "white")
			# Stop line across the lanes coming in on this leg.
			if leg[0] == "ns":
				_fl(Vector2(ROAD_HALF - 0.2, 0.4), Vector3(p.x - s * ROAD_HALF * 0.5, 0.058, p.y + s * (ROAD_HALF + 4.6)), white, "white")
			else:
				_fl(Vector2(0.4, ROAD_HALF - 0.2), Vector3(p.x + s * (ROAD_HALF + 4.6), 0.058, p.y + s * ROAD_HALF * 0.5), white, "white")
		_cy(0.42, 0.03, Vector3(p.x + 3.0, 0.045, p.y - 14.0), Color(0.1, 0.1, 0.11), "iron")
		_cy(0.42, 0.03, Vector3(p.x - 15.0, 0.045, p.y + 2.5), Color(0.1, 0.1, 0.11), "iron")
	# Under the overpass and the plaza by the river: plain concrete.
	_flat_mesh(Vector2(EDGE * 2.0, (OVERPASS_Z + OVERPASS_HALF) - (EW_ROADS[4] + STREET_HALF) + 1.0),
		Vector3(0, 0.02, ((OVERPASS_Z + OVERPASS_HALF) + (EW_ROADS[4] + STREET_HALF)) * 0.5), _mat(Color(0.3, 0.3, 0.31), 0.95))


func _bike_symbol(p: Vector3) -> void:
	var w:= Color(0.92, 0.95, 0.9)
	for dx: float in [-0.45, 0.45]:
		for k in 8:
			var a:= TAU * k / 8.0
			_fl(Vector2(0.24, 0.07), p + Vector3(dx + cos(a) * 0.3, 0.0, sin(a) * 0.3), w, "white", -a + PI * 0.5)
	_fl(Vector2(0.9, 0.07), p + Vector3(0, 0, -0.15), w, "white", 0.4)


func _flat_mesh(size: Vector2, pos: Vector3, mat: Material) -> void:
	var mi:= MeshInstance3D.new()
	var pm:= PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


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


## Is (x, z) on a sidewalk strip of some street (and on the map)?
func _sidewalk_ok(p: Vector2) -> bool:
	return _clear(p) and not _in_block(p) and absf(p.x) < EDGE - 2.0 and p.y < SOUTH_WALL - 2.0


func _build_river() -> void:
	var stone:= _mat(Color(0.4, 0.38, 0.36), 0.9)
	# The bridge deck (flush with the street so you just walk on), railings, posts.
	var deck_len:= BRIDGE_Z1 - BRIDGE_Z0
	var deck_c:= (BRIDGE_Z0 + BRIDGE_Z1) * 0.5
	_box(Vector3(BRIDGE_HALF * 2.0, 0.6, deck_len), Vector3(0, -0.25, deck_c), stone, true)
	_flat_mesh(Vector2(ROAD_HALF * 2.0, deck_len), Vector3(0, 0.06, deck_c), _mat(Color(0.12, 0.12, 0.13), 0.75))
	for s: float in [-1.0, 1.0]:
		_box(Vector3(0.3, 1.1, deck_len), Vector3(s * (BRIDGE_HALF - 0.15), 0.55, deck_c), stone, true)
		_bx(Vector3(0.12, 0.12, deck_len), Vector3(s * (BRIDGE_HALF - 0.15), 1.2, deck_c), Color(0.18, 0.2, 0.24), "iron")
		var z:= BRIDGE_Z0 + 3.0
		while z < BRIDGE_Z1:
			_bx(Vector3(0.5, 2.2, 0.5), Vector3(s * (BRIDGE_HALF - 0.15), 1.1, z), Color(0.4, 0.38, 0.36))
			z += 8.0
	# Piers in the water.
	for z: float in [RIVER_Z - 5.0, RIVER_Z + 5.0]:
		_box(Vector3(BRIDGE_HALF * 1.6, 4.6, 1.8), Vector3(0, -2.6, z), stone, true)
	# Embankment walls along both banks, with a railing.
	for s: float in [-1.0, 1.0]:
		var z:= RIVER_Z + s * (RIVER_BED_HALF + RIVER_BANK + 0.3)
		for side: float in [-1.0, 1.0]:
			var x0:= BRIDGE_HALF + 0.2
			var x1:= EDGE
			var cx:= side * (x0 + x1) * 0.5
			_box(Vector3(x1 - x0, 1.0, 0.25), Vector3(cx, 0.5, z), stone, true)
			_bx(Vector3(x1 - x0, 0.1, 0.1), Vector3(cx, 1.05, z), Color(0.18, 0.2, 0.24), "iron")
	# Benches and bollards on the riverside lawn.
	var lawn_z:= EW_ROADS[4] - STREET_HALF - 2.0
	for x: float in [-130.0, -90.0, -45.0, 44.0, 88.0, 130.0]:
		_bench(Vector3(x, 0, lawn_z - 3.0), PI)
	_bollard_row(Vector2(-EDGE + 4.0, lawn_z + 1.0), Vector2(-BRIDGE_HALF - 3.0, lawn_z + 1.0), 3.0, true)
	_bollard_row(Vector2(BRIDGE_HALF + 3.0, lawn_z + 1.0), Vector2(EDGE - 4.0, lawn_z + 1.0), 3.0, true)


## Short black posts every `gap` metres from a to b, optionally linked by drooping chains.
func _bollard_row(a: Vector2, b: Vector2, gap: float, chains: bool) -> void:
	var n:= int(a.distance_to(b) / gap)
	var prev:= Vector3.INF
	for i in n + 1:
		var p2:= a.lerp(b, float(i) / maxf(1.0, n))
		if _near_street(p2.x, p2.y, ROAD_HALF + 0.5):
			prev = Vector3.INF
			continue
		var p:= Vector3(p2.x, 0, p2.y)
		_cy(0.12, 0.9, p + Vector3(0, 0.45, 0), Color(0.08, 0.08, 0.09), "iron")
		_cy(0.15, 0.08, p + Vector3(0, 0.92, 0), Color(0.75, 0.6, 0.2), "chrome")
		if chains and prev != Vector3.INF:
			var mid:= (prev + p) * 0.5 + Vector3(0, 0.55, 0)
			for half in 2:
				var end:= prev if half == 0 else p
				var c:= (end + Vector3(0, 0.78, 0) + mid) * 0.5
				var seg:= mid - (end + Vector3(0, 0.78, 0))
				var b2:= Basis.looking_at(seg.normalized(), Vector3.UP) if seg.length() > 0.01 else Basis()
				_inst("iron", Transform3D(b2 * Basis.from_scale(Vector3(0.04, 0.04, seg.length())), c), Color(0.1, 0.1, 0.1))
		prev = p


func _build_overpass() -> void:
	var conc:= _mat(Color(0.5, 0.49, 0.47), 0.95)
	var dark:= _mat(Color(0.25, 0.25, 0.26), 0.95)
	# Deck, barriers, and the dark underside.
	_box(Vector3(OUTER * 2.0, 1.2, OVERPASS_HALF * 2.0), Vector3(0, OVERPASS_Y + 0.6, OVERPASS_Z), conc, true)
	_box(Vector3(OUTER * 2.0, 0.6, OVERPASS_HALF * 2.0 - 1.0), Vector3(0, OVERPASS_Y - 0.25, OVERPASS_Z), dark)
	for s: float in [-1.0, 1.0]:
		_bx(Vector3(OUTER * 2.0, 1.0, 0.4), Vector3(0, OVERPASS_Y + 1.7, OVERPASS_Z + s * (OVERPASS_HALF - 0.2)), Color(0.5, 0.49, 0.47))
	var x:= -OUTER + 4.0
	while x < OUTER - 4.0:
		if not _near_ns(x, STREET_HALF + 1.0):
			for s: float in [-1.0, 1.0]:
				var p:= Vector3(x, OVERPASS_Y * 0.5, OVERPASS_Z + s * 3.2)
				_bx(Vector3(1.2, OVERPASS_Y, 1.2), p, Color(0.5, 0.49, 0.47))
				var cs:= CollisionShape3D.new()
				var cyl:= CylinderShape3D.new()
				cyl.radius = 0.8
				cyl.height = OVERPASS_Y
				cs.shape = cyl
				cs.position = p
				_props.add_child(cs)
		x += 16.0
	# Sodium lights hung under the deck.
	for lx: float in [-150.0, -100.0, -64.0, -30.0, 30.0, 64.0, 85.0, 100.0, 150.0]:
		var l:= OmniLight3D.new()
		l.light_color = Color(1.0, 0.62, 0.25)
		l.light_energy = 2.2
		l.omni_range = 15.0
		l.position = Vector3(lx, OVERPASS_Y - 0.8, OVERPASS_Z)
		add_child(l)
		_bx(Vector3(0.8, 0.2, 0.4), l.position + Vector3(0, 0.25, 0), Color(1.0, 0.7, 0.35), "bulb")
	_build_encampment()


## Under the highway: tents, tarps, shopping carts, a burn barrel. Methman's tent is the main one.
func _build_encampment() -> void:
	var c:= Vector3(landmarks["methman_camp"].x, 0, landmarks["methman_camp"].y)
	var tarp_cols:= [Color(0.15, 0.3, 0.6), Color(0.55, 0.45, 0.2), Color(0.2, 0.45, 0.25), Color(0.6, 0.2, 0.15)]
	var spots:= [Vector3(-9, 0, -2), Vector3(-6, 0, 3), Vector3(6, 0, -3), Vector3(11, 0, 2), Vector3(14, 0, -1), Vector3(-13, 0, 1)]
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


## A walkable footbridge over the z = 34 street: two ramps, a deck, railings, a sign.
func _build_footbridge() -> void:
	var rz: float = EW_ROADS[2]
	var x:= FOOTBRIDGE_X
	var y:= FOOTBRIDGE_Y
	var steel:= Color(0.2, 0.42, 0.55)
	var lane:= ROAD_HALF + 1.05   # ramps run along the sidewalk, close to the curb
	var deck_len:= lane * 2.0 + 2.0
	_bx(Vector3(2.6, 0.25, deck_len), Vector3(x, y, rz), steel)
	_solid(Vector3(2.6, 0.25, deck_len), Transform3D(Basis.IDENTITY, Vector3(x, y, rz)))
	for s: float in [-1.0, 1.0]:
		# Railings on the deck (solid, so you can't walk off the side).
		_bx(Vector3(0.08, 1.1, deck_len), Vector3(x + s * 1.28, y + 0.65, rz), steel.lightened(0.3), "iron")
		_solid(Vector3(0.12, 1.2, deck_len), Transform3D(Basis.IDENTITY, Vector3(x + s * 1.28, y + 0.7, rz)))
		# Support legs at each end.
		_bx(Vector3(0.5, y, 0.5), Vector3(x - 1.0, y * 0.5, rz + s * (lane + 0.6)), steel.darkened(0.2))
		_bx(Vector3(0.5, y, 0.5), Vector3(x + 1.0, y * 0.5, rz + s * (lane + 0.6)), steel.darkened(0.2))
		# A ramp down along the sidewalk from each end of the deck.
		var run:= 11.0
		var ang:= atan2(y, run)
		var length:= sqrt(run * run + y * y)
		var zc:= rz + s * lane
		var c:= Vector3(x + 1.3 + run * 0.5, y * 0.5 - 0.06, zc)
		var b:= Basis(Vector3(0, 0, 1), -ang)   # high end at the deck, low end out along the sidewalk
		_bx(Vector3(length, 0.2, 1.9), c, steel, "box", b)
		_solid(Vector3(length, 0.2, 1.9), Transform3D(b, c))
		for side: float in [-1.0, 1.0]:
			_bx(Vector3(length, 0.07, 0.07), c + Vector3(0, 1.0, side * 0.95), steel.lightened(0.3), "iron", b)
		_bx(Vector3(2.6, 0.25, 2.2), Vector3(x, y, zc), steel)
	# Advertising board on the side of the deck.
	_bx(Vector3(0.1, 1.2, 9.0), Vector3(x - 1.4, y - 0.5, rz), Color(0.95, 0.85, 0.2))
	var l:= _sign("SEEN SOMETHING? SNAP IT.", Vector3(x - 1.47, y - 0.5, rz), 70, Color(0.1, 0.08, 0.05), self, -PI * 0.5)
	l.outline_size = 0


func _build_park(r: Rect2) -> void:
	var path:= Color(0.5, 0.45, 0.36)
	var cx:= r.get_center()
	_fl(Vector2(r.size.x - 4.0, 2.6), Vector3(cx.x, 0.03, cx.y), path)
	_fl(Vector2(2.6, r.size.y - 4.0), Vector3(cx.x, 0.03, cx.y), path)
	# Fountain in the middle.
	var stone:= _mat(Color(0.55, 0.53, 0.5), 0.85)
	_cyl(4.0, 0.6, Vector3(cx.x, 0.3, cx.y), stone)
	var pool:= _cyl(3.7, 0.1, Vector3(cx.x, 0.58, cx.y), _mat(Color(0.12, 0.25, 0.35), 0.05))
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cyl(0.35, 1.8, Vector3(cx.x, 1.3, cx.y), stone)
	_cyl(1.1, 0.2, Vector3(cx.x, 2.2, cx.y), stone)
	var cs:= CollisionShape3D.new()
	var cyl:= CylinderShape3D.new()
	cyl.radius = 4.0
	cyl.height = 1.2
	cs.shape = cyl
	cs.position = Vector3(cx.x, 0.3, cx.y)
	_colliders.add_child(cs)
	_park_greenery(r, cx, 26, 18, 7.0)
	for k in 4:
		var a:= TAU * k / 4.0 + PI * 0.25
		_bench(Vector3(cx.x + cos(a) * 8.0, 0, cx.y + sin(a) * 8.0), -a + PI * 0.5)
	_hedge_border(r)
	for corner: Vector2 in [Vector2(r.position.x + 1.5, r.position.y + 1.5), Vector2(r.end.x - 1.5, r.position.y + 1.5),
			Vector2(r.position.x + 1.5, r.end.y - 1.5), Vector2(r.end.x - 1.5, r.end.y - 1.5)]:
		_lamp_spots.append(Vector3(corner.x, 0, corner.y))


## Trees and hide-able bushes round a park, away from the paths.
func _park_greenery(r: Rect2, cx: Vector2, trees: int, bushes: int, keep_r: float) -> void:
	var tree_xf: Array[Transform3D] = []
	var bush_xf: Array[Transform3D] = []
	for _i in trees:
		var p:= Vector2(rng.randf_range(r.position.x + 3, r.end.x - 3), rng.randf_range(r.position.y + 3, r.end.y - 3))
		if absf(p.x - cx.x) < 3.0 or absf(p.y - cx.y) < 3.0 or p.distance_to(cx) < keep_r:
			continue
		var s:= rng.randf_range(0.75, 1.0)
		tree_xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, 0, p.y)))
	for _i in bushes:
		var p:= Vector2(rng.randf_range(r.position.x + 2.5, r.end.x - 2.5), rng.randf_range(r.position.y + 2.5, r.end.y - 2.5))
		if absf(p.x - cx.x) < 2.5 or absf(p.y - cx.y) < 2.5 or p.distance_to(cx) < keep_r - 1.0:
			continue
		var s:= rng.randf_range(0.9, 1.3)
		bush_xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, 0, p.y)))
		hides.append({"pos": p, "radius": 1.0 * s})
	_add_trees(tree_xf)
	if bush_xf.is_empty():
		return
	var mm:= MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = PlantMeshes.bush(1)
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


## Low clipped hedges round a park's edge, with gaps where the paths come in.
func _hedge_border(r: Rect2) -> void:
	var g:= Color(0.16, 0.34, 0.15)
	var cx:= r.get_center()
	for z: float in [r.position.y + 0.9, r.end.y - 0.9]:
		for half in 2:
			var x0:= r.position.x + 1.0 if half == 0 else cx.x + 2.5
			var x1:= cx.x - 2.5 if half == 0 else r.end.x - 1.0
			_bx(Vector3(x1 - x0, 0.9, 0.9), Vector3((x0 + x1) * 0.5, 0.45, z), g)
	for x: float in [r.position.x + 0.9, r.end.x - 0.9]:
		for half in 2:
			var z0:= r.position.y + 1.0 if half == 0 else cx.y + 2.5
			var z1:= cx.y - 2.5 if half == 0 else r.end.y - 1.0
			_bx(Vector3(0.9, 0.9, z1 - z0), Vector3(x, 0.45, (z0 + z1) * 0.5), g)


## A playground: swings that sway on their own (it's that kind of night), a slide,
## a see-saw, a sandpit, a climbing frame, benches for the parents who aren't there.
func _build_playground(r: Rect2) -> void:
	var cx:= r.get_center()
	_fl(Vector2(22.0, 16.0), Vector3(cx.x, 0.03, cx.y), Color(0.6, 0.34, 0.24))   # rubber matting
	_fl(Vector2(r.size.x - 4.0, 2.4), Vector3(cx.x, 0.028, r.position.y + 4.0), Color(0.5, 0.45, 0.36))
	var red:= Color(0.85, 0.2, 0.15)
	var blue:= Color(0.2, 0.4, 0.8)
	var yel:= Color(0.95, 0.78, 0.15)
	# Swing set: A-frames, top bar, two swings on a slowly rocking pivot.
	var sx:= cx.x - 6.0
	var sz:= cx.y - 3.0
	for ex: float in [-2.6, 2.6]:
		for lean: float in [-1.0, 1.0]:
			_bx(Vector3(0.12, 3.3, 0.12), Vector3(sx + ex, 1.55, sz + lean * 0.55), blue, "iron", Basis(Vector3.RIGHT, lean * 0.33))
	_cy(0.07, 5.4, Vector3(sx, 3.1, sz), blue, "iron", Basis(Vector3.FORWARD, PI * 0.5))
	for k in 2:
		var pivot:= Node3D.new()
		pivot.position = Vector3(sx - 1.2 + k * 2.4, 3.05, sz)
		add_child(pivot)
		var chain:= _mat(Color(0.6, 0.6, 0.62), 0.4)
		for cxo: float in [-0.25, 0.25]:
			_box(Vector3(0.03, 2.4, 0.03), Vector3(cxo, -1.2, 0), chain, false, pivot)
		_box(Vector3(0.6, 0.05, 0.25), Vector3(0, -2.42, 0), _mat(Color(0.1, 0.1, 0.1), 0.8), false, pivot)
		var tw:= pivot.create_tween().set_loops()
		tw.tween_property(pivot, "rotation:x", 0.22 + k * 0.08, 1.4 + k * 0.2).set_trans(Tween.TRANS_SINE)
		tw.tween_property(pivot, "rotation:x", -0.22 - k * 0.08, 1.4 + k * 0.2).set_trans(Tween.TRANS_SINE)
	# Slide: ladder, platform with a little roof, sloped chute.
	var px:= cx.x + 5.0
	var pz:= cx.y - 2.0
	for dx: float in [-0.6, 0.6]:
		for dz: float in [-0.6, 0.6]:
			_cy(0.06, 2.6, Vector3(px + dx, 1.3, pz + dz), yel, "iron")
	_bx(Vector3(1.4, 0.1, 1.4), Vector3(px, 1.8, pz), red)
	var roof:= MeshInstance3D.new()
	var pm:= PrismMesh.new()
	pm.size = Vector3(1.6, 0.7, 1.6)
	roof.mesh = pm
	roof.material_override = _mat(red, 0.6)
	roof.position = Vector3(px, 2.95, pz)
	add_child(roof)
	for k in 5:
		_bx(Vector3(0.6, 0.05, 0.05), Vector3(px - 0.95, 0.35 + k * 0.35, pz), yel, "iron")
	var chute_b:= Basis(Vector3(0, 0, 1), -atan2(1.8, 3.2))
	_bx(Vector3(3.7, 0.08, 0.7), Vector3(px + 0.7 + 1.6, 0.95, pz), blue, "chrome", chute_b)
	for s: float in [-0.35, 0.35]:
		_bx(Vector3(3.7, 0.22, 0.05), Vector3(px + 0.7 + 1.6, 1.05, pz + s), blue, "chrome", chute_b)
	_solid(Vector3(1.4, 1.8, 1.4), Transform3D(Basis.IDENTITY, Vector3(px, 0.9, pz)), true)
	# See-saw.
	_bx(Vector3(0.3, 0.5, 0.3), Vector3(cx.x - 2.0, 0.25, cx.y + 4.5), Color(0.3, 0.3, 0.32), "iron")
	_bx(Vector3(4.0, 0.1, 0.3), Vector3(cx.x - 2.0, 0.55, cx.y + 4.5), yel, "box", Basis(Vector3(0, 0, 1), 0.14))
	# Sandpit and a dome climbing frame.
	_bx(Vector3(4.0, 0.3, 4.0), Vector3(cx.x + 5.5, 0.15, cx.y + 4.5), Color(0.45, 0.3, 0.2), "wood")
	_fl(Vector2(3.6, 3.6), Vector3(cx.x + 5.5, 0.31, cx.y + 4.5), Color(0.85, 0.75, 0.5))
	for k in 8:
		var a:= TAU * k / 8.0
		_bx(Vector3(0.06, 2.6, 0.06), Vector3(cx.x + 0.5 + cos(a) * 0.9, 1.1, cx.y + 6.5 + sin(a) * 0.9), red, "iron",
			Basis(Vector3(-sin(a), 0, cos(a)), 0.55))
	for k in 3:
		var bench_x:= cx.x - 9.0 + k * 9.0
		_bench(Vector3(bench_x, 0, r.end.y - 4.0), 0.0)
	_park_greenery(r, cx, 14, 12, 12.0)
	_hedge_border(r)
	for corner: Vector2 in [Vector2(r.position.x + 1.5, r.position.y + 1.5), Vector2(r.end.x - 1.5, r.end.y - 1.5)]:
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
	var b:= Basis(Vector3.UP, yaw)
	var wood:= Color(0.45, 0.3, 0.16)
	var iron:= Color(0.12, 0.12, 0.13)
	_bx(Vector3(1.8, 0.08, 0.45), p + b * Vector3(0, 0.45, 0), wood, "wood", b)
	_bx(Vector3(1.8, 0.4, 0.06), p + b * Vector3(0, 0.75, -0.22), wood, "wood", b)
	for x: float in [-0.8, 0.8]:
		_bx(Vector3(0.06, 0.45, 0.45), p + b * Vector3(x, 0.22, 0), iron, "iron", b)


func _build_parking_lot(r: Rect2, tailgate: bool) -> void:
	_fl(Vector2(r.size.x - 1.0, r.size.y - 1.0), Vector3(r.get_center().x, 0.025, r.get_center().y), Color(0.15, 0.15, 0.16))
	var white:= Color(0.85, 0.85, 0.8)
	var x:= r.position.x + 3.0
	while x < r.end.x - 2.0:
		_fl(Vector2(0.15, 5.0), Vector3(x, 0.04, r.position.y + 4.0), white, "white")
		_fl(Vector2(0.15, 5.0), Vector3(x, 0.04, r.end.y - 4.0), white, "white")
		x += 3.0
	# Parked cars in some bays (the tailgate party, if any, is in the middle).
	for k in 9:
		var bx:= r.position.x + 4.5 + float(rng.randi_range(0, int((r.size.x - 9.0) / 3.0))) * 3.0
		var bz:= r.position.y + 4.0 if k % 2 == 0 else r.end.y - 4.0
		_parked_car(Vector3(bx, 0, bz), PI * 0.5 + (PI if k % 2 == 0 else 0.0) + PI * 0.5, "")
	# Wheel stops and a pay booth.
	if not tailgate:
		_bx(Vector3(2.0, 2.4, 2.0), Vector3(r.end.x - 3.0, 1.2, r.get_center().y), Color(0.9, 0.85, 0.7))
		_bx(Vector3(2.3, 0.15, 2.3), Vector3(r.end.x - 3.0, 2.45, r.get_center().y), Color(0.75, 0.2, 0.15))
		_sign("PAY HERE", Vector3(r.end.x - 4.02, 1.7, r.get_center().y), 60, Color(0.1, 0.1, 0.1), self, -PI * 0.5).outline_size = 0
		_solid(Vector3(2.0, 2.4, 2.0), Transform3D(Basis.IDENTITY, Vector3(r.end.x - 3.0, 1.2, r.get_center().y)), true)
	_bollard_row(Vector2(r.position.x + 1.0, r.position.y + 0.6), Vector2(r.end.x - 1.0, r.position.y + 0.6), 2.5, false)
	for corner: Vector2 in [Vector2(r.position.x + 1.0, r.position.y + 1.0), Vector2(r.end.x - 1.0, r.end.y - 1.0), Vector2(r.position.x + 1.0, r.end.y - 1.0)]:
		_lamp_spots.append(Vector3(corner.x, 0, corner.y))


## A parked car, batched. kind: "" (random paint), "taxi", "police", "ambulance".
func _parked_car(p: Vector3, yaw: float, kind: String) -> void:
	if kind != "":
		_reserved.append(Rect2(p.x - 4.0, p.z - 4.0, 8.0, 8.0))
	var cols:= [Color(0.6, 0.08, 0.08), Color(0.1, 0.2, 0.5), Color(0.75, 0.75, 0.72), Color(0.08, 0.08, 0.09),
		Color(0.2, 0.4, 0.25), Color(0.8, 0.65, 0.2), Color(0.5, 0.52, 0.55), Color(0.35, 0.18, 0.4)]
	var paint: Color = cols[rng.randi() % cols.size()]
	if kind == "" and rng.randf() < 0.12:
		kind = "taxi"
	var b:= Basis(Vector3.UP, yaw)
	var at:= func(local: Vector3) -> Vector3: return p + b * local
	if kind == "ambulance":
		_bx(Vector3(2.2, 2.3, 5.6), at.call(Vector3(0, 1.5, -0.4)), Color(0.95, 0.95, 0.93), "paint", b)
		_bx(Vector3(2.1, 1.3, 1.5), at.call(Vector3(0, 1.0, 2.9)), Color(0.95, 0.95, 0.93), "paint", b)
		_bx(Vector3(2.22, 0.35, 5.62), at.call(Vector3(0, 1.4, -0.4)), Color(0.85, 0.1, 0.1), "paint", b)
		_bx(Vector3(1.9, 0.6, 0.05), at.call(Vector3(0, 1.3, 3.66)), Color(0.08, 0.1, 0.13), "glass", b)
		_bx(Vector3(0.5, 0.2, 0.3), at.call(Vector3(-0.5, 2.75, 2.0)), Color(1, 0.1, 0.1), "red_lamp", b)
		_bx(Vector3(0.5, 0.2, 0.3), at.call(Vector3(0.5, 2.75, 2.0)), Color(0.2, 0.4, 1), "blue_lamp", b)
		for wx: float in [-1.0, 1.0]:
			for wz: float in [-2.2, 2.4]:
				_cy(0.4, 0.3, at.call(Vector3(wx, 0.4, wz)), Color(0.06, 0.06, 0.06), "tyre", b * Basis(Vector3.FORWARD, PI * 0.5))
		_solid(Vector3(2.2, 2.6, 7.0), Transform3D(b, at.call(Vector3(0, 1.3, 0.3))), true)
		return
	if kind == "taxi":
		paint = Color(0.95, 0.75, 0.1)
	elif kind == "police":
		paint = Color(0.06, 0.07, 0.1)
	_bx(Vector3(1.8, 0.7, 4.2), at.call(Vector3(0, 0.6, 0)), paint, "paint", b)
	_bx(Vector3(1.6, 0.6, 2.1), at.call(Vector3(0, 1.22, -0.2)), Color(0.08, 0.1, 0.13), "glass", b)
	_bx(Vector3(1.5, 0.08, 2.0), at.call(Vector3(0, 1.55, -0.2)), paint, "paint", b)
	if kind == "police":
		_bx(Vector3(1.82, 0.3, 1.6), at.call(Vector3(0, 0.7, -0.3)), Color(0.92, 0.92, 0.95), "paint", b)
		_bx(Vector3(0.55, 0.15, 0.3), at.call(Vector3(-0.3, 1.66, -0.2)), Color(1, 0.1, 0.1), "red_lamp", b)
		_bx(Vector3(0.55, 0.15, 0.3), at.call(Vector3(0.3, 1.66, -0.2)), Color(0.2, 0.4, 1), "blue_lamp", b)
	elif kind == "taxi":
		_bx(Vector3(0.7, 0.25, 0.3), at.call(Vector3(0, 1.72, -0.2)), Color(1.0, 0.95, 0.75), "head", b)
		for s: float in [-1.0, 1.0]:
			for k in 4:
				_bx(Vector3(0.02, 0.12, 0.3), at.call(Vector3(s * 0.91, 0.75, -1.2 + k * 0.6 + (0.3 if k % 2 == 0 else 0.0))), Color(0.05, 0.05, 0.05), "box", b)
	for wx: float in [-0.85, 0.85]:
		for wz: float in [-1.35, 1.35]:
			_cy(0.33, 0.25, at.call(Vector3(wx, 0.33, wz)), Color(0.06, 0.06, 0.06), "tyre", b * Basis(Vector3.FORWARD, PI * 0.5))
	_bx(Vector3(1.5, 0.12, 0.05), at.call(Vector3(0, 0.75, 2.11)), Color(1.0, 0.95, 0.8), "chrome", b)
	_bx(Vector3(1.5, 0.1, 0.05), at.call(Vector3(0, 0.75, -2.11)), Color(0.9, 0.08, 0.05), "tail", b)
	_solid(Vector3(1.8, 1.4, 4.2), Transform3D(b, at.call(Vector3(0, 0.7, 0))), true)


## Cars parked along the curbs (both sides, with gaps; not in the moving lanes).
func _build_cars() -> void:
	for rx: float in NS_ROADS:
		var ext:= ns_extent(rx)
		for side: float in [-1.0, 1.0]:
			var z:= ext.x + 6.0
			while z < ext.y - 6.0:
				if not _near_ew(z, STREET_HALF + 4.0) and absf(z - OVERPASS_Z) > OVERPASS_HALF + 2.0 and not on_bridge(rx, z) \
						and absf(z - RIVER_Z) > 30.0 and rng.randf() < 0.32 and _kerb_free(Vector2(rx + side * PARK_LANE, z)):
					_parked_car(Vector3(rx + side * PARK_LANE, 0, z), 0.0 if side > 0 else PI, "")
				z += 6.5
	for rz: float in EW_ROADS:
		for side: float in [-1.0, 1.0]:
			var x:= -EDGE + 6.0
			while x < EDGE - 6.0:
				if not _near_ns(x, STREET_HALF + 4.0) and rng.randf() < 0.28 and _clear(Vector2(x, rz + side * 8.0)) \
						and not (rz == EW_ROADS[0] and absf(x) < 26.0) and _kerb_free(Vector2(x, rz + side * PARK_LANE)):
					_parked_car(Vector3(x, 0, rz + side * PARK_LANE), PI * 0.5 if side > 0 else -PI * 0.5, "")
				x += 6.5


func _kerb_free(p: Vector2) -> bool:
	for r in _reserved:
		if r.has_point(p):
			return false
	return true


func _build_sidewalk_trees() -> void:
	var xfs: Array[Transform3D] = []
	var pit:= Color(0.25, 0.18, 0.12)
	for rx: float in NS_ROADS:
		var ext:= ns_extent(rx)
		for side: float in [-1.0, 1.0]:
			var z:= ext.x + 8.0
			while z < ext.y - 4.0:
				var p:= Vector3(rx + side * (ROAD_HALF + 1.5), 0, z)
				if not _near_ew(z, STREET_HALF + 2.0) and absf(z - OVERPASS_Z) > OVERPASS_HALF + 2.0 and not on_bridge(rx, z) \
						and absf(z - RIVER_Z) > 20.0 and _sidewalk_ok(Vector2(p.x, p.z)):
					xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.62, 0.78)), p))
					_bx(Vector3(1.3, 0.16, 1.3), p + Vector3(0, 0.08, 0), pit)
				z += 13.0
	for rz: float in EW_ROADS:
		for side: float in [-1.0, 1.0]:
			var x:= -EDGE + 6.0
			while x < EDGE - 4.0:
				var p:= Vector3(x, 0, rz + side * (ROAD_HALF + 1.5))
				if not _near_ns(x, STREET_HALF + 2.0) and not (rz == EW_ROADS[0] and absf(x) < 26.0 and side > 0) and _sidewalk_ok(Vector2(p.x, p.z)):
					xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.62, 0.78)), p))
					_bx(Vector3(1.3, 0.16, 1.3), p + Vector3(0, 0.08, 0), pit)
				x += 14.0
	_add_trees(xfs)


func _build_lamps() -> void:
	for rx: float in NS_ROADS:
		var ext:= ns_extent(rx)
		for side: float in [-1.0, 1.0]:
			var z:= ext.x + 4.0 + (0.0 if side > 0 else 15.0)
			while z < ext.y - 2.0:
				var p:= Vector3(rx + side * (ROAD_HALF + 0.4), 0, z)
				if not _near_ew(z, STREET_HALF) and absf(z - OVERPASS_Z) > OVERPASS_HALF and _sidewalk_ok(Vector2(p.x, p.z)):
					_lamp_spots.append(p)
				z += 30.0
	for rz: float in EW_ROADS:
		for side: float in [-1.0, 1.0]:
			var x:= -EDGE + 8.0 + (0.0 if side > 0 else 15.0)
			while x < EDGE - 4.0:
				var p:= Vector3(x, 0, rz + side * (ROAD_HALF + 0.4))
				if not _near_ns(x, STREET_HALF) and _sidewalk_ok(Vector2(p.x, p.z)):
					_lamp_spots.append(p)
				x += 30.0
	var pole:= Color(0.14, 0.15, 0.17)
	var i:= 0
	for p in _lamp_spots:
		_cy(0.08, 6.0, p + Vector3(0, 3.0, 0), pole, "iron")
		_bx(Vector3(0.7, 0.18, 0.35), p + Vector3(0, 6.0, 0), pole, "iron")
		_bx(Vector3(0.5, 0.06, 0.25), p + Vector3(0, 5.89, 0), Color(1.0, 0.72, 0.4), "bulb")
		# Every other lamp actually lights the street (the bulbs all glow): halves the light count.
		if i % 2 == 0:
			var l:= OmniLight3D.new()
			l.light_color = Color(1.0, 0.68, 0.36)
			l.light_energy = 2.0
			l.omni_range = 16.0
			l.omni_attenuation = 1.3
			l.position = p + Vector3(0, 5.6, 0)
			add_child(l)
		i += 1
	# Fire hydrants on the corners, trash cans and newspaper boxes along the blocks.
	var red:= Color(0.75, 0.1, 0.08)
	for p in intersections():
		for corner: Vector2 in [Vector2(1, 1), Vector2(-1, -1)]:
			var hp:= Vector3(p.x + corner.x * (ROAD_HALF + 0.7), 0, p.y + corner.y * (ROAD_HALF + 1.2))
			if not _sidewalk_ok(Vector2(hp.x, hp.z)):
				continue
			_cy(0.16, 0.6, hp + Vector3(0, 0.3, 0), red, "chrome")
			_cy(0.12, 0.12, hp + Vector3(0, 0.66, 0), red, "chrome")
			_cy(0.06, 0.4, hp + Vector3(0, 0.38, 0), red, "chrome", Basis(Vector3.FORWARD, PI * 0.5))
		var tc:= Vector3(p.x - (ROAD_HALF + 0.8), 0, p.y + ROAD_HALF + 3.5)
		if _sidewalk_ok(Vector2(tc.x, tc.z)):
			_cy(0.3, 0.9, tc + Vector3(0, 0.45, 0), Color(0.2, 0.3, 0.22), "iron")
		var nb:= Vector3(p.x + ROAD_HALF + 0.8, 0, p.y - ROAD_HALF - 4.0)
		if _sidewalk_ok(Vector2(nb.x, nb.z)):
			for k in 3:
				_bx(Vector3(0.5, 1.0, 0.45), nb + Vector3(0, 0.5, k * 0.55), [Color(0.2, 0.35, 0.7), Color(0.8, 0.2, 0.15), Color(0.9, 0.75, 0.2)][k], "paint")


## Arm-pole traffic lights at every crossing; the lamps share six materials that Traffic
## switches, so the whole city changes together (a green wave down every avenue).
func _build_traffic_lights() -> void:
	var pole:= Color(0.16, 0.17, 0.18)
	var housing:= Color(0.12, 0.12, 0.08)
	var lamps: Dictionary = {}
	for k in ["ns_r", "ns_y", "ns_g", "ew_r", "ew_y", "ew_g"]:
		lamps[k] = []
	for p in intersections():
		var ext:= ns_extent(p.x)
		# [corner offset, arm direction, axis of the traffic it faces, facing]
		var poles:= [
			[Vector2(1, 1), Vector3(-1, 0, 0), "ns", Vector3(0, 0, 1)],    # northbound traffic (comes from +z)
			[Vector2(-1, -1), Vector3(1, 0, 0), "ns", Vector3(0, 0, -1)],  # southbound
			[Vector2(-1, 1), Vector3(0, 0, -1), "ew", Vector3(-1, 0, 0)],  # eastbound (comes from -x)
			[Vector2(1, -1), Vector3(0, 0, 1), "ew", Vector3(1, 0, 0)],    # westbound
		]
		for pl: Array in poles:
			var c: Vector2 = pl[0]
			var base:= Vector3(p.x + c.x * (ROAD_HALF + 0.6), 0, p.y + c.y * (ROAD_HALF + 0.6))
			if not _sidewalk_ok(Vector2(base.x, base.z)):
				continue
			if pl[2] == "ns" and (p.y + c.y * 12.0 < ext.x or p.y + c.y * 12.0 > ext.y):
				continue   # no street coming in from that side
			var arm: Vector3 = pl[1]
			var face: Vector3 = pl[3]
			_cy(0.12, 6.4, base + Vector3(0, 3.2, 0), pole, "iron")
			var arm_len:= 4.6
			var arm_c:= base + Vector3(0, 6.1, 0) + arm * arm_len * 0.5
			_bx(Vector3(absf(arm.x) * arm_len + 0.12, 0.12, absf(arm.z) * arm_len + 0.12), arm_c, pole, "iron")
			var head:= base + Vector3(0, 5.5, 0) + arm * (arm_len - 0.4)
			var hb:= Basis.looking_at(-face, Vector3.UP)
			_bx(Vector3(0.42, 1.3, 0.32), head, housing, "box", hb)
			for li in 3:
				var lp:= head + Vector3(0, 0.4 - li * 0.4, 0) + face * 0.17
				lamps["%s_%s" % [pl[2], ["r", "y", "g"][li]]].append(Transform3D(hb * Basis.from_scale(Vector3(0.24, 0.24, 0.06)), lp))
				# Visor over each lamp.
				_bx(Vector3(0.3, 0.04, 0.16), lp + Vector3(0, 0.16, 0) + face * 0.06, housing, "box", hb)
			# Pedestrian "walk" box lower on the pole.
			_bx(Vector3(0.3, 0.35, 0.22), base + Vector3(0, 2.6, 0) + face * 0.15, housing, "box", hb)
	traffic.make_light_meshes(self, lamps)


## Wooden power poles with sagging wires along the rowhouse street and the riverside drive.
func _build_power_lines() -> void:
	var wood:= Color(0.32, 0.24, 0.17)
	var wire:= Color(0.05, 0.05, 0.05)
	for rz: float in [EW_ROADS[0] + ROAD_HALF + 2.4, EW_ROADS[4] - ROAD_HALF - 2.4, EW_ROADS[3] + ROAD_HALF + 2.4]:
		var prev:= Vector3.INF
		var x:= -EDGE + 4.0
		while x < EDGE - 2.0:
			if _near_ns(x, STREET_HALF + 0.5) or not _sidewalk_ok(Vector2(x, rz)):
				x += 4.0
				continue
			var p:= Vector3(x, 0, rz)
			_cy(0.14, 9.0, p + Vector3(0, 4.5, 0), wood, "wood")
			_bx(Vector3(0.12, 0.14, 2.2), p + Vector3(0, 8.4, 0), wood, "wood")
			for k in 3:
				_cy(0.05, 0.16, p + Vector3(0, 8.55, -0.9 + k * 0.9), Color(0.75, 0.75, 0.7), "chrome")
			if rng.randf() < 0.3:
				_cy(0.28, 0.8, p + Vector3(0.35, 7.3, 0), Color(0.45, 0.46, 0.45), "chrome")   # transformer
			if prev != Vector3.INF and p.x - prev.x < 45.0:
				for k in 3:
					var a:= prev + Vector3(0, 8.6, -0.9 + k * 0.9)
					var b:= p + Vector3(0, 8.6, -0.9 + k * 0.9)
					var sag:= (a + b) * 0.5 - Vector3(0, 0.7, 0)
					for half in 2:
						var e:= a if half == 0 else b
						var seg:= sag - e
						var bb:= Basis.looking_at(seg.normalized(), Vector3.UP)
						_inst("iron", Transform3D(bb * Basis.from_scale(Vector3(0.035, 0.035, seg.length())), (e + sag) * 0.5), wire)
			prev = p
			x += 32.0


## Food stands, a taco truck and a newspaper kiosk ("THE DAILY CRYPTID"), dumpsters, a bus stop.
func _build_stands() -> void:
	var r2:= EW_ROADS[2]
	_hotdog_cart(Vector3(16.0, 0, r2 + 8.0), PI)
	_kiosk(Vector3(-16.0, 0, r2 + 8.0), "PRETZELS", Color(0.85, 0.45, 0.1), PI)
	_newsstand(Vector3(14.0, 0, EW_ROADS[3] + 8.0), PI)
	_food_truck(Vector3(-10.0, 0, -82.0), PI * 0.5)
	_hotdog_cart(Vector3(-22.0, 0, -76.0), PI)
	_kiosk(Vector3(70.0, 0, r2 - 8.0), "COFFEE", Color(0.35, 0.22, 0.15), 0.0)
	_kiosk(Vector3(-72.0, 0, EW_ROADS[1] - 8.0), "BAGELS", Color(0.75, 0.6, 0.35), 0.0)
	_hotdog_cart(Vector3(40.0, 0, EW_ROADS[1] - 8.0), 0.0)
	_bus_stop(Vector3(-96.0, 0, EW_ROADS[1] + 8.2), PI)
	_bus_stop(Vector3(96.0, 0, EW_ROADS[3] - 8.2), 0.0)
	var green:= Color(0.12, 0.3, 0.18)
	for p: Vector3 in [Vector3(-75, 0, OVERPASS_Z + 6.5), Vector3(40, 0, OVERPASS_Z - 6.5), Vector3(-128, 0, 25.0),
			Vector3(105, 0, 82.5), Vector3(-27, 0, 82.5), Vector3(135, 0, -32.5), Vector3(-140, 0, 137.5),
			Vector3(140, 0, 26.0), Vector3(-66, 0, -32.5)]:
		if blocked(Vector2(p.x, p.z)):
			continue
		_bx(Vector3(2.0, 1.3, 1.2), p + Vector3(0, 0.65, 0), green)
		_bx(Vector3(2.05, 0.1, 1.25), p + Vector3(0, 1.32, 0), Color(0.08, 0.2, 0.12))
		_solid(Vector3(2.0, 1.3, 1.2), Transform3D(Basis.IDENTITY, p + Vector3(0, 0.65, 0)), true)
		var off:= 1.3 if _near_street(p.x, p.z + 1.3, STREET_HALF) else -1.3
		hides.append({"pos": Vector2(p.x, p.z + off), "radius": 1.1})


func _bus_stop(p: Vector3, yaw: float) -> void:
	var n:= Node3D.new()
	n.position = p
	n.rotation.y = yaw
	add_child(n)
	var glass:= _mat(Color(0.6, 0.75, 0.85, 0.3), 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var frame:= _mat(Color(0.2, 0.22, 0.25), 0.5)
	_box(Vector3(4.0, 2.4, 0.05), Vector3(0, 1.3, -0.6), glass, false, n)
	_box(Vector3(0.05, 2.4, 1.2), Vector3(-2.0, 1.3, 0), glass, false, n)
	_box(Vector3(4.2, 0.1, 1.5), Vector3(0, 2.55, 0), frame, false, n)
	_box(Vector3(3.0, 0.08, 0.4), Vector3(0, 0.5, -0.35), _mat(Color(0.35, 0.36, 0.38), 0.5), false, n)
	_box(Vector3(0.1, 2.8, 0.1), Vector3(2.4, 1.4, 0.5), frame, false, n)
	_box(Vector3(0.6, 0.6, 0.05), Vector3(2.4, 2.9, 0.5), _mat(Color(0.1, 0.3, 0.7), 0.5), false, n)
	_sign("BUS", Vector3(2.4, 2.9, 0.53), 60, Color(1, 1, 1), n)
	_box(Vector3(1.3, 1.7, 0.03), Vector3(1.2, 1.3, -0.57), _mat(Color(0.95, 0.9, 0.7), 0.6, 0.4), false, n)
	_sign("HAVE YOU SEEN\nTHIS MAN?\n(he's 9ft tall)", Vector3(1.2, 1.4, -0.55), 34, Color(0.15, 0.1, 0.05), n).outline_size = 0
	_collide_box(n, Vector3(4.0, 2.4, 0.1), Vector3(0, 1.3, -0.6))


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
	_fl(Vector2(CAMP_LOT.size.x, CAMP_LOT.size.y), Vector3(CAMP_LOT.get_center().x, 0.02, CAMP_LOT.get_center().y), Color(0.3, 0.29, 0.27))
	var fence:= _mat(Color(0.55, 0.57, 0.6), 0.4)
	fence.metallic = 0.7
	fence.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fence.albedo_color.a = 0.55
	_box(Vector3(CAMP_LOT.size.x, 2.2, 0.05), Vector3(CAMP_LOT.get_center().x, 1.1, FENCE_Z), fence)
	for x in range(int(CAMP_LOT.position.x), int(CAMP_LOT.end.x) + 1, 4):
		_cy(0.05, 2.3, Vector3(float(x), 1.15, FENCE_Z), Color(0.5, 0.5, 0.52), "chrome")


# ------------------------------------------------------------------ pedestrians

## Ordinary people walking the sidewalks. They ignore cryptids (city folk have seen it all).
func spawn_pedestrians(parent: Node, player: Node3D) -> Array:
	var out: Array = []
	var r:= RandomNumberGenerator.new()
	r.seed = int(Time.get_ticks_usec())
	for i in 30:
		var ped:= Pedestrian.new()
		ped.city = self
		ped.model_path = "res://models/ped_suit.glb" if i % 2 == 0 else "res://models/ped_hoodie.glb"
		ped.player = player
		parent.add_child(ped)
		ped.start(r)
		out.append(ped)
	if traffic != null:
		traffic.pedestrians = out
	return out


## Sidewalk points along streets for pedestrians: [a, b] pairs (the building side of the
## sidewalk, clear of lamps, trees and the footbridge stairs).
func sidewalk_lines() -> Array:
	var lines: Array = []
	for rx: float in NS_ROADS:
		var ext:= ns_extent(rx)
		for side: float in [-1.0, 1.0]:
			var x: float = rx + side * (ROAD_HALF + 2.4)
			lines.append([Vector2(x, maxf(ext.x, EW_ROADS[4] - 4.0)), Vector2(x, minf(ext.y, EW_ROADS[0] + 8.0))])
	for rz: float in EW_ROADS:
		for side: float in [-1.0, 1.0]:
			var z: float = rz + side * (ROAD_HALF + 2.4)
			lines.append([Vector2(-EDGE + 6.0, z), Vector2(EDGE - 6.0, z)])
	return lines
