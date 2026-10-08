extends "res://minigames/stage.gd"
## « Coup de tampon ! » : on saute et on retombe pour peindre le sol à sa couleur.
## Grande arène (2 écrans de large) avec caméra qui suit et mini-carte des territoires.
## Piqué (↓ en l'air) = tampon plus large. L'hôte arbitre à qui appartient chaque case.

const W := 2560.0
const H := 1088.0
const GROUND := 944.0
# [x0 en cases, hauteur, nombre de cases, type]
const LAYOUT := [
	[1, 944.0, 16, "island"], [23, 944.0, 16, "island"],
	[16, 816.0, 7, "thin"],
	[4, 768.0, 5, "thin"], [31, 768.0, 5, "thin"],
	[11, 656.0, 4, "thin"], [25, 656.0, 4, "thin"],
	[6, 528.0, 4, "thin"], [17, 560.0, 6, "thin"], [30, 528.0, 4, "thin"],
	[12, 400.0, 4, "thin"], [24, 400.0, 4, "thin"],
	[18, 272.0, 4, "thin"],
]

var platforms: Array = []   # {x0, y, n, first}
var tiles: Array = []       # {x, y, owner, at}
var paint_layer: Node2D
var was_floor := true
var air_t := 0.0
var air_vy := 0.0


func _setup() -> void:
	title = "Coup de tampon !"
	rules = "Saute et retombe sur le sol pour le peindre à ta couleur !\nAppuie sur ↓ en l'air pour foncer : ton tampon est plus large.\nLe plus grand territoire à la fin gagne. Tomber = tu réapparais."
	controls = "Bouger : Q D / ← →   ·   Sauter : Espace (x2)   ·   Piqué : ↓   ·   Pousser : Maj / X"
	duration = 50.0
	respawn_on_fall = true
	show_heads = false
	follow_cam = true
	cam_limits = Rect2(0, 0, W, H)
	for x in [200, 420, 640, 860, 1700, 1920, 2140, 2360]:
		spawn_points.append(Vector2(x, GROUND))
	respawn_points = [Vector2(1216, 272), Vector2(832, 400), Vector2(1600, 400)]


func _build_level() -> void:
	var deco := [[3, "bush"], [9, "mushroom_red"], [14, "bush"], [26, "bush"], [33, "rock"], [36, "mushroom_brown"]]
	for d in deco:
		tile(d[1], Vector2(int(d[0]) * T, GROUND - T))
	tile("flag_red_a", Vector2(19 * T + 32, 272 - T))
	for p in LAYOUT:
		if p[3] == "island":
			island(p[0], p[1], p[2])
		else:
			thin(p[0], p[1], p[2])
		_add_platform(p[0], p[1], p[2])
	spring(2, GROUND)
	spring(37, GROUND)
	paint_layer = Node2D.new()
	paint_layer.z_index = 2
	world.add_child(paint_layer)
	paint_layer.draw.connect(_draw_paint)


func _on_start() -> void:
	if me:
		me.kill_rect = Rect2(-200, -2000, W + 400.0, 3200.0)


func _add_platform(x0: int, y: float, n: int) -> void:
	platforms.append({"x0": x0 * T, "y": y, "n": n, "first": tiles.size()})
	for i in n:
		tiles.append({"x": (x0 + i) * T, "y": y, "owner": 0, "at": -10.0})


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state != "play" or me == null or me.dead:
		was_floor = true
		return
	var on_floor := me.is_on_floor()
	if not on_floor:
		air_t += delta
		air_vy = maxf(air_vy, me.velocity.y)
	elif not was_floor:
		if air_t > 0.12:
			_stamp(2 if air_vy > 1250.0 else 1)
		air_t = 0.0
		air_vy = 0.0
	was_floor = on_floor


func _stamp(radius: int) -> void:
	for pf in platforms:
		var y: float = pf["y"]
		var x0: float = pf["x0"]
		var n: int = pf["n"]
		if absf(me.position.y - y) > 14.0 or me.position.x < x0 - 12.0 or me.position.x > x0 + n * T + 12.0:
			continue
		var c := clampi(int((me.position.x - x0) / T), 0, n - 1)
		var ids := []
		for i in range(c - radius, c + radius + 1):
			if i >= 0 and i < n:
				var tid: int = int(pf["first"]) + i
				ids.append(tid)
				_set_owner(tid, Net.my_id())
		if ids.size() > 0:
			Net.mg_to_host({"stamp": ids})
			fx.splat(me.position, me.color(), 8 + radius * 6)
			if radius > 1:
				fx.shake(4.0)
				Sfx.play("bump", -6.0, 0.15)
			else:
				Sfx.play("coin", -14.0, 0.2)
		return


func _set_owner(tid: int, owner: int) -> void:
	if tid < 0 or tid >= tiles.size():
		return
	if int(tiles[tid]["owner"]) != owner:
		tiles[tid]["owner"] = owner
		tiles[tid]["at"] = play_t


# côté hôte : on applique les tampons dans l'ordre d'arrivée et on prévient tout le monde
func _on_mg_msg(from_id: int, data: Dictionary) -> void:
	if not data.has("stamp") or state == "intro":
		return
	var flat := []
	for tid in data["stamp"]:
		flat.append(int(tid))
		flat.append(from_id)
	Net.mg_broadcast({"paint": flat})


func _on_mg_state(data: Dictionary) -> void:
	if data.has("paint"):
		var flat: Array = data["paint"]
		for i in range(0, flat.size(), 2):
			_set_owner(int(flat[i]), int(flat[i + 1]))


func counts() -> Dictionary:
	var c := {}
	for id in nodes:
		c[id] = 0
	for tl in tiles:
		var o := int(tl["owner"])
		if c.has(o):
			c[o] += 1
	return c


func host_scores() -> Dictionary:
	var c := counts()
	var out := {}
	for id in c:
		out[id] = [float(c[id]), "%d case%s" % [c[id], "s" if c[id] > 1 else ""]]
	return out


func _process(delta: float) -> void:
	super._process(delta)
	paint_layer.queue_redraw()


func _draw_paint() -> void:
	for tl in tiles:
		var o := int(tl["owner"])
		if o == 0 or not Net.players.has(o):
			continue
		var col := Net.color_of(o)
		var k := clampf((play_t - float(tl["at"])) / 0.22, 0.0, 1.0)
		var grow := 0.55 + 0.45 * (1.0 - pow(1.0 - k, 3.0))
		var x: float = tl["x"]
		var y: float = tl["y"]
		var w := 62.0 * grow
		var r := Rect2(Vector2(x + 32.0 - w / 2.0, y + 3.0), Vector2(w, 24.0))
		paint_layer.draw_style_box(UI.box(col, col.darkened(0.4), 3, 10), r)
		paint_layer.draw_circle(Vector2(x + 18.0, y + 26.0), 5.0 * grow, col)
		paint_layer.draw_circle(Vector2(x + 44.0, y + 28.0), 4.0 * grow, col)
		paint_layer.draw_rect(Rect2(Vector2(x + 32.0 - w / 2.0 + 6.0, y + 7.0), Vector2(w * 0.4, 4.0)), Color(1, 1, 1, 0.35))


func _draw_extra_hud() -> void:
	draw_timer()
	if state == "intro":
		return
	# classement des territoires en direct
	var c := counts()
	var ids := c.keys()
	ids.sort_custom(func(a, b): return c[a] > c[b])
	var total := maxi(1, tiles.size())
	var w := 104.0
	var x0 := 640.0 - ids.size() * (w + 8.0) / 2.0
	for i in ids.size():
		var id: int = ids[i]
		var r := Rect2(Vector2(x0 + i * (w + 8.0), 18), Vector2(w, 52))
		var col := Net.color_of(id)
		hud.draw_style_box(UI.box(UI.WHITE, UI.DARK, 4, 14), r)
		var fill := minf(1.0, float(c[id]) / total * 3.0)
		if fill > 0.0:
			hud.draw_style_box(UI.box(col.lerp(Color.WHITE, 0.45), col, 0, 10), Rect2(r.position + Vector2(4, 4), Vector2((w - 8) * fill, 44)))
		hud.draw_set_transform(r.position + Vector2(24, 48), 0.0, Vector2(0.17, 0.17))
		hud.draw_texture(UI.char_tex(Net.color_idx(id), "idle"), Vector2(-128, -256))
		hud.draw_set_transform(Vector2.ZERO)
		UI.text(hud, r.position + Vector2(72, 26), str(c[id]), 26, col.darkened(0.2), 0)
		if id == Net.my_id():
			hud.draw_rect(Rect2(r.position + Vector2(10, 56), Vector2(w - 20, 5)), col)
	# mini-carte (en bas à droite)
	var s := 0.1
	var mr := Rect2(Vector2(1280 - 24 - W * s - 16, 720 - 24 - H * s - 16), Vector2(W * s + 16, H * s + 16))
	hud.draw_style_box(UI.box(Color(1, 1, 1, 0.92), UI.DARK, 4, 12), mr)
	var o := mr.position + Vector2(8, 8)
	for tl in tiles:
		var ow := int(tl["owner"])
		var col2 := Net.color_of(ow) if ow != 0 and Net.players.has(ow) else Color("#c9cde0")
		hud.draw_rect(Rect2(o + Vector2(float(tl["x"]), float(tl["y"])) * s, Vector2(T * s - 0.6, 5.0)), col2)
	for id in nodes:
		var n: Player = nodes[id]
		if n.visible:
			var pp: Vector2 = o + (n.position + Vector2(0, -30)) * s
			hud.draw_circle(pp, 4.5 if id == Net.my_id() else 3.5, UI.DARK)
			hud.draw_circle(pp, 3.0 if id == Net.my_id() else 2.2, Net.color_of(id))
	if cam:
		var vc := cam.get_screen_center_position()
		var vr := Rect2(o + (vc - Vector2(640, 360)) * s, Vector2(1280, 720) * s)
		hud.draw_rect(vr, Color(UI.DARK, 0.6), false, 1.5)
