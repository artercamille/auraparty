extends Node2D
## « Stop chrono ! » : un temps à viser est affiché (ex. 7,38 s), le chrono démarre, reste visible
## un moment puis se cache. Chacun l'arrête (Espace / A) quand il pense être pile au temps.
## 3 manches, le chrono se cache de plus en plus tôt ; on additionne les écarts : le plus petit total gagne.
## L'hôte donne le départ de chaque manche, chacun chronomètre chez lui et envoie son temps ;
## l'hôte révèle les temps de tout le monde à la fin de chaque manche.

const ROUNDS := 3
const VISIBLE := [3.0, 2.0, 1.2]               # secondes pendant lesquelles on voit le chrono
const TARGET_MIN := [5.0, 6.5, 8.0]
const TARGET_MAX := [7.0, 9.0, 11.5]
const LATE := 5.0                              # au-delà de cible + 5 s : arrêté d'office (écart 5 s)
const TARGET_T := 2.6                          # durée de l'écran « temps à viser »
const REVEAL_T := 5.0                          # durée de la révélation de fin de manche

var ids: Array = []
var me_id := 0
var playing := false
var hud: Control
var view: Node2D
var state := "intro"                           # intro, count, play, over
var t := 0.0
var my_ready := false
var go_received := false
var ready_ids: Array = []
var rng := RandomNumberGenerator.new()
var brng := RandomNumberGenerator.new()

var targets: Array = []                        # temps à viser, identiques chez tout le monde
var rnd := -1                                  # manche en cours (0..2)
var ph := "wait"                               # wait, target, run, reveal, end
var ph_t := 0.0
# mon chrono
var run_t := 0.0                               # temps écoulé depuis le départ de la manche
var my_stop := -1.0                            # mon temps (-1 = pas encore arrêté)
var bot_aim := 0.0
var stop_flash := 0.0
var tick_n := 0
# tout le monde
var stopped := {}                              # id -> true quand il a arrêté (manche en cours)
var results: Array = []                        # par manche : {id: temps}
var totals := {}                               # id -> somme des écarts
var cover := 0.0                               # 0 = chrono visible, 1 = caché (animé)
# hôte
var host_vals := {}
var ended := false


func _ready() -> void:
	rng.seed = int(Net.mg_data.get("seed", 1))
	brng.randomize()
	for id in Net.mg_data.get("players", Net.players.keys()):
		if Net.players.has(id):
			ids.append(id)
	ids.sort()
	me_id = Net.my_id()
	playing = ids.has(me_id)
	for r in ROUNDS:
		targets.append(snappedf(rng.randf_range(TARGET_MIN[r], TARGET_MAX[r]), 0.01))
	for id in ids:
		totals[id] = 0.0
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
	Net.players_changed.connect(_on_players_changed)


func _on_ending() -> void:
	state = "over"
	t = 0.0
	Sfx.play("bell", -2.0, 0.0)


func _on_players_changed() -> void:
	for id in ids.duplicate():
		if not Net.players.has(id):
			ids.erase(id)
			totals.erase(id)


static func fmt(v: float) -> String:
	return ("%.2f" % v).replace(".", ",")


# ------------------------------------------------------------------ réseau
## Hôte : départ d'une manche (affiche le temps à viser), puis lancement du chrono.
func _host_round(r: int) -> void:
	host_vals = {}
	Net.mg_broadcast({"ph": "target", "r": r})
	await get_tree().create_timer(TARGET_T).timeout
	if ended:
		return
	Net.mg_broadcast({"ph": "run", "r": r})
	var limit := float(targets[r]) + LATE + 1.0
	var waited := 0.0
	while waited < limit and host_vals.size() < ids.size():
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if ended:
		return
	var vals := {}
	for id in ids:
		vals[id] = float(host_vals.get(id, float(targets[r]) + LATE))
	Net.mg_broadcast({"ph": "reveal", "r": r, "vals": vals})
	await get_tree().create_timer(REVEAL_T).timeout
	if ended:
		return
	if r + 1 < ROUNDS:
		_host_round(r + 1)
	else:
		_finish()


func _on_mg_msg(from_id: int, d: Dictionary) -> void:
	if not Net.is_host() or ended or not d.has("stop") or not ids.has(from_id):
		return
	if int(d.get("r", -1)) != rnd or host_vals.has(from_id):
		return
	host_vals[from_id] = float(d["stop"])
	Net.mg_broadcast({"ph": "stopped", "p": from_id})


func _on_mg_state(d: Dictionary) -> void:
	match str(d.get("ph", "")):
		"target":
			rnd = int(d["r"])
			ph = "target"
			ph_t = 0.0
			stopped = {}
			my_stop = -1.0
			run_t = 0.0
			cover = 0.0
			Sfx.play("ui_open", -2.0, 0.0)
		"run":
			ph = "run"
			ph_t = 0.0
			run_t = 0.0
			tick_n = 0
			bot_aim = float(targets[rnd]) + brng.randf_range(-0.4, 0.4)
			Sfx.play("ui_ok", 0.0, 0.0)
		"stopped":
			stopped[int(d["p"])] = true
			if int(d["p"]) != me_id:
				Sfx.play("chip", -10.0)
		"reveal":
			ph = "reveal"
			ph_t = 0.0
			var vals := {}
			for k in d["vals"]:
				vals[int(k)] = float(d["vals"][k])
			results.append(vals)
			for id in ids:
				if vals.has(id):
					totals[id] = float(totals.get(id, 0.0)) + absf(vals[id] - float(targets[rnd]))
			Sfx.play("bell", -4.0, 0.0)
			if vals.has(me_id) and absf(vals[me_id] - float(targets[rnd])) < 0.1:
				Sfx.play("jingle_star", -2.0, 0.0)


func _finish() -> void:
	if ended:
		return
	ended = true
	var sc := {}
	for id in ids:
		var tot := float(totals.get(id, 0.0))
		sc[id] = [-tot, "écart total %s s" % fmt(tot)]
	if Net.autotest != "":
		print("[chrono] fin ", sc)
	Net.mg_end_with_scores(sc)


func _press_stop() -> void:
	if my_stop >= 0.0 or not playing:
		return
	my_stop = snappedf(run_t, 0.01)
	stop_flash = 1.0
	stopped[me_id] = true
	Sfx.play("die_hit", 0.0, 0.0)
	Net.mg_to_host({"r": rnd, "stop": my_stop})


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
				if Net.is_host():
					_host_round(0)
		"play":
			ph_t += delta
			if ph == "run":
				run_t += delta
				var vis: float = VISIBLE[clampi(rnd, 0, ROUNDS - 1)]
				cover = clampf((run_t - vis) / 0.35, 0.0, 1.0)
				if run_t < vis and int(run_t) > tick_n:
					tick_n = int(run_t)
					Sfx.play("ui_tick", -8.0, 0.0)
				if playing and my_stop < 0.0:
					var press := false
					if Net.autotest != "":
						press = run_t >= bot_aim
					elif Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("push") or Input.is_action_just_pressed("ui_accept"):
						press = true
					if run_t >= float(targets[rnd]) + LATE:
						press = true
					if press:
						_press_stop()
			elif ph == "reveal":
				cover = maxf(0.0, cover - delta * 3.0)
	stop_flash = maxf(0.0, stop_flash - delta * 2.0)
	view.queue_redraw()
	hud.queue_redraw()


# ------------------------------------------------------------------ dessin
func _draw_view() -> void:
	var c := view
	# studio de jeu télé : fond bleu nuit, rayons tournants, spots
	c.draw_rect(Rect2(-20, -20, 1320, 760), Color("#2f3e8f"))
	var ctr := Vector2(640, 400)
	for k in 16:
		var a := t * 0.12 + k * TAU / 16.0
		var pts := PackedVector2Array([ctr, ctr + Vector2.from_angle(a - 0.09) * 1400.0, ctr + Vector2.from_angle(a + 0.09) * 1400.0])
		c.draw_colored_polygon(pts, Color(1, 1, 1, 0.045 if k % 2 == 0 else 0.0))
	for k in 6:
		c.draw_circle(ctr, 620.0 - k * 95.0, Color(Color("#5a6fd6"), 0.1))
	# estrade
	c.draw_rect(Rect2(-20, 640, 1320, 120), Color("#24306e"))
	c.draw_rect(Rect2(-20, 640, 1320, 8), Color("#7f93ff"))
	for k in 22:
		var x := k * 62.0 + fmod(t * 20.0, 62.0) - 31.0
		var on := (k + int(t * 3.0)) % 3 == 0
		c.draw_circle(Vector2(x, 670), 7.0, Color("#ffe27a") if on else Color("#6a7bd8"))
	_draw_watch(c, Vector2(640, 380), 1.0)


## Le gros chronomètre. Pendant la manche : aiguille + affichage numérique, puis un volet « ? » le cache.
func _draw_watch(c: CanvasItem, p: Vector2, s: float) -> void:
	var r := 200.0 * s
	var ink := UI.INK
	# bouton du haut + anneau
	var press := 8.0 * stop_flash
	c.draw_rect(Rect2(p + Vector2(-26, -r - 52 + press) * Vector2(1, 1), Vector2(52, 40)), ink)
	c.draw_rect(Rect2(p + Vector2(-21, -r - 47 + press), Vector2(42, 34)), Color("#ff5d5d"))
	c.draw_rect(Rect2(p + Vector2(-21, -r - 47 + press), Vector2(42, 10)), Color("#ff9a9a"))
	c.draw_rect(Rect2(p + Vector2(-14, -r - 16), Vector2(28, 24)), ink)
	c.draw_rect(Rect2(p + Vector2(-10, -r - 14), Vector2(20, 20)), Color("#c9cfe6"))
	for sd in [-1.0, 1.0]:
		var bp := p + Vector2.from_angle(-PI / 2.0 + sd * 0.75) * (r + 10.0)
		c.draw_circle(bp, 20.0, ink)
		c.draw_circle(bp, 15.0, Color("#c9cfe6"))
	# boîtier
	c.draw_circle(p + Vector2(0, 12), r + 18.0, Color(0, 0, 0, 0.25))
	c.draw_circle(p, r + 18.0, ink)
	c.draw_circle(p, r + 13.0, Color("#ffd23f"))
	c.draw_arc(p, r + 6.0, PI * 1.05, PI * 1.6, 24, Color(1, 1, 1, 0.6), 6.0)
	c.draw_circle(p, r, ink)
	c.draw_circle(p, r - 5.0, Color("#fffaf0"))
	# graduations (1 tour = 10 s)
	for k in 50:
		var a := -PI / 2.0 + k * TAU / 50.0
		var big := k % 5 == 0
		var d := Vector2.from_angle(a)
		c.draw_line(p + d * (r - 14.0), p + d * (r - (36.0 if big else 24.0)), Color(ink, 0.85 if big else 0.4), 6.0 if big else 3.0)
	for k in 10:
		var d2 := Vector2.from_angle(-PI / 2.0 + k * TAU / 10.0)
		UI.text(c, p + d2 * (r - 60.0), str(k), 26, ink, 0)
	var shown := run_t if ph == "run" else (my_stop if ph == "reveal" and my_stop >= 0.0 else 0.0)
	if ph == "reveal" and not playing and results.size() > 0:
		shown = 0.0
	# aiguille
	var ha := -PI / 2.0 + shown / 10.0 * TAU
	var hd := Vector2.from_angle(ha)
	c.draw_line(p - hd * 24.0, p + hd * (r - 30.0), Color(0, 0, 0, 0.15), 10.0)
	c.draw_line(p - hd * 24.0, p + hd * (r - 34.0), Color("#e2483c"), 8.0)
	c.draw_circle(p, 16.0, ink)
	c.draw_circle(p, 10.0, Color("#e2483c"))
	# affichage numérique
	var lcd := Rect2(p + Vector2(-110, 52), Vector2(220, 70))
	c.draw_style_box(UI.box(ink, Color(0, 0, 0, 0), 0, 16), lcd.grow(5))
	c.draw_style_box(UI.box(Color("#bfe8a8"), Color(0, 0, 0, 0), 0, 12), lcd)
	_digits(c, lcd.get_center() + Vector2(-8, 0), fmt(shown), 44, Color("#1f3b1a"))
	UI.text(c, lcd.get_center() + Vector2(88, 6), "s", 24, Color("#1f3b1a"), 0)
	# volet qui cache le chrono
	if cover > 0.0:
		var k2 := 1.0 - pow(1.0 - cover, 3.0)
		var cr := r - 5.0
		var top := p.y - cr
		var bottom := top + 2.0 * cr * k2
		# partie du disque au-dessus de `bottom` : arc des angles où sin(θ) <= s0, refermé par la corde
		var clip := PackedVector2Array()
		var s0 := clampf((bottom - p.y) / cr, -1.0, 1.0)
		if s0 >= 0.999:
			for i in 64:
				clip.append(p + Vector2.from_angle(i * TAU / 64.0) * cr)
		else:
			var a0 := PI - asin(s0)
			var a1 := TAU + asin(s0)
			for i in 49:
				clip.append(p + Vector2.from_angle(lerpf(a0, a1, i / 48.0)) * cr)
		if clip.size() >= 3:
			c.draw_colored_polygon(clip, Color("#7b5cff"))
		for i in 6:
			var yy := top + (i + 0.5) * (2.0 * cr / 6.0)
			if yy < bottom - 6.0:
				var hw := sqrt(maxf(0.0, cr * cr - (yy - p.y) * (yy - p.y)))
				c.draw_line(Vector2(p.x - hw + 6, yy), Vector2(p.x + hw - 6, yy), Color(1, 1, 1, 0.08), 18.0)
		if k2 > 0.6:
			var wob := sin(t * 5.0) * 0.08
			c.draw_set_transform(p + Vector2(0, -10), wob, Vector2.ONE)
			UI.text(c, Vector2.ZERO, "?", int(150 * clampf((k2 - 0.6) / 0.4, 0.0, 1.0)) + 1, UI.WHITE, 14)
			c.draw_set_transform(Vector2.ZERO)
		c.draw_arc(p, cr, 0.0, TAU, 64, ink, 5.0)
	# tampon « STOP ! » quand j'ai arrêté
	if ph == "run" and my_stop >= 0.0:
		c.draw_set_transform(p + Vector2(0, 150), -0.12, Vector2.ONE * (1.0 + stop_flash * 0.4))
		var sr := Rect2(Vector2(-110, -34), Vector2(220, 68))
		UI.panel(c, sr, Color("#e2483c"), UI.WHITE, 18, 5)
		UI.text(c, UI.face_center(sr), "STOP !", 40, UI.WHITE, 7)
		c.draw_set_transform(Vector2.ZERO)


## Chiffres à chasse fixe (le nombre ne « tremble » pas quand il défile).
func _digits(c: CanvasItem, center: Vector2, s: String, size: int, col: Color) -> void:
	var cw := size * 0.62
	var w := 0.0
	for ch in s:
		w += cw * (0.45 if ch == "," else 1.0)
	var x := center.x - w / 2.0
	for ch in s:
		var adv := cw * (0.45 if ch == "," else 1.0)
		UI.text(c, Vector2(x + adv / 2.0, center.y), ch, size, col, 0)
		x += adv


func _draw_hud() -> void:
	var h := hud
	var St := preload("res://minigames/stage.gd")
	if state == "intro":
		St.draw_intro(h, "Stop chrono !", [
			"Un temps à viser s'affiche, par exemple 7,38 s.",
			"Le chrono démarre puis se cache : compte dans ta tête !",
			"Appuie sur Espace pile au bon moment pour l'arrêter.",
			"3 manches, le chrono se cache de plus en plus tôt.",
			"On additionne tes écarts : le plus petit total gagne."],
			"Arrêter le chrono : Espace")
		St.draw_ready_row(h, my_ready, ready_ids, ids, t, not playing)
		if str(Net.mg_data.get("mode", "")) == "duel":
			St.draw_duel_banner(h)
		return
	if state == "count":
		UI.text(h, Vector2(640, 360), str(3 - int(t)), int(110 * (1.0 + (1.0 - fmod(t, 1.0)) * 0.3)), UI.WHITE, 16)
	if rnd >= 0:
		UI.ribbon(h, Vector2(640, 70), "Manche %d / %d" % [rnd + 1, ROUNDS], 26, Color("#8e6cf0"), UI.YELLOW)
		# temps à viser (toujours visible pendant la manche)
		var tr := Rect2(Vector2(36, 130), Vector2(250, 120))
		UI.panel(h, tr, UI.WHITE, Color("#ffe27a"), 24, 5)
		var fc := UI.face_center(tr)
		UI.text(h, Vector2(fc.x, fc.y - 26), "Arrête-le à", 22, UI.GREY, 0)
		UI.text(h, Vector2(fc.x, fc.y + 18), fmt(float(targets[rnd])) + " s", 48, Color("#e2483c"), 0)
	if state == "play" and ph == "target":
		var pop := 1.0 + maxf(0.0, 0.35 - ph_t) * 1.5
		var br := Rect2(Vector2(340, 250), Vector2(600, 210))
		h.draw_rect(Rect2(0, 0, 1280, 720), Color(0.1, 0.1, 0.3, 0.45))
		UI.panel(h, br, UI.WHITE, Color("#ffe27a"), 30, 6)
		var bc := UI.face_center(br)
		UI.text(h, Vector2(bc.x, bc.y - 52), "Arrête le chrono à", 30, UI.DARK, 0)
		UI.text(h, Vector2(bc.x, bc.y + 22), fmt(float(targets[rnd])) + " s", int(80 * pop), Color("#e2483c"), 10)
		UI.text(h, Vector2(bc.x, bc.y + 82), "Il se cachera au bout de %s s" % str(VISIBLE[rnd]).replace(".", ","), 20, UI.GREY, 0)
	_draw_players(h)
	if state == "play" and ph == "run" and playing and my_stop < 0.0 and cover >= 1.0:
		var hint := "ESPACE : STOP !"
		var hw := UI.text_width(hint, 22) + 40.0
		var hr := Rect2(Vector2(640 - hw / 2.0, 650), Vector2(hw, 42))
		UI.panel(h, hr, Color("#3d4470"), UI.WHITE, 21, 4)
		UI.text(h, UI.face_center(hr), hint, 22, UI.WHITE, 4)
	if state == "play" and ph == "reveal":
		_draw_reveal(h)
	if state == "play" and ph_t < 1.0 and ph == "run" and rnd == 0:
		UI.text(h, Vector2(640, 360), "GO !", int(120 * (1.0 + ph_t * 0.4)), Color(UI.YELLOW, 1.0 - ph_t), 18)
	if state == "over":
		h.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, minf(0.4, t)))
		UI.text(h, Vector2(640, 360), "TERMINÉ !", 96, UI.YELLOW, 16)


## Colonne de droite : chaque joueur, son total d'écarts et s'il a déjà arrêté son chrono.
func _draw_players(h: CanvasItem) -> void:
	if rnd < 0 or ph == "reveal":
		return
	var n := ids.size()
	var rh := minf(64.0, 470.0 / maxf(1.0, float(n)))
	var y0 := 130.0
	for i in n:
		var id: int = ids[i]
		var r := Rect2(Vector2(1280 - 36 - 250, y0 + i * (rh + 6.0)), Vector2(250, rh))
		var col := Net.color_of(id)
		UI.panel(h, r, col.lightened(0.1), UI.WHITE, 18, 4)
		var fy := UI.face_center(r).y
		UI.portrait(h, Vector2(r.position.x + 28, fy), minf(20.0, rh * 0.32), Net.color_idx(id))
		UI.text_left(h, Vector2(r.position.x + 56, fy), Net.name_of(id), 19, UI.WHITE, 5)
		var done := bool(stopped.get(id, false))
		var tag := Rect2(Vector2(r.end.x - 74, fy - 14), Vector2(62, 28))
		h.draw_style_box(UI.box(Color(1, 1, 1, 0.92) if done else Color(1, 1, 1, 0.35), Color(0, 0, 0, 0), 0, 14), tag)
		if done:
			UI.text(h, tag.get_center(), "STOP", 15, Color("#e2483c"), 0)
		else:
			for k in 3:
				var on := int(t * 3.0) % 3 == k
				h.draw_circle(tag.get_center() + Vector2((k - 1) * 12.0, 0), 4.0 if on else 3.0, Color(1, 1, 1, 0.95 if on else 0.6))


## Fin de manche : temps de chacun, écart, total ; classés du plus précis au moins précis.
func _draw_reveal(h: CanvasItem) -> void:
	var vals: Dictionary = results[-1]
	var tg := float(targets[rnd])
	var order := ids.duplicate()
	order.sort_custom(func(a, b): return absf(float(vals.get(a, 99.0)) - tg) < absf(float(vals.get(b, 99.0)) - tg))
	var n := order.size()
	var rh := minf(56.0, 360.0 / maxf(1.0, float(n)))
	var pw := 720.0
	var ph2 := 96.0 + n * (rh + 6.0) + 20.0
	var pr := Rect2(Vector2(640 - pw / 2.0, 360 - ph2 / 2.0 + 30.0), Vector2(pw, ph2))
	h.draw_rect(Rect2(0, 0, 1280, 720), Color(0.1, 0.1, 0.3, 0.5 * minf(1.0, ph_t * 3.0)))
	UI.panel(h, pr, UI.PAPER, UI.WHITE, 26, 6)
	UI.ribbon(h, Vector2(640, pr.position.y + 6), "Temps visé : %s s" % fmt(tg), 28, Color("#e2483c"), UI.WHITE)
	# en-têtes de colonnes
	var hy := pr.position.y + 66.0
	var x_time := pr.position.x + 400.0
	var x_gap := pr.position.x + 520.0
	var x_tot := pr.position.x + 640.0
	UI.text(h, Vector2(x_time, hy), "Temps", 16, UI.GREY, 0)
	UI.text(h, Vector2(x_gap, hy), "Écart", 16, UI.GREY, 0)
	UI.text(h, Vector2(x_tot, hy), "Total", 16, UI.GREY, 0)
	for i in n:
		var id: int = order[i]
		var appear := clampf((ph_t - 0.3 - i * 0.25) * 4.0, 0.0, 1.0)
		if appear <= 0.0:
			continue
		var v := float(vals.get(id, tg + LATE))
		var gap := v - tg
		var r := Rect2(Vector2(pr.position.x + 24, pr.position.y + 84 + i * (rh + 6.0)), Vector2(pw - 48, rh))
		var col := Net.color_of(id)
		UI.panel(h, r, Color(col.lightened(0.15), appear), Color(1, 1, 1, appear), 16, 4)
		var fy := UI.face_center(r).y
		UI.text(h, Vector2(r.position.x + 24, fy), "%d" % (i + 1), 22, Color(1, 1, 1, appear), 5)
		UI.portrait(h, Vector2(r.position.x + 64, fy), minf(19.0, rh * 0.34), Net.color_idx(id), UI.WHITE, Color(1, 1, 1, appear))
		UI.text_left(h, Vector2(r.position.x + 92, fy), Net.name_of(id), 20, Color(1, 1, 1, appear), 5)
		UI.text(h, Vector2(x_time, fy), fmt(v) + " s", 22, Color(1, 1, 1, appear), 5)
		var good := absf(gap) < 0.1
		var gtxt := ("%s%s" % ["+" if gap >= 0.0 else "-", fmt(absf(gap))]) if absf(gap) >= 0.005 else "PILE !"
		var pill := Rect2(Vector2(x_gap - 48, fy - 15), Vector2(96, 30))
		h.draw_style_box(UI.box(Color(Color("#ffe27a") if good else UI.WHITE, appear), Color(0, 0, 0, 0), 0, 15), pill)
		UI.text(h, pill.get_center(), gtxt, 19, Color(Color("#e2483c") if good else UI.DARK, appear), 0)
		UI.text(h, Vector2(x_tot, fy), fmt(float(totals.get(id, 0.0))), 22, Color(1, 1, 1, appear), 5)
