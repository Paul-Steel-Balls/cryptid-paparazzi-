extends CharacterBody3D
class_name Player
## The tabloid photographer. First-person (arms + camera viewmodel) or
## third-person (over-the-shoulder, full body). V toggles.

signal photo_taken(result: Dictionary)
signal film_empty
signal interact_requested
signal item_placed(kind: String, node: Node3D)
signal out_of_item(kind: String)
signal snared
signal view_changed(third_person: bool)
signal flash_not_ready
signal aim_changed(aiming: bool)
signal item_selected(kind: String)
signal stunned(duration: float)
signal need_aim
signal fell_in_water
signal item_consumed(kind: String)

@export var walk_speed:= 5.0
@export var sprint_speed:= 7.0
@export var look_sens:= 0.003
@export var crouch_speed:= 2.5
@export var jump_velocity:= 4.8

const SHOT_COOLDOWN:= 5.0      # flash recharge between photos
const STAND_HEIGHT:= 1.5       # capsule height
const CROUCH_HEIGHT:= 0.95
const CROUCH_EYE:= 0.22

const LAYER_VIEWMODEL:= 2   # only the first-person camera sees this
const LAYER_BODY:= 4        # only the third-person camera sees this
const EYE_HEIGHT:= 0.75
## Where the camera sits in the first-person arms' own frame (tools/characters.py FP_CAMERA).
const FP_CAMERA:= Vector3(-0.13, -0.2, 0.52)

var bigfoot_ref: Cryptid = null   # single-cryptid shortcut (tests)
var cryptids: Array = []          # everyone on the map
var extra_subjects: Array = []    # photographable non-cryptids (PhotoSubject: UFO, Santa)
var bystanders: Array = []        # ordinary people (the City): they set off tripods, worth nothing
var touch_controls = null
var is_touch:= false
var terrain: Terrain = null
var map_limit:= 39.0
var third_person:= false
var crouching:= false
## Right mouse held: camera up at the eye. Only then does left click take a photo.
var aiming:= false
## "bait" or "trap": what Q drops.
var selected_item:= "bait"
## Inside the RV (no terrain/water rules, cryptids can't reach you).
var indoors:= false
## Cutscenes (Toe Rogan swapping cameras, sleeping, driving) freeze the controls.
var controls_locked:= false
var _stun_timer:= 0.0
var _aim_t:= 0.0
## Toggle-sprint mode (pause menu): Shift flips this; stopping cancels it.
var _sprint_latched:= false
## Third-person body: turned toward the way you're moving (head keeps looking at the reticle).
var _body_yaw:= 0.0
var _body_target:= 0.0
var _backpedal:= false
## How far the body may turn from where you're looking (the head turns the rest of the way).
const MAX_BODY_TWIST:= 1.2
var _sprinting:= false
var _head_look: HeadLook
## Footsteps follow the walk cycle: phase 0..1, heel strikes at 0.25 and 0.75.
var _gait_phase:= 0.0
## Toe Rogan has your camera: hide the first-person arms.
var hands_empty:= false

var _yaw:= 0.0
var _pitch:= 0.0
var _camera: Camera3D
var _noise_timer:= 0.0
var _snap_cooldown:= 0.0
var _snare_timer:= 0.0
var _shake:= 0.0
var _snap_kick:= 0.0
var _bob:= 0.0
var _step_dist:= 0.0
var _bob_amt:= 0.0
var _was_on_floor:= true
var _air_time:= 0.0
## Lake surface height on maps with water (-1000 = no water).
var water_level:= -1000.0
const BEER_DURATION:= 25.0
const JOINT_DURATION:= 12.0
const BEER_SPEED:= 1.3
## Seconds left on a beer (faster, louder) and on a joint (main slows the world down).
var beer_time:= 0.0
var joint_time:= 0.0
## Last spot you stood on solid, dry footing (shore or dock): where you end up if you fall in.
var _last_safe:= Vector3.ZERO
var _crouch_toggle:= false
var _crouch_t:= 0.0
var _jump_request:= false
var _shape: CapsuleShape3D
var _shape_node: CollisionShape3D

var _tp_pivot: Node3D
var _tp_arm: SpringArm3D
var _tp_camera: Camera3D
var _viewmodel: Node3D
var _vm_rest:= Vector3(0.0, 0.0, 0.0)
var _vm_flash_mat: StandardMaterial3D
var _body: Node3D
var _body_model: CharacterModel
var _flash_light: OmniLight3D

var _jacket:= Color(0.55, 0.47, 0.3)
var _skin:= Color(0.93, 0.74, 0.58)


func _ready() -> void:
	add_to_group("traffic_stop")   # City cars brake for you
	collision_mask |= CityBlocks.PROPS_LAYER   # you bump into street furniture; cryptids don't
	_camera = $Camera3D
	_shape_node = $CollisionShape3D
	_shape = (_shape_node.shape as CapsuleShape3D).duplicate()
	_shape_node.shape = _shape
	_camera.near = 0.04
	_camera.fov = 75.0
	_camera.cull_mask = 0xFFFFF & ~LAYER_BODY
	is_touch = DisplayServer.is_touchscreen_available()
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.6
	_build_viewmodel()
	_build_body()
	_build_third_person_rig()
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.97, 0.9)
	_flash_light.omni_range = 26.0
	_flash_light.light_energy = 0.0
	_flash_light.position = Vector3(0, EYE_HEIGHT, -0.6)
	add_child(_flash_light)
	set_third_person(GameState.third_person)
	_last_safe = position


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if GameState.game_over:
		return
	if event is InputEventScreenTouch and event.pressed:
		is_touch = true
	if controls_locked or GameState.menu_open:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens:= look_sens * float(GameState.settings.get("sensitivity", 1.0)) * (0.6 if aiming else 1.0)
		_yaw -= event.relative.x * sens
		_pitch = clampf(_pitch - event.relative.y * sens, deg_to_rad(-80.0), deg_to_rad(80.0))
		_apply_look()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.is_action_pressed("aim"):
			set_aiming(true)
		elif event.is_action_released("aim"):
			set_aiming(false)
		elif event.is_action_pressed("snap"):
			if aiming:
				snap_photo()
			else:
				need_aim.emit()
	if event.is_action_pressed("sprint") and bool(GameState.settings.get("toggle_sprint", false)):
		_sprint_latched = not _sprint_latched
	if event.is_action_pressed("toggle_view"):
		toggle_view()
	if event.is_action_pressed("select_bait"):
		select_item("bait")
	if event.is_action_pressed("select_trap"):
		select_item("trap")
	if event.is_action_pressed("select_tripod"):
		select_item("tripod")
	if event.is_action_pressed("select_joint"):
		select_item("joint")
	if event.is_action_pressed("select_beer"):
		select_item("beer")
	if event.is_action_pressed("select_flashtrap"):
		select_item("flashtrap")
	if event.is_action_pressed("use_item"):
		use_item()
	if event.is_action_pressed("jump"):
		jump()
	if event.is_action_pressed("crouch_toggle"):
		toggle_crouch()


func _physics_process(delta: float) -> void:
	if _snap_cooldown > 0.0:
		_snap_cooldown -= delta
	_stun_timer = maxf(0.0, _stun_timer - delta)
	beer_time = maxf(0.0, beer_time - delta)
	joint_time = maxf(0.0, joint_time - delta)
	if GameState.game_over or controls_locked or GameState.menu_open:
		velocity = Vector3(0, velocity.y if GameState.menu_open else 0.0, 0)
		if not indoors and not controls_locked:
			move_and_slide()
		return

	if touch_controls != null and is_touch:
		var ld: Vector2 = touch_controls.get_look_delta()
		if ld != Vector2.ZERO:
			_yaw -= ld.x * look_sens * 2.0
			_pitch = clampf(_pitch - ld.y * look_sens * 2.0, deg_to_rad(-80.0), deg_to_rad(80.0))
			_apply_look()

	var fwd:= 0.0
	var strafe:= 0.0
	var sprinting:= false
	if is_touch and touch_controls != null:
		var mv: Vector2 = touch_controls.move_vector
		fwd = -mv.y
		strafe = mv.x
		sprinting = mv.length() > 0.9
	else:
		fwd = Input.get_axis("move_back", "move_forward")
		strafe = Input.get_axis("move_left", "move_right")
		if bool(GameState.settings.get("toggle_sprint", false)):
			if absf(fwd) + absf(strafe) < 0.1:
				_sprint_latched = false
			sprinting = _sprint_latched
		else:
			sprinting = Input.is_action_pressed("sprint")
	if _snare_timer > 0.0:
		_snare_timer -= delta
		fwd = 0.0
		strafe = 0.0
		sprinting = false
		_jump_request = false
	if _stun_timer > 0.0:
		# Flashed: you can stumble about half-speed, but can't sprint, jump or aim.
		fwd *= 0.5
		strafe *= 0.5
		sprinting = false
		_jump_request = false
	crouching = _crouch_toggle or (not is_touch and Input.is_action_pressed("crouch_hold"))
	if crouching or aiming:
		sprinting = false
	var speed:= sprint_speed if sprinting else walk_speed
	if aiming:
		speed = walk_speed * 0.55
	if crouching:
		speed = crouch_speed
	if beer_time > 0.0:
		speed *= BEER_SPEED
	var input_vec:= Vector2(strafe, fwd)
	if input_vec.length() > 1.0:
		input_vec = input_vec.normalized()
	# Which way the body faces. Diagonals and sideways: turn into the move.
	# Straight-ish backwards: backpedal facing forward (slower), unless sprinting,
	# in which case turn all the way round and run toward the camera.
	# The head always follows the mouse, so the body may only twist so far from where you're
	# looking (no snapped necks). Mostly-backwards movement = run backwards (backpedal),
	# facing the camera's way; flips back to running forwards past ~90 degrees (with a little
	# hysteresis so it doesn't flicker on the diagonal).
	if input_vec.length() > 0.1:
		var ang:= atan2(-input_vec.x, input_vec.y)
		var limit:= deg_to_rad(95.0) if _backpedal else deg_to_rad(110.0)
		_backpedal = absf(ang) > limit
		if _backpedal:
			_body_target = wrapf(ang - signf(ang) * PI, -PI, PI)
			if not aiming and not crouching:
				speed = sprint_speed * 0.8 if sprinting else walk_speed * 0.72
		else:
			_body_target = ang
		_body_target = clampf(_body_target, -MAX_BODY_TWIST, MAX_BODY_TWIST)
		if aiming:
			_body_target = clampf(_body_target, -0.6, 0.6)
	else:
		_backpedal = false
		_body_target = 0.0
	_sprinting = sprinting
	var forward:= Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right:= Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var wish:= forward * input_vec.y + right * input_vec.x
	velocity.x = wish.x * speed
	velocity.z = wish.z * speed
	if not is_on_floor():
		velocity.y -= 12.0 * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	if _jump_request:
		_jump_request = false
		if is_on_floor():
			velocity.y = jump_velocity
			_crouch_toggle = false
			if is_inside_tree():
				Audio.play("step", -8.0, 0.1)
	_update_crouch(delta)
	var before:= global_position
	move_and_slide()
	# Wade the shallows, walk the dock, but no swimming out into the deep.
	if water_level > -100.0 and terrain != null and not indoors:
		var gh:= terrain.height_at(global_position.x, global_position.z)
		var gh_before:= terrain.height_at(before.x, before.z)
		var feet:= global_position.y - STAND_HEIGHT * 0.5
		# From the shallows you can't wade out into the deep...
		if gh < water_level - 1.1 and feet < water_level + 0.3 and gh < gh_before - 0.02:
			global_position.x = before.x
			global_position.z = before.z
		# Jumped off the dock (or over the shallows) into the deep: you're hauled back out
		# to the last dry footing (the dock itself if you jumped from it). No swimming with the camera.
		if gh < water_level - 1.1 and feet < water_level - 0.35:
			global_position = _last_safe
			velocity = Vector3.ZERO
			fell_in_water.emit()
		elif is_on_floor() and (gh >= water_level - 1.1 or feet > water_level + 0.15):
			_last_safe = global_position
	if is_on_floor():
		if not _was_on_floor and _air_time > 0.25 and is_inside_tree():
			Audio.play("wade" if _in_water() else "land", -6.0, 0.05)
		_air_time = 0.0
	else:
		_air_time += delta
	_was_on_floor = is_on_floor()
	if not indoors:
		global_position.x = clampf(global_position.x, -map_limit, map_limit)
		global_position.z = clampf(global_position.z, -map_limit, map_limit)
	# Safety net: never fall through the world.
	if terrain != null and not indoors:
		var gy:= terrain.height_at(global_position.x, global_position.z)
		if global_position.y < gy - 0.5:
			global_position.y = gy + EYE_HEIGHT + 0.2
			velocity.y = 0.0

	var hspeed:= Vector2(velocity.x, velocity.z).length()
	if hspeed > 0.1 and is_on_floor():
		_bob += delta * hspeed * 1.9
		_advance_gait(hspeed, delta, sprinting)

	# Sprinting is noisy. After a beer, so is walking (unless you crouch).
	var noisy:= sprinting or (beer_time > 0.0 and not crouching)
	if noisy and input_vec.length() > 0.1 and not indoors and not _all_cryptids().is_empty():
		_noise_timer -= delta
		if _noise_timer <= 0.0:
			_noise_timer = 0.5
			for c in _all_cryptids():
				c.hear_noise(global_position)
	if Input.is_action_just_pressed("interact"):
		interact()


func _process(delta: float) -> void:
	# Raising the camera: zoom in, arms bring it up to the eye, then you're looking through it.
	_aim_t = move_toward(_aim_t, 1.0 if aiming else 0.0, delta * 6.0)
	var e:= _aim_t * _aim_t * (3.0 - 2.0 * _aim_t)
	_camera.fov = lerpf(75.0, 50.0, e)
	_snap_kick = maxf(0.0, _snap_kick - delta * 3.5)
	_shake = maxf(0.0, _shake - delta * 2.0)
	if _flash_light:
		_flash_light.light_energy = maxf(0.0, _flash_light.light_energy - delta * 60.0)
	if _vm_flash_mat:
		_vm_flash_mat.emission_energy_multiplier = 0.1 + 0.8 * flash_ready_fraction() + _snap_kick * 6.0
	_animate_viewmodel()
	_animate_body()
	# Head bob (first person): a gentle figure-8 while walking, bigger when sprinting,
	# low and swaying when crouch-walking. Plus trap shake.
	var hs:= Vector2(velocity.x, velocity.z).length()
	var amt:= 0.0
	if is_on_floor() and hs > 0.2:
		amt = clampf(hs / walk_speed, 0.0, 1.5) * (0.022 if _crouch_t < 0.5 else 0.012)
	_bob_amt = lerpf(_bob_amt, amt, clampf(delta * 8.0, 0.0, 1.0))
	var sway_x:= sin(_bob * 0.5) * _bob_amt * (1.0 if _crouch_t < 0.5 else 2.2)
	var bob_y:= -absf(cos(_bob * 0.5)) * _bob_amt
	var a:= _shake * 0.05
	_camera.h_offset = sway_x + (randf_range(-a, a) if _shake > 0.0 else 0.0)
	_camera.v_offset = bob_y + (randf_range(-a, a) if _shake > 0.0 else 0.0)
	_camera.rotation.z = sin(_bob * 0.5) * _bob_amt * (0.6 if _crouch_t < 0.5 else 1.4)
	if beer_time > 0.0:
		# a little tipsy
		var tt:= Time.get_ticks_msec() / 1000.0
		_camera.rotation.z += sin(tt * 1.3) * 0.035 * minf(1.0, beer_time / 3.0)
		_camera.h_offset += sin(tt * 0.9) * 0.03 * minf(1.0, beer_time / 3.0)
	if _tp_camera:
		_tp_camera.h_offset = randf_range(-a, a) if _shake > 0.0 else 0.0
		_tp_camera.v_offset = randf_range(-a, a) if _shake > 0.0 else 0.0


# --------------------------------------------------------------- actions

func interact() -> void:
	interact_requested.emit()


## The locomotion animation that matches how you're moving right now.
func _gait_anim(hspeed: float) -> String:
	if _crouch_t > 0.5:
		return "crouch_walk"
	if aiming:
		return "walk"
	if hspeed > walk_speed + 0.5:
		return "run"
	return "jog"


## Metres covered per footstep for an animation: half its cycle at its natural ground speed.
func _step_length(anim: String) -> float:
	var fallback:= {"walk": 0.9, "jog": 1.2, "run": 1.5, "crouch_walk": 0.6}
	if _body_model == null or _body_model.anim_player == null or not _body_model.anim_player.has_animation(anim):
		return float(fallback.get(anim, 1.2))
	var gs:= float(_body_model.ground_speed.get(anim, 0.0))
	var length:= _body_model.anim_player.get_animation(anim).length
	return gs * length * 0.5 if gs > 0.01 else float(fallback.get(anim, 1.2))


## Footsteps land on the heel strikes of the walk cycle: in third person straight from the
## animation's own clock, in first person from distance travelled / step length.
func _advance_gait(hspeed: float, delta: float, sprinting: bool) -> void:
	var anim:= _gait_anim(hspeed)
	var prev:= _gait_phase
	var ap: AnimationPlayer = _body_model.anim_player if _body_model else null
	if third_person and ap and ap.current_animation == anim and ap.current_animation_length > 0.0:
		_gait_phase = fposmod(ap.current_animation_position / ap.current_animation_length, 1.0)
		if _backpedal:
			_gait_phase = 1.0 - _gait_phase   # playing in reverse: run the clock forwards anyway
	else:
		_gait_phase = fposmod(_gait_phase + hspeed * delta / (2.0 * _step_length(anim)), 1.0)
	var crossed:= false
	for c in [0.25, 0.75]:
		if (prev < c and _gait_phase >= c) or (prev > _gait_phase and (c > prev or c <= _gait_phase)):
			crossed = true
	if crossed and is_inside_tree():
		Audio.play(_step_sound(sprinting), -14.0 if crouching else (-5.0 if sprinting else -9.0), 0.08)


func _in_water() -> bool:
	return not indoors and water_level > -100.0 and terrain != null and terrain.height_at(global_position.x, global_position.z) < water_level - 0.05


func _step_sound(sprinting: bool) -> String:
	if _in_water():
		return "wade"
	if crouching:
		return "sneak"
	return "run" if sprinting else "step"


func set_aiming(on: bool) -> void:
	if (controls_locked or _stun_timer > 0.0) and on:
		return
	if aiming == on:
		return
	aiming = on
	_update_cameras()
	if on and is_inside_tree():
		Audio.play("whoosh", -22.0, 0.05)
	aim_changed.emit(on)


## Raising the camera always looks through it, even from third person.
func _update_cameras() -> void:
	if _tp_camera == null or not is_inside_tree():
		return
	var fp:= not third_person or aiming
	_camera.current = fp
	_tp_camera.current = not fp


func select_item(kind: String) -> void:
	selected_item = kind
	item_selected.emit(kind)


func use_item() -> Node3D:
	match selected_item:
		"bait":
			return place_bait()
		"trap":
			return place_trap()
		"tripod":
			return place_tripod()
		"flashtrap":
			return place_flashtrap()
		"joint", "beer":
			consume(selected_item)
	return null


## Joint or beer. The effects run on timers: beer_time (here), joint_time (main slows the world).
func consume(kind: String) -> bool:
	if GameState.game_over or controls_locked:
		return false
	if not GameState.take_item(kind):
		out_of_item.emit(kind)
		return false
	if kind == "beer":
		beer_time = BEER_DURATION
		if is_inside_tree():
			Audio.play("crackin_grunt", -4.0, 0.1)   # *crack*... *burp*
	else:
		joint_time = JOINT_DURATION
		if is_inside_tree():
			Audio.play("whoosh", -12.0)
	item_consumed.emit(kind)
	return true


func is_inebriated() -> bool:
	return beer_time > 0.0 or joint_time > 0.0


func place_tripod() -> Node3D:
	if GameState.game_over or indoors:
		return null
	if not GameState.take_item("tripod"):
		out_of_item.emit("tripod")
		return null
	var t:= Tripod.new()
	var world:= get_parent() if get_parent() != null else self
	world.add_child(t)
	t.global_position = _drop_point(1.4)
	t.rotation.y = _yaw          # looks the way you were looking
	t.player = self
	if is_inside_tree():
		Audio.play_3d("trap_set", t.global_position, -6.0)
	item_placed.emit("tripod", t)
	return t


## Flash trap: hidden prank for the other players (FlashTrap fires on RemotePlayers only).
func place_flashtrap() -> Node3D:
	if GameState.game_over or indoors:
		return null
	if not GameState.take_item("flashtrap"):
		out_of_item.emit("flashtrap")
		return null
	var t:= FlashTrap.new()
	var world:= get_parent() if get_parent() != null else self
	world.add_child(t)
	t.global_position = _drop_point(1.2)
	t.rotation.y = _yaw
	t.owner_player = self
	if is_inside_tree():
		Audio.play_3d("trap_set", t.global_position, -10.0)
	item_placed.emit("flashtrap", t)
	return t


## Tourist flash: blinded and dazed for a moment.
func stun(duration: float) -> void:
	_stun_timer = maxf(_stun_timer, duration)
	set_aiming(false)
	if is_inside_tree():
		Audio.play("stun_ring", -6.0)
	stunned.emit(duration)


func is_stunned() -> bool:
	return _stun_timer > 0.0


func jump() -> void:
	if GameState.game_over or _snare_timer > 0.0 or controls_locked or _stun_timer > 0.0:
		return
	_jump_request = true


func toggle_crouch() -> void:
	_crouch_toggle = not _crouch_toggle


func is_crouching() -> bool:
	return crouching


## 0 right after a shot, 1 when the flash is ready again.
func flash_ready_fraction() -> float:
	return clampf(1.0 - _snap_cooldown / SHOT_COOLDOWN, 0.0, 1.0)


func _update_crouch(delta: float) -> void:
	var target:= 1.0 if crouching else 0.0
	_crouch_t = move_toward(_crouch_t, target, delta * 7.0)
	var h:= lerpf(STAND_HEIGHT, CROUCH_HEIGHT, _crouch_t)
	_shape.height = h
	# Keep the feet planted: shrink from the top.
	_shape_node.position.y = -(STAND_HEIGHT - h) * 0.5
	_camera.position.y = lerpf(EYE_HEIGHT, CROUCH_EYE, _crouch_t)
	if _tp_pivot:
		_tp_pivot.position.y = lerpf(0.55, 0.1, _crouch_t)
	if _flash_light:
		_flash_light.position.y = _camera.position.y


func toggle_view() -> void:
	if indoors or controls_locked:
		return   # no room to swing a camera boom in the RV
	set_third_person(not third_person)
	if is_inside_tree():
		Audio.play("whoosh", -10.0)


func set_third_person(on: bool) -> void:
	third_person = on
	GameState.third_person = on
	if _tp_camera == null:
		return
	_update_cameras()
	_viewmodel.visible = not on or aiming
	_apply_look()
	view_changed.emit(on)


func active_camera() -> Camera3D:
	return _tp_camera if third_person and not aiming and _tp_camera != null else _camera


## Where the photo is taken from and which way it points.
func photo_ray() -> Array:
	var eye:= _camera.global_position
	if not third_person or aiming or _tp_camera == null:
		return [eye, -_camera.global_transform.basis.z]
	# Third person: aim where the crosshair (centre of the TP view) points.
	var tp_fwd:= -_tp_camera.global_transform.basis.z
	var aim:= _tp_camera.global_position + tp_fwd * 25.0
	return [eye, (aim - eye).normalized()]


func snap_photo() -> void:
	if GameState.game_over:
		return
	if _snap_cooldown > 0.0:
		flash_not_ready.emit()
		return
	if GameState.film <= 0 or hands_empty:
		film_empty.emit()
		if is_inside_tree():
			Audio.play("dry_click", -4.0)
		return
	_snap_cooldown = SHOT_COOLDOWN
	GameState.film -= 1
	_snap_kick = 1.0
	if _flash_light:
		_flash_light.light_energy = 14.0
	if is_inside_tree():
		Audio.play("shutter", -2.0, 0.05)
		get_tree().create_timer(0.35).timeout.connect(func(): Audio.play("flash_charge", -14.0))
	var result:= evaluate_shot()
	# Whoever's in the picture got flashed first: a tourist you've already snapped
	# is too dazzled to snap you back.
	for c in result.get("subjects", []):
		if is_instance_valid(c) and c.has_method("photographed_first"):
			c.photographed_first()
	for c in _all_cryptids():
		c.on_flash(global_position)
	# Shaky hands: anything shot while drunk or high pays half.
	if result.get("in_frame", false) and is_inebriated():
		result["value"] = int(result["value"]) / 2
		result["reason"] = str(result["reason"]) + "  (shaky: half pay)"
	if result.get("in_frame", false):
		GameState.unsold_photos.append({"value": int(result["value"]), "quality": str(result["reason"]),
			"species": result["species_list"], "scores": result.get("scores", {}), "map": GameState.current_map})
	photo_taken.emit(result)


func _all_cryptids() -> Array:
	var out: Array = []
	for c in cryptids:
		if is_instance_valid(c) and (c as Node3D).visible:   # gone home at dawn = not there
			out.append(c)
	if out.is_empty() and bigfoot_ref != null and is_instance_valid(bigfoot_ref) and bigfoot_ref.visible:
		out.append(bigfoot_ref)
	for e in extra_subjects:
		if is_instance_valid(e):
			out.append(e)
	return out


func _occluded(from: Vector3, to: Vector3, target: Node, exclude: Array = []) -> bool:
	if not is_inside_tree():
		return false
	var q:= PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()] + exclude
	var hit:= get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.get("collider") != target


## Score the shot against every cryptid in view. Best one sets the base value,
## each extra cryptid in frame adds a bonus, and rarity on this map multiplies pay.
func evaluate_shot() -> Dictionary:
	var ray:= photo_ray()
	return evaluate_from(ray[0], ray[1])


## Score a picture taken from eye looking along dir. up_close: a tripod right in a cryptid's
## path gets the danger bonus as if you'd stood there yourself.
func evaluate_from(eye: Vector3, dir: Vector3, up_close: bool = false, exclude: Array = []) -> Dictionary:
	var ray:= [eye, dir]
	var best:= {"in_frame": false, "score": 0, "value": 0, "reason": "No cryptid in frame", "facing": false,
		"danger": false, "distance": 0.0, "species": "", "species_list": []}
	var in_frame: Array = []
	var subjects: Array = []
	var raw: Dictionary = {}
	var best_value:= -1.0
	for c in _all_cryptids():
		var r:= PhotoScoring.evaluate(c.photo_point(), c.get_facing(), ray[0], ray[1], c.state)
		if not r.get("in_frame", false):
			if best_value < 0.0 and str(r.get("reason", "")) != "Cryptid not in frame":
				best["reason"] = r["reason"]
			continue
		if up_close and not r.get("danger", false):
			r["score"] = int(round(float(r["score"]) * 1.5))
			r["danger"] = true
			if int(r["score"]) >= 60:
				r["reason"] = "AMAZING SHOT!"
			elif int(r["score"]) >= 35:
				r["reason"] = "GREAT SHOT!"
		if _occluded(ray[0], c.photo_point(), c, exclude):
			if best_value < 0.0:
				best["reason"] = "Something's in the way!"
			continue
		var v:= float(r["score"]) * Species.pay_mult(GameState.current_map, c.species_id)
		if c.get("flat_pay") != null and r.get("in_frame", false):
			v = float(c.get("flat_pay"))   # the UFO: a set price for a clear shot
		if c.get("paid_out") == true:
			v = 0.0   # already got the money shot of this one
		in_frame.append(c.species_id)
		subjects.append(c)
		raw[c.species_id] = maxi(int(raw.get(c.species_id, 0)), int(r["score"]))
		if v > best_value:
			best_value = v
			best = r
			best["species"] = c.species_id
	if best_value >= 0.0:
		var unique: Array = []
		for id in in_frame:
			if id not in unique:
				unique.append(id)
		var bonus:= 1.0 + PhotoScoring.GROUP_BONUS * float(in_frame.size() - 1)
		best["value"] = int(round(best_value * bonus))
		best["species_list"] = unique
		best["scores"] = raw
		best["group"] = in_frame.size()
		best["subjects"] = subjects
		var who:= Species.display_name(best["species"])
		best["reason"] = "%s — %s" % [who, best["reason"]] + (" (+%d more!)" % (in_frame.size() - 1) if in_frame.size() > 1 else "")
	return best


func _drop_point(ahead: float) -> Vector3:
	var fwd:= Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var p:= global_position + fwd * ahead
	if terrain != null:
		p.y = terrain.height_at(p.x, p.z)
	else:
		p.y = global_position.y - EYE_HEIGHT
	return p


func place_bait() -> Node3D:
	if GameState.game_over:
		return null
	if GameState.bait <= 0:
		out_of_item.emit("bait")
		return null
	GameState.bait -= 1
	var b:= Bait.new()
	var world:= get_parent() if get_parent() != null else self
	world.add_child(b)
	b.global_position = _drop_point(1.8)
	b.rotation.y = randf() * TAU
	if is_inside_tree():
		Audio.play_3d("bait_drop", b.global_position, 0.0)
	item_placed.emit("bait", b)
	return b


func place_trap() -> Node3D:
	if GameState.game_over:
		return null
	if GameState.traps <= 0:
		out_of_item.emit("trap")
		return null
	GameState.traps -= 1
	var t:= Trap.new()
	var world:= get_parent() if get_parent() != null else self
	world.add_child(t)
	t.global_position = _drop_point(1.3)
	t.rotation.y = _yaw
	if is_inside_tree():
		Audio.play_3d("trap_set", t.global_position, 0.0)
	item_placed.emit("trap", t)
	return t


## Stepped in a (probably your own) trap.
func snare(duration: float) -> void:
	_snare_timer = duration
	Achievements.note_snared()
	_shake = 1.0
	if is_inside_tree():
		Audio.play("ouch", 0.0)
	snared.emit()


func is_snared() -> bool:
	return _snare_timer > 0.0


## Turn to look at a point (cutscenes).
func face_point(p: Vector3, seconds: float = 0.4) -> void:
	var eye:= _camera.global_position
	var d:= p - eye
	var target_yaw:= atan2(-d.x, -d.z)
	var target_pitch:= atan2(d.y, Vector2(d.x, d.z).length())
	target_yaw = _yaw + wrapf(target_yaw - _yaw, -PI, PI)
	if seconds <= 0.0 or not is_inside_tree():
		_yaw = target_yaw
		_pitch = target_pitch
		_apply_look()
		return
	var tw:= create_tween()
	tw.tween_method(func(t: float):
		_yaw = lerpf(_yaw, target_yaw, t)
		_pitch = lerpf(_pitch, target_pitch, t)
		_apply_look(), 0.0, 1.0, seconds)


func set_look(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = pitch
	_apply_look()


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## The photo snapshot is grabbed with a gentler flash so the print isn't blown out.
func set_flash_energy(e: float) -> void:
	if _flash_light:
		_flash_light.light_energy = e


func first_person_camera() -> Camera3D:
	return _camera


## What other players need to draw you: [position, look yaw, body yaw relative to it, pitch,
## anim, speed, backpedal, crouching, indoors, snared, hands empty, camera raised].
func net_state() -> Array:
	var hspeed:= Vector2(velocity.x, velocity.z).length()
	var anim:= "idle"
	if not is_on_floor() and _air_time > 0.08 and not indoors:
		anim = "jump"
	elif _snap_kick > 0.4:
		anim = "snap"
	elif _crouch_t > 0.5:
		anim = "crouch_walk" if hspeed > 0.2 else "crouch"
	elif aiming and hspeed <= 0.2:
		anim = "aim"
	elif hspeed > 0.2:
		anim = _gait_anim(hspeed)
	return [global_position, _yaw, _body_yaw, _pitch, anim, hspeed, _backpedal,
		_crouch_t > 0.5, indoors, _snare_timer > 0.0, hands_empty, aiming and not hands_empty]


func _apply_look() -> void:
	rotation.y = _yaw
	_camera.rotation.x = _pitch
	if _tp_pivot:
		_tp_pivot.rotation.x = clampf(_pitch, deg_to_rad(-70.0), deg_to_rad(45.0))


# ------------------------------------------------------------- visuals

func _mat(c: Color, emissive: bool = false) -> StandardMaterial3D:
	var m:= StandardMaterial3D.new()
	m.albedo_color = c
	if emissive:
		m.emission_enabled = true
		m.emission = c
	return m


func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, layer: int) -> MeshInstance3D:
	var mi:= MeshInstance3D.new()
	var bm:= BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.layers = layer
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r: float, h: float, mat: Material, pos: Vector3, layer: int) -> MeshInstance3D:
	var mi:= MeshInstance3D.new()
	var cm:= CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.layers = layer
	parent.add_child(mi)
	return mi


func _ball(parent: Node3D, r: float, mat: Material, pos: Vector3, layer: int) -> MeshInstance3D:
	var mi:= MeshInstance3D.new()
	var sm:= SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.layers = layer
	parent.add_child(mi)
	return mi


## A box stretched between two points (a limb).
func _limb(parent: Node3D, a: Vector3, b: Vector3, thick: float, mat: Material, layer: int) -> MeshInstance3D:
	var mi:= _box(parent, Vector3(thick, thick, 1.0), mat, Vector3.ZERO, layer)
	_set_limb(mi, a, b, thick)
	return mi


func _set_limb(mi: MeshInstance3D, a: Vector3, b: Vector3, thick: float) -> void:
	var d:= b - a
	var length:= maxf(d.length(), 0.001)
	var up:= Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var basis:= Basis.looking_at(d / length, up)
	mi.transform = Transform3D(basis.scaled_local(Vector3(1.0, 1.0, length)), (a + b) * 0.5)
	(mi.mesh as BoxMesh).size = Vector3(thick, thick, 1.0)


func _build_camera_prop(parent: Node3D, layer: int, flash_mat: StandardMaterial3D) -> void:
	var black:= _mat(Color(0.08, 0.08, 0.09))
	var silver:= _mat(Color(0.7, 0.7, 0.72))
	var glass:= _mat(Color(0.2, 0.35, 0.6), true)
	_box(parent, Vector3(0.2, 0.12, 0.08), black, Vector3.ZERO, layer)
	_box(parent, Vector3(0.2, 0.025, 0.082), silver, Vector3(0, 0.06, 0), layer)
	var lens:= _cyl(parent, 0.045, 0.1, black, Vector3(0, -0.005, -0.08), layer)
	lens.rotation.x = PI / 2.0
	var glass_disc:= _cyl(parent, 0.035, 0.005, glass, Vector3(0, -0.005, -0.131), layer)
	glass_disc.rotation.x = PI / 2.0
	_box(parent, Vector3(0.09, 0.06, 0.06), black, Vector3(0.05, 0.1, -0.005), layer)
	_box(parent, Vector3(0.075, 0.042, 0.006), flash_mat, Vector3(0.05, 0.1, -0.037), layer)
	_cyl(parent, 0.012, 0.015, _mat(Color(0.9, 0.1, 0.1)), Vector3(0.075, 0.07, 0.01), layer)


func _build_viewmodel() -> void:
	_viewmodel = Node3D.new()
	_viewmodel.name = "Viewmodel"
	_viewmodel.position = _vm_rest
	_camera.add_child(_viewmodel)
	# Sculpted arms + camera (tools/characters.py -> fp_arms), authored facing +Z.
	var arms:= CharacterModel.load_model("res://models/fp_arms.glb", 0.004)
	arms.name = "Arms"
	arms.rotation.y = PI
	arms.scale = Vector3.ONE * 0.85
	arms.position = Vector3(0.0, 0.01, 0.0)
	_viewmodel.add_child(arms)
	# The camera is its own model, held in the hands (never sculpted into them: no blending).
	var cam_model:= CharacterModel.load_model("res://models/camera.glb", 0.0025)
	cam_model.name = "Camera"
	cam_model.position = FP_CAMERA
	arms.add_child(cam_model)
	arms.set_layers(LAYER_VIEWMODEL)
	cam_model.set_layers(LAYER_VIEWMODEL)
	for mat in cam_model.glow_materials():
		_vm_flash_mat = mat


func _build_body() -> void:
	_body = Node3D.new()
	_body.name = "BodyModel"
	add_child(_body)
	_load_body_model()
	if not GameState.skin_changed.is_connected(_on_skin_changed):
		GameState.skin_changed.connect(_on_skin_changed)


## Your outfit (Skins): the third-person body and what others see.
func _load_body_model() -> void:
	if _body_model:
		_body_model.queue_free()
		_body_model = null
		_head_look = null
	var sk:= GameState.skin
	_body_model = CharacterModel.load_model(Skins.model_path(sk), 0.012)
	_body_model.rotation.y = PI          # model faces +Z, the player faces -Z
	_body_model.position.y = -STAND_HEIGHT * 0.5
	_body_model.scale = Vector3.ONE * 0.9
	_body.add_child(_body_model)
	attach_camera(_body_model, LAYER_BODY, float(Skins.info(sk)["cam_z"]))
	_body_model.set_layers(LAYER_BODY)
	_body_model.play("idle")
	if _body_model.skeleton:
		_head_look = HeadLook.new()
		_body_model.skeleton.add_child(_head_look)
		Skins.add_springs(_body_model)


func _on_skin_changed(_id: String) -> void:
	if is_inside_tree() and _body != null:
		_load_body_model()


## Where the camera sits when held up to the eye (model space, in front of the face).
const FACE_CAMERA:= Vector3(0, 1.655, 0.205)


## Hang the camera on a photographer model's chest (also used for other players' bodies).
static func attach_camera(model: CharacterModel, layer: int = 1, z: float = 0.19) -> void:
	var ba:= model.attach("chest")
	if ba == null:
		return
	var sk:= model.skeleton
	var chest:= sk.get_bone_global_rest(sk.find_bone("chest"))
	var cam:= CharacterModel.load_model("res://models/camera_lo.glb", 0.003)
	cam.name = "ChestCamera"
	cam.position = chest.affine_inverse() * Vector3(0, 1.225, z)
	ba.add_child(cam)
	cam.set_layers(layer)


## The camera held up to the eye (other players see this while you're aiming).
static func attach_face_camera(model: CharacterModel, layer: int = 1, z: float = FACE_CAMERA.z) -> Node3D:
	var ba:= model.attach("head")
	if ba == null:
		return null
	ba.name = "FaceCamAttach"
	var sk:= model.skeleton
	var head:= sk.get_bone_global_rest(sk.find_bone("head"))
	var cam:= CharacterModel.load_model("res://models/camera_lo.glb", 0.003)
	cam.name = "FaceCamera"
	cam.position = head.affine_inverse() * Vector3(FACE_CAMERA.x, FACE_CAMERA.y, z)
	ba.add_child(cam)
	cam.set_layers(layer)
	return cam


## Online: a cap in the player's colour (over the sculpted red one) so you can tell people apart.
static func set_cap_color(model: CharacterModel, col: Color) -> void:
	var old:= model.find_child("TeamCap", true, false)
	if old:
		old.queue_free()
	var ba:= model.attach("head")
	if ba == null:
		return
	ba.name = "TeamCap"
	var sk:= model.skeleton
	var inv:= sk.get_bone_global_rest(sk.find_bone("head")).affine_inverse()
	var m:= StandardMaterial3D.new()
	m.albedo_color = col
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.roughness = 0.8
	for part in [[Vector3(0, 1.748, 0.0), Vector3(0.158, 0.09, 0.163)], [Vector3(0, 1.736, 0.152), Vector3(0.116, 0.014, 0.106)],
			[Vector3(0, 1.834, 0.0), Vector3(0.021, 0.021, 0.021)]]:
		var mi:= MeshInstance3D.new()
		var sm:= SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		mi.mesh = sm
		mi.material_override = m
		mi.position = inv * (part[0] as Vector3)
		mi.scale = part[1]
		mi.layers = model.meshes[0].layers if not model.meshes.is_empty() else 1
		ba.add_child(mi)


func _build_third_person_rig() -> void:
	_tp_pivot = Node3D.new()
	_tp_pivot.name = "TPPivot"
	_tp_pivot.position = Vector3(0, 0.55, 0)
	add_child(_tp_pivot)
	_tp_arm = SpringArm3D.new()
	_tp_arm.name = "SpringArm"
	_tp_arm.spring_length = 3.4
	_tp_arm.margin = 0.25
	_tp_arm.position = Vector3(0.55, 0.15, 0)
	_tp_arm.add_excluded_object(get_rid())
	var probe:= SphereShape3D.new()
	probe.radius = 0.2
	_tp_arm.shape = probe
	_tp_pivot.add_child(_tp_arm)
	_tp_camera = Camera3D.new()
	_tp_camera.name = "ThirdPersonCamera"
	_tp_camera.fov = 70.0
	_tp_camera.far = _camera.far
	_tp_camera.cull_mask = 0xFFFFF & ~LAYER_VIEWMODEL
	_tp_arm.add_child(_tp_camera)


func _animate_viewmodel() -> void:
	if _viewmodel == null:
		return
	var hs:= Vector2(velocity.x, velocity.z).length()
	var moving:= is_on_floor() and hs > 0.2
	var bob_amt:= (0.012 if _crouch_t < 0.5 else 0.008) if moving else 0.0
	var side:= 1.0 if _crouch_t < 0.5 else 2.0
	var bob:= Vector3(cos(_bob * 0.5) * bob_amt * side, -absf(sin(_bob * 0.5)) * bob_amt, 0.0)
	var breathe:= Vector3(0, sin(Time.get_ticks_msec() / 900.0) * 0.003, 0)
	var tuck:= Vector3(-0.04, -0.03, 0.06) * _crouch_t  # camera pulled in close while sneaking
	var kick:= Vector3(0, _snap_kick * 0.03, _snap_kick * 0.05)
	var raise:= Vector3(0.0, 0.17, 0.26) * (_aim_t * _aim_t * (3.0 - 2.0 * _aim_t))
	_viewmodel.position = _vm_rest + (bob + breathe + tuck) * (1.0 - _aim_t) + kick + raise
	_viewmodel.visible = (not third_person or aiming) and _aim_t < 0.85 and not hands_empty
	_viewmodel.rotation = Vector3(_snap_kick * 0.2 + 0.08 * _crouch_t, 0.0, sin(_bob * 0.5) * bob_amt * 2.0 * side)
	if _snare_timer > 0.0:
		_viewmodel.rotation.z = sin(Time.get_ticks_msec() / 40.0) * 0.08


func _animate_body() -> void:
	# Body swings round to the move direction; the head stays on the reticle. (Tracked in first
	# person too: that's what other players see.) Kept in -PI..PI: lerp_angle can drift past PI,
	# and an un-wrapped angle is what left the head clamped over one shoulder after a backwards sprint.
	var dt:= get_process_delta_time()
	_body_yaw = wrapf(lerp_angle(_body_yaw, _body_target, clampf(dt * 9.0, 0.0, 1.0)), -PI, PI)
	if _body_model == null or not third_person:
		return
	var hspeed:= Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() and _air_time > 0.08 and not indoors:
		_body_model.play("jump", 1.0, 0.1)
	elif _snap_kick > 0.4:
		_body_model.play("snap", 1.0, 0.05)
	elif _crouch_t > 0.5:
		if hspeed > 0.2:
			_body_model.play_locomotion("crouch_walk", hspeed)
		else:
			_body_model.play("crouch")
	elif aiming and hspeed <= 0.2:
		_body_model.play("aim")
	elif hspeed > 0.2:
		_body_model.play_locomotion(_gait_anim(hspeed), hspeed, 0.2, _backpedal)
	else:
		_body_model.play("idle")
	if _snare_timer > 0.0:
		_body.rotation.z = sin(Time.get_ticks_msec() / 40.0) * 0.1
	else:
		_body.rotation.z = 0.0
	_body.rotation.y = _body_yaw
	if _head_look:
		_head_look.yaw = -_body_yaw
		_head_look.pitch = -_pitch * 0.6
