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
		var fy := UI.face_center(row).y
		var md := Vector2(row.position.x + 30, fy)
		if rank < 8:
			(ci as CanvasItem).texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			ci.draw_texture_rect(UI.gui("rank%d" % (rank + 1)), Rect2(md - Vector2(24, 30), Vector2(48, 58)), false, Color(1, 1, 1, appear))
		else:
			ci.draw_circle(md, 22.0, Color(1, 1, 1, appear))
			ci.draw_circle(md, 18.0, Color(mc, appear))
			UI.text(ci, md, str(rank + 1), 24, Color(1, 1, 1, appear), 6)
		# portrait
		var pc := Vector2(row.position.x + 88, fy)
		UI.portrait(ci, pc, 21.0, int(r["color"]), UI.WHITE, Color(1, 1, 1, appear))
		UI.text_left(ci, Vector2(row.position.x + 122, fy), str(r["name"]), 24, Color(1, 1, 1, appear), 6)
		if int(r.get("star", 0)) > 0:
			UI.text_left(ci, Vector2(row.position.x + 316, fy), "+1 ÉTOILE !", 22, Color(UI.YELLOW, appear), 6)
		else:
			UI.text_left(ci, Vector2(row.position.x + 316, fy), str(r["label"]), 20, Color(1, 1, 1, 0.92 * appear), 4, false)
		# pastille des gains : pièce + nombre centrés ensemble
		var pill := Rect2(Vector2(row.position.x + 584, fy - 18), Vector2(104, 36))
		ci.draw_style_box(UI.box(Color(1, 1, 1, appear), Color(0, 0, 0, 0), 0, 18), pill)
		var rw := "%+d" % int(r["reward"])
		var gw := 26.0 + 6.0 + UI.text_width(rw, 24)
		var gx := pill.get_center().x - gw / 2.0
		ci.draw_set_transform(Vector2(gx + 13.0, fy), 0.0, Vector2(0.2, 0.2))
		ci.draw_texture(tex_coin, Vector2(-64, -64), Color(1, 1, 1, appear))
		ci.draw_set_transform(Vector2.ZERO)
		UI.text_left(ci, Vector2(gx + 32.0, fy), rw, 24, Color(UI.RED if int(r["reward"]) < 0 else UI.DARK, appear), 0)
		if int(r.get("star", 0)) > 0:
			var sp := Vector2(row.position.x + 556, fy)
			ci.draw_set_transform(sp, sin(t * 4.0) * 0.2, Vector2(0.36, 0.36) * (1.0 + 0.08 * sin(t * 6.0)))
			ci.draw_texture(tex_star, Vector2(-64, -64))
			ci.draw_set_transform(Vector2.ZERO)
		y += 62.0
	UI.text(ci, Vector2(640, 690), ("Retour au salon dans un instant..." if Net.mg_data.get("practice", false) else "Retour au plateau dans un instant..."), 20, UI.WHITE, 6)
