extends CharacterBody3D
class_name Cryptid
## Any cryptid. Stats and temperament come from Species.DATA (scripts/species.gd).
## Hunters chase and grab, skittish ones bolt, lazy ones mostly can't be bothered.

signal caught_player
signal escaped
signal flashed_player   # a tourist took YOUR picture (and blinded you)

enum State {WANDER, INVESTIGATE, CHASE, CAUGHT, EATING, TRAPPED, FLEE}

@export var wander_speed:= 3.5
@export var investigate_speed:= 3.5
@export var chase_speed:= 6.0
@export var hear_radius:= 25.0
@export var chase_trigger_dist:= 12.0
@export var flash_chase_dist:= 25.0
@export var catch_dist:= 1.8
@export var lose_dist:= 25.0
@export var grab_time:= 0.5
@export var los_break_time:= 4.0
@export var distance_lose_time:= 3.0
@export var smell_radius:= 45.0
@export var eat_time:= 7.0
@export var distracted_trigger_dist:= 6.0
@export var distracted_flash_dist:= 6.0

var species_id:= "bigboobs"
var behaviour:= "hunter"
var display_name:= "Bigboobs"
var body_height:= 2.0
var photo_height:= 1.5
var flee_time:= 6.0

var state: int = State.WANDER
var player_ref: Node3D = null
var map_half:= 38.0
var camp:= Vector2(0, 34)
var terrain: Terrain = null
var water_level:= -1000.0
var home:= Vector2.INF        # wander around here (Methman's tent)
var home_radius:= 25.0
var frozen:= false

var bushes: Array = []

var grab_progress:= 0.0

var _info: Dictionary = {}
var _waypoint:= Vector3.ZERO
var _waypoint_timer:= 0.0
var _investigate_target:= Vector3.ZERO
var _investigate_timer:= 0.0
var _lose_timer:= 0.0
var _los_blocked_timer:= 0.0
var _scent_timer:= 0.0
var _last_known_pos:= Vector3.ZERO
var _grab_timer:= 0.0
var _walk_phase:= 0.0
var _facing:= Vector3(0, 0, 1)
var model: CharacterModel
var _alert_label: Label3D
var _bait_target: Node3D = null
var _bait_check:= 0.0
var _eat_timer:= 0.0
var _trap_timer:= 0.0
var _flee_timer:= 0.0
var _snap_timer:= 0.0
var _snap_cooldown:= 0.0
var _grumble_cooldown:= 0.0
var _call_timer:= -1.0
## < 1 while you're high: they move, think and animate in slow motion.
var time_factor:= 1.0
## Walking round the lake instead of into it: +1/-1 = which way round, held for a while.
var _detour_sign:= 0.0
var _detour_time:= 0.0
## Snagged on a rock, a trunk or the shoreline: sidestep for a moment.
var _stuck_ref:= Vector3.INF
var _stuck_t:= 0.0
var _unstick_time:= 0.0
var _unstick_dir:= Vector3.ZERO
var _victory_timer:= 0.0
var _step_side:= 1.0
var _voice: AudioStreamPlayer3D
var _feet: AudioStreamPlayer3D
var _snap_light: OmniLight3D
var _configured:= false
## The City: walk round the blocks instead of into them.
var city: CityBlocks = null
var _route: Array[Vector2] = []
var _route_goal:= Vector2.INF
var _route_timer:= 0.0
## Online, on a joining PC: no AI here, just a copy of the host's cryptid (NetSync feeds it).
## Reactions to your flashes and noise are passed back to the host through `forward`.
var puppet:= false
var net_index:= -1
var net_target:= 0          # peer id it's after (0 = nobody / offline)
var forward: Callable
var _net_pos:= Vector3.ZERO
var _net_rot:= 0.0
var _net_vel:= Vector3.ZERO
var _net_t:= -1.0
## Stalkers (The Rake) can't move while you're looking right at them.
var watched:= false
## Online host: a joining player is staring at it (they report it ~20x a second).
var remote_watch_until:= 0.0
var _stare:= 0.0
var _stare_limit:= 4.0
var _watch_check:= 0.0


## Apply a species from the table. Call before adding to the tree.
func configure(id: String) -> void:
	species_id = id
	_info = Species.info(id)
	behaviour = str(_info.get("behaviour", "hunter"))
	display_name = str(_info.get("name", id))
	wander_speed = float(_info.get("walk", 3.5))
	investigate_speed = wander_speed
	chase_speed = float(_info.get("chase", 6.0))
	hear_radius = float(_info.get("hear", 25.0))
	chase_trigger_dist = float(_info.get("trigger", 12.0))
	flash_chase_dist = float(_info.get("flash", 25.0))
	los_break_time = float(_info.get("los_break", 4.0))
	distance_lose_time = float(_info.get("lose_time", 3.0))
	body_height = float(_info.get("height", 2.0))
	photo_height = float(_info.get("photo_h", 1.5))
	home_radius = float(_info.get("home_radius", 25.0))
	if _info.has("call_every"):
		_call_timer = randf_range(4.0, float(_info["call_every"][1]))
	_configured = true


func _ready() -> void:
	add_to_group("traffic_stop")   # City cars brake for you
	# They follow the ground by height lookup; colliding with the terrain mesh as well
	# only snags them on slopes (that's what pinned them at the lake shore).
	if terrain != null:
		add_collision_exception_with(terrain)
	if not _configured:
		configure(species_id)
	var cs:= get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs:
		var cap:= CapsuleShape3D.new()
		cap.radius = float(_info.get("radius", 0.6))
		cap.height = maxf(body_height, cap.radius * 2.0 + 0.01)
		cs.shape = cap
	_build_body()
	_voice = _make_player(6.0)
	_feet = _make_player(2.0)
	_pick_waypoint()


func _make_player(vol: float) -> AudioStreamPlayer3D:
	var a:= AudioStreamPlayer3D.new()
	a.volume_db = vol
	a.unit_size = 8.0
	a.max_distance = 70.0
	a.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(a)
	return a


func _voice_name(kind: String) -> String:
	var v:= str(_info.get("voice", "bigfoot"))
	if v == "bigfoot":
		return "bigfoot_roar" if kind == "alert" else ("bigfoot_munch" if kind == "munch" else "bigfoot_grunt")
	if kind == "munch":
		return "bigfoot_munch"
	return v + "_" + kind


func _say(kind: String, pitch: float = 1.0) -> void:
	if _voice == null or not is_inside_tree():
		return
	var st:= Audio.get_stream(_voice_name(kind))
	if st == null:
		return
	_voice.stream = st
	_voice.pitch_scale = pitch * randf_range(0.92, 1.08)
	_voice.play()


func get_facing() -> Vector3:
	return _facing


func photo_point() -> Vector3:
	return global_position + Vector3(0, photo_height - body_height * 0.5, 0)


func stun_time() -> float:
	return float(_info.get("stun", 0.0))


func is_hostile() -> bool:
	return behaviour != "skittish"


func hear_noise(pos: Vector3, radius: float = -1.0) -> void:
	if not visible:
		return
	if puppet:
		if forward.is_valid():
			forward.call("hear_noise", [pos, radius])
		return
	if (state != State.WANDER and state != State.EATING) or frozen:
		return
	if _flat_dist(pos) <= (hear_radius if radius < 0.0 else radius):
		if state == State.EATING:
			_bait_target = null
		_say("grunt")
		state = State.INVESTIGATE
		_investigate_target = pos
		_investigate_timer = 0.0
		_show_label("?")


func on_flash(player_pos: Vector3) -> void:
	if not visible:
		return
	if puppet:
		if forward.is_valid():
			forward.call("on_flash", [player_pos])
		return
	if frozen:
		return
	var d:= _flat_dist(player_pos)
	if state == State.TRAPPED or state == State.CAUGHT:
		return
	if state == State.EATING:
		# Distracted by food: only a flash right in the face sets them off.
		if d <= distracted_flash_dist:
			_bait_target = null
			_react_to_player(true)
		return
	if d <= flash_chase_dist:
		_react_to_player(true)
	elif d <= hear_radius and state == State.WANDER:
		state = State.INVESTIGATE
		_investigate_target = player_pos
		_investigate_timer = 0.0
		_show_label("?")


## A tripod cam went off nearby: skittish ones bolt, the rest wander over to see what it was.
## (Nobody blames you for it.)
func on_device_flash(pos: Vector3) -> void:
	if not visible:
		return
	if puppet:
		if forward.is_valid():
			forward.call("on_device_flash", [pos])
		return
	if frozen or state == State.TRAPPED or state == State.CAUGHT or state == State.CHASE:
		return
	var d:= _flat_dist(pos)
	if d > hear_radius:
		return
	if behaviour == "skittish" and d < flash_chase_dist:
		_enter_flee()
	elif state != State.EATING:
		state = State.INVESTIGATE
		_investigate_target = pos
		_investigate_timer = 0.0
		_show_label("?")


## Hunters chase, skittish ones flee, lazy ones chase only if flashed.
func _react_to_player(flashed: bool) -> void:
	match behaviour:
		"skittish":
			_enter_flee()
		"lazy":
			if flashed:
				_enter_chase()
			elif _grumble_cooldown <= 0.0:
				_grumble_cooldown = 6.0
				_say("grunt")
				_show_label("...")
		_:
			_enter_chase()


func _enter_chase() -> void:
	if state == State.CHASE:
		return
	state = State.CHASE
	_lose_timer = 0.0
	_los_blocked_timer = 0.0
	_grab_timer = 0.0
	grab_progress = 0.0
	if player_ref != null:
		_last_known_pos = player_ref.global_position
	_show_label("!")
	_say("alert")


func _enter_flee() -> void:
	if state == State.FLEE:
		return
	state = State.FLEE
	_flee_timer = flee_time
	_bait_target = null
	_show_label("!!")
	_say("alert")
	# Tourists turn the tables: they snap a photo of you first.
	if _info.get("snaps_back", false) and _snap_cooldown <= 0.0 and player_ref != null and _flat_dist(player_ref.global_position) < 20.0:
		_snap_timer = 0.7
		_snap_cooldown = 10.0
		_face_toward(player_ref.global_position)
		if _snap_light:
			_snap_light.light_energy = 10.0
		if is_inside_tree():
			Audio.play_3d("shutter", global_position, -2.0)
		if _has_line_of_sight():
			flashed_player.emit()


## The Rake's trick: gone in a puff of grit, back a dozen metres behind whoever was staring.
func _vanish_and_reappear() -> void:
	_stare = 0.0
	_stare_limit = randf_range(3.0, 5.5)
	var who: Node3D = player_ref
	if who == null or not is_instance_valid(who) or who.get("indoors") == true:
		return
	var fwd:= -who.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()
	for i in 14:
		var ang:= randf_range(-0.6, 0.6)
		var dist:= randf_range(9.0, 14.0)
		var back:= (-fwd).rotated(Vector3.UP, ang)
		var q:= who.global_position + back * dist
		if absf(q.x) > map_half or absf(q.z) > map_half:
			continue
		if city != null and city.blocked(Vector2(q.x, q.z)):
			continue
		if _deep(q.x, q.z):
			continue
		spawn_puff(get_parent(), global_position + Vector3(0, 0.3, 0))
		Audio.play_3d(_voice_name("grunt"), global_position, 2.0, 60.0)
		var y:= terrain.height_at(q.x, q.z) + body_height * 0.5 if terrain else global_position.y
		global_position = Vector3(q.x, y, q.z)
		_face_toward(who.global_position)
		rotation.y = atan2(_facing.x, _facing.z)
		spawn_puff(get_parent(), global_position + Vector3(0, 0.3, 0))
		watched = false
		remote_watch_until = 0.0
		_route.clear()
		if state != State.CHASE:
			_enter_chase()
		else:
			_last_known_pos = who.global_position
			_los_blocked_timer = 0.0
		_say("alert")
		return


## A burst of dark grit (The Rake coming and going).
static func spawn_puff(parent: Node, pos: Vector3) -> void:
	if parent == null:
		return
	var p:= CPUParticles3D.new()
	p.one_shot = true
	p.amount = 46
	p.lifetime = 1.3
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.4, 1.3, 0.4)
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, 0.4, 0)
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.6
	var curve:= Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var mesh:= SphereMesh.new()
	mesh.radius = 0.3
	mesh.height = 0.6
	mesh.radial_segments = 6
	mesh.rings = 3
	p.mesh = mesh
	var m:= StandardMaterial3D.new()
	m.albedo_color = Color(0.08, 0.07, 0.07, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	p.material_override = m
	p.color = Color(0.1, 0.09, 0.09, 0.85)
	parent.add_child(p)
	p.global_position = pos + Vector3(0, 1.0, 0)
	p.emitting = true
	p.finished.connect(p.queue_free)


## Dawn: run off, and a few seconds later be gone for the day (kept in the list, just switched
## off, so the online copies stay in step).
func go_home_for_the_day() -> void:
	if not visible:
		return
	if not puppet:
		_grab_timer = 0.0
		grab_progress = 0.0
		if state != State.TRAPPED:
			_enter_flee()
	get_tree().create_timer(9.0).timeout.connect(func():
		visible = false
		set_physics_process(false)
		set_process(false)
		collision_layer = 0
		collision_mask = 0
		_hide_label()
		if _voice:
			_voice.stop())


## Online: after grabbing someone, let go and wander off (the night doesn't end for everyone).
func release_after_catch() -> void:
	if state != State.CAUGHT:
		return
	state = State.WANDER
	_grab_timer = 0.0
	grab_progress = 0.0
	_hide_label()
	_pick_waypoint()


## You got their picture before they got yours: no snapping back for a while.
func photographed_first() -> void:
	if puppet:
		if forward.is_valid():
			forward.call("photographed_first", [])
		return
	_snap_cooldown = maxf(_snap_cooldown, 12.0)


## Called by a Trap when they step in it.
func trap(duration: float) -> void:
	if puppet:
		if forward.is_valid():
			forward.call("trap", [duration])
		return
	if state == State.CAUGHT:
		return
	state = State.TRAPPED
	_trap_timer = duration
	_bait_target = null
	grab_progress = 0.0
	_grab_timer = 0.0
	velocity = Vector3.ZERO
	_show_label("?!")
	_say("alert", 1.25)


func is_distracted() -> bool:
	return state == State.EATING or state == State.TRAPPED


func _show_label(t: String) -> void:
	if _alert_label:
		_alert_label.visible = true
		_alert_label.text = t


func _hide_label() -> void:
	if _alert_label:
		_alert_label.visible = false


func _find_bait() -> Node3D:
	if not is_inside_tree():
		return null
	var best: Node3D = null
	var best_d:= smell_radius
	for b in get_tree().get_nodes_in_group("bait"):
		var n:= b as Node3D
		if n == null or n.is_queued_for_deletion() or n.get("claimed_by") not in [null, self]:
			continue
		var d:= _flat_dist(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func distance_to_player() -> float:
	if player_ref == null:
		return -1.0
	return _flat_dist(player_ref.global_position)


func is_player_hidden() -> bool:
	if player_ref == null:
		return false
	if player_ref.get("indoors") == true:
		return true   # safe inside the RV
	if player_ref.has_method("is_snared") and player_ref.is_snared():
		return false
	var p:= Vector2(player_ref.global_position.x, player_ref.global_position.z)
	for b in bushes:
		var bpos: Vector2 = b.get("pos", Vector2.ZERO)
		var brad: float = float(b.get("radius", 0.0))
		if p.distance_to(bpos) < brad:
			return true
	return false


## Is the player's camera pointed at us (and can it actually see us)?
func _is_watched() -> bool:
	if not puppet and Time.get_ticks_msec() / 1000.0 < remote_watch_until:
		return true
	if player_ref == null or not is_inside_tree():
		return false
	var cam:= get_viewport().get_camera_3d()
	if cam == null:
		return false
	var eye:= cam.global_position
	var to:= photo_point() - eye
	var d:= to.length()
	if d > 60.0 or d < 0.01:
		return false
	var fwd:= -cam.global_transform.basis.z
	if fwd.dot(to / d) < cos(deg_to_rad(32.0)):
		return false
	var q:= PhysicsRayQueryParameters3D.create(eye, photo_point())
	q.exclude = [get_rid(), player_ref.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _has_line_of_sight() -> bool:
	if player_ref == null:
		return false
	if is_player_hidden():
		return false
	if not is_inside_tree():
		return true
	var space:= get_world_3d().direct_space_state
	var from:= global_position + Vector3(0, body_height * 0.3, 0)
	var to:= player_ref.global_position + Vector3(0, 0.7, 0)
	var query:= PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit:= space.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.get("collider") == player_ref


func _flat_dist(pos: Vector3) -> float:
	return Vector2(global_position.x, global_position.z).distance_to(Vector2(pos.x, pos.z))


func _check_proximity() -> void:
	if player_ref == null or frozen:
		return
	var trigger:= distracted_trigger_dist if state == State.EATING else chase_trigger_dist
	# Crouched photographers are harder to notice.
	if player_ref.has_method("is_crouching") and player_ref.is_crouching():
		trigger *= 0.6
	if _flat_dist(player_ref.global_position) < trigger:
		if _has_line_of_sight():
			if state == State.EATING and behaviour != "lazy":
				_bait_target = null
			_react_to_player(false)


func _check_bait(delta: float) -> bool:
	_bait_check -= delta
	if _bait_target != null and not is_instance_valid(_bait_target):
		_bait_target = null
	if _bait_target == null and _bait_check <= 0.0:
		_bait_check = 0.5
		_bait_target = _find_bait()
		if _bait_target != null:
			_bait_target.set("claimed_by", self)
			if state == State.WANDER:
				_say("grunt", 1.2)
			state = State.INVESTIGATE
			_show_label("sniff?")
	return _bait_target != null


func _face_toward(p: Vector3) -> void:
	var d:= p - global_position
	d.y = 0.0
	if d.length() > 0.05:
		_facing = d.normalized()


func _physics_process(delta: float) -> void:
	if puppet:
		_puppet_step(delta)
		return
	if frozen:
		velocity = Vector3.ZERO
		return
	delta *= time_factor
	_snap_cooldown = maxf(0.0, _snap_cooldown - delta)
	_grumble_cooldown = maxf(0.0, _grumble_cooldown - delta)
	# Loud far-carrying calls while wandering (the Jersey Devil's "WOOO!").
	if _call_timer > 0.0 and state == State.WANDER:
		_call_timer -= delta
		if _call_timer <= 0.0:
			_call_timer = randf_range(float(_info["call_every"][0]), float(_info["call_every"][1]))
			if is_inside_tree():
				Audio.play_3d(_voice_name("grunt"), global_position + Vector3(0, body_height * 0.8, 0), 8.0, 160.0)
	_victory_timer = maxf(0.0, _victory_timer - delta)
	if _snap_light:
		_snap_light.light_energy = maxf(0.0, _snap_light.light_energy - delta * 40.0)
	var speed:= 0.0
	var target:= Vector3.ZERO
	var has_target:= false
	if behaviour == "stalker":
		_watch_check -= delta
		if _watch_check <= 0.0:
			_watch_check = 0.1
			watched = _is_watched()
		# Stare at it too long and it's simply... not there any more. Then it's behind you.
		if watched:
			_stare += delta
			if _stare > _stare_limit:
				_vanish_and_reappear()
		else:
			_stare = maxf(0.0, _stare - delta * 0.5)
	match state:
		State.WANDER:
			speed = wander_speed
			target = _waypoint
			has_target = _victory_timer <= 0.0
			_waypoint_timer -= delta
			if _waypoint_timer <= 0.0:
				_pick_waypoint()
			if _flat_dist(_waypoint) < 1.0:
				_pick_waypoint()
			if _check_bait(delta):
				target = _bait_target.global_position
			_check_proximity()
		State.INVESTIGATE:
			speed = investigate_speed
			target = _investigate_target
			has_target = true
			if _check_bait(delta):
				target = _bait_target.global_position
				speed = investigate_speed * 1.15
				if _flat_dist(target) < 0.7:
					state = State.EATING
					_eat_timer = 0.0
					_show_label("nom")
					has_target = false
					_say("munch")
			elif _flat_dist(_investigate_target) < 1.2:
				_investigate_timer += delta
				if _investigate_timer > 2.0:
					state = State.WANDER
					_hide_label()
					_pick_waypoint()
			_check_proximity()
		State.CHASE:
			speed = chase_speed
			if player_ref:
				var d:= _flat_dist(player_ref.global_position)
				var los:= _has_line_of_sight()
				if los:
					_last_known_pos = player_ref.global_position
					_los_blocked_timer = 0.0
				else:
					_los_blocked_timer += delta
					# In the City you duck round a corner, not into a thicket: they follow
					# your footsteps round the block for a while.
					if city != null and d < 35.0:
						_scent_timer -= delta
						if _scent_timer <= 0.0:
							_scent_timer = 1.2
							_last_known_pos = player_ref.global_position
				if d > lose_dist:
					_lose_timer += delta
				else:
					_lose_timer = 0.0
				if _lose_timer > distance_lose_time or _los_blocked_timer > los_break_time * (1.8 if city != null else 1.0):
					state = State.WANDER
					_hide_label()
					_grab_timer = 0.0
					grab_progress = 0.0
					escaped.emit()
					_pick_waypoint()
					has_target = false
					speed = 0.0
				else:
					target = player_ref.global_position if los else _last_known_pos
					has_target = true
					if los and d < catch_dist:
						_grab_timer += delta
						grab_progress = clampf(_grab_timer / grab_time, 0.0, 1.0)
						if _grab_timer >= grab_time:
							state = State.CAUGHT
							velocity = Vector3.ZERO
							_hide_label()
							caught_player.emit()
							return
					else:
						_grab_timer = 0.0
						grab_progress = 0.0
		State.FLEE:
			if _snap_timer > 0.0:
				_snap_timer -= delta  # holding the camera up
			else:
				speed = chase_speed
				_flee_timer -= delta
				if player_ref != null:
					var away:= global_position - player_ref.global_position
					away.y = 0.0
					if away.length() < 0.01:
						away = Vector3(randf() - 0.5, 0, randf() - 0.5)
					target = global_position + away.normalized() * 6.0
					has_target = true
					if _flat_dist(player_ref.global_position) > lose_dist + 10.0:
						_flee_timer = minf(_flee_timer, 0.5)
				if _flee_timer <= 0.0:
					state = State.WANDER
					_hide_label()
					_pick_waypoint()
		State.CAUGHT:
			velocity = Vector3.ZERO
			return
		State.EATING:
			if _bait_target == null or not is_instance_valid(_bait_target):
				_finish_eating()
			else:
				_face_toward(_bait_target.global_position)
				_eat_timer += delta
				if _bait_target.has_method("set_eaten_fraction"):
					_bait_target.set_eaten_fraction(_eat_timer / eat_time)
				if fmod(_eat_timer, 1.4) < delta and _voice and not _voice.playing:
					_say("munch")
				if _eat_timer >= eat_time:
					_bait_target.queue_free()
					_finish_eating()
			_check_proximity()
		State.TRAPPED:
			_trap_timer -= delta
			_walk_phase += delta * 14.0
			if _trap_timer <= 0.0:
				_show_label("!")
				state = State.WANDER
				if player_ref != null and _flat_dist(player_ref.global_position) <= hear_radius:
					if behaviour == "skittish":
						_enter_flee()
					else:
						_enter_chase()
				else:
					_hide_label()
					_pick_waypoint()
	if has_target:
		target = _next_step(target, delta)
		var to:= target - global_position
		to.y = 0.0
		var dist:= to.length()
		if dist > 0.3:
			var dir:= _steer_around_water(to / dist, delta)
			if _unstick_time > 0.0:
				_unstick_time -= delta
				if not _deep(global_position.x + _unstick_dir.x * 1.2, global_position.z + _unstick_dir.z * 1.2):
					dir = _unstick_dir
			_check_stuck(dir, speed, delta)
			_facing = dir
			velocity.x = dir.x * speed
			velocity.z = dir.z * speed
			_walk_phase += delta * speed * 1.6
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	velocity.y = 0.0
	if state == State.EATING or state == State.TRAPPED or (watched and state != State.TRAPPED):
		velocity.x = 0.0
		velocity.z = 0.0
	var before:= global_position
	velocity.x *= time_factor
	velocity.z *= time_factor
	move_and_slide()
	if terrain != null:
		global_position.x = clampf(global_position.x, -map_half - 10.0, map_half + 10.0)
		global_position.z = clampf(global_position.z, -map_half - 10.0, map_half + 10.0)
		# Nobody wades into deep water (steering should already have kept them out).
		# Moving toward the shore is always allowed, so nobody can get pinned at the edge.
		if _deep(global_position.x, global_position.z) \
				and terrain.height_at(global_position.x, global_position.z) < terrain.height_at(before.x, before.z) - 0.001:
			global_position.x = before.x
			global_position.z = before.z
			if state == State.WANDER:
				_waypoint_timer = 0.0
		global_position.y = terrain.height_at(global_position.x, global_position.z) + body_height * 0.5
	rotation.y = atan2(_facing.x, _facing.z)
	if model:
		model.time_scale = 0.0 if watched else time_factor
	if watched:
		return  # frozen mid-stride, pose and all
	_animate()


# ------------------------------------------------------------------ online copies

## Host -> here: where it is, which way it faces, what it's doing.
func net_apply(pos: Vector3, rot: float, st: int, w: bool, grab: float, target: int) -> void:
	var now:= Time.get_ticks_msec() / 1000.0
	if _net_t > 0.0 and pos.distance_to(_net_pos) > 6.0:
		# A teleport (The Rake reappearing behind someone): jump, don't glide.
		spawn_puff(get_parent(), global_position + Vector3(0, 0.3, 0))
		global_position = pos
		_net_vel = Vector3.ZERO
		spawn_puff(get_parent(), pos + Vector3(0, 0.3, 0))
	elif _net_t > 0.0 and now > _net_t:
		_net_vel = (pos - _net_pos) / maxf(now - _net_t, 0.03)
		_net_vel.y = 0.0
	else:
		global_position = pos
	_net_t = now
	_net_pos = pos
	_net_rot = rot
	watched = w
	grab_progress = grab
	net_target = target
	if st != state:
		var was:= state
		state = st
		_on_net_state(was)


func _on_net_state(was: int) -> void:
	match state:
		State.CHASE:
			_show_label("!")
			_say("alert")
		State.FLEE:
			_show_label("!!")
			if was != State.FLEE:
				_say("alert")
		State.INVESTIGATE:
			_show_label("?")
		State.EATING:
			_show_label("nom")
		State.TRAPPED:
			_show_label("?!")
			_say("alert", 1.25)
		_:
			_hide_label()


func _puppet_step(delta: float) -> void:
	if _net_t < 0.0:
		return
	# Run slightly ahead of the last report (it's ~1/15 s old), then ease onto it.
	var want:= _net_pos + _net_vel * 0.05
	global_position = global_position.lerp(want, clampf(delta * 12.0, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, _net_rot, clampf(delta * 12.0, 0.0, 1.0))
	var stale:= Time.get_ticks_msec() / 1000.0 - _net_t > 0.4
	velocity = Vector3.ZERO if stale or state in [State.EATING, State.TRAPPED, State.CAUGHT] else _net_vel
	_facing = Vector3(sin(rotation.y), 0, cos(rotation.y))
	if velocity.length() > 0.1:
		_walk_phase += delta * velocity.length() * 1.6
	if model:
		model.time_scale = 0.0 if watched else time_factor
	if not watched:
		_animate()


func _play(n: String, speed: float = 1.0) -> void:
	if model == null:
		return
	if model.has_anim(n):
		model.play(n, speed)
	elif n in ["eat", "trapped", "roar", "snap", "cheer"]:
		model.play("idle", 2.5 if n == "trapped" else 1.0)
	else:
		model.play("idle")


## Pick the model animation that matches what they're doing.
func _animate() -> void:
	if model == null:
		return
	var hs:= Vector2(velocity.x, velocity.z).length()
	var moving:= hs > 0.1
	match state:
		State.TRAPPED:
			_play("trapped")
		State.EATING:
			_play("eat")
		State.CAUGHT:
			_play("roar")
		State.CHASE:
			if moving:
				model.play_locomotion("run", hs)
			else:
				_play("roar")
		State.FLEE:
			if _snap_timer > 0.0:
				_play("snap")
			else:
				model.play_locomotion("run", hs)
		_:
			if _victory_timer > 0.0:
				_play(str(_info.get("victory_anim", "idle")))
			elif moving:
				model.play_locomotion("walk", hs)
			else:
				_play("idle")
	if moving:
		var every:= float(_info.get("step_every", 1.0))
		var s:= sin(_walk_phase / every) * 0.5
		if signf(s) != _step_side:
			_step_side = signf(s)
			if _feet and is_inside_tree():
				_feet.stream = Audio.get_stream(str(_info.get("steps", "bigstep")))
				_feet.pitch_scale = randf_range(0.85, 1.1)
				_feet.volume_db = 4.0 if state == State.CHASE else 0.0
				_feet.play()


## After someone gets away from a hunter, the Jersey Devil does a little celebration.
func celebrate() -> void:
	if _info.has("victory_anim"):
		_victory_timer = 2.5
		_say("grunt")


func _finish_eating() -> void:
	_bait_target = null
	_eat_timer = 0.0
	state = State.WANDER
	_hide_label()
	_pick_waypoint()


func _deep(x: float, z: float) -> bool:
	return terrain != null and water_level > -100.0 and terrain.height_at(x, z) < water_level - 0.6


## Uphill direction on the ground here (away from the water at a shoreline).
func _uphill(p: Vector3) -> Vector3:
	var hx:= terrain.height_at(p.x + 1.0, p.z) - terrain.height_at(p.x - 1.0, p.z)
	var hz:= terrain.height_at(p.x, p.z + 1.0) - terrain.height_at(p.x, p.z - 1.0)
	var u:= Vector3(hx, 0, hz)
	if u.length() < 0.001:
		u = Vector3(p.x - Terrain.LAKE_C.x, 0, p.z - Terrain.LAKE_C.y)
	return u.normalized()


## If the way ahead is deep water, follow the shoreline (along the slope) instead.
## Picks the way round that's closest to where they want to go and sticks with it for a bit.
func _steer_around_water(dir: Vector3, delta: float) -> Vector3:
	if terrain == null or water_level < -100.0:
		return dir
	_detour_time = maxf(0.0, _detour_time - delta)
	var p:= global_position
	var up:= _uphill(p)
	# Already standing in deep water somehow: climb straight out.
	if _deep(p.x, p.z):
		return up
	var ahead_blocked:= false
	for d in [1.2, 2.6]:
		if _deep(p.x + dir.x * d, p.z + dir.z * d):
			ahead_blocked = true
	if not ahead_blocked:
		if _detour_time <= 0.0:
			_detour_sign = 0.0
		return dir
	var tangent:= Vector3(-up.z, 0, up.x)
	if _detour_sign == 0.0:
		_detour_sign = 1.0 if tangent.dot(dir) >= 0.0 else -1.0
	_detour_time = 2.5
	var tdir:= tangent * _detour_sign
	for lean in [0.2, 0.5, 1.0]:
		var cand: Vector3 = (tdir + up * float(lean)).normalized()
		if not _deep(p.x + cand.x * 1.5, p.z + cand.z * 1.5):
			return cand
	return up


func _check_stuck(dir: Vector3, speed: float, _delta: float) -> void:
	if speed < 0.5:
		return
	# Engine physics step, not the passed delta: move_and_slide always moves by the real step.
	_stuck_t += get_physics_process_delta_time()
	if _stuck_t < 1.2:
		return
	_stuck_t = 0.0
	var moved:= INF if _stuck_ref == Vector3.INF else Vector2(global_position.x - _stuck_ref.x, global_position.z - _stuck_ref.z).length()
	_stuck_ref = global_position
	if moved < 0.35 * speed:
		_unstick_time = 1.1
		_unstick_dir = dir.rotated(Vector3.UP, deg_to_rad(80.0) * (1.0 if randf() < 0.5 else -1.0))
		if state == State.WANDER:
			_pick_waypoint()


## Would walking straight from here to (x, z) go through the lake?
func _path_wet(x: float, z: float) -> bool:
	if terrain == null or water_level < -100.0:
		return false
	var a:= Vector2(global_position.x, global_position.z)
	var b:= Vector2(x, z)
	var n:= int(a.distance_to(b) / 4.0) + 1
	for i in range(1, n):
		var q:= a.lerp(b, float(i) / n)
		if _deep(q.x, q.y):
			return true
	return false


func _good_spot(x: float, z: float) -> bool:
	if city != null and city.blocked(Vector2(x, z)):
		return false
	if Vector2(x, z).distance_to(camp) <= 22.0:
		return false
	if is_inside_tree() and _path_wet(x, z) and randf() < 0.85:
		return false   # mostly pick places they can walk to without going round the lake
	if terrain != null and water_level > -100.0:
		var h:= terrain.height_at(x, z)
		if h < water_level + 0.15:
			return false
		# Water-lovers hang around the shoreline.
		if _info.get("water_lover", false) and h > water_level + 3.0 and randf() < 0.75:
			return false
	return true


## Next point to head for on the way to target (round buildings, over the bridge).
func _next_step(target: Vector3, delta: float) -> Vector3:
	if city == null:
		return target
	var me:= Vector2(global_position.x, global_position.z)
	var goal:= Vector2(target.x, target.z)
	_route_timer -= delta
	if _route_timer <= 0.0 or goal.distance_to(_route_goal) > 3.0:
		_route_timer = 0.7
		_route_goal = goal
		_route = city.route(me, goal)
	while _route.size() > 1 and me.distance_to(_route[0]) < 2.0:
		_route.remove_at(0)
	if _route.is_empty():
		return target
	return Vector3(_route[0].x, target.y, _route[0].y)


func _pick_waypoint() -> void:
	for _i in 30:
		var x: float
		var z: float
		if home != Vector2.INF:
			var a:= randf() * TAU
			var r:= sqrt(randf()) * home_radius
			x = home.x + cos(a) * r
			z = home.y + sin(a) * r
		else:
			x = randf_range(-map_half, map_half)
			z = randf_range(-map_half, map_half)
		if _good_spot(x, z):
			_waypoint = Vector3(x, 0, z)
			_waypoint_timer = randf_range(8.0, 15.0)
			return
	_waypoint = Vector3(randf_range(-map_half, map_half), 0, randf_range(-map_half, map_half))
	_waypoint_timer = 10.0


func _build_body() -> void:
	# Sculpted model (tools/characters.py). Feet sit at the bottom of the capsule.
	model = CharacterModel.load_model(str(_info.get("model", "res://models/bigboobs.glb")), float(_info.get("outline", 0.014)))
	model.position = Vector3(0, -body_height * 0.5, 0)
	add_child(model)
	model.play("idle")
	_alert_label = Label3D.new()
	_alert_label.text = "!"
	_alert_label.font_size = 64
	_alert_label.modulate = Color(1, 0.2, 0.2)
	_alert_label.position = Vector3(0, body_height * 0.5 + 0.35, 0)
	_alert_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_alert_label.visible = false
	add_child(_alert_label)
	if _info.get("snaps_back", false):
		_snap_light = OmniLight3D.new()
		_snap_light.light_color = Color(1, 0.97, 0.9)
		_snap_light.omni_range = 18.0
		_snap_light.light_energy = 0.0
		_snap_light.position = Vector3(0, photo_height - body_height * 0.5, 0.4)
		add_child(_snap_light)
