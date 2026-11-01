extends Node3D
## "Cryptid Files": every sculpted character on a turntable. Open from the RV,
## or run res://gallery.tscn directly (F6 in the editor).
## Left/right (A/D or the buttons): next character.  Space: next animation.  Esc / BACK: return to the game.

const ROSTER:= [
	["bigboobs", "BIGBOOBS", "Bigfoot, but... more. Hot-pink tube top, pearl necklace, glowing eyes."],
	["methman", "METHMAN", "Lives in a tent in the woods. Can't stop staring at his lantern."],
	["methman_camp", "METHMAN'S CAMP", "Where you'll find him. Don't touch the lantern."],
	["wherewolf", "WHERE-WOLF", "Hopelessly lost. Unfathomably rare. Holding the map upside down."],
	["grey_tourist", "GREY ALIEN TOURIST", "Hawaiian shirt, socks with sandals, bucket hat. Takes photos of YOU."],
	["cornicorn", "CORNICORN", "A unicorn whose horn is just an ear of corn. Husk, silk and all."],
	["jersey_devil", "JERSEY DEVIL", "Deer head, #13 jersey, beer-sipping helmet, jeans. Go team."],
	["crackin", "CRACKIN'", "Octopus guy. Plumber's crack. Beer held at a perfect right angle."],
	["oh_go_pogo", "OH-GO-POGO", "Canada's lake monster, on a pogo stick, in a toque."],
	["toe_rogan", "TOE ROGAN", "Short. Stacked. A big toe for a head. Show him every common and uncommon to unlock new maps."],
	["photographer", "YOU", "Tabloid photographer. Red cap, vest full of pockets, questionable judgement."],
]

var _index:= 0
var _model: CharacterModel
var _pivot: Node3D
var _cam: Camera3D
var _anims: Array = []
var _anim_i:= 0
var _title: Label
var _blurb: Label
var _anim_label: Label
var _spin:= true


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	var env:= WorldEnvironment.new()
	var e:= Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.08, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.5, 0.7)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
	var key:= DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.3
	add_child(key)
	var rim:= OmniLight3D.new()
	rim.position = Vector3(-2, 2.5, -2)
	rim.light_color = Color(0.6, 0.7, 1.0)
	rim.light_energy = 2.0
	rim.omni_range = 8.0
	add_child(rim)
	var plinth:= MeshInstance3D.new()
	var cm:= CylinderMesh.new()
	cm.top_radius = 1.3
	cm.bottom_radius = 1.4
	cm.height = 0.2
	plinth.mesh = cm
	var pm:= StandardMaterial3D.new()
	pm.albedo_color = Color(0.25, 0.22, 0.35)
	plinth.material_override = pm
	plinth.position.y = -0.1
	add_child(plinth)
	_pivot = Node3D.new()
	add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 38
	add_child(_cam)
	_build_ui()
	_show(0)


func _build_ui() -> void:
	var layer:= CanvasLayer.new()
	add_child(layer)
	var root:= Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_title = _label(root, 44, Color(1, 0.9, 0.3), Vector2(30, 20))
	_blurb = _label(root, 22, Color(1, 1, 1), Vector2(30, 80))
	_anim_label = _label(root, 20, Color(0.6, 0.95, 1.0), Vector2(30, 115))
	var help:= _label(root, 18, Color(1, 1, 1, 0.7), Vector2(30, 0))
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_top = -40
	help.text = "A/D or arrows: next character   ·   Space: next animation   ·   S: stop/start spin   ·   Esc: back to the game"
	var row:= HBoxContainer.new()
	row.anchor_left = 1.0
	row.anchor_right = 1.0
	row.offset_left = -420
	row.offset_top = 20
	root.add_child(row)
	for spec in [["< PREV", func(): _show(_index - 1)], ["NEXT >", func(): _show(_index + 1)], ["ANIM", _next_anim], ["BACK", _back]]:
		var b:= Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(95, 55)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(spec[1])
		row.add_child(b)


func _label(root: Control, size: int, color: Color, pos: Vector2) -> Label:
	var l:= Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.position = pos
	root.add_child(l)
	return l


func _show(i: int) -> void:
	_index = wrapi(i, 0, ROSTER.size())
	if _model:
		_model.queue_free()
	var entry: Array = ROSTER[_index]
	_model = CharacterModel.load_model("res://models/%s.glb" % entry[0], 0.012)
	_pivot.add_child(_model)
	_title.text = entry[1]
	_blurb.text = entry[2]
	_anims = []
	if _model.anim_player:
		_anims = Array(_model.anim_player.get_animation_list())
		_anims.erase("RESET")
	_anim_i = maxi(0, _anims.find("idle"))
	_play_current()
	# Frame the camera on the model's height.
	var aabb:= AABB()
	var first:= true
	for mi in _model.meshes:
		var a:= mi.get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
	var h:= maxf(1.0, aabb.end.y)
	var w:= maxf(aabb.size.x, aabb.size.z)
	var dist:= maxf(h, w) * 1.9 + 0.8
	_cam.position = Vector3(0, h * 0.62, dist)
	_cam.look_at(Vector3(0, h * 0.48, 0))


func _play_current() -> void:
	if _anims.is_empty():
		_anim_label.text = "(static)"
		return
	_model.play(_anims[_anim_i])
	_anim_label.text = "Animation: %s  (%d/%d)" % [_anims[_anim_i], _anim_i + 1, _anims.size()]


func _next_anim() -> void:
	if _anims.is_empty():
		return
	_anim_i = (_anim_i + 1) % _anims.size()
	_play_current()


func _back() -> void:
	get_tree().change_scene_to_file("res://main.tscn")


func _process(delta: float) -> void:
	if _spin:
		_pivot.rotation.y += delta * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_A, KEY_LEFT:
				_show(_index - 1)
			KEY_D, KEY_RIGHT:
				_show(_index + 1)
			KEY_SPACE:
				_next_anim()
			KEY_S:
				_spin = not _spin
			KEY_ESCAPE:
				_back()
