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
	var sb := UI.box(UI.WHITE, UI.DARK, 4, 16)
	sb.set_content_margin_all(12)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.lbl(msg, 18)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 360
	pc.add_child(l)
	toast_box.add_child(pc)
	toast_box.position = Vector2(1280 - 400 - 20, 90)
	await get_tree().create_timer(4.5).timeout
	if is_instance_valid(pc):
		pc.queue_free()
