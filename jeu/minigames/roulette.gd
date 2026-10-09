extends Node2D
## « Roulette-marteau ! » (Spin and Bear It, Mario Party: Island Tour) : une grande roue avec
## autant de places que de joueurs. Chacun choisit sa place, une flèche désigne au hasard celui
## qui fait tourner la roue. Quand elle s'arrête, celui qui se trouve devant le marteau est écrasé.
## Une place de moins à chaque manche. Le dernier qui n'a pas été écrasé gagne.
## Tout est décidé par l'hôte (places, lanceur, arrêt de la roue) ; les autres suivent.

const C := Vector2(585, 392)
const R := Vector2(410, 178)
const SPOT_K := 0.74
const FRONT := 0.0
const CHOOSE_T := 8.0
const ARROW_T := 2.0
const SPIN_WAIT := 8.0
const PIVOT := Vector2(1050, 610)
const HANDLE := 290.0

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

# état partagé (envoyé par l'hôte)
var ph := "wait"                # wait, choose, arrow, spin_wait, spin, smash
var ph_t0 := 0.0
var round_n := 0
var n_spots := 0
var rot := 0.0
var picks := {}                 # place -> id
var spinner := 0
var spin_from := 0.0
var spin_to := 0.0
var spin_dur := 4.0
var victim_spot := -1
var victim := 0
var out_ids := {}
var flat := {}                  # id -> moment où il a été écrasé
# local
var cursor := 0
var my_pick := -1
var charge := -1.0              # jauge du lanceur (-1 = pas en train de charger)
var tick_last := 0
var shake := 0.0
var bot_t := 0.0
var hammer_k := 0.0             # 0 levé .. 1 abattu
var parts: Array = []
# hôte
var h_ph := ""
var h_t := 0.0
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
		for pose in ["front", "idle", "jump", "hit", "duck"]:
			_tex["%d_%s" % [id, pose]] = UI.char_tex(Net.color_idx(id), pose)
	for n in ["tree", "treePine", "bush1"]:
		_tex[n] = load("res://assets/deco/%s.png" % n)
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
	Net.mg_player_out.connect(func(id, _how): out_ids[id] = true)
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


func alive() -> Array:
	return ids.filter(func(i): return not out_ids.has(i) and Net.players.has(i))


func spot_angle(i: int) -> float:
	return rot + TAU * float(i) / float(maxi(1, n_spots))


func spot_pos(i: int) -> Vector2:
	var a := spot_angle(i)
	return C + Vector2(cos(a) * R.x * SPOT_K, sin(a) * R.y * SPOT_K)


func owner_spot(id: int) -> int:
	for s in picks:
		if int(picks[s]) == id:
			return int(s)
	return -1


# ------------------------------------------------------------------ hôte
func _host_go(new_ph: String, data: Dictionary) -> void:
	h_ph = new_ph
	h_t = 0.0
	data["ph"] = new_ph
	Net.mg_broadcast(data)


func _host_new_round() -> void:
	var al := alive()
	if al.size() <= 1:
		return
	round_n += 1
	_host_go("choose", {"round": round_n, "n": al.size(), "rot": fmod(rot, TAU), "picks": {}})


func _host_step(dt: float) -> void:
	if h_end:
		return
	h_t += dt
	match h_ph:
		"":
			_host_new_round()
		"choose":
			var al := alive()
			var all_in := true
			for id in al:
				if owner_spot(id) < 0:
					all_in = false
			if all_in or h_t > CHOOSE_T:
				# ceux qui n'ont pas choisi : une place libre au hasard
				var free := []
				for s in n_spots:
					if not picks.has(s):
						free.append(s)
				for id in al:
					if owner_spot(id) < 0 and free.size() > 0:
						var k := rng.randi_range(0, free.size() - 1)
						picks[free[k]] = id
						free.remove_at(k)
				_host_go("arrow", {"picks": picks.duplicate(), "spinner": al[rng.randi_range(0, al.size() - 1)]})
		"arrow":
			if h_t > ARROW_T:
				_host_go("spin_wait", {"spinner": spinner})
		"spin_wait":
			if h_t > SPIN_WAIT:
				_host_spin(rng.randf_range(0.2, 0.9))
		"spin":
			if h_t > spin_dur + 0.25:
				_host_go("smash", {"victim": victim, "spot": victim_spot})
		"smash":
			if h_t > 0.55 and not out_ids.has(victim) and victim != 0:
				Net._on_out(victim, float(round_n), "écrasé")
				if Net.autotest != "":
					print("[roulette] manche ", round_n, " écrasé ", Net.name_of(victim), " t=", snappedf(play_t, 0.1))
			if h_t > 2.4:
				if alive().size() >= 2:
					_host_new_round()
				else:
					h_end = true


func _host_spin(power: float) -> void:
	if h_ph != "spin_wait":
		return
	var turns := 1.6 + power * 2.6 + rng.randf_range(0.0, 1.0)
	var raw := rot + turns * TAU
	var step := TAU / float(n_spots)
	var m := roundi((raw - FRONT) / step)
	var to := FRONT + m * step
	if to < rot + TAU:
		to += TAU
	var spot := posmod(-m, n_spots)
	var vid := int(picks.get(spot, 0))
	_host_go("spin", {"from": rot, "to": to, "dur": 3.6 + power * 1.6, "spot": spot, "victim": vid})


func _on_mg_msg(from_id: int, d: Dictionary) -> void:
	if not Net.is_host() or h_end:
		return
	if d.has("pick") and h_ph == "choose":
		var s := int(d["pick"])
		if s >= 0 and s < n_spots and not picks.has(s) and owner_spot(from_id) < 0 and not out_ids.has(from_id):
			picks[s] = from_id
			Net.mg_broadcast({"picks": picks.duplicate()})
	elif d.has("spin") and h_ph == "spin_wait" and from_id == spinner:
		_host_spin(clampf(float(d["spin"]), 0.0, 1.0))


func _on_mg_state(d: Dictionary) -> void:
	if d.has("picks"):
		var np: Dictionary = d["picks"]
		var newp := {}
		for s in np:
			newp[int(s)] = int(np[s])
		if newp.size() > picks.size():
			Sfx.play("ui_drop", -8.0)
		picks = newp
		my_pick = owner_spot(me_id)
	if not d.has("ph"):
		return
	ph = str(d["ph"])
	ph_t0 = play_t
	match ph:
		"choose":
			round_n = int(d["round"])
			n_spots = int(d["n"])
			rot = float(d["rot"])
			my_pick = -1
			cursor = _front_free_spot()
			bot_t = brng.randf_range(0.6, 3.0)
			hammer_k = 0.0
			Sfx.play("ui_open", -4.0, 0.0)
		"arrow":
			spinner = int(d["spinner"])
			Sfx.play("dice_shuffle", -4.0)
		"spin_wait":
			spinner = int(d["spinner"])
			charge = -1.0
			bot_t = brng.randf_range(0.6, 2.2)
			if spinner == me_id:
				Sfx.play("jingle_turn", -2.0, 0.0)
		"spin":
			spin_from = float(d["from"])
			spin_to = float(d["to"])
			spin_dur = float(d["dur"])
			victim_spot = int(d["spot"])
			victim = int(d["victim"])
			tick_last = int(floor(_spot_phase(spin_from)))
			Sfx.play("whoosh", 0.0, 0.0)
		"smash":
			victim = int(d["victim"])
			victim_spot = int(d["spot"])


func _front_free_spot() -> int:
	var best := 0
	var bd := 1e9
	for s in n_spots:
		var dd := absf(angle_difference(spot_angle(s), FRONT + PI))
		if dd < bd:
			bd = dd
			best = s
	return best


func _spot_phase(r: float) -> float:
	return (r - FRONT) / (TAU / float(maxi(1, n_spots)))


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
			_local_step(delta)
	for p in parts:
		p["t"] = float(p["t"]) + delta
		p["p"] = (p["p"] as Vector2) + (p["v"] as Vector2) * delta
		p["v"] = (p["v"] as Vector2) + Vector2(0, 600) * delta
	parts = parts.filter(func(p): return float(p["t"]) < 1.0)
	shake = maxf(0.0, shake - delta * 2.5)
	view.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * 12.0
	view.queue_redraw()
	hud.queue_redraw()


func _local_step(dt: float) -> void:
	var k := play_t - ph_t0
	match ph:
		"choose":
			if playing and not out_ids.has(me_id) and my_pick < 0:
				if Net.autotest != "":
					bot_t -= dt
					if bot_t <= 0.0:
						var free := []
						for s in n_spots:
							if not picks.has(s):
								free.append(s)
						if free.size() > 0:
							Net.mg_to_host({"pick": free[brng.randi_range(0, free.size() - 1)]})
						bot_t = 0.8
				else:
					var dir := 0
					if Input.is_action_just_pressed("left"):
						dir = -1
					elif Input.is_action_just_pressed("right"):
						dir = 1
					if dir != 0:
						cursor = posmod(cursor + dir, n_spots)
						Sfx.play("ui_move", -8.0, 0.0)
					if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("push") or Input.is_action_just_pressed("ui_accept"):
						if not picks.has(cursor):
							Net.mg_to_host({"pick": cursor})
							Sfx.play("ui_ok", -6.0, 0.0)
						else:
							Sfx.play("ui_error", -8.0, 0.0)
		"spin_wait":
			if spinner == me_id and playing:
				var press := false
				var release := false
				if Net.autotest != "":
					bot_t -= dt
					if charge < 0.0 and bot_t <= 0.0:
						press = true
						bot_t = brng.randf_range(0.3, 1.4)
					elif charge >= 0.0 and bot_t <= 0.0:
						release = true
				else:
					press = Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("push")
					release = charge >= 0.0 and not (Input.is_action_pressed("jump") or Input.is_action_pressed("push"))
				if press and charge < 0.0:
					charge = 0.0
				elif charge >= 0.0:
					charge += dt
					if release:
						var power := 1.0 - absf(fmod(charge, 1.2) / 0.6 - 1.0)
						Net.mg_to_host({"spin": power})
						charge = -2.0
		"spin":
			var u := clampf(k / spin_dur, 0.0, 1.0)
			rot = spin_from + (spin_to - spin_from) * (1.0 - pow(1.0 - u, 3.0))
			var ph2 := int(floor(_spot_phase(rot)))
			if ph2 != tick_last:
				tick_last = ph2
				Sfx.play("ui_tick", -6.0, 0.05)
			if u >= 1.0:
				rot = spin_to
		"smash":
			var prev := hammer_k
			hammer_k = clampf((k - 0.2) / 0.3, 0.0, 1.0) if k < 1.4 else clampf(1.0 - (k - 1.4) / 0.5, 0.0, 1.0)
			if prev < 1.0 and hammer_k >= 1.0:
				shake = 1.0
				Sfx.play("bump", 3.0, 0.0)
				Sfx.play("hurt", -2.0, 0.0)
				if victim != 0:
					flat[victim] = play_t
				var hp := spot_pos(victim_spot)
				for i in 22:
					var a := randf() * TAU
					parts.append({"p": hp, "v": Vector2(cos(a), sin(a) * 0.5) * randf_range(120, 420) + Vector2(0, -200), "t": 0.0,
						"c": [UI.YELLOW, UI.WHITE, Color("#ff9a5a")][i % 3], "r": randf_range(5, 11)})


# ------------------------------------------------------------------ dessin
func _ellipse(c: CanvasItem, ctr: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 64:
		var a := TAU * k / 64.0
		pts.append(ctr + Vector2(cos(a) * r.x, sin(a) * r.y))
	c.draw_colored_polygon(pts, col)


func _draw_view() -> void:
	var c := view
	c.draw_rect(Rect2(-20, -20, 1320, 760), Color("#bfe9fb"))
	c.draw_circle(Vector2(160, 300), 380, Color("#a7d870"))
	c.draw_circle(Vector2(1130, 320), 400, Color("#9bd065"))
	c.draw_rect(Rect2(-20, 220, 1320, 560), Color("#a6dc62"))
	for k in 10:
		var tx: Texture2D = _tex["tree" if k % 3 != 1 else "treePine"]
		var s := 0.36 + (k % 2) * 0.06
		c.draw_set_transform(Vector2(40.0 + k * 135.0, 228 + (k % 2) * 8), 0.0, Vector2(s, s))
		c.draw_texture(tx, Vector2(-tx.get_width() / 2.0, -tx.get_height()))
		c.draw_set_transform(Vector2.ZERO)
	# la roue : tranche + dessus
	_ellipse(c, C + Vector2(0, 56), R + Vector2(10, 6), Color(0, 0, 0, 0.12))
	_ellipse(c, C + Vector2(0, 36), R, Color("#c46b3d"))
	c.draw_rect(Rect2(C + Vector2(-R.x, 0), Vector2(R.x * 2.0, 36)), Color("#c46b3d"))
	_ellipse(c, C, R, Color("#ffe3a8"))
	var n := maxi(1, n_spots)
	if n_spots > 0:
		for i in n:
			var a0 := spot_angle(i) - PI / n
			var pts := PackedVector2Array([C])
			for k in 13:
				var a := a0 + TAU / n * k / 12.0
				pts.append(C + Vector2(cos(a) * (R.x - 14), sin(a) * (R.y - 7)))
			var col: Color = [Color("#ff8fa3"), Color("#7fd6ff"), Color("#ffd23f"), Color("#8ee07a"), Color("#c8a2ff"), Color("#ffb36b"), Color("#6be0d4"), Color("#ff9ad5")][i % 8]
			if ph == "smash" and i == victim_spot:
				col = col.lerp(UI.RED, 0.5 + 0.5 * sin(t * 20.0))
			c.draw_colored_polygon(pts, col)
		for i in n:
			var a1 := spot_angle(i) - PI / n
			c.draw_line(C, C + Vector2(cos(a1) * (R.x - 14), sin(a1) * (R.y - 7)), UI.WHITE, 4.0)
	_ellipse(c, C, Vector2(64, 28), UI.WHITE)
	_ellipse(c, C, Vector2(52, 22), Color("#ff6f6f"))
	# repère du marteau, à l'avant de la roue
	var fp := C + Vector2(R.x + 14, 18)
	c.draw_colored_polygon(PackedVector2Array([fp + Vector2(26, -20), fp + Vector2(26, 20), fp + Vector2(-2, 0)]), UI.RED)
	# places (cercles) et curseur
	if n_spots > 0 and ph != "wait":
		for i in n:
			var sp := spot_pos(i)
			_ellipse(c, sp, Vector2(40, 17), Color(1, 1, 1, 0.75))
			if ph == "choose" and playing and my_pick < 0 and i == cursor and not out_ids.has(me_id):
				var pulse := 1.0 + 0.12 * sin(t * 10.0)
				_ellipse_line(c, sp, Vector2(48, 21) * pulse, Net.color_of(me_id), 5.0)
	# flèche du lanceur au centre
	if ph == "arrow" or ph == "spin_wait":
		var target := owner_spot(spinner)
		var ta := spot_angle(target) if target >= 0 else 0.0
		var k := play_t - ph_t0
		var a2 := ta
		if ph == "arrow" and k < ARROW_T - 0.4:
			var u := k / (ARROW_T - 0.4)
			a2 = ta + (1.0 - u) * (1.0 - u) * TAU * 3.0
		var tip := C + Vector2(cos(a2) * 150.0, sin(a2) * 65.0)
		c.draw_line(C, tip, UI.DARK, 10.0)
		var dv := (tip - C).normalized()
		var pv := Vector2(-dv.y, dv.x)
		c.draw_colored_polygon(PackedVector2Array([tip + dv * 22.0, tip + pv * 16.0, tip - pv * 16.0]), UI.DARK)
		c.draw_circle(C, 14.0, UI.DARK)
	# joueurs (sur leur place, ou en attente au fond)
	var order := []
	var waiting := []
	for id in ids:
		if out_ids.has(id) and not flat.has(id):
			continue
		var s := owner_spot(id)
		if s >= 0 and ph != "wait":
			order.append(id)
		elif not out_ids.has(id):
			waiting.append(id)
	for wi in waiting.size():
		var id2: int = waiting[wi]
		var wp := Vector2(82.0 + (wi % 2) * 70.0, 330.0 + (wi / 2) * 110.0)
		_draw_char(c, id2, wp, 0.38, "front")
	order.sort_custom(func(a, b): return spot_pos(owner_spot(a)).y < spot_pos(owner_spot(b)).y)
	for id3 in order:
		var p := spot_pos(owner_spot(id3))
		var pose := "idle"
		if flat.has(id3):
			pose = "hit"
		elif ph == "spin" or (ph == "smash" and id3 == victim):
			pose = "jump" if id3 != victim or ph == "spin" else "hit"
		elif id3 == spinner and ph == "spin_wait":
			pose = "jump"
		_draw_char(c, id3, p, 0.46, pose)
	# le marteau, devant tout
	_draw_hammer(c)
	for p2 in parts:
		var q := float(p2["t"])
		c.draw_circle(p2["p"], float(p2["r"]) * (1.0 - q), Color(p2["c"], 1.0 - q))
	if ph == "smash" and play_t - ph_t0 > 0.5 and play_t - ph_t0 < 2.2 and victim != 0:
		var vk := (play_t - ph_t0 - 0.5) / 1.7
		UI.text(c, spot_pos(victim_spot) + Vector2(0, -120 - vk * 40.0), "ÉCRASÉ !", 40, Color(UI.RED, 1.0 - vk * vk), 9)


func _draw_char(c: CanvasItem, id: int, p: Vector2, s: float, pose: String) -> void:
	var tx: Texture2D = _tex["%d_%s" % [id, pose]]
	var sy := s
	var sx := s
	if flat.has(id):
		var k := clampf((play_t - float(flat[id])) / 0.12, 0.0, 1.0)
		sy = s * lerpf(1.0, 0.22, k)
		sx = s * lerpf(1.0, 1.5, k)
	_ellipse(c, p + Vector2(0, 2), Vector2(30, 11), Color(0, 0, 0, 0.18))
	var hop := 0.0
	if pose == "jump" and not flat.has(id):
		hop = absf(sin(t * 8.0 + id)) * 10.0
	c.draw_set_transform(p + Vector2(0, -hop), 0.0, Vector2(sx, sy))
	c.draw_texture(tx, Vector2(-128, -256), Color(1, 1, 1, 0.8) if flat.has(id) else Color.WHITE)
	c.draw_set_transform(Vector2.ZERO)
	if not flat.has(id):
		var nm := "TOI" if id == me_id else Net.name_of(id)
		UI.text(c, p + Vector2(0, -256 * s - 10 - hop), nm, 17 if id == me_id else 14, UI.YELLOW if id == me_id else Net.color_of(id), 5)
	if flat.has(id):
		for k2 in 3:
			var a := t * 5.0 + TAU * k2 / 3.0
			c.draw_circle(p + Vector2(cos(a) * 30.0, -24 + sin(a) * 8.0), 5.0, UI.YELLOW)


func _ellipse_line(c: CanvasItem, ctr: Vector2, r: Vector2, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for k in 41:
		var a := TAU * k / 40.0
		pts.append(ctr + Vector2(cos(a) * r.x, sin(a) * r.y))
	c.draw_polyline(pts, col, w, true)


func _draw_hammer(c: CanvasItem) -> void:
	var target := C + Vector2(R.x * SPOT_K, -36)
	var down := (target - PIVOT).angle()
	var up := -PI / 3.0
	var idle := sin(t * 2.0) * 0.04
	var a := lerp_angle(up + idle, down, hammer_k * hammer_k)
	var head := PIVOT + Vector2(cos(a), sin(a)) * HANDLE
	# socle
	_ellipse(c, PIVOT + Vector2(0, 30), Vector2(70, 22), Color(0, 0, 0, 0.15))
	c.draw_style_box(UI.box(Color("#8a5a32"), UI.WHITE, 4, 12), Rect2(PIVOT + Vector2(-46, -10), Vector2(92, 46)))
	# manche
	c.draw_line(PIVOT, head, Color("#6b4a2b"), 22.0)
	c.draw_line(PIVOT, head, Color("#9c6a3c"), 14.0)
	# tête
	c.draw_set_transform(head, a + PI / 2.0, Vector2.ONE)
	c.draw_style_box(UI.box(Color("#f04650"), UI.WHITE, 6, 20), Rect2(Vector2(-90, -50), Vector2(180, 100)))
	c.draw_rect(Rect2(Vector2(-64, -50), Vector2(18, 100)), Color("#c43a55"))
	c.draw_rect(Rect2(Vector2(46, -50), Vector2(18, 100)), Color("#c43a55"))
	c.draw_style_box(UI.box(Color(1, 1, 1, 0.3), Color(0, 0, 0, 0), 0, 10), Rect2(Vector2(-80, -42), Vector2(160, 18)))
	c.draw_set_transform(Vector2.ZERO)
	c.draw_circle(PIVOT, 16.0, Color("#ffd23f"))


# ------------------------------------------------------------------ HUD
func _draw_hud() -> void:
	var h := hud
	var St := preload("res://minigames/stage.gd")
	if state == "intro":
		St.draw_intro(h, "Roulette-marteau !", [
			"Choisis ta place sur la grande roue (une place par joueur).",
			"Une flèche désigne celui qui fait tourner la roue...",
			"Quand elle s'arrête, celui qui est devant le marteau est écrasé !",
			"À chaque manche, une place de moins. Le dernier épargné gagne !"],
			"Choisir sa place : Q D / ← →   ·   Valider : Espace   ·   Lancer la roue : maintiens Espace puis lâche")
		St.draw_ready_row(h, my_ready, ready_ids, ids, t, not playing)
		if str(Net.mg_data.get("mode", "")) == "duel":
			St.draw_duel_banner(h)
		return
	St.draw_heads(h, ids, out_ids)
	var k := play_t - ph_t0
	var msg := ""
	match ph:
		"choose":
			var left := maxi(0, ceili(CHOOSE_T - k))
			if playing and not out_ids.has(me_id):
				msg = "Choisis ta place ! (← →, Espace)   %d s" % left if my_pick < 0 else "Place choisie ! On attend les autres..."
			else:
				msg = "Les joueurs choisissent leur place...   %d s" % left
		"arrow":
			msg = "Qui va faire tourner la roue ?"
		"spin_wait":
			msg = ("À TOI ! Maintiens Espace puis lâche pour lancer la roue !" if spinner == me_id else "%s va lancer la roue..." % Net.name_of(spinner))
		"spin":
			msg = "Ça tourne..."
	if msg != "":
		UI.ribbon(h, Vector2(640, 118), msg, 24, Color("#8e6cf0"))
	if ph == "choose" or ph == "wait" or ph == "arrow":
		UI.text(h, Vector2(1180, 104), "Manche %d" % maxi(1, round_n), 22, UI.WHITE, 6)
	# jauge du lanceur
	if ph == "spin_wait" and spinner == me_id and charge >= 0.0:
		var power := 1.0 - absf(fmod(charge, 1.2) / 0.6 - 1.0)
		var r := Rect2(Vector2(440, 650), Vector2(400, 40))
		UI.panel(h, r, UI.WHITE, UI.DARK, 18, 4)
		h.draw_style_box(UI.box(UI.YELLOW.lerp(UI.RED, power), Color(0, 0, 0, 0), 0, 12), Rect2(r.position + Vector2(6, 6), Vector2((r.size.x - 12) * power, r.size.y - 12)))
		UI.text(h, r.get_center(), "FORCE", 20, UI.DARK, 0)
	if state == "count":
		UI.text(h, Vector2(640, 380), str(3 - int(t)), int(110 * (1.0 + (1.0 - fmod(t, 1.0)) * 0.3)), UI.WHITE, 16)
	elif state == "play" and t < 1.0:
		UI.text(h, Vector2(640, 380), "GO !", int(120 * (1.0 + t * 0.4)), Color(UI.YELLOW, 1.0 - t), 18)
	if playing and out_ids.has(me_id) and state == "play":
		var m2 := "Écrasé ! Tu regardes la suite..."
		var mw := UI.text_width(m2, 24) + 50.0
		UI.panel(h, Rect2(Vector2(640 - mw / 2.0, 660), Vector2(mw, 46)), UI.WHITE, Color("#ffd0d0"), 20, 4)
		UI.text(h, Vector2(640, 683), m2, 24, UI.RED, 0)
	if state == "over":
		h.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, minf(0.4, t)))
		UI.text(h, Vector2(640, 360), "TERMINÉ !", 96, UI.YELLOW, 16)
