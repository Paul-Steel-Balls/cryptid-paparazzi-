extends CanvasLayer
class_name PhotobookUI
## The photo book on the RV's dinette table. Top: this session's freshly developed prints
## (GameState.recent_prints); paste any of them into the book. Below: the book itself, six to a
## spread, with page turns and a way to take a photo back out.

signal closed

const PER_SPREAD:= 6
var _fresh: HBoxContainer
var _fresh_hint: Label
var _grid: GridContainer
var _page_label: Label
var _count_label: Label
var _prev: Button
var _next: Button
var _page:= 0


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim:= ColorRect.new()
	dim.color = Color(0.07, 0.05, 0.04, 0.95)
	UIStyle.full_rect(dim)
	add_child(dim)
	var v:= VBoxContainer.new()
	UIStyle.full_rect(v)
	v.offset_left = 36
	v.offset_right = -36
	v.offset_top = 20
	v.offset_bottom = -20
	v.add_theme_constant_override("separation", 10)
	dim.add_child(v)
	var head:= HBoxContainer.new()
	v.add_child(head)
	var title:= UIStyle.label("PHOTO BOOK", 40, UIStyle.GOLD, UIStyle.western())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_count_label = UIStyle.label("", 18, Color(0.9, 0.85, 0.75), UIStyle.typewriter())
	head.add_child(_count_label)
	var close_b:= UIStyle.dark_button("CLOSE", UIStyle.GOLD)
	close_b.pressed.connect(close)
	head.add_child(close_b)

	v.add_child(UIStyle.label("FRESH PRINTS — from the darkroom this session. Paste the keepers in.", 17, Color(0.95, 0.75, 0.45), UIStyle.typewriter()))
	var fs:= ScrollContainer.new()
	fs.custom_minimum_size = Vector2(0, 150)
	fs.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(fs)
	_fresh = HBoxContainer.new()
	_fresh.add_theme_constant_override("separation", 12)
	fs.add_child(_fresh)
	_fresh_hint = UIStyle.label("Nothing fresh. Develop some film in the darkroom first.", 16, Color(0.7, 0.65, 0.6), UIStyle.typewriter())
	v.add_child(_fresh_hint)

	var book:= PanelContainer.new()
	book.add_theme_stylebox_override("panel", UIStyle.box(Color(0.93, 0.89, 0.78), Color(0.35, 0.18, 0.08), 6, 8, 14))
	book.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(book)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 40)
	_grid.add_theme_constant_override("v_separation", 8)
	var center:= CenterContainer.new()
	book.add_child(center)
	center.add_child(_grid)
	var nav:= HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 30)
	v.add_child(nav)
	_prev = UIStyle.dark_button("< PREV", UIStyle.GOLD, 18)
	_prev.pressed.connect(func(): _turn(-1))
	nav.add_child(_prev)
	_page_label = UIStyle.label("", 18, Color(0.95, 0.9, 0.8), UIStyle.typewriter())
	nav.add_child(_page_label)
	_next = UIStyle.dark_button("NEXT >", UIStyle.GOLD, 18)
	_next.pressed.connect(func(): _turn(1))
	nav.add_child(_next)
	visible = false


func open() -> void:
	visible = true
	_page = maxi(0, (Photobook.count() - 1) / PER_SPREAD)   # open at the newest page
	_refresh()


func is_open() -> bool:
	return visible


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		get_viewport().set_input_as_handled()
		close()


func _turn(d: int) -> void:
	_page = clampi(_page + d, 0, _pages() - 1)
	_refresh()


func _pages() -> int:
	return maxi(1, ceili(float(Photobook.count()) / PER_SPREAD))


## Paste fresh print i into the book.
func paste(i: int) -> bool:
	if i < 0 or i >= GameState.recent_prints.size():
		return false
	var p: Dictionary = GameState.recent_prints[i]
	if Photobook.add(p.get("tex"), str(p.get("caption", ""))) == "":
		return false
	GameState.recent_prints.remove_at(i)
	_page = _pages() - 1
	if is_inside_tree():
		Audio.play("trap_set", -14.0, 0.1)
	_refresh()
	return true


func _refresh() -> void:
	if not is_inside_tree():
		return
	for c in _fresh.get_children():
		c.free()
	for i in GameState.recent_prints.size():
		var p: Dictionary = GameState.recent_prints[i]
		var card:= VBoxContainer.new()
		card.add_theme_constant_override("separation", 2)
		card.add_child(_pic(p.get("tex"), Vector2(140, 84)))
		var cap:= UIStyle.label(str(p.get("caption", "")), 11, Color(0.9, 0.85, 0.75), UIStyle.typewriter())
		cap.custom_minimum_size = Vector2(140, 0)
		cap.clip_text = true
		card.add_child(cap)
		var b:= UIStyle.poster_button("PASTE IN" if not Photobook.is_full() else "BOOK FULL", 14)
		b.disabled = Photobook.is_full()
		var idx:= i
		b.pressed.connect(func(): paste(idx))
		card.add_child(b)
		_fresh.add_child(card)
	_fresh_hint.visible = GameState.recent_prints.is_empty()
	for c in _grid.get_children():
		c.free()
	var all:= Photobook.entries()
	_page = clampi(_page, 0, _pages() - 1)
	for k in PER_SPREAD:
		var n:= _page * PER_SPREAD + k
		var slot:= VBoxContainer.new()
		slot.add_theme_constant_override("separation", 2)
		if n < all.size():
			var e: Dictionary = all[n]
			slot.add_child(_pic(Photobook.texture(str(e.get("id", ""))), Vector2(230, 134), true))
			var row:= HBoxContainer.new()
			var cap:= UIStyle.label(str(e.get("caption", "")), 13, UIStyle.INK, UIStyle.typewriter())
			cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cap.clip_text = true
			cap.custom_minimum_size = Vector2(180, 0)
			row.add_child(cap)
			var rm:= Button.new()
			rm.text = "TAKE OUT"
			rm.add_theme_font_size_override("font_size", 11)
			var pid:= str(e.get("id", ""))
			rm.pressed.connect(func():
				Photobook.remove(pid)
				_refresh())
			row.add_child(rm)
			slot.add_child(row)
		else:
			var blank:= ColorRect.new()
			blank.color = Color(0.85, 0.8, 0.68)
			blank.custom_minimum_size = Vector2(230, 134)
			slot.add_child(blank)
			slot.add_child(UIStyle.label(" ", 13, UIStyle.INK))
		_grid.add_child(slot)
	_page_label.text = "Pages %d-%d of %d" % [_page * 2 + 1, _page * 2 + 2, _pages() * 2]
	_prev.disabled = _page <= 0
	_next.disabled = _page >= _pages() - 1
	_count_label.text = "%d / %d photos   " % [Photobook.count(), Photobook.MAX_PHOTOS]


func _pic(tex: Texture2D, sz: Vector2, taped: bool = false) -> Control:
	var frame:= PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UIStyle.box(Color(0.98, 0.97, 0.94), Color(0.75, 0.7, 0.6) if taped else Color(0.2, 0.2, 0.2), 1, 2, 6))
	var r:= TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.custom_minimum_size = sz
	r.clip_contents = true
	frame.add_child(r)
	return frame
