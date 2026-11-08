extends CanvasLayer
class_name WardrobeUI
## DRIP CITY (the City's costume shop) and the closet in the RV: pick an outfit, see it turn
## on the plinth, buy it (shop only) or put it on. Outfits are just for looks.

signal closed

var shop_mode:= true
var _list: VBoxContainer
var _title: Label
var _blurb: Label
var _price: Label
var _money: Label
var _action: Button
var _view: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _model: CharacterModel
var _selected:= ""
var _head: Label


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim:= ColorRect.new()
	dim.color = Color(0.05, 0.02, 0.07, 0.93)
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
	left.custom_minimum_size = Vector2(360, 0)
	root.add_child(left)
	_head = UIStyle.label("DRIP CITY", 40, Color(1.0, 0.45, 0.8), UIStyle.western())
	left.add_child(_head)
	_money = UIStyle.label("", 18, Color(0.5, 1.0, 0.55), UIStyle.typewriter())
	left.add_child(_money)
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
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)
	_title = UIStyle.label("", 44, UIStyle.GOLD, UIStyle.western())
	right.add_child(_title)
	_blurb = UIStyle.label("", 19, Color(1, 1, 1), UIStyle.typewriter())
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_blurb)
	_price = UIStyle.label("", 22, Color(0.6, 0.95, 1.0), UIStyle.typewriter())
	right.add_child(_price)
	var frame:= PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UIStyle.box(Color(0.1, 0.06, 0.12), Color(1.0, 0.45, 0.8, 0.6), 2, 8, 0))
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
	_action = UIStyle.dark_button("", Color(1.0, 0.45, 0.8), 26)
	_action.custom_minimum_size = Vector2(0, 60)
	_action.pressed.connect(_on_action)
	right.add_child(_action)
	_build_stage()
	visible = false


func _build_stage() -> void:
	var env:= WorldEnvironment.new()
	var e:= Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.05, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.6, 0.75)
	e.ambient_light_energy = 0.9
	env.environment = e
	_view.add_child(env)
	var key:= DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.3
	_view.add_child(key)
	# Changing-room bulbs, pink and gold.
	for i in 2:
		var l:= OmniLight3D.new()
		l.position = Vector3(-2.0 if i == 0 else 2.0, 2.4, 1.2)
		l.light_color = Color(1.0, 0.5, 0.85) if i == 0 else Color(1.0, 0.85, 0.5)
		l.light_energy = 2.0
		l.omni_range = 7.0
		_view.add_child(l)
	var plinth:= MeshInstance3D.new()
	var cm:= CylinderMesh.new()
	cm.top_radius = 0.9
	cm.bottom_radius = 1.0
	cm.height = 0.16
	plinth.mesh = cm
	var pm:= StandardMaterial3D.new()
	pm.albedo_color = Color(0.4, 0.15, 0.35)
	plinth.material_override = pm
	plinth.position.y = -0.08
	_view.add_child(plinth)
	_pivot = Node3D.new()
	_view.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 36
	_cam.position = Vector3(0, 1.35, 4.6)
	_view.add_child(_cam)
	_cam.look_at_from_position(_cam.position, Vector3(0, 1.1, 0))


## shop = DRIP CITY (everything, buy or wear); closet = just what you own.
func open(shop: bool) -> void:
	shop_mode = shop
	_head.text = "DRIP CITY" if shop else "THE CLOSET"
	_refresh_list()
	visible = true
	_select(GameState.skin)


func is_open() -> bool:
	return visible


func close() -> void:
	visible = false
	if _model:
		_model.queue_free()
		_model = null
	closed.emit()


func _refresh_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	_money.text = "Wallet: $%d" % GameState.money
	for id: String in Skins.ids():
		var own: bool = id in GameState.owned_skins
		if not shop_mode and not own:
			continue
		var si:= Skins.info(id)
		var tag:= "WEARING" if id == GameState.skin else ("OWNED" if own else "$%d" % int(si["price"]))
		var b:= UIStyle.dark_button("  %s   ·  %s" % [str(si["name"]).to_upper(), tag], UIStyle.GOLD if own else Color(1.0, 0.6, 0.85), 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 50)
		b.pressed.connect(_select.bind(id))
		_list.add_child(b)


func _select(id: String) -> void:
	_selected = id
	var si:= Skins.info(id)
	_title.text = str(si["name"]).to_upper()
	_blurb.text = str(si["blurb"])
	var own: bool = id in GameState.owned_skins
	if id == GameState.skin:
		_price.text = "You're wearing it."
		_action.text = "LOOKING GOOD"
		_action.disabled = true
	elif own:
		_price.text = "In your closet."
		_action.text = "PUT IT ON"
		_action.disabled = false
	else:
		var price:= int(si["price"])
		_price.text = "$%d" % price
		_action.text = "BUY & WEAR  ($%d)" % price if GameState.money >= price else "NEED $%d MORE" % (price - GameState.money)
		_action.disabled = GameState.money < price
	if _model:
		_model.queue_free()
	_model = CharacterModel.load_model(Skins.model_path(id), 0.012)
	_pivot.add_child(_model)
	_model.play("idle")


func _on_action() -> void:
	var id:= _selected
	if id == "" or id == GameState.skin:
		return
	if not id in GameState.owned_skins:
		if not GameState.buy_skin(id):
			Audio.play("dry_click", -6.0)
			return
		Audio.play("cash", -4.0)
	else:
		Audio.play("ui_click", -6.0)
	GameState.wear_skin(id)
	_refresh_list()
	_select(id)


func _process(delta: float) -> void:
	if visible and _pivot:
		_pivot.rotation.y += delta * 0.6


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
