extends PhotoSubject
class_name Santa
## Once in a blue moon (about one night in 365) Santa parks his sleigh on top of the RV.
## He waves and ho-ho-hos when you're about. Get the picture before he takes off:
## one flash and he's gone, back up into the night.

signal departed

var player: Player
var model: CharacterModel
var _ho_cool:= 3.0
var _leaving:= false
var _t:= 0.0
var _start:= Vector3.ZERO
var _dir:= Vector3(1, 0, 0)
var _bells: AudioStreamPlayer3D


func _init() -> void:
	species_id = "santa"
	display_name = "Santa Claus"
	photo_offset = Vector3(0, 1.35, 0)


func _ready() -> void:
	model = CharacterModel.load_model("res://models/santa_sleigh.glb", 0.012)
	add_child(model)
	model.play("idle")
	_bells = AudioStreamPlayer3D.new()
	_bells.stream = Audio.get_stream("sleigh_bells")
	_bells.unit_size = 8.0
	_bells.max_distance = 90.0
	add_child(_bells)
	var glow:= OmniLight3D.new()
	glow.light_color = Color(1.0, 0.85, 0.6)
	glow.light_energy = 1.2
	glow.omni_range = 6.0
	glow.position = Vector3(0, 1.8, 0)
	add_child(glow)


func get_facing() -> Vector3:
	# He's always turned to wave at you.
	if player == null:
		return global_transform.basis.z
	var d:= player.global_position - photo_point()
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else global_transform.basis.z


func is_leaving() -> bool:
	return _leaving


## Got his picture: a cheery HO HO HO and off he goes.
func take_off() -> void:
	if _leaving:
		return
	_leaving = true
	_t = 0.0
	_start = global_position
	_dir = global_transform.basis.z
	if model:
		model.play("wave")
	if is_inside_tree():
		Audio.play_3d("santa_ho", photo_point(), 6.0, 120.0)
		_bells.play()


func _process(delta: float) -> void:
	if _leaving:
		_t += delta
		if _t > 0.9:
			var k:= _t - 0.9
			global_position = _start + _dir * (k * k * 6.0) + Vector3(0, k * k * 3.0 + k * 1.5, 0)
			rotation.x = -minf(0.35, k * 0.25)
		if _t > 9.0:
			departed.emit()
			queue_free()
		return
	if player == null or not is_instance_valid(player):
		return
	_ho_cool -= delta
	var d:= player.global_position.distance_to(global_position)
	if d < 28.0:
		if _ho_cool <= 0.0:
			_ho_cool = randf_range(7.0, 11.0)
			model.play("wave")
			Audio.play_3d("santa_ho", photo_point(), 3.0, 90.0)
			get_tree().create_timer(2.2).timeout.connect(func():
				if is_instance_valid(model) and not _leaving:
					model.play("idle"))
