extends Control
## Salon : les persos des joueurs, l'IP à partager, l'hôte règle et lance la partie.

const Backdrop := preload("res://screens/backdrop.gd")

const ROUNDS := [5, 10, 15, 20]

var grid: HBoxContainer
var count_lbl: Label
var rounds_btn: Button
var rounds_idx := 1


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	# prépare le décor de l'île pendant qu'on attend les potes (le plateau s'affiche ensuite sans attente)
	preload("res://board/island.gd").prebake(get_tree())
	add_child(Backdrop.new("hills"))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(1060, 0)
	center.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	pc.add_child(v)

	v.add_child(UI.lbl("Salon", 52, UI.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, 14, true))
	if Net.is_host():
		var ips := Net.local_ips()
		var radmin: Array = ips["radmin"]
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 14)
		if radmin.size() > 0:
			row.add_child(UI.lbl("Donne cette IP à tes potes :", 22, UI.GREY))
			row.add_child(UI.lbl(str(radmin[0]), 30, UI.BLUE, HORIZONTAL_ALIGNMENT_CENTER, 0, true))
			row.add_child(UI.btn("Copier", func(): DisplayServer.clipboard_set(str(radmin[0])); Net.toast.emit("IP copiée ! Colle-la sur Discord."), UI.GREY, 18))
		else:
			var other: Array = ips["other"]
			var warn := UI.lbl("Aucun VPN détecté (Radmin VPN, ou ZeroTier s'il y a des Mac) : lance-le et rejoins le réseau de tes potes.\nTes adresses : %s" % ", ".join(other), 18, UI.RED)
			warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			warn.custom_minimum_size.x = 900
			row.add_child(warn)
		v.add_child(row)

	count_lbl = UI.lbl("", 20, UI.GREY)
	v.add_child(count_lbl)
	grid = HBoxContainer.new()
	grid.alignment = BoxContainer.ALIGNMENT_CENTER
	grid.add_theme_constant_override("separation", 6)
	grid.custom_minimum_size.y = 190
	v.add_child(grid)

	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 16)
	bar.add_child(UI.btn("Changer de couleur", Net.next_color, UI.YELLOW, 22))
	if Net.is_host():
		rounds_btn = UI.btn("", _cycle_rounds, UI.BLUE, 22)
		bar.add_child(rounds_btn)
		_update_rounds()
		bar.add_child(UI.btn("Lancer la partie !", func(): Net.start_game(ROUNDS[rounds_idx]), UI.GREEN, 30))
	bar.add_child(UI.btn("Quitter", func(): Net.leave(), UI.RED, 22))
	v.add_child(bar)
	if Net.is_host():
		var row2 := HBoxContainer.new()
		row2.alignment = BoxContainer.ALIGNMENT_CENTER
		row2.add_theme_constant_override("separation", 16)
		row2.add_child(UI.btn("Tester un mini-jeu (sans plateau)", _open_picker, Color("#a064f0"), 20))
		row2.add_child(UI.btn("Options", _open_options, Color("#4fc3e8"), 20))
		v.add_child(row2)
	if not Net.is_host():
		v.add_child(UI.lbl("En attente que l'hôte lance la partie...", 20, UI.GREY))
		var row3 := HBoxContainer.new()
		row3.alignment = BoxContainer.ALIGNMENT_CENTER
		row3.add_child(UI.btn("Options (son)", _open_options, Color("#4fc3e8"), 18))
		v.add_child(row3)

	Net.players_changed.connect(_refresh)
	_refresh()
	if OS.get_environment("SHOW_OPTIONS") != "":
		_open_options.call_deferred()


func _cycle_rounds() -> void:
	rounds_idx = (rounds_idx + 1) % ROUNDS.size()
	_update_rounds()


func _update_rounds() -> void:
	rounds_btn.text = "%d tours" % ROUNDS[rounds_idx]


func _refresh() -> void:
	for c in grid.get_children():
		c.queue_free()
	var ids := Net.players.keys()
	ids.sort()
	for id in ids:
		var icon := UI.CharIcon.new(Net.color_idx(id), 124, 190)
		icon.label = Net.name_of(id)
		var tags := []
		if id == 1:
			tags.append("hôte")
		if id == Net.my_id():
			tags.append("toi")
		var ping := int(Net.players[id].get("ping", 0))
		if id != 1 and ping > 0:
			tags.append("%d ms" % ping)
		icon.sub = " · ".join(tags)
		if Net.is_host() and id != Net.my_id():
			var box := VBoxContainer.new()
			box.add_theme_constant_override("separation", 2)
			box.add_child(icon)
			var pid: int = id
			var kb := UI.btn("Exclure", func(): Net.kick_player(pid), UI.RED, 14)
			kb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			box.add_child(kb)
			grid.add_child(box)
		else:
			grid.add_child(icon)
	count_lbl.text = "%d / %d joueurs" % [Net.players.size(), Net.MAX_PLAYERS]
	if Net.players.has(Net.my_id()):
		var cfg := ConfigFile.new()
		cfg.load("user://potes.cfg")
		cfg.set_value("p", "color", Net.color_idx(Net.my_id()))
		cfg.save("user://potes.cfg")


# ------------------------------------------------------------------ choix d'un mini-jeu (test)
func _open_picker() -> void:
	var over := Control.new()
	over.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(over)
	var dim := ColorRect.new()
	dim.color = Color(UI.DARK, 0.55)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	over.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	over.add_child(center)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(960, 0)
	center.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	pc.add_child(v)
	v.add_child(UI.lbl("Quel mini-jeu ?", 44, UI.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, 12, true))
	v.add_child(UI.lbl("Il se lance tout de suite avec les joueurs du salon, puis vous revenez ici.", 18, UI.GREY))
	var grid2 := GridContainer.new()
	grid2.columns = 3
	grid2.add_theme_constant_override("h_separation", 14)
	grid2.add_theme_constant_override("v_separation", 8)
	v.add_child(grid2)
	var cols := [UI.RED, UI.BLUE, UI.GREEN, Color("#ff8c28"), Color("#a064f0"), Color("#2dc8d2"), Color("#ff78c3"), UI.YELLOW]
	var i := 0
	for key in Net.MINIGAMES:
		var k: String = key
		var b := UI.btn(str(Net.MINIGAMES[k]["name"]), func(): over.queue_free(); Net.start_practice(k), cols[i % cols.size()], 20)
		b.custom_minimum_size = Vector2(290, 46)
		grid2.add_child(b)
		i += 1
	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_CENTER
	close_row.add_child(UI.btn("Fermer", func(): over.queue_free(), UI.GREY, 20))
	v.add_child(close_row)
	UI.open_modal(over, func(): over.queue_free())


# ------------------------------------------------------------------ options
func _open_options() -> void:
	var over := Control.new()
	over.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(over)
	var dim := ColorRect.new()
	dim.color = Color(0.16, 0.12, 0.3, 0.5)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	over.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	over.add_child(center)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(900, 0)
	center.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pc.add_child(v)
	v.add_child(UI.lbl("Options", 40, UI.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, 12, true))
	# son (chacun pour soi)
	v.add_child(UI.lbl("Son", 26, UI.DARK, HORIZONTAL_ALIGNMENT_LEFT, 0, true))
	v.add_child(_vol_row("Musique", func(): return Sfx.music_vol, func(x): Sfx.set_volumes(x, Sfx.sfx_vol)))
	v.add_child(_vol_row("Bruitages", func(): return Sfx.sfx_vol, func(x): Sfx.set_volumes(Sfx.music_vol, x); Sfx.play("coin")))
	if Net.is_host():
		v.add_child(UI.lbl("Partie (réglée par l'hôte)", 26, UI.DARK, HORIZONTAL_ALIGNMENT_LEFT, 0, true))
		var bonus_btn := UI.btn("", func(): pass, UI.GREEN, 20)
		var upd := func():
			bonus_btn.text = "Étoiles bonus à la fin : %s" % ("OUI" if Net.opt_bonus else "NON")
			for st in ["normal", "hover", "pressed"]:
				bonus_btn.add_theme_stylebox_override(st, UI.button_box(UI.GREEN if Net.opt_bonus else UI.GREY, st == "pressed"))
		bonus_btn.pressed.connect(func(): Net.opt_bonus = not Net.opt_bonus; Net.save_party_options(); upd.call())
		upd.call()
		bonus_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(bonus_btn)
		v.add_child(UI.lbl("Mini-jeux en jeu (clique pour en retirer) :", 18, UI.GREY, HORIZONTAL_ALIGNMENT_LEFT))
		var grid2 := GridContainer.new()
		grid2.columns = 4
		grid2.add_theme_constant_override("h_separation", 10)
		grid2.add_theme_constant_override("v_separation", 4)
		v.add_child(grid2)
		for key in Net.MINIGAMES:
			var k: String = key
			var b := UI.btn("", func(): pass, UI.BLUE, 15)
			b.custom_minimum_size = Vector2(212, 34)
			var refresh := func():
				var on := not Net.opt_excluded.has(k)
				b.text = str(Net.MINIGAMES[k]["name"])
				for st in ["normal", "hover", "pressed"]:
					b.add_theme_stylebox_override(st, UI.button_box(Color("#7fcf6a") if on else Color("#b4b8c8"), st == "pressed"))
			b.pressed.connect(func():
				if Net.opt_excluded.has(k):
					Net.opt_excluded.erase(k)
				elif Net.opt_excluded.size() < Net.MINIGAMES.size() - 2:
					Net.opt_excluded.append(k)
				Net.save_party_options()
				refresh.call())
			refresh.call()
			grid2.add_child(b)
	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_CENTER
	close_row.add_child(UI.btn("Fermer", func(): over.queue_free(), UI.GREY, 22))
	v.add_child(close_row)
	UI.open_modal(over, func(): over.queue_free())


func _vol_row(label: String, getv: Callable, setv: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UI.lbl(label, 22, UI.DARK, HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size.x = 160
	row.add_child(l)
	var bar := VolBar.new()
	bar.getv = getv
	row.add_child(UI.btn("-", func(): setv.call(maxf(0.0, float(getv.call()) - 0.1)); bar.queue_redraw(), UI.GREY, 22))
	row.add_child(bar)
	row.add_child(UI.btn("+", func(): setv.call(minf(1.0, float(getv.call()) + 0.1)); bar.queue_redraw(), UI.GREY, 22))
	return row


class VolBar extends Control:
	var getv: Callable

	func _init() -> void:
		custom_minimum_size = Vector2(420, 44)

	func _draw() -> void:
		var v := float(getv.call())
		for i in 10:
			var on := v > i / 10.0 + 0.001
			var r := Rect2(Vector2(i * 42.0, 8), Vector2(36, 28))
			draw_style_box(UI.box(Color("#8e6cf0") if on else Color("#e4e2f2"), Color(0, 0, 0, 0), 0, 10), r)
