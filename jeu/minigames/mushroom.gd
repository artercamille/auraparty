extends "res://minigames/stage.gd"
## « Champi-couleurs ! » (Mushroom Mix-Up, Mario Party) : une couleur est annoncée,
## il faut vite sauter sur le champignon de cette couleur avant que les autres coulent.
## On peut pousser les autres. Le dernier hors de l'eau gagne. Le motif est le même chez tout le monde.

const COLS := [
	["ROUGE", Color("#f0645a")], ["BLEU", Color("#4fa8e8")], ["VERT", Color("#79c94a")],
	["JAUNE", Color("#f5c83c")], ["VIOLET", Color("#a27be0")], ["ORANGE", Color("#ff9a3c")],
]
const XS := [130.0, 330.0, 532.0, 748.0, 950.0, 1150.0]
const YS := [500.0, 455.0, 510.0, 460.0, 505.0, 455.0]
const CAP_W := 172.0
const WATER_Y := 610.0
const SINK := 0.5
const DOWN := 1.5
const RISE := 0.7
const DEPTH := 300.0

var rounds: Array = []       # {t, warn, safe: [indices]}
var shrooms: Array = []      # {body, x, y}
var view: Node2D
var water: Node2D
var announced := -1
var last_phase := {}


func _setup() -> void:
	title = "Champi-couleurs !"
	rules = "Une couleur s'affiche en haut de l'écran...\nSaute vite sur le champignon de cette couleur :\ntous les autres coulent ! Pousse les autres à l'eau.\nLe dernier hors de l'eau gagne !"
	duration = 75.0
	for i in 8:
		var k := i % 6
		spawn_points.append(Vector2(XS[k] + (-30.0 if i >= 6 else 0.0), YS[k] - 2.0))
	_make_schedule()


func _make_schedule() -> void:
	var tt := 1.5
	var n := 0
	var last := -1
	while tt < duration:
		var prog := clampf(tt / 55.0, 0.0, 1.0)
		var warn := lerpf(3.2, 1.25, prog)
		var safe := []
		var a := rng.randi_range(0, 5)
		if a == last:
			a = (a + rng.randi_range(1, 5)) % 6
		safe.append(a)
		if n < 2:
			var b := (a + rng.randi_range(2, 4)) % 6
			safe.append(b)
		last = a
		rounds.append({"t": tt, "warn": warn, "safe": safe})
		tt += warn + SINK + DOWN + RISE + lerpf(1.2, 0.5, prog)
		n += 1


func _build_level() -> void:
	view = Node2D.new()
	view.z_index = -1
	world.add_child(view)
	view.draw.connect(_draw_view)
	water = Node2D.new()
	water.z_index = 9
	world.add_child(water)
	water.draw.connect(_draw_water)
	for i in 6:
		var b := AnimatableBody2D.new()
		b.sync_to_physics = true
		b.collision_layer = 1
		b.collision_mask = 0
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = Vector2(CAP_W - 10.0, 26.0)
		cs.shape = rs
		cs.position = Vector2(0, 13)
		b.add_child(cs)
		b.position = Vector2(XS[i], YS[i])
		world.add_child(b)
		shrooms.append({"body": b, "x": XS[i], "y": YS[i]})


## Pour le champignon i à l'instant tt : [décalage vers le bas, phase, n° de manche]
func _state(i: int, tt: float) -> Array:
	for r in range(rounds.size() - 1, -1, -1):
		var rd: Dictionary = rounds[r]
		var s: float = tt - float(rd["t"])
		if s < 0.0:
			continue
		var w: float = rd["warn"]
		if s < w:
			return [0.0, "warn", r]
		s -= w
		var safe: Array = rd["safe"]
		if safe.has(i):
			return [0.0, "safe", r]
		if s < SINK:
			var k := s / SINK
			return [DEPTH * k * k, "sink", r]
		s -= SINK
		if s < DOWN:
			return [DEPTH + sin(s * 3.0) * 4.0, "down", r]
		s -= DOWN
		if s < RISE:
			var k2 := s / RISE
			return [DEPTH * (1.0 - k2 * k2 * (3.0 - 2.0 * k2)), "rise", r]
		break
	return [0.0, "idle", -1]


func _current_round(tt: float) -> int:
	for r in range(rounds.size() - 1, -1, -1):
		var rd: Dictionary = rounds[r]
		var s: float = tt - float(rd["t"])
		if s >= 0.0 and s < float(rd["warn"]) + SINK + DOWN:
			return r
	return -1


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	var tt := play_t if state != "intro" and state != "count" else 0.0
	for i in 6:
		var st := _state(i, tt)
		var sh: Dictionary = shrooms[i]
		var body: AnimatableBody2D = sh["body"]
		var wob := 0.0
		if st[1] == "idle" or st[1] == "warn" or st[1] == "safe":
			wob = sin(tt * 2.2 + i) * 3.0
		body.position = Vector2(float(sh["x"]), float(sh["y"]) + float(st[0]) + wob)
		# petit bruit quand ça coule
		var key := "%d_%s" % [i, str(st[1])]
		if st[1] == "sink" and not last_phase.has(key + str(st[2])):
			last_phase[key + str(st[2])] = true
			if i == 0 or not last_phase.has("snd%d" % st[2]):
				last_phase["snd%d" % st[2]] = true
				Sfx.play("fall", -6.0)
				fx.shake(3.0)
	var r := _current_round(tt)
	if r != announced and r >= 0 and state == "play":
		announced = r
		Sfx.play("ui_question", -2.0)
	# les robots de test : ils filent vers le bon champignon (avec un temps de réaction)
	if me and me.is_bot and (state == "play" or state == "count"):
		var cr := _current_round(tt)
		var near := 0
		for k in 6:
			if absf(XS[k] - me.position.x) < absf(XS[near] - me.position.x):
				near = k
		me.set_meta("goal_x", XS[near])
		if cr >= 0:
			var rd: Dictionary = rounds[cr]
			var since := tt - float(rd["t"])
			if since > 0.45 + float(Net.my_id() % 5) * 0.12:
				var safe: Array = rd["safe"]
				var best: int = safe[0]
				for s in safe:
					if absf(XS[s] - me.position.x) < absf(XS[best] - me.position.x):
						best = s
				me.set_meta("goal_x", XS[best] + float((Net.my_id() % 3) - 1) * 30.0)
				me.set_meta("goal_jump", absf(XS[best] - me.position.x) > 50.0)
		else:
			me.set_meta("goal_jump", false)
	# dans l'eau = éliminé
	if state == "play" and me and not me.dead and not my_out and me.position.y > WATER_Y + 20.0:
		fx.splash(clampf(me.position.x, 60.0, 1220.0), me.color(), "PLOUF !", WATER_Y + 30.0)
		Sfx.play("fall", 0.0)
		eliminate_me("tombé")
	view.queue_redraw()
	water.queue_redraw()


func splash_y() -> float:
	return WATER_Y + 30.0


func _draw_water() -> void:
	var tt := play_t if state != "intro" and state != "count" else 0.0
	var wy := WATER_Y + 30.0
	for k in 24:
		var x := k * 60.0 - fmod(tt * 25.0, 60.0)
		water.draw_circle(Vector2(x, wy + 6), 24.0, Color("#8fdcf6", 0.92))
	water.draw_rect(Rect2(-40, wy + 8, 1360, 200), Color("#5ec8ef", 0.92))
	for k in 14:
		var x2 := fmod(k * 97.0 + tt * 18.0, 1360.0) - 40.0
		water.draw_line(Vector2(x2, wy + 30 + (k % 3) * 22), Vector2(x2 + 34, wy + 30 + (k % 3) * 22), Color(1, 1, 1, 0.5), 3.0)


func _draw_view() -> void:
	var tt := play_t if state != "intro" and state != "count" else 0.0
	# champignons
	for i in 6:
		var sh: Dictionary = shrooms[i]
		var p: Vector2 = (sh["body"] as Node2D).position
		var col: Color = COLS[i][1]
		var st := _state(i, tt)
		# pied
		var stem_h := 600.0
		view.draw_rect(Rect2(p.x - 26, p.y + 10, 52, stem_h), Color("#f3ead6"))
		view.draw_rect(Rect2(p.x + 8, p.y + 10, 18, stem_h), Color("#e3d6bb"))
		# chapeau
		var cap := PackedVector2Array()
		for k in 21:
			var a := PI + k * PI / 20.0
			cap.append(p + Vector2(cos(a) * CAP_W * 0.5, sin(a) * 58.0 + 18.0))
		view.draw_colored_polygon(cap, col)
		view.draw_rect(Rect2(p.x - CAP_W * 0.5, p.y + 12, CAP_W, 12), col.darkened(0.12))
		for d in [[-38, -8, 12], [10, -26, 14], [44, -2, 9], [-8, 4, 7]]:
			view.draw_circle(p + Vector2(d[0], d[1]), d[2], Color(1, 1, 1, 0.9))
		# reflet
		view.draw_arc(p + Vector2(0, 18), CAP_W * 0.42, PI * 1.15, PI * 1.45, 10, Color(1, 1, 1, 0.45), 6.0)
		# celui qui va couler tremble un peu juste avant
		if st[1] == "warn":
			var rd: Dictionary = rounds[int(st[2])]
			var left := float(rd["t"]) + float(rd["warn"]) - tt
			if left < 0.5:
				view.draw_circle(p + Vector2(0, 30), 4.0, Color(1, 1, 1, 0.0))


func _update(_delta: float) -> void:
	pass


func _draw_extra_hud() -> void:
	draw_timer()
	var tt := play_t if state == "play" else 0.0
	var r := _current_round(tt)
	if r < 0 or state != "play":
		return
	var rd: Dictionary = rounds[r]
	var since := tt - float(rd["t"])
	var safe: Array = rd["safe"]
	# grand panneau avec la (les) couleur(s) sûre(s)
	var names := []
	for s in safe:
		names.append(COLS[s][0])
	var txt := " ou ".join(names) + " !"
	var pop := 1.0 + maxf(0.0, 0.3 - since) * 1.2
	var w := UI.text_width(txt, int(46 * pop)) + 120.0
	var box := Rect2(Vector2(640 - w / 2.0, 92), Vector2(w, 74))
	var main_col: Color = COLS[safe[0]][1]
	UI.panel(hud, box, main_col, UI.WHITE, 26, 6)
	UI.text(hud, box.get_center(), txt, int(46 * pop), UI.WHITE, 9)
	# petits champignons de la couleur de chaque côté
	for sd in [-1.0, 1.0]:
		var c := Vector2(640 + sd * (w / 2.0 - 34.0), 129)
		hud.draw_circle(c, 22.0, UI.WHITE)
		hud.draw_circle(c, 17.0, main_col.darkened(0.1))
		hud.draw_circle(c + Vector2(-5, -5), 5.0, Color(1, 1, 1, 0.9))
	# compte à rebours avant que ça coule
	var left := float(rd["warn"]) - since
	if left > 0.0:
		var bw := 300.0
		var br := Rect2(Vector2(640 - bw / 2.0, 176), Vector2(bw, 16))
		hud.draw_style_box(UI.box(Color(1, 1, 1, 0.8), Color(0, 0, 0, 0), 0, 8), br)
		hud.draw_style_box(UI.box(main_col.darkened(0.1), Color(0, 0, 0, 0), 0, 8), Rect2(br.position, Vector2(bw * left / float(rd["warn"]), 16)))
