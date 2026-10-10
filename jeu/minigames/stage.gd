extends Node2D
## Base commune des mini-jeux de plateforme : décor, persos, poussées, intro avec règles,
## élimination ou réapparition, HUD. Chaque mini-jeu redéfinit _setup, _build_level,
## _on_start, _update, et éventuellement host_scores / _on_mg_msg / _on_mg_state.

const Player := preload("res://arena/player.gd")
const Fx := preload("res://arena/fx.gd")
const Backdrop := preload("res://screens/backdrop.gd")
const T := 64.0

var world: Node2D
var players_node: Node2D
var fx: Node2D
var me: Player
var nodes: Dictionary = {}
var hud: Control
var cam: Camera2D
var rng := RandomNumberGenerator.new()

var state := "intro"   # intro, play, over
var t := 0.0
var play_t := 0.0
var intro_len := 6.0
var duration := 60.0
var title := ""
var rules := ""
var controls := "Bouger : Q D / ← →   ·   Sauter : Espace (x2)   ·   Pousser : Maj / X / clic"
var spawn_points: Array = []
var respawn_points: Array = []
var out_ids: Dictionary = {}
var my_out := false
var my_out_time := 0.0
var go_flash := 0.0
var star_tex: Texture2D = load("res://assets/tiles/star.png")

# options des mini-jeux
var contact := true            # poussées / sauts sur la tête entre joueurs
var respawn_on_fall := false   # true : on réapparaît au lieu d'être éliminé
var ghosts := false            # true : les autres sont transparents (chacun sa course)
var follow_cam := false        # true : la caméra suit mon perso
var cam_offset := Vector2(0, -120)
var cam_limits := Rect2(0, 0, 1280, 720)
var show_heads := true
var respawn_t := 0.0
var springs: Array = []
var my_ready := false
var go_received := false
var ready_ids: Array = []
var spectating := false      # true quand on a fini (arrivé) : la caméra suit les autres
var spec_id := 0


func _ready() -> void:
	rng.seed = int(Net.mg_data.get("seed", 1))
	_setup()
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	var themes := ["colored_grass", "colored_desert", "colored_shroom", "colored_land"]
	bg_layer.add_child(Backdrop.new("theme:" + themes[absi(int(Net.mg_data.get("seed", 0))) % themes.size()]))
	world = Node2D.new()
	add_child(world)
	_build_level()
	players_node = Node2D.new()
	world.add_child(players_node)
	fx = Fx.new()
	fx.world = world
	world.add_child(fx)
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 5
	add_child(ui_layer)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	ui_layer.add_child(hud)

	var ids: Array = []
	for id in Net.mg_data.get("players", Net.players.keys()):
		if Net.players.has(id):
			ids.append(id)
	ids.sort()
	for i in ids.size():
		var id: int = ids[i]
		var p: Player = Player.new()
		var local: bool = id == Net.my_id()
		p.setup(id, local, Net.color_idx(id), fx)
		nodes[id] = p
		players_node.add_child(p)
		p.position = spawn_points[i % spawn_points.size()]
		p.visible = true
		p.remote_has_data = not local
		if ghosts and not local:
			p.modulate.a = 0.45
		if local:
			me = p
			p.set_meta("blocked", true)
			p.facing = 1 if p.position.x < 640 else -1
			p.died.connect(_on_me_died)
			p.z_index = 7
	if follow_cam:
		cam = Camera2D.new()
		cam.limit_left = int(cam_limits.position.x)
		cam.limit_top = int(cam_limits.position.y)
		cam.limit_right = int(cam_limits.end.x)
		cam.limit_bottom = int(cam_limits.end.y)
		cam.position_smoothing_enabled = true
		cam.position_smoothing_speed = 7.0
		world.add_child(cam)
		cam.make_current()
		if me:
			cam.position = me.position + cam_offset
			cam.reset_smoothing()
	Net.remote_state.connect(_on_remote_state)
	Net.got_hit.connect(_on_got_hit)
	Net.hit_fx.connect(_on_hit_fx)
	Net.mg_player_out.connect(_on_player_out)
	Net.mg_ending.connect(_on_ending)
	Net.players_changed.connect(_on_players_changed)
	Net.mg_msg.connect(_on_mg_msg)
	Net.mg_state.connect(_on_mg_state)
	Net.mg_ready_changed.connect(func(ids): ready_ids = ids)
	Net.mg_go.connect(func(): go_received = true)


func _on_got_hit(kind: int, dir: Vector2, from_id: int) -> void:
	if me and state == "play" and contact:
		me.receive_hit(kind, dir, from_id)


func _on_ending() -> void:
	state = "over"
	t = 0.0
	Sfx.play("bell", -2.0, 0.0)


# --- à redéfinir
func _setup() -> void:
	pass

func _build_level() -> void:
	pass

func _on_start() -> void:
	pass

func _update(_delta: float) -> void:
	pass

func _draw_extra_hud() -> void:
	pass

## Côté hôte, à la fin du chrono : {} = classement par élimination, sinon id -> [score, texte].
func host_scores() -> Dictionary:
	return {}

func _on_mg_msg(_from_id: int, _data: Dictionary) -> void:
	pass

func _on_mg_state(_data: Dictionary) -> void:
	pass


# ------------------------------------------------------------------ outils de décor
func tile(n: String, pos: Vector2, parent: Node2D = null, sc := 0.5) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load("res://assets/tiles/%s.png" % n)
	s.centered = false
	s.position = pos
	s.scale = Vector2(sc, sc)
	(parent if parent else world).add_child(s)
	return s


func solid(r: Rect2, oneway := false) -> StaticBody2D:
	var b := StaticBody2D.new()
	b.collision_layer = 2 if oneway else 1
	b.collision_mask = 0
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = r.size
	cs.shape = rs
	cs.position = r.get_center()
	cs.one_way_collision = oneway
	b.add_child(cs)
	world.add_child(b)
	return b


func island(x0: int, y: float, w: int) -> void:
	if w == 1:
		tile("terrain_grass_vertical_top", Vector2(x0 * T, y))
		tile("terrain_grass_vertical_bottom", Vector2(x0 * T, y + T))
		solid(Rect2(x0 * T + 4, y + 4, T - 8, 2 * T - 10))
		return
	for i in w:
		var top := "terrain_grass_block_top"
		var bot := "terrain_grass_block_bottom"
		if i == 0:
			top += "_left"
			bot += "_left"
		elif i == w - 1:
			top += "_right"
			bot += "_right"
		tile(top, Vector2((x0 + i) * T, y))
		tile(bot, Vector2((x0 + i) * T, y + T))
	solid(Rect2(x0 * T + 2, y + 4, w * T - 4, 2 * T - 10))


func thin(x0: int, y: float, w: int) -> void:
	for i in w:
		var n := "terrain_grass_horizontal_"
		if w == 1:
			n += "middle"
		elif i == 0:
			n += "left"
		elif i == w - 1:
			n += "right"
		else:
			n += "middle"
		tile(n, Vector2((x0 + i) * T, y))
	solid(Rect2(x0 * T + 2, y + 4, w * T - 4, 20), true)


func spring(tx: int, ground_y: float) -> void:
	var s := tile("spring_out", Vector2(tx * T, ground_y - T))
	solid(Rect2(tx * T + 12, ground_y - 22, 40, 22))
	springs.append({"sprite": s, "trig": Rect2(tx * T + 4, ground_y - 40, 56, 22), "t": 0.0,
		"center": Vector2(tx * T + 32, ground_y - 24)})


func splash_y() -> float:
	return cam_limits.end.y - 30.0 if follow_cam else 690.0


# ------------------------------------------------------------------ boucle
func _process(delta: float) -> void:
	t += delta
	go_flash = maxf(0.0, go_flash - delta)
	match state:
		"intro":
			# chacun appuie sur Espace quand il est prêt ; l'hôte donne le départ
			if not my_ready and t > 0.6 and me != null:
				var bot_ready := me != null and me.is_bot and t > 1.0 and OS.get_environment("NOREADY") == ""
				if bot_ready or Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("push"):
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
				go_flash = 0.8
				if me:
					me.set_meta("blocked", false)
				Sfx.voice("go")
				_on_start()
		"play":
			play_t += delta
			_update(delta)
			if respawn_t > 0.0:
				respawn_t -= delta
				if respawn_t <= 0.0 and me and me.dead:
					me.respawn(_pick_respawn())
			if play_t >= duration and Net.is_host():
				var sc := host_scores()
				if sc.is_empty():
					Net.report_time_up()
				else:
					Net.mg_end_with_scores(sc)
		"over":
			if me:
				me.set_meta("blocked", true)
	if cam:
		var target: Node2D = me
		if follow_cam and (my_out or spectating or me == null):
			var st := _spec_target()
			if st != null:
				target = st
			if Input.is_action_just_pressed("left") or Input.is_action_just_pressed("right"):
				_spec_cycle(1 if Input.is_action_just_pressed("right") else -1)
		if target != null:
			cam.position = target.position + cam_offset
	for sp in springs:
		sp["t"] = maxf(0.0, float(sp["t"]) - delta)
		(sp["sprite"] as Sprite2D).texture = load("res://assets/tiles/spring.png") if float(sp["t"]) > 0.17 else load("res://assets/tiles/spring_out.png")
	hud.queue_redraw()


func _physics_process(delta: float) -> void:
	if state != "play" or me == null or me.dead:
		return
	for sp in springs:
		if me.velocity.y >= 0.0 and (sp["trig"] as Rect2).has_point(me.position):
			me.spring_bounce()
			sp["t"] = 0.25
			Net.send_fx(sp["center"], 3)
	if not contact:
		return
	for id in nodes:
		var o: Player = nodes[id]
		if o == me or not o.visible or o.dead:
			continue
		var d: Vector2 = o.position - me.position
		var protected: bool = o.remote_invuln()
		var head_y: float = o.position.y - o.HEIGHT
		if me.velocity.y > 150.0 and absf(d.x) < 36.0 and me.position.y > head_y - 16.0 and me.position.y < head_y + 26.0:
			me.velocity.y = -760.0
			me.air_jumps = 1
			me.jump_cut_ok = false
			me.squash = Vector2(1.3, 0.75)
			Sfx.play("bump", -3.0)
			if not protected:
				Net.send_hit(id, 1, Vector2.ZERO)
				Net.send_fx(Vector2(o.position.x, head_y), 1)
				fx.stars(Vector2(o.position.x, head_y), 4)
			continue
		if me.push_t > 0.0 and not me.hit_ids.has(id) and not protected:
			var ahead: float = d.x * me.facing
			if ahead > -14.0 and ahead < 80.0 and absf(d.y) < 60.0:
				me.hit_ids[id] = true
				Net.send_hit(id, 0, Vector2(me.facing * me.KNOCK.x, me.KNOCK.y))
				var hp: Vector2 = o.position + Vector2(-me.facing * 10.0, -36.0)
				Net.send_fx(hp, 1)
				fx.stars(hp, 6)
				fx.shake(5.0)
				Sfx.play("bump", 0.0)
				me.hitstop = 0.07
				me.velocity.x = -me.facing * 150.0
				me.push_t = 0.0
		if absf(d.x) < 40.0 and absf(d.y) < 56.0:
			var sx := signf(d.x) if d.x != 0.0 else 1.0
			me.velocity.x -= sx * 1500.0 * delta


# ------------------------------------------------------------------ élimination / réapparition
func eliminate_me(how: String) -> void:
	if my_out or me == null:
		return
	my_out = true
	my_out_time = play_t
	if Net.autotest != "":
		print("[out] ", how, " t=", snappedf(play_t, 0.01), " x=", int(me.position.x))
	if not me.dead:
		me.eliminate()
	Net.report_out(play_t, how)


func _on_me_died(_attacker: int) -> void:
	if respawn_on_fall:
		fx.splash(clampf(me.position.x, 60.0, 1220.0) if not follow_cam else me.position.x, me.color(), "PLOUF !", splash_y())
		respawn_t = 1.5
	else:
		eliminate_me("tombé")


func _pick_respawn() -> Vector2:
	var pts: Array = respawn_points if respawn_points.size() > 0 else spawn_points
	var best: Vector2 = pts[0]
	var best_d := -1.0
	for s in pts:
		var dmin := 1e9
		for id in nodes:
			var o: Player = nodes[id]
			if o != me and o.visible:
				dmin = minf(dmin, (s as Vector2).distance_to(o.position))
		dmin += randf() * 60.0
		if dmin > best_d:
			best_d = dmin
			best = s
	return best


## Spectateur : on suit un joueur encore en course (← → pour changer).
func _spec_candidates() -> Array:
	var out := []
	var ids := nodes.keys()
	ids.sort()
	for id in ids:
		var n: Player = nodes[id]
		if n != me and n.visible and not out_ids.has(id) and not _is_done(id):
			out.append(id)
	return out


## À redéfinir : vrai si ce joueur a déjà fini (arrivé), pour ne pas le suivre en spectateur.
func _is_done(_id: int) -> bool:
	return false


func _spec_target() -> Node2D:
	var c := _spec_candidates()
	if c.is_empty():
		return me
	if not c.has(spec_id):
		spec_id = c[0]
	return nodes[spec_id]


func _spec_cycle(dir: int) -> void:
	var c := _spec_candidates()
	if c.is_empty():
		return
	var i := c.find(spec_id)
	spec_id = c[(i + dir + c.size()) % c.size()]


func _on_player_out(id: int, how: String) -> void:
	out_ids[id] = how
	if nodes.has(id):
		var n: Player = nodes[id]
		var c := Net.color_of(id)
		if how == "écrasé":
			fx.stars(n.position + Vector2(0, -20), 6)
			fx.popup(n.position + Vector2(0, -60), "ÉCRASÉ !", c)
		else:
			fx.splash(clampf(n.position.x, 60.0, 1220.0) if not follow_cam else n.position.x, c, "PLOUF !", splash_y())
		if id != Net.my_id():
			Sfx.play("fall", -8.0)


func _on_remote_state(id: int, pos: Vector2, vel: Vector2, st: int) -> void:
	if nodes.has(id) and id != Net.my_id():
		nodes[id].push_snapshot(pos, vel, st)


func _on_hit_fx(pos: Vector2, kind: int) -> void:
	if kind == 1:
		fx.stars(pos, 5)
		Sfx.play("bump", -8.0)
	elif kind == 3:
		for sp in springs:
			if (sp["center"] as Vector2).distance_to(pos) < 40.0:
				sp["t"] = 0.25


func _on_players_changed() -> void:
	for id in nodes.keys():
		if not Net.players.has(id):
			nodes[id].queue_free()
			nodes.erase(id)


func alive_count() -> int:
	var n := 0
	for id in nodes:
		if not out_ids.has(id):
			n += 1
	return n


# ------------------------------------------------------------------ HUD
func draw_timer() -> void:
	if state == "intro":
		return
	var left := maxi(0, ceili(duration - play_t))
	var r := Rect2(Vector2(24, 18), Vector2(120, 52))
	UI.panel(hud, r, UI.WHITE, Color("#e4e2f2"), 18, 4)
	UI.text(hud, r.get_center(), "%d s" % left, 30, UI.RED if left <= 10 else UI.DARK, 0)


func _draw_hud() -> void:
	if show_heads:
		var hids := nodes.keys()
		hids.sort()
		draw_heads(hud, hids, out_ids)
	_draw_extra_hud()

	var center := Vector2(640, 360)
	if state == "intro":
		draw_intro(hud, title, Array(rules.split("\n")), controls)
		draw_ready_row(hud, my_ready, ready_ids, nodes.keys(), t, me == null)
		if str(Net.mg_data.get("mode", "")) == "duel":
			draw_duel_banner(hud)
	elif state == "count":
		var pulse := 1.0 + (1.0 - fmod(t, 1.0)) * 0.35
		UI.text(hud, center, str(3 - int(t)), int(110 * pulse), UI.WHITE, 16)
	elif go_flash > 0.0:
		var s := 1.0 + (0.8 - go_flash) * 0.6
		UI.text(hud, center, "GO !", int(110 * s), Color(UI.YELLOW, minf(1.0, go_flash * 2.0)), 18)
	if follow_cam and (my_out or spectating or me == null) and state == "play" and _spec_candidates().size() > 0:
		var who := Net.name_of(spec_id)
		var sm := "Tu regardes %s   (← → pour changer)" % who
		var sw := UI.text_width(sm, 20) + 40.0
		hud.draw_style_box(UI.box(Color(UI.DARK, 0.8), UI.DARK, 0, 14), Rect2(Vector2(640 - sw / 2.0, 588), Vector2(sw, 40)))
		UI.text(hud, Vector2(640, 608), sm, 20, UI.WHITE, 0)
	if my_out and state == "play":
		var msg := "Éliminé ! Tu as tenu %.1f s" % my_out_time
		var mw := UI.text_width(msg, 26) + 50.0
		UI.panel(hud, Rect2(Vector2(640 - mw / 2.0, 640), Vector2(mw, 50)), UI.WHITE, Color("#ffd0d0"), 20, 4)
		UI.text(hud, Vector2(640, 664), msg, 26, UI.RED, 0)
	if state == "over":
		hud.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, minf(0.4, t)))
		UI.text(hud, center, "TERMINÉ !", int(96 * minf(1.0, 0.6 + t * 2.0)), UI.YELLOW, 16)


## Têtes des joueurs en haut (barrées quand ils sont éliminés), façon Mario Party.
static func draw_heads(h: CanvasItem, ids: Array, out: Dictionary) -> void:
	var w := 64.0
	var x0 := 640.0 - ids.size() * w / 2.0
	for i in ids.size():
		var id: int = ids[i]
		var c := Vector2(x0 + i * w + w / 2.0, 44)
		var o := out.has(id)
		UI.portrait(h, c, 25.0, Net.color_idx(id), UI.WHITE, Color(0.6, 0.6, 0.66, 1.0) if o else Color.WHITE)
		if o:
			h.draw_line(c + Vector2(-15, -15), c + Vector2(15, 15), UI.RED, 6.0)
			h.draw_line(c + Vector2(15, -15), c + Vector2(-15, 15), UI.RED, 6.0)
		if id == Net.my_id():
			UI.text(h, c + Vector2(0, 38), "TOI", 14, UI.YELLOW, 5)


## Écran de présentation d'un mini-jeu, façon Mario Party : titre, aperçu, explication,
## encart « Commandes » à droite, puis les joueurs prêts et le bouton pour commencer.
static var _previews := {}

static func draw_intro(h: CanvasItem, ttl: String, lines: Array, ctrl: String) -> void:
	# fond pastel à pois
	h.draw_rect(Rect2(0, 0, 1280, 720), Color("#fbe3ec"))
	for k in 7:
		var c := Color("#fff4c9") if k % 2 == 0 else Color("#e6f1ff")
		h.draw_circle(Vector2(1280 + 60 - k * 40, -60 + k * 30), 420.0 - k * 50.0, Color(c, 0.35))
	for yy in range(0, 760, 46):
		for xx in range(0, 1320, 46):
			var off := 23.0 if (yy / 46) % 2 == 1 else 0.0
			h.draw_circle(Vector2(xx + off, yy), 4.0, Color(1, 1, 1, 0.55))
	# carte de gauche
	var card := Rect2(Vector2(36, 26), Vector2(790, 668))
	UI.panel(h, card, Color("#fffaf2"), UI.WHITE, 28, 6)
	UI.text(h, Vector2(card.get_center().x, 66), ttl, 42, UI.DARK, 0)
	# aperçu
	var typ := str(Net.mg_data.get("type", ""))
	if not _previews.has(typ):
		var path := "res://assets/previews/%s.png" % typ
		_previews[typ] = load(path) if ResourceLoader.exists(path) else null
	var pv: Texture2D = _previews[typ]
	var pr := Rect2(Vector2(card.position.x + 40, 100), Vector2(card.size.x - 80, (card.size.x - 80) * 9.0 / 16.0))
	h.draw_style_box(UI.box(Color(0.13, 0.1, 0.25, 0.2), Color(0, 0, 0, 0), 0, 20), Rect2(pr.position + Vector2(0, 6), pr.size))
	h.draw_style_box(UI.box(UI.WHITE, Color(0, 0, 0, 0), 0, 20), pr.grow(6))
	if pv:
		(h as CanvasItem).texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		h.draw_texture_rect(pv, pr, false)
	else:
		h.draw_style_box(UI.box(Color("#c9e8f7"), Color(0, 0, 0, 0), 0, 16), pr)
		UI.text(h, pr.get_center(), ttl, 34, UI.WHITE, 8)
	# explication
	var y := pr.end.y + 34.0
	var fs := 21 if lines.size() <= 4 else 19
	var step := (card.end.y - 18.0 - y) / maxf(1.0, float(lines.size()))
	step = minf(step, 30.0)
	for i in lines.size():
		h.draw_string(UI.font(), Vector2(card.position.x + 20, y + i * step + 6), UI.padify(str(lines[i])), HORIZONTAL_ALIGNMENT_CENTER, card.size.x - 40, fs, UI.DARK)
	# commandes
	var cx := 856.0
	UI.text(h, Vector2(cx + 120, 66), "Commandes", 36, UI.DARK, 0)
	_pad_icon(h, Vector2(cx + 280, 66))
	h.draw_line(Vector2(cx, 98), Vector2(1250, 98), UI.DARK, 4.0)
	var yy2 := 132.0
	for part in ctrl.split("·"):
		var e := str(part).strip_edges()
		if e == "":
			continue
		var act := e
		var keys := ""
		var ci := e.find(":")
		if ci >= 0:
			act = e.substr(0, ci).strip_edges()
			keys = e.substr(ci + 1).strip_edges()
		h.draw_string(UI.font(true), Vector2(cx + 4, yy2), act, HORIZONTAL_ALIGNMENT_LEFT, 380, 22, UI.DARK)
		yy2 += 8.0
		for k in 38:
			h.draw_circle(Vector2(cx + 8 + k * 10.0, yy2), 1.6, Color(UI.DARK, 0.5))
		if keys != "":
			yy2 += _keys(h, Vector2(cx + 4, yy2 + 30), keys, 392.0) + 66.0
		else:
			yy2 += 20.0
		yy2 += 18.0


## Touches dessinées comme de vraies touches (blanches, contour encre) ; les mots de liaison
## (« ou », « en l'air »...) restent en texte simple. Renvoie la hauteur en plus si ça passe à la ligne.
const KEY_WORDS := ["Espace", "Entrée", "Tab", "Maj", "Ctrl", "Échap", "flèches", "←", "→", "↑", "↓", "Clic"]

const PAD_MAP := {"Q": "←", "D": "→", "Z": "↑", "W": "↑", "S": "↓", "flèches": "Stick", "Espace": "A", "Entrée": "A",
	"Maj": "X", "X": "X", "E": "X", "J": "X", "clic": "X", "Clic": "X", "Tab": "Y", "Échap": "Start"}


## Version manette d'une liste de touches : « Q D / ← → » devient « ← → », « Maj / X / clic » devient « X ».
static func _pad_tokens(keys: String) -> Array:
	var groups: Array = [[]]
	for tok in keys.split(" ", false):
		var tk := str(tok)
		if tk == "/" or tk == "ou":
			groups.append([])
			continue
		(groups[-1] as Array).append(PAD_MAP.get(tk, tk))
	var out: Array = []
	var seen: Array = []
	for g in groups:
		var arr: Array = g
		var dirs := 0
		for d in ["←", "→", "↑", "↓"]:
			if d in arr:
				dirs += 1
		if dirs >= 3:
			arr = ["Stick"]
		if arr.is_empty() or str(arr) in seen:
			continue
		seen.append(str(arr))
		if not out.is_empty():
			out.append("/")
		out.append_array(arr)
	return out


static func _keys(h: CanvasItem, at: Vector2, keys: String, maxw: float) -> float:
	var x := at.x
	var y := at.y
	var toks: Array = _pad_tokens(keys) if UI.pad_mode else Array(keys.split(" ", false))
	for tok in toks:
		var tk := str(tok)
		if UI.pad_mode:
			var pk := tk in ["A", "B", "X", "Y", "Stick", "Start", "←", "→", "↑", "↓"]
			var pw := (maxf(34.0, UI.text_width(tk, 16) + 20.0) if pk else UI.text_width(tk, 18, false)) + 7.0
			if x + pw > at.x + maxw:
				x = at.x
				y += 42.0
			if pk:
				pw = UI.pad_chip(h, Vector2(x, y), tk, 16) + 7.0
			else:
				h.draw_string(UI.font(), Vector2(x, y + 7), tk, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(UI.INK, 0.8))
			x += pw
			continue
		var is_key := tk in KEY_WORDS or (tk.length() == 1 and tk != "/" and tk != "+" and tk.to_upper() == tk and tk.to_lower() != tk) or tk.is_valid_int()
		var lab := "← ↑ ↓ →" if tk == "flèches" else tk
		var w := (maxf(34.0, UI.text_width(lab, 18) + 20.0) if is_key else UI.text_width(tk, 18, false)) + 7.0
		if x + w > at.x + maxw:
			x = at.x
			y += 42.0
		if is_key:
			var kr := Rect2(Vector2(x, y - 17), Vector2(w - 7.0, 34))
			var kb := UI.KitBox.new()
			kb.col = UI.PAPER
			kb.radius = 9
			h.draw_style_box(kb, kr)
			UI.text(h, kr.get_center() + Vector2(0, -2), lab, 18, UI.INK, 0)
		else:
			h.draw_string(UI.font(), Vector2(x, y + 7), tk, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(UI.INK, 0.8))
		x += w
	return y - at.y


static func _pad_icon(h: CanvasItem, c: Vector2) -> void:
	h.draw_style_box(UI.box(UI.DARK, Color(0, 0, 0, 0), 0, 14), Rect2(c - Vector2(32, 14), Vector2(64, 28)))
	h.draw_rect(Rect2(c + Vector2(-22, -2), Vector2(14, 4)), UI.WHITE)
	h.draw_rect(Rect2(c + Vector2(-17, -7), Vector2(4, 14)), UI.WHITE)
	h.draw_circle(c + Vector2(12, -4), 3.5, UI.WHITE)
	h.draw_circle(c + Vector2(20, 3), 3.5, UI.WHITE)


## Bas à droite : les joueurs (cochés quand ils sont prêts) et le gros bouton.
static func draw_ready_row(h: CanvasItem, mine: bool, ready: Array, all_ids: Array, tt: float, watch := false) -> void:
	var ids := all_ids.duplicate()
	ids.sort()
	var cx := 1053.0
	# têtes
	var w := minf(54.0, 390.0 / maxf(1.0, float(ids.size())))
	var x0 := cx - ids.size() * w / 2.0
	for i in ids.size():
		var id: int = ids[i]
		var c := Vector2(x0 + i * w + w / 2.0, 560)
		var ok := ready.has(id)
		UI.portrait(h, c, 22.0, Net.color_idx(id), UI.GREEN.lightened(0.3) if ok else UI.WHITE, Color.WHITE if ok else Color(0.62, 0.62, 0.68, 1.0))
		if ok:
			h.draw_circle(c + Vector2(16, 15), 11, UI.WHITE)
			h.draw_circle(c + Vector2(16, 15), 8, UI.GREEN)
			h.draw_polyline(PackedVector2Array([c + Vector2(11, 15), c + Vector2(15, 19), c + Vector2(21, 11)]), UI.WHITE, 2.5)
	# bouton
	var r := Rect2(Vector2(860, 610), Vector2(390, 66))
	if watch:
		UI.panel(h, r, Color("#9aa0b4"), UI.WHITE, 33, 5)
		UI.text(h, r.get_center(), "C'est un duel : tu regardes !", 24, UI.WHITE, 6)
	elif not mine:
		var k := 1.0 + 0.03 * sin(tt * 6.0)
		var rr := Rect2(r.get_center() - r.size * k / 2.0, r.size * k)
		UI.panel(h, rr, Color("#ff7f8f"), UI.WHITE, 33, 5)
		UI.text(h, rr.get_center(), "ESPACE : Commencer", 30, UI.WHITE, 7)
	else:
		UI.panel(h, r, Color("#7fcf6a"), UI.WHITE, 33, 5)
		UI.text(h, r.get_center(), "Prêt ! On attend les autres...", 24, UI.WHITE, 6)


## Bandeau « DUEL : A contre B » (colonne de droite).
static func draw_duel_banner(h: CanvasItem) -> void:
	var ids: Array = Net.mg_data.get("players", [])
	if ids.size() < 2:
		return
	var r := Rect2(Vector2(860, 430), Vector2(390, 90))
	UI.panel(h, r, Color("#8a4fd8"), UI.WHITE, 24, 5)
	UI.text(h, r.position + Vector2(195, 28), "DUEL !", 30, Color("#ffe27a"), 7)
	UI.text(h, r.position + Vector2(195, 62), "%s contre %s  ·  %d pièces" % [Net.name_of(ids[0]), Net.name_of(ids[1]), int(Net.mg_data.get("stake", 0))], 20, UI.WHITE, 5)
