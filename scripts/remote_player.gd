extends CharacterBody3D
class_name RemotePlayer
## Another photographer in an online game, drawn from the state their PC sends ~20 times a second
## (Player.net_state). On the host it's also a real target: cryptids see, hear, chase and grab it,
## traps snare it, tourists flash it; NetSync passes those on to that player's PC.

var peer_id:= 0
var indoors:= false
var snared:= false
var model: CharacterModel
var _label: Label3D
var _head: HeadLook
var _target:= Vector3.ZERO
var _look_yaw:= 0.0
var _body_rel:= 0.0
var _pitch:= 0.0
var _anim:= "idle"
var _speed:= 0.0
var _back:= false
var _have:= false
var _cam_node: Node3D
var _body: Node3D


func _ready() -> void:
	var cs:= CollisionShape3D.new()
	var cap:= CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = Player.STAND_HEIGHT
	cs.shape = cap
	add_child(cs)
	_body = Node3D.new()
	add_child(_body)
	model = CharacterModel.load_model("res://models/photographer.glb", 0.012)
	model.rotation.y = PI
	model.position.y = -Player.STAND_HEIGHT * 0.5
	model.scale = Vector3.ONE * 0.9
	_body.add_child(model)
	Player.attach_camera(model)
	_cam_node = model.find_child("ChestCamera", true, false)
	model.play("idle")
	if model.skeleton:
		_head = HeadLook.new()
		model.skeleton.add_child(_head)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font = load("res://fonts/Oswald.ttf")
	_label.font_size = 60
	_label.pixel_size = 0.004
	_label.outline_size = 10
	_label.outline_modulate = Color(0.05, 0.03, 0.06)
	_label.no_depth_test = false
	_label.position = Vector3(0, 1.3, 0)
	add_child(_label)
	refresh_name()


func refresh_name() -> void:
	if _label:
		_label.text = Net.name_of(peer_id)
		_label.modulate = Net.color_of(peer_id).lerp(Color.WHITE, 0.35)


func apply_state(st: Array) -> void:
	if st.size() < 11:
		return
	_target = st[0]
	_look_yaw = float(st[1])
	_body_rel = float(st[2])
	_pitch = float(st[3])
	_anim = str(st[4])
	_speed = float(st[5])
	_back = bool(st[6])
	indoors = bool(st[8])
	snared = bool(st[9])
	if _cam_node:
		_cam_node.visible = not bool(st[10])
	if not _have:
		global_position = _target
		_have = true


func is_snared() -> bool:
	return snared


## A host-side trap caught them.
func snare(duration: float) -> void:
	var ns:= get_tree().current_scene.get_node_or_null("NetSync")
	if ns:
		ns.tell_snared(peer_id, duration)


func _process(delta: float) -> void:
	if not _have:
		return
	# Smooth toward the latest reported position; snap if it's way off (teleports, RV door).
	if global_position.distance_to(_target) > 6.0:
		global_position = _target
	else:
		global_position = global_position.lerp(_target, clampf(delta * 14.0, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, _look_yaw, clampf(delta * 14.0, 0.0, 1.0))
	_body.rotation.y = lerp_angle(_body.rotation.y, _body_rel, clampf(delta * 10.0, 0.0, 1.0))
	_body.rotation.z = sin(Time.get_ticks_msec() / 40.0) * 0.1 if snared else 0.0
	if _anim in ["walk", "jog", "run", "crouch_walk"]:
		model.play_locomotion(_anim, _speed, 0.2, _back)
	else:
		model.play(_anim)
	if _head:
		_head.yaw = -_body_rel
		_head.pitch = -_pitch * 0.6
