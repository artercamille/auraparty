extends Control
## Ciel en dégradé + calques du pack Kenney qui défilent (effet de profondeur).

var mode := "hills"   # "hills" (menus) ou "sky" (arène au-dessus des nuages)
var t := 0.0
var clouds: Texture2D = load("res://assets/bg/layer_clouds.png")
var hills: Texture2D = load("res://assets/bg/layer_hills.png")
var puffs := []


func _init(m := "hills") -> void:
	mode = m
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 6:
		puffs.append({"x": randf() * 1500.0, "y": randf_range(60, 260), "s": randf_range(0.6, 1.2), "v": randf_range(8, 22)})


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _strip(tex: Texture2D, y: float, h: float, speed: float, alpha := 1.0) -> void:
	var sc := h / tex.get_height()
	var w := tex.get_width() * sc
	var x := fposmod(-t * speed, w) - w
	while x < size.x:
		draw_texture_rect(tex, Rect2(Vector2(floorf(x), y), Vector2(ceilf(w) + 1.0, h)), false, Color(1, 1, 1, alpha))
		x += w


func _puff(c: Vector2, s: float, a: float) -> void:
	var col := Color(1, 1, 1, a)
	for b in [[-46, 8, 30], [-14, -10, 40], [26, -2, 34], [52, 10, 24], [0, 14, 36]]:
		draw_circle(c + Vector2(b[0], b[1]) * s, b[2] * s, col)


func _draw() -> void:
	var top := Color("#5fb2ff")
	var bot := Color("#d2ebff")
	var steps := 32
	for i in steps:
		draw_rect(Rect2(0, floorf(size.y * i / steps), size.x, ceilf(size.y / steps) + 1), top.lerp(bot, float(i) / (steps - 1)))
	for p in puffs:
		var x: float = fposmod(float(p["x"]) + t * float(p["v"]), size.x + 300.0) - 150.0
		_puff(Vector2(x, float(p["y"])), float(p["s"]), 0.75)
	if mode == "hills":
		_strip(clouds, size.y - 560.0, 520.0, 6.0, 0.8)
		_strip(hills, size.y - 470.0, 560.0, 16.0)
	else:
		_strip(clouds, size.y - 600.0, 560.0, 5.0, 0.55)
		_strip(clouds, size.y - 470.0, 560.0, 12.0)
