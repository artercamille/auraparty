extends Control
## Écran titre : logo Aura PARTY, petit décor animé façon plateformes, pseudo / créer / rejoindre.

const CFG := "user://potes.cfg"
const TILE := 64.0
const TEX := [
	"tiles/terrain_grass_block_top", "tiles/terrain_grass_block_top_left", "tiles/terrain_grass_block_top_right",
	"tiles/terrain_grass_block_center", "tiles/terrain_grass_block_left", "tiles/terrain_grass_block_right",
	"tiles/water_top", "tiles/water", "tiles/bush", "tiles/lever", "tiles/sign_right", "tiles/door_closed",
	"tiles/door_closed_top", "tiles/flag_yellow_a", "tiles/flag_yellow_b", "tiles/brick_brown", "tiles/bricks_brown", "tiles/block_exclamation_active",
	"tiles/block_empty_warning", "tiles/lock_red", "tiles/ladder_top", "tiles/ladder_middle", "tiles/ladder_bottom",
	"tiles/coin_gold", "tiles/coin_gold_side", "tiles/coin_bronze", "tiles/star", "enemies/bee_a", "enemies/bee_b",
]
# couleurs : 0 rouge, 1 orange, 2 jaune, 3 vert, 4 turquoise, 5 bleu, 6 violet, 7 rose
const ISLAND_TOP := 628.0
const WATER_Y := 662.0

var my_name := ""
var name_btn: Button
var name_over: Control
var ip_edit: LineEdit
var join_btn: Button
var t := 0.0
var logo: Texture2D = load("res://assets/ui/logo.png")
var trees: Texture2D = load("res://assets/bg/layer_trees.png")
var tx := {}
var puffs := []


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for n in TEX:
		tx[n.get_file()] = load("res://assets/%s.png" % n)
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	Net.my_color_wish = int(cfg.get_value("p", "color", randi() % 8))
	for i in 6:
		puffs.append({"x": i * 260.0 + randf() * 120.0, "y": randf_range(60, 330), "s": randf_range(1.0, 1.8), "v": randf_range(5, 12)})

	my_name = str(cfg.get_value("p", "name", "")).strip_edges()

	# créer / rejoindre, sous le logo
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	holder.offset_top = 352
	holder.offset_bottom = -150
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 14)
	form.custom_minimum_size.x = 500
	holder.add_child(form)
	var host_btn := UI.btn("Créer une partie", _on_host, UI.GREEN, 34)
	host_btn.custom_minimum_size.y = 74
	form.add_child(host_btn)
	var join_box := PanelContainer.new()
	var sb := UI.box(UI.WHITE, UI.DARK, 5, 22)
	sb.set_content_margin_all(12)
	sb.content_margin_left = 16
	join_box.add_theme_stylebox_override("panel", sb)
	form.add_child(join_box)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 10)
	join_box.add_child(r2)
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "IP d'un pote (26.x.x.x)"
	ip_edit.text = str(cfg.get_value("p", "ip", ""))
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_edit.text_submitted.connect(func(_s): _on_join())
	r2.add_child(ip_edit)
	join_btn = UI.btn("Rejoindre", _on_join, UI.BLUE, 24)
	r2.add_child(join_btn)

	# badge du joueur en haut à gauche (cliquer pour changer de pseudo)
	name_btn = UI.btn("", func(): _ask_name(true), UI.WHITE, 22)
	name_btn.add_theme_color_override("font_color", UI.DARK)
	name_btn.add_theme_color_override("font_hover_color", UI.DARK)
	name_btn.add_theme_color_override("font_pressed_color", UI.DARK)
	name_btn.add_theme_constant_override("outline_size", 0)
	name_btn.add_theme_constant_override("icon_max_width", 40)
	name_btn.icon = UI.char_tex(Net.my_color_wish, "idle")
	name_btn.position = Vector2(16, 14)
	name_btn.tooltip_text = "Changer de pseudo"
	add_child(name_btn)
	_update_name_btn()

	var quit := UI.btn("Quitter", func(): get_tree().quit(), UI.RED, 18)
	add_child(quit)
	quit.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	var ver := UI.lbl("v%s" % Net.VERSION, 16, UI.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 6, true)
	ver.position = Vector2(20, 690)
	add_child(ver)
	if my_name == "" and Net.autotest == "":
		_ask_name.call_deferred(false)
	_check_update()


## Regarde sur GitHub si une version plus récente existe, et propose de la télécharger.
func _check_update() -> void:
	if Net.REPO == "" or Net.autotest != "":
		return
	var http := HTTPRequest.new()
	http.timeout = 6.0
	add_child(http)
	http.request_completed.connect(func(result, code, _h, body):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var remote := (body as PackedByteArray).get_string_from_utf8().strip_edges()
		if _newer(remote, Net.VERSION):
			_show_update(remote))
	http.request("https://raw.githubusercontent.com/%s/main/version.txt" % Net.REPO)


func _newer(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false


func _show_update(v: String) -> void:
	var b := UI.btn("Nouvelle version v%s disponible : télécharger" % v, func(): OS.shell_open("https://github.com/%s" % Net.REPO), UI.YELLOW, 20)
	b.add_theme_color_override("font_color", UI.DARK)
	b.add_theme_constant_override("outline_size", 0)
	add_child(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 14)


func _update_name_btn() -> void:
	name_btn.text = "%s  ✎" % (my_name if my_name != "" else "Pseudo")
	name_btn.size = Vector2.ZERO


## Fenêtre « Comment tu t'appelles ? » : au tout premier lancement, ou en cliquant sur le badge.
func _ask_name(can_close: bool) -> void:
	if name_over and is_instance_valid(name_over):
		return
	name_over = Control.new()
	name_over.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(name_over)
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.18, 0.35, 0.55)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	name_over.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	name_over.add_child(center)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(560, 0)
	center.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	pc.add_child(v)
	v.add_child(UI.lbl("Bienvenue !" if not can_close else "Ton pseudo", 50, UI.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, 14, true))
	var icon := UI.CharIcon.new(Net.my_color_wish, 160, 170)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(icon)
	v.add_child(UI.lbl("Comment tu t'appelles ?", 26, UI.DARK))
	var edit := LineEdit.new()
	edit.max_length = 14
	edit.placeholder_text = "Ton pseudo"
	edit.text = my_name
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.add_theme_font_size_override("font_size", 32)
	v.add_child(edit)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	var ok := func():
		var n := edit.text.strip_edges()
		if n == "":
			Net.toast.emit("Écris ton pseudo d'abord !")
			return
		my_name = n
		_save()
		_update_name_btn()
		name_over.queue_free()
		name_over = null
	edit.text_submitted.connect(func(_s): ok.call())
	if can_close:
		row.add_child(UI.btn("Annuler", func(): name_over.queue_free(); name_over = null, UI.GREY, 22))
	row.add_child(UI.btn("C'est parti !" if not can_close else "Valider", ok, UI.GREEN, 28))
	edit.grab_focus.call_deferred()
	edit.caret_column = edit.text.length()


func _player_name() -> String:
	return my_name if my_name != "" else "Joueur"


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("p", "name", my_name)
	cfg.set_value("p", "ip", ip_edit.text.strip_edges())
	cfg.save(CFG)


func _on_host() -> void:
	if my_name == "":
		_ask_name(false)
		return
	_save()
	Net.host_game(_player_name())


func _on_join() -> void:
	if my_name == "":
		_ask_name(false)
		return
	var ip := ip_edit.text.strip_edges()
	if ip == "":
		Net.toast.emit("Entre l'IP de l'hôte : elle s'affiche dans son salon.")
		return
	_save()
	join_btn.text = "..."
	join_btn.disabled = true
	Net.join_game(_player_name(), ip)


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


# ---------- dessin ----------

func _tile(n: String, x: float, y: float, s := TILE, col := Color.WHITE) -> void:
	draw_texture_rect(tx[n], Rect2(x, y, s, s), false, col)


func _tile_at(n: String, c: Vector2, s: float, rot := 0.0, sx := 1.0) -> void:
	draw_set_transform(c, rot, Vector2(sx, 1.0))
	draw_texture_rect(tx[n], Rect2(-s / 2.0, -s / 2.0, s, s), false)
	draw_set_transform(Vector2.ZERO)


func _char(c: int, pose: String, feet: Vector2, s: float, flip := false, sq := Vector2.ONE) -> void:
	draw_set_transform(feet, 0.0, Vector2(s * sq.x * (-1.0 if flip else 1.0), s * sq.y))
	draw_texture(UI.char_tex(c, pose), Vector2(-128, -256))
	draw_set_transform(Vector2.ZERO)


func _puff(c: Vector2, s: float) -> void:
	for b in [[-62, 14, 38], [-22, -12, 52], [30, -4, 46], [70, 14, 32], [0, 20, 44]]:
		draw_circle(c + Vector2(b[0], b[1]) * s, b[2] * s, Color(1, 1, 1, 0.9))


func _coin(c: Vector2, s: float, ph: float, n := "coin_gold") -> void:
	var k := cos(t * 3.0 + ph)
	if absf(k) < 0.25:
		_tile_at(n + "_side" if n == "coin_gold" else n, c, s, 0.0, 1.0)
	else:
		_tile_at(n, c, s, 0.0, absf(k))


func _ground(x0: float, cols: int, top: float, rows: int, left_edge: bool, right_edge: bool) -> void:
	for i in cols:
		var x := x0 + i * TILE
		var e := "_left" if (i == 0 and left_edge) else ("_right" if (i == cols - 1 and right_edge) else "")
		_tile("terrain_grass_block_top" + e, x, top)
		for r in range(1, rows):
			_tile("terrain_grass_block" + (e if e != "" else "_center"), x, top + r * TILE)


func _hop(c: int, a: Vector2, b: Vector2, off: float, s := 0.3) -> void:
	# attend, saute vers b, attend, revient
	var p := fposmod(t + off, 3.6)
	var feet := a
	var pose := "idle"
	var flip := b.x < a.x
	var sq := Vector2.ONE
	if p < 1.1:
		sq = Vector2(1.0 + 0.04 * sin(p * 9.0), 1.0 - 0.04 * sin(p * 9.0)) if p < 0.35 else Vector2.ONE
	elif p < 1.8:
		var u := (p - 1.1) / 0.7
		feet = a.lerp(b, u) - Vector2(0, sin(u * PI) * 70.0)
		pose = "jump"
	elif p < 2.9:
		feet = b
		flip = not flip
		var q := p - 1.8
		sq = Vector2(1.0 + 0.04 * sin(q * 9.0), 1.0 - 0.04 * sin(q * 9.0)) if q < 0.35 else Vector2.ONE
	else:
		var u := (p - 2.9) / 0.7
		feet = b.lerp(a, u) - Vector2(0, sin(u * PI) * 70.0)
		pose = "jump"
		flip = not flip
	_char(c, pose, feet, s, flip, sq)


func _draw() -> void:
	# ciel clair + gros nuages + forêt pâle (comme l'image du logo)
	var top := Color("#a4d4ff")
	var bot := Color("#eef8ff")
	var steps := 36
	for i in steps:
		draw_rect(Rect2(0, floorf(720.0 * i / steps), 1280, ceilf(720.0 / steps) + 1), top.lerp(bot, float(i) / (steps - 1)))
	for p in puffs:
		var x: float = fposmod(float(p["x"]) + t * float(p["v"]), 1280.0 + 400.0) - 200.0
		_puff(Vector2(x, float(p["y"])), float(p["s"]))
	var tw := 520.0
	var tx0 := fposmod(-t * 8.0, tw) - tw
	while tx0 < 1280.0:
		draw_texture_rect(trees, Rect2(floorf(tx0), 196, tw + 1.0, 520), false)
		tx0 += tw

	# échelle volante + perso jaune qui grimpe
	var lad := Vector2(56, 290 + sin(t * 1.2) * 6.0)
	var rot := -0.16
	draw_set_transform(lad, rot)
	for i in 5:
		var n := "ladder_top" if i == 0 else ("ladder_bottom" if i == 4 else "ladder_middle")
		draw_texture_rect(tx[n], Rect2(-32, -160 + i * 64, 64, 64), false)
	var u := sin(t * 0.8) * 0.5 + 0.5
	var moving := absf(cos(t * 0.8)) > 0.15
	var frame := "climb_a" if (not moving or int(t * 7.0) % 2 == 0) else "climb_b"
	draw_set_transform(lad + Vector2(0, 150 - u * 230).rotated(rot), rot, Vector2(0.3, 0.3))
	draw_texture(UI.char_tex(2, frame), Vector2(-128, -256))
	draw_set_transform(Vector2.ZERO)

	# blocs flottants
	var by := 168.0 + sin(t * 1.5) * 6.0
	var bump := maxf(0.0, sin(t * 2.4)) ** 8 * 10.0
	_tile("bricks_brown", 150, by)
	_tile("block_exclamation_active", 214, by - bump)
	_tile("bricks_brown", 278, by)
	for i in 3:
		_coin(Vector2(206 + i * 36, 474 + sin(t * 2.0 + i) * 3.0), 40, i * 0.6)
	# débris + cadenas + abeille à droite
	_tile_at("block_empty_warning", Vector2(1000, 196 + sin(t * 1.3) * 8.0), 70, 0.22 + sin(t * 0.9) * 0.12)
	_tile_at("brick_brown", Vector2(930, 112 + sin(t * 1.7 + 1.0) * 6.0), 46, 0.4 + t * 0.4)
	_tile_at("brick_brown", Vector2(1080, 140 + sin(t * 1.4 + 2.0) * 6.0), 38, -0.3 - t * 0.5)
	_coin(Vector2(945, 250 + sin(t * 1.8) * 5.0), 30, 1.0, "coin_bronze")
	_coin(Vector2(1050, 280 + sin(t * 1.6 + 1.0) * 5.0), 26, 2.0, "coin_bronze")
	_tile_at("lock_red", Vector2(1150, 236 + sin(t * 1.1 + 0.5) * 7.0), 64, 0.08)
	var bee := Vector2(1170 + sin(t * 0.9) * 70.0, 350 + sin(t * 1.8) * 26.0)
	var bee_dir := cos(t * 0.9)
	draw_set_transform(bee, 0.0, Vector2(-0.5 if bee_dir > 0.0 else 0.5, 0.5))
	draw_texture(tx["bee_a" if int(t * 12.0) % 2 == 0 else "bee_b"], Vector2(-64, -64))
	draw_set_transform(Vector2.ZERO)

	# logo
	var lw := 512.0
	var lh := lw * logo.get_height() / logo.get_width()
	var sc := 1.0 + 0.012 * sin(t * 2.2)
	var lc := Vector2(640, 8.0 + lh / 2.0 + sin(t * 1.6) * 4.0)
	draw_set_transform(lc + Vector2(0, 9), 0.0, Vector2(sc, sc))
	draw_texture_rect(logo, Rect2(-lw / 2.0, -lh / 2.0, lw, lh), false, Color(0.12, 0.3, 0.6, 0.22))
	draw_set_transform(lc, 0.0, Vector2(sc, sc))
	draw_texture_rect(logo, Rect2(-lw / 2.0, -lh / 2.0, lw, lh), false)
	draw_set_transform(Vector2.ZERO)

	# îlots dans l'eau
	_tile("terrain_grass_block_top_left", 236, ISLAND_TOP)
	_tile("terrain_grass_block_top_right", 300, ISLAND_TOP)
	_tile("terrain_grass_block_top_left", 560, ISLAND_TOP + 14)
	_tile("terrain_grass_block_top_right", 624, ISLAND_TOP + 14)
	_tile("bush", 590, ISLAND_TOP + 14 - 40, 48)
	_tile("terrain_grass_block_top_left", 830, ISLAND_TOP)
	_tile("terrain_grass_block_top", 894, ISLAND_TOP)
	_tile("terrain_grass_block_top_right", 958, ISLAND_TOP)
	_tile("bush", 852, ISLAND_TOP - 46, 54)
	# eau
	var wx := fposmod(-t * 18.0, TILE) - TILE
	while wx < 1280.0:
		_tile("water_top", wx, WATER_Y, TILE, Color(1, 1, 1, 0.92))
		_tile("water", wx, WATER_Y + TILE, TILE, Color(1, 1, 1, 0.92))
		wx += TILE
	# sol à gauche (levier, panneau, buisson) et à droite (porte, drapeau)
	_ground(0, 3, 560, 3, false, true)
	_tile("lever", 8, 560 - 56, 56)
	_tile("bush", 120, 560 - 50, 54)
	_tile("sign_right", 70, 560 - 60, 60)
	_ground(1040, 4, 596, 2, true, false)
	_tile("bush", 1046, 596 - 44, 48)
	_tile("door_closed_top", 1106, 596 - 112, 56)
	_tile("door_closed", 1106, 596 - 56, 56)
	_tile("flag_yellow_a" if int(t * 4.0) % 2 == 0 else "flag_yellow_b", 1172, 596 - 84, 84)

	# persos
	_hop(3, Vector2(150, 560), Vector2(300, ISLAND_TOP), 0.0)
	_hop(5, Vector2(990, ISLAND_TOP), Vector2(1064, 596), 1.7)
	var wk := sin(t * 0.7)
	var walking := absf(cos(t * 0.7)) > 0.12
	_char(7, ("walk_a" if int(t * 8.0) % 2 == 0 else "walk_b") if walking else "idle", Vector2(30 + (wk * 0.5 + 0.5) * 90.0, 560), 0.3, cos(t * 0.7) < 0.0)
	_char(0, "idle", Vector2(660, ISLAND_TOP + 14 - absf(sin(t * 3.0)) * 4.0), 0.3, true)
