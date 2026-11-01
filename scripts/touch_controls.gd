extends CanvasLayer
class_name TouchControls






signal snap_pressed
signal interact_pressed
signal bait_pressed
signal trap_pressed
signal view_pressed
signal jump_pressed
signal crouch_pressed

var move_vector:= Vector2.ZERO

var _look_delta:= Vector2.ZERO
var _look_touch:= -1
var _last_look_pos:= Vector2.ZERO
var _joy_touch:= -1
var _joy_base: Control
var _joy_knob: Control
var _snap_button: Button
var _interact_button: Button
var _extra_buttons: Array[Button] = []
var _joy_radius:= 60.0


func _ready() -> void:
	var root:= Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(root, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0)
	add_child(root)

	_joy_base = Control.new()
	_joy_base.name = "Joystick"
	_joy_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_joy_base, 0.0, 1.0, 0.0, 1.0, 40.0, -190.0, 180.0, -50.0)
	var base_bg:= ColorRect.new()
	base_bg.color = Color(0, 0, 0, 0.35)
	_place(base_bg, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0)
	_joy_base.add_child(base_bg)
	_joy_knob = ColorRect.new()
	_joy_knob.color = Color(1, 1, 1, 0.85)
	_joy_knob.size = Vector2(56, 56)
	_joy_knob.position = Vector2(42, 42)
	_joy_base.add_child(_joy_knob)
	root.add_child(_joy_base)

	_snap_button = Button.new()
	_snap_button.name = "SnapButton"
	_snap_button.text = "SNAP!"
	_place(_snap_button, 1.0, 1.0, 1.0, 1.0, -190.0, -190.0, -40.0, -40.0)
	_snap_button.add_theme_font_size_override("font_size", 28)
	_snap_button.pressed.connect(func(): snap_pressed.emit())
	root.add_child(_snap_button)

	_interact_button = Button.new()
	_interact_button.name = "InteractButton"
	_interact_button.text = "ENTER RV"
	_place(_interact_button, 1.0, 1.0, 1.0, 1.0, -190.0, -330.0, -40.0, -210.0)
	_interact_button.add_theme_font_size_override("font_size", 22)
	_interact_button.visible = false
	_interact_button.pressed.connect(func(): interact_pressed.emit())
	root.add_child(_interact_button)

	_add_button(root, "BAIT", 1.0, 1.0, -330.0, -190.0, -205.0, -120.0, func(): bait_pressed.emit())
	_add_button(root, "TRAP", 1.0, 1.0, -330.0, -110.0, -205.0, -40.0, func(): trap_pressed.emit())
	_add_button(root, "VIEW", 1.0, 0.0, -150.0, 105.0, -20.0, 160.0, func(): view_pressed.emit())
	_add_button(root, "JUMP", 1.0, 1.0, -470.0, -110.0, -345.0, -40.0, func(): jump_pressed.emit())
	_add_button(root, "CROUCH", 1.0, 1.0, -470.0, -190.0, -345.0, -120.0, func(): crouch_pressed.emit())


func _add_button(root: Control, label: String, ax: float, ay: float, l: float, t: float, r: float, b: float, cb: Callable) -> void:
	var btn:= Button.new()
	btn.name = label.capitalize() + "Button"
	btn.text = label
	_place(btn, ax, ay, ax, ay, l, t, r, b)
	btn.add_theme_font_size_override("font_size", 22)
	btn.pressed.connect(cb)
	root.add_child(btn)
	_extra_buttons.append(btn)


func set_interact_visible(v: bool) -> void:
	_interact_button.visible = v


func get_look_delta() -> Vector2:
	var d:= _look_delta
	_look_delta = Vector2.ZERO
	return d


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch:= event as InputEventScreenTouch
		if touch.pressed:
			var pos:= touch.position
			if _in_control(pos, _joy_base):
				_joy_touch = touch.index
				_update_joy(pos)
			elif _in_control(pos, _snap_button) or _in_control(pos, _interact_button):
				pass
			elif _look_touch == -1:
				_look_touch = touch.index
				_last_look_pos = pos
		else:
			if touch.index == _joy_touch:
				_joy_touch = -1
				move_vector = Vector2.ZERO
				_joy_knob.position = Vector2(42, 42)
			if touch.index == _look_touch:
				_look_touch = -1
	elif event is InputEventScreenDrag:
		var drag:= event as InputEventScreenDrag
		if drag.index == _joy_touch:
			_update_joy(drag.position)
		elif drag.index == _look_touch:
			_look_delta += drag.position - _last_look_pos
			_last_look_pos = drag.position


func _over_extra(pos: Vector2) -> bool:
	for b in _extra_buttons:
		if _in_control(pos, b):
			return true
	return false


func _in_control(pos: Vector2, ctrl: Control) -> bool:
	if ctrl == null or not ctrl.visible:
		return false
	return ctrl.get_global_rect().has_point(pos)


func _update_joy(pos: Vector2) -> void:
	var center:= _joy_base.get_global_rect().get_center()
	var delta:= pos - center
	if delta.length() > _joy_radius:
		delta = delta.normalized() * _joy_radius
	move_vector = delta / _joy_radius
	_joy_knob.position = Vector2(42, 42) + delta


func _place(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob
