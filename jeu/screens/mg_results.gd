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
	ci.draw_style_box(UI.box(UI.WHITE, UI.DARK, 6, 28), panel)
	var duel := str(Net.mg_data.get("mode", "")) == "duel"
	UI.text(ci, Vector2(640, panel.position.y + 52), ("DUEL - " if duel else "") + str(info["name"]), 46, Color("#c79bff") if duel else UI.YELLOW, 12)
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
		ci.draw_style_box(UI.box(Color(col.lerp(Color.WHITE, 0.75), appear) if rank == 0 else Color(UI.PAPER, appear), Color(UI.DARK, appear), 3, 14), row)
		var rank_txt := "1er" if rank == 0 else "%de" % (rank + 1)
		UI.text(ci, row.position + Vector2(40, 27), rank_txt, 26, UI.YELLOW if rank == 0 else UI.DARK, 6 if rank == 0 else 0)
		ci.draw_set_transform(row.position + Vector2(104, 52), 0.0, Vector2(0.2, 0.2))
		ci.draw_texture(UI.char_tex(int(r["color"]), "idle" if rank == 0 else "front"), Vector2(-128, -256))
		ci.draw_set_transform(Vector2.ZERO)
		ci.draw_string(UI.font(true), row.position + Vector2(140, 36), str(r["name"]), HORIZONTAL_ALIGNMENT_LEFT, 200, 24, col.darkened(0.2))
		if int(r.get("star", 0)) > 0:
			UI.text(ci, row.position + Vector2(440, 27), "+1 ÉTOILE !", 22, UI.YELLOW, 6)
		else:
			ci.draw_string(UI.font(), row.position + Vector2(350, 36), str(r["label"]), HORIZONTAL_ALIGNMENT_LEFT, 220, 20, UI.GREY)
		ci.draw_set_transform(row.position + Vector2(600, 27), 0.0, Vector2(0.3, 0.3))
		ci.draw_texture(tex_coin, Vector2(-64, -64))
		ci.draw_set_transform(Vector2.ZERO)
		ci.draw_string(UI.font(true), row.position + Vector2(622, 37), "%+d" % int(r["reward"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UI.RED if int(r["reward"]) < 0 else UI.DARK)
		if int(r.get("star", 0)) > 0:
			var sp := row.position + Vector2(556, 27)
			ci.draw_set_transform(sp, sin(t * 4.0) * 0.2, Vector2(0.36, 0.36) * (1.0 + 0.08 * sin(t * 6.0)))
			ci.draw_texture(tex_star, Vector2(-64, -64))
			ci.draw_set_transform(Vector2.ZERO)
		y += 62.0
	UI.text(ci, Vector2(640, 690), ("Retour au salon dans un instant..." if Net.mg_data.get("practice", false) else "Retour au plateau dans un instant..."), 20, UI.WHITE, 6)
