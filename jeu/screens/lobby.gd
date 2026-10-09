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
			var warn := UI.lbl("Radmin VPN n'est pas détecté : lance-le et rejoins le réseau de tes potes.\nTes adresses : %s" % ", ".join(other), 18, UI.RED)
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
		row2.add_child(UI.btn("Tester un mini-jeu (sans plateau)", _open_picker, Color("#a064f0"), 20))
		v.add_child(row2)
	if not Net.is_host():
		v.add_child(UI.lbl("En attente que l'hôte lance la partie...", 20, UI.GREY))

	Net.players_changed.connect(_refresh)
	_refresh()


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
	pc.custom_minimum_size = Vector2(820, 0)
	center.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	pc.add_child(v)
	v.add_child(UI.lbl("Quel mini-jeu ?", 44, UI.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, 12, true))
	v.add_child(UI.lbl("Il se lance tout de suite avec les joueurs du salon, puis vous revenez ici.", 18, UI.GREY))
	var grid2 := GridContainer.new()
	grid2.columns = 2
	grid2.add_theme_constant_override("h_separation", 14)
	grid2.add_theme_constant_override("v_separation", 12)
	v.add_child(grid2)
	var cols := [UI.RED, UI.BLUE, UI.GREEN, Color("#ff8c28"), Color("#a064f0"), Color("#2dc8d2"), Color("#ff78c3"), UI.YELLOW]
	var i := 0
	for key in Net.MINIGAMES:
		var k: String = key
		var b := UI.btn(str(Net.MINIGAMES[k]["name"]), func(): over.queue_free(); Net.start_practice(k), cols[i % cols.size()], 24)
		b.custom_minimum_size = Vector2(380, 56)
		grid2.add_child(b)
		i += 1
	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_CENTER
	close_row.add_child(UI.btn("Fermer", func(): over.queue_free(), UI.GREY, 20))
	v.add_child(close_row)
