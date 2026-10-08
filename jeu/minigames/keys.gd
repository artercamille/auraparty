extends "res://minigames/stage.gd"
## « La bonne clé ! » : course de 5 portes. Devant chaque porte, 3 clés : une seule l'ouvre
## (tirage différent pour chaque joueur). Pas de contact : les autres sont des fantômes.

const GROUND := 592.0
const ROOMS := 5
const ROOM_W := 640.0
const START_W := 320.0
const KEY_COLORS := ["red", "blue", "green", "yellow"]

var finish_x := 0.0
var world_w := 0.0
var rooms: Array = []        # {x, keys: [{pos, color, sprite, used}], door_x, door_body, door_spr, door_top, good, open}
var carry := -1              # index de clé portée dans la salle courante
var carry_room := -1
var doors_done := 0
var finished := false
var finish_time := 0.0
var finishes: Dictionary = {}   # id -> temps (diffusé par l'hôte)
var host_prog: Dictionary = {}  # hôte : id -> [portes, x]
var prog_acc := 0.0
var overlay: Node2D
var key_tex := {}
var msg := ""
var msg_t := 0.0


func _setup() -> void:
	title = "La bonne clé !"
	rules = "Ramasse une clé et fonce vers la porte !\nUne seule des 3 clés ouvre chaque porte... à toi de deviner.\nLe premier à franchir les 5 portes gagne. Les autres sont des fantômes."
	controls = "Bouger : Q D / ← →   ·   Sauter : Espace (x2)   ·   Ramasser une clé : passe dessus"
	duration = 60.0
	contact = false
	ghosts = true
	follow_cam = true
	respawn_on_fall = true
	show_heads = false
	finish_x = START_W + ROOMS * ROOM_W + 60.0
	world_w = finish_x + 360.0
	cam_limits = Rect2(0, 0, world_w, 720)
	for i in 8:
		spawn_points.append(Vector2(110 + i * 14, GROUND))
	respawn_points = [Vector2(110, GROUND)]
	for c in KEY_COLORS:
		key_tex[c] = load("res://assets/tiles/key_%s.png" % c)


func _build_level() -> void:
	var n := int(ceil(world_w / T))
	island(0, GROUND, n)
	tile("sign_right", Vector2(150, GROUND - T))
	# tirage commun : couleurs des clés et salle par salle
	# tirage perso : la bonne clé (différente pour chacun)
	var mine := RandomNumberGenerator.new()
	mine.seed = int(Net.mg_data.get("seed", 1)) ^ (Net.my_id() * 7919)
	for r in ROOMS:
		var x: float = START_W + r * ROOM_W
		var cols := KEY_COLORS.duplicate()
		for i in range(cols.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = cols[i]
			cols[i] = cols[j]
			cols[j] = tmp
		var raised := r % 3
		var keys := []
		for k in 3:
			var kx := x + 80.0 + k * 160.0
			var ky := GROUND - 46.0
			if k == raised:
				thin(int((kx - 64.0) / T), GROUND - 144.0, 2)
				ky = GROUND - 144.0 - 46.0
			var spr := Sprite2D.new()
			spr.texture = key_tex[cols[k]]
			spr.scale = Vector2(0.5, 0.5)
			spr.position = Vector2(kx, ky)
			spr.z_index = 3
			world.add_child(spr)
			keys.append({"pos": Vector2(kx, ky), "color": cols[k], "sprite": spr, "used": false})
		if r > 0:
			tile("block_planks", Vector2(x + 300.0, GROUND - T))
			solid(Rect2(x + 300.0 + 2.0, GROUND - T + 2.0, T - 4.0, T - 2.0))
		var dx := x + 560.0
		var top := tile("door_closed_top", Vector2(dx, GROUND - 2 * T))
		var bot := tile("door_closed", Vector2(dx, GROUND - T))
		var body := solid(Rect2(dx + 6.0, GROUND - 2 * T, T - 12.0, 2 * T))
		tile("sign", Vector2(dx - 4.0, GROUND - 3 * T - 6.0), null, 0.4)
		rooms.append({"x": x, "keys": keys, "door_x": dx, "door_body": body, "door_spr": bot, "door_top": top,
			"good": mine.randi_range(0, 2), "open": false})
	var flag := tile("flag_green_a", Vector2(finish_x + 20.0, GROUND - T))
	flag.set_meta("anim", true)
	overlay = Node2D.new()
	overlay.z_index = 9
	world.add_child(overlay)
	overlay.draw.connect(_draw_overlay)


func _on_start() -> void:
	if me:
		me.kill_rect = Rect2(-200, -2000, world_w + 400.0, 2860)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state != "play" or me == null or me.dead:
		return
	var room_i := mini(doors_done, ROOMS - 1)
	if doors_done < ROOMS:
		var room: Dictionary = rooms[room_i]
		# ramasser une clé
		if carry < 0:
			for k in 3:
				var key: Dictionary = room["keys"][k]
				if key["used"]:
					continue
				var kp: Vector2 = key["pos"]
				if absf(me.position.x - kp.x) < 34.0 and me.position.y > kp.y - 10.0 and me.position.y < kp.y + 90.0:
					carry = k
					carry_room = room_i
					key["used"] = true
					(key["sprite"] as Sprite2D).visible = false
					Sfx.play("coin", -4.0)
					fx.ring(kp, UI.YELLOW)
					break
		# essayer la porte
		var dx: float = room["door_x"]
		if carry >= 0 and me.position.x > dx - 40.0 and me.position.x < dx + 70.0:
			if carry == int(room["good"]):
				room["open"] = true
				(room["door_body"] as StaticBody2D).collision_layer = 0
				(room["door_spr"] as Sprite2D).texture = load("res://assets/tiles/door_open.png")
				(room["door_top"] as Sprite2D).texture = load("res://assets/tiles/door_open_top.png")
				doors_done += 1
				Sfx.play("gem", -2.0)
				fx.stars(Vector2(dx + 32.0, GROUND - 80.0), 8)
				_say("Bonne clé !", UI.GREEN)
				Net.mg_to_host({"prog": doors_done, "x": int(me.position.x)})
			else:
				Sfx.play("hurt", -2.0)
				fx.stars(me.position + Vector2(0, -90), 6)
				me.receive_hit(0, Vector2(-560.0, -340.0), 0)
				_say("Mauvaise clé !", UI.RED)
			carry = -1
	# ligne d'arrivée
	if not finished and doors_done >= ROOMS and me.position.x > finish_x:
		finished = true
		finish_time = play_t
		Sfx.play("gem", 0.0)
		fx.ring(me.position + Vector2(0, -30), me.color())
		fx.stars(me.position + Vector2(0, -60), 10)
		Net.mg_to_host({"finish": play_t})
		get_tree().create_timer(1.5).timeout.connect(func(): spectating = true)
	# progression envoyée régulièrement (pour départager à la fin du chrono)
	prog_acc += delta
	if prog_acc > 1.0:
		prog_acc = 0.0
		Net.mg_to_host({"prog": doors_done, "x": int(me.position.x)})
	_bot_goal()


func _bot_goal() -> void:
	if not me.is_bot:
		return
	if doors_done >= ROOMS:
		me.set_meta("goal_x", finish_x + 120.0)
		me.set_meta("goal_jump", false)
		return
	var room: Dictionary = rooms[doors_done]
	if carry >= 0:
		me.set_meta("goal_x", float(room["door_x"]) + 20.0)
		me.set_meta("goal_jump", false)
		return
	for k in 3:
		var key: Dictionary = room["keys"][k]
		if not key["used"]:
			var kp: Vector2 = key["pos"]
			me.set_meta("goal_x", kp.x)
			me.set_meta("goal_jump", kp.y < GROUND - 100.0 and absf(me.position.x - kp.x) < 60.0)
			return


func _say(text: String, col: Color) -> void:
	msg = text
	msg_t = 1.4
	fx.popup(me.position + Vector2(0, -110), text, col)


# ------------------------------------------------------------------ hôte
func _on_mg_msg(from_id: int, data: Dictionary) -> void:
	if data.has("prog"):
		host_prog[from_id] = [int(data["prog"]), int(data.get("x", 0))]
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
			var pr: Array = host_prog.get(id, [0, 0])
			out[id] = [float(pr[0]) * 1000.0 + float(pr[1]) * 0.1, "%d porte%s sur %d" % [pr[0], "s" if int(pr[0]) > 1 else "", ROOMS]]
	return out


# ------------------------------------------------------------------ rendu
func _process(delta: float) -> void:
	super._process(delta)
	msg_t = maxf(0.0, msg_t - delta)
	for r in rooms:
		for key in r["keys"]:
			var s: Sprite2D = key["sprite"]
			s.position.y = (key["pos"] as Vector2).y + sin(t * 3.0 + s.position.x * 0.01) * 5.0
	overlay.queue_redraw()


func _draw_overlay() -> void:
	# clé portée au-dessus de la tête
	if carry >= 0 and me and not me.dead and carry_room >= 0:
		var c: String = rooms[carry_room]["keys"][carry]["color"]
		overlay.draw_set_transform(me.position + Vector2(0, -112 + sin(t * 6.0) * 4.0), sin(t * 4.0) * 0.2, Vector2(0.45, 0.45))
		overlay.draw_texture(key_tex[c], Vector2(-64, -64))
		overlay.draw_set_transform(Vector2.ZERO)
	# "?" sur les portes fermées, ligne d'arrivée
	for r in rooms:
		if not r["open"]:
			UI.text(overlay, Vector2(float(r["door_x"]) + 28.0, GROUND - 3 * T + 18.0), "?", 30, UI.DARK, 0)
	for i in 12:
		var y := GROUND - 12.0 - i * 26.0
		overlay.draw_rect(Rect2(Vector2(finish_x, y), Vector2(13, 13)), UI.DARK if i % 2 == 0 else UI.WHITE)
		overlay.draw_rect(Rect2(Vector2(finish_x + 13, y), Vector2(13, 13)), UI.WHITE if i % 2 == 0 else UI.DARK)


func _draw_extra_hud() -> void:
	draw_timer()
	if state == "intro":
		return
	# barre de course
	var bar := Rect2(Vector2(200, 26), Vector2(880, 34))
	hud.draw_style_box(UI.box(UI.WHITE, UI.DARK, 4, 16), bar)
	for r in ROOMS:
		var dxp := bar.position.x + 20.0 + (float(rooms[r]["door_x"]) / finish_x) * (bar.size.x - 40.0)
		hud.draw_rect(Rect2(Vector2(dxp - 2, bar.position.y + 6), Vector2(4, 22)), Color(UI.DARK, 0.35))
	var ids := nodes.keys()
	ids.sort_custom(func(a, b): return nodes[a].position.x < nodes[b].position.x)
	if ids.has(Net.my_id()):
		ids.erase(Net.my_id())
		ids.append(Net.my_id())
	for id in ids:
		var n: Player = nodes[id]
		var prog := clampf(n.position.x / finish_x, 0.0, 1.0)
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
	# mes portes
	var pr := Rect2(Vector2(1280 - 190, 18), Vector2(166, 52))
	hud.draw_style_box(UI.box(UI.WHITE, UI.DARK, 4, 14), pr)
	UI.text(hud, pr.get_center(), "Portes %d / %d" % [doors_done, ROOMS], 24, UI.DARK, 0)
	# arrivées
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
