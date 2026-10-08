extends "res://minigames/stage.gd"
## « Défilé de bûches ! » (Lumber Tumble) : sur un pont suspendu dans le ciel, des bûches dévalent
## des toboggans aux deux bouts puis roulent sur le pont, une souris court dessus.
## On saute par-dessus, ou on rebondit sur la souris. Une bûche qui te touche t'envoie valser.
## À mi-partie, des bûches à PIQUES cassent des planches. Le dernier sur le pont gagne.
## Bûches et planches cassées sont calculées à partir de la graine : identiques chez tout le monde.

const BY := 500.0            # dessus des planches
const NP := 15               # nombre de planches
const X0 := 160.0            # bord gauche du pont
const X1 := X0 + NP * 64.0   # bord droit (1120)
const CHUTE := 0.6           # durée de la descente du toboggan
const SPIKE_AT := 25.0       # arrivée des bûches à piques
const FAST_AT := 42.0        # ça accélère
const MAX_HOLES := 5
const GRAV := 2000.0
const WOOD := Color("#de7e4f")
const WOOD_DARK := Color("#bd6341")
const WOOD_LIGHT := Color("#fa9f72")

var logs: Array = []         # {id, t0, dir, r, v, spiky}
var planks: Array = []       # {sprite, t_break, broken, vy, spin}
var plank_bodies: Array = []
var log_layer: Node2D
var back_layer: Node2D
var hit_cd: Dictionary = {}
var squash_t: Dictionary = {}
var landed: Dictionary = {}
var mouse_tex := []
var slime_tex := []
var banner_t := 0.0
var banner_txt := ""
var banner_col := UI.RED
var level := 0
var bot_goal := 640.0
var bot_goal_t := 0.0


func _setup() -> void:
	title = "Défilé de bûches !"
	rules = "Des bûches dévalent les toboggans et roulent sur le pont.\nSaute par-dessus, ou rebondis sur la souris qui court dessus !\nUne bûche te touche : tu valses. Attention aux bords !\nBûches à PIQUES : elles cassent les planches qui rougissent.\nLe dernier debout sur le pont gagne !"
	duration = 60.0
	for i in 8:
		spawn_points.append(Vector2(380 + i * 74, BY))
	mouse_tex = [load("res://assets/enemies/mouse_walk_a.png"), load("res://assets/enemies/mouse_walk_b.png")]
	slime_tex = [load("res://assets/enemies/slime_spike_walk_a.png"), load("res://assets/enemies/slime_spike_walk_b.png")]


# ------------------------------------------------------------------ génération (même graine = même partie)
func _pick_radius(p: float) -> float:
	var w := {34.0: 1.0 - p * 0.6, 46.0: 1.0, 62.0: maxf(0.0, (p - 0.15) * 1.4)}
	var total := 0.0
	for k in w:
		total += float(w[k])
	var r := rng.randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return float(k)
	return 46.0


func _add_log(t0: float, dir: int, r: float, v: float, spiky: bool) -> void:
	# pas de chevauchement avec la bûche précédente du même côté
	for i in range(logs.size() - 1, -1, -1):
		var o: Dictionary = logs[i]
		if int(o["dir"]) == dir:
			var min_t := float(o["t0"]) + maxf(CHUTE + 0.3, (float(o["r"]) + r + 90.0) / float(o["v"]))
			t0 = maxf(t0, min_t)
			break
	if t0 > duration - 1.0:
		return
	logs.append({"id": logs.size(), "t0": t0, "dir": dir, "r": r, "v": v, "spiky": spiky})


func _gen_logs() -> void:
	var tt := 1.0
	var last_dir := 0
	var same := 0
	while tt < duration - 1.5:
		var p := tt / duration
		var dir := 1 if rng.randf() < 0.5 else -1
		if dir == last_dir:
			same += 1
			if same >= 2:
				dir = -dir
				same = 0
		else:
			same = 0
		last_dir = dir
		var fast := 1.12 if tt >= FAST_AT else 1.0
		var v := lerpf(250.0, 400.0, p) * fast * rng.randf_range(0.96, 1.04)
		var spiky := tt >= SPIKE_AT and rng.randf() < lerpf(0.4, 0.6, (tt - SPIKE_AT) / (duration - SPIKE_AT))
		_add_log(tt, dir, _pick_radius(p), v, spiky)
		if tt > 14.0 and rng.randf() < lerpf(0.12, 0.35, p):
			_add_log(tt + rng.randf_range(0.0, 0.5), -dir, minf(_pick_radius(p), 46.0), v * rng.randf_range(0.9, 1.0), spiky and rng.randf() < 0.5)
		tt += lerpf(2.5, 1.35, p) * (0.88 if tt >= FAST_AT else 1.0) * rng.randf_range(0.85, 1.15)
	logs.sort_custom(func(a, b): return float(a["t0"]) < float(b["t0"]))


func _land(L: Dictionary) -> Vector2:
	var r: float = L["r"]
	return Vector2(X0 + r, BY - r) if int(L["dir"]) > 0 else Vector2(X1 - r, BY - r)


func _chute_top(dir: int) -> Vector2:
	return Vector2(-70, 250) if dir > 0 else Vector2(1350, 250)


func _chute_start(L: Dictionary) -> Vector2:
	var dir: int = L["dir"]
	var a := _chute_top(dir)
	var b := Vector2(X0, BY) if dir > 0 else Vector2(X1, BY)
	var d := (b - a).normalized()
	var n := Vector2(d.y, -d.x)
	if n.y > 0.0:
		n = -n
	return a + n * float(L["r"])


## Moment où la bûche passe au-dessus de x (sur le pont).
func _time_over(L: Dictionary, x: float) -> float:
	return float(L["t0"]) + CHUTE + absf(x - _land(L).x) / float(L["v"])


func _gen_breaks() -> void:
	var holes := 0
	var marked := {}
	var last_break := -10.0
	for L in logs:
		if not L["spiky"] or holes >= MAX_HOLES:
			continue
		var want := 1 if rng.randf() < 0.6 else 2
		var tries := 0
		while want > 0 and tries < 14 and holes < MAX_HOLES:
			tries += 1
			var i := rng.randi_range(1, NP - 2)
			if marked.has(i) or marked.has(i - 1) or marked.has(i + 1):
				continue
			var tb := _time_over(L, X0 + (i + 0.5) * T)
			if tb < last_break + 4.0:
				continue
			planks[i]["t_break"] = tb
			last_break = tb
			marked[i] = true
			holes += 1
			want -= 1


## [phase, centre, angle] : 0 pas encore là, 1 toboggan, 2 sur le pont, 3 tombe, 4 disparue.
func _log_at(L: Dictionary, tt: float) -> Array:
	var dt := tt - float(L["t0"])
	if dt < 0.0:
		return [0, Vector2.ZERO, 0.0]
	var dir: int = L["dir"]
	var r: float = L["r"]
	var v: float = L["v"]
	var start := _chute_start(L)
	var land := _land(L)
	var chute_len := start.distance_to(land)
	if dt < CHUTE:
		var u := dt / CHUTE
		var c := start.lerp(land, u * u)
		return [1, c, dir * chute_len * u * u / r]
	var d := dt - CHUTE
	var x := land.x + dir * v * d
	var travel := absf(x - land.x)
	var span := (X1 - X0) - r
	var ang := dir * (chute_len + travel) / r
	if travel <= span:
		var hop := 0.0
		if d < 0.3:
			hop = sin(d / 0.3 * PI) * 16.0
		return [2, Vector2(x, land.y - hop), ang]
	var tf := (travel - span) / v
	var y := land.y + 0.5 * GRAV * tf * tf
	if y > 900.0:
		return [4, Vector2(x, y), ang]
	return [3, Vector2(x, y), ang]


# ------------------------------------------------------------------ décor
func _build_level() -> void:
	_gen_logs()
	back_layer = Node2D.new()
	back_layer.z_index = -1
	world.add_child(back_layer)
	back_layer.draw.connect(_draw_back)
	for i in NP:
		var s := tile("bridge", Vector2(X0 + i * T, BY - 2.0))
		planks.append({"sprite": s, "t_break": INF, "broken": false, "vy": 0.0, "spin": 0.0})
	_gen_breaks()
	_rebuild_floor()
	log_layer = Node2D.new()
	log_layer.z_index = 5
	world.add_child(log_layer)
	log_layer.draw.connect(_draw_logs)


func _rebuild_floor() -> void:
	for b in plank_bodies:
		(b as Node).queue_free()
	plank_bodies.clear()
	var i := 0
	while i < NP:
		if planks[i]["broken"]:
			i += 1
			continue
		var j := i
		while j + 1 < NP and not planks[j + 1]["broken"]:
			j += 1
		plank_bodies.append(solid(Rect2(X0 + i * T, BY, (j - i + 1) * T, 24.0)))
		i = j + 1


func _hole_at(x: float) -> bool:
	if x < X0 or x >= X1:
		return true
	return bool(planks[int((x - X0) / T)]["broken"])


func _on_start() -> void:
	if me:
		me.kill_rect = Rect2(-400, -2000, 2080, 2780)


# ------------------------------------------------------------------ boucle
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state != "play":
		return
	# planches cassées par les bûches à piques (même moment chez tout le monde)
	var changed := false
	for i in NP:
		var pl: Dictionary = planks[i]
		if not pl["broken"] and play_t >= float(pl["t_break"]):
			pl["broken"] = true
			pl["vy"] = -120.0
			pl["spin"] = randf_range(-4.0, 4.0)
			changed = true
			var cx := X0 + (i + 0.5) * T
			fx.dust(Vector2(cx, BY + 4.0), 6, 1.2)
			fx.popup(Vector2(cx, BY + 40.0), "CRAC !", UI.DARK)
			Sfx.play("hurt", -10.0, 0.2)
	if changed:
		_rebuild_floor()
	for id in hit_cd.keys():
		hit_cd[id] = float(hit_cd[id]) - delta
		if float(hit_cd[id]) <= 0.0:
			hit_cd.erase(id)
	if me == null or me.dead:
		return
	var godmode := Net.autotest != "" and OS.get_environment("GODMODE") != ""
	for L in logs:
		var st := _log_at(L, play_t)
		var ph: int = st[0]
		if ph == 0:
			break
		if godmode:
			continue
		if ph != 1 and ph != 2:
			continue
		var id: int = L["id"]
		if ph == 2 and not landed.has(id):
			landed[id] = true
			fx.dust(Vector2((st[1] as Vector2).x, BY), 5, 1.4)
			Sfx.play("bump", -12.0, 0.2)
		if hit_cd.has(id):
			continue
		var touch := _touch(st[1], float(L["r"]), 42.0 if L["spiky"] else 34.0)
		if touch == 0:
			continue
		var c: Vector2 = st[1]
		var kx := signf(me.position.x - c.x)
		if kx == 0.0:
			kx = float(L["dir"])
		if touch == 2 and not L["spiky"]:
			# rebond sur la souris
			me.velocity.y = -900.0
			me.air_jumps = 1
			me.jump_cut_ok = false
			me.squash = Vector2(1.3, 0.75)
			squash_t[id] = 0.35
			hit_cd[id] = 0.3
			Sfx.play("bump", -3.0)
			fx.stars(c + Vector2(0, -float(L["r"]) - 20.0), 4)
		else:
			var strong: bool = L["spiky"]
			me.receive_hit(0, Vector2(kx * (740.0 if strong else 600.0), -620.0 if touch == 2 else -520.0), 0)
			hit_cd[id] = 0.6
			fx.popup(me.position + Vector2(0, -90), "AÏE !" if strong else "BOING !", me.color())
	if me.is_bot:
		_bot()


## 0 = rien, 1 = touché sur le côté, 2 = arrivé par-dessus
func _touch(c: Vector2, r: float, rider_h: float) -> int:
	var pr := Rect2(me.position + Vector2(-18, -56), Vector2(36, 52))
	var q := Vector2(clampf(c.x, pr.position.x, pr.end.x), clampf(c.y, pr.position.y, pr.end.y))
	var on_log := q.distance_to(c) < r
	var rider := pr.intersects(Rect2(c.x - 20.0, c.y - r - rider_h + 4.0, 40.0, rider_h))
	if not on_log and not rider:
		return 0
	if me.velocity.y >= 0.0 and me.position.y < c.y - r * 0.5 - (rider_h * 0.4 if rider else 0.0):
		return 2
	return 1


func _bot() -> void:
	bot_goal_t -= get_physics_process_delta_time()
	if bot_goal_t <= 0.0 or _hole_at(bot_goal):
		bot_goal_t = randf_range(1.5, 3.5)
		for k in 10:
			bot_goal = randf_range(X0 + 200.0, X1 - 200.0)
			if not _hole_at(bot_goal) and not _hole_at(bot_goal - 30.0) and not _hole_at(bot_goal + 30.0):
				break
	me.set_meta("goal_x", bot_goal)
	var jump := false
	var dx := signf(bot_goal - me.position.x)
	if me.is_on_floor() and dx != 0.0 and _hole_at(me.position.x + dx * 46.0):
		jump = true
	for L in logs:
		var st := _log_at(L, play_t)
		if int(st[0]) == 0:
			break
		if int(st[0]) != 2:
			continue
		var c: Vector2 = st[1]
		var rel := (me.position.x - c.x) * float(L["dir"])
		if rel <= 0.0:
			continue
		var ttc := (rel - float(L["r"]) - 18.0) / float(L["v"])
		if ttc < 0.3 and ttc > -0.1:
			if me.is_on_floor():
				jump = true
			elif float(L["r"]) > 50.0 and me.velocity.y > -150.0 and me.air_jumps > 0:
				jump = true
	me.set_meta("jump_now", jump)


func _process(delta: float) -> void:
	super._process(delta)
	banner_t = maxf(0.0, banner_t - delta)
	if state == "play":
		if level == 0 and play_t >= SPIKE_AT:
			level = 1
			_banner("BÛCHES À PIQUES !", UI.RED)
		elif level == 1 and play_t >= FAST_AT:
			level = 2
			_banner("ÇA ACCÉLÈRE !", Color("#ff8c28"))
	for id in squash_t.keys():
		squash_t[id] = float(squash_t[id]) - delta
		if float(squash_t[id]) <= 0.0:
			squash_t.erase(id)
	for i in NP:
		var pl: Dictionary = planks[i]
		var s0: Sprite2D = pl["sprite"]
		if not pl["broken"]:
			var left := float(pl["t_break"]) - play_t
			if state == "play" and left < 1.3:
				var k := 1.0 - maxf(0.0, left) / 1.3
				s0.modulate = Color(1, 1, 1).lerp(Color(1.0, 0.55, 0.5), k)
				s0.position = Vector2(X0 + i * T + randf_range(-2.0, 2.0) * k, BY - 2.0 + randf_range(-1.5, 1.5) * k)
			continue
		if pl["broken"]:
			var s: Sprite2D = pl["sprite"]
			if s.visible:
				pl["vy"] = float(pl["vy"]) + 1800.0 * delta
				s.position.y += float(pl["vy"]) * delta
				s.rotation += float(pl["spin"]) * delta
				if s.position.y > 820.0:
					s.visible = false
	log_layer.queue_redraw()


func _banner(txt: String, col: Color) -> void:
	banner_txt = txt
	banner_col = col
	banner_t = 2.0
	Sfx.play("jump2", -2.0)
	fx.shake(8.0)


# ------------------------------------------------------------------ dessin
func _draw_chute(dir: int) -> void:
	var a := _chute_top(dir)
	var b := Vector2(X0 + 4.0, BY) if dir > 0 else Vector2(X1 - 4.0, BY)
	var d := (b - a).normalized()
	var down := Vector2(-d.y, d.x)
	if down.y < 0.0:
		down = -down
	# poteaux sous le toboggan
	for k in [0.35, 0.8]:
		var p: Vector2 = a.lerp(b, k)
		back_layer.draw_rect(Rect2(p.x - 9.0, p.y, 18.0, 760.0 - p.y), UI.DARK)
		back_layer.draw_rect(Rect2(p.x - 5.0, p.y, 10.0, 760.0 - p.y), WOOD_DARK)
	var th := 26.0
	var poly := PackedVector2Array([a - d * 200.0, b, b + down * th, a - d * 200.0 + down * th])
	back_layer.draw_colored_polygon(poly, WOOD)
	back_layer.draw_polyline(PackedVector2Array([a - d * 200.0, b, b + down * th, a - d * 200.0 + down * th, a - d * 200.0]), UI.DARK, 5.0)
	back_layer.draw_line(a - d * 200.0 + down * 6.0, b + down * 6.0, WOOD_LIGHT, 4.0)
	for k in 7:
		var p: Vector2 = a.lerp(b, (k + 0.5) / 7.0)
		back_layer.draw_line(p + down * 3.0, p + down * (th - 3.0), WOOD_DARK, 3.0)
	# rebord
	back_layer.draw_line(a - d * 200.0 - down * 12.0, b - down * 12.0 - d * 40.0, UI.DARK, 7.0)
	back_layer.draw_line(a - d * 200.0 - down * 12.0, b - down * 12.0 - d * 40.0, WOOD_DARK, 3.0)


func _draw_back() -> void:
	# piliers aux deux bouts + corde sous les planches
	for x in [X0 - 4.0, X1 - 16.0]:
		back_layer.draw_rect(Rect2(x - 4.0, BY + 6.0, 28.0, 260.0), UI.DARK)
		back_layer.draw_rect(Rect2(x, BY + 6.0, 20.0, 260.0), WOOD_DARK)
		back_layer.draw_rect(Rect2(x + 3.0, BY + 6.0, 5.0, 260.0), WOOD)
	var pts := PackedVector2Array()
	for k in 25:
		var u := k / 24.0
		pts.append(Vector2(lerpf(X0, X1, u), BY + 30.0 + sin(u * PI) * 26.0))
	for k in NP + 1:
		var x := X0 + k * T
		var u := k / float(NP)
		back_layer.draw_line(Vector2(x, BY + 20.0), Vector2(x, BY + 30.0 + sin(u * PI) * 26.0), Color("#8a5a3c"), 3.0)
	back_layer.draw_polyline(pts, UI.DARK, 7.0)
	back_layer.draw_polyline(pts, Color("#c99a6b"), 3.0)
	_draw_chute(1)
	_draw_chute(-1)


func _draw_logs() -> void:
	var tt := play_t if state != "intro" else 0.0
	for L in logs:
		var st := _log_at(L, tt)
		var ph: int = st[0]
		var until := float(L["t0"]) - tt
		if state == "play" and until < 0.75 and until > -CHUTE * 0.6:
			_draw_warning(int(L["dir"]), bool(L["spiky"]))
		if ph == 0:
			if until > 0.75:
				break
			continue
		if ph == 4:
			continue
		var c: Vector2 = st[1]
		var ang: float = st[2]
		var r: float = L["r"]
		var spiky: bool = L["spiky"]
		if ph == 2:
			log_layer.draw_set_transform(Vector2(c.x, BY + 2.0), 0.0, Vector2(1.0, 0.16))
			log_layer.draw_circle(Vector2.ZERO, r * 0.9, Color(UI.DARK, 0.22))
			log_layer.draw_set_transform(Vector2.ZERO)
		if spiky:
			for k in 8:
				var a := ang + k * TAU / 8.0
				var tip := c + Vector2(cos(a), sin(a)) * (r + 17.0)
				var b1 := c + Vector2(cos(a - 0.24), sin(a - 0.24)) * (r - 4.0)
				var b2 := c + Vector2(cos(a + 0.24), sin(a + 0.24)) * (r - 4.0)
				var out := PackedVector2Array([b1, tip, b2])
				log_layer.draw_polyline(PackedVector2Array([b1, tip, b2, b1]), UI.DARK, 7.0)
				log_layer.draw_colored_polygon(out, Color("#c8ccd8"))
		log_layer.draw_circle(c, r + 4.5, UI.DARK)
		log_layer.draw_circle(c, r, WOOD)
		log_layer.draw_arc(c, r * 0.84, PI * 1.05, PI * 1.5, 10, WOOD_LIGHT, maxf(3.0, r * 0.08))
		log_layer.draw_circle(c, r * 0.68, WOOD_DARK)
		log_layer.draw_circle(c, r * 0.58, WOOD)
		log_layer.draw_circle(c, r * 0.32, WOOD_DARK)
		log_layer.draw_circle(c, r * 0.22, WOOD)
		# fente qui tourne (on voit la bûche rouler)
		var dv := Vector2(cos(ang), sin(ang))
		log_layer.draw_line(c + dv * r * 0.12, c + dv * r * 0.9, UI.DARK, 3.5)
		log_layer.draw_circle(c - dv * r * 0.45, r * 0.07, WOOD_DARK)
		# la souris (ou le slime à pique) qui court dessus
		var frames: Array = slime_tex if spiky else mouse_tex
		var sq := 0.5 if squash_t.has(L["id"]) else 1.0
		var sc := 0.36
		var feet := c + Vector2(0, -r + 3.0)
		log_layer.draw_set_transform(feet, 0.0, Vector2(-sc * float(L["dir"]), sc * sq))
		log_layer.draw_texture(frames[int(tt * 10.0 + float(L["id"])) % 2], Vector2(-64, -128))
		log_layer.draw_set_transform(Vector2.ZERO)


func _draw_warning(dir: int, spiky: bool) -> void:
	var p := Vector2(X0 + 4.0, BY - 230.0) if dir > 0 else Vector2(X1 - 4.0, BY - 230.0)
	var k := 1.0 + 0.15 * sin(play_t * 18.0)
	log_layer.draw_circle(p, 27.0 * k, UI.DARK)
	log_layer.draw_circle(p, 22.0 * k, UI.WHITE if not spiky else Color("#ffd2d2"))
	UI.text(log_layer, p + Vector2(0, -2), "!", int(34 * k), UI.RED, 0)
	var tip := p + Vector2(dir * 44.0, 26.0)
	log_layer.draw_line(p + Vector2(dir * 24.0, 12.0), tip, UI.DARK, 6.0)


func _draw_extra_hud() -> void:
	draw_timer()
	if state == "intro":
		return
	# niveau : bûches normales -> piques -> rapide
	var lr := Rect2(Vector2(24, 80), Vector2(120, 40))
	hud.draw_style_box(UI.box(UI.WHITE, UI.DARK, 4, 14), lr)
	for i in 3:
		var cc := lr.position + Vector2(24 + i * 36, 20)
		hud.draw_circle(cc, 12.0, UI.DARK)
		hud.draw_circle(cc, 9.0, (Color("#ff8c28").lerp(UI.RED, i / 2.0)) if i <= level else Color("#d6d9e6"))
	if banner_t > 0.0:
		var k := 1.0 - banner_t / 2.0
		var s := 1.0 + (1.0 - minf(1.0, k * 5.0)) * 0.6
		UI.text(hud, Vector2(640, 230), banner_txt, int(68 * s), Color(banner_col, minf(1.0, banner_t * 2.0)), 16)
