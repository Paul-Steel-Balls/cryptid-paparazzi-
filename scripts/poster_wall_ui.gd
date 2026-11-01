extends CanvasLayer
class_name PosterWallUI
## Pick which of your posters hangs in each of the RV's six spots.

signal changed
signal closed

var _rows: VBoxContainer


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim:= ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.04, 0.5)
	UIStyle.full_rect(dim)
	add_child(dim)
	var panel:= PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.box(Color(0.1, 0.07, 0.05, 0.95), UIStyle.GOLD, 3, 8, 22))
	UIStyle.center(panel, 620, 560)
	dim.add_child(panel)
	var v:= VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var t:= UIStyle.label("POSTER WALL", 44, UIStyle.GOLD, UIStyle.western())
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub:= UIStyle.label("Buy more posters at the bait & trap stand. New ones show up once you've photographed the cryptid.", 15, Color(1, 1, 1, 0.75), UIStyle.typewriter())
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_rows)
	var done:= UIStyle.poster_button("DONE", 20)
	done.pressed.connect(close)
	v.add_child(done)
	visible = false


func open() -> void:
	for c in _rows.get_children():
		c.queue_free()
	var owned: Array = []
	for id in Catalog.ids_of("poster"):
		if Catalog.owned(id):
			owned.append(id)
	for i in Catalog.POSTER_SLOTS:
		var h:= HBoxContainer.new()
		var l:= UIStyle.label(RVInterior.SLOT_NAMES[i], 18, Color(1, 1, 1), UIStyle.typewriter())
		l.custom_minimum_size = Vector2(230, 0)
		h.add_child(l)
		var ob:= OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob.add_theme_font_size_override("font_size", 18)
		ob.add_item("— empty —")
		ob.set_item_metadata(0, "")
		var sel:= 0
		for k in owned.size():
			ob.add_item(str(Catalog.item(owned[k])["name"]))
			ob.set_item_metadata(k + 1, owned[k])
			if GameState.poster_slots[i] == owned[k]:
				sel = k + 1
		ob.select(sel)
		var slot:= i
		ob.item_selected.connect(func(idx: int):
			var id: String = str(ob.get_item_metadata(idx))
			# One copy of each poster: hanging it here takes it down from anywhere else.
			if id != "":
				for j in GameState.poster_slots.size():
					if j != slot and GameState.poster_slots[j] == id:
						GameState.poster_slots[j] = ""
			GameState.poster_slots[slot] = id
			GameState.save_game()
			Audio.play("ui_click", -8.0)
			changed.emit()
			open())
		h.add_child(ob)
		_rows.add_child(h)
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_open() -> bool:
	return visible


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		close()
		get_viewport().set_input_as_handled()
