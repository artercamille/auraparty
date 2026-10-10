extends Node2D
## « Toujours plus haut ! » : façon Doodle Jump. On rebondit tout seul de plateforme en plateforme,
## ← → pour se diriger ; on sort d'un côté de l'écran, on revient de l'autre. Ressorts (super saut),
## hélice (on s'envole), plateformes qui bougent, qui cassent (marron) ou qui disparaissent (blanches),
## monstres : on les écrase en leur sautant dessus, sinon on tombe. L'écran ne redescend jamais :
## tomber en bas = fini. Au bout d'une minute, le plus haut gagne.
## Les plateformes sont les mêmes pour tout le monde (même graine) ; chacun grimpe chez lui,
## les autres sont dessinés en transparence. L'hôte récolte les hauteurs et décide de la fin.

const W := 720.0                  # largeur de la colonne de jeu
const OX := (1280.0 - W) / 2.0    # bord gauche de la colonne à l'écran
const MAX_T := 60.0
const G := 2300.0                 # gravité
const JUMP_V := 1130.0            # rebond normal (~280 px)
const SPRING_V := 1950.0          # ressort (~830 px)
const HELI_V := 1250.0
const HELI_T := 2.4
const RUN := 540.0
const PW := 112.0                 # largeur des plateformes
const FOOT := 16.0                # demi-largeur des pieds
const CAM_Y := 430.0              # hauteur (depuis le bas de l'écran) où la caméra garde le joueur
const GEN_TOP := 70000.0
const MONS := ["bee", "fly", "slime"]
const PX_PER_M := 10.0

var ids: Array = []
var me_id := 0
var playing := false
var hud: Control
var view: Node2D
var state := "intro"              # intro, count, play, over
var t := 0.0
var race_t := 0.0
var my_ready := false
var go_received := false
var ready_ids: Array = []
var rng := RandomNumberGenerator.new()
var brng := RandomNumberGenerator.new()
var _tex := {}

# le niveau (identique chez tout le monde)
var plats: Array = []             # {a, x, w, k (g n m b v), amp, sp, ph, it ("", spring, heli), io}
var mons: Array = []              # {a, x, amp, sp, ph, k}
var plat_alts := PackedFloat64Array()
# ce qui a bougé chez moi
var broken := {}                  # plateforme marron cassée -> instant
var gone := {}                    # plateforme blanche disparue -> instant
var dead_mon := {}                # monstre écrasé -> instant
var spring_t := {}                # ressort utilisé -> instant
var taken := {}                   # hélice ramassée

# mon perso
var x := W / 2.0
var alt := 0.0
var vx := 0.0
var vy := 0.0
var facing := 1.0
var heli_t := 0.0
var hit := false
var fell := false
var fell_t := 0.0
var best := 0.0
var squash := 0.0
var spin := 0.0                   # salto après un ressort (0..1)
var cam_a := -170.0               # altitude du bas de l'écran
var send_acc := 0.0
var prog_acc := 0.0
var spec_id := 0
var pops: Array = []
var bot_tx := W / 2.0
var bot_acc := 0.0

# les autres (fantômes)
var ghosts := {}                  # id -> {x, a, st, snaps}
var outs := {}                    # id -> hauteur finale (tombés)
var bests := {}                   # id -> meilleure hauteur connue
# hôte
var host_best := {}
var host_out := {}
var ended := false
var pose := false
const POSE_OFFS := [Vector2(-200, 170), Vector2(210, -90), Vector2(-40, -260)]


func _ready() -> void:
	rng.seed = int(Net.mg_data.get("seed", 1))
	brng.randomize()
	for id in Net.mg_data.get("players", Net.players.keys()):
		if Net.players.has(id):
			ids.append(id)
	ids.sort()
	me_id = Net.my_id()
	playing = ids.has(me_id)
	for i in ids.size():
		var id: int = ids[i]
		var sx := W * float(i + 1) / float(ids.size() + 1)
		ghosts[id] = {"x": sx, "a": 0.0, "st": 0, "snaps": [], "vx": 0.0, "vy": 0.0}
		bests[id] = 0.0
		if id == me_id:
			x = sx
		for pose in ["idle", "jump", "hit"]:
			_tex["%d_%s" % [id, pose]] = UI.char_tex(Net.color_idx(id), pose)
	for n in ["bee_a", "bee_b", "fly_a", "slime_spike_walk_a", "slime_spike_walk_b"]:
		_tex[n] = load("res://assets/enemies/%s.png" % n)
	for n in ["cloud1", "cloud2", "cloud3", "cloud5", "cloud7"]:
		_tex[n] = load("res://assets/deco/%s.png" % n)
	_build()
	# tests : départ plus haut (DOODLE_ALT=altitude) pour voir les monstres et les bonus
	if Net.autotest != "" and OS.get_environment("DOODLE_ALT") != "":
		for i in range(first_at(float(OS.get_environment("DOODLE_ALT"))), plats.size()):
			if str(plats[i]["k"]) == "n":
				x = float(plats[i]["x"])
				alt = float(plats[i]["a"])
				cam_a = alt - 150.0
				break
	# aperçu (DOODLE_POSE=1) : image figée avec hélice, ressort, monstre et les autres autour
	if Net.autotest != "" and OS.get_environment("DOODLE_POSE") != "":
		pose = true
		x = W / 2.0 - 30.0
		alt = maxf(alt, 3000.0) + 200.0
		cam_a = alt - CAM_Y
		heli_t = 999.0
		best = alt
		var zones := [Vector2(x, alt), Vector2(x + 250.0, alt + 190.0), Vector2(x - 200.0, alt - 170.0), Vector2(x + 190.0, alt - 330.0)]
		plats = plats.filter(func(p):
			for z in zones:
				if absf(float(p["a"]) - z.y) < 80.0 and absf(float(p["x"]) - z.x) < 150.0:
					return false
			return true)
		plats.append({"a": alt - 170.0, "x": x - 200.0, "w": PW, "k": "n", "amp": 0.0, "sp": 0.0, "ph": 0.0, "it": "spring", "io": 10.0})
		plats.append({"a": alt - 330.0, "x": x + 190.0, "w": PW, "k": "v", "amp": 0.0, "sp": 0.0, "ph": 0.0, "it": "", "io": 0.0})
		plats.sort_custom(func(p, q): return float(p["a"]) < float(q["a"]))
		plat_alts = PackedFloat64Array()
		for p in plats:
			plat_alts.append(float(p["a"]))
		mons.append({"a": alt + 190.0, "x": x + 250.0, "amp": 0.0, "sp": 1.0, "ph": 0.0, "k": "bee"})
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
	Net.mg_msg.connect(_on_mg_msg)
	Net.mg_state.connect(_on_mg_state)
	Net.mg_ending.connect(_on_ending)
	Net.mg_ready_changed.connect(func(r): ready_ids = r)
	Net.mg_go.connect(func(): go_received = true)
	Net.players_changed.connect(_on_players_changed)


## Le niveau : un chemin de plateformes toujours atteignable (écart < hauteur d'un saut),
## plus des plateformes « en trop » (pièges marron, bonus) ; ça se corse avec l'altitude.
func _build() -> void:
	plats.append({"a": 0.0, "x": W / 2.0, "w": W, "k": "g", "amp": 0.0, "sp": 0.0, "ph": 0.0, "it": "", "io": 0.0})
	var a := 0.0
	var last_x := W / 2.0
	while a < GEN_TOP:
		var diff := clampf(a / 22000.0, 0.0, 1.0)
		var gap := rng.randf_range(lerpf(55.0, 125.0, diff), lerpf(120.0, 245.0, diff))
		a += gap
		var k := "n"
		var roll := rng.randf()
		if a > 1200.0 and roll < 0.08 + diff * 0.27:
			k = "m"
		elif a > 2500.0 and roll < 0.14 + diff * 0.38:
			k = "v"
		var px := rng.randf_range(PW / 2.0 + 6.0, W - PW / 2.0 - 6.0)
		# grand écart : la plateforme suivante n'est pas trop loin sur le côté (on doit pouvoir l'atteindre)
		if gap > 170.0:
			px = fposmod(last_x + rng.randf_range(-240.0, 240.0), W)
			px = clampf(px, PW / 2.0 + 6.0, W - PW / 2.0 - 6.0)
		var p := {"a": a, "x": px, "w": PW, "k": k, "amp": 0.0, "sp": 0.0, "ph": 0.0, "it": "", "io": 0.0}
		if k == "m":
			var amp := rng.randf_range(80.0, 220.0)
			p["amp"] = amp
			p["x"] = clampf(px, PW / 2.0 + amp + 4.0, W - PW / 2.0 - amp - 4.0)
			p["sp"] = rng.randf_range(0.9, 1.5 + diff)
			p["ph"] = rng.randf() * TAU
		if k == "n":
			var r2 := rng.randf()
			if r2 < 0.075 - diff * 0.02 and a > 400.0:
				p["it"] = "spring"
				p["io"] = rng.randf_range(-PW / 2.0 + 20.0, PW / 2.0 - 20.0)
			elif r2 < 0.095 and a > 3000.0:
				p["it"] = "heli"
				p["io"] = rng.randf_range(-20.0, 20.0)
		plats.append(p)
		last_x = float(p["x"])
		# plateformes en plus : nombreuses en bas, de plus en plus rares
		if rng.randf() < 0.55 - diff * 0.45:
			var ex := _away_from(last_x)
			plats.append({"a": a + rng.randf_range(-40.0, 40.0), "x": ex, "w": PW, "k": "n", "amp": 0.0, "sp": 0.0, "ph": 0.0, "it": "", "io": 0.0, "extra": true})
		# pièges marron (cassent quand on atterrit dessus)
		if a > 800.0 and rng.randf() < 0.12 + diff * 0.25:
			var bx := _away_from(last_x)
			plats.append({"a": a - gap * rng.randf_range(0.4, 0.6), "x": bx, "w": PW, "k": "b", "amp": 0.0, "sp": 0.0, "ph": 0.0, "it": "", "io": 0.0, "extra": true})
		# monstres, loin du chemin
		if a > 3500.0 and rng.randf() < 0.035 + diff * 0.05:
			var mx := fposmod(last_x + W / 2.0 + rng.randf_range(-80.0, 80.0), W - 120.0) + 60.0
			mons.append({"a": a + gap * 0.5 + 40.0, "x": mx, "amp": rng.randf_range(0.0, 60.0), "sp": rng.randf_range(1.0, 2.2),
				"ph": rng.randf() * TAU, "k": MONS[rng.randi() % MONS.size()]})
	plats.sort_custom(func(p, q): return float(p["a"]) < float(q["a"]))
	# on retire les plateformes en plus qui en chevauchent une autre
	var keep: Array = []
	for i in plats.size():
		var p: Dictionary = plats[i]
		var ok := true
		if p.get("extra", false):
			for j in range(maxi(0, i - 4), mini(plats.size(), i + 5)):
				var q: Dictionary = plats[j]
				if j != i and absf(float(q["a"]) - float(p["a"])) < 34.0 and absf(float(q["x"]) - float(p["x"])) < PW + float(q["amp"]) + 14.0 and not (q.get("extra", false) and j > i):
					ok = false
		if ok:
			keep.append(p)
	plats = keep
	for p in plats:
		plat_alts.append(float(p["a"]))


## Indice de la première plateforme à l'altitude `a` ou au-dessus.
func first_at(a: float) -> int:
	return plat_alts.bsearch(a, true)


## Une position libre à côté de la plateforme `x0` (pas de plateformes qui se chevauchent).
func _away_from(x0: float) -> float:
	var lo := PW / 2.0 + 6.0
	var hi := W - PW / 2.0 - 6.0
	var ex := rng.randf_range(lo, hi)
	for k in 8:
		if absf(ex - x0) > PW + 30.0:
			break
		ex = rng.randf_range(lo, hi)
	if absf(ex - x0) <= PW + 30.0:
		ex = x0 + PW + 40.0 if x0 < W / 2.0 else x0 - PW - 40.0
	return ex


static func _tri(u: float) -> float:
	return asin(sin(u)) * 2.0 / PI


func plat_x(p: Dictionary) -> float:
	if str(p["k"]) == "m":
		return float(p["x"]) + float(p["amp"]) * _tri(float(p["sp"]) * race_t + float(p["ph"]))
	return float(p["x"])


func mon_pos(m: Dictionary) -> Vector2:
	return Vector2(float(m["x"]) + float(m["amp"]) * sin(float(m["sp"]) * race_t + float(m["ph"])),
		float(m["a"]) + sin(race_t * 3.0 + float(m["ph"])) * 6.0)


static func wrap_dx(d: float) -> float:
	return wrapf(d, -W / 2.0, W / 2.0)


func _on_ending() -> void:
	state = "over"
	t = 0.0
	Sfx.play("bell", -2.0, 0.0)


func _on_players_changed() -> void:
	for id in ghosts.keys():
		if not Net.players.has(id):
			ghosts.erase(id)
			ids.erase(id)
			host_best.erase(id)
			host_out.erase(id)


# ------------------------------------------------------------------ réseau
func _on_remote_state(id: int, p: Vector2, vel: Vector2, st: int) -> void:
	if not ghosts.has(id) or id == me_id:
		return
	var snaps: Array = ghosts[id]["snaps"]
	snaps.append([Time.get_ticks_msec() / 1000.0, p, vel, st])
	if snaps.size() > 12:
		snaps.pop_front()


func _on_mg_msg(from_id: int, d: Dictionary) -> void:
	if not Net.is_host() or ended or not ghosts.has(from_id):
		return
	if d.has("h"):
		host_best[from_id] = maxf(float(host_best.get(from_id, 0.0)), float(d["h"]))
	if d.has("out") and not host_out.has(from_id):
		host_best[from_id] = maxf(float(host_best.get(from_id, 0.0)), float(d["out"]))
		host_out[from_id] = float(host_best[from_id])
		Net.mg_broadcast({"outs": host_out, "bests": host_best})
		_host_check_end()


func _on_mg_state(d: Dictionary) -> void:
	if d.has("outs"):
		for k in d["outs"]:
			var id := int(k)
			if not outs.has(id) and id != me_id and ghosts.has(id):
				pops.append({"txt": "%s est tombé !" % Net.name_of(id), "t": 0.0, "c": Net.color_of(id)})
			outs[id] = float(d["outs"][k])
	if d.has("bests"):
		for k in d["bests"]:
			bests[int(k)] = maxf(float(bests.get(int(k), 0.0)), float(d["bests"][k]))


func _host_check_end() -> void:
	if ended or state != "play":
		return
	var alive: Array = []
	for id in ids:
		if Net.players.has(id) and not host_out.has(id):
			alive.append(id)
	var done := alive.is_empty() or race_t >= MAX_T
	# un seul encore en lice et déjà le plus haut : inutile d'attendre
	if alive.size() == 1 and ids.size() >= 2:
		var lead := true
		for id in ids:
			if id != alive[0] and float(host_best.get(id, 0.0)) >= float(host_best.get(alive[0], 0.0)):
				lead = false
		if lead:
			done = true
	if done:
		_finish()


func _finish() -> void:
	if ended:
		return
	ended = true
	var sc := {}
	for id in ids:
		if not Net.players.has(id):
			continue
		var h := float(int(float(host_best.get(id, 0.0)) / PX_PER_M))   # en mètres : même affichage = égalité
		var txt := "%d m" % int(h)
		if not host_out.has(id):
			txt += " (en vie)"
		sc[id] = [h, txt]
	if Net.autotest != "":
		print("[doodle] fin ", sc)
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
			if playing and not pose:
				_steps(delta, false)
			if t >= 3.0:
				state = "play"
				t = 0.0
				Sfx.voice("go")
		"play":
			race_t += delta
			if pose:
				heli_t = 999.0
				_send(delta)
			elif playing:
				_steps(delta, true)
			if Net.is_host():
				host_best[me_id] = maxf(float(host_best.get(me_id, 0.0)), best) if playing else float(host_best.get(me_id, 0.0))
				_host_check_end()
		"over":
			if playing and not fell:
				_steps(delta, false)
	_update_remotes()
	if pose:
		var k := 0
		for id in ghosts:
			if id != me_id:
				var o: Vector2 = POSE_OFFS[k % 3]
				ghosts[id]["x"] = fposmod(x + o.x, W)
				ghosts[id]["a"] = alt + o.y
				ghosts[id]["st"] = 4 if k == 1 else 0
				ghosts[id]["vy"] = 600.0 if k != 2 else -100.0
				k += 1
	_camera(delta)
	for p in pops:
		p["t"] = float(p["t"]) + delta
	pops = pops.filter(func(p): return float(p["t"]) < 2.0)
	view.queue_redraw()
	hud.queue_redraw()


## Petits pas de physique (même à 10 images/s, on ne traverse pas les plateformes).
func _steps(delta: float, control: bool) -> void:
	var left := minf(delta, 0.1)
	while left > 0.0:
		var dt := minf(left, 1.0 / 120.0)
		left -= dt
		_phys(dt, control)
	_send(delta)


func _phys(dt: float, control: bool) -> void:
	if fell:
		return
	squash = maxf(0.0, squash - dt)
	if spin > 0.0:
		spin = minf(1.0, spin + dt * 1.1)
		if spin >= 1.0:
			spin = 0.0
	var dir := 0.0
	if control and not hit:
		if Net.autotest != "":
			dir = _bot_dir(dt)
		else:
			dir = Input.get_axis("left", "right")
	if absf(dir) > 0.2:
		facing = signf(dir)
	vx = move_toward(vx, dir * RUN, (3400.0 if absf(dir) > 0.2 else 2600.0) * dt)
	if heli_t > 0.0:
		heli_t -= dt
		vy = HELI_V
		if heli_t <= 0.0:
			vy = 650.0
	else:
		vy = maxf(vy - G * dt, -1500.0)
	x = fposmod(x + vx * dt, W)
	var old := alt
	alt += vy * dt
	# atterrissage (seulement en descendant)
	if vy <= 0.0 and not hit and heli_t <= 0.0:
		for i in range(first_at(alt - 1.0), plats.size()):
			var p: Dictionary = plats[i]
			var pa: float = p["a"]
			if pa > old + 0.01:
				break
			if pa < alt or broken.has(i) or gone.has(i):
				continue
			var dx := wrap_dx(x - plat_x(p))
			if absf(dx) > float(p["w"]) / 2.0 + FOOT:
				continue
			if str(p["k"]) == "b":
				broken[i] = race_t
				Sfx.play("bump", -6.0, 0.2)
				continue
			alt = pa
			if str(p["it"]) == "spring" and absf(dx - float(p["io"])) < 24.0:
				vy = SPRING_V
				spring_t[i] = race_t
				spin = 0.001
				Sfx.play("jump2", -3.0)
			else:
				vy = JUMP_V
				Sfx.play("jump", -10.0, 0.12)
			if str(p["k"]) == "v":
				gone[i] = race_t
				Sfx.play("fall", -12.0, 0.1)
			squash = 0.12
			break
	# hélice
	for i in range(first_at(alt - 140.0), plats.size()):
		var p: Dictionary = plats[i]
		if float(p["a"]) > alt + 140.0:
			break
		if str(p["it"]) != "heli" or taken.has(i):
			continue
		var hp := Vector2(plat_x(p) + float(p["io"]), float(p["a"]) + 22.0)
		if absf(wrap_dx(x - hp.x)) < 40.0 and absf(alt + 40.0 - hp.y) < 52.0 and not hit:
			taken[i] = true
			heli_t = HELI_T
			spin = 0.0
			Sfx.play("whoosh", -2.0)
			Sfx.play("gem", -4.0)
			pops.append({"txt": "HÉLICE !", "t": 0.0, "c": UI.YELLOW})
	# monstres
	for i in mons.size():
		if dead_mon.has(i):
			continue
		var m: Dictionary = mons[i]
		var mp := mon_pos(m)
		if absf(mp.y - alt) > 160.0:
			continue
		var dx2 := wrap_dx(x - mp.x)
		var dy2 := alt + 40.0 - mp.y
		if absf(dx2) < 46.0 and absf(dy2) < 62.0 and not hit:
			if heli_t > 0.0 or (vy < 0.0 and alt > mp.y - 4.0):
				dead_mon[i] = race_t
				if heli_t <= 0.0:
					vy = JUMP_V
					squash = 0.12
				Sfx.play("bump", -2.0)
				Sfx.play("coin", -8.0)
				pops.append({"txt": "ÉCRASÉ !", "t": 0.0, "c": UI.GREEN})
			else:
				hit = true
				vy = minf(vy, 250.0)
				vx = 0.0
				Sfx.play("hurt", -2.0)
				pops.append({"txt": "AÏE !", "t": 0.0, "c": UI.RED})
	if state == "play":
		best = maxf(best, alt)
	cam_a = maxf(cam_a, alt - CAM_Y)
	if alt < cam_a - 70.0 and state == "play":
		fell = true
		fell_t = race_t
		Sfx.play("fall", 0.0, 0.0)
		Net.mg_to_host({"out": best})
		outs[me_id] = best
		if Net.autotest != "":
			print("[doodle] tombé à %d m (monstre : %s)" % [int(best / PX_PER_M), str(hit)])


func _send(dt: float) -> void:
	var g: Dictionary = ghosts[me_id]
	g["x"] = x
	g["a"] = alt
	g["st"] = _pack()
	g["vx"] = vx
	g["vy"] = vy
	bests[me_id] = best
	send_acc += dt
	if send_acc >= 1.0 / 20.0:
		send_acc = 0.0
		Net.send_state(Vector2(x, alt), Vector2(vx, vy), _pack())
	prog_acc += dt
	if prog_acc > 0.5 and state == "play":
		prog_acc = 0.0
		Net.mg_to_host({"h": best})


func _pack() -> int:
	return (1 if fell else 0) | (2 if heli_t > 0.0 else 0) | (4 if facing < 0.0 else 0) | (8 if squash > 0.0 else 0) | (16 if hit else 0) | (32 if spin > 0.0 else 0)


## Robot de test : vise la plateforme la plus haute qu'il peut atteindre.
func _bot_dir(dt: float) -> float:
	bot_acc += dt
	if bot_acc > 0.1:
		bot_acc = 0.0
		var apex := alt + maxf(0.0, vy) * maxf(0.0, vy) / (2.0 * G)
		var best_s := -1.0e9
		for i in range(first_at(alt - 300.0), plats.size()):
			var p: Dictionary = plats[i]
			var pa: float = p["a"]
			if pa > apex - 10.0:
				break
			if str(p["k"]) == "b" or gone.has(i):
				continue
			if vy < 0.0 and pa > alt:
				continue
			var dx := absf(wrap_dx(plat_x(p) - x))
			# temps pour tomber jusqu'à la plateforme
			var fall_h := apex - pa
			var tt := (maxf(0.0, vy) / G) + sqrt(2.0 * maxf(0.0, fall_h) / G)
			if dx > RUN * tt * 0.85 + PW / 2.0:
				continue
			var sc := pa - dx * 0.15 + (400.0 if str(p["it"]) == "spring" else 0.0)
			if sc > best_s:
				best_s = sc
				bot_tx = plat_x(p) + (float(p["io"]) if str(p["it"]) == "spring" else 0.0)
	# s'écarte des monstres juste au-dessus
	for m in mons:
		var mp := mon_pos(m)
		var mdx := wrap_dx(mp.x - x)
		if mp.y > alt - 140.0 and mp.y < alt + 320.0 and absf(mdx) < 125.0 and not (vy < 0.0 and alt > mp.y + 30.0):
			return -signf(mdx) if mdx != 0.0 else 1.0
	var d := wrap_dx(bot_tx - x)
	if absf(d) < 10.0:
		return 0.0
	return clampf(d / 40.0, -1.0, 1.0)


func _update_remotes() -> void:
	var rt := Time.get_ticks_msec() / 1000.0 - 0.1
	for id in ghosts:
		if id == me_id:
			continue
		var g: Dictionary = ghosts[id]
		var snaps: Array = g["snaps"]
		if snaps.is_empty():
			continue
		var p: Vector2 = snaps[-1][1]
		var st := int(snaps[-1][3])
		if rt < float(snaps[-1][0]):
			for i in range(snaps.size() - 1, 0, -1):
				var a: Array = snaps[i - 1]
				var b: Array = snaps[i]
				if float(a[0]) <= rt:
					var u := clampf((rt - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0])), 0.0, 1.0)
					var pa: Vector2 = a[1]
					var pb: Vector2 = b[1]
					# passage d'un bord à l'autre : pas d'interpolation en travers de l'écran
					p = pb if absf(pb.x - pa.x) > W / 2.0 else pa.lerp(pb, u)
					st = int(b[3])
					break
		g["x"] = p.x
		g["a"] = p.y
		g["st"] = st
		g["vy"] = (snaps[-1][2] as Vector2).y
		bests[id] = maxf(float(bests.get(id, 0.0)), p.y)


func _camera(delta: float) -> void:
	var watch := 0
	if not playing:
		watch = _spec_pick(true)
	elif fell and race_t - fell_t > 1.4:
		watch = _spec_pick(false)
	spec_id = watch
	if watch != 0 and ghosts.has(watch):
		var target := float(ghosts[watch]["a"]) - CAM_Y
		cam_a = lerpf(cam_a, target, 1.0 - exp(-delta * 5.0))


func _spec_pick(any: bool) -> int:
	var cands: Array = []
	for id in ids:
		if id != me_id and ghosts.has(id) and (int(ghosts[id]["st"]) & 1) == 0 and not outs.has(id):
			cands.append(id)
	if cands.is_empty():
		if not any:
			return 0
		for id in ids:
			if id != me_id and ghosts.has(id):
				cands.append(id)
		if cands.is_empty():
			return 0
	if not cands.has(spec_id):
		cands.sort_custom(func(p, q): return float(ghosts[p]["a"]) > float(ghosts[q]["a"]))
		return cands[0]
	if Input.is_action_just_pressed("left") or Input.is_action_just_pressed("right"):
		var i := cands.find(spec_id) + (1 if Input.is_action_just_pressed("right") else -1)
		return cands[(i + cands.size()) % cands.size()]
	return spec_id


func ranking() -> Array:
	var arr := ids.duplicate()
	arr.sort_custom(func(p, q): return float(bests.get(p, 0.0)) > float(bests.get(q, 0.0)))
	return arr


# ------------------------------------------------------------------ dessin
func _sy(a: float) -> float:
	return 720.0 - (a - cam_a)


func _sky(a: float) -> Color:
	var stops := [[0.0, Color("#bfe6ff")], [5000.0, Color("#c4d2ff")], [10000.0, Color("#f2c8ea")], [15000.0, Color("#ffcaa0")], [21000.0, Color("#b07fd0")], [27000.0, Color("#4a4596")], [33000.0, Color("#1d1b44")]]
	for i in range(stops.size() - 1):
		if a < float(stops[i + 1][0]):
			return (stops[i][1] as Color).lerp(stops[i + 1][1], clampf((a - float(stops[i][0])) / (float(stops[i + 1][0]) - float(stops[i][0])), 0.0, 1.0))
	return stops[-1][1]


func _h(n: int) -> int:
	var v := (n * 374761393 + 668265263) & 0x7fffffff
	v = ((v ^ (v >> 13)) * 1274126177) & 0x7fffffff
	return v


func _draw_view() -> void:
	var c := view
	# papier quadrillé (comme un cahier) dans la colonne
	c.draw_rect(Rect2(OX, 0, W, 720), Color("#fdf8ec"))
	var cell := 30.0
	var off := fmod(cam_a, cell)
	var yy := 720.0 + off
	var row := int(floorf(cam_a / cell))
	while yy > -cell:
		var strong := row % 5 == 0
		c.draw_line(Vector2(OX, yy), Vector2(OX + W, yy), Color("#c9dcf2") if strong else Color("#e2ecf8"), 2.0 if strong else 1.0)
		yy -= cell
		row += 1
	for k in int(W / cell) + 1:
		c.draw_line(Vector2(OX + k * cell, 0), Vector2(OX + k * cell, 720), Color("#c9dcf2") if k % 5 == 0 else Color("#e2ecf8"), 2.0 if k % 5 == 0 else 1.0)
	# sol de départ
	var gy := _sy(0.0)
	if gy < 760.0:
		c.draw_rect(Rect2(OX, gy, W, 720.0 - gy + 40.0), Color("#a8d672"))
		c.draw_rect(Rect2(OX, gy + 18.0, W, 720.0 - gy + 40.0), Color("#c99a6b"))
		c.draw_line(Vector2(OX, gy), Vector2(OX + W, gy), UI.INK, 4.0)
		for k in 24:
			c.draw_circle(Vector2(OX + 15.0 + k * 30.0, gy + 2.0), 9.0, Color("#a8d672"))
	# records des joueurs tombés
	for id in outs:
		var ry := _sy(float(outs[id]))
		if ry > 0.0 and ry < 720.0 and id != me_id:
			for k in 24:
				c.draw_line(Vector2(OX + k * 30.0, ry), Vector2(OX + k * 30.0 + 16.0, ry), Color(Net.color_of(id), 0.6), 3.0)
			UI.text_left(c, Vector2(OX + 8.0, ry - 14.0), Net.name_of(id), 14, Net.color_of(id), 4)
	# plateformes
	for i in range(first_at(cam_a - 90.0), plats.size()):
		var p: Dictionary = plats[i]
		var sy := _sy(float(p["a"]))
		if sy > 800.0:
			continue
		if sy < -60.0:
			break
		if str(p["k"]) == "g":
			continue
		_plat(c, i, p, sy)
	# monstres
	for i in mons.size():
		var m: Dictionary = mons[i]
		var mp := mon_pos(m)
		var sy2 := _sy(mp.y)
		if sy2 < -80.0 or sy2 > 900.0:
			continue
		_monster(c, i, m, Vector2(OX + mp.x, sy2))
	# les autres en transparence, puis moi
	for id in ids:
		if id != me_id and ghosts.has(id):
			_body(c, id, 0.5)
	if playing and ghosts.has(me_id):
		_body(c, me_id, 1.0)
	# côtés : ciel (cache aussi ce qui dépasse de la colonne)
	_sides(c)


func _plat(c: CanvasItem, i: int, p: Dictionary, sy: float) -> void:
	var px := OX + plat_x(p)
	var w: float = p["w"]
	var k := str(p["k"])
	if gone.has(i):
		var q := (race_t - float(gone[i])) / 0.35
		if q < 1.0:
			for s in 5:
				c.draw_circle(Vector2(px - w / 2.0 + s * w / 4.0, sy + 6.0), 14.0 * (1.0 + q), Color(1, 1, 1, 0.8 * (1.0 - q)))
		return
	if broken.has(i):
		var q2 := race_t - float(broken[i])
		if q2 > 1.2:
			return
		for sd in [-1.0, 1.0]:
			var hp := Vector2(px + sd * (w / 4.0 + q2 * 30.0), sy + q2 * q2 * 900.0)
			c.draw_set_transform(hp, sd * q2 * 2.0, Vector2.ONE)
			_slab(c, Rect2(Vector2(-w / 4.0, 0), Vector2(w / 2.0, 22)), Color("#b98552"))
			c.draw_set_transform(Vector2.ZERO)
		return
	var col := Color("#7ed957")
	match k:
		"m":
			col = Color("#62b4f5")
		"b":
			col = Color("#b98552")
		"v":
			col = Color("#ffffff")
	var r := Rect2(Vector2(px - w / 2.0, sy), Vector2(w, 22))
	_slab(c, r, col)
	if k == "b":
		c.draw_polyline(PackedVector2Array([Vector2(px - 6, sy + 3), Vector2(px + 4, sy + 10), Vector2(px - 3, sy + 19)]), Color("#6b4526"), 3.0)
		c.draw_line(Vector2(px - 30, sy + 12), Vector2(px - 18, sy + 9), Color("#6b4526"), 2.0)
		c.draw_line(Vector2(px + 22, sy + 8), Vector2(px + 34, sy + 13), Color("#6b4526"), 2.0)
	elif k == "m":
		for sd in [-1.0, 1.0]:
			var ax: float = px + sd * (w / 2.0 - 12.0)
			c.draw_colored_polygon(PackedVector2Array([Vector2(ax + sd * 6.0, sy + 11), Vector2(ax - sd * 3.0, sy + 6), Vector2(ax - sd * 3.0, sy + 16)]), Color(1, 1, 1, 0.85))
	match str(p["it"]):
		"spring":
			_spring(c, Vector2(px + float(p["io"]), sy + 2.0), spring_t.has(i))
		"heli":
			if not (playing and taken.has(i)):
				_heli(c, Vector2(px + float(p["io"]), sy - 18.0 + sin(t * 4.0 + i) * 3.0), 1.0, Color("#ff7b2e"))


## Ressort façon Doodle Jump : un ressort tassé, qui reste détendu une fois utilisé.
func _spring(c: CanvasItem, base: Vector2, used: bool) -> void:
	var hh := 34.0 if used else 16.0
	var pts := PackedVector2Array()
	for k in 7:
		pts.append(base + Vector2(-11.0 if k % 2 == 0 else 11.0, -k * hh / 6.0))
	c.draw_polyline(pts, UI.INK, 8.0, true)
	c.draw_polyline(pts, Color("#c9cfe0"), 4.0, true)
	var top := Rect2(base + Vector2(-19, -hh - 9.0), Vector2(38, 10))
	c.draw_style_box(UI.box(UI.INK, Color(0, 0, 0, 0), 0, 5), top.grow(3))
	c.draw_style_box(UI.box(Color("#ff6b4a"), Color(0, 0, 0, 0), 0, 4), top)
	c.draw_rect(Rect2(top.position + Vector2(4, 2), Vector2(top.size.x - 8, 3)), Color(1, 1, 1, 0.5))


## Plateforme façon kit : contour encre, bas plus foncé, reflet.
func _slab(c: CanvasItem, r: Rect2, col: Color) -> void:
	c.draw_style_box(UI.box(UI.INK, Color(0, 0, 0, 0), 0, 11), r.grow(3))
	c.draw_style_box(UI.box(col.darkened(0.22), Color(0, 0, 0, 0), 0, 9), r)
	c.draw_style_box(UI.box(col, Color(0, 0, 0, 0), 0, 9), Rect2(r.position, Vector2(r.size.x, r.size.y - 6.0)))
	c.draw_style_box(UI.box(Color(1, 1, 1, 0.45), Color(0, 0, 0, 0), 0, 3), Rect2(r.position + Vector2(8, 3), Vector2(r.size.x - 16, 4)))


## Casquette à hélice (bonus posé sur une plateforme, ou sur la tête quand on vole).
func _heli(c: CanvasItem, p: Vector2, s: float, col: Color, rot := 0.0, al := 1.0) -> void:
	c.draw_set_transform(p, rot, Vector2(s, s))
	if al < 1.0:
		col = Color(col, al)
	var cap := PackedVector2Array()
	for k in 13:
		var a := PI + k * PI / 12.0
		cap.append(Vector2(cos(a) * 24.0, sin(a) * 18.0 + 6.0))
	c.draw_colored_polygon(cap, UI.INK)
	var cap2 := PackedVector2Array()
	for k in 13:
		var a := PI + k * PI / 12.0
		cap2.append(Vector2(cos(a) * 20.0, sin(a) * 14.0 + 4.0))
	c.draw_colored_polygon(cap2, col)
	c.draw_rect(Rect2(-26, 3, 52, 6), UI.INK)
	c.draw_rect(Rect2(-24, 4, 48, 4), Color("#ffd23f"))
	c.draw_line(Vector2(0, -12), Vector2(0, -22), UI.INK, 4.0)
	var bl := absf(cos(t * 22.0)) * 26.0 + 4.0
	c.draw_line(Vector2(-bl, -23), Vector2(bl, -23), UI.INK, 7.0)
	c.draw_line(Vector2(-bl + 2.0, -23), Vector2(bl - 2.0, -23), Color("#62b4f5"), 3.0)
	c.draw_circle(Vector2(0, -23), 4.0, UI.INK)
	c.draw_set_transform(Vector2.ZERO)


func _monster(c: CanvasItem, i: int, m: Dictionary, p: Vector2) -> void:
	var k := str(m["k"])
	var dead := dead_mon.has(i)
	var rot := 0.0
	if dead:
		var q := race_t - float(dead_mon[i])
		if q > 1.2:
			return
		p.y += q * q * 900.0
		rot = q * 6.0
	var tn := "bee_a"
	match k:
		"bee":
			tn = "bee_a" if int(t * 10.0) % 2 == 0 else "bee_b"
		"fly":
			tn = "fly_a"
		"slime":
			tn = "slime_spike_walk_a" if int(t * 5.0) % 2 == 0 else "slime_spike_walk_b"
	var tx: Texture2D = _tex[tn]
	var dirx := cos(float(m["sp"]) * race_t + float(m["ph"]))
	var flip := -1.0 if dirx > 0.0 else 1.0
	if not dead:
		c.draw_set_transform(p + Vector2(0, 40), 0.0, Vector2(1.0, 0.3))
		c.draw_circle(Vector2.ZERO, 30.0, Color(0, 0, 0, 0.08))
		c.draw_set_transform(Vector2.ZERO)
	c.draw_set_transform(p, rot, Vector2(flip, 1.0) * (100.0 / 128.0))
	c.draw_texture(tx, -tx.get_size() / 2.0, Color(1, 1, 1, 0.5) if dead else Color.WHITE)
	c.draw_set_transform(Vector2.ZERO)
	# toujours dessiné en double près des bords (l'écran boucle)
	if p.x - OX < 60.0 or OX + W - p.x < 60.0:
		var p2 := p + Vector2(W if p.x - OX < 60.0 else -W, 0)
		c.draw_set_transform(p2, rot, Vector2(flip, 1.0) * (100.0 / 128.0))
		c.draw_texture(tx, -tx.get_size() / 2.0)
		c.draw_set_transform(Vector2.ZERO)


func _body(c: CanvasItem, id: int, al: float) -> void:
	var g: Dictionary = ghosts[id]
	var st := int(g["st"])
	if (st & 1) != 0 and id != me_id:
		return
	var gx := OX + float(g["x"])
	var gy := _sy(float(g["a"]))
	if gy < -120.0 or gy > 840.0:
		return
	for dup in [0.0, -W, W]:
		var px: float = gx + dup
		if px < OX - 70.0 or px > OX + W + 70.0:
			continue
		_body_at(c, id, Vector2(px, gy), st, al)
	var mine := id == me_id
	if not mine:
		UI.text(c, Vector2(gx, gy - (124.0 if (st & 2) != 0 else 108.0)), Net.name_of(id), 16, Color(Net.color_of(id), 0.8), 5)
	elif state == "count" or (state == "play" and race_t < 3.0):
		UI.text(c, Vector2(gx, gy - (128.0 if (st & 2) != 0 else 112.0)), "TOI", 22, UI.YELLOW, 7)


func _body_at(c: CanvasItem, id: int, p: Vector2, st: int, al: float) -> void:
	var g: Dictionary = ghosts[id]
	var rising := float(g["vy"]) > 120.0
	var pose := "jump" if rising or (st & 2) != 0 else "idle"
	if (st & 16) != 0:
		pose = "hit"
	var face := -1.0 if (st & 4) != 0 else 1.0
	var rot := 0.0
	if (st & 32) != 0 and id == me_id:
		rot = spin * TAU * face
	var sq := Vector2(1.14, 0.84) if (st & 8) != 0 else Vector2.ONE
	if (st & 16) != 0:
		rot = sin(t * 30.0) * 0.4
	var sc := 0.36
	c.draw_set_transform(p + Vector2(0, -46.0 * sc / 0.36), rot, Vector2(sc * face * sq.x, sc * sq.y))
	c.draw_texture(_tex["%d_%s" % [id, pose]], Vector2(-128, -128) + Vector2(0, 0), Color(1, 1, 1, al))
	c.draw_set_transform(Vector2.ZERO)
	if (st & 2) != 0:
		_heli(c, p + Vector2(0, -46.0) + Vector2(0, -30).rotated(rot), 0.9, Net.color_of(id), rot, al)


func _sides(c: CanvasItem) -> void:
	var top := _sky(cam_a + 720.0)
	var bot := _sky(cam_a)
	for side in [Rect2(-20, -20, OX + 20, 760), Rect2(OX + W, -20, 1280 - OX - W + 20, 760)]:
		var r: Rect2 = side
		c.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			PackedColorArray([top, top, bot, bot]))
	# étoiles quand il fait nuit
	var night := clampf((cam_a - 18000.0) / 6000.0, 0.0, 1.0)
	if night > 0.0:
		for k in 40:
			var hv := _h(k * 7 + 3)
			var sx := float(hv % 1280)
			if sx > OX - 6.0 and sx < OX + W + 6.0:
				continue
			var sy := fposmod(float((hv >> 8) % 1400) + cam_a * 0.05, 760.0) - 20.0
			c.draw_circle(Vector2(sx, sy), 1.5 + float((hv >> 4) % 3), Color(1, 1, 1, night * (0.6 + 0.4 * sin(t * 3.0 + k))))
	# nuages en parallaxe
	for j in 10:
		var hv2 := _h(500 + j)
		var left := j % 2 == 0
		var cx := float(hv2 % 200) + 40.0 if left else 1280.0 - float(hv2 % 200) - 40.0
		var cy := fposmod(float((hv2 >> 6) % 900) + cam_a * 0.35, 900.0) - 90.0
		var tx: Texture2D = _tex[["cloud1", "cloud2", "cloud3", "cloud5", "cloud7"][hv2 % 5]]
		var s := 0.42 + float((hv2 >> 3) % 4) * 0.08
		c.draw_set_transform(Vector2(cx, cy), 0.0, Vector2(s, s))
		c.draw_texture(tx, -tx.get_size() / 2.0, Color(1, 1, 1, 0.85 - night * 0.5))
		c.draw_set_transform(Vector2.ZERO)
	# bords de la colonne
	for ex in [OX, OX + W]:
		c.draw_rect(Rect2(ex - 3.0, -10, 6, 740), UI.INK)
	c.draw_rect(Rect2(OX + W + 3.0, -10, 10, 740), Color(0, 0, 0, 0.12))


# ------------------------------------------------------------------ HUD
func _draw_hud() -> void:
	var h := hud
	var St := preload("res://minigames/stage.gd")
	if state == "intro":
		St.draw_intro(h, "Toujours plus haut !", [
			"On rebondit tout seul de plateforme en plateforme !",
			"Sors d'un côté de l'écran : tu reviens de l'autre.",
			"Ressort = super saut · Hélice = tu t'envoles !",
			"Les marron cassent, les blanches disparaissent après un saut.",
			"Écrase les monstres en sautant dessus, sinon tu tombes !",
			"Tombe en bas de l'écran et c'est fini. Après 1 minute, le plus haut gagne."],
			"Aller à gauche / droite : Q D / ← →")
		St.draw_ready_row(h, my_ready, ready_ids, ids, t, not playing)
		if str(Net.mg_data.get("mode", "")) == "duel":
			St.draw_duel_banner(h)
		return
	# gauche : chrono et ma hauteur
	var left := maxf(0.0, MAX_T - race_t)
	var tr := Rect2(Vector2(40, 24), Vector2(200, 64))
	UI.panel(h, tr, UI.WHITE, UI.WHITE, 18, 4)
	UI.text(h, UI.face_center(tr), "%d:%02d" % [int(ceilf(left)) / 60, int(ceilf(left)) % 60], 34, UI.RED if left <= 10.0 else UI.DARK, 0)
	var me_shown := me_id if playing else spec_id
	if me_shown != 0:
		var hr := Rect2(Vector2(40, 108), Vector2(200, 112))
		UI.panel(h, hr, Color("#7ed957"), UI.WHITE, 22, 5)
		var fc := UI.face_center(hr)
		UI.text(h, Vector2(fc.x, fc.y - 26), "Hauteur" if me_shown == me_id else Net.name_of(me_shown), 20, UI.WHITE, 5)
		var hv := best
		if me_shown != me_id and ghosts.has(me_shown):
			hv = float(ghosts[me_shown]["a"])
		elif not fell:
			hv = alt
		UI.text(h, Vector2(fc.x, fc.y + 16), "%d m" % int(maxf(0.0, hv) / PX_PER_M), 40, UI.WHITE, 8)
	# droite : classement
	var order := ranking()
	var n := order.size()
	var rh := minf(58.0, 560.0 / maxf(1.0, float(n)))
	var x0 := OX + W + 24.0
	var rw := 1280.0 - x0 - 20.0
	UI.text(h, Vector2(x0 + rw / 2.0, 46), "Classement", 24, UI.WHITE, 7)
	for i in n:
		var id: int = order[i]
		var r := Rect2(Vector2(x0, 82.0 + i * (rh + 6.0)), Vector2(rw, rh))
		var out := outs.has(id)
		var col := Net.color_of(id)
		UI.panel(h, r, (col.lightened(0.1) if not out else Color("#9aa0b4")), UI.WHITE, 16, 4)
		var fy := UI.face_center(r).y
		UI.text(h, Vector2(r.position.x + 18, fy), str(i + 1), 20, UI.WHITE, 5)
		UI.portrait(h, Vector2(r.position.x + 52, fy), minf(17.0, rh * 0.3), Net.color_idx(id), UI.WHITE, Color(0.7, 0.7, 0.75) if out else Color.WHITE)
		UI.text_left(h, Vector2(r.position.x + 76, fy - 9), Net.name_of(id), 16, UI.WHITE, 4)
		var hm := "%d m" % int(float(bests.get(id, 0.0)) / PX_PER_M)
		UI.text_left(h, Vector2(r.position.x + 76, fy + 11), hm + ("  · tombé" if out else ""), 14, Color(1, 1, 1, 0.9), 4)
		if id == me_id:
			h.draw_style_box(UI.box(Color(0, 0, 0, 0), UI.YELLOW, 3, 16), r.grow(3))
	# messages
	for j in pops.size():
		var p: Dictionary = pops[j]
		var k := float(p["t"]) / 2.0
		UI.text(h, Vector2(640, 190 - k * 40.0 + j * 4.0), str(p["txt"]), 30, Color(p["c"], 1.0 - k * k), 8)
	if state == "count":
		UI.text(h, Vector2(640, 330), str(3 - int(t)), int(110 * (1.0 + (1.0 - fmod(t, 1.0)) * 0.3)), UI.WHITE, 16)
	elif state == "play" and t < 1.0:
		UI.text(h, Vector2(640, 330), "SAUTE !", int(100 * (1.0 + t * 0.3)), Color(UI.GREEN, 1.0 - t), 18)
	if state == "play" and playing and not fell and race_t < 8.0:
		var help := "← → pour te diriger"
		var hw := UI.text_width(help, 22) + 44.0
		h.draw_style_box(UI.box(Color(UI.DARK, 0.82), UI.DARK, 0, 16), Rect2(Vector2(640 - hw / 2.0, 664), Vector2(hw, 40)))
		UI.text(h, Vector2(640, 684), help, 22, UI.YELLOW, 0)
	if playing and fell and state == "play":
		UI.text(h, Vector2(640, 300), "TOMBÉ !", 72, UI.RED, 14)
		UI.text(h, Vector2(640, 362), "Tu es monté à %d m" % int(best / PX_PER_M), 28, UI.WHITE, 8)
	if state == "play" and spec_id != 0 and ghosts.has(spec_id) and (fell or not playing):
		var sm := "Tu regardes %s   (← → pour changer)" % Net.name_of(spec_id)
		var sw := UI.text_width(sm, 20) + 40.0
		h.draw_style_box(UI.box(Color(UI.DARK, 0.8), UI.DARK, 0, 14), Rect2(Vector2(640 - sw / 2.0, 664), Vector2(sw, 40)))
		UI.text(h, Vector2(640, 684), sm, 20, UI.WHITE, 0)
	if state == "over":
		h.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, minf(0.4, t)))
		UI.text(h, Vector2(640, 360), "TERMINÉ !", 96, UI.YELLOW, 16)
