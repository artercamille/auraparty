extends Node2D
## « Jackpot Aura ! » (Lucky Lineup, Mario Party 5) : chacun a sa machine à sous.
## 3 tirages ; Espace arrête les rouleaux un par un. Chaque ligne (3 horizontales + 2 diagonales)
## de 3 symboles identiques rapporte des points ; l'étoile est un joker. Le plus de points gagne.
## Chacun joue sa machine en local et envoie son résultat à l'hôte, qui le renvoie à tous.

const SYMS := ["seven", "gem", "heart", "coin", "star"]
const VALUE := [50, 20, 10, 5, 0]
const STAR := 4
const STAR_ALL := 100
const SPINS := 3
const STRIP := [0, 4, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 3]
const SPEEDS := [9.0, 11.0, 13.0]     # symboles par seconde, de plus en plus vite
const AUTO_STOP := 7.0
const LINES := [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 4, 8], [6, 4, 2]]
const CELL := Vector2(112, 96)
const MAX_T := 60.0

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

var strips: Array = []          # 3 rouleaux (indices de SYMS), identiques pour tout le monde
# ma machine
var spin_n := 0                 # tirages terminés
var mphase := "wait"            # wait, spin, show, done
var reel_pos := [0.0, 0.0, 0.0]
var reel_target := [-1.0, -1.0, -1.0]
var reel_stop_t := [-1.0, -1.0, -1.0]
var spin_t := 0.0
var show_t := 0.0
var lever_t := -1.0
var my_score := 0
var my_lines: Array = []        # [index de ligne, gain]
var bot_wait := 1.0
var auto_acc := 0.0
var tick_acc := 0.0
# tout le monde (renvoyé par l'hôte)
var pdata := {}                 # id -> {score, spin, grid, gain, lines, at}
var popups: Array = []
var sparks: Array = []
# hôte
var ended := false
var finish_in := -1.0


func _ready() -> void:
	rng.seed = int(Net.mg_data.get("seed", 1))
	brng.randomize()
	for id in Net.mg_data.get("players", Net.players.keys()):
		if Net.players.has(id):
			ids.append(id)
	ids.sort()
	me_id = Net.my_id()
	playing = ids.has(me_id)
	for i in 3:
		var s := STRIP.duplicate()
		for k in range(s.size() - 1, 0, -1):
			var j := rng.randi_range(0, k)
			var tmp: int = s[k]
			s[k] = s[j]
			s[j] = tmp
		strips.append(s)
		reel_pos[i] = float(rng.randi_range(0, s.size() - 1))
	for id in ids:
		pdata[id] = {"score": 0, "spin": 0, "grid": _grid_at([reel_pos[0], reel_pos[1], reel_pos[2]]), "gain": 0, "lines": [], "at": -10.0}
		_tex["%d" % id] = UI.char_tex(Net.color_idx(id), "front")
	for i in SYMS.size():
		_tex[SYMS[i]] = load("res://assets/slots/%s.png" % SYMS[i])
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
			pdata.erase(id)


# ------------------------------------------------------------------ règles
func _sym(reel: int, pos: float, row: int) -> int:
	var s: Array = strips[reel]
	return int(s[posmod(int(round(pos)) - row, s.size())])


## Grille 3x3 (ligne par ligne) quand les rouleaux sont arrêtés à ces positions.
func _grid_at(pos: Array) -> Array:
	var g := []
	for r in 3:
		for c in 3:
			g.append(_sym(c, float(pos[c]), r))
	return g


static func eval_lines(g: Array) -> Array:
	var out := []
	for li in LINES.size():
		var l: Array = LINES[li]
		var kind := -1
		var ok := true
		for k in l:
			var s := int(g[k])
			if s == STAR:
				continue
			if kind == -1:
				kind = s
			elif kind != s:
				ok = false
				break
		if ok:
			out.append([li, STAR_ALL if kind == -1 else int(VALUE[kind])])
	return out


# ------------------------------------------------------------------ ma machine
func _start_spin() -> void:
	mphase = "spin"
	spin_t = 0.0
	lever_t = 0.0
	my_lines = []
	auto_acc = 0.0
	bot_wait = brng.randf_range(0.6, 1.4)
	for i in 3:
		reel_target[i] = -1.0
		reel_stop_t[i] = -1.0
		reel_pos[i] += brng.randf_range(0.0, 14.0)
	Sfx.play("chips_handle", -2.0)


func _next_reel() -> int:
	for i in 3:
		if reel_target[i] < 0.0:
			return i
	return -1


func _press_stop() -> void:
	var i := _next_reel()
	if i < 0:
		return
	reel_target[i] = ceil(reel_pos[i] + 0.3)
	Sfx.play("ui_move", -6.0, 0.0)


func _my_step(dt: float) -> void:
	if not playing:
		return
	match mphase:
		"spin":
			spin_t += dt
			var sp: float = SPEEDS[mini(spin_n, SPEEDS.size() - 1)]
			var all_stopped := true
			for i in 3:
				if reel_stop_t[i] >= 0.0:
					reel_stop_t[i] += dt
					continue
				all_stopped = false
				reel_pos[i] += sp * dt
				if reel_target[i] >= 0.0 and reel_pos[i] >= reel_target[i]:
					reel_pos[i] = reel_target[i]
					reel_stop_t[i] = 0.0
					Sfx.play("chip", -2.0, 0.1)
			tick_acc += dt
			if tick_acc > 1.0 / sp and not all_stopped:
				tick_acc = 0.0
				Sfx.play("ui_tick", -18.0, 0.15)
			if all_stopped:
				_spin_done()
				return
			if spin_t > 0.35:
				var press := false
				if Net.autotest != "":
					bot_wait -= dt
					if bot_wait <= 0.0:
						press = true
						bot_wait = brng.randf_range(0.35, 1.1)
				elif Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("push") or Input.is_action_just_pressed("ui_accept"):
					press = true
				if spin_t > AUTO_STOP:
					auto_acc -= dt
					if auto_acc <= 0.0:
						auto_acc = 0.35
						press = true
				if press:
					_press_stop()
		"show":
			show_t -= dt
			if show_t <= 0.0:
				if spin_n >= SPINS:
					mphase = "done"
				else:
					_start_spin()


func _spin_done() -> void:
	var g := _grid_at(reel_pos)
	my_lines = eval_lines(g)
	var gain := 0
	for l in my_lines:
		gain += int(l[1])
	my_score += gain
	spin_n += 1
	mphase = "show"
	show_t = 1.4 if gain == 0 else 2.2
	if gain >= 50:
		Sfx.play("jingle_star", 0.0, 0.0)
	elif gain > 0:
		Sfx.play("jingle_good", -2.0, 0.0)
		Sfx.play("coin", -4.0)
	else:
		Sfx.play("ui_back", -6.0, 0.0)
	if Net.autotest != "":
		print("[slots] spin ", spin_n, " gain ", gain, " t=", snappedf(play_t, 0.1), " fps=", Engine.get_frames_per_second())
	var lines := []
	for l in my_lines:
		lines.append(int(l[0]))
	Net.mg_to_host({"spin": spin_n, "grid": g, "gain": gain, "score": my_score, "lines": lines})


# ------------------------------------------------------------------ réseau
func _on_mg_msg(from_id: int, d: Dictionary) -> void:
	if not Net.is_host() or ended or not d.has("spin") or not ids.has(from_id):
		return
	Net.mg_broadcast({"p": from_id, "spin": int(d["spin"]), "grid": d["grid"], "gain": int(d["gain"]),
		"score": int(d["score"]), "lines": d.get("lines", [])})


func _on_mg_state(d: Dictionary) -> void:
	if not d.has("p"):
		return
	var id := int(d["p"])
	if not pdata.has(id):
		return
	pdata[id] = {"score": int(d["score"]), "spin": int(d["spin"]), "grid": d["grid"], "gain": int(d["gain"]),
		"lines": d["lines"], "at": play_t}
	if id != me_id and int(d["gain"]) > 0:
		Sfx.play("coin", -12.0)
	if Net.is_host() and finish_in < 0.0:
		var all_done := true
		for pid in ids:
			if int(pdata[pid]["spin"]) < SPINS:
				all_done = false
		if all_done:
			finish_in = 2.6


func _finish() -> void:
	if ended:
		return
	ended = true
	if Net.autotest != "":
		print("[slots] finish t=", snappedf(play_t, 0.1), " ", pdata)
	var sc := {}
	for id in ids:
		var s := int(pdata[id]["score"])
		sc[id] = [float(s), "%d point%s" % [s, "s" if s > 1 else ""]]
	Net.mg_end_with_scores(sc)


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
				if playing:
					_start_spin()
		"play":
			play_t += delta
			_my_step(delta)
			if Net.is_host():
				if finish_in >= 0.0:
					finish_in -= delta
					if finish_in <= 0.0:
						_finish()
				elif play_t > MAX_T:
					_finish()
	if lever_t >= 0.0:
		lever_t += delta
		if lever_t > 0.6:
			lever_t = -1.0
	for p in popups:
		p["t"] = float(p["t"]) + delta
	popups = popups.filter(func(p): return float(p["t"]) < 1.6)
	for p in sparks:
		p["t"] = float(p["t"]) + delta
		p["p"] = (p["p"] as Vector2) + (p["v"] as Vector2) * delta
		p["v"] = (p["v"] as Vector2) + Vector2(0, 700) * delta
	sparks = sparks.filter(func(p): return float(p["t"]) < 1.2)
	view.queue_redraw()
	hud.queue_redraw()


# ------------------------------------------------------------------ dessin
func _draw_view() -> void:
	var c := view
	# salle de casino pastel : fond violet, rideaux, guirlande d'ampoules
	c.draw_rect(Rect2(-20, -20, 1320, 760), Color("#6c4fb0"))
	for k in 6:
		c.draw_circle(Vector2(640, 380), 760.0 - k * 110.0, Color(Color("#8c6ad0"), 0.18))
	for k in 14:
		var x := -40.0 + k * 100.0
		c.draw_rect(Rect2(x, -20, 50, 760), Color(1, 1, 1, 0.035))
	# rideaux
	for sd in [-1, 1]:
		var side := float(sd)
		var x0 := 0.0 if side < 0.0 else 1280.0
		var pts := PackedVector2Array([Vector2(x0, -10), Vector2(x0 - side * 150.0, -10), Vector2(x0 - side * 70.0, 300), Vector2(x0 - side * 30.0, 760), Vector2(x0, 760)])
		c.draw_colored_polygon(pts, Color("#e5536b"))
		c.draw_polyline(PackedVector2Array([Vector2(x0 - side * 110.0, -10), Vector2(x0 - side * 50.0, 330), Vector2(x0 - side * 18.0, 760)]), Color("#c43a55"), 8.0)
	c.draw_rect(Rect2(-20, -20, 1320, 46), Color("#e5536b"))
	for k in 33:
		var bx := 20.0 + k * 39.0
		var on := (k + int(t * 4.0)) % 3 == 0
		c.draw_circle(Vector2(bx, 30 + sin(k * 0.9) * 4.0), 8.0, Color("#fff2a8") if on else Color("#ffd23f"))
		if on:
			c.draw_circle(Vector2(bx, 30 + sin(k * 0.9) * 4.0), 14.0, Color(1, 0.95, 0.6, 0.25))
	# moquette
	c.draw_rect(Rect2(-20, 640, 1320, 120), Color("#c43a55"))
	for k in 18:
		c.draw_circle(Vector2(30 + k * 75.0, 690), 10.0, Color("#ffd23f", 0.5))
	if state == "intro":
		return
	if playing:
		_draw_machine(c, Vector2(640, 392), 1.0, me_id, true)
		var others := ids.filter(func(i): return i != me_id)
		for k in others.size():
			var left := k % 2 == 0
			var row := k / 2
			_draw_card(c, Vector2(24 if left else 1036, 92 + row * 140), others[k])
	else:
		var n := ids.size()
		for k in n:
			var cx := 640.0 + (float(k) - (n - 1) / 2.0) * (1280.0 / maxf(2.0, float(n)))
			_draw_machine(c, Vector2(cx, 400), 0.82 if n <= 2 else 0.5, ids[k], false)
	for p in sparks:
		var q := float(p["t"]) / 1.2
		c.draw_circle(p["p"], float(p["r"]) * (1.0 - q), Color(p["c"], 1.0 - q))


## La machine à sous, centrée sur `ctr`, à l'échelle `s`. `live` = ma machine qui tourne.
func _draw_machine(c: CanvasItem, ctr: Vector2, s: float, id: int, live: bool) -> void:
	c.draw_set_transform(ctr, 0.0, Vector2(s, s))
	var col := Net.color_of(id)
	var body := Rect2(Vector2(-210, -232), Vector2(420, 470))
	c.draw_style_box(UI.box(Color(0.1, 0.05, 0.25, 0.3), Color(0, 0, 0, 0), 0, 40), Rect2(body.position + Vector2(0, 14), body.size))
	UI.panel(c, body, Color("#ff8fa3"), UI.WHITE, 40, 7, false)
	c.draw_style_box(UI.box(Color("#ffb3c1"), Color(0, 0, 0, 0), 0, 30), Rect2(body.position + Vector2(18, 16), Vector2(body.size.x - 36, 40)))
	# fronton
	var top := Rect2(Vector2(-180, -290), Vector2(360, 84))
	UI.panel(c, top, Color("#ffd23f"), UI.WHITE, 40, 6, false)
	for k in 12:
		var a := PI + PI * float(k) / 11.0
		var bp := Vector2(cos(a) * 168.0, -248.0 + sin(a) * 34.0 + 20.0)
		var on := (k + int(t * 5.0)) % 2 == 0
		c.draw_circle(bp, 6.0, UI.WHITE if on else Color("#ff9a5a"))
	UI.text(c, Vector2(0, -246), "JACKPOT", 46, Color("#e5536b"), 9)
	# fenêtre des rouleaux
	var win := Rect2(Vector2(-CELL.x * 1.5, -170), Vector2(CELL.x * 3.0, CELL.y * 3.0))
	c.draw_style_box(UI.box(Color("#5b3f96"), Color(0, 0, 0, 0), 0, 26), win.grow(14))
	c.draw_style_box(UI.box(UI.WHITE, Color(0, 0, 0, 0), 0, 18), win)
	var grid: Array = pdata[id]["grid"] if pdata.has(id) else []
	for r in 3:
		c.draw_rect(Rect2(win.position + Vector2(4, r * CELL.y + CELL.y / 2.0 - 1), Vector2(win.size.x - 8, 2)), Color(0.4, 0.3, 0.6, 0.06))
	for col_i in 3:
		var x0 := win.position.x + col_i * CELL.x
		if col_i > 0:
			c.draw_rect(Rect2(Vector2(x0 - 2, win.position.y + 6), Vector2(4, win.size.y - 12)), Color("#e4dcf5"))
		if live:
			_draw_reel_live(c, col_i, Rect2(Vector2(x0, win.position.y), Vector2(CELL.x, win.size.y)))
		else:
			for r in 3:
				var sym := int(grid[r * 3 + col_i]) if grid.size() == 9 else 3
				var cr := Rect2(Vector2(x0, win.position.y + r * CELL.y), CELL)
				_draw_sym(c, sym, cr.get_center(), 1.0)
	# ombre intérieure haut / bas (effet tambour)
	for k in 6:
		var a := 0.12 - k * 0.02
		c.draw_rect(Rect2(win.position + Vector2(0, k * 5.0), Vector2(win.size.x, 5)), Color(0.3, 0.2, 0.5, a))
		c.draw_rect(Rect2(Vector2(win.position.x, win.end.y - (k + 1) * 5.0), Vector2(win.size.x, 5)), Color(0.3, 0.2, 0.5, a))
	# lignes gagnantes
	var lines: Array = []
	var shown := false
	if live:
		shown = mphase == "show" or mphase == "done"
		for l in my_lines:
			lines.append(int(l[0]))
	else:
		lines = pdata[id]["lines"] if pdata.has(id) else []
		shown = pdata.has(id) and play_t - float(pdata[id]["at"]) < 2.5
	if shown and lines.size() > 0:
		var blink := 0.55 + 0.45 * sin(t * 10.0)
		for li in lines:
			var l: Array = LINES[int(li)]
			var a := win.position + Vector2((int(l[0]) % 3 + 0.5) * CELL.x, (int(l[0]) / 3 + 0.5) * CELL.y)
			var b := win.position + Vector2((int(l[2]) % 3 + 0.5) * CELL.x, (int(l[2]) / 3 + 0.5) * CELL.y)
			var dirv := (b - a).normalized()
			a -= dirv * 40.0
			b += dirv * 40.0
			c.draw_line(a, b, Color(1, 0.85, 0.2, 0.35 * blink), 26.0)
			c.draw_line(a, b, Color(UI.RED, 0.9 * blink), 7.0)
	# boutons d'arrêt
	for i in 3:
		var bc := Vector2((i - 1) * CELL.x, 168)
		var stopped: bool = (reel_target[i] >= 0.0) if live else true
		var active := live and mphase == "spin" and _next_reel() == i
		var k := 1.0 + (0.12 * sin(t * 12.0) if active else 0.0)
		c.draw_circle(bc + Vector2(0, 6), 30.0 * k, Color(0.2, 0.1, 0.3, 0.25))
		c.draw_circle(bc, 30.0 * k, UI.WHITE)
		c.draw_circle(bc, 24.0 * k, Color("#ffd23f") if active else (Color("#c9c3dc") if stopped else Color("#f04650")))
		c.draw_circle(bc + Vector2(-7, -8) * k, 7.0 * k, Color(1, 1, 1, 0.5))
		if active:
			UI.text(c, bc + Vector2(0, 46), "ESPACE", 18, UI.WHITE, 6)
	# levier
	var pull := 0.0
	if live and lever_t >= 0.0:
		pull = sin(clampf(lever_t / 0.6, 0.0, 1.0) * PI)
	var base := Vector2(222, -40)
	var knob := base + Vector2(30, -110 + pull * 150.0)
	c.draw_style_box(UI.box(Color("#c9c3dc"), UI.WHITE, 4, 10), Rect2(base + Vector2(-8, -20), Vector2(30, 60)))
	c.draw_line(base + Vector2(14, 10), knob, Color("#8d86a3"), 12.0)
	c.draw_circle(knob, 22.0, UI.WHITE)
	c.draw_circle(knob, 17.0, UI.RED)
	c.draw_circle(knob + Vector2(-5, -6), 5.0, Color(1, 1, 1, 0.6))
	# plaque du joueur
	var plate := Rect2(Vector2(-180, 214), Vector2(360, 64))
	UI.panel(c, plate, UI.WHITE, col, 32, 6, false)
	var hc := Vector2(-150, 246)
	var happy := live and mphase == "show" and my_lines.size() > 0
	c.draw_circle(hc, 36.0, UI.WHITE)
	c.draw_circle(hc, 30.0, col.darkened(0.1))
	c.draw_texture_rect_region(_tex["%d" % id], Rect2(hc - Vector2(27, 28 + (6.0 * absf(sin(t * 10.0)) if happy else 0.0)), Vector2(54, 48)), Rect2(66, 104, 124, 96))
	var sc: int = my_score if live else int(pdata[id]["score"]) if pdata.has(id) else 0
	var nm := "TOI" if live else Net.name_of(id)
	UI.text(c, Vector2(-40, 246), nm, 26, col.darkened(0.3), 0)
	UI.text(c, Vector2(100, 246), "%d pts" % sc, 32, UI.DARK, 0)
	var sn: int = spin_n if live else int(pdata[id]["spin"]) if pdata.has(id) else 0
	var tag := "Tirage %d/%d" % [mini(sn + 1, SPINS), SPINS] if sn < SPINS else "Terminé !"
	UI.text(c, Vector2(0, -196), tag, 20, UI.WHITE, 6)
	c.draw_set_transform(Vector2.ZERO)
	# gain qui s'envole
	var gain := 0
	var gain_age := 99.0
	if live:
		if mphase == "show" or mphase == "done":
			for l in my_lines:
				gain += int(l[1])
			gain_age = (2.2 - show_t) if mphase == "show" else 99.0
	elif pdata.has(id):
		gain = int(pdata[id]["gain"])
		gain_age = play_t - float(pdata[id]["at"])
	if gain > 0 and gain_age < 1.6:
		var k2 := gain_age / 1.6
		UI.text(c, ctr + Vector2(0, -40 - k2 * 120.0) * s, "+%d" % gain, int((70 + 20 * minf(1.0, gain_age * 4.0)) * s), Color(UI.YELLOW, 1.0 - k2 * k2), int(12 * s))


func _draw_reel_live(c: CanvasItem, reel: int, area: Rect2) -> void:
	var s: Array = strips[reel]
	var n := s.size()
	var pos: float = reel_pos[reel]
	var bounce := 0.0
	if reel_stop_t[reel] >= 0.0 and reel_stop_t[reel] < 0.25:
		bounce = sin(reel_stop_t[reel] / 0.25 * PI) * 0.12
	var spinning: bool = reel_stop_t[reel] < 0.0 and mphase == "spin"
	for i in n:
		var rowc := fposmod(pos + bounce - float(i), float(n))
		if rowc > n - 2.0:
			rowc -= n
		if rowc < -1.0 or rowc > 3.0:
			continue
		var cy := area.position.y + (rowc + 0.5) * CELL.y
		_draw_sym_clipped(c, int(s[i]), Vector2(area.get_center().x, cy), area, spinning)


func _draw_sym(c: CanvasItem, sym: int, at: Vector2, k: float) -> void:
	var tx: Texture2D = _tex[SYMS[sym]]
	var sz := 84.0 * k
	c.draw_texture_rect(tx, Rect2(at - Vector2(sz, sz) / 2.0, Vector2(sz, sz)), false)


func _draw_sym_clipped(c: CanvasItem, sym: int, at: Vector2, area: Rect2, blur: bool) -> void:
	var tx: Texture2D = _tex[SYMS[sym]]
	var sz := 84.0
	var r := Rect2(at - Vector2(sz, sz) / 2.0, Vector2(sz, sz))
	var cl := r.intersection(area)
	if cl.size.y <= 1.0:
		return
	var tw := float(tx.get_width())
	var src := Rect2(Vector2(0, (cl.position.y - r.position.y) / sz * tw), Vector2(tw, cl.size.y / sz * tw))
	var mod := Color(1, 1, 1, 0.75) if blur else Color.WHITE
	c.draw_texture_rect_region(tx, cl, src, mod)
	if blur:
		var off := Rect2(cl.position + Vector2(0, -10), cl.size).intersection(area)
		if off.size.y > 1.0:
			c.draw_texture_rect_region(tx, off, Rect2(src.position, Vector2(tw, off.size.y / sz * tw)), Color(1, 1, 1, 0.22))


## Petite carte d'un adversaire (sur les côtés) : nom, score et sa dernière grille.
func _draw_card(c: CanvasItem, pos: Vector2, id: int) -> void:
	var d: Dictionary = pdata[id]
	var fresh := play_t - float(d["at"]) < 1.2 and int(d["gain"]) > 0
	var r := Rect2(pos, Vector2(220, 128))
	var col := Net.color_of(id)
	UI.panel(c, r, UI.WHITE, col.lerp(Color.WHITE, 0.2) if not fresh else UI.YELLOW, 20, 6 if not fresh else 8)
	c.draw_set_transform(pos + Vector2(28, 52), 0.0, Vector2(0.17, 0.17))
	c.draw_texture(_tex["%d" % id], Vector2(-128, -256))
	c.draw_set_transform(Vector2.ZERO)
	UI.text(c, pos + Vector2(70, 22), Net.name_of(id), 18, col.darkened(0.25), 0)
	UI.text(c, pos + Vector2(56, 82), "%d" % int(d["score"]), 34, UI.DARK, 0)
	UI.text(c, pos + Vector2(56, 110), "pts", 15, UI.GREY, 0)
	# mini-grille
	var g: Array = d["grid"]
	var gp := pos + Vector2(116, 18)
	c.draw_style_box(UI.box(Color("#f1ecfb"), Color(0, 0, 0, 0), 0, 10), Rect2(gp - Vector2(4, 4), Vector2(98, 98)))
	for k in 9:
		var cc := gp + Vector2((k % 3) * 30.0 + 15.0, (k / 3) * 30.0 + 15.0)
		var tx: Texture2D = _tex[SYMS[int(g[k])]]
		c.draw_texture_rect(tx, Rect2(cc - Vector2(13, 13), Vector2(26, 26)), false)
	var lines: Array = d["lines"]
	if play_t - float(d["at"]) < 2.5:
		for li in lines:
			var l: Array = LINES[int(li)]
			var a := gp + Vector2((int(l[0]) % 3) * 30.0 + 15.0, (int(l[0]) / 3) * 30.0 + 15.0)
			var b := gp + Vector2((int(l[2]) % 3) * 30.0 + 15.0, (int(l[2]) / 3) * 30.0 + 15.0)
			c.draw_line(a, b, Color(UI.RED, 0.8), 4.0)
	var sp := int(d["spin"])
	UI.text(c, pos + Vector2(165, 116), "%d/%d" % [mini(sp, SPINS), SPINS] if sp < SPINS else "fini", 14, UI.GREY, 0)
	if fresh:
		UI.text(c, pos + Vector2(165, 60 - (play_t - float(d["at"])) * 30.0), "+%d" % int(d["gain"]), 28, UI.YELLOW, 7)


# ------------------------------------------------------------------ HUD
func _draw_hud() -> void:
	var h := hud
	var St := preload("res://minigames/stage.gd")
	if state == "intro":
		St.draw_intro(h, "Jackpot Aura !", [
			"Chacun sa machine à sous ! Tu as 3 tirages.",
			"Appuie sur Espace pour arrêter les rouleaux un par un.",
			"3 symboles pareils sur une ligne ou une diagonale = des points :",
			"7 = 50  ·  gemme = 20  ·  cœur = 10  ·  pièce = 5. L'étoile est un joker !",
			"Le plus de points après 3 tirages gagne."],
			"Arrêter un rouleau : Espace / Entrée")
		St.draw_ready_row(h, my_ready, ready_ids, ids, t, not playing)
		if str(Net.mg_data.get("mode", "")) == "duel":
			St.draw_duel_banner(h)
		return
	if state == "count":
		UI.text(h, Vector2(640, 360), str(3 - int(t)), int(110 * (1.0 + (1.0 - fmod(t, 1.0)) * 0.3)), UI.WHITE, 16)
	elif state == "play" and t < 1.0:
		UI.text(h, Vector2(640, 360), "GO !", int(120 * (1.0 + t * 0.4)), Color(UI.YELLOW, 1.0 - t), 18)
	if state == "play" and playing and mphase == "done":
		var msg := "Bravo ! On attend les autres..."
		var mw := UI.text_width(msg, 24) + 50.0
		UI.panel(h, Rect2(Vector2(640 - mw / 2.0, 664), Vector2(mw, 46)), UI.WHITE, Color("#e4dcf5"), 20, 4)
		UI.text(h, Vector2(640, 687), msg, 24, Color("#6c4fb0"), 0)
	if state == "over":
		h.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, minf(0.4, t)))
		UI.text(h, Vector2(640, 360), "TERMINÉ !", 96, UI.YELLOW, 16)
