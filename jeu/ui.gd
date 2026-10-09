class_name UI
extends RefCounted
## Direction artistique : couleurs, police, boutons et panneaux façon Kenney.

const DARK := Color("#3b3550")
const SKY := Color("#c5e4ff")
const WHITE := Color("#ffffff")
const PAPER := Color("#f4f7ff")
const YELLOW := Color("#facd2d")
const GREEN := Color("#5fcd55")
const BLUE := Color("#4b87f5")
const RED := Color("#f04650")
const GREY := Color("#8a8fa8")

static var _font: Font
static var _font_bold: Font


static func font(bold := false) -> Font:
	if _font == null:
		var base: FontFile = load("res://assets/fonts/Fredoka.ttf")
		var f := FontVariation.new()
		f.base_font = base
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 560}
		_font = f
		var fb := FontVariation.new()
		fb.base_font = base
		fb.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
		_font_bold = fb
	return _font_bold if bold else _font


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 24
	# boutons
	t.set_stylebox("normal", "Button", button_box(BLUE))
	t.set_stylebox("hover", "Button", button_box(BLUE.lightened(0.12)))
	t.set_stylebox("pressed", "Button", button_box(BLUE.darkened(0.08), true))
	t.set_stylebox("disabled", "Button", button_box(GREY))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.7))
	t.set_color("font_outline_color", "Button", DARK)
	t.set_constant("outline_size", "Button", 7)
	t.set_font("font", "Button", font(true))
	# champs texte
	var le := box(WHITE, DARK, 4, 14)
	le.content_margin_left = 16
	le.content_margin_right = 16
	le.content_margin_top = 10
	le.content_margin_bottom = 10
	t.set_stylebox("normal", "LineEdit", le)
	var lef: StyleBoxFlat = le.duplicate()
	lef.border_color = BLUE
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_color("font_color", "LineEdit", DARK)
	t.set_color("font_placeholder_color", "LineEdit", Color(DARK, 0.4))
	t.set_color("caret_color", "LineEdit", DARK)
	t.set_color("font_color", "Label", DARK)
	# panneaux
	var pn := box(WHITE, Color("#ece9fb"), 6, 30)
	pn.set_content_margin_all(28)
	pn.shadow_color = Color(0.13, 0.1, 0.25, 0.25)
	pn.shadow_size = 1
	pn.shadow_offset = Vector2(0, 10)
	t.set_stylebox("panel", "PanelContainer", pn)
	return t


static func box(bg: Color, border := DARK, bw := 4, radius := 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(bw)
	# style pastel : pas de gros contour sombre, une bordure dans la teinte du fond
	if border == DARK and bg.a > 0.5:
		border = Color("#e4e2f2") if bg.v > 0.95 and bg.s < 0.1 else bg.lightened(0.45)
	sb.border_color = border
	if bg.a > 0.9 and bw > 0:
		# petite ombre portée douce (style Mario Party)
		sb.shadow_color = Color(0.13, 0.1, 0.25, 0.2)
		sb.shadow_offset = Vector2(0, 5)
		sb.shadow_size = 1
	sb.anti_aliasing = true
	return sb


static func button_box(col: Color, pressed := false) -> StyleBoxFlat:
	var sb := box(col, col.darkened(0.22), 0, 24)
	sb.border_width_bottom = 4 if pressed else 8
	sb.shadow_color = Color(0.13, 0.1, 0.25, 0.22)
	sb.shadow_offset = Vector2(0, 4)
	sb.shadow_size = 1
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 12 + (5 if pressed else 0)
	sb.content_margin_bottom = 10
	return sb


static func lbl(text: String, size := 24, color := DARK, align := HORIZONTAL_ALIGNMENT_CENTER, outline := 0, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font(true))
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", DARK)
	return l


static func btn(text: String, cb: Callable, color := BLUE, size := 26) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", button_box(color))
	b.add_theme_stylebox_override("hover", button_box(color.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", button_box(color.darkened(0.08), true))
	b.pressed.connect(func(): Sfx.play("ui_ok", -4.0, 0.03); cb.call())
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


## Panneau façon Mario Party : fond coloré, bord blanc épais, ombre portée douce.
static func panel(ci: CanvasItem, r: Rect2, bg: Color, border := WHITE, radius := 20, bw := 5, shadow := true) -> void:
	if shadow:
		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(0.13, 0.1, 0.25, 0.22 * bg.a)
		sh.set_corner_radius_all(radius + 2)
		sh.anti_aliasing = true
		ci.draw_style_box(sh, Rect2(r.position + Vector2(0, 6), r.size))
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(bw)
	sb.border_color = border
	sb.anti_aliasing = true
	ci.draw_style_box(sb, r)
	# reflet en haut
	if bg.a > 0.9 and r.size.y > 30:
		var hl := StyleBoxFlat.new()
		hl.bg_color = Color(1, 1, 1, 0.22)
		hl.set_corner_radius_all(maxi(4, radius - bw - 2))
		hl.anti_aliasing = true
		ci.draw_style_box(hl, Rect2(r.position + Vector2(bw + 4, bw + 3), Vector2(r.size.x - 2 * bw - 8, minf(14.0, r.size.y * 0.22))))


## Bandeau titre (ruban) façon Mario Party.
static func ribbon(ci: CanvasItem, center: Vector2, s: String, size := 26, col := Color("#8e6cf0"), txt := WHITE) -> void:
	var w := text_width(s, size) + 70.0
	var h := size + 26.0
	var r := Rect2(center - Vector2(w / 2.0, h / 2.0), Vector2(w, h))
	var dk := col.darkened(0.3)
	for sd in [-1.0, 1.0]:
		var ex: float = center.x + sd * (w / 2.0 - 6.0)
		var pts := PackedVector2Array([Vector2(ex, r.position.y + 10), Vector2(ex + sd * 34, r.position.y + 10),
			Vector2(ex + sd * 22, r.position.y + 10 + h * 0.5), Vector2(ex + sd * 34, r.end.y + 10), Vector2(ex, r.end.y + 10)])
		ci.draw_colored_polygon(pts, dk)
	panel(ci, r, col, WHITE, 14, 4)
	text(ci, center, s, size, txt, 7)


## Texte centré avec contour, dessiné directement (noms, scores, gros titres).
static func text(ci: CanvasItem, center: Vector2, s: String, size := 24, col := WHITE, outline := 8, bold := true) -> void:
	var f := font(bold)
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := Vector2(center.x - w / 2.0, center.y + size * 0.36)
	if outline > 0:
		ci.draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, DARK)
	ci.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func text_width(s: String, size: int, bold := true) -> float:
	return font(bold).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


static var _tex_cache := {}


## Charge une fois pour toutes les 8 persos et leurs poses (à appeler au démarrage).
static func warm_cache() -> void:
	for c in 8:
		for pose in ["idle", "walk_a", "walk_b", "jump", "hit", "duck", "front", "climb_a", "climb_b"]:
			char_tex(c, pose)


static func char_tex(color_idx: int, pose := "idle") -> Texture2D:
	var key := "%d_%s" % [clampi(color_idx, 0, 7), pose]
	if not _tex_cache.has(key):
		_tex_cache[key] = load("res://assets/chars/%s/%s.png" % [Net.COLOR_IDS[clampi(color_idx, 0, 7)], pose])
	return _tex_cache[key]


## Petit perso qui se dandine, utilisé dans le menu et le salon.
class CharIcon extends Control:
	var color_idx := 0
	var t := 0.0
	var label := ""
	var sub := ""
	var tex: Texture2D

	func _init(c: int, w := 120.0, h := 150.0) -> void:
		color_idx = c
		t = randf() * 10.0
		custom_minimum_size = Vector2(w, h)
		tex = UI.char_tex(c, "idle")

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var s := minf(size.x, size.y - 40.0) / 200.0
		var bob := absf(sin(t * 3.2))
		var sq := Vector2(1.0 + (1.0 - bob) * 0.06, 1.0 - (1.0 - bob) * 0.06)
		var feet := Vector2(size.x / 2.0, size.y - 34.0)
		# rond de couleur derrière le perso (sinon sa bulle blanche disparaît sur les panneaux blancs)
		var pc: Color = Net.COLORS[color_idx]
		var hc := feet + Vector2(0, -132.0 * s - bob * 10.0)
		draw_circle(hc, 50.0 * s, pc.darkened(0.08))
		_draw_ellipse(feet + Vector2(0, 2), Vector2(70.0 * s, 16.0 * s), Color(0, 0, 0, 0.12))
		draw_set_transform(feet - Vector2(0, bob * 10.0), 0.0, sq * s)
		draw_texture(tex, Vector2(-128, -256))
		draw_set_transform(Vector2.ZERO)
		draw_circle(Vector2(size.x / 2.0, size.y - 32.0), 30.0 * s * 2.2 * (0.8 + 0.2 * (1.0 - bob)), Color(0, 0, 0, 0.0))
		if label != "":
			UI.text(self, Vector2(size.x / 2.0, size.y - 16.0), label, 20, Net.COLORS[color_idx], 7)

	func _draw_ellipse(c: Vector2, r: Vector2, col: Color) -> void:
		draw_set_transform(c, 0.0, Vector2(1.0, r.y / r.x))
		draw_circle(Vector2.ZERO, r.x, col)
		draw_set_transform(Vector2.ZERO)
		if sub != "":
			UI.text(self, Vector2(size.x / 2.0, 10.0), sub, 16, UI.GREY, 0)
