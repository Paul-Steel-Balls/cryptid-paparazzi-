extends CanvasLayer
class_name PauseMenu
## Esc: pause the game. Resume, Settings (graphics, sound, mouse, mic), Controls (rebind any
## key or mouse button), Cryptid Files, Multiplayer, quit.

signal resumed
signal settings_changed
signal files_pressed
signal multiplayer_pressed

var _panel: Control
var _quit_armed:= false
var _quit_btn: Button
var _mic_meter: ProgressBar
var _fs_cb: CheckButton
var _scroll: ScrollContainer
var _main_page: Control
var _settings_page: Control
var _controls_page: Control
var _ach_page: VBoxContainer
var _ach_list: VBoxContainer
var _bind_buttons: Dictionary = {}   # action -> Button
var _waiting_for:= ""                # action being rebound
## Set by main: shows the live mic level in the meter while paused.
var mic: MicListener


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim:= ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.06, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = dim
	var box:= PanelContainer.new()
	var sb:= StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.12, 0.95)
	sb.border_color = Color(0.95, 0.75, 0.3)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(20)
	box.add_theme_stylebox_override("panel", sb)
	UIStyle.center(box, 640, 680)
	dim.add_child(box)
	# Scrolls if the window is short; buttons and sliders stay a comfortable size.
	var scroll:= ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var pages:= VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	_scroll = scroll

	# --- main page: just the big buttons
	var v:= _page(pages, "PAUSED")
	_main_page = v
	v.add_child(_button("RESUME", _resume))
	v.add_child(_button("SETTINGS", func(): _show(_settings_page)))
	v.add_child(_button("CONTROLS", func(): _show(_controls_page)))
	v.add_child(_button("CRYPTID FILES", func(): files_pressed.emit()))
	v.add_child(_button("ACHIEVEMENTS", func(): _show(_ach_page)))
	v.add_child(_button("MULTIPLAYER", func(): multiplayer_pressed.emit()))
	v.add_child(HSeparator.new())
	_quit_btn = _button("QUIT TO DESKTOP", _quit)
	v.add_child(_quit_btn)

	# --- settings page: graphics, sound, mouse, mic
	var st:= _page(pages, "SETTINGS")
	_settings_page = st
	st.add_child(_section("GRAPHICS"))
	for pair in [["shadows", "Moon shadows"], ["ssao", "Ambient occlusion"], ["glow", "Glow (eyes, lights, flash)"], ["vol_fog", "Volumetric fog"]]:
		st.add_child(_slider(pair[1], pair[0], 0.0, 1.0, true))
	st.add_child(_check("fullscreen", "Fullscreen (F11)"))
	st.add_child(_section("SOUND"))
	st.add_child(_slider("Volume", "volume", 0.0, 1.0))
	st.add_child(_slider("Other players' voices", "voice_volume", 0.0, 1.0))
	st.add_child(_section("MOUSE & MOVEMENT"))
	st.add_child(_slider("Mouse sensitivity", "sensitivity", 0.3, 2.5))
	st.add_child(_check("toggle_sprint", "Toggle sprint (tap instead of holding)"))
	st.add_child(_section("MICROPHONE"))
	st.add_child(_check("mic_enabled", "Microphone (cryptids can hear you talk!)"))
	st.add_child(_check("voice_open", "Online voice: open mic (otherwise hold push-to-talk)"))
	st.add_child(_slider("Mic sensitivity", "mic_sens", 0.2, 3.0))
	_mic_meter = ProgressBar.new()
	_mic_meter.show_percentage = false
	_mic_meter.max_value = 1.0
	_mic_meter.custom_minimum_size = Vector2(0, 10)
	_mic_meter.tooltip_text = "Mic level"
	st.add_child(_mic_meter)
	st.add_child(HSeparator.new())
	st.add_child(_button("BACK", func(): _show(_main_page)))

	# --- controls page: every control, click one and press a key to change it
	var ct:= _page(pages, "CONTROLS")
	_controls_page = ct
	var hint:= Label.new()
	hint.text = "Click a control, then press the key or mouse button you want. Esc cancels."
	hint.add_theme_font_size_override("font_size", 17)
	hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ct.add_child(hint)
	for c in GameState.CONTROLS:
		ct.add_child(_control_row(str(c[0]), str(c[1])))
	ct.add_child(_section("FIXED"))
	for pair in [["Look around", "Mouse"], ["Pause / back", "Esc"], ["Fullscreen", "F11  or  Alt + Enter"]]:
		var h:= HBoxContainer.new()
		var l:= Label.new()
		l.text = pair[0]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", 19)
		h.add_child(l)
		var k:= Label.new()
		k.text = pair[1]
		k.add_theme_font_size_override("font_size", 19)
		k.add_theme_color_override("font_color", Color(0.95, 0.75, 0.3))
		h.add_child(k)
		ct.add_child(h)
	ct.add_child(HSeparator.new())
	ct.add_child(_button("RESET TO DEFAULTS", func():
		GameState.reset_bindings()
		_refresh_controls()))
	ct.add_child(_button("BACK", func(): _show(_main_page)))

	# --- achievements page: rebuilt every time it's opened
	_ach_page = _page(pages, "ACHIEVEMENTS")
	_ach_list = VBoxContainer.new()
	_ach_list.add_theme_constant_override("separation", 6)
	_ach_page.add_child(_ach_list)
	_ach_page.add_child(HSeparator.new())
	_ach_page.add_child(_button("BACK", func(): _show(_main_page)))
	_show(_main_page)
	visible = false


func _page(parent: Control, title_text: String) -> VBoxContainer:
	var v:= VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(v)
	var title:= Label.new()
	title.text = title_text
	title.add_theme_font_override("font", load("res://fonts/Rye-Regular.ttf"))
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.95, 0.75, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	return v


func _section(t: String) -> Label:
	var l:= Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.95, 0.75, 0.3, 0.85))
	return l


func _show(page: Control) -> void:
	_cancel_rebind()
	for p in [_main_page, _settings_page, _controls_page, _ach_page]:
		p.visible = p == page
	if page == _controls_page:
		_refresh_controls()
	if page == _ach_page:
		_refresh_achievements()
	if _scroll:
		_scroll.scroll_vertical = 0


func _refresh_achievements() -> void:
	for c in _ach_list.get_children():
		c.queue_free()
	var total:= Label.new()
	total.text = "%d of %d unlocked" % [Achievements.count(), Achievements.DEFS.size()]
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total.add_theme_font_size_override("font_size", 19)
	_ach_list.add_child(total)
	var group:= ""
	for d in Achievements.DEFS:
		if d[3] != group:
			group = d[3]
			_ach_list.add_child(_section(str(Achievements.GROUP_NAMES[group])))
		var have:= Achievements.has(str(d[0]))
		var row:= VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var name_l:= Label.new()
		var prog:= Achievements.progress(str(d[0]))
		name_l.text = ("★ " if have else "☆ ") + str(d[1]) + ("" if have or prog == "" else "   (%s)" % prog)
		name_l.add_theme_font_size_override("font_size", 20)
		name_l.add_theme_color_override("font_color", Color(1, 0.85, 0.35) if have else Color(0.7, 0.7, 0.75))
		row.add_child(name_l)
		var desc:= Label.new()
		desc.text = "    " + str(d[2])
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 16)
		desc.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9) if have else Color(0.55, 0.55, 0.6))
		row.add_child(desc)
		_ach_list.add_child(row)


func _check(key: String, text: String) -> CheckButton:
	var cb:= CheckButton.new()
	cb.text = text
	cb.button_pressed = bool(GameState.settings.get(key, false))
	cb.add_theme_font_size_override("font_size", 20)
	if key == "fullscreen":
		_fs_cb = cb
	cb.toggled.connect(func(on: bool):
		GameState.settings[key] = on
		GameState.save_settings()
		GameState.apply_system_settings()
		settings_changed.emit())
	return cb


func _control_row(action: String, label: String) -> Control:
	var h:= HBoxContainer.new()
	var l:= Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 19)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(l)
	var b:= Button.new()
	b.custom_minimum_size = Vector2(200, 38)
	b.add_theme_font_size_override("font_size", 18)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): _start_rebind(action))
	h.add_child(b)
	_bind_buttons[action] = b
	return h


func _refresh_controls() -> void:
	for act in _bind_buttons:
		var names: Array = []
		for bnd in GameState.bindings_of(act):
			names.append(GameState.binding_name(bnd))
		(_bind_buttons[act] as Button).text = " / ".join(names) if not names.is_empty() else "(none)"


func _start_rebind(action: String) -> void:
	_cancel_rebind()
	_waiting_for = action
	(_bind_buttons[action] as Button).text = "Press a key..."


func _cancel_rebind() -> void:
	if _waiting_for != "":
		_waiting_for = ""
		_refresh_controls()


func _input(event: InputEvent) -> void:
	if _waiting_for == "" or not visible:
		return
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_cancel_rebind()
		get_viewport().set_input_as_handled()
		return
	var bnd = GameState.binding_from_event(event)
	if bnd == null:
		return
	get_viewport().set_input_as_handled()
	var act:= _waiting_for
	_waiting_for = ""
	GameState.rebind(act, bnd)
	_refresh_controls()


func _button(text: String, cb: Callable) -> Button:
	var b:= Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	return b


func _slider(label: String, key: String, lo: float, hi: float, percent: bool = false) -> Control:
	var h:= HBoxContainer.new()
	var l:= Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(230, 0)
	l.add_theme_font_size_override("font_size", 20)
	h.add_child(l)
	var s:= HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = float(GameState.settings.get(key, GameState.SETTING_DEFAULTS.get(key, 1.0)))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	h.add_child(s)
	var val_l:= Label.new()
	val_l.custom_minimum_size = Vector2(52, 0)
	val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_l.add_theme_font_size_override("font_size", 18)
	h.add_child(val_l)
	var show:= func(val: float):
		if percent:
			val_l.text = "OFF" if val <= 0.001 else "%d%%" % roundi(val * 100.0)
		else:
			val_l.text = "%.2f" % val if hi > 1.0 else "%d%%" % roundi(val * 100.0)
	show.call(s.value)
	s.value_changed.connect(func(val: float):
		show.call(val)
		GameState.settings[key] = val
		GameState.save_settings()
		GameState.apply_system_settings()
		settings_changed.emit())
	return h


## Hide the panel (but stay paused) while the Cryptid Files are up.
func set_panel_visible(on: bool) -> void:
	_panel.visible = on


func open() -> void:
	if _fs_cb:
		_fs_cb.set_pressed_no_signal(bool(GameState.settings["fullscreen"]))
	visible = true
	_panel.visible = true
	_show(_main_page)
	_quit_armed = false
	_quit_btn.text = "QUIT TO DESKTOP"
	# Online the world can't stop for one player's menu.
	if Net.online():
		GameState.menu_open = true
	else:
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_open() -> bool:
	return visible


func _resume() -> void:
	visible = false
	get_tree().paused = false
	GameState.menu_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	resumed.emit()


func _quit() -> void:
	if not _quit_armed:
		_quit_armed = true
		_quit_btn.text = "CLICK AGAIN TO QUIT (progress is saved)"
		return
	GameState.save_game()
	Net.leave("")
	get_tree().quit()


func _process(_delta: float) -> void:
	if visible and _mic_meter:
		_mic_meter.value = mic.level if mic != null and mic.active else 0.0


func _unhandled_input(event: InputEvent) -> void:
	if visible and _panel.visible and event.is_action_pressed("ui_cancel"):
		if not _main_page.visible:
			_show(_main_page)   # Esc backs out of Settings / Controls first
		else:
			_resume()
		get_viewport().set_input_as_handled()
