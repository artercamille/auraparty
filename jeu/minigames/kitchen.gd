extends Node2D
## « Cuisine en folie ! » : jeu COOP façon Overcooked. Toute l'équipe prépare les commandes :
## prendre les ingrédients dans les caisses, couper tomates et oignons sur les planches,
## cuire les steaks sur le feu (attention, ça brûle !), tout mettre dans une assiette et servir à la passe.
## Score d'équipe → rang S / A / B (ou raté) → tout le monde gagne les mêmes pièces.
## L'hôte gère toute la cuisine (objets, planches, feux, commandes) ; chacun déplace son perso.

const TS := 72.0
const COLS := 14
const ROWS := 8
const O := Vector2(640.0 - COLS * TS / 2.0, 120.0)
const LAYOUT := [
	"CCTTOOCCSSBBCC",
	"C............F",
	"X............F",
	"X...CCPPCC...F",
	"C...CCCCCC...C",
	"X............C",
	"C............D",
	"CCCCCWWWCCCCCC",
]
const CRATE := {"T": "tomato", "O": "onion", "S": "steak", "B": "bread"}
const CHOP := {"tomato": "tomato_cut", "onion": "onion_cut"}
const PLATEABLE := ["tomato_cut", "onion_cut", "steak_cooked", "bread"]
const RECIPES := {
	"burger": {"name": "Burger", "in": ["bread", "steak_cooked"], "pts": 20, "icon": "dish_burger"},
	"salad": {"name": "Salade", "in": ["onion_cut", "tomato_cut"], "pts": 20, "icon": "dish_salad"},
	"full": {"name": "Burger garni", "in": ["bread", "onion_cut", "steak_cooked", "tomato_cut"], "pts": 40, "icon": "dish_full"},
}
const COOK := 5.0
const BURN := 13.0
const CHOP_HITS := 6
const ORDER_T := 70.0
const DURATION := 100.0
const P_SPEED := 290.0
const R := 22.0

var ids: Array = []
var me_id := 0
var playing := false
var hud: Control
var view: Node2D
var state := "intro"
var t := 0.0
var play_t := 0.0
var my_ready := false
var go_received := false
var ready_ids: Array = []
var rng := RandomNumberGenerator.new()
var brng := RandomNumberGenerator.new()
var _tex := {}

# état de la cuisine (envoyé par l'hôte)
var tiles := {}                 # index de case -> objet {k, in?}
var held := {}                  # id -> objet ou null
var chop := {}                  # case -> nombre de coups
var cook := {}                  # case -> secondes de cuisson
var orders: Array = []          # {r, left, id}
var score := 0
var served := 0
var pops: Array = []
var result := {}
# persos
var bodies := {}
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var facing := Vector2.DOWN
var send_acc := 0.0
# hôte
var h_next_order := 0.0
var h_order_id := 0
var h_acc := 0.0
var h_done := false
var h_end_t := -1.0
# robot
var bot := {"step": 0, "t": 0.0, "plate": -1, "path": [], "goal": -1, "stove": -1}


func _ready() -> void:
	rng.seed = int(Net.mg_data.get("seed", 1))
	brng.randomize()
	for id in Net.mg_data.get("players", Net.players.keys()):
		if Net.players.has(id):
			ids.append(id)
	ids.sort()
	me_id = Net.my_id()
	playing = ids.has(me_id)
	var starts := [Vector2(2, 1), Vector2(11, 1), Vector2(2, 6), Vector2(11, 6), Vector2(5, 1), Vector2(8, 6), Vector2(5, 6), Vector2(8, 1)]
	for i in ids.size():
		var id: int = ids[i]
		var p := cell_center(int(starts[i % 8].x), int(starts[i % 8].y))
		bodies[id] = {"p": p, "v": Vector2.ZERO, "snaps": [], "face": 1, "walk": 0.0}
		held[id] = null
		if id == me_id:
			pos = p
		for pose in ["idle", "walk_a", "walk_b", "front"]:
			_tex["%d_%s" % [id, pose]] = UI.char_tex(Net.color_idx(id), pose)
	for n in ["tomato", "tomato_cut", "onion", "onion_cut", "steak", "steak_cooked", "bread", "plate", "dish_burger", "dish_full", "dish_salad"]:
		_tex[n] = load("res://assets/coop/%s.png" % n)
	view = Node2D.new()
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(view)
	view.draw.connect(_draw_view)
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	hud.draw.connect(_draw_hud)
	ui.add_child(hud)
	Net.remote_state.connect(_on_remote_state)
	Net.mg_msg.connect(_on_mg_msg)
	Net.mg_state.connect(_on_mg_state)
	Net.mg_ending.connect(func(): state = "over"; t = 0.0)
	Net.mg_ready_changed.connect(func(r): ready_ids = r)
	Net.mg_go.connect(func(): go_received = true)
	Net.players_changed.connect(_on_players_changed)


func _on_players_changed() -> void:
	for id in bodies.keys():
		if not Net.players.has(id):
			bodies.erase(id)
			held.erase(id)
	for id in ids.duplicate():
		if not Net.players.has(id):
			ids.erase(id)


# ------------------------------------------------------------------ grille
func ch(cx: int, cy: int) -> String:
	if cx < 0 or cy < 0 or cx >= COLS or cy >= ROWS:
		return "#"
	return str(LAYOUT[cy])[cx]


func cell_center(cx: int, cy: int) -> Vector2:
	return O + Vector2((cx + 0.5) * TS, (cy + 0.5) * TS)


func idx_of(cx: int, cy: int) -> int:
	return cy * COLS + cx


func idx_ch(i: int) -> String:
	return ch(i % COLS, i / COLS)


func idx_center(i: int) -> Vector2:
	return cell_center(i % COLS, i / COLS)


func solid_at(p: Vector2) -> bool:
	var c := ((p - O) / TS).floor()
	return ch(int(c.x), int(c.y)) != "."


func _collide(p: Vector2) -> bool:
	for off in [Vector2(-R, -R), Vector2(R, -R), Vector2(-R, R), Vector2(R, R), Vector2(0, -R), Vector2(0, R), Vector2(-R, 0), Vector2(R, 0)]:
		if solid_at(p + off * 0.92):
			return true
	return false


## La case visée : celle devant moi, sinon la plus proche case utile.
func target_tile(p: Vector2, f: Vector2) -> int:
	var front := p + f.normalized() * 50.0
	var c := ((front - O) / TS).floor()
	if ch(int(c.x), int(c.y)) not in [".", "#"]:
		return idx_of(int(c.x), int(c.y))
	var best := -1
	var bd := 1e9
	for cy in ROWS:
		for cx in COLS:
			if ch(cx, cy) in [".", "#"]:
				continue
			var cc := cell_center(cx, cy)
			var d := cc.distance_to(p) - maxf(0.0, (cc - p).normalized().dot(f.normalized())) * 20.0
			if d < bd and cc.distance_to(p) < TS * 1.05:
				bd = d
				best = idx_of(cx, cy)
	return best


# ------------------------------------------------------------------ hôte : la cuisine
func _new_order() -> void:
	var keys := RECIPES.keys()
	var r: String = keys[rng.randi_range(0, keys.size() - 1)]
	if play_t < 15.0 and r == "full":
		r = "burger"
	h_order_id += 1
	orders.append({"r": r, "left": ORDER_T, "id": h_order_id})


func _host_step(dt: float) -> void:
	if h_end_t >= 0.0:
		h_end_t -= dt
		if h_end_t <= 0.0:
			h_end_t = -1.0
			var rk := str(result.get("rank", "raté"))
			Net.mg_end_coop(int(result.get("coins", 0)), ("Rang %s : +%d pièces" % [rk, int(result.get("coins", 0))]) if rk != "raté" else "Raté... 0 pièce")
		return
	if h_done:
		return
	var changed := false
	# commandes
	h_next_order -= dt
	if orders.size() < 2 or (h_next_order <= 0.0 and orders.size() < 4):
		_new_order()
		h_next_order = 16.0
		changed = true
	for o in orders.duplicate():
		o["left"] = float(o["left"]) - dt
		if float(o["left"]) <= 0.0:
			orders.erase(o)
			score -= 10
			pops.append({"txt": "Commande ratée ! -10", "c": UI.RED, "t": 0.0})
			Net.mg_broadcast({"pop": "Commande ratée ! -10", "bad": true})
			changed = true
	# cuisson
	for i in tiles.keys():
		if idx_ch(i) != "F":
			continue
		var it: Dictionary = tiles[i]
		var k := str(it["k"])
		if k in ["steak", "steak_cooked"]:
			cook[i] = float(cook.get(i, 0.0)) + dt
			if k == "steak" and float(cook[i]) >= COOK:
				it["k"] = "steak_cooked"
				changed = true
			elif k == "steak_cooked" and float(cook[i]) >= BURN:
				it["k"] = "steak_burnt"
				changed = true
	h_acc += dt
	if changed or h_acc > 0.5:
		h_acc = 0.0
		_broadcast()
	if play_t >= DURATION:
		h_done = true
		var n := ids.size()
		var f := clampf(0.5 + n * 0.125, 0.75, 1.25)
		var rank := "raté"
		var coins := 0
		for r in [["S", 160, 10], ["A", 110, 7], ["B", 60, 4]]:
			if score >= int(round(float(r[1]) * f)):
				rank = str(r[0])
				coins = int(r[2])
				break
		Net.mg_broadcast({"result": rank, "coins": coins, "score": score})
		h_end_t = 2.8
		if Net.autotest != "":
			print("[kitchen] fin score ", score, " plats ", served, " rang ", rank)


func _broadcast() -> void:
	var hd := {}
	for id in held:
		hd[id] = held[id] if held[id] != null else {}
	Net.mg_broadcast({"tiles": tiles.duplicate(true), "held": hd, "chop": chop.duplicate(), "cook": cook.duplicate(),
		"orders": orders.duplicate(true), "score": score, "served": served})


func _on_mg_msg(from_id: int, d: Dictionary) -> void:
	if not Net.is_host() or h_done or state != "play":
		return
	if d.has("use"):
		_use(from_id, int(d["use"]))
		_broadcast()
	elif d.has("chop"):
		_chop(from_id, int(d["chop"]))
		_broadcast()


func _near(id: int, i: int) -> bool:
	if not bodies.has(id):
		return false
	return (bodies[id]["p"] as Vector2).distance_to(idx_center(i)) < TS * 1.9


func _use(id: int, i: int) -> void:
	if i < 0 or not _near(id, i):
		return
	var c := idx_ch(i)
	var h = held.get(id)
	var it = tiles.get(i)
	if CRATE.has(c):
		var ing: String = CRATE[c]
		if h == null:
			held[id] = {"k": ing}
		elif str(h["k"]) == "plate" and ing == "bread":
			_add_to_plate(h, "bread")
		return
	match c:
		"P":
			if h == null:
				held[id] = {"k": "plate", "in": []}
		"D":
			if h != null:
				if str(h["k"]) == "plate":
					h["in"] = []
				else:
					held[id] = null
		"W":
			if h != null and str(h["k"]) == "plate" and (h["in"] as Array).size() > 0:
				_serve(h)
				held[id] = null
		_:
			if h == null and it != null:
				held[id] = it
				tiles.erase(i)
				chop.erase(i)
				cook.erase(i)
			elif h != null and it == null:
				if c == "F" and not str(h["k"]) in ["steak", "steak_cooked", "steak_burnt"]:
					return
				tiles[i] = h
				held[id] = null
				if c == "F":
					cook[i] = COOK if str(h["k"]) == "steak_cooked" else (BURN if str(h["k"]) == "steak_burnt" else 0.0)
			elif h != null and it != null:
				if str(h["k"]) == "plate" and str(it["k"]) in PLATEABLE:
					if _add_to_plate(h, str(it["k"])):
						tiles.erase(i)
						cook.erase(i)
				elif str(it["k"]) == "plate" and str(h["k"]) in PLATEABLE:
					if _add_to_plate(it, str(h["k"])):
						held[id] = null


func _add_to_plate(plate: Dictionary, k: String) -> bool:
	var inside: Array = plate["in"]
	if inside.has(k) or inside.size() >= 4:
		return false
	inside.append(k)
	inside.sort()
	return true


func _chop(id: int, i: int) -> void:
	if i < 0 or idx_ch(i) != "X" or not _near(id, i) or not tiles.has(i):
		return
	var k := str(tiles[i]["k"])
	if not CHOP.has(k):
		return
	chop[i] = int(chop.get(i, 0)) + 1
	if int(chop[i]) >= CHOP_HITS:
		tiles[i] = {"k": CHOP[k]}
		chop.erase(i)


func _serve(plate: Dictionary) -> void:
	var inside: Array = (plate["in"] as Array).duplicate()
	inside.sort()
	for o in orders:
		var need: Array = (RECIPES[str(o["r"])]["in"] as Array).duplicate()
		need.sort()
		if need == inside:
			var pts := int(RECIPES[str(o["r"])]["pts"]) + int(float(o["left"]) / ORDER_T * 10.0)
			score += pts
			served += 1
			orders.erase(o)
			Net.mg_broadcast({"pop": "%s servi ! +%d" % [str(RECIPES[str(o["r"])]["name"]), pts], "bad": false})
			return
	Net.mg_broadcast({"pop": "Ce plat n'est pas commandé !", "bad": true})


func _on_mg_state(d: Dictionary) -> void:
	if d.has("tiles"):
		var nt: Dictionary = d["tiles"]
		tiles = {}
		for k in nt:
			tiles[int(k)] = nt[k]
		var nh: Dictionary = d["held"]
		for k in nh:
			var v: Dictionary = nh[k]
			held[int(k)] = v if not v.is_empty() else null
		chop = {}
		for k in d["chop"]:
			chop[int(k)] = d["chop"][k]
		cook = {}
		for k in d["cook"]:
			cook[int(k)] = float(d["cook"][k])
		orders = d["orders"]
		score = int(d["score"])
		served = int(d["served"])
	elif d.has("pop"):
		pops.append({"txt": str(d["pop"]), "c": UI.RED if d.get("bad", false) else UI.GREEN, "t": 0.0})
		if d.get("bad", false):
			Sfx.play("ui_error", -4.0, 0.0)
		else:
			Sfx.play("bell", -2.0, 0.0)
			Sfx.play("coin", -4.0)
	elif d.has("result"):
		result = {"rank": str(d["result"]), "coins": int(d["coins"])}
		Sfx.play("jingle_bad" if str(d["result"]) == "raté" else "jingle_star", 0.0, 0.0)


# ------------------------------------------------------------------ mon perso
func _step(dt: float) -> void:
	var d := Vector2.ZERO
	var use := false
	var cut := false
	if Net.autotest != "":
		var bi := _bot(dt)
		d = bi[0]
		use = bi[1]
		cut = bi[2]
	else:
		d = Vector2(Input.get_axis("left", "right"), Input.get_axis("up", "down")).limit_length(1.0)
		use = Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("ui_accept")
		cut = Input.is_action_just_pressed("push")
	if d.length() > 0.2:
		facing = d.normalized()
	vel = vel.move_toward(d * P_SPEED, 2600.0 * dt)
	var np := pos + Vector2(vel.x * dt, 0)
	if not _collide(np):
		pos = np
	else:
		vel.x = 0.0
	np = pos + Vector2(0, vel.y * dt)
	if not _collide(np):
		pos = np
	else:
		vel.y = 0.0
	var tgt := target_tile(pos, facing)
	if use and tgt >= 0:
		Net.mg_to_host({"use": tgt})
		Sfx.play("ui_drop", -8.0, 0.1)
	if cut and tgt >= 0 and idx_ch(tgt) == "X":
		Net.mg_to_host({"chop": tgt})
		Sfx.play("card_place", -6.0, 0.15)
	var b: Dictionary = bodies[me_id]
	b["p"] = pos
	b["v"] = vel
	if absf(vel.x) > 20.0:
		b["face"] = 1 if vel.x > 0.0 else -1
	b["walk"] = float(b["walk"]) + vel.length() * dt
	send_acc += dt
	if send_acc >= 1.0 / 30.0:
		send_acc = 0.0
		Net.send_state(pos, vel, 0)


func _on_remote_state(id: int, p: Vector2, v: Vector2, st: int) -> void:
	if not bodies.has(id) or id == me_id:
		return
	var snaps: Array = bodies[id]["snaps"]
	snaps.append([Time.get_ticks_msec() / 1000.0, p, v, st])
	if snaps.size() > 12:
		snaps.pop_front()


func _update_remotes() -> void:
	var rt := Time.get_ticks_msec() / 1000.0 - 0.08
	for id in bodies:
		if id == me_id:
			continue
		var b: Dictionary = bodies[id]
		var snaps: Array = b["snaps"]
		if snaps.is_empty():
			continue
		var p: Vector2 = snaps[-1][1]
		b["v"] = snaps[-1][2]
		if rt < float(snaps[-1][0]):
			for i in range(snaps.size() - 1, 0, -1):
				var a: Array = snaps[i - 1]
				var c: Array = snaps[i]
				if float(a[0]) <= rt:
					p = (a[1] as Vector2).lerp(c[1], clampf((rt - float(a[0])) / maxf(0.001, float(c[0]) - float(a[0])), 0.0, 1.0))
					break
		var old: Vector2 = b["p"]
		b["p"] = p
		if absf(p.x - old.x) > 0.5:
			b["face"] = 1 if p.x > old.x else -1
		b["walk"] = float(b["walk"]) + old.distance_to(p)


# ------------------------------------------------------------------ robot (tests) : fait des burgers en boucle
func _find(chars: String, need_empty: bool, near: Vector2) -> int:
	var best := -1
	var bd := 1e9
	for cy in ROWS:
		for cx in COLS:
			if chars.find(ch(cx, cy)) < 0:
				continue
			var i := idx_of(cx, cy)
			if need_empty and tiles.has(i):
				continue
			if _access(i) == Vector2(-1, -1):
				continue
			var d := cell_center(cx, cy).distance_to(near)
			if d < bd:
				bd = d
				best = i
	return best


func _access(i: int) -> Vector2:
	var cx := i % COLS
	var cy := i / COLS
	for dv in [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]:
		if ch(cx + int(dv.x), cy + int(dv.y)) == ".":
			return Vector2(cx + dv.x, cy + dv.y)
	return Vector2(-1, -1)


func _path_to(cell: Vector2) -> Array:
	var start := ((pos - O) / TS).floor()
	var prev := {start: start}
	var q := [start]
	while not q.is_empty():
		var c: Vector2 = q.pop_front()
		if c == cell:
			break
		for dv in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var n: Vector2 = c + dv
			if not prev.has(n) and ch(int(n.x), int(n.y)) == ".":
				prev[n] = c
				q.append(n)
	if not prev.has(cell):
		return []
	var path := []
	var cur := cell
	while cur != start:
		path.push_front(cur)
		cur = prev[cur]
	return path


func _bot(dt: float) -> Array:
	bot["t"] = float(bot["t"]) + dt
	var h = held.get(me_id)
	var hk := str(h["k"]) if h != null else ""
	var step := int(bot["step"])
	var goal := -1
	match step:
		0:
			goal = _find("P", false, pos) if hk == "" else -1
			if hk == "plate":
				bot["step"] = 1
		1:
			if hk == "plate" and (int(bot["plate"]) == -1 or tiles.has(int(bot["plate"]))):
				bot["plate"] = _find("C", true, O + Vector2(7 * TS, 4 * TS))
			goal = int(bot["plate"])
			if hk == "" and tiles.has(goal) and str(tiles[goal]["k"]) == "plate":
				bot["step"] = 2
		2:
			goal = _find("B", false, pos)
			if hk == "bread":
				bot["step"] = 3
		3:
			goal = int(bot["plate"])
			if hk == "":
				bot["step"] = 4
		4:
			goal = _find("S", false, pos)
			if hk == "steak":
				bot["step"] = 5
				bot["stove"] = _find("F", true, pos)
		5:
			goal = int(bot["stove"])
			if hk == "" and tiles.has(goal):
				var sk := str(tiles[goal]["k"])
				if sk == "steak":
					goal = -2     # on attend la cuisson
				elif sk == "steak_cooked" or sk == "steak_burnt":
					pass
			if hk == "steak_cooked":
				bot["step"] = 6
			elif hk == "steak_burnt":
				bot["step"] = 9
		6:
			goal = int(bot["plate"])
			if hk == "":
				bot["step"] = 7
		7:
			goal = int(bot["plate"])
			if hk == "plate":
				bot["step"] = 8
		8:
			goal = _find("W", false, pos)
			if hk == "":
				bot["step"] = 0
		9:
			goal = _find("D", false, pos)
			if hk == "":
				bot["step"] = 4
	if int(bot["step"]) != step:
		bot["t"] = 0.0
		bot["path"] = []
		return [Vector2.ZERO, false, false]
	if float(bot["t"]) > 14.0:
		# coincé : on jette ce qu'on tient et on recommence
		bot["t"] = 0.0
		bot["step"] = 9 if hk != "" and hk != "plate" else 0
		if hk == "plate":
			bot["step"] = 8
		bot["path"] = []
	if goal < 0:
		return [Vector2.ZERO, false, false]
	var acc := _access(goal)
	var acc_p := cell_center(int(acc.x), int(acc.y))
	if pos.distance_to(acc_p) < 14.0:
		facing = (idx_center(goal) - pos).normalized()
		var use := fmod(float(bot["t"]), 0.5) < dt
		return [Vector2.ZERO, use, false]
	if (bot["path"] as Array).is_empty() or int(bot["goal"]) != goal:
		bot["path"] = _path_to(acc)
		bot["goal"] = goal
	var path: Array = bot["path"]
	if path.is_empty():
		return [(acc_p - pos).normalized(), false, false]
	var wp := cell_center(int(path[0].x), int(path[0].y))
	if pos.distance_to(wp) < 10.0:
		path.pop_front()
	return [(wp - pos).normalized(), false, false]


# ------------------------------------------------------------------ boucle
func _process(delta: float) -> void:
	t += delta
	match state:
		"intro":
			if not my_ready and t > 0.6 and playing:
				if (Net.autotest != "" and t > 1.0 and OS.get_environment("NOREADY") == "") or Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("push"):
					my_ready = true
					Net.mg_set_ready()
					Sfx.play("select", -4.0)
			if go_received:
				state = "count"
				t = 0.0
				Sfx.voice("3")
		"count":
			if int(t) != int(t - delta) and t < 3.0:
				Sfx.voice(str(3 - int(t)))
			if t >= 3.0:
				state = "play"
				t = 0.0
				Sfx.voice("go")
		"play":
			if result.is_empty():
				play_t += delta
				if not Net.is_host():
					for i in cook:
						cook[i] = float(cook[i]) + delta
					for o in orders:
						o["left"] = float(o["left"]) - delta
			if playing:
				_step(delta)
			if Net.is_host():
				_host_step(delta)
	_update_remotes()
	for p in pops:
		p["t"] = float(p["t"]) + delta
	pops = pops.filter(func(p): return float(p["t"]) < 1.8)
	view.queue_redraw()
	hud.queue_redraw()


# ------------------------------------------------------------------ dessin
func _draw_view() -> void:
	var c := view
	c.draw_rect(Rect2(-20, -20, 1320, 760), Color("#f6d6c8"))
	for cy in ROWS:
		for cx in COLS:
			var r := Rect2(O + Vector2(cx, cy) * TS, Vector2(TS, TS))
			var k := ch(cx, cy)
			if k == ".":
				c.draw_rect(r, Color("#fff4e6") if (cx + cy) % 2 == 0 else Color("#ffe8d1"))
	# ombre des comptoirs sur le sol
	for cy in ROWS:
		for cx in COLS:
			if ch(cx, cy) != ".":
				_draw_station(c, cx, cy)
	# objets posés
	for i in tiles:
		_draw_item(c, tiles[i], idx_center(i) + Vector2(0, -6), 1.0)
		if chop.has(i):
			_bar(c, idx_center(i) + Vector2(0, -38), float(chop[i]) / CHOP_HITS, UI.GREEN)
		if cook.has(i) and idx_ch(i) == "F":
			var e := float(cook[i])
			var it: Dictionary = tiles[i]
			if str(it["k"]) == "steak":
				_bar(c, idx_center(i) + Vector2(0, -38), e / COOK, UI.YELLOW)
			elif str(it["k"]) == "steak_cooked" and e > COOK + 3.0:
				var warn := 0.5 + 0.5 * sin(t * 14.0)
				c.draw_circle(idx_center(i) + Vector2(0, -42), 14.0, Color(UI.RED, warn))
				UI.text(c, idx_center(i) + Vector2(0, -42), "!", 22, UI.WHITE, 0)
	# la case que je vise
	if playing and state == "play":
		var tg := target_tile(pos, facing)
		if tg >= 0:
			var rr := Rect2(idx_center(tg) - Vector2(TS, TS) / 2.0, Vector2(TS, TS)).grow(-3)
			c.draw_style_box(UI.box(Color(0, 0, 0, 0), Net.color_of(me_id), 4, 10), rr)
	# persos
	var order := bodies.keys()
	order.sort_custom(func(a, b): return float(bodies[a]["p"].y) < float(bodies[b]["p"].y))
	for id in order:
		_draw_body(c, id)


func _draw_station(c: CanvasItem, cx: int, cy: int) -> void:
	var k := ch(cx, cy)
	var r := Rect2(O + Vector2(cx, cy) * TS, Vector2(TS, TS))
	var top := Color("#e9b77c")
	match k:
		"F":
			top = Color("#6d6a80")
		"D":
			top = Color("#9aa0b4")
		"W":
			top = Color("#ffd23f")
	c.draw_rect(r, top.darkened(0.25))
	c.draw_style_box(UI.box(top, top.lightened(0.25), 3, 8), Rect2(r.position + Vector2(2, 2), r.size - Vector2(4, 12)))
	var cc := r.get_center() + Vector2(0, -5)
	match k:
		"T", "O", "S", "B":
			c.draw_style_box(UI.box(Color("#c9874b"), Color("#8a5a32"), 3, 6), Rect2(cc - Vector2(28, 24), Vector2(56, 48)))
			c.draw_texture_rect(_tex[str(CRATE[k])], Rect2(cc - Vector2(20, 20), Vector2(40, 40)), false)
		"P":
			c.draw_style_box(UI.box(Color("#7fd6ff"), Color("#4b87f5"), 3, 8), Rect2(cc - Vector2(30, 26), Vector2(60, 52)))
			for s in 4:
				c.draw_texture_rect(_tex["plate"], Rect2(cc - Vector2(24, 14 + s * 5), Vector2(48, 34)), false)
		"X":
			c.draw_style_box(UI.box(Color("#f3d29b"), Color("#c9a26a"), 3, 6), Rect2(cc - Vector2(28, 20), Vector2(56, 40)))
			c.draw_line(cc + Vector2(14, -14), cc + Vector2(26, -26), Color("#9aa0b4"), 5.0)
		"F":
			c.draw_circle(cc, 24.0, Color("#3b3550"))
			c.draw_arc(cc, 18.0, 0, TAU, 24, Color("#ff7b2e") if tiles.has(idx_of(cx, cy)) else Color("#55506b"), 3.0)
			if tiles.has(idx_of(cx, cy)):
				for f in 5:
					var a := TAU * f / 5.0 + t * 3.0
					c.draw_circle(cc + Vector2(cos(a), sin(a)) * 22.0, 4.0 + sin(t * 20.0 + f) * 1.5, Color("#ffb627"))
		"D":
			c.draw_style_box(UI.box(Color("#55506b"), Color("#3b3550"), 3, 10), Rect2(cc - Vector2(20, 22), Vector2(40, 44)))
			c.draw_rect(Rect2(cc - Vector2(24, 26), Vector2(48, 8)), Color("#3b3550"))
		"W":
			if cx == 6:
				UI.text(c, cc + Vector2(0, -2), "PASSE", 20, Color("#8a5a32"), 0)
			c.draw_rect(Rect2(r.position + Vector2(0, 50), Vector2(TS, 6)), Color("#ffe27a"))


func _draw_item(c: CanvasItem, it, at: Vector2, k: float) -> void:
	if it == null:
		return
	var kind := str(it["k"])
	if kind == "plate":
		c.draw_texture_rect(_tex["plate"], Rect2(at - Vector2(30, 22) * k, Vector2(60, 44) * k), false)
		var inside: Array = it["in"]
		for j in inside.size():
			var off := Vector2((j % 2) * 20.0 - 10.0, (j / 2) * 12.0 - 10.0) * k
			c.draw_texture_rect(_tex[str(inside[j])], Rect2(at + off - Vector2(15, 15) * k, Vector2(30, 30) * k), false)
		return
	var tx_name := "steak_cooked" if kind == "steak_burnt" else kind
	var col := Color(0.25, 0.2, 0.2) if kind == "steak_burnt" else Color.WHITE
	c.draw_texture_rect(_tex[tx_name], Rect2(at - Vector2(22, 22) * k, Vector2(44, 44) * k), false, col)
	if kind == "steak_burnt":
		for s in 3:
			c.draw_circle(at + Vector2(-8 + s * 8, -22 - fmod(t * 20.0 + s * 7.0, 20.0)) * k, 5.0, Color(0.4, 0.4, 0.45, 0.5))


func _bar(c: CanvasItem, at: Vector2, v: float, col: Color) -> void:
	var r := Rect2(at - Vector2(28, 6), Vector2(56, 12))
	c.draw_style_box(UI.box(UI.WHITE, UI.DARK, 2, 6), r)
	c.draw_rect(Rect2(r.position + Vector2(3, 3), Vector2((r.size.x - 6) * clampf(v, 0.0, 1.0), 6)), col)


func _draw_body(c: CanvasItem, id: int) -> void:
	var b: Dictionary = bodies[id]
	var g: Vector2 = b["p"]
	c.draw_set_transform(g + Vector2(0, 18), 0.0, Vector2(1.0, 0.36))
	c.draw_circle(Vector2.ZERO, 26.0, Color(0, 0, 0, 0.18))
	c.draw_set_transform(Vector2.ZERO)
	var moving := (b["v"] as Vector2).length() > 30.0
	var pose := ("walk_a" if int(float(b["walk"]) / 30.0) % 2 == 0 else "walk_b") if moving else "idle"
	c.draw_set_transform(g + Vector2(0, 22), 0.0, Vector2(0.36 * float(b["face"]), 0.36))
	c.draw_texture(_tex["%d_%s" % [id, pose]], Vector2(-128, -256))
	c.draw_set_transform(Vector2.ZERO)
	var h = held.get(id)
	if h != null:
		_draw_item(c, h, g + Vector2(0, -78), 0.85)
	UI.text(c, g + Vector2(0, -100 if h == null else -112), "TOI" if id == me_id else Net.name_of(id), 15 if id == me_id else 13, UI.YELLOW if id == me_id else Net.color_of(id), 5)


# ------------------------------------------------------------------ HUD
func _draw_hud() -> void:
	var h := hud
	var St := preload("res://minigames/stage.gd")
	if state == "intro":
		St.draw_intro(h, "Cuisine en folie !", [
			"JEU COOP : toute l'équipe tient le restaurant ensemble !",
			"Prends les ingrédients dans les caisses, coupe-les sur les planches,",
			"cuis les steaks sur le feu (ils brûlent si tu les oublies !),",
			"mets tout dans une assiette et sers à la passe.",
			"Burger : pain + steak · Salade : tomate + oignon coupés · Garni : les 4",
			"Plus l'équipe sert de plats, plus chacun gagne de pièces !"],
			"Bouger : flèches ou Z Q S D   ·   Prendre / poser : Espace   ·   Couper : Maj / X (plusieurs fois)")
		St.draw_ready_row(h, my_ready, ready_ids, ids, t, not playing)
		return
	# chrono
	var left := maxf(0.0, DURATION - play_t)
	var tr := Rect2(Vector2(20, 16), Vector2(110, 56))
	UI.panel(h, tr, UI.WHITE, Color("#f6d6c8"), 18, 4)
	UI.text(h, UI.face_center(tr), "%d:%02d" % [int(left) / 60, int(left) % 60], 28, UI.RED if left <= 15.0 else UI.DARK, 0)
	# score
	var sr := Rect2(Vector2(1280 - 170, 16), Vector2(150, 56))
	UI.panel(h, sr, Color("#ffc93c"), UI.WHITE, 18, 4)
	UI.text(h, UI.face_center(sr), "%d pts" % score, 28, UI.WHITE, 6)
	# tickets de commande
	for j in orders.size():
		var o: Dictionary = orders[j]
		var rec: Dictionary = RECIPES[str(o["r"])]
		var r := Rect2(Vector2(150 + j * 236, 10), Vector2(226, 96))
		var urg := float(o["left"]) / ORDER_T
		UI.panel(h, r, UI.WHITE, UI.RED if urg < 0.25 and int(t * 4.0) % 2 == 0 else Color("#e4dcf5"), 14, 4)
		h.draw_texture_rect(_tex[str(rec["icon"])], Rect2(r.position + Vector2(8, 8), Vector2(56, 56)), false)
		UI.text(h, r.position + Vector2(146, 18), str(rec["name"]), 16, UI.DARK, 0)
		var ins: Array = rec["in"]
		for q in ins.size():
			h.draw_texture_rect(_tex[str(ins[q])], Rect2(r.position + Vector2(72 + q * 36, 32), Vector2(32, 32)), false)
		h.draw_rect(Rect2(r.position + Vector2(8, 76), Vector2(210, 10)), Color("#e4dcf5"))
		h.draw_rect(Rect2(r.position + Vector2(8, 76), Vector2(210 * clampf(urg, 0.0, 1.0), 10)), UI.GREEN.lerp(UI.RED, 1.0 - urg))
	for p in pops:
		var k := float(p["t"]) / 1.8
		UI.text(h, Vector2(640, 150 - k * 30.0), str(p["txt"]), 30, Color(p["c"], 1.0 - k * k), 8)
	if state == "count":
		UI.text(h, Vector2(640, 380), str(3 - int(t)), int(110 * (1.0 + (1.0 - fmod(t, 1.0)) * 0.3)), UI.WHITE, 16)
	elif state == "play" and t < 1.0:
		UI.text(h, Vector2(640, 380), "GO !", int(120 * (1.0 + t * 0.4)), Color(UI.YELLOW, 1.0 - t), 18)
	if not result.is_empty():
		preload("res://minigames/penguins.gd")._draw_result(h, result, t)
