extends "res://minigames/stage.gd"
## « Le rocher fou ! » : un rocher géant roule de plus en plus vite. On fuit vers la droite.
## La piste devient de plus en plus dure : caisses et petits trous au début, puis piles de
## caisses, pics, ponts, et enfin pierres de gué, scies au-dessus du vide, combos.
## On peut pousser les autres vers le rocher. Dernier en vie gagne.
## La piste et le rocher sont identiques chez tout le monde (même graine, même horloge).

const GROUND := 592.0
const L_TILES := 340
const R := 150.0
const SPEEDUPS := [12.0, 24.0, 34.0]

var L := 0.0
var holes: Array = []        # [x début, x fin] en pixels
var hole_tiles: Array = []   # [case début, nb de cases]
var bridges: Array = []      # [case début, nb de cases]
var crates: Array = []       # [case, hauteur]
var spike_rects: Array = []
var obstacles_x: Array = []  # pour les bots
var saws: Array = []
var saw_tex := []
var rock_layer: Node2D
var rumble_acc := 0.0
var banner_t := 0.0
var level := 0


func _setup() -> void:
	title = "Le rocher fou !"
	rules = "Un rocher géant te fonce dessus... COURS !\nLe début est tranquille, puis la piste devient de plus en plus dure\net le rocher accélère. Pousse les autres vers lui. Le dernier en vie gagne !"
	duration = 50.0
	follow_cam = true
	cam_offset = Vector2(-260, -120)
	L = L_TILES * T
	cam_limits = Rect2(-700, 0, L + 700.0, 720)
	for i in 8:
		spawn_points.append(Vector2(520 + i * 34, GROUND))
	saw_tex = [load("res://assets/enemies/saw_a.png"), load("res://assets/enemies/saw_b.png")]


func rock_x(tt: float) -> float:
	return -250.0 + 330.0 * tt + 1.65 * tt * tt


func _difficulty(tx: int) -> float:
	return clampf((tx * T - 1100.0) / 11000.0, 0.0, 1.0)


func _pick_kind(d: float) -> String:
	var w := {"crate": 3.0 * (1.0 - d * 0.75), "hole2": 3.0 * (1.0 - d * 0.6)}
	if d > 0.12:
		w["crate2"] = 2.0 * d
		w["stairs"] = 2.0 * d
		w["hole3"] = 2.0 * d
		w["spikes1"] = 2.0 * d
	if d > 0.35:
		w["bridge"] = 1.4
		w["spikes2"] = 1.6 * d
		w["crate_hole"] = 2.0 * d
	if d > 0.55:
		w["stones"] = 2.4 * d
		w["saw_hole"] = 2.2 * d
		w["hole4"] = 1.5 * d
		w["spike_land"] = 1.8 * d
	var total := 0.0
	for k in w:
		total += float(w[k])
	var r := rng.randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return "crate"


func _build_level() -> void:
	var tx := 17
	while tx < L_TILES - 16:
		var d := _difficulty(tx)
		var kind := _pick_kind(d)
		var width := 1
		match kind:
			"crate":
				crates.append([tx, 1])
			"crate2":
				crates.append([tx, 2])
			"stairs":
				crates.append([tx, 1])
				crates.append([tx + 1, 2])
				width = 2
			"hole2":
				hole_tiles.append([tx, 2])
				width = 2
			"hole3":
				hole_tiles.append([tx, 3])
				width = 3
			"hole4":
				hole_tiles.append([tx, 4])
				width = 4
			"bridge":
				hole_tiles.append([tx, 5])
				bridges.append([tx, 5])
				width = 5
			"spikes1":
				_spikes(tx, 1)
			"spikes2":
				_spikes(tx, 2)
				width = 2
			"stones":
				hole_tiles.append([tx, 2])
				hole_tiles.append([tx + 3, 2])
				hole_tiles.append([tx + 6, 2])
				width = 8
			"crate_hole":
				crates.append([tx, 1])
				hole_tiles.append([tx + 2, 2])
				width = 4
			"saw_hole":
				hole_tiles.append([tx, 3])
				saws.append({"x": tx * T + 1.5 * T, "y": GROUND - 150.0, "amp": 70.0, "speed": 2.0 + d, "phase": rng.randf() * TAU})
				width = 3
			"spike_land":
				hole_tiles.append([tx, 2])
				_spikes(tx + 3, 1)
				width = 4
		tx += width + int(round(lerpf(9.0, 3.5, d) + rng.randf_range(0.0, lerpf(3.0, 1.5, d))))
	# sol entre les trous
	hole_tiles.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	var gx := 0
	for h in hole_tiles:
		var h0: int = h[0]
		if h0 > gx:
			island(gx, GROUND, h0 - gx)
		gx = h0 + int(h[1])
		holes.append([h0 * T, (h0 + int(h[1])) * T])
		obstacles_x.append(h0 * T)
	island(gx, GROUND, L_TILES + 4 - gx)
	for b in bridges:
		thin(int(b[0]), GROUND - 150.0, int(b[1]))
	# caisses (empilées si hauteur 2)
	for c in crates:
		var cx: float = int(c[0]) * T
		var hgt: int = c[1]
		for k in hgt:
			tile("block_planks", Vector2(cx, GROUND - T * (k + 1)))
		solid(Rect2(cx + 2.0, GROUND - T * hgt + 2.0, T - 4.0, T * hgt - 2.0))
		obstacles_x.append(cx)
	# scies
	for sw in saws:
		var s := Sprite2D.new()
		s.texture = saw_tex[0]
		s.scale = Vector2(0.62, 0.62)
		s.z_index = 6
		world.add_child(s)
		sw["sprite"] = s
	# décor dans les endroits libres
	var deco := RandomNumberGenerator.new()
	deco.seed = rng.seed + 5
	var dx := 300.0
	while dx < L:
		var free := true
		for h in holes:
			if dx > float(h[0]) - 80.0 and dx < float(h[1]) + 20.0:
				free = false
		for ox in obstacles_x:
			if absf(dx - float(ox)) < 110.0:
				free = false
		if free:
			var s2 := tile(["bush", "rock", "mushroom_red", "fence", "cactus"][deco.randi() % 5], Vector2(dx, GROUND - T))
			s2.z_index = -1
		dx += deco.randf_range(300.0, 900.0)
	rock_layer = Node2D.new()
	rock_layer.z_index = 12
	world.add_child(rock_layer)
	rock_layer.draw.connect(_draw_rock)


func _spikes(tx: int, n: int) -> void:
	for i in n:
		tile("spikes", Vector2((tx + i) * T, GROUND - T))
		spike_rects.append(Rect2((tx + i) * T + 8.0, GROUND - 28.0, 48.0, 28.0))
	obstacles_x.append(tx * T)


func _on_start() -> void:
	if me:
		me.kill_rect = Rect2(-600, -2000, L + 400.0, 2840.0)


func _physics_process(delta: float) -> void:
	var tt := play_t if state != "intro" else 0.0
	for sw in saws:
		var s: Sprite2D = sw["sprite"]
		s.position = Vector2(float(sw["x"]), float(sw["y"]) + sin(tt * float(sw["speed"]) + float(sw["phase"])) * float(sw["amp"]))
		s.rotation = tt * 9.0
		s.texture = saw_tex[int(tt * 12.0) % 2]
	super._physics_process(delta)
	if state != "play" or me == null or me.dead:
		return
	if Net.autotest != "" and OS.get_environment("GODMODE") != "":
		me.position = Vector2(rock_x(play_t) + 700.0, GROUND - 260.0)
		me.velocity = Vector2.ZERO
		return
	var rx := rock_x(play_t)
	var center := Vector2(rx, GROUND - R)
	if me.position.x < rx or center.distance_to(me.position + Vector2(0, -30)) < R + 16.0:
		_hurt("ÉCRASÉ !", "écrasé")
		return
	var mr := Rect2(me.position + Vector2(-16, -54), Vector2(32, 52))
	for r in spike_rects:
		if (r as Rect2).intersects(mr):
			_hurt("AÏE !", "piqué")
			return
	for sw in saws:
		if (sw["sprite"] as Sprite2D).position.distance_to(me.position + Vector2(0, -28)) < 52.0:
			_hurt("AÏE !", "scié")
			return
	# tremblement et grondement quand le rocher est proche
	var dist := me.position.x - rx
	if dist < 700.0:
		fx.shake(clampf((700.0 - dist) / 110.0, 0.0, 6.0))
		rumble_acc += delta
		if rumble_acc > 0.35:
			rumble_acc = 0.0
			Sfx.play("bump", -20.0 + (700.0 - dist) / 60.0, 0.3)
	if me.is_bot:
		me.set_meta("goal_x", L)
		var jump := false
		for ox in obstacles_x:
			var ahead := float(ox) - me.position.x
			if ahead > -10.0 and ahead < 75.0:
				jump = true
		me.set_meta("goal_jump", jump)


func _hurt(txt: String, how: String) -> void:
	fx.stars(me.position + Vector2(0, -30), 8)
	fx.popup(me.position + Vector2(0, -90), txt, me.color())
	Sfx.play("hurt", 0.0)
	eliminate_me(how)


func _process(delta: float) -> void:
	super._process(delta)
	banner_t = maxf(0.0, banner_t - delta)
	if state == "play":
		if level < SPEEDUPS.size() and play_t >= float(SPEEDUPS[level]):
			level += 1
			banner_t = 1.8
			Sfx.play("jump2", -2.0)
			fx.shake(8.0)
		if randf() < 0.3 + level * 0.15:
			fx.dust(Vector2(rock_x(play_t) - R * 0.6, GROUND), 1, 1.6 + level * 0.3)
	rock_layer.queue_redraw()


func _draw_rock() -> void:
	var tt := play_t if state != "intro" else 0.0
	var c := Vector2(rock_x(tt), GROUND - R)
	var ang := (rock_x(tt) + 250.0) / R
	var anger := float(level) / SPEEDUPS.size()
	rock_layer.draw_set_transform(c + Vector2(0, R + 2.0), 0.0, Vector2(1.0, 0.16))
	rock_layer.draw_circle(Vector2.ZERO, R * 0.95, Color(UI.DARK, 0.25))
	rock_layer.draw_set_transform(Vector2.ZERO)
	rock_layer.draw_circle(c, R + 7.0, UI.DARK)
	rock_layer.draw_circle(c, R, Color("#a3abbd").lerp(Color("#c98a8a"), anger * 0.6))
	rock_layer.draw_circle(c + Vector2(-R * 0.25, -R * 0.3), R * 0.55, Color("#b9c0cf").lerp(Color("#d9a3a3"), anger * 0.6))
	for i in 6:
		var a := ang + i * TAU / 6.0
		var rr := R * (0.55 if i % 2 == 0 else 0.72)
		var p := c + Vector2(cos(a), sin(a)) * rr
		rock_layer.draw_circle(p, R * (0.13 if i % 2 == 0 else 0.09), Color("#7f889c").lerp(Color("#9a5c5c"), anger * 0.6))
	# yeux méchants (ne tournent pas), de plus en plus en colère
	for s in [-1.0, 1.0]:
		var e := c + Vector2(R * 0.32 * s + R * 0.25, -R * 0.12)
		rock_layer.draw_circle(e, R * 0.17, UI.DARK)
		rock_layer.draw_circle(e, R * 0.13, Color.WHITE.lerp(Color("#ffb3b3"), anger))
		rock_layer.draw_circle(e + Vector2(R * 0.04, R * 0.02), R * 0.07, UI.DARK if anger < 0.6 else Color("#d42020"))
		var tilt := R * (0.04 + anger * 0.06)
		var brow := PackedVector2Array([e + Vector2(-R * 0.2, -R * 0.2 - s * tilt), e + Vector2(R * 0.2, -R * 0.2 + s * tilt)])
		rock_layer.draw_polyline(brow, UI.DARK, 9.0 + anger * 4.0)
	if anger > 0.3:
		rock_layer.draw_circle(c + Vector2(-R * 0.1, R * 0.18), R * 0.09, Color(1, 0.35, 0.35, 0.5))
		rock_layer.draw_circle(c + Vector2(R * 0.62, R * 0.18), R * 0.09, Color(1, 0.35, 0.35, 0.5))


func _draw_extra_hud() -> void:
	draw_timer()
	if state == "intro" or me == null:
		return
	var dist := maxf(0.0, (me.position.x - rock_x(play_t)) / 64.0)
	var col := UI.GREEN.darkened(0.2)
	if dist < 6.0:
		col = UI.RED
	elif dist < 12.0:
		col = Color("#ff8c28")
	var r := Rect2(Vector2(24, 80), Vector2(200, 46))
	UI.panel(hud, r, UI.WHITE, UI.WHITE, 14, 4)
	if my_out:
		UI.text(hud, UI.face_center(r), "Éliminé !", 22, UI.RED, 0)
	else:
		UI.text(hud, UI.face_center(r), "Rocher : %d m" % int(dist), 22, col, 0)
	# niveau de difficulté
	var lr := Rect2(Vector2(24, 134), Vector2(200, 40))
	UI.panel(hud, lr, UI.WHITE, UI.WHITE, 14, 4)
	for i in SPEEDUPS.size() + 1:
		var on := i <= level
		var cc := lr.position + Vector2(38 + i * 42, 20)
		hud.draw_circle(cc, 13.0, UI.DARK)
		hud.draw_circle(cc, 10.0, (Color("#ff8c28").lerp(UI.RED, float(i) / SPEEDUPS.size())) if on else Color("#d6d9e6"))
	if banner_t > 0.0:
		var k := 1.0 - banner_t / 1.8
		var sc := 1.0 + (1.0 - minf(1.0, k * 5.0)) * 0.6
		UI.text(hud, Vector2(640, 230), "ÇA ACCÉLÈRE !", int(72 * sc), Color(UI.RED, minf(1.0, banner_t * 2.0)), 16)
