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
				var bot_ready := me != null and me.is_bot and t > 1.0
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
	hud.draw_style_box(UI.box(UI.WHITE, UI.DARK, 4, 14), r)
	UI.text(hud, r.get_center(), "%d s" % left, 30, UI.RED if left <= 10 else UI.DARK, 0)


func _draw_hud() -> void:
	if show_heads:
		# têtes des joueurs en haut, barrées quand ils sont éliminés
		var ids := nodes.keys()
		ids.sort()
		var w := 64.0
		var x0 := 640.0 - ids.size() * w / 2.0
		for i in ids.size():
			var id: int = ids[i]
			var c := Vector2(x0 + i * w + w / 2.0, 44)
			var out := out_ids.has(id)
			hud.draw_circle(c, 27, UI.DARK)
			hud.draw_circle(c, 23, Net.color_of(id).lerp(Color.WHITE, 0.55) if not out else Color("#b9bccb"))
			hud.draw_set_transform(c + Vector2(0, 20), 0.0, Vector2(0.17, 0.17))
			hud.draw_texture(UI.char_tex(Net.color_idx(id), "hit" if out else "idle"), Vector2(-128, -256), Color(1, 1, 1, 0.45 if out else 1.0))
			hud.draw_set_transform(Vector2.ZERO)
			if out:
				hud.draw_line(c + Vector2(-16, -16), c + Vector2(16, 16), UI.RED, 6.0)
				hud.draw_line(c + Vector2(16, -16), c + Vector2(-16, 16), UI.RED, 6.0)
			if id == Net.my_id():
				hud.draw_rect(Rect2(c + Vector2(-16, 32), Vector2(32, 5)), Net.color_of(id))
	_draw_extra_hud()

	var center := Vector2(640, 360)
	if state == "intro" or state == "count":
		hud.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, 0.45))
		var r := Rect2(Vector2(240, 130), Vector2(800, 400))
		hud.draw_style_box(UI.box(UI.WHITE, UI.DARK, 6, 30), r)
		UI.text(hud, Vector2(640, 196), title, 56, UI.YELLOW, 14)
		var lines := rules.split("\n")
		for i in lines.size():
			hud.draw_string(UI.font(), Vector2(240, 270 + i * 36), lines[i], HORIZONTAL_ALIGNMENT_CENTER, 800, 24, UI.DARK)
		var cy := 270 + lines.size() * 36 + 24
		hud.draw_style_box(UI.box(UI.PAPER, UI.DARK, 3, 12), Rect2(Vector2(280, cy - 2), Vector2(720, 40)))
		hud.draw_string(UI.font(), Vector2(280, cy + 25), controls, HORIZONTAL_ALIGNMENT_CENTER, 720, 17, UI.GREY)
		var pulse := 1.0 + (1.0 - fmod(t, 1.0)) * 0.35
		if state == "count":
			UI.text(hud, Vector2(640, 610), str(3 - int(t)), int(80 * pulse), UI.WHITE, 16)
		else:
			draw_ready_row(hud, my_ready, ready_ids, nodes.keys(), t, me == null)
		if str(Net.mg_data.get("mode", "")) == "duel":
			draw_duel_banner(hud)
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
		hud.draw_style_box(UI.box(UI.WHITE, UI.DARK, 4, 16), Rect2(Vector2(640 - mw / 2.0, 640), Vector2(mw, 50)))
		UI.text(hud, Vector2(640, 664), msg, 26, UI.RED, 0)
	if state == "over":
		hud.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, minf(0.4, t)))
		UI.text(hud, center, "TERMINÉ !", int(96 * minf(1.0, 0.6 + t * 2.0)), UI.YELLOW, 16)


## Ligne « Appuie sur ESPACE quand tu es prêt » + têtes cochées (aussi utilisé par le kart).
static func draw_ready_row(h: CanvasItem, mine: bool, ready: Array, all_ids: Array, tt: float, watch := false) -> void:
	var ids := all_ids.duplicate()
	ids.sort()
	if watch:
		UI.text(h, Vector2(640, 590), "C'est un duel : tu regardes !", 28, UI.WHITE, 9)
	elif not mine:
		var k := 1.0 + 0.06 * sin(tt * 6.0)
		UI.text(h, Vector2(640, 590), "Appuie sur ESPACE quand tu es prêt !", int(30 * k), UI.YELLOW, 9)
	else:
		UI.text(h, Vector2(640, 590), "Prêt ! On attend les autres...", 28, UI.WHITE, 9)
	var w := 52.0
	var x0 := 640.0 - ids.size() * w / 2.0
	for i in ids.size():
		var id: int = ids[i]
		var c := Vector2(x0 + i * w + w / 2.0, 650)
		var ok := ready.has(id)
		h.draw_circle(c, 22, UI.DARK)
		h.draw_circle(c, 18, Net.color_of(id).lerp(Color.WHITE, 0.5) if ok else Color("#9da2b6"))
		h.draw_set_transform(c + Vector2(0, 16), 0.0, Vector2(0.14, 0.14))
		h.draw_texture(UI.char_tex(Net.color_idx(id), "idle"), Vector2(-128, -256), Color(1, 1, 1, 1.0 if ok else 0.45))
		h.draw_set_transform(Vector2.ZERO)
		if ok:
			h.draw_circle(c + Vector2(15, 14), 10, UI.DARK)
			h.draw_circle(c + Vector2(15, 14), 8, UI.GREEN)
			h.draw_polyline(PackedVector2Array([c + Vector2(10, 14), c + Vector2(14, 18), c + Vector2(20, 10)]), UI.WHITE, 2.5)


## Bandeau « DUEL : A contre B » en haut de l'écran.
static func draw_duel_banner(h: CanvasItem) -> void:
	var ids: Array = Net.mg_data.get("players", [])
	if ids.size() < 2:
		return
	var txt := "DUEL : %s contre %s  -  %d pièces en jeu" % [Net.name_of(ids[0]), Net.name_of(ids[1]), int(Net.mg_data.get("stake", 0))]
	var w := UI.text_width(txt, 26) + 60.0
	var r := Rect2(Vector2(640 - w / 2.0, 70), Vector2(w, 50))
	h.draw_style_box(UI.box(Color("#8a4fd8"), UI.DARK, 4, 16), r)
	UI.text(h, r.get_center(), txt, 26, UI.WHITE, 6)
