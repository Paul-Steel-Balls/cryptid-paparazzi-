extends Node3D
class_name PotOfGold
## The Leperchaun's pot of gold, out in the Deep Woods. He never strays far from it.
## Catch it unguarded (lure him off with bait, trap him, or wait for him to wander) and it's yours:
## straight cash, once a night. He will NOT take it well.

const VALUE:= 150
const GUARD_DIST:= 14.0
const TAKE_DIST:= 2.3

var taken:= false
var _coins: Node3D
var _light: OmniLight3D
var _t:= 0.0


func _ready() -> void:
	var iron:= StandardMaterial3D.new()
	iron.albedo_color = Color(0.09, 0.09, 0.1)
	iron.metallic = 0.6
	iron.roughness = 0.45
	var gold:= StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.78, 0.18)
	gold.metallic = 1.0
	gold.roughness = 0.25
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.7, 0.15)
	gold.emission_energy_multiplier = 0.35
	# Fat iron cauldron on three stubby legs.
	var pot:= MeshInstance3D.new()
	var sm:= SphereMesh.new()
	sm.radius = 0.42
	sm.height = 0.7
	pot.mesh = sm
	pot.material_override = iron
	pot.position = Vector3(0, 0.42, 0)
	add_child(pot)
	var lip:= MeshInstance3D.new()
	var tm:= TorusMesh.new()
	tm.inner_radius = 0.3
	tm.outer_radius = 0.4
	lip.mesh = tm
	lip.material_override = iron
	lip.position = Vector3(0, 0.74, 0)
	add_child(lip)
	for i in 3:
		var a:= TAU * float(i) / 3.0
		var leg:= MeshInstance3D.new()
		var cm:= CylinderMesh.new()
		cm.top_radius = 0.04
		cm.bottom_radius = 0.06
		cm.height = 0.2
		leg.mesh = cm
		leg.material_override = iron
		leg.position = Vector3(cos(a) * 0.25, 0.08, sin(a) * 0.25)
		add_child(leg)
	# Heaped coins, a few spilled on the ground.
	_coins = Node3D.new()
	add_child(_coins)
	var heap:= MeshInstance3D.new()
	var hm:= SphereMesh.new()
	hm.radius = 0.33
	hm.height = 0.3
	heap.mesh = hm
	heap.material_override = gold
	heap.position = Vector3(0, 0.78, 0)
	_coins.add_child(heap)
	var rng:= RandomNumberGenerator.new()
	rng.seed = 77
	for i in 16:
		var c:= MeshInstance3D.new()
		var cy:= CylinderMesh.new()
		cy.top_radius = 0.05
		cy.bottom_radius = 0.05
		cy.height = 0.012
		c.mesh = cy
		c.material_override = gold
		if i < 10:
			var a:= rng.randf() * TAU
			c.position = Vector3(cos(a) * rng.randf_range(0.05, 0.25), 0.9 + rng.randf() * 0.06, sin(a) * rng.randf_range(0.05, 0.25))
		else:
			var a:= rng.randf() * TAU
			c.position = Vector3(cos(a) * rng.randf_range(0.5, 0.9), 0.01, sin(a) * rng.randf_range(0.5, 0.9))
		c.rotation = Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5))
		_coins.add_child(c)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.8, 0.3)
	_light.light_energy = 1.4
	_light.omni_range = 5.0
	_light.position = Vector3(0, 1.1, 0)
	add_child(_light)
	var sb:= StaticBody3D.new()
	var cs:= CollisionShape3D.new()
	var cyl:= CylinderShape3D.new()
	cyl.radius = 0.45
	cyl.height = 0.9
	cs.shape = cyl
	cs.position = Vector3(0, 0.45, 0)
	sb.add_child(cs)
	add_child(sb)


func _process(delta: float) -> void:
	_t += delta
	if not taken:
		_light.light_energy = 1.2 + sin(_t * 3.0) * 0.3


func player_near(p: Vector3) -> bool:
	return not taken and Vector2(p.x - global_position.x, p.z - global_position.z).length() < TAKE_DIST


## Is a Leperchaun close enough (and free to act) to be guarding it?
func guarded_by(cryptids: Array) -> Cryptid:
	for c in cryptids:
		if not is_instance_valid(c) or (c as Cryptid).species_id != "leperchaun":
			continue
		var k:= c as Cryptid
		if k.state == Cryptid.State.TRAPPED or k.state == Cryptid.State.EATING:
			continue
		if Vector2(k.global_position.x - global_position.x, k.global_position.z - global_position.z).length() < GUARD_DIST:
			return k
	return null


func take() -> void:
	taken = true
	_coins.visible = false
	_light.visible = false
