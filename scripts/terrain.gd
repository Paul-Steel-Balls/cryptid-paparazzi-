extends StaticBody3D
class_name Terrain
## Rolling hills, valleys and a raised rim, built from layered noise.
## Collision is a trimesh of the exact render mesh, so feet and eyes agree.
## height_at() interpolates the same triangles, so props sit flush.

## v0.14: maps grew 20% across; v0.16: another 50% on top (1.8x the original, 3.24x the ground).
const SCALE:= 1.8
const HALF:= 216.0          # map spans -HALF..HALF on X and Z
const STEP:= 2.0            # grid spacing in metres
const CAMP:= Vector2(0, 180) # RV / spawn clearing (x, z)
const CAMP_FLAT_R:= 16.0
const CAMP_BLEND_R:= 34.0
const RIM_START:= 171.0
## Camp is a safe zone (v0.17): nothing chases, grabs, flashes or beams you up within this.
const SAFE_R:= 16.0     # beyond this the land rises into a bowl wall

const LAKE_C:= Vector2(0, -15)   # Lakeside map: centre of the lake
## Where things can roam/spawn: a square of +-SPAN inside the rim.
const SPAN:= 128.0

var seed_value:= 0
var map_id:= "woods"
## Water surface height (-1000 = no water on this map).
var water_level:= -1000.0
var _n:= 0                  # vertices per side
var _h: PackedFloat32Array
var _camp_h:= 0.0

var _style: Dictionary = {}
var _hills:= FastNoiseLite.new()
var _detail:= FastNoiseLite.new()
var _valley:= FastNoiseLite.new()


func _init(p_seed: int = 0, p_map: String = "woods") -> void:
	seed_value = p_seed if p_seed != 0 else randi()
	map_id = p_map
	_style = Species.style(map_id)
	is_city = _style["terrain"] == "city"
	if _style["terrain"] == "lake":
		water_level = -2.0
	elif _style["terrain"] == "city":
		water_level = CityBlocks.WATER
	_setup_noise()
	_build_heights()


func _ready() -> void:
	_build_mesh_and_collision()


func _setup_noise() -> void:
	_hills.seed = seed_value
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 0.008
	_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	_hills.fractal_octaves = 3
	_detail.seed = seed_value + 17
	_detail.frequency = 0.045
	_detail.fractal_octaves = 2
	_valley.seed = seed_value + 99
	_valley.frequency = 0.006
	_valley.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_valley.fractal_octaves = 2


func _raw_height(x: float, z: float) -> float:
	if _style["terrain"] == "lake":
		return _lake_height(x, z)
	if _style["terrain"] == "city":
		return CityBlocks.ground_height(x, z)
	var h:= _hills.get_noise_2d(x, z) * 11.0
	h += _detail.get_noise_2d(x, z) * 1.4
	# Ridged noise inverted gives long winding valleys.
	var v:= _valley.get_noise_2d(x, z)
	h -= maxf(0.0, v) * 7.0
	# Rim: land climbs steeply near the edge so the world feels enclosed.
	var edge:= maxf(absf(x), absf(z))
	if edge > RIM_START:
		var t:= (edge - RIM_START) / (HALF - RIM_START)
		h += t * t * 26.0
	return h


## Lakeside: gentler hills around a big irregular lake with shallow, wadeable edges.
func _lake_height(x: float, z: float) -> float:
	var h:= _hills.get_noise_2d(x, z) * 6.0 + 1.5
	h += _detail.get_noise_2d(x, z) * 1.2
	var d:= Vector2(x, z).distance_to(LAKE_C)
	var r:= 80.0 + _valley.get_noise_2d(x * 0.4, z * 0.4) * 21.0
	var t:= clampf((d - (r - 22.0)) / 30.0, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	h = lerpf(-7.0, maxf(h, water_level + 0.8), t)
	var edge:= maxf(absf(x), absf(z))
	if edge > RIM_START:
		var e:= (edge - RIM_START) / (HALF - RIM_START)
		h += e * e * 22.0
	return h


func _build_heights() -> void:
	_n = int(HALF * 2.0 / STEP) + 1
	_h.resize(_n * _n)
	_camp_h = _raw_height(CAMP.x, CAMP.y)
	if water_level > -100.0 and _style["terrain"] != "city":
		_camp_h = maxf(_camp_h, water_level + 2.5)
	for iz in _n:
		for ix in _n:
			var x:= -HALF + ix * STEP
			var z:= -HALF + iz * STEP
			var h:= _raw_height(x, z)
			var d:= Vector2(x, z).distance_to(CAMP)
			if d < CAMP_BLEND_R:
				var t:= clampf((d - CAMP_FLAT_R) / (CAMP_BLEND_R - CAMP_FLAT_R), 0.0, 1.0)
				t = t * t * (3.0 - 2.0 * t)
				h = lerpf(_camp_h, h, t)
			_h[iz * _n + ix] = h


func _vh(ix: int, iz: int) -> float:
	ix = clampi(ix, 0, _n - 1)
	iz = clampi(iz, 0, _n - 1)
	return _h[iz * _n + ix]


## Exact height of the rendered/collision surface at (x, z) (the City's bridge deck counts).
func height_at(x: float, z: float) -> float:
	var h:= _surface_at(x, z)
	if is_city and CityBlocks.on_bridge(x, z):
		return maxf(h, 0.05)
	return h


var is_city:= false


func _surface_at(x: float, z: float) -> float:
	var fx:= (clampf(x, -HALF, HALF) + HALF) / STEP
	var fz:= (clampf(z, -HALF, HALF) + HALF) / STEP
	var ix:= mini(int(fx), _n - 2)
	var iz:= mini(int(fz), _n - 2)
	var u:= fx - ix
	var v:= fz - iz
	var h00:= _vh(ix, iz)
	var h10:= _vh(ix + 1, iz)
	var h01:= _vh(ix, iz + 1)
	var h11:= _vh(ix + 1, iz + 1)
	# Quads are split along the 00-11 diagonal (matches _build_mesh).
	if u >= v:
		return h00 + (h10 - h00) * u + (h11 - h10) * v
	return h00 + (h11 - h01) * u + (h01 - h00) * v


func normal_at(x: float, z: float) -> Vector3:
	var e:= 0.5
	var dx:= height_at(x + e, z) - height_at(x - e, z)
	var dz:= height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


static func in_camp(p: Vector3) -> bool:
	return Vector2(p.x, p.z).distance_to(CAMP) < SAFE_R


func camp_height() -> float:
	return _camp_h


func _color_for(h: float, slope: float, x: float, z: float) -> Color:
	if is_city:
		return CityBlocks.ground_color(x, z)
	var grass: Color = _style["grass"]
	var lush: Color = _style["lush"]
	var dry: Color = _style["dry"]
	var dirt:= Color(0.42, 0.32, 0.2)
	var rock:= Color(0.45, 0.45, 0.5)
	var c:= grass.lerp(lush, clampf(0.5 - h * 0.06, 0.0, 1.0))
	c = c.lerp(dry, clampf((h - 5.0) * 0.12, 0.0, 0.7))
	c = c.lerp(dirt, clampf((slope - 0.25) * 3.0, 0.0, 0.8))
	c = c.lerp(rock, clampf((slope - 0.55) * 3.0, 0.0, 1.0))
	if water_level > -100.0:
		var sand:= Color(0.72, 0.64, 0.44)
		var mud:= Color(0.3, 0.27, 0.2)
		c = c.lerp(sand, clampf(1.0 - (h - water_level) / 1.2, 0.0, 1.0))
		if h < water_level - 0.3:
			c = c.lerp(mud, clampf((water_level - h) / 3.0, 0.0, 1.0))
	var d:= Vector2(x, z).distance_to(CAMP)
	if d < CAMP_FLAT_R:
		c = c.lerp(Color(0.32, 0.62, 0.3), 0.6)
	var speck:= _detail.get_noise_2d(x * 4.0, z * 4.0) * 0.05
	return Color(c.r + speck, c.g + speck, c.b + speck)


func _build_mesh_and_collision() -> void:
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in _n:
		for ix in _n:
			var x:= -HALF + ix * STEP
			var z:= -HALF + iz * STEP
			var h:= _vh(ix, iz)
			var nrm:= Vector3(_vh(ix - 1, iz) - _vh(ix + 1, iz), 2.0 * STEP, _vh(ix, iz - 1) - _vh(ix, iz + 1)).normalized()
			st.set_color(_color_for(h, 1.0 - nrm.y, x, z) * 1.0)
			st.set_normal(nrm)
			st.set_uv(Vector2(x, z) * 0.1)
			st.add_vertex(Vector3(x, h, z))
	for iz in _n - 1:
		for ix in _n - 1:
			var i00:= iz * _n + ix
			var i10:= i00 + 1
			var i01:= i00 + _n
			var i11:= i01 + 1
			# Counter-clockwise seen from above (Godot front faces are CW from camera => up-facing).
			st.add_index(i00); st.add_index(i10); st.add_index(i11)
			st.add_index(i00); st.add_index(i11); st.add_index(i01)
	var mesh:= st.commit()
	var mi:= MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	var mat:= StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mi.material_override = mat
	add_child(mi)
	var cs:= CollisionShape3D.new()
	cs.name = "GroundCollision"
	cs.shape = mesh.create_trimesh_shape()
	add_child(cs)
	if water_level > -100.0:
		_build_water()


func _build_water() -> void:
	var water:= MeshInstance3D.new()
	water.name = "Water"
	var pm:= PlaneMesh.new()
	pm.size = Vector2(HALF * 2.0, HALF * 2.0)
	pm.subdivide_width = 32
	pm.subdivide_depth = 32
	water.mesh = pm
	var m:= StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.22, 0.34, 0.78)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.06
	m.metallic = 0.35
	m.emission_enabled = true
	m.emission = Color(0.03, 0.06, 0.1)
	water.material_override = m
	water.position = Vector3(0, water_level, 0)
	add_child(water)
