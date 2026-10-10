extends Node2D
## « Bombe chaude ! » (Hot Bob-omb, Mario Party) : les joueurs sont en cercle et se passent
## une bombe. Celui qui la tient quand elle explose est éliminé. Le dernier en jeu gagne.
## L'hôte décide de tout (qui tient la bombe, la mèche) ; les autres envoient « je lance ».

const CENTER := Vector2(640, 420)
const RAD := Vector2(330, 190)
const FLY := 0.32          # durée d'un lancer
const CATCH := 0.22        # temps avant de pouvoir relancer
const MAX_T := 100.0

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

# état partagé (envoyé par l'hôte)
var alive: Array = []
var holder := 0
var fly_from := 0
var fly_to := 0
var fly_t := -1.0          # temps écoulé depuis le lancer (-1 = pas en vol)
var fuse_left := 10.0
var fuse_total := 10.0
var pause_t := 0.0         # pause après une explosion
var out_t := {}            # id -> moment de l'élimination
var boom_at := Vector2.ZERO
var boom_t := -1.0
var last_boom_id := 0

# hôte
var catch_t := 0.0
var send_acc := 0.0
var ended := false
# local
var bot_wait := 0.6
var shake := 0.0
var parts: Array = []
var _tex := {}
var tick_acc := 0.0


func _ready() -> void:
	rng.seed = int(Net.mg_data.get("seed", 1))
	brng.randomize()
	for id in Net.mg_data.get("players", Net.players.keys()):
		if Net.players.has(id):
			ids.append(id)
	ids.sort()
	me_id = Net.my_id()
	playing = ids.has(me_id)
	alive = ids.duplicate()
	for id in ids:
		_tex["%d" % id] = UI.char_tex(Net.color_idx(id), "front")
		_tex["%d_hold" % id] = UI.char_tex(Net.color_idx(id), "jump")
		_tex["%d_hit" % id] = UI.char_tex(Net.color_idx(id), "hit")
	_tex["bomb"] = load("res://assets/tiles/bomb.png")
	_tex["bomb_w"] = load("res://assets/tiles/bomb_white.png")
	for n in ["bush1", "tree", "treePine", "foliage_020"]:
		_tex[n] = load("res://assets/deco/%s.png" % n)
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
			alive.erase(id)


# ------------------------------------------------------------------ hôte
func _new_round() -> void:
	fuse_total = rng.randf_range(7.0, 13.0) if alive.size() > 2 else rng.randf_range(6.0, 10.0)
	fuse_left = fuse_total
	holder = alive[rng.randi() % alive.size()]
	fly_t = -1.0
	catch_t = CATCH
	_broadcast()


func _neighbor(of: int, dir: int) -> int:
	var order := alive.duplicate()
	order.sort_custom(func(a, b): return ids.find(a) < ids.find(b))
	var i := order.find(of)
	if i < 0 or order.size() < 2:
		return of
	return order[(i + dir + order.size()) % order.size()]


func _on_mg_msg(from_id: int, d: Dictionary) -> void:
	if not Net.is_host() or state != "play" or pause_t > 0.0:
		return
	if d.has("toss") and from_id == holder and fly_t < 0.0 and catch_t <= 0.0 and alive.size() > 1:
		var dir := 1 if int(d["toss"]) > 0 else -1
		fly_from = holder
		fly_to = _neighbor(holder, dir)
		fly_t = 0.0
		holder = 0
		_broadcast()


func _host_step(dt: float) -> void:
	if ended:
		return
	if pause_t > 0.0:
		pause_t -= dt
		if pause_t <= 0.0:
			if alive.size() <= 1:
				_finish()
				return
			_new_round()
		return
	catch_t -= dt
	fuse_left -= dt
	if fly_t >= 0.0:
		fly_t += dt
		if fly_t >= FLY:
			holder = fly_to
			fly_t = -1.0
			catch_t = CATCH
			_broadcast()
	if fuse_left <= 0.0:
		var victim := holder if holder != 0 else fly_to
		alive.erase(victim)
		out_t[victim] = play_t
		last_boom_id = victim
		holder = 0
		fly_t = -1.0
		pause_t = 2.4
		_broadcast(true)
		return
	if play_t > MAX_T:
		_finish()
		return
	send_acc += dt
	if send_acc > 0.25:
		send_acc = 0.0
		_broadcast()


func _broadcast(boom := false) -> void:
	Net.mg_broadcast({"alive": alive, "holder": holder, "from": fly_from, "to": fly_to, "fly": fly_t,
		"fuse": fuse_left, "total": fuse_total, "pause": pause_t, "out": out_t, "boom": last_boom_id if boom else 0})


func _finish() -> void:
	if ended:
		return
	ended = true
	var sc := {}
	for id in ids:
		if alive.has(id):
			sc[id] = [1000.0, "Survivant !"]
		else:
			sc[id] = [float(out_t.get(id, 0.0)), "Explosé à %.1f s" % float(out_t.get(id, 0.0))]
	Net.mg_end_with_scores(sc)


func _on_mg_state(d: Dictionary) -> void:
	if d.has("holder"):
		var prev_holder := holder
		alive = d["alive"]
		holder = int(d["holder"])
		fly_from = int(d["from"])
		fly_to = int(d["to"])
		var nf := float(d["fly"])
		if nf >= 0.0 and fly_t < 0.0:
			Sfx.play("whoosh", -4.0)
		if not Net.is_host():
			fly_t = nf
			fuse_left = float(d["fuse"])
			pause_t = float(d["pause"])
		fuse_total = float(d["total"])
		out_t = d["out"]
		if holder != 0 and holder != prev_holder:
			Sfx.play("ui_drop", -6.0)
		if int(d.get("boom", 0)) != 0:
			_explode(int(d["boom"]))


func _explode(victim: int) -> void:
	boom_at = _seat(victim) + Vector2(0, -70)
	boom_t = 0.0
	shake = 1.0
	Sfx.play("hurt", 2.0, 0.0)
	Sfx.play("bump", 0.0, 0.0)
	for i in 30:
		var a := randf() * TAU
		parts.append({"p": boom_at, "v": Vector2(cos(a), sin(a)) * randf_range(150, 520), "t": 0.0, "c": [Color("#ffd23f"), Color("#ff7b2e"), Color("#f04650"), Color.WHITE][i % 4], "r": randf_range(6, 16)})


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
					_new_round()
		"play":
			play_t += delta
			if Net.is_host():
				_host_step(delta)
			else:
				if pause_t > 0.0:
					pause_t -= delta
				else:
					fuse_left -= delta
					if fly_t >= 0.0:
						fly_t = minf(fly_t + delta, FLY)
			_my_input(delta)
			# tic-tac de plus en plus rapide
			if pause_t <= 0.0 and holder != 0 or fly_t >= 0.0:
				var rate := lerpf(0.7, 0.12, clampf(1.0 - fuse_left / maxf(1.0, fuse_total), 0.0, 1.0))
				tick_acc += delta
				if tick_acc >= rate:
					tick_acc = 0.0
					Sfx.play("ui_tick", -8.0, 0.0)
	if boom_t >= 0.0:
		boom_t += delta
	for p in parts:
		p["t"] = float(p["t"]) + delta
		p["p"] = (p["p"] as Vector2) + (p["v"] as Vector2) * delta
		p["v"] = (p["v"] as Vector2) * (1.0 - 2.0 * delta) + Vector2(0, 300) * delta
	parts = parts.filter(func(p): return float(p["t"]) < 1.0)
	shake = maxf(0.0, shake - delta * 2.5)
	view.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * 16.0
	view.queue_redraw()
	hud.queue_redraw()


func _my_input(dt: float) -> void:
	if not playing or holder != me_id or fly_t >= 0.0 or pause_t > 0.0:
		bot_wait = brng.randf_range(0.35, 1.3)
		return
	var dir := 0
	if Net.autotest != "":
		bot_wait -= dt
		if bot_wait <= 0.0:
			dir = 1 if brng.randf() < 0.5 else -1
			bot_wait = 99.0
	else:
		if Input.is_action_just_pressed("left"):
			dir = -1
		elif Input.is_action_just_pressed("right") or Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("push"):
			dir = 1
	if dir != 0:
		Net.mg_to_host({"toss": dir})


# ------------------------------------------------------------------ dessin
func _seat(id: int) -> Vector2:
	var i := ids.find(id)
	var n := maxi(1, ids.size())
	var a := PI / 2.0 + TAU * float(i) / float(n)
	return CENTER + Vector2(cos(a) * RAD.x, sin(a) * RAD.y)


func _bomb_pos() -> Vector2:
	if fly_t >= 0.0:
		var u := clampf(fly_t / FLY, 0.0, 1.0)
		var a := _seat(fly_from) + Vector2(0, -150)
		var b := _seat(fly_to) + Vector2(0, -150)
		return a.lerp(b, u) + Vector2(0, -sin(u * PI) * 120.0)
	if holder != 0:
		return _seat(holder) + Vector2(0, -150)
	return CENTER + Vector2(0, -40)


func _draw_view() -> void:
	var c := view
	c.draw_rect(Rect2(-40, -40, 1360, 800), Color("#bfeaf5"))
	# collines et arbres au fond
	c.draw_circle(Vector2(200, 420), 420, Color("#a7d870"))
	c.draw_circle(Vector2(1100, 440), 460, Color("#9bd065"))
	c.draw_rect(Rect2(-40, 300, 1360, 460), Color("#a6dc62"))
	for k in 9:
		var tx: Texture2D = _tex["tree" if k % 3 != 1 else "treePine"]
		var x := 60.0 + k * 150.0
		var s := 0.42 + (k % 2) * 0.08
		c.draw_set_transform(Vector2(x, 300 + (k % 2) * 10), 0.0, Vector2(s, s))
		c.draw_texture(tx, Vector2(-tx.get_width() / 2.0, -tx.get_height()))
		c.draw_set_transform(Vector2.ZERO)
	# grand tapis rond
	_ell(c, CENTER + Vector2(0, 30), RAD + Vector2(120, 80), Color(0, 0, 0, 0.08))
	_ell(c, CENTER + Vector2(0, 14), RAD + Vector2(110, 70), Color("#e8b56a"))
	_ell(c, CENTER, RAD + Vector2(110, 70), Color("#ffd889"))
	_ell(c, CENTER, RAD + Vector2(60, 36), Color("#ffe7b0"))
	for k in 16:
		var a := TAU * k / 16.0
		var p := CENTER + Vector2(cos(a) * (RAD.x + 85), sin(a) * (RAD.y + 53))
		c.draw_circle(p, 9.0, Color("#ff9a5a") if k % 2 == 0 else Color("#ffffff"))
	# joueurs (de l'arrière vers l'avant)
	var order := ids.duplicate()
	order.sort_custom(func(a, b): return _seat(a).y < _seat(b).y)
	for id in order:
		var p := _seat(id)
		var dead: bool = not alive.has(id)
		_ell(c, p + Vector2(0, 4), Vector2(46, 14), Color(0, 0, 0, 0.16))
		var tx: Texture2D = _tex["%d_hit" % id] if dead else (_tex["%d_hold" % id] if holder == id else _tex["%d" % id])
		var bob := absf(sin(t * 8.0 + id)) * 6.0 if holder == id else 0.0
		c.draw_set_transform(p + Vector2(0, -bob), 0.0, Vector2(0.5, 0.5))
		c.draw_texture(tx, Vector2(-128, -256), Color(1, 1, 1, 0.45) if dead else Color.WHITE)
		c.draw_set_transform(Vector2.ZERO)
		var nm := "TOI" if id == me_id and playing else Net.name_of(id)
		UI.text(c, p + Vector2(0, 26), nm, 20 if id == me_id else 17, UI.YELLOW if id == me_id and playing else Net.color_of(id), 6)
	# la bombe
	if (holder != 0 or fly_t >= 0.0) and pause_t <= 0.0:
		var bp := _bomb_pos()
		var urg := clampf(1.0 - fuse_left / maxf(1.0, fuse_total), 0.0, 1.0)
		var flash := sin(t * lerpf(6.0, 40.0, urg)) > 0.3 and urg > 0.35
		var s := 0.7 + 0.08 * sin(t * 12.0) * urg
		c.draw_set_transform(bp, sin(t * 3.0) * 0.12, Vector2(s, s))
		c.draw_texture(_tex["bomb_w"] if flash else _tex["bomb"], Vector2(-64, -70), Color("#ff6b5a") if flash else Color("#4b4660"))
		c.draw_set_transform(Vector2.ZERO)
		# étincelle de la mèche
		var sp := bp + Vector2(-34, -40) * s
		for k in 5:
			var a := t * 20.0 + k * 1.3
			c.draw_line(sp, sp + Vector2(cos(a), sin(a)) * randf_range(8, 18), Color("#ffd23f"), 3.0)
		c.draw_circle(sp, 6.0, Color("#fff3a0"))
	# explosion
	if boom_t >= 0.0 and boom_t < 1.2:
		var k := boom_t / 1.2
		c.draw_circle(boom_at, 40.0 + k * 220.0, Color(1, 0.85, 0.3, 0.7 * (1.0 - k)))
		c.draw_circle(boom_at, 20.0 + k * 140.0, Color(1, 1, 1, 0.8 * (1.0 - k)))
		UI.text(c, boom_at + Vector2(0, -30 - k * 40.0), "BOUM !", int(60 + k * 30), Color(UI.RED, 1.0 - k * k), 10)
	for p in parts:
		var q: float = float(p["t"])
		c.draw_circle(p["p"], float(p["r"]) * (1.0 - q), Color(p["c"], 1.0 - q))


func _ell(c: CanvasItem, ctr: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 48:
		var a := TAU * k / 48.0
		pts.append(ctr + Vector2(cos(a) * r.x, sin(a) * r.y))
	c.draw_colored_polygon(pts, col)


# ------------------------------------------------------------------ HUD
func _draw_hud() -> void:
	var h := hud
	var St := preload("res://minigames/stage.gd")
	if state == "intro":
		St.draw_intro(h, "Bombe chaude !", [
			"Tout le monde est assis en cercle... et une bombe circule !",
			"Si tu l'as, lance-la vite à ton voisin de gauche ou de droite.",
			"Celui qui la tient quand elle explose est éliminé.",
			"Le dernier encore en jeu gagne !"],
			"Lancer à gauche : Q / ←   ·   Lancer à droite : D / → / Espace")
		St.draw_ready_row(h, my_ready, ready_ids, ids, t, not playing)
		if str(Net.mg_data.get("mode", "")) == "duel":
			St.draw_duel_banner(h)
		return
	var outd := {}
	for id in ids:
		if not alive.has(id):
			outd[id] = true
	St.draw_heads(h, ids, outd)
	if state == "count":
		UI.text(h, Vector2(640, 360), str(3 - int(t)), int(110 * (1.0 + (1.0 - fmod(t, 1.0)) * 0.3)), UI.WHITE, 16)
	elif state == "play" and t < 1.0:
		UI.text(h, Vector2(640, 360), "GO !", int(120 * (1.0 + t * 0.4)), Color(UI.YELLOW, 1.0 - t), 18)
	if state == "play" and playing and alive.has(me_id) and holder == me_id and fly_t < 0.0 and pause_t <= 0.0:
		var k := 1.0 + 0.06 * sin(t * 14.0)
		var r := Rect2(Vector2(640 - 260 * k, 120), Vector2(520 * k, 64))
		UI.panel(h, r, Color("#ff6f6f"), UI.WHITE, 30, 5)
		UI.text(h, UI.face_center(r), "LANCE-LA !   ← Q   ·   D →", int(30 * k), UI.WHITE, 7)
	if playing and not alive.has(me_id) and state == "play":
		var msg := "BOUM ! Tu es éliminé..."
		var mw := UI.text_width(msg, 26) + 50.0
		UI.panel(h, Rect2(Vector2(640 - mw / 2.0, 646), Vector2(mw, 50)), UI.WHITE, Color("#ffd0d0"), 20, 4)
		UI.text(h, Vector2(640, 671), msg, 26, UI.RED, 0)
	if state == "over":
		h.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, minf(0.4, t)))
		UI.text(h, Vector2(640, 360), "TERMINÉ !", 96, UI.YELLOW, 16)
