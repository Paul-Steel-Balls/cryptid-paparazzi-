extends Node3D
class_name Pedestrian
## Someone walking the City's sidewalks at night. Back and forth along a street, a pause
## now and then (checking their phone). They set off tripod cams, so place them carefully.

var city: CityBlocks
var player: Node3D
var model_path:= "res://models/ped_suit.glb"
var model: CharacterModel
var speed:= 1.4
var _a:= Vector2.ZERO
var _b:= Vector2.ZERO
var _t:= 0.0
var _dir:= 1.0
var _pause:= 0.0
var _len:= 1.0


func _ready() -> void:
	model = CharacterModel.load_model(model_path, 0.01)
	add_child(model)
	model.play("walk")


func start(r: RandomNumberGenerator) -> void:
	var lines:= city.sidewalk_lines()
	var line: Array = lines[r.randi() % lines.size()]
	_a = line[0]
	_b = line[1]
	_len = maxf(1.0, _a.distance_to(_b))
	_t = r.randf()
	_dir = 1.0 if r.randf() < 0.5 else -1.0
	speed = r.randf_range(1.1, 1.6)
	_place()


func _place() -> void:
	var p:= _a.lerp(_b, _t)
	global_position = Vector3(p.x, 0.05, p.y)
	var d:= (_b - _a).normalized() * _dir
	rotation.y = atan2(d.x, d.y)


func _process(delta: float) -> void:
	if _pause > 0.0:
		_pause -= delta
		return
	_t += _dir * speed * delta / _len
	if _t > 1.0 or _t < 0.0:
		_t = clampf(_t, 0.0, 1.0)
		_dir = -_dir
	elif randf() < delta * 0.02:
		_pause = randf_range(2.0, 5.0)
		model.play("idle")
		return
	_place()
	if model:
		model.play_locomotion("walk", speed)
