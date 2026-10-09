extends Node2D
## Le décor de la grande île volante : village, forêt, lac, château, volcan et plage.
## Presque tout est dessiné une seule fois ; l'eau, la lave, la fumée et les nuages bougent.

const OUT := Color(0.16, 0.2, 0.12, 0.16)   # bord très doux (style pastel, sans contour)
const LAKE_C := Vector2(820, 750)
const LAKE_R := Vector2(300, 225)
const CASTLE := Vector2(1520, 800)      # pied du château
const VOLCANO := Vector2(3080, 900)     # pied du volcan
const LAGOON_C := Vector2(3120, 1820)
const LAGOON_R := Vector2(285, 215)
const POND_C := Vector2(770, 1910)
const POND_R := Vector2(150, 98)
const LAVA_C := Vector2(2790, 1170)
const STATUE := Vector2(2060, 1660)
const SHOP := Vector2(1705, 2578)
const BANK := Vector2(1660, 2070)
const TOLL := Vector2(790, 1195)

# chemins : [bord, remplissage, milieu] — clairs et bien contrastés pour qu'on les lise d'un coup d'œil
const PATH_STYLE := {
	"village": [Color("#c49a6c"), Color("#fff0cf"), Color("#fff8e8")],
	"foret": [Color("#9c6b3f"), Color("#f3d8a4"), Color("#fbe8c4")],
	"lac": [Color("#b88e57"), Color("#f7e2b0"), Color("#fff1d2")],
	"chateau": [Color("#8f8a84"), Color("#ecE8e1"), Color("#f8f6f2")],
	"volcan": [Color("#4a3b36"), Color("#d2bdb0"), Color("#e3d6cd")],
	"plage": [Color("#b07a45"), Color("#f2cf9a"), Color("#f9e0b8")],
}

const SPACE_COL := {
	"B": Color("#4b87f5"), "R": Color("#f04650"), "E": Color("#84cb33"), "C": Color("#ff9a2e"),
	"I": Color("#22b8cf"), "D": Color("#8a4fd8"), "T": Color("#3a3446"), "K": Color("#f2b705"),
	"H": Color("#ff6fb5"), "P": Color("#6dae23"), "S": Color("#ffffff"),
	"W": Color("#b8322a"), "G": Color("#6c5fa8"),
}

var rng := RandomNumberGenerator.new()
var t := 0.0
var layers := {}
var coast: PackedVector2Array
var inner: PackedVector2Array
var props: Array = []          # [pos, kind, scale, flip]
var streams: Array = []        # polylignes d'eau
var falls: Array = []          # cascades [x, y]
var ash: PackedVector2Array
var sand: PackedVector2Array
var forest: PackedVector2Array
var grid := PackedByteArray()  # 1 = pas de décor ici (chemins, eau, monuments)
var gw := 0
var gh := 0
const CELL := 20.0
var isles: Array = []
var shop_links: Array = []      # [cabane, case boutique]


func _ready() -> void:
	rng.seed = 4242
	BoardMap.build()
	coast = BoardMap.coast()
	inner = _offset(coast, -70.0)
	for n in ["back", "clouds", "ground", "water", "props", "top"]:
		var l := Node2D.new()
		l.z_index = layers.size() - 2
		add_child(l)
		layers[n] = l
	(layers["ground"] as Node2D).texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	(layers["back"] as Node2D).draw.connect(_draw_back)
	(layers["clouds"] as Node2D).draw.connect(_draw_clouds)
	(layers["ground"] as Node2D).draw.connect(_draw_ground)
	(layers["water"] as Node2D).draw.connect(_draw_water)
	(layers["props"] as Node2D).draw.connect(_draw_props)
	(layers["top"] as Node2D).draw.connect(_draw_top)
	ash = _clip(_blob(Vector2(3170, 760), Vector2(720, 600), 22, 0.08))
	sand = _clip(_blob(Vector2(3260, 1980), Vector2(760, 620), 22, 0.08))
	forest = _clip(_blob(Vector2(720, 1880), Vector2(600, 560), 22, 0.1))
	var s1 := [Vector2(880, 950), Vector2(945, 1170), Vector2(990, 1330), Vector2(1015, 1470), Vector2(935, 1650), Vector2(820, 1830)]
	var s2 := [Vector2(745, 1990), Vector2(705, 2200), Vector2(692, 2400)]
	var s3 := [Vector2(3150, 2020), Vector2(3165, 2250), Vector2(3175, 2450)]
	for x in [692.0, 3175.0]:
		var by := _bottom_y(coast, x)
		falls.append([x, by])
		(s2 if x < 1000.0 else s3).append(Vector2(x, by + 40.0))
	for s in [s1, s2, s3]:
		streams.append(BoardMap.smooth(s, 10))
	isles = [[Vector2(-330, 520), 190.0], [Vector2(4330, 820), 210.0], [Vector2(4270, 2280), 150.0], [Vector2(-280, 2050), 160.0], [Vector2(2000, -330), 140.0]]
	_preload_textures()
	_add_statue_sprite()
	_build_grid()
	_place_props()


func _process(delta: float) -> void:
	t += delta
	(layers["clouds"] as Node2D).queue_redraw()
	(layers["water"] as Node2D).queue_redraw()
	(layers["top"] as Node2D).queue_redraw()


# ------------------------------------------------------------------ outils
func _offset(src: PackedVector2Array, d: float) -> PackedVector2Array:
	var polys := Geometry2D.offset_polygon(src, d, Geometry2D.JOIN_ROUND)
	var best := PackedVector2Array()
	for p in polys:
		if p.size() > best.size():
			best = p
	return best


func _clip(poly: PackedVector2Array) -> PackedVector2Array:
	var res := Geometry2D.intersect_polygons(poly, inner)
	var best := PackedVector2Array()
	for p in res:
		if p.size() > best.size():
			best = p
	return best


func _blob(c: Vector2, r: Vector2, n := 16, jitter := 0.12) -> PackedVector2Array:
	var p := PackedVector2Array()
	for k in n:
		var a := k * TAU / n
		p.append(c + Vector2(cos(a) * r.x, sin(a) * r.y) * (1.0 + rng.randf_range(-jitter, jitter)))
	return BoardMap.smooth(Array(p), 6, true)


func _ell(c: Vector2, r: Vector2, n := 48) -> PackedVector2Array:
	var p := PackedVector2Array()
	for k in n:
		var a := k * TAU / n
		p.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return p


func _poly(ci: CanvasItem, poly: PackedVector2Array, fill: Color, line := OUT, w := 8.0) -> void:
	if poly.size() < 3:
		return
	ci.draw_colored_polygon(poly, fill)
	if w > 0.0:
		var l := poly.duplicate()
		l.append(poly[0])
		ci.draw_polyline(l, line, w, true)


func _ellipse(ci: CanvasItem, c: Vector2, r: Vector2, col: Color) -> void:
	ci.draw_set_transform(c, 0.0, Vector2(1.0, r.y / r.x))
	ci.draw_circle(Vector2.ZERO, r.x, col)
	ci.draw_set_transform(Vector2.ZERO)


func _closed(c: PackedVector2Array) -> PackedVector2Array:
	var l := c.duplicate()
	l.append(c[0])
	return l


func _bottom_y(poly: PackedVector2Array, x: float) -> float:
	var best := -1e9
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if (a.x - x) * (b.x - x) <= 0.0 and absf(b.x - a.x) > 0.001:
			var k := (x - a.x) / (b.x - a.x)
			best = maxf(best, lerpf(a.y, b.y, k))
	return best


func _dist_line(p: Vector2, line: PackedVector2Array) -> float:
	var best := 1e9
	for i in range(line.size() - 1):
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1]).distance_to(p))
	return best


func _in_ell(p: Vector2, c: Vector2, r: Vector2) -> bool:
	var d := (p - c) / r
	return d.length_squared() <= 1.0


## La statue dorée du perso couronné (un shader transforme le perso vert en or).
func _add_statue_sprite() -> void:
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = clamp(dot(c.rgb, vec3(0.299, 0.587, 0.114)) * 1.3, 0.0, 1.0);
	vec3 dark = vec3(0.48, 0.29, 0.05);
	vec3 mid = vec3(0.89, 0.66, 0.12);
	vec3 hi = vec3(1.0, 0.95, 0.66);
	vec3 g = l < 0.5 ? mix(dark, mid, l * 2.0) : mix(mid, hi, (l - 0.5) * 2.0);
	COLOR = vec4(g, c.a);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var spr := Sprite2D.new()
	spr.texture = load("res://assets/chars/vert/idle.png")
	spr.material = mat
	spr.centered = false
	spr.offset = Vector2(-128, -256)
	spr.position = STATUE + Vector2(0, -84)
	spr.scale = Vector2(0.95, 0.95)
	(layers["props"] as Node2D).add_child(spr)
	var crown := Node2D.new()
	crown.draw.connect(func(): _crown(crown, STATUE + Vector2(0, -292)))
	(layers["props"] as Node2D).add_child(crown)


# ------------------------------------------------------------------ zones interdites au décor
func _build_grid() -> void:
	gw = int(BoardMap.SIZE.x / CELL) + 1
	gh = int(BoardMap.SIZE.y / CELL) + 1
	grid.resize(gw * gh)
	grid.fill(0)
	for c in BoardMap.curves:
		var line: PackedVector2Array = c[0]
		for i in line.size():
			_mark(line[i], 135.0)
	for i in BoardMap.count():
		_mark(BoardMap.pos(i), 150.0)
	for s in streams:
		var sl: PackedVector2Array = s
		for p in sl:
			_mark(p, 58.0)
	_mark_ell(LAKE_C, LAKE_R + Vector2(40, 40))
	_mark_ell(Vector2(CASTLE.x, CASTLE.y - 90), Vector2(350, 260))
	_mark_ell(Vector2(VOLCANO.x, VOLCANO.y - 140), Vector2(330, 260))
	_mark_ell(LAGOON_C, LAGOON_R + Vector2(50, 50))
	_mark_ell(POND_C, POND_R + Vector2(36, 36))
	_mark_ell(LAVA_C, Vector2(140, 90))
	_mark_ell(STATUE, Vector2(190, 120))
	_mark_ell(SHOP + Vector2(0, -50), Vector2(150, 90))
	_mark_ell(BANK + Vector2(0, -60), Vector2(140, 100))
	_mark_ell(Vector2(1953, 2290), Vector2(180, 130))
	_mark_ell(TOLL, Vector2(60, 60))
	for f in _fields():
		var r: Rect2 = f
		_mark_ell(r.get_center(), r.size / 2.0 + Vector2(40, 40))


func _mark(p: Vector2, r: float) -> void:
	var x0 := maxi(0, int((p.x - r) / CELL))
	var x1 := mini(gw - 1, int((p.x + r) / CELL))
	var y0 := maxi(0, int((p.y - r) / CELL))
	var y1 := mini(gh - 1, int((p.y + r) / CELL))
	for gy in range(y0, y1 + 1):
		for gx in range(x0, x1 + 1):
			if Vector2(gx * CELL + CELL / 2.0, gy * CELL + CELL / 2.0).distance_to(p) <= r:
				grid[gy * gw + gx] = 1


func _mark_ell(c: Vector2, r: Vector2) -> void:
	for gy in range(maxi(0, int((c.y - r.y) / CELL)), mini(gh - 1, int((c.y + r.y) / CELL)) + 1):
		for gx in range(maxi(0, int((c.x - r.x) / CELL)), mini(gw - 1, int((c.x + r.x) / CELL)) + 1):
			if _in_ell(Vector2(gx * CELL + CELL / 2.0, gy * CELL + CELL / 2.0), c, r):
				grid[gy * gw + gx] = 1


func _free(p: Vector2) -> bool:
	var gx := int(p.x / CELL)
	var gy := int(p.y / CELL)
	if gx < 0 or gy < 0 or gx >= gw or gy >= gh:
		return false
	return grid[gy * gw + gx] == 0


func _fields() -> Array:
	return [Rect2(1420, 1440, 300, 170), Rect2(2230, 1230, 280, 160)]


func zone_at(p: Vector2) -> String:
	if Geometry2D.is_point_in_polygon(p, ash):
		return "volcan"
	if Geometry2D.is_point_in_polygon(p, sand):
		return "plage"
	if Geometry2D.is_point_in_polygon(p, forest) or (p.x < 330.0 and p.y > 1100.0):
		return "foret"
	if _in_ell(p, LAKE_C, LAKE_R * 1.9):
		return "lac"
	if p.y < 330.0:
		return "nord"
	if p.y > 1980.0 and p.x > 1300.0 and p.x < 2750.0:
		return "village"
	if _in_ell(p, CASTLE + Vector2(0, -80), Vector2(520, 420)):
		return "chateau"
	return "prairie"


# ------------------------------------------------------------------ placement du décor
# familles de sprites (packs Kenney « Background Elements » et « Foliage ») et hauteur visée
const SPR := {
	"tree": ["deco/tree", "deco/treeLong", "deco/foliage_007", "deco/foliage_008", "deco/foliage_009", "deco/foliage_010", "deco/foliage_011", "deco/foliage_039", "deco/foliage_041"],
	"tree_autumn": ["deco/treeOrange", "deco/treeLongOrange", "deco/foliage_013", "deco/foliage_014", "deco/foliage_016", "deco/foliage_045", "deco/foliage_047"],
	"pine": ["deco/treePine", "deco/foliage_005", "deco/foliage_006", "deco/foliage_037", "deco/foliage_012"],
	"small_tree": ["deco/treeSmall_green1", "deco/treeSmall_green2", "deco/treeSmall_green3", "deco/treeSmall_greenAlt1", "deco/treeSmall_greenAlt2", "deco/treeSmall_greenAlt3"],
	"small_autumn": ["deco/treeSmall_orange1", "deco/treeSmall_orange2", "deco/treeSmall_orange3"],
	"palm": ["deco/treePalm"],
	"dead": ["deco/treeDead", "deco/foliage_023", "deco/foliage_024", "deco/foliage_025"],
	"bush": ["deco/bush1", "deco/bushAlt1", "deco/foliage_050", "deco/foliage_051", "deco/foliage_052", "deco/foliage_053"],
	"grass": ["deco/bush2", "deco/bush3", "deco/bush4", "deco/bushAlt2", "deco/bushAlt3", "deco/foliage_019", "deco/foliage_020", "deco/foliage_021"],
	"grass_orange": ["deco/bushOrange1", "deco/bushOrange2"],
	"flower": ["deco/foliage_001", "deco/foliage_002", "deco/foliage_003", "deco/foliage_004"],
	"rock": ["deco/foliage_054", "deco/foliage_055", "deco/foliage_056", "deco/foliage_057", "deco/foliage_058", "deco/foliage_059"],
	"house": ["deco/house1", "deco/house2", "deco/houseAlt1", "deco/houseAlt2"],
	"house_small": ["deco/houseSmall1", "deco/houseSmall2", "deco/houseSmallAlt1", "deco/houseSmallAlt2"],
}
const SPR_H := {"tree": 180.0, "tree_autumn": 180.0, "pine": 210.0, "small_tree": 95.0, "small_autumn": 95.0, "palm": 215.0,
	"dead": 160.0, "bush": 52.0, "grass": 44.0, "grass_orange": 44.0, "flower": 34.0, "rock": 48.0, "house": 205.0, "house_small": 95.0}
const TALL := ["tree", "tree_autumn", "pine", "palm", "dead", "small_tree", "small_autumn", "house"]
const ZONE_MIX := {
	"foret": [["tree", 34], ["pine", 30], ["tree_autumn", 14], ["mushroom", 10], ["bush", 12]],
	"lac": [["tree", 45], ["bush", 35], ["rock", 20]],
	"nord": [["pine", 65], ["rock", 20], ["small_tree", 15]],
	"village": [["bush", 40], ["small_tree", 60]],
	"chateau": [["bush", 50], ["small_tree", 50]],
	"volcan": [["dead", 40], ["vrock", 60]],
	"plage": [["palm", 70], ["shell", 15], ["starfish", 15]],
	"prairie": [["tree", 45], ["small_tree", 20], ["bush", 35]],
}

var _tc := {}


## Les textures doivent être chargées AVANT le dessin (sinon elles sortent blanches dans les couches dessinées une seule fois).
func _preload_textures() -> void:
	for fam in SPR:
		for n in SPR[fam]:
			_t(n)
	for n in ["deco/shop", "deco/bank", "deco/castleSmallAlt", "deco/towerAlt", "deco/towerSmallAlt", "deco/castleWallAlt", "deco/fence", "deco/cloud1", "deco/cloud2",
			"deco/cloud3", "deco/cloud5", "deco/cloud7", "tiles/flag_red_a", "tiles/flag_blue_a", "tiles/coin_gold", "deco/tex_tile_68", "deco/tex_tile_73"]:
		_t(n)
	for w in ["Beige", "Gray"]:
		for part in ["", "TopLeft", "TopMid", "TopRight", "MidLeft", "MidRight", "BottomLeft", "BottomMid", "BottomRight"]:
			_t("buildings/house%s%s" % [w, part])
	for r in ["Red", "Grey"]:
		for part in ["TopLeft", "TopMid", "TopRight"]:
			_t("buildings/roof%s%s" % [r, part])
	for n in ["windowCheckered", "signHangingCoin", "awningRed", "windowLow", "doorKnob", "windowLowCheckered", "windowHighTop", "clock",
			"windowHighBottom", "doorTop", "doorLock"]:
		_t("buildings/" + n)
	for k in SPACE_ICON:
		_icon(str(SPACE_ICON[k]))


func _t(n: String) -> Texture2D:
	if not _tc.has(n):
		_tc[n] = load("res://assets/%s.png" % n)
	return _tc[n]


## Ajoute un sprite au décor (pied du sprite en p), avec une taille visée.
func _add_spr(p: Vector2, fam: String, name := "", hmul := 1.0, mod := Color.WHITE, flip := -1) -> bool:
	var list: Array = SPR.get(fam, [])
	if name == "":
		if list.is_empty():
			return false
		name = list[rng.randi() % list.size()]
	var tx := _t(name)
	if tx == null:
		return false
	var sz := tx.get_size()
	var sc: float = float(SPR_H.get(fam, 100.0)) * hmul * rng.randf_range(0.88, 1.12) / sz.y
	var fl := rng.randf() < 0.5 if flip < 0 else flip == 1
	props.append([p, "spr", sc, fl, name, sz.x * sc * 0.42, mod])
	return true


func _pick(mix: Array) -> String:
	var total := 0.0
	for m in mix:
		total += float(m[1])
	var r := rng.randf() * total
	for m in mix:
		r -= float(m[1])
		if r <= 0.0:
			return str(m[0])
	return str(mix[0][0])


## Une cabane-boutique à côté de chaque case boutique (celle du village est déjà placée).
func _place_shops() -> void:
	# points des chemins (pour garder la cabane à distance)
	var pts := PackedVector2Array()
	for c in BoardMap.curves:
		var line: PackedVector2Array = c[0]
		for j in range(0, line.size(), 2):
			pts.append(line[j])
	for i in BoardMap.count():
		pts.append(BoardMap.pos(i))
	for i in BoardMap.count():
		if BoardMap.kind(i) != "H" or BoardMap.pos(i).distance_to(SHOP) < 500.0:
			continue
		var p := BoardMap.pos(i)
		var best := Vector2.ZERO
		for dist in [190.0, 230.0, 270.0, 320.0, 380.0]:
			for k in 16:
				var ang := TAU * k / 16.0 + PI / 2.0
				var foot: Vector2 = p + Vector2(cos(ang), sin(ang)) * float(dist)
				var ok := true
				for o: Vector2 in [Vector2(0, 0), Vector2(-85, -20), Vector2(85, -20), Vector2(0, -100), Vector2(-75, -150), Vector2(75, -150), Vector2(0, -190)]:
					var q: Vector2 = foot + o
					if not Geometry2D.is_point_in_polygon(q, inner) or _in_ell(q, LAKE_C, LAKE_R + Vector2(40, 40)) or _in_ell(q, LAGOON_C, LAGOON_R + Vector2(60, 60)) \
							or _in_ell(q, CASTLE + Vector2(0, -90), Vector2(360, 260)) or _in_ell(q, POND_C, POND_R + Vector2(40, 40)):
						ok = false
						break
					for pp in pts:
						if pp.distance_squared_to(q) < 78.0 * 78.0:
							ok = false
							break
					if not ok:
						break
				if ok:
					best = foot
					break
			if best != Vector2.ZERO:
				break
		if best == Vector2.ZERO:
			continue
		props.append([best, "hut", 1.0, false])
		_mark_ell(best + Vector2(0, -80), Vector2(130, 120))
		# petit panneau-flèche vers la case
		shop_links.append([best, p])


func _place_props() -> void:
	# monuments
	props.append([CASTLE, "castle", 1.0, false])
	props.append([VOLCANO, "volcano", 1.0, false])
	props.append([STATUE, "statue", 1.0, false])
	props.append([SHOP, "shop", 1.0, false])
	_place_shops()
	props.append([BANK, "bank", 1.0, false])
	props.append([TOLL, "toll", 1.0, false])
	props.append([Vector2(1953, 2236), "start_arch", 1.0, false])
	props.append([Vector2(3790, 2300), "lighthouse", 1.0, false])
	props.append([Vector2(1880, 1480), "windmill", 1.15, false])
	props.append([Vector2(LAKE_C.x + 90, LAKE_C.y + 20), "boat", 1.0, false])
	props.append([Vector2(LAGOON_C.x - 120, LAGOON_C.y + 60), "boat", 0.8, true])
	var houses := ["deco/houseAlt1", "deco/house1", "deco/houseAlt2", "deco/house2", "deco/houseAlt1", "deco/house2", "deco/houseAlt2", "deco/house1"]
	var hp := [Vector2(1450, 2560), Vector2(2000, 2090), Vector2(2190, 2115), Vector2(2380, 2150), Vector2(1985, 2595), Vector2(2215, 2600),
		Vector2(2445, 2585), Vector2(1280, 2505)]
	for i in hp.size():
		_add_spr(hp[i], "house", houses[i], 0.95 if i % 3 == 0 else 1.0, Color.WHITE, i % 2)
	for lp in [Vector2(1860, 2160), Vector2(2080, 2180)]:
		props.append([lp, "lamp", 1.0, false])
	for b in [Vector2(1845, 2560), Vector2(1575, 2585)]:
		props.append([b, "crate", 1.0, rng.randf() < 0.5])
	for fl in [Vector2(1250, 700), Vector2(1790, 700), Vector2(1330, 990), Vector2(1720, 990)]:
		props.append([fl, "banner", 1.0, false])
	for u in [Vector2(2960, 2100), Vector2(3330, 2110), Vector2(3420, 1640)]:
		props.append([u, "umbrella", 1.0, rng.randf() < 0.5])
	for r in [Vector2(LAKE_C.x - 300, LAKE_C.y + 40), Vector2(LAKE_C.x + 290, LAKE_C.y - 90)]:
		_add_spr(r, "grass", "", 1.3)

	var want := {"foret": 75, "lac": 14, "nord": 18, "village": 6, "chateau": 6, "volcan": 18, "plage": 18, "prairie": 46}
	var count := {}
	for k in want:
		count[k] = 0
	var tries := 0
	while tries < 30000:
		tries += 1
		var p := Vector2(rng.randf_range(40, BoardMap.SIZE.x - 40), rng.randf_range(40, BoardMap.SIZE.y - 40))
		if not Geometry2D.is_point_in_polygon(p, inner) or not _free(p):
			continue
		var z := zone_at(p)
		if int(count[z]) >= int(want[z]):
			continue
		var kind := _pick(ZONE_MIX[z])
		# les grands décors ne doivent pas cacher les chemins avec leur feuillage
		var h: float = float(SPR_H.get(kind, 60.0))
		if kind == "mushroom":
			h = 110.0
		if h > 80.0:
			var bad := false
			for k in [0.35, 0.7, 1.0]:
				if not _free(p + Vector2(0, -h * k)):
					bad = true
			if not _free(p + Vector2(-45, -h * 0.6)) or not _free(p + Vector2(45, -h * 0.6)):
				bad = true
			if bad:
				continue
		var small := kind in ["flower", "shell", "starfish", "grass", "grass_orange", "rock"]
		var min_d := 90.0 if small else 125.0
		if z == "foret" and kind in ["tree", "pine", "tree_autumn"]:
			min_d = 95.0
		var ok := true
		for q in props:
			if (q[0] as Vector2).distance_to(p) < min_d:
				ok = false
				break
		if not ok:
			continue
		match kind:
			"mushroom", "shell", "starfish", "fence":
				props.append([p, kind, rng.randf_range(0.85, 1.2), rng.randf() < 0.5])
			"vrock":
				_add_spr(p, "rock", "", rng.randf_range(0.9, 1.5), Color("#8a7266"))
			"flower":
				for f in 3:
					_add_spr(p + Vector2(f * 18 - 18, (f % 2) * 8), "flower", "", rng.randf_range(0.8, 1.1))
			_:
				_add_spr(p, kind)
		count[z] = int(count[z]) + 1
	props.sort_custom(func(a, b): return (a[0] as Vector2).y < (b[0] as Vector2).y)


# ------------------------------------------------------------------ fond : ciel et nuages
func _draw_back() -> void:
	var ci: Node2D = layers["back"]
	var r := RandomNumberGenerator.new()
	r.seed = 11
	for i in 40:
		var c := Vector2(r.randf_range(-1500, BoardMap.SIZE.x + 1500), r.randf_range(BoardMap.SIZE.y - 100, BoardMap.SIZE.y + 1300))
		_cloud(ci, c, r.randf_range(1.6, 3.4), Color(1, 1, 1, 0.5))
	for isle in isles:
		_sky_island(ci, _blob(isle[0], Vector2(isle[1], isle[1] * 0.7), 14, 0.1), 0.5, false)


func _cloud(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var tx := _t("deco/cloud%d" % [1, 2, 3, 5, 7][int(absf(c.x * 0.37 + c.y * 0.11)) % 5])
	if tx:
		var sz := tx.get_size() * s * 0.9
		ci.draw_texture_rect(tx, Rect2(c - sz / 2.0, sz), false, col)


func _draw_clouds() -> void:
	var ci: Node2D = layers["clouds"]
	var r := RandomNumberGenerator.new()
	r.seed = 21
	var span := BoardMap.SIZE.x + 3000.0
	for i in 12:
		var x := fposmod(r.randf_range(0, span) + t * r.randf_range(10, 24), span) - 1500.0
		var c := Vector2(x, r.randf_range(-900, BoardMap.SIZE.y + 900))
		_cloud(ci, c, r.randf_range(1.4, 2.6), Color(1, 1, 1, 0.8))


# ------------------------------------------------------------------ sol
func _sky_island(ci: CanvasItem, top: PackedVector2Array, sc: float, big := true) -> void:
	var xmin := 1e9
	var xmax := -1e9
	for p in top:
		xmin = minf(xmin, p.x)
		xmax = maxf(xmax, p.x)
	var cliff_h := 110.0 * sc
	var n := 70 if big else 24
	var raw := []
	for k in n + 1:
		raw.append(_bottom_y(top, lerpf(xmin + 6.0, xmax - 6.0, k / float(n))))
	var by := []
	for k in n + 1:
		var m := -1e9
		for j in range(maxi(0, k - 4), mini(n, k + 4) + 1):
			m = maxf(m, float(raw[j]))
		by.append(m)
	var depth := 720.0 * sc
	var under := PackedVector2Array()
	for k in n + 1:
		under.append(Vector2(lerpf(xmin + 6.0, xmax - 6.0, k / float(n)), float(raw[k]) + cliff_h - 6.0))
	var tips := PackedVector2Array()
	for k in range(n, -1, -1):
		var x := lerpf(xmin + 6.0, xmax - 6.0, k / float(n))
		var u := k / float(n)
		var dep: float = depth * pow(sin(u * PI), 0.7) * (0.75 + 0.25 * sin(k * 1.7))
		tips.append(Vector2(x + sin(k * 2.3) * 10.0, float(by[k]) + cliff_h + dep))
	var rock := under.duplicate()
	rock.append_array(tips)
	_poly(ci, rock, Color("#7d5a3e"), OUT, 8.0)
	for f in [0.68, 0.38]:
		var band := under.duplicate()
		for k in range(n, -1, -1):
			var x := lerpf(xmin + 6.0, xmax - 6.0, k / float(n))
			var u := k / float(n)
			var dep: float = depth * pow(sin(u * PI), 0.7) * (0.75 + 0.25 * sin(k * 1.7)) * f
			band.append(Vector2(x, maxf(float(raw[k]) + cliff_h, float(by[k]) + cliff_h + dep - 20.0)))
		_poly(ci, band, Color("#916a48") if f > 0.5 else Color("#a87c52"), OUT, 0.0)
	for k in range(2, n - 1, 3):
		var x := lerpf(xmin, xmax, k / float(n))
		var y0 := float(by[k]) + cliff_h + depth * pow(sin(k / float(n) * PI), 0.7) * 0.3
		var ln := 50.0 + fmod(k * 37.0, 110.0) * sc
		ci.draw_line(Vector2(x, y0), Vector2(x + 6.0, y0 + ln), Color("#72a334"), 6.0 * sc + 1.0)
		ci.draw_circle(Vector2(x + 6.0, y0 + ln), 8.0 * sc + 2.0, Color("#8cc446"))
	var cliff := PackedVector2Array()
	for p in top:
		cliff.append(p + Vector2(0, cliff_h))
	_poly(ci, cliff, Color("#d98f5a"), OUT, 8.0)
	for k in 2:
		var bl := PackedVector2Array()
		for p in top:
			bl.append(p + Vector2(0, cliff_h * (0.42 + k * 0.28)))
		bl.append(bl[0])
		ci.draw_polyline(bl, Color("#c27a48"), 5.0, true)
	_poly(ci, top, Color("#a3db57"), OUT, 8.0)
	if not big:
		return
	var hi := _offset(top, -18.0)
	if hi.size() > 2:
		ci.draw_polyline(_closed(hi), Color("#baec70"), 10.0, true)


func _draw_ground() -> void:
	var ci: Node2D = layers["ground"]
	_sky_island(ci, coast, 1.0)
	# zones
	_poly(ci, forest, Color("#84c03c"), OUT, 0.0)
	_poly(ci, _offset(forest, -30.0), Color("#7ab336"), OUT, 0.0)
	_poly(ci, sand, Color("#efd08a"), OUT, 0.0)
	_poly(ci, _offset(sand, -26.0), Color("#f6dc9e"), OUT, 0.0)
	_tex_poly(ci, _offset(sand, -26.0), "deco/tex_tile_68", Color(1, 0.97, 0.9, 0.9), 1.6)
	_poly(ci, ash, Color("#9c8270"), OUT, 0.0)
	_poly(ci, _offset(ash, -30.0), Color("#8a7060"), OUT, 0.0)
	# champs
	for f in _fields():
		_field(ci, f)
	# château : colline, douves
	_poly(ci, _ell(CASTLE + Vector2(0, -90), Vector2(345, 245)), Color("#46a3e0"), Color("#2c7cc0"), 6.0)
	_tex_poly(ci, _ell(CASTLE + Vector2(0, -90), Vector2(342, 242)), "deco/tex_tile_73", Color(0.75, 0.9, 1.0, 0.8), 1.4)
	_poly(ci, _ell(CASTLE + Vector2(0, -90), Vector2(300, 205)), Color("#aadc63"), Color("#88ba44"), 6.0)
	_poly(ci, _ell(CASTLE + Vector2(0, -95), Vector2(250, 165)), Color("#d8d2c6"), Color("#b8b0a2"), 6.0)
	# volcan : coulée et bassin de lave
	ci.draw_polyline(PackedVector2Array([VOLCANO + Vector2(-110, -60), Vector2(2880, 1010), LAVA_C]), OUT, 54.0, true)
	ci.draw_polyline(PackedVector2Array([VOLCANO + Vector2(-110, -60), Vector2(2880, 1010), LAVA_C]), Color("#e8531f"), 42.0, true)
	_poly(ci, _ell(LAVA_C, Vector2(105, 62)), Color("#e8531f"), OUT, 7.0)
	# eau : lac, étang, lagon (sable autour)
	_poly(ci, _ell(LAKE_C, LAKE_R + Vector2(34, 30)), Color("#f2dfb0"), Color("#d9bf86"), 5.0)
	_poly(ci, _ell(LAKE_C, LAKE_R), Color("#3aa3e8"), Color("#2c7cc0"), 7.0)
	_tex_poly(ci, _ell(LAKE_C, LAKE_R - Vector2(4, 4)), "deco/tex_tile_73", Color(0.8, 0.93, 1.0, 0.95), 1.6)
	_poly(ci, _ell(POND_C, POND_R + Vector2(24, 20)), Color("#79a03e"), OUT, 0.0)
	_poly(ci, _ell(POND_C, POND_R), Color("#3aa3e8"), Color("#2c7cc0"), 6.0)
	_tex_poly(ci, _ell(POND_C, POND_R - Vector2(4, 4)), "deco/tex_tile_73", Color(0.8, 0.93, 1.0, 0.95), 1.4)
	_poly(ci, _ell(LAGOON_C, LAGOON_R + Vector2(56, 46)), Color("#fbe7b4"), Color("#e8c98a"), 4.0)
	_poly(ci, _ell(LAGOON_C, LAGOON_R), Color("#25c4d8"), Color("#1a95a8"), 7.0)
	_tex_poly(ci, _ell(LAGOON_C, LAGOON_R - Vector2(4, 4)), "deco/tex_tile_73", Color(0.75, 1.0, 0.98, 0.95), 1.6)
	# ruisseaux
	for s in streams:
		var sl: PackedVector2Array = s
		ci.draw_polyline(sl, Color("#2c7cc0"), 70.0, true)
		ci.draw_polyline(sl, Color("#4fb4f0"), 58.0, true)
		ci.draw_polyline(sl, Color("#8fd6fb"), 22.0, true)
	# places
	_plaza(ci, Vector2(1953, 2290), Vector2(200, 112))
	_plaza(ci, STATUE + Vector2(0, -10), Vector2(170, 96))
	# chemins
	for c in BoardMap.curves:
		_path(ci, c[0], str(c[1]))
	_bridges(ci)
	# cases
	for i in BoardMap.count():
		draw_space(ci, BoardMap.pos(i), BoardMap.kind(i))


## Polygone rempli avec une texture qui se répète (eau, sable).
func _tex_poly(ci: CanvasItem, poly: PackedVector2Array, tex: String, mod: Color, scale := 1.0) -> void:
	var tx := _t(tex)
	if tx == null or poly.size() < 3:
		return
	var uv := PackedVector2Array()
	var ts := tx.get_size() * scale
	for q in poly:
		uv.append(q / ts)
	ci.draw_colored_polygon(poly, mod, uv, tx)


func _speckles(ci: CanvasItem) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 6
	for i in 1400:
		var p := Vector2(r.randf_range(0, BoardMap.SIZE.x), r.randf_range(0, BoardMap.SIZE.y))
		if not _free(p) or not Geometry2D.is_point_in_polygon(p, inner):
			continue
		var z := zone_at(p)
		match z:
			"plage":
				ci.draw_circle(p, r.randf_range(2.5, 4.5), Color("#dcb46a"))
			"volcan":
				ci.draw_circle(p, r.randf_range(3, 6), Color("#6f5a4d"))
			_:
				var col := Color("#72a335") if z == "foret" else Color("#8ac143")
				ci.draw_arc(p, 7, PI * 1.1, PI * 1.9, 6, col, 3.0)
				ci.draw_arc(p + Vector2(10, 2), 6, PI * 1.1, PI * 1.9, 6, col, 3.0)


func _field(ci: CanvasItem, f: Rect2) -> void:
	var sk := Vector2(30, 0)
	var poly := PackedVector2Array([f.position + sk, f.position + Vector2(f.size.x, 0) + sk, f.end - sk, f.position + Vector2(0, f.size.y) - sk])
	_poly(ci, poly, Color("#b8763f"), OUT, 6.0)
	var rows := 6
	for k in rows:
		var u := (k + 0.5) / rows
		var a := poly[0].lerp(poly[3], u)
		var b := poly[1].lerp(poly[2], u)
		ci.draw_line(a + Vector2(10, 0), b - Vector2(10, 0), Color("#9a5f30"), 10.0)
		var n := int(a.distance_to(b) / 34.0)
		for j in n:
			var q := a.lerp(b, (j + 0.5) / n) + Vector2(0, -6)
			ci.draw_circle(q, 9.0, Color("#7cba31"))
			ci.draw_circle(q + Vector2(-2, -3), 4.0, Color("#b1e669"))


func _plaza(ci: CanvasItem, c: Vector2, r: Vector2) -> void:
	_poly(ci, _ell(c, r), Color("#d9cbb0"), Color("#b9a988"), 6.0)
	var rr := RandomNumberGenerator.new()
	rr.seed = int(c.x)
	for i in 60:
		var a := rr.randf() * TAU
		var d := sqrt(rr.randf()) * 0.9
		var p := c + Vector2(cos(a) * r.x * d, sin(a) * r.y * d)
		ci.draw_circle(p, rr.randf_range(7, 12), Color("#e8dcc4"))


func _path(ci: CanvasItem, line: PackedVector2Array, zone: String) -> void:
	var st: Array = PATH_STYLE.get(zone, PATH_STYLE["foret"])
	# ombre douce sous le chemin (effet passerelle)
	var sh := PackedVector2Array()
	for q in line:
		sh.append(q + Vector2(0, 10))
	ci.draw_polyline(sh, Color(0.1, 0.12, 0.05, 0.16), 124.0, true)
	ci.draw_polyline(line, st[0], 118.0, true)
	ci.draw_polyline(line, st[1], 100.0, true)
	ci.draw_polyline(line, Color(st[2], 0.8), 46.0, true)
	if zone == "plage":
		# planches discrètes
		var acc := 0.0
		for i in range(line.size() - 1):
			var a := line[i]
			var b := line[i + 1]
			var seg := a.distance_to(b)
			var d := (b - a).normalized()
			var nn := Vector2(-d.y, d.x)
			var s2 := 0.0
			while acc + seg - s2 >= 26.0:
				s2 += 26.0 - acc
				acc = 0.0
				var p := a + d * s2
				ci.draw_line(p - nn * 46.0, p + nn * 46.0, Color(st[0], 0.35), 2.0)
			acc += seg - s2


func _bridges(ci: CanvasItem) -> void:
	for c in BoardMap.curves:
		var line: PackedVector2Array = c[0]
		for s in streams:
			var sl: PackedVector2Array = s
			for i in range(0, line.size() - 1):
				var p := line[i]
				if _dist_line(p, sl) > 52.0:
					continue
				var d := (line[i + 1] - p).normalized()
				var nn := Vector2(-d.y, d.x)
				ci.draw_line(p - nn * 50.0, p + nn * 50.0, OUT, 18.0)
				ci.draw_line(p - nn * 46.0, p + nn * 46.0, Color("#c98a4e"), 12.0)
				if i % 4 == 0:
					for sd in [-1.0, 1.0]:
						ci.draw_circle(p + nn * 52.0 * sd, 10.0, OUT)
						ci.draw_circle(p + nn * 52.0 * sd, 6.5, Color("#8a5530"))


## Une case façon Mario Party : socle en pierre, pastille bombée et brillante, symbole en relief.
static func draw_space(ci: CanvasItem, p: Vector2, ty: String, r := 37.0, flat := false) -> void:
	var col: Color = SPACE_COL.get(ty, SPACE_COL["B"])
	var s := r / 34.0
	if ty == "S":
		col = Color("#a1d94b")
	if not flat:
		_e(ci, p + Vector2(0, 15) * s, Vector2(r + 16.0 * s, (r + 16.0 * s) * 0.55), Color(0, 0, 0, 0.2))
		_e(ci, p + Vector2(0, 9) * s, Vector2(r + 14.0 * s, r + 11.0 * s), Color("#8f877b"))
		_e(ci, p + Vector2(0, 9) * s, Vector2(r + 10.0 * s, r + 7.0 * s), Color("#a79f92"))
		_e(ci, p + Vector2(0, 4) * s, Vector2(r + 14.0 * s, r + 11.0 * s), Color("#8f877b"))
		_e(ci, p + Vector2(0, 4) * s, Vector2(r + 10.0 * s, r + 7.0 * s), Color("#ece6da"))
		ci.draw_circle(p + Vector2(0, 7) * s, r + 4.0 * s, col.darkened(0.45))
		ci.draw_circle(p + Vector2(0, 7) * s, r, col.darkened(0.35))
	ci.draw_circle(p, r + 4.0 * s, col.darkened(0.28))
	ci.draw_circle(p, r, col)
	ci.draw_circle(p + Vector2(0, -3) * s, r - 5.0 * s, col.lightened(0.12))
	ci.draw_circle(p + Vector2(0, -6) * s, r - 14.0 * s, col.lightened(0.2))
	ci.draw_arc(p, r - 4.0 * s, PI * 1.08, PI * 1.62, 12, Color(1, 1, 1, 0.7), 5.0 * s)
	ci.draw_circle(p + Vector2(-r * 0.42, -r * 0.5), 4.0 * s, Color(1, 1, 1, 0.85))
	var w := Color.WHITE
	if SPACE_ICON.has(ty):
		var tx := _icon(str(SPACE_ICON[ty]))
		if tx:
			var isz := r * 1.32
			var rr := Rect2(p - Vector2(isz, isz) / 2.0 + Vector2(0, -1) * s, Vector2(isz, isz))
			ci.draw_texture_rect(tx, Rect2(rr.position + Vector2(0, 3) * s, rr.size), false, Color(0, 0, 0, 0.3))
			ci.draw_texture_rect(tx, rr, false, Color("#fff6d8") if ty == "K" else w)
		return
	match ty:
		"B", "R":
			var bars := [Rect2(-17, -6, 34, 12)]
			if ty == "B":
				bars.append(Rect2(-6, -17, 12, 34))
			for rr2 in bars:
				var q := Rect2(p + (rr2 as Rect2).position * s + Vector2(0, 3) * s, (rr2 as Rect2).size * s)
				ci.draw_style_box(UI.box(Color(0, 0, 0, 0.28), Color(0, 0, 0, 0), 0, int(6 * s)), q)
			for rr2 in bars:
				var q2 := Rect2(p + (rr2 as Rect2).position * s, (rr2 as Rect2).size * s)
				ci.draw_style_box(UI.box(w, w, 0, int(6 * s)), q2)
		"P":
			ci.draw_rect(Rect2(p + Vector2(-11, -4) * s, Vector2(22, 20) * s), OUT)
			ci.draw_rect(Rect2(p + Vector2(-8, -4) * s, Vector2(16, 18) * s), Color("#baf162"))
			ci.draw_style_box(UI.box(Color("#d1ff88"), OUT, maxi(2, int(3 * s)), int(4 * s)), Rect2(p + Vector2(-16, -16) * s, Vector2(32, 13) * s))


const SPACE_ICON := {"E": "hexagon_question", "C": "cards_fan", "I": "pouch_add", "D": "sword", "T": "skull", "K": "tokens_stack", "H": "hand_token", "S": "flag_triangle",
	"W": "fire", "G": "ghost"}
static var _icons := {}


static func _icon(n: String) -> Texture2D:
	if not _icons.has(n):
		_icons[n] = load("res://assets/icons/%s.png" % n)
	return _icons[n]


static func _e(ci: CanvasItem, c: Vector2, r: Vector2, col: Color) -> void:
	ci.draw_set_transform(c, 0.0, Vector2(1.0, r.y / r.x))
	ci.draw_circle(Vector2.ZERO, r.x, col)
	ci.draw_set_transform(Vector2.ZERO)


# ------------------------------------------------------------------ eau, lave, cascades (animés)
func _draw_water() -> void:
	var ci: Node2D = layers["water"]
	for w in [[LAKE_C, LAKE_R, 9], [LAGOON_C, LAGOON_R, 8], [POND_C, POND_R, 3]]:
		var c: Vector2 = w[0]
		var r: Vector2 = w[1]
		for i in int(w[2]):
			var a := i * 2.4
			var p := c + Vector2(cos(a) * r.x * 0.62 + sin(t * 0.4 + i) * 20.0, sin(a) * r.y * 0.55)
			var al := 0.35 + 0.3 * sin(t * 1.6 + i)
			ci.draw_arc(p, 18.0, PI * 1.15, PI * 1.85, 8, Color(1, 1, 1, al), 4.0)
			ci.draw_arc(p + Vector2(30, 6), 13.0, PI * 1.15, PI * 1.85, 8, Color(1, 1, 1, al * 0.8), 3.0)
	# lave qui bouillonne
	var g := 0.5 + 0.5 * sin(t * 2.0)
	_ellipse(ci, LAVA_C, Vector2(78, 42), Color("#ff8a2a").lerp(Color("#ffd23f"), g * 0.6))
	for k in 4:
		var bp := LAVA_C + Vector2(sin(k * 2.1 + t * 0.7) * 50.0, cos(k * 1.3 + t * 0.9) * 22.0)
		var br := 6.0 + 5.0 * absf(sin(t * 2.5 + k))
		ci.draw_circle(bp, br + 2.0, Color("#c8401a"))
		ci.draw_circle(bp, br, Color("#ffd23f"))
	var flow := PackedVector2Array([VOLCANO + Vector2(-110, -60), Vector2(2880, 1010), LAVA_C])
	for k in 6:
		var u := fposmod(t * 0.25 + k / 6.0, 1.0)
		var q := flow[0].lerp(flow[1], u * 2.0) if u < 0.5 else flow[1].lerp(flow[2], (u - 0.5) * 2.0)
		ci.draw_circle(q, 9.0, Color("#ffcf3a"))
	# cascades sous l'île
	for f in falls:
		var x: float = f[0]
		var y0: float = float(f[1]) + 20.0
		var h := 900.0
		ci.draw_rect(Rect2(x - 32.0, y0, 64.0, h), Color("#7fd0ff"))
		ci.draw_rect(Rect2(x - 20.0, y0, 40.0, h), Color("#b4e6ff"))
		for k in 16:
			var yy := y0 + fposmod(t * 520.0 + k * 61.0, h)
			var xx := x - 24.0 + fmod(k * 13.0, 48.0)
			ci.draw_line(Vector2(xx, yy), Vector2(xx, yy + 40.0), Color(1, 1, 1, 0.8), 4.0)
		for k in 6:
			var a := t * 1.5 + k
			ci.draw_circle(Vector2(x + sin(a) * 40.0, y0 + h - 30.0 + cos(a * 1.3) * 10.0), 40.0 + 8.0 * sin(a), Color(1, 1, 1, 0.35))
		ci.draw_circle(Vector2(x, y0 + 6.0), 30.0, Color(1, 1, 1, 0.4 + 0.2 * sin(t * 3.0)))


# ------------------------------------------------------------------ dessus : fumée du volcan, moulin
func _draw_top() -> void:
	var ci: Node2D = layers["top"]
	var top := VOLCANO + Vector2(0, -430)
	for k in 7:
		var u := fposmod(t * 0.12 + k / 7.0, 1.0)
		var p := top + Vector2(sin(u * 5.0 + k) * 40.0 + u * 120.0, -u * 520.0)
		var r := 30.0 + u * 90.0
		ci.draw_circle(p, r, Color(0.45, 0.42, 0.45, 0.42 * (1.0 - u)))
	ci.draw_circle(top + Vector2(0, 8), 34.0 + 6.0 * sin(t * 3.0), Color(1.0, 0.55, 0.15, 0.35))
	for pr in props:
		if pr[1] == "windmill":
			_windmill_blades(ci, pr[0], pr[2])


func _windmill_blades(ci: CanvasItem, p: Vector2, s: float) -> void:
	var hub := p + Vector2(0, -132) * s
	for k in 4:
		var a := t * 1.2 + k * PI / 2.0
		var d := Vector2(cos(a), sin(a))
		var nn := Vector2(-d.y, d.x)
		var blade := PackedVector2Array([hub + nn * 6.0 * s, hub + d * 100.0 * s + nn * 6.0 * s, hub + d * 100.0 * s + nn * 28.0 * s, hub + d * 20.0 * s + nn * 28.0 * s])
		_poly(ci, blade, Color("#f4efe4"), OUT, 4.0)
	ci.draw_circle(hub, 10.0 * s, OUT)
	ci.draw_circle(hub, 6.0 * s, Color("#facd2d"))


# ------------------------------------------------------------------ décor
func _draw_props() -> void:
	var ci: Node2D = layers["props"]
	for pr in props:
		var p: Vector2 = pr[0]
		var s: float = pr[2]
		var fl: bool = pr[3]
		match str(pr[1]):
			"spr":
				_spr(ci, str(pr[4]), p, s, fl, pr[6], float(pr[5]))
			"shell":
				_shell(ci, p, s)
			"starfish":
				_starfish(ci, p, s)
			"mushroom":
				_mushroom(ci, p, s)
			"fence":
				_spr(ci, "deco/fence", p, 0.42 * s, fl, Color.WHITE, 30.0)
			"lamp":
				_lamp(ci, p, s)
			"crate":
				_crate(ci, p, s)
			"banner":
				_banner(ci, p, s)
			"umbrella":
				_umbrella(ci, p, s, fl)
			"boat":
				_boat(ci, p, s, fl)
			"windmill":
				_windmill(ci, p, s)
			"castle":
				_castle(ci, p)
			"volcano":
				_volcano(ci, p)
			"statue":
				_statue(ci, p)
			"shop":
				_shop(ci, p)
			"hut":
				_spr(ci, "deco/shop", p + Vector2(0, 6), 0.62, false, Color.WHITE, 95.0)
				_sign(ci, p + Vector2(0, -162), "BOUTIQUE", Color("#ff3d96"), 20)
			"bank":
				_bank(ci, p)
			"toll":
				_toll(ci, p)
			"start_arch":
				_start_arch(ci, p)
			"lighthouse":
				_lighthouse(ci, p)


## Dessine un sprite posé au sol (pied en p).
func _spr(ci: CanvasItem, name: String, p: Vector2, s: float, flip := false, mod := Color.WHITE, shadow := 0.0) -> void:
	var tx := _t(name)
	if tx == null:
		return
	if shadow > 0.0:
		_ellipse(ci, p + Vector2(0, -2), Vector2(shadow, shadow * 0.3), Color(0, 0, 0, 0.16))
	var sz := tx.get_size()
	ci.draw_set_transform(p, 0.0, Vector2(-s if flip else s, s))
	ci.draw_texture(tx, Vector2(-sz.x / 2.0, -sz.y), mod)
	ci.draw_set_transform(Vector2.ZERO)


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
			var c := top + dir * ln * u + Vector2(0, u * u * 46.0 * s)
			var w := sin(u * PI) * 17.0 * s
			var nn := Vector2(-dir.y, dir.x)
			leaf.append(c + nn * w)
			side.insert(0, c - nn * w)
		leaf.append_array(side)
		_poly(ci, leaf, Color("#84cb33") if k % 2 == 0 else Color("#95dc43"), OUT, 4.0)
	for k in 3:
		ci.draw_circle(top + Vector2(-10 + k * 10, 8) * s, 9.0 * s, OUT)
		ci.draw_circle(top + Vector2(-10 + k * 10, 8) * s, 6.5 * s, Color("#8e5a31"))


func _bush(ci: CanvasItem, p: Vector2, s: float) -> void:
	_shadow(ci, p, 40.0 * s)
	for b in [[-22, -20, 22], [0, -32, 28], [24, -20, 22]]:
		ci.draw_circle(p + Vector2(b[0], b[1]) * s, (b[2] + 4) * s, OUT)
	for b in [[-22, -20, 22], [0, -32, 28], [24, -20, 22]]:
		ci.draw_circle(p + Vector2(b[0], b[1]) * s, b[2] * s, Color("#7cba31"))
	ci.draw_circle(p + Vector2(-6, -40) * s, 9.0 * s, Color("#9fdc53"))


func _hedge(ci: CanvasItem, p: Vector2, s: float) -> void:
	_shadow(ci, p, 46.0 * s)
	var r := Rect2(p + Vector2(-44, -44) * s, Vector2(88, 44) * s)
	ci.draw_style_box(UI.box(Color("#69a724"), OUT, 4, int(16 * s)), r)
	ci.draw_style_box(UI.box(Color("#88c93c"), Color(0, 0, 0, 0), 0, int(10 * s)), Rect2(r.position + Vector2(8, 6) * s, Vector2(72, 12) * s))


func _flowers(ci: CanvasItem, p: Vector2, s: float) -> void:
	var cols := [Color("#ff6b8a"), Color("#ffd23f"), Color("#ffffff"), Color("#b98cff")]
	for k in 5:
		var q := p + Vector2(sin(k * 2.4) * 22.0, cos(k * 1.7) * 12.0) * s
		var col: Color = cols[(k + int(p.x)) % 4]
		ci.draw_line(q, q + Vector2(0, 10) * s, Color("#629327"), 3.0)
		for j in 5:
			var a := j * TAU / 5.0
			ci.draw_circle(q + Vector2(cos(a), sin(a)) * 5.0 * s, 4.0 * s, col)
		ci.draw_circle(q, 3.0 * s, Color("#ffb020"))


func _rock(ci: CanvasItem, p: Vector2, s: float, col: Color, lava := false) -> void:
	_shadow(ci, p, 36.0 * s)
	var poly := PackedVector2Array([p + Vector2(-34, 0) * s, p + Vector2(-28, -26) * s, p + Vector2(-6, -40) * s,
		p + Vector2(22, -34) * s, p + Vector2(36, -8) * s, p + Vector2(30, 2) * s])
	_poly(ci, poly, col, OUT, 5.0)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-22, -24) * s, p + Vector2(-6, -34) * s, p + Vector2(8, -28) * s, p + Vector2(-12, -18) * s]), col.lightened(0.2))
	if lava:
		ci.draw_polyline(PackedVector2Array([p + Vector2(-14, -4) * s, p + Vector2(-4, -18) * s, p + Vector2(6, -14) * s, p + Vector2(16, -28) * s]), Color("#ff7b2e"), 3.0 * s + 1.0)


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
		ci.draw_circle(p + Vector2(b[0], b[1]) * s, b[2] * s, Color("#69a724"))
	ci.draw_circle(p + Vector2(-12, -118) * s, 16.0 * s, Color("#88c93c"))
	ci.draw_circle(p + Vector2(18, -96) * s, 10.0 * s, Color("#88c93c"))
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
		_poly(ci, tri, Color("#5b9521") if k % 2 == 0 else Color("#6aaa29"), OUT, 5.0)


func _dead_tree(ci: CanvasItem, p: Vector2, s: float) -> void:
	_shadow(ci, p, 34.0 * s)
	var trunk := PackedVector2Array([p + Vector2(-12, 0) * s, p + Vector2(12, 0) * s, p + Vector2(5, -110) * s, p + Vector2(-5, -110) * s])
	_poly(ci, trunk, Color("#4a3a35"), OUT, 4.0)
	for b in [[-4, -60, -40, -95], [4, -75, 38, -112], [0, -100, -22, -140], [2, -105, 20, -135]]:
		ci.draw_line(p + Vector2(b[0], b[1]) * s, p + Vector2(b[2], b[3]) * s, OUT, 11.0 * s)
		ci.draw_line(p + Vector2(b[0], b[1]) * s, p + Vector2(b[2], b[3]) * s, Color("#4a3a35"), 6.0 * s)


func _mushroom(ci: CanvasItem, p: Vector2, s: float) -> void:
	_shadow(ci, p, 40.0 * s)
	ci.draw_rect(Rect2(p + Vector2(-17, -54) * s, Vector2(34, 54) * s), OUT)
	ci.draw_rect(Rect2(p + Vector2(-13, -54) * s, Vector2(26, 52) * s), Color("#f7ecd6"))
	var cap := PackedVector2Array()
	for k in 17:
		var a := PI + k * PI / 16.0
		cap.append(p + Vector2(cos(a) * 58.0, sin(a) * 46.0 - 50.0) * s)
	_poly(ci, cap, Color("#f04650") if int(p.y) % 3 != 0 else Color("#8a4fd8"), OUT, 6.0)
	for d in [[-30, -66, 10], [0, -82, 12], [28, -64, 9], [-10, -60, 6]]:
		ci.draw_circle(p + Vector2(d[0], d[1]) * s, d[2] * s, Color.WHITE)
	ci.draw_circle(p + Vector2(-6, -32) * s, 4.0 * s, OUT)
	ci.draw_circle(p + Vector2(6, -32) * s, 4.0 * s, OUT)


func _reeds(ci: CanvasItem, p: Vector2, s: float) -> void:
	for k in 6:
		var x := (k - 2.5) * 9.0 * s
		var h := (46.0 + fmod(k * 17.0, 28.0)) * s
		ci.draw_line(p + Vector2(x, 0), p + Vector2(x + 4.0 * s, -h), Color("#699333"), 4.0 * s)
		if k % 2 == 0:
			ci.draw_line(p + Vector2(x + 3.0 * s, -h + 4.0 * s), p + Vector2(x + 4.0 * s, -h - 16.0 * s), OUT, 9.0 * s)
			ci.draw_line(p + Vector2(x + 3.0 * s, -h + 4.0 * s), p + Vector2(x + 4.0 * s, -h - 16.0 * s), Color("#8a5530"), 6.0 * s)


func _fence(ci: CanvasItem, p: Vector2, s: float) -> void:
	for k in 4:
		var x := (k - 1.5) * 22.0 * s
		ci.draw_rect(Rect2(p + Vector2(x - 5.0 * s, -38.0 * s), Vector2(10, 38) * s), OUT)
		ci.draw_rect(Rect2(p + Vector2(x - 3.0 * s, -36.0 * s), Vector2(6, 35) * s), Color("#e8c08a"))
	for y in [-28.0, -14.0]:
		ci.draw_line(p + Vector2(-40, y) * s, p + Vector2(40, y) * s, OUT, 7.0 * s)
		ci.draw_line(p + Vector2(-38, y) * s, p + Vector2(38, y) * s, Color("#d9a46a"), 4.0 * s)


func _house(ci: CanvasItem, p: Vector2, s: float, roof_col: Color) -> void:
	_shadow(ci, p, 90.0 * s)
	ci.draw_rect(Rect2(p + Vector2(-60, -84) * s, Vector2(120, 84) * s), OUT)
	ci.draw_rect(Rect2(p + Vector2(-55, -80) * s, Vector2(110, 78) * s), Color("#fff1d6"))
	ci.draw_rect(Rect2(p + Vector2(-14, -50) * s, Vector2(28, 50) * s), OUT)
	ci.draw_rect(Rect2(p + Vector2(-11, -47) * s, Vector2(22, 47) * s), Color("#9b6a3e"))
	ci.draw_rect(Rect2(p + Vector2(22, -64) * s, Vector2(24, 22) * s), OUT)
	ci.draw_rect(Rect2(p + Vector2(25, -61) * s, Vector2(18, 16) * s), Color("#7fd0ff"))
	ci.draw_rect(Rect2(p + Vector2(-46, -64) * s, Vector2(24, 22) * s), OUT)
	ci.draw_rect(Rect2(p + Vector2(-43, -61) * s, Vector2(18, 16) * s), Color("#7fd0ff"))
	ci.draw_rect(Rect2(p + Vector2(28, -150) * s, Vector2(20, 50) * s), OUT)
	ci.draw_rect(Rect2(p + Vector2(31, -147) * s, Vector2(14, 47) * s), Color("#c9785a"))
	var roof := PackedVector2Array([p + Vector2(-80, -78) * s, p + Vector2(80, -78) * s, p + Vector2(0, -148) * s])
	_poly(ci, roof, roof_col, OUT, 6.0)
	ci.draw_line(p + Vector2(-60, -88) * s, p + Vector2(0, -140) * s, roof_col.lightened(0.25), 5.0 * s)


func _lamp(ci: CanvasItem, p: Vector2, s: float) -> void:
	_shadow(ci, p, 16.0 * s)
	ci.draw_line(p, p + Vector2(0, -92) * s, OUT, 9.0 * s)
	ci.draw_line(p, p + Vector2(0, -92) * s, Color("#4a4a5a"), 5.0 * s)
	ci.draw_circle(p + Vector2(0, -100) * s, 14.0 * s, OUT)
	ci.draw_circle(p + Vector2(0, -100) * s, 10.0 * s, Color("#ffe27a"))
	ci.draw_circle(p + Vector2(0, -100) * s, 22.0 * s, Color(1, 0.9, 0.5, 0.18))


func _crate(ci: CanvasItem, p: Vector2, s: float) -> void:
	_shadow(ci, p, 34.0 * s)
	var r := Rect2(p + Vector2(-26, -50) * s, Vector2(52, 50) * s)
	ci.draw_style_box(UI.box(Color("#d99a5c"), OUT, 4, 4), r)
	ci.draw_line(r.position + Vector2(6, 6), r.end - Vector2(6, 6), Color("#a86f3d"), 5.0)
	ci.draw_line(r.position + Vector2(r.size.x - 6, 6), r.position + Vector2(6, r.size.y - 6), Color("#a86f3d"), 5.0)


func _banner(ci: CanvasItem, p: Vector2, s: float) -> void:
	_spr(ci, "tiles/flag_blue_a", p, 0.55 * s, false, Color.WHITE, 12.0)


func _umbrella(ci: CanvasItem, p: Vector2, s: float, fl: bool) -> void:
	_ellipse(ci, p + Vector2(0, 2), Vector2(62, 18), Color(0, 0, 0, 0.15))
	var towel := Rect2(p + Vector2(-70 if fl else 10, -10), Vector2(60, 26))
	ci.draw_style_box(UI.box(Color("#4b87f5") if fl else Color("#f04650"), OUT, 3, 4), towel)
	ci.draw_line(p, p + Vector2(0, -110), OUT, 7.0)
	ci.draw_line(p, p + Vector2(0, -110), Color.WHITE, 3.5)
	var dome := PackedVector2Array()
	for k in 13:
		var a := PI + k * PI / 12.0
		dome.append(p + Vector2(cos(a) * 70.0, sin(a) * 34.0 - 104.0))
	_poly(ci, dome, Color("#ff6fb5"), OUT, 4.0)
	for k in 3:
		var a2 := PI + (k * 2 + 1) * PI / 6.0
		var a3 := PI + (k * 2 + 2) * PI / 6.0
		ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -136), p + Vector2(cos(a2) * 66.0, sin(a2) * 30.0 - 104.0), p + Vector2(cos(a3) * 66.0, sin(a3) * 30.0 - 104.0)]), Color.WHITE)


func _boat(ci: CanvasItem, p: Vector2, s: float, fl: bool) -> void:
	var bob := 0.0
	var dir := -1.0 if fl else 1.0
	var hull := PackedVector2Array([p + Vector2(-60, -20) * s, p + Vector2(60, -20) * s, p + Vector2(42, 6) * s, p + Vector2(-42, 6) * s])
	_poly(ci, hull, Color("#c98a4e"), OUT, 5.0)
	ci.draw_line(p + Vector2(-50, -12) * s, p + Vector2(50, -12) * s, Color("#a86f3d"), 4.0)
	ci.draw_line(p + Vector2(0, -20) * s, p + Vector2(0, -120 + bob) * s, OUT, 6.0)
	var sail := PackedVector2Array([p + Vector2(4 * dir, -116) * s, p + Vector2(50 * dir, -34) * s, p + Vector2(4 * dir, -34) * s])
	_poly(ci, sail, Color.WHITE, OUT, 4.0)
	ci.draw_line(p + Vector2(12 * dir, -60) * s, p + Vector2(38 * dir, -40) * s, Color("#f04650"), 4.0)


func _windmill(ci: CanvasItem, p: Vector2, s: float) -> void:
	_shadow(ci, p, 60.0 * s)
	var body := PackedVector2Array([p + Vector2(-42, 0) * s, p + Vector2(42, 0) * s, p + Vector2(28, -140) * s, p + Vector2(-28, -140) * s])
	_poly(ci, body, Color("#fff1d6"), OUT, 6.0)
	var roof := PackedVector2Array([p + Vector2(-36, -136) * s, p + Vector2(36, -136) * s, p + Vector2(0, -182) * s])
	_poly(ci, roof, Color("#4b87f5"), OUT, 6.0)
	ci.draw_rect(Rect2(p + Vector2(-13, -42) * s, Vector2(26, 42) * s), OUT)
	ci.draw_rect(Rect2(p + Vector2(-10, -39) * s, Vector2(20, 39) * s), Color("#9b6a3e"))
	ci.draw_circle(p + Vector2(0, -92) * s, 10.0 * s, OUT)
	ci.draw_circle(p + Vector2(0, -92) * s, 7.0 * s, Color("#7fd0ff"))


func _castle(ci: CanvasItem, p: Vector2) -> void:
	_ellipse(ci, p + Vector2(0, -8), Vector2(285, 46), Color(0, 0, 0, 0.16))
	_spr(ci, "deco/towerAlt", p + Vector2(-178, -64), 0.82)
	_spr(ci, "deco/towerAlt", p + Vector2(178, -64), 0.82, true)
	_spr(ci, "deco/castleSmallAlt", p + Vector2(0, -52), 1.95)
	for k in 5:
		_spr(ci, "deco/castleWallAlt", p + Vector2(-192 + k * 96, 0), 0.8)
	_spr(ci, "deco/towerSmallAlt", p + Vector2(-262, 8), 0.9)
	_spr(ci, "deco/towerSmallAlt", p + Vector2(262, 8), 0.9, true)
	# grande porte
	var door := PackedVector2Array()
	for k in 13:
		var a2 := PI + k * PI / 12.0
		door.append(p + Vector2(cos(a2) * 40.0, sin(a2) * 40.0 - 44.0))
	door.append(p + Vector2(40, 0))
	door.append(p + Vector2(-40, 0))
	ci.draw_colored_polygon(door, Color("#7a4a2a"))
	for k in 4:
		ci.draw_line(p + Vector2(-30 + k * 20, -78), p + Vector2(-30 + k * 20, -2), Color("#5e3820"), 4.0)
	_spr(ci, "tiles/flag_red_a", p + Vector2(0, -372), 0.6)


func _tower(ci: CanvasItem, base: Vector2, r: float, h: float, stone: Color, shade: Color, roof: Color) -> void:
	var body := Rect2(base + Vector2(-r, -h), Vector2(r * 2.0, h))
	ci.draw_style_box(UI.box(stone, OUT, 6, 4), body)
	ci.draw_rect(Rect2(body.position + Vector2(6, 6), Vector2(r * 0.5, h - 12)), shade)
	var cone := PackedVector2Array([base + Vector2(-r - 14, -h + 4), base + Vector2(r + 14, -h + 4), base + Vector2(0, -h - r * 2.0)])
	_poly(ci, cone, roof, OUT, 6.0)


func _volcano(ci: CanvasItem, p: Vector2) -> void:
	var h := 430.0
	var w := 330.0
	var tw := 78.0
	_ellipse(ci, p + Vector2(0, -6), Vector2(w + 30, 50), Color(0, 0, 0, 0.18))
	var cone := PackedVector2Array()
	for k in 13:
		var u := k / 12.0
		cone.append(p + Vector2(-w + (w - tw) * u, -h * pow(u, 0.75)))
	for k in 13:
		var u := 1.0 - k / 12.0
		cone.append(p + Vector2(w - (w - tw) * u, -h * pow(u, 0.75)))
	_poly(ci, cone, Color("#7a5444"), OUT, 8.0)
	# face éclairée
	var lit := PackedVector2Array()
	for k in 13:
		var u := k / 12.0
		lit.append(p + Vector2(-w + (w - tw) * u + 14.0, -h * pow(u, 0.75) - 4.0))
	lit.append(p + Vector2(-20, -h + 10))
	lit.append(p + Vector2(-90, -10))
	ci.draw_colored_polygon(lit, Color("#94685a"))
	# coulées de lave
	for lv in [[-30.0, 0.95], [40.0, 0.7], [-95.0, 0.55]]:
		var x0: float = lv[0]
		var ln: float = lv[1]
		var pts := PackedVector2Array()
		for k in 9:
			var u := k / 8.0
			pts.append(p + Vector2(x0 * (0.4 + u) + sin(u * 9.0 + x0) * 10.0, -h + 8.0 + u * h * ln))
		ci.draw_polyline(pts, OUT, 22.0, true)
		ci.draw_polyline(pts, Color("#ff6a2b"), 15.0, true)
		ci.draw_polyline(pts, Color("#ffcf3a"), 6.0, true)
	# cratère
	_ellipse(ci, p + Vector2(0, -h), Vector2(tw + 8, 24), OUT)
	_ellipse(ci, p + Vector2(0, -h), Vector2(tw, 18), Color("#ff6a2b"))
	_ellipse(ci, p + Vector2(0, -h + 2), Vector2(tw - 26, 10), Color("#ffd23f"))
	for k in 5:
		var rp := p + Vector2(-w * 0.75 + k * 120.0, -10.0 - (k % 2) * 16.0)
		_rock(ci, rp, 0.9, Color("#5c4e4a"), true)


func _statue(ci: CanvasItem, p: Vector2) -> void:
	_ellipse(ci, p + Vector2(0, -4), Vector2(110, 26), Color(0, 0, 0, 0.18))
	var ped := Rect2(p + Vector2(-80, -70), Vector2(160, 70))
	ci.draw_style_box(UI.box(Color("#d8d2c6"), OUT, 6, 6), ped)
	ci.draw_style_box(UI.box(Color("#e9e4dc"), OUT, 5, 6), Rect2(p + Vector2(-96, -86), Vector2(192, 22)))
	UI.text(ci, p + Vector2(0, -34), "AURA", 30, Color("#b8860b"), 0)


func _crown(ci: CanvasItem, c: Vector2) -> void:
	var crown := PackedVector2Array([c + Vector2(-50, 24), c + Vector2(-56, -26), c + Vector2(-26, 2), c + Vector2(0, -38),
		c + Vector2(26, 2), c + Vector2(56, -26), c + Vector2(50, 24)])
	_poly(ci, crown, Color("#ffd23f"), OUT, 6.0)
	ci.draw_circle(c + Vector2(0, 10), 8.0, Color("#f04650"))
	ci.draw_circle(c + Vector2(-30, 12), 6.0, Color("#4b87f5"))
	ci.draw_circle(c + Vector2(30, 12), 6.0, Color("#84cb33"))


func _sign(ci: CanvasItem, c: Vector2, txt: String, col: Color, size := 22) -> void:
	var w := UI.text_width(txt, size) + 30.0
	ci.draw_style_box(UI.box(col, OUT, 4, 10), Rect2(c - Vector2(w / 2.0, 20), Vector2(w, 40)))
	UI.text(ci, c, txt, size, Color.WHITE, 5)


## Une façade de maison construite avec les tuiles « Platformer Art Buildings » (70 px).
func _facade(ci: CanvasItem, base: Vector2, w: int, walls: String, roof: String, rows: Array, sc := 1.0) -> void:
	var n := rows.size()
	var tw := 70.0 * sc
	var x0 := base.x - w * tw / 2.0
	var y0 := base.y - (n + 1) * tw
	_ellipse(ci, base + Vector2(0, -4), Vector2(w * tw * 0.6, 26), Color(0, 0, 0, 0.16))
	for x in w:
		_tile(ci, "roof%sTopMid" % roof, Vector2(x0 + x * tw, y0), sc)
	_tile(ci, "roof%sTopLeft" % roof, Vector2(x0 - 11.0 * sc, y0), sc)
	_tile(ci, "roof%sTopRight" % roof, Vector2(x0 + w * tw - 59.0 * sc, y0), sc)
	for y in n:
		var row: Array = rows[y]
		for x in w:
			var v := "Top" if y == 0 else ("Bottom" if y == n - 1 else "")
			var hz := "Left" if x == 0 else ("Right" if x == w - 1 else "")
			var nm := "house" + walls
			if v != "":
				nm += v + (hz if hz != "" else "Mid")
			elif hz != "":
				nm += "Mid" + hz
			var pos := Vector2(x0 + x * tw, y0 + (y + 1) * tw)
			_tile(ci, nm, pos, sc)
			if x < row.size():
				for o in str(row[x]).split("+"):
					if o != "":
						_tile(ci, o, pos, sc)


func _tile(ci: CanvasItem, name: String, pos: Vector2, sc: float) -> void:
	var tx := _t("buildings/" + name)
	if tx:
		ci.draw_texture_rect(tx, Rect2(pos, Vector2(70, 70) * sc), false)


func _shop(ci: CanvasItem, p: Vector2) -> void:
	_spr(ci, "deco/shop", p + Vector2(0, 6), 0.8, false, Color.WHITE, 120.0)
	_sign(ci, p + Vector2(0, -206), "BOUTIQUE", Color("#ff3d96"), 24)


func _bank(ci: CanvasItem, p: Vector2) -> void:
	_spr(ci, "deco/bank", p + Vector2(0, 6), 0.9, false, Color.WHITE, 100.0)
	_sign(ci, p + Vector2(0, -238), "BANQUE", Color("#d69a00"), 22)


func _toll(ci: CanvasItem, p: Vector2) -> void:
	_shadow(ci, p, 30.0)
	ci.draw_line(p, p + Vector2(0, -96), OUT, 9.0)
	ci.draw_line(p, p + Vector2(0, -96), Color("#c9a061"), 5.0)
	var r := Rect2(p + Vector2(-56, -150), Vector2(112, 60))
	ci.draw_style_box(UI.box(Color("#fff1d6"), OUT, 5, 10), r)
	UI.text(ci, r.position + Vector2(56, 16), "PÉAGE", 16, Color("#8a5530"), 0)
	ci.draw_set_transform(r.position + Vector2(36, 40), 0.0, Vector2(0.18, 0.18))
	ci.draw_texture(_t("tiles/coin_gold"), Vector2(-64, -64))
	ci.draw_set_transform(Vector2.ZERO)
	UI.text(ci, r.position + Vector2(70, 40), "5", 22, OUT, 0)


func _start_arch(ci: CanvasItem, p: Vector2) -> void:
	for x in [-92.0, 92.0]:
		ci.draw_line(p + Vector2(x, 70), p + Vector2(x, -110), OUT, 14.0)
		ci.draw_line(p + Vector2(x, 70), p + Vector2(x, -110), Color("#e8c08a"), 8.0)
	var r := Rect2(p + Vector2(-110, -150), Vector2(220, 52))
	ci.draw_style_box(UI.box(Color("#a1d94b"), OUT, 5, 14), r)
	UI.text(ci, r.get_center(), "DÉPART", 30, Color.WHITE, 7)
	for k in 6:
		var x2 := -100.0 + k * 40.0
		ci.draw_line(p + Vector2(x2, -96), p + Vector2(x2 + 20, -80), Color("#ff6fb5") if k % 2 == 0 else Color("#4b87f5"), 6.0)


func _lighthouse(ci: CanvasItem, p: Vector2) -> void:
	_shadow(ci, p, 60.0)
	var body := PackedVector2Array([p + Vector2(-44, 0), p + Vector2(44, 0), p + Vector2(28, -220), p + Vector2(-28, -220)])
	_poly(ci, body, Color.WHITE, OUT, 6.0)
	for k in 3:
		var y0 := -30.0 - k * 70.0
		var y1 := y0 - 34.0
		var w0 := lerpf(44.0, 28.0, -y0 / 220.0)
		var w1 := lerpf(44.0, 28.0, -y1 / 220.0)
		ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-w0 + 3, y0), p + Vector2(w0 - 3, y0), p + Vector2(w1 - 3, y1), p + Vector2(-w1 + 3, y1)]), Color("#f04650"))
	ci.draw_style_box(UI.box(Color("#ffe27a"), OUT, 5, 6), Rect2(p + Vector2(-26, -262), Vector2(52, 44)))
	var cap := PackedVector2Array([p + Vector2(-36, -262), p + Vector2(36, -262), p + Vector2(0, -300)])
	_poly(ci, cap, Color("#f04650"), OUT, 5.0)
