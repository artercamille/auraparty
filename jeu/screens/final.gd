extends Control
## Fin de partie : 1) étoiles bonus révélées une par une, 2) roulement de tambour,
## 3) le gagnant sous les projecteurs : podium, couronne, rayons, feux d'artifice, confettis.

const Backdrop := preload("res://screens/backdrop.gd")
const AWARD_T := 3.2
const DRUM_T := 2.4

var t := 0.0
var confetti := []
var bursts := []
var next_burst := 0.0
var tex_star: Texture2D = load("res://assets/tiles/star.png")
var tex_coin: Texture2D = load("res://assets/tiles/coin_gold.png")
var layer: Control
var buttons: HBoxContainer
var awards: Array = []
var reveal_at := 0.0
var last_phase := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(Backdrop.new("hills"))
	layer = Control.new()
	layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.draw.connect(_draw_final)
	add_child(layer)
	awards = Net.bonus_awards
	reveal_at = awards.size() * AWARD_T + DRUM_T
	for i in 160:
		confetti.append({"x": randf() * 1280.0, "d": randf() * 6.0, "v": randf_range(80, 180), "c": Net.COLORS[i % 8],
			"w": randf_range(5, 10), "r": randf() * TAU})
	buttons = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	if Net.is_host():
		buttons.add_child(UI.btn("Rejouer", Net.back_to_lobby, UI.GREEN))
	buttons.add_child(UI.btn("Menu principal", func(): Net.leave(), UI.RED))
	add_child(buttons)
	buttons.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 20)
	buttons.visible = false


func _phase() -> String:
	if t < awards.size() * AWARD_T:
		return "award"
	if t < reveal_at:
		return "drum"
	return "win"


func _process(delta: float) -> void:
	t += delta
	var ph := _phase()
	if ph != last_phase:
		last_phase = ph
		match ph:
			"drum":
				Sfx.play("whoosh", -2.0)
			"win":
				Sfx.play("jingle_star", 0.0, 0.0)
				Sfx.voice("congratulations")
				buttons.visible = true
	if ph == "award":
		var k := int(t / AWARD_T)
		var local := t - k * AWARD_T
		if local - delta < 1.0 and local >= 1.0:
			Sfx.play("jingle_good", -2.0, 0.0)
	if ph == "drum" and int(t * 8.0) != int((t - delta) * 8.0):
		Sfx.play("die_hit", -10.0, 0.2)
	if ph == "win":
		next_burst -= delta
		if next_burst <= 0.0:
			next_burst = randf_range(0.35, 0.8)
			_burst(Vector2(randf_range(160, 1120), randf_range(90, 300)))
	for b in bursts:
		b["t"] = float(b["t"]) + delta
	bursts = bursts.filter(func(b): return float(b["t"]) < 1.6)
	layer.queue_redraw()


func _burst(p: Vector2) -> void:
	var col: Color = Net.COLORS[randi() % 8]
	var parts := []
	for i in 26:
		var a := i * TAU / 26.0 + randf() * 0.1
		parts.append(Vector2(cos(a), sin(a)) * randf_range(160, 260))
	bursts.append({"p": p, "c": col, "parts": parts, "t": 0.0})
	Sfx.play("bump", -12.0, 0.3)


# ------------------------------------------------------------------ dessin
func _draw_final() -> void:
	var r: Array = Net.final_ranking
	if r.is_empty():
		return
	match _phase():
		"award":
			_draw_award()
		"drum":
			_draw_drum()
		"win":
			_draw_win(r)


func _draw_award() -> void:
	var ci := layer
	var k := int(t / AWARD_T)
	var a: Dictionary = awards[k]
	var local := t - k * AWARD_T
	ci.draw_rect(Rect2(0, 0, 1280, 720), Color(UI.DARK, 0.35))
	UI.ribbon(ci, Vector2(640, 92), "ÉTOILES BONUS !", 52, Color("#8e6cf0"), UI.YELLOW)
	var appear := clampf(local * 4.0, 0.0, 1.0)
	var card := Rect2(Vector2(290, 170 + (1.0 - appear) * 60.0), Vector2(700, 380))
	UI.panel(ci, card, Color(1, 1, 1, appear), Color(Color("#ece9fb"), appear), 30, 6)
	UI.text(ci, Vector2(640, card.position.y + 60), str(a["title"]), 46, Color(UI.YELLOW, appear), 12)
	UI.text(ci, Vector2(640, card.position.y + 112), "%s (%d)" % [str(a["desc"]), int(a["value"])], 24, Color(UI.GREY, appear), 0)
	var who: Array = a["who"]
	var w := 170.0
	var x0 := 640.0 - (who.size() - 1) * w / 2.0
	for i in who.size():
		var p: Dictionary = who[i]
		var c := Vector2(x0 + i * w, card.position.y + 300)
		var pop := clampf((local - 1.0) * 4.0, 0.0, 1.0)
		var bob := -absf(sin(t * 6.0 + i)) * 14.0 * pop
		ci.draw_set_transform(c + Vector2(0, bob), 0.0, Vector2(0.5, 0.5))
		ci.draw_texture(UI.char_tex(int(p["color"]), "jump" if bob < -6.0 else "idle"), Vector2(-128, -256))
		ci.draw_set_transform(Vector2.ZERO)
		UI.text(ci, c + Vector2(0, 28), str(p["name"]), 24, Net.COLORS[int(p["color"])], 7)
		if pop > 0.0:
			var sp := c + Vector2(70, -130)
			ci.draw_set_transform(sp, sin(t * 3.0) * 0.25, Vector2(0.5, 0.5) * (0.6 + pop * 0.4 + 0.08 * sin(t * 8.0)))
			ci.draw_texture(tex_star, Vector2(-64, -64))
			ci.draw_set_transform(Vector2.ZERO)
			UI.text(ci, sp + Vector2(0, 46), "+1", 26, Color(UI.YELLOW, pop), 7)


func _draw_drum() -> void:
	var ci := layer
	var local := t - awards.size() * AWARD_T
	ci.draw_rect(Rect2(0, 0, 1280, 720), Color(0.05, 0.05, 0.12, 0.7))
	# projecteur qui balaie
	var x := 640.0 + sin(local * 5.0) * 380.0 * (1.0 - local / DRUM_T)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(x - 30, 0), Vector2(x + 30, 0), Vector2(x + 190, 720), Vector2(x - 190, 720)]), Color(1, 0.95, 0.6, 0.18))
	ci.draw_circle(Vector2(x, 560), 150, Color(1, 0.95, 0.6, 0.12))
	var dots := ".".repeat(1 + int(local * 3.0) % 3)
	UI.text(ci, Vector2(640, 300), "Et le grand gagnant est" + dots, 52, UI.WHITE, 12)


func _draw_win(r: Array) -> void:
	var ci := layer
	var local := t - reveal_at
	var winner: Dictionary = r[0]
	var wc: Color = Net.COLORS[int(winner["color"])]
	var base_y := 520.0
	var wx := 640.0
	# rayons qui tournent derrière le gagnant
	var rc := Vector2(wx, base_y - 260)
	for k in 14:
		var a := k * TAU / 14.0 + local * 0.35
		ci.draw_colored_polygon(PackedVector2Array([rc, rc + Vector2(cos(a - 0.09), sin(a - 0.09)) * 900.0, rc + Vector2(cos(a + 0.09), sin(a + 0.09)) * 900.0]), Color(1, 0.92, 0.45, 0.22))
	# titre
	var pop := minf(1.0, local * 3.0)
	var s := 1.0 + (1.0 - pop) * 0.6 + 0.03 * sin(local * 4.0)
	UI.text(ci, Vector2(640, 58), "%s gagne la partie !" % str(winner["name"]), int(52 * s), wc, 14)
	# podium
	var slots := [[1, -250.0, 130.0], [0, 0.0, 190.0], [2, 250.0, 90.0]]
	for sl in slots:
		var idx: int = sl[0]
		if idx >= r.size():
			continue
		var p: Dictionary = r[idx]
		var x: float = 640.0 + float(sl[1])
		var h: float = float(sl[2]) * minf(1.0, local * 2.0)
		var col: Color = Net.COLORS[int(p["color"])]
		var block := Rect2(Vector2(x - 100, base_y - h), Vector2(200, h))
		UI.panel(ci, block, col, UI.WHITE, 18, 6)
		ci.draw_rect(Rect2(block.position + Vector2(10, 10), Vector2(180, 8)), Color(1, 1, 1, 0.35))
		if h > 60.0:
			UI.text(ci, block.get_center(), "%d" % (int(p["rank"]) + 1), 64, UI.WHITE, 12)
		var top := base_y - h
		if idx == 0:
			# danse du gagnant : sauts, petits tours sur lui-même, couronne
			var ph := fmod(local, 1.6)
			var jump := -absf(sin(local * 4.0)) * 32.0
			var rot := sin(local * 8.0) * 0.12 if ph < 0.8 else 0.0
			var sc := 0.62 * (1.0 + 0.05 * sin(local * 8.0))
			ci.draw_set_transform(Vector2(x, top + jump), rot, Vector2(sc * (1.0 if fmod(local, 3.2) < 1.6 else -1.0), sc))
			ci.draw_texture(UI.char_tex(int(p["color"]), "jump" if jump < -20.0 else "idle"), Vector2(-128, -256))
			ci.draw_set_transform(Vector2.ZERO)
			_crown(ci, Vector2(x + sin(local * 8.0) * 6.0, top + jump - 150.0), 0.9 + 0.05 * sin(local * 6.0))
		else:
			var bob := -absf(sin(local * 5.0 + idx)) * 10.0
			ci.draw_set_transform(Vector2(x, top + bob), 0.0, Vector2(0.52, 0.52))
			ci.draw_texture(UI.char_tex(int(p["color"]), "idle"), Vector2(-128, -256))
			ci.draw_set_transform(Vector2.ZERO)
		var info := Rect2(Vector2(x - 105, base_y + 12), Vector2(210, 66))
		UI.panel(ci, info, UI.WHITE, col.lightened(0.4), 18, 4)
		UI.text(ci, info.position + Vector2(105, 21), str(p["name"]), 22, col.darkened(0.15), 0)
		_icons(ci, info.position + Vector2(105, 47), int(p["stars"]), int(p["coins"]))
	# le reste du classement
	var others := []
	for i in range(3, r.size()):
		others.append("%de %s : %d étoile(s), %d pièces" % [int(r[i]["rank"]) + 1, str(r[i]["name"]), int(r[i]["stars"]), int(r[i]["coins"])])
	if others.size() > 0:
		UI.text(ci, Vector2(640, 612), "   ·   ".join(others), 18, UI.WHITE, 6)
	# feux d'artifice
	for b in bursts:
		var k: float = float(b["t"]) / 1.6
		for v in b["parts"]:
			var q: Vector2 = b["p"] + (v as Vector2) * k + Vector2(0, 260.0 * k * k)
			ci.draw_circle(q, 5.0 * (1.0 - k) + 1.5, Color(b["c"], 1.0 - k))
			ci.draw_circle(q, 2.0 * (1.0 - k) + 0.5, Color(1, 1, 1, 1.0 - k))
	# confettis
	for c in confetti:
		var cy: float = fmod(float(c["d"]) * 130.0 + local * float(c["v"]), 760.0) - 20.0
		var cx: float = float(c["x"]) + sin(t * 2.0 + float(c["d"])) * 24.0
		ci.draw_set_transform(Vector2(cx, cy), float(c["r"]) + t * 3.0, Vector2.ONE)
		ci.draw_rect(Rect2(Vector2(-c["w"] / 2.0, -c["w"]), Vector2(c["w"], float(c["w"]) * 2.0)), c["c"])
	ci.draw_set_transform(Vector2.ZERO)


func _crown(ci: Control, c: Vector2, s: float) -> void:
	var pts := PackedVector2Array([c + Vector2(-42, 22) * s, c + Vector2(-48, -22) * s, c + Vector2(-22, 0) * s,
		c + Vector2(0, -34) * s, c + Vector2(22, 0) * s, c + Vector2(48, -22) * s, c + Vector2(42, 22) * s])
	var outline := pts.duplicate()
	outline.append(pts[0])
	ci.draw_colored_polygon(pts, Color("#facd2d"))
	ci.draw_polyline(outline, UI.DARK, 5.0)
	ci.draw_rect(Rect2(c + Vector2(-42, 10) * s, Vector2(84, 12) * s), Color("#e0a91c"))
	for k in 3:
		ci.draw_circle(c + Vector2(-26 + k * 26, 16) * s, 5.0 * s, [Color("#f04650"), Color("#4b87f5"), Color("#a3d15d")][k])
	ci.draw_circle(c + Vector2(-48, -22) * s, 5.0 * s, Color.WHITE)
	ci.draw_circle(c + Vector2(0, -34) * s, 5.0 * s, Color.WHITE)
	ci.draw_circle(c + Vector2(48, -22) * s, 5.0 * s, Color.WHITE)


func _icons(ci: Control, c: Vector2, stars: int, coins: int) -> void:
	ci.draw_set_transform(c + Vector2(-56, 0), 0.0, Vector2(0.24, 0.24))
	ci.draw_texture(tex_star, Vector2(-64, -64))
	ci.draw_set_transform(Vector2.ZERO)
	ci.draw_string(UI.font(true), c + Vector2(-42, 8), str(stars), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UI.DARK)
	ci.draw_set_transform(c + Vector2(4, 0), 0.0, Vector2(0.24, 0.24))
	ci.draw_texture(tex_coin, Vector2(-64, -64))
	ci.draw_set_transform(Vector2.ZERO)
	ci.draw_string(UI.font(true), c + Vector2(18, 8), str(coins), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UI.DARK)
