extends SceneTree
## Renders a transparent "mugshot" PNG for every species (used on Toe Rogan's wanted poster
## and in the Cryptid Files list).
##   godot --path . --rendering-driver opengl3 --resolution 360x440 --script res://tools/render_portraits.gd
const ALL_IDS:= ["bigboobs", "methman", "wherewolf", "grey_tourist", "cornicorn", "jersey_devil", "crackin", "oh_go_pogo",
	"fhairy", "leperchaun", "the_rake", "bent", "santa", "toe_rogan", "shopkeeper", "photographer"]
## Model file when it isn't named after the id.
const MODEL_FOR:= {"santa": "santa_sleigh"}
## ONLY=a,b,c renders just those.
var IDS: Array = ALL_IDS
const OUT:= "res://ui/portraits/%s.png"

var _i:= -1
var _frames:= 0
var _world: Node3D
var _model: Node3D
var _cam: Camera3D


func _initialize() -> void:
	if OS.get_environment("ONLY") != "":
		IDS = Array(OS.get_environment("ONLY").split(","))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://ui/portraits"))
	root.transparent_bg = true
	_world = Node3D.new()
	root.add_child(_world)
	var env:= WorldEnvironment.new()
	var e:= Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.58, 0.55)
	e.ambient_light_energy = 0.9
	env.environment = e
	_world.add_child(env)
	var key:= DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 25, 0)
	key.light_energy = 1.35
	_world.add_child(key)
	_cam = Camera3D.new()
	_cam.fov = 30
	_world.add_child(_cam)
	_next()


func _next() -> void:
	_i += 1
	if _model:
		_model.queue_free()
		_model = null
	if _i >= IDS.size():
		quit()
		return
	var cm = load("res://scripts/character_model.gd")
	_model = cm.load_model("res://models/%s.glb" % MODEL_FOR.get(IDS[_i], IDS[_i]), 0.012)
	_model.rotation.y = deg_to_rad(18)
	_world.add_child(_model)
	_model.play("idle")
	var aabb:= AABB()
	var first:= true
	for mi in _model.meshes:
		var a: AABB = mi.get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
	var h:= maxf(0.8, aabb.end.y)
	var w:= maxf(aabb.size.x, aabb.size.z)
	# Upper body framing, like a mugshot; wide critters get pulled back.
	var focus_y:= h * 0.66
	var dist:= maxf(h * 0.55, w * 0.75) / tan(deg_to_rad(15.0)) * 0.95
	_cam.look_at_from_position(Vector3(0, focus_y + h * 0.05, dist), Vector3(0, focus_y, 0))
	_frames = 0


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 2 and _model and _model.anim_player:
		_model.anim_player.seek(0.3, true)
		_model.anim_player.pause()
	if _frames == 5:
		var img:= root.get_viewport().get_texture().get_image()
		img.save_png(OUT % IDS[_i])
		print("portrait ", IDS[_i])
		_next()
	return false
