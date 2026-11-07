extends CanvasLayer
class_name HUD
## In-game overlay. Top-left: night, night timer, money (green), undeveloped film value (yellow).
## Top-centre: compass strip with the RV marker. Bottom-right: bait/trap selector.
## Raising the camera shows a viewfinder with film count and flash charge.

signal try_again_pressed
signal win_continue_pressed

const GREEN:= Color(0.2, 0.95, 0.35)
const YELLOW:= Color(1.0, 0.82, 0.18)
const NIGHT_GOLD:= Color(0.93, 0.66, 0.2)
const INK:= Color(0, 0, 0, 0.75)

var is_touch:= false

var _root: Control
var _night_label: Label
var _timer_label: Label
var _money_label: Label
var _undev_label: Label
var _compass: Compass
var _viewfinder: Viewfinder
var _item_box: ItemBox
var _crosshair: Control
var _popup_label: Label
var _message_label: Label
var _alert_label: Label
var _hint_label: Label
var _grab_label: Label
var _struggle: Control
var _struggle_bar: ColorRect
var _struggle_label: Label
var _mic_label: Label
var _net_label: Label
var _prompt: PanelContainer
var _prompt_label: Label
var _flash_rect: ColorRect
var _vignette: TextureRect
var _help_label: Label
var _win_panel: Control
var _lose_panel: Control
var _win_title: Label
var _win_sub: Label
var _lose_sub: Label
var _popup_timer:= 0.0
var _message_timer:= 0.0
var _help_timer:= 14.0
var _danger:= false
var _stun_fade:= 0.0
var _effects_label: Label
var _haze: ColorRect
var _haze_on:= false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_vignette = TextureRect.new()
	var g:= GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var grad:= Gradient.new()
	grad.set_color(0, Color(0.6, 0, 0, 0))
	grad.set_color(1, Color(0.7, 0, 0, 0.85))
	grad.add_point(0.55, Color(0.6, 0, 0, 0.0))
	g.gradient = grad
	_vignette.texture = g
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	_root.add_child(_vignette)

	_viewfinder = Viewfinder.new()
	_viewfinder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewfinder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewfinder.visible = false
	_root.add_child(_viewfinder)

	# --- top-left status block
	var tl:= VBoxContainer.new()
	tl.position = Vector2(24, 16)
	tl.add_theme_constant_override("separation", -4)
	_root.add_child(tl)
	var night_row:= HBoxContainer.new()
	night_row.add_theme_constant_override("separation", 12)
	tl.add_child(night_row)
	_night_label = _label(26, NIGHT_GOLD)
	_night_label.add_theme_font_override("font", load("res://fonts/Rye-Regular.ttf"))
	_outline(_night_label, 6)
	night_row.add_child(_night_label)
	_timer_label = _label(22, Color(0.92, 0.9, 1.0))
	_outline(_timer_label, 5)
	night_row.add_child(_timer_label)
	_money_label = _label(26, GREEN)
	_outline(_money_label, 6)
	tl.add_child(_money_label)
	_undev_label = _label(22, YELLOW)
	_outline(_undev_label, 5)
	tl.add_child(_undev_label)
	_effects_label = _label(18, Color(0.8, 1.0, 0.6))
	_outline(_effects_label, 5)
	tl.add_child(_effects_label)

	_compass = Compass.new()
	_compass.anchor_left = 0.5
	_compass.anchor_right = 0.5
	_compass.offset_left = -300
	_compass.offset_right = 300
	_compass.offset_top = 14
	_compass.offset_bottom = 74
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_compass)

	_item_box = ItemBox.new()
	_place(_item_box, 1.0, 1.0, 1.0, 1.0, -150.0, -150.0, -24.0, -24.0)
	_item_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_box.modulate.a = 0.0
	_root.add_child(_item_box)

	_crosshair = Crosshair.new()
	_place(_crosshair, 0.5, 0.5, 0.5, 0.5, -10, -10, 10, 10)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_crosshair)

	_popup_label = _centered(30, Color(1, 0.92, 0.3), 0.5, -150)
	_message_label = _centered(24, Color(1, 1, 1), 1.0, -150)
	_alert_label = _centered(28, Color(1, 0.25, 0.2), 0.0, 92)
	_hint_label = _centered(22, Color(0.45, 1.0, 0.45), 0.0, 130)
	_grab_label = _centered(40, Color(1, 0.12, 0.1), 0.0, 168)
	_grab_label.text = "THEY'VE GOT YOU!"

	# Tractor beam: mash A / D to wriggle free.
	_struggle = Control.new()
	_place(_struggle, 0.5, 0.5, 0.5, 0.5, -260, 90, 260, 170)
	_struggle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_struggle.visible = false
	_root.add_child(_struggle)
	var sbg:= ColorRect.new()
	sbg.color = Color(0.03, 0.08, 0.05, 0.85)
	_place(sbg, 0, 0, 1, 0, 0, 44, 0, 74)
	_struggle.add_child(sbg)
	_struggle_bar = ColorRect.new()
	_struggle_bar.color = Color(0.45, 1.0, 0.55)
	_place(_struggle_bar, 0, 0, 0, 0, 4, 48, 4, 70)
	_struggle.add_child(_struggle_bar)
	_struggle_label = _label(30, Color(0.6, 1.0, 0.65))
	_outline(_struggle_label, 6)
	_struggle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_struggle_label, 0, 0, 1, 0, 0, 0, 0, 40)
	_struggle_label.text = "MASH  A + D  TO BREAK FREE!"
	_struggle.add_child(_struggle_label)

	# Microphone: a little "MIC" tag that lights up as you talk (cryptids hear it).
	_mic_label = _label(18, Color(0.6, 0.6, 0.6))
	_outline(_mic_label, 4)
	_place(_mic_label, 1.0, 0.0, 1.0, 0.0, -230, 18, -24, 44)
	_mic_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mic_label.visible = false
	_root.add_child(_mic_label)

	# Online: who's in the game.
	_net_label = _label(17, Color(0.6, 0.9, 1.0))
	_outline(_net_label, 4)
	_place(_net_label, 1.0, 0.0, 1.0, 0.0, -620, 44, -24, 70)
	_net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_net_label.visible = false
	_root.add_child(_net_label)

	_prompt = PanelContainer.new()
	var ps:= StyleBoxFlat.new()
	ps.bg_color = Color(0.05, 0.04, 0.09, 0.78)
	ps.border_color = Color(1, 0.85, 0.4, 0.9)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(18)
	ps.content_margin_left = 18
	ps.content_margin_right = 18
	ps.content_margin_top = 6
	ps.content_margin_bottom = 6
	_prompt.add_theme_stylebox_override("panel", ps)
	_place(_prompt, 0.5, 1.0, 0.5, 1.0, -200, -220, 200, -180)
	_prompt.visible = false
	_prompt_label = _label(22, Color(1, 1, 1))
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_child(_prompt_label)
	_root.add_child(_prompt)

	_help_label = _label(19, Color(1, 1, 1, 0.92))
	_place(_help_label, 0.0, 1.0, 0.0, 1.0, 24.0, -190.0, 900.0, -20.0)
	_root.add_child(_help_label)

	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1, 1, 1)
	_flash_rect.modulate.a = 0.0
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_flash_rect)

	_build_end_panel(true)
	_build_end_panel(false)
	update_stats()


# ------------------------------------------------------------------ helpers

func _label(size: int, color: Color) -> Label:
	var l:= Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", INK)
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Solid dark outline so text reads against bright sky and dark woods alike.
func _outline(l: Label, px: int) -> void:
	l.add_theme_constant_override("outline_size", px)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.06, 1.0))


func _centered(size: int, color: Color, anchor_y: float, y: float) -> Label:
	var l:= _label(size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(l, 0.5, anchor_y, 0.5, anchor_y, -450, y, 450, y + 44)
	l.visible = false
	_root.add_child(l)
	return l


func _place(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if _popup_timer > 0.0:
		_popup_timer -= delta
		if _popup_timer <= 0.0:
			_popup_label.visible = false
	if _message_timer > 0.0:
		_message_timer -= delta
		_message_label.modulate.a = clampf(_message_timer / 0.5, 0.0, 1.0)
		if _message_timer <= 0.0:
			_message_label.visible = false
	if _help_timer > 0.0:
		_help_timer -= delta
		_help_label.modulate.a = clampf(_help_timer / 2.0, 0.0, 1.0)
		if _help_timer <= 0.0:
			_help_label.visible = false
	if _item_box.modulate.a > 0.0:
		_item_box.hold -= delta
		if _item_box.hold <= 0.0:
			_item_box.modulate.a = maxf(0.0, _item_box.modulate.a - delta * 2.5)
	if _stun_fade > 0.0:
		_stun_fade -= delta
		_flash_rect.modulate.a = maxf(_flash_rect.modulate.a, clampf(_stun_fade / 1.2, 0.0, 0.95))
	elif _flash_rect.modulate.a > 0.0 and _flash_rect.color == Color(1, 1, 1):
		# camera-flash white decays on its own; black fades are driven by fade_to()
		_flash_rect.modulate.a = maxf(0.0, _flash_rect.modulate.a - delta * 1.5)
	if _danger:
		_vignette.modulate.a = 0.55 + 0.25 * sin(Time.get_ticks_msec() / 150.0)
	elif _vignette.modulate.a > 0.0:
		_vignette.modulate.a = maxf(0.0, _vignette.modulate.a - delta * 1.5)


func update_stats() -> void:
	_night_label.text = "NIGHT %d" % GameState.night
	_money_label.text = "$%d" % GameState.money
	_undev_label.text = "$%d" % GameState.undeveloped_value()
	_viewfinder.film = GameState.film
	_viewfinder.film_max = GameState.FILM_MAX
	_viewfinder.queue_redraw()


## Active effects ("SLOW-MO 12s", "BUZZED 20s") under the cash.
func set_effects(lines: Array) -> void:
	_effects_label.text = "\n".join(lines)


## Hazy green-purple swirl while the joint lasts.
func set_haze(on: bool) -> void:
	_haze_on = on
	if _haze == null:
		_haze = ColorRect.new()
		_haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_haze.set_anchors_preset(Control.PRESET_FULL_RECT)
		var sh:= Shader.new()
		sh.code = """shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	vec2 uv = UV - 0.5;
	float r = length(uv);
	float swirl = sin(TIME * 0.7 + r * 9.0) * 0.5 + 0.5;
	vec3 tint = mix(vec3(0.35, 0.9, 0.45), vec3(0.75, 0.4, 0.95), swirl);
	float edge = smoothstep(0.25, 0.75, r);
	COLOR = vec4(tint, strength * (0.08 + 0.32 * edge));
}"""
		var mat:= ShaderMaterial.new()
		mat.shader = sh
		_haze.material = mat
		_root.add_child(_haze)
		_root.move_child(_haze, 1)
	var tw:= create_tween()
	tw.tween_method(func(v: float): (_haze.material as ShaderMaterial).set_shader_parameter("strength", v),
		1.0 if not on else 0.0, 1.0 if on else 0.0, 1.2)


func set_night_time(seconds: float) -> void:
	var s:= int(seconds)
	_timer_label.text = "%d:%02d" % [s / 60, s % 60]


## The moon's path across the sky is the clock now; nothing on screen. (Kept for callers.)
func set_clock(_day: bool, _left: float) -> void:
	_timer_label.text = ""


## Compass: player's heading + markers [{"pos": Vector3, "label": String, "color": Color}].
func set_compass(player_pos: Vector3, yaw: float, markers: Array) -> void:
	_compass.yaw = yaw
	_compass.player_pos = player_pos
	_compass.markers = markers
	_compass.queue_redraw()


func set_flash_charge(frac: float) -> void:
	_viewfinder.charge = frac
	_crosshair.charge = frac
	_crosshair.queue_redraw()
	if _viewfinder.visible:
		_viewfinder.queue_redraw()


func set_aiming(on: bool) -> void:
	_viewfinder.visible = on
	_crosshair.visible = not on
	update_stats()


## 1 / 2 pressed (or an item used): show the selector square for a moment.
func show_item(kind: String) -> void:
	_item_box.kind = kind
	_item_box.count = GameState.item_count(kind)
	_item_box.max_count = GameState.MAX_ITEMS
	_item_box.hold = 1.6
	_item_box.modulate.a = 1.0
	_item_box.queue_redraw()


func show_controls_help() -> void:
	_help_label.text = "WASD move   Shift sprint (noisy!)   Space jump   C crouch\nHold RIGHT-CLICK to raise the camera, LEFT-CLICK to snap\n1 bait  2 trap  3 tripod cam  4 joint  5 beer   Q use it   V 1st/3rd person   E interact   Esc pause\nCareful: your traps don't know whose side you're on."
	_help_label.visible = true
	_help_label.modulate.a = 1.0
	_help_timer = 14.0


func show_photo_popup(text: String) -> void:
	_popup_label.text = text
	_popup_label.visible = true
	_popup_timer = 2.2


func show_message(text: String) -> void:
	_message_label.text = text
	_message_label.visible = true
	_message_label.modulate.a = 1.0
	_message_timer = 2.8


func set_alert(text: String, color: Color) -> void:
	if text.is_empty():
		_alert_label.visible = false
		return
	_alert_label.text = text
	_alert_label.add_theme_color_override("font_color", color)
	_alert_label.visible = true


func set_chase_alert(dist: float, who: String = "Bigboobs") -> void:
	_alert_label.text = "RUN! %s is %.0f m away!" % [who, dist]
	_alert_label.add_theme_color_override("font_color", Color(1, 0.25, 0.2))
	_alert_label.visible = true


func show_hint(text: String) -> void:
	_hint_label.text = text
	_hint_label.visible = true


func hide_hint() -> void:
	_hint_label.visible = false


func set_grab_warning(active: bool) -> void:
	_grab_label.visible = active


## v < 0 hides it. Otherwise 0..1 how close you are to wriggling out of the beam.
func set_struggle(v: float) -> void:
	_struggle.visible = v >= 0.0
	if v >= 0.0:
		_struggle_bar.offset_right = 4.0 + 512.0 * clampf(v, 0.0, 1.0)
		var pulse:= 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.02)
		_struggle_label.modulate = Color(1, 1, 1, pulse)


func set_net_status(t: String) -> void:
	_net_label.visible = t != ""
	_net_label.text = t


## level < 0 hides the tag. radius = how far away cryptids can hear you right now.
func set_mic(level: float, radius: float = 0.0, talking: bool = false) -> void:
	_mic_label.visible = level >= 0.0
	if level < 0.0:
		return
	if Net.online():
		var hold:= not bool(GameState.settings.get("voice_open", false))
		_mic_label.text = "TALKING" if talking else ("HOLD T TO TALK" if hold else "MIC OPEN")
		_mic_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.5) if talking else Color(0.6, 0.65, 0.6))
		return
	var loud:= clampf(level, 0.0, 1.0)
	_mic_label.text = ("MIC  ▮▮▮  %dm" % int(radius)) if loud > 0.6 else (("MIC  ▮▮  %dm" % int(radius)) if loud > 0.25 else (("MIC  ▮  %dm" % int(radius)) if loud > 0.05 else "MIC"))
	_mic_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.55).lerp(Color(1.0, 0.35, 0.25), loud))


func set_danger(active: bool) -> void:
	_danger = active


func show_interact_prompt(show: bool, what: String = "Enter RV") -> void:
	_prompt.visible = show
	if show:
		_prompt_label.text = ("TAP  " if is_touch else "[E]  ") + what


func flash() -> void:
	_flash_rect.color = Color(1, 1, 1)
	_flash_rect.modulate.a = 0.7


## Blinded by a tourist's flash.
func stun_flash(duration: float) -> void:
	_stun_fade = duration
	_flash_rect.color = Color(1, 1, 1)
	_flash_rect.modulate.a = 1.0


func fade_to(alpha: float, seconds: float, color: Color = Color(0, 0, 0)) -> void:
	_flash_rect.color = color
	var tw:= create_tween()
	tw.tween_property(_flash_rect, "modulate:a", alpha, seconds)
	if alpha <= 0.0:
		tw.tween_callback(func(): _flash_rect.color = Color(1, 1, 1))


## Big map title card that fades in and out (arrivals, the drive).
var _title_box: VBoxContainer
func show_title(title: String, sub: String) -> void:
	if _title_box == null:
		_title_box = VBoxContainer.new()
		_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_place(_title_box, 0.5, 0.35, 0.5, 0.35, -500, -60, 500, 60)
		var t:= _label(64, Color(1, 0.9, 0.6))
		t.name = "T"
		t.add_theme_font_override("font", load("res://fonts/Rye-Regular.ttf"))
		_outline(t, 10)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_title_box.add_child(t)
		var s2:= _label(26, Color(1, 1, 1, 0.9))
		s2.name = "S"
		_outline(s2, 6)
		s2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_title_box.add_child(s2)
		_root.add_child(_title_box)
		# Above the fade so it shows over black.
		_root.move_child(_title_box, -1)
	(_title_box.get_node("T") as Label).text = title
	(_title_box.get_node("S") as Label).text = sub.to_upper()
	_title_box.modulate.a = 0.0
	var tw:= create_tween()
	tw.tween_property(_title_box, "modulate:a", 1.0, 0.6)
	tw.tween_interval(2.0)
	tw.tween_property(_title_box, "modulate:a", 0.0, 0.9)


func black_out() -> void:
	_flash_rect.color = Color(0, 0, 0)
	_flash_rect.modulate.a = 1.0


func set_hud_visible(on: bool) -> void:
	for c in [_night_label.get_parent().get_parent(), _compass, _crosshair]:
		c.visible = on
	if not on:
		_viewfinder.visible = false
		_prompt.visible = false


func set_compass_visible(on: bool) -> void:
	_compass.visible = on


func show_win(title: String = "TABLOID GOLD!", sub: String = "") -> void:
	_win_title.text = title
	_win_sub.text = sub
	_win_panel.visible = true


func show_lose(who: String = "Bigboobs") -> void:
	_lose_sub.text = "%s grabbed you and ripped the film out of your camera.\nYou wake up back at the RV..." % who
	_lose_panel.visible = true


func _build_end_panel(is_win: bool) -> void:
	var panel:= ColorRect.new()
	panel.color = Color(0.03, 0.02, 0.06, 0.85)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.visible = false
	_root.add_child(panel)
	var title:= _label(64, Color(1, 0.85, 0.3) if is_win else Color(1, 0.22, 0.2))
	title.add_theme_font_override("font", load("res://fonts/Rye-Regular.ttf"))
	title.text = "TABLOID GOLD!" if is_win else "GOTCHA!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(title, 0.5, 0.5, 0.5, 0.5, -500, -150, 500, -60)
	panel.add_child(title)
	var sub:= _label(26, Color(1, 1, 1))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_place(sub, 0.5, 0.5, 0.5, 0.5, -460, -40, 460, 60)
	panel.add_child(sub)
	var b:= Button.new()
	b.text = "KEEP GOING" if is_win else "NEXT NIGHT"
	b.add_theme_font_size_override("font_size", 26)
	_place(b, 0.5, 0.5, 0.5, 0.5, -130, 90, 130, 150)
	b.pressed.connect(func():
		if is_win:
			win_continue_pressed.emit()
		else:
			try_again_pressed.emit())
	panel.add_child(b)
	if is_win:
		_win_panel = panel
		_win_title = title
		_win_sub = sub
	else:
		_lose_panel = panel
		_lose_sub = sub


# ================================================================== widgets

class Compass extends Control:
	var yaw:= 0.0
	var player_pos:= Vector3.ZERO
	var markers: Array = []
	const SPAN:= 200.0  # degrees visible across the strip

	func _draw() -> void:
		var w:= size.x
		var h:= 30.0
		var font:= get_theme_default_font()
		# fading backdrop
		for i in 24:
			var t0:= float(i) / 24.0
			var a:= 0.55 * sin(PI * (t0 + 0.5 / 24.0))
			draw_rect(Rect2(w * t0, 0, w / 24.0 + 1, h), Color(0.03, 0.02, 0.07, a))
		draw_line(Vector2(w * 0.12, h), Vector2(w * 0.88, h), Color(1, 0.85, 0.4, 0.5), 1.5)
		var heading:= fposmod(-rad_to_deg(yaw), 360.0)  # 0 = north (-Z), clockwise
		for deg in range(0, 360, 15):
			var rel:= wrapf(float(deg) - heading, -180.0, 180.0)
			if absf(rel) > SPAN * 0.5:
				continue
			var x:= w * 0.5 + rel / SPAN * w
			var fade:= 1.0 - absf(rel) / (SPAN * 0.5)
			var col:= Color(1, 1, 1, 0.9 * fade)
			var label: String = {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}.get(deg, "")
			if label != "":
				var fs:= 22 if label.length() == 1 else 15
				var tw:= font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(font, Vector2(x - tw * 0.5, 21), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					Color(1, 0.4, 0.3, fade) if deg == 0 else col)
			else:
				draw_line(Vector2(x, h - 8), Vector2(x, h - 2), col, 1.5)
		# centre needle
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5 - 7, h + 1), Vector2(w * 0.5 + 7, h + 1), Vector2(w * 0.5, h - 7)]), Color(1, 0.85, 0.4))
		# markers
		for m in markers:
			var to: Vector3 = m["pos"] - player_pos
			var dist:= Vector2(to.x, to.z).length()
			var bearing:= rad_to_deg(atan2(to.x, -to.z))
			var rel:= wrapf(bearing - heading, -180.0, 180.0)
			var clamped:= clampf(rel, -SPAN * 0.5, SPAN * 0.5)
			var x:= w * 0.5 + clamped / SPAN * w
			var c: Color = m.get("color", Color(0.5, 0.9, 1.0))
			if absf(rel) > SPAN * 0.5:
				# off the edge: arrow pointing the way to turn
				var s:= signf(rel)
				draw_colored_polygon(PackedVector2Array([Vector2(x - s * 8, h + 10), Vector2(x + s * 6, h + 17), Vector2(x - s * 8, h + 24)]), c)
				continue
			_draw_marker_icon(Vector2(x, h + 16), c, str(m.get("icon", "pin")))
			var txt:= "%s %dm" % [m.get("label", ""), int(dist)]
			var tw:= font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string(font, Vector2(x - tw * 0.5 + 1, h + 43), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, 0.7))
			draw_string(font, Vector2(x - tw * 0.5, h + 42), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c)

	func _draw_marker_icon(p: Vector2, c: Color, icon: String) -> void:
		if icon == "rv":
			draw_rect(Rect2(p + Vector2(-10, -6), Vector2(20, 10)), c)
			draw_rect(Rect2(p + Vector2(6, -3), Vector2(6, 7)), c.darkened(0.2))
			draw_rect(Rect2(p + Vector2(-6, -4), Vector2(5, 4)), Color(0.05, 0.05, 0.1))
			draw_circle(p + Vector2(-5, 5), 2.6, Color(0.05, 0.05, 0.08))
			draw_circle(p + Vector2(6, 5), 2.6, Color(0.05, 0.05, 0.08))
		else:
			draw_circle(p, 6, c)
			draw_circle(p, 3, Color(0.05, 0.05, 0.08))


class Viewfinder extends Control:
	var film:= 6
	var film_max:= 6
	var charge:= 1.0

	func _draw() -> void:
		var w:= size.x
		var h:= size.y
		var m:= Vector2(w * 0.08, h * 0.1)
		var c:= Color(1, 1, 1, 0.85)
		# letterbox-ish dark edges
		draw_rect(Rect2(0, 0, w, m.y * 0.6), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(0, h - m.y * 0.6, w, m.y * 0.6), Color(0, 0, 0, 0.55))
		# corner brackets
		var L:= 46.0
		for corner in [Vector2(m.x, m.y), Vector2(w - m.x, m.y), Vector2(m.x, h - m.y), Vector2(w - m.x, h - m.y)]:
			var sx:= 1.0 if corner.x < w * 0.5 else -1.0
			var sy:= 1.0 if corner.y < h * 0.5 else -1.0
			draw_line(corner, corner + Vector2(L * sx, 0), c, 3)
			draw_line(corner, corner + Vector2(0, L * sy), c, 3)
		# rule of thirds, very faint
		for i in [1, 2]:
			draw_line(Vector2(w * i / 3.0, m.y), Vector2(w * i / 3.0, h - m.y), Color(1, 1, 1, 0.12), 1)
			draw_line(Vector2(m.x, h * i / 3.0), Vector2(w - m.x, h * i / 3.0), Color(1, 1, 1, 0.12), 1)
		# focus box
		var fb:= Rect2(w * 0.5 - 60, h * 0.5 - 42, 120, 84)
		var fc:= Color(0.5, 1, 0.5, 0.9) if charge >= 1.0 else Color(1, 0.8, 0.3, 0.8)
		for corner in [fb.position, fb.position + Vector2(fb.size.x, 0), fb.position + Vector2(0, fb.size.y), fb.end]:
			var sx:= 1.0 if corner.x < w * 0.5 else -1.0
			var sy:= 1.0 if corner.y < h * 0.5 else -1.0
			draw_line(corner, corner + Vector2(16 * sx, 0), fc, 2)
			draw_line(corner, corner + Vector2(0, 16 * sy), fc, 2)
		draw_circle(Vector2(w * 0.5, h * 0.5), 2.5, fc)
		var font:= get_theme_default_font()
		# film counter on the camera readout, centred in the bottom band
		var band:= m.y * 0.6
		var by:= h - band * 0.5 + 7
		draw_string(font, Vector2(m.x, by), "FILM", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))
		for i in film_max:
			var r:= Rect2(m.x + 50 + i * 20, by - 15, 14, 18)
			if i < film:
				draw_rect(r, Color(1, 0.86, 0.3))
			else:
				draw_rect(r, Color(1, 1, 1, 0.35), false, 1.5)
		draw_string(font, Vector2(m.x + 54 + film_max * 20, by + 1), "%d/%d" % [film, film_max], HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
			Color(1, 0.3, 0.25) if film == 0 else Color(1, 1, 1))
		# flash readiness
		var ready:= charge >= 1.0
		var fx:= w - m.x - 300
		var fc2:= Color(0.5, 1, 0.5) if ready else Color(1, 0.8, 0.3)
		draw_string(font, Vector2(fx, by), "FLASH", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))
		draw_rect(Rect2(fx + 60, by - 12, 150, 10), Color(1, 1, 1, 0.25))
		draw_rect(Rect2(fx + 60, by - 12, 150 * charge, 10), fc2)
		draw_string(font, Vector2(fx + 222, by), "READY" if ready else "CHARGING", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, fc2)
		if fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6:
			draw_circle(Vector2(w - m.x - 14, m.y + 14), 6, Color(1, 0.2, 0.15))


class Crosshair extends Control:
	var charge:= 1.0

	func _draw() -> void:
		var c:= size * 0.5
		draw_circle(c, 2.2, Color(1, 1, 1, 0.85))
		if charge < 1.0:
			draw_arc(c, 9, -PI / 2, -PI / 2 + TAU * charge, 24, Color(1, 0.8, 0.3, 0.9), 2.0)


class ItemBox extends Control:
	var kind:= "bait"
	var count:= 0
	var max_count:= 5
	var hold:= 0.0

	func _draw() -> void:
		var bare:= count < 0   # icon only (shop)
		if not bare:
			var sb:= StyleBoxFlat.new()
			sb.bg_color = Color(0.05, 0.04, 0.09, 0.82)
			sb.border_color = Color(1, 0.85, 0.4)
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(12)
			draw_style_box(sb, Rect2(Vector2.ZERO, size))
		var c:= size * Vector2(0.5, 0.5 if bare else 0.42)
		if kind == "tripod":
			for dx in [-26, 0, 26]:
				draw_line(c + Vector2(0, -4), c + Vector2(dx, 36), Color(0.75, 0.75, 0.78), 4)
			draw_rect(Rect2(c + Vector2(-22, -30), Vector2(44, 28)), Color(0.32, 0.36, 0.2))
			draw_circle(c + Vector2(0, -16), 9, Color(0.1, 0.1, 0.12))
			draw_circle(c + Vector2(15, -26), 3, Color(1, 0.15, 0.1))
		elif kind == "joint":
			# a proper cone: skinny twisted end, fat lit end, green flecks, no filter
			var tail:= c + Vector2(-34, 18)
			var head:= c + Vector2(24, -10)
			var dir:= (head - tail).normalized()
			var nrm:= Vector2(-dir.y, dir.x)
			var paper:= Color(0.96, 0.95, 0.9)
			draw_colored_polygon(PackedVector2Array([tail + nrm * 2.5, head + nrm * 8, head - nrm * 8, tail - nrm * 2.5]), paper)
			draw_line(tail, tail - dir * 8 + nrm * 3, paper, 3)      # twisted tip
			for k in 5:
				var q:= tail.lerp(head, 0.25 + k * 0.15) + nrm * (sin(k * 2.3) * 3.0)
				draw_circle(q, 1.6, Color(0.3, 0.55, 0.2))
			draw_circle(head, 8, Color(0.25, 0.22, 0.2))
			draw_circle(head + dir * 2, 5, Color(1, 0.45, 0.1))
			for i in 3:
				draw_arc(c + Vector2(30 + i * 4, -26 - i * 10), 6 + i * 2, PI * 0.2, PI * 1.2, 8, Color(0.85, 0.85, 0.9, 0.7 - i * 0.2), 2)
		elif kind == "beer":
			draw_rect(Rect2(c + Vector2(-18, -32), Vector2(36, 64)), Color(0.85, 0.65, 0.15))
			draw_rect(Rect2(c + Vector2(-18, -32), Vector2(36, 8)), Color(0.8, 0.8, 0.82))
			draw_rect(Rect2(c + Vector2(-18, -8), Vector2(36, 16)), Color(0.75, 0.1, 0.1))
			draw_rect(Rect2(c + Vector2(-18, 26), Vector2(36, 6)), Color(0.8, 0.8, 0.82))
		elif kind == "bait":
			draw_circle(c + Vector2(-6, 4), 26, Color(0.7, 0.24, 0.16))
			draw_circle(c + Vector2(-14, -4), 12, Color(0.8, 0.32, 0.22))
			draw_line(c + Vector2(10, -10), c + Vector2(34, -30), Color(0.96, 0.93, 0.84), 8)
			draw_circle(c + Vector2(36, -34), 6, Color(0.96, 0.93, 0.84))
			draw_circle(c + Vector2(30, -36), 6, Color(0.96, 0.93, 0.84))
		else:
			draw_arc(c, 28, PI * 0.1, PI * 0.9, 16, Color(0.7, 0.7, 0.75), 5)
			draw_arc(c, 28, PI * 1.1, PI * 1.9, 16, Color(0.7, 0.7, 0.75), 5)
			for i in 9:
				var a:= PI * 0.12 + i * PI * 0.095
				draw_line(c + Vector2(cos(a), sin(a)) * 28, c + Vector2(cos(a), sin(a)) * 18, Color(0.85, 0.85, 0.9), 3)
				draw_line(c - Vector2(cos(a), sin(a)) * 28, c - Vector2(cos(a), sin(a)) * 18, Color(0.85, 0.85, 0.9), 3)
			draw_line(c + Vector2(-36, 0), c + Vector2(36, 0), Color(0.6, 0.6, 0.65), 4)
		if bare:
			return
		var font:= get_theme_default_font()
		var it:= Catalog.item(kind)
		var key:= "%d  %s" % [int(it.get("key", 0)), str({"bait": "BAIT", "trap": "TRAP", "tripod": "TRIPOD", "joint": "JOINT", "beer": "BEER"}.get(kind, kind)).to_upper()]
		draw_string(font, Vector2(10, 22), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.85, 0.4))
		var txt:= "%d/%d" % [count, max_count]
		var tw:= font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		draw_string(font, Vector2((size.x - tw) * 0.5, size.y - 14), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26,
			Color(1, 0.4, 0.3) if count == 0 else Color(1, 1, 1))
