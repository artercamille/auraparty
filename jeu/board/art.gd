extends Node2D
## Décor du plateau, en 3 ambiances au choix :
##   "tropical" : île dans l'océan, plage, palmiers, ponton en planches
##   "forest"   : forêt enchantée, rivière avec ponts, champignons géants, chemin pavé
##   "sky"      : grande île volante, falaise rocheuse, cascades, petites îles autour
## Le gros du décor est dessiné une seule fois ; l'eau, les cascades et les nuages bougent.

const M := Vector2(2760, 1500)
const OUT := UI.DARK
const BLUE := Color("#4b87f5")
const RED := Color("#f04650")
const START := Color("#5fcd55")

var theme := "tropical"
var curve: PackedVector2Array
var land: PackedVector2Array
var rng := RandomNumberGenerator.new()
var t := 0.0
var layers := {}
var props: Array = []          # [pos, kind, scale, flip]
var river: PackedVector2Array
var falls: Array = []          # cascades [x, y haut]
var isles: Array = []          # petites îles volantes [centre, rayon]
var waves: Array = []
var _off_cache := {}
var river_polys: Array = []
var foam1: PackedVector2Array
var foam2: PackedVector2Array


func _init(th := "tropical") -> void:
	theme = th


func _ready() -> void:
	curve = BoardLayout.curve()
	rng.seed = 2024
	land = _offset(curve, 230.0)
	for n in ["back", "anim_lo", "ground", "anim_hi", "props"]:
		var l := Node2D.new()
		l.z_index = layers.size()
		add_child(l)
		layers[n] = l
	(layers["back"] as Node2D).draw.connect(_draw_back)
	(layers["anim_lo"] as Node2D).draw.connect(_draw_anim_lo)
	(layers["ground"] as Node2D).draw.connect(_draw_ground)
	(layers["anim_hi"] as Node2D).draw.connect(_draw_anim_hi)
	(layers["props"] as Node2D).draw.connect(_draw_props)
	if theme == "forest":
		river = _smooth([Vector2(-600, 120), Vector2(300, 360), Vector2(900, 620), Vector2(1420, 700),
			Vector2(1900, 980), Vector2(2450, 1160), Vector2(3400, 1500)], 16)
		river_polys = Geometry2D.offset_polyline(river, 112.0)
	if theme == "sky":
		isles = [[Vector2(-120, 260), 150.0], [Vector2(2930, 420), 170.0], [Vector2(2880, 1380), 130.0], [Vector2(-60, 1330), 120.0]]
		var xmin := 1e9
		var xmax := -1e9
		for q in land:
			xmin = minf(xmin, q.x)
			xmax = maxf(xmax, q.x)
		for fx in [0.27, 0.71]:
			var x := lerpf(xmin, xmax, fx)
			falls.append([x, _bottom_y(land, x)])
	if theme == "tropical":
		foam1 = _offset(curve, 312.0)
		foam2 = _offset(curve, 348.0)
		var sea := _offset(curve, 380.0)
		while waves.size() < 80:
			var w := Vector2(rng.randf_range(-1400, M.x + 1400), rng.randf_range(-900, M.y + 900))
			if not Geometry2D.is_point_in_polygon(w, sea):
				waves.append(w)
	_place_props()


func _process(delta: float) -> void:
	t += delta
	(layers["anim_lo"] as Node2D).queue_redraw()
	(layers["anim_hi"] as Node2D).queue_redraw()


# ------------------------------------------------------------------ outils
func _offset(src: PackedVector2Array, d: float) -> PackedVector2Array:
	var polys := Geometry2D.offset_polygon(src, d, Geometry2D.JOIN_ROUND)
	var best := PackedVector2Array()
	for p in polys:
		if p.size() > best.size():
			best = p
	return best


func _smooth(pts: Array, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(pts.size() - 1):
		var p0: Vector2 = pts[maxi(i - 1, 0)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[mini(i + 2, pts.size() - 1)]
		for k in steps:
			var u := k / float(steps)
			var u2 := u * u
			var u3 := u2 * u
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3))
	out.append(pts[-1])
	return out


func _poly(ci: CanvasItem, poly: PackedVector2Array, fill: Color, line := OUT, w := 8.0) -> void:
	if poly.size() < 3:
		return
	ci.draw_colored_polygon(poly, fill)
	if w > 0.0:
		var l := poly.duplicate()
		l.append(poly[0])
		ci.draw_polyline(l, line, w, true)


func _blob(c: Vector2, r: float, n := 14, jitter := 0.12) -> PackedVector2Array:
	var p := PackedVector2Array()
	for k in n:
		var a := k * TAU / n
		p.append(c + Vector2(cos(a), sin(a) * 0.82) * r * (1.0 + rng.randf_range(-jitter, jitter)))
	return p


func _ellipse(ci: CanvasItem, c: Vector2, r: Vector2, col: Color) -> void:
	ci.draw_set_transform(c, 0.0, Vector2(1.0, r.y / r.x))
	ci.draw_circle(Vector2.ZERO, r.x, col)
	ci.draw_set_transform(Vector2.ZERO)


func _off(d: float) -> PackedVector2Array:
	if not _off_cache.has(d):
		_off_cache[d] = _offset(curve, d)
	return _off_cache[d]


## Vrai si p est à au moins d du chemin (la boucle des cases).
func _far(p: Vector2, d: float) -> bool:
	return not Geometry2D.is_point_in_polygon(p, _off(d)) or Geometry2D.is_point_in_polygon(p, _off(-d))


func _near_river(p: Vector2) -> bool:
	for poly in river_polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false


func _dist_to_line(p: Vector2, line: PackedVector2Array) -> float:
	var best := 1e9
	for i in range(line.size() - 1):
		var q := Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])
		best = minf(best, q.distance_to(p))
	return best


## Bas de l'île à l'abscisse x (pour la falaise de l'île volante).
func _bottom_y(poly: PackedVector2Array, x: float) -> float:
	var best := -1e9
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if (a.x - x) * (b.x - x) <= 0.0 and absf(b.x - a.x) > 0.001:
			var k := (x - a.x) / (b.x - a.x)
			best = maxf(best, lerpf(a.y, b.y, k))
	return best


# ------------------------------------------------------------------ placement du décor
func _place_props() -> void:
	var inner := _offset(curve, 190.0) if theme != "forest" else PackedVector2Array()
	var sand_out := _offset(curve, 300.0)
	var tries := 0
	var want: int = {"tropical": 120, "forest": 230, "sky": 110}[theme]
	while props.size() < want and tries < 9000:
		tries += 1
		var p := Vector2(rng.randf_range(-700, M.x + 700), rng.randf_range(-500, M.y + 500))
		if not _far(p, 112.0):
			continue
		# les grands décors ne doivent pas cacher le chemin avec leur feuillage
		if not _far(p + Vector2(0, -110), 150.0):
			continue
		var kind := ""
		match theme:
			"tropical":
				if not Geometry2D.is_point_in_polygon(p, sand_out):
					continue
				var on_grass := Geometry2D.is_point_in_polygon(p, inner)
				if not on_grass:
					kind = ["palm", "palm", "palm", "shell", "shell", "star_fish", "rock"][rng.randi() % 7]
				else:
					kind = ["palm", "bush", "bush", "flowers", "flowers", "flowers", "rock", "palm"][rng.randi() % 8]
			"forest":
				if _near_river(p):
					continue
				var inside := Geometry2D.is_point_in_polygon(p, curve)
				if not inside and _far(p, 330.0):
					kind = ["tree", "tree", "tree", "pine", "pine", "tree"][rng.randi() % 6]
				elif inside and _far(p, 260.0):
					kind = ["tree", "mushroom", "flowers", "flowers", "bush", "pine"][rng.randi() % 6]
				else:
					kind = ["flowers", "flowers", "bush", "mushroom", "rock", "tree"][rng.randi() % 6]
			"sky":
				if not Geometry2D.is_point_in_polygon(p, inner):
					continue
				kind = ["tree", "bush", "flowers", "flowers", "tree", "rock", "pine"][rng.randi() % 7]
		var ok := true
		var min_d := 70.0 if kind in ["flowers", "shell", "star_fish"] else 110.0
		if kind in ["tree", "pine"] and theme == "forest":
			min_d = 95.0
		for q in props:
			if (q[0] as Vector2).distance_to(p) < min_d:
				ok = false
				break
		if ok:
			props.append([p, kind, rng.randf_range(0.85, 1.2), rng.randf() < 0.5])
	# éléments uniques
	match theme:
		"tropical":
			props.append([Vector2(1390, 760), "hut", 1.3, false])
			props.append([Vector2(1150, 690), "palm", 1.2, true])
			props.append([Vector2(1640, 700), "palm", 1.25, false])
		"forest":
			props.append([Vector2(1420, 820), "mushroom_house", 1.4, false])
			props.append([Vector2(1180, 900), "mushroom", 1.5, true])
		"sky":
			props.append([Vector2(1380, 760), "house", 1.3, false])
			props.append([Vector2(1650, 700), "windmill", 1.2, false])
	props.sort_custom(func(a, b): return (a[0] as Vector2).y < (b[0] as Vector2).y)


# ------------------------------------------------------------------ fonds
func _draw_back() -> void:
	var ci: Node2D = layers["back"]
	var big := Rect2(-1800, -1300, M.x + 3600, M.y + 2600)
	match theme:
		"tropical":
			ci.draw_rect(big, Color("#1b7fd1"))
			for k in 4:
				var d := 620.0 - k * 80.0
				_poly(ci, _offset(curve, d), [Color("#2390db"), Color("#2fa3e4"), Color("#3db8ea"), Color("#4fcdec")][k], OUT, 0.0)
		"forest":
			ci.draw_rect(big, Color("#5dbb4f"))
			var r := RandomNumberGenerator.new()
			r.seed = 7
			for i in 140:
				var c := Vector2(r.randf_range(-1500, M.x + 1500), r.randf_range(-1000, M.y + 1000))
				_ellipse(ci, c, Vector2(r.randf_range(80, 220), r.randf_range(40, 110)), Color("#69c95a") if i % 2 == 0 else Color("#55b048"))
			# rivière
			ci.draw_polyline(river, OUT, 168.0, true)
			ci.draw_polyline(river, Color("#3aa3e8"), 152.0, true)
			ci.draw_polyline(river, Color("#5cc0f4"), 104.0, true)
			ci.draw_polyline(river, Color("#86d6ff"), 40.0, true)
		"sky":
			# nuages lointains sous l'île
			var r := RandomNumberGenerator.new()
			r.seed = 11
			for i in 26:
				var c := Vector2(r.randf_range(-1300, M.x + 1300), r.randf_range(M.y - 200, M.y + 900))
				_cloud(ci, c, r.randf_range(1.2, 2.6), Color(1, 1, 1, 0.55))


func _cloud(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	for b in [[-60, 10, 44], [-20, -14, 58], [34, -6, 50], [72, 12, 36], [8, 18, 50]]:
		ci.draw_circle(c + Vector2(b[0], b[1]) * s, b[2] * s, col)


func _draw_anim_lo() -> void:
	var ci: Node2D = layers["anim_lo"]
	match theme:
		"tropical":
			for i in waves.size():
				var w: Vector2 = waves[i] + Vector2(fmod(t * 14.0 + i * 37.0, 120.0) - 60.0, 0)
				var a := 0.35 + 0.25 * sin(t * 1.5 + i)
				ci.draw_arc(w, 22.0, PI * 1.15, PI * 1.85, 8, Color(1, 1, 1, a), 4.0)
				ci.draw_arc(w + Vector2(34, 6), 16.0, PI * 1.15, PI * 1.85, 8, Color(1, 1, 1, a * 0.8), 3.0)
			# écume autour de la plage
			ci.draw_polyline(_closed(foam1), Color(1, 1, 1, 0.6 + 0.2 * sin(t * 1.4)), 12.0 + 3.0 * sin(t * 1.4))
			ci.draw_polyline(_closed(foam2), Color(1, 1, 1, 0.22 + 0.12 * sin(t * 1.4 + 1.5)), 6.0)
		"forest":
			for i in 40:
				var u := fmod(t * 0.03 + i / 40.0, 1.0)
				var idx := int(u * (river.size() - 1))
				var p := river[idx] + Vector2(sin(i * 3.1) * 36.0, cos(i * 2.3) * 14.0)
				ci.draw_arc(p, 14.0, PI * 1.2, PI * 1.8, 6, Color(1, 1, 1, 0.6), 3.0)
		"sky":
			var r := RandomNumberGenerator.new()
			r.seed = 21
			for i in 10:
				var c := Vector2(fposmod(r.randf_range(-1300, M.x + 1300) + t * r.randf_range(8, 20), M.x + 2600) - 1300, r.randf_range(-700, M.y + 600))
				_cloud(ci, c, r.randf_range(1.0, 2.0), Color(1, 1, 1, 0.8))


# ------------------------------------------------------------------ terre, chemin, cases
func _draw_ground() -> void:
	var ci: Node2D = layers["ground"]
	match theme:
		"tropical":
			var sand := _offset(curve, 300.0)
			_poly(ci, sand, Color("#f5d38c"), OUT, 9.0)
			_poly(ci, _offset(curve, 284.0), Color("#f9e0a6"), OUT, 0.0)
			var r := RandomNumberGenerator.new()
			r.seed = 3
			for i in 500:
				var p := Vector2(r.randf_range(0, M.x), r.randf_range(0, M.y))
				if Geometry2D.is_point_in_polygon(p, sand):
					ci.draw_circle(p, r.randf_range(2, 4), Color("#e7bf74"))
			var grass := _offset(curve, 196.0)
			_poly(ci, grass, Color("#5ccb5c"), Color("#3a9f45"), 8.0)
			_patches(ci, grass, Color("#6dd76a"), 40)
			_path_planks(ci)
		"forest":
			_path_cobbles(ci)
		"sky":
			_sky_island(ci, land, 1.0)
			for isle in isles:
				var c: Vector2 = isle[0]
				var rad: float = isle[1]
				_sky_island(ci, _blob(c, rad, 16, 0.1), 0.55)
			_path_dirt(ci)
	_draw_spaces(ci)


func _patches(ci: CanvasItem, area: PackedVector2Array, col: Color, n: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var placed := 0
	var tries := 0
	while placed < n and tries < 2000:
		tries += 1
		var p := Vector2(r.randf_range(0, M.x), r.randf_range(0, M.y))
		if Geometry2D.is_point_in_polygon(p, area) and _far(p, 90.0):
			_ellipse(ci, p, Vector2(r.randf_range(50, 120), r.randf_range(26, 50)), col)
			placed += 1
	r.seed = 6
	for i in 260:
		var p := Vector2(r.randf_range(0, M.x), r.randf_range(0, M.y))
		if Geometry2D.is_point_in_polygon(p, area) and _far(p, 60.0):
			ci.draw_arc(p, 7, PI * 1.1, PI * 1.9, 6, col.darkened(0.3), 3.0)
			ci.draw_arc(p + Vector2(10, 2), 6, PI * 1.1, PI * 1.9, 6, col.darkened(0.3), 3.0)


func _closed(c: PackedVector2Array) -> PackedVector2Array:
	var l := c.duplicate()
	l.append(c[0])
	return l


func _path_planks(ci: CanvasItem) -> void:
	var road := _closed(curve)
	ci.draw_polyline(road, OUT, 78.0, true)
	ci.draw_polyline(road, Color("#c98a4e"), 66.0, true)
	ci.draw_polyline(road, Color("#d99a5c"), 46.0, true)
	var acc := 0.0
	for i in curve.size():
		var a := curve[i]
		var b := curve[(i + 1) % curve.size()]
		var seg := a.distance_to(b)
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x)
		var s := 0.0
		while acc + seg - s >= 24.0:
			s += 24.0 - acc
			acc = 0.0
			var p := a + d * s
			ci.draw_line(p - n * 32.0, p + n * 32.0, Color("#9c6235"), 3.0)
		acc += seg - s
	# clous / rambardes
	for i in range(0, curve.size(), 14):
		var p := curve[i]
		var d := (curve[(i + 1) % curve.size()] - p).normalized()
		var n := Vector2(-d.y, d.x)
		for s in [-1.0, 1.0]:
			ci.draw_circle(p + n * 36.0 * s, 7.0, OUT)
			ci.draw_circle(p + n * 36.0 * s, 4.5, Color("#8a5530"))


func _path_cobbles(ci: CanvasItem) -> void:
	var road := _closed(curve)
	ci.draw_polyline(road, Color("#3f8a3a"), 90.0, true)
	ci.draw_polyline(road, Color("#caa271"), 72.0, true)
	var r := RandomNumberGenerator.new()
	r.seed = 9
	for i in range(0, curve.size(), 2):
		var p := curve[i]
		var d := (curve[(i + 1) % curve.size()] - p).normalized()
		var n := Vector2(-d.y, d.x)
		for k in [-1.0, 0.0, 1.0]:
			var q: Vector2 = p + n * (k * 21.0 + r.randf_range(-3, 3))
			var rr := r.randf_range(8.0, 11.0)
			ci.draw_circle(q, rr + 2.5, Color("#9c8f7e"))
			ci.draw_circle(q, rr, Color("#e8e2d6"))
			ci.draw_circle(q + Vector2(-2, -3), rr * 0.4, Color("#f7f4ee"))
	# ponts au-dessus de la rivière
	for i in curve.size():
		var p := curve[i]
		if _dist_to_line(p, river) < 92.0:
			var d := (curve[(i + 1) % curve.size()] - p).normalized()
			var n := Vector2(-d.y, d.x)
			ci.draw_line(p - n * 46.0, p + n * 46.0, OUT, 16.0)
			ci.draw_line(p - n * 42.0, p + n * 42.0, Color("#c98a4e"), 10.0)
			if i % 6 == 0:
				for s in [-1.0, 1.0]:
					ci.draw_circle(p + n * 48.0 * s, 9.0, OUT)
					ci.draw_circle(p + n * 48.0 * s, 6.0, Color("#8a5530"))


func _path_dirt(ci: CanvasItem) -> void:
	var road := _closed(curve)
	ci.draw_polyline(road, Color("#3f9a45"), 84.0, true)
	ci.draw_polyline(road, Color("#e2b57a"), 68.0, true)
	ci.draw_polyline(road, Color("#ecc791"), 40.0, true)
	var r := RandomNumberGenerator.new()
	r.seed = 12
	for i in range(0, curve.size(), 3):
		var p := curve[i] + Vector2(r.randf_range(-24, 24), r.randf_range(-24, 24))
		ci.draw_circle(p, r.randf_range(3, 6), Color("#c99a62"))


func _sky_island(ci: CanvasItem, top: PackedVector2Array, sc: float) -> void:
	var xmin := 1e9
	var xmax := -1e9
	for p in top:
		xmin = minf(xmin, p.x)
		xmax = maxf(xmax, p.x)
	var cliff_h := 70.0 * sc
	# bas de l'île lissé (on bouche les creux pour une falaise propre)
	var n := 40
	var raw := []
	for k in n + 1:
		raw.append(_bottom_y(top, lerpf(xmin + 6.0, xmax - 6.0, k / float(n))))
	var by := []
	for k in n + 1:
		var m := -1e9
		for j in range(maxi(0, k - 5), mini(n, k + 5) + 1):
			m = maxf(m, float(raw[j]))
		by.append(m)
	# dessous rocheux en pointe
	var under := PackedVector2Array()
	for k in n + 1:
		var x := lerpf(xmin + 6.0, xmax - 6.0, k / float(n))
		under.append(Vector2(x, float(raw[k]) + cliff_h - 6.0))
	var tips := PackedVector2Array()
	for k in range(n, -1, -1):
		var x := lerpf(xmin + 6.0, xmax - 6.0, k / float(n))
		var u := k / float(n)
		var dep: float = (430.0 * sc) * pow(sin(u * PI), 0.75) * (0.8 + 0.2 * sin(k * 1.7))
		tips.append(Vector2(x + sin(k * 2.3) * 8.0, float(by[k]) + cliff_h + dep))
	var rock := under.duplicate()
	rock.append_array(tips)
	_poly(ci, rock, Color("#7d5a3e"), OUT, 8.0 * sc + 2.0)
	for f in [0.66, 0.36]:
		var band := under.duplicate()
		for k in range(n, -1, -1):
			var x := lerpf(xmin + 6.0, xmax - 6.0, k / float(n))
			var u := k / float(n)
			var dep: float = (430.0 * sc) * pow(sin(u * PI), 0.75) * (0.8 + 0.2 * sin(k * 1.7)) * f
			band.append(Vector2(x, maxf(float(raw[k]) + cliff_h, float(by[k]) + cliff_h + dep - 20.0)))
		_poly(ci, band, Color("#916a48") if f > 0.5 else Color("#a87c52"), OUT, 0.0)
	# lianes
	for k in range(2, n - 1, 3):
		var x := lerpf(xmin, xmax, k / float(n))
		var y0 := float(by[k]) + cliff_h + (430.0 * sc) * pow(sin(k / float(n) * PI), 0.75) * 0.3
		var ln := 40.0 + fmod(k * 37.0, 90.0) * sc
		ci.draw_line(Vector2(x, y0), Vector2(x + 6.0, y0 + ln), Color("#3c9a46"), 5.0 * sc + 1.0)
		ci.draw_circle(Vector2(x + 6.0, y0 + ln), 7.0 * sc + 2.0, Color("#4fb85a"))
	# falaise de terre + herbe
	var cliff := PackedVector2Array()
	for p in top:
		cliff.append(p + Vector2(0, cliff_h))
	_poly(ci, cliff, Color("#d98f5a"), OUT, 8.0)
	for k in 2:
		var bl := PackedVector2Array()
		for p in top:
			bl.append(p + Vector2(0, cliff_h * (0.45 + k * 0.28)))
		bl.append(bl[0])
		ci.draw_polyline(bl, Color("#c27a48"), 5.0, true)
	_poly(ci, top, Color("#5fcf62"), OUT, 8.0)
	var hi := _offset(top, -16.0)
	if hi.size() > 2:
		var hl := hi.duplicate()
		hl.append(hi[0])
		ci.draw_polyline(hl, Color("#79df76"), 8.0, true)
	if sc >= 1.0:
		_patches(ci, top, Color("#6fd970"), 30)


func _draw_spaces(ci: CanvasItem) -> void:
	for i in BoardLayout.count():
		var p := BoardLayout.pos_at(i)
		var ty := BoardLayout.type_at(i)
		_space(ci, p, ty)


## Une case façon Mario Party : socle en pierre, pastille bombée et brillante, symbole + / - en relief.
func _space(ci: CanvasItem, p: Vector2, ty: String) -> void:
	var col := BLUE if ty == "B" else (RED if ty == "R" else START)
	var r := 36.0
	# ombre au sol + socle en pierre
	_ellipse(ci, p + Vector2(0, 16), Vector2(r + 16.0, (r + 16.0) * 0.55), Color(0, 0, 0, 0.2))
	_ellipse(ci, p + Vector2(0, 9), Vector2(r + 14.0, r + 11.0), OUT)
	_ellipse(ci, p + Vector2(0, 9), Vector2(r + 10.0, r + 7.0), Color("#a79f92"))
	_ellipse(ci, p + Vector2(0, 4), Vector2(r + 14.0, r + 11.0), OUT)
	_ellipse(ci, p + Vector2(0, 4), Vector2(r + 10.0, r + 7.0), Color("#ece6da"))
	for k in 8:
		var a := k * TAU / 8.0 + 0.2
		var q := p + Vector2(cos(a) * (r + 6.0), sin(a) * (r + 3.5) + 4.0)
		ci.draw_line(q, q + Vector2(cos(a), sin(a)) * 5.0, Color("#c7bfb1"), 2.5)
	# épaisseur de la pastille
	ci.draw_circle(p + Vector2(0, 7), r + 4.0, OUT)
	ci.draw_circle(p + Vector2(0, 7), r, col.darkened(0.35))
	# dessus bombé
	ci.draw_circle(p, r + 4.0, OUT)
	ci.draw_circle(p, r, col)
	ci.draw_circle(p + Vector2(0, -3), r - 5.0, col.lightened(0.14))
	ci.draw_circle(p + Vector2(0, -6), r - 14.0, col.lightened(0.24))
	ci.draw_arc(p, r - 4.0, PI * 1.08, PI * 1.62, 12, Color(1, 1, 1, 0.75), 5.0)
	ci.draw_circle(p + Vector2(-r * 0.42, -r * 0.5), 4.0, Color(1, 1, 1, 0.85))
	# symbole en relief
	var sym := Color.WHITE
	if ty == "B" or ty == "R":
		var bars := [Rect2(-17, -6, 34, 12)]
		if ty == "B":
			bars.append(Rect2(-6, -17, 12, 34))
		for rr in bars:
			ci.draw_style_box(UI.box(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 0, 6), (rr as Rect2).grow(1.0).abs() if false else Rect2(p + (rr as Rect2).position + Vector2(0, 4), (rr as Rect2).size))
		for rr in bars:
			ci.draw_style_box(UI.box(OUT, OUT, 0, 8), Rect2(p + (rr as Rect2).position - Vector2(3.5, 3.5), (rr as Rect2).size + Vector2(7, 7)))
		for rr in bars:
			ci.draw_style_box(UI.box(sym, sym, 0, 6), Rect2(p + (rr as Rect2).position, (rr as Rect2).size))
	else:
		# départ : petit drapeau
		ci.draw_line(p + Vector2(-9, 18), p + Vector2(-9, -20), OUT, 7.0)
		ci.draw_line(p + Vector2(-9, 18), p + Vector2(-9, -20), sym, 3.5)
		var flag := PackedVector2Array([p + Vector2(-8, -20), p + Vector2(18, -12), p + Vector2(-8, -3)])
		_poly(ci, flag, Color("#facd2d"), OUT, 3.5)


# ------------------------------------------------------------------ animations au-dessus du sol
func _draw_anim_hi() -> void:
	var ci: Node2D = layers["anim_hi"]
	if theme == "sky":
		for f in falls:
			var x: float = f[0]
			var y0: float = float(f[1]) + 40.0
			var h := 760.0
			ci.draw_rect(Rect2(x - 34.0, y0, 68.0, h), Color("#7fd0ff"))
			ci.draw_rect(Rect2(x - 22.0, y0, 44.0, h), Color("#b4e6ff"))
			for k in 14:
				var yy := y0 + fposmod(t * 520.0 + k * 61.0, h)
				ci.draw_line(Vector2(x - 26.0 + fmod(k * 13.0, 50.0), yy), Vector2(x - 26.0 + fmod(k * 13.0, 50.0), yy + 40.0), Color(1, 1, 1, 0.8), 4.0)
			for k in 6:
				var a := t * 1.5 + k
				ci.draw_circle(Vector2(x + sin(a) * 40.0, y0 + h - 30.0 + cos(a * 1.3) * 10.0), 40.0 + 8.0 * sin(a), Color(1, 1, 1, 0.35))
			# petit lac en haut
			_ellipse(ci, Vector2(x, y0 - 70.0), Vector2(80, 38), OUT)
			_ellipse(ci, Vector2(x, y0 - 70.0), Vector2(72, 32), Color("#5cc0f4"))
			ci.draw_rect(Rect2(x - 22.0, y0 - 70.0, 44.0, 70.0), Color("#5cc0f4"))
			_ellipse(ci, Vector2(x - 10.0, y0 - 76.0), Vector2(26, 8), Color(1, 1, 1, 0.5 + 0.2 * sin(t * 2.0)))


# ------------------------------------------------------------------ décor
func _draw_props() -> void:
	var ci: Node2D = layers["props"]
	for pr in props:
		var p: Vector2 = pr[0]
		var s: float = pr[2]
		var fl: bool = pr[3]
		match str(pr[1]):
			"palm":
				_palm(ci, p, s, -1.0 if fl else 1.0)
			"bush":
				_bush(ci, p, s)
			"flowers":
				_flowers(ci, p, s)
			"rock":
				_rock(ci, p, s)
			"shell":
				_shell(ci, p, s)
			"star_fish":
				_starfish(ci, p, s)
			"tree":
				_tree(ci, p, s)
			"pine":
				_pine(ci, p, s)
			"mushroom":
				_mushroom(ci, p, s)
			"hut":
				_hut(ci, p, s)
			"house":
				_house(ci, p, s)
			"mushroom_house":
				_mushroom_house(ci, p, s)
			"windmill":
				_windmill(ci, p, s)


func _shadow(ci: CanvasItem, p: Vector2, w: float) -> void:
	_ellipse(ci, p, Vector2(w, w * 0.32), Color(0, 0, 0, 0.18))


func _palm(ci: CanvasItem, p: Vector2, s: float, lean: float) -> void:
	_shadow(ci, p + Vector2(30 * lean * s, 4), 46.0 * s)
	var top := p + Vector2(lean * 46.0, -170.0) * s
	var pts := PackedVector2Array()
	for k in 9:
		var u := k / 8.0
		pts.append(p.lerp(top, u) + Vector2(lean * sin(u * PI) * 14.0 * s, 0))
	ci.draw_polyline(pts, OUT, 26.0 * s, true)
	ci.draw_polyline(pts, Color("#b97a46"), 17.0 * s, true)
	for k in range(1, 8):
		var q := pts[k]
		ci.draw_line(q + Vector2(-8, 0) * s, q + Vector2(8, -3) * s, Color("#8e5a31"), 3.0)
	for k in 7:
		var a := -PI / 2.0 + (k - 3.0) * 0.62 + lean * 0.1
		var dir := Vector2(cos(a), sin(a))
		var leaf := PackedVector2Array()
		var side := PackedVector2Array()
		var ln := 92.0 * s
		for j in 8:
			var u := j / 7.0
			var droop := Vector2(0, u * u * 46.0 * s)
			var c := top + dir * ln * u + droop
			var w := sin(u * PI) * 17.0 * s
			var nn := Vector2(-dir.y, dir.x)
			leaf.append(c + nn * w)
			side.insert(0, c - nn * w)
		leaf.append_array(side)
		_poly(ci, leaf, Color("#3fbf5a") if k % 2 == 0 else Color("#4fd068"), OUT, 4.0)
	for k in 3:
		ci.draw_circle(top + Vector2(-10 + k * 10, 8) * s, 9.0 * s, OUT)
		ci.draw_circle(top + Vector2(-10 + k * 10, 8) * s, 6.5 * s, Color("#8e5a31"))


func _bush(ci: CanvasItem, p: Vector2, s: float) -> void:
	_shadow(ci, p, 40.0 * s)
	for b in [[-22, -20, 22], [0, -32, 28], [24, -20, 22]]:
		ci.draw_circle(p + Vector2(b[0], b[1]) * s, (b[2] + 4) * s, OUT)
	for b in [[-22, -20, 22], [0, -32, 28], [24, -20, 22]]:
		ci.draw_circle(p + Vector2(b[0], b[1]) * s, b[2] * s, Color("#3caf4f"))
	ci.draw_circle(p + Vector2(-6, -40) * s, 9.0 * s, Color("#5cd06a"))


func _flowers(ci: CanvasItem, p: Vector2, s: float) -> void:
	var cols := [Color("#ff6b8a"), Color("#ffd23f"), Color("#ffffff"), Color("#b98cff")]
	for k in 5:
		var q := p + Vector2(sin(k * 2.4) * 22.0, cos(k * 1.7) * 12.0) * s
		var col: Color = cols[(k + int(p.x)) % 4]
		ci.draw_line(q, q + Vector2(0, 10) * s, Color("#2f8a3c"), 3.0)
		for j in 5:
			var a := j * TAU / 5.0
			ci.draw_circle(q + Vector2(cos(a), sin(a)) * 5.0 * s, 4.0 * s, col)
		ci.draw_circle(q, 3.0 * s, Color("#ffb020"))


func _rock(ci: CanvasItem, p: Vector2, s: float) -> void:
	_shadow(ci, p, 36.0 * s)
	var poly := PackedVector2Array([p + Vector2(-34, 0) * s, p + Vector2(-28, -26) * s, p + Vector2(-6, -40) * s,
		p + Vector2(22, -34) * s, p + Vector2(36, -8) * s, p + Vector2(30, 2) * s])
	_poly(ci, poly, Color("#a9b2c3"), OUT, 5.0)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-22, -24) * s, p + Vector2(-6, -34) * s, p + Vector2(8, -28) * s, p + Vector2(-12, -18) * s]), Color("#c9d0dc"))


func _shell(ci: CanvasItem, p: Vector2, s: float) -> void:
	var col := Color("#ff9ab0") if int(p.x) % 2 == 0 else Color("#fff1d6")
	var pts := PackedVector2Array([p + Vector2(-14, 0) * s])
	for k in 9:
		var a := PI + k * PI / 8.0
		pts.append(p + Vector2(cos(a) * 14.0, sin(a) * 14.0 - 4.0) * s)
	_poly(ci, pts, col, OUT, 3.0)
	for k in 3:
		ci.draw_line(p + Vector2(0, -1) * s, p + Vector2(-8 + k * 8, -14) * s, col.darkened(0.25), 2.0)


func _starfish(ci: CanvasItem, p: Vector2, s: float) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI / 2.0 + k * PI / 5.0 + p.x
		pts.append(p + Vector2(cos(a), sin(a) * 0.8) * (16.0 if k % 2 == 0 else 7.0) * s)
	_poly(ci, pts, Color("#ff8c5a"), OUT, 3.0)


func _tree(ci: CanvasItem, p: Vector2, s: float) -> void:
	_shadow(ci, p, 52.0 * s)
	ci.draw_rect(Rect2(p + Vector2(-13, -60) * s, Vector2(26, 60) * s), OUT)
	ci.draw_rect(Rect2(p + Vector2(-9, -60) * s, Vector2(18, 58) * s), Color("#9b6a3e"))
	var blobs := [[-30, -80, 34], [28, -82, 34], [0, -112, 42], [-14, -96, 34], [16, -98, 32]]
	for b in blobs:
		ci.draw_circle(p + Vector2(b[0], b[1]) * s, (b[2] + 5) * s, OUT)
	for b in blobs:
		ci.draw_circle(p + Vector2(b[0], b[1]) * s, b[2] * s, Color("#2f9e48"))
	ci.draw_circle(p + Vector2(-12, -118) * s, 16.0 * s, Color("#47bd5d"))
	ci.draw_circle(p + Vector2(18, -96) * s, 10.0 * s, Color("#47bd5d"))
	if int(p.x * 7.0) % 3 == 0:
		for k in 3:
			ci.draw_circle(p + Vector2(-20 + k * 18, -90 + (k % 2) * 16) * s, 6.0 * s, Color("#f04650"))


func _pine(ci: CanvasItem, p: Vector2, s: float) -> void:
	_shadow(ci, p, 40.0 * s)
	ci.draw_rect(Rect2(p + Vector2(-9, -30) * s, Vector2(18, 30) * s), Color("#8a5a33"))
	for k in 3:
		var y := -30.0 - k * 38.0
		var w := 52.0 - k * 12.0
		var tri := PackedVector2Array([p + Vector2(-w, y) * s, p + Vector2(w, y) * s, p + Vector2(0, y - 62.0) * s])
		_poly(ci, tri, Color("#2b8c4a") if k % 2 == 0 else Color("#33a056"), OUT, 5.0)


func _mushroom(ci: CanvasItem, p: Vector2, s: float) -> void:
	_shadow(ci, p, 40.0 * s)
	ci.draw_rect(Rect2(p + Vector2(-17, -54) * s, Vector2(34, 54) * s), OUT)
	ci.draw_rect(Rect2(p + Vector2(-13, -54) * s, Vector2(26, 52) * s), Color("#f7ecd6"))
	var cap := PackedVector2Array()
	for k in 17:
		var a := PI + k * PI / 16.0
		cap.append(p + Vector2(cos(a) * 58.0, sin(a) * 46.0 - 50.0) * s)
	_poly(ci, cap, Color("#f04650"), OUT, 6.0)
	for d in [[-30, -66, 10], [0, -82, 12], [28, -64, 9], [-10, -60, 6]]:
		ci.draw_circle(p + Vector2(d[0], d[1]) * s, d[2] * s, Color.WHITE)
	ci.draw_circle(p + Vector2(-6, -32) * s, 4.0 * s, OUT)
	ci.draw_circle(p + Vector2(6, -32) * s, 4.0 * s, OUT)


func _hut(ci: CanvasItem, p: Vector2, s: float) -> void:
	_shadow(ci, p, 90.0 * s)
	ci.draw_rect(Rect2(p + Vector2(-62, -80) * s, Vector2(124, 80) * s), OUT)
	ci.draw_rect(Rect2(p + Vector2(-56, -76) * s, Vector2(112, 74) * s), Color("#e7c27f"))
	for k in 7:
		ci.draw_line(p + Vector2(-48 + k * 16, -76) * s, p + Vector2(-48 + k * 16, -2) * s, Color("#c9a061"), 3.0)
	ci.draw_rect(Rect2(p + Vector2(-16, -52) * s, Vector2(32, 52) * s), Color("#7a4a2a"))
	var roof := PackedVector2Array([p + Vector2(-90, -70) * s, p + Vector2(90, -70) * s, p + Vector2(0, -150) * s])
	_poly(ci, roof, Color("#d9a24a"), OUT, 6.0)
	for k in 5:
		ci.draw_line(p + Vector2(0, -150) * s, p + Vector2(-80 + k * 40, -72) * s, Color("#b9822f"), 3.0)


func _house(ci: CanvasItem, p: Vector2, s: float) -> void:
	_shadow(ci, p, 90.0 * s)
	ci.draw_rect(Rect2(p + Vector2(-60, -84) * s, Vector2(120, 84) * s), OUT)
	ci.draw_rect(Rect2(p + Vector2(-55, -80) * s, Vector2(110, 78) * s), Color("#fff1d6"))
	ci.draw_rect(Rect2(p + Vector2(-14, -50) * s, Vector2(28, 50) * s), Color("#9b6a3e"))
	ci.draw_rect(Rect2(p + Vector2(22, -64) * s, Vector2(24, 22) * s), Color("#7fd0ff"))
	var roof := PackedVector2Array([p + Vector2(-78, -78) * s, p + Vector2(78, -78) * s, p + Vector2(0, -150) * s])
	_poly(ci, roof, Color("#f04650"), OUT, 6.0)


func _mushroom_house(ci: CanvasItem, p: Vector2, s: float) -> void:
	_shadow(ci, p, 90.0 * s)
	ci.draw_rect(Rect2(p + Vector2(-48, -90) * s, Vector2(96, 90) * s), OUT)
	ci.draw_rect(Rect2(p + Vector2(-43, -88) * s, Vector2(86, 86) * s), Color("#f7ecd6"))
	ci.draw_rect(Rect2(p + Vector2(-14, -50) * s, Vector2(28, 50) * s), Color("#9b6a3e"))
	ci.draw_circle(p + Vector2(22, -64) * s, 10.0 * s, Color("#7fd0ff"))
	var cap := PackedVector2Array()
	for k in 21:
		var a := PI + k * PI / 20.0
		cap.append(p + Vector2(cos(a) * 100.0, sin(a) * 74.0 - 84.0) * s)
	_poly(ci, cap, Color("#f04650"), OUT, 7.0)
	for d in [[-52, -104, 16], [0, -134, 20], [50, -102, 15], [-20, -96, 9], [26, -120, 8]]:
		ci.draw_circle(p + Vector2(d[0], d[1]) * s, d[2] * s, Color.WHITE)


func _windmill(ci: CanvasItem, p: Vector2, s: float) -> void:
	_shadow(ci, p, 60.0 * s)
	var body := PackedVector2Array([p + Vector2(-40, 0) * s, p + Vector2(40, 0) * s, p + Vector2(26, -140) * s, p + Vector2(-26, -140) * s])
	_poly(ci, body, Color("#fff1d6"), OUT, 6.0)
	var roof := PackedVector2Array([p + Vector2(-34, -136) * s, p + Vector2(34, -136) * s, p + Vector2(0, -180) * s])
	_poly(ci, roof, Color("#4b87f5"), OUT, 6.0)
	ci.draw_rect(Rect2(p + Vector2(-12, -40) * s, Vector2(24, 40) * s), Color("#9b6a3e"))
	var hub := p + Vector2(0, -132) * s
	for k in 4:
		var a := t * 1.2 + k * PI / 2.0
		var d := Vector2(cos(a), sin(a))
		var nn := Vector2(-d.y, d.x)
		var blade := PackedVector2Array([hub + nn * 6.0 * s, hub + d * 96.0 * s + nn * 6.0 * s, hub + d * 96.0 * s + nn * 26.0 * s, hub + d * 20.0 * s + nn * 26.0 * s])
		_poly(ci, blade, Color("#e8e2d6"), OUT, 4.0)
	ci.draw_circle(hub, 9.0 * s, OUT)
