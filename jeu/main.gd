extends Control
## Change d'écran selon la phase et affiche les notifications.

const SCREENS := {
	"menu": "res://screens/menu.gd",
	"lobby": "res://screens/lobby.gd",
	"board": "res://board/board.gd",
	"mg_results": "res://screens/mg_results.gd",
	"final": "res://screens/final.gd",
}

var current: Node
var toast_box: VBoxContainer


func _ready() -> void:
	theme = UI.make_theme()
	UI.warm_cache()
	get_window().title = "Aura PARTY"
	get_window().min_size = Vector2i(960, 540)
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	toast_box = VBoxContainer.new()
	toast_box.theme = theme
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_theme_constant_override("separation", 8)
	layer.add_child(toast_box)
	Net.state_changed.connect(_on_state)
	Net.toast.connect(_show_toast)
	_on_state(Net.phase)


func _on_state(s: String) -> void:
	var path: String = SCREENS.get(s, "")
	if s == "minigame":
		path = str(Net.MINIGAMES.get(str(Net.mg_data.get("type", "")), {}).get("path", ""))
	if path == "":
		return
	if current:
		current.queue_free()
	current = load(path).new()
	add_child(current)
	move_child(current, 0)
	if s in ["board", "minigame", "mg_results", "final", "lobby"]:
		_iris_open()
	var shots := OS.get_environment("SHOTS")
	if shots != "":
		var delays := [2.0]
		if s == "board":
			delays = [1.0, 6.0, 12.0]
			if OS.get_environment("BOARD_DELAYS") != "":
				delays = Array(OS.get_environment("BOARD_DELAYS").split(",")).map(func(x): return float(x))
		elif s == "minigame":
			delays = [2.0, 9.0, 13.0, 18.0]
			if OS.get_environment("SHOT_DELAYS") != "":
				delays = Array(OS.get_environment("SHOT_DELAYS").split(",")).map(func(x): return float(x))
		elif s == "mg_results" or s == "final":
			delays = [3.0]
			if OS.get_environment("SHOT_DELAYS") != "":
				delays = Array(OS.get_environment("SHOT_DELAYS").split(",")).map(func(x): return float(x))
		for d in delays:
			_shot(shots, "%06d_%s%s" % [Time.get_ticks_msec(), s, ("_" + str(Net.mg_data.get("type", ""))) if s == "minigame" else ""], d)


func _shot(dir: String, n: String, d: float) -> void:
	await get_tree().create_timer(d, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s_%d.png" % [dir, n, int(d)])


func _show_toast(msg: String) -> void:
	var pc := PanelContainer.new()
	var sb := UI.KitBox.new()
	sb.col = UI.PAPER
	sb.radius = 16
	sb.set_content_margin_all(12)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.lbl(msg, 18, UI.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 300
	pc.add_child(l)
	toast_box.add_child(pc)
	# en mini-jeu : sur l'aperçu (l'encart Commandes reste lisible) ; ailleurs : à droite
	toast_box.position = Vector2(90, 112) if Net.phase == "minigame" else Vector2(1280 - 340 - 20, 400)
	await get_tree().create_timer(4.5).timeout
	if is_instance_valid(pc):
		pc.queue_free()


# ------------------------------------------------------------------ transition « rond » façon Mario Party
var _iris: ColorRect


func _iris_open() -> void:
	if _iris == null:
		var layer := CanvasLayer.new()
		layer.layer = 60
		add_child(layer)
		_iris = ColorRect.new()
		_iris.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_iris.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = """shader_type canvas_item;
uniform float r = 0.0;
void fragment() {
	vec2 p = (UV - 0.5) * vec2(1.7778, 1.0);
	float d = length(p);
	COLOR = vec4(0.05, 0.04, 0.08, 1.0 - smoothstep(r - 0.004, r + 0.004, d));
	COLOR.a = 1.0 - COLOR.a;
}"""
		var m := ShaderMaterial.new()
		m.shader = sh
		_iris.material = m
		layer.add_child(_iris)
	_iris.visible = true
	var mat := _iris.material as ShaderMaterial
	mat.set_shader_parameter("r", 0.0)
	var tw := create_tween()
	tw.tween_method(func(v): mat.set_shader_parameter("r", v), 0.0, 1.15, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): _iris.visible = false)
