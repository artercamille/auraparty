class_name BoardMap
extends RefCounted
## La grande île : un graphe de cases (comme un vrai Mario Party), identique chez tout le monde.
## Des carrefours relient des chemins ; à chaque carrefour on choisit sa route.
## Types de cases : B bleue (+3), R rouge (-3), E événement « ? », C carte hasard « ! »,
## I objet, D duel, T piège, K banque, H boutique, P tuyau (téléporte vers l'autre tuyau), S départ,
## W Roi Grognon (malus), G fantôme (vole des pièces ou une étoile).

const SIZE := Vector2(4000, 2700)

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
const COAST := [Vector2(120, 230), Vector2(700, 60), Vector2(1450, 110), Vector2(2150, 50), Vector2(2900, 60),
	Vector2(3500, 150), Vector2(3900, 420), Vector2(3960, 950), Vector2(3830, 1420), Vector2(3950, 1950),
	Vector2(3780, 2430), Vector2(3150, 2620), Vector2(2500, 2560), Vector2(1850, 2650), Vector2(1150, 2590),
	Vector2(520, 2520), Vector2(150, 2080), Vector2(60, 1350), Vector2(80, 700)]

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
		nodes.append({"pos": j[0], "type": j[1], "zone": j[2], "next": [], "cost": {}, "seg": -1})
	for si in SEGMENTS.size():
		var sg: Array = SEGMENTS[si]
		var a: int = jid[sg[0]]
		var b: int = jid[sg[1]]
		var pts: Array = [nodes[a]["pos"]]
		pts.append_array(sg[3])
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
