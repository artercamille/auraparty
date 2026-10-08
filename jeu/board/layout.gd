class_name BoardLayout
extends RefCounted
## Tracé du plateau : une boucle de cases sur une grande île. Identique chez tout le monde.

const SPACING := 132.0
const CONTROL := [
	Vector2(420, 760), Vector2(560, 420), Vector2(930, 260), Vector2(1330, 380), Vector2(1720, 250),
	Vector2(2160, 360), Vector2(2330, 760), Vector2(2120, 1130), Vector2(1680, 1240), Vector2(1300, 1060),
	Vector2(900, 1230), Vector2(520, 1120),
]
const MAP_SIZE := Vector2(2760, 1500)

static var _cache: Array = []
static var _curve: PackedVector2Array


## Courbe lisse fermée (Catmull-Rom) passant par les points de contrôle.
static func curve() -> PackedVector2Array:
	if _curve.size() > 0:
		return _curve
	var pts := PackedVector2Array()
	var n := CONTROL.size()
	for i in n:
		var p0: Vector2 = CONTROL[(i - 1 + n) % n]
		var p1: Vector2 = CONTROL[i]
		var p2: Vector2 = CONTROL[(i + 1) % n]
		var p3: Vector2 = CONTROL[(i + 2) % n]
		for k in 40:
			var t := k / 40.0
			var t2 := t * t
			var t3 := t2 * t
			pts.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	_curve = pts
	return pts


## Cases à espacement régulier le long de la courbe : [{pos, type}]
static func spaces() -> Array:
	if _cache.size() > 0:
		return _cache
	var c := curve()
	var total := 0.0
	for i in c.size():
		total += c[i].distance_to(c[(i + 1) % c.size()])
	var count := int(round(total / SPACING))
	var step := total / count
	var out := []
	var acc := 0.0
	var target := 0.0
	var idx := 0
	for i in c.size():
		var a := c[i]
		var b := c[(i + 1) % c.size()]
		var seg := a.distance_to(b)
		while target <= acc + seg and idx < count:
			var k := (target - acc) / maxf(seg, 0.001)
			out.append({"pos": a.lerp(b, k), "type": _type_of(idx)})
			idx += 1
			target += step
		acc += seg
	_cache = out
	return out


static func _type_of(i: int) -> String:
	if i == 0:
		return "S"
	if i % 5 == 3 or i % 11 == 7:
		return "R"
	return "B"


static func count() -> int:
	return spaces().size()


static func type_at(i: int) -> String:
	return str(spaces()[i]["type"])


static func pos_at(i: int) -> Vector2:
	return spaces()[i]["pos"]
