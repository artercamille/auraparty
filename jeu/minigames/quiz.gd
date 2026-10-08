extends "res://minigames/stage.gd"
## « Quiz sous le chapiteau ! » (Big Top Quiz) : des ballons montrent brièvement des images
## (objets à compter, bestioles, bonneteau), puis une question s'affiche. Trois estrades portent
## les réponses : saute sur la bonne ! Le premier posé sur une estrade est verrouillé.
## Bonne réponse : 5 pts au plus rapide, puis 3, 2, 1. Le plus de points après 5 questions gagne.
## L'hôte rythme les phases (show / ask / reveal) et compte l'ordre d'arrivée ; le contenu des
## questions vient de la graine, identique chez tout le monde.

const FLOOR := 620.0
const PAD_Y := 490.0
const PAD_W := 192.0
const PAD_X := [300.0, 640.0, 980.0]
const CARD_Y := 300.0
const ROUNDS := 5
const ASK := 6.5
const REVEAL := 2.4
const POINTS := [5, 3, 2, 1]
const BALLOON_COLS := [Color("#f04650"), Color("#4b87f5"), Color("#5fcd55"), Color("#facd2d"),
	Color("#a064f0"), Color("#ff8c28"), Color("#2dc8d2"), Color("#ff78c3")]
const PAD_COLS := [Color("#f04650"), Color("#4b87f5"), Color("#facd2d")]

# bestioles (intrus, bonneteau) : [image, nom avec article]
const CRITTERS := {
	"bee": ["enemies/bee_a", "l'abeille", Rect2(4, 12, 120, 102)],
	"mouse": ["enemies/mouse_walk_a", "la souris", Rect2(0, 35, 128, 93)],
	"frog": ["enemies/frog_idle", "la grenouille", Rect2(0, 16, 128, 112)],
	"snail": ["enemies/snail_rest", "l'escargot", Rect2(0, 26, 128, 102)],
	"ladybug": ["enemies/ladybug_rest", "la coccinelle", Rect2(0, 29, 126, 99)],
	"fish": ["enemies/fish_blue_rest", "le poisson", Rect2(2, 13, 124, 104)],
	"slime": ["enemies/slime_normal_rest", "le slime", Rect2(8, 44, 112, 84)],
	"fly": ["enemies/fly_a", "la mouche", Rect2(14, 6, 100, 118)],
}
# objets (compter, plus / moins) : [image, nom au pluriel]
const THINGS := {
	"coin": ["tiles/coin_gold", "PIÈCES", Rect2(26, 24, 75, 81)],
	"star": ["tiles/star", "ÉTOILES", Rect2(24, 26, 80, 76)],
	"heart": ["tiles/heart", "CŒURS", Rect2(28, 32, 72, 64)],
	"gem": ["tiles/gem_blue", "DIAMANTS", Rect2(24, 28, 80, 70)],
	"key": ["tiles/key_yellow", "CLÉS", Rect2(16, 32, 96, 64)],
	"mushroom": ["tiles/mushroom_red", "CHAMPIGNONS", Rect2(35, 80, 58, 48)],
}

var tex := {}
var rounds: Array = []
var pads: Array = []          # StaticBody2D
var tent: Node2D
var front: Node2D
var pad_layer: Node2D

# état partagé (diffusé par l'hôte)
var round_i := -1
var phase := "wait"           # wait, show, ask, reveal, done
var phase_t := 0.0
var locks: Dictionary = {}    # id -> [pad, ordre]
var totals: Dictionary = {}   # id -> points
var gained: Dictionary = {}   # id -> points gagnés à cette question

# local
var my_lock := -1
var pads_on := false
var bot_pad := -1
var bot_wander := 640.0
var bot_wander_t := 0.0

# hôte
var host_lock_t: Dictionary = {}   # id -> temps de réponse (s) cumulé quand c'est juste
var host_all_locked_t := -1.0


func _setup() -> void:
	title = "Quiz sous le chapiteau !"
	rules = "Regarde bien les ballons : ils ne montrent leurs images qu'un instant !\nUne question arrive, avec 3 réponses sur les estrades.\nSaute sur la bonne : la PREMIÈRE estrade où tu te poses est ta réponse.\nLes plus rapides gagnent plus de points (5, 3, 2, 1). 5 questions !"
	duration = 999.0
	show_heads = false
	for i in 8:
		spawn_points.append(Vector2(250 + i * 112, FLOOR))
	for k in CRITTERS:
		tex[k] = load("res://assets/%s.png" % CRITTERS[k][0])
	for k in THINGS:
		tex[k] = load("res://assets/%s.png" % THINGS[k][0])


# ------------------------------------------------------------------ questions (même graine = mêmes questions)
func _pick(arr: Array, n: int) -> Array:
	var a := arr.duplicate()
	var out := []
	for i in n:
		var k := rng.randi_range(0, a.size() - 1)
		out.append(a[k])
		a.remove_at(k)
	return out


func _shuffle(arr: Array) -> Array:
	var a := arr.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a


func _gen_rounds() -> void:
	var types := ["count", "intrus", "shell", "most", "shell"]
	if rng.randf() < 0.5:
		types = ["count", "shell", "intrus", "most", "count"]
	for i in ROUNDS:
		var d := i / float(ROUNDS - 1)
		var q := {"type": types[i], "d": d}
		match types[i]:
			"count":
				var kinds := _pick(THINGS.keys(), 2 if d < 0.5 else 3)
				var n := 5 + int(round(d * 4.0))
				var target: String = kinds[0]
				var c := rng.randi_range(2, n - 2)
				var items := []
				for k in c:
					items.append(target)
				for k in n - c:
					items.append(kinds[1 + (k % (kinds.size() - 1)) if k < kinds.size() - 1 else rng.randi_range(1, kinds.size() - 1)])
				items = _shuffle(items)
				var opts := [c]
				var cand := _shuffle([c - 2, c - 1, c + 1, c + 2].filter(func(v): return v >= 1))
				opts.append(cand[0])
				opts.append(cand[1])
				opts = _shuffle(opts)
				q["items"] = items
				q["answers"] = opts.map(func(v): return str(v))
				q["correct"] = opts.find(c)
				q["question"] = "Combien de %s ?" % THINGS[target][1]
				q["icon"] = target
				q["show"] = lerpf(3.0, 2.2, d)
			"most":
				var kinds := _pick(THINGS.keys(), 3)
				var counts := _shuffle([2, 3, 5] if d < 0.6 else [3, 4, 5])
				var items := []
				for k in 3:
					for m in int(counts[k]):
						items.append(kinds[k])
				items = _shuffle(items)
				var most := rng.randf() < 0.5
				var best := 0
				for k in 3:
					if (most and int(counts[k]) > int(counts[best])) or (not most and int(counts[k]) < int(counts[best])):
						best = k
				var order := _shuffle([0, 1, 2])
				q["items"] = items
				q["answers"] = order.map(func(k): return "img:" + str(kinds[k]))
				q["correct"] = order.find(best)
				q["question"] = "Lequel y en avait-il le %s ?" % ("PLUS" if most else "MOINS")
				q["show"] = lerpf(3.0, 2.4, d)
			"intrus":
				var all := _pick(CRITTERS.keys(), 5 + int(round(d * 2.0)))
				var absent: String = all[0]
				var shown: Array = all.slice(1)
				var opts := [absent, shown[0], shown[1]]
				opts = _shuffle(opts)
				q["items"] = _shuffle(shown)
				q["answers"] = opts.map(func(k): return "img:" + str(k))
				q["correct"] = opts.find(absent)
				q["question"] = "Lequel n'était PAS là ?"
				q["show"] = lerpf(2.8, 2.0, d)
			"shell":
				var crit := _pick(CRITTERS.keys(), 3)
				var target := rng.randi_range(0, 2)
				var n_sw := 3 + int(round(d * 4.0))
				var swaps := []
				for k in n_sw:
					var a := rng.randi_range(0, 2)
					var b := (a + rng.randi_range(1, 2)) % 3
					swaps.append([a, b])
				# position finale de la cible
				var pos := [0, 1, 2]   # pos[k] = emplacement du ballon k
				for sw in swaps:
					for k in 3:
						if pos[k] == sw[0]:
							pos[k] = sw[1]
						elif pos[k] == sw[1]:
							pos[k] = sw[0]
				q["items"] = crit
				q["swaps"] = swaps
				q["swap_dur"] = lerpf(0.62, 0.36, d)
				q["answers"] = ["pos", "pos", "pos"]
				q["correct"] = pos[target]
				q["question"] = "Où est %s ?" % CRITTERS[crit[target]][1]
				q["icon"] = crit[target]
				q["show"] = 2.0
				q["color"] = BALLOON_COLS[rng.randi_range(0, 7)]
		q["cols"] = []
		for k in 12:
			q["cols"].append(BALLOON_COLS[rng.randi_range(0, 7)])
		rounds.append(q)


func show_total(q: Dictionary) -> float:
	if q["type"] == "shell":
		return 0.6 + float(q["show"]) + 0.4 + q["swaps"].size() * float(q["swap_dur"]) + 0.3
	return 0.9 + float(q["show"]) + 0.9 + 0.2


# ------------------------------------------------------------------ décor
func _build_level() -> void:
	_gen_rounds()
	tent = Node2D.new()
	tent.z_index = -5
	world.add_child(tent)
	tent.draw.connect(_draw_tent)
	solid(Rect2(-200, FLOOR, 1680, 300))
	solid(Rect2(-100, -800, 140, 1600))
	solid(Rect2(1240, -800, 140, 1600))
	for i in 3:
		var b := solid(Rect2(float(PAD_X[i]) - PAD_W / 2.0, PAD_Y, PAD_W, 18.0), true)
		b.collision_layer = 0
		pads.append(b)
	pad_layer = Node2D.new()
	pad_layer.z_index = -1
	world.add_child(pad_layer)
	pad_layer.draw.connect(_draw_pads)
	front = Node2D.new()
	front.z_index = -1
	world.add_child(front)
	front.draw.connect(_draw_front)


func _set_pads(on: bool) -> void:
	pads_on = on
	for b in pads:
		(b as StaticBody2D).collision_layer = 2 if on else 0


func _on_start() -> void:
	for id in nodes:
		totals[id] = 0


# ------------------------------------------------------------------ hôte : rythme et points
func _host_phase(r: int, ph: String, extra := {}) -> void:
	var d := {"r": r, "ph": ph}
	d.merge(extra)
	Net.mg_broadcast(d)


func _on_mg_msg(from_id: int, data: Dictionary) -> void:
	if data.has("lock") and int(data.get("r", -1)) == round_i and phase == "ask" and not locks.has(from_id):
		var pad := int(data["lock"])
		locks[from_id] = [pad, locks.size()]
		if pad == int(rounds[round_i]["correct"]):
			host_lock_t[from_id] = float(host_lock_t.get(from_id, 0.0)) + phase_t
		Net.mg_broadcast({"r": round_i, "locks": locks})


func _host_update() -> void:
	if round_i < 0 or round_i >= ROUNDS:
		return
	var q: Dictionary = rounds[round_i]
	match phase:
		"show":
			if phase_t >= show_total(q):
				_host_phase(round_i, "ask")
		"ask":
			var everyone := true
			for id in nodes:
				if Net.players.has(id) and not locks.has(id):
					everyone = false
			if everyone and host_all_locked_t < 0.0:
				host_all_locked_t = phase_t
			if phase_t >= ASK or (host_all_locked_t >= 0.0 and phase_t >= host_all_locked_t + 0.5):
				host_all_locked_t = -1.0
				var g := {}
				var ok := []
				for id in locks:
					if int(locks[id][0]) == int(q["correct"]):
						ok.append(id)
				ok.sort_custom(func(a, b): return int(locks[a][1]) < int(locks[b][1]))
				for k in ok.size():
					g[ok[k]] = POINTS[mini(k, POINTS.size() - 1)]
				var tot := totals.duplicate()
				for id in g:
					tot[id] = int(tot.get(id, 0)) + int(g[id])
				_host_phase(round_i, "reveal", {"gained": g, "totals": tot})
		"reveal":
			if phase_t >= REVEAL:
				if round_i + 1 < ROUNDS:
					_host_phase(round_i + 1, "show")
				else:
					_host_phase(round_i, "done")
					Net.mg_end_with_scores(host_scores())


func host_scores() -> Dictionary:
	var out := {}
	for id in nodes:
		var p := int(totals.get(id, 0))
		out[id] = [p * 1000.0 - float(host_lock_t.get(id, 0.0)), "%d point%s" % [p, "s" if p > 1 else ""]]
	return out


func _on_mg_state(data: Dictionary) -> void:
	if data.has("locks"):
		if int(data.get("r", -1)) == round_i:
			locks = data["locks"]
		return
	var r := int(data.get("r", 0))
	var ph := str(data.get("ph", ""))
	if ph == "" or (r == round_i and ph == phase):
		return
	round_i = r
	phase = ph
	phase_t = 0.0
	match ph:
		"show":
			locks = {}
			gained = {}
			my_lock = -1
			bot_pad = -1
			_set_pads(false)
			Sfx.play("whoosh", -4.0)
		"ask":
			_set_pads(true)
			Sfx.play("spawn", -4.0)
			fx.shake(3.0)
		"reveal":
			_set_pads(false)
			gained = data.get("gained", {})
			totals = data.get("totals", totals)
			var q: Dictionary = rounds[round_i]
			for id in gained:
				if nodes.has(id):
					var n: Player = nodes[id]
					fx.popup(n.position + Vector2(0, -90), "+%d" % int(gained[id]), Net.color_of(id))
					fx.stars(n.position + Vector2(0, -40), 4)
			if gained.has(Net.my_id()):
				Sfx.play("gem", -2.0)
			elif my_lock >= 0:
				Sfx.play("hurt", -10.0)
			if q["type"] == "shell":
				Sfx.play("select", -6.0)


# ------------------------------------------------------------------ boucle
func _process(delta: float) -> void:
	super._process(delta)
	if Net.is_host() and state == "play" and round_i < 0 and play_t >= 1.2 and phase == "wait":
		phase = "starting"
		_host_phase(0, "show")
	if phase != "wait" and phase != "done" and phase != "starting":
		phase_t += delta
		if Net.is_host() and state == "play":
			_host_update()
		# petits bruits pendant le bonneteau
		if phase == "show" and round_i >= 0 and rounds[round_i]["type"] == "shell":
			var q: Dictionary = rounds[round_i]
			var t0 := 0.6 + float(q["show"]) + 0.4
			var k := int(floor((phase_t - t0) / float(q["swap_dur"])))
			var kp := int(floor((phase_t - delta - t0) / float(q["swap_dur"])))
			if k != kp and k >= 0 and k < q["swaps"].size():
				Sfx.play("whoosh", -12.0, 0.15)
	tent.queue_redraw()
	pad_layer.queue_redraw()
	front.queue_redraw()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state != "play" or me == null:
		return
	if phase == "ask" and my_lock < 0 and pads_on and me.is_on_floor() and absf(me.position.y - PAD_Y) < 4.0:
		for i in 3:
			if absf(me.position.x - float(PAD_X[i])) < PAD_W / 2.0 + 4.0:
				my_lock = i
				Net.mg_to_host({"lock": i, "r": round_i})
				Sfx.play("coin", -4.0)
				fx.ring(me.position + Vector2(0, -30), me.color())
				break
	if me.is_bot:
		_bot(delta)


func _bot(delta: float) -> void:
	bot_wander_t -= delta
	if bot_wander_t <= 0.0:
		bot_wander_t = randf_range(0.8, 2.0)
		bot_wander = randf_range(200.0, 1080.0)
	var goal := bot_wander
	var jump := false
	if phase == "ask" and my_lock < 0 and phase_t > randf_range(0.4, 0.9):
		if bot_pad < 0:
			bot_pad = int(rounds[round_i]["correct"]) if randf() < 0.6 else randi() % 3
		goal = float(PAD_X[bot_pad])
		if absf(me.position.x - goal) < 60.0 and me.is_on_floor() and me.position.y > PAD_Y + 20.0:
			jump = true
	me.set_meta("goal_x", goal)
	me.set_meta("jump_now", jump)


# ------------------------------------------------------------------ ballons
## Positions des ballons pendant la phase "show" : [centre, rayon, montre l'image ?, échelle x]
func _balloons(q: Dictionary, tt: float) -> Array:
	var out := []
	if q["type"] == "shell":
		var swaps: Array = q["swaps"]
		var sd: float = q["swap_dur"]
		var t_flip := 0.6 + float(q["show"])
		var t_sw := t_flip + 0.4
		var pos := [0, 1, 2]
		var moving := {}
		var k_now := -1
		if tt >= t_sw:
			k_now = int(floor((tt - t_sw) / sd))
		for k in mini(k_now, swaps.size()):
			var sw: Array = swaps[k]
			for b in 3:
				if pos[b] == sw[0]:
					pos[b] = sw[1]
				elif pos[b] == sw[1]:
					pos[b] = sw[0]
		var u := 0.0
		if k_now >= 0 and k_now < swaps.size():
			u = (tt - t_sw - k_now * sd) / sd
			var sw: Array = swaps[k_now]
			for b in 3:
				if pos[b] == sw[0]:
					moving[b] = [sw[0], sw[1], 1.0]
				elif pos[b] == sw[1]:
					moving[b] = [sw[1], sw[0], -1.0]
		for b in 3:
			var x := float(PAD_X[pos[b]])
			var y := 250.0
			if moving.has(b):
				var m: Array = moving[b]
				var e := u * u * (3.0 - 2.0 * u)
				x = lerpf(float(PAD_X[m[0]]), float(PAD_X[m[1]]), e)
				y -= sin(u * PI) * 70.0 * float(m[2])
			if tt < 0.6:
				y += (1.0 - tt / 0.6) * (1.0 - tt / 0.6) * 500.0
			y += sin(tt * 2.4 + b) * 5.0
			var face := tt < t_flip + 0.2
			var sx := 1.0
			if tt >= t_flip and tt < t_flip + 0.4:
				sx = absf(cos((tt - t_flip) / 0.4 * PI))
			out.append([Vector2(x, y), 62.0, face, sx, b])
		return out
	var items: Array = q["items"]
	var n := items.size()
	var two_rows := n > 6
	var per_row := int(ceil(n / 2.0)) if two_rows else n
	for k in n:
		var row := (k / per_row) if two_rows else 0
		var col := k - row * per_row
		var cnt := per_row if row == 0 else n - per_row
		var gap := minf(170.0, 900.0 / maxf(1.0, cnt))
		var sx0 := 640.0 - gap * (cnt - 1) / 2.0
		var slot := Vector2(sx0 + col * gap + (gap * 0.25 if row == 1 else 0.0), 200.0 + row * 112.0 if two_rows else 250.0)
		var t_in := 0.9
		var t_out := 0.9 + float(q["show"])
		var stag := k * 0.05
		var p := slot
		if tt < t_in + stag:
			var u := clampf((tt - stag) / t_in, 0.0, 1.0)
			u = 1.0 - (1.0 - u) * (1.0 - u)
			p = Vector2(lerpf(-120.0, slot.x, u), slot.y + (1.0 - u) * 40.0)
		elif tt > t_out + stag:
			var u := clampf((tt - t_out - stag) / 0.9, 0.0, 1.0)
			u = u * u
			p = Vector2(lerpf(slot.x, 1420.0, u), slot.y - u * 120.0)
		p.y += sin(tt * 2.2 + k * 1.3) * 6.0
		out.append([p, 50.0 if two_rows else 56.0, true, 1.0, k])
	return out


func _draw_item(ci: CanvasItem, key: String, c: Vector2, size: float) -> void:
	var info: Array = CRITTERS[key] if CRITTERS.has(key) else THINGS[key]
	var src: Rect2 = info[2]
	var sc := size / maxf(src.size.x, src.size.y)
	var dst := Rect2(c - src.size * sc / 2.0, src.size * sc)
	ci.draw_texture_rect_region(tex[key], dst, src)


func _draw_balloon(c: Vector2, r: float, col: Color, item: String, face: bool, sx: float) -> void:
	# ficelle
	var pts := PackedVector2Array()
	for k in 8:
		var u := k / 7.0
		pts.append(c + Vector2(sin(u * 5.0 + c.x * 0.02) * 5.0, r + 6.0 + u * 52.0))
	front.draw_polyline(pts, Color(UI.DARK, 0.75), 2.5)
	front.draw_set_transform(c, 0.0, Vector2(maxf(sx, 0.02), 1.0))
	front.draw_colored_polygon(PackedVector2Array([Vector2(-9, r + 10), Vector2(9, r + 10), Vector2(0, r - 4)]), UI.DARK)
	front.draw_circle(Vector2.ZERO, r + 4.5, UI.DARK)
	front.draw_circle(Vector2.ZERO, r, col)
	front.draw_circle(Vector2(-r * 0.38, -r * 0.42), r * 0.2, Color(1, 1, 1, 0.45))
	front.draw_circle(Vector2.ZERO, r * 0.7, Color(1, 1, 1, 0.95))
	if face:
		_draw_item(front, item, Vector2.ZERO, r * 1.12)
	else:
		UI.text(front, Vector2(0, -2), "?", int(r * 1.0), col, 8)
	front.draw_set_transform(Vector2.ZERO)


# ------------------------------------------------------------------ dessin
func _draw_tent() -> void:
	# toile rayée du chapiteau
	tent.draw_rect(Rect2(-50, -50, 1380, 820), Color("#9e2735"))
	var apex := Vector2(640, -330)
	var n := 22
	for k in n:
		var x0 := lerpf(-900.0, 2180.0, k / float(n))
		var x1 := lerpf(-900.0, 2180.0, (k + 1) / float(n))
		var col := Color("#e2434f") if k % 2 == 0 else Color("#fbe8cf")
		tent.draw_colored_polygon(PackedVector2Array([apex, Vector2(x0, 760), Vector2(x1, 760)]), col)
	# assombrir le bas pour la lisibilité
	var c0 := Color(0.25, 0.05, 0.12, 0.0)
	var c1 := Color(0.25, 0.05, 0.12, 0.36)
	tent.draw_polygon(PackedVector2Array([Vector2(-50, 330), Vector2(1330, 330), Vector2(1330, 720), Vector2(-50, 720)]),
		PackedColorArray([c0, c0, c1, c1]))
	# projecteurs
	var tt := t
	for s in [-1.0, 1.0]:
		var src := Vector2(640 + s * 700.0, -40)
		var aim := Vector2(640 + s * -120.0 + sin(tt * 0.7 * s) * 260.0, FLOOR)
		var dir := (aim - src).normalized()
		var side := Vector2(-dir.y, dir.x)
		tent.draw_colored_polygon(PackedVector2Array([src + side * 18.0, src - side * 18.0, aim - side * 170.0, aim + side * 170.0]), Color(1.0, 0.95, 0.7, 0.13))
	# guirlande de fanions
	var prev := Vector2(-20, 104)
	for k in 1 + 21:
		var p := Vector2(-20.0 + k * 66.0, 104.0 + sin(k / 21.0 * PI * 3.0) * 14.0)
		if k > 0:
			tent.draw_line(prev, p, UI.DARK, 3.0)
			var mid := (prev + p) / 2.0
			var tri := PackedVector2Array([mid + Vector2(-20, -2), mid + Vector2(20, -2), mid + Vector2(0, 30)])
			tent.draw_colored_polygon(tri, BALLOON_COLS[k % 8])
			tent.draw_polyline(PackedVector2Array([tri[0], tri[2], tri[1]]), UI.DARK, 2.5)
		prev = p
	# rideaux sur les côtés
	for s in [0, 1]:
		var x := 0.0 if s == 0 else 1280.0
		var w := 70.0
		var poly := PackedVector2Array()
		poly.append(Vector2(x, -10))
		for k in 13:
			var y := k * 60.0
			var bulge := w + sin(k * 0.9) * 6.0 - (22.0 if y > 300 and y < 420 else 0.0)
			poly.append(Vector2(x + (bulge if s == 0 else -bulge), y))
		poly.append(Vector2(x, 740))
		tent.draw_colored_polygon(poly, Color("#b81f35"))
		tent.draw_polyline(poly, UI.DARK, 4.0)
		for k in 3:
			var lx := x + (18.0 + k * 16.0 if s == 0 else -18.0 - k * 16.0)
			tent.draw_line(Vector2(lx, 0), Vector2(lx, 720), Color("#8e1426"), 3.0)
		tent.draw_circle(Vector2(x + (52.0 if s == 0 else -52.0), 360), 11.0, UI.DARK)
		tent.draw_circle(Vector2(x + (52.0 if s == 0 else -52.0), 360), 8.0, Color("#f2c14e"))
	# piste (sol)
	tent.draw_rect(Rect2(-50, FLOOR, 1380, 120), Color("#7a1f2b"))
	tent.draw_rect(Rect2(-50, FLOOR, 1380, 16), Color("#f2c14e"))
	tent.draw_line(Vector2(-50, FLOOR), Vector2(1330, FLOOR), UI.DARK, 4.0)
	tent.draw_line(Vector2(-50, FLOOR + 16), Vector2(1330, FLOOR + 16), UI.DARK, 3.0)
	for k in 9:
		var c := Vector2(100 + k * 135.0, FLOOR + 62)
		_star(tent, c, 14.0, Color("#f2c14e"))


func _star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var p := PackedVector2Array()
	for k in 10:
		var a := -PI / 2.0 + k * PI / 5.0
		p.append(c + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.45))
	ci.draw_colored_polygon(p, col)


func _draw_pads() -> void:
	for i in 3:
		var x := float(PAD_X[i])
		var on := pads_on
		var y := PAD_Y + (0.0 if on else 18.0)
		var a := 1.0 if on else 0.55
		var col: Color = PAD_COLS[i]
		var good := phase == "reveal" and round_i >= 0 and i == int(rounds[round_i]["correct"])
		if good:
			col = UI.GREEN
		var r := Rect2(x - PAD_W / 2.0, y, PAD_W, 26.0)
		pad_layer.draw_rect(Rect2(x - 40.0, y + 20.0, 80.0, FLOOR - y - 20.0), Color(UI.DARK, a))
		pad_layer.draw_rect(Rect2(x - 33.0, y + 20.0, 66.0, FLOOR - y - 20.0), Color(col.darkened(0.25), a))
		for k in 3:
			pad_layer.draw_rect(Rect2(x - 33.0 + k * 22.0 + 6.0, y + 20.0, 8.0, FLOOR - y - 20.0), Color(1, 1, 1, 0.35 * a))
		pad_layer.draw_style_box(UI.box(Color(col, a), Color(UI.DARK, a), 4, 12), r)
		pad_layer.draw_rect(Rect2(r.position + Vector2(10, 5), Vector2(PAD_W - 20, 5)), Color(1, 1, 1, 0.4 * a))


func _draw_front() -> void:
	if round_i < 0 or round_i >= rounds.size():
		return
	var q: Dictionary = rounds[round_i]
	# ballons
	var show_balloons: bool = phase == "show" or (q["type"] == "shell" and phase in ["ask", "reveal"])
	if show_balloons:
		var tt := phase_t if phase == "show" else 999.0
		var bl := _balloons(q, tt if phase == "show" else show_total(q) - 0.01)
		for b in bl:
			var idx: int = b[4]
			var face: bool = b[2]
			var sxv: float = b[3]
			if q["type"] == "shell" and phase == "reveal":
				face = phase_t > 0.2
				sxv = absf(cos(clampf(phase_t / 0.4, 0.0, 1.0) * PI))
			var col: Color = q["color"] if q["type"] == "shell" else q["cols"][idx % 12]
			_draw_balloon(b[0], b[1], col, str(q["items"][idx]), face, sxv)
	# cartes réponses + têtes verrouillées
	if phase in ["ask", "reveal"]:
		for i in 3:
			var ans: String = q["answers"][i]
			var x := float(PAD_X[i])
			var good := phase == "reveal" and i == int(q["correct"])
			var bad := phase == "reveal" and not good
			if ans != "pos":
				var cr := Rect2(x - 78.0, CARD_Y, 156.0, 104.0)
				var bg := UI.WHITE if not good else Color("#d9f7d2")
				front.draw_style_box(UI.box(Color(bg, 0.5 if bad else 1.0), Color(UI.DARK, 0.5 if bad else 1.0), 5, 18), cr)
				if ans.begins_with("img:"):
					_draw_item(front, ans.substr(4), cr.get_center(), 78.0)
				else:
					UI.text(front, cr.get_center(), ans, 64, UI.DARK, 0)
				if bad:
					front.draw_rect(cr, Color(1, 1, 1, 0.45))
			if good:
				var pc := Vector2(x, 330.0 if ans == "pos" else CARD_Y + 104.0)
				front.draw_circle(pc, 22.0, UI.DARK)
				front.draw_circle(pc, 18.0, UI.GREEN)
				front.draw_polyline(PackedVector2Array([pc + Vector2(-9, 0), pc + Vector2(-2, 7), pc + Vector2(10, -7)]), UI.WHITE, 5.0)
		# qui a répondu où
		var per_pad := [[], [], []]
		for id in locks:
			var l: Array = locks[id]
			per_pad[int(l[0])].append([int(l[1]), id])
		for i in 3:
			var lst: Array = per_pad[i]
			lst.sort()
			for k in lst.size():
				var id: int = lst[k][1]
				var hc := Vector2(float(PAD_X[i]) - (lst.size() - 1) * 17.0 + k * 34.0, CARD_Y - 26.0 if q["answers"][i] != "pos" else PAD_Y - 96.0)
				front.draw_circle(hc, 17.0, UI.DARK)
				front.draw_circle(hc, 14.0, Net.color_of(id).lerp(Color.WHITE, 0.4))
				front.draw_set_transform(hc + Vector2(0, 13), 0.0, Vector2(0.11, 0.11))
				front.draw_texture(UI.char_tex(Net.color_idx(id), "idle"), Vector2(-128, -256))
				front.draw_set_transform(Vector2.ZERO)


func _draw_extra_hud() -> void:
	# scores en haut
	var ids := nodes.keys()
	ids.sort()
	var w := 70.0
	var x0 := 640.0 - ids.size() * w / 2.0
	for i in ids.size():
		var id: int = ids[i]
		var c := Vector2(x0 + i * w + w / 2.0, 38)
		hud.draw_circle(c, 25, UI.DARK)
		hud.draw_circle(c, 21, Net.color_of(id).lerp(Color.WHITE, 0.55))
		hud.draw_set_transform(c + Vector2(0, 18), 0.0, Vector2(0.15, 0.15))
		hud.draw_texture(UI.char_tex(Net.color_idx(id), "idle"), Vector2(-128, -256))
		hud.draw_set_transform(Vector2.ZERO)
		var sr := Rect2(c + Vector2(-26, 24), Vector2(52, 28))
		hud.draw_style_box(UI.box(UI.WHITE, UI.DARK, 3, 10), sr)
		UI.text(hud, sr.get_center(), str(int(totals.get(id, 0))), 20, UI.DARK, 0)
		if id == Net.my_id():
			hud.draw_rect(Rect2(c + Vector2(-16, 56), Vector2(32, 5)), Net.color_of(id))
	if state == "intro" or round_i < 0:
		return
	var rr := Rect2(Vector2(24, 18), Vector2(178, 46))
	hud.draw_style_box(UI.box(UI.WHITE, UI.DARK, 4, 14), rr)
	UI.text(hud, rr.get_center(), "Question %d / %d" % [round_i + 1, ROUNDS], 22, UI.DARK, 0)
	var q: Dictionary = rounds[mini(round_i, ROUNDS - 1)]
	if phase == "show" and phase_t < 1.2:
		var s := 1.0 + maxf(0.0, 0.4 - phase_t) * 1.2
		UI.text(hud, Vector2(640, 420), "Regarde bien !", int(48 * s), Color(UI.YELLOW, minf(1.0, (1.2 - phase_t) * 3.0)), 12)
	if phase in ["ask", "reveal"]:
		var qtxt: String = q["question"]
		var tw := UI.text_width(qtxt, 34)
		var iw := 58.0 if q.has("icon") else 0.0
		var bw := tw + iw + 56.0
		var br := Rect2(Vector2(640 - bw / 2.0, 112), Vector2(bw, 66))
		hud.draw_style_box(UI.box(UI.WHITE, UI.DARK, 5, 20), br)
		UI.text(hud, Vector2(br.position.x + 28.0 + tw / 2.0, 143), qtxt, 34, UI.DARK, 0)
		if q.has("icon"):
			_draw_item(hud, str(q["icon"]), Vector2(br.position.x + 28.0 + tw + 12.0 + 23.0, 143), 46.0)
		if phase == "ask":
			var left := clampf(1.0 - phase_t / ASK, 0.0, 1.0)
			var bar := Rect2(Vector2(br.position.x + 14.0, br.end.y - 12.0), Vector2((br.size.x - 28.0), 7.0))
			hud.draw_rect(bar, Color(UI.DARK, 0.15))
			hud.draw_rect(Rect2(bar.position, Vector2(bar.size.x * left, bar.size.y)), UI.RED if left < 0.3 else UI.GREEN)
			if my_lock < 0 and me and not me.dead:
				UI.text(hud, Vector2(640, 214), "Saute sur la bonne estrade !", 26, UI.WHITE, 8)
