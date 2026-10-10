extends Node2D
## « Le Capitaine a dit ! » (Shy Guy Says, Mario Party / Superstars) : le capitaine, sur son bateau,
## lève le drapeau rouge ou blanc ; il faut lever le même. Les joueurs flottent dans des tonneaux
## attachés au bateau par une corde : mauvais drapeau (ou aucun) = le capitaine coupe la corde.
## Feintes : deux drapeaux levés puis un baissé, ou un drapeau levé puis échangé. De plus en plus vite.
## Comme dans Superstars : s'il reste au moins 2 joueurs assez longtemps, un minuteur de 30 s
## apparaît, et à zéro tous les survivants gagnent.
## L'hôte envoie les ordres ; chacun juge sa propre réponse (pas de pénalité pour le ping).

const RED := 0
const WHITE := 1
const TIMER_AT := 45.0
const TIMER_LEN := 30.0
const MAX_T := 95.0
const BOAT := Vector2(640, 280)

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

# ordre en cours (reçu de l'hôte)
var cmd := {}                   # id, kind, first, final, d, w, at, t0 (local)
var cap_flags := [false, false] # drapeaux levés par le capitaine (rouge, blanc)
var cap_anim := [0.0, 0.0]      # 0 baissé .. 1 levé (lissé)
var my_flag := -1
var judged := -1
var flags := {}                 # id -> drapeau levé (-1 aucun)
var flag_anim := {}             # id -> [rouge 0..1, blanc 0..1]
var out_at := {}                # id -> moment local de la coupure
var my_out := false
var timer_end := -1.0           # play_t local où le minuteur final se termine
var slash: Array = []
var bot_press_at := -1.0
var bot_choice := 0
var shake := 0.0
# hôte
var h_n := 0
var h_next := 1.2
var h_timer_sent := false
var h_end := false


func _ready() -> void:
	rng.seed = int(Net.mg_data.get("seed", 1))
	brng.randomize()
	for id in Net.mg_data.get("players", Net.players.keys()):
		if Net.players.has(id):
			ids.append(id)
	ids.sort()
	me_id = Net.my_id()
	playing = ids.has(me_id)
	for id in ids:
		flags[id] = -1
		flag_anim[id] = [0.0, 0.0]
		for pose in ["front", "jump", "hit"]:
			_tex["%d_%s" % [id, pose]] = UI.char_tex(Net.color_idx(id), pose)
	_tex["captain"] = load("res://assets/chars/vendeur/idle.png")
	for n in ["cloud1", "cloud2", "cloud3"]:
		_tex[n] = load("res://assets/deco/%s.png" % n)
	_tex["sword"] = load("res://assets/icons/sword.png")
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
	hud.draw.connect(_draw_hud)
	ui.add_child(hud)
	Net.mg_msg.connect(_on_mg_msg)
	Net.mg_state.connect(_on_mg_state)
	Net.mg_ending.connect(_on_ending)
	Net.mg_player_out.connect(_on_player_out)
	Net.mg_ready_changed.connect(func(r): ready_ids = r)
	Net.mg_go.connect(func(): go_received = true)
	Net.players_changed.connect(_on_players_changed)


func _on_ending() -> void:
	state = "over"
	t = 0.0
	Sfx.play("bell", -2.0, 0.0)


func _on_players_changed() -> void:
	for id in ids.duplicate():
		if not Net.players.has(id):
			ids.erase(id)


func _on_player_out(id: int, _how: String) -> void:
	if out_at.has(id):
		return
	out_at[id] = play_t
	if Net.autotest != "" and Net.is_host():
		print("[flags] coupé ", Net.name_of(id), " t=", snappedf(play_t, 0.1), " ordre ", h_n)
	slash.append({"p": _seat(id) + Vector2(0, -150), "t": 0.0})
	Sfx.play("whoosh", -2.0, 0.0)
	Sfx.play("fall", -4.0 if id == me_id else -10.0)
	if id == me_id:
		shake = 1.0


# ------------------------------------------------------------------ hôte : les ordres du capitaine
func _host_step(dt: float) -> void:
	if h_end:
		return
	var alive := 0
	for id in ids:
		if not out_at.has(id):
			alive += 1
	if not h_timer_sent and play_t > TIMER_AT and alive >= 2:
		h_timer_sent = true
		Net.mg_broadcast({"timer": TIMER_LEN})
	if h_timer_sent and timer_end >= 0.0 and play_t >= timer_end:
		h_end = true
		if Net.autotest != "":
			print("[flags] minuteur fini, survivants ", ids.size() - out_at.size())
		Net.report_time_up()
		return
	if play_t > MAX_T:
		h_end = true
		Net.report_time_up()
		return
	h_next -= dt
	if h_next > 0.0:
		return
	var n := h_n
	h_n += 1
	var final := rng.randi_range(0, 1)
	var kind := 0
	if n >= 2 and rng.randf() < minf(0.55, 0.25 + n * 0.02):
		kind = 1 if rng.randf() < 0.5 else 2
	var d := rng.randf_range(0.35, 0.65) if kind != 0 else 0.0
	var w := maxf(0.62, 1.3 - n * 0.035)
	var gap := maxf(0.55, 1.5 - n * 0.05)
	Net.mg_broadcast({"cmd": n, "kind": kind, "final": final, "d": d, "w": w, "at": play_t})
	h_next = d + w + 0.35 + gap


func _on_mg_msg(from_id: int, data: Dictionary) -> void:
	if Net.is_host() and data.has("flag"):
		Net.mg_broadcast({"pf": from_id, "f": int(data["flag"])})


func _on_mg_state(d: Dictionary) -> void:
	if d.has("cmd"):
		cmd = {"id": int(d["cmd"]), "kind": int(d["kind"]), "final": int(d["final"]), "d": float(d["d"]),
			"w": float(d["w"]), "at": float(d["at"]), "t0": play_t + 0.05}
		my_flag = -1
		for id in flags:
			flags[id] = -1
		if playing and not my_out:
			Net.mg_to_host({"flag": -1})
		# robot : bonne réponse de moins en moins souvent, plus ou moins vite
		var reveal := float(cmd["t0"]) + float(cmd["d"])
		var p_ok := clampf(0.97 - int(cmd["id"]) * 0.012, 0.6, 0.97)
		bot_choice = int(cmd["final"]) if brng.randf() < p_ok else 1 - int(cmd["final"])
		bot_press_at = reveal + brng.randf_range(0.18, 0.5) + (brng.randf_range(0.2, 0.6) if brng.randf() < 0.08 else 0.0)
	elif d.has("pf"):
		var id := int(d["pf"])
		if id != me_id and flags.has(id):
			flags[id] = int(d["f"])
	elif d.has("timer"):
		timer_end = play_t + float(d["timer"])
		Sfx.voice("hurry_up")


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
			if Net.is_host():
				_host_step(delta)
			_update_captain()
			_my_input()
			_judge()
	# animations des drapeaux
	for i in 2:
		cap_anim[i] = move_toward(cap_anim[i], 1.0 if cap_flags[i] else 0.0, delta * 9.0)
	for id in flags:
		var fa: Array = flag_anim[id]
		var f := int(flags[id])
		fa[0] = move_toward(float(fa[0]), 1.0 if f == RED else 0.0, delta * 10.0)
		fa[1] = move_toward(float(fa[1]), 1.0 if f == WHITE else 0.0, delta * 10.0)
	for s in slash:
		s["t"] = float(s["t"]) + delta
	slash = slash.filter(func(s): return float(s["t"]) < 0.6)
	shake = maxf(0.0, shake - delta * 3.0)
	view.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * 8.0
	view.queue_redraw()
	hud.queue_redraw()


func _update_captain() -> void:
	if cmd.is_empty():
		cap_flags = [false, false]
		return
	var k := play_t - float(cmd["t0"])
	var fin := int(cmd["final"])
	var other := 1 - fin
	var d := float(cmd["d"])
	var w := float(cmd["w"])
	var nf := [false, false]
	if k < 0.0:
		nf = [false, false]
	elif int(cmd["kind"]) == 0:
		nf[fin] = true
	elif int(cmd["kind"]) == 1:
		# les deux levés, puis l'un se baisse
		nf = [true, true] if k < d else [false, false]
		if k >= d:
			nf[fin] = true
	else:
		# un drapeau levé... puis échangé
		if k < d:
			nf[other] = true
		else:
			nf[fin] = true
	if k > d + w + 0.35:
		nf = [false, false]
	if nf != cap_flags:
		cap_flags = nf
		Sfx.play("whoosh", -12.0, 0.1)


func _my_input() -> void:
	if not playing or my_out or cmd.is_empty():
		return
	var f := -1
	if Net.autotest != "":
		if bot_press_at > 0.0 and play_t >= bot_press_at:
			f = bot_choice
			bot_press_at = -1.0
	elif Input.is_action_just_pressed("left"):
		f = RED
	elif Input.is_action_just_pressed("right"):
		f = WHITE
	if f >= 0 and f != my_flag:
		my_flag = f
		flags[me_id] = f
		Net.mg_to_host({"flag": f})
		Sfx.play("ui_move", -6.0, 0.0)


## Fin de la fenêtre de réponse : j'ai le bon drapeau, ou la corde est coupée.
func _judge() -> void:
	if not playing or my_out or cmd.is_empty() or judged == int(cmd["id"]):
		return
	var end := float(cmd["t0"]) + float(cmd["d"]) + float(cmd["w"])
	if play_t < end:
		return
	judged = int(cmd["id"])
	if my_flag == int(cmd["final"]):
		Sfx.play("ui_ok", -10.0, 0.0)
		return
	my_out = true
	Net.report_out(float(cmd["at"]), "coupé")


# ------------------------------------------------------------------ dessin
func _seat(id: int) -> Vector2:
	var i := ids.find(id)
	var n := maxi(1, ids.size())
	var u := (float(i) + 0.5) / float(n)
	var a := lerpf(PI * 0.86, PI * 0.14, u)
	var p := Vector2(640, 330) + Vector2(cos(a) * 540.0, sin(a) * 270.0)
	if out_at.has(id):
		var k := play_t - float(out_at[id])
		p += Vector2((p.x - 640.0) * 0.4 * k, 70.0 * k)
	return p + Vector2(0, sin(t * 2.4 + i * 1.3) * 5.0)


func _draw_view() -> void:
	var c := view
	# ciel et mer
	c.draw_rect(Rect2(-20, -20, 1320, 760), Color("#9fdcf7"))
	c.draw_rect(Rect2(-20, -20, 1320, 180), Color("#bfe9fb"))
	for k in 4:
		var tx: Texture2D = _tex["cloud%d" % (k % 3 + 1)]
		var x := fmod(80.0 + k * 360.0 + t * 12.0, 1500.0) - 150.0
		c.draw_texture(tx, Vector2(x, 20 + (k % 2) * 40), Color(1, 1, 1, 0.9))
	c.draw_rect(Rect2(-20, 230, 1320, 530), Color("#4fb4e6"))
	c.draw_rect(Rect2(-20, 230, 1320, 14), Color("#7fd0f2"))
	for k in 40:
		var x2 := fmod(k * 97.0 + t * (14.0 + (k % 3) * 6.0), 1360.0) - 40.0
		var y2 := 262.0 + float((k * 53) % 460)
		c.draw_line(Vector2(x2, y2), Vector2(x2 + 26, y2), Color(1, 1, 1, 0.4), 3.0)
	# cordes (dessinées sous le bateau)
	for id in ids:
		if out_at.has(id) and play_t - float(out_at[id]) > 0.15:
			continue
		var sp := _seat(id) + Vector2(0, -40)
		var anchor := BOAT + Vector2(clampf((sp.x - 640.0) * 0.35, -170.0, 170.0), 60)
		var mid := (sp + anchor) / 2.0 + Vector2(0, 26)
		c.draw_polyline(_bezier(anchor, mid, sp), Color("#a87a45"), 4.0, true)
	_draw_boat(c)
	# tonneaux (de l'arrière vers l'avant)
	var order := ids.duplicate()
	order.sort_custom(func(a, b): return _seat(a).y < _seat(b).y)
	for id in order:
		_draw_barrel(c, id)
	for s in slash:
		var k2 := float(s["t"]) / 0.6
		var p: Vector2 = s["p"]
		c.draw_line(p + Vector2(-40, -30) + Vector2(80, 60) * k2 * 0.6, p + Vector2(-40, -30) + Vector2(80, 60) * minf(1.0, k2 * 1.6), Color(1, 1, 1, 1.0 - k2), 6.0)
		UI.text(c, p + Vector2(0, -40 - k2 * 30.0), "COUPÉ !", 30, Color(UI.RED, 1.0 - k2 * k2), 7)


func _bezier(a: Vector2, m: Vector2, b: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 13:
		var u := k / 12.0
		pts.append(a.lerp(m, u).lerp(m.lerp(b, u), u))
	return pts


func _draw_boat(c: CanvasItem) -> void:
	var bob := sin(t * 1.6) * 4.0
	var b := BOAT + Vector2(0, bob)
	# voile et mât
	var mb := b + Vector2(170, 0)
	c.draw_rect(Rect2(mb + Vector2(-6, -210), Vector2(12, 210)), Color("#8a5a32"))
	var sail := PackedVector2Array([mb + Vector2(10, -200), mb + Vector2(10, -60), mb + Vector2(120, -70)])
	c.draw_colored_polygon(sail, UI.WHITE)
	c.draw_colored_polygon(PackedVector2Array([mb + Vector2(10, -150), mb + Vector2(10, -115), mb + Vector2(80, -120)]), Color("#ff7b9c"))
	c.draw_colored_polygon(PackedVector2Array([mb + Vector2(6, -208), mb + Vector2(6, -182), mb + Vector2(48, -195)]), Color("#ffd23f"))
	# coque
	var hull := PackedVector2Array([b + Vector2(-230, 0), b + Vector2(230, 0), b + Vector2(180, 74), b + Vector2(-180, 74)])
	c.draw_colored_polygon(hull, Color("#c9874b"))
	c.draw_colored_polygon(PackedVector2Array([b + Vector2(-230, 0), b + Vector2(230, 0), b + Vector2(220, 16), b + Vector2(-220, 16)]), Color("#e4a564"))
	for k in 5:
		c.draw_circle(b + Vector2(-140 + k * 70, 42), 10.0, Color("#8a5a32"))
		c.draw_circle(b + Vector2(-140 + k * 70, 42), 6.0, Color("#bfe9fb"))
	# le capitaine
	var cp := b + Vector2(-20, 6)
	var cs := 0.82
	c.draw_set_transform(cp, 0.0, Vector2(cs, cs))
	c.draw_texture(_tex["captain"], Vector2(-128, -256))
	c.draw_set_transform(Vector2.ZERO)
	# chapeau de capitaine
	var hp := cp + Vector2(0, -150 * cs - 8)
	c.draw_colored_polygon(PackedVector2Array([hp + Vector2(-62, 14), hp + Vector2(62, 14), hp + Vector2(44, -22), hp + Vector2(0, -36), hp + Vector2(-44, -22)]), Color("#2f3b66"))
	c.draw_rect(Rect2(hp + Vector2(-56, 4), Vector2(112, 10)), Color("#ffd23f"))
	c.draw_circle(hp + Vector2(0, -12), 9.0, UI.WHITE)
	# ses deux drapeaux : rouge à gauche, blanc à droite
	for i in 2:
		var side := -1.0 if i == RED else 1.0
		var shoulder := cp + Vector2(side * 50.0, -100)
		var a: float = lerpf(PI * 0.5 + side * -0.9, -PI * 0.5 + side * 0.12, float(cap_anim[i]))
		var tip := shoulder + Vector2(cos(a), sin(a)) * 140.0
		_flag(c, shoulder, tip, Color("#f04650") if i == RED else UI.WHITE, side, 1.25)


func _flag(c: CanvasItem, from: Vector2, tip: Vector2, col: Color, side: float, k: float) -> void:
	c.draw_line(from, tip, Color("#6b4a2b"), 6.0 * k)
	c.draw_circle(tip, 5.0 * k, UI.YELLOW)
	var dirv := (tip - from).normalized()
	var perp := Vector2(-dirv.y, dirv.x) * side * -1.0
	var wave := sin(t * 10.0) * 6.0 * k
	var p1 := tip - dirv * 6.0 * k
	var p2 := tip - dirv * 52.0 * k
	var pts := PackedVector2Array([p1, p1 + perp * 62.0 * k + Vector2(0, wave), p2 + perp * 62.0 * k + Vector2(0, -wave), p2])
	c.draw_colored_polygon(pts, col)
	c.draw_polyline(PackedVector2Array([p1, p1 + perp * 62.0 * k + Vector2(0, wave), p2 + perp * 62.0 * k + Vector2(0, -wave), p2, p1]), Color(0.2, 0.15, 0.3, 0.35), 2.5 * k)


func _draw_barrel(c: CanvasItem, id: int) -> void:
	var p := _seat(id)
	var gone := out_at.has(id)
	var alpha := 1.0
	if gone:
		alpha = clampf(1.0 - (play_t - float(out_at[id]) - 1.2) / 0.8, 0.0, 1.0)
		if alpha <= 0.0:
			return
	var col := Color(1, 1, 1, alpha)
	# reflet dans l'eau
	c.draw_set_transform(p + Vector2(0, 16), 0.0, Vector2(1.0, 0.3))
	c.draw_circle(Vector2.ZERO, 58.0, Color(0, 0.2, 0.4, 0.18 * alpha))
	c.draw_set_transform(Vector2.ZERO)
	# perso dans le tonneau
	var pose := "hit" if gone else ("jump" if int(flags[id]) >= 0 else "front")
	var tx: Texture2D = _tex["%d_%s" % [id, pose]]
	var s := 0.5
	c.draw_set_transform(p + Vector2(0, -30), sin(t * 2.0 + id) * 0.04, Vector2(s, s))
	c.draw_texture(tx, Vector2(-128, -256), col)
	c.draw_set_transform(Vector2.ZERO)
	# ses petits drapeaux
	var fa: Array = flag_anim[id]
	for i in 2:
		var side := -1.0 if i == RED else 1.0
		var sh := p + Vector2(side * 30.0, -70)
		var a: float = lerpf(PI * 0.5 + side * -0.5, -PI * 0.5 + side * 0.15, float(fa[i]))
		var tip := sh + Vector2(cos(a), sin(a)) * 64.0
		_flag(c, sh, tip, (Color("#f04650") if i == RED else UI.WHITE) * col, side, 0.55)
	# le tonneau
	var br := Rect2(p + Vector2(-50, -40), Vector2(100, 70))
	c.draw_style_box(UI.box(Color("#b9773e") * col, Color("#7a4a24") * col, 4, 18), br)
	for k in 3:
		c.draw_rect(Rect2(br.position + Vector2(0, 12 + k * 22), Vector2(100, 6)), Color("#7a4a24") * col)
	c.draw_rect(Rect2(br.position + Vector2(10, 4), Vector2(16, br.size.y - 8)), Color(1, 1, 1, 0.15 * alpha))
	var nm := "TOI" if id == me_id else Net.name_of(id)
	UI.text(c, p + Vector2(0, 52), nm, 18 if id == me_id else 15, (UI.YELLOW if id == me_id else Net.color_of(id)) * col, 5)


# ------------------------------------------------------------------ HUD
func _draw_hud() -> void:
	var h := hud
	var St := preload("res://minigames/stage.gd")
	if state == "intro":
		St.draw_intro(h, "Le Capitaine a dit !", [
			"Le capitaine lève le drapeau rouge ou le drapeau blanc :",
			"lève vite le même ! Mauvais drapeau ou trop lent = corde coupée.",
			"Attention aux feintes : deux drapeaux levés, ou un drapeau qu'il change...",
			"Il va de plus en plus vite ! Le dernier attaché gagne.",
			"S'il reste du monde à la fin du minuteur, tous les survivants gagnent."],
			"Drapeau rouge : Q / ←   ·   Drapeau blanc : D / →")
		St.draw_ready_row(h, my_ready, ready_ids, ids, t, not playing)
		if str(Net.mg_data.get("mode", "")) == "duel":
			St.draw_duel_banner(h)
		return
	if timer_end >= 0.0 and state == "play":
		var left := maxi(0, ceili(timer_end - play_t))
		var tr := Rect2(Vector2(24, 18), Vector2(120, 52))
		UI.panel(h, tr, UI.WHITE, Color("#ffd0d0"), 18, 4)
		UI.text(h, UI.face_center(tr), "%d s" % left, 30, UI.RED, 0)
	if playing and not my_out and state == "play":
		# rappel des touches, le drapeau levé s'allume
		for i in 2:
			var on := my_flag == i
			var r := Rect2(Vector2(24 if i == RED else 1280 - 90 - 150, 650), Vector2(150, 54))
			UI.panel(h, r, (Color("#f04650") if i == RED else Color("#f4f7ff")) if on else Color(1, 1, 1, 0.6), UI.WHITE if i == RED else Color("#c9cde0"), 26, 5)
			UI.text(h, UI.face_center(r), "← ROUGE" if i == RED else "BLANC →", 22, UI.WHITE if (on and i == RED) else (UI.RED if i == RED else UI.DARK), 0)
	if playing and my_out and state == "play":
		var msg := "Corde coupée ! Tu regardes la fin..."
		var mw := UI.text_width(msg, 24) + 50.0
		UI.panel(h, Rect2(Vector2(640 - mw / 2.0, 652), Vector2(mw, 48)), UI.WHITE, Color("#ffd0d0"), 20, 4)
		UI.text(h, Vector2(640, 676), msg, 24, UI.RED, 0)
	if state == "count":
		UI.text(h, Vector2(640, 400), str(3 - int(t)), int(110 * (1.0 + (1.0 - fmod(t, 1.0)) * 0.3)), UI.WHITE, 16)
	elif state == "play" and t < 1.0:
		UI.text(h, Vector2(640, 400), "GO !", int(120 * (1.0 + t * 0.4)), Color(UI.YELLOW, 1.0 - t), 18)
	if state == "over":
		h.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, minf(0.4, t)))
		UI.text(h, Vector2(640, 360), "TERMINÉ !", 96, UI.YELLOW, 16)
