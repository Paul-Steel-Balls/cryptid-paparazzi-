extends CanvasLayer
class_name MultiplayerPanel
## Pause → MULTIPLAYER. Host a game on this PC, or join someone else's by address.

signal closed

var _name: LineEdit
var _addr: LineEdit
var _port: SpinBox
var _status: Label
var _info: Label
var _host_btn: Button
var _join_btn: Button
var _leave_btn: Button


func _ready() -> void:
	layer = 55
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim:= ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.06, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box:= PanelContainer.new()
	box.add_theme_stylebox_override("panel", UIStyle.box(Color(0.08, 0.07, 0.12, 0.97), Color(0.95, 0.75, 0.3), 3, 10, 26))
	UIStyle.center(box, 700, 640)
	dim.add_child(box)
	# Scrolls rather than hanging off the bottom of a short window.
	var scroll:= ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var v:= VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var title:= UIStyle.label("MULTIPLAYER", 40, Color(0.95, 0.75, 0.3), UIStyle.western())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	for pair in [["Up to 4 photographers. One PC hosts the night; the others join it.", 17, Color(0.85, 0.85, 0.9)],
			["Voice: turn on Microphone in Settings, then hold T to talk (nearby players hear you, and so do cryptids).", 15, Color(0.6, 0.95, 0.65)]]:
		var l:= UIStyle.label(pair[0], pair[1], pair[2])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	_name = _row(v, "Your name", Net.my_name)
	_name.max_length = 16
	_name.text_submitted.connect(func(_t: String): Net.set_my_name(_name.text))
	_name.focus_exited.connect(func(): Net.set_my_name(_name.text))
	v.add_child(HSeparator.new())
	var ph:= HBoxContainer.new()
	ph.add_child(_lbl("Port"))
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = int(GameState.settings.get("net_port", Net.DEFAULT_PORT))
	_port.custom_minimum_size = Vector2(150, 0)
	ph.add_child(_port)
	v.add_child(ph)
	_host_btn = UIStyle.dark_button("HOST A GAME ON THIS PC")
	_host_btn.pressed.connect(_on_host)
	v.add_child(_host_btn)
	_addr = _row(v, "Host's address", str(GameState.settings.get("last_join", "")))
	_addr.placeholder_text = "e.g. 192.168.1.20 or 100.64.0.5"
	_join_btn = UIStyle.dark_button("JOIN")
	_join_btn.pressed.connect(_on_join)
	v.add_child(_join_btn)
	_leave_btn = UIStyle.dark_button("LEAVE / STOP HOSTING", Color(0.95, 0.4, 0.3))
	_leave_btn.pressed.connect(func(): Net.leave("You left the game."))
	v.add_child(_leave_btn)
	_status = UIStyle.label("", 19, Color(0.6, 0.95, 1.0))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	_info = UIStyle.label("", 15, Color(0.8, 0.8, 0.85))
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_info)
	var back:= UIStyle.dark_button("BACK")
	back.pressed.connect(close)
	v.add_child(back)
	Net.players_changed.connect(_refresh)
	Net.connection_failed.connect(func(r: String): _status.text = r)
	visible = false


func _lbl(t: String) -> Label:
	var l:= UIStyle.label(t, 19, Color(1, 1, 1))
	l.custom_minimum_size = Vector2(170, 0)
	return l


func _row(v: VBoxContainer, label: String, value: String) -> LineEdit:
	var h:= HBoxContainer.new()
	h.add_child(_lbl(label))
	var e:= LineEdit.new()
	e.text = value
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", 19)
	h.add_child(e)
	v.add_child(h)
	return e


func open() -> void:
	visible = true
	_refresh()


func close() -> void:
	Net.set_my_name(_name.text)
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func _on_host() -> void:
	Net.set_my_name(_name.text)
	GameState.settings["net_port"] = int(_port.value)
	GameState.save_settings()
	if Net.host_game(int(_port.value)):
		_status.text = "Hosting! Friends can join now."
	_refresh()


func _on_join() -> void:
	Net.set_my_name(_name.text)
	var a:= _addr.text.strip_edges()
	if a == "":
		_status.text = "Type the host's address first."
		return
	GameState.settings["last_join"] = a
	GameState.settings["net_port"] = int(_port.value)
	GameState.save_settings()
	if Net.join_game(a, int(_port.value)):
		_status.text = "Connecting to %s..." % a


func _process(_d: float) -> void:
	if visible and Net.connecting():
		_status.text = "Connecting..."


func _refresh() -> void:
	var on:= Net.online()
	_host_btn.disabled = on
	_join_btn.disabled = on
	_leave_btn.disabled = not on and not Net.connecting()
	if on:
		var names: Array = []
		for id in Net.players:
			names.append(Net.name_of(id) + (" (host)" if id == 1 else ""))
		_status.text = ("Hosting. " if Net.is_host() else "Connected. ") + "In the game: " + ", ".join(names)
	if Net.is_host():
		var addrs:= Net.local_addresses()
		_info.text = "Same house / LAN: friends join  %s  (port %d).\nOver the internet: forward UDP port %d on your router to this PC and give them your public IP, or use a VPN like Tailscale and give them your Tailscale IP. Allow the game through Windows Firewall when it asks." % [
			"  or  ".join(addrs) if not addrs.is_empty() else "this PC's IP", int(_port.value), int(_port.value)]
	elif not on:
		_info.text = "Hosting uses this PC as the server: the host's world (cryptids, the night, the map) is the one everyone plays in. Only the host can sleep or drive."
	else:
		_info.text = ""
