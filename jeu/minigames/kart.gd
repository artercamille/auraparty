extends Node2D
## « Grand Prix Aura ! » : course de karts vue de dessus, 3 tours, objets façon Mario Kart
## (banane, carapace, champignon), turbo en dérapage, flèches d'accélération.
## Chacun pilote son kart chez lui (positions envoyées 30 fois par seconde) ;
## l'hôte collecte les arrivées et la progression pour le classement.

const CTRL := [Vector2(800, 2350), Vector2(2000, 2380), Vector2(3200, 2330), Vector2(3950, 2050), Vector2(4150, 1450),
	Vector2(3850, 950), Vector2(3200, 800), Vector2(2700, 1150), Vector2(2150, 1250), Vector2(1700, 850),
	Vector2(1420, 420), Vector2(950, 300), Vector2(500, 550), Vector2(380, 1200), Vector2(450, 1850)]
const HALF := 150.0          # demi-largeur de la piste
const WALL := 345.0          # barrières de pneus
const LAPS := 3
const MAX := 560.0
const ACC := 720.0
const BRAKE := 1300.0
const DRAG := 320.0
const TURN := 2.7
const GRIP := 9.0
const OFF_MAX := 290.0
const KART_R := 31.0
const INTERP := 0.1
const MAX_T := 150.0
const ITEMS := ["banana", "shell", "mushroom"]

var pts := PackedVector2Array()
var cum := PackedFloat32Array()
var L := 0.0
var rng := RandomNumberGenerator.new()

var ids: Array = []
var karts: Dictionary = {}    # id -> {pos, ang, vel, snaps, lap, s, idx, st, spin, boost, drift}
var me_id := 0
var fx: Node2D
var world: Node2D
var ground: Node2D
var dyn: Node2D
var cam: Camera2D
var hud: Control

var state := "intro"          # intro, count, race, over
var t := 0.0
var race_t := 0.0
var intro_len := 7.0

# mon kart
var pos := Vector2.ZERO
var ang := 0.0
var vel := Vector2.ZERO
var idx := 0
var s_now := 0.0
var lap := -1
var finished := false
var finish_t := 0.0
var spin_t := 0.0
var invuln_t := 0.0
var boost_t := 0.0
var drift_t := 0.0
var wall_cd := 0.0
var item := ""
var roulette_t := 0.0
var send_acc := 0.0
var prog_acc := 0.0
var obj_n := 0
var bump_cd := 0.0
var _q_use := false
var my_ready := false
var go_received := false
var ready_ids: Array = []
var spec_id := 0

# monde partagé
var boxes: Array = []         # {p, off_until}
var pads: Array = []          # [pos, ang]
var objs: Dictionary = {}     # oid -> {kind, p, v, t0, owner}
var parts: Array = []
var banner := ""
var banner_t := 0.0
var my_rank := 1

# hôte
var host_finish: Dictionary = {}
var host_prog: Dictionary = {}
var host_first_t := -1.0


var _ktex := {}


func _ready() -> void:
	# textures chargées avant le dessin (sinon elles sortent blanches)
	for n in ["tires_red", "tires_white", "barrier_red_race", "barrier_white_race", "arrow_yellow", "tribune_full", "tribune_overhang_red",
			"tent_red_large", "tent_blue_large", "cone_straight", "barrel_red", "barrel_blue", "barrel_red_down", "tree_large", "tree_small",
			"rock1", "rock2", "rock3"]:
		_ktex[n] = load("res://assets/kart/%s.png" % n)
	rng.seed = int(Net.mg_data.get("seed", 1))
	_build_track()
	world = Node2D.new()
	add_child(world)
	ground = Node2D.new()
	world.add_child(ground)
	ground.draw.connect(_draw_ground)
	dyn = Node2D.new()
	dyn.z_index = 5
	world.add_child(dyn)
	dyn.draw.connect(_draw_dyn)
	fx = preload("res://arena/fx.gd").new()
	fx.world = null
	fx.z_index = 8
	world.add_child(fx)
	cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	cam.zoom = Vector2(1.0, 1.0)
	world.add_child(cam)
	cam.make_current()
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	ui.add_child(hud)

	for id in Net.mg_data.get("players", Net.players.keys()):
		if Net.players.has(id):
			ids.append(id)
	ids.sort()
	me_id = Net.my_id()
	for i in ids.size():
		var id: int = ids[i]
		var gp := _grid_pos(i)
		karts[id] = {"pos": gp, "ang": _dir_at(L - 150.0).angle(), "vel": Vector2.ZERO, "snaps": [], "lap": -1,
			"s": L - 150.0, "idx": 0, "st": 0, "seen": false}
		if id == me_id:
			pos = gp
			ang = _dir_at(L - 150.0).angle()
			idx = _nearest(pos, -1)
			s_now = _s_of(pos, idx)
	cam.position = pos
	cam.reset_smoothing()
	# cubes à objets et flèches d'accélération
	for frac in [0.17, 0.52, 0.8]:
		var s: float = L * frac
		var c := _point_at(s)
		var n := _dir_at(s).orthogonal()
		for k in 4:
			boxes.append({"p": c + n * (-96.0 + k * 64.0), "off_until": -1.0})
	for frac in [0.36, 0.66, 0.93]:
		var s2: float = L * frac
		pads.append([_point_at(s2) + _dir_at(s2).orthogonal() * (45.0 if int(frac * 100) % 2 == 0 else -45.0), _dir_at(s2).angle()])

	Net.remote_state.connect(_on_remote_state)
	Net.mg_msg.connect(_on_mg_msg)
	Net.mg_state.connect(_on_mg_state)
	Net.mg_ending.connect(_on_ending)
	Net.mg_ready_changed.connect(func(r): ready_ids = r)
	Net.mg_go.connect(func(): go_received = true)
	Net.players_changed.connect(_on_players_changed)


func _on_ending() -> void:
	state = "over"
	t = 0.0
	Sfx.play("bell", -2.0, 0.0)


func _on_players_changed() -> void:
	for id in karts.keys():
		if not Net.players.has(id):
			karts.erase(id)


# ------------------------------------------------------------------ piste
func _build_track() -> void:
	var n := CTRL.size()
	for i in n:
		var p0: Vector2 = CTRL[(i - 1 + n) % n]
		var p1: Vector2 = CTRL[i]
		var p2: Vector2 = CTRL[(i + 1) % n]
		var p3: Vector2 = CTRL[(i + 2) % n]
		for k in 30:
			var u := k / 30.0
			var u2 := u * u
			var u3 := u2 * u
			pts.append(0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3))
	cum.append(0.0)
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
	L = cum[pts.size() - 1] + pts[pts.size() - 1].distance_to(pts[0])


func _seg(i: int) -> Array:
	var a := pts[i]
	var b := pts[(i + 1) % pts.size()]
	return [a, b]


func _point_at(s: float) -> Vector2:
	s = fposmod(s, L)
	var i := cum.bsearch(s) - 1
	i = clampi(i, 0, pts.size() - 1)
	var a := pts[i]
	var b := pts[(i + 1) % pts.size()]
	var seg := a.distance_to(b)
	return a.lerp(b, clampf((s - cum[i]) / maxf(seg, 0.001), 0.0, 1.0))


func _dir_at(s: float) -> Vector2:
	return (_point_at(s + 20.0) - _point_at(s - 20.0)).normalized()


## Index du segment le plus proche (recherche locale autour de hint, ou complète si hint < 0).
func _nearest(p: Vector2, hint: int) -> int:
	var best := 0
	var bd := 1e18
	if hint < 0:
		for i in pts.size():
			var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[(i + 1) % pts.size()])
			var d := q.distance_squared_to(p)
			if d < bd:
				bd = d
				best = i
		return best
	for k in range(-25, 26):
		var i := (hint + k + pts.size()) % pts.size()
		var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[(i + 1) % pts.size()])
		var d := q.distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func _s_of(p: Vector2, i: int) -> float:
	var a := pts[i]
	var b := pts[(i + 1) % pts.size()]
	var q := Geometry2D.get_closest_point_to_segment(p, a, b)
	return cum[i] + a.distance_to(q)


## [distance signée au centre de la piste, normale]
func _side(p: Vector2, i: int) -> Array:
	var a := pts[i]
	var b := pts[(i + 1) % pts.size()]
	var q := Geometry2D.get_closest_point_to_segment(p, a, b)
	var n := (b - a).normalized().orthogonal()
	var d := (p - q).dot(n)
	return [d, n, q]


func _grid_pos(i: int) -> Vector2:
	var s := L - 130.0 - (i / 2) * 105.0
	return _point_at(s) + _dir_at(s).orthogonal() * (-55.0 if i % 2 == 0 else 55.0)


# ------------------------------------------------------------------ réseau
func _on_remote_state(id: int, p: Vector2, v: Vector2, st: int) -> void:
	if not karts.has(id) or id == me_id:
		return
	var k: Dictionary = karts[id]
	var snaps: Array = k["snaps"]
	snaps.append([Time.get_ticks_msec() / 1000.0, p, v, st])
	if snaps.size() > 20:
		snaps.pop_front()
	if not k["seen"]:
		k["seen"] = true
		k["pos"] = p
		k["idx"] = _nearest(p, -1)


func _pack() -> int:
	var a := int(fposmod(rad_to_deg(ang), 360.0) * 10.0) & 4095
	var fl := (1 if spin_t > 0.0 else 0) | (2 if boost_t > 0.0 else 0) | ((2 if drift_t > 1.3 else (1 if drift_t > 0.6 else 0)) << 2)
	return a | (fl << 12) | ((clampi(lap + 1, 0, 7)) << 16) | ((1 if finished else 0) << 19)


func _spawn_obj(kind: String, p: Vector2, v: Vector2) -> void:
	obj_n += 1
	var oid := "%d_%d" % [me_id, obj_n]
	objs[oid] = {"kind": kind, "p": p, "v": v, "t0": t, "owner": me_id}
	Net.mg_to_host({"spawn": kind, "oid": oid, "p": p, "v": v})


func _kill_obj(oid: String) -> void:
	objs.erase(oid)
	Net.mg_to_host({"kill": oid})


func _on_mg_msg(from_id: int, d: Dictionary) -> void:
	# hôte : relaie à tout le monde, et note la progression
	if d.has("spawn") or d.has("kill") or d.has("box"):
		var out := d.duplicate()
		out["from"] = from_id
		Net.mg_broadcast(out)
	if d.has("prog"):
		host_prog[from_id] = float(d["prog"])
	if d.has("finish") and not host_finish.has(from_id):
		host_finish[from_id] = float(d["finish"])
		if host_first_t < 0.0:
			host_first_t = race_t
		Net.mg_broadcast({"finished": host_finish})


func _on_mg_state(d: Dictionary) -> void:
	if d.has("spawn") and int(d.get("from", 0)) != me_id:
		var oid := str(d["oid"])
		if not objs.has(oid):
			objs[oid] = {"kind": str(d["spawn"]), "p": d["p"], "v": d["v"], "t0": t, "owner": int(d.get("from", 0))}
	if d.has("kill"):
		objs.erase(str(d["kill"]))
	if d.has("box"):
		var b: Dictionary = boxes[int(d["box"])]
		b["off_until"] = t + 3.0
	if d.has("finished"):
		host_finish = d["finished"]


func host_scores() -> Dictionary:
	var out := {}
	for id in karts:
		if host_finish.has(id):
			var ft: float = host_finish[id]
			out[id] = [1.0e7 - ft * 100.0, "Arrivé en %.1f s" % ft]
		else:
			var pr := float(host_prog.get(id, 0.0))
			var lp := clampi(int(floor(pr / L)) + 1, 1, LAPS)
			out[id] = [pr, "Tour %d / %d" % [lp, LAPS]]
	return out


# ------------------------------------------------------------------ boucle
func _process(delta: float) -> void:
	t += delta
	if Input.is_action_just_pressed("push") and state == "race":
		_q_use = true
	banner_t = maxf(0.0, banner_t - delta)
	match state:
		"intro":
			if not my_ready and t > 0.6:
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
		"race":
			race_t += delta
			if Net.is_host():
				var all_done := true
				for id in karts:
					if Net.players.has(id) and not host_finish.has(id):
						all_done = false
				if all_done or (host_first_t >= 0.0 and race_t > host_first_t + 20.0) or race_t > MAX_T:
					state = "ending"
					Net.mg_end_with_scores(host_scores())
	_update_remotes()
	_update_objs(delta)
	for p in parts:
		p["t"] = float(p["t"]) + delta
	parts = parts.filter(func(p): return float(p["t"]) < float(p["life"]))
	# caméra : un peu en avant du kart (ou sur un autre joueur quand on a fini : spectateur)
	var focus := pos + vel * 0.32
	if finished:
		var cands := []
		for id in karts:
			if id != me_id and karts[id]["seen"] and ((int(karts[id]["st"]) >> 19) & 1) == 0:
				cands.append(id)
		cands.sort()
		if cands.size() > 0:
			if not cands.has(spec_id):
				spec_id = cands[0]
			if Input.is_action_just_pressed("left") or Input.is_action_just_pressed("right"):
				var i := cands.find(spec_id) + (1 if Input.is_action_just_pressed("right") else -1)
				spec_id = cands[(i + cands.size()) % cands.size()]
			focus = karts[spec_id]["pos"]
		else:
			spec_id = 0
	cam.position = focus
	var z := lerpf(cam.zoom.x, 1.0 - minf(vel.length() / MAX, 1.3) * 0.1, 1.0 - exp(-delta * 2.0))
	cam.zoom = Vector2(z, z)
	dyn.queue_redraw()
	hud.queue_redraw()


func _physics_process(dt: float) -> void:
	if not karts.has(me_id):
		return
	var can_drive := state == "race" and not finished
	var inp := _read_input()
	if finished:
		inp = _bot_input()
		inp["use"] = false
	var fwd := Vector2.RIGHT.rotated(ang)
	var spd := vel.dot(fwd)
	idx = _nearest(pos, idx)
	var sd: Array = _side(pos, idx)
	var off := absf(float(sd[0])) > HALF + 6.0
	invuln_t = maxf(0.0, invuln_t - dt)
	wall_cd = maxf(0.0, wall_cd - dt)
	bump_cd = maxf(0.0, bump_cd - dt)
	if spin_t > 0.0:
		spin_t -= dt
		ang += 13.0 * dt
		vel *= exp(-3.2 * dt)
		drift_t = 0.0
	else:
		var gas: bool = can_drive and inp["gas"]
		var brk: bool = can_drive and inp["brake"]
		var steer: float = inp["steer"] if can_drive or finished else 0.0
		if finished:
			gas = true
		var maxs := MAX * (1.38 if boost_t > 0.0 else 1.0)
		if off and boost_t <= 0.0:
			maxs = OFF_MAX
		if gas:
			spd = minf(spd + ACC * dt, maxs) if spd < maxs else move_toward(spd, maxs, 900.0 * dt)
		elif brk:
			spd = maxf(spd - (BRAKE if spd > 0.0 else 420.0) * dt, -200.0)
		else:
			spd = move_toward(spd, 0.0, DRAG * dt)
		if boost_t > 0.0:
			spd = maxf(spd, MAX * 1.3)
		var turn := TURN * clampf(absf(spd) / 230.0, 0.0, 1.0) * (1.0 if spd >= 0.0 else -1.0)
		if drift_t > 0.3:
			turn *= 1.18
		ang += steer * turn * dt
		fwd = Vector2.RIGHT.rotated(ang)
		var lat := vel - fwd * vel.dot(fwd)
		lat *= exp(-(GRIP if not off else 5.0) * dt)
		vel = fwd * spd + lat
		# turbo en dérapage : tourner longtemps à fond charge des étincelles
		if absf(steer) > 0.5 and spd > MAX * 0.72 and not off and can_drive:
			drift_t += dt
		else:
			if drift_t > 1.3:
				_boost(0.85)
			elif drift_t > 0.6:
				_boost(0.45)
			drift_t = 0.0
	boost_t = maxf(0.0, boost_t - dt)
	pos += vel * dt
	# barrières
	idx = _nearest(pos, idx)
	sd = _side(pos, idx)
	var dd: float = sd[0]
	if absf(dd) > WALL:
		var n: Vector2 = sd[1] * signf(dd)
		pos -= n * (absf(dd) - WALL)
		var out := vel.dot(n)
		if out > 0.0:
			vel -= n * out * 1.5
			vel *= 0.8
			if wall_cd <= 0.0 and out > 150.0:
				wall_cd = 0.3
				Sfx.play("bump", -6.0)
				fx.stars(pos + n * KART_R, 3)
	# autres karts
	for id in karts:
		if id == me_id:
			continue
		var o: Vector2 = karts[id]["pos"]
		var dv := pos - o
		var dl := dv.length()
		if dl > 0.1 and dl < KART_R * 2.0:
			var nn := dv / dl
			pos += nn * (KART_R * 2.0 - dl)
			vel += nn * 160.0
			if bump_cd <= 0.0:
				bump_cd = 0.4
				Sfx.play("bump", -8.0)
	# poussière hors piste
	if off and vel.length() > 120.0 and randf() < 0.4:
		_part("dust", pos - fwd * 20.0, Color("#c9a26b"), 0.5)
	# progression / tours
	var s_new := _s_of(pos, idx)
	if s_now > L * 0.75 and s_new < L * 0.25:
		lap += 1
		if lap >= 1 and lap < LAPS and not finished:
			banner = "Tour %d / %d" % [lap + 1, LAPS] if lap + 1 < LAPS else "DERNIER TOUR !"
			banner_t = 2.0
			Sfx.play("gem", -4.0)
		if lap >= LAPS and not finished:
			finished = true
			finish_t = race_t
			Net.mg_to_host({"finish": race_t})
			banner = "ARRIVÉ !"
			banner_t = 4.0
			Sfx.play("gem", 0.0)
			fx.ring(pos, Net.color_of(me_id))
	elif s_now < L * 0.25 and s_new > L * 0.75:
		lap -= 1
	s_now = s_new
	# cubes à objets
	for i in boxes.size():
		var b: Dictionary = boxes[i]
		if t > float(b["off_until"]) and pos.distance_to(b["p"]) < 52.0:
			b["off_until"] = t + 3.0
			Net.mg_to_host({"box": i})
			fx.stars(b["p"], 4)
			if item == "" and roulette_t <= 0.0 and not finished:
				roulette_t = 1.1
				Sfx.play("coin", -4.0)
	if roulette_t > 0.0:
		roulette_t -= dt
		if roulette_t <= 0.0:
			item = _roll_item()
			Sfx.play("select", -2.0)
	# flèches d'accélération
	for pd in pads:
		if pos.distance_to(pd[0]) < 52.0 and boost_t < 0.5:
			_boost(1.0)
	# objets
	if inp["use"] and item != "" and can_drive and spin_t <= 0.0:
		_use_item()
	for oid in objs.keys():
		var o: Dictionary = objs[oid]
		if invuln_t > 0.0 or spin_t > 0.0:
			break
		if int(o["owner"]) == me_id and t - float(o["t0"]) < 0.5:
			continue
		if (o["p"] as Vector2).distance_to(pos) < KART_R + 18.0:
			_kill_obj(oid)
			_spin_out()
			break
	# envoi de l'état
	karts[me_id]["pos"] = pos
	karts[me_id]["ang"] = ang
	karts[me_id]["lap"] = lap
	karts[me_id]["s"] = s_now
	send_acc += dt
	if send_acc >= 1.0 / 30.0:
		send_acc = 0.0
		Net.send_state(pos, vel, _pack())
	prog_acc += dt
	if prog_acc > 0.5:
		prog_acc = 0.0
		Net.mg_to_host({"prog": lap * L + s_now})


func _read_input() -> Dictionary:
	if karts.has(me_id) and Net.autotest != "":
		return _bot_input()
	return {
		"gas": Input.is_action_pressed("up") or Input.is_action_pressed("jump"),
		"brake": Input.is_action_pressed("down"),
		"steer": Input.get_axis("left", "right"),
		"use": _take_use(),
	}


func _take_use() -> bool:
	var v := _q_use
	_q_use = false
	return v


func _bot_input() -> Dictionary:
	var target := _point_at(s_now + 230.0)
	var want := (target - pos).angle()
	var diff := wrapf(want - ang, -PI, PI)
	return {"gas": absf(diff) < 1.6, "brake": absf(diff) > 1.6, "steer": clampf(diff * 2.5, -1.0, 1.0),
		"use": item != "" and randf() < 0.02}


func _boost(d: float) -> void:
	boost_t = maxf(boost_t, d)
	Sfx.play("whoosh", -4.0)
	fx.ring(pos, Color("#ffb020"))


func _spin_out() -> void:
	spin_t = 1.1
	invuln_t = 2.2
	vel *= 0.35
	boost_t = 0.0
	Sfx.play("hurt", -2.0)
	fx.stars(pos, 6)
	fx.popup(pos + Vector2(0, -50), "AÏE !", Net.color_of(me_id))


func _roll_item() -> String:
	var n := maxi(1, karts.size() - 1)
	var f := float(my_rank - 1) / n
	var w := {"banana": 0.45 - 0.25 * f, "shell": 0.4, "mushroom": 0.15 + 0.4 * f}
	var r := randf() * (float(w["banana"]) + float(w["shell"]) + float(w["mushroom"]))
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return "mushroom"


func _use_item() -> void:
	var fwd := Vector2.RIGHT.rotated(ang)
	match item:
		"banana":
			_spawn_obj("banana", pos - fwd * 62.0, Vector2.ZERO)
			Sfx.play("whoosh", -6.0)
		"shell":
			_spawn_obj("shell", pos + fwd * 66.0, fwd * 980.0)
			Sfx.play("whoosh", -2.0)
		"mushroom":
			_boost(1.3)
	item = ""


func _update_objs(delta: float) -> void:
	var dead := []
	for oid in objs:
		var o: Dictionary = objs[oid]
		if o["kind"] == "shell":
			var p: Vector2 = o["p"]
			var v: Vector2 = o["v"]
			p += v * delta
			var i := _nearest(p, int(o.get("idx", -1)))
			o["idx"] = i
			var sd: Array = _side(p, i)
			if absf(float(sd[0])) > WALL - 14.0:
				var n: Vector2 = sd[1] * signf(float(sd[0]))
				if v.dot(n) > 0.0:
					v -= 2.0 * n * v.dot(n)
				p -= n * (absf(float(sd[0])) - (WALL - 14.0))
			o["p"] = p
			o["v"] = v
			if t - float(o["t0"]) > 7.0:
				dead.append(oid)
			for oid2 in objs:
				if oid2 != oid and objs[oid2]["kind"] == "banana" and (objs[oid2]["p"] as Vector2).distance_to(p) < 34.0:
					dead.append(oid)
					dead.append(oid2)
	for oid in dead:
		objs.erase(oid)


func _update_remotes() -> void:
	var rt := Time.get_ticks_msec() / 1000.0 - INTERP
	for id in karts:
		if id == me_id:
			continue
		var k: Dictionary = karts[id]
		var snaps: Array = k["snaps"]
		if snaps.is_empty():
			continue
		var st := int(snaps[-1][3])
		var p: Vector2 = snaps[-1][1]
		if rt >= float(snaps[-1][0]):
			p = snaps[-1][1] + snaps[-1][2] * minf(rt - float(snaps[-1][0]), 0.15)
		else:
			for i in range(snaps.size() - 1, 0, -1):
				var a: Array = snaps[i - 1]
				var b: Array = snaps[i]
				if float(a[0]) <= rt:
					var u := clampf((rt - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0])), 0.0, 1.0)
					p = (a[1] as Vector2).lerp(b[1], u)
					st = int(b[3])
					break
		k["pos"] = p
		k["st"] = st
		k["ang"] = deg_to_rad((st & 4095) / 10.0)
		k["lap"] = ((st >> 16) & 7) - 1
		var i2 := _nearest(p, int(k["idx"]))
		k["idx"] = i2
		k["s"] = _s_of(p, i2)
	# mon classement
	var mine := lap * L + s_now
	my_rank = 1
	for id in karts:
		if id != me_id:
			var k: Dictionary = karts[id]
			var fin := ((int(k["st"]) >> 19) & 1) == 1
			var pr := float(k["lap"]) * L + float(k["s"])
			if (fin and not finished) or (not finished and pr > mine):
				my_rank += 1
			elif fin and finished and host_finish.has(id) and host_finish.has(me_id) and float(host_finish[id]) < float(host_finish[me_id]):
				my_rank += 1


func _part(kind: String, p: Vector2, c: Color, life: float) -> void:
	parts.append({"k": kind, "p": p + Vector2(randf_range(-6, 6), randf_range(-6, 6)), "c": c, "t": 0.0, "life": life})


# ------------------------------------------------------------------ dessin du circuit (une seule fois)
func _offset(src: PackedVector2Array, d: float) -> Array:
	return Geometry2D.offset_polygon(src, d, Geometry2D.JOIN_ROUND)


func _largest(arr: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	for p in arr:
		if p.size() > best.size():
			best = p
	return best


func _closed(p: PackedVector2Array) -> PackedVector2Array:
	var l := p.duplicate()
	l.append(p[0])
	return l


func _draw_ground() -> void:
	var g := ground
	var big := Rect2(-1500, -1300, 7600, 5600)
	g.draw_rect(big, Color("#5cb84e"))
	# herbe tondue en bandes
	for k in range(-30, 60):
		var x := k * 160.0
		g.draw_colored_polygon(PackedVector2Array([Vector2(x, -1300), Vector2(x + 80, -1300), Vector2(x + 80 - 1500, 4300), Vector2(x - 1500, 4300)]), Color("#64c255"))
	# zone de dégagement (sable) entre la piste et les pneus
	var outer_wall := _largest(_offset(pts, WALL))
	var outer_run := _largest(_offset(pts, HALF + 70.0))
	g.draw_colored_polygon(outer_run, Color("#e9cf94"))
	var asphalt := _largest(_offset(pts, HALF + 10.0))
	g.draw_colored_polygon(asphalt, Color("#3a3c48"))
	g.draw_colored_polygon(_largest(_offset(pts, HALF)), Color("#5d6070"))
	# intérieur de la boucle
	for poly in _offset(pts, -HALF):
		g.draw_colored_polygon(poly, Color("#3a3c48"))
	for poly in _offset(pts, -(HALF + 10.0)):
		g.draw_colored_polygon(poly, Color("#e9cf94"))
	for poly in _offset(pts, -(HALF + 70.0)):
		g.draw_colored_polygon(poly, Color("#5cb84e"))
		g.draw_polyline(_closed(poly), Color("#4ea842"), 6.0, true)
	# re-dessiner l'asphalte proprement (le remplissage intérieur a pu déborder)
	var road := _closed(pts)
	g.draw_polyline(road, Color("#5d6070"), HALF * 2.0, true)
	for i in range(0, pts.size(), 1):
		g.draw_circle(pts[i], HALF - 1.0, Color("#5d6070"))
	# vibreurs rouges et blancs sur les deux bords
	for side in [-1.0, 1.0]:
		var acc := 0.0
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			var n := (b - a).normalized().orthogonal()
			var col := Color("#f04650") if int(acc / 46.0) % 2 == 0 else Color.WHITE
			g.draw_line(a + n * side * (HALF - 6.0), b + n * side * (HALF - 6.0), col, 14.0)
			acc += a.distance_to(b)
	# ligne pointillée au centre
	var acc2 := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		if int(acc2 / 60.0) % 2 == 0:
			g.draw_line(a, b, Color(1, 1, 1, 0.35), 6.0)
		acc2 += a.distance_to(b)
	# ligne d'arrivée en damier + grille de départ
	var s0 := 0.0
	var c0 := _point_at(s0)
	var d0 := _dir_at(s0)
	var n0 := d0.orthogonal()
	for row in 2:
		for k in 10:
			var cell := (HALF * 2.0) / 10.0
			var p := c0 + n0 * (-HALF + cell * (k + 0.5)) + d0 * (row * cell - cell * 0.5)
			var col := Color.WHITE if (k + row) % 2 == 0 else Color("#22232c")
			g.draw_set_transform(p, d0.angle(), Vector2.ONE)
			g.draw_rect(Rect2(-cell / 2.0, -cell / 2.0, cell, cell), col)
			g.draw_set_transform(Vector2.ZERO)
	for i in 8:
		var gp := _grid_pos(i)
		var dd := _dir_at(L - 130.0 - (i / 2) * 105.0)
		g.draw_set_transform(gp, dd.angle(), Vector2.ONE)
		g.draw_rect(Rect2(-34, -30, 68, 60), Color(1, 1, 1, 0.55), false, 4.0)
		g.draw_set_transform(Vector2.ZERO)
	# pneus le long des barrières
	_tires(g, outer_wall)
	for poly in _offset(pts, -WALL):
		_tires(g, poly)
	# panneaux « RACE » le long de la ligne droite des stands et chevrons dans les virages
	for k in 7:
		var sb := 260.0 + k * 230.0
		var cb := _point_at(sb)
		var db := _dir_at(sb)
		var nb := db.orthogonal()
		_ksprite(g, "barrier_red_race" if k % 2 == 0 else "barrier_white_race", cb + nb * (WALL + 40.0), db.angle(), 1.0)
	for i in range(0, pts.size(), 6):
		var a0 := _dir_at(cum[i])
		var a1 := _dir_at(cum[i] + 160.0)
		var turn := a0.angle_to(a1)
		if absf(turn) > 0.28:
			var side := -signf(turn)
			var cp := pts[i] + a0.orthogonal() * side * (HALF + 48.0)
			_ksprite(g, "arrow_yellow", cp, a0.angle() + PI / 2.0 * (1.0 if side > 0.0 else -1.0) + PI, 0.42)
	# décor : arbres dehors, tribune, lac dans la boucle
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var inner_walls := _offset(pts, -(WALL + 60.0))
	var outer_far := _largest(_offset(pts, WALL + 60.0))
	var placed := []
	var tries := 0
	while placed.size() < 160 and tries < 6000:
		tries += 1
		var p := Vector2(r.randf_range(-900, 5100), r.randf_range(-700, 3200))
		var inside := false
		for poly in inner_walls:
			if Geometry2D.is_point_in_polygon(p, poly):
				inside = true
		if not inside and Geometry2D.is_point_in_polygon(p, outer_far):
			continue
		if p.distance_to(Vector2(2300, 1800)) < 320.0 or p.distance_to(Vector2(1900, 2900)) < 480.0:
			continue
		var ok := true
		for q in placed:
			if (q as Vector2).distance_to(p) < 120.0:
				ok = false
				break
		if ok:
			placed.append(p)
	placed.sort_custom(func(a, b): return a.y < b.y)
	# lac au milieu
	_blob(g, Vector2(2300, 1800), Vector2(260, 150), Color("#3aa3e8"), Color("#5cc0f4"))
	_grandstand(g, Vector2(1900, 2900))
	for p in placed:
		_tree(g, p, r.randf_range(0.9, 1.3), r.randi() % 3)


func _tires(g: CanvasItem, poly: PackedVector2Array) -> void:
	var red: Texture2D = _ktex["tires_red"]
	var white: Texture2D = _ktex["tires_white"]
	var acc := 0.0
	var next := 0.0
	var n := 0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var seg := a.distance_to(b)
		while next <= acc + seg:
			var p := a.lerp(b, (next - acc) / maxf(seg, 0.001))
			var tx := red if (n / 3) % 2 == 0 else white
			g.draw_set_transform(p, 0.0, Vector2(0.68, 0.68))
			g.draw_texture(tx, -tx.get_size() / 2.0)
			g.draw_set_transform(Vector2.ZERO)
			next += 36.0
			n += 1
		acc += seg


func _blob(g: CanvasItem, c: Vector2, r: Vector2, col: Color, col2: Color) -> void:
	g.draw_set_transform(c, 0.0, Vector2(1.0, r.y / r.x))
	g.draw_circle(Vector2.ZERO, r.x + 10.0, Color("#2c7cc0"))
	g.draw_circle(Vector2.ZERO, r.x, col)
	g.draw_circle(Vector2(-r.x * 0.2, -r.x * 0.15), r.x * 0.55, col2)
	g.draw_set_transform(Vector2.ZERO)


func _grandstand(g: CanvasItem, c: Vector2) -> void:
	for k in 2:
		_ksprite(g, "tribune_full", c + Vector2(-226 + k * 452, 0), 0.0, 1.0)
	_ksprite(g, "tribune_overhang_red", c + Vector2(-226, -150), 0.0, 1.0)
	_ksprite(g, "tribune_overhang_red", c + Vector2(226, -150), 0.0, 1.0)
	for k in 4:
		_ksprite(g, "tent_red_large" if k % 2 == 0 else "tent_blue_large", c + Vector2(-600 + k * 400 if k < 2 else -600 + k * 400 + 400, 230), 0.0, 0.62)
	for k in 6:
		_ksprite(g, ["cone_straight", "barrel_red", "barrel_blue", "tires_white", "cone_straight", "barrel_red_down"][k], c + Vector2(-560 + k * 225, 360 + (k % 2) * 40), k * 0.7, 0.8)
	g.draw_style_box(UI.box(Color("#f04650"), UI.DARK, 4, 12), Rect2(c + Vector2(-260, -250), Vector2(520, 56)))
	UI.text(g, c + Vector2(0, -222), "GRAND PRIX AURA", 32, UI.WHITE, 6)


## Sprite du pack Racing, centré en p.
func _ksprite(g: CanvasItem, name: String, p: Vector2, ang: float, s: float) -> void:
	var tx: Texture2D = _ktex.get(name)
	if tx == null:
		return
	g.draw_set_transform(p, ang, Vector2(s, s))
	g.draw_texture(tx, -tx.get_size() / 2.0)
	g.draw_set_transform(Vector2.ZERO)


func _tree(g: CanvasItem, p: Vector2, s: float, kind: int) -> void:
	g.draw_set_transform(p + Vector2(14, 18) * s, 0.0, Vector2(1.0, 0.75))
	g.draw_circle(Vector2.ZERO, 62.0 * s, Color(0, 0, 0, 0.16))
	g.draw_set_transform(Vector2.ZERO)
	match kind:
		0:
			_ksprite(g, "tree_large", p, s * 0.7, 0.62 * s)
		1:
			_ksprite(g, "tree_small", p, s, 0.8 * s)
		_:
			_ksprite(g, ["rock1", "rock2", "rock3"][int(absf(p.x)) % 3], p, s * 2.0, 0.7 * s)


# ------------------------------------------------------------------ dessin dynamique
func _draw_dyn() -> void:
	var d := dyn
	# flèches d'accélération
	for pd in pads:
		var p: Vector2 = pd[0]
		d.draw_set_transform(p, float(pd[1]), Vector2.ONE)
		d.draw_style_box(UI.box(Color("#ffb020"), UI.DARK, 4, 12), Rect2(-50, -36, 100, 72))
		for k in 3:
			var x := -30.0 + k * 22.0 + fmod(t * 60.0, 22.0)
			var a := 0.4 + 0.6 * (k / 2.0)
			d.draw_polyline(PackedVector2Array([Vector2(x - 8, -20), Vector2(x + 8, 0), Vector2(x - 8, 20)]), Color(1, 1, 1, a), 7.0)
		d.draw_set_transform(Vector2.ZERO)
	# cubes à objets
	for b in boxes:
		if t <= float(b["off_until"]):
			continue
		var p: Vector2 = b["p"] + Vector2(0, sin(t * 3.0 + (b["p"] as Vector2).x) * 4.0)
		d.draw_set_transform(p, t * 1.5, Vector2.ONE)
		d.draw_style_box(UI.box(Color.from_hsv(fmod(t * 0.3 + p.x * 0.001, 1.0), 0.55, 1.0, 0.92), UI.DARK, 5, 10), Rect2(-27, -27, 54, 54))
		d.draw_rect(Rect2(-17, -19, 14, 6), Color(1, 1, 1, 0.6))
		d.draw_set_transform(Vector2.ZERO)
		UI.text(d, p, "?", 36, UI.WHITE, 7)
	# objets posés / lancés
	for oid in objs:
		var o: Dictionary = objs[oid]
		_draw_item(d, str(o["kind"]), o["p"], 1.0, t * 8.0 if o["kind"] == "shell" else 0.0)
	# particules
	for pt in parts:
		var k: float = float(pt["t"]) / float(pt["life"])
		d.draw_circle(pt["p"], 10.0 * (0.6 + k), Color(pt["c"], 0.7 * (1.0 - k)))
	# karts, du plus haut au plus bas
	var order := karts.keys()
	order.sort_custom(func(a, b): return (karts[a]["pos"] as Vector2).y < (karts[b]["pos"] as Vector2).y)
	for id in order:
		var k: Dictionary = karts[id]
		if id != me_id and not k["seen"]:
			continue
		var st := _pack() if id == me_id else int(k["st"])
		_draw_kart(d, id, k["pos"], float(k["ang"]), st)


func _draw_kart(d: CanvasItem, id: int, p: Vector2, a: float, st: int) -> void:
	var col := Net.color_of(id)
	var fl := (st >> 12) & 15
	var spinning := (fl & 1) != 0
	var boosting := (fl & 2) != 0
	var drift := (fl >> 2) & 3
	var ks := Vector2(1.25, 1.25)
	d.draw_set_transform(p + Vector2(6, 8), a, ks)
	d.draw_style_box(UI.box(Color(0, 0, 0, 0.22), Color(0, 0, 0, 0), 0, 14), Rect2(-34, -24, 68, 48))
	d.draw_set_transform(p, a, ks)
	# flammes du turbo
	if boosting:
		for k in 2:
			var y := -12.0 + k * 24.0
			var ln := 26.0 + sin(t * 40.0 + k) * 8.0
			d.draw_colored_polygon(PackedVector2Array([Vector2(-32, y - 7), Vector2(-32 - ln, y), Vector2(-32, y + 7)]), Color("#ff8c28"))
			d.draw_colored_polygon(PackedVector2Array([Vector2(-32, y - 4), Vector2(-32 - ln * 0.6, y), Vector2(-32, y + 4)]), Color("#ffe066"))
	# roues
	for w in [Vector2(-20, -22), Vector2(-20, 22), Vector2(18, -22), Vector2(18, 22)]:
		d.draw_style_box(UI.box(Color("#22232c"), UI.DARK, 0, 4), Rect2(w - Vector2(10, 6), Vector2(20, 12)))
	# carrosserie
	d.draw_style_box(UI.box(col, UI.DARK, 4, 12), Rect2(-30, -18, 62, 36))
	d.draw_style_box(UI.box(col.lightened(0.25), col.lightened(0.25), 0, 8), Rect2(-22, -12, 30, 10))
	d.draw_style_box(UI.box(Color("#f4f7ff"), UI.DARK, 3, 6), Rect2(22, -14, 12, 28))
	# étincelles du dérapage
	if drift > 0:
		var sc := Color("#5ab4ff") if drift == 1 else Color("#ff8c28")
		for w in [Vector2(-26, -24), Vector2(-26, 24)]:
			for k in 3:
				var q: Vector2 = w + Vector2(randf_range(-14, 2), randf_range(-6, 6))
				d.draw_circle(q, randf_range(2.5, 5.0), sc)
	d.draw_set_transform(Vector2.ZERO)
	# le perso, toujours debout dans son kart
	var bob := sin(t * 12.0 + id) * 1.5
	var tex := UI.char_tex(Net.color_idx(id), "hit" if spinning else "front")
	d.draw_set_transform(p + Vector2(0, 10 + bob), (t * 14.0 if spinning else 0.0), Vector2(0.3, 0.3))
	d.draw_texture(tex, Vector2(-128, -256))
	d.draw_set_transform(Vector2.ZERO)
	UI.text(d, p + Vector2(0, -80), Net.name_of(id), 20, col, 6)


func _draw_item(d: CanvasItem, kind: String, p: Vector2, s: float, rot := 0.0) -> void:
	match kind:
		"banana":
			d.draw_set_transform(p, -0.3 + rot, Vector2(s, s))
			var pts2 := PackedVector2Array()
			for k in 13:
				var u := k / 12.0
				var a := lerpf(PI * 0.15, PI * 0.85, u)
				pts2.append(Vector2(cos(a) * 22.0, sin(a) * 22.0 - 10.0))
			for k in range(12, -1, -1):
				var u := k / 12.0
				var a := lerpf(PI * 0.2, PI * 0.8, u)
				pts2.append(Vector2(cos(a) * 12.0, sin(a) * 10.0 - 6.0))
			d.draw_colored_polygon(pts2, Color("#ffd23f"))
			var l := pts2.duplicate()
			l.append(pts2[0])
			d.draw_polyline(l, UI.DARK, 3.5)
			d.draw_circle(Vector2(cos(PI * 0.15), sin(PI * 0.15)) * 22.0 + Vector2(2, -10), 3.5, Color("#6b4a2a"))
			d.draw_set_transform(Vector2.ZERO)
		"shell":
			d.draw_set_transform(p, rot, Vector2(s, s))
			d.draw_circle(Vector2.ZERO, 20.0, UI.DARK)
			d.draw_circle(Vector2.ZERO, 16.5, Color("#f4f7ff"))
			d.draw_circle(Vector2.ZERO, 13.0, Color("#3fbf5a"))
			for k in 6:
				var a := k * TAU / 6.0
				d.draw_line(Vector2.ZERO, Vector2(cos(a), sin(a)) * 13.0, Color("#2b8c4a"), 2.5)
			d.draw_circle(Vector2.ZERO, 5.0, Color("#7fe08f"))
			d.draw_set_transform(Vector2.ZERO)
		"mushroom":
			d.draw_set_transform(p, rot, Vector2(s, s))
			d.draw_rect(Rect2(-9, -2, 18, 18), UI.DARK)
			d.draw_rect(Rect2(-6, -2, 12, 15), Color("#fff1d6"))
			var cap := PackedVector2Array()
			for k in 13:
				var a := PI + k * PI / 12.0
				cap.append(Vector2(cos(a) * 22.0, sin(a) * 18.0))
			d.draw_colored_polygon(cap, Color("#f04650"))
			var cl := cap.duplicate()
			cl.append(cap[0])
			d.draw_polyline(cl, UI.DARK, 3.5)
			d.draw_circle(Vector2(-9, -9), 4.5, Color.WHITE)
			d.draw_circle(Vector2(8, -10), 4.0, Color.WHITE)
			d.draw_set_transform(Vector2.ZERO)


# ------------------------------------------------------------------ HUD
func _draw_hud() -> void:
	var h := hud
	if state == "intro":
		h.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, 0.45))
		var r := Rect2(Vector2(220, 120), Vector2(840, 430))
		h.draw_style_box(UI.box(UI.WHITE, UI.DARK, 6, 30), r)
		UI.text(h, Vector2(640, 186), "Grand Prix Aura !", 56, UI.YELLOW, 14)
		var lines := ["3 tours de circuit : le premier arrivé gagne !",
			"Roule sur les cubes « ? » pour avoir un objet :",
			"banane (posée derrière), carapace (lancée devant), champignon (turbo).",
			"Tourne longtemps à fond : des étincelles chargent un turbo !",
			"Les flèches jaunes au sol te propulsent."]
		for i in lines.size():
			h.draw_string(UI.font(), Vector2(220, 258 + i * 36), lines[i], HORIZONTAL_ALIGNMENT_CENTER, 840, 23, UI.DARK)
		var cy := 258 + lines.size() * 36 + 18
		h.draw_style_box(UI.box(UI.PAPER, UI.DARK, 3, 12), Rect2(Vector2(250, cy - 2), Vector2(780, 40)))
		h.draw_string(UI.font(), Vector2(250, cy + 25), "Accélérer : Z / ↑ / Espace  ·  Freiner : S / ↓  ·  Tourner : Q D  ·  Objet : Maj / X / clic", HORIZONTAL_ALIGNMENT_CENTER, 780, 16, UI.GREY)
		preload("res://minigames/stage.gd").draw_ready_row(h, my_ready, ready_ids, karts.keys(), t)
		return
	# tour
	var lr := Rect2(Vector2(24, 18), Vector2(180, 56))
	h.draw_style_box(UI.box(UI.WHITE, UI.DARK, 4, 16), lr)
	UI.text(h, lr.get_center(), "Tour %d / %d" % [clampi(lap + 1, 1, LAPS), LAPS], 28, UI.DARK, 0)
	var tr := Rect2(Vector2(24, 82), Vector2(180, 44))
	h.draw_style_box(UI.box(UI.WHITE, UI.DARK, 4, 14), tr)
	var shown_t := finish_t if finished else race_t
	UI.text(h, tr.get_center(), "%d:%04.1f" % [int(shown_t) / 60, fmod(shown_t, 60.0)], 22, UI.DARK, 0)
	# objet
	var ir := Rect2(Vector2(1280 - 124, 18), Vector2(100, 100))
	h.draw_style_box(UI.box(UI.WHITE, UI.DARK, 5, 22), ir)
	if roulette_t > 0.0:
		_draw_item(h, ITEMS[int(t * 14.0) % 3], ir.get_center(), 1.6)
	elif item == "":
		UI.text(h, ir.get_center(), "?", 44, Color("#d6d9e6"), 0)
	elif item != "":
		_draw_item(h, item, ir.get_center(), 1.8)
		UI.text(h, ir.get_center() + Vector2(0, 66), "Maj / X / clic", 15, UI.WHITE, 5)
	# position
	var suffix := "er" if my_rank == 1 else "e"
	var pc: Color = [UI.YELLOW, Color("#c9d0dc"), Color("#e09a5a"), UI.WHITE][mini(my_rank - 1, 3)]
	UI.text(h, Vector2(1180, 650), "%d%s" % [my_rank, suffix], 76, pc, 16)
	# mini-carte
	var mr := Rect2(Vector2(20, 520), Vector2(300, 180))
	h.draw_style_box(UI.box(Color(1, 1, 1, 0.85), UI.DARK, 4, 16), mr)
	var sc := minf((mr.size.x - 30.0) / 3900.0, (mr.size.y - 24.0) / 2200.0)
	var o := mr.position + Vector2(15, 12) - Vector2(360, 280) * sc
	var mp := PackedVector2Array()
	for i in range(0, pts.size(), 4):
		mp.append(o + pts[i] * sc)
	mp.append(mp[0])
	h.draw_polyline(mp, UI.DARK, 9.0, true)
	h.draw_polyline(mp, Color("#8a8fa8"), 5.0, true)
	for id in karts:
		var kp: Vector2 = karts[id]["pos"]
		h.draw_circle(o + kp * sc, 7.0 if id == me_id else 5.5, UI.DARK)
		h.draw_circle(o + kp * sc, 5.0 if id == me_id else 3.5, Net.color_of(id))
	# compte à rebours
	if state == "count":
		var n := 3 - int(t)
		var lights := Rect2(Vector2(640 - 130, 150), Vector2(260, 90))
		h.draw_style_box(UI.box(Color("#2b2c35"), UI.DARK, 5, 20), lights)
		for k in 3:
			var on := k < int(t) + 1
			h.draw_circle(lights.position + Vector2(50 + k * 80, 45), 28.0, UI.DARK)
			h.draw_circle(lights.position + Vector2(50 + k * 80, 45), 24.0, UI.RED if on else Color("#4a4c58"))
		UI.text(h, Vector2(640, 330), str(n), int(110 * (1.0 + (1.0 - fmod(t, 1.0)) * 0.3)), UI.WHITE, 16)
	elif state == "race" and t < 1.0:
		UI.text(h, Vector2(640, 330), "GO !", int(120 * (1.0 + t * 0.4)), Color(UI.GREEN, 1.0 - t), 18)
	if banner_t > 0.0:
		var k := 1.0 - banner_t / 2.0
		UI.text(h, Vector2(640, 220), banner, int(64 * (1.0 + maxf(0.0, 0.2 - k) * 2.0)), Color(UI.YELLOW, minf(1.0, banner_t * 2.0)), 14)
	if finished and state == "race":
		UI.text(h, Vector2(640, 300), "Bravo ! %d%s" % [my_rank, suffix], 44, UI.WHITE, 12)
		if spec_id != 0 and karts.has(spec_id):
			var sm := "Tu regardes %s   (← → pour changer)" % Net.name_of(spec_id)
			var sw := UI.text_width(sm, 20) + 40.0
			h.draw_style_box(UI.box(Color(UI.DARK, 0.8), UI.DARK, 0, 14), Rect2(Vector2(640 - sw / 2.0, 588), Vector2(sw, 40)))
			UI.text(h, Vector2(640, 608), sm, 20, UI.WHITE, 0)
	if state == "over" or state == "ending":
		h.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, minf(0.4, t)))
		UI.text(h, Vector2(640, 360), "TERMINÉ !", 96, UI.YELLOW, 16)
