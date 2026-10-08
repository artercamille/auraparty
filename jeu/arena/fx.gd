extends Node2D
## Effets : poussière, anneaux, étoiles, gros "PAF" quand quelqu'un tombe, tremblement d'écran.

var parts: Array = []
var star_tex: Texture2D = load("res://assets/tiles/star.png")
var shake_amt := 0.0
var world: Node2D


func _ready() -> void:
	z_index = 20


func dust(p: Vector2, n: int, size := 1.0) -> void:
	for i in n:
		parts.append({"k": "dust", "p": p + Vector2(randf_range(-14, 14), randf_range(-4, 2)),
			"v": Vector2(randf_range(-90, 90), randf_range(-70, -20)), "t": 0.0, "life": randf_range(0.35, 0.5), "s": randf_range(7, 12) * size})


func ring(p: Vector2, col: Color) -> void:
	parts.append({"k": "ring", "p": p, "t": 0.0, "life": 0.35, "c": col})


func stars(p: Vector2, n: int) -> void:
	for i in n:
		var a := randf() * TAU
		parts.append({"k": "star", "p": p, "v": Vector2(cos(a), sin(a)) * randf_range(180, 320), "t": 0.0, "life": 0.5, "r": randf() * TAU})
	parts.append({"k": "flash", "p": p, "t": 0.0, "life": 0.15})


func splash(x: float, col: Color, label: String, y := 690.0) -> void:
	parts.append({"k": "splash", "p": Vector2(x, y), "t": 0.0, "life": 1.3, "c": col, "txt": label})
	for i in 10:
		parts.append({"k": "dust", "p": Vector2(x + randf_range(-40, 40), y + 10.0), "v": Vector2(randf_range(-160, 160), randf_range(-420, -200)),
			"t": 0.0, "life": randf_range(0.5, 0.8), "s": randf_range(12, 22)})
	shake(10.0)


func splat(p: Vector2, col: Color, n: int) -> void:
	for i in n:
		var a := randf_range(PI * 1.05, PI * 1.95)
		parts.append({"k": "splat", "p": p, "v": Vector2(cos(a), sin(a)) * randf_range(140, 320), "t": 0.0,
			"life": randf_range(0.35, 0.55), "s": randf_range(5, 10), "c": col})


func popup(p: Vector2, txt: String, col: Color) -> void:
	parts.append({"k": "pop", "p": p, "t": 0.0, "life": 1.1, "c": col, "txt": txt})


func shake(a: float) -> void:
	shake_amt = maxf(shake_amt, a)


func _process(delta: float) -> void:
	for p in parts:
		p["t"] += delta
		if p.has("v"):
			var v: Vector2 = p["v"]
			p["p"] += v * delta
			if p["k"] == "dust":
				v *= 0.9
				v.y -= 30.0 * delta
			elif p["k"] == "star":
				v *= 0.88
				p["r"] += delta * 8.0
			elif p["k"] == "splat":
				v.y += 900.0 * delta
			p["v"] = v
	parts = parts.filter(func(p): return p["t"] < p["life"])
	if world:
		shake_amt = move_toward(shake_amt, 0.0, delta * 40.0)
		world.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amt
	queue_redraw()


func _draw() -> void:
	for p in parts:
		var k: float = p["t"] / p["life"]
		match p["k"]:
			"dust":
				draw_circle(p["p"], p["s"] * (0.6 + k * 0.8), Color(1, 1, 1, 0.85 * (1.0 - k)))
			"splat":
				draw_circle(p["p"], p["s"] * (1.0 - k * 0.5) + 2.0, Color(UI.DARK, 1.0 - k))
				draw_circle(p["p"], p["s"] * (1.0 - k * 0.5), Color(p["c"], 1.0 - k))
			"ring":
				var c: Color = p["c"]
				draw_arc(p["p"], 14.0 + k * 34.0, 0, TAU, 32, Color(UI.DARK, 1.0 - k), 9.0 * (1.0 - k) + 2.0)
				draw_arc(p["p"], 14.0 + k * 34.0, 0, TAU, 32, Color(c, 1.0 - k), 5.0 * (1.0 - k) + 1.0)
			"star":
				var s := 0.22 * (1.0 - k * 0.5)
				draw_set_transform(p["p"], p["r"], Vector2(s, s))
				draw_texture(star_tex, Vector2(-64, -64), Color(1, 1, 1, 1.0 - k * k))
				draw_set_transform(Vector2.ZERO)
			"flash":
				draw_circle(p["p"], 30.0 + k * 30.0, Color(1, 1, 1, 0.9 * (1.0 - k)))
			"splash":
				var c: Color = p["c"]
				var grow := minf(1.0, k * 6.0)
				draw_circle(p["p"], 70.0 * grow, Color(c, 0.35 * (1.0 - k)))
				var wob := 1.0 + sin(k * 30.0) * 0.08 * (1.0 - k)
				UI.text(self, p["p"] + Vector2(0, -60.0 - k * 50.0), p["txt"], int(46 * wob * grow + 1), c, 12)
			"pop":
				UI.text(self, p["p"] + Vector2(0, -k * 60.0), p["txt"], 28, p["c"], 9)
