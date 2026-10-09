extends Node2D
## Fusées en folie : course verticale jusqu'à la Lune.
## ← → pour slalomer entre les astéroïdes et les soucoupes, ↑ pour accélérer, ↓ pour freiner.
## Les étoiles donnent un turbo. Le premier arrivé gagne.

const W := 1600.0                 # largeur du terrain (unités du monde)
const GOAL := 15000.0             # altitude de l'arrivée
const MAX_T := 90.0
const ZOOM := 0.8
const ROCKET_Y := 730.0           # hauteur de ma fusée dans la vue (avant zoom)
const VIEW_H := 900.0             # 720 / ZOOM
const ROCKS := ["rock_round1", "rock_round2", "rock_round3", "rock_round4", "rock_brown1", "rock_brown2",
	"rock_brown3", "rock_brown4", "rock_grey1", "rock_grey2", "rock_grey3", "rock_grey4"]
const UFOS := ["ufo_blue", "ufo_green", "ufo_pink", "ufo_yellow", "ufo_beige"]

const SOFT := Color(0.33, 0.35, 0.43, 0.55)   # bord doux (style pastel)
var ids: Array = []
var ships: Dictionary = {}        # id -> {x, a, st, snaps, puff}
var me_id := 0
var playing := false
var hud: Control
var view: Node2D
var state := "intro"
var t := 0.0
var race_t := 0.0
var my_ready := false
var go_received := false
var ready_ids: Array = []
var rng := RandomNumberGenerator.new()
var brng := RandomNumberGenerator.new()
var obs: Array = []               # {k: rock/ufo/star, a, x0, r, amp, w, ph, tex, rot}
var taken := {}                   # étoiles déjà prises (chez moi)
var ranks := {}

# ma fusée
var x := 0.0
var alt := 0.0
var vx := 0.0
var vy := 0.0
var stun_t := 0.0
var inv_t := 0.0
var boost_t := 0.0
var finished := false
var finish_t := 0.0
var my_rank := 1
var send_acc := 0.0
var prog_acc := 0.0
var shake := 0.0
var cam_a := 0.0
var spec_id := 0
var pops: Array = []
var puffs: Array = []             # fumée : [x, a, t, taille]
var bot_tx := 800.0
var bot_acc := 0.0
var bot_up := true

# hôte
var host_finish: Dictionary = {}
var host_prog: Dictionary = {}
var host_first_t := -1.0
var _tex := {}


func _ready() -> void:
	rng.seed = int(Net.mg_data.get("seed", 1))
	brng.randomize()
	for id in Net.mg_data.get("players", Net.players.keys()):
		if Net.players.has(id):
			ids.append(id)
	ids.sort()
	me_id = Net.my_id()
	playing = ids.has(me_id)
	for i in ids.size():
		var id: int = ids[i]
		var sx := W * float(i + 1) / float(ids.size() + 1)
		ships[id] = {"x": sx, "a": 0.0, "st": 0, "snaps": [], "puff": 0.0, "vx": 0.0}
		_tex["face_%d" % id] = UI.char_tex(Net.color_idx(id), "front")
		ranks[id] = 1
		if id == me_id:
			x = sx
	for n in ROCKS + UFOS + ["star", "bolt"]:
		_tex[n] = load("res://assets/space/%s.png" % n)
	for n in ["cloud1", "cloud2", "cloud3", "cloud5", "cloud7"]:
		_tex[n] = load("res://assets/deco/%s.png" % n)
	_tex["flag"] = load("res://assets/tiles/flag_red_a.png")
	_build_course()
	view = Node2D.new()
	view.scale = Vector2(ZOOM, ZOOM)
	add_child(view)
	view.draw.connect(_draw_view)
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	ui.add_child(hud)
	Net.remote_state.connect(_on_remote_state)
	Net.mg_msg.connect(_on_mg_msg)
	Net.mg_state.connect(_on_mg_state)
	Net.mg_ending.connect(_on_ending)
	Net.mg_ready_changed.connect(func(r): ready_ids = r)
	Net.mg_go.connect(func(): go_received = true)
	Net.players_changed.connect(_on_players_changed)


## Le parcours est le même pour tout le monde (même graine).
func _build_course() -> void:
	var a := 950.0
	while a < GOAL - 450.0:
		var diff := a / GOAL
		var roll := rng.randf()
		if roll < 0.42:
			# quelques astéroïdes, certains dérivent
			var n := 1 + rng.randi_range(0, 1 + int(diff * 2.5))
			for i in n:
				var moving := rng.randf() < 0.35 + diff * 0.3
				obs.append({"k": "rock", "a": a + rng.randf_range(-70, 70), "x0": rng.randf_range(110, W - 110),
					"r": rng.randf_range(48, 82), "amp": rng.randf_range(90, 260) if moving else 0.0,
					"w": rng.randf_range(0.5, 1.3), "ph": rng.randf() * TAU, "tex": ROCKS[rng.randi() % ROCKS.size()],
					"rot": rng.randf_range(-0.8, 0.8)})
			if rng.randf() < 0.3:
				obs.append({"k": "star", "a": a + rng.randf_range(120, 170), "x0": rng.randf_range(150, W - 150),
					"r": 34.0, "amp": 0.0, "w": 0.0, "ph": 0.0, "tex": "star", "rot": 0.0})
		elif roll < 0.62:
			# soucoupe qui fait des allers-retours
			obs.append({"k": "ufo", "a": a, "x0": W / 2.0, "r": 62.0, "amp": rng.randf_range(380, 640),
				"w": rng.randf_range(0.7, 1.3 + diff * 0.5), "ph": rng.randf() * TAU,
				"tex": UFOS[rng.randi() % UFOS.size()], "rot": 0.0})
		elif roll < 0.86:
			# ceinture d'astéroïdes avec un trou
			var gap := rng.randf_range(260, W - 260)
			var gw := 330.0 - diff * 70.0
			var bx := 60.0
			while bx < W - 40.0:
				if absf(bx - gap) > gw / 2.0 + 50.0:
					obs.append({"k": "rock", "a": a + rng.randf_range(-18, 18), "x0": bx, "r": rng.randf_range(46, 58),
						"amp": 0.0, "w": 0.0, "ph": 0.0, "tex": ROCKS[rng.randi() % ROCKS.size()], "rot": rng.randf_range(-0.5, 0.5)})
				bx += 118.0
			if rng.randf() < 0.45:
				obs.append({"k": "star", "a": a, "x0": gap, "r": 34.0, "amp": 0.0, "w": 0.0, "ph": 0.0, "tex": "star", "rot": 0.0})
		else:
			# étoiles bonus et un caillou qui traverse
			for i in rng.randi_range(2, 3):
				obs.append({"k": "star", "a": a + i * 110.0, "x0": rng.randf_range(150, W - 150), "r": 34.0,
					"amp": 0.0, "w": 0.0, "ph": 0.0, "tex": "star", "rot": 0.0})
			obs.append({"k": "rock", "a": a + 160.0, "x0": W / 2.0, "r": 70.0, "amp": 620.0, "w": rng.randf_range(0.8, 1.2),
				"ph": rng.randf() * TAU, "tex": ROCKS[rng.randi() % 4], "rot": 1.2})
		a += 360.0 - diff * 90.0 + rng.randf_range(0, 90)


func _obs_x(o: Dictionary, at: float) -> float:
	return float(o["x0"]) + float(o["amp"]) * sin(float(o["w"]) * at + float(o["ph"]))


func _on_ending() -> void:
	state = "over"
	t = 0.0
	Sfx.play("bell", -2.0, 0.0)


func _on_players_changed() -> void:
	for id in ships.keys():
		if not Net.players.has(id):
			ships.erase(id)
			ids.erase(id)


# ------------------------------------------------------------------ réseau
func _on_remote_state(id: int, p: Vector2, vel: Vector2, st: int) -> void:
	if not ships.has(id) or id == me_id:
		return
	var s: Dictionary = ships[id]
	var snaps: Array = s["snaps"]
	snaps.append([Time.get_ticks_msec() / 1000.0, p, vel, st])
	if snaps.size() > 12:
		snaps.pop_front()


func _on_mg_msg(from_id: int, d: Dictionary) -> void:
	if d.has("prog"):
		host_prog[from_id] = float(d["prog"])
	if d.has("finish") and not host_finish.has(from_id):
		host_finish[from_id] = float(d["finish"])
		if host_first_t < 0.0:
			host_first_t = race_t
		Net.mg_broadcast({"finished": host_finish})


func _on_mg_state(d: Dictionary) -> void:
	if d.has("finished"):
		host_finish = d["finished"]


func host_scores() -> Dictionary:
	var out := {}
	for id in ships:
		if host_finish.has(id):
			var ft: float = host_finish[id]
			out[id] = [1.0e7 - ft * 100.0, "Arrivé en %.1f s" % ft]
		else:
			var pr := float(host_prog.get(id, 0.0))
			out[id] = [pr, "Altitude : %d %%" % int(clampf(pr / GOAL, 0.0, 1.0) * 100.0)]
	return out


# ------------------------------------------------------------------ boucle
func _process(delta: float) -> void:
	t += delta
	match state:
		"intro":
			if not my_ready and t > 0.6 and playing:
				if (Net.autotest != "" and t > 1.0) or Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("push"):
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
				state = "race"
				t = 0.0
				Sfx.voice("go")
				Sfx.play("whoosh", -2.0)
		"race":
			race_t += delta
			if playing:
				_step(delta)
			if Net.is_host():
				var all_done := true
				for id in ships:
					if Net.players.has(id) and not host_finish.has(id):
						all_done = false
				if all_done or (host_first_t >= 0.0 and race_t > host_first_t + 15.0) or race_t > MAX_T:
					state = "ending"
					Net.mg_end_with_scores(host_scores())
	_update_remotes()
	_compute_ranks()
	# fumée derrière chaque fusée
	for id in ships:
		var s: Dictionary = ships[id]
		s["puff"] = float(s["puff"]) + delta
		if float(s["puff"]) > 0.045 and (state == "race" or state == "count"):
			s["puff"] = 0.0
			var boosting := (int(s["st"]) & 4) != 0
			puffs.append([float(s["x"]) + randf_range(-8, 8), float(s["a"]) - 52.0, 0.0, 1.5 if boosting else 1.0])
	for p in puffs:
		p[2] = float(p[2]) + delta
	puffs = puffs.filter(func(p): return float(p[2]) < 0.9)
	# caméra
	var focus := alt
	if not playing or finished:
		var cands := []
		for id in ids:
			if ships.has(id) and (int(ships[id]["st"]) & 2) == 0 and id != me_id:
				cands.append(id)
		if cands.size() > 0 and (not playing or race_t - finish_t > 1.5):
			if not cands.has(spec_id):
				spec_id = cands[0]
			if Input.is_action_just_pressed("left") or Input.is_action_just_pressed("right"):
				var i := cands.find(spec_id) + (1 if Input.is_action_just_pressed("right") else -1)
				spec_id = cands[(i + cands.size()) % cands.size()]
			focus = float(ships[spec_id]["a"])
		else:
			spec_id = 0
			if not playing:
				var best := 0.0
				for id in ships:
					best = maxf(best, float(ships[id]["a"]))
				focus = best
	cam_a = lerpf(cam_a, focus, 1.0 - exp(-delta * 9.0))
	shake = maxf(0.0, shake - delta * 2.5)
	for p in pops:
		p["t"] = float(p["t"]) + delta
	pops = pops.filter(func(p): return float(p["t"]) < 1.0)
	view.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * 14.0
	view.queue_redraw()
	hud.queue_redraw()


func _step(dt: float) -> void:
	inv_t = maxf(0.0, inv_t - dt)
	boost_t = maxf(0.0, boost_t - dt)
	if finished:
		# on se pose tranquillement près de la Lune
		vy = move_toward(vy, 0.0, 500.0 * dt)
		vx = move_toward(vx, 0.0, 1500.0 * dt)
		alt = minf(alt + vy * dt, GOAL + 260.0)
		x += vx * dt
		_send(dt)
		return
	var inp := _bot_input(dt) if Net.autotest != "" else {
		"l": Input.is_action_pressed("left"), "r": Input.is_action_pressed("right"),
		"u": Input.is_action_pressed("up") or Input.is_action_pressed("jump"), "d": Input.is_action_pressed("down")}
	if stun_t > 0.0:
		stun_t -= dt
		vy = move_toward(vy, 90.0, 900.0 * dt)
		vx = move_toward(vx, 0.0, 1200.0 * dt)
	else:
		var target := 400.0
		if inp["u"]:
			target = 600.0
		elif inp["d"]:
			target = 220.0
		if boost_t > 0.0:
			target = 850.0
		vy = move_toward(vy, target, (1500.0 if boost_t > 0.0 else 650.0) * dt)
		var dir := (1.0 if inp["r"] else 0.0) - (1.0 if inp["l"] else 0.0)
		if dir != 0.0:
			vx = move_toward(vx, dir * 540.0, 2800.0 * dt)
		else:
			vx = move_toward(vx, 0.0, 2000.0 * dt)
	x += vx * dt
	if x < 60.0 or x > W - 60.0:
		x = clampf(x, 60.0, W - 60.0)
		vx = 0.0
	alt += vy * dt
	# collisions
	for i in obs.size():
		var o: Dictionary = obs[i]
		var oa: float = o["a"]
		if absf(oa - alt) > 160.0:
			continue
		var ox := _obs_x(o, race_t)
		var r: float = o["r"]
		if o["k"] == "star":
			if not taken.has(i) and Vector2(ox - x, oa - alt).length() < r + 34.0:
				taken[i] = true
				boost_t = 1.6
				Sfx.play("gem", -2.0)
				pops.append({"x": ox, "a": oa + 40.0, "txt": "TURBO !", "t": 0.0, "c": UI.YELLOW})
			continue
		if inv_t > 0.0:
			continue
		var hr := r * (0.78 if o["k"] == "rock" else 0.7)
		var hit := false
		for c in [[18.0, 19.0], [-16.0, 23.0]]:
			if Vector2(ox - x, oa - (alt + float(c[0]))).length() < hr + float(c[1]):
				hit = true
		if hit:
			stun_t = 0.8
			inv_t = 2.2
			vy = -160.0
			vx = signf(x - ox) * 260.0
			boost_t = 0.0
			shake = 1.0
			Sfx.play("hurt", -2.0)
			Sfx.play("bump", -4.0)
			pops.append({"x": x, "a": alt + 70.0, "txt": "BOUM !", "t": 0.0, "c": UI.RED})
			break
	if alt >= GOAL and not finished:
		finished = true
		finish_t = race_t
		Net.mg_to_host({"finish": finish_t})
		Sfx.play("jingle_good", -2.0, 0.0)
		pops.append({"x": x, "a": alt + 80.0, "txt": "ARRIVÉ !", "t": 0.0, "c": UI.GREEN})
	_send(dt)


func _send(dt: float) -> void:
	ships[me_id]["x"] = x
	ships[me_id]["a"] = alt
	ships[me_id]["st"] = _pack()
	ships[me_id]["vx"] = vx
	send_acc += dt
	if send_acc >= 1.0 / 20.0:
		send_acc = 0.0
		Net.send_state(Vector2(x, alt), Vector2(vx, vy), _pack())
	prog_acc += dt
	if prog_acc > 0.5:
		prog_acc = 0.0
		Net.mg_to_host({"prog": alt})


func _pack() -> int:
	return (1 if stun_t > 0.0 else 0) | (2 if finished else 0) | (4 if boost_t > 0.0 else 0) | (8 if inv_t > 0.0 else 0)


## Robot de test : vise l'endroit le plus dégagé un peu plus haut.
func _bot_input(dt: float) -> Dictionary:
	bot_acc += dt
	if bot_acc > 0.14:
		bot_acc = 0.0
		var best_x := x
		var best_s := -1.0e9
		var cand := 110.0
		while cand <= W - 110.0:
			var sc := -absf(cand - x) * 0.12
			var clear := 9999.0
			for i in obs.size():
				var o: Dictionary = obs[i]
				var da: float = float(o["a"]) - alt
				if da < -40.0 or da > 420.0:
					continue
				var tt := race_t + maxf(0.0, da) / maxf(200.0, vy)
				var dx := absf(_obs_x(o, tt) - cand)
				if o["k"] == "star":
					if not taken.has(i) and dx < 60.0:
						sc += 120.0
					continue
				clear = minf(clear, dx - float(o["r"]))
			sc += minf(clear, 260.0)
			if sc > best_s:
				best_s = sc
				best_x = cand
			cand += 70.0
		if brng.randf() < 0.85:
			bot_tx = best_x
		bot_up = best_s > 150.0
	var d := bot_tx - x
	return {"l": d < -25.0, "r": d > 25.0, "u": bot_up, "d": false}


func _update_remotes() -> void:
	var rt := Time.get_ticks_msec() / 1000.0 - 0.1
	for id in ships:
		if id == me_id:
			continue
		var s: Dictionary = ships[id]
		var snaps: Array = s["snaps"]
		if snaps.is_empty():
			continue
		var p: Vector2 = snaps[-1][1]
		var st := int(snaps[-1][3])
		var vel: Vector2 = snaps[-1][2]
		if rt >= float(snaps[-1][0]):
			p = snaps[-1][1] + vel * minf(rt - float(snaps[-1][0]), 0.15)
		else:
			for i in range(snaps.size() - 1, 0, -1):
				var a: Array = snaps[i - 1]
				var b: Array = snaps[i]
				if float(a[0]) <= rt:
					var u := clampf((rt - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0])), 0.0, 1.0)
					p = (a[1] as Vector2).lerp(b[1], u)
					st = int(b[3])
					vel = b[2]
					break
		s["x"] = p.x
		s["a"] = p.y
		s["st"] = st
		s["vx"] = vel.x


func _compute_ranks() -> void:
	var keys := {}
	for id in ships:
		var s: Dictionary = ships[id]
		if host_finish.has(id):
			keys[id] = 1.0e7 - float(host_finish[id])
		elif (int(s["st"]) & 2) != 0:
			keys[id] = 1.0e6 + float(s["a"])
		else:
			keys[id] = float(s["a"])
	for id in keys:
		var r := 1
		for o in keys:
			if o != id and float(keys[o]) > float(keys[id]):
				r += 1
		ranks[id] = r
	if playing:
		my_rank = int(ranks.get(me_id, 1))


# ------------------------------------------------------------------ dessin
func _sy(a: float) -> float:
	return ROCKET_Y - (a - cam_a)


func _sky(a: float) -> Color:
	if a < 1500.0:
		return Color("#9fd8ff")
	if a < 4500.0:
		return Color("#9fd8ff").lerp(Color("#3a3f8f"), (a - 1500.0) / 3000.0)
	if a < 7500.0:
		return Color("#3a3f8f").lerp(Color("#17153a"), (a - 4500.0) / 3000.0)
	return Color("#17153a")


func _h(n: int) -> int:
	var v := (n * 374761393 + 668265263) & 0x7fffffff
	v = ((v ^ (v >> 13)) * 1274126177) & 0x7fffffff
	return v


func _draw_view() -> void:
	var c := view
	var a_top := cam_a + ROCKET_Y
	var a_bot := cam_a + ROCKET_Y - VIEW_H
	# ciel : dégradé selon l'altitude
	var steps := 6
	for i in steps:
		var y0 := VIEW_H * float(i) / steps
		var y1 := VIEW_H * float(i + 1) / steps
		var c0 := _sky(lerpf(a_top, a_bot, float(i) / steps))
		var c1 := _sky(lerpf(a_top, a_bot, float(i + 1) / steps))
		c.draw_polygon(PackedVector2Array([Vector2(-40, y0 - 1), Vector2(W + 40, y0 - 1), Vector2(W + 40, y1 + 1), Vector2(-40, y1 + 1)]),
			PackedColorArray([c0, c0, c1, c1]))
	# étoiles (parallaxe)
	var star_al := clampf((cam_a - 2200.0) / 2500.0, 0.0, 1.0)
	if star_al > 0.0:
		var pa := cam_a * 0.45
		var cell := 260.0
		var j0 := int(floorf((pa - 400.0) / cell))
		for j in range(j0, j0 + int(VIEW_H / cell) + 3):
			for k in 7:
				var hv := _h(j * 13 + k)
				var sx := float(hv % 1600)
				var sa := j * cell + float((hv >> 11) % 260)
				var sy := ROCKET_Y - (sa - pa)
				var tw := 0.6 + 0.4 * sin(t * 3.0 + float(hv % 100))
				var sz := 1.5 + float((hv >> 5) % 3)
				c.draw_circle(Vector2(sx, sy), sz, Color(1, 1, 1, star_al * tw))
	# planètes au loin
	_planet(c, 260.0, 5600.0, 130.0, Color("#f08c3c"), true)
	_planet(c, 1330.0, 8800.0, 170.0, Color("#7b6cf0"), false)
	_planet(c, 330.0, 12100.0, 110.0, Color("#3fc3a8"), true)
	# nuages (en bas)
	if a_bot < 4200.0:
		for j in 22:
			var hv := _h(900 + j)
			var ca := 250.0 + j * 170.0
			var cy := ROCKET_Y - (ca - cam_a * 0.75) * 1.0
			if cy < -150 or cy > VIEW_H + 150:
				continue
			var cx := float(hv % 1800) - 100.0 + sin(t * 0.2 + j) * 30.0
			var tx: Texture2D = _tex[["cloud1", "cloud2", "cloud3", "cloud5", "cloud7"][hv % 5]]
			var al := clampf(1.0 - (ca - 2200.0) / 1600.0, 0.0, 0.9)
			var s := 0.5 + float((hv >> 8) % 5) * 0.1
			c.draw_set_transform(Vector2(cx, cy), 0.0, Vector2(s, s))
			c.draw_texture(tx, -tx.get_size() / 2.0, Color(1, 1, 1, al))
			c.draw_set_transform(Vector2.ZERO)
	# sol et pas de tir
	var gy := _sy(-48.0)
	if gy < VIEW_H + 20:
		c.draw_rect(Rect2(-40, gy, W + 80, 400), Color("#94bc55"))
		c.draw_line(Vector2(-40, gy), Vector2(W + 40, gy), UI.DARK, 4.0)
		for i in ids.size():
			var px := W * float(i + 1) / float(ids.size() + 1)
			var pad := Rect2(Vector2(px - 70, gy - 14), Vector2(140, 22))
			c.draw_style_box(UI.box(Color("#8a8fa8"), UI.DARK, 4, 6), pad)
			c.draw_rect(Rect2(Vector2(px - 60, gy - 9), Vector2(120, 4)), UI.YELLOW)
			# tour de lancement
			c.draw_rect(Rect2(px + 78, gy - 150, 16, 150), UI.DARK)
			c.draw_rect(Rect2(px + 81, gy - 147, 10, 147), Color("#e0643c"))
			for k in 6:
				c.draw_line(Vector2(px + 81, gy - 140 + k * 24), Vector2(px + 91, gy - 128 + k * 24), Color.WHITE, 2.0)
	# Lune et ligne d'arrivée
	_finish(c)
	# obstacles
	for i in obs.size():
		var o: Dictionary = obs[i]
		var sy := _sy(float(o["a"]))
		if sy < -160 or sy > VIEW_H + 160:
			continue
		var ox := _obs_x(o, race_t)
		var r: float = o["r"]
		match str(o["k"]):
			"rock":
				var tx: Texture2D = _tex[o["tex"]]
				var s := r * 2.25 / float(maxi(tx.get_width(), tx.get_height()))
				c.draw_set_transform(Vector2(ox, sy), race_t * float(o["rot"]), Vector2(s, s))
				c.draw_texture(tx, -tx.get_size() / 2.0)
				c.draw_set_transform(Vector2.ZERO)
			"ufo":
				var tx2: Texture2D = _tex[o["tex"]]
				var s2 := r * 2.4 / float(tx2.get_width())
				var tilt := cos(float(o["w"]) * race_t + float(o["ph"])) * 0.18
				c.draw_set_transform(Vector2(ox, sy + sin(t * 4.0 + i) * 5.0), tilt, Vector2(s2, s2))
				c.draw_texture(tx2, -tx2.get_size() / 2.0)
				c.draw_set_transform(Vector2.ZERO)
			"star":
				if taken.has(i):
					continue
				var tx3: Texture2D = _tex["star"]
				var pul := 1.0 + 0.12 * sin(t * 6.0 + i)
				c.draw_circle(Vector2(ox, sy), 46.0 * pul, Color(1, 0.95, 0.55, 0.22))
				c.draw_arc(Vector2(ox, sy), 46.0 * pul, 0, TAU, 32, Color(1, 0.95, 0.55, 0.5), 3.0)
				c.draw_set_transform(Vector2(ox, sy), sin(t * 2.0 + i) * 0.3, Vector2(0.8, 0.8) * pul)
				c.draw_texture(tx3, -tx3.get_size() / 2.0)
				c.draw_set_transform(Vector2.ZERO)
	# fumée
	for p in puffs:
		var k := float(p[2]) / 0.9
		var py := _sy(float(p[1])) + k * 30.0
		c.draw_circle(Vector2(float(p[0]), py), (8.0 + k * 22.0) * float(p[3]), Color(1, 1, 1, 0.5 * (1.0 - k)))
	# fusées : les autres puis moi
	for id in ids:
		if id != me_id and ships.has(id):
			_rocket(c, id)
	if playing and ships.has(me_id):
		_rocket(c, me_id)
	for p in pops:
		var q: float = float(p["t"])
		UI.text(c, Vector2(float(p["x"]), _sy(float(p["a"])) - q * 50.0), p["txt"], 34, Color(p["c"], 1.0 - q * q), 8)
	# repères des fusées hors de l'écran
	for id in ids:
		if not ships.has(id) or (id == me_id and playing):
			continue
		var s: Dictionary = ships[id]
		var sy := _sy(float(s["a"]))
		if sy > -70.0 and sy < VIEW_H + 60.0:
			continue
		var top := sy <= -70.0
		var px := clampf(float(s["x"]), 60.0, W - 140.0)
		var py := 120.0 if top else VIEW_H - 50.0
		var tri := PackedVector2Array([Vector2(px, py + (-30.0 if top else 30.0)), Vector2(px - 16, py + (-12.0 if top else 12.0)), Vector2(px + 16, py + (-12.0 if top else 12.0))])
		c.draw_colored_polygon(tri, UI.DARK)
		c.draw_circle(Vector2(px, py), 22.0, UI.DARK)
		c.draw_circle(Vector2(px, py), 18.0, Net.color_of(id))
		var dist := absf(float(s["a"]) - (alt if playing else cam_a)) / 10.0
		UI.text(c, Vector2(px, py + (32.0 if top else -34.0)), "%d m" % int(dist), 20, UI.WHITE, 6)


func _planet(c: CanvasItem, px: float, pa: float, r: float, col: Color, ring: bool) -> void:
	# parallaxe : la planète « glisse » plus lentement que le reste
	var sy := ROCKET_Y - (pa * 0.55 - cam_a * 0.55)
	if sy < -r - 80 or sy > VIEW_H + r + 80:
		return
	var al := clampf((cam_a - 3000.0) / 2000.0, 0.0, 1.0)
	if al <= 0.0:
		return
	var p := Vector2(px, sy)
	if ring:
		c.draw_set_transform(p, -0.3, Vector2(1.0, 0.28))
		c.draw_arc(Vector2.ZERO, r * 1.65, PI, TAU, 40, Color(SOFT, al), 16.0)
		c.draw_arc(Vector2.ZERO, r * 1.65, PI, TAU, 40, Color(col.lightened(0.4), al), 9.0)
		c.draw_set_transform(Vector2.ZERO)
	c.draw_circle(p, r + 5.0, Color(SOFT, al))
	c.draw_circle(p, r, Color(col, al))
	c.draw_circle(p + Vector2(r * 0.25, r * 0.2), r * 0.72, Color(col.darkened(0.15), al * 0.6))
	c.draw_circle(p + Vector2(-r * 0.35, -r * 0.3), r * 0.22, Color(col.lightened(0.3), al))
	if ring:
		c.draw_set_transform(p, -0.3, Vector2(1.0, 0.28))
		c.draw_arc(Vector2.ZERO, r * 1.65, 0, PI, 40, Color(SOFT, al), 16.0)
		c.draw_arc(Vector2.ZERO, r * 1.65, 0, PI, 40, Color(col.lightened(0.4), al), 9.0)
		c.draw_set_transform(Vector2.ZERO)


func _finish(c: CanvasItem) -> void:
	var fy := _sy(GOAL)
	if fy < -1600 or fy > VIEW_H + 100:
		return
	# la Lune
	var mc := Vector2(W / 2.0, _sy(GOAL + 520.0 + 1500.0))
	c.draw_circle(mc, 1508.0, UI.DARK)
	c.draw_circle(mc, 1500.0, Color("#d9dce8"))
	for k in 9:
		var hv := _h(400 + k)
		var cr := 26.0 + float((hv >> 4) % 50)
		var dx := float(hv % 1300) - 650.0
		var cp := mc + Vector2(dx, sqrt(1500.0 * 1500.0 - dx * dx) - cr - 30.0 - float((hv >> 9) % 300))
		c.draw_circle(cp, cr + 4.0, Color("#a9aec2"))
		c.draw_circle(cp + Vector2(4, -4), cr, Color("#c3c7d6"))
	# ligne d'arrivée en damier
	var cell := 32.0
	for i in int(W / cell) + 2:
		for r in 2:
			var col := Color.WHITE if (i + r) % 2 == 0 else UI.DARK
			c.draw_rect(Rect2(i * cell - 20.0, fy - r * cell, cell, cell), col)
	c.draw_rect(Rect2(-20, fy - cell, W + 40, cell * 2), UI.DARK, false, 4.0)
	var lr := Rect2(Vector2(W / 2.0 - 140, fy - 110), Vector2(280, 64))
	c.draw_style_box(UI.box(UI.YELLOW, UI.DARK, 5, 14), lr)
	UI.text(c, lr.get_center(), "ARRIVÉE", 40, UI.DARK, 0)


func _rocket(c: CanvasItem, id: int) -> void:
	var s: Dictionary = ships[id]
	var st := int(s["st"])
	var p := Vector2(float(s["x"]), _sy(float(s["a"])))
	if p.y < -120 or p.y > VIEW_H + 120:
		return
	var col := Net.color_of(id)
	var ang := clampf(float(s["vx"]) / 540.0, -1.0, 1.0) * 0.22
	if (st & 1) != 0:
		ang = t * 14.0
	var mine := id == me_id and playing
	var sc := 1.0 if mine else 0.92
	c.draw_set_transform(p, ang, Vector2(sc, sc))
	# flamme
	if state != "intro":
		var boost := (st & 4) != 0
		var fl := (26.0 if boost else 16.0) + sin(t * 40.0 + id) * 5.0
		c.draw_colored_polygon(PackedVector2Array([Vector2(-15, 36), Vector2(15, 36), Vector2(0, 36 + fl * 2.2)]), SOFT)
		c.draw_colored_polygon(PackedVector2Array([Vector2(-11, 36), Vector2(11, 36), Vector2(0, 34 + fl * 2.0)]), Color("#f08c3c"))
		c.draw_colored_polygon(PackedVector2Array([Vector2(-6, 36), Vector2(6, 36), Vector2(0, 34 + fl * 1.2)]), Color("#ffe066"))
	# ailerons
	for sd in [-1.0, 1.0]:
		var fin := PackedVector2Array([Vector2(16 * sd, 2), Vector2(38 * sd, 34), Vector2(38 * sd, 46), Vector2(14 * sd, 34)])
		c.draw_colored_polygon(fin, col)
		var fo := fin.duplicate()
		fo.append(fin[0])
		c.draw_polyline(fo, SOFT, 4.0, true)
	# corps
	var body := PackedVector2Array()
	for k in 11:
		var a := PI + k * PI / 10.0
		body.append(Vector2(cos(a) * 22.0, -18.0 + sin(a) * 40.0))
	body.append(Vector2(22, 32))
	body.append(Vector2(16, 40))
	body.append(Vector2(-16, 40))
	body.append(Vector2(-22, 32))
	c.draw_colored_polygon(body, Color("#f4f6fb"))
	# nez coloré
	var nose := PackedVector2Array()
	for k in 11:
		var a := PI + k * PI / 10.0
		nose.append(Vector2(cos(a) * 22.0, -18.0 + sin(a) * 40.0))
	var nose_cut := PackedVector2Array()
	for v in nose:
		if v.y <= -30.0:
			nose_cut.append(v)
	if nose_cut.size() >= 3:
		c.draw_colored_polygon(nose_cut, col)
	c.draw_rect(Rect2(-16, 34, 32, 6), col.darkened(0.2))
	var bo := body.duplicate()
	bo.append(body[0])
	c.draw_polyline(bo, SOFT, 4.0, true)
	# hublot avec le perso dedans
	var face: Texture2D = _tex.get("face_%d" % id)
	c.draw_circle(Vector2(0, -6), 17.0, SOFT)
	c.draw_circle(Vector2(0, -6), 14.0, Color("#bfe6ff"))
	if face:
		c.draw_texture_rect_region(face, Rect2(Vector2(-13, -20), Vector2(26, 26)), Rect2(78, 66, 100, 100))
	c.draw_arc(Vector2(0, -6), 14.0, 0, TAU, 24, SOFT, 3.0)
	c.draw_arc(Vector2(0, -6), 10.0, PI * 1.1, PI * 1.5, 8, Color(1, 1, 1, 0.8), 2.5)
	c.draw_set_transform(Vector2.ZERO)
	# bouclier pendant l'invincibilité (après un choc)
	if (st & 8) != 0 and (st & 1) == 0:
		var pul := 1.0 + 0.05 * sin(t * 14.0)
		c.draw_circle(p, 62.0 * pul, Color(0.6, 0.9, 1.0, 0.18))
		c.draw_arc(p, 62.0 * pul, 0, TAU, 40, Color(0.75, 0.95, 1.0, 0.7), 4.0)
	# nom au-dessus des autres
	if not mine:
		UI.text(c, p + Vector2(0, -74), Net.name_of(id), 20, col, 6)
	elif (st & 2) == 0 and state == "race" and race_t < 4.0:
		UI.text(c, p + Vector2(0, -78), "TOI", 24, UI.YELLOW, 7)


# ------------------------------------------------------------------ HUD
func _draw_hud() -> void:
	var h := hud
	if state == "intro":
		h.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, 0.45))
		var r := Rect2(Vector2(220, 110), Vector2(840, 450))
		h.draw_style_box(UI.box(UI.WHITE, UI.DARK, 6, 30), r)
		UI.text(h, Vector2(640, 176), "Fusées en folie !", 56, UI.YELLOW, 14)
		var lines := ["Course jusqu'à la Lune : le premier arrivé gagne !",
			"← → (ou Q D) : slalome entre les astéroïdes et les soucoupes.",
			"↑ (ou Z) : accélère.   ↓ (ou S) : freine.",
			"Attrape les étoiles pour un TURBO !",
			"Si tu touches un obstacle, ta fusée part en vrille..."]
		for i in lines.size():
			h.draw_string(UI.font(), Vector2(220, 250 + i * 38), lines[i], HORIZONTAL_ALIGNMENT_CENTER, 840, 24, UI.DARK)
		preload("res://minigames/stage.gd").draw_ready_row(h, my_ready, ready_ids, ships.keys(), t, not playing)
		if str(Net.mg_data.get("mode", "")) == "duel":
			preload("res://minigames/stage.gd").draw_duel_banner(h)
		return
	# barre d'altitude (à droite)
	var bar := Rect2(Vector2(1222, 120), Vector2(30, 500))
	h.draw_style_box(UI.box(Color(UI.DARK, 0.55), UI.DARK, 4, 12), bar)
	h.draw_circle(Vector2(1237, 100), 20.0, UI.DARK)
	h.draw_circle(Vector2(1237, 100), 16.0, Color("#d9dce8"))
	h.draw_circle(Vector2(1232, 96), 5.0, Color("#a9aec2"))
	for id in ids:
		if not ships.has(id):
			continue
		var u := clampf(float(ships[id]["a"]) / GOAL, 0.0, 1.0)
		var py := bar.position.y + bar.size.y - 8.0 - (bar.size.y - 16.0) * u
		var big: bool = id == me_id and playing
		h.draw_circle(Vector2(1237, py), 11.0 if big else 8.0, UI.DARK)
		h.draw_circle(Vector2(1237, py), 8.0 if big else 6.0, Net.color_of(id))
	# chrono
	var tr := Rect2(Vector2(24, 18), Vector2(150, 44))
	h.draw_style_box(UI.box(UI.WHITE, UI.DARK, 4, 14), tr)
	var shown := finish_t if finished else race_t
	UI.text(h, tr.get_center(), "%d:%04.1f" % [int(shown) / 60, fmod(shown, 60.0)], 22, UI.DARK, 0)
	if playing:
		var suffix := "er" if my_rank == 1 else "e"
		var pc: Color = [UI.YELLOW, Color("#c9d0dc"), Color("#e09a5a"), UI.WHITE][mini(my_rank - 1, 3)]
		UI.text(h, Vector2(1120, 46), "%d%s" % [my_rank, suffix], 56, pc, 14)
		if boost_t > 0.0 and state == "race":
			UI.text(h, Vector2(640, 120), "TURBO !", int(40 + 6 * sin(t * 20.0)), UI.YELLOW, 10)
		if state == "race" and not finished and race_t < 12.0:
			var help := "← → slalome   ·   ↑ accélère   ·   ↓ freine"
			var hw := UI.text_width(help, 24) + 50.0
			h.draw_style_box(UI.box(Color(UI.DARK, 0.82), UI.DARK, 0, 16), Rect2(Vector2(640 - hw / 2.0, 670), Vector2(hw, 40)))
			UI.text(h, Vector2(640, 690), help, 24, UI.YELLOW, 0)
	if state == "count":
		UI.text(h, Vector2(640, 330), str(3 - int(t)), int(110 * (1.0 + (1.0 - fmod(t, 1.0)) * 0.3)), UI.WHITE, 16)
	elif state == "race" and t < 1.0:
		UI.text(h, Vector2(640, 330), "DÉCOLLAGE !", int(90 * (1.0 + t * 0.3)), Color(UI.GREEN, 1.0 - t), 18)
	if state == "race" and spec_id != 0 and ships.has(spec_id):
		var sm := "Tu regardes %s   (← → pour changer)" % Net.name_of(spec_id)
		var sw := UI.text_width(sm, 20) + 40.0
		h.draw_style_box(UI.box(Color(UI.DARK, 0.8), UI.DARK, 0, 14), Rect2(Vector2(640 - sw / 2.0, 670), Vector2(sw, 40)))
		UI.text(h, Vector2(640, 690), sm, 20, UI.WHITE, 0)
	if finished and state == "race":
		UI.text(h, Vector2(640, 150), "ARRIVÉ ! %d%s" % [my_rank, "er" if my_rank == 1 else "e"], 48, UI.GREEN, 12)
	if state == "over" or state == "ending":
		h.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, minf(0.4, t)))
		UI.text(h, Vector2(640, 360), "TERMINÉ !", 96, UI.YELLOW, 16)
