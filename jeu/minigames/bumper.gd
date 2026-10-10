extends Node2D
## « Boules-tamponneuses ! » (Bumper Balls, Mario Party) : chacun roule sur une grosse boule
## dans une arène ronde au-dessus de l'eau. On se rentre dedans pour éjecter les autres.
## L'arène rétrécit à la fin. Le dernier dessus gagne.

const R0 := 330.0          # rayon de l'arène (vue de dessus)
const R_MIN := 175.0
const BALL := 34.0
const ACC := 1050.0
const VMAX := 340.0
const FRICTION := 1.5
const CENTER := Vector2(640, 420)
const SQ := 0.6            # écrasement vertical de la vue (perspective)
const MAX_T := 75.0
const DASH_CD := 2.0

var ids: Array = []
var balls: Dictionary = {}       # id -> {p, v, st, snaps, roll, fall}
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
var out_ids := {}
var my_out := false
var my_out_t := 0.0
var rng := RandomNumberGenerator.new()
var brng := RandomNumberGenerator.new()

var pos := Vector2.ZERO
var vel := Vector2.ZERO
var falling := -1.0
var dash_cd := 0.0
var bump_cd := {}
var send_acc := 0.0
var shake := 0.0
var bot_acc := 0.0
var bot_dir := Vector2.ZERO
var pops: Array = []
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
		var a := TAU * float(i) / float(ids.size()) - PI / 2.0
		var p := Vector2(cos(a), sin(a)) * R0 * 0.62
		balls[id] = {"p": p, "v": Vector2.ZERO, "st": 0, "snaps": [], "roll": 0.0, "fall": -1.0}
		_tex["%d" % id] = UI.char_tex(Net.color_idx(id), "idle")
		_tex["%d_hit" % id] = UI.char_tex(Net.color_idx(id), "hit")
		if id == me_id:
			pos = p
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
	Net.mg_ending.connect(_on_ending)
	Net.mg_ready_changed.connect(func(r): ready_ids = r)
	Net.mg_go.connect(func(): go_received = true)
	Net.mg_player_out.connect(_on_player_out)
	Net.players_changed.connect(_on_players_changed)


func _radius() -> float:
	if play_t < 25.0:
		return R0
	return maxf(R_MIN, R0 - (play_t - 25.0) * 4.2)


func _on_ending() -> void:
	state = "over"
	t = 0.0
	Sfx.play("bell", -2.0, 0.0)


func _on_players_changed() -> void:
	for id in balls.keys():
		if not Net.players.has(id):
			balls.erase(id)
			ids.erase(id)


func _on_player_out(id: int, _how: String) -> void:
	out_ids[id] = true
	if id != me_id and balls.has(id):
		Sfx.play("fall", -6.0)
		pops.append({"p": balls[id]["p"], "txt": "PLOUF !", "t": 0.0, "c": Net.color_of(id)})


func _on_remote_state(id: int, p: Vector2, v: Vector2, st: int) -> void:
	if not balls.has(id) or id == me_id:
		return
	var snaps: Array = balls[id]["snaps"]
	snaps.append([Time.get_ticks_msec() / 1000.0, p, v, st])
	if snaps.size() > 12:
		snaps.pop_front()


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
			play_t += delta
			if playing and not my_out:
				_step(delta)
			if Net.is_host() and play_t > MAX_T:
				Net.report_time_up()
	_update_remotes()
	for id in balls:
		var b: Dictionary = balls[id]
		b["roll"] = float(b["roll"]) + (b["v"] as Vector2).length() * delta / BALL
	for p in pops:
		p["t"] = float(p["t"]) + delta
	pops = pops.filter(func(p): return float(p["t"]) < 1.0)
	shake = maxf(0.0, shake - delta * 3.0)
	view.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * 10.0
	view.queue_redraw()
	hud.queue_redraw()


func _input_dir() -> Vector2:
	if Net.autotest != "":
		return _bot_dir()
	var d := Vector2(Input.get_axis("left", "right"), Input.get_axis("up", "down"))
	return d.limit_length(1.0)


func _step(dt: float) -> void:
	dash_cd = maxf(0.0, dash_cd - dt)
	for k in bump_cd.keys():
		bump_cd[k] = float(bump_cd[k]) - dt
		if float(bump_cd[k]) <= 0.0:
			bump_cd.erase(k)
	if falling >= 0.0:
		falling += dt
		pos += vel * dt
		if falling > 0.7 and not my_out:
			my_out = true
			my_out_t = play_t
			Net.report_out(play_t, "tombé")
			Sfx.play("fall", 0.0)
			pops.append({"p": pos, "txt": "PLOUF !", "t": 0.0, "c": Net.color_of(me_id)})
		_send(dt)
		return
	var d := _input_dir()
	vel += d * ACC * dt
	vel -= vel * FRICTION * dt
	if vel.length() > VMAX and dash_cd < DASH_CD - 0.35:
		vel = vel.limit_length(VMAX)
	# coup de boost
	var want_dash := Input.is_action_just_pressed("push") if Net.autotest == "" else (brng.randf() < 0.01)
	if want_dash and dash_cd <= 0.0 and d.length() > 0.2:
		vel = d.normalized() * 620.0
		dash_cd = DASH_CD
		Sfx.play("whoosh", -2.0)
	# chocs avec les autres boules (chacun calcule son propre rebond)
	for id in balls:
		if id == me_id or out_ids.has(id):
			continue
		var o: Dictionary = balls[id]
		if float(o["fall"]) >= 0.0:
			continue
		var op: Vector2 = o["p"]
		var dv := pos - op
		var dist := dv.length()
		if dist < BALL * 2.0 and dist > 0.01:
			var n := dv / dist
			pos += n * (BALL * 2.0 - dist) * 0.5
			var rel := vel - (o["v"] as Vector2)
			var along := rel.dot(n)
			if along < 0.0:
				vel -= n * along * 1.15
				vel += n * 60.0
				if not bump_cd.has(id):
					bump_cd[id] = 0.25
					var force := absf(along)
					Sfx.play("bump", clampf(-14.0 + force * 0.03, -14.0, 0.0), 0.15)
					shake = minf(1.0, shake + force / 900.0)
	pos += vel * dt
	# hors de l'arène ?
	if pos.length() > _radius() + BALL * 0.3:
		falling = 0.0
		Sfx.play("whoosh", -4.0)
	_send(dt)


func _send(dt: float) -> void:
	var b: Dictionary = balls[me_id]
	b["p"] = pos
	b["v"] = vel
	b["fall"] = falling
	b["st"] = 1 if falling >= 0.0 else 0
	send_acc += dt
	if send_acc >= 1.0 / 30.0:
		send_acc = 0.0
		Net.send_state(pos, vel, int(b["st"]))


func _bot_dir() -> Vector2:
	bot_acc -= get_process_delta_time()
	if bot_acc <= 0.0:
		bot_acc = brng.randf_range(0.25, 0.6)
		var target := Vector2.ZERO
		var best := 1e9
		for id in balls:
			if id == me_id or out_ids.has(id):
				continue
			var dd := (balls[id]["p"] as Vector2).distance_to(pos)
			if dd < best:
				best = dd
				target = balls[id]["p"]
		bot_dir = (target - pos).normalized() if best < 1e8 else -pos.normalized()
		if brng.randf() < 0.25:
			bot_dir = Vector2.from_angle(brng.randf() * TAU)
	# ne pas sortir tout seul
	if pos.length() > _radius() - 70.0:
		return (-pos.normalized() + bot_dir * 0.3).normalized()
	return bot_dir


func _update_remotes() -> void:
	var rt := Time.get_ticks_msec() / 1000.0 - 0.08
	for id in balls:
		if id == me_id:
			continue
		var b: Dictionary = balls[id]
		var snaps: Array = b["snaps"]
		if snaps.is_empty():
			continue
		var p: Vector2 = snaps[-1][1]
		var v: Vector2 = snaps[-1][2]
		var st := int(snaps[-1][3])
		if rt >= float(snaps[-1][0]):
			p = p + v * minf(rt - float(snaps[-1][0]), 0.12)
		else:
			for i in range(snaps.size() - 1, 0, -1):
				var a: Array = snaps[i - 1]
				var c: Array = snaps[i]
				if float(a[0]) <= rt:
					var u := clampf((rt - float(a[0])) / maxf(0.001, float(c[0]) - float(a[0])), 0.0, 1.0)
					p = (a[1] as Vector2).lerp(c[1], u)
					v = (a[2] as Vector2).lerp(c[2], u)
					st = int(c[3])
					break
		b["p"] = p
		b["v"] = v
		if (st & 1) != 0:
			b["fall"] = maxf(0.0, float(b["fall"])) + get_process_delta_time()
		else:
			b["fall"] = -1.0


# ------------------------------------------------------------------ dessin
func _scr(p: Vector2) -> Vector2:
	return CENTER + Vector2(p.x, p.y * SQ)


func _draw_view() -> void:
	var c := view
	# ciel + mer
	c.draw_rect(Rect2(-20, -20, 1320, 760), Color("#bfeaf5"))
	c.draw_rect(Rect2(-20, 300, 1320, 460), Color("#6fcdee"))
	for k in 30:
		var x := fmod(k * 83.0 + t * 20.0, 1360.0) - 40.0
		var y := 330.0 + float((k * 37) % 380)
		c.draw_line(Vector2(x, y), Vector2(x + 30, y), Color(1, 1, 1, 0.45), 3.0)
	# arène : pilier + plateau
	var r := _radius()
	var pil := PackedVector2Array()
	for k in 33:
		var a := PI * k / 32.0
		pil.append(CENTER + Vector2(cos(a) * r, sin(a) * r * SQ))
	for k in 33:
		var a2 := PI - PI * k / 32.0
		pil.append(CENTER + Vector2(cos(a2) * r, sin(a2) * r * SQ + 90.0))
	c.draw_colored_polygon(pil, Color("#d9a35f"))
	_ellipse(c, CENTER, r, r * SQ, Color("#f4d08a"))
	_ellipse(c, CENTER, r - 18.0, (r - 18.0) * SQ, Color("#ffe3a8"))
	# motif en étoile au centre (comme un vrai ring Mario Party)
	for k in 8:
		var a3 := TAU * k / 8.0 + 0.2
		var q := PackedVector2Array([CENTER, CENTER + Vector2(cos(a3 - 0.18), sin(a3 - 0.18) * SQ) * (r - 30.0), CENTER + Vector2(cos(a3 + 0.18), sin(a3 + 0.18) * SQ) * (r - 30.0)])
		c.draw_colored_polygon(q, Color("#ffd27f") if k % 2 == 0 else Color("#ffeac0"))
	_ellipse(c, CENTER, 46.0, 46.0 * SQ, Color("#ff9a5a"))
	# bord qui clignote quand ça rétrécit
	if play_t > 22.0 and play_t < 25.0 and int(t * 6.0) % 2 == 0:
		c.draw_arc(CENTER, r, 0, TAU, 64, Color("#ff6b6b"), 6.0)
	# boules (de l'arrière vers l'avant)
	var order := balls.keys()
	order.sort_custom(func(a, b): return float(balls[a]["p"].y) < float(balls[b]["p"].y))
	for id in order:
		if out_ids.has(id) and float(balls[id]["fall"]) < 0.0:
			continue
		_ball(c, id)
	for p in pops:
		var k2: float = p["t"]
		UI.text(c, _scr(p["p"]) + Vector2(0, -60 - k2 * 40.0), p["txt"], 30, Color(p["c"], 1.0 - k2 * k2), 7)


func _ellipse(c: CanvasItem, ctr: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 48:
		var a := TAU * k / 48.0
		pts.append(ctr + Vector2(cos(a) * rx, sin(a) * ry))
	c.draw_colored_polygon(pts, col)


func _ball(c: CanvasItem, id: int) -> void:
	var b: Dictionary = balls[id]
	var fall := float(b["fall"])
	if fall > 0.75:
		return
	var p := _scr(b["p"])
	var sc := 1.0
	var drop := 0.0
	if fall >= 0.0:
		drop = fall * fall * 600.0
		sc = 1.0 - fall * 0.6
	var col := Net.color_of(id)
	if fall < 0.0:
		_ellipse(c, p + Vector2(0, 4), BALL * 1.05, BALL * 0.42, Color(0, 0, 0, 0.18))
	var bc := p + Vector2(0, -BALL + drop) * sc
	# boule rayée qui tourne
	c.draw_circle(bc, BALL * sc, col)
	var roll := float(b["roll"])
	var v: Vector2 = b["v"]
	var dirx := signf(v.x) if absf(v.x) > 5.0 else 1.0
	for k in 3:
		var off := fmod(roll * 12.0 * dirx + k * 22.0, 66.0) - 33.0
		if absf(off) < BALL * 0.95:
			var hh := sqrt(BALL * BALL - off * off) * sc
			c.draw_line(bc + Vector2(off * sc, -hh), bc + Vector2(off * sc, hh), Color(1, 1, 1, 0.75), 7.0 * sc)
	c.draw_circle(bc + Vector2(-10, -12) * sc, 8.0 * sc, Color(1, 1, 1, 0.55))
	# le perso assis dessus
	var tx: Texture2D = _tex["%d_hit" % id] if fall >= 0.0 else _tex["%d" % id]
	var s2 := 0.27 * sc
	c.draw_set_transform(bc + Vector2(0, -BALL * sc + 8.0 + sin(t * 9.0 + id) * 1.5), (v.x / VMAX) * 0.15, Vector2(s2, s2))
	c.draw_texture(tx, Vector2(-128, -256))
	c.draw_set_transform(Vector2.ZERO)
	if fall < 0.0:
		UI.text(c, bc + Vector2(0, -BALL - 64), "TOI" if id == me_id and playing else Net.name_of(id), 18 if id == me_id else 15, UI.YELLOW if id == me_id else col, 5)


# ------------------------------------------------------------------ HUD
func _draw_hud() -> void:
	var h := hud
	if state == "intro":
		preload("res://minigames/stage.gd").draw_intro(h, "Boules-tamponneuses !", [
			"Chacun roule sur une grosse boule au milieu de l'eau.",
			"Fonce dans les autres pour les éjecter de l'arène !",
			"Attention : à la fin, l'arène rétrécit...",
			"Le dernier encore dessus gagne !"],
			"Bouger : flèches ou Z Q S D   ·   Boost : Maj / X / clic")
		preload("res://minigames/stage.gd").draw_ready_row(h, my_ready, ready_ids, balls.keys(), t, not playing)
		if str(Net.mg_data.get("mode", "")) == "duel":
			preload("res://minigames/stage.gd").draw_duel_banner(h)
		return
	preload("res://minigames/stage.gd").draw_heads(h, ids, out_ids)
	var left := maxi(0, ceili(MAX_T - play_t))
	var tr := Rect2(Vector2(24, 18), Vector2(120, 52))
	UI.panel(h, tr, UI.WHITE, Color("#e4e2f2"), 18, 4)
	UI.text(h, UI.face_center(tr), "%d s" % left, 30, UI.RED if left <= 10 else UI.DARK, 0)
	if playing and not my_out and state == "play":
		# jauge du boost
		var br := Rect2(Vector2(1280 - 190, 24), Vector2(166, 40))
		UI.panel(h, br, Color("#8e6cf0"), UI.WHITE, 16, 4)
		var k := 1.0 - dash_cd / DASH_CD
		h.draw_style_box(UI.box(Color(1, 1, 1, 0.35), Color(0, 0, 0, 0), 0, 8), Rect2(br.position + Vector2(10, 26), Vector2(146, 8)))
		h.draw_style_box(UI.box(UI.YELLOW, Color(0, 0, 0, 0), 0, 8), Rect2(br.position + Vector2(10, 26), Vector2(146 * k, 8)))
		UI.text(h, br.position + Vector2(83, 14), "BOOST" if k >= 1.0 else "recharge", 16, UI.WHITE, 4)
	if play_t > 22.0 and play_t < 27.0 and state == "play":
		UI.ribbon(h, Vector2(640, 130), "L'arène rétrécit !", 28, Color("#ff7b6b"))
	if state == "count":
		UI.text(h, Vector2(640, 330), str(3 - int(t)), int(110 * (1.0 + (1.0 - fmod(t, 1.0)) * 0.3)), UI.WHITE, 16)
	elif state == "play" and t < 1.0:
		UI.text(h, Vector2(640, 330), "GO !", int(120 * (1.0 + t * 0.4)), Color(UI.YELLOW, 1.0 - t), 18)
	if my_out and state == "play":
		var msg := "Éliminé ! Tu as tenu %.1f s" % my_out_t
		var mw := UI.text_width(msg, 26) + 50.0
		UI.panel(h, Rect2(Vector2(640 - mw / 2.0, 640), Vector2(mw, 50)), UI.WHITE, Color("#ffd0d0"), 20, 4)
		UI.text(h, Vector2(640, 665), msg, 26, UI.RED, 0)
	if state == "over":
		h.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, minf(0.4, t)))
		UI.text(h, Vector2(640, 360), "TERMINÉ !", 96, UI.YELLOW, 16)
