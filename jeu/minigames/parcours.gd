extends "res://minigames/stage.gd"
## « Le grand parcours ! » : course de plateformes. Trous, pics, scies, plateformes mobiles,
## ressort. Drapeaux = points de sauvegarde. Les autres sont des fantômes. Premier arrivé gagne.

const GROUND := 592.0
const W := 6016.0
const FINISH_X := 5600.0
const CHECKPOINTS := [Vector2(110, 592), Vector2(2140, 592), Vector2(4100, 592)]

var spikes: Array = []       # Rect2
var saws: Array = []         # {sprite, x, y, amp, speed, phase, vertical}
var movers: Array = []       # {body, cx, y, amp, speed, phase}
var flags: Array = []        # {sprite, idx}
var checkpoint := 0
var finished := false
var finish_time := 0.0
var finishes: Dictionary = {}
var host_prog: Dictionary = {}
var prog_acc := 0.0
var hazard_death := false
var saw_tex := []
var overlay: Node2D


func _setup() -> void:
	title = "Le grand parcours !"
	rules = "Saute de plateforme en plateforme jusqu'à l'arrivée !\nÉvite les pics et les scies. Les drapeaux sauvegardent ta progression.\nLe premier arrivé gagne. Les autres sont des fantômes."
	controls = "Bouger : Q D / ← →   ·   Sauter : Espace (x2), garde appuyé pour sauter plus haut"
	duration = 75.0
	contact = false
	ghosts = true
	follow_cam = true
	respawn_on_fall = true
	show_heads = false
	cam_limits = Rect2(0, 0, W, 720)
	for i in 8:
		spawn_points.append(Vector2(70 + i * 14, GROUND))
	saw_tex = [load("res://assets/enemies/saw_a.png"), load("res://assets/enemies/saw_b.png")]


func cloud(x0: int, y: float, w: int) -> void:
	for i in w:
		var n := "terrain_grass_cloud_" + ("left" if i == 0 else ("right" if i == w - 1 else "middle"))
		tile(n, Vector2((x0 + i) * T, y))
	solid(Rect2(x0 * T + 2, y + 4, w * T - 4, 42))


func spike(tx: int, ground_y: float) -> void:
	tile("spikes", Vector2(tx * T, ground_y - T))
	spikes.append(Rect2(tx * T + 8, ground_y - 28, 48, 28))


func saw(x: float, y: float, amp: float, speed: float, phase: float, vertical := true) -> void:
	var s := Sprite2D.new()
	s.texture = saw_tex[0]
	s.scale = Vector2(0.62, 0.62)
	s.z_index = 6
	world.add_child(s)
	saws.append({"sprite": s, "x": x, "y": y, "amp": amp, "speed": speed, "phase": phase, "vertical": vertical})


func mover(cx: float, y: float, amp: float, speed: float, phase: float) -> void:
	var b := AnimatableBody2D.new()
	b.sync_to_physics = true
	b.collision_layer = 2
	b.collision_mask = 0
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(3 * T - 4, 20)
	cs.shape = rs
	cs.position = Vector2(0, 14)
	cs.one_way_collision = true
	b.add_child(cs)
	for i in 3:
		var n: String = "terrain_grass_horizontal_" + ["left", "middle", "right"][i]
		var s := Sprite2D.new()
		s.texture = load("res://assets/tiles/%s.png" % n)
		s.centered = false
		s.scale = Vector2(0.5, 0.5)
		s.position = Vector2(-1.5 * T + i * T, 0)
		b.add_child(s)
	b.position = Vector2(cx, y)
	world.add_child(b)
	movers.append({"body": b, "cx": cx, "y": y, "amp": amp, "speed": speed, "phase": phase})


func _build_level() -> void:
	# départ
	island(0, GROUND, 9)
	tile("sign_right", Vector2(3 * T, GROUND - T))
	# petites îles
	cloud(10, 560.0, 3)
	cloud(15, 504.0, 3)
	cloud(20, 560.0, 2)
	# escalier
	thin(23, 464.0, 2)
	thin(26, 368.0, 2)
	thin(29, 272.0, 2)
	# drapeau 1 + pics
	island(32, GROUND, 7)
	spike(35, GROUND)
	spike(36, GROUND)
	# longue île : pics et scie
	island(40, GROUND, 12)
	spike(43, GROUND)
	spike(44, GROUND)
	saw(47 * T + 32.0, GROUND - 120.0, 64.0, 2.4, 0.0)
	spike(50, GROUND)
	# plateformes mobiles au-dessus du vide
	mover(3480.0, 560.0, 90.0, 1.3, 0.0)
	mover(3800.0, 500.0, 100.0, 1.3, 1.6)
	# drapeau 2 + ressort
	island(63, GROUND, 8)
	spring(69, GROUND)
	# en hauteur, avec une scie entre deux plateformes
	thin(71, 320.0, 2)
	saw(4768.0, 300.0, 90.0, 2.0, 0.8)
	thin(76, 320.0, 2)
	thin(80, 400.0, 2)
	# arrivée
	island(83, GROUND, 11)
	tile("flag_green_a", Vector2(FINISH_X + 60.0, GROUND - T))
	for i in CHECKPOINTS.size():
		if i == 0:
			continue
		var cp: Vector2 = CHECKPOINTS[i]
		var f := tile("flag_off", Vector2(cp.x - 20.0, GROUND - T))
		flags.append({"sprite": f, "idx": i})
	overlay = Node2D.new()
	overlay.z_index = 9
	world.add_child(overlay)
	overlay.draw.connect(_draw_overlay)


func _on_start() -> void:
	if me:
		me.kill_rect = Rect2(-200, -2000, W + 400.0, 2840.0)


func _pick_respawn() -> Vector2:
	return CHECKPOINTS[checkpoint]


func _on_me_died(_attacker: int) -> void:
	if not hazard_death:
		fx.splash(me.position.x, me.color(), "PLOUF !", 690.0)
	hazard_death = false
	respawn_t = 1.0


func _physics_process(delta: float) -> void:
	var tt := play_t if state != "intro" else 0.0
	for m in movers:
		var b: AnimatableBody2D = m["body"]
		b.position = Vector2(float(m["cx"]) + sin(tt * float(m["speed"]) + float(m["phase"])) * float(m["amp"]), float(m["y"]))
	for sw in saws:
		var s: Sprite2D = sw["sprite"]
		var o := sin(tt * float(sw["speed"]) + float(sw["phase"])) * float(sw["amp"])
		s.position = Vector2(float(sw["x"]), float(sw["y"]) + o) if sw["vertical"] else Vector2(float(sw["x"]) + o, float(sw["y"]))
		s.rotation = tt * 9.0
		s.texture = saw_tex[int(tt * 12.0) % 2]
	super._physics_process(delta)
	if state != "play" or me == null or me.dead:
		return
	var mr := Rect2(me.position + Vector2(-16, -54), Vector2(32, 52))
	var hurt := false
	for r in spikes:
		if (r as Rect2).intersects(mr):
			hurt = true
	for sw in saws:
		var sp: Vector2 = (sw["sprite"] as Sprite2D).position
		if sp.distance_to(me.position + Vector2(0, -28)) < 52.0:
			hurt = true
	if hurt:
		hazard_death = true
		fx.stars(me.position + Vector2(0, -30), 6)
		fx.popup(me.position + Vector2(0, -80), "AÏE !", UI.RED)
		Sfx.play("hurt", -2.0)
		me._die()
		return
	# drapeaux
	for f in flags:
		var idx: int = f["idx"]
		if idx > checkpoint and me.position.x >= (CHECKPOINTS[idx] as Vector2).x - 10.0:
			checkpoint = idx
			(f["sprite"] as Sprite2D).texture = load("res://assets/tiles/flag_green_a.png")
			Sfx.play("coin", -2.0)
			fx.ring(CHECKPOINTS[idx] + Vector2(0, -60), UI.GREEN)
			fx.popup(me.position + Vector2(0, -100), "Sauvegardé !", UI.GREEN)
	# arrivée
	if not finished and me.position.x > FINISH_X:
		finished = true
		finish_time = play_t
		Sfx.play("gem", 0.0)
		fx.ring(me.position + Vector2(0, -30), me.color())
		fx.stars(me.position + Vector2(0, -60), 10)
		Net.mg_to_host({"finish": play_t})
		get_tree().create_timer(1.5).timeout.connect(func(): spectating = true)
	prog_acc += delta
	if prog_acc > 1.0:
		prog_acc = 0.0
		Net.mg_to_host({"prog": checkpoint, "x": int(me.position.x)})
	if me.is_bot:
		me.set_meta("goal_x", W - 100.0)
		me.set_meta("goal_jump", true)


# ------------------------------------------------------------------ hôte
func _on_mg_msg(from_id: int, data: Dictionary) -> void:
	if data.has("prog"):
		host_prog[from_id] = int(data.get("x", 0))
	if data.has("finish") and not finishes.has(from_id):
		finishes[from_id] = float(data["finish"])
		Net.mg_broadcast({"finishes": finishes})
		var all_done := true
		for id in nodes:
			if not finishes.has(id) and Net.players.has(id):
				all_done = false
		if all_done:
			Net.mg_end_with_scores(host_scores())


func _on_mg_state(data: Dictionary) -> void:
	if data.has("finishes"):
		var before := finishes.size()
		finishes = data["finishes"]
		if finishes.size() > before:
			Sfx.play("coin", -6.0)


func host_scores() -> Dictionary:
	var out := {}
	for id in nodes:
		if finishes.has(id):
			var ft: float = finishes[id]
			out[id] = [100000.0 - ft * 100.0, "Arrivé en %.1f s" % ft]
		else:
			var x: int = host_prog.get(id, 0)
			out[id] = [float(x), "Parcouru %d %%" % int(clampf(x / FINISH_X, 0.0, 1.0) * 100.0)]
	return out


# ------------------------------------------------------------------ rendu
func _process(delta: float) -> void:
	super._process(delta)
	overlay.queue_redraw()


func _draw_overlay() -> void:
	for i in 12:
		var y := GROUND - 12.0 - i * 26.0
		overlay.draw_rect(Rect2(Vector2(FINISH_X, y), Vector2(13, 13)), UI.DARK if i % 2 == 0 else UI.WHITE)
		overlay.draw_rect(Rect2(Vector2(FINISH_X + 13, y), Vector2(13, 13)), UI.WHITE if i % 2 == 0 else UI.DARK)
	UI.text(overlay, Vector2(FINISH_X + 13, GROUND - 340), "ARRIVÉE", 30, UI.YELLOW, 9)


func _draw_extra_hud() -> void:
	draw_timer()
	if state == "intro":
		return
	var bar := Rect2(Vector2(200, 26), Vector2(880, 34))
	hud.draw_style_box(UI.box(UI.WHITE, UI.DARK, 4, 16), bar)
	for i in range(1, CHECKPOINTS.size()):
		var cx := bar.position.x + 20.0 + ((CHECKPOINTS[i] as Vector2).x / FINISH_X) * (bar.size.x - 40.0)
		hud.draw_rect(Rect2(Vector2(cx - 2, bar.position.y + 6), Vector2(4, 22)), Color(UI.GREEN, 0.7))
	var ids := nodes.keys()
	ids.sort_custom(func(a, b): return nodes[a].position.x < nodes[b].position.x)
	if ids.has(Net.my_id()):
		ids.erase(Net.my_id())
		ids.append(Net.my_id())
	for id in ids:
		var n: Player = nodes[id]
		var prog := clampf(n.position.x / FINISH_X, 0.0, 1.0)
		if finishes.has(id):
			prog = 1.0
		var p := Vector2(bar.position.x + 20.0 + prog * (bar.size.x - 40.0), bar.position.y + 17.0)
		hud.draw_circle(p, 17.0, UI.DARK)
		hud.draw_circle(p, 14.0, Net.color_of(id))
		hud.draw_set_transform(p + Vector2(0, 13), 0.0, Vector2(0.11, 0.11))
		hud.draw_texture(UI.char_tex(Net.color_idx(id), "idle"), Vector2(-128, -256))
		hud.draw_set_transform(Vector2.ZERO)
		if id == Net.my_id():
			hud.draw_rect(Rect2(p + Vector2(-12, 21), Vector2(24, 4)), Net.color_of(id))
	if finishes.size() > 0:
		var order := finishes.keys()
		order.sort_custom(func(a, b): return finishes[a] < finishes[b])
		var y := 90.0
		for i in order.size():
			var id: int = order[i]
			var txt := "%d. %s  %.1f s" % [i + 1, Net.name_of(id), float(finishes[id])]
			var w := UI.text_width(txt, 18) + 28.0
			hud.draw_style_box(UI.box(UI.WHITE, UI.DARK, 3, 10), Rect2(Vector2(1280 - 24 - w, y), Vector2(w, 30)))
			hud.draw_string(UI.font(true), Vector2(1280 - 10 - w, y + 22), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Net.color_of(id).darkened(0.15))
			y += 36.0
	if finished and state == "play":
		var m := "Arrivé en %.1f s ! Attends les autres..." % finish_time
		var mw := UI.text_width(m, 26) + 50.0
		hud.draw_style_box(UI.box(UI.WHITE, UI.DARK, 4, 16), Rect2(Vector2(640 - mw / 2.0, 640), Vector2(mw, 50)))
		UI.text(hud, Vector2(640, 664), m, 26, UI.GREEN.darkened(0.2), 0)


func _is_done(id: int) -> bool:
	return finishes.has(id)
