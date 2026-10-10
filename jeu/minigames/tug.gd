extends Node2D
## « Tir à la corde ! » (Tug o' War, Mario Party) : deux équipes tirent sur une corde
## au-dessus d'une mare de boue. On martèle ESPACE ; l'équipe tirée dans la boue perd.
## Équipes tirées au sort (même tirage chez tout le monde). Nombre impair : un joueur
## tiré au sort est l'arbitre — il regarde et gagne d'office.

const MAX_T := 30.0
const WIN_X := 1.0
const TAP_CAP := 11.0      # au-delà, taper plus vite ne sert à rien

var ids: Array = []
var team_l: Array = []
var team_r: Array = []
var referee := 0
var me_id := 0
var my_team := 0           # -1 gauche, 1 droite, 0 aucun
var hud: Control
var view: Node2D
var state := "intro"
var t := 0.0
var play_t := 0.0
var my_ready := false
var go_received := false
var ready_ids: Array = []
var brng := RandomNumberGenerator.new()

var rope := 0.0            # -1 : la gauche gagne ; +1 : la droite gagne
var rope_shown := 0.0
var winner := 0            # -1 / 1 quand c'est fini
var my_taps := 0
var my_rate := 0.0         # mes tapes / seconde (lissé, pour l'animation)
var send_acc := 0.0
var tap_marks: Array = []
var bot_acc := 0.0
var bot_rate := 8.0
var rates := {}            # id -> cadence (envoyée par l'hôte, pour l'animation)

# hôte
var host_taps := {}        # id -> tapes reçues depuis la dernière mise à jour
var host_rates := {}
var host_acc := 0.0
var ended := false
var _tex := {}


func _ready() -> void:
	brng.randomize()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Net.mg_data.get("seed", 1)) * 7 + 3
	for id in Net.mg_data.get("players", Net.players.keys()):
		if Net.players.has(id):
			ids.append(id)
	ids.sort()
	var pool := ids.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	if pool.size() % 2 == 1 and pool.size() > 1:
		referee = pool.pop_front()
	for i in pool.size():
		(team_l if i % 2 == 0 else team_r).append(pool[i])
	me_id = Net.my_id()
	my_team = -1 if team_l.has(me_id) else (1 if team_r.has(me_id) else 0)
	bot_rate = brng.randf_range(6.5, 10.5)
	for id in ids:
		for pose in ["walk_a", "walk_b", "idle", "hit", "jump"]:
			_tex["%d_%s" % [id, pose]] = UI.char_tex(Net.color_idx(id), pose)
	for n in ["tree", "treePine", "bush1"]:
		_tex[n] = load("res://assets/deco/%s.png" % n)
	_tex["flag"] = load("res://assets/tiles/flag_red_a.png")
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
	Net.mg_msg.connect(_on_mg_msg)
	Net.mg_state.connect(_on_mg_state)
	Net.mg_ending.connect(_on_ending)
	Net.mg_ready_changed.connect(func(r): ready_ids = r)
	Net.mg_go.connect(func(): go_received = true)


func _on_ending() -> void:
	state = "over"
	t = 0.0
	Sfx.play("bell", -2.0, 0.0)


# ------------------------------------------------------------------ hôte
func _on_mg_msg(from_id: int, d: Dictionary) -> void:
	if d.has("taps"):
		host_taps[from_id] = int(host_taps.get(from_id, 0)) + int(d["taps"])


func _team_power(team: Array) -> float:
	var sum := 0.0
	var n := 0
	for id in team:
		if Net.players.has(id):
			sum += minf(float(host_rates.get(id, 0.0)), TAP_CAP)
			n += 1
	return sum / maxf(1.0, float(n))


func _host_step(dt: float) -> void:
	if ended:
		return
	host_acc += dt
	if host_acc >= 0.1:
		# cadence de chacun (tapes/s), lissée
		for id in ids:
			var r := float(host_taps.get(id, 0)) / host_acc
			host_rates[id] = lerpf(float(host_rates.get(id, 0.0)), r, 0.35)
		host_taps.clear()
		host_acc = 0.0
		var diff := _team_power(team_r) - _team_power(team_l)
		rope = clampf(rope + diff * 0.0055, -1.2, 1.2)
		if absf(rope) >= WIN_X:
			winner = int(signf(rope))
			_finish()
		elif play_t >= MAX_T:
			winner = int(signf(rope)) if absf(rope) > 0.02 else 0
			_finish()
		Net.mg_broadcast({"rope": rope, "rates": host_rates, "win": winner})


func _finish() -> void:
	ended = true
	Net.mg_broadcast({"rope": rope, "rates": host_rates, "win": winner})
	var sc := {}
	for id in ids:
		var side := -1 if team_l.has(id) else (1 if team_r.has(id) else 0)
		if id == referee:
			sc[id] = [1.0, "Arbitre : gagné d'office !"]
		elif winner == 0:
			sc[id] = [0.5, "Égalité !"]
		elif side == winner:
			sc[id] = [1.0, "Équipe gagnante !"]
		else:
			sc[id] = [0.0, "Dans la boue..."]
	Net.mg_end_with_scores(sc)


func _on_mg_state(d: Dictionary) -> void:
	if d.has("rope"):
		rope = float(d["rope"])
		rates = d["rates"]
		var w := int(d.get("win", 0))
		if w != 0 and winner == 0:
			Sfx.play("fall", 0.0)
			Sfx.play("jingle_good" if w == my_team or me_id == referee else ("jingle_bad" if my_team != 0 else "jingle_good"), -2.0, 0.0)
		winner = w


# ------------------------------------------------------------------ boucle
func _process(delta: float) -> void:
	t += delta
	match state:
		"intro":
			if not my_ready and t > 0.6:
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
			if my_team != 0 and winner == 0:
				var n := 0
				if Net.autotest != "":
					bot_acc += delta * bot_rate
					while bot_acc >= 1.0:
						bot_acc -= 1.0
						n += 1
				else:
					for a in ["jump", "push", "left", "right", "up", "down"]:
						if Input.is_action_just_pressed(a):
							n += 1
				if n > 0:
					my_taps += n
					tap_marks.append({"t": 0.0, "x": randf_range(-40, 40)})
					Sfx.play("step1" if randf() < 0.5 else "step2", -14.0, 0.2)
				my_rate = lerpf(my_rate, float(n) / maxf(delta, 0.001), 1.0 - exp(-delta * 3.0))
				send_acc += delta
				if send_acc >= 0.1:
					send_acc = 0.0
					if my_taps > 0:
						Net.mg_to_host({"taps": my_taps})
						my_taps = 0
			if Net.is_host():
				_host_step(delta)
	rope_shown = lerpf(rope_shown, clampf(rope, -1.2, 1.2), 1.0 - exp(-delta * 8.0))
	for m in tap_marks:
		m["t"] = float(m["t"]) + delta
	tap_marks = tap_marks.filter(func(m): return float(m["t"]) < 0.5)
	view.queue_redraw()
	hud.queue_redraw()


# ------------------------------------------------------------------ dessin
const GROUND_Y := 520.0
const PIT_W := 260.0


func _draw_view() -> void:
	var c := view
	c.draw_rect(Rect2(-20, -20, 1320, 760), Color("#bfeaf5"))
	c.draw_circle(Vector2(240, 560), 380, Color("#b6e07a"))
	c.draw_circle(Vector2(1060, 580), 420, Color("#a9d96d"))
	for k in 8:
		var tx: Texture2D = _tex["tree" if k % 3 != 1 else "treePine"]
		var x := 80.0 + k * 160.0
		if absf(x - 640.0) < 160.0:
			continue
		c.draw_set_transform(Vector2(x, 420), 0.0, Vector2(0.45, 0.45))
		c.draw_texture(tx, Vector2(-tx.get_width() / 2.0, -tx.get_height()))
		c.draw_set_transform(Vector2.ZERO)
	var shift := rope_shown * 150.0
	# mare de boue au milieu (ne bouge pas)
	c.draw_rect(Rect2(640 - PIT_W / 2.0, GROUND_Y + 20, PIT_W, 300), Color("#8a5a36"))
	for k in 6:
		var bx := 640.0 - PIT_W / 2.0 + 20.0 + k * 42.0
		c.draw_circle(Vector2(bx, GROUND_Y + 40 + sin(t * 2.0 + k) * 4.0), 16.0, Color("#a06a40"))
	# berges
	for sd in [-1.0, 1.0]:
		var x0 := 0.0 if sd < 0 else 640.0 + PIT_W / 2.0
		var w := 640.0 - PIT_W / 2.0
		c.draw_rect(Rect2(x0, GROUND_Y, w, 260), Color("#c98a4e"))
		c.draw_rect(Rect2(x0, GROUND_Y, w, 26), Color("#7fc84a"))
		c.draw_rect(Rect2(x0, GROUND_Y + 22, w, 6), Color("#5fa83a"))
	# repère central au sol
	c.draw_rect(Rect2(640 - 3, GROUND_Y - 6, 6, 12), Color(1, 1, 1, 0.6))
	# la corde
	var ry := GROUND_Y - 62.0
	var lx := 40.0 + shift
	var rx := 1240.0 + shift
	c.draw_line(Vector2(lx, ry + 2), Vector2(rx, ry + 2), Color(0, 0, 0, 0.12), 12.0)
	var segs := 40
	var pts := PackedVector2Array()
	for k in segs + 1:
		var u := float(k) / segs
		pts.append(Vector2(lerpf(lx, rx, u), ry + sin(u * PI) * 8.0))
	c.draw_polyline(pts, Color("#c99a5c"), 9.0, true)
	for k in segs:
		var p := pts[k]
		c.draw_line(p + Vector2(-3, -3), p + Vector2(3, 3), Color("#a87a40"), 2.0)
	# ruban au milieu de la corde
	var mid := Vector2(640 + shift, ry + 8)
	c.draw_colored_polygon(PackedVector2Array([mid, mid + Vector2(-14, 36), mid + Vector2(14, 36)]), Color("#ff5a6a"))
	# équipes
	_draw_team(c, team_l, -1, shift, ry)
	_draw_team(c, team_r, 1, shift, ry)
	# arbitre au fond
	if referee != 0:
		var rp := Vector2(640, 300)
		c.draw_set_transform(rp + Vector2(0, -absf(sin(t * 4.0)) * 6.0), 0.0, Vector2(0.42, 0.42))
		c.draw_texture(_tex["%d_jump" % referee], Vector2(-128, -256))
		c.draw_set_transform(Vector2.ZERO)
		c.draw_set_transform(rp + Vector2(36, -40), sin(t * 6.0) * 0.3, Vector2(0.4, 0.4))
		c.draw_texture(_tex["flag"], Vector2(-30, -110))
		c.draw_set_transform(Vector2.ZERO)
		UI.text(c, rp + Vector2(0, 20), "Arbitre : %s" % Net.name_of(referee), 18, Net.color_of(referee), 5)


func _draw_team(c: CanvasItem, team: Array, side: int, shift: float, ry: float) -> void:
	var n := team.size()
	for i in n:
		var id: int = team[i]
		var base_x := 640.0 + side * (PIT_W / 2.0 + 70.0 + i * minf(110.0, 300.0 / maxf(1.0, float(n)))) + shift
		var pit_l := 640.0 - PIT_W / 2.0
		var pit_r := 640.0 + PIT_W / 2.0
		var fell := winner != 0 and winner != side
		if not fell:
			base_x = minf(base_x, pit_l - 26.0 - i * 40.0) if side < 0 else maxf(base_x, pit_r + 26.0 + i * 40.0)
		var y := GROUND_Y + 4.0
		if fell and i == 0:
			y += 70.0
			base_x = clampf(base_x, 640.0 - PIT_W / 2.0 + 40.0, 640.0 + PIT_W / 2.0 - 40.0)
		var rate := float(rates.get(id, 0.0)) if id != me_id else my_rate
		var pose := "walk_a" if int(t * maxf(2.0, rate)) % 2 == 0 else "walk_b"
		if fell:
			pose = "hit"
		if rate < 0.5 and not fell:
			pose = "idle"
		var lean := -side * (0.12 + minf(rate, 12.0) * 0.012)
		c.draw_set_transform(Vector2(base_x, y), lean, Vector2(-side * 0.55, 0.55))
		c.draw_texture(_tex["%d_%s" % [id, pose]], Vector2(-128, -256))
		c.draw_set_transform(Vector2.ZERO)
		if fell and i == 0:
			c.draw_circle(Vector2(base_x, GROUND_Y + 40), 30.0, Color("#8a5a36"))
		var nm := "TOI" if id == me_id else Net.name_of(id)
		UI.text(c, Vector2(base_x, y + 24), nm, 18 if id == me_id else 15, UI.YELLOW if id == me_id else Net.color_of(id), 5)
		if id == me_id:
			for m in tap_marks:
				var k := float(m["t"]) / 0.5
				UI.text(c, Vector2(base_x + float(m["x"]), y - 120 - k * 40.0), "+1", 20, Color(UI.YELLOW, 1.0 - k), 4)


# ------------------------------------------------------------------ HUD
func _draw_hud() -> void:
	var h := hud
	var St := preload("res://minigames/stage.gd")
	if state == "intro":
		var lines := ["Deux équipes tirent sur la corde au-dessus de la boue !",
			"Martèle ESPACE le plus vite possible pour tirer.",
			"L'équipe qui se fait tirer dans la boue a perdu."]
		if referee != 0:
			lines.append("%s est l'arbitre (nombre impair) : gagné d'office !" % Net.name_of(referee))
		lines.append(_team_line())
		St.draw_intro(h, "Tir à la corde !", lines, "Tirer : marteler Espace (ou n'importe quelle touche)")
		St.draw_ready_row(h, my_ready, ready_ids, ids, t, false)
		if str(Net.mg_data.get("mode", "")) == "duel":
			St.draw_duel_banner(h)
		return
	# jauge de la corde
	var bar := Rect2(Vector2(340, 24), Vector2(600, 40))
	UI.panel(h, bar, UI.WHITE, Color("#e4e2f2"), 20, 4)
	var inner := Rect2(bar.position + Vector2(10, 10), bar.size - Vector2(20, 20))
	h.draw_style_box(UI.box(Color("#ffb3b3"), Color(0, 0, 0, 0), 0, 10), Rect2(inner.position, Vector2(inner.size.x / 2.0, inner.size.y)))
	h.draw_style_box(UI.box(Color("#b3d1ff"), Color(0, 0, 0, 0), 0, 10), Rect2(inner.position + Vector2(inner.size.x / 2.0, 0), Vector2(inner.size.x / 2.0, inner.size.y)))
	var mx := inner.get_center().x + clampf(rope_shown, -1.0, 1.0) * inner.size.x / 2.0
	h.draw_circle(Vector2(mx, inner.get_center().y), 15.0, UI.WHITE)
	h.draw_circle(Vector2(mx, inner.get_center().y), 11.0, Color("#ff5a6a"))
	UI.text(h, bar.position + Vector2(-60, 20), "GAUCHE", 18, Color("#e0404a"), 5)
	UI.text(h, bar.end + Vector2(56, -20), "DROITE", 18, Color("#4b87f5"), 5)
	var tr := Rect2(Vector2(24, 18), Vector2(120, 52))
	UI.panel(h, tr, UI.WHITE, Color("#e4e2f2"), 18, 4)
	UI.text(h, UI.face_center(tr), "%d s" % maxi(0, ceili(MAX_T - play_t)), 30, UI.DARK, 0)
	if state == "count":
		UI.text(h, Vector2(640, 300), str(3 - int(t)), int(110 * (1.0 + (1.0 - fmod(t, 1.0)) * 0.3)), UI.WHITE, 16)
	elif state == "play" and winner == 0:
		if t < 1.0:
			UI.text(h, Vector2(640, 300), "TIREZ !", int(110 * (1.0 + t * 0.4)), Color(UI.YELLOW, 1.0 - t), 18)
		if my_team != 0:
			var k := 1.0 + 0.05 * sin(t * 16.0)
			var r := Rect2(Vector2(640 - 210 * k, 640), Vector2(420 * k, 56))
			UI.panel(h, r, Color("#ff7f8f"), UI.WHITE, 28, 5)
			UI.text(h, UI.face_center(r), "TAPE ESPACE !!!", int(30 * k), UI.WHITE, 7)
		elif me_id == referee:
			UI.text(h, Vector2(640, 660), "Tu es l'arbitre : tu as gagné d'office !", 26, UI.WHITE, 7)
	if winner != 0:
		var txt := "L'équipe de %s gagne !" % ("GAUCHE" if winner < 0 else "DROITE")
		UI.ribbon(h, Vector2(640, 160), txt, 40, Color("#e0404a") if winner < 0 else Color("#4b87f5"), UI.WHITE)
	if state == "over":
		h.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, minf(0.4, t)))
		UI.text(h, Vector2(640, 360), "TERMINÉ !", 96, UI.YELLOW, 16)


func _team_line() -> String:
	var a := []
	for id in team_l:
		a.append(Net.name_of(id))
	var b := []
	for id in team_r:
		b.append(Net.name_of(id))
	return "%s  contre  %s" % [", ".join(a), ", ".join(b)]
