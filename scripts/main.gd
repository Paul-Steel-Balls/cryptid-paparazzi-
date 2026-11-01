extends Node3D
## One night on one map. GameState (the save) decides which map and night;
## Species decides who shows up. Sleep in the RV or get grabbed to end the night.
##
## Around camp: the RV (go inside: drive, sleep, develop), Toe Rogan by the fire
## (wanted poster, film swap, map unlocks) and the bait & trap stand.

const TOE_TALK_DIST:= 3.0

var _player: Player
var _cryptids: Array[Cryptid] = []
var _bigfoot: Cryptid          # kept for older tools/tests: first hunter (or first cryptid)
var _rv: RV
var _interior: RVInterior
var _shop: ShopStand
var _hud: HUD
var _touch: TouchControls
var _pause: PauseMenu
var _poster: ToePoster
var _shop_ui: ShopUI
var _files: CryptidFiles
var _travel: TravelPanel
var _poster_wall: PosterWallUI
var _forest: Forest
var _terrain: Terrain
var _toe: Node3D
var _toe_model: CharacterModel
var _env: Environment
var _moon: DirectionalLight3D
var _moon_disc: MeshInstance3D
var _cine: Camera3D
var _ending:= false
var _cutscene:= false
var _interact_cool:= 0.0
var _night_time:= 0.0
var _need_aim_cool:= 0.0
var _was_third_person:= false
var _music_state:= ""
var _map:= "woods"
var _rng:= RandomNumberGenerator.new()
## Special visitors and loot (see scripts/ufo.gd, santa.gd, pot_of_gold.gd).
var _ufo: UFO
var _ufo_done:= false
var _tourist_flashes:= 0
const UFO_AFTER_FLASHES:= 3
var _santa: Santa
var _pot: PotOfGold
var _peds: Array = []
var _city: CityBlocks
var _mic: MicListener
## Online play (scripts/net_sync.gd). Always present; idle in single player.
var _net: NetSync
var _mp_panel: MultiplayerPanel


func _ready() -> void:
	_rng.randomize()
	GameState.start_night()
	get_tree().paused = false
	_map = GameState.current_map
	_setup_sky()
	_forest = Forest.new(int(Species.style(_map)["seed"]), _map)   # same layout every night on a map
	add_child(_forest)
	_terrain = _forest.terrain
	if _terrain.is_city:
		_city = CityBlocks.new(_terrain)
		add_child(_city)
		_forest.landmarks.merge(_city.landmarks, true)
		_forest.bushes.append_array(_city.hides)
	var camp:= Terrain.CAMP
	var camp_y:= _terrain.camp_height()

	var rv_scene:= load("res://rv.tscn")
	_rv = rv_scene.instantiate() as RV
	_rv.position = Vector3(camp.x, camp_y, camp.y + 4.0)
	add_child(_rv)
	_interior = RVInterior.new()
	add_child(_interior)

	_spawn_toe_rogan()
	_spawn_camera_pile()
	_spawn_shop()
	_spawn_props()

	var p_scene:= load("res://player.tscn")
	_player = p_scene.instantiate() as Player
	_player.terrain = _terrain
	_player.water_level = _terrain.water_level
	_player.map_limit = Terrain.RIM_START + 18.0
	_player.position = Vector3(camp.x, camp_y + Player.EYE_HEIGHT + 0.3, camp.y - 3.0)
	add_child(_player)

	_spawn_cryptids()
	_player.cryptids = _cryptids
	_spawn_specials()
	if bool(Species.style(_map)["fireflies"]):
		_spawn_fireflies()
	if not _cryptids.is_empty():
		_player.bigfoot_ref = _bigfoot

	_hud = HUD.new()
	add_child(_hud)
	_hud.is_touch = _player.is_touch
	_hud.update_stats()
	_hud.show_controls_help()
	_touch = TouchControls.new()
	add_child(_touch)
	_touch.visible = _player.is_touch
	_player.touch_controls = _touch

	_poster = ToePoster.new()
	add_child(_poster)
	_shop_ui = ShopUI.new()
	add_child(_shop_ui)
	_travel = TravelPanel.new()
	add_child(_travel)
	_poster_wall = PosterWallUI.new()
	add_child(_poster_wall)
	_pause = PauseMenu.new()
	_pause.mic = _mic
	add_child(_pause)
	_files = CryptidFiles.new()
	add_child(_files)
	_mp_panel = MultiplayerPanel.new()
	add_child(_mp_panel)

	_player.photo_taken.connect(_on_photo_taken)
	_player.film_empty.connect(_on_film_empty)
	_player.interact_requested.connect(_on_interact)
	_player.item_placed.connect(_on_item_placed)
	_player.out_of_item.connect(_on_out_of_item)
	_player.aim_changed.connect(_hud.set_aiming)
	_player.item_selected.connect(_hud.show_item)
	_player.stunned.connect(_hud.stun_flash)
	_player.need_aim.connect(_on_need_aim)
	_player.fell_in_water.connect(_on_fell_in_water)
	_player.item_consumed.connect(_on_item_consumed)
	_player.flash_not_ready.connect(func(): _hud.show_message("Flash still charging..."))
	_touch.snap_pressed.connect(_player.snap_photo)
	_touch.interact_pressed.connect(_on_interact)
	_touch.bait_pressed.connect(_player.place_bait)
	_touch.trap_pressed.connect(_player.place_trap)
	_touch.view_pressed.connect(_player.toggle_view)
	_touch.jump_pressed.connect(_player.jump)
	_touch.crouch_pressed.connect(_player.toggle_crouch)
	_hud.try_again_pressed.connect(_on_next_night)
	_poster.closed.connect(_close_ui)
	_poster.reload_pressed.connect(_on_toe_reload)
	_poster.show_pressed.connect(_on_toe_show)
	_shop_ui.closed.connect(_close_ui)
	_shop_ui.buy_pressed.connect(_on_buy)
	_travel.closed.connect(_close_ui)
	_poster_wall.closed.connect(_close_ui)
	_poster_wall.changed.connect(func(): _interior.refresh_decor())
	_travel.chosen.connect(_on_travel)
	_pause.resumed.connect(func(): _interact_cool = 0.2)
	_pause.settings_changed.connect(_apply_quality)
	_pause.files_pressed.connect(func():
		_pause.set_panel_visible(false)
		_files.open())
	_files.closed.connect(func(): _pause.set_panel_visible(true))
	_pause.multiplayer_pressed.connect(func():
		_pause.set_panel_visible(false)
		_mp_panel.open())
	_mp_panel.closed.connect(func(): _pause.set_panel_visible(true))
	if not _player.is_touch:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Audio.start_ambience(str(Species.MAPS[_map]["ambience"]))
	Audio.set_music("explore", 2.5)
	# Every night starts from black with a title card (no pop-in when you arrive somewhere).
	_hud.black_out()
	_hud.fade_to(0.0, 1.6 if GameState.arrival != "" else 1.0)
	_hud.show_title(str(Species.MAPS[_map]["name"]).to_upper(), "Night %d" % GameState.night)
	GameState.arrival = ""
	GameState.menu_open = false
	_net = NetSync.new()
	_net.setup(self)
	add_child(_net)
	Net.left_game.connect(_on_left_game)
	Net.players_changed.connect(_update_net_label)
	_update_net_label()


# ------------------------------------------------------------------ spawning

func _spawn_toe_rogan() -> void:
	# Toe Rogan holds court by the campfire.
	var fire:= Terrain.CAMP + Vector2(4.5, -4.0)
	var spot:= fire + Vector2(1.7, 0.9)
	_toe = StaticBody3D.new()
	_toe.name = "ToeRogan"
	_toe.process_mode = Node.PROCESS_MODE_ALWAYS
	var cs:= CollisionShape3D.new()
	var cap:= CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.6
	cs.shape = cap
	cs.position = Vector3(0, 0.8, 0)
	_toe.add_child(cs)
	_toe_model = CharacterModel.load_model("res://models/toe_rogan.glb", 0.012)
	_toe.add_child(_toe_model)
	_toe_model.play("idle")
	add_child(_toe)
	_toe.global_position = Vector3(spot.x, _terrain.height_at(spot.x, spot.y), spot.y)
	var to_fire:= fire - spot
	_toe.rotation.y = atan2(to_fire.x, to_fire.y) + 0.9


func _spawn_shop() -> void:
	var p:= Vector2(_rv.global_position.x - 5.6, _rv.global_position.z - 1.4)
	_shop = ShopStand.new()
	_shop.name = "Shop"
	_shop.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_shop)
	_shop.global_position = Vector3(p.x, _terrain.height_at(p.x, p.y), p.y)
	_shop.rotation.y = PI + 0.35   # counter faces the campfire


func _spawn_props() -> void:
	if _forest.landmarks.has("tailgate"):
		_spawn_tailgate(_forest.landmarks["tailgate"])
	if _forest.landmarks.has("methman_camp"):
		var p: Vector2 = _forest.landmarks["methman_camp"]
		var camp_model:= CharacterModel.load_model("res://models/methman_camp.glb", 0.012)
		camp_model.name = "MethmanCamp"
		add_child(camp_model)
		camp_model.global_position = Vector3(p.x, _terrain.height_at(p.x, p.y), p.y)
		var sb:= StaticBody3D.new()
		var cs:= CollisionShape3D.new()
		var cyl:= CylinderShape3D.new()
		cyl.radius = 1.4
		cyl.height = 2.0
		cs.shape = cyl
		cs.position = Vector3(0, 1.0, 0.5)
		sb.add_child(cs)
		camp_model.add_child(sb)
		# His lantern glows; you can spot the camp from a way off.
		var lamp:= OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.75, 0.35)
		lamp.light_energy = 2.5
		lamp.omni_range = 9.0
		lamp.position = Vector3(0, 1.2, 0)
		camp_model.add_child(lamp)


## The Jersey Devil's tailgate: lawn chair, cooler, glowing grill, a team pennant.
func _spawn_tailgate(p: Vector2) -> void:
	var root:= Node3D.new()
	root.name = "Tailgate"
	add_child(root)
	root.global_position = Vector3(p.x, _terrain.height_at(p.x, p.y), p.y)
	root.rotation.y = _rng.randf() * TAU
	var mat:= func(c: Color, glow: float = 0.0) -> StandardMaterial3D:
		var m:= StandardMaterial3D.new()
		m.albedo_color = c
		if glow > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = glow
		return m
	var box:= func(size: Vector3, pos: Vector3, m: Material, rot: Vector3 = Vector3.ZERO) -> void:
		var mi:= MeshInstance3D.new()
		var bm:= BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = m
		mi.position = pos
		mi.rotation = rot
		root.add_child(mi)
	var cyl:= func(r: float, h: float, pos: Vector3, m: Material) -> void:
		var mi:= MeshInstance3D.new()
		var cm:= CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = h
		mi.mesh = cm
		mi.material_override = m
		mi.position = pos
		root.add_child(mi)
	# cooler
	box.call(Vector3(0.6, 0.38, 0.38), Vector3(1.0, 0.19, 0.3), mat.call(Color(0.85, 0.15, 0.12)))
	box.call(Vector3(0.62, 0.06, 0.4), Vector3(1.0, 0.41, 0.3), mat.call(Color(0.95, 0.95, 0.95)))
	# folding lawn chair, red and white webbing
	var red: StandardMaterial3D = mat.call(Color(0.8, 0.1, 0.1))
	var white: StandardMaterial3D = mat.call(Color(0.95, 0.95, 0.92))
	var alu: StandardMaterial3D = mat.call(Color(0.7, 0.72, 0.75))
	for x in [-0.25, 0.25]:
		box.call(Vector3(0.04, 0.45, 0.04), Vector3(x, 0.22, 0.25), alu)
		box.call(Vector3(0.04, 0.9, 0.04), Vector3(x, 0.45, -0.25), alu, Vector3(-0.2, 0, 0))
	for i in 4:
		box.call(Vector3(0.5, 0.02, 0.09), Vector3(0, 0.44, 0.2 - i * 0.12), red if i % 2 == 0 else white)
		box.call(Vector3(0.5, 0.09, 0.02), Vector3(0, 0.6 + i * 0.12, -0.3 - i * 0.025), white if i % 2 == 0 else red, Vector3(-0.2, 0, 0))
	# kettle grill with glowing coals
	cyl.call(0.03, 0.7, Vector3(-1.2, 0.35, 0.0), mat.call(Color(0.15, 0.15, 0.15)))
	cyl.call(0.3, 0.22, Vector3(-1.2, 0.75, 0.0), mat.call(Color(0.12, 0.12, 0.13)))
	cyl.call(0.26, 0.02, Vector3(-1.2, 0.87, 0.0), mat.call(Color(1.0, 0.35, 0.08), 3.0))
	var coals:= OmniLight3D.new()
	coals.light_color = Color(1.0, 0.45, 0.15)
	coals.light_energy = 2.2
	coals.omni_range = 7.0
	coals.position = Vector3(-1.2, 1.1, 0.0)
	root.add_child(coals)
	# pennant on a pole
	box.call(Vector3(0.05, 2.6, 0.05), Vector3(0.0, 1.3, -1.2), alu)
	box.call(Vector3(1.0, 0.45, 0.02), Vector3(0.52, 2.3, -1.2), red)
	var flag:= Label3D.new()
	flag.text = "GO DEVILS!"
	flag.font = UIStyle.western()
	flag.font_size = 48
	flag.pixel_size = 0.0035
	flag.modulate = Color(1, 1, 1)
	flag.double_sided = true
	flag.position = Vector3(0.52, 2.3, -1.18)
	root.add_child(flag)
	# empties
	for i in 5:
		var a:= _rng.randf() * TAU
		cyl.call(0.033, 0.12, Vector3(cos(a) * _rng.randf_range(0.6, 1.6), 0.06, sin(a) * _rng.randf_range(0.6, 1.6)), mat.call(Color(0.75, 0.75, 0.8) if i % 2 == 0 else Color(0.2, 0.3, 0.8)))


var _slowmo_on:= false

## Joint: the world (cryptids, sound) slows down while it lasts. Beer: just a timer on the HUD.
func _update_effects() -> void:
	var high:= _player.joint_time > 0.0
	if high != _slowmo_on:
		_slowmo_on = high
		AudioServer.playback_speed_scale = 0.82 if high else 1.0
		_hud.set_haze(high)
		if not high:
			_hud.show_message("...and you're back.")
	# Online the cryptids are shared, so the joint can't slow them down for everyone: just the haze.
	var tf:= 0.4 if high and not Net.online() else 1.0
	for c in _cryptids:
		c.time_factor = tf
	var lines: Array = []
	if high:
		lines.append(("SLOW-MO  %ds" if not Net.online() else "HIGH  %ds") % ceili(_player.joint_time))
	if _player.beer_time > 0.0:
		lines.append("BUZZED  %ds" % ceili(_player.beer_time))
	_hud.set_effects(lines)


## Deep Woods: fireflies drifting around wherever you are.
var _fireflies: CPUParticles3D
func _spawn_fireflies() -> void:
	var p:= CPUParticles3D.new()
	p.name = "Fireflies"
	p.amount = 90
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(22, 2.0, 22)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.4
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.07
	var curve:= Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(0.2, 1))
	curve.add_point(Vector2(0.5, 0.2))
	curve.add_point(Vector2(0.75, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var m:= SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 3
	var mat:= StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 1.0, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 1.0, 0.3)
	mat.emission_energy_multiplier = 3.0
	m.material = mat
	p.mesh = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	_fireflies = p


func _spawn_spot(min_camp: float = 45.0) -> Vector2:
	for _i in 200:
		var p:= Vector2(_rng.randf_range(-85, 85), _rng.randf_range(-85, 70))
		if p.distance_to(Terrain.CAMP) < min_camp:
			continue
		if _terrain.water_level > -100.0 and _terrain.height_at(p.x, p.y) < _terrain.water_level + 0.3:
			continue
		if _city != null and (_city.blocked(p) or _city.blocked(p + Vector2(4, 4)) or _city.blocked(p - Vector2(4, 4))):
			continue
		return p
	return Vector2(0, -40)


func _spawn_cryptids() -> void:
	if Net.is_client():
		return   # the host's cryptids arrive as puppets (build_puppet_world)
	var roster:= Species.roll_night(_map, _rng)
	var scene:= load("res://cryptid.tscn") as PackedScene
	for entry in roster:
		var id: String = entry["id"]
		var info:= Species.info(id)
		var centre:= _spawn_spot()
		if info.has("home") and _forest.landmarks.has(info["home"]):
			centre = _forest.landmarks[info["home"]] + Vector2(3, 3)
		for k in int(entry["count"]):
			var c:= scene.instantiate() as Cryptid
			c.configure(id)
			c.terrain = _terrain
			c.water_level = _terrain.water_level
			c.camp = Terrain.CAMP
			c.map_half = Terrain.RIM_START
			c.city = _city
			if info.has("home") and _forest.landmarks.has(info["home"]):
				c.home = _forest.landmarks[info["home"]]
			var p:= centre + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3)) * float(k)
			c.position = Vector3(p.x, _terrain.height_at(p.x, p.y) + c.body_height * 0.5, p.y)
			add_child(c)
			c.bushes = _forest.bushes
			c.player_ref = _player
			c.caught_player.connect(_on_caught.bind(c))
			c.escaped.connect(_on_escaped.bind(c))
			c.flashed_player.connect(_on_flashed_by_tourist.bind(c))
			_cryptids.append(c)
	_bigfoot = null
	for c in _cryptids:
		if c.behaviour == "hunter":
			_bigfoot = c
			break
	if _bigfoot == null and not _cryptids.is_empty():
		_bigfoot = _cryptids[0]


## Pot of gold (if the Leperchaun turned up), Santa (one night in 365), the City's people, the mic.
func _spawn_specials() -> void:
	var leper:= false
	for c in _cryptids:
		if c.species_id == "leperchaun":
			leper = true
	if leper and _forest.landmarks.has("pot_of_gold") and not Net.is_client():
		var gp: Vector2 = _forest.landmarks["pot_of_gold"]
		_pot = PotOfGold.new()
		add_child(_pot)
		_pot.global_position = Vector3(gp.x, _terrain.height_at(gp.x, gp.y), gp.y)
	var force:= OS.get_environment("CP_SANTA") == "1"
	if not Net.is_client() and (force or GameState.night % 365 == 0 or _rng.randf() < Species.SANTA_CHANCE):
		_spawn_santa()
	if _city != null:
		_peds = _city.spawn_pedestrians(self, _player)
		_player.bystanders = _peds
	_mic = MicListener.new()
	_mic.player = _player
	_mic.cryptids = _cryptids
	add_child(_mic)
	if OS.get_environment("CP_UFO") == "1":
		_summon_ufo.call_deferred()


func _spawn_santa() -> void:
	_santa = Santa.new()
	_santa.player = _player
	add_child(_santa)
	# Parked on the roof, nose to the RV's front (+X).
	_santa.global_transform = Transform3D(_rv.global_basis * Basis(Vector3.UP, PI * 0.5), _rv.to_global(Vector3(0.4, 2.8, 0)))
	_player.extra_subjects.append(_santa)


func santa_leave() -> void:
	if _santa != null and is_instance_valid(_santa):
		_santa.take_off()


func _summon_ufo() -> void:
	_ufo_done = true
	_ufo = UFO.new()
	_ufo.player = _player
	_ufo.terrain = _terrain
	var a:= _rng.randf() * TAU
	add_child(_ufo)
	var p:= _player.global_position + Vector3(cos(a), 0, sin(a)) * 60.0
	_ufo.global_position = Vector3(p.x, _terrain.height_at(p.x, p.z) + UFO.ALTITUDE + 12.0, p.z)
	_player.extra_subjects.append(_ufo)
	_ufo.abducted.connect(_on_abducted)
	_ufo.escaped_beam.connect(func(): _hud.show_message("You wriggled free! It's had enough of you for one night."))
	_ufo.left.connect(func(): _ufo = null)
	_hud.show_message("A low hum overhead... THEY'RE COMING FOR YOU. Snap it before it gets you — or run!")


## The beam got you all the way up.
func _on_abducted() -> void:
	_begin_cutscene()
	_hud.fade_to(1.0, 0.4)
	Audio.play("tractor", 2.0)
	await _wait(1.4)
	var lost:= GameState.undeveloped_value()
	for rec in GameState.unsold_photos:
		GameState.photo_images.erase(str(rec.get("img", "")))
	GameState.unsold_photos.clear()
	GameState.film = 0
	_player.hands_empty = true
	GameState.save_game()
	var camp:= Terrain.CAMP
	_player.global_position = Vector3(camp.x + 2.0, _terrain.height_at(camp.x + 2.0, camp.y - 6.0) + Player.EYE_HEIGHT + 0.4, camp.y - 6.0)
	_player.velocity = Vector3.ZERO
	await _wait(1.0)
	_hud.fade_to(0.0, 1.5)
	_end_cutscene()
	_hud.update_stats()
	_hud.show_message("You wake up by the campfire. Your camera's gone%s. You feel... probed. (Toe has spare cameras.)" %
		(" — and $%d of undeveloped film with it" % lost if lost > 0 else ""))


## Grab the Leperchaun's gold, if he's not standing guard over it.
func _take_gold() -> void:
	if _pot == null or _pot.taken:
		return
	if Net.is_client():
		_net.request_gold()   # the host's Leperchaun decides
		return
	var guard:= _pot.guarded_by(_cryptids)
	if guard != null:
		_hud.show_message("He's right there guarding it! Lure him away first (bait, a trap...).")
		guard.hear_noise(_pot.global_position, 999.0)
		return
	host_take_gold(null)
	gold_result(true)


## Host (or single player): the pot changes hands; the Leperchaun goes after the thief.
## thief: a RemotePlayer, or null for this PC's player. Returns false if he's guarding it.
func host_take_gold(thief) -> bool:
	if _pot == null or _pot.taken:
		return false
	var guard:= _pot.guarded_by(_cryptids)
	if guard != null:
		guard.hear_noise(_pot.global_position, 999.0)
		return false
	_pot.take()
	if Net.online():
		_net.gold_taken()
	var who: Node3D = thief if thief != null else _player
	for c in _cryptids:
		if c.species_id == "leperchaun":
			if c.global_position.distance_to(who.global_position) < 40.0 and c.state != Cryptid.State.TRAPPED:
				c.player_ref = who
				c._enter_chase()
			else:
				c.hear_noise(_pot.global_position, 999.0)
	return true


## Whoever grabbed the gold: the money (or the bad news).
func gold_result(ok: bool) -> void:
	if not ok:
		_hud.show_message("He's right there guarding it! Lure him away first (bait, a trap...).")
		return
	if _pot != null and is_instance_valid(_pot):
		_pot.take()
	GameState.money += PotOfGold.VALUE
	GameState.save_game()
	_hud.update_stats()
	Audio.play("coins", 0.0)
	_hud.show_photo_popup("POT OF GOLD!  +$%d" % PotOfGold.VALUE)
	_hud.show_message("You nabbed the Leperchaun's gold. He is going to be FURIOUS.")


# ------------------------------------------------------------------ per-frame HUD

## The cryptid that matters most right now for the HUD.
func _focus() -> Cryptid:
	var best: Cryptid = null
	var best_rank:= -1
	var best_d:= 1e9
	var rank:= {Cryptid.State.CHASE: 5, Cryptid.State.TRAPPED: 4, Cryptid.State.EATING: 3, Cryptid.State.FLEE: 2, Cryptid.State.INVESTIGATE: 1}
	for c in _cryptids:
		var r: int = rank.get(c.state, 0)
		if Net.online() and c.state == Cryptid.State.CHASE and _net.target_id(c) != Net.my_id() and c.net_target != Net.my_id():
			r = 2   # it's after somebody else
		var d:= c.distance_to_player()
		if r > best_rank or (r == best_rank and d < best_d):
			best_rank = r
			best_d = d
			best = c
	return best if best_rank > 0 else null


func _ui_open() -> bool:
	return _poster.is_open() or _shop_ui.is_open() or _travel.is_open() or _pause.is_open() or _files.is_open() or _poster_wall.is_open() or _mp_panel.is_open()


## What E would do right now: "toe", "shop", "rv", "drive", "sleep", "develop", "exit" or "".
func _interaction() -> String:
	if _cutscene or _ui_open() or GameState.game_over:
		return ""
	if _player.indoors:
		var cam:= _player.first_person_camera()
		return _interior.focus_hotspot(cam.global_position, -cam.global_transform.basis.z)
	if _pot != null and _pot.player_near(_player.global_position):
		return "gold"
	if _player.global_position.distance_to(_toe.global_position) < TOE_TALK_DIST:
		return "toe"
	if _shop.player_near(_player.global_position):
		return "shop"
	if _rv.player_in_zone:
		return "rv"
	return ""


func _process(delta: float) -> void:
	var cam:= get_viewport().get_camera_3d()
	if cam:
		_place_moon(cam.global_position)
	if _fireflies and _player:
		_fireflies.global_position = _player.global_position + Vector3(0, 0.6, 0)
		_fireflies.visible = not _player.indoors
	if GameState.game_over or _ending:
		return
	_night_time += delta
	_interact_cool = maxf(0.0, _interact_cool - delta)
	_need_aim_cool = maxf(0.0, _need_aim_cool - delta)
	_hud.set_night_time(_night_time)
	_update_effects()
	var act:= _interaction()
	var labels:= {"toe": "Talk to Toe Rogan", "shop": "Bait & trap stand", "rv": "Enter the RV", "gold": "Grab the pot of gold"}
	if act == "":
		_hud.show_interact_prompt(false)
	elif labels.has(act):
		_hud.show_interact_prompt(true, labels[act])
	else:
		_hud.show_interact_prompt(true, _interior.hotspot_label(act))
	_touch.set_interact_visible(act != "")
	if _player.indoors:
		_hud.set_compass(_player.global_position, _player._yaw, [])
	else:
		_hud.set_compass(_player.global_position, _player._yaw, [
			{"pos": _rv.global_position, "label": "RV", "color": Color(0.45, 0.95, 1.0), "icon": "rv"},
			{"pos": _toe.global_position, "label": "TOE", "color": Color(1.0, 0.65, 0.3)},
		])
	_hud.set_flash_charge(_player.flash_ready_fraction())
	_hud.set_struggle(_ufo.struggle if _ufo != null and is_instance_valid(_ufo) and _ufo.is_beaming() else -1.0)
	if _mic != null:
		_hud.set_mic(_mic.level if _mic.active else -1.0, _mic.radius)
	# Toe Rogan looks over when you come near.
	if _toe_model and not _poster.is_open() and not _cutscene:
		_toe_model.play("talk" if _player.global_position.distance_to(_toe.global_position) < 8.0 else "idle")
	var f:= _focus()
	var ufo_on:= _ufo != null and is_instance_valid(_ufo) and _ufo.phase != UFO.Phase.LEAVE
	var chasing:= (f != null and f.state == Cryptid.State.CHASE or ufo_on) and not _player.indoors
	var want:= "chase" if chasing else "explore"
	if want != _music_state:
		_music_state = want
		Audio.set_music(want)
	if ufo_on and not _player.indoors:
		var ud:= Vector2(_ufo.global_position.x - _player.global_position.x, _ufo.global_position.z - _player.global_position.z).length()
		_hud.set_alert("UFO INCOMING — %dm!  Snap it before it gets you!" % int(ud) if not _ufo.is_beaming() else "", Color(0.5, 1.0, 0.55))
		_hud.set_danger(true)
		_hud.hide_hint()
		_hud.set_grab_warning(false)
		return
	if f == null or _player.indoors:
		_hud.set_alert("", Color(1, 1, 1))
		_hud.set_danger(false)
		if _player.is_snared():
			_hud.show_hint("Stuck in your own trap...")
		else:
			_hud.hide_hint()
		_hud.set_grab_warning(false)
		return
	match f.state:
		Cryptid.State.CHASE:
			_hud.set_chase_alert(f.distance_to_player(), f.display_name)
			_hud.set_danger(true)
			if f.is_player_hidden():
				_hud.show_hint("Hidden — stay still!")
			elif _player.is_snared():
				_hud.show_hint("You're stuck in a trap!")
			else:
				_hud.hide_hint()
			_hud.set_grab_warning(f.grab_progress > 0.0)
		Cryptid.State.TRAPPED:
			_hud.set_alert("%s IS TRAPPED! Get the shot!" % f.display_name.to_upper(), Color(0.4, 1, 1))
			_hud.set_danger(false)
			_hud.hide_hint()
			_hud.set_grab_warning(false)
		Cryptid.State.EATING:
			_hud.set_alert("%s is eating — sneak in for the shot!" % f.display_name, Color(0.6, 1, 0.5))
			_hud.set_danger(false)
			_hud.hide_hint()
			_hud.set_grab_warning(false)
		Cryptid.State.FLEE:
			_hud.set_alert("%s is bolting! Quick!" % f.display_name, Color(1, 0.85, 0.4))
			_hud.set_danger(false)
			_hud.hide_hint()
			_hud.set_grab_warning(false)
		_:
			_hud.set_alert("You hear something moving...", Color(1, 0.8, 0.2))
			_hud.set_danger(false)
			_hud.hide_hint()
			_hud.set_grab_warning(false)


func _input(event: InputEvent) -> void:
	if GameState.game_over and event is InputEventKey and event.keycode == KEY_R and event.pressed:
		_on_next_night()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _ui_open() and not GameState.game_over and not _ending:
		_player.set_aiming(false)
		_pause.open()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ events

func _on_photo_taken(result: Dictionary) -> void:
	var who: Array = result.get("species_list", [])
	if "ufo" in who and _ufo != null and is_instance_valid(_ufo):
		_ufo.spooked()
		_hud.show_message("YOU GOT THE UFO!! It's bolting — that one's worth a fortune.")
	if "santa" in who and _santa != null and is_instance_valid(_santa):
		_santa.take_off()
		if Net.online():
			_net.santa_snapped()
		_hud.show_message("HO HO HO! Santa's off — and you got him on film!")
	if result.get("in_frame", false) and not GameState.unsold_photos.is_empty():
		await _capture_photo(GameState.unsold_photos.back())
	_hud.flash()
	if result.get("in_frame", false):
		_hud.show_photo_popup("%s  $%d" % [str(result.get("reason", "Got it!")), int(result.get("value", 0))])
	else:
		_hud.show_photo_popup(str(result.get("reason", "No shot")))
	_hud.update_stats()


## Keep the actual picture (3D only, no HUD) so it can come up in the darkroom later.
func _capture_photo(rec: Dictionary) -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var key:= "p%d" % Time.get_ticks_usec()
	rec["img"] = key
	_hud.visible = false
	_player.set_flash_energy(4.0)
	await RenderingServer.frame_post_draw
	var img:= get_viewport().get_texture().get_image()
	_hud.visible = true
	_player.set_flash_energy(14.0)   # the visible flash still pops for the player
	if img == null or img.is_empty():
		return
	img.resize(320, int(320.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
	img.adjust_bcs(0.96, 1.12, 1.2)   # a touch of contrast and colour, like a real print
	GameState.photo_images[key] = ImageTexture.create_from_image(img)


func _on_film_empty() -> void:
	_hud.show_message("Out of film — Toe Rogan has fresh cameras by the fire.")


func _on_fell_in_water() -> void:
	Audio.play("wade", 2.0)
	_hud.black_out()
	_hud.fade_to(0.0, 0.6)
	_hud.show_message("Too deep to swim with the camera — you scramble back out.")


func _on_need_aim() -> void:
	if _need_aim_cool <= 0.0:
		_need_aim_cool = 4.0
		_hud.show_message("Hold RIGHT-CLICK to raise the camera, then LEFT-CLICK to snap.")


func _on_item_placed(kind: String, node: Node3D) -> void:
	_hud.update_stats()
	_hud.show_item(kind)
	if Net.online() and kind in ["bait", "trap"]:
		# Bait and traps live on the host (that's where the cryptids are).
		var xf:= node.global_transform
		node.queue_free()
		_net.place_item(kind, xf)
		_hud.show_message("Trap set. Don't step in it." if kind == "trap" else "Bait down. Something will smell that...")
		return
	if kind == "tripod":
		(node as Tripod).fired.connect(_on_tripod_fired.bind(node))
		_hud.show_message("Tripod cam set. It'll snap the first thing that walks in front of it. Stay out of its way.")
	elif kind == "trap":
		(node as Trap).sprung.connect(_on_trap_sprung.bind(node))
		_hud.show_message("Trap set. Don't step in it.")
	else:
		_hud.show_message("Bait down. Something will smell that...")


func _on_out_of_item(kind: String) -> void:
	_hud.show_item(kind)
	var names:= {"bait": "bait", "trap": "traps", "tripod": "tripod cams", "joint": "joints", "beer": "beer"}
	_hud.show_message("No %s left — the stand by the RV sells more." % names.get(kind, kind))


func _on_item_consumed(kind: String) -> void:
	_hud.show_item(kind)
	_hud.update_stats()
	if kind == "beer":
		_hud.show_message("*crack* ... ahh. Faster legs — and every cryptid can hear you now.")
	else:
		_hud.show_message("Whoa. Everything's... sloooow. Get your shot.")
		Audio.play("whoosh", -8.0)


## The tripod cam caught something (or someone).
func _on_tripod_fired(result: Dictionary, target: Node3D, tripod: Tripod) -> void:
	if target == _player:
		_hud.flash()
		_hud.show_message("Your tripod cam got a lovely shot of... you. Worth exactly $0.")
		return
	if not (target is Cryptid):
		_hud.show_message("Tripod cam went off on some random passer-by. Worth nothing.")
		return
	if not result.get("in_frame", false):
		_hud.show_message("Tripod cam went off — but whatever it caught is just a blur.")
		return
	var rec:= {"value": int(result["value"]), "quality": str(result["reason"]), "species": result["species_list"],
		"scores": result.get("scores", {}), "map": GameState.current_map, "tripod": true}
	GameState.unsold_photos.append(rec)
	_capture_view(Transform3D(Basis.looking_at(tripod.facing()), tripod.eye()), rec)
	_hud.show_photo_popup("TRIPOD CAM: %s  $%d" % [str(result["reason"]), int(result["value"])])
	Audio.play("cash_tick", -6.0)
	_hud.update_stats()


## Render a snapshot from somewhere other than your eyes (the tripod) for the darkroom.
func _capture_view(xf: Transform3D, rec: Dictionary) -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var key:= "p%d" % Time.get_ticks_usec()
	rec["img"] = key
	var sv:= SubViewport.new()
	sv.size = Vector2i(320, 180)
	sv.world_3d = get_viewport().world_3d
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cam:= Camera3D.new()
	cam.fov = 55.0
	cam.cull_mask = 0xFFFFF & ~(Player.LAYER_VIEWMODEL)
	sv.add_child(cam)
	add_child(sv)
	cam.global_transform = xf
	cam.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img:= sv.get_texture().get_image()
	sv.queue_free()
	if img == null or img.is_empty():
		return
	img.adjust_bcs(0.96, 1.12, 1.2)
	GameState.photo_images[key] = ImageTexture.create_from_image(img)


func _on_trap_sprung(victim: Node3D, trap: Node3D) -> void:
	if victim == _player:
		_hud.show_message("OUCH! You stepped in your own trap!")
		for c in _cryptids:
			c.hear_noise(trap.global_position, 45.0)  # that clang carries
	elif victim is Cryptid:
		_hud.show_message("GOT %s! Quick — photos!" % (victim as Cryptid).display_name.to_upper())


func _on_escaped(c: Cryptid) -> void:
	if Net.online() and c.player_ref is RemotePlayer:
		_hud.show_message("%s lost %s!" % [Net.name_of((c.player_ref as RemotePlayer).peer_id), c.display_name])
	else:
		_hud.show_message("You lost %s!" % c.display_name)
	Audio.play("escaped", -6.0)
	c.celebrate()


func _on_flashed_by_tourist(c: Cryptid) -> void:
	var d:= c.stun_time() if c.stun_time() > 0.0 else 1.5
	if Net.online() and c.player_ref is RemotePlayer:
		_net.tell_flashed((c.player_ref as RemotePlayer).peer_id, d)
		return
	flashed_by_tourist_remote(d)


## A tourist flashed this PC's player (called directly, or from the host online).
func flashed_by_tourist_remote(d: float) -> void:
	_player.stun(d)
	_tourist_flashes += 1
	if _tourist_flashes == UFO_AFTER_FLASHES - 1 and not _ufo_done:
		_hud.show_message("Another grey snapped you. They're starting to take a real interest in you...")
	elif _tourist_flashes >= UFO_AFTER_FLASHES and not _ufo_done and _ufo == null:
		_summon_ufo()
	else:
		_hud.show_message("A tourist just took YOUR picture! You're seeing spots...")


func _on_interact() -> void:
	if _interact_cool > 0.0:
		return
	match _interaction():
		"gold":
			_take_gold()
		"toe":
			_open_toe()
		"shop":
			_open_shop()
		"rv":
			_enter_rv()
		"exit":
			_exit_rv()
		"sleep", "bunk":
			if Net.is_client():
				_hud.show_message("Only the host (%s) can call it a night." % Net.name_of(1))
			else:
				_sleep()
		"drive":
			if Net.is_client():
				_hud.show_message("Only the host (%s) can drive." % Net.name_of(1))
			else:
				_open_travel()
		"develop":
			_develop()
		"posters":
			_open_ui()
			_poster_wall.open()


## Pause the world for a menu.
func _open_ui() -> void:
	_player.set_aiming(false)
	if Net.online():
		GameState.menu_open = true   # the world keeps going for everyone else
	else:
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hud.show_interact_prompt(false)


func _close_ui() -> void:
	get_tree().paused = false
	GameState.menu_open = false
	_interact_cool = 0.35
	if not _player.is_touch and not _cutscene:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _toe_model:
		_toe_model.play("idle")


# ------------------------------------------------------------------ shop

func _open_shop() -> void:
	_open_ui()
	_shop.greet()
	_shop_ui.open()


func _on_buy(item: String) -> void:
	var it:= Catalog.item(item)
	if str(it.get("kind", "gear")) != "gear":
		if GameState.buy_decor(item):
			Audio.play("cash", -6.0, 0.1)
			_shop.chat()
			_shop_ui.react("decor")
			GameState.save_game()
			_interior.refresh_decor()
			_rv.refresh_decor()
			_hud.show_message("%s — it's waiting in the RV." % str(it["name"]))
		else:
			Audio.play("dry_click", -4.0)
			_shop.laugh()
			_shop_ui.react("broke")
		_hud.update_stats()
		return
	var have: int = GameState.item_count(item)
	var price:= GameState.item_price(item)
	if have >= GameState.MAX_ITEMS:
		Audio.play("dry_click", -4.0)
		_shop.laugh()
		_shop_ui.react("full")
	elif GameState.money < price:
		Audio.play("dry_click", -4.0)
		_shop.laugh()
		_shop_ui.react("broke")
	elif GameState.buy(item):
		Audio.play("cash", -6.0, 0.1)
		_shop.chat()
		_shop_ui.react("bought")
		GameState.save_game()
	_hud.update_stats()


# ------------------------------------------------------------------ RV

func _begin_cutscene() -> void:
	_cutscene = true
	_player.set_aiming(false)
	_player.controls_locked = true
	_hud.show_interact_prompt(false)


func _end_cutscene() -> void:
	_cutscene = false
	_player.controls_locked = false
	_interact_cool = 0.35
	if not _player.is_touch:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout   # holds while paused


func _enter_rv() -> void:
	_begin_cutscene()
	_rv.open_door(true)
	Audio.play("door", -6.0)
	_player.face_point(_rv.global_position + Vector3(0, 1.3, 0) - _rv.door_out_dir() * 1.2, 0.3)
	_hud.fade_to(1.0, 0.45)
	await _wait(0.5)
	_was_third_person = _player.third_person
	if _player.third_person:
		_player.set_third_person(false)
	_player.indoors = true
	_interior.refresh_decor()
	_player.velocity = Vector3.ZERO
	_player.global_position = _interior.entry_point() + Vector3(0, Player.EYE_HEIGHT + 0.05, 0)
	_player.set_look(PI, -0.08)   # facing the darkroom, red light glowing
	_rv.open_door(false, 0.01)
	_hud.set_compass_visible(false)
	_hud.fade_to(0.0, 0.45)
	await _wait(0.3)
	if GameState.unsold_photos.is_empty():
		_hud.show_message("Home sweet home.")
	else:
		_hud.show_message("You've got $%d of undeveloped film. The darkroom's straight ahead." % GameState.undeveloped_value())
	_end_cutscene()


func _exit_rv() -> void:
	_begin_cutscene()
	Audio.play("door", -6.0)
	_hud.fade_to(1.0, 0.35)
	await _wait(0.4)
	_player.indoors = false
	var out:= _rv.door_front()
	_player.velocity = Vector3.ZERO
	_player.global_position = Vector3(out.x, _terrain.height_at(out.x, out.z) + Player.EYE_HEIGHT + 0.1, out.z)
	var d:= _rv.door_out_dir()
	_player.set_look(atan2(-d.x, -d.z), 0.0)
	if _was_third_person:
		_player.set_third_person(true)
	_rv.open_door(true, 0.01)
	_rv.open_door(false, 0.5)
	_hud.set_compass_visible(true)
	_hud.fade_to(0.0, 0.35)
	await _wait(0.2)
	_end_cutscene()


## A temporary camera for cutscenes, starting from wherever the player is looking.
func _cine_from_player() -> Camera3D:
	if _cine == null:
		_cine = Camera3D.new()
		_cine.fov = 70
		_cine.cull_mask = 0xFFFFF & ~(Player.LAYER_VIEWMODEL | Player.LAYER_BODY)
		add_child(_cine)
	var cam:= _player.active_camera()
	_cine.global_transform = cam.global_transform
	_cine.fov = cam.fov
	_cine.current = true
	_player.hands_empty = true
	return _cine


func _cine_to(xf: Transform3D, seconds: float) -> void:
	var tw:= create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_cine, "global_transform", xf, seconds)
	await tw.finished


func _cine_release() -> void:
	if _cine:
		_cine.current = false
	_player.hands_empty = false
	_player.active_camera().current = true


func _sleep() -> void:
	_begin_cutscene()
	_hud.set_hud_visible(false)
	_cine_from_player()
	await _cine_to(_interior.bed_view(), 1.4)
	Audio.play("snore", -6.0)
	_hud.fade_to(1.0, 2.2)
	_hud.show_message("Zzz...")
	await _wait(2.6)
	# Undeveloped photos keep overnight; you just get a fresh night.
	var keep:= GameState.unsold_photos.duplicate(true)
	GameState.end_night(false)
	GameState.unsold_photos = keep
	GameState.arrival = "sleep"
	if Net.is_host():
		_net.night_over(GameState.current_map, GameState.night, "sleep")
	_reload()


func _open_travel() -> void:
	_open_ui()
	_travel.open(_map)


func _on_travel(map_id: String) -> void:
	_travel.visible = false
	get_tree().paused = false
	_begin_cutscene()
	_hud.set_hud_visible(false)
	# The camera's left on the passenger seat, looking up at you driving.
	_interior.seat_driver()
	_hud.fade_to(1.0, 0.35)
	await _wait(0.4)
	_cine_from_player()
	_cine.fov = 82
	_cine.global_transform = _interior.seat_cam_view()
	_hud.fade_to(0.0, 0.5)
	_interior.headlights(true)
	Audio.play("engine", -2.0)
	_interior.start_road(true)
	# Handheld wobble as the RV rumbles along.
	var base:= _cine.global_transform
	var wob:= create_tween().set_loops(12)
	wob.tween_method(func(t: float):
		_cine.global_transform = base.rotated_local(Vector3.FORWARD, 0.012 * sin(t * TAU * 2.0)) \
			.translated_local(Vector3(0, 0.006 * sin(t * TAU * 3.0), 0)), 0.0, 1.0, 0.35)
	await _wait(1.2)
	_hud.show_title(str(Species.MAPS[map_id]["name"]).to_upper(), "next stop")
	await _wait(1.8)
	_hud.fade_to(1.0, 1.2)
	await _wait(1.3)
	var keep:= GameState.unsold_photos.duplicate(true)
	GameState.travel(map_id)
	GameState.unsold_photos = keep
	GameState.arrival = "travel"
	GameState.save_game()
	if Net.is_host():
		_net.night_over(GameState.current_map, GameState.night, "travel")
	_reload()


## The darkroom: each photo comes up on the line under the red light, and the money ticks in.
func _develop() -> void:
	if GameState.unsold_photos.is_empty():
		_hud.show_message("Nothing to develop. Go take some pictures!")
		_interact_cool = 0.5
		return
	_begin_cutscene()
	_hud.set_hud_visible(false)
	_cine_from_player()
	await _cine_to(_interior.develop_view(), 0.9)
	var photos: Array = GameState.unsold_photos.duplicate(true)
	var shown:= mini(photos.size(), 6)
	var base:= _interior.print_count()
	var running:= GameState.money
	for i in photos.size():
		var rec: Dictionary = photos[i]
		if i < shown:
			var tex: Texture2D = GameState.photo_images.get(str(rec.get("img", "")), null)
			var names: Array = []
			for id in rec.get("species", []):
				names.append(Species.display_name(id))
			var cap:= "%s  $%d" % [", ".join(names), int(rec.get("value", 0))]
			var m:= _interior.hang_print(base + i, maxi(base + shown, 4), tex, cap)
			Audio.play("develop", -8.0, 0.08)
			_interior.develop_print(m, 1.1)
			await _wait(0.7)
		running += int(rec.get("value", 0))
		Audio.play("cash_tick", -8.0, 0.1)
		_hud.show_photo_popup("+$%d" % int(rec.get("value", 0)))
	var before_files: Array = []
	for id in Species.DATA:
		if GameState.has_file(id):
			before_files.append(id)
	var gained:= GameState.develop()
	GameState.save_game()
	Audio.play("cash", -4.0)
	_hud.update_stats()
	var new_files: Array = []
	for id in Species.DATA:
		if GameState.has_file(id) and id not in before_files:
			new_files.append(Species.display_name(id))
	var msg:= "Developed: +$%d. Toe Rogan will want to see these." % gained
	if not new_files.is_empty():
		msg = "+$%d!  NEW CRYPTID FILE: %s  (Esc → Cryptid Files)" % [gained, ", ".join(new_files)]
	_hud.show_message(msg)
	for rec in photos:
		GameState.photo_images.erase(str(rec.get("img", "")))
	await _wait(1.6)
	await _cine_to(_player.active_camera().global_transform, 0.7)
	_cine_release()
	_hud.set_hud_visible(true)
	_hud.set_compass_visible(false)
	_end_cutscene()


# ------------------------------------------------------------------ getting grabbed

func _on_caught(c: Cryptid) -> void:
	if Net.online():
		# Online the night goes on: whoever got grabbed is knocked out and loses their film.
		if c.player_ref is RemotePlayer:
			_net.tell_caught((c.player_ref as RemotePlayer).peer_id, c.display_name)
		else:
			knocked_out(c.display_name)
		get_tree().create_timer(2.5).timeout.connect(func():
			if is_instance_valid(c):
				c.release_after_catch())
		return
	if GameState.game_over or _player.indoors:
		return
	GameState.game_over = true
	for k in _cryptids:
		k.frozen = true
	Audio.set_music("", 0.2)
	Audio.play_3d(c._voice_name("alert"), c.global_position, 4.0)
	Audio.play("lose", -3.0)
	_hud.show_lose(c.display_name)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Online: grabbed. Lose the undeveloped film, black out, come to at camp.
func knocked_out(who: String) -> void:
	if _cutscene:
		return
	_begin_cutscene()
	Audio.play("lose", -3.0)
	_hud.fade_to(1.0, 0.4)
	var lost:= GameState.undeveloped_value()
	for rec in GameState.unsold_photos:
		GameState.photo_images.erase(str(rec.get("img", "")))
	GameState.unsold_photos.clear()
	GameState.save_game()
	await _wait(1.6)
	var camp:= Terrain.CAMP
	_player.global_position = Vector3(camp.x - 2.0, _terrain.height_at(camp.x - 2.0, camp.y - 7.0) + Player.EYE_HEIGHT + 0.4, camp.y - 7.0)
	_player.velocity = Vector3.ZERO
	_hud.fade_to(0.0, 1.2)
	_end_cutscene()
	_hud.update_stats()
	_hud.show_message("%s got you! You come to back at camp%s." % [who, (" — your $%d of undeveloped film is gone" % lost) if lost > 0 else ""])


func _on_next_night() -> void:
	if _ending:
		return
	GameState.end_night(GameState.game_over)
	_reload()


func _reload() -> void:
	_ending = true
	AudioServer.playback_speed_scale = 1.0
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


# ------------------------------------------------------------------ Toe Rogan

func _open_toe() -> void:
	var missing:= GameState.missing_for_unlock(_map)
	var nxt:= Species.next_map(_map)
	var text:= ""
	var can_show:= false
	var where: String = str(Species.MAPS[_map].get("where", "out here"))
	if not missing.is_empty():
		text = "Dude. C'mere. You have any idea what's living %s? Look at this poster. Before I send you anywhere else, I need to see the whole set: every common and every uncommon. Developed photos, man, not stories." % where
	elif nxt != "" and not GameState.is_unlocked(nxt):
		text = "Wait. Wait, wait, wait. You got all of them? Show me. Right now."
		can_show = true
	elif nxt != "":
		text = "%s is open, man. Take the RV whenever you want. Go get weird." % Species.MAPS[nxt]["name"]
	else:
		text = "That's every spot I know about... for now. Keep shooting. The rare ones pay big."
	if GameState.film < GameState.FILM_MAX:
		if GameState.unsold_photos.is_empty():
			text += " Out of film? Hand it over."
		else:
			text += " Out of film? Hand it over. Heads up, though: anything you haven't developed goes with it."
	_open_ui()
	_poster.open(_map, text, can_show)
	if _toe_model:
		_toe_model.play("talk")
	Audio.play_3d("toe_talk", _toe.global_position + Vector3(0, 1.4, 0), 2.0)


func _on_toe_show() -> void:
	var nxt:= Species.next_map(_map)
	if nxt == "" or not GameState.missing_for_unlock(_map).is_empty():
		return
	GameState.unlock(nxt)
	_poster.visible = false
	if _toe_model:
		_toe_model.play("impressed")
	Audio.play("toe_whoa", 0.0)
	Audio.play("win", -4.0)
	_hud.show_win("NEW MAP UNLOCKED!", "Toe Rogan: \"That's insane, man. Okay — I know a spot. %s.\"\nDrive there from the RV whenever you're ready." % Species.MAPS[nxt]["name"])
	_hud.update_stats()
	get_tree().paused = false
	if not _hud.win_continue_pressed.is_connected(_hide_unlock):
		_hud.win_continue_pressed.connect(_hide_unlock)


func _hide_unlock() -> void:
	_hud._win_panel.visible = false
	_interact_cool = 0.35
	if not _player.is_touch:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Toe takes your camera, chucks it into the woods, and hands you a fresh one.
func _on_toe_reload() -> void:
	_poster.visible = false
	get_tree().paused = false
	if _player.hands_empty:
		await _toe_spare_camera()
		return
	_begin_cutscene()
	if not Net.online():
		for c in _cryptids:
			c.frozen = true
	_was_third_person = _player.third_person
	if _player.third_person:
		_player.set_third_person(false)
	# Step up in front of him and look at him.
	var front:= _toe.global_position + _toe.global_transform.basis.z * 1.25
	var stand:= Vector3(front.x, _terrain.height_at(front.x, front.z) + Player.EYE_HEIGHT + 0.05, front.z)
	var tw:= create_tween()
	tw.tween_property(_player, "global_position", stand, 0.35)
	await tw.finished
	_player.face_point(_toe.global_position + Vector3(0, 0.9, 0), 0.3)
	Audio.play_3d("toe_talk", _toe.global_position + Vector3(0, 1.4, 0), 2.0)
	_toe_model.play("swap", 1.0, 0.1)
	_toe_model.seek(0.0)
	var hand:= _toe_model.attach("hand_r")
	var prop:= _camera_prop()
	await _wait(0.5)
	# He grabs it out of your hands.
	_player.hands_empty = true
	if hand:
		hand.add_child(prop)
		prop.position = Vector3(0, -0.05, 0.06)
	else:
		_toe.add_child(prop)
		prop.position = Vector3(0.3, 1.0, 0.3)
	Audio.play("whoosh", -10.0)
	await _wait(1.0)
	# ...SLAMS it into the dirt in front of him, and it bounces up over his shoulder onto the pile.
	var start:= prop.global_position
	prop.reparent(self)
	prop.global_position = start
	var fwd:= _toe.global_transform.basis.z
	var side:= _toe.global_transform.basis.x
	var impact:= _toe.global_position + fwd * 0.85 + side * 0.25
	impact.y = _terrain.height_at(impact.x, impact.z) + 0.06
	var rest:= _pile_spot(GameState.cameras_thrown)
	var pre:= rest - Vector3(rest.x - impact.x, 0, rest.z - impact.z).normalized() * 0.55
	pre.y = _terrain.height_at(pre.x, pre.z) + 0.06
	var apex:= _toe.global_position + side * 0.45 + Vector3(0, 4.6, 0)   # Bezier control: clears his head
	Audio.play("whoosh", -4.0)
	var spike:= create_tween()
	spike.tween_property(prop, "global_position", impact, 0.16).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	spike.parallel().tween_property(prop, "rotation", Vector3(2.5, 0.4, 0.0), 0.16)
	await spike.finished
	Audio.play_3d("camera_crash", impact, 2.0)
	_dust_puff(impact)
	_player.shake(0.35)
	var bounce:= create_tween()
	bounce.tween_method(func(t: float):
		var a:= impact.lerp(apex, t)
		var b:= apex.lerp(pre, t)
		prop.global_position = a.lerp(b, t)
		prop.rotation = Vector3(2.5 + t * 13.0, 0.4 + t * 7.0, t * 4.0), 0.0, 1.0, 0.8)
	await bounce.finished
	Audio.play_3d("camera_crash", pre, -6.0)
	var hop:= create_tween()
	hop.tween_method(func(t: float):
		var p:= pre.lerp(rest, t)
		p.y += sin(PI * t) * 0.35
		prop.global_position = p, 0.0, 1.0, 0.25)
	hop.parallel().tween_property(prop, "rotation", Vector3(PI * 0.5, randf() * TAU, 0.0), 0.25)
	GameState.cameras_thrown += 1
	# The film was in that camera.
	var lost:= GameState.undeveloped_value()
	for rec in GameState.unsold_photos:
		GameState.photo_images.erase(str(rec.get("img", "")))
	GameState.unsold_photos.clear()
	GameState.save_game()
	await _wait(0.15)
	# Fresh camera out of his pocket...
	var fresh:= _camera_prop()
	if hand:
		hand.add_child(fresh)
		fresh.position = Vector3(0, -0.05, 0.06)
	await _wait(0.6)
	# ...and into your hands.
	fresh.queue_free()
	_player.hands_empty = false
	GameState.film = GameState.FILM_MAX
	Audio.play("reload", -4.0)
	_hud.update_stats()
	if lost > 0:
		_hud.show_message("\"Don't ask where I get these, man.\"  (The $%d of undeveloped film went with the old one.)" % lost)
	else:
		_hud.show_message("\"Don't ask where I get these, man.\"  Film: %d/%d" % [GameState.film, GameState.FILM_MAX])
	await _wait(0.6)
	if hand:
		hand.queue_free()
	_toe_model.play("idle")
	if _was_third_person:
		_player.set_third_person(true)
	for c in _cryptids:
		c.frozen = false
	_end_cutscene()


## No camera to smash (the greys took it): he just hands you a spare.
func _toe_spare_camera() -> void:
	_begin_cutscene()
	_player.face_point(_toe.global_position + Vector3(0, 0.9, 0), 0.3)
	Audio.play_3d("toe_talk", _toe.global_position + Vector3(0, 1.4, 0), 2.0)
	_toe_model.play("swap", 1.0, 0.1)
	await _wait(1.2)
	_player.hands_empty = false
	GameState.film = GameState.FILM_MAX
	Audio.play("reload", -4.0)
	_hud.update_stats()
	_hud.show_message("\"Aliens, huh? Happens to the best of us, man.\"  Fresh camera: %d shots." % GameState.FILM_MAX)
	await _wait(0.5)
	_toe_model.play("idle")
	_end_cutscene()


## Where the n-th thrown camera comes to rest: a growing heap behind Toe Rogan.
func _pile_spot(n: int) -> Vector3:
	var back:= -_toe.global_transform.basis.z
	var centre:= _toe.global_position + back * 5.5 + _toe.global_transform.basis.x * 0.8
	var r:= RandomNumberGenerator.new()
	r.seed = 7919 * (n + 1)
	var rad:= 0.15 + sqrt(float(n)) * 0.28 * r.randf()
	var ang:= r.randf() * TAU
	var p:= centre + Vector3(cos(ang) * rad, 0, sin(ang) * rad)
	# The heap rises in the middle as it grows.
	var mound:= maxf(0.0, 1.0 - rad / (0.4 + sqrt(float(n + 1)) * 0.28)) * minf(0.9, float(n) * 0.035)
	p.y = _terrain.height_at(p.x, p.z) + 0.06 + mound
	return p


## Every camera Toe has ever thrown is still out there.
func _spawn_camera_pile() -> void:
	var count:= mini(GameState.cameras_thrown, 60)
	for i in count:
		var c:= _camera_prop()
		add_child(c)
		var r:= RandomNumberGenerator.new()
		r.seed = 31 * (i + 1)
		c.global_position = _pile_spot(i)
		c.rotation = Vector3(r.randf_range(-0.6, 0.6) + (PI * 0.5 if r.randf() < 0.4 else 0.0), r.randf() * TAU, r.randf_range(-0.6, 0.6))


func _dust_puff(at: Vector3) -> void:
	var p:= CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 24
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, -4.0, 0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.14
	var m:= SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 3
	var mat:= StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.45, 0.32)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material = mat
	p.mesh = m
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(1.5, false).timeout.connect(p.queue_free)


func _camera_prop() -> Node3D:
	# Lens along +Z, like the old box prop.
	return CharacterModel.load_model("res://models/camera_lo.glb", 0.003)


# ------------------------------------------------------------------ sky + quality

func _apply_quality() -> void:
	if _env == null:
		return
	var s: Dictionary = GameState.settings
	var glow:= float(s.get("glow", 0.5))
	var ao:= float(s.get("ssao", 0.6))
	var fog:= float(s.get("vol_fog", 0.4))
	var sh:= float(s.get("shadows", 1.0))
	_env.glow_enabled = glow > 0.001
	_env.glow_intensity = 1.6 * glow
	_env.glow_strength = 0.8 + 0.4 * glow
	_env.glow_bloom = 0.12 * glow
	_env.glow_hdr_threshold = 1.1
	_env.ssao_enabled = ao > 0.001
	_env.ssao_radius = 1.2
	_env.ssao_intensity = 0.5 + 3.0 * ao
	_env.volumetric_fog_enabled = fog > 0.001
	_env.volumetric_fog_density = 0.025 * fog
	_env.volumetric_fog_albedo = Color(0.55, 0.55, 0.8)
	_env.volumetric_fog_length = 80.0
	if _moon:
		_moon.shadow_enabled = sh > 0.001
		_moon.shadow_opacity = sh
		_moon.shadow_bias = 0.04
		_moon.shadow_normal_bias = 1.5
		_moon.directional_shadow_max_distance = 70.0
		_moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		_moon.shadow_blur = 1.5


## The moon disc sits exactly where the moonlight comes from (so shadows point away from it)
## and travels with the camera like a real sky object.
func _place_moon(eye: Vector3) -> void:
	if _moon and _moon_disc:
		_moon_disc.global_position = eye + _moon.global_transform.basis.z * 380.0


func _setup_sky() -> void:
	var st:= Species.style(_map)
	var env:= WorldEnvironment.new()
	var e:= Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = st["sky"]
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = st["ambient"]
	e.ambient_light_energy = float(st["ambient_energy"])
	e.fog_enabled = true
	e.fog_light_color = st["fog"]
	e.fog_density = float(st["fog_density"])
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	env.environment = e
	add_child(env)
	_env = e
	var moon:= DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-50, 30, 0)
	moon.light_color = Color(0.7, 0.75, 1.0)
	moon.light_energy = float(st["moon_energy"])
	moon.light_cull_mask = 0xFFFFF & ~RVInterior.LAYER   # no moonlight through the RV roof
	add_child(moon)
	_moon = moon
	_apply_quality()
	var disc:= MeshInstance3D.new()
	var sm:= SphereMesh.new()
	sm.radius = 14.0
	sm.height = 28.0
	disc.mesh = sm
	var mmat:= StandardMaterial3D.new()
	mmat.albedo_color = Color(1.0, 0.95, 0.7)
	mmat.emission_enabled = true
	mmat.emission = Color(1.0, 0.9, 0.5)
	mmat.disable_fog = true
	disc.material_override = mmat
	# The disc sits right in the moonlight's path, so it must never cast a shadow
	# (it used to throw a 14 m shadow over wherever you stood).
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	_moon_disc = disc
	_place_moon(Vector3.ZERO)
	var rng:= RandomNumberGenerator.new()
	rng.randomize()
	var star_mesh:= SphereMesh.new()
	star_mesh.radius = 0.9
	star_mesh.height = 1.8
	star_mesh.radial_segments = 6
	star_mesh.rings = 3
	var mm:= MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = star_mesh
	mm.instance_count = 260
	for i in mm.instance_count:
		var ang:= rng.randf_range(0, TAU)
		var elev:= rng.randf_range(0.12, 1.4)
		var r:= 450.0
		var p:= Vector3(cos(ang) * cos(elev), sin(elev), sin(ang) * cos(elev)) * r
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.5, 1.4)), p))
	var stars:= MultiMeshInstance3D.new()
	stars.name = "Stars"
	stars.multimesh = mm
	var smat:= StandardMaterial3D.new()
	smat.albedo_color = Color(1, 1, 1)
	smat.emission_enabled = true
	smat.emission = Color(1, 1, 1)
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.disable_fog = true
	stars.material_override = smat
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stars)


# ------------------------------------------------------------------ online

## Joining PC: the host's cryptids (as puppets), pot of gold and Santa.
func build_puppet_world(w: Dictionary) -> void:
	for c in _cryptids:
		if is_instance_valid(c):
			c.queue_free()
	_cryptids.clear()
	var scene:= load("res://cryptid.tscn") as PackedScene
	var roster: Array = w.get("roster", [])
	for i in roster.size():
		var c:= scene.instantiate() as Cryptid
		c.configure(str(roster[i][0]))
		c.puppet = true
		c.net_index = i
		c.terrain = _terrain
		c.city = _city
		c.forward = _net.forward_for(i)
		add_child(c)
		c.global_position = roster[i][1]
		c.player_ref = _player
		c.bushes = _forest.bushes
		_cryptids.append(c)
	if not _cryptids.is_empty():
		_bigfoot = _cryptids[0]
		_player.bigfoot_ref = _bigfoot
	var pot: Array = w.get("pot", [])
	if not pot.is_empty() and _pot == null:
		_pot = PotOfGold.new()
		add_child(_pot)
		_pot.global_position = pot[0]
		if bool(pot[1]):
			_pot.take()
	if bool(w.get("santa", false)) and _santa == null:
		_spawn_santa()
	_hud.show_message("Joined %s's game. %d players." % [Net.name_of(1), Net.players.size()])


## Joining PC: the host slept or drove; follow them (your undeveloped film comes along).
func follow_host(map_id: String, night: int, how: String) -> void:
	if _ending:
		return
	var keep:= GameState.unsold_photos.duplicate(true)
	GameState.current_map = map_id
	GameState.night = night
	GameState.film = GameState.FILM_MAX
	GameState.unsold_photos = keep
	GameState.arrival = how
	GameState.save_game()
	_hud.fade_to(1.0, 0.6)
	_hud.show_message("%s is %s..." % [Net.name_of(1), "driving on" if how == "travel" else "calling it a night"])
	await _wait(0.8)
	_reload()


func on_player_arrived(id: int) -> void:
	_hud.show_message("%s is here." % Net.name_of(id))
	_update_net_label()


func on_player_left(_id: int, pname: String) -> void:
	_hud.show_message("%s left the game." % pname)
	_update_net_label()


## Lost the host (or left): carry on alone on this map.
func _on_left_game(reason: String) -> void:
	_hud.show_message(reason)
	if not _ending:
		_ending = true
		await get_tree().create_timer(1.5).timeout
		get_tree().paused = false
		get_tree().reload_current_scene()


func _update_net_label() -> void:
	if _hud == null:
		return
	if not Net.online():
		_hud.set_net_status("")
		return
	var names: Array = []
	for id in Net.players:
		names.append(Net.name_of(id))
	_hud.set_net_status(("HOSTING" if Net.is_host() else "ONLINE") + "  ·  " + ", ".join(names))
