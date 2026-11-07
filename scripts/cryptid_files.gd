extends CanvasLayer
class_name CryptidFiles
## "Cryptid Files": a case file per cryptid, opened from the pause menu over the paused game.
## A file unlocks the first time you develop a medium-quality (GREAT SHOT or better) photo of that cryptid.
## Unlocked files show the 3D model on a turntable with its animations.

signal closed

const ENTRIES:= [
	["bigboobs", "Bigfoot, but... more. Hot-pink tube top, pearl necklace, glowing eyes. Hunts by ear: don't sprint near her."],
	["methman", "Lives in a tent under the city overpass and can't stop staring at his lantern. Twitchy, fast, hears everything. Stays near camp."],
	["jersey_devil", "Deer head, #13 jersey, beer-sipping helmet, jeans. Celebrates every time he loses you."],
	["oh_go_pogo", "Canada's lake monster, on a pogo stick, in a toque. Loves the shallows."],
	["grey_tourist", "Hawaiian shirt, socks with sandals, bucket hat. Travels in groups, runs faster than you, and takes YOUR picture. The flash will blind you."],
	["cornicorn", "A unicorn whose horn is just an ear of corn. Skittish: bolts at the first sign of you."],
	["crackin", "Octopus guy. Plumber's crack. Beer held at a perfect right angle. Too lazy to chase you... unless you flash him up close."],
	["fhairy", "A large, very hairy man in a fairy costume three sizes too small. Wand, wings, tutu. Skittish: one flash and he flutters off, shrieking."],
	["leperchaun", "A leprechaun with leprosy. Bits keep falling off; the gold never does. Guards his pot of gold in the Deep Woods: catch it unguarded and it's yours."],
	["bent", "An Ent with bloodshot eyes, a red solo cup in one branch and a joint in the other. Slow. Very slow. Duuude."],
	["the_rake", "Slenderman-tall, suit and tie, and a big plastic leaf rake for a head. Only moves when you're not looking at it. So keep looking... but not for too long: stare and it's gone, and then it's behind you."],
	["santa", "Turns up on the roof of your RV about one night a year. Waves. Ho-ho-hos. One flash and he's gone till next Christmas."],
	["wherewolf", "Hopelessly lost. Unfathomably rare. Holding the map upside down. If you see him, you are very lucky."],
]
const ALWAYS:= [
	["toe_rogan", "TOE ROGAN", "Short. Stacked. A big toe for a head. Show him every common and uncommon on a map to unlock the next one. Also swaps your film."],
	["shopkeeper", "THE PROPRIETOR", "Runs the bait & trap stand by the RV. Was into cryptids before they were mainstream."],
	["photographer", "YOU", "Tabloid photographer. Red cap, vest full of pockets, questionable judgement."],
]

var _list: VBoxContainer
var _title: Label
var _blurb: Label
var _stats: Label
var _anim_btn: Button
var _view: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _model: CharacterModel
var _locked_pic: TextureRect
var _anims: Array = []
var _anim_i:= 0


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim:= ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.05, 0.92)
	UIStyle.full_rect(dim)
	add_child(dim)
	var root:= HBoxContainer.new()
	UIStyle.full_rect(root)
	root.offset_left = 30
	root.offset_right = -30
	root.offset_top = 24
	root.offset_bottom = -24
	root.add_theme_constant_override("separation", 24)
	dim.add_child(root)

	var left:= VBoxContainer.new()
	left.custom_minimum_size = Vector2(330, 0)
	root.add_child(left)
	var head:= UIStyle.label("CRYPTID FILES", 38, UIStyle.GOLD, UIStyle.western())
	left.add_child(head)
	var count:= UIStyle.label("", 16, Color(1, 1, 1, 0.7), UIStyle.typewriter())
	count.name = "Count"
	left.add_child(count)
	var scroll:= ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	var back:= UIStyle.dark_button("BACK", UIStyle.GOLD)
	back.pressed.connect(close)
	left.add_child(back)

	var right:= VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	_title = UIStyle.label("", 44, UIStyle.GOLD, UIStyle.western())
	right.add_child(_title)
	_blurb = UIStyle.label("", 19, Color(1, 1, 1), UIStyle.typewriter())
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_blurb)
	_stats = UIStyle.label("", 17, Color(0.6, 0.95, 1.0), UIStyle.typewriter())
	right.add_child(_stats)
	var frame:= PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UIStyle.box(Color(0.08, 0.07, 0.14), Color(UIStyle.GOLD, 0.5), 2, 8, 0))
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(frame)
	var svc:= SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(svc)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_2X
	svc.add_child(_view)
	_locked_pic = TextureRect.new()
	_locked_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_locked_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Not on film yet: a sketch-artist WANTED poster (ui/wanted, made by tools/make_wanted.py).
	_locked_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_locked_pic)
	_anim_btn = UIStyle.dark_button("NEXT ANIMATION", Color(0.6, 0.95, 1.0), 18)
	_anim_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	_anim_btn.pressed.connect(_next_anim)
	right.add_child(_anim_btn)
	_build_stage()
	visible = false


func _build_stage() -> void:
	var env:= WorldEnvironment.new()
	var e:= Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.07, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.5, 0.7)
	e.ambient_light_energy = 0.9
	env.environment = e
	_view.add_child(env)
	var key:= DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.3
	_view.add_child(key)
	var rim:= OmniLight3D.new()
	rim.position = Vector3(-2, 2.5, -2)
	rim.light_color = Color(0.6, 0.7, 1.0)
	rim.light_energy = 2.0
	rim.omni_range = 8.0
	_view.add_child(rim)
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
	_view.add_child(plinth)
	_pivot = Node3D.new()
	_view.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 38
	_view.add_child(_cam)


func open() -> void:
	for c in _list.get_children():
		c.queue_free()
	var unlocked:= 0
	for e in ENTRIES:
		var ok:= GameState.has_file(e[0])
		if ok:
			unlocked += 1
		_list.add_child(_entry_button(e[0], Species.display_name(e[0]).to_upper() if ok else "WANTED: " + Species.display_name(e[0]).to_upper(), ok))
	for e in ALWAYS:
		_list.add_child(_entry_button(e[0], e[1], true))
	(find_child("Count", true, false) as Label).text = "%d of %d cryptid files unlocked" % [unlocked, ENTRIES.size()]
	visible = true
	_select(ENTRIES[0][0])


func close() -> void:
	visible = false
	if _model:
		_model.queue_free()
		_model = null
	closed.emit()


func is_open() -> bool:
	return visible


func _entry_button(id: String, text: String, unlocked: bool) -> Button:
	var b:= UIStyle.dark_button("  " + text, UIStyle.GOLD if unlocked else Color(0.5, 0.5, 0.55), 18)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 56)
	var path:= ("res://ui/portraits/%s.png" if unlocked else "res://ui/wanted/%s.png") % id
	if ResourceLoader.exists(path):
		b.icon = load(path)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 40)
	b.pressed.connect(_select.bind(id))
	return b


func _select(id: String) -> void:
	Audio.play("ui_click", -10.0)
	if _model:
		_model.queue_free()
		_model = null
	var blurb:= ""
	var title:= ""
	var is_cryptid:= false
	for e in ENTRIES:
		if e[0] == id:
			blurb = e[1]
			title = Species.display_name(id).to_upper()
			is_cryptid = true
	for e in ALWAYS:
		if e[0] == id:
			blurb = e[2]
			title = e[1]
	var unlocked:= not is_cryptid or GameState.has_file(id)
	if not unlocked:
		_title.text = "WANTED: " + title
		_blurb.text = "Witnesses gave the sketch artist this much. Develop a GREAT SHOT (or better) of it to open the real file."
		var best:= int(GameState.file_scores.get(id, 0))
		_stats.text = "Best photo so far: %s" % (str(best) if best > 0 else "none")
		var wp:= "res://ui/wanted/%s.png" % id
		_locked_pic.texture = load(wp) if ResourceLoader.exists(wp) else null
		_locked_pic.visible = true
		_anim_btn.visible = false
		return
	_locked_pic.visible = false
	_title.text = title
	_blurb.text = blurb
	if is_cryptid:
		var tiers: Array = []
		for m in Species.MAP_ORDER:
			for t in Species.TIERS:
				if id in Species.MAPS[m][t]:
					tiers.append("%s: %s" % [Species.MAPS[m]["name"], t])
		var info:= Species.info(id)
		_stats.text = "Best photo score: %d    ·    Best sale: $%d\n%s    ·    Temperament: %s" % [int(GameState.file_scores.get(id, 0)),
			int(GameState.album.get(id, 0)), "   ".join(tiers), str(info.get("behaviour", "?"))]
	else:
		_stats.text = ""
	var mpath:= str(Species.info(id).get("model", "res://models/%s.glb" % id)) if is_cryptid else "res://models/%s.glb" % id
	_model = CharacterModel.load_model(mpath, 0.012)
	_model.process_mode = Node.PROCESS_MODE_ALWAYS
	_pivot.add_child(_model)
	_anims = []
	if _model.anim_player:
		_model.anim_player.process_mode = Node.PROCESS_MODE_ALWAYS
		_anims = Array(_model.anim_player.get_animation_list())
		_anims.erase("RESET")
	_anim_i = maxi(0, _anims.find("idle"))
	_anim_btn.visible = _anims.size() > 1
	if not _anims.is_empty():
		_model.play(_anims[_anim_i])
		_anim_btn.text = "ANIMATION: %s  ▶" % _anims[_anim_i]
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
	_cam.look_at_from_position(_cam.position, Vector3(0, h * 0.48, 0))


func _next_anim() -> void:
	if _anims.is_empty() or _model == null:
		return
	_anim_i = (_anim_i + 1) % _anims.size()
	_model.play(_anims[_anim_i])
	_anim_btn.text = "ANIMATION: %s  ▶" % _anims[_anim_i]


func _process(delta: float) -> void:
	if visible and _pivot:
		_pivot.rotation.y += delta * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
