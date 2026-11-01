extends CanvasLayer
class_name ToePoster
## Talking to Toe Rogan: an old WANTED poster of this map's cryptids.
## Snapped ones show their mugshot with a red stamp; the rest are black silhouettes.
## From here: reload film (Toe swaps your camera), show him your photos (unlocks the next map), or walk away.

signal reload_pressed
signal show_pressed
signal closed

var _dim: ColorRect
var _poster: PosterPaper
var _title_sub: Label
var _cards: HBoxContainer
var _progress: Label
var _quote: Label
var _reload_btn: Button
var _show_btn: Button
var _rng:= RandomNumberGenerator.new()


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.01, 0.03, 0.6)
	UIStyle.full_rect(_dim)
	add_child(_dim)

	_poster = PosterPaper.new()
	UIStyle.center(_poster, 1060, 650)
	_dim.add_child(_poster)

	var v:= VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 50
	v.offset_right = -50
	v.offset_top = 22
	v.offset_bottom = -26
	v.add_theme_constant_override("separation", 4)
	_poster.add_child(v)

	var wanted:= UIStyle.label("WANTED", 78, UIStyle.BLOOD, UIStyle.western())
	wanted.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(wanted)
	_title_sub = UIStyle.label("", 20, UIStyle.INK, UIStyle.typewriter())
	_title_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title_sub)
	v.add_child(_rule())

	_cards = HBoxContainer.new()
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards.add_theme_constant_override("separation", 14)
	_cards.custom_minimum_size = Vector2(0, 250)
	v.add_child(_cards)

	_progress = UIStyle.label("", 19, UIStyle.INK, UIStyle.typewriter())
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_progress)
	v.add_child(_rule())

	var bottom:= HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 24)
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(bottom)
	var qv:= VBoxContainer.new()
	qv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(qv)
	qv.add_child(UIStyle.label("TOE ROGAN SAYS:", 18, UIStyle.BLOOD, UIStyle.western()))
	_quote = UIStyle.label("", 19, UIStyle.INK, UIStyle.typewriter())
	_quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quote.custom_minimum_size = Vector2(560, 0)
	qv.add_child(_quote)
	var bv:= VBoxContainer.new()
	bv.custom_minimum_size = Vector2(300, 0)
	bv.add_theme_constant_override("separation", 8)
	bottom.add_child(bv)
	_reload_btn = UIStyle.poster_button("RELOAD FILM")
	_reload_btn.pressed.connect(func(): reload_pressed.emit())
	bv.add_child(_reload_btn)
	_show_btn = UIStyle.poster_button("SHOW HIM THE PHOTOS")
	_show_btn.pressed.connect(func(): show_pressed.emit())
	bv.add_child(_show_btn)
	var walk:= UIStyle.poster_button("WALK AWAY", 18)
	walk.pressed.connect(close)
	bv.add_child(walk)
	visible = false


func _rule() -> Control:
	var r:= ColorRect.new()
	r.color = Color(UIStyle.INK, 0.6)
	r.custom_minimum_size = Vector2(0, 3)
	return r


func open(map_id: String, quote: String, can_show: bool) -> void:
	_rng.seed = hash(map_id)
	var m: Dictionary = Species.MAPS[map_id]
	_title_sub.text = "FOR PHOTOGRAPHS  ·  LAST SEEN: %s  ·  REWARD PAID ON DEVELOPMENT" % str(m["name"]).to_upper()
	for c in _cards.get_children():
		c.queue_free()
	var seen: Array = []
	for tier in Species.TIERS:
		for id in m[tier]:
			if id in seen:
				continue
			seen.append(id)
			_cards.add_child(_card(id, tier))
	var need:= Species.required_for_unlock(map_id)
	var have:= 0
	for id in need:
		if GameState.has_photo(id):
			have += 1
	_progress.text = "Toe needs a developed photo of every COMMON and UNCOMMON:   %d / %d" % [have, need.size()]
	_quote.text = "\"%s\"" % quote
	_show_btn.visible = can_show
	_reload_btn.disabled = GameState.film >= GameState.FILM_MAX
	if _reload_btn.disabled:
		_reload_btn.text = "FILM'S STILL FULL"
	elif GameState.unsold_photos.is_empty():
		_reload_btn.text = "RELOAD FILM  (%d/%d)" % [GameState.film, GameState.FILM_MAX]
	else:
		# The film is IN the camera he's about to throw away.
		_reload_btn.text = "RELOAD  (LOSE $%d UNDEVELOPED)" % GameState.undeveloped_value()
	_reload_btn.add_theme_font_size_override("font_size", 22 if GameState.unsold_photos.is_empty() or _reload_btn.disabled else 16)
	visible = true
	_poster.pivot_offset = _poster.size * 0.5
	_poster.scale = Vector2(0.85, 0.85)
	_poster.rotation = deg_to_rad(-3)
	var tw:= create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_poster, "scale", Vector2.ONE, 0.25)
	tw.parallel().tween_property(_poster, "rotation", deg_to_rad(0.6), 0.25)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_open() -> bool:
	return visible


func close() -> void:
	if not visible:
		return
	visible = false
	Audio.play("ui_click", -6.0)
	closed.emit()


func _card(id: String, tier: String) -> Control:
	var snapped:= GameState.has_photo(id)
	var card:= PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIStyle.box(Color(UIStyle.PAPER_DARK, 0.55), Color(UIStyle.INK, 0.8), 2, 2, 6))
	card.custom_minimum_size = Vector2(148, 0)
	card.rotation = deg_to_rad(_rng.randf_range(-2.5, 2.5))
	var v:= VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	card.add_child(v)
	var holder:= Control.new()
	holder.custom_minimum_size = Vector2(136, 160)
	holder.clip_contents = true
	v.add_child(holder)
	var pic:= TextureRect.new()
	pic.texture = load("res://ui/portraits/%s.png" % id) if ResourceLoader.exists("res://ui/portraits/%s.png" % id) else null
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	UIStyle.full_rect(pic)
	# Sepia for snapped, solid ink silhouette for the unknowns.
	if snapped:
		pic.modulate = Color(1.0, 0.9, 0.75)
	else:
		pic.material = UIStyle.silhouette()
	holder.add_child(pic)
	var name_text:= Species.display_name(id).to_upper() if snapped or tier in ["common", "uncommon"] else "? ? ?"
	var nl:= UIStyle.label(name_text, 16, UIStyle.INK, UIStyle.western())
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nl)
	var tl:= UIStyle.label(tier.to_upper(), 14, UIStyle.BLOOD if tier in ["rare", "legendary"] else UIStyle.INK, UIStyle.typewriter())
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tl)
	var pay:= UIStyle.label("x%.1f BOUNTY" % float(Species.PAY[tier]), 13, Color(UIStyle.INK, 0.75), UIStyle.typewriter())
	pay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(pay)
	if snapped:
		var stamp:= UIStyle.label("SNAPPED!", 19, Color(0.75, 0.08, 0.05, 0.85), UIStyle.western())
		stamp.add_theme_stylebox_override("normal", UIStyle.box(Color(0, 0, 0, 0), Color(0.75, 0.08, 0.05, 0.85), 3, 4, 4))
		stamp.position = Vector2(10, 74)
		stamp.rotation = deg_to_rad(-18)
		holder.add_child(stamp)
	return card


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		close()
		get_viewport().set_input_as_handled()


## Aged paper with ragged edges, stains and nails in the corners.
class PosterPaper extends Control:
	func _draw() -> void:
		var r:= RandomNumberGenerator.new()
		r.seed = 7
		var w:= size.x
		var h:= size.y
		var pts:= PackedVector2Array()
		var steps:= 40
		for i in steps:
			pts.append(Vector2(w * i / float(steps), r.randf_range(0, 7)))
		for i in steps:
			pts.append(Vector2(w - r.randf_range(0, 7), h * i / float(steps)))
		for i in steps:
			pts.append(Vector2(w - w * i / float(steps), h - r.randf_range(0, 7)))
		for i in steps:
			pts.append(Vector2(r.randf_range(0, 7), h - h * i / float(steps)))
		# drop shadow
		var sh:= PackedVector2Array()
		for p in pts:
			sh.append(p + Vector2(10, 12))
		draw_colored_polygon(sh, Color(0, 0, 0, 0.45))
		draw_colored_polygon(pts, UIStyle.PAPER)
		# age: darker edges and coffee stains
		for i in 14:
			var a:= 0.05 + 0.03 * i
			draw_rect(Rect2(i * 3, i * 3, w - i * 6, h - i * 6), Color(0.45, 0.3, 0.12, 0.05 - a * 0.05), false, 3.0)
		for i in 6:
			var c:= Vector2(r.randf_range(40, w - 40), r.randf_range(40, h - 40))
			var rad:= r.randf_range(18, 60)
			draw_circle(c, rad, Color(0.55, 0.38, 0.15, 0.06))
			draw_arc(c, rad, 0, TAU, 40, Color(0.5, 0.32, 0.12, 0.12), 2.0)
		draw_rect(Rect2(18, 14, w - 36, h - 28), Color(UIStyle.INK, 0.7), false, 3.0)
		draw_rect(Rect2(26, 22, w - 52, h - 44), Color(UIStyle.INK, 0.5), false, 1.0)
		for c in [Vector2(14, 12), Vector2(w - 14, 12), Vector2(14, h - 12), Vector2(w - 14, h - 12)]:
			draw_circle(c + Vector2(1, 2), 7, Color(0, 0, 0, 0.4))
			draw_circle(c, 7, Color(0.45, 0.45, 0.48))
			draw_circle(c + Vector2(-2, -2), 3, Color(0.8, 0.8, 0.85))
