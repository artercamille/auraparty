extends Node2D
## « Sors du labyrinthe ! » : tout le monde part du centre d'un labyrinthe de haies (le même pour
## tous, tiré avec la graine). Une seule sortie : le premier dehors gagne. La caméra suit son perso,
## on ne voit qu'un bout du labyrinthe ; une flèche jaune montre la DIRECTION de la sortie (pas le chemin).
## Champignons dans les culs-de-sac = on court plus vite un moment. On passe à travers les autres.
## Fin : tout le monde est sorti, 15 s après le premier, ou au bout de 90 s. Les autres sont classés
## selon la distance (en cases) qui leur restait jusqu'à la sortie.

const NX := 19
const NY := 11
const CS := 140.0                 # taille d'une case
const WT := 34.0                  # épaisseur des haies
const MW := NX * CS
const MH := NY * CS
const R := 20.0                   # rayon du perso (collisions)
const SPEED := 300.0
const BOOST := 1.6
const BOOST_T := 3.0
const MAX_T := 90.0
const AFTER_FIRST := 15.0
const OUT := 260.0                # herbe autour du labyrinthe

var ids: Array = []
var me_id := 0
var playing := false
var hud: Control
var world: Node2D
var ground: Node2D               # labyrinthe : dessiné une seule fois
var dyn: Node2D                  # persos, champignons, flèche : redessinés à chaque image
var state := "intro"              # intro, count, play, over
var t := 0.0
var race_t := 0.0
var my_ready := false
var go_received := false
var ready_ids: Array = []
var rng := RandomNumberGenerator.new()
var brng := RandomNumberGenerator.new()
var _tex := {}

# le labyrinthe (identique chez tout le monde)
var wall_r := {}                  # cellule (Vector2i) -> mur à droite ?
var wall_d := {}                  # cellule -> mur en bas ?
var walls: Array = []             # Rect2 des haies (collisions + dessin)
var exit_cell := Vector2i.ZERO
var exit_dir := Vector2i.ZERO     # vers l'extérieur
var exit_pos := Vector2.ZERO      # milieu de l'ouverture
var dist_exit := {}               # cellule -> nombre de cases jusqu'à la sortie
var shrooms: Array = []           # positions des champignons
var taken := {}                   # champignons pris (chez moi)
var center := Vector2i(NX / 2, NY / 2)

# mon perso
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var face := 1.0
var walk := 0.0
var boost_t := 0.0
var finished := false
var finish_t := 0.0
var send_acc := 0.0
var prog_acc := 0.0
var cam := Vector2.ZERO
var spec_id := 0
var spec_id_keep := 0
var pops: Array = []
var bot_speed := 1.0
var bot_path: Array = []
var bot_acc := 0.0

# tout le monde
var bodies := {}                  # id -> {p, v, snaps, face, walk, st}
var fin := {}                     # id -> temps de sortie
# hôte
var host_dist := {}
var host_first_t := -1.0
var ended := false


func _ready() -> void:
	rng.seed = int(Net.mg_data.get("seed", 1))
	brng.randomize()
	bot_speed = brng.randf_range(0.75, 1.0)
	for id in Net.mg_data.get("players", Net.players.keys()):
		if Net.players.has(id):
			ids.append(id)
	ids.sort()
	me_id = Net.my_id()
	playing = ids.has(me_id)
	_build()
	var c0 := cell_center(center)
	for i in ids.size():
		var id: int = ids[i]
		var a := TAU * float(i) / float(maxi(1, ids.size())) - PI / 2.0
		var p := c0 + Vector2.from_angle(a) * (0.0 if ids.size() == 1 else 78.0)
		bodies[id] = {"p": p, "v": Vector2.ZERO, "snaps": [], "face": 1.0 if p.x <= c0.x else -1.0, "walk": 0.0, "st": 0}
		if id == me_id:
			pos = p
			face = bodies[id]["face"]
		for pose in ["idle", "walk_a", "walk_b", "jump", "front"]:
			_tex["%d_%s" % [id, pose]] = UI.char_tex(Net.color_idx(id), pose)
	cam = pos if playing else c0
	_tex["shroom"] = load("res://assets/tiles/mushroom_red.png")
	_tex["flag"] = load("res://assets/tiles/flag_red_a.png")
	_tex["flag_b"] = load("res://assets/tiles/flag_red_b.png")
	for n in ["bush1", "bush2", "bush3", "bush4", "treeSmall_green1", "treeSmall_green2", "foliage_001", "foliage_003"]:
		_tex[n] = load("res://assets/deco/%s.png" % n)
	world = Node2D.new()
	world.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(world)
	ground = Node2D.new()
	world.add_child(ground)
	ground.draw.connect(_draw_ground)
	dyn = Node2D.new()
	world.add_child(dyn)
	dyn.draw.connect(_draw_dyn)
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	hud.draw.connect(_draw_hud)
	ui.add_child(hud)
	_place_camera(0.0)
	Net.remote_state.connect(_on_remote_state)
	Net.mg_msg.connect(_on_mg_msg)
	Net.mg_state.connect(_on_mg_state)
	Net.mg_ending.connect(_on_ending)
	Net.mg_ready_changed.connect(func(r): ready_ids = r)
	Net.mg_go.connect(func(): go_received = true)
	Net.players_changed.connect(_on_players_changed)


# ------------------------------------------------------------------ le labyrinthe
func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CS, (c.y + 0.5) * CS)


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(floorf(p.x / CS)), 0, NX - 1), clampi(int(floorf(p.y / CS)), 0, NY - 1))


func in_maze(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < NX and c.y < NY


## Peut-on passer de la case c à la voisine c + d ?
func open_to(c: Vector2i, d: Vector2i) -> bool:
	var n := c + d
	if not in_maze(n):
		return c == exit_cell and d == exit_dir
	if d == Vector2i.RIGHT:
		return not wall_r[c]
	if d == Vector2i.LEFT:
		return not wall_r[n]
	if d == Vector2i.DOWN:
		return not wall_d[c]
	return not wall_d[n]


const DIRS := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]


## Labyrinthe parfait (exploration en profondeur), quelques murs en moins pour faire des boucles,
## une salle de départ 3x3 au centre et une sortie loin du centre.
func _build() -> void:
	for y in NY:
		for x in NX:
			wall_r[Vector2i(x, y)] = true
			wall_d[Vector2i(x, y)] = true
	var seen := {center: true}
	var stack: Array = [center]
	while not stack.is_empty():
		var c: Vector2i = stack[-1]
		var opts: Array = []
		for d in DIRS:
			var n: Vector2i = c + d
			if in_maze(n) and not seen.has(n):
				opts.append(d)
		if opts.is_empty():
			stack.pop_back()
			continue
		var d2: Vector2i = opts[rng.randi() % opts.size()]
		_remove_wall(c, d2)
		seen[c + d2] = true
		stack.append(c + d2)
	# boucles : on retire quelques murs intérieurs au hasard
	for y in NY:
		for x in NX:
			var c := Vector2i(x, y)
			if x < NX - 1 and wall_r[c] and rng.randf() < 0.09:
				wall_r[c] = false
			if y < NY - 1 and wall_d[c] and rng.randf() < 0.09:
				wall_d[c] = false
	# salle de départ
	for y in range(center.y - 1, center.y + 2):
		for x in range(center.x - 1, center.x + 2):
			if x < center.x + 1:
				wall_r[Vector2i(x, y)] = false
			if y < center.y + 1:
				wall_d[Vector2i(x, y)] = false
	# sortie : une case du bord, loin du centre (en nombre de cases)
	var from_c := _bfs(center)
	var border: Array = []
	var far := 0
	for y in NY:
		for x in NX:
			var c := Vector2i(x, y)
			var on_edge := x == 0 or y == 0 or x == NX - 1 or y == NY - 1
			var corner := (x == 0 or x == NX - 1) and (y == 0 or y == NY - 1)
			if on_edge and not corner:
				border.append(c)
				far = maxi(far, int(from_c[c]))
	var cands := border.filter(func(c): return int(from_c[c]) >= int(far * 0.75))
	exit_cell = cands[rng.randi() % cands.size()]
	if exit_cell.x == 0:
		exit_dir = Vector2i.LEFT
	elif exit_cell.x == NX - 1:
		exit_dir = Vector2i.RIGHT
	elif exit_cell.y == 0:
		exit_dir = Vector2i.UP
	else:
		exit_dir = Vector2i.DOWN
	exit_pos = cell_center(exit_cell) + Vector2(exit_dir) * CS * 0.5
	dist_exit = _bfs(exit_cell)
	# champignons dans les culs-de-sac
	var ends: Array = []
	for y in NY:
		for x in NX:
			var c := Vector2i(x, y)
			if c == exit_cell or (absi(x - center.x) <= 1 and absi(y - center.y) <= 1):
				continue
			var n_open := 0
			for d in DIRS:
				if open_to(c, d):
					n_open += 1
			if n_open == 1:
				ends.append(c)
	for c in ends:
		if rng.randf() < 0.5 and shrooms.size() < 12:
			shrooms.append(cell_center(c))
	# haies : un rectangle par mur, débordant sur les coins
	for y in NY:
		for x in NX:
			var c := Vector2i(x, y)
			var x1 := (x + 1) * CS
			var y1 := (y + 1) * CS
			if wall_r[c] and not (c == exit_cell and exit_dir == Vector2i.RIGHT):
				walls.append(Rect2(Vector2(x1 - WT / 2.0, y * CS - WT / 2.0), Vector2(WT, CS + WT)))
			if wall_d[c] and not (c == exit_cell and exit_dir == Vector2i.DOWN):
				walls.append(Rect2(Vector2(x * CS - WT / 2.0, y1 - WT / 2.0), Vector2(CS + WT, WT)))
			if x == 0 and not (c == exit_cell and exit_dir == Vector2i.LEFT):
				walls.append(Rect2(Vector2(-WT / 2.0, y * CS - WT / 2.0), Vector2(WT, CS + WT)))
			if y == 0 and not (c == exit_cell and exit_dir == Vector2i.UP):
				walls.append(Rect2(Vector2(x * CS - WT / 2.0, -WT / 2.0), Vector2(CS + WT, WT)))


func _remove_wall(c: Vector2i, d: Vector2i) -> void:
	match d:
		Vector2i.RIGHT:
			wall_r[c] = false
		Vector2i.LEFT:
			wall_r[c + d] = false
		Vector2i.DOWN:
			wall_d[c] = false
		Vector2i.UP:
			wall_d[c + d] = false


func _bfs(from: Vector2i) -> Dictionary:
	var dist := {from: 0}
	var q: Array = [from]
	var qi := 0
	while qi < q.size():
		var c: Vector2i = q[qi]
		qi += 1
		for d in DIRS:
			var n: Vector2i = c + d
			if in_maze(n) and not dist.has(n) and open_to(c, d):
				dist[n] = int(dist[c]) + 1
				q.append(n)
	return dist


func _hits(p: Vector2) -> bool:
	for w in walls:
		var r: Rect2 = w
		if p.x + R < r.position.x or p.x - R > r.end.x or p.y + R < r.position.y or p.y - R > r.end.y:
			continue
		var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		if q.distance_squared_to(p) < R * R:
			return true
	return false


func _on_ending() -> void:
	state = "over"
	t = 0.0
	Sfx.play("bell", -2.0, 0.0)


func _on_players_changed() -> void:
	for id in bodies.keys():
		if not Net.players.has(id):
			bodies.erase(id)
			ids.erase(id)
			host_dist.erase(id)


# ------------------------------------------------------------------ réseau
func _on_remote_state(id: int, p: Vector2, v: Vector2, st: int) -> void:
	if not bodies.has(id) or id == me_id:
		return
	var snaps: Array = bodies[id]["snaps"]
	snaps.append([Time.get_ticks_msec() / 1000.0, p, v, st])
	if snaps.size() > 12:
		snaps.pop_front()


func _on_mg_msg(from_id: int, d: Dictionary) -> void:
	if not Net.is_host() or ended or not bodies.has(from_id):
		return
	if d.has("d"):
		host_dist[from_id] = int(d["d"])
	if d.has("finish") and not fin.has(from_id):
		fin[from_id] = float(d["finish"])
		if host_first_t < 0.0:
			host_first_t = race_t
		Net.mg_broadcast({"fin": fin})


func _on_mg_state(d: Dictionary) -> void:
	if d.has("fin"):
		for k in d["fin"]:
			var id := int(k)
			if not fin.has(id) and id != me_id:
				pops.append({"txt": "%s est sorti !" % Net.name_of(id), "t": 0.0, "c": Net.color_of(id)})
				Sfx.play("coin", -6.0)
			fin[id] = float(d["fin"][k])


func _finish() -> void:
	if ended:
		return
	ended = true
	var sc := {}
	for id in ids:
		if not Net.players.has(id):
			continue
		if fin.has(id):
			sc[id] = [1.0e6 - float(fin[id]) * 100.0, "Sorti en %s s" % ("%.1f" % float(fin[id])).replace(".", ",")]
		else:
			var dd := int(host_dist.get(id, 99))
			sc[id] = [-float(dd), "À %d case%s de la sortie" % [dd, "s" if dd > 1 else ""]]
	if Net.autotest != "":
		print("[maze] fin ", sc)
	Net.mg_end_with_scores(sc)


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
			race_t += delta
			if playing:
				var left := minf(delta, 0.1)
				while left > 0.0:
					var dt := minf(left, 1.0 / 60.0)
					left -= dt
					_step(dt)
				_send(delta)
			if Net.is_host() and not ended:
				var all_done := true
				for id in ids:
					if Net.players.has(id) and not fin.has(id):
						all_done = false
				if all_done or (host_first_t >= 0.0 and race_t > host_first_t + AFTER_FIRST) or race_t > MAX_T:
					_finish()
	_update_remotes()
	_place_camera(delta)
	for p in pops:
		p["t"] = float(p["t"]) + delta
	pops = pops.filter(func(p): return float(p["t"]) < 2.2)
	dyn.queue_redraw()
	hud.queue_redraw()


func _step(dt: float) -> void:
	boost_t = maxf(0.0, boost_t - dt)
	var d := Vector2.ZERO
	if finished:
		# on sort tranquillement puis on fait la fête
		if race_t - finish_t < 0.8:
			d = Vector2(exit_dir)
	elif Net.autotest != "":
		d = _bot_dir(dt)
	else:
		d = Vector2(Input.get_axis("left", "right"), Input.get_axis("up", "down")).limit_length(1.0)
	var sp := SPEED * (BOOST if boost_t > 0.0 else 1.0)
	vel = vel.move_toward(d * sp, 3000.0 * dt)
	if absf(vel.x) > 20.0:
		face = signf(vel.x)
	var np := pos + Vector2(vel.x * dt, 0)
	if finished or not _hits(np):
		pos = np
	else:
		vel.x = 0.0
		_slide(Vector2(signf(d.x), 0), dt, sp)
	np = pos + Vector2(0, vel.y * dt)
	if finished or not _hits(np):
		pos = np
	else:
		vel.y = 0.0
		_slide(Vector2(0, signf(d.y)), dt, sp)
	walk += vel.length() * dt
	# champignons
	for i in shrooms.size():
		if not taken.has(i) and pos.distance_to(shrooms[i]) < 46.0:
			taken[i] = true
			boost_t = BOOST_T
			Sfx.play("gem", -2.0)
			pops.append({"txt": "TURBO !", "t": 0.0, "c": UI.YELLOW})
	# dehors ?
	if not finished and (pos.x < -WT or pos.y < -WT or pos.x > MW + WT or pos.y > MH + WT):
		finished = true
		finish_t = race_t
		Net.mg_to_host({"finish": finish_t})
		fin[me_id] = finish_t
		Sfx.play("jingle_good", -2.0, 0.0)


## Aide pour tourner : bloqué contre une haie, on glisse vers le milieu du couloir le plus proche
## s'il y a un passage dans la direction voulue.
func _slide(d: Vector2, dt: float, sp: float) -> void:
	if d == Vector2.ZERO:
		return
	var c := cell_of(pos)
	var cc := cell_center(c)
	var di := Vector2i(int(d.x), int(d.y))
	if not open_to(c, di):
		return
	var off := (cc.y - pos.y) if d.x != 0.0 else (cc.x - pos.x)
	if absf(off) < 1.0:
		return
	var mv := signf(off) * minf(absf(off), sp * 0.8 * dt)
	var np := pos + (Vector2(0, mv) if d.x != 0.0 else Vector2(mv, 0))
	if not _hits(np):
		pos = np


func _send(dt: float) -> void:
	var b: Dictionary = bodies[me_id]
	b["p"] = pos
	b["v"] = vel
	b["face"] = face
	b["walk"] = walk
	b["st"] = _pack()
	send_acc += dt
	if send_acc >= 1.0 / 25.0:
		send_acc = 0.0
		Net.send_state(pos, vel, _pack())
	prog_acc += dt
	if prog_acc > 0.4 and not finished:
		prog_acc = 0.0
		Net.mg_to_host({"d": int(dist_exit.get(cell_of(pos), 99))})


func _pack() -> int:
	return (1 if finished else 0) | (2 if boost_t > 0.0 else 0)


## Robot de test : suit le plus court chemin vers la sortie (à sa vitesse).
func _bot_dir(dt: float) -> Vector2:
	bot_acc += dt
	var c := cell_of(pos)
	if bot_acc > 0.3 or bot_path.is_empty():
		bot_acc = 0.0
		bot_path = []
		var cur := c
		for k in 200:
			if cur == exit_cell:
				break
			var best_d := int(dist_exit.get(cur, 999))
			var nxt := cur
			for d in DIRS:
				var n: Vector2i = cur + d
				if in_maze(n) and open_to(cur, d) and int(dist_exit.get(n, 999)) < best_d:
					best_d = int(dist_exit[n])
					nxt = n
			if nxt == cur:
				break
			bot_path.append(nxt)
			cur = nxt
	var target := exit_pos + Vector2(exit_dir) * 80.0
	if not bot_path.is_empty():
		target = cell_center(bot_path[0])
		if pos.distance_to(target) < 14.0:
			bot_path.pop_front()
	# au milieu du couloir avant de tourner
	var to := target - pos
	var cc := cell_center(c)
	if absf(to.x) > absf(to.y) and absf(pos.y - cc.y) > 8.0 and c != exit_cell:
		to = Vector2(0, cc.y - pos.y)
	elif absf(to.y) >= absf(to.x) and absf(pos.x - cc.x) > 8.0 and c != exit_cell:
		to = Vector2(cc.x - pos.x, 0)
	return to.normalized() * bot_speed


func _update_remotes() -> void:
	var rt := Time.get_ticks_msec() / 1000.0 - 0.1
	for id in bodies:
		if id == me_id:
			continue
		var b: Dictionary = bodies[id]
		var snaps: Array = b["snaps"]
		if snaps.is_empty():
			continue
		var p: Vector2 = snaps[-1][1]
		b["v"] = snaps[-1][2]
		b["st"] = int(snaps[-1][3])
		if rt < float(snaps[-1][0]):
			for i in range(snaps.size() - 1, 0, -1):
				var a: Array = snaps[i - 1]
				var c: Array = snaps[i]
				if float(a[0]) <= rt:
					p = (a[1] as Vector2).lerp(c[1], clampf((rt - float(a[0])) / maxf(0.001, float(c[0]) - float(a[0])), 0.0, 1.0))
					break
		var old: Vector2 = b["p"]
		b["p"] = p
		if absf(p.x - old.x) > 0.5:
			b["face"] = 1.0 if p.x > old.x else -1.0
		b["walk"] = float(b["walk"]) + old.distance_to(p)


func _place_camera(delta: float) -> void:
	var target := pos
	spec_id = 0
	if not playing or (finished and race_t - finish_t > 1.6):
		var cands: Array = []
		for id in ids:
			if id != me_id and bodies.has(id) and not fin.has(id):
				cands.append(id)
		if not cands.is_empty():
			var cur := 0
			if Input.is_action_just_pressed("left") or Input.is_action_just_pressed("right"):
				cur = 1 if Input.is_action_just_pressed("right") else -1
			if not cands.has(spec_id_keep):
				spec_id_keep = cands[0]
			elif cur != 0:
				spec_id_keep = cands[(cands.find(spec_id_keep) + cur + cands.size()) % cands.size()]
			spec_id = spec_id_keep
			target = bodies[spec_id]["p"]
		elif not playing:
			target = cell_center(center)
	var lim := Rect2(Vector2(640.0 - OUT, 360.0 - OUT), Vector2(MW + 2.0 * OUT - 1280.0, MH + 2.0 * OUT - 720.0))
	target = Vector2(clampf(target.x, lim.position.x, lim.end.x), clampf(target.y, lim.position.y, lim.end.y))
	cam = target if delta <= 0.0 else cam.lerp(target, 1.0 - exp(-delta * 10.0))
	world.position = (Vector2(640, 360) - cam).round()



func ranking() -> Array:
	var arr := ids.duplicate()
	arr.sort_custom(func(a, b):
		var fa := fin.has(a)
		var fb := fin.has(b)
		if fa != fb:
			return fa
		if fa:
			return float(fin[a]) < float(fin[b])
		return a < b)
	return arr


# ------------------------------------------------------------------ dessin
func _h(n: int) -> int:
	var v := (n * 374761393 + 668265263) & 0x7fffffff
	v = ((v ^ (v >> 13)) * 1274126177) & 0x7fffffff
	return v


const GRASS := Color("#9fd36a")
const PATH := Color("#f3e3b6")
const HEDGE := Color("#3f9a45")
const HEDGE_TOP := Color("#67c15a")


## Le labyrinthe ne bouge pas : dessiné une seule fois (Godot garde les commandes de dessin).
func _draw_ground() -> void:
	var c := ground
	# herbe autour, avec touffes et fleurs
	c.draw_rect(Rect2(-OUT - 400.0, -OUT - 400.0, MW + 2.0 * OUT + 800.0, MH + 2.0 * OUT + 800.0), GRASS)
	for k in 260:
		var hv := _h(k + 11)
		var p := Vector2(float(hv % int(MW + 2.0 * OUT)) - OUT, float((hv >> 9) % int(MH + 2.0 * OUT)) - OUT)
		if p.x > -40.0 and p.y > -40.0 and p.x < MW + 40.0 and p.y < MH + 40.0:
			continue
		if hv % 5 == 0:
			for f in 5:
				c.draw_circle(p + Vector2.from_angle(f * TAU / 5.0) * 6.0, 4.5, [Color("#ffffff"), Color("#ffe27a"), Color("#ff9ebb")][hv % 3])
			c.draw_circle(p, 3.5, Color("#ffcf3f"))
		else:
			for g in 3:
				c.draw_line(p + Vector2(g * 6 - 6, 0), p + Vector2(g * 6 - 8 + g * 2, -12), Color("#7fbd4f"), 3.0)
	# quelques arbustes autour
	for k in 26:
		var hv2 := _h(k * 31 + 7)
		var side := hv2 % 4
		var u := float((hv2 >> 4) % 1000) / 1000.0
		var p2 := Vector2.ZERO
		match side:
			0:
				p2 = Vector2(u * MW, -OUT * 0.55)
			1:
				p2 = Vector2(u * MW, MH + OUT * 0.55)
			2:
				p2 = Vector2(-OUT * 0.55, u * MH)
			_:
				p2 = Vector2(MW + OUT * 0.55, u * MH)
		if p2.distance_to(exit_pos) < 260.0:
			continue
		var tn: String = ["bush1", "bush2", "bush3", "bush4", "treeSmall_green1", "treeSmall_green2"][hv2 % 6]
		var tx: Texture2D = _tex[tn]
		var s := 0.55 + float((hv2 >> 2) % 4) * 0.08
		c.draw_set_transform(p2, 0.0, Vector2(s, s))
		c.draw_texture(tx, Vector2(-tx.get_width() / 2.0, -tx.get_height()))
		c.draw_set_transform(Vector2.ZERO)
	# chemin de la sortie (tapis à damier vers l'extérieur)
	var ed := Vector2(exit_dir)
	var side_v := Vector2(-ed.y, ed.x)
	for k in 6:
		for j in 4:
			var cp := exit_pos + ed * (12.0 + k * 26.0) + side_v * ((j - 1.5) * 26.0)
			c.draw_rect(Rect2(cp - Vector2(13, 13), Vector2(26, 26)), UI.WHITE if (k + j) % 2 == 0 else UI.INK)
	# sol du labyrinthe
	c.draw_rect(Rect2(-WT / 2.0, -WT / 2.0, MW + WT, MH + WT), PATH)
	for y in NY:
		for x in NX:
			if (x + y) % 2 == 0:
				c.draw_rect(Rect2(x * CS, y * CS, CS, CS), Color(1, 1, 1, 0.18))
			var hv3 := _h(x * 97 + y * 13)
			for g in 3:
				var gp := Vector2(x * CS + 24.0 + float((hv3 >> (g * 5)) % 92), y * CS + 24.0 + float((hv3 >> (g * 5 + 3)) % 92))
				c.draw_circle(gp, 2.5 + g, Color("#e2cc93"))
	# dalle de départ
	var c0 := cell_center(center)
	c.draw_circle(c0, 132.0, Color("#e9d39b"))
	c.draw_arc(c0, 132.0, 0, TAU, 64, Color("#d6bc7c"), 6.0)
	c.draw_circle(c0, 104.0, Color("#f7ebc8"))
	UI.text(c, c0 + Vector2(0, 112), "DÉPART", 22, Color("#c2a565"), 0)
	# haies : ombre, côté sombre, dessus clair, petites feuilles
	for w in walls:
		var r: Rect2 = w
		c.draw_style_box(UI.box(Color(0, 0, 0, 0.13), Color(0, 0, 0, 0), 0, 14), Rect2(r.position + Vector2(5, 12), r.size))
	for w in walls:
		var r: Rect2 = w
		c.draw_style_box(UI.box(UI.INK, Color(0, 0, 0, 0), 0, 16), r.grow(3))
	for w in walls:
		var r: Rect2 = w
		c.draw_style_box(UI.box(HEDGE, Color(0, 0, 0, 0), 0, 14), r)
	for w in walls:
		var r: Rect2 = w
		c.draw_style_box(UI.box(HEDGE_TOP, Color(0, 0, 0, 0), 0, 12), Rect2(r.position + Vector2(3, 2), r.size - Vector2(6, 11)))
	for i in walls.size():
		var r: Rect2 = walls[i]
		var long := maxf(r.size.x, r.size.y)
		var horiz := r.size.x > r.size.y
		var n := int(long / 30.0)
		for k in n:
			var hv4 := _h(i * 53 + k)
			var u := (k + 0.5) / float(n)
			var lp := r.position + (Vector2(u * r.size.x, r.size.y * 0.3 + float(hv4 % 6)) if horiz else Vector2(r.size.x * 0.3 + float(hv4 % 8), u * r.size.y))
			c.draw_circle(lp, 6.0 + float(hv4 % 3), Color("#86d46f"))
			if hv4 % 4 == 0:
				c.draw_circle(lp + Vector2(10, 6), 3.0, Color("#ff8fb0") if hv4 % 8 == 0 else Color("#fff3a6"))
	# arche de sortie
	_draw_gate(c)


func _draw_gate(c: CanvasItem) -> void:
	var ed := Vector2(exit_dir)
	var sv := Vector2(-ed.y, ed.x)
	var p := exit_pos
	for sd in [-1.0, 1.0]:
		var pp: Vector2 = p + sv * sd * (CS / 2.0 - 6.0)
		c.draw_circle(pp + Vector2(4, 8), 22.0, Color(0, 0, 0, 0.15))
		c.draw_circle(pp, 22.0, UI.INK)
		c.draw_circle(pp, 18.0, Color("#c98a4b"))
		c.draw_circle(pp + Vector2(-5, -5), 6.0, Color("#e6b07a"))
	# panneau « SORTIE » posé dehors, à côté de l'ouverture
	var sp: Vector2 = p + ed * 96.0 + sv * (CS / 2.0 + 40.0)
	var sr := Rect2(sp - Vector2(66, 28), Vector2(132, 50))
	c.draw_rect(Rect2(sp + Vector2(-5, 18), Vector2(10, 34)), Color("#8a5a32"))
	UI.panel(c, sr, UI.GREEN, UI.WHITE, 12, 4)
	UI.text(c, UI.face_center(sr), "SORTIE", 24, UI.WHITE, 6)


func _draw_dyn() -> void:
	var c := dyn
	# drapeau de l'arrivée (animé)
	var ed := Vector2(exit_dir)
	var sv := Vector2(-ed.y, ed.x)
	var fp := exit_pos + ed * 70.0 - sv * (CS / 2.0 + 34.0)
	var ft: Texture2D = _tex["flag" if int(t * 4.0) % 2 == 0 else "flag_b"]
	c.draw_texture_rect(ft, Rect2(fp - Vector2(40, 80), Vector2(80, 80)), false)
	# champignons
	for i in shrooms.size():
		if playing and taken.has(i):
			continue
		var sp: Vector2 = shrooms[i]
		var bob := sin(t * 4.0 + i) * 4.0
		c.draw_set_transform(sp + Vector2(0, 16), 0.0, Vector2(1.0, 0.35))
		c.draw_circle(Vector2.ZERO, 20.0, Color(0, 0, 0, 0.15))
		c.draw_set_transform(Vector2.ZERO)
		c.draw_texture_rect(_tex["shroom"], Rect2(sp + Vector2(-27, -36 + bob), Vector2(54, 54)), false)
	# persos (du haut vers le bas), moi par-dessus
	var order := bodies.keys()
	order.sort_custom(func(a, b): return float(bodies[a]["p"].y) < float(bodies[b]["p"].y))
	for id in order:
		if id != me_id:
			_draw_body(c, id)
	if playing and bodies.has(me_id):
		_draw_body(c, me_id)
	# flèche vers la sortie (direction seulement)
	if playing and not finished and state != "intro":
		var to := exit_pos - pos
		if to.length() > 150.0:
			var a := to.angle()
			var ap := pos + Vector2(0, -30) + Vector2.from_angle(a) * 74.0
			var pul := 1.0 + 0.08 * sin(t * 6.0)
			var tri := PackedVector2Array([Vector2(26, 0), Vector2(-12, -18), Vector2(-4, 0), Vector2(-12, 18)])
			c.draw_set_transform(ap, a, Vector2(pul, pul))
			var outl := PackedVector2Array([Vector2(33, 0), Vector2(-17, -25), Vector2(-9, 0), Vector2(-17, 25)])
			c.draw_colored_polygon(outl, UI.INK)
			c.draw_colored_polygon(tri, UI.YELLOW)
			c.draw_set_transform(Vector2.ZERO)


func _draw_body(c: CanvasItem, id: int) -> void:
	var b: Dictionary = bodies[id]
	var g: Vector2 = b["p"]
	var st := int(b["st"])
	var mine := id == me_id
	var done := (st & 1) != 0 or fin.has(id)
	c.draw_set_transform(g + Vector2(0, 14), 0.0, Vector2(1.0, 0.36))
	c.draw_circle(Vector2.ZERO, 24.0, Color(0, 0, 0, 0.2))
	c.draw_set_transform(Vector2.ZERO)
	var moving := (b["v"] as Vector2).length() > 30.0
	var pose := ("walk_a" if int(float(b["walk"]) / 34.0) % 2 == 0 else "walk_b") if moving else "idle"
	var hop := 0.0
	if done and not moving:
		pose = "jump" if int(t * 3.0 + id) % 2 == 0 else "front"
		hop = absf(sin(t * 6.0 + id)) * 14.0
	if (st & 2) != 0:
		for k in 3:
			var lx := -float(b["face"]) * (30.0 + k * 10.0)
			c.draw_line(g + Vector2(lx, -50 + k * 16), g + Vector2(lx - float(b["face"]) * 22.0, -50 + k * 16), Color(1, 1, 1, 0.8), 4.0)
	var sc := 0.34
	c.draw_set_transform(g + Vector2(0, 18 - hop), 0.0, Vector2(sc * float(b["face"]), sc))
	c.draw_texture(_tex["%d_%s" % [id, pose]], Vector2(-128, -256))
	c.draw_set_transform(Vector2.ZERO)
	if mine:
		UI.text(c, g + Vector2(0, -88 - hop), "TOI", 18, UI.YELLOW, 6)
	else:
		UI.text(c, g + Vector2(0, -88 - hop), Net.name_of(id), 15, Net.color_of(id), 5)


# ------------------------------------------------------------------ HUD
func _draw_hud() -> void:
	var h := hud
	var St := preload("res://minigames/stage.gd")
	if state == "intro":
		St.draw_intro(h, "Sors du labyrinthe !", [
			"Tout le monde part du centre du labyrinthe.",
			"Une seule sortie : le premier dehors gagne !",
			"La flèche jaune montre la direction de la sortie... pas le chemin !",
			"Les champignons au fond des culs-de-sac font courir plus vite.",
			"Après le premier sorti, les autres ont 15 secondes."],
			"Bouger : flèches ou Z Q S D")
		St.draw_ready_row(h, my_ready, ready_ids, ids, t, not playing)
		if str(Net.mg_data.get("mode", "")) == "duel":
			St.draw_duel_banner(h)
		return
	# chrono (compte à rebours de 15 s après le premier sorti)
	var tr := Rect2(Vector2(24, 18), Vector2(150, 54))
	UI.panel(h, tr, UI.WHITE, UI.WHITE, 16, 4)
	var first := -1.0
	for id in fin:
		first = float(fin[id]) if first < 0.0 else minf(first, float(fin[id]))
	if first >= 0.0 and state == "play":
		var left := maxf(0.0, first + AFTER_FIRST - race_t)
		UI.text(h, UI.face_center(tr), "%d s" % int(ceilf(left)), 28, UI.RED, 0)
	else:
		var shown := finish_t if finished else race_t
		UI.text(h, UI.face_center(tr), "%d:%02d" % [int(shown) / 60, int(shown) % 60], 28, UI.DARK, 0)
	# en haut : les têtes ; coche verte et temps pour ceux qui sont sortis
	var order := ranking()
	var n := order.size()
	var w := 74.0
	var x0 := 640.0 - n * w / 2.0
	for i in n:
		var id: int = order[i]
		var hc := Vector2(x0 + i * w + w / 2.0, 42)
		var out := fin.has(id)
		UI.portrait(h, hc, 24.0, Net.color_idx(id), UI.GREEN.lightened(0.3) if out else UI.WHITE, Color.WHITE if out else Color(0.8, 0.8, 0.85))
		if out:
			h.draw_circle(hc + Vector2(18, 17), 11, UI.WHITE)
			h.draw_circle(hc + Vector2(18, 17), 8, UI.GREEN)
			h.draw_polyline(PackedVector2Array([hc + Vector2(13, 17), hc + Vector2(17, 21), hc + Vector2(23, 13)]), UI.WHITE, 2.5)
			UI.text(h, hc + Vector2(0, 42), "%s s" % ("%.1f" % float(fin[id])).replace(".", ","), 16, UI.YELLOW, 5)
		elif id == me_id:
			UI.text(h, hc + Vector2(0, 42), "TOI", 16, UI.YELLOW, 5)
	for j in pops.size():
		var p: Dictionary = pops[j]
		var k := float(p["t"]) / 2.2
		UI.text(h, Vector2(640, 150 - k * 30.0 + j * 4.0), str(p["txt"]), 30, Color(p["c"], 1.0 - k * k), 8)
	if state == "count":
		UI.text(h, Vector2(640, 330), str(3 - int(t)), int(110 * (1.0 + (1.0 - fmod(t, 1.0)) * 0.3)), UI.WHITE, 16)
	elif state == "play" and t < 1.0:
		UI.text(h, Vector2(640, 330), "GO !", int(120 * (1.0 + t * 0.4)), Color(UI.YELLOW, 1.0 - t), 18)
	if state == "play" and playing and not finished and race_t < 9.0:
		var help := "Suis la flèche jaune : elle montre où est la sortie"
		var hw := UI.text_width(help, 21) + 44.0
		h.draw_style_box(UI.box(Color(UI.DARK, 0.82), UI.DARK, 0, 16), Rect2(Vector2(640 - hw / 2.0, 664), Vector2(hw, 40)))
		UI.text(h, Vector2(640, 684), help, 21, UI.YELLOW, 0)
	if finished and state == "play":
		var rk := order.find(me_id) + 1
		UI.text(h, Vector2(640, 130), "SORTI ! %d%s" % [rk, "er" if rk == 1 else "e"], 52, UI.GREEN, 12)
	if state == "play" and spec_id != 0 and bodies.has(spec_id):
		var sm := "Tu regardes %s   (← → pour changer)" % Net.name_of(spec_id)
		var sw := UI.text_width(sm, 20) + 40.0
		h.draw_style_box(UI.box(Color(UI.DARK, 0.8), UI.DARK, 0, 14), Rect2(Vector2(640 - sw / 2.0, 664), Vector2(sw, 40)))
		UI.text(h, Vector2(640, 684), sm, 20, UI.WHITE, 0)
	if state == "over":
		h.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, minf(0.4, t)))
		UI.text(h, Vector2(640, 360), "TERMINÉ !", 96, UI.YELLOW, 16)
