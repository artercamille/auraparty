extends Node2D
## « Mémo-boum ! » (Memory Mash, Mario Party DS) : 2 contre 2 (ici jusqu'à 4 contre 4).
## 18 cartes face cachée posées au sol (6 x 3, 9 paires), vue de dessus.
## On saute (Espace) puis on frappe le sol (Espace en l'air) sur une carte pour la retourner.
## Chaque équipe retourne 2 cartes : pareilles = l'équipe gagne la paire, sinon elles se recachent.
## Tout le monde voit les cartes retournées. La première équipe à 4 paires gagne.
## Nombre impair de joueurs : un joueur tiré au sort est l'arbitre et gagne d'office (comme la corde).

const COLS := 6
const ROWS := 3
const CELL := Vector2(176, 200)
const CARD := Vector2(144, 168)
const SQ := 0.62
const CENTER := Vector2(640, 418)
const ARENA := Rect2(-560, -318, 1120, 636)
const SYMS := ["star", "heart", "coin", "gem_blue", "key", "mushroom", "bomb", "flag", "cupcake"]
const WIN_PAIRS := 4
const MAX_T := 180.0
const SPEED := 340.0
const ACC := 2600.0
const JUMP_V := 560.0
const GRAV := 1750.0
const POUND_V := 1600.0
const HOVER := 0.14
const RADIUS := 30.0
const FIRST_TIMEOUT := 8.0
const MISS_SHOW := 1.2
const MATCH_SHOW := 0.8
const TEAM_NAMES := ["", "rouge", "bleue"]
const TEAM_COLS := [Color("#9aa0b4"), Color("#f04650"), Color("#4b87f5")]

var ids: Array = []
var team_of := {}               # id -> 1 / 2 (0 = arbitre)
var teams := [[], [], []]
var referee := 0
var me_id := 0
var my_team := 0
var playing := false            # je cours dans l'arène
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

# cartes (état renvoyé par l'hôte)
var card_sym: Array = []
var cstate: Array = []          # 0 cachée, 1 visible, 2 gagnée
var cowner: Array = []          # équipe qui l'a retournée / gagnée
var cchange: Array = []
var pairs := [0, 0, 0]
var won_syms := [[], [], []]    # symboles gagnés par équipe (pour le HUD)
var team_first := [-1, -1, -1]  # première carte en cours de chaque équipe

# persos
var bodies := {}                # id -> {p, v, z, st, snaps, face, walk}
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var z := 0.0
var vz := 0.0
var pounding := false
var hover_t := 0.0
var stun := 0.0
var send_acc := 0.0
var shake := 0.0
var fx: Array = []              # {kind, p, t, c}
var banner := ""
var banner_t := 0.0
var banner_col := UI.WHITE
# hôte
var h_first := [null, null, null]
var h_busy := [false, false, false]
var h_timers: Array = []
var h_end_t := -1.0
var ended := false
# robots
var bot_seen := {}
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
	# équipes tirées au sort (même tirage chez tout le monde)
	var pool := ids.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	if pool.size() % 2 == 1 and pool.size() > 2:
		referee = pool.pop_front()
	for i in pool.size():
		var tm := 1 if i % 2 == 0 else 2
		team_of[pool[i]] = tm
		teams[tm].append(pool[i])
	if referee != 0:
		team_of[referee] = 0
	my_team = int(team_of.get(me_id, 0))
	playing = my_team != 0
	# les cartes
	var deck := []
	for s in SYMS:
		deck.append(s)
		deck.append(s)
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp2 = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp2
	card_sym = deck
	for i in deck.size():
		cstate.append(0)
		cowner.append(0)
		cchange.append(-10.0)
	# départ : chaque équipe d'un côté
	for tm in [1, 2]:
		var tl: Array = teams[tm]
		for k in tl.size():
			var id: int = tl[k]
			var p := Vector2(-520.0 if tm == 1 else 520.0, (float(k) - (tl.size() - 1) / 2.0) * 120.0)
			bodies[id] = {"p": p, "v": Vector2.ZERO, "z": 0.0, "st": 0, "snaps": [], "face": 1 if tm == 1 else -1, "walk": 0.0}
			if id == me_id:
				pos = p
	for id in ids:
		for pose in ["idle", "walk_a", "walk_b", "jump", "hit", "duck", "front"]:
			_tex["%d_%s" % [id, pose]] = UI.char_tex(Net.color_idx(id), pose)
	for s in SYMS:
		_tex[s] = load("res://assets/cards/%s.png" % s)
	for n in ["tree", "treePine", "bush1", "bush3"]:
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
	hud.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	hud.draw.connect(_draw_hud)
	ui.add_child(hud)
	Net.remote_state.connect(_on_remote_state)
	Net.got_hit.connect(_on_got_hit)
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
	for id in bodies.keys():
		if not Net.players.has(id):
			bodies.erase(id)
	for id in ids.duplicate():
		if not Net.players.has(id):
			ids.erase(id)


# ------------------------------------------------------------------ géométrie
func card_center(i: int) -> Vector2:
	return Vector2((float(i % COLS) - (COLS - 1) / 2.0) * CELL.x, (float(i / COLS) - (ROWS - 1) / 2.0) * CELL.y)


func card_at(p: Vector2) -> int:
	for i in card_sym.size():
		var c := card_center(i)
		if absf(p.x - c.x) < CARD.x / 2.0 + 6.0 and absf(p.y - c.y) < CARD.y / 2.0 + 6.0:
			return i
	return -1


func scr(p: Vector2, height := 0.0) -> Vector2:
	return CENTER + Vector2(p.x, p.y * SQ - height)


# ------------------------------------------------------------------ mon perso
func _step(dt: float) -> void:
	stun = maxf(0.0, stun - dt)
	var d := Vector2.ZERO
	var want_jump := false
	if Net.autotest != "":
		var bi := _bot_input(dt)
		d = bi[0]
		want_jump = bi[1]
	else:
		d = Vector2(Input.get_axis("left", "right"), Input.get_axis("up", "down")).limit_length(1.0)
		want_jump = Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("push")
	if stun > 0.0:
		d = Vector2.ZERO
		want_jump = false
	if pounding:
		d = Vector2.ZERO
	# déplacement
	var target := d * SPEED
	var acc := ACC if z <= 0.0 else ACC * 0.6
	vel = vel.move_toward(target, acc * dt)
	if stun > 0.0:
		vel = vel.move_toward(Vector2.ZERO, 900.0 * dt)
	# saut / frappe au sol
	if want_jump:
		if z <= 0.0 and not pounding:
			vz = JUMP_V
			z = 0.01
			Sfx.play("jump", -6.0)
		elif z > 0.0 and not pounding:
			pounding = true
			hover_t = HOVER
			vz = 0.0
			vel = Vector2.ZERO
			Sfx.play("whoosh", -6.0)
	if z > 0.0:
		if pounding:
			if hover_t > 0.0:
				hover_t -= dt
			else:
				vz = -POUND_V
		else:
			vz -= GRAV * dt
		z += vz * dt
		if z <= 0.0:
			z = 0.0
			vz = 0.0
			if pounding:
				pounding = false
				_land_pound()
			else:
				Sfx.play("step1", -14.0)
	pos += vel * dt
	pos.x = clampf(pos.x, ARENA.position.x + RADIUS, ARENA.end.x - RADIUS)
	pos.y = clampf(pos.y, ARENA.position.y + RADIUS, ARENA.end.y - RADIUS)
	# on se pousse entre persos
	for id in bodies:
		if id == me_id:
			continue
		var op: Vector2 = bodies[id]["p"]
		var dv := pos - op
		var dist := dv.length()
		if dist < RADIUS * 2.0 and dist > 0.01:
			pos += dv / dist * (RADIUS * 2.0 - dist) * 0.5
	var b: Dictionary = bodies[me_id]
	b["p"] = pos
	b["v"] = vel
	b["z"] = z
	if absf(vel.x) > 20.0:
		b["face"] = 1 if vel.x > 0.0 else -1
	b["walk"] = float(b["walk"]) + vel.length() * dt
	b["st"] = _pack()
	send_acc += dt
	if send_acc >= 1.0 / 30.0:
		send_acc = 0.0
		Net.send_state(pos, vel, int(b["st"]))


func _pack() -> int:
	return (1 if pounding else 0) | (2 if stun > 0.0 else 0) | (clampi(int(z), 0, 400) << 4)


func _land_pound() -> void:
	shake = 1.0
	Sfx.play("bump", -1.0, 0.1)
	fx.append({"kind": "ring", "p": pos, "t": 0.0, "c": TEAM_COLS[my_team]})
	var i := card_at(pos)
	if i >= 0 and int(cstate[i]) == 0:
		Net.mg_to_host({"flip": i})
	# les persos tout près sont sonnés
	for id in bodies:
		if id == me_id:
			continue
		var o: Dictionary = bodies[id]
		var dv: Vector2 = (o["p"] as Vector2) - pos
		if dv.length() < 92.0 and float(o["z"]) < 30.0:
			Net.send_hit(id, 2, dv.normalized() if dv.length() > 1.0 else Vector2.RIGHT)


func _on_got_hit(kind: int, dir: Vector2, _from: int) -> void:
	if kind != 2 or not playing or state != "play" or stun > 0.0 or z > 30.0:
		return
	stun = 0.9
	vel = dir * 430.0
	pounding = false
	Sfx.play("hurt", -4.0)
	fx.append({"kind": "stars", "p": pos, "t": 0.0, "c": UI.YELLOW})


func _on_remote_state(id: int, p: Vector2, v: Vector2, st: int) -> void:
	if not bodies.has(id) or id == me_id:
		return
	var snaps: Array = bodies[id]["snaps"]
	snaps.append([Time.get_ticks_msec() / 1000.0, p, v, st])
	if snaps.size() > 12:
		snaps.pop_front()


func _update_remotes(dt: float) -> void:
	var rt := Time.get_ticks_msec() / 1000.0 - 0.08
	for id in bodies:
		if id == me_id:
			continue
		var b: Dictionary = bodies[id]
		var snaps: Array = b["snaps"]
		if snaps.is_empty():
			continue
		var p: Vector2 = snaps[-1][1]
		var st := int(snaps[-1][3])
		b["v"] = snaps[-1][2]
		if rt < float(snaps[-1][0]):
			for i in range(snaps.size() - 1, 0, -1):
				var a: Array = snaps[i - 1]
				var c: Array = snaps[i]
				if float(a[0]) <= rt:
					var u := clampf((rt - float(a[0])) / maxf(0.001, float(c[0]) - float(a[0])), 0.0, 1.0)
					p = (a[1] as Vector2).lerp(c[1], u)
					st = int(c[3])
					break
		var old: Vector2 = b["p"]
		b["p"] = p
		b["st"] = st
		b["z"] = float(st >> 4)
		if absf(p.x - old.x) > 0.5:
			b["face"] = 1 if p.x > old.x else -1
		b["walk"] = float(b["walk"]) + old.distance_to(p)
		if dt > 0.0 and (int(b.get("prev_st", 0)) & 1) != 0 and (st & 1) == 0:
			fx.append({"kind": "ring", "p": p, "t": 0.0, "c": TEAM_COLS[int(team_of.get(id, 0))]})
			Sfx.play("bump", -10.0, 0.1)
		b["prev_st"] = st


# ------------------------------------------------------------------ robots
func _bot_input(dt: float) -> Array:
	bot_t -= dt
	if bot_target >= 0 and int(cstate[bot_target]) != 0:
		bot_target = -1
	if bot_target < 0 or bot_t <= 0.0:
		bot_t = brng.randf_range(3.0, 5.0)
		var choices := []
		var first: int = team_first[my_team]
		if first >= 0:
			for i in bot_seen:
				if i != first and int(cstate[i]) == 0 and str(bot_seen[i]) == str(card_sym[first]):
					choices = [i]
		if choices.is_empty():
			for i in card_sym.size():
				if int(cstate[i]) == 0:
					choices.append(i)
		if choices.is_empty():
			return [Vector2.ZERO, false]
		bot_target = choices[brng.randi() % choices.size()]
	var c := card_center(bot_target)
	var dv := c - pos
	var jump := false
	if dv.length() < 26.0:
		if z <= 0.0:
			jump = true
		elif vz < 120.0 and not pounding:
			jump = true
		return [Vector2.ZERO, jump]
	return [dv.normalized() * minf(1.0, dv.length() / 60.0), false]


# ------------------------------------------------------------------ hôte : les cartes
func _on_mg_msg(from_id: int, data: Dictionary) -> void:
	if not Net.is_host() or state != "play" or ended or h_end_t >= 0.0 or not data.has("flip"):
		return
	var tm := int(team_of.get(from_id, 0))
	var i := int(data["flip"])
	if tm == 0 or h_busy[tm] or i < 0 or i >= card_sym.size() or int(cstate[i]) != 0:
		return
	var ev := {}
	var first = h_first[tm]
	if first != null and int(cstate[int(first[0])]) == 1 and int(cowner[int(first[0])]) == tm:
		var a := int(first[0])
		h_first[tm] = null
		h_busy[tm] = true
		cstate[i] = 1
		cowner[i] = tm
		var same := str(card_sym[a]) == str(card_sym[i])
		h_timers.append({"t": MATCH_SHOW if same else MISS_SHOW, "act": "match" if same else "hide", "cards": [a, i], "team": tm})
		ev = {"kind": "flip2", "id": from_id, "team": tm, "card": i, "same": same}
	else:
		h_first[tm] = [i, play_t]
		cstate[i] = 1
		cowner[i] = tm
		ev = {"kind": "flip1", "id": from_id, "team": tm, "card": i}
	_broadcast(ev)


func _host_step(dt: float) -> void:
	if ended:
		return
	for tm2 in h_timers.duplicate():
		tm2["t"] = float(tm2["t"]) - dt
		if float(tm2["t"]) > 0.0:
			continue
		h_timers.erase(tm2)
		var cs: Array = tm2["cards"]
		var team := int(tm2["team"])
		h_busy[team] = false
		if str(tm2["act"]) == "match":
			for c in cs:
				cstate[int(c)] = 2
				cowner[int(c)] = team
			pairs[team] = int(pairs[team]) + 1
			_broadcast({"kind": "match", "team": team, "cards": cs})
			if int(pairs[team]) >= WIN_PAIRS and h_end_t < 0.0:
				h_end_t = 1.6
		else:
			for c in cs:
				cstate[int(c)] = 0
				cowner[int(c)] = 0
			_broadcast({"kind": "miss", "team": team, "cards": cs})
	for team in [1, 2]:
		var f = h_first[team]
		if f != null and play_t - float(f[1]) > FIRST_TIMEOUT:
			h_first[team] = null
			var a := int(f[0])
			if int(cstate[a]) == 1 and int(cowner[a]) == team:
				cstate[a] = 0
				cowner[a] = 0
				_broadcast({"kind": "timeout", "team": team, "cards": [a]})
	if h_end_t >= 0.0:
		h_end_t -= dt
		if h_end_t <= 0.0:
			_finish()
	elif play_t > MAX_T or not cstate.has(0) and h_timers.is_empty() and not cstate.has(1):
		_finish()


func _broadcast(ev: Dictionary) -> void:
	Net.mg_broadcast({"cs": cstate.duplicate(), "own": cowner.duplicate(), "pairs": pairs.duplicate(), "ev": ev})


func _finish() -> void:
	if ended:
		return
	ended = true
	var pa := int(pairs[1])
	var pb := int(pairs[2])
	var sc := {}
	for id in ids:
		var tm := int(team_of.get(id, 0))
		if tm == 0:
			sc[id] = [1000.0, "Arbitre : gagné d'office !"]
			continue
		var mine := pa if tm == 1 else pb
		var other := pb if tm == 1 else pa
		var won := mine > other
		var s := float(mine) + (100.0 if won else 0.0)
		if mine == other:
			s = float(mine) + 100.0
		sc[id] = [s, "%s · %d paire%s" % ["Équipe gagnante" if won else ("Égalité" if mine == other else "Perdu"), mine, "s" if mine > 1 else ""]]
	if Net.autotest != "":
		print("[memory] fin t=", snappedf(play_t, 0.1), " paires ", pairs)
	Net.mg_end_with_scores(sc)


func _on_mg_state(data: Dictionary) -> void:
	if not data.has("cs"):
		return
	var ncs: Array = data["cs"]
	var nown: Array = data["own"]
	for i in mini(ncs.size(), cstate.size()):
		if int(ncs[i]) != int(cstate[i]):
			cchange[i] = play_t
			if int(ncs[i]) == 1:
				bot_seen[i] = str(card_sym[i])
		cstate[i] = int(ncs[i])
		cowner[i] = int(nown[i])
	pairs = data["pairs"]
	var ev: Dictionary = data.get("ev", {})
	var kind := str(ev.get("kind", ""))
	var tm := int(ev.get("team", 0))
	match kind:
		"flip1":
			team_first[tm] = int(ev["card"])
			Sfx.play("card_slide", -2.0)
		"flip2":
			team_first[tm] = -1
			Sfx.play("card_slide", -2.0)
			if ev.get("same", false):
				Sfx.play("ui_ok", -4.0, 0.0)
		"match":
			var cs: Array = ev["cards"]
			won_syms[tm].append(str(card_sym[int(cs[0])]))
			for c in cs:
				fx.append({"kind": "fly", "card": int(c), "team": tm, "t": 0.0})
				fx.append({"kind": "ring", "p": card_center(int(c)), "t": 0.0, "c": TEAM_COLS[tm]})
			Sfx.play("jingle_good" if tm == my_team else "coin", -2.0 if tm == my_team else -6.0, 0.0)
			_say("Équipe %s : une paire ! (%d/%d)" % [TEAM_NAMES[tm], int(pairs[tm]), WIN_PAIRS], TEAM_COLS[tm])
		"miss":
			if tm == my_team:
				Sfx.play("ui_error", -6.0, 0.0)
		"timeout":
			team_first[tm] = -1


func _say(txt: String, col: Color) -> void:
	banner = txt
	banner_col = col
	banner_t = 1.8


# ------------------------------------------------------------------ boucle
func _process(delta: float) -> void:
	t += delta
	match state:
		"intro":
			if not my_ready and t > 0.6 and ids.has(me_id):
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
			if playing:
				_step(delta)
			if Net.is_host():
				_host_step(delta)
			if Net.autotest != "" and int(play_t / 10.0) != int((play_t - delta) / 10.0):
				print("[memory] t=", int(play_t), " paires ", pairs)
	_update_remotes(delta)
	for f in fx:
		f["t"] = float(f["t"]) + delta
	fx = fx.filter(func(f): return float(f["t"]) < 1.0)
	banner_t = maxf(0.0, banner_t - delta)
	shake = maxf(0.0, shake - delta * 4.0)
	view.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * 6.0
	view.queue_redraw()
	hud.queue_redraw()


# ------------------------------------------------------------------ dessin
func _draw_view() -> void:
	var c := view
	# ciel, collines, herbe
	c.draw_rect(Rect2(-20, -20, 1320, 760), Color("#bfe9fb"))
	c.draw_circle(Vector2(180, 330), 360, Color("#a7d870"))
	c.draw_circle(Vector2(1120, 340), 380, Color("#9bd065"))
	c.draw_rect(Rect2(-20, 190, 1320, 600), Color("#a6dc62"))
	for k in 10:
		var tx: Texture2D = _tex["tree" if k % 3 != 1 else "treePine"]
		var x := 30.0 + k * 136.0
		var s := 0.34 + (k % 2) * 0.06
		c.draw_set_transform(Vector2(x, 196 + (k % 2) * 8), 0.0, Vector2(s, s))
		c.draw_texture(tx, Vector2(-tx.get_width() / 2.0, -tx.get_height()))
		c.draw_set_transform(Vector2.ZERO)
	# l'estrade
	var tl := scr(ARENA.position)
	var br := scr(ARENA.end)
	var ar := Rect2(tl, br - tl).grow(26)
	c.draw_style_box(UI.box(Color(0, 0, 0, 0.12), Color(0, 0, 0, 0), 0, 34), Rect2(ar.position + Vector2(0, 30), ar.size))
	c.draw_style_box(UI.box(Color("#c98a4b"), Color(0, 0, 0, 0), 0, 34), Rect2(ar.position + Vector2(0, 18), ar.size))
	c.draw_style_box(UI.box(Color("#ffe3a8"), UI.WHITE, 6, 34), ar)
	c.draw_style_box(UI.box(Color("#ffd889"), Color(0, 0, 0, 0), 0, 26), ar.grow(-18))
	for k in 24:
		var fx0 := ar.position.x + 30.0 + k * (ar.size.x - 60.0) / 23.0
		c.draw_circle(Vector2(fx0, ar.end.y + 9), 5.0, Color("#ffe3a8"))
	# emplacements + cartes
	for i in card_sym.size():
		_draw_card(c, i)
	# persos, de l'arrière vers l'avant
	var order := bodies.keys()
	order.sort_custom(func(a, b): return float(bodies[a]["p"].y) < float(bodies[b]["p"].y))
	for id in order:
		_draw_body(c, id)
	# effets
	for f in fx:
		var k2 := float(f["t"])
		match str(f["kind"]):
			"ring":
				var p := scr(f["p"])
				_ellipse_line(c, p, 30.0 + k2 * 110.0, (30.0 + k2 * 110.0) * SQ, Color(f["c"], 1.0 - k2), 6.0 * (1.0 - k2) + 1.0)
			"stars":
				var p2 := scr(f["p"], 90.0)
				for s in 5:
					var a := TAU * s / 5.0 + k2 * 6.0
					c.draw_circle(p2 + Vector2(cos(a) * 34.0, sin(a) * 14.0), 6.0 * (1.0 - k2), UI.YELLOW)
			"fly":
				var ci := int(f["card"])
				var from := scr(card_center(ci))
				var to := Vector2(150 if int(f["team"]) == 1 else 1130, 70)
				var e := minf(1.0, k2 / 0.7)
				var q := from.lerp(to, e * e) + Vector2(0, -sin(e * PI) * 160.0)
				var sz := lerpf(1.0, 0.35, e)
				var rr := Rect2(q - CARD * Vector2(1.0, 0.8) * sz / 2.0, CARD * Vector2(1.0, 0.8) * sz)
				c.draw_style_box(UI.box(UI.WHITE, TEAM_COLS[int(f["team"])], 5, 12), rr)
				var tx2: Texture2D = _tex[str(card_sym[ci])]
				c.draw_texture_rect(tx2, Rect2(q - Vector2(70, 70) * sz / 2.0, Vector2(70, 70) * sz), false, Color(1, 1, 1, 1.0 - maxf(0.0, e - 0.9) * 10.0))


func _draw_card(c: CanvasItem, i: int) -> void:
	var ctr := scr(card_center(i))
	var w := CARD.x
	var h := CARD.y * SQ
	var st := int(cstate[i])
	var age := play_t - float(cchange[i])
	# emplacement vide
	var slot := Rect2(ctr - Vector2(w, h) / 2.0, Vector2(w, h))
	c.draw_style_box(UI.box(Color(0.6, 0.4, 0.2, 0.18), Color(0, 0, 0, 0), 0, 12), slot.grow(4))
	if st == 2 and age > 0.05:
		return
	var sx := 1.0
	var face := st >= 1
	var lift := 0.0
	if age < 0.32:
		var k := age / 0.32
		sx = absf(cos(k * PI))
		lift = sin(k * PI) * 26.0
		if k < 0.5:
			face = not face
	var r := Rect2(ctr - Vector2(w * sx, h) / 2.0 - Vector2(0, lift), Vector2(w * sx, h))
	# épaisseur
	c.draw_style_box(UI.box(Color(0.25, 0.15, 0.4, 0.35) if not face else Color(0.5, 0.45, 0.4, 0.35), Color(0, 0, 0, 0), 0, 12), Rect2(r.position + Vector2(0, 7 + lift), r.size))
	# la carte sous mes pieds
	var mine_under := playing and state == "play" and card_at(pos) == i and st == 0
	if not face:
		c.draw_style_box(UI.box(Color("#8e6cf0"), UI.YELLOW if mine_under else UI.WHITE, 6 if mine_under else 5, 12), r)
		if sx > 0.3:
			var inner := r.grow(-12)
			c.draw_style_box(UI.box(Color("#a487f5"), Color(0, 0, 0, 0), 0, 8), inner)
			for a in 4:
				for b in 3:
					var p := inner.position + Vector2((a + 0.5) * inner.size.x / 4.0, (b + 0.5) * inner.size.y / 3.0)
					c.draw_circle(p, 3.0 * sx, Color(1, 1, 1, 0.3))
			c.draw_circle(r.get_center(), 24.0 * sx, Color("#7a55e0"))
			UI.text(c, r.get_center() + Vector2(0, 1), "?", int(32 * sx) + 1, UI.WHITE, 0)
	else:
		var tm := int(cowner[i])
		var border: Color = TEAM_COLS[tm] if tm > 0 else UI.WHITE
		c.draw_style_box(UI.box(Color("#fffaf2"), border, 7, 12), r)
		if sx > 0.15:
			var tx: Texture2D = _tex[str(card_sym[i])]
			var pop := 1.0 + (0.22 * sin(clampf(age / 0.45, 0.0, 1.0) * PI) if age < 0.45 else 0.0)
			var sz := Vector2(84.0 * sx, 84.0 * 0.8) * pop
			c.draw_texture_rect(tx, Rect2(r.get_center() - sz / 2.0, sz), false)


func _draw_body(c: CanvasItem, id: int) -> void:
	var b: Dictionary = bodies[id]
	var p: Vector2 = b["p"]
	var bz := float(b["z"])
	var st := int(b["st"])
	var tm := int(team_of.get(id, 0))
	var g := scr(p)
	# ombre + anneau d'équipe
	var sh := clampf(1.0 - bz / 300.0, 0.4, 1.0)
	_ellipse(c, g, 40.0 * sh, 15.0 * sh, Color(0, 0, 0, 0.2))
	_ellipse_line(c, g, 44.0, 17.0, TEAM_COLS[tm], 5.0)
	var pose := "idle"
	var rot := 0.0
	if (st & 2) != 0:
		pose = "hit"
		rot = sin(t * 20.0) * 0.15
	elif (st & 1) != 0:
		pose = "duck"
		rot = 0.0
	elif bz > 0.0:
		pose = "jump"
	elif (b["v"] as Vector2).length() > 30.0:
		pose = "walk_a" if int(float(b["walk"]) / 34.0) % 2 == 0 else "walk_b"
	var tx: Texture2D = _tex["%d_%s" % [id, pose]]
	var face := float(b["face"])
	var s := 0.54
	c.draw_set_transform(g + Vector2(0, -bz), rot, Vector2(s * face, s))
	c.draw_texture(tx, Vector2(-128, -256))
	c.draw_set_transform(Vector2.ZERO)
	var nm := "TOI" if id == me_id else Net.name_of(id)
	UI.text(c, g + Vector2(0, -bz - 150), nm, 18 if id == me_id else 15, UI.YELLOW if id == me_id else TEAM_COLS[tm].lightened(0.1), 5)
	if (st & 2) != 0:
		for k in 3:
			var a := t * 6.0 + TAU * k / 3.0
			c.draw_circle(g + Vector2(cos(a) * 30.0, -bz - 128 + sin(a) * 8.0), 6.0, UI.YELLOW)


func _ellipse(c: CanvasItem, ctr: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 32:
		var a := TAU * k / 32.0
		pts.append(ctr + Vector2(cos(a) * rx, sin(a) * ry))
	c.draw_colored_polygon(pts, col)


func _ellipse_line(c: CanvasItem, ctr: Vector2, rx: float, ry: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for k in 33:
		var a := TAU * k / 32.0
		pts.append(ctr + Vector2(cos(a) * rx, sin(a) * ry))
	c.draw_polyline(pts, col, w, true)


# ------------------------------------------------------------------ HUD
func _draw_team_panel(h: CanvasItem, tm: int, x: float) -> void:
	var col: Color = TEAM_COLS[tm]
	var r := Rect2(Vector2(x, 14), Vector2(300, 112))
	UI.panel(h, r, col, UI.WHITE, 22, 6)
	UI.text(h, r.position + Vector2(150, 22), "Équipe %s" % TEAM_NAMES[tm], 22, UI.WHITE, 6)
	# têtes
	var tl: Array = teams[tm]
	for k in tl.size():
		var id: int = tl[k]
		var hc := r.position + Vector2(28 + k * 36, 66)
		h.draw_circle(hc, 17.0, UI.WHITE)
		h.draw_texture_rect_region(_tex["%d_front" % id], Rect2(hc - Vector2(16, 15), Vector2(32, 28)), Rect2(66, 104, 124, 96))
		if id == me_id:
			UI.text(h, hc + Vector2(0, 26), "TOI", 12, UI.YELLOW, 4)
	# 4 cases de paires
	var syms: Array = won_syms[tm]
	for k in WIN_PAIRS:
		var sc := r.position + Vector2(176 + k * 32, 66)
		h.draw_style_box(UI.box(Color(1, 1, 1, 0.9) if k < syms.size() else Color(1, 1, 1, 0.35), Color(0, 0, 0, 0), 0, 8), Rect2(sc - Vector2(14, 18), Vector2(28, 36)))
		if k < syms.size():
			h.draw_texture_rect(_tex[str(syms[k])], Rect2(sc - Vector2(12, 12), Vector2(24, 24)), false)
	UI.text(h, r.position + Vector2(232, 100), "%d / %d paires" % [int(pairs[tm]), WIN_PAIRS], 15, UI.WHITE, 4)


func _draw_hud() -> void:
	var h := hud
	var St := preload("res://minigames/stage.gd")
	if state == "intro":
		var lines := [
			"2 équipes ! 18 cartes face cachée sont posées au sol.",
			"Saute puis frappe le sol (Espace en l'air) pour retourner une carte.",
			"2 cartes pareilles retournées par ton équipe = une paire !",
			"Retiens les cartes des autres... et assomme-les en frappant le sol !",
			"La première équipe à 4 paires gagne !"]
		if referee != 0:
			lines.append("%s est l'arbitre (nombre impair) : gagné d'office !" % Net.name_of(referee))
		lines.append(_team_line())
		St.draw_intro(h, "Mémo-boum !", lines, "Bouger : flèches ou Z Q S D   ·   Sauter : Espace   ·   Frapper le sol : Espace en l'air")
		St.draw_ready_row(h, my_ready, ready_ids, ids, t, not ids.has(me_id))
		if str(Net.mg_data.get("mode", "")) == "duel":
			St.draw_duel_banner(h)
		return
	_draw_team_panel(h, 1, 20)
	_draw_team_panel(h, 2, 1280 - 320)
	var left := maxi(0, ceili(MAX_T - play_t))
	var tr := Rect2(Vector2(580, 18), Vector2(120, 52))
	UI.panel(h, tr, UI.WHITE, Color("#e4e2f2"), 18, 4)
	UI.text(h, tr.get_center(), "%d:%02d" % [left / 60, left % 60], 28, UI.RED if left <= 15 else UI.DARK, 0)
	if banner_t > 0.0:
		var a := minf(1.0, banner_t * 3.0)
		UI.text(h, Vector2(640, 104), banner, 30, Color(banner_col.lightened(0.15), a), 8)
	# rappel de la première carte de mon équipe
	if playing and state == "play" and int(team_first[my_team]) >= 0:
		var msg := "Trouvez l'autre carte !"
		var mw := UI.text_width(msg, 22) + 90.0
		var rr := Rect2(Vector2(640 - mw / 2.0, 662), Vector2(mw, 48))
		UI.panel(h, rr, UI.WHITE, TEAM_COLS[my_team], 22, 5)
		h.draw_texture_rect(_tex[str(card_sym[int(team_first[my_team])])], Rect2(rr.position + Vector2(14, 6), Vector2(36, 36)), false)
		UI.text(h, rr.get_center() + Vector2(24, 0), msg, 22, UI.DARK, 0)
	if not playing and state == "play":
		var msg2 := "Tu es l'arbitre : gagné d'office !" if me_id == referee else "Tu regardes le duel !"
		var mw2 := UI.text_width(msg2, 22) + 50.0
		h.draw_style_box(UI.box(Color(UI.DARK, 0.8), UI.DARK, 0, 16), Rect2(Vector2(640 - mw2 / 2.0, 664), Vector2(mw2, 44)))
		UI.text(h, Vector2(640, 686), msg2, 22, UI.WHITE, 0)
	if state == "count":
		UI.text(h, Vector2(640, 380), str(3 - int(t)), int(110 * (1.0 + (1.0 - fmod(t, 1.0)) * 0.3)), UI.WHITE, 16)
	elif state == "play" and t < 1.0:
		UI.text(h, Vector2(640, 380), "GO !", int(120 * (1.0 + t * 0.4)), Color(UI.YELLOW, 1.0 - t), 18)
	if state == "over":
		h.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, minf(0.4, t)))
		var w := 0
		if int(pairs[1]) != int(pairs[2]):
			w = 1 if int(pairs[1]) > int(pairs[2]) else 2
		UI.text(h, Vector2(640, 330), "TERMINÉ !", 96, UI.YELLOW, 16)
		if w != 0:
			UI.text(h, Vector2(640, 420), "L'équipe %s gagne !" % TEAM_NAMES[w], 44, TEAM_COLS[w].lightened(0.2), 10)


func _team_line() -> String:
	var parts := []
	for tm in [1, 2]:
		var names := []
		for id in teams[tm]:
			names.append("TOI" if id == me_id else Net.name_of(id))
		parts.append("%s : %s" % [TEAM_NAMES[tm].capitalize(), ", ".join(names)])
	return "   ·   ".join(parts)
