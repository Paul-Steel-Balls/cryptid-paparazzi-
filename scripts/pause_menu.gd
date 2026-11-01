extends CanvasLayer
class_name PauseMenu
## Esc: pause the game. Resume, quality sliders, volume, mouse and mic sensitivity, quit.

signal resumed
signal settings_changed
signal files_pressed
signal multiplayer_pressed

var _panel: Control
var _quit_armed:= false
var _quit_btn: Button
var _mic_meter: ProgressBar
var _fs_cb: CheckButton
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
	var v:= VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var title:= Label.new()
	title.text = "PAUSED"
	title.add_theme_font_override("font", load("res://fonts/Rye-Regular.ttf"))
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.95, 0.75, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	v.add_child(_button("RESUME", _resume))
	v.add_child(_button("CRYPTID FILES", func(): files_pressed.emit()))
	v.add_child(_button("MULTIPLAYER", func(): multiplayer_pressed.emit()))
	v.add_child(HSeparator.new())
	for pair in [["shadows", "Moon shadows"], ["ssao", "Ambient occlusion"], ["glow", "Glow (eyes, lights, flash)"], ["vol_fog", "Volumetric fog"]]:
		v.add_child(_slider(pair[1], pair[0], 0.0, 1.0, true))
	for pair in [["fullscreen", "Fullscreen"], ["toggle_sprint", "Toggle sprint (tap Shift instead of holding)"],
			["mic_enabled", "Microphone (cryptids can hear you talk!)"]]:
		var cb:= CheckButton.new()
		cb.text = pair[1]
		cb.button_pressed = bool(GameState.settings.get(pair[0], false))
		cb.add_theme_font_size_override("font_size", 20)
		var key: String = pair[0]
		if key == "fullscreen":
			cb.text = "Fullscreen (F11)"
			_fs_cb = cb
		cb.toggled.connect(func(on: bool):
			GameState.settings[key] = on
			GameState.save_settings()
			GameState.apply_system_settings()
			settings_changed.emit())
		v.add_child(cb)
	v.add_child(HSeparator.new())
	v.add_child(_slider("Volume", "volume", 0.0, 1.0))
	v.add_child(_slider("Mouse sensitivity", "sensitivity", 0.3, 2.5))
	v.add_child(_slider("Mic sensitivity", "mic_sens", 0.2, 3.0))
	_mic_meter = ProgressBar.new()
	_mic_meter.show_percentage = false
	_mic_meter.max_value = 1.0
	_mic_meter.custom_minimum_size = Vector2(0, 10)
	_mic_meter.tooltip_text = "Mic level"
	v.add_child(_mic_meter)
	v.add_child(HSeparator.new())
	_quit_btn = _button("QUIT TO DESKTOP", _quit)
	v.add_child(_quit_btn)
	visible = false


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
		_resume()
		get_viewport().set_input_as_handled()
