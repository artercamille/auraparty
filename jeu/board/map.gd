class_name BoardMap
extends RefCounted
## La grande île : un graphe de cases (comme un vrai Mario Party), identique chez tout le monde.
## Des carrefours relient des chemins ; à chaque carrefour on choisit sa route.
## Types de cases : B bleue (+3), R rouge (-3), E événement « ? », C carte hasard « ! »,
## I objet, D duel, T piège, K banque, H boutique, P tuyau (téléporte vers l'autre tuyau), S départ,
## W Roi Grognon (malus), G fantôme (vole des pièces ou une étoile).

## Échelle du plateau : les positions ci-dessous sont multipliées par K (île plus grande et plus aérée).
const K := 1.25
const SIZE := Vector2(4000, 2700) * K

# carrefours : nom -> [position, type, zone]
const JUNCTIONS := {
	"S": [Vector2(1953, 2290), "S", "village"],
	"J1": [Vector2(1445, 2065), "B", "village"],
	"J2": [Vector2(713, 1333), "B", "foret"],
	"J3": [Vector2(1250, 300), "B", "lac"],
	"J4": [Vector2(1891, 1085), "B", "chateau"],
	"J5": [Vector2(2573, 471), "B", "lac"],
	"J6": [Vector2(3007, 1252), "B", "volcan"],
	"J7": [Vector2(2635, 2263), "B", "plage"],
}
const J_ORDER := ["S", "J1", "J2", "J3", "J4", "J5", "J6", "J7"]

# chemins : [départ, arrivée, zone, points intermédiaires, types des cases, péage, nom affiché]
const SEGMENTS := [
	["S", "J1", "village", [Vector2(1798, 2282), Vector2(1612, 2220)], "BHKB", 0, "Village"],
	["J1", "J2", "foret", [Vector2(1178, 2282), Vector2(806, 2331), Vector2(496, 2158), Vector2(347, 1835), Vector2(434, 1519)], "BEBIBRHCBEBB", 0, "Grande forêt"],
	["J1", "J2", "foret", [Vector2(1240, 1829), Vector2(992, 1581)], "ETCRE", 0, "Sentier des champignons"],
	["J2", "J3", "lac", [Vector2(403, 1085), Vector2(298, 713), Vector2(434, 403), Vector2(806, 260)], "BIBEBPBCGRBB", 0, "Rive du lac"],
	["J2", "J4", "chateau", [Vector2(1054, 1240), Vector2(1519, 1178)], "BDBCBE", 5, "Pont du château"],
	["J3", "J5", "lac", [Vector2(1674, 260), Vector2(2139, 298)], "BRBIHEBCB", 0, "Col du nord"],
	["J4", "J5", "chateau", [Vector2(2046, 775), Vector2(2294, 589)], "BDEWB", 0, "Remparts"],
	["J5", "J6", "volcan", [Vector2(3007, 298), Vector2(3441, 403), Vector2(3658, 775), Vector2(3441, 1116)], "BRERBTBCWBEBI", 0, "Volcan"],
	["J6", "J7", "plage", [Vector2(3472, 1519), Vector2(3627, 1891), Vector2(3348, 2263)], "BIBEHPBCBDBB", 0, "Plage"],
	["J6", "J7", "volcan", [Vector2(2728, 1519), Vector2(2604, 1891)], "RWTCR", 0, "Coulée de lave"],
	["J7", "S", "village", [Vector2(2356, 2368), Vector2(2108, 2306)], "BEB", 0, "Village"],
]

const ZONE_NAMES := {"village": "Village", "foret": "Forêt", "lac": "Lac", "chateau": "Château", "volcan": "Volcan", "plage": "Plage"}

# île : contour (lissé ensuite)
const COAST := [Vector2(5210, 3096), Vector2(5080, 3196), Vector2(4872, 3235), Vector2(4704, 3213), Vector2(4520, 3119), Vector2(4424, 3100),
	Vector2(3952, 3161), Vector2(3512, 3105), Vector2(3288, 3164), Vector2(3048, 3316), Vector2(2880, 3378), Vector2(2384, 3430),
	Vector2(2016, 3396), Vector2(1840, 3332), Vector2(1680, 3237), Vector2(1480, 3189), Vector2(1040, 3227), Vector2(848, 3190),
	Vector2(672, 3118), Vector2(480, 2986), Vector2(321, 2816), Vector2(205, 2616), Vector2(134, 2392), Vector2(122, 2192),
	Vector2(169, 1952), Vector2(212, 1888), Vector2(387, 1752), Vector2(432, 1648), Vector2(381, 1536), Vector2(164, 1368),
	Vector2(93, 1168), Vector2(62, 992), Vector2(66, 816), Vector2(99, 648), Vector2(161, 496), Vector2(296, 311),
	Vector2(472, 174), Vector2(704, 71), Vector2(968, 17), Vector2(1520, 46), Vector2(2048, 13), Vector2(2528, 34),
	Vector2(2792, 86), Vector2(3040, 244), Vector2(3208, 285), Vector2(3395, 248), Vector2(3616, 92), Vector2(3728, 62),
	Vector2(4043, 80), Vector2(4232, 123), Vector2(4360, 179), Vector2(4532, 288), Vector2(4696, 449), Vector2(4837, 736),
	Vector2(4875, 984), Vector2(4845, 1152), Vector2(4774, 1296), Vector2(4712, 1342), Vector2(4573, 1392), Vector2(4311, 1624),
	Vector2(4502, 1800), Vector2(4600, 1923), Vector2(4728, 1975), Vector2(4776, 2021), Vector2(4833, 2208), Vector2(4864, 2541),
	Vector2(5004, 2792), Vector2(5211, 2952), Vector2(5231, 3024)]

static var nodes: Array = []      # {pos, type, zone, next, cost, seg}
static var curves: Array = []     # [polyline lissée, zone, nom] par chemin
static var _coast: PackedVector2Array


static func build() -> void:
	if nodes.size() > 0:
		return
	var jid := {}
	for k in J_ORDER:
		var j: Array = JUNCTIONS[k]
		jid[k] = nodes.size()
		nodes.append({"pos": (j[0] as Vector2) * K, "type": j[1], "zone": j[2], "next": [], "cost": {}, "seg": -1})
	for si in SEGMENTS.size():
		var sg: Array = SEGMENTS[si]
		var a: int = jid[sg[0]]
		var b: int = jid[sg[1]]
		var pts: Array = [nodes[a]["pos"]]
		for q in sg[3]:
			pts.append((q as Vector2) * K)
		pts.append(nodes[b]["pos"])
		var c := smooth(pts, 24)
		curves.append([c, sg[2], sg[6]])
		var types: String = sg[4]
		var n := types.length()
		var cum := PackedFloat32Array([0.0])
		for i in range(1, c.size()):
			cum.append(cum[i - 1] + c[i - 1].distance_to(c[i]))
		var total: float = cum[c.size() - 1]
		var prev := a
		for k in n:
			var s := total * (k + 1) / (n + 1)
			var i := clampi(cum.bsearch(s), 1, c.size() - 1)
			var u := (s - cum[i - 1]) / maxf(0.001, cum[i] - cum[i - 1])
			var id := nodes.size()
			nodes.append({"pos": c[i - 1].lerp(c[i], u), "type": types[k], "zone": sg[2], "next": [], "cost": {}, "seg": si})
			nodes[prev]["next"].append(id)
			if prev == a and int(sg[5]) > 0:
				nodes[a]["cost"][id] = int(sg[5])
			prev = id
		nodes[prev]["next"].append(b)


static func smooth(pts: Array, steps: int, closed := false) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	var segs := n if closed else n - 1
	for i in segs:
		var p0: Vector2 = pts[(i - 1 + n) % n] if closed else pts[maxi(i - 1, 0)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[(i + 1) % n]
		var p3: Vector2 = pts[(i + 2) % n] if closed else pts[mini(i + 2, n - 1)]
		for k in steps:
			var u := k / float(steps)
			var u2 := u * u
			var u3 := u2 * u
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3))
	if not closed:
		out.append(pts[n - 1])
	return out


static func coast() -> PackedVector2Array:
	if _coast.size() == 0:
		_coast = smooth(COAST, 20, true)
	return _coast


static func count() -> int:
	build()
	return nodes.size()


static func pos(i: int) -> Vector2:
	build()
	return nodes[i]["pos"]


static func kind(i: int) -> String:
	build()
	return nodes[i]["type"]


static func zone(i: int) -> String:
	build()
	return nodes[i]["zone"]


static func next(i: int) -> Array:
	build()
	return nodes[i]["next"]


static func cost(from: int, to: int) -> int:
	build()
	return int(nodes[from]["cost"].get(to, 0))


## Première case d'un chemin (index du chemin dans SEGMENTS).
static func first_of_segment(si: int) -> int:
	build()
	for k in nodes.size():
		if int(nodes[k]["seg"]) == si:
			return k
	return -1


static func start() -> int:
	return 0


## Nom du chemin qui commence par la case `first` (pour le choix au carrefour).
static func route_name(first: int) -> String:
	build()
	var si: int = nodes[first]["seg"]
	return str(SEGMENTS[si][6]) if si >= 0 else ""


## L'autre tuyau (téléportation).
static func pipe_pair(i: int) -> int:
	build()
	for k in nodes.size():
		if k != i and nodes[k]["type"] == "P":
			return k
	return i


## Distances (en cases, vers l'avant) depuis `from`.
static func dist_from(from: int) -> Dictionary:
	build()
	var d := {from: 0}
	var q := [from]
	while q.size() > 0:
		var c: int = q.pop_front()
		for n2 in nodes[c]["next"]:
			if not d.has(n2):
				d[n2] = int(d[c]) + 1
				q.append(n2)
	return d
