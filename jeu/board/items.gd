class_name Items
extends RefCounted
## Les objets du plateau : nom, description, prix en boutique, et leur petite icône dessinée.

const MAX_HELD := 3
const DATA := {
	"mushroom": ["Champignon", "+3 à ton lancer de dé", 3, false],
	"double": ["Double dé", "Lance 2 dés", 6, false],
	"triple": ["Triple dé", "Lance 3 dés", 12, false],
	"custom": ["Dé pipé", "Choisis ton chiffre (1 à 10)", 8, false],
	"poison": ["Champi poison", "Le prochain dé d'un joueur ne fera que 1 à 3", 5, true],
	"boo": ["Cloche fantôme", "Vole jusqu'à 10 pièces à un joueur", 10, true],
	"swap": ["Échangeur", "Échange ta place avec un joueur", 8, true],
	"pipe": ["Tuyau doré", "Va directement à l'étoile", 25, false],
}
const SHOP := ["mushroom", "double", "triple", "custom", "poison", "boo", "swap", "pipe"]
# objets gagnés au hasard (case objet, cartes...) : plus de chances pour les objets simples
const GIFT_WEIGHTS := {"mushroom": 5, "double": 4, "poison": 3, "custom": 2, "boo": 2, "swap": 2, "triple": 1, "pipe": 0.4}


static func item_name(k: String) -> String:
	return str(DATA[k][0]) if DATA.has(k) else k


static func desc(k: String) -> String:
	return str(DATA[k][1]) if DATA.has(k) else ""


static func price(k: String) -> int:
	return int(DATA[k][2]) if DATA.has(k) else 0


static func needs_target(k: String) -> bool:
	return bool(DATA[k][3]) if DATA.has(k) else false


static func random_gift(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in GIFT_WEIGHTS:
		total += float(GIFT_WEIGHTS[k])
	var r := rng.randf() * total
	for k in GIFT_WEIGHTS:
		r -= float(GIFT_WEIGHTS[k])
		if r <= 0.0:
			return k
	return "mushroom"


# ------------------------------------------------------------------ icônes
static func _dice(ci: CanvasItem, c: Vector2, s: float, col: Color, label: String) -> void:
	ci.draw_style_box(UI.box(col, UI.DARK, maxi(2, int(3 * s)), int(6 * s)), Rect2(c - Vector2(13, 13) * s, Vector2(26, 26) * s))
	UI.text(ci, c + Vector2(0, -1) * s, label, int(17 * s), UI.WHITE if col != Color.WHITE else UI.DARK, int(3 * s) if col != Color.WHITE else 0)


static func _mush(ci: CanvasItem, c: Vector2, s: float, cap: Color, dots: Color) -> void:
	ci.draw_rect(Rect2(c + Vector2(-8, -2) * s, Vector2(16, 16) * s), UI.DARK)
	ci.draw_rect(Rect2(c + Vector2(-5.5, -2) * s, Vector2(11, 13.5) * s), Color("#fff1d6"))
	var cp := PackedVector2Array()
	for k in 13:
		var a := PI + k * PI / 12.0
		cp.append(c + Vector2(cos(a) * 19.0, sin(a) * 16.0 + 1.0) * s)
	ci.draw_colored_polygon(cp, cap)
	var l := cp.duplicate()
	l.append(cp[0])
	ci.draw_polyline(l, UI.DARK, 3.0 * s)
	ci.draw_circle(c + Vector2(-7, -7) * s, 4.0 * s, dots)
	ci.draw_circle(c + Vector2(7, -9) * s, 3.5 * s, dots)


## Icône d'un objet, centrée sur c (taille de base ~40 px à s = 1).
static func draw_icon(ci: CanvasItem, k: String, c: Vector2, s := 1.0) -> void:
	match k:
		"mushroom":
			_mush(ci, c, s, Color("#f04650"), Color.WHITE)
		"poison":
			_mush(ci, c, s, Color("#a064f0"), Color("#e2c8ff"))
		"double":
			_dice(ci, c + Vector2(-8, 5) * s, s * 0.85, Color("#4b87f5"), "2")
			_dice(ci, c + Vector2(8, -6) * s, s * 0.85, Color("#4b87f5"), "")
		"triple":
			_dice(ci, c + Vector2(-10, 7) * s, s * 0.75, Color("#f04650"), "")
			_dice(ci, c + Vector2(10, 7) * s, s * 0.75, Color("#f04650"), "")
			_dice(ci, c + Vector2(0, -9) * s, s * 0.75, Color("#f04650"), "3")
		"custom":
			_dice(ci, c, s * 1.1, Color("#facd2d"), "?")
		"boo":
			# petit fantôme
			var body := PackedVector2Array()
			for k2 in 11:
				var a := PI + k2 * PI / 10.0
				body.append(c + Vector2(cos(a) * 15.0, sin(a) * 15.0 - 2.0) * s)
			body.append(c + Vector2(15, 14) * s)
			body.append(c + Vector2(7, 9) * s)
			body.append(c + Vector2(0, 14) * s)
			body.append(c + Vector2(-7, 9) * s)
			body.append(c + Vector2(-15, 14) * s)
			ci.draw_colored_polygon(body, Color("#f4f7ff"))
			var bl := body.duplicate()
			bl.append(body[0])
			ci.draw_polyline(bl, UI.DARK, 3.0 * s)
			ci.draw_circle(c + Vector2(-5, -4) * s, 2.8 * s, UI.DARK)
			ci.draw_circle(c + Vector2(5, -4) * s, 2.8 * s, UI.DARK)
			ci.draw_arc(c + Vector2(0, 3) * s, 4.0 * s, 0.2, PI - 0.2, 8, UI.DARK, 2.0 * s)
		"swap":
			for d in [-1.0, 1.0]:
				var y: float = d * 7.0
				var a0 := c + Vector2(-14 * d, y) * s
				var a1 := c + Vector2(14 * d, y) * s
				ci.draw_line(a0, a1, UI.DARK, 7.0 * s)
				ci.draw_line(a0, a1, Color("#5fcd55") if d > 0 else Color("#ff8c28"), 4.0 * s)
				ci.draw_colored_polygon(PackedVector2Array([a1 + Vector2(-6 * d, -7) * s, a1 + Vector2(6 * d, 0) * s, a1 + Vector2(-6 * d, 7) * s]), Color("#5fcd55") if d > 0 else Color("#ff8c28"))
		"pipe":
			ci.draw_rect(Rect2(c + Vector2(-11, -4) * s, Vector2(22, 20) * s), UI.DARK)
			ci.draw_rect(Rect2(c + Vector2(-8, -4) * s, Vector2(16, 18) * s), Color("#facd2d"))
			ci.draw_style_box(UI.box(Color("#ffd84a"), UI.DARK, maxi(2, int(3 * s)), int(4 * s)), Rect2(c + Vector2(-16, -16) * s, Vector2(32, 13) * s))
			ci.draw_rect(Rect2(c + Vector2(-4, -2) * s, Vector2(4, 14) * s), Color(1, 1, 1, 0.5))
