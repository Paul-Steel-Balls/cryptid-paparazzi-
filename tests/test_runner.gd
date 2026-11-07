extends Node





var _passed:= 0
var _failed:= 0
var _caught_signal:= false
var _escaped_signal:= false


func _check(name: String, cond: bool) -> void:
	if cond:
		_passed += 1
		print("PASS: ", name)
	else:
		_failed += 1
		print("FAIL: ", name)


func _ready() -> void:
	GameState.saving_enabled = false
	GameState.reset()
	_test_scoring()
	_test_film_and_develop()
	_test_player_snap()
	_test_bigfoot()
	_test_hud()
	_test_scene_fixes()
	_test_escape()
	_test_hud_chase()
	_test_render_fixes()
	_test_terrain()
	await _test_terrain_physics()
	_test_inventory()
	_test_bait()
	_test_traps()
	_test_third_person()
	_test_audio()
	_test_models()
	await _test_movement()
	_test_species()
	_test_behaviours()
	_test_album_and_unlocks()
	_test_save_roundtrip()
	await _test_multi_photo()
	await _test_maps()
	await _test_v08()
	_test_overnight()
	await _test_v081()
	await _test_v09()
	await _test_v010()
	await _test_v011()
	_test_v012()
	_test_v013()
	await _test_v014()
	print("RESULT: %d/%d checks passed" % [_passed, _passed + _failed])
	if _failed > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func _test_scoring() -> void:
	var cam_pos:= Vector3(0, 1.7, 30)
	var cam_fwd:= Vector3(0, 0, -1)
	var bf_pos:= Vector3(0, 1.5, 20)
	var facing_toward:= Vector3(0, 0, 1)
	var facing_away:= Vector3(0, 0, -1)

	var r1:= PhotoScoring.evaluate(bf_pos, facing_toward, cam_pos, cam_fwd, PhotoScoring.CryptidState.WANDER)
	_check("scoring: in frame, facing, 10m, wander = 62", r1["in_frame"] == true and r1["score"] == 62)

	var r2:= PhotoScoring.evaluate(bf_pos, facing_away, cam_pos, cam_fwd, PhotoScoring.CryptidState.WANDER)
	_check("scoring: in frame, not facing, 10m, wander = 47", r2["in_frame"] == true and r2["score"] == 47)

	var r3:= PhotoScoring.evaluate(bf_pos, facing_toward, cam_pos, cam_fwd, PhotoScoring.CryptidState.CHASE)
	_check("scoring: danger bonus CHASE = 93", r3["in_frame"] == true and r3["score"] == 93)
	var r4:= PhotoScoring.evaluate(bf_pos, facing_toward, cam_pos, cam_fwd, PhotoScoring.CryptidState.INVESTIGATE)
	_check("scoring: danger bonus INVESTIGATE = 93", r4["in_frame"] == true and r4["score"] == 93)

	var r5:= PhotoScoring.evaluate(bf_pos, facing_toward, cam_pos, Vector3(0, 0, 1), PhotoScoring.CryptidState.WANDER)
	_check("scoring: out of frame = 0", r5["in_frame"] == false and r5["score"] == 0)

	var r6:= PhotoScoring.evaluate(Vector3(0, 1.5, -10), facing_toward, cam_pos, cam_fwd, PhotoScoring.CryptidState.WANDER)
	_check("scoring: too far = 0", r6["in_frame"] == false and r6["score"] == 0)

	var r7:= PhotoScoring.evaluate(Vector3(0, 1.5, 22), facing_toward, cam_pos, cam_fwd, PhotoScoring.CryptidState.WANDER)
	var r8:= PhotoScoring.evaluate(Vector3(0, 1.5, 10), facing_toward, cam_pos, cam_fwd, PhotoScoring.CryptidState.WANDER)
	_check("scoring: closer = higher score", r7["score"] > r8["score"])
	_check("scoring: 8m facing wander = 65", r7["score"] == 65)


func _test_film_and_develop() -> void:
	GameState.reset()
	_check("film: starts at 6", GameState.film == 6)
	GameState.film -= 1
	_check("film: snap decrements to 5", GameState.film == 5)
	GameState.film = GameState.FILM_MAX
	_check("film: reload restores 6", GameState.film == 6)
	GameState.unsold_photos.append({"value": 50, "quality": "GREAT"})
	GameState.unsold_photos.append({"value": 30, "quality": "OK"})
	var gained:= GameState.develop()
	_check("develop: sums to 80", gained == 80 and GameState.money == 80)
	_check("develop: clears unsold", GameState.unsold_photos.is_empty())


func _test_player_snap() -> void:
	GameState.reset()
	var p_scene:= load("res://player.tscn")
	var player:= p_scene.instantiate() as Player
	add_child(player)
	var bf_scene:= load("res://cryptid.tscn")
	var bf:= bf_scene.instantiate() as Cryptid
	bf.position = Vector3(0, 1.7, 0)
	add_child(bf)
	player.bigfoot_ref = bf
	player.position = Vector3(0, 1.0, 20)
	player.force_update_transform()
	bf.force_update_transform()
	player.get_node("Camera3D").force_update_transform()

	GameState.film = 0
	player.snap_photo()
	_check("snap: no film = no photo", GameState.unsold_photos.is_empty() and GameState.film == 0)

	GameState.film = 6
	player.snap_photo()
	_check("snap: with film takes photo", GameState.film == 5 and GameState.unsold_photos.size() == 1)
	player.queue_free()
	bf.queue_free()


func _test_bigfoot() -> void:
	var bf_scene:= load("res://cryptid.tscn")
	var bf:= bf_scene.instantiate() as Cryptid
	bf.position = Vector3(0, 1.7, 0)
	add_child(bf)
	var dummy:= Node3D.new()
	dummy.position = Vector3(0, 1.0, 10)
	add_child(dummy)
	bf.player_ref = dummy
	_check("bigfoot: starts WANDER", bf.state == Cryptid.State.WANDER)
	bf.hear_noise(Vector3(5, 0, 5))
	_check("bigfoot: noise -> INVESTIGATE", bf.state == Cryptid.State.INVESTIGATE)

	var bf2:= bf_scene.instantiate() as Cryptid
	bf2.position = Vector3(0, 1.7, 0)
	add_child(bf2)
	bf2.on_flash(Vector3(0, 0, 60))
	_check("bigfoot: far flash = no reaction", bf2.state == Cryptid.State.WANDER)

	bf2.on_flash(Vector3(0, 0, 10))
	_check("bigfoot: near flash -> CHASE", bf2.state == Cryptid.State.CHASE)

	var bf3:= bf_scene.instantiate() as Cryptid
	bf3.position = Vector3(0, 1.7, 0)
	add_child(bf3)
	var dummy3:= Node3D.new()
	dummy3.position = Vector3(0, 1.0, 5)
	add_child(dummy3)
	dummy3.force_update_transform()
	bf3.player_ref = dummy3
	bf3._physics_process(0.1)
	_check("bigfoot: proximity -> CHASE", bf3.state == Cryptid.State.CHASE)


	var bf4:= bf_scene.instantiate() as Cryptid
	bf4.position = Vector3(20, 1.7, 0)
	add_child(bf4)
	var dummy4:= Node3D.new()
	dummy4.position = Vector3(20, 1.0, 0.5)
	add_child(dummy4)
	dummy4.force_update_transform()
	bf4.player_ref = dummy4
	_caught_signal = false
	bf4.caught_player.connect(func(): _caught_signal = true)
	bf4.state = Cryptid.State.CHASE
	bf4._physics_process(0.1)
	_check("bigfoot: 0.1s contact = no catch yet", not _caught_signal and bf4.state == Cryptid.State.CHASE)
	for _i in 5:
		bf4._physics_process(0.1)
	_check("bigfoot: catch triggers signal after 0.5s", _caught_signal and bf4.state == Cryptid.State.CAUGHT)
	bf.queue_free()
	bf2.queue_free()
	bf3.queue_free()
	bf4.queue_free()


func _test_hud() -> void:
	var hud:= HUD.new()
	add_child(hud)
	hud.show_win()
	_check("hud: win panel shows", hud._win_panel.visible)
	hud.show_lose()
	_check("hud: lose panel shows", hud._lose_panel.visible)
	GameState.reset()
	GameState.money = 125
	GameState.unsold_photos = [{"value": 40}, {"value": 15}]
	hud.update_stats()
	_check("hud: money is just $ and the amount", hud._money_label.text == "$125")
	_check("hud: undeveloped film value shown as $", hud._undev_label.text == "$55")
	_check("hud: money green, undeveloped yellow", hud._money_label.get_theme_color("font_color").g > 0.9 and hud._undev_label.get_theme_color("font_color").b < 0.5)
	_check("hud: night shown top-left", hud._night_label.text == "NIGHT %d" % GameState.night)
	hud.set_night_time(65.4)
	_check("hud: night timer m:ss", hud._timer_label.text == "1:05")
	hud.set_aiming(true)
	_check("hud: viewfinder (with film count) shows while aiming", hud._viewfinder.visible and not hud._crosshair.visible)
	hud.set_aiming(false)
	_check("hud: viewfinder hides when lowered", not hud._viewfinder.visible)
	GameState.traps = 3
	hud.show_item("trap")
	_check("hud: item popup shows trap count out of 5", hud._item_box.kind == "trap" and hud._item_box.count == 3 and hud._item_box.max_count == 5 and hud._item_box.modulate.a > 0.9)
	hud.set_compass(Vector3.ZERO, 0.0, [{"pos": Vector3(0, 0, -30), "label": "RV", "icon": "rv"}])
	_check("hud: compass takes markers", hud._compass.markers.size() == 1)
	_check("hud: old film/inventory labels are gone", hud.get("_film_label") == null and hud.get("_inv_label") == null)
	hud.queue_free()
	GameState.reset()


func _test_scene_fixes() -> void:

	var forest:= Forest.new(1234)
	add_child(forest)
	var ground: MeshInstance3D = forest.terrain.get_node("Ground")
	var aabb:= ground.get_aabb()
	_check("fix: terrain covers >= 240x240", aabb.size.x >= 240.0 and aabb.size.z >= 240.0)
	_check("fix: no giant wall-like mesh (the old vertical ground bug)", _count_wall_meshes(forest) == 0)
	_check("fix: forest records bush hiding spots", forest.bushes.size() >= 10)
	forest.free()

	var p_scene:= load("res://player.tscn")
	var player:= p_scene.instantiate() as Player
	add_child(player)
	var cam:= player.get_node("Camera3D") as Camera3D
	_check("fix: camera far >= 500", cam.far >= 500.0)
	player.free()


	var main_scene: PackedScene = load("res://main.tscn")
	var main_node: Node = main_scene.instantiate()
	add_child(main_node)
	var has_fog_volume:= false
	var fog_density:= -1.0
	var bg_is_color:= false
	var stack: Array = [main_node]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is FogVolume:
			has_fog_volume = true
		if n is WorldEnvironment:
			var env:= (n as WorldEnvironment).environment
			if env != null:
				fog_density = env.fog_density
				bg_is_color = env.background_mode == Environment.BG_COLOR
		for c in n.get_children():
			stack.append(c)
	_check("fix: no FogVolume in scene", not has_fog_volume)
	_check("fix: fog density <= 0.005", fog_density >= 0.0 and fog_density <= 0.005)
	_check("fix: background is BG_COLOR (no skybox cube)", bg_is_color)
	main_node.free()


func _test_escape() -> void:
	var bf_scene:= load("res://cryptid.tscn")

	var p_scene:= load("res://player.tscn")
	var player:= p_scene.instantiate() as Player
	add_child(player)
	var bf:= bf_scene.instantiate() as Cryptid
	add_child(bf)
	_check("escape: player walk 5.0", player.walk_speed == 5.0)
	_check("escape: player sprint 7.0", player.sprint_speed == 7.0)
	_check("escape: bigfoot wander 3.5", bf.wander_speed == 3.5)
	_check("escape: bigfoot chase 6.0", bf.chase_speed == 6.0)
	_check("escape: chase < sprint", bf.chase_speed < player.sprint_speed)
	_check("escape: wander < walk", bf.wander_speed < player.walk_speed)
	player.free()
	bf.free()

	var bf2:= bf_scene.instantiate() as Cryptid
	bf2.position = Vector3(0, 1.7, 0)
	add_child(bf2)
	var dummy:= Node3D.new()
	dummy.position = Vector3(10, 1.0, 0)
	add_child(dummy)
	dummy.force_update_transform()
	bf2.player_ref = dummy
	_escaped_signal = false
	bf2.escaped.connect(func(): _escaped_signal = true)
	bf2.on_flash(dummy.global_position)
	for _i in 35:
		dummy.position = Vector3(bf2.position.x + 30.0, 1.0, bf2.position.z)
		dummy.force_update_transform()
		bf2._physics_process(0.1)
	_check("escape: >25m for 3s -> WANDER", bf2.state == Cryptid.State.WANDER)
	_check("escape: distance give-up emits escaped", _escaped_signal)
	bf2.free()
	dummy.free()

	var bf3:= bf_scene.instantiate() as Cryptid
	bf3.position = Vector3(0, 1.7, 0)
	add_child(bf3)
	var wall:= StaticBody3D.new()
	var wall_col:= CollisionShape3D.new()
	var wall_box:= BoxShape3D.new()
	wall_box.size = Vector3(20, 4, 0.5)
	wall_col.shape = wall_box
	wall.add_child(wall_col)
	wall.position = Vector3(0, 2, 5)
	add_child(wall)
	var dummy3:= Node3D.new()
	dummy3.position = Vector3(0, 1.0, 10)
	add_child(dummy3)
	dummy3.force_update_transform()
	bf3.player_ref = dummy3
	_escaped_signal = false
	bf3.escaped.connect(func(): _escaped_signal = true)
	bf3.on_flash(dummy3.global_position)
	for _i in 45:
		bf3._physics_process(0.1)
	_check("escape: LOS blocked 4s -> WANDER", bf3.state == Cryptid.State.WANDER)
	_check("escape: LOS give-up emits escaped", _escaped_signal)
	bf3.free()
	wall.free()
	dummy3.free()

	var forest2:= Forest.new()
	add_child(forest2)
	var bush_pos:= Vector2.ZERO
	var bush_rad:= 0.0
	if forest2.bushes.size() > 0:
		bush_pos = forest2.bushes[0].get("pos", Vector2.ZERO)
		bush_rad = float(forest2.bushes[0].get("radius", 0.0))
	_check("escape: forest has a bush to test", bush_rad > 0.0)
	var bf4:= bf_scene.instantiate() as Cryptid
	bf4.position = Vector3(bush_pos.x + 10.0, 1.7, bush_pos.y)
	add_child(bf4)
	var dummy4:= Node3D.new()
	dummy4.position = Vector3(bush_pos.x, 1.0, bush_pos.y)
	add_child(dummy4)
	dummy4.force_update_transform()
	bf4.player_ref = dummy4
	bf4.bushes = forest2.bushes
	_check("escape: player in bush = hidden", bf4.is_player_hidden())
	_escaped_signal = false
	bf4.escaped.connect(func(): _escaped_signal = true)
	bf4.on_flash(dummy4.global_position)
	for _i in 45:
		bf4._physics_process(0.1)
	_check("escape: bush hide 4s -> WANDER", bf4.state == Cryptid.State.WANDER)
	_check("escape: bush give-up emits escaped", _escaped_signal)
	_check("escape: bush hide does not catch", bf4.state != Cryptid.State.CAUGHT)
	bf4.free()
	dummy4.free()
	forest2.free()


	var bf5:= bf_scene.instantiate() as Cryptid
	bf5.position = Vector3(0, 1.7, 0)
	add_child(bf5)
	var dummy5:= Node3D.new()
	dummy5.position = Vector3(0, 1.0, 1.0)
	add_child(dummy5)
	dummy5.force_update_transform()
	bf5.player_ref = dummy5
	_caught_signal = false
	bf5.caught_player.connect(func(): _caught_signal = true)
	bf5.on_flash(dummy5.global_position)
	for _i in 3:
		bf5._physics_process(0.1)
	_check("escape: 0.3s contact = no catch", not _caught_signal and bf5.state == Cryptid.State.CHASE)
	dummy5.position = Vector3(0, 1.0, 10.0)
	dummy5.force_update_transform()
	bf5._physics_process(0.1)
	_check("escape: breaking contact resets grab", bf5.grab_progress == 0.0)
	dummy5.position = Vector3(0, 1.0, 1.0)
	dummy5.force_update_transform()
	for _i in 3:
		bf5._physics_process(0.1)
	_check("escape: 0.3s after reset = no catch", not _caught_signal and bf5.state == Cryptid.State.CHASE)
	for _i in 3:
		bf5._physics_process(0.1)
	_check("escape: 0.6s continuous contact = catch", _caught_signal and bf5.state == Cryptid.State.CAUGHT)
	bf5.free()
	dummy5.free()


func _test_hud_chase() -> void:
	var hud:= HUD.new()
	add_child(hud)
	hud.set_chase_alert(12.3)
	_check("hud: chase alert shows RUN + distance", hud._alert_label.visible and "RUN!" in hud._alert_label.text and "12" in hud._alert_label.text)
	hud.show_hint("Hidden — stay still!")
	_check("hud: hint shows", hud._hint_label.visible and hud._hint_label.text == "Hidden — stay still!")
	hud.hide_hint()
	_check("hud: hint hides", not hud._hint_label.visible)
	hud.set_grab_warning(true)
	_check("hud: grab warning shows", hud._grab_label.visible)
	hud.set_grab_warning(false)
	_check("hud: grab warning hides", not hud._grab_label.visible)
	hud.queue_free()


func _test_render_fixes() -> void:













	var forest:= Forest.new(99)
	add_child(forest)
	var ground_mesh: Mesh = (forest.terrain.get_node("Ground") as MeshInstance3D).mesh
	var min_trunk_collider:= 999.0
	var stack: Array = [forest]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is CollisionShape3D:
			var cs:= n as CollisionShape3D
			if cs.shape is CylinderShape3D:
				min_trunk_collider = minf(min_trunk_collider, (cs.shape as CylinderShape3D).radius)
		for c in n.get_children():
			stack.append(c)
	var max_edge:= _max_triangle_edge(ground_mesh)
	_check("render: terrain max triangle edge <= 15m", max_edge > 0.0 and max_edge <= 15.0)
	_check("render: terrain normals all point up", _min_normal_y(ground_mesh) > 0.2)
	_check("render: trunk collider radius >= 0.6 (camera stays off trunk)", min_trunk_collider >= 0.6)
	forest.free()



	var main_scene: PackedScene = load("res://main.tscn")
	var main_node: Node = main_scene.instantiate()
	add_child(main_node)
	var bad_planes:= 0
	var stack2: Array = [main_node]
	while not stack2.is_empty():
		var n = stack2.pop_back()
		if n is MeshInstance3D:
			var mi:= n as MeshInstance3D
			if mi.mesh is PlaneMesh:
				var pm:= mi.mesh as PlaneMesh
				# Big ground-like planes need subdivisions (shadow fix); small quads (prints, windows) don't.
				if pm.size.x * pm.size.y > 100.0 and (pm.subdivide_width < 32 or pm.subdivide_depth < 32):
					bad_planes += 1
		for c in n.get_children():
			stack2.append(c)
	_check("render: no un-subdivided PlaneMesh in full scene", bad_planes == 0)
	main_node.free()




func _count_wall_meshes(root: Node) -> int:
	var walls:= 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D:
			var a:= (n as MeshInstance3D).get_aabb()
			var t:= (n as MeshInstance3D).global_transform
			var size:= (t.basis * a.size).abs()
			if size.y > 60.0 and minf(size.x, size.z) < 5.0:
				walls += 1
		for c in n.get_children():
			stack.append(c)
	return walls


func _min_normal_y(mesh: Mesh) -> float:
	var arrays:= mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var m:= 1.0
	for nrm in normals:
		m = minf(m, nrm.y)
	return m


func _test_terrain() -> void:
	var t:= Terrain.new(4242)
	add_child(t)
	var lo:= 1e9
	var hi:= -1e9
	for x in range(-90, 91, 10):
		for z in range(-90, 91, 10):
			var h:= t.height_at(x, z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	_check("terrain: has real hills and valleys (relief >= 8m)", hi - lo >= 8.0)
	var camp_ok:= true
	for a in 12:
		var p:= Terrain.CAMP + Vector2(cos(a), sin(a)) * 10.0
		if absf(t.height_at(p.x, p.y) - t.camp_height()) > 0.05:
			camp_ok = false
	_check("terrain: camp clearing is flat", camp_ok)
	var grid_ok:= true
	for i in 20:
		var x:= -Terrain.HALF + Terrain.STEP * (i * 5)
		var z:= -Terrain.HALF + Terrain.STEP * (i * 3)
		if absf(t.height_at(x, z) - t._vh(i * 5, i * 3)) > 0.001:
			grid_ok = false
	_check("terrain: height_at matches grid vertices", grid_ok)
	_check("terrain: rim rises at the map edge", t.height_at(0, -Terrain.HALF + 2.0) > t.height_at(0, -Terrain.HALF * 0.5) + 5.0)
	t.free()


func _test_terrain_physics() -> void:
	var t:= Terrain.new(777)
	add_child(t)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space:= get_viewport().world_3d.direct_space_state
	var worst:= 0.0
	var hits:= 0
	for i in 25:
		var x:= randf_range(-100, 100)
		var z:= randf_range(-100, 100)
		var q:= PhysicsRayQueryParameters3D.create(Vector3(x, 200, z), Vector3(x, -200, z))
		var hit:= space.intersect_ray(q)
		if not hit.is_empty():
			hits += 1
			worst = maxf(worst, absf(hit["position"].y - t.height_at(x, z)))
	_check("terrain: solid from above (rays hit ground)", hits == 25)
	_check("terrain: collision matches height_at within 5cm", worst < 0.05)
	t.free()


func _test_inventory() -> void:
	GameState.reset()
	_check("inventory: start with 3 bait, 2 traps", GameState.bait == 3 and GameState.traps == 2)
	GameState.money = 50
	_check("inventory: can't buy bait with $50", not GameState.buy("bait") and GameState.bait == 3)
	GameState.money = 500
	_check("inventory: buy bait costs $100", GameState.buy("bait") and GameState.bait == 4 and GameState.money == 400)
	_check("inventory: buy trap costs $200", GameState.buy("trap") and GameState.traps == 3 and GameState.money == 200)
	GameState.reset()


func _test_bait() -> void:
	GameState.reset()
	var bf_scene:= load("res://cryptid.tscn")
	var bf:= bf_scene.instantiate() as Cryptid
	bf.position = Vector3(300, 1.7, 0)
	add_child(bf)
	var far_player:= Node3D.new()
	far_player.position = Vector3(300, 1.0, 80)
	add_child(far_player)
	bf.player_ref = far_player
	var bait:= Bait.new()
	add_child(bait)
	bait.global_position = Vector3(300, 0, 6)
	bf._physics_process(0.1)
	_check("bait: bigfoot smells bait -> INVESTIGATE", bf.state == Cryptid.State.INVESTIGATE)
	# move_and_slide advances by the engine physics step (1/60s), not our delta.
	for _i in 400:
		bf._physics_process(0.1)
		if bf.state == Cryptid.State.EATING:
			break
	_check("bait: reaches bait -> EATING", bf.state == Cryptid.State.EATING)
	var res:= PhotoScoring.evaluate(bf.global_position + Vector3(0, 1.5, 0), Vector3(0, 0, 1), Vector3(300, 1.7, 14), Vector3(0, 0, -1), bf.state)
	_check("bait: eating is not a danger bonus", res["danger"] == false)
	far_player.position = Vector3(300, 1.0, 14)
	far_player.force_update_transform()
	bf._physics_process(0.1)
	_check("bait: eating bigfoot ignores you at 8m", bf.state == Cryptid.State.EATING)
	bf.on_flash(far_player.global_position)
	_check("bait: flash at 8m while eating = no chase (distracted)", bf.state == Cryptid.State.EATING)
	far_player.position = Vector3(300, 1.0, 80)
	far_player.force_update_transform()
	for _i in 80:
		bf._physics_process(0.1)
	_check("bait: finishes eating -> WANDER", bf.state == Cryptid.State.WANDER)
	_check("bait: bait is consumed", not is_instance_valid(bait) or bait.is_queued_for_deletion())
	bf.free()
	far_player.free()


func _test_traps() -> void:
	var bf_scene:= load("res://cryptid.tscn")
	var bf:= bf_scene.instantiate() as Cryptid
	bf.position = Vector3(-300, 1.7, 0)
	add_child(bf)
	var dummy:= Node3D.new()
	dummy.position = Vector3(-300, 1.0, 15)
	add_child(dummy)
	dummy.force_update_transform()
	bf.player_ref = dummy
	var trap:= Trap.new()
	add_child(trap)
	trap._on_body(bf)
	_check("trap: arming trap does nothing", bf.state == Cryptid.State.WANDER)
	trap.force_arm()
	var sprung_on: Array = []
	trap.sprung.connect(func(v): sprung_on.append(v))
	trap._on_body(bf)
	_check("trap: armed trap catches bigfoot", bf.state == Cryptid.State.TRAPPED and sprung_on.size() == 1)
	var p0:= bf.global_position
	bf._physics_process(0.5)
	_check("trap: trapped bigfoot can't move", bf.global_position.distance_to(p0) < 0.01)
	bf.on_flash(dummy.global_position)
	_check("trap: flash doesn't free him", bf.state == Cryptid.State.TRAPPED)
	var r:= PhotoScoring.evaluate(Vector3(0, 1.5, 20), Vector3(0, 0, 1), Vector3(0, 1.7, 30), Vector3(0, 0, -1), PhotoScoring.CryptidState.TRAPPED)
	_check("trap: trapped photo bonus 62 -> 81", r["score"] == 81 and r["trapped"] == true)
	for _i in 65:
		bf._physics_process(0.1)
	_check("trap: breaks free angry -> CHASE (you were close)", bf.state == Cryptid.State.CHASE)
	trap._on_body(bf)
	_check("trap: sprung trap can't fire twice", sprung_on.size() == 1)
	bf.free()
	dummy.free()
	trap.free()

	var p_scene:= load("res://player.tscn")
	var player:= p_scene.instantiate() as Player
	add_child(player)
	var trap2:= Trap.new()
	add_child(trap2)
	trap2.force_arm()
	trap2._on_body(player)
	_check("trap: friendly fire snares the player", player.is_snared())
	for _i in 31:
		player._physics_process(0.1)
	_check("trap: snare wears off after 3s", not player.is_snared())
	player.free()
	trap2.free()

	GameState.reset()
	var player2:= p_scene.instantiate() as Player
	add_child(player2)
	var placed:= player2.place_trap()
	_check("trap: placing uses one trap", placed != null and GameState.traps == 1)
	player2.place_trap()
	_check("trap: out of traps -> nothing placed", player2.place_trap() == null and GameState.traps == 0)
	var b:= player2.place_bait()
	_check("bait: placing uses one bait", b != null and GameState.bait == 2 and b.is_in_group("bait"))
	for n in get_tree().get_nodes_in_group("bait"):
		n.free()
	for c in get_children():
		if c is Trap:
			c.free()
	player2.free()
	GameState.reset()


func _test_third_person() -> void:
	GameState.third_person = false
	var p_scene:= load("res://player.tscn")
	var player:= p_scene.instantiate() as Player
	add_child(player)
	var fp_cam:= player.get_node("Camera3D") as Camera3D
	var vm:= fp_cam.get_node("Viewmodel") as Node3D
	var arms:= vm.get_node_or_null("Arms") as CharacterModel
	_check("view: first-person has sculpted arms+camera", vm.visible and arms != null and arms.meshes.size() > 0)
	_check("view: third-person body is the photographer model", player._body_model != null and player._body_model.has_anim("walk") and player._body_model.has_anim("crouch"))
	_check("view: FP camera can't see own body", (fp_cam.cull_mask & Player.LAYER_BODY) == 0)
	player.set_third_person(true)
	var tp_cam:= player.active_camera()
	_check("view: third person switches camera", tp_cam != fp_cam and tp_cam.current and not vm.visible)
	_check("view: TP camera can't see FP arms", (tp_cam.cull_mask & Player.LAYER_VIEWMODEL) == 0)
	_check("view: choice persists in GameState", GameState.third_person)
	player.force_update_transform()
	var ray:= player.photo_ray()
	_check("view: TP photos aim forward", (ray[1] as Vector3).dot(Vector3(0, 0, -1)) > 0.9)
	player.toggle_view()
	_check("view: toggle back to first person", not player.third_person and fp_cam.current)
	player.free()
	GameState.third_person = false


func _test_models() -> void:
	var names:= ["bigboobs", "methman", "methman_camp", "wherewolf", "grey_tourist", "cornicorn", "jersey_devil", "crackin", "oh_go_pogo", "photographer", "fp_arms"]
	var missing:= []
	for n in names:
		var m:= CharacterModel.load_model("res://models/%s.glb" % n)
		if m.meshes.is_empty():
			missing.append(n)
		elif n != "methman_camp" and n != "fp_arms" and not (m.has_anim("idle") and m.has_anim("walk") and m.has_anim("run")):
			missing.append(n + " (anims)")
		m.free()
	_check("models: every character loads with idle/walk/run (problems: %s)" % str(missing), missing.is_empty())
	var bf:= (load("res://cryptid.tscn") as PackedScene).instantiate() as Cryptid
	add_child(bf)
	_check("models: Cryptid uses the sculpted model with eat/trapped/roar", bf.model != null and bf.model.has_anim("eat") and bf.model.has_anim("trapped") and bf.model.has_anim("roar"))
	bf.trap(5.0)
	bf._physics_process(0.1)
	_check("models: trapped state plays the trapped animation", bf.model.current == "trapped")
	bf.free()
	var g:= (load("res://gallery.tscn") as PackedScene).instantiate()
	add_child(g)
	_check("gallery: opens and shows a character", g._model != null and g._title.text != "")
	g._show(8)
	_check("gallery: can flip to Oh-Go-Pogo", g._title.text == "OH-GO-POGO")
	g.free()


func _test_audio() -> void:
	var missing:= []
	for n in Audio.SFX:
		if Audio.get_stream(n) == null:
			missing.append(n)
	for k in Audio.LOOPS:
		if Audio.get_stream(k) == null:
			missing.append(k)
	_check("audio: all sounds load (missing: %s)" % str(missing), missing.is_empty())
	_check("audio: step has variants", Audio._variants.has("step") and Audio._variants["step"].size() >= 3)


func _test_movement() -> void:
	GameState.reset()
	var floor_body:= StaticBody3D.new()
	var fcs:= CollisionShape3D.new()
	var fbox:= BoxShape3D.new()
	fbox.size = Vector3(40, 1, 40)
	fcs.shape = fbox
	floor_body.add_child(fcs)
	floor_body.position = Vector3(500, -0.5, 0)
	add_child(floor_body)
	var player:= (load("res://player.tscn") as PackedScene).instantiate() as Player
	player.position = Vector3(500, 0.76, 0)
	player.map_limit = 1000.0
	add_child(player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for _i in 10:
		player._physics_process(0.016)
	_check("move: player stands on the floor", player.is_on_floor())

	# 5 second flash cooldown
	var blocked:= [false]
	player.flash_not_ready.connect(func(): blocked[0] = true)
	player.snap_photo()
	_check("cooldown: first shot uses film", GameState.film == 5)
	player.snap_photo()
	_check("cooldown: second shot right away is blocked", GameState.film == 5 and blocked[0])
	_check("cooldown: flash not ready right after a shot", player.flash_ready_fraction() < 0.05)
	for _i in 49:
		player._physics_process(0.1)
	player.snap_photo()
	_check("cooldown: still blocked at 4.9s", GameState.film == 5)
	player._physics_process(0.15)
	player.snap_photo()
	_check("cooldown: ready again after 5s", GameState.film == 4)

	# Jump
	player.jump()
	player._physics_process(0.016)
	_check("jump: leaves the ground with upward speed", player.velocity.y > 4.0)
	var peak:= player.global_position.y
	for _i in 30:
		player._physics_process(0.016)
		peak = maxf(peak, player.global_position.y)
	_check("jump: actually rises", peak > 0.76 + 0.2)
	for _i in 120:
		player._physics_process(0.016)
	_check("jump: lands again", player.is_on_floor())

	# Crouch
	var stand_eye: float = (player.get_node("Camera3D") as Camera3D).position.y
	player.toggle_crouch()
	for _i in 30:
		player._physics_process(0.016)
	_check("crouch: is crouching", player.is_crouching())
	_check("crouch: eye height drops", player.get_node("Camera3D").position.y < stand_eye - 0.4)
	var bf:= (load("res://cryptid.tscn") as PackedScene).instantiate() as Cryptid
	bf.position = Vector3(500 + 9.0, 1.7, 0)
	add_child(bf)
	bf.player_ref = player
	bf._check_proximity()
	_check("crouch: at 9m a crouched player isn't noticed", bf.state == Cryptid.State.WANDER)
	player.toggle_crouch()
	for _i in 30:
		player._physics_process(0.016)
	_check("crouch: stands back up", not player.is_crouching() and absf(player.get_node("Camera3D").position.y - stand_eye) < 0.01)
	player.free()
	bf.free()
	floor_body.free()
	GameState.reset()


func _test_species() -> void:
	var ok_ids:= true
	for m in Species.MAPS:
		for t in Species.TIERS:
			for id in Species.MAPS[m][t]:
				if not Species.DATA.has(id):
					ok_ids = false
	_check("species: every map roster entry has stats", ok_ids)
	var models_ok:= true
	for id in Species.DATA:
		if Species.DATA[id].has("model") and load(str(Species.DATA[id]["model"])) == null:
			models_ok = false
	_check("species: every cryptid model loads", models_ok)
	var rng:= RandomNumberGenerator.new()
	rng.seed = 5
	var always:= true
	for _i in 20:
		var ids:= []
		for e in Species.roll_night("woods", rng):
			ids.append(e["id"])
		for id in Species.MAPS["woods"]["common"]:
			if id not in ids:
				always = false
	_check("species: commons show up every night", always)
	var wolves:= 0
	for _i in 2000:
		for e in Species.roll_night("woods", rng):
			if e["id"] == "wherewolf":
				wolves += 1
	_check("species: where-wolf is unfathomably rare (but possible)", wolves < 40)
	_check("species: tourists come in groups", int(Species.info("grey_tourist")["group"][0]) >= 2)
	_check("species: rare pays more than common", Species.pay_mult("woods", "bigboobs") > Species.pay_mult("woods", "cornicorn"))
	_check("species: woods -> lake is the next map", Species.next_map("woods") == "lake")


func _make(id: String, pos: Vector3) -> Cryptid:
	var c:= (load("res://cryptid.tscn") as PackedScene).instantiate() as Cryptid
	c.configure(id)
	c.position = pos
	add_child(c)
	return c


func _test_behaviours() -> void:
	var dummy:= Node3D.new()
	dummy.position = Vector3(-600, 1.0, 5)
	add_child(dummy)
	dummy.force_update_transform()
	var t:= _make("grey_tourist", Vector3(-600, 0.7, 0))
	t.player_ref = dummy
	var got_snapped:= [false]
	t.flashed_player.connect(func(): got_snapped[0] = true)
	t._check_proximity()
	_check("behaviour: tourist flees instead of chasing", t.state == Cryptid.State.FLEE)
	_check("behaviour: tourist takes YOUR picture first", got_snapped[0])
	var d0:= t.distance_to_player()
	for _i in 120:
		t._physics_process(0.1)
	_check("behaviour: fleeing tourist gets further away", t.distance_to_player() > d0 + 1.0)
	t.free()

	var corn:= _make("cornicorn", Vector3(-600, 1.0, 0))
	corn.player_ref = dummy
	corn.on_flash(dummy.global_position)
	_check("behaviour: cornicorn bolts when flashed", corn.state == Cryptid.State.FLEE)
	corn.free()

	var crack:= _make("crackin", Vector3(-600, 1.0, 2))
	crack.player_ref = dummy
	crack._check_proximity()
	_check("behaviour: Crackin' can't be bothered when you walk up", crack.state != Cryptid.State.CHASE)
	crack.on_flash(dummy.global_position)
	_check("behaviour: ...but flash him up close and he's coming", crack.state == Cryptid.State.CHASE)
	_check("behaviour: Crackin' is slower than you walk", crack.chase_speed < 5.0)
	crack.free()

	var meth:= _make("methman", Vector3(-600, 1.0, 0))
	meth.home = Vector2(-600, -40)
	meth.camp = Vector2(5000, 5000)
	var near_home:= true
	for _i in 20:
		meth._pick_waypoint()
		if Vector2(meth._waypoint.x, meth._waypoint.z).distance_to(meth.home) > meth.home_radius + 0.1:
			near_home = false
	_check("behaviour: Methman hangs around his tent", near_home)
	_check("behaviour: Methman is a hunter", meth.behaviour == "hunter")
	meth.free()
	dummy.free()


func _test_album_and_unlocks() -> void:
	GameState.reset()
	_check("album: starts empty, lake locked", GameState.album.is_empty() and not GameState.is_unlocked("lake"))
	_check("album: Toe Rogan needs 4 on the woods", GameState.missing_for_unlock("woods").size() == 4)
	var need:= Species.required_for_unlock("woods")
	var last: String = need[need.size() - 1]
	GameState.unsold_photos.append({"value": 40, "species": [need[0], need[1]]})
	GameState.unsold_photos.append({"value": 70, "species": [need[2]]})
	GameState.develop()
	_check("album: developing files photos by species", GameState.has_photo(need[0]) and GameState.has_photo(need[1]) and GameState.has_photo(need[2]))
	_check("album: still missing the last one", GameState.missing_for_unlock("woods") == [last])
	GameState.unsold_photos.append({"value": 55, "species": [last]})
	_check("album: undeveloped photos don't count", GameState.missing_for_unlock("woods").size() == 1)
	GameState.end_night(true)
	_check("night: getting grabbed loses undeveloped photos", GameState.unsold_photos.is_empty() and GameState.night == 2)
	_check("night: money survives the night", GameState.money == 110)
	GameState.unsold_photos.append({"value": 55, "species": [last]})
	GameState.develop()
	_check("album: complete set for the woods", GameState.missing_for_unlock("woods").is_empty())
	GameState.travel("lake")
	_check("travel: can't drive to a locked map", GameState.current_map == "woods")
	GameState.unlock("lake")
	GameState.travel("lake")
	_check("travel: unlocked map works", GameState.current_map == "lake" and GameState.film == GameState.FILM_MAX)
	GameState.reset()


func _test_save_roundtrip() -> void:
	var real:= GameState.SAVE_PATH
	GameState.SAVE_PATH = "user://test_roundtrip.json"
	GameState.saving_enabled = true
	GameState.reset()
	GameState.money = 321
	GameState.night = 7
	GameState.album = {"cornicorn": 30}
	GameState.unlock("lake")
	GameState.current_map = "lake"
	GameState.save_game()
	GameState.reset()
	GameState.load_game()
	_check("save: money/night/map/album/unlocks survive a restart", GameState.money == 321 and GameState.night == 7
		and GameState.current_map == "lake" and GameState.has_photo("cornicorn") and GameState.is_unlocked("lake"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	GameState.SAVE_PATH = real
	GameState.saving_enabled = false
	GameState.reset()


func _test_multi_photo() -> void:
	GameState.reset()
	var player:= (load("res://player.tscn") as PackedScene).instantiate() as Player
	player.position = Vector3(800, 1.0, 20)
	player.map_limit = 5000.0
	add_child(player)
	var a:= _make("grey_tourist", Vector3(799, 0.7, 10))
	var b:= _make("grey_tourist", Vector3(801, 0.7, 10))
	var c:= _make("cornicorn", Vector3(800, 1.05, 12))
	for k in [a, b, c]:
		k.frozen = true
	player.cryptids = [a, b, c]
	await get_tree().physics_frame
	await get_tree().physics_frame
	var r:= player.evaluate_shot()
	_check("photo: several cryptids in one shot", r["in_frame"] and r["group"] == 3)
	_check("photo: album credit for every species in frame", "grey_tourist" in r["species_list"] and "cornicorn" in r["species_list"])
	var solo:= PhotoScoring.evaluate(c.photo_point(), c.get_facing(), player.photo_ray()[0], player.photo_ray()[1], c.state)
	_check("photo: group bonus beats the best single", r["value"] > int(solo["score"]))
	var wall:= StaticBody3D.new()
	var wcs:= CollisionShape3D.new()
	var wb:= BoxShape3D.new()
	wb.size = Vector3(20, 6, 0.5)
	wcs.shape = wb
	wall.add_child(wcs)
	wall.position = Vector3(800, 2, 16)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var r2:= player.evaluate_shot()
	_check("photo: can't shoot through a wall", not r2["in_frame"] and "way" in str(r2["reason"]))
	for k in [a, b, c, wall, player]:
		k.free()
	GameState.reset()


func _test_maps() -> void:
	for m in ["woods", "lake", "city"]:
		GameState.reset()
		GameState.current_map = m
		var main_node: Node = (load("res://main.tscn") as PackedScene).instantiate()
		add_child(main_node)
		await get_tree().process_frame
		var cryptids: Array = main_node.get("_cryptids")
		var forest: Forest = main_node.get("_forest")
		_check("map %s: loads with cryptids roaming" % m, cryptids.size() >= 3)
		_check("map %s: Toe Rogan is at the campfire" % m, main_node.get_node_or_null("ToeRogan") != null)
		if m == "lake":
			_check("map lake: has a lake", forest.terrain.get_node_or_null("Water") != null)
			_check("map lake: camp is above the waterline", forest.terrain.camp_height() > forest.terrain.water_level + 1.0)
			var dry:= true
			for c in cryptids:
				var cc: Cryptid = c
				if forest.terrain.height_at(cc.global_position.x, cc.global_position.z) < forest.terrain.water_level - 0.6:
					dry = false
			_check("map lake: nobody spawns in deep water", dry)
		elif m == "city":
			_check("map city: Methman's camp is under the overpass", main_node.get_node_or_null("MethmanCamp") != null)
			var city: CityBlocks = main_node.get("_city")
			_check("map city: has the street grid and buildings", city != null and city.blockers.size() >= 12)
			var clear:= true
			for c in cryptids:
				var cc: Cryptid = c
				if city.blocked(Vector2(cc.global_position.x, cc.global_position.z)):
					clear = false
			_check("map city: nobody spawns inside a building", clear)
		else:
			_check("map woods: the Leperchaun's gold has a spot", forest.landmarks.has("pot_of_gold"))
		main_node.free()
	GameState.reset()


func _max_triangle_edge(mesh: Mesh) -> float:
	var max_edge:= 0.0
	for s in mesh.get_surface_count():
		var arrays:= mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if verts.is_empty():
			continue
		var tri_count:= 0
		if not idx.is_empty():
			tri_count = idx.size() / 3
		else:
			tri_count = verts.size() / 3
		for t in tri_count:
			var a: Vector3
			var b: Vector3
			var c: Vector3
			if not idx.is_empty():
				a = verts[idx[t * 3]]
				b = verts[idx[t * 3 + 1]]
				c = verts[idx[t * 3 + 2]]
			else:
				a = verts[t * 3]
				b = verts[t * 3 + 1]
				c = verts[t * 3 + 2]
			max_edge = maxf(max_edge, a.distance_to(b))
			max_edge = maxf(max_edge, b.distance_to(c))
			max_edge = maxf(max_edge, c.distance_to(a))
	return max_edge


# ---------------------------------------------------------------- v0.8: PC build features

func _test_v08() -> void:
	GameState.reset()
	# --- aiming, item select, stun
	var player:= (load("res://player.tscn") as PackedScene).instantiate() as Player
	add_child(player)
	player.position = Vector3(0, 1.0, 0)
	var got_need_aim:= [false]
	player.need_aim.connect(func(): got_need_aim[0] = true)
	player.set_aiming(true)
	_check("v08: right-click raises the camera (aiming)", player.aiming)
	player.set_aiming(false)
	var picked: Array = []
	player.item_selected.connect(func(k): picked.append(k))
	player.select_item("trap")
	_check("v08: 2 selects traps", player.selected_item == "trap" and picked == ["trap"])
	player.select_item("bait")
	var bait_before:= GameState.bait
	player.use_item()
	_check("v08: Q uses the selected item (bait)", GameState.bait == bait_before - 1)
	player.select_item("trap")
	var traps_before:= GameState.traps
	player.use_item()
	_check("v08: Q uses the selected item (trap)", GameState.traps == traps_before - 1)
	player.stun(2.5)
	_check("v08: tourist flash stuns you", player.is_stunned())
	player.set_aiming(true)
	player.controls_locked = true
	player.set_aiming(true)
	player.controls_locked = false
	player.queue_free()
	var tourist:= Species.info("grey_tourist")
	_check("v08: grey tourists outrun your sprint", float(tourist["chase"]) > player.sprint_speed)
	_check("v08: grey tourists stun on flash", float(tourist.get("stun", 0.0)) >= 2.0)

	# --- items cap, cryptid files
	GameState.reset()
	GameState.money = 10000
	GameState.bait = 4
	_check("v08: can buy up to 5", GameState.buy("bait") and GameState.bait == 5)
	_check("v08: can't carry more than 5", not GameState.buy("bait") and GameState.bait == 5)
	GameState.reset()
	GameState.unsold_photos = [{"value": 20, "species": ["cornicorn"], "scores": {"cornicorn": 20}}]
	GameState.develop()
	_check("v08: a so-so photo doesn't unlock the file", not GameState.has_file("cornicorn") and GameState.has_photo("cornicorn"))
	GameState.unsold_photos = [{"value": 60, "species": ["cornicorn"], "scores": {"cornicorn": 45}}]
	GameState.develop()
	_check("v08: a GREAT shot unlocks the cryptid file", GameState.has_file("cornicorn"))
	var files:= CryptidFiles.new()
	add_child(files)
	files.open()
	await get_tree().process_frame
	_check("v08: cryptid files list every entry", files._list.get_child_count() == CryptidFiles.ENTRIES.size() + CryptidFiles.ALWAYS.size())
	files._select("bigboobs")
	_check("v08: locked file shows a silhouette, no model", files._model == null and files._locked_pic.visible)
	files._select("cornicorn")
	_check("v08: unlocked file shows the 3D model", files._model != null and not files._locked_pic.visible)
	files.close()
	files.queue_free()

	# --- Toe's wanted poster, shop, travel
	GameState.reset()
	GameState.album = {"cornicorn": 30}
	var poster:= ToePoster.new()
	add_child(poster)
	poster.open("woods", "hey man", false)
	await get_tree().process_frame
	_check("v08: wanted poster shows all 6 woods cryptids", poster._cards.get_child_count() == 6)
	_check("v08: poster counts progress", poster._progress.text.contains("1 / 4"))
	_check("v08: no SHOW button until the set is complete", not poster._show_btn.visible)
	_check("v08: reload disabled with full film", poster._reload_btn.disabled)
	GameState.film = 2
	poster.open("woods", "hey man", true)
	_check("v08: reload offered when film is used", not poster._reload_btn.disabled and poster._show_btn.visible)
	poster.queue_free()
	var shop:= ShopUI.new()
	add_child(shop)
	GameState.money = 50
	shop.open()
	_check("v08: shop won't sell when broke", (shop._buttons["bait"] as Button).disabled)
	GameState.money = 1000
	shop.refresh()
	_check("v08: shop sells when you can pay", not (shop._buttons["bait"] as Button).disabled)
	shop.queue_free()
	var travel:= TravelPanel.new()
	add_child(travel)
	travel.open("woods")
	await get_tree().process_frame
	_check("v08: driver's seat lists every map", travel._list.get_child_count() == Species.MAP_ORDER.size())
	travel.queue_free()

	# --- RV interior stations
	var rv_in:= RVInterior.new()
	add_child(rv_in)
	var eye:= rv_in.entry_point() + Vector3(0, 1.5, 0)
	_check("v08: from the door, looking in: darkroom", rv_in.focus_hotspot(eye, Vector3(0, 0, 1)) == "develop")
	_check("v08: turn to the cab: driver's seat", rv_in.focus_hotspot(rv_in.to_global(Vector3(1.5, 1.5, -0.4)), Vector3(1, -0.3, 0).normalized()) == "drive")
	_check("v08: look at the bed: sleep", rv_in.focus_hotspot(rv_in.to_global(Vector3(-1.0, 1.5, 0.0)), Vector3(-1, -0.5, 0.2).normalized()) == "sleep")
	_check("v08: turn around: exit", rv_in.focus_hotspot(eye, Vector3(0, -0.2, -1).normalized()) == "exit")
	var pr:= rv_in.hang_print(0, 3, null, "Cornicorn $40")
	_check("v08: darkroom hangs prints on the line", rv_in.print_count() == 1 and pr.get_parent() == rv_in)
	rv_in.queue_free()

	# --- full scene: shop by the RV, interior, pause menu
	GameState.reset()
	var main_node: Node = (load("res://main.tscn") as PackedScene).instantiate()
	add_child(main_node)
	await get_tree().process_frame
	var mp: Player = main_node.get("_player")
	var shop_node: ShopStand = main_node.get("_shop")
	var rv: RV = main_node.get("_rv")
	_check("v08: bait & trap stand next to the RV", shop_node != null and shop_node.global_position.distance_to(rv.global_position) < 9.0)
	_check("v08: shopkeeper behind the counter", shop_node.keeper != null and shop_node.keeper.has_anim("tip_hat"))
	_check("v08: RV interior exists off-map", main_node.get("_interior") != null)
	_check("v08: pause menu exists", main_node.get("_pause") != null)
	var fp:= shop_node.front_point()
	mp.global_position = Vector3(fp.x, fp.y + 1.0, fp.z)
	_check("v08: E at the stand opens the shop", main_node.call("_interaction") == "shop")
	var toe: Node3D = main_node.get("_toe")
	mp.global_position = toe.global_position + Vector3(1.0, 1.0, 0.0)
	_check("v08: E near Toe talks to Toe", main_node.call("_interaction") == "toe")
	var tm: CharacterModel = main_node.get("_toe_model")
	_check("v08: Toe has the camera-swap animation", tm.has_anim("swap") and tm.skeleton != null and tm.skeleton.find_bone("hand_r") >= 0)
	main_node.free()
	GameState.reset()


func _test_overnight() -> void:
	GameState.reset()
	GameState.unsold_photos = [{"value": 40, "species": ["cornicorn"]}]
	GameState.end_night(false)
	_check("night: sleeping keeps undeveloped photos", GameState.unsold_photos.size() == 1 and GameState.film == GameState.FILM_MAX)
	GameState.start_night()
	_check("night: a new night doesn't wipe undeveloped photos", GameState.unsold_photos.size() == 1)
	GameState.travel("woods")
	_check("night: travelling keeps undeveloped photos", GameState.unsold_photos.size() == 1)
	GameState.end_night(true)
	_check("night: getting grabbed still loses them", GameState.unsold_photos.is_empty())
	GameState.reset()


func _test_v081() -> void:
	GameState.reset()
	# third-person aiming looks through the camera
	var player:= (load("res://player.tscn") as PackedScene).instantiate() as Player
	add_child(player)
	await get_tree().process_frame
	player.set_third_person(true)
	_check("v081: third person uses the shoulder camera", player.active_camera() != player.first_person_camera() and not player.first_person_camera().current)
	player.set_aiming(true)
	_check("v081: raising the camera in third person goes first person", player.active_camera() == player.first_person_camera() and player.first_person_camera().current)
	player.set_aiming(false)
	_check("v081: lowering it goes back to third person", player.active_camera() != player.first_person_camera())
	player.set_third_person(false)
	# toggle sprint
	GameState.settings["toggle_sprint"] = true
	var ev:= InputEventAction.new()
	ev.action = "sprint"
	ev.pressed = true
	player._input(ev)
	_check("v081: toggle sprint latches on a tap", player._sprint_latched)
	player._input(ev)
	_check("v081: second tap turns it off", not player._sprint_latched)
	GameState.settings["toggle_sprint"] = false
	player.queue_free()
	# settings are sliders now; old on/off saves convert
	_check("v081: effects are 0..1 strengths", typeof(GameState.settings["glow"]) == TYPE_FLOAT)
	# Jersey Devil hangs out at his tailgate and calls out
	var jd:= Species.info("jersey_devil")
	_check("v081: Jersey Devil has a home (tailgate)", jd.get("home", "") == "tailgate" and jd.has("call_every"))
	GameState.current_map = "city"
	var main_node: Node = (load("res://main.tscn") as PackedScene).instantiate()
	add_child(main_node)
	await get_tree().process_frame
	var forest: Forest = main_node.get("_forest")
	_check("v081: the City has a tailgate spot", forest.landmarks.has("tailgate") and main_node.get_node_or_null("Tailgate") != null)
	# moon disc lines up with the light direction
	var moon: DirectionalLight3D = main_node.get("_moon")
	var disc: MeshInstance3D = main_node.get("_moon_disc")
	main_node.call("_place_moon", Vector3.ZERO)
	var dir:= disc.global_position.normalized()
	_check("v081: moon disc sits where the moonlight comes from", dir.dot(moon.global_transform.basis.z) > 0.999)
	_check("v081: moon is above the horizon", disc.global_position.y > 100.0)
	main_node.free()
	GameState.reset()


func _test_v09() -> void:
	GameState.reset()
	# moon disc never shadows the player
	var main_node: Node = (load("res://main.tscn") as PackedScene).instantiate()
	add_child(main_node)
	await get_tree().process_frame
	var disc: MeshInstance3D = main_node.get("_moon_disc")
	_check("v09: moon disc casts no shadow", disc.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var mp: Player = main_node.get("_player")
	# third-person body turns into the move, head stays on the reticle
	_check("v09: head-look modifier on the third-person body", mp.get("_head_look") != null)
	# footsteps follow the animation's stride
	var jog_step: float = mp._step_length("jog")
	var run_step: float = mp._step_length("run")
	_check("v09: step length comes from the walk cycle (jog ~1.2 m, run ~1.5 m)", absf(jog_step - 1.2) < 0.15 and absf(run_step - 1.49) < 0.15)
	# Toe's camera pile and losing film on reload
	GameState.cameras_thrown = 5
	var p0: Vector3 = main_node.call("_pile_spot", 0)
	var p4: Vector3 = main_node.call("_pile_spot", 4)
	var toe: Node3D = main_node.get("_toe")
	_check("v09: thrown cameras land behind Toe, in a heap", p0.distance_to(p4) < 2.5 and (p0 - toe.global_position).dot(toe.global_transform.basis.z) < -3.0)
	# shop decor + poster wall
	var interior: RVInterior = main_node.get("_interior")
	GameState.money = 5000
	_check("v09: poster for an un-photographed cryptid isn't in stock", not GameState.buy_decor("poster_wolf"))
	GameState.album["cornicorn"] = 40
	_check("v09: poster in stock once you've photographed it", GameState.buy_decor("poster_corn") and GameState.money == 4700)
	_check("v09: new poster goes up in a free slot", "poster_corn" in GameState.poster_slots)
	_check("v09: trinkets buyable once", GameState.buy_decor("lava_lamp") and not GameState.buy_decor("lava_lamp"))
	interior.refresh_decor()
	var decor: Node3D = interior.get("_decor")
	_check("v09: RV shows the posters and trinkets you own", decor.get_node_or_null("Poster_poster_corn") != null and decor.get_node_or_null("LavaLamp") != null)
	# per-map looks
	var w:= Species.style("woods")
	var l:= Species.style("lake")
	_check("v09: Deep Woods is denser than Lakeside", int(w["trees"]) > int(l["trees"]) * 2 and int(w["bushes"]) > int(l["bushes"]) * 3)
	_check("v09: Deep Woods has ferns and glowing mushrooms", main_node.get("_forest").get_node_or_null("Ferns") != null and main_node.get("_forest").get_node_or_null("MushroomCaps") != null)
	main_node.free()

	# Toe throwing your camera loses the undeveloped film
	GameState.reset()
	GameState.unsold_photos = [{"value": 50, "species": ["cornicorn"]}]
	var poster:= ToePoster.new()
	add_child(poster)
	GameState.film = 2
	poster.open("woods", "hey", false)
	_check("v09: reload button warns you'll lose undeveloped film", poster._reload_btn.text.contains("LOSE $50"))
	poster.queue_free()

	# Lakeside: cryptids walk round the lake instead of sticking at the shore
	GameState.reset()
	GameState.current_map = "lake"
	var lake: Node = (load("res://main.tscn") as PackedScene).instantiate()
	add_child(lake)
	await get_tree().process_frame
	var t: Terrain = lake.get("_terrain")
	var lp: Player = lake.get("_player")
	for c in lake.get("_cryptids"):
		c.frozen = true
	var hunter:= (load("res://cryptid.tscn") as PackedScene).instantiate() as Cryptid
	hunter.configure("bigboobs")
	hunter.terrain = t
	hunter.water_level = t.water_level
	hunter.camp = Terrain.CAMP
	hunter.map_half = Terrain.RIM_START
	lake.add_child(hunter)
	hunter.player_ref = lp
	hunter.global_position = Vector3(-62, t.height_at(-62, -8) + 1.2, -8)
	var start:= hunter.global_position
	# Heading for a spot on the far shore: the straight line is all lake.
	hunter.set("_waypoint", Vector3(60, 0, -8))
	hunter.set("_waypoint_timer", 99.0)
	lp.global_position = Vector3(0, 40, 150)
	lp.controls_locked = true
	for i in 360:
		await get_tree().physics_frame
	_check("v09: cryptids walk round the lake, not into the shore", hunter.global_position.distance_to(start) > 12.0 and not hunter._deep(hunter.global_position.x, hunter.global_position.z))
	# jumping off the dock into deep water puts you back on dry footing
	var dock: Vector2 = lake.get("_forest").landmarks["dock"]
	lp.controls_locked = false
	lp.global_position = Vector3(dock.x, t.height_at(dock.x, dock.y) + 1.2, dock.y)
	for i in 30:
		await get_tree().physics_frame
	var safe: Vector3 = lp.get("_last_safe")
	var deep:= Vector3(Terrain.LAKE_C.x, t.water_level, Terrain.LAKE_C.y)
	var fell:= [false]
	lp.fell_in_water.connect(func(): fell[0] = true)
	lp.global_position = deep + Vector3(0, -0.2, 0)
	for i in 3:
		await get_tree().physics_frame
	_check("v09: falling into deep water puts you back where you last stood", fell[0] and lp.global_position.distance_to(safe) < 1.0)
	lake.free()
	GameState.reset()


func _test_v010() -> void:
	GameState.reset()
	var main_node: Node = (load("res://main.tscn") as PackedScene).instantiate()
	add_child(main_node)
	await get_tree().process_frame
	var mp: Player = main_node.get("_player")
	for c in main_node.get("_cryptids"):
		c.frozen = true
	# head-look doesn't pile up: after looking over the shoulder, back to straight ahead
	var hl: HeadLook = mp.get("_head_look")
	var sk: Skeleton3D = mp.get("_body_model").skeleton
	var head:= sk.find_bone("head")
	mp.set_third_person(true)
	hl.yaw = 0.0
	for i in 3:
		await get_tree().process_frame
	var straight:= sk.get_bone_pose_rotation(head)
	hl.yaw = 1.3
	for i in 20:
		await get_tree().process_frame
	hl.yaw = 0.0
	mp.set("_body_target", 0.0)
	mp.set("_body_yaw", 0.0)
	for i in 6:
		await get_tree().process_frame
	_check("v010: head comes back from looking over the shoulder", sk.get_bone_pose_rotation(head).angle_to(straight) < 0.15)
	mp.set_third_person(false)
	# tripod cam: shoots a cryptid that walks in front of it, high value; or you
	var t: Terrain = main_node.get("_terrain")
	GameState.tripods = 2
	var spot:= Terrain.CAMP + Vector2(-9, -8)   # flat camp clearing
	mp.global_position = Vector3(spot.x, t.height_at(spot.x, spot.y) + 1.0, spot.y)
	mp.set_look(0.0, 0.0)
	mp.select_item("tripod")
	var tri: Tripod = mp.use_item()
	_check("v010: Q sets a tripod cam facing where you look", tri != null and GameState.tripods == 1 and tri.facing().dot(Vector3(0, 0, -1)) > 0.95)
	var got:= []
	tri.fired.connect(func(r, who): got.append([r, who]))
	mp.global_position = Vector3(spot.x, t.height_at(spot.x, spot.y + 6) + 1.0, spot.y + 6)   # behind it
	var c: Cryptid = (load("res://cryptid.tscn") as PackedScene).instantiate()
	c.configure("cornicorn")
	c.terrain = t
	main_node.add_child(c)
	c.frozen = true
	var cp:= tri.global_position + Vector3(0, 0, -5)
	c.global_position = Vector3(cp.x, t.height_at(cp.x, cp.z) + c.body_height * 0.5, cp.z)
	c.set("_facing", Vector3(0, 0, 1))
	mp.cryptids = [c]
	for i in 200:
		await get_tree().physics_frame
		if not got.is_empty():
			break
	_check("v010: tripod fires on a cryptid in front of it", got.size() == 1 and got[0][1] == c)
	var res: Dictionary = got[0][0] if not got.is_empty() else {}
	_check("v011: tripod shot is an ordinary photo (no tripod bonus)", res.get("in_frame", false) and not res.get("danger", false))
	_check("v010: a used tripod doesn't fire again", tri.used)
	var tri2: Tripod = Tripod.new()
	main_node.add_child(tri2)
	tri2.global_position = Vector3(spot.x + 8, t.height_at(spot.x + 8, spot.y), spot.y)
	tri2.player = mp
	mp.cryptids = []
	var got2:= []
	tri2.fired.connect(func(r, who): got2.append(who))
	mp.global_position = tri2.global_position + Vector3(0, 1.0, -4)
	for i in 220:
		await get_tree().physics_frame
		if not got2.is_empty():
			break
	_check("v010: tripod will happily photograph you instead", got2.size() == 1 and got2[0] == mp)
	# joint: the world slows down
	GameState.joints = 1
	mp.select_item("joint")
	mp.use_item()
	mp.cryptids = [c]
	main_node.get("_cryptids").append(c)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("v010: joint slows cryptids down", GameState.joints == 0 and mp.joint_time > 0.0 and c.time_factor < 0.5)
	mp.joint_time = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	_check("v010: and wears off", c.time_factor == 1.0)
	# beer: faster, louder
	GameState.beers = 1
	mp.select_item("beer")
	mp.use_item()
	_check("v010: beer gives you a buzz", GameState.beers == 0 and mp.beer_time > 20.0)
	main_node.free()
	# shop sells all five kinds of gear, capped at 5 each
	GameState.reset()
	GameState.money = 100000
	for k in GameState.GEAR:
		GameState.set_item_count(k, 4)
	var all_ok:= true
	for k in GameState.GEAR:
		all_ok = all_ok and GameState.buy(k) and not GameState.buy(k)
	_check("v010: every gear item buyable up to 5", all_ok)
	var shop:= ShopUI.new()
	add_child(shop)
	shop.open()
	_check("v010: gear tab lists bait, trap, tripod, joint, beer", shop._buttons.size() == 5)
	shop.queue_free()
	GameState.reset()


func _test_v011() -> void:
	GameState.reset()
	# rosters
	var woods: Dictionary = Species.MAPS["woods"]
	var lake: Dictionary = Species.MAPS["lake"]
	var city: Dictionary = Species.MAPS["city"]
	_check("v011: Leperchaun and bEnt live in the Deep Woods", "leperchaun" in woods["uncommon"] and "bent" in woods["uncommon"])
	_check("v011: F'hairy lives at Lakeside", "fhairy" in lake["common"])
	var city_all: Array = city["common"] + city["uncommon"] + city["rare"]
	_check("v011: Methman, Jersey Devil, Crackin' and The Rake live in the City",
		"methman" in city_all and "jersey_devil" in city_all and "crackin" in city_all and "the_rake" in city_all)
	_check("v011: the City is the third map", Species.MAP_ORDER == ["woods", "lake", "city"] and Species.next_map("lake") == "city")
	_check("v014: Santa pays a fortune, the UFO a modest bonus", Species.pay_mult("woods", "santa") >= 10.0 and Species.pay_mult("city", "ufo") <= 4.0)
	# The Rake: frozen while you look at it, coming for you when you don't.
	var holder:= Node3D.new()
	add_child(holder)
	var target:= StaticBody3D.new()
	var tcs:= CollisionShape3D.new()
	tcs.shape = SphereShape3D.new()
	target.add_child(tcs)
	holder.add_child(target)
	var cam:= Camera3D.new()
	holder.add_child(cam)
	cam.global_position = Vector3(0, 1.6, 0)
	cam.current = true
	var rake:= (load("res://cryptid.tscn") as PackedScene).instantiate() as Cryptid
	rake.configure("the_rake")
	rake.player_ref = target
	holder.add_child(rake)
	rake.global_position = Vector3(0, 1.4, -12)
	rake.call("_enter_chase")
	cam.look_at(rake.global_position)
	var start:= rake.global_position
	for i in 20:
		await get_tree().physics_frame
	_check("v011: The Rake can't move while you're looking at it", rake.watched and rake.global_position.distance_to(start) < 0.05)
	cam.look_at(Vector3(0, 1.6, 12))
	for i in 20:
		await get_tree().physics_frame
	_check("v011: ...and closes in the moment you look away", not rake.watched and rake.global_position.distance_to(start) > 0.5)
	holder.free()
	# UFO: struggle free by alternating A and D; holding one key does nothing.
	var p_scene:= load("res://player.tscn")
	var pl:= p_scene.instantiate() as Player
	add_child(pl)
	pl.global_position = Vector3(0, 1, 0)
	var ufo:= UFO.new()
	ufo.player = pl
	add_child(ufo)
	ufo.global_position = Vector3(0, UFO.ALTITUDE, 0)
	pl.extra_subjects = [ufo]
	var shot:= pl.evaluate_from(Vector3(8, 1.6, 8), (ufo.photo_point() - Vector3(8, 1.6, 8)).normalized())
	_check("v014: a UFO photo pays a bit (not a fortune)", shot.get("species", "") == "ufo" and int(shot.get("value", 0)) >= 100 and int(shot.get("value", 0)) <= 400)
	ufo.photographed()
	var shot2:= pl.evaluate_from(Vector3(8, 1.6, 8), (ufo.photo_point() - Vector3(8, 1.6, 8)).normalized())
	_check("v014: ...once: more photos of the same UFO pay nothing", int(shot2.get("value", 0)) == 0)
	_check("v014: snapping it doesn't send it away", ufo.phase != UFO.Phase.LEAVE)
	ufo.call("_start_beam")
	_check("v011: the tractor beam grabs you (controls locked)", ufo.is_beaming() and pl.controls_locked)
	for i in 6:
		ufo.mash("a")
	_check("v011: mashing one key doesn't help", ufo.struggle <= UFO.MASH_GAIN + 0.001)
	var freed:= [false]
	ufo.escaped_beam.connect(func(): freed[0] = true)
	for i in 14:
		ufo.mash("d" if i % 2 == 0 else "a")
	await get_tree().process_frame
	await get_tree().process_frame
	_check("v011: alternating A/D breaks you free and it gives up", freed[0] and not pl.controls_locked and ufo.phase == UFO.Phase.LEAVE)
	ufo.free()
	var ufo2:= UFO.new()
	ufo2.player = pl
	add_child(ufo2)
	ufo2.call("_start_beam")
	var took:= [false]
	ufo2.abducted.connect(func(): took[0] = true)
	ufo2.set("lift", 0.999)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("v011: don't struggle and you're abducted", took[0])
	ufo2.free()
	pl.free()
	# Pot of gold: guarded while he's close, yours when he isn't.
	var pot:= PotOfGold.new()
	add_child(pot)
	pot.global_position = Vector3.ZERO
	var lep:= (load("res://cryptid.tscn") as PackedScene).instantiate() as Cryptid
	lep.configure("leperchaun")
	add_child(lep)
	lep.frozen = true
	lep.global_position = Vector3(5, 0.6, 0)
	_check("v011: the Leperchaun guards his gold", pot.guarded_by([lep]) == lep)
	lep.global_position = Vector3(30, 0.6, 0)
	_check("v011: ...unless he's wandered off", pot.guarded_by([lep]) == null)
	pot.take()
	_check("v011: and then it's gone", pot.taken and not pot.player_near(Vector3.ZERO))
	lep.free()
	pot.free()
	# City: walking round a block of buildings instead of through it.
	var cb:= CityBlocks.new()
	var a:= Vector2(-38, CityBlocks.EW_ROADS[1])
	var b:= Vector2(-38, CityBlocks.EW_ROADS[0])
	var path:= cb.route(a, b)
	var ok:= cb.segment_blocked(a, b) and path.size() > 1
	var prev:= a
	for q in path:
		if cb.segment_blocked(prev, q):
			ok = false
		prev = q
	_check("v011: City cryptids route round buildings (every leg clear)", ok)
	_check("v011: the bridge is walkable, the river isn't", not cb.blocked(Vector2(0, CityBlocks.RIVER_Z)) and cb.blocked(Vector2(30, CityBlocks.RIVER_Z)))
	cb.free()
	# Microphone: loudness -> how far away you can be heard.
	var quiet:= PackedVector2Array()
	var loud:= PackedVector2Array()
	for i in 512:
		quiet.append(Vector2(0.0005, 0.0005))
		loud.append(Vector2(sin(i * 0.3), sin(i * 0.3)) * 0.7)
	_check("v011: mic: silence is silent", MicListener.hear_radius(MicListener.loudness(quiet, 1.0)) == 0.0)
	_check("v011: mic: shouting carries 30m+", MicListener.hear_radius(MicListener.loudness(loud, 1.0)) > 30.0)
	_check("v011: mic is off by default", GameState.settings.get("mic_enabled", true) == false)
	GameState.reset()


func _test_v012() -> void:
	GameState.reset()
	_check("v012: prices have an extra zero", Catalog.item("bait")["price"] == 100 and Catalog.item("tripod")["price"] == 1500 and Catalog.item("lava_lamp")["price"] == 450)
	# A tourist you photograph first can't flash you back.
	var t:= (load("res://cryptid.tscn") as PackedScene).instantiate() as Cryptid
	t.configure("grey_tourist")
	add_child(t)
	t.frozen = true
	var dummy:= Node3D.new()
	add_child(dummy)
	t.player_ref = dummy
	t.photographed_first()
	var flashed:= [false]
	t.flashed_player.connect(func(): flashed[0] = true)
	t.call("_enter_flee")
	_check("v012: snap a tourist first and it can't stun you", not flashed[0])
	t.free()
	dummy.free()
	# The RV sleeps four.
	var rv_in:= RVInterior.new()
	add_child(rv_in)
	_check("v012: RV interior is bigger (9 m x 3.8 m) with a bunk", RVInterior.HALF_L >= 4.5 and RVInterior.HALF_W >= 1.8 and rv_in.hotspots.has("bunk"))
	rv_in.free()
	# The camera is its own model in the hands (not sculpted into them).
	var p_scene:= load("res://player.tscn")
	var pl:= p_scene.instantiate() as Player
	add_child(pl)
	_check("v012: first-person camera is a separate model", pl.find_child("Camera", true, false) is CharacterModel)
	_check("v012: third-person body wears the camera", pl.find_child("ChestCamera", true, false) != null)
	var st:= pl.net_state()
	_check("v012: player reports its state for other players", st.size() == 11 and st[4] is String)
	pl.free()
	# Online plumbing: a puppet copies what the host sends and passes reactions back.
	var pup:= (load("res://cryptid.tscn") as PackedScene).instantiate() as Cryptid
	pup.configure("cornicorn")
	pup.puppet = true
	var calls: Array = []
	pup.forward = func(m: String, args: Array): calls.append([m, args])
	add_child(pup)
	pup.net_apply(Vector3(3, 1, 4), 1.0, Cryptid.State.CHASE, false, 0.3, 7)
	pup.on_flash(Vector3.ZERO)
	pup.hear_noise(Vector3.ZERO, 10.0)
	_check("v012: puppet takes the host's state", pup.state == Cryptid.State.CHASE and pup.net_target == 7 and pup.global_position.is_equal_approx(Vector3(3, 1, 4)))
	_check("v012: puppet forwards flashes and noise to the host", calls.size() == 2 and calls[0][0] == "on_flash" and calls[1][0] == "hear_noise")
	pup.free()
	var hosted:= Net.host_game(24711)
	_check("v012: can host a game", hosted and Net.online() and Net.is_host() and Net.players.size() == 1)
	Net.leave("")
	_check("v012: and stop hosting", not Net.online() and Net.has_authority())
	_check("v012: fullscreen can be toggled", GameState.has_method("toggle_fullscreen"))
	GameState.reset()


func _test_v013() -> void:
	# Voice: 16-bit round trip keeps the waveform.
	var wave:= PackedFloat32Array()
	for i in 320:
		wave.append(sin(i * 0.3) * 0.6)
	var back:= MicListener.decode(MicListener.encode(wave))
	var err:= 0.0
	for i in wave.size():
		err = maxf(err, absf(back[i] - wave[i]))
	_check("v013: voice survives 16-bit encoding", back.size() == 320 and err < 0.001)
	_check("v013: a voice packet is small (640 bytes / 20 ms)", MicListener.encode(wave).size() == 640)
	_check("v013: push-to-talk key exists", InputMap.has_action("voice_ptt"))
	# Remote players: coloured cap, and their voice plays from them.
	Net.players = {5: {"name": "Alex", "color": Color(0.25, 0.55, 1.0)}}
	var rp:= RemotePlayer.new()
	rp.peer_id = 5
	add_child(rp)
	_check("v013: other players wear their colour", rp.find_child("TeamCap*", true, false) != null)
	rp.play_voice(MicListener.encode(wave))
	_check("v013: their voice plays from their character", rp.voice_samples == 320 and rp.is_talking())
	rp.free()
	Net.players = {}
	# Someone else's UFO shows up as a copy you can photograph.
	var u:= UFO.new()
	u.ghost = true
	u.ghost_owner = 5
	add_child(u)
	u.ghost_apply(Vector3(1, 12, 2), true, false, 0.4)
	_check("v013: a copy of another player's UFO shows its beam", u.is_beaming() and u.get("_beam").visible)
	u.ghost_apply(Vector3(1, 12, 2), false, true, 0.0)
	_check("v013: ...and leaves when theirs does", u.phase == UFO.Phase.LEAVE)
	u.free()


func _test_v014() -> void:
	GameState.reset()
	_check("v014: maps are 20% bigger", is_equal_approx(Terrain.HALF, 144.0) and is_equal_approx(Terrain.RIM_START, 114.0))
	_check("v014: the UFO comes after 10 tourist photos", (load("res://scripts/main.gd") as GDScript).get_script_constant_map()["UFO_AFTER_FLASHES"] == 10)
	# Controls: rebind and swap, then reset.
	GameState.rebind("jump", KEY_E)
	_check("v014: rebinding a key works", GameState.bindings_of("jump") == [KEY_E] and InputMap.action_has_event("jump", _key(KEY_E)))
	_check("v014: ...and the action that had it gets the old key (swap)", GameState._index_of_binding(GameState.bindings_of("interact"), KEY_SPACE) >= 0)
	GameState.rebind("snap", "mouse:3")
	_check("v014: mouse buttons can be bound", GameState.binding_name(GameState.bindings_of("snap")[0]) == "Middle Mouse")
	GameState.reset_bindings()
	_check("v014: reset restores the defaults", GameState.bindings_of("jump") == [KEY_SPACE] and GameState.bindings_of("snap") == ["mouse:1"])
	# Day and night.
	GameState.current_map = "woods"
	var main_node: Node = (load("res://main.tscn") as PackedScene).instantiate()
	add_child(main_node)
	await get_tree().process_frame
	var cs: Array = main_node.get("_cryptids")
	_check("v014: a night is 15 minutes", is_equal_approx(main_node.NIGHT_LENGTH, 900.0) and not main_node.is_day)
	main_node.set("_night_time", 899.9)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("v014: then the sun comes up", main_node.is_day)
	var fleeing:= true
	for c in cs:
		if c.state != Cryptid.State.FLEE and c.state != Cryptid.State.TRAPPED:
			fleeing = false
	_check("v014: ...and the cryptids head home", fleeing)
	for c in cs:
		c.visible = false   # (they vanish 9 s later)
	var pl: Player = main_node.get("_player")
	_check("v014: nothing to photograph in daylight", pl.call("_all_cryptids").filter(func(x): return x is Cryptid).is_empty())
	main_node.free()
	# Settings live behind a Settings button now.
	var pm:= PauseMenu.new()
	add_child(pm)
	_check("v014: pause menu has Settings and Controls pages", pm.get("_settings_page") != null and pm.get("_controls_page") != null and not pm.get("_settings_page").visible)
	pm.free()
	GameState.reset()


func _key(k: int) -> InputEventKey:
	var e:= InputEventKey.new()
	e.keycode = k as Key
	return e
