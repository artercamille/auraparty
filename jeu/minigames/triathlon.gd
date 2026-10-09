extends Node2D
## Mini-triathlon : trois épreuves à la suite, chacun dans son couloir.
## 1) pagaie : Q et D en alternance  2) vélo : Z et S en alternance  3) haies : Espace pour sauter.
## Le premier arrivé gagne.

const L1 := 4000.0                # fin de la pagaie
const L2 := 8600.0                # fin du vélo
const L3 := 12400.0               # arrivée
const MAX_T := 110.0
const SCREEN_X := 360.0           # position de l'athlète à l'écran
const STAGE_NAMES := ["PAGAIE", "VÉLO", "HAIES"]
const STAGE_HELP := ["Q et D (ou ← →) en alternance !", "Z et S (ou ↑ ↓) en alternance !", "ESPACE pour sauter les haies !"]

var ids: Array = []
var lanes: Dictionary = {}        # id -> {x, h, st, snaps, seen}
var me_id := 0
var playing := false              # vrai si je participe (pas spectateur d'un duel)
var hud: Control
var view: Node2D
var state := "intro"
var t := 0.0
var race_t := 0.0
var my_ready := false
var go_received := false
var ready_ids: Array = []
var rng := RandomNumberGenerator.new()
var hurdles := PackedFloat32Array()
var knocked := {}                 # haies renversées (chez moi)
var ranks := {}                   # id -> place actuelle
var brng := RandomNumberGenerator.new()   # pour les robots de test

# mon athlète
var x := 0.0
var v := 0.0
var last_key := 0
var stumble_t := 0.0
var air_t := -1.0
var transit_t := 0.0
var finished := false
var finish_t := 0.0
var splash_t := 0.0
var my_rank := 1
var send_acc := 0.0
var prog_acc := 0.0
var bot_acc := 0.0
var bot_next := 0.12
var _q := {}                      # touches appuyées (captées dans _process)
var pops: Array = []              # textes qui montent

# hôte
var host_finish: Dictionary = {}
var host_prog: Dictionary = {}
var host_first_t := -1.0
var _tex := {}
var _deco := {}


func _ready() -> void:
	rng.seed = int(Net.mg_data.get("seed", 1))
	var hx := L2 + 300.0
	while hx < L3 - 200.0:
		hurdles.append(hx)
		hx += rng.randf_range(210.0, 330.0)
	for id in Net.mg_data.get("players", Net.players.keys()):
		if Net.players.has(id):
			ids.append(id)
	ids.sort()
	me_id = Net.my_id()
	playing = ids.has(me_id)
	for id in ids:
		lanes[id] = {"x": 0.0, "h": 0.0, "st": 0, "snaps": [], "seen": false, "cam": -SCREEN_X, "kn": {}}
		for pose in ["idle", "front", "walk_a", "walk_b", "jump", "hit"]:
			_tex["%d_%s" % [id, pose]] = UI.char_tex(Net.color_idx(id), pose)
	brng.randomize()
	for n in ["bush1", "bushAlt2", "tree", "treePine", "treeSmall_green1", "treeSmall_green2", "foliage_020", "fence"]:
		_deco[n] = load("res://assets/deco/%s.png" % n)
	for n in ["flag_red_a", "flag_green_a"]:
		_deco[n] = load("res://assets/tiles/%s.png" % n)
	_deco["hills"] = load("res://assets/bg/layer_hills.png")
	for id in ids:
		ranks[id] = 1
	view = Node2D.new()
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


func _on_ending() -> void:
	state = "over"
	t = 0.0
	Sfx.play("bell", -2.0, 0.0)


func _on_players_changed() -> void:
	for id in lanes.keys():
		if not Net.players.has(id):
			lanes.erase(id)
			ids.erase(id)


func _stage_of(px: float) -> int:
	return 0 if px < L1 else (1 if px < L2 else 2)


# ------------------------------------------------------------------ réseau
func _on_remote_state(id: int, p: Vector2, vel: Vector2, st: int) -> void:
	if not lanes.has(id) or id == me_id:
		return
	var l: Dictionary = lanes[id]
	var snaps: Array = l["snaps"]
	snaps.append([Time.get_ticks_msec() / 1000.0, p, vel, st])
	if snaps.size() > 12:
		snaps.pop_front()
	l["seen"] = true


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
	for id in lanes:
		if host_finish.has(id):
			var ft: float = host_finish[id]
			out[id] = [1.0e7 - ft * 100.0, "Arrivé en %.1f s" % ft]
		else:
			var pr := float(host_prog.get(id, 0.0))
			out[id] = [pr, "%s : %d %%" % [STAGE_NAMES[_stage_of(pr)].capitalize(), int(pr / L3 * 100.0)]]
	return out


# ------------------------------------------------------------------ boucle
func _process(delta: float) -> void:
	t += delta
	for a in ["left", "right", "up", "down", "jump", "push"]:
		if Input.is_action_just_pressed(a):
			_q[a] = true
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
				_q.clear()
				Sfx.voice("go")
		"race":
			race_t += delta
			if playing:
				_step(delta)
			if Net.is_host():
				var all_done := true
				for id in lanes:
					if Net.players.has(id) and not host_finish.has(id):
						all_done = false
				if all_done or (host_first_t >= 0.0 and race_t > host_first_t + 15.0) or race_t > MAX_T:
					state = "ending"
					Net.mg_end_with_scores(host_scores())
	_q.clear()
	_update_remotes()
	# une caméra par couloir, qui suit son athlète
	for id in lanes:
		var l: Dictionary = lanes[id]
		var target := float(l["x"]) - SCREEN_X
		if absf(float(l["cam"]) - target) > 900.0:
			l["cam"] = target
		l["cam"] = lerpf(float(l["cam"]), target, 1.0 - exp(-delta * 10.0))
	_compute_ranks()
	for p in pops:
		p["t"] = float(p["t"]) + delta
	pops = pops.filter(func(p): return float(p["t"]) < 1.0)
	view.queue_redraw()
	hud.queue_redraw()


func _compute_ranks() -> void:
	var keys := {}
	for id in lanes:
		var l: Dictionary = lanes[id]
		if host_finish.has(id):
			keys[id] = 1.0e7 - float(host_finish[id])
		elif (int(l["st"]) & 2) != 0:
			keys[id] = 1.0e6 + float(l["x"])
		else:
			keys[id] = float(l["x"])
	for id in keys:
		var r := 1
		for o in keys:
			if o != id and float(keys[o]) > float(keys[id]):
				r += 1
		ranks[id] = r
	if playing:
		my_rank = int(ranks.get(me_id, 1))


func _pressed(a: String) -> bool:
	return _q.get(a, false)


func _step(dt: float) -> void:
	if finished:
		v = maxf(0.0, v - 400.0 * dt)
		x += v * dt
		_send(dt)
		return
	splash_t = maxf(0.0, splash_t - dt)
	var stage := _stage_of(x)
	if transit_t > 0.0:
		transit_t -= dt
		_send(dt)
		return
	var inp := _bot_input(stage, dt) if Net.autotest != "" else {
		"a": _pressed("left") or (stage == 1 and _pressed("up")),
		"b": _pressed("right") or (stage == 1 and _pressed("down")),
		"jump": _pressed("jump") or _pressed("push")}
	match stage:
		0, 1:
			# alternance gauche/droite (pagaie) ou haut/bas (pédales)
			var key := -1 if inp["a"] else (1 if inp["b"] else 0)
			if key != 0:
				if key != last_key:
					v = minf(v + (60.0 if stage == 0 else 55.0), 520.0 if stage == 0 else 620.0)
					Sfx.play("step1" if key < 0 else "step2", -10.0, 0.15)
				else:
					v *= 0.82
					splash_t = 0.3
					Sfx.play("bump", -14.0, 0.1)
				last_key = key
			v -= v * (1.2 if stage == 0 else 0.9) * dt
		2:
			if stumble_t > 0.0:
				stumble_t -= dt
				v = move_toward(v, 140.0, 900.0 * dt)
			else:
				v = move_toward(v, 470.0, 520.0 * dt)
			if inp["jump"] and air_t < 0.0:
				air_t = 0.0
				Sfx.play("jump", -6.0)
			if air_t >= 0.0:
				air_t += dt
				if air_t > 0.56:
					air_t = -1.0
			# haies
			for i in hurdles.size():
				if knocked.has(i):
					continue
				var hx := hurdles[i]
				if absf(x - hx) < 20.0 and _height() < 30.0:
					knocked[i] = true
					stumble_t = 0.7
					v = 110.0
					Sfx.play("hurt", -4.0)
					lanes[me_id]["kn"] = knocked
					pops.append({"id": me_id, "x": x, "txt": "OUPS !", "t": 0.0, "c": UI.RED})
	var before := x
	x += v * dt
	# changement d'épreuve
	if _stage_of(before) != _stage_of(x) and x < L3:
		var ns := _stage_of(x)
		x = L1 if ns == 1 else L2
		v = 0.0
		last_key = 0
		transit_t = 0.55
		Sfx.play("spawn", -6.0)
	if x >= L3 and not finished:
		finished = true
		finish_t = race_t
		Net.mg_to_host({"finish": finish_t})
		Sfx.play("gem", 0.0)
		pops.append({"id": me_id, "x": x, "txt": "ARRIVÉ !", "t": 0.0, "c": UI.GREEN})
	_send(dt)


func _height() -> float:
	if air_t < 0.0:
		return 0.0
	var u := air_t / 0.56
	return 4.0 * u * (1.0 - u) * 78.0


func _send(dt: float) -> void:
	lanes[me_id]["x"] = x
	lanes[me_id]["h"] = _height()
	lanes[me_id]["st"] = _pack()
	send_acc += dt
	if send_acc >= 1.0 / 20.0:
		send_acc = 0.0
		Net.send_state(Vector2(x, _height()), Vector2(v, 0), _pack())
	prog_acc += dt
	if prog_acc > 0.5:
		prog_acc = 0.0
		Net.mg_to_host({"prog": x})


func _pack() -> int:
	return (1 if stumble_t > 0.0 else 0) | (2 if finished else 0) | (4 if splash_t > 0.0 else 0) | (8 if transit_t > 0.0 else 0)


func _bot_input(stage: int, dt: float) -> Dictionary:
	var out := {"a": false, "b": false, "jump": false}
	if stage < 2:
		bot_acc += dt
		if bot_acc >= bot_next:
			bot_acc = minf(bot_acc - bot_next, 0.1)
			bot_next = brng.randf_range(0.1, 0.16)
			if brng.randf() < 0.93:
				out["a" if last_key >= 0 else "b"] = true
			else:
				out["a" if last_key < 0 else "b"] = true
	else:
		for hx in hurdles:
			var d := hx - x
			if d > 30.0 and d < 30.0 + v * 0.16 and air_t < 0.0 and brng.randf() < 0.3:
				out["jump"] = true
	return out


func _update_remotes() -> void:
	var rt := Time.get_ticks_msec() / 1000.0 - 0.1
	for id in lanes:
		if id == me_id:
			continue
		var l: Dictionary = lanes[id]
		var snaps: Array = l["snaps"]
		if snaps.is_empty():
			continue
		var p: Vector2 = snaps[-1][1]
		var st := int(snaps[-1][3])
		if rt >= float(snaps[-1][0]):
			p = snaps[-1][1] + Vector2(float(snaps[-1][2].x), 0) * minf(rt - float(snaps[-1][0]), 0.15)
		else:
			for i in range(snaps.size() - 1, 0, -1):
				var a: Array = snaps[i - 1]
				var b: Array = snaps[i]
				if float(a[0]) <= rt:
					var u := clampf((rt - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0])), 0.0, 1.0)
					p = (a[1] as Vector2).lerp(b[1], u)
					st = int(b[3])
					break
		var prev := int(l["st"])
		l["x"] = p.x
		l["h"] = p.y
		l["st"] = st
		# petits événements vus chez les autres
		if (st & 1) != 0 and (prev & 1) == 0:
			var kn: Dictionary = l["kn"]
			for i in hurdles.size():
				if not kn.has(i) and absf(hurdles[i] - p.x) < 120.0:
					kn[i] = true
					break
			pops.append({"id": id, "x": p.x, "txt": "OUPS !", "t": 0.0, "c": UI.RED})


# ------------------------------------------------------------------ dessin
func _lane_geo() -> Array:
	var n := maxi(1, ids.size())
	var lh := clampf(560.0 / n, 66.0, 160.0)
	var top := 106.0 + (560.0 - lh * n) / 2.0
	return [top, lh]


func _draw_view() -> void:
	var c := view
	c.draw_rect(Rect2(0, 0, 1280, 720), Color("#9fd8ff"))
	var geo := _lane_geo()
	var top: float = geo[0]
	var lh: float = geo[1]
	# du bas vers le haut : chaque couloir recouvre ce qui déborde de celui du dessous
	for i in range(ids.size() - 1, -1, -1):
		var id: int = ids[i]
		_draw_lane(c, id, i, top + i * lh, lh, id == me_id and playing)
	c.draw_line(Vector2(0, top + ids.size() * lh), Vector2(1280, top + ids.size() * lh), UI.DARK, 3.0)


func _spr(c: CanvasItem, name: String, feet: Vector2, hgt: float, flip := false) -> void:
	var tx: Texture2D = _deco.get(name)
	if tx == null:
		return
	var s := hgt / float(tx.get_height())
	c.draw_set_transform(feet, 0.0, Vector2(-s if flip else s, s))
	c.draw_texture(tx, Vector2(-tx.get_width() / 2.0, -tx.get_height()))
	c.draw_set_transform(Vector2.ZERO)


func _hash(j: int) -> int:
	var hsh := (j * 7919 + 104729) % 1000003
	return (hsh * 31 + 17) % 9973


func _draw_lane(c: CanvasItem, id: int, li: int, y0: float, lh: float, mine: bool) -> void:
	var l: Dictionary = lanes.get(id, {})
	if l.is_empty():
		return
	var cam: float = l["cam"]
	var k := lh / 150.0
	var gy := y0 + lh * 0.75             # niveau du sol / de l'eau
	var x0 := cam - 80.0
	var x1 := cam + 1360.0
	# ciel + collines lointaines (parallaxe)
	c.draw_rect(Rect2(0, y0, 1280, lh), Color("#c3e3ff"))
	var hills: Texture2D = _deco["hills"]
	var band := (gy - y0) * 0.62
	var hw := 512.0 * band / 284.0
	var off := fmod(cam * 0.3 + li * 130.0, hw)
	var hx0 := -off
	while hx0 < 1280.0:
		c.draw_texture_rect_region(hills, Rect2(hx0, gy - band, hw + 1.0, band), Rect2(0, 228, 512, 284))
		hx0 += hw
	# décor proche selon l'épreuve
	var seg := 170.0
	var j := int(floorf(x0 / seg))
	while j * seg < x1:
		var wx := j * seg
		var st := _stage_of(wx)
		var hsh := _hash(j + li * 37)
		var sx := wx - cam + float(hsh % 60)
		match st:
			0:
				if hsh % 3 != 0:
					var pick: String = ["bush1", "bushAlt2", "tree", "treeSmall_green1", "foliage_020", "bush1"][hsh % 6]
					var hh: float = {"bush1": 44.0, "bushAlt2": 40.0, "tree": 96.0, "treeSmall_green1": 64.0, "foliage_020": 34.0}[pick]
					_spr(c, pick, Vector2(sx, gy - 12 * k), hh * k, hsh % 2 == 0)
			1:
				if hsh % 4 == 0:
					_spr(c, "fence", Vector2(sx, gy + 2 * k), 34 * k)
					_spr(c, "fence", Vector2(sx + 42 * k, gy + 2 * k), 34 * k)
				elif hsh % 4 != 1:
					var pick2: String = ["tree", "treePine", "bush1", "treeSmall_green2", "treePine"][hsh % 5]
					var hh2: float = {"tree": 100.0, "treePine": 108.0, "bush1": 42.0, "treeSmall_green2": 66.0}[pick2]
					_spr(c, pick2, Vector2(sx, gy + 2 * k), hh2 * k, hsh % 2 == 1)
			2:
				# tribune avec le public
				var tr := Rect2(wx - cam, gy - 50 * k, seg + 1.0, 50 * k)
				c.draw_rect(tr, Color("#8a8fa8"))
				for s in 8:
					var bounce := absf(sin(t * 6.0 + s * 1.7 + j)) * 4.0 * k
					var cc: Color = [Color("#f04650"), Color("#4b87f5"), Color("#facd2d"), Color("#5fcd55"), Color("#f08c3c")][(s + hsh) % 5]
					var pp := Vector2(tr.position.x + 12 + s * 20, tr.position.y + 16 * k + (s % 2) * 16 * k - bounce)
					c.draw_circle(pp, 7.0 * k, UI.DARK)
					c.draw_circle(pp, 5.0 * k, cc)
				c.draw_line(tr.position, tr.position + Vector2(seg + 1.0, 0), UI.DARK, 3.0)
				c.draw_rect(Rect2(tr.position.x, tr.position.y - 8 * k, seg + 1.0, 8 * k), Color("#e0643c"))
		j += 1
	# sol de chaque épreuve
	_ground(c, cam, 0, maxf(x0, -600.0), minf(x1, L1), gy, y0, lh, k)
	_ground(c, cam, 1, maxf(x0, L1), minf(x1, L2), gy, y0, lh, k)
	_ground(c, cam, 2, maxf(x0, L2), x1, gy, y0, lh, k)
	# départ
	var dx := -cam
	if dx > -40 and dx < 1340:
		_spr(c, "flag_green_a", Vector2(dx - 70 * k, gy - 4 * k), 60 * k)
	# panneaux de changement d'épreuve
	for b in [[L1, "VÉLO"], [L2, "HAIES"]]:
		var bx := float(b[0]) - cam
		if bx > -100 and bx < 1400:
			c.draw_rect(Rect2(bx - 4 * k, gy - 64 * k, 8 * k, 64 * k), UI.DARK)
			c.draw_rect(Rect2(bx - 2 * k, gy - 64 * k, 4 * k, 64 * k), Color("#c98a4e"))
			var r := Rect2(Vector2(bx - 48 * k, gy - 94 * k), Vector2(96 * k, 32 * k))
			c.draw_style_box(UI.box(UI.YELLOW, UI.DARK, 3, 8), r)
			UI.text(c, r.get_center(), b[1], int(17 * k + 4), UI.DARK, 0)
	# haies
	var kn: Dictionary = l.get("kn", {})
	for i in hurdles.size():
		var hxs := hurdles[i] - cam
		if hxs < -50 or hxs > 1330:
			continue
		_hurdle(c, Vector2(hxs, gy), k, kn.has(i))
	# arrivée
	var fx := L3 - cam
	if fx > -40 and fx < 1340:
		var cell := maxf(8.0, 12.0 * k)
		for jj in int((y0 + lh - (gy - 30 * k)) / cell) + 1:
			var yy := gy - 30 * k + jj * cell
			var hcell := minf(cell, y0 + lh - yy)
			if hcell <= 0.0:
				break
			c.draw_rect(Rect2(fx, yy, cell, hcell), Color.WHITE if jj % 2 == 0 else UI.DARK)
			c.draw_rect(Rect2(fx + cell, yy, cell, hcell), UI.DARK if jj % 2 == 0 else Color.WHITE)
		_spr(c, "flag_red_a", Vector2(fx + cell * 0.5, gy - 28 * k), 62 * k)
	# l'athlète
	_athlete(c, id, Vector2(float(l["x"]) - cam, gy), float(l["h"]), int(l["st"]), k)
	# textes qui montent
	for p in pops:
		if int(p["id"]) != id:
			continue
		var q: float = float(p["t"])
		UI.text(c, Vector2(float(p["x"]) - cam, gy - 96 * k - q * 26.0), p["txt"], int(20 * k + 8), Color(p["c"], 1.0 - q * q), 6)
	# bandeau du couloir
	c.draw_line(Vector2(0, y0), Vector2(1280, y0), UI.DARK, 3.0)
	var fs := int(clampf(12.0 + 4.0 * k, 13.0, 17.0))
	var tag := Rect2(Vector2(8, y0 + 6), Vector2(UI.text_width(Net.name_of(id), fs) + 22, fs + 9))
	c.draw_style_box(UI.box(Net.color_of(id), UI.DARK, 3, 8), tag)
	UI.text(c, tag.get_center(), Net.name_of(id), fs, UI.WHITE, 4)
	# rang dans le couloir
	var rk := int(ranks.get(id, 1))
	var rtxt := "%d%s" % [rk, "er" if rk == 1 else "e"]
	var rcol: Color = [UI.YELLOW, Color("#dfe4ee"), Color("#e09a5a")][rk - 1] if rk <= 3 else UI.WHITE
	UI.text(c, Vector2(1236, y0 + lh * 0.3), rtxt, int(clampf(20.0 + 14.0 * k, 22.0, 38.0)), rcol, 8)
	if (int(l["st"]) & 2) != 0:
		var ft: float = float(host_finish.get(id, -1.0))
		var lbl := "ARRIVÉ !" if ft < 0.0 else "ARRIVÉ EN %.1f s" % ft
		var bw := UI.text_width(lbl, fs + 2) + 26.0
		var br := Rect2(Vector2(640 - bw / 2.0, y0 + 6), Vector2(bw, fs + 12))
		c.draw_style_box(UI.box(UI.GREEN, UI.DARK, 3, 8), br)
		UI.text(c, br.get_center(), lbl, fs + 2, UI.WHITE, 4)
	if mine:
		c.draw_rect(Rect2(2, y0 + 2, 1276, lh - 3), UI.YELLOW, false, 4.0)


func _ground(c: CanvasItem, cam: float, st: int, a: float, b: float, gy: float, y0: float, lh: float, k: float) -> void:
	if b <= a:
		return
	var sa := a - cam
	var sb := b - cam
	var bottom := y0 + lh
	match st:
		0:
			# berge puis rivière
			c.draw_rect(Rect2(sa, gy - 18 * k, sb - sa, 14 * k), Color("#5cb84e"))
			c.draw_line(Vector2(sa, gy - 18 * k), Vector2(sb, gy - 18 * k), UI.DARK, 3.0)
			c.draw_rect(Rect2(sa, gy - 6 * k, sb - sa, bottom - gy + 6 * k), Color("#3aa3e8"))
			c.draw_rect(Rect2(sa, gy - 6 * k, sb - sa, 5 * k), Color("#8fd6fb"))
			c.draw_line(Vector2(sa, gy - 6 * k), Vector2(sb, gy - 6 * k), UI.DARK, 2.0)
			var w := floorf(a / 70.0) * 70.0
			while w < b:
				var wx := w - cam + fmod(t * 30.0, 70.0)
				c.draw_arc(Vector2(wx, gy + 14 * k), 10.0 * k, PI * 1.1, PI * 1.9, 6, Color(1, 1, 1, 0.6), 2.5)
				w += 70.0
		1:
			c.draw_rect(Rect2(sa, gy, sb - sa, bottom - gy), Color("#5cb84e"))
			c.draw_rect(Rect2(sa, gy, sb - sa, 22 * k), Color("#8a8fa8"))
			c.draw_line(Vector2(sa, gy), Vector2(sb, gy), UI.DARK, 3.0)
			c.draw_line(Vector2(sa, gy + 22 * k), Vector2(sb, gy + 22 * k), UI.DARK, 2.0)
			var d := floorf(a / 60.0) * 60.0
			while d < b:
				c.draw_rect(Rect2(d - cam, gy + 10 * k, 28, 3), Color.WHITE)
				d += 60.0
		2:
			c.draw_rect(Rect2(sa, gy, sb - sa, bottom - gy), Color("#5cb84e"))
			c.draw_rect(Rect2(sa, gy, sb - sa, 24 * k), Color("#e0643c"))
			c.draw_line(Vector2(sa, gy), Vector2(sb, gy), UI.DARK, 3.0)
			c.draw_line(Vector2(sa, gy + 24 * k), Vector2(sb, gy + 24 * k), UI.DARK, 2.0)
			c.draw_rect(Rect2(sa, gy + 11 * k, sb - sa, 2), Color.WHITE)


func _hurdle(c: CanvasItem, p: Vector2, k: float, down: bool) -> void:
	var h := 40.0 * k
	if down:
		c.draw_line(p + Vector2(-16, -4) * k, p + Vector2(18, -10) * k, UI.DARK, 9.0 * k)
		c.draw_line(p + Vector2(-16, -4) * k, p + Vector2(18, -10) * k, Color.WHITE, 5.0 * k)
		return
	for sx in [-14.0, 14.0]:
		c.draw_line(p + Vector2(sx, 0) * k, p + Vector2(sx * k, -h), UI.DARK, 6.0 * k)
		c.draw_line(p + Vector2(sx, 0) * k, p + Vector2(sx * k, -h), Color("#c9cde0"), 3.0 * k)
	var bar := Rect2(p + Vector2(-20 * k, -h - 6 * k), Vector2(40 * k, 10 * k))
	c.draw_style_box(UI.box(Color.WHITE, UI.DARK, 3, 3), bar)
	c.draw_rect(Rect2(bar.position + Vector2(10 * k, 2), Vector2(9 * k, bar.size.y - 4)), UI.RED)
	c.draw_rect(Rect2(bar.position + Vector2(25 * k, 2), Vector2(7 * k, bar.size.y - 4)), UI.RED)


func _athlete(c: CanvasItem, id: int, p: Vector2, h: float, st: int, k: float) -> void:
	var col := Net.color_of(id)
	var lx := float(lanes[id]["x"])
	var stage := _stage_of(lx)
	var transit := (st & 8) != 0
	var sc := 0.33 * k
	var bob := sin(t * 10.0 + id) * 2.0 * k
	match stage:
		0:
			# canoë
			var hull := PackedVector2Array()
			for j in 13:
				var a := j * PI / 12.0
				hull.append(p + Vector2(cos(a) * 62.0, sin(a) * 16.0 - 4.0) * k)
			hull.append(p + Vector2(-70, -10) * k)
			hull.append(p + Vector2(70, -10) * k)
			_tex_char(c, id, "idle", p + Vector2(0, -6 * k + bob), sc)
			c.draw_colored_polygon(hull, col)
			var hl := hull.duplicate()
			hl.append(hull[0])
			c.draw_polyline(hl, UI.DARK, 3.0, true)
			c.draw_line(p + Vector2(-50, -6) * k, p + Vector2(50, -6) * k, col.lightened(0.35), 4.0 * k)
			var pa := sin(lx * 0.02) * 0.9 if not transit else 0.0
			var pc := p + Vector2(4, -30) * k
			var dir := Vector2(cos(pa + PI / 2.0), sin(pa + PI / 2.0))
			c.draw_line(pc - dir * 40.0 * k, pc + dir * 40.0 * k, UI.DARK, 7.0 * k)
			c.draw_line(pc - dir * 40.0 * k, pc + dir * 40.0 * k, Color("#c98a4e"), 3.5 * k)
			var blade := pc + dir * 40.0 * k
			c.draw_circle(blade, 7.0 * k, UI.DARK)
			c.draw_circle(blade, 5.0 * k, Color("#c98a4e"))
			if (st & 4) != 0:
				for j in 4:
					c.draw_circle(p + Vector2(randf_range(-60, 60), randf_range(-14, 4)) * k, 5.0 * k, Color(1, 1, 1, 0.8))
		1:
			# vélo
			var spin := lx * 0.05
			for wx in [-30.0, 32.0]:
				var wc := p + Vector2(wx, -18) * k
				c.draw_arc(wc, 18.0 * k, 0, TAU, 24, UI.DARK, 6.0 * k)
				c.draw_arc(wc, 18.0 * k, 0, TAU, 24, Color("#4a4f63"), 3.0 * k)
				for s in 3:
					var a2 := spin + s * TAU / 3.0
					c.draw_line(wc, wc + Vector2(cos(a2), sin(a2)) * 16.0 * k, Color("#c9cde0"), 2.0)
				c.draw_circle(wc, 3.0 * k, UI.DARK)
			var seat := p + Vector2(-8, -44) * k
			var front := p + Vector2(32, -18) * k
			var back := p + Vector2(-30, -18) * k
			var pedal := p + Vector2(0, -20) * k
			for seg in [[back, seat], [seat, front], [back, pedal], [pedal, seat]]:
				c.draw_line(seg[0], seg[1], UI.DARK, 7.0 * k)
			for seg in [[back, seat], [seat, front], [back, pedal], [pedal, seat]]:
				c.draw_line(seg[0], seg[1], col, 3.5 * k)
			c.draw_line(p + Vector2(24, -50) * k, front, UI.DARK, 5.0 * k)
			c.draw_line(p + Vector2(18, -52) * k, p + Vector2(32, -50) * k, UI.DARK, 5.0 * k)
			_tex_char(c, id, "walk_a" if int(lx / 50.0) % 2 == 0 else "walk_b", seat + Vector2(4, 10) * k + Vector2(0, bob * 0.5), sc)
		2:
			var pose := "walk_a" if int(lx / 40.0) % 2 == 0 else "walk_b"
			if h > 2.0:
				pose = "jump"
			if (st & 1) != 0:
				pose = "hit"
			c.draw_circle(p + Vector2(0, 2), 18.0 * k * (1.0 - h / 160.0), Color(0, 0, 0, 0.2))
			_tex_char(c, id, pose, p + Vector2(0, -h * k * 0.62), sc)


func _tex_char(c: CanvasItem, id: int, pose: String, feet: Vector2, sc: float) -> void:
	var tx: Texture2D = _tex.get("%d_%s" % [id, pose])
	if tx == null:
		return
	c.draw_set_transform(feet, 0.0, Vector2(sc, sc))
	c.draw_texture(tx, Vector2(-128, -256))
	c.draw_set_transform(Vector2.ZERO)


# ------------------------------------------------------------------ HUD
func _draw_hud() -> void:
	var h := hud
	if state == "intro":
		h.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, 0.45))
		var r := Rect2(Vector2(220, 110), Vector2(840, 450))
		h.draw_style_box(UI.box(UI.WHITE, UI.DARK, 6, 30), r)
		UI.text(h, Vector2(640, 176), "Mini-triathlon !", 56, UI.YELLOW, 14)
		var lines := ["Trois épreuves à la suite, le premier arrivé gagne !",
			"1. PAGAIE : appuie sur Q et D (ou ← →) en alternance.",
			"2. VÉLO : appuie sur Z et S (ou ↑ ↓) en alternance.",
			"3. HAIES : tu cours tout seul, ESPACE pour sauter.",
			"Deux fois la même touche = tu ralentis !"]
		for i in lines.size():
			h.draw_string(UI.font(), Vector2(220, 250 + i * 38), lines[i], HORIZONTAL_ALIGNMENT_CENTER, 840, 24, UI.DARK)
		preload("res://minigames/stage.gd").draw_ready_row(h, my_ready, ready_ids, lanes.keys(), t, not playing)
		if str(Net.mg_data.get("mode", "")) == "duel":
			preload("res://minigames/stage.gd").draw_duel_banner(h)
		return
	# barre de progression
	var bar := Rect2(Vector2(240, 22), Vector2(800, 30))
	h.draw_style_box(UI.box(UI.WHITE, UI.DARK, 4, 12), bar)
	var cols := [Color("#3aa3e8"), Color("#8a8fa8"), Color("#e0643c")]
	var bounds := [0.0, L1, L2, L3]
	for s in 3:
		var a: float = bar.position.x + 6 + (bar.size.x - 12) * float(bounds[s]) / L3
		var b: float = bar.position.x + 6 + (bar.size.x - 12) * float(bounds[s + 1]) / L3
		h.draw_rect(Rect2(a, bar.position.y + 6, b - a - 2, bar.size.y - 12), Color(cols[s], 0.55))
		UI.text(h, Vector2((a + b) / 2.0, bar.position.y + 15), STAGE_NAMES[s], 14, UI.WHITE, 4)
	for id in ids:
		if not lanes.has(id):
			continue
		var px: float = bar.position.x + 6 + (bar.size.x - 12) * clampf(float(lanes[id]["x"]) / L3, 0.0, 1.0)
		h.draw_circle(Vector2(px, bar.position.y + bar.size.y + 8), 8.0 if id == me_id else 6.0, UI.DARK)
		h.draw_circle(Vector2(px, bar.position.y + bar.size.y + 8), 6.0 if id == me_id else 4.0, Net.color_of(id))
	# chrono
	var tr := Rect2(Vector2(24, 18), Vector2(150, 44))
	h.draw_style_box(UI.box(UI.WHITE, UI.DARK, 4, 14), tr)
	var shown := finish_t if finished else race_t
	UI.text(h, tr.get_center(), "%d:%04.1f" % [int(shown) / 60, fmod(shown, 60.0)], 22, UI.DARK, 0)
	if playing:
		var suffix := "er" if my_rank == 1 else "e"
		var pc: Color = [UI.YELLOW, Color("#c9d0dc"), Color("#e09a5a"), UI.WHITE][mini(my_rank - 1, 3)]
		UI.text(h, Vector2(1180, 46), "%d%s" % [my_rank, suffix], 56, pc, 14)
		if state == "race" and not finished:
			var stg := _stage_of(x)
			var help: String = STAGE_HELP[stg]
			var hw := UI.text_width(help, 26) + 50.0
			var pulse := 1.0 + 0.04 * sin(t * 10.0)
			h.draw_style_box(UI.box(Color(UI.DARK, 0.82), UI.DARK, 0, 16), Rect2(Vector2(640 - hw / 2.0, 676), Vector2(hw, 40)))
			UI.text(h, Vector2(640, 696), help, int(26 * pulse), UI.YELLOW, 0)
	if state == "count":
		UI.text(h, Vector2(640, 360), str(3 - int(t)), int(110 * (1.0 + (1.0 - fmod(t, 1.0)) * 0.3)), UI.WHITE, 16)
	elif state == "race" and t < 1.0:
		UI.text(h, Vector2(640, 360), "GO !", int(120 * (1.0 + t * 0.4)), Color(UI.GREEN, 1.0 - t), 18)
	if state == "over" or state == "ending":
		h.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, minf(0.4, t)))
		UI.text(h, Vector2(640, 360), "TERMINÉ !", 96, UI.YELLOW, 16)
