extends "res://minigames/stage.gd"
## « Mémo-boum ! » (Memory Mash, Mario Party DS) : le sol est fait de cartes face cachée.
## On saute et on retombe en piqué (↓) sur une carte pour la retourner. Deux cartes pareilles
## à la suite = une paire gagnée. Tout le monde voit les cartes retournées par les autres.
## L'hôte arbitre : qui retourne quoi, les paires, et quand les cartes se recachent.

const GROUND := 600.0
const UPPER := 420.0
const PITCH := 80.0
const CARD := Vector2(72, 86)
const SYMS := ["star", "heart", "coin", "gem_blue", "gem_orange", "gem_green", "key", "mushroom", "bomb", "lock", "flag", "cupcake"]
const FIRST_TIMEOUT := 5.0     # une première carte seule se recache au bout de 5 s
const MISS_SHOW := 1.1         # deux cartes différentes restent visibles 1,1 s
const MATCH_SHOW := 0.7

var cards: Array = []          # {sym, x, y, row}
var cstate: Array = []         # 0 caché, 1 visible, 2 gagné
var cowner: Array = []         # qui l'a retournée / gagnée
var cchange: Array = []        # moment du dernier changement (animation)
var pairs := {}                # id -> paires
var sym_tex := {}
var back_tex: Texture2D
var card_layer: Node2D
var air_t := 0.0
var pound := false
var was_floor := true
var my_first := -1
var banner := ""
var banner_t := 0.0
var banner_col := UI.WHITE
# hôte
var h_first := {}              # id -> [carte, temps]
var h_timers: Array = []       # {t, act, cards, id}
var h_done := false
# robots
var bot_seen := {}             # carte -> symbole déjà vu
var bot_target := -1
var bot_t := 0.0
var bot_dj := false


func _setup() -> void:
	title = "Mémo-boum !"
	rules = "Le sol est fait de cartes face cachée !\nSaute puis retombe en piqué (↓) sur une carte pour la retourner.\nRetourne 2 cartes pareilles à la suite pour gagner la paire.\nRetiens bien les cartes que les autres découvrent... Le plus de paires gagne !"
	controls = "Bouger : Q D / ← →   ·   Sauter : Espace (x2)   ·   Retourner : ↓ en l'air   ·   Pousser : Maj / X"
	duration = 90.0
	show_heads = false
	var n := 0
	for id in Net.mg_data.get("players", Net.players.keys()):
		if Net.players.has(id):
			n += 1
	var big := n >= 5
	var bottom := 12 if big else 8
	var side := 6 if big else 4
	var x0 := 640.0 - bottom * PITCH / 2.0
	for i in bottom:
		cards.append({"x": x0 + i * PITCH + PITCH / 2.0, "y": GROUND, "row": 0})
	var lx := 340.0 - side * PITCH / 2.0
	var rx := 940.0 - side * PITCH / 2.0
	for i in side:
		cards.append({"x": lx + i * PITCH + PITCH / 2.0, "y": UPPER, "row": 1})
	for i in side:
		cards.append({"x": rx + i * PITCH + PITCH / 2.0, "y": UPPER, "row": 2})
	# tirage commun des symboles
	var pool := SYMS.duplicate()
	for k in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp = pool[k]
		pool[k] = pool[j]
		pool[j] = tmp
	var deck := []
	for k in cards.size() / 2:
		deck.append(pool[k])
		deck.append(pool[k])
	for k in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp = deck[k]
		deck[k] = deck[j]
		deck[j] = tmp
	for i in cards.size():
		cards[i]["sym"] = deck[i]
		cstate.append(0)
		cowner.append(0)
		cchange.append(-10.0)
	for s in SYMS:
		sym_tex[s] = load("res://assets/cards/%s.png" % s)
	var sp := []
	for i in 8:
		sp.append(Vector2(640.0 + (i - 3.5) * 90.0, GROUND))
	spawn_points = sp


func _build_level() -> void:
	# sol d'herbe sur les côtés, terre sous les cartes, murs invisibles
	var left_w := int(ceil((float(cards[0]["x"]) - PITCH / 2.0) / T))
	island(0, GROUND, left_w + 1)
	island(int((1280.0 - (float(cards[0]["x"]) - PITCH / 2.0)) / T) - 1, GROUND, left_w + 2)
	var bx0 := float(cards[0]["x"]) - PITCH / 2.0
	var nb := 0
	for c in cards:
		if int(c["row"]) == 0:
			nb += 1
	solid(Rect2(bx0, GROUND + 4, nb * PITCH, 200))
	for row in [1, 2]:
		var xs := []
		for c in cards:
			if int(c["row"]) == row:
				xs.append(float(c["x"]))
		solid(Rect2(float(xs[0]) - PITCH / 2.0, UPPER + 2, xs.size() * PITCH, 20), true)
	solid(Rect2(-40, -400, 40, 1400))
	solid(Rect2(1280, -400, 40, 1400))
	for d in [[40, "bush"], [1200, "mushroom_red"]]:
		tile(d[1], Vector2(float(d[0]), GROUND - T))
	card_layer = Node2D.new()
	card_layer.z_index = 2
	card_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	world.add_child(card_layer)
	card_layer.draw.connect(_draw_cards)


func _on_start() -> void:
	for id in nodes:
		pairs[id] = 0


# ------------------------------------------------------------------ retourner une carte
func _card_under(p: Vector2) -> int:
	for i in cards.size():
		var c: Dictionary = cards[i]
		if absf(p.y - float(c["y"])) < 16.0 and absf(p.x - float(c["x"])) < PITCH / 2.0:
			return i
	return -1


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state != "play" or me == null or me.dead:
		was_floor = true
		return
	if me.is_bot:
		_bot_think(delta)
	var on_floor := me.is_on_floor()
	if not on_floor:
		air_t += delta
		var down := Input.is_action_pressed("down") if not me.is_bot else bool(me.get_meta("goal_down", false))
		if down and me.velocity.y > -100.0:
			pound = true
	elif not was_floor:
		if pound and air_t > 0.1:
			_pound()
		air_t = 0.0
		pound = false
	was_floor = on_floor


func _pound() -> void:
	fx.dust(me.position, 6, 1.2)
	fx.shake(4.0)
	Sfx.play("bump", -4.0, 0.1)
	var i := _card_under(me.position)
	if i >= 0 and cstate[i] == 0:
		Net.mg_to_host({"flip": i})


# ------------------------------------------------------------------ hôte
func _on_mg_msg(from_id: int, data: Dictionary) -> void:
	if not Net.is_host() or state != "play" or h_done or not data.has("flip"):
		return
	var i := int(data["flip"])
	if i < 0 or i >= cards.size() or cstate[i] != 0:
		return
	var ev := {}
	if h_first.has(from_id) and cstate[int(h_first[from_id][0])] == 1 and cowner[int(h_first[from_id][0])] == from_id:
		var a := int(h_first[from_id][0])
		h_first.erase(from_id)
		cstate[i] = 1
		cowner[i] = from_id
		if str(cards[a]["sym"]) == str(cards[i]["sym"]):
			h_timers.append({"t": MATCH_SHOW, "act": "match", "cards": [a, i], "id": from_id})
			ev = {"kind": "flip2", "id": from_id, "card": i}
		else:
			h_timers.append({"t": MISS_SHOW, "act": "hide", "cards": [a, i], "id": from_id})
			ev = {"kind": "flip2", "id": from_id, "card": i}
	else:
		h_first[from_id] = [i, play_t]
		cstate[i] = 1
		cowner[i] = from_id
		ev = {"kind": "flip1", "id": from_id, "card": i}
	_broadcast(ev)


func _host_step(dt: float) -> void:
	for tm in h_timers.duplicate():
		tm["t"] = float(tm["t"]) - dt
		if float(tm["t"]) > 0.0:
			continue
		h_timers.erase(tm)
		var cs: Array = tm["cards"]
		var id := int(tm["id"])
		if str(tm["act"]) == "match":
			for c in cs:
				cstate[int(c)] = 2
				cowner[int(c)] = id
			pairs[id] = int(pairs.get(id, 0)) + 1
			_broadcast({"kind": "match", "id": id, "cards": cs})
		else:
			for c in cs:
				cstate[int(c)] = 0
				cowner[int(c)] = 0
			_broadcast({"kind": "miss", "id": id, "cards": cs})
	for id in h_first.keys():
		var a := int(h_first[id][0])
		if play_t - float(h_first[id][1]) > FIRST_TIMEOUT:
			h_first.erase(id)
			if cstate[a] == 1:
				cstate[a] = 0
				cowner[a] = 0
				_broadcast({"kind": "timeout", "id": id, "cards": [a]})
	if not h_done and not cstate.has(0) and not cstate.has(1) and h_timers.is_empty():
		h_done = true
		if Net.autotest != "":
			print("[memory] all pairs t=", snappedf(play_t, 0.1), " ", pairs)
		Net.mg_end_with_scores(host_scores())


func _broadcast(ev: Dictionary) -> void:
	var pk := {}
	for id in pairs:
		pk[id] = pairs[id]
	Net.mg_broadcast({"cs": cstate.duplicate(), "own": cowner.duplicate(), "pairs": pk, "ev": ev})


func host_scores() -> Dictionary:
	var out := {}
	for id in nodes:
		var n := int(pairs.get(id, 0))
		out[id] = [float(n), "%d paire%s" % [n, "s" if n > 1 else ""]]
	return out


func _on_mg_state(data: Dictionary) -> void:
	if not data.has("cs"):
		return
	var ncs: Array = data["cs"]
	var nown: Array = data["own"]
	for i in mini(ncs.size(), cards.size()):
		if int(ncs[i]) != int(cstate[i]):
			cchange[i] = play_t
			if int(ncs[i]) >= 1:
				bot_seen[i] = str(cards[i]["sym"])
		cstate[i] = int(ncs[i])
		cowner[i] = int(nown[i])
	var pk: Dictionary = data["pairs"]
	for id in pk:
		pairs[int(id)] = int(pk[id])
	var ev: Dictionary = data.get("ev", {})
	var kind := str(ev.get("kind", ""))
	var who := int(ev.get("id", 0))
	if kind == "flip1" or kind == "flip2":
		var c: Dictionary = cards[int(ev["card"])]
		Sfx.play("card_slide", -2.0)
		fx.stars(Vector2(float(c["x"]), float(c["y"]) + 30.0), 4)
		if who == Net.my_id():
			my_first = int(ev["card"]) if kind == "flip1" else -1
	elif kind == "match":
		var cs: Array = ev["cards"]
		for ci in cs:
			var c2: Dictionary = cards[int(ci)]
			fx.ring(Vector2(float(c2["x"]), float(c2["y"]) + 40.0), Net.color_of(who))
			fx.stars(Vector2(float(c2["x"]), float(c2["y"]) + 20.0), 8)
		Sfx.play("jingle_good" if who == Net.my_id() else "coin", -2.0 if who == Net.my_id() else -6.0, 0.0)
		_say("%s : une paire !" % ("TOI" if who == Net.my_id() else Net.name_of(who)), Net.color_of(who))
	elif kind == "miss":
		if who == Net.my_id():
			Sfx.play("ui_error", -6.0, 0.0)
	elif kind == "timeout":
		if who == Net.my_id():
			my_first = -1


func _say(text: String, col: Color) -> void:
	banner = text
	banner_col = col
	banner_t = 1.6


# ------------------------------------------------------------------ robots
func _bot_think(dt: float) -> void:
	bot_t -= dt
	# cible valide ?
	if bot_target >= 0 and cstate[bot_target] != 0:
		bot_target = -1
	if bot_target < 0 or bot_t <= 0.0:
		bot_t = randf_range(2.0, 4.0)
		var choices := []
		# une paire connue : la carte qui va avec ma première carte, sinon deux cartes déjà vues
		if my_first >= 0:
			for i in bot_seen:
				if i != my_first and cstate[i] == 0 and str(bot_seen[i]) == str(cards[my_first]["sym"]):
					choices = [i]
		if choices.is_empty():
			for i in cards.size():
				if cstate[i] == 0:
					choices.append(i)
		if choices.is_empty():
			me.set_meta("goal_x", me.position.x)
			me.set_meta("goal_down", false)
			return
		bot_target = choices[randi() % choices.size()]
		bot_dj = false
	var c: Dictionary = cards[bot_target]
	var gx := float(c["x"])
	var gy := float(c["y"])
	me.set_meta("goal_x", gx)
	var close := absf(me.position.x - gx) < 16.0
	var above := me.position.y <= gy + 6.0
	me.set_meta("goal_jump", close and me.is_on_floor() and (above or gy < me.position.y - 20.0) or (gy < me.position.y - 20.0 and absf(me.position.x - gx) < 60.0 and me.is_on_floor()))
	if me.is_on_floor():
		bot_dj = false
	elif gy < me.position.y - 20.0 and not bot_dj and me.velocity.y > -150.0:
		bot_dj = true
		me.set_meta("jump_now", true)
	me.set_meta("goal_down", (close or absf(me.position.x - gx) < 30.0 and me.velocity.y > 200.0) and me.position.y < gy - 10.0)


# ------------------------------------------------------------------ dessin
func _process(delta: float) -> void:
	super._process(delta)
	if state == "play" and Net.is_host():
		_host_step(delta)
	banner_t = maxf(0.0, banner_t - delta)
	card_layer.queue_redraw()
	if Net.autotest != "" and state == "play" and int(play_t / 10.0) != int((play_t - delta) / 10.0):
		print("[memory] t=", int(play_t), " real=", Time.get_ticks_msec() / 1000, " fps=", Engine.get_frames_per_second(), " pairs=", pairs, " left=", cstate.count(0))


func _draw_cards() -> void:
	var c := card_layer
	# terre sous la rangée du bas
	var bx0 := float(cards[0]["x"]) - PITCH / 2.0
	var nb := 0
	for cd in cards:
		if int(cd["row"]) == 0:
			nb += 1
	c.draw_rect(Rect2(bx0, GROUND + 70, nb * PITCH, 120), Color("#c58b52"))
	c.draw_rect(Rect2(bx0, GROUND + 70, nb * PITCH, 10), Color("#a8713f"))
	for row in [1, 2]:
		var xs := []
		for cd in cards:
			if int(cd["row"]) == row:
				xs.append(float(cd["x"]))
		var r := Rect2(float(xs[0]) - PITCH / 2.0 - 10.0, UPPER + 60.0, xs.size() * PITCH + 20.0, 26)
		c.draw_style_box(UI.box(Color("#9bd065"), Color("#6aa83e"), 4, 12), r)
	for i in cards.size():
		_draw_card(c, i)


func _draw_card(c: CanvasItem, i: int) -> void:
	var cd: Dictionary = cards[i]
	var top := Vector2(float(cd["x"]), float(cd["y"]))
	var st := int(cstate[i])
	var age := play_t - float(cchange[i])
	# retournement : la carte s'écrase à l'horizontale puis revient
	var sx := 1.0
	var show_face := st >= 1
	if age < 0.24:
		var k := age / 0.24
		sx = absf(cos(k * PI))
		if k < 0.5:
			show_face = not show_face
	var r := Rect2(top + Vector2(-CARD.x * sx / 2.0, 0), Vector2(CARD.x * sx, CARD.y))
	c.draw_style_box(UI.box(Color(0.15, 0.1, 0.3, 0.25), Color(0, 0, 0, 0), 0, 12), Rect2(r.position + Vector2(0, 5), r.size))
	if not show_face:
		c.draw_style_box(UI.box(Color("#8e6cf0"), UI.WHITE, 5, 12), r)
		if sx > 0.3:
			var inner := r.grow(-11)
			c.draw_style_box(UI.box(Color("#a487f5"), Color(0, 0, 0, 0), 0, 8), inner)
			for k in 3:
				for m in 4:
					var p := inner.position + Vector2((k + 0.5) * inner.size.x / 3.0, (m + 0.5) * inner.size.y / 4.0)
					c.draw_circle(p, 3.0 * sx, Color(1, 1, 1, 0.35))
			UI.text(c, r.get_center() + Vector2(0, 2), "?", int(34 * sx) + 1, UI.WHITE, 6)
		# petite marque si c'est ma cible (aide pour viser)
		if me and not me.dead and state == "play" and _card_under(me.position + Vector2(0, 2)) == i:
			c.draw_rect(Rect2(r.position + Vector2(8, -6), Vector2(r.size.x - 16, 5)), Color(UI.YELLOW, 0.9))
	else:
		var won := st == 2
		var ow := int(cowner[i])
		var border := Net.color_of(ow) if ow != 0 and Net.players.has(ow) else UI.WHITE
		c.draw_style_box(UI.box(Color("#fffaf2") if not won else border.lerp(Color.WHITE, 0.65), border, 6, 12), r)
		if sx > 0.15:
			var tx: Texture2D = sym_tex[str(cd["sym"])]
			var sz := 58.0
			var pop := 1.0 + (0.25 * sin(clampf(age / 0.4, 0.0, 1.0) * PI) if age < 0.4 else 0.0)
			c.draw_texture_rect(tx, Rect2(r.get_center() - Vector2(sz * sx * pop, sz * pop) / 2.0, Vector2(sz * sx * pop, sz * pop)), false, Color(1, 1, 1, 0.85 if won else 1.0))
		if won and ow != 0 and sx > 0.8:
			c.draw_circle(r.position + Vector2(r.size.x - 10, 10), 9.0, border)
			c.draw_circle(r.position + Vector2(r.size.x - 10, 10), 5.0, UI.WHITE)


func _draw_extra_hud() -> void:
	draw_timer()
	if state == "intro":
		return
	# tableau des paires
	var ids := nodes.keys()
	ids.sort_custom(func(a, b): return int(pairs.get(a, 0)) > int(pairs.get(b, 0)) or int(pairs.get(a, 0)) == int(pairs.get(b, 0)) and a < b)
	var w := 96.0
	var x0 := 640.0 - ids.size() * (w + 8.0) / 2.0
	for i in ids.size():
		var id: int = ids[i]
		var r := Rect2(Vector2(x0 + i * (w + 8.0), 18), Vector2(w, 52))
		var col := Net.color_of(id)
		hud.draw_style_box(UI.box(UI.WHITE, col if id == Net.my_id() else UI.DARK, 4, 14), r)
		hud.draw_set_transform(r.position + Vector2(24, 48), 0.0, Vector2(0.17, 0.17))
		hud.draw_texture(UI.char_tex(Net.color_idx(id), "idle"), Vector2(-128, -256))
		hud.draw_set_transform(Vector2.ZERO)
		UI.text(hud, r.position + Vector2(68, 26), str(int(pairs.get(id, 0))), 28, col.darkened(0.25), 0)
		if id == Net.my_id():
			hud.draw_rect(Rect2(r.position + Vector2(10, 56), Vector2(w - 20, 5)), col)
	# rappel de ma première carte
	if my_first >= 0 and state == "play":
		var msg := "Trouve l'autre carte !"
		var mw := UI.text_width(msg, 22) + 90.0
		var rr := Rect2(Vector2(640 - mw / 2.0, 646), Vector2(mw, 50))
		UI.panel(hud, rr, UI.WHITE, Net.color_of(Net.my_id()), 22, 5)
		hud.draw_texture_rect(sym_tex[str(cards[my_first]["sym"])], Rect2(rr.position + Vector2(14, 7), Vector2(36, 36)), false)
		UI.text(hud, rr.get_center() + Vector2(24, 0), msg, 22, UI.DARK, 0)
	if banner_t > 0.0:
		var a := minf(1.0, banner_t * 3.0)
		UI.text(hud, Vector2(640, 118), banner, 34, Color(banner_col.lightened(0.2), a), 9)
