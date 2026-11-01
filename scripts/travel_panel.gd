extends CanvasLayer
class_name TravelPanel
## Sitting in the driver's seat: a road map with the spots Toe Rogan has told you about.

signal chosen(map_id: String)
signal closed

var _list: VBoxContainer


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim:= ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.04, 0.55)
	UIStyle.full_rect(dim)
	add_child(dim)
	var panel:= PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.box(Color(0.9, 0.86, 0.72), Color(0.2, 0.35, 0.6), 4, 6, 24))
	UIStyle.center(panel, 560, 420)
	dim.add_child(panel)
	var v:= VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var t:= UIStyle.label("WHERE TO?", 46, Color(0.15, 0.25, 0.5), UIStyle.western())
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub:= UIStyle.label("Undeveloped film rides along with you.", 16, UIStyle.INK, UIStyle.typewriter())
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_list)
	var stay:= UIStyle.poster_button("STAY PARKED", 18)
	stay.pressed.connect(close)
	v.add_child(stay)
	visible = false


func open(current: String) -> void:
	for c in _list.get_children():
		c.queue_free()
	for id in Species.MAP_ORDER:
		var nm: String = str(Species.MAPS[id]["name"]).to_upper()
		var b: Button
		if id == current:
			b = UIStyle.poster_button("%s  (you're here)" % nm, 20)
			b.disabled = true
		elif GameState.is_unlocked(id):
			b = UIStyle.poster_button("DRIVE TO  %s" % nm, 20)
			b.pressed.connect(func(): chosen.emit(id))
		else:
			b = UIStyle.poster_button("? ? ?   (ask Toe Rogan)", 20)
			b.disabled = true
		_list.add_child(b)
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_open() -> bool:
	return visible


func close() -> void:
	if not visible:
		return
	visible = false
	Audio.play("ui_click", -6.0)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		close()
		get_viewport().set_input_as_handled()
