extends Node3D
class_name Traffic
## The City's moving traffic and its traffic lights.
## Cars drive loops round the blocks, keeping right. They stop at red lights (every crossing
## shares one cycle, a green wave), brake for anyone in the road (you, pedestrians, cryptids)
## and lean on the horn if it's you standing there. Cars are solid to you (collision layer 2,
## like the parked ones) but cryptids slip past them, so a chase never snags on a taxi.
## Purely local scenery: in multiplayer every machine runs its own traffic.

const SPEED:= 9.0
const CYCLE:= 28.0
const LIGHT_COLS:= {"r": Color(1.0, 0.12, 0.08), "y": Color(1.0, 0.72, 0.1), "g": Color(0.2, 1.0, 0.45)}
const PAINTS:= [Color(0.6, 0.08, 0.08), Color(0.1, 0.2, 0.5), Color(0.75, 0.75, 0.72), Color(0.08, 0.08, 0.09),
	Color(0.2, 0.4, 0.25), Color(0.5, 0.52, 0.55), Color(0.35, 0.18, 0.4), Color(0.85, 0.45, 0.12)]

var city: CityBlocks
var pedestrians: Array = []
var cars: Array = []
var _clock:= 0.0
var _lamp_mats: Dictionary = {}
var _phase_key:= ""
var _flash:= 0.0
var _rng:= RandomNumberGenerator.new()
var _crossings: Array[Vector2] = []


## Which light an axis ("ns" / "ew") shows at time t: "g", "y" or "r".
static func light(t: float, axis: String) -> String:
	t = fposmod(t, CYCLE)
	if axis == "ns":
		if t < 10.0:
			return "g"
		if t < 13.0:
			return "y"
		return "r"
	if t >= 14.0 and t < 24.0:
		return "g"
	if t >= 24.0 and t < 27.0:
		return "y"
	return "r"


## Right-hand side of a direction of travel on the ground plane (x, z).
static func right_of(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)


## A loop round the rectangle x0..x1, z0..z1 in the right-hand lane. dir 1 or -1.
static func ring_path(x0: float, x1: float, z0: float, z1: float, dir: int) -> PackedVector2Array:
	var c:= [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]
	if dir < 0:
		c.reverse()
	var out:= PackedVector2Array()
	var n:= c.size()
	for i in n:
		var prev: Vector2 = c[(i - 1 + n) % n]
		var cur: Vector2 = c[i]
		var nxt: Vector2 = c[(i + 1) % n]
		var din:= (cur - prev).normalized()
		var dout:= (nxt - cur).normalized()
		out.append(cur + right_of(din) * CityBlocks.LANE + right_of(dout) * CityBlocks.LANE)
	return out


## The six lamp MultiMeshes (red/amber/green for each axis), drawn on the city node.
func make_light_meshes(parent: Node3D, lamps: Dictionary) -> void:
	for key in lamps:
		var xfs: Array = lamps[key]
		var mat:= StandardMaterial3D.new()
		mat.albedo_color = Color(0.08, 0.08, 0.08)
		mat.emission_enabled = true
		mat.emission = LIGHT_COLS[str(key).right(1)]
		mat.emission_energy_multiplier = 0.0
		_lamp_mats[key] = mat
		var mm:= MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var bm:= BoxMesh.new()
		bm.size = Vector3.ONE
		mm.mesh = bm
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi:= MultiMeshInstance3D.new()
		mmi.name = "Lights_" + str(key)
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
	_update_lamps()


func build_loops() -> void:
	_rng.seed = 777
	_crossings = CityBlocks.intersections()
	var ns:= CityBlocks.NS_ROADS
	var ew:= CityBlocks.EW_ROADS
	var rings:= [
		[ns[0], ns[4], ew[1], ew[3], 1, 4],
		[ns[0], ns[4], ew[1], ew[3], -1, 4],
		[ns[1], ns[3], ew[0], ew[2], 1, 3],
		[ns[2], ns[4], ew[2], ew[4], -1, 3],
		[ns[0], ns[2], ew[3], ew[4], 1, 2],
	]
	for ring: Array in rings:
		var path:= ring_path(ring[0], ring[1], ring[2], ring[3], ring[4])
		var total:= 0.0
		for i in path.size():
			total += path[i].distance_to(path[(i + 1) % path.size()])
		for k in int(ring[5]):
			var at:= total * (float(k) + _rng.randf_range(0.0, 0.4)) / float(ring[5])
			_add_car(path, at, "taxi" if _rng.randf() < 0.35 else "")


func _add_car(path: PackedVector2Array, at: float, kind: String) -> void:
	var seg:= 0
	while at > path[seg].distance_to(path[(seg + 1) % path.size()]):
		at -= path[seg].distance_to(path[(seg + 1) % path.size()])
		seg = (seg + 1) % path.size()
	var body:= AnimatableBody3D.new()
	body.name = "Car%d" % cars.size()
	body.collision_layer = CityBlocks.PROPS_LAYER
	body.collision_mask = 0
	body.sync_to_physics = false
	var cs:= CollisionShape3D.new()
	var bs:= BoxShape3D.new()
	bs.size = Vector3(1.8, 1.4, 4.2)
	cs.shape = bs
	cs.position = Vector3(0, 0.7, 0)
	body.add_child(cs)
	_build_car_model(body, kind)
	add_child(body)
	var car:= {"body": body, "path": path, "seg": seg, "u": at, "speed": SPEED * 0.6, "yaw": 0.0,
		"honk": 0.0, "stuck": 0.0, "ghost": 0.0}
	var a:= path[seg]
	var b:= path[(seg + 1) % path.size()]
	var d:= (b - a).normalized()
	car["yaw"] = atan2(d.x, d.y)
	_place(car, a + d * at)
	cars.append(car)


func _build_car_model(body: Node3D, kind: String) -> void:
	var paint_c: Color = PAINTS[_rng.randi() % PAINTS.size()]
	if kind == "taxi":
		paint_c = Color(0.95, 0.75, 0.1)
	var paint:= StandardMaterial3D.new()
	paint.albedo_color = paint_c
	paint.roughness = 0.3
	paint.metallic = 0.5
	var glass:= StandardMaterial3D.new()
	glass.albedo_color = Color(0.08, 0.1, 0.13)
	glass.roughness = 0.08
	glass.metallic = 0.3
	var tyre:= StandardMaterial3D.new()
	tyre.albedo_color = Color(0.06, 0.06, 0.06)
	var head:= StandardMaterial3D.new()
	head.albedo_color = Color(1.0, 0.95, 0.8)
	head.emission_enabled = true
	head.emission = Color(1.0, 0.95, 0.8)
	head.emission_energy_multiplier = 3.0
	var tail:= StandardMaterial3D.new()
	tail.albedo_color = Color(0.9, 0.08, 0.05)
	tail.emission_enabled = true
	tail.emission = Color(0.9, 0.08, 0.05)
	tail.emission_energy_multiplier = 2.0
	var box:= func(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
		var mi:= MeshInstance3D.new()
		var bm:= BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = mat
		mi.position = pos
		body.add_child(mi)
		return mi
	box.call(Vector3(1.8, 0.7, 4.2), Vector3(0, 0.6, 0), paint)
	box.call(Vector3(1.6, 0.6, 2.1), Vector3(0, 1.22, -0.2), glass)
	box.call(Vector3(1.5, 0.08, 2.0), Vector3(0, 1.55, -0.2), paint)
	for wx: float in [-0.85, 0.85]:
		for wz: float in [-1.35, 1.35]:
			var w:= MeshInstance3D.new()
			var cm:= CylinderMesh.new()
			cm.top_radius = 0.33
			cm.bottom_radius = 0.33
			cm.height = 0.25
			cm.radial_segments = 10
			w.mesh = cm
			w.material_override = tyre
			w.position = Vector3(wx, 0.33, wz)
			w.rotation.z = PI * 0.5
			body.add_child(w)
	for sx: float in [-0.55, 0.55]:
		box.call(Vector3(0.36, 0.14, 0.05), Vector3(sx, 0.75, 2.11), head)
		box.call(Vector3(0.36, 0.12, 0.05), Vector3(sx, 0.75, -2.11), tail)
	if kind == "taxi":
		box.call(Vector3(0.8, 0.26, 0.32), Vector3(0, 1.72, -0.2), head)
		var l:= Label3D.new()
		l.text = "TAXI"
		l.font = load("res://fonts/Oswald.ttf")
		l.font_size = 48
		l.pixel_size = 0.004
		l.modulate = Color(0.1, 0.08, 0.02)
		l.outline_size = 0
		l.position = Vector3(0, 1.72, -0.03)
		l.shaded = false
		body.add_child(l)
	var lamp:= SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.92, 0.75)
	lamp.light_energy = 2.5
	lamp.spot_range = 22.0
	lamp.spot_angle = 32.0
	lamp.position = Vector3(0, 0.8, 2.2)
	lamp.rotation.x = -0.12
	lamp.rotation.y = PI   # spot lights shine down -Z; the car's nose is +Z
	body.add_child(lamp)


func _place(car: Dictionary, p: Vector2) -> void:
	var body: AnimatableBody3D = car["body"]
	body.transform = Transform3D(Basis(Vector3.UP, float(car["yaw"])), Vector3(p.x, 0.0, p.y))


func _physics_process(delta: float) -> void:
	_clock += delta
	_update_lamps()
	_flash_emergency(delta)
	var people: Array = []
	for n in get_tree().get_nodes_in_group("traffic_stop"):
		var n3:= n as Node3D
		if n3 != null and n3.visible:
			people.append([Vector2(n3.global_position.x, n3.global_position.z), n3 is Player])
	for p in pedestrians:
		if is_instance_valid(p):
			people.append([Vector2(p.global_position.x, p.global_position.z), false])
	for car in cars:
		_drive(car, delta, people)


func _update_lamps() -> void:
	var ns:= light(_clock, "ns")
	var ew:= light(_clock, "ew")
	var key:= ns + ew
	if key == _phase_key or _lamp_mats.is_empty():
		return
	_phase_key = key
	for axis in ["ns", "ew"]:
		var on:= ns if axis == "ns" else ew
		for c: String in ["r", "y", "g"]:
			var m: StandardMaterial3D = _lamp_mats.get("%s_%s" % [axis, c])
			if m == null:
				continue
			var lit: bool = c == on
			m.emission_energy_multiplier = 4.0 if lit else 0.0
			m.albedo_color = (LIGHT_COLS[c] as Color) if lit else Color(0.08, 0.08, 0.08)


## Police and ambulance light bars (and the blue lamp outside the station) flash.
func _flash_emergency(delta: float) -> void:
	if city == null:
		return
	_flash += delta
	var red: StandardMaterial3D = city._mats.get("red_lamp")
	var blue: StandardMaterial3D = city._mats.get("blue_lamp")
	if red == null or blue == null:
		return
	var on:= int(_flash / 0.35) % 2 == 0
	red.emission_enabled = true
	blue.emission_enabled = true
	blue.emission = Color(0.2, 0.4, 1.0)
	red.emission_energy_multiplier = 3.0 if on else 0.2
	blue.emission_energy_multiplier = 0.2 if on else 3.0


## How far ahead the car must stop for a light (INF if it can go).
func _light_stop(pos: Vector2, d: Vector2) -> float:
	var best_ahead:= INF
	var best: Vector2
	for c in _crossings:
		var rel:= c - pos
		var ahead:= rel.dot(d)
		var lat:= absf(rel.x * d.y - rel.y * d.x)
		if lat < 4.5 and ahead > 0.0 and ahead < best_ahead:
			best_ahead = ahead
			best = c
	if best_ahead == INF:
		return INF
	var s:= best_ahead - (CityBlocks.ROAD_HALF + 4.6)
	if s < -0.3 or s > 30.0:
		return INF
	var l:= light(_clock, "ns" if absf(d.y) > 0.5 else "ew")
	if l == "r" or (l == "y" and s > 3.0):
		return s
	return INF


func _drive(car: Dictionary, delta: float, people: Array) -> void:
	var path: PackedVector2Array = car["path"]
	var n:= path.size()
	var seg: int = car["seg"]
	var a:= path[seg]
	var b:= path[(seg + 1) % n]
	var seg_len:= maxf(0.01, a.distance_to(b))
	var d:= (b - a) / seg_len
	var pos:= a + d * float(car["u"])
	var target:= SPEED
	var stop_s:= _light_stop(pos, d)
	if stop_s < INF:
		target = minf(target, _brake(stop_s - 0.5))
	var for_you:= false
	for pr: Array in people:
		var rel: Vector2 = pr[0] - pos
		var ahead:= rel.dot(d)
		var lat:= absf(rel.x * d.y - rel.y * d.x)
		if ahead > 0.0 and ahead < 16.0 and lat < 1.9:
			var gap:= ahead - 2.8
			target = minf(target, _brake(gap - 1.2))
			if pr[1] and gap < 6.0:
				for_you = true
	var by_car:= false
	if float(car["ghost"]) <= 0.0:
		for other in cars:
			if other == car:
				continue
			var op:= _pos_of(other)
			var rel:= op - pos
			var ahead:= rel.dot(d)
			var lat:= absf(rel.x * d.y - rel.y * d.x)
			if ahead > 0.0 and ahead < 14.0 and lat < 1.5:
				var gap:= ahead - 4.6
				var t2:= _brake(gap - 0.8)
				if t2 < target:
					target = t2
					by_car = true
	else:
		car["ghost"] = float(car["ghost"]) - delta
	var sp: float = car["speed"]
	sp = move_toward(sp, target, (16.0 if target < sp else 5.0) * delta)
	car["speed"] = sp
	# Stuck behind another car for ages (a jam at a corner): let it squeeze through.
	if by_car and sp < 0.2:
		car["stuck"] = float(car["stuck"]) + delta
		if float(car["stuck"]) > 5.0:
			car["ghost"] = 2.5
			car["stuck"] = 0.0
	else:
		car["stuck"] = 0.0
	# Honk at the photographer standing in the road.
	if for_you and sp < 0.4:
		car["honk"] = float(car["honk"]) + delta
		if float(car["honk"]) > 1.2:
			Audio.play_3d("horn", Vector3(pos.x, 1.0, pos.y), 0.0, 70.0)
			car["honk"] = -3.0
	elif float(car["honk"]) > 0.0:
		car["honk"] = 0.0
	else:
		car["honk"] = minf(0.0, float(car["honk"]) + delta)
	var u: float = float(car["u"]) + sp * delta
	while u >= seg_len:
		u -= seg_len
		seg = (seg + 1) % n
		a = path[seg]
		b = path[(seg + 1) % n]
		seg_len = maxf(0.01, a.distance_to(b))
		d = (b - a) / seg_len
	car["u"] = u
	car["seg"] = seg
	car["yaw"] = lerp_angle(float(car["yaw"]), atan2(d.x, d.y), minf(1.0, delta * 5.0))
	_place(car, a + d * u)


## Speed that still stops within `room` metres at a comfortable 6 m/s^2.
static func _brake(room: float) -> float:
	return sqrt(maxf(0.0, room) * 12.0)


func _pos_of(car: Dictionary) -> Vector2:
	var body: Node3D = car["body"]
	return Vector2(body.position.x, body.position.z)
