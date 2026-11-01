extends Node3D
class_name ShopStand
## The bait & trap stand next to the RV, with its proprietor behind the counter.
## Front of the counter faces local +Z.

const TALK_DIST:= 2.8

var keeper: CharacterModel
var _idle_timer:= 0.0
var _busy_timer:= 0.0


func _ready() -> void:
	var stand:= CharacterModel.load_model("res://models/shop_stand.glb", 0.01)
	add_child(stand)
	keeper = CharacterModel.load_model("res://models/shopkeeper.glb", 0.012)
	keeper.position = Vector3(0.25, 0, -0.9)   # belly clears the counter
	add_child(keeper)
	keeper.play("idle")
	# counter + keeper collision
	var sb:= StaticBody3D.new()
	var cs:= CollisionShape3D.new()
	var box:= BoxShape3D.new()
	box.size = Vector3(2.7, 1.1, 1.65)
	cs.shape = box
	cs.position = Vector3(0, 0.55, -0.32)
	sb.add_child(cs)
	add_child(sb)
	# painted sign board up on two poles, high enough to clear the awning
	var plank:= StandardMaterial3D.new()
	plank.albedo_color = Color(0.93, 0.86, 0.66)
	var board:= MeshInstance3D.new()
	var bm:= BoxMesh.new()
	bm.size = Vector3(2.3, 0.5, 0.06)
	board.mesh = bm
	board.material_override = plank
	board.position = Vector3(0, 3.4, -0.1)
	add_child(board)
	var pole_mat:= StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.35, 0.24, 0.14)
	for x in [-0.95, 0.95]:
		var pole:= MeshInstance3D.new()
		var pm:= BoxMesh.new()
		pm.size = Vector3(0.06, 0.9, 0.06)
		pole.mesh = pm
		pole.material_override = pole_mat
		pole.position = Vector3(x, 2.95, -0.14)
		add_child(pole)
	var sign:= Label3D.new()
	sign.text = "BAIT & TRAPS"
	sign.font = UIStyle.western()
	sign.font_size = 64
	sign.pixel_size = 0.0045
	sign.modulate = Color(0.55, 0.08, 0.05)
	sign.outline_size = 0
	sign.position = Vector3(0, 3.4, -0.065)
	add_child(sign)
	var price:= Label3D.new()
	price.text = "MEAT · TRAPS · TRIPODS · \"HERBS\" · BEER"
	price.font = UIStyle.typewriter()
	price.font_size = 40
	price.pixel_size = 0.0042
	price.modulate = Color(1, 0.95, 0.8)
	price.outline_size = 8
	price.outline_modulate = Color(0, 0, 0)
	price.position = Vector3(0, 0.75, 0.37)
	add_child(price)
	# a hanging lantern so you can find it at night
	var lamp:= OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.72, 0.35)
	lamp.light_energy = 2.2
	lamp.omni_range = 7.0
	lamp.position = Vector3(-1.1, 2.2, 0.7)
	add_child(lamp)
	var bulb:= MeshInstance3D.new()
	var sm:= SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	bulb.mesh = sm
	var bmat:= StandardMaterial3D.new()
	bmat.albedo_color = Color(1, 0.8, 0.4)
	bmat.emission_enabled = true
	bmat.emission = Color(1, 0.75, 0.35)
	bmat.emission_energy_multiplier = 3.0
	bulb.material_override = bmat
	bulb.position = lamp.position
	add_child(bulb)


## Where the customer stands.
func front_point() -> Vector3:
	return to_global(Vector3(0, 0, 1.2))


func player_near(p: Vector3) -> bool:
	return Vector2(p.x, p.z).distance_to(Vector2(front_point().x, front_point().z)) < TALK_DIST


func greet() -> void:
	_busy_timer = 1.6
	keeper.play("tip_hat")
	Audio.play_3d("shop_talk", keeper.global_position + Vector3(0, 1.6, 0), -6.0)   # about as loud as Toe


func chat() -> void:
	_busy_timer = 2.0
	keeper.play("talk")
	Audio.play_3d("shop_talk", keeper.global_position + Vector3(0, 1.6, 0), -7.0)


func laugh() -> void:
	_busy_timer = 1.2
	keeper.play("talk")
	Audio.play_3d("shop_laugh", keeper.global_position + Vector3(0, 1.6, 0), -8.0)


func _process(delta: float) -> void:
	if _busy_timer > 0.0:
		_busy_timer -= delta
		if _busy_timer <= 0.0:
			keeper.play("idle")
