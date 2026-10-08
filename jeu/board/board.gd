extends Node2D
## Le plateau façon Mario Party : la grande île, les pions, le dé et les menus
## (objets, choix de route, boutique, duel). Les règles sont chez l'hôte (game.gd) :
## ici on met en scène ses événements et on envoie nos réponses.

const Backdrop := preload("res://screens/backdrop.gd")
const Island := preload("res://board/island.gd")
const TOKEN_SCALE := 0.36
const MAP_ZOOM := 0.212
const LEGEND := [["B", "+3 pièces"], ["R", "-3 pièces"], ["E", "Événement de la zone"], ["C", "Carte chance"],
	["I", "Objet gratuit"], ["D", "Duel 1 contre 1"], ["T", "Piège : -10 pièces"], ["K", "Banque"],
	["H", "Boutique"], ["P", "Tuyau : téléportation"]]

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
var tex_block: Texture2D = load("res://assets/tiles/block_exclamation.png")
var tex_block_hit: Texture2D = load("res://assets/tiles/block_exclamation_active.png")
var _debug_shot := false


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
		cam.position = BoardMap.SIZE / 2.0 + Vector2(0, 150)
		_show_banner("Tour %d / %d" % [Net.round_num, Net.total_rounds], UI.YELLOW)
		if Net.round_num == Net.total_rounds:
			_show_banner("Dernier tour !", UI.RED)
	else:
		cam.zoom = Vector2(0.9, 0.9)
		cam.position = vis.get(turn_id, BoardMap.SIZE / 2.0)
	cam_target = cam.position
	Game.event.connect(_on_event)
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
		if space_of[o] == s:
			same.append(o)
	same.sort()
	if same.size() <= 1:
		return base
	var k := same.find(id)
	var a := TAU * k / same.size() - PI / 2.0
	return base + Vector2(cos(a) * 34.0, sin(a) * 16.0)


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
	# petits gains de pièces
	for pp in popups:
		var k3: float = (t - float(pp["t"])) / 1.4
		if k3 < 1.0 and k3 >= 0.0:
			var pos: Vector2 = pp["p"] + Vector2(0, -150 - k3 * 70.0)
			UI.text(board_fx, pos, pp["txt"], 36, Color(pp["c"], 1.0 - k3 * k3), 9)
	# noms des zones en vue carte
	if m > 1.6:
		for z in [["FORÊT", Vector2(760, 1720)], ["LAC", Vector2(820, 760)], ["CHÂTEAU", Vector2(1520, 380)], ["VOLCAN", Vector2(3080, 980)],
				["PLAGE", Vector2(3120, 1820)], ["VILLAGE", Vector2(2000, 2450)]]:
			UI.text(board_fx, z[1], z[0], 84, Color(1, 1, 1, 0.85), 18)


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
				Sfx.play("select", -2.0)
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
				if what == "branch":
					map_view = false
				Sfx.play("select", -6.0)
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
			Sfx.play("gem", -4.0)
		"roll":
			_close_menu()
			turn_id = id
			phase = "dice"
			dice_vals = d.get("dice", [1])
			dice_bonus = int(d.get("bonus", 0))
			dice_total = int(d.get("total", 1))
			dice_t0 = t
			_hop(id, 0.3, 60.0)
			Sfx.play("bump", -2.0)
			if d.get("poison", false):
				_show_banner("Empoisonné ! Dé de 1 à 3...", Color("#a064f0"), 1.6)
		"step":
			phase = "moving"
			steps_left = int(d.get("left", 0))
			_hop(id, 0.26, 26.0)
			Sfx.play("jump", -16.0, 0.12)
		"coins":
			var delta := int(d.get("delta", 0))
			if vis.has(id):
				popups.append({"p": vis[id], "txt": ("+%d" % delta) if delta >= 0 else str(delta), "c": UI.YELLOW if delta >= 0 else UI.RED, "t": t})
			Sfx.play("coin" if delta >= 0 else "hurt", -3.0)
			if str(d.get("text", "")) != "":
				_show_banner(str(d["text"]), UI.YELLOW if delta >= 0 else UI.RED, 1.6)
		"star":
			if d.get("bought", false):
				_show_banner("%s achète une ÉTOILE !" % Net.name_of(id), UI.YELLOW, 2.6)
				Sfx.play("gem", 0.0)
				if vis.has(id):
					popups.append({"p": vis[id], "txt": "+1 étoile", "c": UI.YELLOW, "t": t})
				_hop(id, 0.5, 90.0)
				star = int(d.get("from", star))
				_sync(d, k, id)
				await get_tree().create_timer(1.2).timeout
				if not is_inside_tree():
					return
				star = int(d.get("star", star))
				star_fly = 2.0
				return
			else:
				_show_banner("Il faut %d pièces pour l'étoile..." % Game.STAR_COST, UI.GREY, 1.6)
		"msg":
			panel = {"kind": "msg", "title": str(d.get("title", "")), "text": str(d.get("text", "")), "item": str(d.get("item", "")),
				"t0": t, "dur": 3.2, "col": UI.RED if d.get("bad", false) else UI.BLUE}
			Sfx.play("hurt" if d.get("bad", false) else "select", -4.0)
		"card":
			panel = {"kind": "card", "title": str(d.get("title", "")), "text": str(d.get("text", "")), "result": str(d.get("result", "")), "t0": t, "dur": 4.0}
			Sfx.play("select", -2.0)
		"teleport":
			if str(d.get("text", "")) != "":
				_show_banner(str(d["text"]), UI.GREEN, 2.0)
			Sfx.play("spawn", -4.0)
		"bought":
			var it2 := str(d.get("item", ""))
			if vis.has(id):
				popups.append({"p": vis[id], "txt": Items.item_name(it2), "c": UI.GREEN, "t": t})
			Sfx.play("coin", -2.0)
		"shop_done":
			if menu == "shop":
				_close_menu()
		"duel":
			var target := int(d.get("target", 0))
			panel = {"kind": "duel", "a": id, "b": target, "stake": int(d.get("stake", 0)), "t0": t, "dur": 3.0}
			Sfx.play("gem", 0.0)
		"announce":
			_show_banner(str(d.get("text", "")), UI.YELLOW, 3.0)
			phase = "idle"
			turn_id = 0
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
	Sfx.play("select", -4.0)
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
			if a == "leave":
				Game.send_request({"what": "shop", "buy": ""})
				_close_menu()
			elif a.begins_with("buy:"):
				Game.send_request({"what": "shop", "buy": a.substr(4)})
				_close_menu()
		"duel":
			if a.begins_with("p:"):
				Game.send_request({"what": "duel", "target": int(a.substr(2))})
				_close_menu()


func _use(k: String, target: int, value: int) -> void:
	Game.send_request({"what": "action", "do": "item", "item": k, "target": target, "value": value})
	_close_menu()


func _input(event: InputEvent) -> void:
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
	if nav != 0:
		if menu == "custom":
			custom_val = clampi(custom_val + signi(nav), 1, 10)
		else:
			sel = clampi(sel + nav, 0, buttons.size() - 1) if absi(nav) == 4 else posmod(sel + nav, buttons.size())
		Sfx.play("select", -12.0)
		get_viewport().set_input_as_handled()
		return
	var go := false
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).physical_keycode
		go = kc == KEY_SPACE or kc == KEY_ENTER or kc == KEY_KP_ENTER
		if kc == KEY_ESCAPE or kc == KEY_BACKSPACE:
			if menu in ["items", "target", "custom"]:
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
		cam_target = BoardMap.SIZE / 2.0 + Vector2(0, 150)
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
func _btn(r: Rect2, a: String, on := true) -> void:
	buttons.append({"r": r, "a": a, "on": on})
	var i := buttons.size() - 1
	var focus := i == sel
	var col := UI.WHITE if on else Color("#d5d8e3")
	if focus and on:
		col = Color("#fff4c2")
	hud.draw_style_box(UI.box(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 0, 16), Rect2(r.position + Vector2(0, 6), r.size))
	hud.draw_style_box(UI.box(col, UI.YELLOW.darkened(0.2) if focus and on else UI.DARK, 6 if focus and on else 4, 16), r)


func _draw_hud() -> void:
	buttons.clear()
	var me := Net.my_id()
	# tour, étoile, banque
	var r := Rect2(Vector2(20, 16), Vector2(200, 56))
	hud.draw_style_box(UI.box(UI.WHITE, UI.DARK, 4, 16), r)
	UI.text(hud, r.get_center(), "Tour %d / %d" % [mini(Net.round_num, Net.total_rounds), Net.total_rounds], 28, UI.DARK, 0)
	var r2 := Rect2(Vector2(1280 - 250, 16), Vector2(230, 56))
	hud.draw_style_box(UI.box(UI.WHITE, UI.DARK, 4, 16), r2)
	hud.draw_set_transform(r2.position + Vector2(34, 28), 0.0, Vector2(0.38, 0.38))
	hud.draw_texture(tex_star, Vector2(-64, -64))
	hud.draw_set_transform(Vector2.ZERO)
	hud.draw_string(UI.font(true), r2.position + Vector2(60, 37), "= %d pièces" % Game.STAR_COST, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UI.DARK)
	var r3 := Rect2(Vector2(1280 - 250, 80), Vector2(230, 44))
	hud.draw_style_box(UI.box(Color("#fff4c2"), UI.DARK, 4, 14), r3)
	hud.draw_string(UI.font(true), r3.position + Vector2(18, 30), "Banque : %d" % Game.bank, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#b37a00"))
	hud.draw_set_transform(r3.position + Vector2(200, 22), 0.0, Vector2(0.26, 0.26))
	hud.draw_texture(tex_coin, Vector2(-64, -64))
	hud.draw_set_transform(Vector2.ZERO)
	_draw_cards()
	if map_view:
		_draw_legend()
	# bandeau
	if banner != "":
		var s := 34
		var w := UI.text_width(banner, s) + 60.0
		var br := Rect2(Vector2(640 - w / 2.0, 110), Vector2(w, 66))
		hud.draw_style_box(UI.box(UI.WHITE, UI.DARK, 5, 20), br)
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
				hud.draw_style_box(UI.box(Color(UI.DARK, 0.75), UI.DARK, 0, 16), Rect2(Vector2(640 - mw / 2.0, 556), Vector2(mw, 42)))
				UI.text(hud, Vector2(640, 577), msg, 22, Net.color_of(who), 5)
	if sel >= buttons.size():
		sel = maxi(0, buttons.size() - 1)
	UI.text(hud, Vector2(84, 98), "Tab : carte", 17, UI.WHITE, 5)


func _draw_cards() -> void:
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
		var cr := Rect2(Vector2(x0 + i * (cw + gap), 720 - 96), Vector2(cw, 84))
		var active := id == turn_id
		if active:
			cr.position.y -= 8.0
		var col := Net.color_of(id)
		hud.draw_style_box(UI.box(UI.WHITE, col.darkened(0.25) if active else UI.DARK, 5 if active else 4, 14), cr)
		var strip := UI.box(col, UI.DARK, 0, 10)
		strip.corner_radius_top_right = 0
		strip.corner_radius_bottom_right = 0
		hud.draw_style_box(strip, Rect2(cr.position + Vector2(4, 4), Vector2(46, cr.size.y - 8)))
		hud.draw_set_transform(cr.position + Vector2(27, 72), 0.0, Vector2(0.21, 0.21))
		hud.draw_texture(tex_idle.get(id, UI.char_tex(Net.color_idx(id))), Vector2(-128, -256))
		hud.draw_set_transform(Vector2.ZERO)
		var badge := Vector2(cr.position.x + 10, cr.position.y + 4)
		hud.draw_circle(badge, 13.0, UI.DARK)
		hud.draw_circle(badge, 10.0, UI.YELLOW if rank == 0 else UI.WHITE)
		hud.draw_string(UI.font(true), badge + Vector2(-5, 6), str(rank + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.DARK)
		var nm := str(disp[id]["name"])
		if nm.length() > 9:
			nm = nm.substr(0, 8) + "."
		hud.draw_string(UI.font(true), cr.position + Vector2(58, 23), nm, HORIZONTAL_ALIGNMENT_LEFT, 88, 17, UI.DARK)
		hud.draw_set_transform(cr.position + Vector2(68, 43), 0.0, Vector2(0.24, 0.24))
		hud.draw_texture(tex_star, Vector2(-64, -64))
		hud.draw_set_transform(Vector2.ZERO)
		hud.draw_string(UI.font(true), cr.position + Vector2(80, 51), str(int(disp[id]["stars"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UI.DARK)
		hud.draw_set_transform(cr.position + Vector2(108, 43), 0.0, Vector2(0.24, 0.24))
		hud.draw_texture(tex_coin, Vector2(-64, -64))
		hud.draw_set_transform(Vector2.ZERO)
		hud.draw_string(UI.font(true), cr.position + Vector2(120, 51), str(int(round(float(shown_coins.get(id, 0.0))))), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UI.DARK)
		var items: Array = disp[id].get("items", [])
		for j in Items.MAX_HELD:
			var ic := cr.position + Vector2(68 + j * 27, 69)
			hud.draw_circle(ic, 11.0, Color("#e9ecf5"))
			if j < items.size():
				Items.draw_icon(hud, str(items[j]), ic, 0.42)
		if disp[id].get("poison", false):
			hud.draw_circle(cr.position + Vector2(cw - 8, 8), 9.0, Color("#a064f0"))
		if id == Net.my_id():
			hud.draw_rect(Rect2(cr.position + Vector2(12, -9), Vector2(cw - 24, 5)), col)


func _draw_legend() -> void:
	var r := Rect2(Vector2(20, 140), Vector2(270, 34 + LEGEND.size() * 38))
	hud.draw_style_box(UI.box(Color(UI.WHITE, 0.95), UI.DARK, 4, 16), r)
	UI.text(hud, r.position + Vector2(135, 22), "Les cases", 22, UI.DARK, 0)
	for i in LEGEND.size():
		var y := r.position.y + 58 + i * 38
		Island.draw_space(hud, Vector2(r.position.x + 30, y), str(LEGEND[i][0]), 14.0, true)
		hud.draw_string(UI.font(), Vector2(r.position.x + 56, y + 7), str(LEGEND[i][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UI.DARK)
	UI.text(hud, Vector2(640, 96), "Carte de l'île  (Tab pour revenir)", 24, UI.WHITE, 7)


func _draw_panel() -> void:
	var k := t - float(panel["t0"])
	var appear := clampf(k * 6.0, 0.0, 1.0)
	var out := clampf((float(panel["dur"]) - k) * 5.0, 0.0, 1.0)
	var a := minf(appear, out)
	var center := Vector2(640, 330)
	match str(panel["kind"]):
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
			hud.draw_style_box(UI.box(Color(Color("#8a4fd8"), a), Color(UI.DARK, a), 6, 26), rr2)
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
			hud.draw_style_box(UI.box(Color(UI.WHITE, a), Color(UI.DARK, a), 6, 24), rr3)
			UI.text(hud, center + Vector2(0, -58), str(panel["title"]), 34, Color(panel.get("col", UI.BLUE), a), 0)
			var tx := center + Vector2(-260, -12)
			var tw := 520.0
			if it != "":
				Items.draw_icon(hud, it, center + Vector2(-230, 30), 1.6)
				tx = center + Vector2(-170, -12)
				tw = 430.0
			hud.draw_multiline_string(UI.font(), tx, str(panel["text"]), HORIZONTAL_ALIGNMENT_CENTER, tw, 24, 4, Color(UI.DARK, a))


func _title(txt: String, y: float) -> void:
	var w := UI.text_width(txt, 26) + 50.0
	hud.draw_style_box(UI.box(UI.DARK, UI.DARK, 0, 16), Rect2(Vector2(640 - w / 2.0, y - 22), Vector2(w, 44)))
	UI.text(hud, Vector2(640, y), txt, 26, UI.YELLOW, 0)


func _menu_action() -> void:
	_title("À toi ! Que veux-tu faire ?", 470)
	var items := _my_items()
	var used: bool = ask.get("used", false)
	var labels := [["roll", "Lancer le dé", true], ["items", "Objets (%d)" % items.size(), items.size() > 0 and not used], ["map", "Carte", true]]
	var w := 230.0
	var x0 := 640.0 - (labels.size() * w + (labels.size() - 1) * 16.0) / 2.0
	for i in labels.size():
		var r := Rect2(Vector2(x0 + i * (w + 16.0), 504), Vector2(w, 66))
		_btn(r, labels[i][0], labels[i][2])
		var on: bool = labels[i][2]
		UI.text(hud, r.get_center() + Vector2(14, 0), labels[i][1], 24, UI.DARK if on else UI.GREY, 0)
		var ic := r.position + Vector2(30, 35)
		match str(labels[i][0]):
			"roll":
				hud.draw_set_transform(ic, 0.0, Vector2(0.36, 0.36))
				hud.draw_texture(tex_block, Vector2(-64, -64))
				hud.draw_set_transform(Vector2.ZERO)
			"items":
				Items.draw_icon(hud, str(items[0]) if items.size() > 0 else "mushroom", ic, 0.7)
			"map":
				_map_icon(ic)
	UI.text(hud, Vector2(640, 596), "ESPACE : lancer le dé  ·  ← → : choisir  ·  Tab : carte", 18, UI.WHITE, 5)


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
			UI.text(hud, r.get_center() + Vector2(0, 18), "Péage : %d pièces" % cost, 17, UI.RED if cost > coins else Color("#b37a00"), 0)
	UI.text(hud, Vector2(640, 596), "← → : choisir  ·  ESPACE : valider  ·  %d pas restants" % int(ask.get("left", 0)), 18, UI.WHITE, 5)


func _menu_shop() -> void:
	var pr := Rect2(Vector2(150, 132), Vector2(980, 470))
	hud.draw_style_box(UI.box(Color("#fff4fa"), UI.DARK, 6, 26), pr)
	UI.text(hud, pr.position + Vector2(490, 36), "BOUTIQUE", 40, Color("#ff3d96"), 8)
	var coins := int(disp.get(Net.my_id(), {}).get("coins", 0))
	var full := _my_items().size() >= Items.MAX_HELD
	hud.draw_string(UI.font(true), pr.position + Vector2(30, 46), "Tes pièces : %d" % coins, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UI.DARK)
	hud.draw_string(UI.font(true), pr.position + Vector2(760, 46), "Sac : %d / %d" % [_my_items().size(), Items.MAX_HELD], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UI.RED if full else UI.DARK)
	var stock: Array = ask.get("stock", Items.SHOP)
	var w := 222.0
	var h := 150.0
	for i in stock.size():
		var k := str(stock[i])
		var col := i % 4
		var row := i / 4
		var r := Rect2(pr.position + Vector2(30 + col * (w + 10.0), 70 + row * (h + 10.0)), Vector2(w, h))
		var ok := coins >= Items.price(k) and not full
		_btn(r, "buy:" + k, ok)
		Items.draw_icon(hud, k, r.position + Vector2(w / 2.0, 46), 1.25)
		UI.text(hud, r.position + Vector2(w / 2.0, 96), Items.item_name(k), 21, UI.DARK if ok else UI.GREY, 0)
		hud.draw_set_transform(r.position + Vector2(w / 2.0 - 22, 126), 0.0, Vector2(0.24, 0.24))
		hud.draw_texture(tex_coin, Vector2(-64, -64))
		hud.draw_set_transform(Vector2.ZERO)
		hud.draw_string(UI.font(true), r.position + Vector2(w / 2.0 - 4, 134), str(Items.price(k)), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UI.DARK if ok else UI.RED)
	var rl := Rect2(pr.position + Vector2(780, 400), Vector2(170, 56))
	_btn(rl, "leave")
	UI.text(hud, rl.get_center(), "Partir", 24, UI.DARK, 0)
	if sel < stock.size():
		var k2 := str(stock[sel])
		hud.draw_string(UI.font(), pr.position + Vector2(36, 438), "%s : %s" % [Items.item_name(k2), Items.desc(k2)], HORIZONTAL_ALIGNMENT_LEFT, 720, 20, UI.GREY)


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
