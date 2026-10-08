extends Node2D
## Le plateau façon Mario Party : une île, une boucle de cases bleues et rouges, une étoile.
## On frappe le dé, on avance case par case, la caméra suit le joueur.

const Backdrop := preload("res://screens/backdrop.gd")
const Art := preload("res://board/art.gd")
const THEME := "sky"
const GRASS := Color("#2ecc71")
const GRASS_HI := Color("#46e087")
const GRASS_DARK := Color("#20b860")
const DIRT := Color("#ee9366")
const DIRT_DARK := Color("#de7e4f")
const ROAD := Color("#f6dfa4")
const BLUE := Color("#4b87f5")
const RED := Color("#f04650")
const START := Color("#5fcd55")
const TOKEN_SCALE := 0.36

var world: Node2D
var island: Node2D
var deco: Node2D
var board_fx: Node2D
var cam: Camera2D
var hud: Control
var t := 0.0

var disp: Dictionary = {}        # joueurs affichés (pièces/étoiles mises à jour au bon moment)
var space_of: Dictionary = {}    # case affichée de chaque pion
var vis: Dictionary = {}         # position visuelle
var hop: Dictionary = {}         # saut en cours [début, durée, hauteur]
var tex_idle: Dictionary = {}
var tex_jump: Dictionary = {}
var star: int = 0
var star_vis := Vector2.ZERO
var star_fly := 0.0
var turn_id := 0
var my_turn := false
var dice_state := "none"   # none, rolling, hit, moving
var dice_val := 1
var dice_tick := 0.0
var dice_bounce := 0.0
var steps_left := 0
var banner := ""
var banner_t := 0.0
var banner_col := UI.YELLOW
var popups: Array = []
var cam_target := Vector2.ZERO
var cam_zoom_target := 0.9
var overview := 0.0
var shown_coins: Dictionary = {}
var tex_star: Texture2D = load("res://assets/tiles/star.png")
var tex_coin: Texture2D = load("res://assets/tiles/coin_gold.png")
var tex_block: Texture2D = load("res://assets/tiles/block_exclamation.png")
var tex_block_hit: Texture2D = load("res://assets/tiles/block_exclamation_active.png")
var island_poly: PackedVector2Array
var _debug_shot := false
var turn_t := 0.0


func _ready() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	bg_layer.add_child(Backdrop.new("sky"))
	world = Node2D.new()
	add_child(world)
	var th := OS.get_environment("BOARD_THEME") if OS.get_environment("BOARD_THEME") != "" else THEME
	world.add_child(Art.new(th))
	board_fx = Node2D.new()
	board_fx.z_index = 10
	world.add_child(board_fx)
	board_fx.draw.connect(_draw_tokens)
	cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 4.0
	world.add_child(cam)
	cam.make_current()

	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 5
	add_child(ui_layer)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	ui_layer.add_child(hud)

	disp = Net.players.duplicate(true)
	star = Net.star_pos
	star_vis = BoardLayout.pos_at(star)
	for id in disp:
		space_of[id] = int(disp[id]["pos"])
		tex_idle[id] = UI.char_tex(int(disp[id]["color"]), "idle")
		tex_jump[id] = UI.char_tex(int(disp[id]["color"]), "jump")
		shown_coins[id] = float(disp[id]["coins"])
	for id in disp:
		vis[id] = _token_target(id)

	# vue d'ensemble au début de chaque tour de table
	overview = 2.4
	cam_zoom_target = 0.42
	cam.zoom = Vector2(0.42, 0.42)
	cam.position = BoardLayout.MAP_SIZE / 2.0
	cam.reset_smoothing()
	cam_target = BoardLayout.MAP_SIZE / 2.0
	_show_banner("Tour %d / %d" % [Net.round_num, Net.total_rounds], UI.YELLOW)
	if Net.round_num == Net.total_rounds:
		_show_banner("Dernier tour !", UI.RED)

	Net.turn_started.connect(_on_turn_started)
	Net.turn_result.connect(_on_turn_result)
	Net.announce.connect(func(txt): _show_banner(txt, UI.YELLOW))
	Net.players_changed.connect(_on_players_changed)


# ------------------------------------------------------------------ pions
func _token_target(id: int) -> Vector2:
	var s: int = space_of.get(id, 0)
	var same := []
	for o in space_of:
		if space_of[o] == s:
			same.append(o)
	same.sort()
	if id == turn_id and dice_state != "none":
		return BoardLayout.pos_at(s)
	var k := same.find(id)
	var off := Vector2.ZERO
	if same.size() > 1:
		var a := TAU * k / same.size() - PI / 2.0
		off = Vector2(cos(a) * 30.0, sin(a) * 14.0)
	return BoardLayout.pos_at(s) + off


func _hop(id: int, dur: float, h: float) -> void:
	hop[id] = [t, dur, h]


func _hop_offset(id: int) -> float:
	if not hop.has(id):
		return 0.0
	var a: Array = hop[id]
	var k := (t - float(a[0])) / float(a[1])
	if k >= 1.0:
		hop.erase(id)
		return 0.0
	return -sin(k * PI) * float(a[2])


func _draw_tokens() -> void:
	# étoile
	var sp := star_vis
	var pulse := sin(t * 4.0)
	var spc := BoardLayout.pos_at(star)
	for k in 4:
		board_fx.draw_circle(spc, 70.0 - k * 12.0 + pulse * 4.0, Color(1.0, 0.85, 0.2, 0.08 + k * 0.03))
	board_fx.draw_arc(spc, 50.0 + pulse * 3.0, 0, TAU, 48, Color(UI.DARK, 0.9), 11.0, true)
	board_fx.draw_arc(spc, 50.0 + pulse * 3.0, 0, TAU, 48, UI.YELLOW, 6.0, true)
	board_fx.draw_set_transform(sp + Vector2(0, -92 + sin(t * 2.5) * 8.0), sin(t * 1.5) * 0.15, Vector2(0.95, 0.95))
	board_fx.draw_texture(tex_star, Vector2(-64, -64))
	board_fx.draw_set_transform(Vector2.ZERO)
	for i in 3:
		var a := t * 2.0 + i * TAU / 3.0
		board_fx.draw_circle(sp + Vector2(cos(a) * 62.0, -92 + sin(a) * 26.0), 5.0, Color(1, 1, 0.7, 0.9))
	# pions triés par profondeur, le joueur actif devant
	var ids := vis.keys()
	ids.sort_custom(func(a, b): return vis[a].y < vis[b].y)
	if ids.has(turn_id):
		ids.erase(turn_id)
		ids.append(turn_id)
	for id in ids:
		var p: Vector2 = vis[id]
		var ho := _hop_offset(id)
		var squash := 1.0 + (0.08 * sin(t * 3.0 + float(id % 7)) if ho == 0.0 else 0.0)
		board_fx.draw_circle(p + Vector2(0, 2), 22.0 * (1.0 + ho / 200.0), Color(UI.DARK, 0.25))
		var tx: Texture2D = tex_jump[id] if ho < -2.0 else tex_idle[id]
		board_fx.draw_set_transform(p + Vector2(0, ho), 0.0, Vector2(TOKEN_SCALE * (2.0 - squash), TOKEN_SCALE * squash))
		board_fx.draw_texture(tx, Vector2(-128, -256))
		board_fx.draw_set_transform(Vector2.ZERO)
		if id == turn_id:
			UI.text(board_fx, p + Vector2(0, ho - 112), Net.name_of(id), 22, Net.color_of(id), 7)
	# bloc-dé au-dessus du joueur actif
	if dice_state in ["rolling", "hit"] and vis.has(turn_id):
		var bp: Vector2 = vis[turn_id] + Vector2(0, -185 - dice_bounce * 18.0)
		var tb := tex_block_hit if dice_state == "hit" else tex_block
		board_fx.draw_set_transform(bp, 0.0, Vector2(0.62, 0.62))
		board_fx.draw_texture(tb, Vector2(-64, -64))
		board_fx.draw_set_transform(Vector2.ZERO)
		UI.text(board_fx, bp, str(dice_val), 46, UI.WHITE, 10)
	elif dice_state == "moving" and vis.has(turn_id) and steps_left > 0:
		var np: Vector2 = vis[turn_id] + Vector2(0, -150 + _hop_offset(turn_id))
		board_fx.draw_circle(np, 30.0, UI.DARK)
		board_fx.draw_circle(np, 25.0, UI.WHITE)
		UI.text(board_fx, np, str(steps_left), 34, UI.BLUE, 0)
	# petits gains de pièces
	for pp in popups:
		var k: float = (t - float(pp["t"])) / 1.2
		if k < 1.0:
			var pos: Vector2 = pp["p"] + Vector2(0, -150 - k * 70.0)
			UI.text(board_fx, pos, pp["txt"], 34, Color(pp["c"], 1.0 - k * k), 9)


# ------------------------------------------------------------------ tours
func _on_players_changed() -> void:
	for id in vis.keys():
		if not Net.players.has(id):
			vis.erase(id)
			space_of.erase(id)
			disp.erase(id)


func _on_turn_started(id: int) -> void:
	turn_id = id
	turn_t = 0.0
	my_turn = id == Net.my_id()
	dice_state = "rolling"
	dice_tick = 0.0
	overview = 0.0
	if my_turn:
		_show_banner("À toi de jouer ! Appuie sur Espace", Net.color_of(id), 99.0)
		Sfx.play("select", -2.0)
	else:
		_show_banner("Au tour de %s" % Net.name_of(id), Net.color_of(id), 2.0)


func _try_roll() -> void:
	if my_turn and dice_state == "rolling":
		my_turn = false
		banner = ""
		_hop(turn_id, 0.3, 60.0)
		Net.roll_dice()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _on_turn_result(d: Dictionary) -> void:
	var id: int = d["id"]
	turn_id = id
	my_turn = false
	if banner.begins_with("À toi"):
		banner = ""
	# frappe du bloc
	if not hop.has(id):
		_hop(id, 0.3, 60.0)
	await _wait(0.15)
	dice_state = "hit"
	dice_val = int(d["roll"])
	dice_bounce = 1.0
	Sfx.play("bump", -2.0)
	await _wait(0.9)
	dice_state = "moving"
	steps_left = dice_val
	var events: Array = d["events"]
	var step_i := 0
	for s in d["path"]:
		step_i += 1
		if not is_inside_tree():
			return
		space_of[id] = int(s)
		steps_left -= 1
		_hop(id, 0.26, 26.0)
		Sfx.play("jump", -16.0, 0.12)
		await _wait(0.28)
		for e in events:
			if int(e["step"]) == step_i - 1:
				await _star_event(id, e)
	# arrivée
	var delta: int = d["delta"]
	var land: Vector2 = BoardLayout.pos_at(int(d["path"][-1])) if d["path"].size() > 0 else vis[id]
	if delta >= 0:
		popups.append({"p": land, "txt": "+%d" % delta, "c": UI.YELLOW, "t": t})
		Sfx.play("coin", -2.0)
	else:
		popups.append({"p": land, "txt": "%d" % delta, "c": UI.RED, "t": t})
		Sfx.play("hurt", -4.0)
	if disp.has(id):
		disp[id]["coins"] = int(disp[id]["coins"]) + delta
	await _wait(1.0)
	if turn_id == id:
		dice_state = "none"
	var snap: Dictionary = d["players"]
	for pid in snap:
		if disp.has(pid):
			disp[pid]["coins"] = int(snap[pid]["coins"])
			disp[pid]["stars"] = int(snap[pid]["stars"])
			space_of[pid] = int(snap[pid]["pos"])
	star = int(d["star"])


func _star_event(id: int, e: Dictionary) -> void:
	if str(e["kind"]) == "buy":
		_show_banner("%s achète une ÉTOILE !" % Net.name_of(id), UI.YELLOW, 2.2)
		Sfx.play("gem", 0.0)
		if disp.has(id):
			disp[id]["coins"] = int(disp[id]["coins"]) - Net.STAR_COST
			disp[id]["stars"] = int(disp[id]["stars"]) + 1
		popups.append({"p": vis[id], "txt": "+1 étoile", "c": UI.YELLOW, "t": t})
		_hop(id, 0.5, 90.0)
		await _wait(1.0)
		star = int(e["star"])
		star_fly = 1.0
		await _wait(1.2)
	else:
		_show_banner("Il faut %d pièces pour l'étoile..." % Net.STAR_COST, UI.GREY, 1.6)
		await _wait(1.6)


func _show_banner(txt: String, col: Color, dur := 2.4) -> void:
	banner = txt
	banner_col = col
	banner_t = dur


func _process(delta: float) -> void:
	t += delta
	turn_t += delta
	if my_turn and dice_state == "rolling" and (Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("push")):
		_try_roll()
	banner_t -= delta
	if banner_t <= 0.0:
		banner = ""
	dice_bounce = maxf(0.0, dice_bounce - delta * 5.0)
	if dice_state == "rolling":
		dice_tick += delta
		if dice_tick > 0.07:
			dice_tick = 0.0
			var nv := randi_range(1, Net.DICE_MAX)
			if nv == dice_val:
				nv = nv % Net.DICE_MAX + 1
			dice_val = nv
	# étoile qui s'envole vers sa nouvelle case
	var star_target := BoardLayout.pos_at(star)
	star_vis = star_vis.lerp(star_target, 1.0 - exp(-delta * (3.0 if star_fly > 0.0 else 20.0)))
	star_fly = maxf(0.0, star_fly - delta)
	for id in vis:
		vis[id] = (vis[id] as Vector2).lerp(_token_target(id), 1.0 - exp(-delta * 16.0))
	for id in disp:
		shown_coins[id] = move_toward(float(shown_coins.get(id, 0.0)), float(disp[id]["coins"]), delta * 25.0)
	popups = popups.filter(func(p): return t - float(p["t"]) < 1.2)
	# caméra
	if overview > 0.0:
		overview -= delta
		cam_target = BoardLayout.MAP_SIZE / 2.0 + Vector2(0, 60)
		cam_zoom_target = 0.42
	elif star_fly > 0.0:
		cam_target = star_vis
		cam_zoom_target = 0.8
	elif vis.has(turn_id) and turn_id != 0:
		cam_target = vis[turn_id] + Vector2(0, -60)
		cam_zoom_target = 0.95
	if OS.get_environment("BOARD_SHOT") != "" and t > 7.0 and not _debug_shot:
		_debug_shot = true
		_save_debug_shot()
	if OS.get_environment("BOARD_CAM") != "" and overview <= 0.0:
		var bc := OS.get_environment("BOARD_CAM").split(",")
		cam_target = Vector2(float(bc[0]), float(bc[1]))
		cam_zoom_target = float(bc[2])
	cam.position = cam_target
	var z := lerpf(cam.zoom.x, cam_zoom_target, 1.0 - exp(-delta * 3.0))
	cam.zoom = Vector2(z, z)
	board_fx.queue_redraw()
	hud.queue_redraw()


# ------------------------------------------------------------------ HUD
func _draw_hud() -> void:
	# tour
	var r := Rect2(Vector2(20, 16), Vector2(200, 56))
	hud.draw_style_box(UI.box(UI.WHITE, UI.DARK, 4, 16), r)
	UI.text(hud, r.get_center(), "Tour %d / %d" % [mini(Net.round_num, Net.total_rounds), Net.total_rounds], 28, UI.DARK, 0)
	var r2 := Rect2(Vector2(1280 - 250, 16), Vector2(230, 56))
	hud.draw_style_box(UI.box(UI.WHITE, UI.DARK, 4, 16), r2)
	hud.draw_set_transform(r2.position + Vector2(34, 28), 0.0, Vector2(0.38, 0.38))
	hud.draw_texture(tex_star, Vector2(-64, -64))
	hud.draw_set_transform(Vector2.ZERO)
	hud.draw_string(UI.font(true), r2.position + Vector2(60, 37), "= %d pièces" % Net.STAR_COST, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UI.DARK)

	# cartes des joueurs, classées
	var ids := disp.keys()
	ids.sort_custom(func(a, b):
		var ka := int(disp[a]["stars"]) * 100000 + int(disp[a]["coins"])
		var kb := int(disp[b]["stars"]) * 100000 + int(disp[b]["coins"])
		return ka > kb)
	var n := ids.size()
	var cw := 150.0
	var gap := 8.0
	var x0 := (1280.0 - (n * cw + (n - 1) * gap)) / 2.0
	var rank := 0
	for i in n:
		var id: int = ids[i]
		if i > 0:
			var ka := int(disp[id]["stars"]) * 100000 + int(disp[id]["coins"])
			var kp := int(disp[ids[i - 1]]["stars"]) * 100000 + int(disp[ids[i - 1]]["coins"])
			if ka != kp:
				rank = i
		var cr := Rect2(Vector2(x0 + i * (cw + gap), 720 - 82), Vector2(cw, 68))
		var active := id == turn_id and dice_state != "none"
		if active:
			cr.position.y -= 8.0
		var col := Net.color_of(id)
		hud.draw_style_box(UI.box(UI.WHITE, col.darkened(0.25) if active else UI.DARK, 5 if active else 4, 14), cr)
		var strip := UI.box(col, UI.DARK, 0, 10)
		strip.corner_radius_top_right = 0
		strip.corner_radius_bottom_right = 0
		hud.draw_style_box(strip, Rect2(cr.position + Vector2(4, 4), Vector2(46, cr.size.y - 8)))
		hud.draw_set_transform(cr.position + Vector2(27, 62), 0.0, Vector2(0.21, 0.21))
		hud.draw_texture(tex_idle.get(id, UI.char_tex(Net.color_idx(id))), Vector2(-128, -256))
		hud.draw_set_transform(Vector2.ZERO)
		var badge := Vector2(cr.position.x + 10, cr.position.y + 4)
		hud.draw_circle(badge, 13.0, UI.DARK)
		hud.draw_circle(badge, 10.0, UI.YELLOW if rank == 0 else UI.WHITE)
		hud.draw_string(UI.font(true), badge + Vector2(-5, 6), str(rank + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.DARK)
		var nm := str(disp[id]["name"])
		if nm.length() > 9:
			nm = nm.substr(0, 8) + "."
		hud.draw_string(UI.font(true), cr.position + Vector2(58, 25), nm, HORIZONTAL_ALIGNMENT_LEFT, 88, 17, UI.DARK)
		hud.draw_set_transform(cr.position + Vector2(68, 47), 0.0, Vector2(0.24, 0.24))
		hud.draw_texture(tex_star, Vector2(-64, -64))
		hud.draw_set_transform(Vector2.ZERO)
		hud.draw_string(UI.font(true), cr.position + Vector2(80, 55), str(int(disp[id]["stars"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UI.DARK)
		hud.draw_set_transform(cr.position + Vector2(108, 47), 0.0, Vector2(0.24, 0.24))
		hud.draw_texture(tex_coin, Vector2(-64, -64))
		hud.draw_set_transform(Vector2.ZERO)
		hud.draw_string(UI.font(true), cr.position + Vector2(120, 55), str(int(round(float(shown_coins.get(id, 0.0))))), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UI.DARK)
		if id == Net.my_id():
			hud.draw_rect(Rect2(cr.position + Vector2(12, -9), Vector2(cw - 24, 5)), col)

	# bandeau
	if banner != "":
		var s := 34
		var w := UI.text_width(banner, s) + 60.0
		var pulse := 1.0 + (sin(t * 6.0) * 0.03 if banner.begins_with("À toi") else 0.0)
		var br := Rect2(Vector2(640 - w * pulse / 2.0, 110), Vector2(w * pulse, 66))
		hud.draw_style_box(UI.box(UI.WHITE, UI.DARK, 5, 20), br)
		UI.text(hud, br.get_center(), banner, s, banner_col, 8)
	if dice_state == "rolling" and turn_t > 7.0:
		var left := maxi(0, ceili(Net.ROLL_TIMEOUT - turn_t))
		UI.text(hud, Vector2(640, 200), "Lancement automatique dans %d s" % left, 24, UI.WHITE, 7)


func _save_debug_shot() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("BOARD_SHOT"))
	get_tree().quit()
