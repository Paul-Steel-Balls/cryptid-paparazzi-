extends RefCounted
class_name UIStyle
## Shared fonts, colours and widget styles for the menus.

const PAPER:= Color(0.88, 0.79, 0.6)
const PAPER_DARK:= Color(0.74, 0.62, 0.42)
const INK:= Color(0.2, 0.12, 0.07)
const BLOOD:= Color(0.55, 0.1, 0.06)
const GOLD:= Color(1, 0.85, 0.4)

static var _western: Font
static var _typewriter: Font


static func western() -> Font:
	if _western == null:
		_western = load("res://fonts/Rye-Regular.ttf")
	return _western


static func typewriter() -> Font:
	if _typewriter == null:
		_typewriter = load("res://fonts/SpecialElite-Regular.ttf")
	return _typewriter


static func label(text: String, size: int, color: Color, font: Font = null) -> Label:
	var l:= Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	return l


static func box(bg: Color, border: Color, width: int = 2, radius: int = 6, margin: int = 10) -> StyleBoxFlat:
	var sb:= StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


## Chunky woodcut-looking button: dark ink plate with paper-coloured western lettering.
static func poster_button(text: String, size: int = 22) -> Button:
	var b:= Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", western())
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", PAPER)
	b.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.75))
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.47, 0.35))
	b.add_theme_stylebox_override("normal", box(INK, BLOOD, 2, 4, 12))
	b.add_theme_stylebox_override("hover", box(Color(0.32, 0.17, 0.08), GOLD, 2, 4, 12))
	b.add_theme_stylebox_override("pressed", box(BLOOD, GOLD, 2, 4, 12))
	b.add_theme_stylebox_override("disabled", box(Color(0.3, 0.24, 0.18), Color(0.4, 0.32, 0.22), 2, 4, 12))
	b.custom_minimum_size = Vector2(0, 50)
	return b


## Neon-ish dark button for the shop and the RV.
static func dark_button(text: String, accent: Color = GOLD, size: int = 22) -> Button:
	var b:= Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", accent)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.55))
	b.add_theme_stylebox_override("normal", box(Color(0.08, 0.07, 0.12, 0.95), accent.darkened(0.35), 2, 8, 12))
	b.add_theme_stylebox_override("hover", box(Color(0.14, 0.12, 0.2, 0.95), accent, 2, 8, 12))
	b.add_theme_stylebox_override("pressed", box(accent.darkened(0.5), accent, 2, 8, 12))
	b.add_theme_stylebox_override("disabled", box(Color(0.1, 0.1, 0.12, 0.8), Color(0.3, 0.3, 0.35), 2, 8, 12))
	b.custom_minimum_size = Vector2(0, 50)
	return b


static func full_rect(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0


static func center(c: Control, w: float, h: float) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 0.5
	c.anchor_bottom = 0.5
	c.offset_left = -w * 0.5
	c.offset_right = w * 0.5
	c.offset_top = -h * 0.5
	c.offset_bottom = h * 0.5


## Material that turns a portrait into a flat silhouette.
static func silhouette(ink: Color = Color(0.12, 0.07, 0.04)) -> ShaderMaterial:
	var m:= ShaderMaterial.new()
	m.shader = load("res://ui/silhouette.gdshader")
	m.set_shader_parameter("ink", ink)
	return m
