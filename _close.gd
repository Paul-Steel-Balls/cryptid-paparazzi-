extends SceneTree
var f:= 0
func _initialize():
	var a:= OS.get_cmdline_user_args()
	var w:= Node3D.new(); root.add_child(w)
	var env:= WorldEnvironment.new(); var e:= Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.45, 0.4, 0.6)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.7, 0.7, 0.75); e.ambient_light_energy = 0.7
	env.environment = e; w.add_child(env)
	var l:= DirectionalLight3D.new(); l.rotation_degrees = Vector3(-35, 25, 0); w.add_child(l)
	var cm = load("res://scripts/character_model.gd")
	var yaws:= [0.0, 0.6, 1.57, 3.14]
	var spacing:= float(a[4])
	for i in yaws.size():
		var m = cm.load_model(a[1], 0.012)
		w.add_child(m)
		m.position = Vector3((i - 1.5) * spacing, 0, 0)
		m.rotation.y = yaws[i]
		m.play(a[5] if a.size() > 5 else "idle")
	var c:= Camera3D.new(); c.fov = 28; w.add_child(c)
	c.position = Vector3(0, float(a[2]), float(a[3])); c.look_at(Vector3(0, float(a[2]) - 0.05, 0))
func _process(_d):
	f += 1
	if f == 10:
		root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0]); quit()
	return false
