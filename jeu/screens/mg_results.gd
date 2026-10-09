extends Control
## Résultats d'un mini-jeu : classement et pièces gagnées.

const Backdrop := preload("res://screens/backdrop.gd")

var t := 0.0
var tex_coin: Texture2D = load("res://assets/tiles/coin_gold.png")
var tex_star: Texture2D = load("res://assets/tiles/star.png")
var played_sfx := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(Backdrop.new("hills"))
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.draw.connect(_draw_results.bind(layer))
	add_child(layer)


func _process(delta: float) -> void:
	t += delta
	for c in get_children():
		c.queue_redraw()


func _draw_results(ci: Control) -> void:
	var info: Dictionary = Net.MINIGAMES.get(str(Net.mg_data.get("type", "")), {"name": "Mini-jeu"})
	var res: Array = Net.mg_results
	var rows := res.size()
	var h := 120.0 + rows * 62.0
	var panel := Rect2(Vector2(250, 360 - h / 2.0 - 20), Vector2(780, h + 40))
	UI.panel(ci, panel, UI.WHITE, Color("#ece9fb"), 30, 6)
	var duel := str(Net.mg_data.get("mode", "")) == "duel"
	UI.ribbon(ci, Vector2(640, panel.position.y + 8), ("DUEL - " if duel else "") + str(info["name"]), 38, Color("#8a4fd8") if duel else Color("#8e6cf0"), UI.YELLOW)
	var y := panel.position.y + 104
	for i in rows:
		var r: Dictionary = res[i]
		var appear := clampf((t - 0.4 - i * 0.22) * 5.0, 0.0, 1.0)
		if appear <= 0.0:
			break
		if played_sfx <= i:
			played_sfx = i + 1
			Sfx.play("chip", -4.0, 0.1)
		var rank := int(r["rank"])
		var x0 := 290.0 + (1.0 - appear) * 50.0
		var row := Rect2(Vector2(x0, y), Vector2(700, 54))
		var col: Color = Net.COLORS[int(r["color"])]
		UI.panel(ci, row, Color(col.lightened(0.1), appear), Color(1, 1, 1, appear), 20, 5)
		# médaille
		var mc: Color = [Color("#ffc93c"), Color("#c9d3e3"), Color("#e8a061")][rank] if rank < 3 else Color("#9aa3b8")
		var md := row.position + Vector2(34, 27)
		ci.draw_circle(md, 22.0, Color(1, 1, 1, appear))
		ci.draw_circle(md, 18.0, Color(mc, appear))
		UI.text(ci, md, str(rank + 1), 24, Color(1, 1, 1, appear), 6)
		# portrait
		var pc := row.position + Vector2(92, 27)
		ci.draw_circle(pc, 23.0, Color(1, 1, 1, appear))
		ci.draw_circle(pc, 19.0, Color(col.darkened(0.18), appear))
		ci.draw_texture_rect_region(UI.char_tex(int(r["color"]), "front"), Rect2(pc - Vector2(18, 19), Vector2(36, 32)), Rect2(66, 104, 124, 96), Color(1, 1, 1, appear))
		UI.text(ci, row.position + Vector2(196, 27), str(r["name"]), 24, Color(1, 1, 1, appear), 6)
		if int(r.get("star", 0)) > 0:
			UI.text(ci, row.position + Vector2(440, 27), "+1 ÉTOILE !", 22, UI.YELLOW, 6)
		else:
			ci.draw_string(UI.font(), row.position + Vector2(330, 36), str(r["label"]), HORIZONTAL_ALIGNMENT_LEFT, 240, 20, Color(1, 1, 1, 0.92 * appear))
		var pill := Rect2(row.position + Vector2(584, 9), Vector2(104, 36))
		ci.draw_style_box(UI.box(Color(1, 1, 1, appear), Color(0, 0, 0, 0), 0, 18), pill)
		ci.draw_set_transform(pill.position + Vector2(22, 18), 0.0, Vector2(0.24, 0.24))
		ci.draw_texture(tex_coin, Vector2(-64, -64), Color(1, 1, 1, appear))
		ci.draw_set_transform(Vector2.ZERO)
		ci.draw_string(UI.font(true), pill.position + Vector2(42, 27), "%+d" % int(r["reward"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(UI.RED if int(r["reward"]) < 0 else UI.DARK, appear))
		if int(r.get("star", 0)) > 0:
			var sp := row.position + Vector2(556, 27)
			ci.draw_set_transform(sp, sin(t * 4.0) * 0.2, Vector2(0.36, 0.36) * (1.0 + 0.08 * sin(t * 6.0)))
			ci.draw_texture(tex_star, Vector2(-64, -64))
			ci.draw_set_transform(Vector2.ZERO)
		y += 62.0
	UI.text(ci, Vector2(640, 690), ("Retour au salon dans un instant..." if Net.mg_data.get("practice", false) else "Retour au plateau dans un instant..."), 20, UI.WHITE, 6)
