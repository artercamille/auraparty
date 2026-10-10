extends Node2D
## « Pingouins perdus ! » (Penguin Pushers, Super Mario Party) : jeu COOP.
## Tout le monde ensemble doit ramener les bébés pingouins vers leur parent, qui attend derrière
## la fente en bas de la banquise. Les bébés s'enfuient quand on s'approche : il faut les rabattre.
## Rang selon le temps : S ≤ 45 s, A ≤ 55 s, B ≤ 60 s, sinon raté. Tout le monde gagne les mêmes pièces.
## L'hôte fait bouger les pingouins ; chacun déplace son perso et l'envoie aux autres.

const C := Vector2(640, 372)
const SQ := 0.8
const ARENA := Rect2(-540, -255, 1080, 510)
const GAP := 78.0
const PARENT := Vector2(0, 372)
const LIMIT := 60.0
const RANKS := [[45.0, "S", 10], [55.0, "A", 7], [60.0, "B", 4]]
const P_SPEED := 300.0
const PEN_R := 22.0
const SCARE := 175.0

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

var pens: Array = []            # {p, v, saved, st (moment sauvé), w (direction d'errance), wt}
var bodies := {}                # id -> {p, v, snaps, face, walk}
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var send_acc := 0.0
var result := {}                # rang final {rank, t, coins}
var hearts: Array = []
# hôte
var h_acc := 0.0
var h_done := false
var h_end_t := -1.0
# robot
var bot_target := -1
var bot_t := 0.0


func _ready() -> void:
	rng.seed = int(Net.mg_data.get("seed", 1))
	brng.randomize()
	for id in Net.mg_data.get("players", Net.players.keys()):
		if Net.players.has(id):
			ids.append(id)
	ids.sort()
	me_id = Net.my_id()
	playing = ids.has(me_id)
	var n := 6 if ids.size() <= 3 else (8 if ids.size() <= 5 else 10)
	for i in n:
		var p := Vector2(rng.randf_range(-470, 470), rng.randf_range(-220, 40))
		pens.append({"p": p, "v": Vector2.ZERO, "saved": false, "st": 0.0, "w": Vector2.from_angle(rng.randf() * TAU), "wt": rng.randf_range(0.5, 2.0)})
	for i in ids.size():
		var id: int = ids[i]
		var p := Vector2((float(i) - (ids.size() - 1) / 2.0) * 110.0, 200)
		bodies[id] = {"p": p, "v": Vector2.ZERO, "snaps": [], "face": 1, "walk": 0.0}
		if id == me_id:
			pos = p
		for pose in ["idle", "walk_a", "walk_b", "jump", "front"]:
			_tex["%d_%s" % [id, pose]] = UI.char_tex(Net.color_idx(id), pose)
	_tex["penguin"] = load("res://assets/coop/penguin.png")
	_tex["heart"] = load("res://assets/tiles/heart.png")
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
	Net.mg_state.connect(_on_mg_state)
	Net.mg_ending.connect(_on_ending)
	Net.mg_ready_changed.connect(func(r): ready_ids = r)
	Net.mg_go.connect(func(): go_received = true)
	Net.players_changed.connect(_on_players_changed)


func _on_ending() -> void:
	state = "over"
	t = 0.0


func _on_players_changed() -> void:
	for id in bodies.keys():
		if not Net.players.has(id):
			bodies.erase(id)
	for id in ids.duplicate():
		if not Net.players.has(id):
			ids.erase(id)


func scr(p: Vector2) -> Vector2:
	return C + Vector2(p.x, p.y * SQ)


func saved_count() -> int:
	var n := 0
	for pg in pens:
		if pg["saved"]:
			n += 1
	return n


# ------------------------------------------------------------------ mon perso
func _step(dt: float) -> void:
	var d := Vector2.ZERO
	if Net.autotest != "":
		d = _bot_dir(dt)
	else:
		d = Vector2(Input.get_axis("left", "right"), Input.get_axis("up", "down")).limit_length(1.0)
	vel = vel.move_toward(d * P_SPEED, 2400.0 * dt)
	pos += vel * dt
	pos.x = clampf(pos.x, ARENA.position.x + 26.0, ARENA.end.x - 26.0)
	pos.y = clampf(pos.y, ARENA.position.y + 26.0, ARENA.end.y - 26.0)
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


func _bot_dir(dt: float) -> Vector2:
	bot_t -= dt
	if bot_target < 0 or pens[bot_target]["saved"] or bot_t <= 0.0:
		bot_t = brng.randf_range(2.5, 4.0)
		var cand := []
		for i in pens.size():
			if not pens[i]["saved"]:
				cand.append(i)
		if cand.is_empty():
			return Vector2.ZERO
		# le pingouin le plus loin de la sortie, avec un peu de hasard
		cand.sort_custom(func(a, b): return (pens[a]["p"] as Vector2).distance_to(Vector2(0, ARENA.end.y)) > (pens[b]["p"] as Vector2).distance_to(Vector2(0, ARENA.end.y)))
		bot_target = cand[mini(cand.size() - 1, brng.randi_range(0, 2))]
	var pp: Vector2 = pens[bot_target]["p"]
	var exit := Vector2(0, ARENA.end.y + 30)
	var behind := pp + (pp - exit).normalized() * 120.0
	var dv := behind - pos
	if dv.length() < 20.0:
		return (exit - pos).normalized() * 0.5
	# contourner le pingouin pour ne pas le pousser du mauvais côté
	if pos.distance_to(pp) < 150.0 and (pos - pp).dot(pp - exit) < 0.0:
		var side := (pos - pp).orthogonal().normalized()
		return (dv.normalized() + side * 0.9).normalized()
	return dv.normalized()


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


# ------------------------------------------------------------------ hôte : les pingouins
func _host_step(dt: float) -> void:
	if h_end_t >= 0.0:
		h_end_t -= dt
		if h_end_t <= 0.0:
			h_end_t = -1.0
			Net.mg_end_coop(int(result.get("coins", 0)), "Rang %s : +%d pièces" % [str(result.get("rank", "-")), int(result.get("coins", 0))] if str(result.get("rank", "")) != "raté" else "Raté... 0 pièce")
		return
	if h_done:
		return
	for i in pens.size():
		var pg: Dictionary = pens[i]
		if pg["saved"]:
			continue
		var p: Vector2 = pg["p"]
		var v: Vector2 = pg["v"]
		var force := Vector2.ZERO
		var scared := false
		for id in bodies:
			var dv: Vector2 = p - (bodies[id]["p"] as Vector2)
			var d := dv.length()
			if d < SCARE and d > 0.1:
				force += dv / d * (SCARE - d) * 11.0
				scared = true
		# errance tranquille
		pg["wt"] = float(pg["wt"]) - dt
		if float(pg["wt"]) <= 0.0:
			pg["wt"] = rng.randf_range(0.8, 2.2)
			pg["w"] = Vector2.from_angle(rng.randf() * TAU) if rng.randf() < 0.7 else Vector2.ZERO
		if not scared:
			force += (pg["w"] as Vector2) * 160.0
		# on s'écarte des autres bébés
		for j in pens.size():
			if j == i or pens[j]["saved"]:
				continue
			var dd: Vector2 = p - (pens[j]["p"] as Vector2)
			if dd.length() < PEN_R * 2.2 and dd.length() > 0.1:
				force += dd.normalized() * 500.0
		v += force * dt
		v -= v * 3.0 * dt
		v = v.limit_length(215.0 if scared else 70.0)
		p += v * dt
		# murs (sauf la fente en bas)
		var in_gap := absf(p.x) < GAP - PEN_R * 0.6
		if p.x < ARENA.position.x + PEN_R:
			p.x = ARENA.position.x + PEN_R
			v.x = absf(v.x) * 0.5
		if p.x > ARENA.end.x - PEN_R:
			p.x = ARENA.end.x - PEN_R
			v.x = -absf(v.x) * 0.5
		if p.y < ARENA.position.y + PEN_R:
			p.y = ARENA.position.y + PEN_R
			v.y = absf(v.y) * 0.5
		if p.y > ARENA.end.y - PEN_R and not in_gap:
			if p.y < ARENA.end.y + 4.0:
				p.y = ARENA.end.y - PEN_R
				v.y = -absf(v.y) * 0.5
		if p.y > ARENA.end.y + 6.0:
			p.x = clampf(p.x, -GAP + PEN_R * 0.6, GAP - PEN_R * 0.6)
		pg["p"] = p
		pg["v"] = v
		if p.y > ARENA.end.y + 26.0:
			pg["saved"] = true
			pg["st"] = play_t
			Net.mg_broadcast({"saved": i, "at": play_t})
	h_acc += dt
	if h_acc >= 1.0 / 20.0:
		h_acc = 0.0
		var flat := PackedFloat32Array()
		for pg in pens:
			flat.append((pg["p"] as Vector2).x)
			flat.append((pg["p"] as Vector2).y)
		Net.mg_broadcast({"pp": flat})
	var n := saved_count()
	if n >= pens.size() or play_t >= LIMIT:
		h_done = true
		var rank := "raté"
		var coins := 0
		if n >= pens.size():
			for r in RANKS:
				if play_t <= float(r[0]):
					rank = str(r[1])
					coins = int(r[2])
					break
		Net.mg_broadcast({"result": rank, "t": play_t, "coins": coins, "n": n})
		h_end_t = 2.6
		if Net.autotest != "":
			print("[penguins] fin t=", snappedf(play_t, 0.1), " sauvés ", n, "/", pens.size(), " rang ", rank)


func _on_mg_state(d: Dictionary) -> void:
	if d.has("pp") and not Net.is_host():
		var flat: PackedFloat32Array = d["pp"]
		for i in mini(pens.size(), flat.size() / 2):
			if pens[i]["saved"]:
				continue
			var np := Vector2(flat[i * 2], flat[i * 2 + 1])
			pens[i]["v"] = (np - (pens[i]["p"] as Vector2)) * 20.0
			pens[i]["target"] = np
	elif d.has("saved"):
		var i := int(d["saved"])
		pens[i]["saved"] = true
		pens[i]["st"] = play_t
		Sfx.play("coin", -2.0)
		Sfx.play("jingle_item", -8.0, 0.0)
		hearts.append({"p": PARENT + Vector2(0, -40), "t": 0.0})
	elif d.has("result"):
		result = {"rank": str(d["result"]), "t": float(d["t"]), "coins": int(d["coins"]), "n": int(d["n"])}
		if str(d["result"]) == "raté":
			Sfx.play("jingle_bad", 0.0, 0.0)
		else:
			Sfx.play("jingle_star", 0.0, 0.0)
			Sfx.voice("congratulations")


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
			if playing:
				_step(delta)
			if Net.is_host():
				_host_step(delta)
	_update_remotes()
	# côté client : les pingouins glissent vers leur position reçue
	if not Net.is_host():
		for pg in pens:
			if pg.has("target") and not pg["saved"]:
				pg["p"] = (pg["p"] as Vector2).lerp(pg["target"], 1.0 - exp(-delta * 14.0))
	for h in hearts:
		h["t"] = float(h["t"]) + delta
	hearts = hearts.filter(func(h): return float(h["t"]) < 1.2)
	view.queue_redraw()
	hud.queue_redraw()


# ------------------------------------------------------------------ dessin
func _draw_view() -> void:
	var c := view
	c.draw_rect(Rect2(-20, -20, 1320, 760), Color("#cfeaf8"))
	# neige autour
	for k in 26:
		var x := float((k * 211) % 1300)
		var y := float((k * 97) % 720)
		c.draw_circle(Vector2(x, y), 30.0 + (k % 4) * 12.0, Color(1, 1, 1, 0.5))
	# la banquise
	var tl := scr(ARENA.position)
	var br := scr(ARENA.end)
	var ar := Rect2(tl, br - tl)
	c.draw_style_box(UI.box(Color("#9fd6f0"), Color(0, 0, 0, 0), 0, 40), Rect2(ar.position + Vector2(0, 24), ar.size).grow(26))
	c.draw_style_box(UI.box(Color("#e9f7ff"), UI.WHITE, 10, 40), ar.grow(26))
	c.draw_style_box(UI.box(Color("#bfe6fa"), Color(0, 0, 0, 0), 0, 30), ar)
	for k in 9:
		var cx := ar.position.x + 60.0 + k * 120.0
		c.draw_line(Vector2(cx, ar.position.y + 40), Vector2(cx + 50, ar.position.y + 70), Color(1, 1, 1, 0.5), 3.0)
		c.draw_line(Vector2(cx + 30, ar.end.y - 80), Vector2(cx + 90, ar.end.y - 60), Color(1, 1, 1, 0.45), 3.0)
	# la fente en bas
	var g1 := scr(Vector2(-GAP, ARENA.end.y))
	var g2 := scr(Vector2(GAP, ARENA.end.y))
	c.draw_rect(Rect2(g1 - Vector2(0, 4), Vector2(g2.x - g1.x, 120)), Color("#bfe6fa"))
	for sx in [-1.0, 1.0]:
		c.draw_circle(scr(Vector2(sx * GAP, ARENA.end.y)) + Vector2(0, 12), 16.0, UI.WHITE)
	for k in 3:
		var ay := g1.y + 14.0 + k * 22.0 + fmod(t * 30.0, 22.0)
		c.draw_colored_polygon(PackedVector2Array([Vector2(640 - 18, ay), Vector2(640 + 18, ay), Vector2(640, ay + 14)]), Color(1, 1, 1, 0.55))
	# le parent et les bébés sauvés
	var pp := scr(PARENT)
	_shadow(c, pp, 60.0)
	var bob := sin(t * 3.0) * 4.0
	c.draw_set_transform(pp + Vector2(0, -44 + bob), sin(t * 2.0) * 0.06, Vector2(0.8, 0.8))
	c.draw_texture(_tex["penguin"], Vector2(-64, -64))
	c.draw_set_transform(Vector2.ZERO)
	var k2 := 0
	for pg in pens:
		if pg["saved"]:
			var sp := pp + Vector2((k2 % 2 * 2 - 1) * (80.0 + (k2 / 2) * 44.0), -2)
			k2 += 1
			var age := play_t - float(pg["st"])
			var hop := absf(sin(t * 6.0 + k2)) * 8.0
			c.draw_set_transform(sp + Vector2(0, -24 - hop), 0.0, Vector2(0.38, 0.38) * minf(1.0, 0.4 + age * 2.0))
			c.draw_texture(_tex["penguin"], Vector2(-64, -64))
			c.draw_set_transform(Vector2.ZERO)
	for h in hearts:
		var hk := float(h["t"]) / 1.2
		c.draw_texture_rect(_tex["heart"], Rect2(scr(h["p"]) + Vector2(-16, -60 - hk * 50.0), Vector2(32, 32)), false, Color(1, 1, 1, 1.0 - hk))
	# pingouins et persos, de l'arrière vers l'avant
	var things := []
	for i in pens.size():
		if not pens[i]["saved"]:
			things.append(["pen", i, (pens[i]["p"] as Vector2).y])
	for id in bodies:
		things.append(["pl", id, (bodies[id]["p"] as Vector2).y])
	things.sort_custom(func(a, b): return float(a[2]) < float(b[2]))
	for th in things:
		if th[0] == "pen":
			_draw_pen(c, int(th[1]))
		else:
			_draw_body(c, int(th[1]))


func _shadow(c: CanvasItem, p: Vector2, w: float) -> void:
	c.draw_set_transform(p, 0.0, Vector2(1.0, 0.36))
	c.draw_circle(Vector2.ZERO, w / 2.0, Color(0.1, 0.3, 0.5, 0.2))
	c.draw_set_transform(Vector2.ZERO)


func _draw_pen(c: CanvasItem, i: int) -> void:
	var pg: Dictionary = pens[i]
	var p := scr(pg["p"])
	var v: Vector2 = pg["v"]
	var fast := v.length() > 110.0
	_shadow(c, p, 46.0)
	var wob := sin(t * (16.0 if fast else 6.0) + i) * (0.22 if fast else 0.08)
	c.draw_set_transform(p + Vector2(0, -22 - absf(sin(t * 8.0 + i)) * (4.0 if fast else 1.0)), wob, Vector2(0.42, 0.42))
	c.draw_texture(_tex["penguin"], Vector2(-64, -64))
	c.draw_set_transform(Vector2.ZERO)
	if fast:
		c.draw_circle(p + Vector2(18, -46), 4.0, Color("#7fd0f2"))
		c.draw_circle(p + Vector2(23, -54), 2.5, Color("#7fd0f2"))


func _draw_body(c: CanvasItem, id: int) -> void:
	var b: Dictionary = bodies[id]
	var g := scr(b["p"])
	_shadow(c, g, 64.0)
	var moving := (b["v"] as Vector2).length() > 30.0
	var pose := ("walk_a" if int(float(b["walk"]) / 34.0) % 2 == 0 else "walk_b") if moving else "idle"
	c.draw_set_transform(g, 0.0, Vector2(0.44 * float(b["face"]), 0.44))
	c.draw_texture(_tex["%d_%s" % [id, pose]], Vector2(-128, -256))
	c.draw_set_transform(Vector2.ZERO)
	UI.text(c, g + Vector2(0, -122), "TOI" if id == me_id else Net.name_of(id), 17 if id == me_id else 14, UI.YELLOW if id == me_id else Net.color_of(id), 5)


# ------------------------------------------------------------------ HUD
func _draw_hud() -> void:
	var h := hud
	var St := preload("res://minigames/stage.gd")
	if state == "intro":
		St.draw_intro(h, "Pingouins perdus !", [
			"JEU COOP : tout le monde joue ensemble !",
			"Ramenez les bébés pingouins à leur parent, derrière la fente en bas.",
			"Ils s'enfuient quand on s'approche : rabattez-les ensemble !",
			"Astuce : un joueur près de la sortie, c'est plus facile.",
			"Rang S en 45 s : 10 pièces chacun · A en 55 s : 7 · B en 60 s : 4"],
			"Bouger : flèches ou Z Q S D")
		St.draw_ready_row(h, my_ready, ready_ids, ids, t, not playing)
		return
	# chrono + objectif
	var left := maxf(0.0, LIMIT - play_t)
	var tr := Rect2(Vector2(24, 18), Vector2(130, 56))
	UI.panel(h, tr, UI.WHITE, Color("#cfeaf8"), 18, 4)
	UI.text(h, UI.face_center(tr), "%d s" % ceili(left), 32, UI.RED if left <= 10.0 else UI.DARK, 0)
	var cnt := Rect2(Vector2(640 - 170, 16), Vector2(340, 60))
	UI.panel(h, cnt, Color("#4b87f5"), UI.WHITE, 24, 5)
	h.draw_texture_rect(_tex["penguin"], Rect2(cnt.position + Vector2(14, 8), Vector2(44, 44)), false)
	UI.text(h, UI.face_center(cnt) + Vector2(24, 0), "Sauvés : %d / %d" % [saved_count(), pens.size()], 26, UI.WHITE, 6)
	# rang visé en fonction du temps
	var target := "raté"
	for r in RANKS:
		if play_t <= float(r[0]):
			target = "Rang %s possible" % str(r[1])
			break
	UI.text(h, Vector2(1150, 46), target, 20, UI.WHITE, 6)
	if state == "count":
		UI.text(h, Vector2(640, 380), str(3 - int(t)), int(110 * (1.0 + (1.0 - fmod(t, 1.0)) * 0.3)), UI.WHITE, 16)
	elif state == "play" and t < 1.0:
		UI.text(h, Vector2(640, 380), "GO !", int(120 * (1.0 + t * 0.4)), Color(UI.YELLOW, 1.0 - t), 18)
	if not result.is_empty():
		_draw_result(h, result, t)


static func _draw_result(h: CanvasItem, r: Dictionary, tt: float) -> void:
	h.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, 0.45))
	var rank := str(r["rank"])
	var ok := rank != "raté"
	var col := {"S": Color("#ffc93c"), "A": Color("#ff7b9c"), "B": Color("#7fd6ff")}.get(rank, Color("#9aa0b4")) as Color
	var pulse := 1.0 + 0.04 * sin(tt * 6.0)
	if ok:
		h.draw_circle(Vector2(640, 320), 120.0 * pulse, UI.WHITE)
		h.draw_circle(Vector2(640, 320), 106.0 * pulse, col)
		UI.text(h, Vector2(640, 322), rank, int(150 * pulse), UI.WHITE, 14)
		UI.ribbon(h, Vector2(640, 480), "Bravo l'équipe ! +%d pièces chacun" % int(r["coins"]), 34, col.darkened(0.1))
	else:
		UI.text(h, Vector2(640, 320), "RATÉ...", 110, Color("#c9cde0"), 14)
		UI.ribbon(h, Vector2(640, 470), "Pas de pièces cette fois !", 32, Color("#8a8fa8"))
