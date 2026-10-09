extends Node2D
## Le plateau façon Mario Party : la grande île, les pions, le dé et les menus
## (objets, choix de route, boutique, duel). Les règles sont chez l'hôte (game.gd) :
## ici on met en scène ses événements et on envoie nos réponses.

const Backdrop := preload("res://screens/backdrop.gd")
const Island := preload("res://board/island.gd")
const TOKEN_SCALE := 0.42
const MAP_ZOOM := 0.152
const MAP_OFS := Vector2(-1000, 230)   # l'île à droite de la légende
const LEGEND := [["B", "+3 pièces"], ["R", "-3 pièces"], ["E", "Événement de la zone"], ["C", "Carte chance"],
	["I", "Objet gratuit"], ["D", "Duel 1 contre 1"], ["T", "Piège : -10 pièces"], ["K", "Banque"],
	["H", "Boutique"], ["P", "Tuyau : téléportation"], ["W", "Roi Grognon : malus !"], ["G", "Fantôme : vole pièces/étoile"]]

var world: Node2D
var island: Node2D
var board_fx: Node2D
var cam: Camera2D
var hud: Control
var t := 0.0

var disp: Dictionary = {}        # joueurs affichés
var space_of: Dictionary = {}    # case affichée de chaque pion
var vis: Dictionary = {}         # position visuelle
var hop: Dictionary = {}         # saut en cours [début, durée, hauteur]
var warp: Dictionary = {}        # téléportation en cours [début, position de départ]
var shown_coins: Dictionary = {}
var tex_idle: Dictionary = {}
var tex_jump: Dictionary = {}
var star := 0
var star_vis := Vector2.ZERO
var star_fly := 0.0
var turn_id := 0
var phase := "idle"              # idle, action, dice, moving
var spin_n := 1                  # nombre de dés qui tournent (double/triple dé)
var spin_fixed := 0
var spin_bonus := 0
var dice_vals: Array = []
var dice_t0 := 0.0
var dice_bonus := 0
var dice_total := 0
var steps_left := 0
var ask: Dictionary = {}
var ask_t0 := 0.0
var menu := ""                   # "", action, items, target, custom, branch, shop, duel
var sel := 0
var menu_item := ""
var custom_val := 6
var buttons: Array = []
var hover_btn := -1
var banner := ""
var banner_t := 0.0
var banner_col := UI.YELLOW
var popups: Array = []
var panel: Dictionary = {}
var map_view := false
var overview := 0.0
var cam_target := Vector2.ZERO
var cam_zoom_target := 0.9
var tex_star: Texture2D = load("res://assets/tiles/star.png")
var tex_coin: Texture2D = load("res://assets/tiles/coin_gold.png")
var tex_vendor: Texture2D = load("res://assets/chars/vendeur/idle.png")
var tex_ghost: Texture2D = load("res://assets/enemies/ghost_npc.png")
var tex_rock: Texture2D = load("res://assets/enemies/rock_toll.png")
var tex_fire: Texture2D = load("res://assets/icons/fire.png")
var boo_step := 0
var boo_do := ""
var shop_step := 0
var hidden_fx := {}      # 0 : « Veux-tu acheter ? »  1 : l'étagère
var tex_block: Texture2D = load("res://assets/tiles/block_exclamation.png")
var tex_block_hit: Texture2D = load("res://assets/tiles/block_exclamation_active.png")
var _debug_shot := false
var star_cele := {}               # grande animation « étoile gagnée » : id, t0, txt
var cele_conf: Array = []
const CELE_LEN := 3.7
var dice_hits := 0
var sparks: Array = []            # particules (pack Kenney Particle)
var _ptex := {}
var emotes: Dictionary = {}       # id -> [nom, début]
var _emote_cd := 0.0
const EMOTE_KEYS := {KEY_1: "faceHappy", KEY_2: "laugh", KEY_3: "faceAngry", KEY_4: "faceSad", KEY_5: "heart", KEY_6: "idea"}


func _ready() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	bg_layer.add_child(Backdrop.new("sky"))
	world = Node2D.new()
	add_child(world)
	island = Island.new()
	world.add_child(island)
	board_fx = Node2D.new()
	board_fx.z_index = 10
	world.add_child(board_fx)
	board_fx.draw.connect(_draw_world)
	cam = Camera2D.new()
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
	star = Game.star_node
	star_vis = BoardMap.pos(star)
	turn_id = Game.cur
	for id in disp:
		space_of[id] = int(disp[id].get("pos", 0))
		tex_idle[id] = UI.char_tex(int(disp[id]["color"]), "idle")
		tex_jump[id] = UI.char_tex(int(disp[id]["color"]), "jump")
		shown_coins[id] = float(disp[id]["coins"])
	for id in disp:
		vis[id] = _token_target(id)

	if turn_id == 0:
		# vue d'ensemble au début de chaque tour de table
		overview = 2.6
		cam_zoom_target = MAP_ZOOM
		cam.zoom = Vector2(MAP_ZOOM, MAP_ZOOM)
		cam.position = BoardMap.SIZE / 2.0 + MAP_OFS
		_show_banner("Tour %d / %d" % [Net.round_num, Net.total_rounds], UI.YELLOW)
		if Net.round_num == Net.total_rounds:
			_show_banner("Dernier tour !", UI.RED)
	else:
		cam.zoom = Vector2(0.9, 0.9)
		cam.position = vis.get(turn_id, BoardMap.SIZE / 2.0)
	cam_target = cam.position
	Game.event.connect(_on_event)
	Game.emote_shown.connect(show_emote)
	for n in ["faceHappy", "laugh", "faceAngry", "faceSad", "heart", "idea", "exclamation", "exclamations", "stars", "drops", "cash", "anger"]:
		_emote_tex(n)
	for n in ["star_04", "star_06", "spark_03", "magic_02", "twirl_01", "light_02", "flare_01"]:
		_ptex[n] = load("res://assets/particles/%s.png" % n)
	Net.players_changed.connect(_on_players_changed)
	if not Game.ask.is_empty():
		_on_event(Game.ask)
	if OS.get_environment("BOARD_EVENT") != "":
		_debug_event()
	if OS.get_environment("BOARD_MAP") != "":
		map_view = true


func _debug_event() -> void:
	for ev in OS.get_environment("BOARD_EVENT").split("|"):
		await get_tree().create_timer(0.8).timeout
		if ev.begins_with("emote:"):
			var parts := ev.split(":")
			show_emote(int(parts[1]), parts[2])
			continue
		var d = JSON.parse_string(ev)
		if d is Dictionary:
			d["players"] = Net.players
			_on_event(d)
	if OS.get_environment("BOARD_MENU") != "":
		menu = OS.get_environment("BOARD_MENU")
		menu_item = OS.get_environment("BOARD_ITEM")


# ------------------------------------------------------------------ pions
func _token_target(id: int) -> Vector2:
	var s: int = space_of.get(id, 0)
	var base := BoardMap.pos(s)
	if id == turn_id and phase != "idle":
		return base
	var same := []
	for o in space_of:
		if space_of[o] == s and not (o == turn_id and phase != "idle"):
			same.append(o)
	same.sort()
	var centered: bool = turn_id != 0 and phase != "idle" and int(space_of.get(turn_id, -1)) == s
	if same.size() <= 1 and not centered:
		return base
	var k := same.find(id)
	var a := TAU * k / maxi(1, same.size()) + (0.6 if centered else -PI / 2.0)
	var rad := Vector2(66.0, 30.0) if centered else Vector2(40.0, 18.0)
	return base + Vector2(cos(a) * rad.x, sin(a) * rad.y)


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


func _warp_scale(id: int) -> float:
	if not warp.has(id):
		return 1.0
	var k := t - float(warp[id][0])
	if k < 0.45:
		return 1.0 - k / 0.45
	if k < 0.9:
		return (k - 0.45) / 0.45
	warp.erase(id)
	return 1.0


func _big() -> float:
	# en vue carte, les pions et l'étoile grossissent pour rester visibles
	return clampf(0.62 / cam.zoom.x, 1.0, 2.6)


func _draw_world() -> void:
	var m := _big()
	# flèches du carrefour
	if str(ask.get("what", "")) == "branch":
		var at := int(ask["at"])
		var opts: Array = ask["options"]
		var c := BoardMap.pos(at)
		for i in opts.size():
			var to := int(opts[i]["to"])
			var dir := (BoardMap.pos(to) - c).normalized()
			var mine := menu == "branch" and sel == i
			var tip := c + dir * (150.0 + (10.0 * sin(t * 6.0) if mine else 0.0))
			var nn := Vector2(-dir.y, dir.x)
			var sz := 1.5 if mine else 1.15
			var tri := PackedVector2Array([tip, tip - dir * 50.0 * sz + nn * 36.0 * sz, tip - dir * 30.0 * sz, tip - dir * 50.0 * sz - nn * 36.0 * sz])
			board_fx.draw_colored_polygon(tri, UI.YELLOW if mine else Color.WHITE)
			var l := tri.duplicate()
			l.append(tri[0])
			board_fx.draw_polyline(l, UI.DARK, 6.0, true)
	# fantômes au-dessus des cases fantôme, rochers piquants à l'entrée des raccourcis
	for i in BoardMap.count():
		if BoardMap.kind(i) == "G":
			var gp := BoardMap.pos(i) + Vector2(0, -120 + sin(t * 2.0 + i) * 12.0)
			board_fx.draw_circle(BoardMap.pos(i) + Vector2(0, 14), 30.0, Color(0, 0, 0, 0.12))
			board_fx.draw_texture_rect(tex_ghost, Rect2(gp - Vector2(48, 48), Vector2(96, 96)), false, Color(1, 1, 1, 0.85 + 0.15 * sin(t * 3.0)))
	for f in Game.rocks:
		var fi := int(f)
		var jn := fi
		for k in BoardMap.count():
			if (BoardMap.next(k) as Array).has(fi) and (BoardMap.next(k) as Array).size() > 1:
				jn = k
		var prev_c := BoardMap.pos(jn).lerp(BoardMap.pos(fi), 0.55)
		var rp := prev_c + Vector2(0, -40)
		board_fx.draw_circle(prev_c + Vector2(0, 30), 46.0, Color(0, 0, 0, 0.16))
		board_fx.draw_set_transform(rp, sin(t * 1.3 + fi) * 0.08, Vector2(0.45, 0.45))
		board_fx.draw_texture(tex_rock, -tex_rock.get_size() / 2.0)
		board_fx.draw_set_transform(Vector2.ZERO)
		var sign_r := Rect2(rp + Vector2(-46, -128), Vector2(92, 40))
		UI.panel(board_fx, sign_r, Color("#fff3d6"), UI.WHITE, 14, 4)
		board_fx.draw_set_transform(sign_r.position + Vector2(24, 20), 0.0, Vector2(0.22, 0.22))
		board_fx.draw_texture(tex_coin, Vector2(-64, -64))
		board_fx.draw_set_transform(Vector2.ZERO)
		UI.text(board_fx, sign_r.position + Vector2(60, 20), str(int(Game.rocks[f])), 24, UI.DARK, 0)
	# bloc caché qui sort au-dessus du joueur
	if not hidden_fx.is_empty() and t - float(hidden_fx["t0"]) < 2.6 and vis.has(int(hidden_fx["id"])):
		var hk := t - float(hidden_fx["t0"])
		var hp: Vector2 = vis[int(hidden_fx["id"])] + Vector2(0, -170 - minf(hk, 0.3) * 120.0)
		board_fx.draw_set_transform(hp, 0.0, Vector2(0.8, 0.8) * (1.0 + maxf(0.0, 0.25 - hk)))
		board_fx.draw_texture(tex_block_hit if hk > 0.3 else tex_block, Vector2(-64, -64))
		board_fx.draw_set_transform(Vector2.ZERO)
	# étoile
	var sp := star_vis
	var pulse := sin(t * 4.0)
	var spc := BoardMap.pos(star)
	for k in 4:
		board_fx.draw_circle(spc, (74.0 - k * 12.0 + pulse * 4.0) * m, Color(1.0, 0.85, 0.2, 0.08 + k * 0.03))
	board_fx.draw_arc(spc, (52.0 + pulse * 3.0), 0, TAU, 48, Color(UI.DARK, 0.9), 11.0, true)
	board_fx.draw_arc(spc, (52.0 + pulse * 3.0), 0, TAU, 48, UI.YELLOW, 6.0, true)
	board_fx.draw_set_transform(sp + Vector2(0, -92 + sin(t * 2.5) * 8.0) * Vector2(1, 1) + Vector2(0, -60.0 * (m - 1.0)), sin(t * 1.5) * 0.15, Vector2(0.95, 0.95) * m)
	board_fx.draw_texture(tex_star, Vector2(-64, -64))
	board_fx.draw_set_transform(Vector2.ZERO)
	for i in 3:
		var a := t * 2.0 + i * TAU / 3.0
		board_fx.draw_circle(sp + Vector2(cos(a) * 62.0 * m, -92 * m + sin(a) * 26.0 * m), 5.0 * m, Color(1, 1, 0.7, 0.9))
	# pions triés par profondeur, le joueur actif devant
	var ids := vis.keys()
	ids.sort_custom(func(a, b): return vis[a].y < vis[b].y)
	if ids.has(turn_id):
		ids.erase(turn_id)
		ids.append(turn_id)
	for id in ids:
		var p: Vector2 = vis[id]
		var ho := _hop_offset(id)
		var ws := _warp_scale(id)
		var squash := 1.0 + (0.08 * sin(t * 3.0 + float(id % 7)) if ho == 0.0 else 0.0)
		var sc := TOKEN_SCALE * m * ws
		board_fx.draw_circle(p + Vector2(0, 2), 22.0 * m * ws * (1.0 + ho / 200.0), Color(UI.DARK, 0.25))
		if m > 1.2:
			board_fx.draw_circle(p + Vector2(0, -40.0 * m), 44.0 * m * ws, Color(Net.color_of(id), 0.35))
		var tx: Texture2D = tex_jump.get(id) if ho < -2.0 else tex_idle.get(id)
		if tx:
			board_fx.draw_set_transform(p + Vector2(0, ho), warp_spin(id), Vector2(sc * (2.0 - squash), sc * squash))
			board_fx.draw_texture(tx, Vector2(-128, -256))
			board_fx.draw_set_transform(Vector2.ZERO)
		if id == turn_id and ws > 0.5:
			UI.text(board_fx, p + Vector2(0, ho - 112 * m), Net.name_of(id), int(22 * m), Net.color_of(id), int(7 * m))
		if warp.has(id):
			for k in 6:
				var a2 := t * 6.0 + k * TAU / 6.0
				board_fx.draw_circle(p + Vector2(cos(a2) * 50.0, -50 + sin(a2) * 24.0), 6.0, Color(1, 1, 0.6, 0.9))
	# dés au-dessus du joueur actif
	if vis.has(turn_id) and turn_id != 0:
		var head: Vector2 = vis[turn_id] + Vector2(0, -238 + _hop_offset(turn_id))
		if phase == "action":
			var n := spin_n
			for i in n:
				var bp := head + Vector2((i - (n - 1) / 2.0) * 118.0, sin(t * 5.0 + i) * 6.0)
				_dice_block(bp, spin_fixed if spin_fixed > 0 else _spin_val(i), false)
			if spin_bonus > 0:
				UI.text(board_fx, head + Vector2(n * 59.0 + 50.0, 0), "+%d" % spin_bonus, 40, UI.RED, 9)
		elif phase == "dice":
			var n2 := dice_vals.size()
			var all_done := true
			for i in n2:
				var stop := dice_t0 + 0.25 + 0.35 * i
				var done := t >= stop
				all_done = all_done and done
				var bump := clampf(1.0 - (t - stop) * 5.0, 0.0, 1.0) if done else 0.0
				var bp := head + Vector2((i - (n2 - 1) / 2.0) * 118.0, -bump * 22.0)
				_dice_block(bp, int(dice_vals[i]) if done else _spin_val(i), done)
			if all_done and (n2 > 1 or dice_bonus > 0) and t > dice_t0 + 0.25 + 0.35 * n2 + 0.2:
				if dice_bonus > 0:
					UI.text(board_fx, head + Vector2(n2 * 59.0 + 34.0, 0), "+%d" % dice_bonus, 38, UI.RED, 8)
				var pill := head + Vector2(n2 * 59.0 + (130.0 if dice_bonus > 0 else 70.0), 0)
				UI.text(board_fx, pill + Vector2(-30, 0), "=", 40, UI.WHITE, 8)
				board_fx.draw_circle(pill + Vector2(30, 0), 44.0, UI.DARK)
				board_fx.draw_circle(pill + Vector2(30, 0), 38.0, UI.WHITE)
				UI.text(board_fx, pill + Vector2(30, 0), str(dice_total), 44, UI.BLUE, 0)
		elif phase == "moving" and steps_left > 0:
			var np: Vector2 = vis[turn_id] + Vector2(0, -150 + _hop_offset(turn_id))
			board_fx.draw_circle(np, 32.0, UI.DARK)
			board_fx.draw_circle(np, 27.0, UI.WHITE)
			UI.text(board_fx, np, str(steps_left), 36, UI.BLUE, 0)
	# particules
	for spk in sparks:
		var tx2: Texture2D = _ptex.get(str(spk["tex"]))
		if tx2 == null:
			continue
		var k4 := (t - float(spk["t0"])) / float(spk["life"])
		var c4: Color = spk["c"]
		c4.a = 1.0 - k4 * k4
		var sc4 := float(spk["s"]) * (1.0 - k4 * 0.4)
		board_fx.draw_set_transform(spk["p"], float(spk["r"]), Vector2(sc4, sc4))
		board_fx.draw_texture(tx2, -tx2.get_size() / 2.0, c4)
		board_fx.draw_set_transform(Vector2.ZERO)
	# bulles d'émotes
	for eid in emotes:
		if not vis.has(eid):
			continue
		var age := t - float(emotes[eid][1])
		var tx := _emote_tex(str(emotes[eid][0]))
		if tx == null:
			continue
		var pop := minf(1.0, age * 7.0)
		var sc := (0.8 + 0.3 * (1.0 - pop) * sin(age * 30.0)) * m * pop
		if age > 1.9:
			sc *= maxf(0.0, 1.0 - (age - 1.9) * 3.3)
		var side := 82.0 if (eid == turn_id and phase in ["action", "dice", "moving"]) else 0.0
		var ep: Vector2 = vis[eid] + Vector2(side * m, (-150.0 if side == 0.0 else -110.0) * m + _hop_offset(eid))
		board_fx.draw_set_transform(ep, sin(age * 3.0) * 0.08, Vector2(sc, sc))
		board_fx.draw_texture(tx, -tx.get_size() / 2.0)
		board_fx.draw_set_transform(Vector2.ZERO)
	# petits gains de pièces
	for pp in popups:
		var k3: float = (t - float(pp["t"])) / 1.4
		if k3 < 1.0 and k3 >= 0.0:
			var pos: Vector2 = pp["p"] + Vector2(0, -150 - k3 * 70.0)
			UI.text(board_fx, pos, pp["txt"], 36, Color(pp["c"], 1.0 - k3 * k3), 9)
	# noms des zones en vue carte
	if m > 1.6:
		var KK := BoardMap.K
		for z in [["FORÊT", Vector2(760, 1720) * KK], ["LAC", Vector2(820, 760) * KK], ["CHÂTEAU", Vector2(1520, 800) * KK + Vector2(0, -420)], ["VOLCAN", Vector2(3080, 900) * KK + Vector2(0, 80)],
				["PLAGE", Vector2(3120, 1820) * KK], ["VILLAGE", Vector2(2000, 2450) * KK]]:
			UI.text(board_fx, z[1], z[0], 120, Color(1, 1, 1, 0.92), 26)


var _etex := {}


func _emote_tex(n: String) -> Texture2D:
	if not _etex.has(n):
		_etex[n] = load("res://assets/emotes/%s.png" % n)
	return _etex[n]


func warp_spin(id: int) -> float:
	return (t - float(warp[id][0])) * 14.0 if warp.has(id) else 0.0


func _spin_val(i: int) -> int:
	return int(fmod(t * 14.0 + i * 3.7, 10.0)) + 1


func _dice_block(bp: Vector2, v: int, hit: bool) -> void:
	board_fx.draw_set_transform(bp, 0.0, Vector2(0.66, 0.66))
	board_fx.draw_texture(tex_block_hit if hit else tex_block, Vector2(-64, -64))
	board_fx.draw_set_transform(Vector2.ZERO)
	UI.text(board_fx, bp, str(v), 46, UI.WHITE, 10)


# ------------------------------------------------------------------ événements de l'hôte
func _on_players_changed() -> void:
	for id in vis.keys():
		if not Net.players.has(id):
			vis.erase(id)
			space_of.erase(id)
			disp.erase(id)


func _on_event(d: Dictionary) -> void:
	if not is_inside_tree():
		return
	var k := str(d.get("k", ""))
	var id := int(d.get("id", 0))
	var me := Net.my_id()
	if k != "ask":
		ask = {}
	match k:
		"turn":
			turn_id = id
			phase = "idle"
			spin_n = 1
			spin_fixed = 0
			spin_bonus = 0
			overview = 0.0
			map_view = false
			if id == me:
				_show_banner("À toi de jouer !", Net.color_of(id), 1.8)
				Sfx.play("jingle_turn", 0.0, 0.0)
			else:
				_show_banner("Au tour de %s" % Net.name_of(id), Net.color_of(id), 1.8)
		"ask":
			ask = d
			ask_t0 = t
			var what := str(d.get("what", ""))
			if what == "action":
				phase = "action"
				turn_id = id
			if id == me:
				menu = what
				sel = 0
				if what == "shop":
					shop_step = 0 if int(d.get("n", 0)) == 0 else 1
				if what == "boo":
					boo_step = 0
					boo_do = ""
				if what == "branch":
					map_view = false
				Sfx.play("ui_open", -6.0, 0.0)
			if what == "action":
				Sfx.play("dice_shuffle", -10.0)
		"item":
			_close_menu()
			var it := str(d.get("item", ""))
			match it:
				"double":
					spin_n = 2
				"triple":
					spin_n = 3
				"custom":
					spin_fixed = int(d.get("value", 0))
				"mushroom":
					spin_bonus += 3
			panel = {"kind": "item", "item": it, "title": Items.item_name(it), "text": str(d.get("text", "")), "t0": t, "dur": 2.0, "col": Net.color_of(id)}
			Sfx.play("jingle_item", -2.0, 0.0)
			show_emote(id, "exclamation")
		"roll":
			_close_menu()
			turn_id = id
			phase = "dice"
			dice_vals = d.get("dice", [1])
			dice_bonus = int(d.get("bonus", 0))
			dice_total = int(d.get("total", 1))
			dice_t0 = t
			_hop(id, 0.3, 60.0)
			dice_hits = 0
			Sfx.play("dice_throw", 0.0)
			if d.get("poison", false):
				_show_banner("Empoisonné ! Dé de 1 à 3...", Color("#a064f0"), 1.6)
		"step":
			phase = "moving"
			steps_left = int(d.get("left", 0))
			_hop(id, 0.26, 26.0)
			Sfx.play("step1" if steps_left % 2 == 0 else "step2", -2.0, 0.1)
		"coins":
			var delta := int(d.get("delta", 0))
			if vis.has(id):
				popups.append({"p": vis[id], "txt": ("+%d" % delta) if delta >= 0 else str(delta), "c": UI.YELLOW if delta >= 0 else UI.RED, "t": t})
			if delta > 0:
				Sfx.play("coin", -3.0)
				if vis.has(id):
					burst(vis[id] + Vector2(0, -40), "spark_03", mini(14, 3 + delta), UI.YELLOW, 220.0)
				if delta >= 5:
					Sfx.play("chips", -6.0)
			elif delta < 0:
				Sfx.play("hurt", -4.0)
				if delta <= -5:
					show_emote(id, "faceSad")
			if str(d.get("text", "")) != "":
				_show_banner(str(d["text"]), UI.YELLOW if delta >= 0 else UI.RED, 1.6)
		"star":
			if d.get("bought", false):
				_show_banner("%s achète une ÉTOILE !" % Net.name_of(id), UI.YELLOW, 0.4)
				show_emote(id, "stars")
				if vis.has(id):
					burst(vis[id] + Vector2(0, -60), "star_06", 18, UI.YELLOW, 420.0)
					burst(vis[id] + Vector2(0, -60), "light_02", 4, Color(1, 0.9, 0.4), 120.0)
				if vis.has(id):
					popups.append({"p": vis[id], "txt": "+1 étoile", "c": UI.YELLOW, "t": t})
				_hop(id, 0.5, 90.0)
				star_celebrate(id, "%s gagne une ÉTOILE !" % _who(id), 0.3)
				star = int(d.get("from", star))
				_sync(d, k, id)
				await get_tree().create_timer(CELE_LEN + 0.2).timeout
				if not is_inside_tree():
					return
				star = int(d.get("star", star))
				star_fly = 2.0
				return
			else:
				_show_banner("Il faut %d pièces pour l'étoile..." % Game.STAR_COST, UI.GREY, 1.6)
				Sfx.play("ui_error", -4.0, 0.0)
				show_emote(id, "drops")
		"hidden":
			panel = {"kind": "msg", "title": "Bloc caché !", "text": str(d.get("text", "")), "item": str(d.get("item", "")),
				"tex": "block", "t0": t, "dur": 3.0, "col": Color("#e0a000")}
			Sfx.play("die_hit", 0.0, 0.0)
			if str(d.get("prize", "")) != "star":
				Sfx.play("jingle_good", 0.0, 0.0)
			show_emote(id, "stars" if str(d.get("prize", "")) == "star" else "exclamation")
			if vis.has(id):
				burst(vis[id] + Vector2(0, -120), "star_06", 14, UI.YELLOW, 300.0)
				hidden_fx = {"id": id, "t0": t}
			if str(d.get("prize", "")) == "star":
				star_celebrate(id, "%s trouve une ÉTOILE !" % _who(id), 1.4)
		"king":
			panel = {"kind": "msg", "title": "Case du Roi Grognon !", "text": str(d.get("text", "")), "item": "",
				"tex": "fire", "t0": t, "dur": 3.8, "col": Color("#b8322a")}
			Sfx.play("jingle_bad", 0.0, 0.0)
			show_emote(id, "anger")
			if vis.has(id):
				burst(vis[id] + Vector2(0, -40), "flare_01", 10, Color("#ff7b2e"), 260.0)
		"boo":
			panel = {"kind": "msg", "title": "Le fantôme", "text": str(d.get("text", "")), "item": "",
				"tex": "ghost", "t0": t, "dur": 3.2, "col": Color("#6c5fa8")}
			Sfx.play("jingle_item" if d.get("ok", false) else "ui_error", -2.0, 0.0)
			if d.get("ok", false):
				show_emote(int(d.get("target", 0)), "faceAngry")
				show_emote(id, "laugh")
				if str(d.get("what", "")) == "star":
					star_celebrate(id, "%s vole une ÉTOILE !" % _who(id), 1.2)
		"msg":
			panel = {"kind": "msg", "title": str(d.get("title", "")), "text": str(d.get("text", "")), "item": str(d.get("item", "")),
				"t0": t, "dur": 3.2, "col": UI.RED if d.get("bad", false) else UI.BLUE}
			if d.get("bad", false):
				Sfx.play("jingle_bad", 0.0, 0.0)
				show_emote(id, "faceAngry")
			elif str(d.get("item", "")) != "":
				Sfx.play("jingle_item", -2.0, 0.0)
				show_emote(id, "heart")
			else:
				Sfx.play("ui_question", -4.0, 0.0)
				_msg_feeling(id, str(d.get("text", "")))
		"card":
			panel = {"kind": "card", "title": str(d.get("title", "")), "text": str(d.get("text", "")), "result": str(d.get("result", "")), "t0": t, "dur": 4.0}
			Sfx.play("card_slide", 0.0)
			_card_sounds(id, str(d.get("result", "")))
		"teleport":
			if str(d.get("text", "")) != "":
				_show_banner(str(d["text"]), UI.GREEN, 2.0)
			Sfx.play("spawn", -2.0)
			if vis.has(id):
				burst(vis[id] + Vector2(0, -40), "twirl_01", 6, Color(0.6, 1.0, 0.7), 160.0)
			burst(BoardMap.pos(int(d.get("node", 0))) + Vector2(0, -40), "magic_02", 10, Color(0.6, 1.0, 0.7), 200.0)
		"bought":
			var it2 := str(d.get("item", ""))
			if vis.has(id):
				popups.append({"p": vis[id], "txt": Items.item_name(it2), "c": UI.GREEN, "t": t})
			Sfx.play("chips_handle", -2.0)
		"shop_done":
			if menu == "shop":
				_close_menu()
		"duel":
			var target := int(d.get("target", 0))
			panel = {"kind": "duel", "a": id, "b": target, "stake": int(d.get("stake", 0)), "t0": t, "dur": 3.0}
			Sfx.play("jingle_duel", 2.0, 0.0)
			if vis.has(id):
				burst(vis[id] + Vector2(0, -50), "flare_01", 6, Color("#c79bff"), 200.0)
			show_emote(id, "anger")
			show_emote(target, "exclamations")
		"last5":
			panel = {"kind": "last5", "last": int(d.get("last", 0)), "bonus": int(d.get("bonus", 10)), "t0": t, "dur": 6.2}
			Sfx.voice("hurry_up")
			Sfx.play("jingle_star", 0.0, 0.0)
		"order_roll":
			panel = {"kind": "order", "rolls": d.get("rolls", {}), "order": d.get("order", []), "t0": t, "dur": 3.0 + (d.get("order", []) as Array).size() * 0.45 + 2.4, "stopped": {}}
			Sfx.play("dice_shuffle", -2.0)
		"announce":
			_show_banner(str(d.get("text", "")), UI.YELLOW, 3.0)
			phase = "idle"
			turn_id = 0
			if Net.round_num >= Net.total_rounds:
				Sfx.voice("final_round")
			else:
				Sfx.play("bell", -4.0, 0.0)
		"end":
			phase = "idle"
			steps_left = 0
	_sync(d, k, id)


func _sync(d: Dictionary, k: String, id: int) -> void:
	if d.has("star") and k != "star" and int(d["star"]) != star:
		star = int(d["star"])
		star_fly = 2.0
	if not d.has("players"):
		return
	var snap: Dictionary = d["players"]
	for pid in snap:
		if not disp.has(pid):
			continue
		var sp: Dictionary = snap[pid]
		disp[pid]["coins"] = int(sp.get("coins", 0))
		disp[pid]["stars"] = int(sp.get("stars", 0))
		disp[pid]["items"] = sp.get("items", [])
		disp[pid]["poison"] = sp.get("poison", false)
		var np := int(sp.get("pos", 0))
		if int(space_of.get(pid, -1)) != np:
			var walking: bool = k == "step" and pid == id
			space_of[pid] = np
			if not walking and vis.has(pid):
				# téléportation (tuyau, échange, carte...)
				warp[pid] = [t, vis[pid]]
				_teleport_later(pid)


func _teleport_later(pid: int) -> void:
	await get_tree().create_timer(0.45).timeout
	if is_inside_tree() and vis.has(pid):
		vis[pid] = _token_target(pid)


## Gerbe de particules (étoiles, étincelles, magie).
func burst(p: Vector2, kind: String, n: int, col := Color.WHITE, speed := 260.0) -> void:
	for i in n:
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a) * 0.7) * randf_range(speed * 0.4, speed) + Vector2(0, -speed * 0.4)
		sparks.append({"tex": kind, "p": p, "v": v, "t0": t, "life": randf_range(0.6, 1.1), "r": randf() * TAU, "s": randf_range(0.35, 0.7), "c": col})


func _who(id: int) -> String:
	return "Tu" if id == Net.my_id() else Net.name_of(id)


## Grande animation « étoile gagnée » (façon Mario Party) par-dessus tout l'écran.
func star_celebrate(id: int, txt: String, delay := 0.0) -> void:
	star_cele = {"id": id, "t0": t + delay, "txt": txt.replace("Tu gagne ", "Tu gagnes ").replace("Tu trouve ", "Tu trouves ").replace("Tu vole ", "Tu voles "), "snd": false}
	cele_conf.clear()
	var col := Net.color_of(id)
	for i in 90:
		cele_conf.append({"p": Vector2(randf_range(-40, 1320), randf_range(-700, -20)), "v": Vector2(randf_range(-60, 60), randf_range(160, 320)),
			"r": randf() * TAU, "w": randf_range(-8, 8), "s": randf_range(7, 13),
			"c": [UI.YELLOW, col, Color("#ff7b9c"), Color("#7fd6ff"), UI.WHITE][i % 5]})


## Position de l'icône étoile d'un joueur dans les cartouches du bas (même calcul que _draw_cards).
func _card_star_pos(id: int) -> Vector2:
	var ids := disp.keys()
	ids.sort_custom(func(a, b):
		var ka := int(disp[a]["stars"]) * 100000 + int(disp[a]["coins"])
		var kb := int(disp[b]["stars"]) * 100000 + int(disp[b]["coins"])
		return ka > kb)
	var n := ids.size()
	var cw := 168.0 if n <= 6 else 140.0
	var gap := 10.0 if n <= 6 else 6.0
	var x0 := (1280.0 - (n * cw + (n - 1) * gap)) / 2.0
	var i := maxi(0, ids.find(id))
	return Vector2(x0 + i * (cw + gap) + 74.0, 720 - 90 + 41)


static func star_shape(c: CanvasItem, at: Vector2, r: float, rot: float, face := true) -> void:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var core := PackedVector2Array()
	for k in 10:
		var a := rot - PI / 2.0 + PI * k / 5.0
		var rr := r if k % 2 == 0 else r * 0.5
		outer.append(at + Vector2(cos(a), sin(a)) * (rr + r * 0.12))
		inner.append(at + Vector2(cos(a), sin(a)) * rr)
		core.append(at + Vector2(cos(a), sin(a)) * rr * 0.62 + Vector2(-r * 0.05, -r * 0.08))
	c.draw_colored_polygon(outer, Color("#fff8d8"))
	c.draw_colored_polygon(inner, Color("#ffb627"))
	c.draw_colored_polygon(core, Color("#ffe066"))
	if face:
		for sx in [-1.0, 1.0]:
			var e := at + Vector2(sx * r * 0.17, -r * 0.02).rotated(rot)
			c.draw_set_transform(e, rot, Vector2(1.0, 1.7))
			c.draw_circle(Vector2.ZERO, r * 0.07, Color("#3b2a1a"))
			c.draw_circle(Vector2(-r * 0.02, -r * 0.03), r * 0.025, UI.WHITE)
			c.draw_set_transform(Vector2.ZERO)


func _draw_star_cele() -> void:
	if star_cele.is_empty():
		return
	var k := t - float(star_cele["t0"])
	if k < 0.0:
		return
	if k > CELE_LEN:
		star_cele = {}
		return
	if not star_cele["snd"]:
		star_cele["snd"] = true
		Sfx.play("spawn", 0.0, 0.0)
		Sfx.play("jingle_star", 2.0, 0.0)
		if int(star_cele["id"]) == Net.my_id():
			Sfx.voice("congratulations", -2.0)
	var h := hud
	var id := int(star_cele["id"])
	var col := Net.color_of(id)
	var fade_in := clampf(k / 0.3, 0.0, 1.0)
	var fly := clampf((k - 2.45) / 0.75, 0.0, 1.0)
	var dim := 0.55 * fade_in * (1.0 - fly)
	h.draw_rect(Rect2(0, 0, 1280, 720), Color(0.12, 0.07, 0.25, dim))
	var center := Vector2(640, 215)
	# rayons qui tournent
	var ray_a := (1.0 - fly) * fade_in
	if ray_a > 0.0:
		for i in 16:
			var a0 := k * 0.6 + TAU * i / 16.0
			var pts := PackedVector2Array([center, center + Vector2(cos(a0), sin(a0)) * 900.0, center + Vector2(cos(a0 + 0.17), sin(a0 + 0.17)) * 900.0])
			h.draw_colored_polygon(pts, Color(1, 0.92, 0.5, 0.22 * ray_a) if i % 2 == 0 else Color(1, 1, 1, 0.08 * ray_a))
		h.draw_circle(center, 190.0, Color(1, 0.95, 0.6, 0.18 * ray_a))
		h.draw_circle(center, 130.0, Color(1, 1, 0.85, 0.25 * ray_a))
	# confettis
	for cf in cele_conf:
		var p: Vector2 = (cf["p"] as Vector2) + (cf["v"] as Vector2) * k + Vector2(sin(k * 3.0 + float(cf["w"])) * 20.0, 0)
		if p.y > 760:
			continue
		var sz := float(cf["s"])
		h.draw_set_transform(p, float(cf["r"]) + k * float(cf["w"]), Vector2(1.0, absf(cos(k * 5.0 + float(cf["w"])))))
		h.draw_rect(Rect2(Vector2(-sz / 2.0, -sz / 3.0), Vector2(sz, sz * 0.66)), Color(cf["c"], 1.0 - fly))
		h.draw_set_transform(Vector2.ZERO)
	# le perso qui saute de joie, l'étoile au-dessus de la tête
	if fly < 1.0:
		var hop := absf(sin(k * 6.0)) * 26.0 * (1.0 - fly)
		var cs := 0.95 * minf(1.0, k / 0.25) * (1.0 - fly)
		var tx: Texture2D = UI.char_tex(Net.color_idx(id), "jump")
		h.draw_set_transform(Vector2(640, 572 - hop), sin(k * 6.0) * 0.06, Vector2(cs, cs))
		h.draw_texture(tx, Vector2(-128, -256))
		h.draw_set_transform(Vector2.ZERO)
	# l'étoile : arrive en tournant, rebondit, puis file vers le compteur du joueur
	var pop := 0.0
	if k < 0.5:
		var u := k / 0.5
		pop = 1.0 + sin(u * PI * 1.5) * (1.0 - u) * 0.6 - (1.0 - u) * (1.0 - u)
	else:
		pop = 1.0 + 0.05 * sin(k * 7.0)
	var spin := (1.0 - minf(1.0, k / 0.6)) * TAU * 1.5 + sin(k * 3.0) * 0.12
	var sp := center + Vector2(0, -sin(k * 2.2) * 10.0)
	var sr := 95.0 * pop
	if fly > 0.0:
		var e := fly * fly * (3.0 - 2.0 * fly)
		var target := _card_star_pos(id)
		sp = sp.lerp(target, e) + Vector2(0, -sin(fly * PI) * 120.0)
		sr = lerpf(95.0, 12.0, e)
		spin += fly * TAU
	if k < 0.6:
		for i in 10:
			var a := TAU * i / 10.0 + k * 4.0
			h.draw_circle(sp + Vector2(cos(a), sin(a)) * (sr * 1.6 + k * 120.0), 7.0 * (1.0 - k / 0.6), Color(1, 1, 0.8, 1.0 - k / 0.6))
	star_shape(h, sp, sr, spin, sr > 30.0)
	# éclats autour
	if fly < 1.0:
		for i in 6:
			var a2 := TAU * i / 6.0 + k * 1.3
			var tw := 0.5 + 0.5 * sin(k * 9.0 + i * 1.7)
			var q := sp + Vector2(cos(a2), sin(a2)) * (sr + 46.0)
			h.draw_line(q - Vector2(0, 10 * tw), q + Vector2(0, 10 * tw), Color(1, 1, 1, tw * (1.0 - fly)), 3.0)
			h.draw_line(q - Vector2(10 * tw, 0), q + Vector2(10 * tw, 0), Color(1, 1, 1, tw * (1.0 - fly)), 3.0)
	# bandeau
	if k > 0.35 and fly < 0.6:
		var bk := minf(1.0, (k - 0.35) / 0.2)
		var sc := 0.6 + 0.4 * bk + (0.08 * sin((k - 0.35) * 12.0) * (1.0 - bk))
		h.draw_set_transform(Vector2(640, 628), 0.0, Vector2(sc, sc))
		UI.ribbon(h, Vector2.ZERO, str(star_cele["txt"]), 40, col.lerp(UI.YELLOW, 0.15))
		h.draw_set_transform(Vector2.ZERO)
	# arrivée sur le compteur : un anneau qui s'ouvre
	if fly >= 1.0:
		var ak := clampf((k - 3.2) / 0.45, 0.0, 1.0)
		var tp := _card_star_pos(id)
		h.draw_arc(tp, 14.0 + ak * 26.0, 0, TAU, 32, Color(1, 0.9, 0.3, 1.0 - ak), 4.0)


## Bulle d'émote au-dessus d'un pion.
func show_emote(id: int, name: String) -> void:
	emotes[id] = [name, t]
	if id != Net.my_id() and name in ["faceHappy", "laugh", "faceAngry", "faceSad", "heart", "idea"]:
		Sfx.play("ui_drop", -8.0)


func _msg_feeling(id: int, text: String) -> void:
	if "+" in text or "gagne" in text or "Trésor" in text or "miraculeuse" in text or "Fête" in text:
		Sfx.play("jingle_good", -2.0, 0.0)
		show_emote(id, "faceHappy")
	elif "vole" in text or "perd" in text or "-" in text or "soleil" in text or "ÉRUPTION" in text:
		Sfx.play("jingle_bad", -2.0, 0.0)
		show_emote(id, "faceSad")


func _card_sounds(id: int, result: String) -> void:
	await get_tree().create_timer(0.7).timeout
	if not is_inside_tree():
		return
	Sfx.play("card_place", 0.0)
	await get_tree().create_timer(0.8).timeout
	if not is_inside_tree():
		return
	if result.begins_with("+") or "Pile" in result or "remercient" in result:
		Sfx.play("jingle_good", -2.0, 0.0)
		show_emote(id, "faceHappy" if not result.begins_with("+") else "cash")
	elif result.begins_with("-") or "Face" in result:
		Sfx.play("jingle_bad", -2.0, 0.0)
		show_emote(id, "faceSad")


func _show_banner(txt: String, col: Color, dur := 2.4) -> void:
	banner = txt
	banner_col = col
	banner_t = dur


func _close_menu() -> void:
	menu = ""
	sel = 0


# ------------------------------------------------------------------ réponses du joueur
func _my_items() -> Array:
	return disp.get(Net.my_id(), {}).get("items", [])


func _others() -> Array:
	var out := []
	var ids := disp.keys()
	ids.sort()
	for id in ids:
		if id != Net.my_id():
			out.append(id)
	return out


func _activate(a: String) -> void:
	if a == "":
		return
	Sfx.play("ui_ok", -4.0, 0.0)
	if a == "map":
		map_view = not map_view
		return
	match menu:
		"action":
			if a == "roll":
				Game.send_request({"what": "action", "do": "roll"})
				_close_menu()
			elif a == "items":
				menu = "items"
				sel = 0
		"items":
			if a == "back":
				menu = "action"
				sel = 1
			elif a.begins_with("item:"):
				menu_item = a.substr(5)
				if menu_item == "custom":
					menu = "custom"
					custom_val = 6
				elif Items.needs_target(menu_item):
					menu = "target"
					sel = 0
				else:
					_use(menu_item, -1, 0)
		"target":
			if a == "back":
				menu = "items"
				sel = 0
			elif a.begins_with("p:"):
				_use(menu_item, int(a.substr(2)), 0)
		"custom":
			if a == "back":
				menu = "items"
				sel = 0
			elif a == "minus":
				custom_val = maxi(1, custom_val - 1)
			elif a == "plus":
				custom_val = mini(10, custom_val + 1)
			elif a == "ok":
				_use("custom", -1, custom_val)
		"branch":
			if a.begins_with("to:"):
				Game.send_request({"what": "branch", "to": int(a.substr(3))})
				_close_menu()
		"shop":
			if a == "yes":
				shop_step = 1
				sel = 0
			elif a == "leave" or a == "no":
				Game.send_request({"what": "shop", "buy": ""})
				_close_menu()
			elif a.begins_with("buy:"):
				Game.send_request({"what": "shop", "buy": a.substr(4)})
				_close_menu()
		"duel":
			if a.begins_with("p:"):
				Game.send_request({"what": "duel", "target": int(a.substr(2))})
				_close_menu()
		"boo":
			if a == "no" or a == "back" and boo_step == 0:
				Game.send_request({"what": "boo", "do": ""})
				_close_menu()
			elif a == "back":
				boo_step = 0
				sel = 0
			elif a == "coins" or a == "star":
				boo_do = a
				boo_step = 1
				sel = 0
			elif a.begins_with("p:"):
				Game.send_request({"what": "boo", "do": boo_do, "target": int(a.substr(2))})
				_close_menu()


func _use(k: String, target: int, value: int) -> void:
	Game.send_request({"what": "action", "do": "item", "item": k, "target": target, "value": value})
	_close_menu()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and EMOTE_KEYS.has((event as InputEventKey).physical_keycode):
		if _emote_cd <= 0.0 and Net.players.has(Net.my_id()):
			_emote_cd = 1.0
			Game.send_emote(EMOTE_KEYS[(event as InputEventKey).physical_keycode])
		return
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_TAB:
		map_view = not map_view
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		hover_btn = _btn_at((event as InputEventMouseMotion).position)
		if hover_btn >= 0:
			sel = hover_btn
		return
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var b := _btn_at((event as InputEventMouseButton).position)
		if b >= 0 and bool(buttons[b]["on"]):
			_activate(str(buttons[b]["a"]))
			get_viewport().set_input_as_handled()
		elif b >= 0:
			Sfx.play("ui_error", -6.0, 0.0)
		return
	if not panel.is_empty() and str(panel.get("kind", "")) == "order" and event.is_action_pressed("jump"):
		var st: Dictionary = panel["stopped"]
		var me_id := Net.my_id()
		if not st.has(me_id) and (panel["rolls"] as Dictionary).has(me_id):
			st[me_id] = t - float(panel["t0"])
			Sfx.play("die_hit", 0.0)
		return
	if menu == "" or buttons.is_empty():
		return
	var nav := 0
	if event.is_action_pressed("left"):
		nav = -1
	elif event.is_action_pressed("right"):
		nav = 1
	elif event.is_action_pressed("down") and menu == "shop":
		nav = 4
	elif event.is_action_pressed("up") and menu == "shop":
		nav = -4
	elif event.is_action_pressed("down") and menu == "action":
		nav = 1
	elif event.is_action_pressed("up") and menu == "action":
		nav = -1
	if nav != 0:
		if menu == "custom":
			custom_val = clampi(custom_val + signi(nav), 1, 10)
		else:
			sel = clampi(sel + nav, 0, buttons.size() - 1) if absi(nav) == 4 else posmod(sel + nav, buttons.size())
		Sfx.play("ui_move", -8.0, 0.0)
		get_viewport().set_input_as_handled()
		return
	var go := false
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).physical_keycode
		go = kc == KEY_SPACE or kc == KEY_ENTER or kc == KEY_KP_ENTER
		if kc == KEY_ESCAPE or kc == KEY_BACKSPACE:
			if menu == "boo":
				_activate("back")
			elif menu in ["items", "target", "custom"]:
				_activate("back")
			elif menu == "shop":
				_activate("leave")
			get_viewport().set_input_as_handled()
			return
	elif event is InputEventJoypadButton and event.pressed:
		go = (event as InputEventJoypadButton).button_index == JOY_BUTTON_A
	if go:
		if menu == "custom":
			_activate("ok")
		elif sel >= 0 and sel < buttons.size() and bool(buttons[sel]["on"]):
			_activate(str(buttons[sel]["a"]))
		elif sel >= 0 and sel < buttons.size():
			Sfx.play("ui_error", -6.0, 0.0)
		get_viewport().set_input_as_handled()


func _btn_at(p: Vector2) -> int:
	var vp := get_viewport().get_visible_rect().size
	var q := p * Vector2(1280, 720) / vp
	for i in buttons.size():
		if (buttons[i]["r"] as Rect2).has_point(q):
			return i
	return -1


# ------------------------------------------------------------------ boucle
func _process(delta: float) -> void:
	t += delta
	_emote_cd -= delta
	if phase == "dice":
		while dice_hits < dice_vals.size() and t >= dice_t0 + 0.25 + 0.35 * dice_hits:
			dice_hits += 1
			Sfx.play("die_hit", -2.0)
	for eid in emotes.keys():
		if t - float(emotes[eid][1]) > 2.2:
			emotes.erase(eid)
	for sp in sparks:
		sp["p"] = (sp["p"] as Vector2) + (sp["v"] as Vector2) * delta
		sp["v"] = (sp["v"] as Vector2) * (1.0 - 2.2 * delta) + Vector2(0, 260.0 * delta)
		sp["r"] = float(sp["r"]) + delta * 4.0
	sparks = sparks.filter(func(sp): return t - float(sp["t0"]) < float(sp["life"]))
	banner_t -= delta
	if banner_t <= 0.0:
		banner = ""
	if not panel.is_empty() and t - float(panel["t0"]) > float(panel["dur"]):
		panel = {}
	if menu != "" and (ask.is_empty() or int(ask.get("id", 0)) != Net.my_id()):
		_close_menu()
	star_vis = star_vis.lerp(BoardMap.pos(star), 1.0 - exp(-delta * (2.5 if star_fly > 0.0 else 20.0)))
	star_fly = maxf(0.0, star_fly - delta)
	for id in vis:
		if warp.has(id) and t - float(warp[id][0]) < 0.45:
			continue
		vis[id] = (vis[id] as Vector2).lerp(_token_target(id), 1.0 - exp(-delta * 16.0))
	for id in disp:
		shown_coins[id] = move_toward(float(shown_coins.get(id, 0.0)), float(disp[id]["coins"]), delta * 25.0)
	popups = popups.filter(func(p): return t - float(p["t"]) < 1.4)
	# caméra
	var zoom := 0.9
	if map_view or overview > 0.0:
		overview -= delta
		cam_target = BoardMap.SIZE / 2.0 + (MAP_OFS if map_view else Vector2(0, 230))
		zoom = MAP_ZOOM
	elif star_fly > 0.0:
		cam_target = star_vis
		zoom = 0.7
	elif str(ask.get("what", "")) == "branch":
		cam_target = BoardMap.pos(int(ask["at"])) + Vector2(0, 40)
		zoom = 0.8
	elif vis.has(turn_id) and turn_id != 0:
		cam_target = vis[turn_id] + Vector2(0, -20)
	if OS.get_environment("BOARD_CAM") != "":
		var bc := OS.get_environment("BOARD_CAM").split(",")
		cam_target = Vector2(float(bc[0]), float(bc[1]))
		zoom = float(bc[2])
	cam_zoom_target = zoom
	var z := lerpf(cam.zoom.x, cam_zoom_target, 1.0 - exp(-delta * 3.5))
	cam.zoom = Vector2(z, z)
	cam.position = cam.position.lerp(cam_target, 1.0 - exp(-delta * (6.0 if z > 0.5 else 3.0)))
	if OS.get_environment("BOARD_SHOT") != "" and t > float(OS.get_environment("BOARD_SHOT_T") if OS.get_environment("BOARD_SHOT_T") != "" else "7") and not _debug_shot:
		_debug_shot = true
		_save_debug_shot()
	board_fx.queue_redraw()
	hud.queue_redraw()


# ------------------------------------------------------------------ HUD
func _btn(r: Rect2, a: String, on := true, visible_box := true) -> void:
	buttons.append({"r": r, "a": a, "on": on})
	var i := buttons.size() - 1
	var focus := i == sel
	if not visible_box:
		return
	var col := UI.WHITE if on else Color("#d5d8e3")
	if focus and on:
		col = Color("#fff4c2")
	if focus and on:
		var g := 4.0 + 2.0 * sin(t * 6.0)
		UI.panel(hud, r.grow(g), Color("#ffe066"), Color("#fff6c9"), 24, 5)
	else:
		UI.panel(hud, r, col, Color("#e7e9f6") if on else Color("#c9ccd9"), 22, 5)


func _draw_hud() -> void:
	buttons.clear()
	var me := Net.my_id()
	# tour, étoile, banque : mêmes panneaux du kit, même hauteur, icône qui déborde à gauche
	var r := Rect2(Vector2(20, 14), Vector2(196, 62))
	UI.panel(hud, r, Color("#ff6f6f") if Game.final_turns() else Color("#8e6cf0"), UI.WHITE, 22, 5)
	UI.text(hud, r.position + Vector2(50, 29), "TOUR", 19, Color("#efe8ff"), 5)
	UI.text(hud, r.position + Vector2(134, 29), "%d/%d" % [mini(Net.round_num, Net.total_rounds), Net.total_rounds], 32, UI.WHITE, 7)
	_info_panel(Rect2(Vector2(1280 - 238, 14), Vector2(218, 62)), Color("#ffc93c"), "ic_star", "Prix d'une étoile", str(Game.STAR_COST))
	_info_panel(Rect2(Vector2(1280 - 238, 86), Vector2(218, 62)), Color("#4fc3e8"), "ic_bag", "Banque", str(Game.bank))
	if not (menu == "shop" and shop_step == 1) and not map_view:
		_draw_cards()
	if map_view:
		_draw_legend()
	# bandeau
	if banner != "":
		var s := 34
		var w := UI.text_width(banner, s) + 60.0
		var br := Rect2(Vector2(640 - w / 2.0, 110), Vector2(w, 66))
		UI.panel(hud, br, UI.WHITE, banner_col.lightened(0.35), 24, 6)
		UI.text(hud, br.get_center(), banner, s, banner_col, 8)
	if not panel.is_empty():
		_draw_panel()
	# question en cours
	if not ask.is_empty():
		var who := int(ask.get("id", 0))
		var left := maxi(0, ceili(float(ask.get("timeout", 15.0)) - (t - ask_t0)))
		if who == me and menu != "":
			match menu:
				"action":
					_menu_action()
				"items":
					_menu_items()
				"target":
					_menu_target()
				"custom":
					_menu_custom()
				"branch":
					_menu_branch()
				"shop":
					_menu_shop()
				"duel":
					_menu_duel()
				"boo":
					_menu_boo()
			if left <= 8:
				UI.text(hud, Vector2(640, 196), "Choix automatique dans %d s" % left, 22, UI.WHITE, 6)
		elif who != me and who != 0:
			var msg := ""
			match str(ask.get("what", "")):
				"action":
					msg = "%s réfléchit..." % Net.name_of(who)
				"branch":
					msg = "%s choisit son chemin..." % Net.name_of(who)
				"shop":
					msg = "%s fait ses courses..." % Net.name_of(who)
				"duel":
					msg = "%s choisit son adversaire..." % Net.name_of(who)
			if msg != "":
				var mw := UI.text_width(msg, 22) + 50.0
				UI.panel(hud, Rect2(Vector2(640 - mw / 2.0, 554), Vector2(mw, 46)), Color("#3d4470"), UI.WHITE, 18, 4)
				UI.text(hud, Vector2(640, 577), msg, 22, Net.color_of(who), 5)
	if sel >= buttons.size():
		sel = maxi(0, buttons.size() - 1)
	if not map_view:
		UI.key_chip(hud, Vector2(24, 100), "Tab", "carte")
		UI.key_chip(hud, Vector2(24, 136), "1-6", "émotes")
	_draw_star_cele()


## Panneau d'info du HUD : grosse icône du kit à gauche, petite étiquette, valeur en gros + pièce.
func _info_panel(r: Rect2, col: Color, icon: String, label: String, value: String) -> void:
	UI.panel(hud, r, col, UI.WHITE, 22, 5)
	hud.draw_texture_rect(UI.gui(icon), Rect2(r.position + Vector2(-12, 4), Vector2(56, 56)), false)
	UI.text_left(hud, r.position + Vector2(52, 20), label, 15, Color(1, 1, 1, 0.95), 4)
	var w := UI.text_left(hud, r.position + Vector2(52, 42), value, 26, UI.WHITE, 7)
	hud.draw_texture_rect(UI.gui("ic_coin"), Rect2(r.position + Vector2(58 + w, 29), Vector2(26, 26)), false)


func _draw_cards() -> void:
	var ids := disp.keys()
	ids.sort_custom(func(a, b):
		var ka := int(disp[a]["stars"]) * 100000 + int(disp[a]["coins"])
		var kb := int(disp[b]["stars"]) * 100000 + int(disp[b]["coins"])
		return ka > kb)
	var n := ids.size()
	var cw := 168.0 if n <= 6 else 140.0
	var gap := 10.0 if n <= 6 else 6.0
	var x0 := (1280.0 - (n * cw + (n - 1) * gap)) / 2.0
	var rank := 0
	for i in n:
		var id: int = ids[i]
		if i > 0:
			var ka := int(disp[id]["stars"]) * 100000 + int(disp[id]["coins"])
			var kp := int(disp[ids[i - 1]]["stars"]) * 100000 + int(disp[ids[i - 1]]["coins"])
			if ka != kp:
				rank = i
		var cr := Rect2(Vector2(x0 + i * (cw + gap), 720 - 90), Vector2(cw, 80))
		var active := id == turn_id
		if active:
			cr.position.y -= 10.0 + 3.0 * sin(t * 5.0)
		var col := Net.color_of(id)
		UI.panel(hud, cr, col.lightened(0.08), Color("#fff6c9") if active else UI.WHITE, 20, 6 if active else 5)
		# portrait dans un rond blanc
		var pc := cr.position + Vector2(36, 42)
		UI.portrait(hud, pc, 27.0, Net.color_idx(id), Color("#fff2a8") if active else UI.WHITE)
		# rang
		var rk_col: Color = [Color("#ffc93c"), Color("#c9d3e3"), Color("#e8a061")][rank] if rank < 3 else Color("#9aa3b8")
		var badge := cr.position + Vector2(6, 2)
		hud.draw_texture_rect(UI.gui("rank%d" % mini(rank + 1, 8)), Rect2(badge - Vector2(17, 20), Vector2(34, 41)), false)
		var nm := str(disp[id]["name"])
		if nm.length() > 9:
			nm = nm.substr(0, 8) + "."
		UI.text(hud, cr.position + Vector2(112, 17), nm, 17, UI.WHITE, 5)
		for ic2 in [[74.0, UI.gui("ic_star"), str(int(disp[id]["stars"]))], [cw - 48.0, UI.gui("ic_coin"), str(int(round(float(shown_coins.get(id, 0.0)))))]]:
			var ip := cr.position + Vector2(float(ic2[0]), 41)
			hud.draw_texture_rect(ic2[1], Rect2(ip - Vector2(14, 14), Vector2(28, 28)), false)
			UI.text(hud, ip + Vector2(24, 0), ic2[2], 22, UI.WHITE, 6)
		var items: Array = disp[id].get("items", [])
		for j in Items.MAX_HELD:
			var ic := cr.position + Vector2(80 + j * 26, 64)
			hud.draw_circle(ic, 11.0, col.darkened(0.3))
			hud.draw_circle(ic + Vector2(0, 1), 9.5, col.darkened(0.12))
			if j < items.size():
				Items.draw_icon(hud, str(items[j]), ic, 0.38)
		if disp[id].get("poison", false):
			hud.draw_circle(cr.position + Vector2(cw - 8, 8), 9.0, Color("#a064f0"))
		if id == Net.my_id():
			UI.text(hud, cr.position + Vector2(cw / 2.0, -10), "TOI", 15, UI.YELLOW, 5)


func _draw_legend() -> void:
	var r := Rect2(Vector2(20, 140), Vector2(296, 34 + LEGEND.size() * 38 + 30))
	UI.panel(hud, r, UI.PAPER, UI.WHITE, 20, 5)
	UI.text(hud, r.position + Vector2(148, 24), "Carte de l'île", 22, UI.INK, 0)
	for i in LEGEND.size():
		var y := r.position.y + 58 + i * 38
		Island.draw_space(hud, Vector2(r.position.x + 30, y), str(LEGEND[i][0]), 14.0, true)
		hud.draw_string(UI.font(), Vector2(r.position.x + 56, y + 7), str(LEGEND[i][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UI.DARK)
	UI.text(hud, Vector2(r.position.x + 148, r.end.y - 22), "Tab : revenir au jeu", 17, UI.GREY, 0)


func _draw_panel() -> void:
	var k := t - float(panel["t0"])
	var appear := clampf(k * 6.0, 0.0, 1.0)
	var out := clampf((float(panel["dur"]) - k) * 5.0, 0.0, 1.0)
	var a := minf(appear, out)
	var center := Vector2(640, 330)
	match str(panel["kind"]):
		"order":
			_draw_order(k, a)
		"last5":
			hud.draw_rect(Rect2(0, 0, 1280, 720), Color(0.16, 0.12, 0.3, 0.5 * a))
			var pop := 1.0 + maxf(0.0, 0.4 - k) * 1.2
			UI.ribbon(hud, Vector2(640, 170), "PLUS QUE 5 TOURS !", int(52 * pop), Color("#ff6f6f"), UI.WHITE)
			var r5 := Rect2(Vector2(290, 250), Vector2(700, 300))
			UI.panel(hud, r5, Color(UI.WHITE, a), Color(Color("#ffd0d0"), a), 30, 6)
			if k > 1.0:
				var lid := int(panel["last"])
				hud.draw_set_transform(r5.position + Vector2(130, 200), 0.0, Vector2(0.55, 0.55))
				hud.draw_texture(UI.char_tex(Net.color_idx(lid), "jump" if fmod(k, 0.8) < 0.4 else "idle"), Vector2(-128, -256), Color(1, 1, 1, a))
				hud.draw_set_transform(Vector2.ZERO)
				UI.text(hud, r5.position + Vector2(130, 228), Net.name_of(lid), 24, Color(Net.color_of(lid), a), 6)
				hud.draw_string(UI.font(true), r5.position + Vector2(250, 80), "Coup de pouce pour le dernier :", HORIZONTAL_ALIGNMENT_LEFT, 420, 24, Color(UI.DARK, a))
				UI.text(hud, r5.position + Vector2(460, 125), "+%d pièces !" % int(panel["bonus"]), 40, Color(Color("#ffc93c"), a), 8)
			if k > 2.4:
				hud.draw_string(UI.font(true), r5.position + Vector2(250, 200), "Jusqu'à la fin :", HORIZONTAL_ALIGNMENT_LEFT, 420, 24, Color(UI.DARK, a))
				hud.draw_string(UI.font(), r5.position + Vector2(250, 240), "cases bleues +6 et cases rouges -6 !", HORIZONTAL_ALIGNMENT_LEFT, 440, 22, Color(UI.DARK, a))
		"card":
			var flip := clampf((k - 0.5) * 4.0, 0.0, 1.0)
			var sx := absf(cos(flip * PI))
			var front := flip > 0.5
			var size := Vector2(300, 380) * (0.85 + 0.15 * appear)
			var rr := Rect2(center - Vector2(size.x * sx, size.y) / 2.0, Vector2(size.x * sx, size.y))
			hud.draw_style_box(UI.box(Color(UI.WHITE if front else Color("#ff9a2e"), a), Color(UI.DARK, a), 6, 22), rr)
			if not front:
				if sx > 0.3:
					UI.text(hud, center, "!", 120, Color(1, 1, 1, a), 14)
			elif sx > 0.6:
				UI.text(hud, center + Vector2(0, -130), "CARTE CHANCE", 22, Color(Color("#ff9a2e"), a), 0)
				UI.text(hud, center + Vector2(0, -80), str(panel["title"]), 34, Color(UI.DARK, a), 0)
				hud.draw_multiline_string(UI.font(), center + Vector2(-130, -20), str(panel["text"]), HORIZONTAL_ALIGNMENT_CENTER, 260, 22, 4, Color(UI.GREY, a))
				if k > 1.5:
					hud.draw_multiline_string(UI.font(true), center + Vector2(-130, 100), str(panel["result"]), HORIZONTAL_ALIGNMENT_CENTER, 260, 28, 3, Color(UI.BLUE, a))
		"duel":
			var w := 760.0
			var rr2 := Rect2(center - Vector2(w / 2.0, 120), Vector2(w, 240))
			UI.panel(hud, rr2, Color(Color("#8a4fd8"), a), Color(1, 1, 1, a), 30, 6)
			UI.text(hud, center + Vector2(0, -80), "DUEL !", 54, Color(Color("#ffe27a"), a), 10)
			var ida := int(panel["a"])
			var idb := int(panel["b"])
			for side in [-1, 1]:
				var pid := ida if side < 0 else idb
				var pc := center + Vector2(side * 220.0, 60)
				hud.draw_set_transform(pc, 0.0, Vector2(0.5, 0.5))
				hud.draw_texture(UI.char_tex(Net.color_idx(pid)), Vector2(-128, -256), Color(1, 1, 1, a))
				hud.draw_set_transform(Vector2.ZERO)
				UI.text(hud, pc + Vector2(0, 22), Net.name_of(pid), 26, Color(Net.color_of(pid).lightened(0.3), a), 6)
			UI.text(hud, center + Vector2(0, 10), "VS", 64, Color(UI.WHITE, a), 10)
			UI.text(hud, center + Vector2(0, 80), "%d pièces en jeu" % int(panel["stake"]), 24, Color(UI.WHITE, a), 6)
		_:
			var w2 := 600.0
			var it := str(panel.get("item", ""))
			var rr3 := Rect2(center - Vector2(w2 / 2.0, 100), Vector2(w2, 200))
			UI.panel(hud, rr3, Color(UI.WHITE, a), Color(Color(panel.get("col", UI.BLUE)).lightened(0.45), a), 28, 6)
			UI.text(hud, center + Vector2(0, -58), str(panel["title"]), 34, Color(panel.get("col", UI.BLUE), a), 0)
			var tx := center + Vector2(-260, -12)
			var tw := 520.0
			var ptex := str(panel.get("tex", ""))
			if it != "":
				Items.draw_icon(hud, it, center + Vector2(-230, 30), 1.6)
				tx = center + Vector2(-170, -12)
				tw = 430.0
			elif ptex != "":
				var tt: Texture2D = {"ghost": tex_ghost, "fire": tex_fire, "block": tex_block}.get(ptex)
				var ic := center + Vector2(-220, 30 + sin(t * 4.0) * 5.0)
				hud.draw_circle(ic, 52.0, Color(Color(panel.get("col", UI.BLUE)).lightened(0.6), a))
				if tt:
					hud.draw_texture_rect(tt, Rect2(ic - Vector2(42, 42), Vector2(84, 84)), false, Color(1, 1, 1, a) if ptex != "fire" else Color(Color("#b8322a"), a))
				tx = center + Vector2(-160, -12)
				tw = 420.0
			hud.draw_multiline_string(UI.font(), tx, str(panel["text"]), HORIZONTAL_ALIGNMENT_CENTER, tw, 24, 4, Color(UI.DARK, a))


## « Qui commence ? » : un bloc par joueur, les chiffres défilent puis s'arrêtent.
func _draw_order(k: float, a: float) -> void:
	hud.draw_rect(Rect2(0, 0, 1280, 720), Color(0.16, 0.12, 0.3, 0.45 * a))
	UI.ribbon(hud, Vector2(640, 150), "Qui commence ?", 40, Color("#8e6cf0"), UI.YELLOW)
	var rolls: Dictionary = panel["rolls"]
	var ids := rolls.keys()
	ids.sort()
	var n := ids.size()
	var w := minf(150.0, 1100.0 / maxf(1.0, float(n)))
	var x0 := 640.0 - n * w / 2.0
	var stopped: Dictionary = panel["stopped"]
	var all_done := true
	var order: Array = panel["order"]
	for i in n:
		var id = ids[i]
		var stop_t := 1.6 + i * 0.45
		if int(id) == Net.my_id() and not stopped.has(id):
			stop_t = 2.6 + n * 0.45   # c'est toi qui tapes (ESPACE), sinon ça s'arrête tout seul
		if stopped.has(id):
			stop_t = float(stopped[id])
		var done := k >= stop_t
		if done and not stopped.has(id):
			stopped[id] = k
			Sfx.play("die_hit", -2.0)
		if not done:
			all_done = false
		var c := Vector2(x0 + i * w + w / 2.0, 430)
		# perso
		var jump := -absf(sin((k - stop_t) * 10.0)) * 22.0 if done and k - stop_t < 0.3 else 0.0
		hud.draw_set_transform(c + Vector2(0, 120 + jump), 0.0, Vector2(0.42, 0.42))
		hud.draw_texture(UI.char_tex(Net.color_idx(int(id)), "jump" if jump < -4.0 else "idle"), Vector2(-128, -256), Color(1, 1, 1, a))
		hud.draw_set_transform(Vector2.ZERO)
		UI.text(hud, c + Vector2(0, 148), Net.name_of(int(id)), 18, Color(Net.color_of(int(id)), a), 5)
		# bloc
		var br := Rect2(c + Vector2(-42, -110), Vector2(84, 84))
		var val := int(rolls[id]) if done else 1 + int(t * 18.0 + i * 3) % 10
		UI.panel(hud, br, Color(Color("#ffc93c") if not done else UI.WHITE, a), Color(1, 1, 1, a), 16, 5)
		UI.text(hud, br.get_center(), str(val), 44, Color(UI.DARK if done else UI.WHITE, a), 0 if done else 7)
		if k > 3.0 + n * 0.45:
			var rk := order.find(id)
			if rk >= 0 and k > stop_t + 0.3:
				var badge := c + Vector2(0, -150)
				var mc: Color = [Color("#ffc93c"), Color("#c9d3e3"), Color("#e8a061")][rk] if rk < 3 else Color("#9aa3b8")
				hud.draw_circle(badge, 22.0, Color(1, 1, 1, a))
				hud.draw_circle(badge, 18.0, Color(mc, a))
				UI.text(hud, badge, str(rk + 1), 22, Color(1, 1, 1, a), 5)
	if not stopped.has(Net.my_id()) and rolls.has(Net.my_id()):
		UI.text(hud, Vector2(640, 640), "ESPACE : tape ton bloc !", 30, Color(UI.YELLOW, a), 8)


func _title(txt: String, y: float) -> void:
	UI.ribbon(hud, Vector2(640, y), txt, 26)


func _menu_action() -> void:
	# menu façon Mario Party : barres penchées empilées à droite (kit d'interface)
	var items := _my_items()
	var used: bool = ask.get("used", false)
	var labels := [["roll", "Lancer le dé", true, "bar_blue"], ["items", "Objets (%d)" % items.size(), items.size() > 0 and not used, "bar_green"],
		["map", "Carte", true, "bar_yellow"]]
	UI.ribbon(hud, Vector2(1010, 268), "À toi ! Que fais-tu ?", 22, Color("#8e6cf0"))
	for i in labels.size():
		var bar: Texture2D = UI.gui(str(labels[i][3]))
		var on: bool = labels[i][2]
		var focus := i == sel and on
		var k := 1.22 if not focus else 1.3 + 0.03 * sin(t * 7.0)
		var sz := Vector2(bar.get_width(), bar.get_height()) * k
		var c := Vector2(1040 - i * 12 + (-16 if focus else 0), 350 + i * 70)
		var r := Rect2(c - sz / 2.0, sz)
		buttons.append({"r": Rect2(c - Vector2(sz.x / 2.0, 30), Vector2(sz.x, 60)), "a": labels[i][0], "on": on})
		if focus:
			hud.draw_texture_rect(bar, Rect2(r.position + Vector2(-6, -6), r.size + Vector2(12, 12)), false, Color(1, 1, 0.75, 0.55))
		hud.draw_texture_rect(bar, r, false, Color.WHITE if on else Color(0.55, 0.57, 0.65))
		hud.draw_set_transform(c + Vector2(22, -2), -0.2, Vector2.ONE)
		UI.text(hud, Vector2.ZERO, str(labels[i][1]), 24 if focus else 21, UI.WHITE if on else Color("#d5d8e3"), 7)
		hud.draw_set_transform(Vector2.ZERO)
		if focus:
			var ar := c + Vector2(-sz.x / 2.0 - 10.0 + 6.0 * sin(t * 8.0), 8)
			hud.draw_colored_polygon(PackedVector2Array([ar + Vector2(-20, -18), ar + Vector2(10, 0), ar + Vector2(-20, 18)]), UI.outline_of(UI.YELLOW))
			hud.draw_colored_polygon(PackedVector2Array([ar + Vector2(-16, -12), ar + Vector2(4, 0), ar + Vector2(-16, 12)]), Color("#ffd23f"))
	UI.text(hud, Vector2(1010, 560), "ESPACE : valider  ·  ↑ ↓ : choisir", 17, UI.WHITE, 5)


func _map_icon(c: Vector2) -> void:
	var pts := PackedVector2Array([c + Vector2(-17, -12), c + Vector2(-6, -16), c + Vector2(6, -12), c + Vector2(17, -16),
		c + Vector2(17, 12), c + Vector2(6, 16), c + Vector2(-6, 12), c + Vector2(-17, 16)])
	hud.draw_colored_polygon(pts, Color("#f6e3b0"))
	var l := pts.duplicate()
	l.append(pts[0])
	hud.draw_polyline(l, UI.DARK, 3.0)
	hud.draw_line(c + Vector2(-6, -16), c + Vector2(-6, 12), Color(UI.DARK, 0.5), 2.0)
	hud.draw_line(c + Vector2(6, -12), c + Vector2(6, 16), Color(UI.DARK, 0.5), 2.0)
	hud.draw_line(c + Vector2(-12, 4), c + Vector2(10, -4), UI.RED, 3.0)
	hud.draw_circle(c + Vector2(10, -4), 3.5, UI.RED)


func _menu_items() -> void:
	_title("Quel objet utiliser ?", 352)
	var items := _my_items()
	var w := 250.0
	var n := items.size() + 1
	var x0 := 640.0 - (n * w + (n - 1) * 14.0) / 2.0
	for i in items.size():
		var k := str(items[i])
		var r := Rect2(Vector2(x0 + i * (w + 14.0), 388), Vector2(w, 170))
		_btn(r, "item:" + k)
		Items.draw_icon(hud, k, r.position + Vector2(w / 2.0, 50), 1.4)
		UI.text(hud, r.position + Vector2(w / 2.0, 104), Items.item_name(k), 23, UI.DARK, 0)
		hud.draw_multiline_string(UI.font(), r.position + Vector2(12, 132), Items.desc(k), HORIZONTAL_ALIGNMENT_CENTER, w - 24, 16, 2, UI.GREY)
	var rb := Rect2(Vector2(x0 + items.size() * (w + 14.0), 438), Vector2(w * 0.6, 70))
	_btn(rb, "back")
	UI.text(hud, rb.get_center(), "Retour", 22, UI.DARK, 0)


func _menu_target() -> void:
	_title("%s : sur qui ?" % Items.item_name(menu_item), 400)
	var others := _others()
	var w := 150.0
	var n := others.size() + 1
	var x0 := 640.0 - (n * w + (n - 1) * 10.0) / 2.0
	for i in others.size():
		var pid: int = others[i]
		var r := Rect2(Vector2(x0 + i * (w + 10.0), 436), Vector2(w, 120))
		_btn(r, "p:%d" % pid)
		hud.draw_set_transform(r.position + Vector2(w / 2.0, 82), 0.0, Vector2(0.26, 0.26))
		hud.draw_texture(UI.char_tex(Net.color_idx(pid)), Vector2(-128, -256))
		hud.draw_set_transform(Vector2.ZERO)
		UI.text(hud, r.position + Vector2(w / 2.0, 100), Net.name_of(pid), 18, Net.color_of(pid).darkened(0.2), 0)
		hud.draw_string(UI.font(true), r.position + Vector2(w - 50, 22), str(int(disp.get(pid, {}).get("coins", 0))), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.GREY)
	var rb := Rect2(Vector2(x0 + others.size() * (w + 10.0), 461), Vector2(w * 0.7, 70))
	_btn(rb, "back")
	UI.text(hud, rb.get_center(), "Retour", 20, UI.DARK, 0)


func _menu_custom() -> void:
	_title("Dé pipé : choisis ton chiffre", 400)
	var c := Vector2(640, 492)
	var rm := Rect2(c + Vector2(-190, -40), Vector2(80, 80))
	_btn(rm, "minus")
	UI.text(hud, rm.get_center(), "<", 40, UI.DARK, 0)
	hud.draw_style_box(UI.box(Color("#facd2d"), UI.DARK, 5, 18), Rect2(c - Vector2(60, 50), Vector2(120, 100)))
	UI.text(hud, c, str(custom_val), 64, UI.WHITE, 10)
	var rp := Rect2(c + Vector2(110, -40), Vector2(80, 80))
	_btn(rp, "plus")
	UI.text(hud, rp.get_center(), ">", 40, UI.DARK, 0)
	var ro := Rect2(c + Vector2(210, -35), Vector2(130, 70))
	_btn(ro, "ok")
	UI.text(hud, ro.get_center(), "Valider", 22, UI.DARK, 0)
	var rb := Rect2(c + Vector2(-340, -35), Vector2(130, 70))
	_btn(rb, "back")
	UI.text(hud, rb.get_center(), "Retour", 22, UI.DARK, 0)
	UI.text(hud, Vector2(640, 566), "← → : changer  ·  ESPACE : valider", 18, UI.WHITE, 5)


func _menu_branch() -> void:
	_title("Choisis ton chemin !", 470)
	var opts: Array = ask.get("options", [])
	var w := 300.0
	var x0 := 640.0 - (opts.size() * w + (opts.size() - 1) * 16.0) / 2.0
	var coins := int(disp.get(Net.my_id(), {}).get("coins", 0))
	for i in opts.size():
		var o: Dictionary = opts[i]
		var cost := int(o.get("cost", 0))
		var r := Rect2(Vector2(x0 + i * (w + 16.0), 504), Vector2(w, 70))
		_btn(r, "to:%d" % int(o["to"]), cost <= coins)
		UI.text(hud, r.get_center() + Vector2(0, -10 if cost > 0 else 0), str(o.get("name", "?")), 23, UI.DARK if cost <= coins else UI.GREY, 0)
		if cost > 0:
			UI.text(hud, r.get_center() + Vector2(0, 18), ("Rocher piquant : %d pièces" if o.get("rock", false) else "Péage : %d pièces") % cost, 17, UI.RED if cost > coins else Color("#b37a00"), 0)
	UI.text(hud, Vector2(640, 596), "← → : choisir  ·  ESPACE : valider  ·  %d pas restants" % int(ask.get("left", 0)), 18, UI.WHITE, 5)


func _menu_shop() -> void:
	if shop_step == 0:
		_shop_intro()
		return
	var coins := int(disp.get(Net.my_id(), {}).get("coins", 0))
	var full := _my_items().size() >= Items.MAX_HELD
	var stock: Array = ask.get("stock", Items.SHOP)
	# l'échoppe en bois
	hud.draw_rect(Rect2(0, 0, 1280, 720), Color(0.16, 0.12, 0.3, 0.35))
	var pr := Rect2(Vector2(110, 96), Vector2(1060, 500))
	UI.panel(hud, pr, Color("#b07a48"), Color("#8a5a33"), 28, 8)
	var wall := Rect2(pr.position + Vector2(14, 14), pr.size - Vector2(28, 28))
	hud.draw_style_box(UI.box(Color("#9c6a3d"), Color(0, 0, 0, 0), 0, 20), wall)
	var px := wall.position.x + 70.0
	while px < wall.end.x - 20.0:
		hud.draw_line(Vector2(px, wall.position.y + 4), Vector2(px, wall.end.y - 4), Color("#8d5d33"), 3.0)
		px += 92.0
	# auvent rayé en haut
	for k in 14:
		var x0 := pr.position.x + k * (pr.size.x / 14.0)
		var cw := pr.size.x / 14.0
		var col := Color("#ff6f91") if k % 2 == 0 else Color("#fff4e2")
		hud.draw_rect(Rect2(Vector2(x0, pr.position.y - 26), Vector2(cw, 30)), col)
		hud.draw_circle(Vector2(x0 + cw / 2.0, pr.position.y + 4), cw / 2.0, col)
	# le vendeur et sa bulle
	var vp := Vector2(1040, 470 + absf(sin(t * 3.0)) * -4.0)
	hud.draw_set_transform(vp, 0.0, Vector2(0.72, 0.72))
	hud.draw_texture(tex_vendor, Vector2(-128, -256))
	hud.draw_set_transform(Vector2.ZERO)
	var bought_any := int(ask.get("n", 0)) > 0
	_bubble(Rect2(Vector2(760, 128), Vector2(360, 92)), "Merci ! Autre chose ?" if bought_any else "Qu'est-ce qui te tente ?", Vector2(1030, 228))
	# objet choisi : grande image, nom, description
	var cur := str(stock[clampi(sel, 0, stock.size() - 1)]) if sel < stock.size() else ""
	if cur != "":
		var ip := Vector2(230, 196)
		hud.draw_circle(ip + Vector2(0, 6), 62.0, Color(0, 0, 0, 0.15))
		hud.draw_circle(ip, 60.0, Color("#fff1d6"))
		Items.draw_icon(hud, cur, ip, 2.2)
		UI.text(hud, Vector2(500, 176), Items.item_name(cur), 38, UI.WHITE, 8)
		hud.draw_line(Vector2(320, 214), Vector2(700, 214), Color(1, 1, 1, 0.85), 3.0)
		hud.draw_string(UI.font(), Vector2(320, 250), Items.desc(cur), HORIZONTAL_ALIGNMENT_CENTER, 380, 21, UI.WHITE)
	else:
		UI.text(hud, Vector2(500, 196), "Tu repars sans rien ?", 32, UI.WHITE, 8)
	# l'étagère et les objets
	var shelf_y := 440.0
	hud.draw_style_box(UI.box(Color("#d39a62"), Color(0, 0, 0, 0), 0, 8), Rect2(Vector2(wall.position.x + 8, shelf_y + 34), Vector2(wall.size.x - 16, 26)))
	hud.draw_rect(Rect2(Vector2(wall.position.x + 8, shelf_y + 56), Vector2(wall.size.x - 16, 6)), Color("#8a5a33"))
	var n := stock.size()
	var step := 104.0
	var x0b := 190.0
	for i in n:
		var k := str(stock[i])
		var c := Vector2(x0b + i * step, shelf_y)
		var ok := coins >= Items.price(k) and not full
		var r := Rect2(c - Vector2(44, 64), Vector2(88, 128))
		_btn(r, "buy:" + k, ok, false)
		var focus := sel == i
		var lift := (-10.0 - absf(sin(t * 6.0)) * 8.0) if focus else 0.0
		if focus:
			hud.draw_circle(c + Vector2(0, -6 + lift), 50.0, Color(1, 0.95, 0.5, 0.5))
		hud.draw_circle(c + Vector2(0, 30), 30.0, Color(0, 0, 0, 0.0))
		Items.draw_icon(hud, k, c + Vector2(0, -6 + lift), 1.9 if focus else 1.55)
		if not ok:
			hud.draw_circle(c + Vector2(0, -6), 34.0, Color(0.3, 0.2, 0.15, 0.35))
		# étiquette de prix
		var tag := Rect2(c + Vector2(-38, 40), Vector2(76, 32))
		hud.draw_style_box(UI.box(Color("#fff3d6") if not focus else Color("#ffe066"), Color(0, 0, 0, 0), 0, 6), tag)
		hud.draw_set_transform(tag.position + Vector2(20, 16), 0.0, Vector2(0.2, 0.2))
		hud.draw_texture(tex_coin, Vector2(-64, -64))
		hud.draw_set_transform(Vector2.ZERO)
		UI.text(hud, tag.position + Vector2(50, 16), str(Items.price(k)), 22, UI.DARK if coins >= Items.price(k) else UI.RED, 0)
	# bas : pièces, sac, partir
	var info := Rect2(Vector2(150, 612), Vector2(330, 48))
	UI.panel(hud, info, UI.WHITE, Color("#ece9fb"), 22, 4)
	hud.draw_set_transform(info.position + Vector2(30, 24), 0.0, Vector2(0.24, 0.24))
	hud.draw_texture(tex_coin, Vector2(-64, -64))
	hud.draw_set_transform(Vector2.ZERO)
	hud.draw_string(UI.font(true), info.position + Vector2(52, 32), "%d pièces   ·   Sac %d/%d" % [coins, _my_items().size(), Items.MAX_HELD], HORIZONTAL_ALIGNMENT_LEFT, -1, 21, UI.RED if full else UI.DARK)
	var rl := Rect2(Vector2(1280 - 150 - 220, 610), Vector2(220, 52))
	_btn(rl, "leave")
	UI.text(hud, rl.get_center(), "Partir", 24, UI.DARK, 0)
	UI.text(hud, Vector2(640, 690), "← → : choisir  ·  ESPACE : acheter  ·  Échap : partir", 18, UI.WHITE, 5)


## Bulle de dialogue blanche avec une petite pointe vers celui qui parle.
func _bubble(r: Rect2, txt: String, tail: Vector2) -> void:
	var tip := PackedVector2Array([Vector2(tail.x - 18, r.end.y - 4), Vector2(tail.x + 18, r.end.y - 4), tail])
	hud.draw_style_box(UI.box(Color(0.13, 0.1, 0.25, 0.18), Color(0, 0, 0, 0), 0, int(r.size.y / 2.0)), Rect2(r.position + Vector2(0, 6), r.size))
	hud.draw_colored_polygon(tip, UI.WHITE)
	hud.draw_style_box(UI.box(UI.WHITE, Color(0, 0, 0, 0), 0, int(r.size.y / 2.0)), r)
	hud.draw_multiline_string(UI.font(), r.position + Vector2(20, r.size.y / 2.0 - 4), txt, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 40, 24, 2, UI.DARK)


## « Bienvenue à la boutique ! Veux-tu acheter quelque chose ? »  D'accord ! / Non, merci.
func _shop_intro() -> void:
	var vp := Vector2(250, 590 + absf(sin(t * 3.0)) * -5.0)
	hud.draw_circle(vp + Vector2(0, -96), 92.0, Color(1, 1, 1, 0.35))
	hud.draw_set_transform(vp, 0.0, Vector2(0.9, 0.9))
	hud.draw_texture(tex_vendor, Vector2(-128, -256))
	hud.draw_set_transform(Vector2.ZERO)
	_bubble(Rect2(Vector2(330, 300), Vector2(560, 120)), "Bienvenue à la boutique !\nVeux-tu acheter quelque chose ?", Vector2(360, 470))
	var opts := [["yes", "D'accord !"], ["no", "Non, merci."]]
	for i in opts.size():
		var r := Rect2(Vector2(920, 308 + i * 66), Vector2(250, 54))
		_btn(r, opts[i][0], true, false)
		var focus := sel == i
		var rr := r if not focus else r.grow(3)
		UI.panel(hud, rr, Color("#ff7f8f") if focus else UI.WHITE, UI.WHITE, 27, 4)
		if focus:
			hud.draw_circle(rr.position + Vector2(26, 27), 15.0, UI.DARK)
			hud.draw_polyline(PackedVector2Array([rr.position + Vector2(22, 19), rr.position + Vector2(30, 27), rr.position + Vector2(22, 35)]), Color("#ffe066"), 4.0)
		UI.text(hud, rr.get_center() + Vector2(10, 0), opts[i][1], 26, UI.WHITE if focus else UI.DARK, 5 if focus else 0)


## Le fantôme : « Que veux-tu que je vole ? » puis « À qui ? »
func _menu_boo() -> void:
	var coins := int(disp.get(Net.my_id(), {}).get("coins", 0))
	var gp := Vector2(250, 420 + sin(t * 2.5) * 10.0)
	hud.draw_circle(gp + Vector2(0, 110), 60.0, Color(0, 0, 0, 0.15))
	hud.draw_texture_rect(tex_ghost, Rect2(gp - Vector2(80, 80), Vector2(160, 160)), false, Color(1, 1, 1, 0.92))
	if boo_step == 0:
		_bubble(Rect2(Vector2(330, 250), Vector2(560, 110)), "Hihihi... je peux voler pour toi !\nQue veux-tu que je vole ?", Vector2(370, 380))
		var opts := [["coins", "Des pièces (%d)" % int(ask.get("price_coins", 5)), coins >= int(ask.get("price_coins", 5))],
			["star", "Une étoile (%d)" % int(ask.get("price_star", 30)), coins >= int(ask.get("price_star", 30))], ["no", "Rien, merci.", true]]
		for i in opts.size():
			var r := Rect2(Vector2(920, 250 + i * 66), Vector2(290, 54))
			_btn(r, opts[i][0], opts[i][2], false)
			var focus := sel == i
			var on: bool = opts[i][2]
			UI.panel(hud, r.grow(3) if focus else r, Color("#8e6cf0") if focus else (UI.WHITE if on else Color("#d5d8e3")), UI.WHITE, 27, 4)
			UI.text(hud, r.get_center(), opts[i][1], 23, UI.WHITE if focus else (UI.DARK if on else UI.GREY), 5 if focus else 0)
	else:
		_bubble(Rect2(Vector2(330, 250), Vector2(560, 90)), "À qui je vole %s ?" % ("une étoile" if boo_do == "star" else "des pièces"), Vector2(370, 360))
		var others: Array = ask.get("options", [])
		var w := 150.0
		var x0 := 640.0 - (others.size() * w + (others.size() - 1) * 10.0) / 2.0 + 120.0
		for i in others.size():
			var pid := int(others[i])
			var r := Rect2(Vector2(x0 + i * (w + 10.0), 420), Vector2(w, 130))
			_btn(r, "p:%d" % pid)
			hud.draw_set_transform(r.position + Vector2(w / 2.0, 86), 0.0, Vector2(0.26, 0.26))
			hud.draw_texture(UI.char_tex(Net.color_idx(pid)), Vector2(-128, -256))
			hud.draw_set_transform(Vector2.ZERO)
			UI.text(hud, r.position + Vector2(w / 2.0, 104), Net.name_of(pid), 18, Net.color_of(pid).darkened(0.2), 0)
			var info := "%d étoile(s)" % int(disp.get(pid, {}).get("stars", 0)) if boo_do == "star" else "%d pièces" % int(disp.get(pid, {}).get("coins", 0))
			UI.text(hud, r.position + Vector2(w / 2.0, 122), info, 15, UI.GREY, 0)
	UI.text(hud, Vector2(640, 690), "← → : choisir  ·  ESPACE : valider  ·  Échap : retour", 18, UI.WHITE, 5)


func _menu_duel() -> void:
	_title("DUEL ! Choisis ton adversaire", 400)
	var opts: Array = ask.get("options", [])
	var w := 150.0
	var x0 := 640.0 - (opts.size() * w + (opts.size() - 1) * 10.0) / 2.0
	for i in opts.size():
		var pid := int(opts[i])
		var r := Rect2(Vector2(x0 + i * (w + 10.0), 436), Vector2(w, 120))
		_btn(r, "p:%d" % pid)
		hud.draw_set_transform(r.position + Vector2(w / 2.0, 82), 0.0, Vector2(0.26, 0.26))
		hud.draw_texture(UI.char_tex(Net.color_idx(pid)), Vector2(-128, -256))
		hud.draw_set_transform(Vector2.ZERO)
		UI.text(hud, r.position + Vector2(w / 2.0, 100), Net.name_of(pid), 18, Net.color_of(pid).darkened(0.2), 0)
		hud.draw_string(UI.font(true), r.position + Vector2(w - 50, 22), str(int(disp.get(pid, {}).get("coins", 0))), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.GREY)


func _save_debug_shot() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("BOARD_SHOT"))
	get_tree().quit()
