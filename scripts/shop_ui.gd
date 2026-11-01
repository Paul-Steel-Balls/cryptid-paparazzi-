extends CanvasLayer
class_name ShopUI
## The bait & trap stand's menu: a plywood price board, two items, and a shopkeeper with opinions.

## kind: a Catalog id ("bait", "trap", "poster_corn", "lava_lamp", ...)
signal buy_pressed(kind: String)
signal closed

const GREETINGS:= [
	"Ah. A fellow connoisseur of the unexplained. Welcome to my establishment.",
	"Bait's fresh. Ish. Don't ask what kind of meat.",
	"I was into cryptids before they were mainstream, just so you know.",
	"*tips fedora*  What can I get you, friend?",
]
const BOUGHT:= ["Excellent choice. A person of culture.", "Heh. You won't regret it. Probably.", "Pleasure doing business. Genuinely."]
const BROKE:= ["No money, no meat. Them's the rules.", "Come back when you've developed some film, friend."]
const FULL:= ["Five's the limit. Store policy. I made the store policy.", "Your pockets are full, my guy."]
const DECOR:= ["Ah, a collector. You have exquisite taste.", "That'll really tie the RV together.", "Limited edition. Well. Edition."]

var _board: PlankBoard
var _money: Label
var _quip: Label
var _counts:= {}
var _buttons:= {}
var _rng:= RandomNumberGenerator.new()
var _tab:= "gear"
var _tab_buttons:= {}
var _content: Control


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	var dim:= ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.03, 0.55)
	UIStyle.full_rect(dim)
	add_child(dim)
	_board = PlankBoard.new()
	UIStyle.center(_board, 1000, 640)
	dim.add_child(_board)
	var v:= VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 36
	v.offset_right = -36
	v.offset_top = 22
	v.offset_bottom = -22
	v.add_theme_constant_override("separation", 8)
	_board.add_child(v)
	var head:= HBoxContainer.new()
	v.add_child(head)
	var title:= UIStyle.label("BAIT & TRAPS", 48, Color(1, 0.93, 0.75), UIStyle.western())
	title.add_theme_color_override("font_shadow_color", Color(0.45, 0.05, 0.03))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_money = UIStyle.label("", 34, Color(0.2, 0.95, 0.35))
	_money.add_theme_constant_override("outline_size", 6)
	_money.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.06))
	head.add_child(_money)
	_quip = UIStyle.label("", 19, Color(1, 0.95, 0.85), UIStyle.typewriter())
	_quip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quip.custom_minimum_size = Vector2(0, 48)
	v.add_child(_quip)
	var tabs:= HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	v.add_child(tabs)
	for t in [["gear", "GEAR"], ["poster", "POSTERS"], ["trinket", "TRINKETS"]]:
		var b:= UIStyle.poster_button(t[1], 20)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(170, 44)
		var key: String = t[0]
		b.pressed.connect(func(): _show_tab(key))
		tabs.add_child(b)
		_tab_buttons[key] = b
	var holder:= MarginContainer.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(holder)
	_content = holder
	var leave:= UIStyle.poster_button("LEAVE", 20)
	leave.custom_minimum_size = Vector2(200, 46)
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave.pressed.connect(close)
	v.add_child(leave)
	visible = false
	_show_tab("gear")


func _show_tab(tab: String) -> void:
	_tab = tab
	for k in _tab_buttons:
		(_tab_buttons[k] as Button).button_pressed = k == tab
	for c in _content.get_children():
		c.free()
	_counts.clear()
	_buttons.clear()
	match tab:
		"gear":
			var scroll:= ScrollContainer.new()
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			_content.add_child(scroll)
			var grid:= GridContainer.new()
			grid.columns = 3
			grid.add_theme_constant_override("h_separation", 14)
			grid.add_theme_constant_override("v_separation", 14)
			scroll.add_child(grid)
			for id in GameState.GEAR:
				var it:= Catalog.item(id)
				grid.add_child(_item_card(id, str(it["name"]), str(it["blurb"]), int(it["price"])))
		"poster", "trinket":
			var scroll:= ScrollContainer.new()
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			_content.add_child(scroll)
			var grid:= GridContainer.new()
			grid.columns = 5 if tab == "poster" else 4
			grid.add_theme_constant_override("h_separation", 12)
			grid.add_theme_constant_override("v_separation", 12)
			scroll.add_child(grid)
			for id in Catalog.ids_of(tab):
				if Catalog.item(id).get("starter", false):
					continue
				grid.add_child(_poster_card(id) if tab == "poster" else _trinket_card(id))
	refresh()


func _item_card(kind: String, title: String, blurb: String, price: int) -> Control:
	var card:= PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIStyle.box(Color(0.94, 0.88, 0.72), Color(0.25, 0.14, 0.07), 3, 6, 10))
	card.custom_minimum_size = Vector2(285, 0)
	var v:= VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var top:= HBoxContainer.new()
	v.add_child(top)
	var icon:= HUD.ItemBox.new()
	icon.kind = kind
	icon.custom_minimum_size = Vector2(84, 84)
	icon.count = -1
	top.add_child(icon)
	var tv:= VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	var tl:= UIStyle.label(title, 20, UIStyle.INK, UIStyle.western())
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.custom_minimum_size = Vector2(170, 0)
	tv.add_child(tl)
	tv.add_child(UIStyle.label("$%d" % price, 32, Color(0.12, 0.5, 0.15), UIStyle.western()))
	var bl:= UIStyle.label(blurb, 14, UIStyle.INK, UIStyle.typewriter())
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bl.custom_minimum_size = Vector2(260, 64)
	v.add_child(bl)
	var cnt:= UIStyle.label("", 15, UIStyle.INK, UIStyle.typewriter())
	v.add_child(cnt)
	_counts[kind] = cnt
	var b:= UIStyle.poster_button("BUY ONE", 18)
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(func(): buy_pressed.emit(kind))
	v.add_child(b)
	_buttons[kind] = b
	return card


## Mini poster: the art, its price, and a buy button. Unproven cryptids are silhouettes.
func _poster_card(id: String) -> Control:
	var it:= Catalog.item(id)
	var stocked:= Catalog.in_stock(id)
	var card:= VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)
	var art:= PanelContainer.new()
	art.add_theme_stylebox_override("panel", UIStyle.box(it.get("bg", Color.GRAY) if stocked else Color(0.3, 0.27, 0.24), Color(0.96, 0.94, 0.86), 4, 2, 4))
	art.custom_minimum_size = Vector2(160, 205)
	card.add_child(art)
	var av:= VBoxContainer.new()
	art.add_child(av)
	var pic:= TextureRect.new()
	var path:= "res://ui/portraits/%s.png" % str(it.get("portrait", ""))
	pic.texture = load(path) if ResourceLoader.exists(path) else null
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(150, 140)
	if not stocked:
		pic.material = UIStyle.silhouette(Color(0.08, 0.06, 0.05))
	av.add_child(pic)
	var cap:= UIStyle.label(str(it.get("caption", "")) if stocked else "? ? ?", 13, it.get("ink", Color.WHITE) if stocked else Color(0.8, 0.75, 0.7), UIStyle.western())
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cap.custom_minimum_size = Vector2(150, 0)
	av.add_child(cap)
	card.add_child(_buy_button(id, stocked, "SNAP ONE FIRST"))
	return card


func _trinket_card(id: String) -> Control:
	var it:= Catalog.item(id)
	var card:= PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIStyle.box(Color(0.94, 0.88, 0.72), Color(0.25, 0.14, 0.07), 3, 6, 10))
	card.custom_minimum_size = Vector2(205, 230)
	var v:= VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var t:= UIStyle.label(str(it["name"]), 19, UIStyle.INK, UIStyle.western())
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(185, 0)
	v.add_child(t)
	var bl:= UIStyle.label(str(it["blurb"]), 14, UIStyle.INK, UIStyle.typewriter())
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bl.custom_minimum_size = Vector2(185, 0)
	bl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(bl)
	v.add_child(_buy_button(id, true, ""))
	return card


func _buy_button(id: String, stocked: bool, locked_text: String) -> Button:
	var price:= int(Catalog.item(id)["price"])
	var b:= UIStyle.poster_button("$%d" % price, 18)
	b.custom_minimum_size = Vector2(0, 40)
	if Catalog.owned(id):
		b.text = "OWNED"
		b.disabled = true
	elif not stocked:
		b.text = locked_text
		b.disabled = true
		b.add_theme_font_size_override("font_size", 13)
	else:
		b.disabled = GameState.money < price
		b.pressed.connect(func(): buy_pressed.emit(id))
	_buttons[id] = b
	return b


func open() -> void:
	_show_tab(_tab)
	say(GREETINGS[_rng.randi() % GREETINGS.size()])
	visible = true
	_board.pivot_offset = _board.size * 0.5
	_board.scale = Vector2(0.9, 0.9)
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(_board, "scale", Vector2.ONE, 0.22)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_open() -> bool:
	return visible


func close() -> void:
	if not visible:
		return
	visible = false
	Audio.play("ui_click", -6.0)
	closed.emit()


func refresh() -> void:
	_money.text = "$%d" % GameState.money
	for kind in GameState.GEAR:
		if not _counts.has(kind):
			continue
		var have: int = GameState.item_count(kind)
		var pips:= ""
		for i in GameState.MAX_ITEMS:
			pips += "■ " if i < have else "□ "
		(_counts[kind] as Label).text = "PACK: %s %d/%d" % [pips, have, GameState.MAX_ITEMS]
		var price:= GameState.item_price(kind)
		var b: Button = _buttons[kind]
		b.disabled = have >= GameState.MAX_ITEMS or GameState.money < price
		b.text = "PACK FULL" if have >= GameState.MAX_ITEMS else ("CAN'T AFFORD" if GameState.money < price else "BUY ONE")
	for id in _buttons:
		if id in GameState.GEAR:
			continue
		var b2: Button = _buttons[id]
		if Catalog.owned(id):
			b2.text = "OWNED"
			b2.disabled = true
		elif Catalog.in_stock(id):
			b2.disabled = GameState.money < int(Catalog.item(id)["price"])


func say(text: String) -> void:
	_quip.text = "\"%s\"" % text


## Main calls this after trying a purchase so he can react.
func react(result: String) -> void:
	match result:
		"bought":
			say(BOUGHT[_rng.randi() % BOUGHT.size()])
		"broke":
			say(BROKE[_rng.randi() % BROKE.size()])
		"full":
			say(FULL[_rng.randi() % FULL.size()])
		"decor":
			say(DECOR[_rng.randi() % DECOR.size()])
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		close()
		get_viewport().set_input_as_handled()


## Weathered plywood with a painted red border.
class PlankBoard extends Control:
	func _draw() -> void:
		var r:= RandomNumberGenerator.new()
		r.seed = 3
		var w:= size.x
		var h:= size.y
		draw_rect(Rect2(10, 12, w, h), Color(0, 0, 0, 0.45))
		var y:= 0.0
		while y < h:
			var ph:= minf(70.0, h - y)
			var base:= Color(0.46, 0.31, 0.18).lerp(Color(0.56, 0.4, 0.24), r.randf())
			draw_rect(Rect2(0, y, w, ph), base)
			for k in 7:
				var gy:= y + r.randf_range(4, ph - 4)
				draw_line(Vector2(0, gy), Vector2(w, gy + r.randf_range(-3, 3)), Color(0.3, 0.19, 0.1, 0.25), 1.5)
			draw_line(Vector2(0, y), Vector2(w, y), Color(0.18, 0.1, 0.05, 0.9), 2.5)
			y += ph
		draw_rect(Rect2(8, 8, w - 16, h - 16), Color(0.7, 0.12, 0.08), false, 6.0)
		for c in [Vector2(20, 20), Vector2(w - 20, 20), Vector2(20, h - 20), Vector2(w - 20, h - 20)]:
			draw_circle(c, 5, Color(0.6, 0.6, 0.62))
