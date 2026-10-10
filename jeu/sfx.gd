extends Node
## Bruitages (packs Kenney) et musique (morceaux libres de droits, FreePD).
## La musique change toute seule selon l'écran ; touche M pour la couper.

const FILES := {
	"jump": "res://assets/sfx/sfx_jump.ogg",
	"jump2": "res://assets/sfx/sfx_jump-high.ogg",
	"bump": "res://assets/sfx/sfx_bump.ogg",
	"hurt": "res://assets/sfx/sfx_hurt.ogg",
	"fall": "res://assets/sfx/sfx_disappear.ogg",
	"select": "res://assets/sfx/sfx_select.ogg",
	"spawn": "res://assets/sfx/sfx_magic.ogg",
	"whoosh": "res://assets/sfx/sfx_throw.ogg",
	"coin": "res://assets/sfx/sfx_coin.ogg",
	"gem": "res://assets/sfx/sfx_gem.ogg",
	"dice_throw": "res://assets/sfx/dice_throw.ogg",
	"dice_shuffle": "res://assets/sfx/dice_shuffle.ogg",
	"die_hit": "res://assets/sfx/die_hit.ogg",
	"card_slide": "res://assets/sfx/card_slide.ogg",
	"card_place": "res://assets/sfx/card_place.ogg",
	"card_fan": "res://assets/sfx/card_fan.ogg",
	"chips": "res://assets/sfx/chips.ogg",
	"chips_handle": "res://assets/sfx/chips_handle.ogg",
	"chip": "res://assets/sfx/chip.ogg",
	"ui_move": "res://assets/sfx/ui_move.ogg",
	"ui_ok": "res://assets/sfx/ui_ok.ogg",
	"ui_back": "res://assets/sfx/ui_back.ogg",
	"ui_error": "res://assets/sfx/ui_error.ogg",
	"ui_open": "res://assets/sfx/ui_open.ogg",
	"ui_question": "res://assets/sfx/ui_question.ogg",
	"ui_drop": "res://assets/sfx/ui_drop.ogg",
	"ui_tick": "res://assets/sfx/ui_tick.ogg",
	"jingle_turn": "res://assets/sfx/jingle_turn.ogg",
	"jingle_star": "res://assets/sfx/jingle_star.ogg",
	"jingle_good": "res://assets/sfx/jingle_good.ogg",
	"jingle_bad": "res://assets/sfx/jingle_bad.ogg",
	"jingle_duel": "res://assets/sfx/jingle_duel.ogg",
	"jingle_item": "res://assets/sfx/jingle_item.ogg",
	"step1": "res://assets/sfx/step1.ogg",
	"step2": "res://assets/sfx/step2.ogg",
	"bell": "res://assets/sfx/bell.ogg",
	"voice_ready": "res://assets/sfx/voice_ready.ogg",
	"voice_go": "res://assets/sfx/voice_go.ogg",
	"voice_1": "res://assets/sfx/voice_1.ogg",
	"voice_2": "res://assets/sfx/voice_2.ogg",
	"voice_3": "res://assets/sfx/voice_3.ogg",
	"voice_game_over": "res://assets/sfx/voice_game_over.ogg",
	"voice_you_win": "res://assets/sfx/voice_you_win.ogg",
	"voice_you_lose": "res://assets/sfx/voice_you_lose.ogg",
	"voice_congratulations": "res://assets/sfx/voice_congratulations.ogg",
	"voice_final_round": "res://assets/sfx/voice_final_round.ogg",
	"voice_time_over": "res://assets/sfx/voice_time_over.ogg",
	"voice_its_a_tie": "res://assets/sfx/voice_its_a_tie.ogg",
	"voice_hurry_up": "res://assets/sfx/voice_hurry_up.ogg",
	"voice_round": "res://assets/sfx/voice_round.ogg",
}

const MUSIC := {
	"menu": "res://assets/music/menu.ogg",
	"board1": "res://assets/music/board1.ogg",
	"board2": "res://assets/music/board2.ogg",
	"board3": "res://assets/music/board3.ogg",
	"mg1": "res://assets/music/mg1.ogg",
	"mg2": "res://assets/music/mg2.ogg",
	"mg3": "res://assets/music/mg3.ogg",
	"mg4": "res://assets/music/mg4.ogg",
	"mg5": "res://assets/music/mg5.ogg",
	"kart": "res://assets/music/kart.ogg",
	"duel": "res://assets/music/duel.ogg",
	"quiz": "res://assets/music/quiz.ogg",
	"results": "res://assets/music/results.ogg",
	"final": "res://assets/music/final.ogg",
}
const MUSIC_DB := -9.0

var streams := {}
var pool: Array[AudioStreamPlayer] = []
var idx := 0
var music_on := true
var music_vol := 0.8   # 0..1
var sfx_vol := 0.9
var _mus: Array[AudioStreamPlayer] = []
var _cur := 0
var _cur_name := ""
var _last_mg := ""
var _fade := {}   # joueur -> [volume visé, vitesse]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for k in FILES:
		streams[k] = load(FILES[k])
	for i in 16:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.volume_db = -80.0
		add_child(m)
		_mus.append(m)
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		music_on = bool(cfg.get_value("audio", "music", true))
		music_vol = float(cfg.get_value("audio", "music_vol", 0.8))
		sfx_vol = float(cfg.get_value("audio", "sfx_vol", 0.9))
	if OS.get_cmdline_user_args().has("--checkall") or DisplayServer.get_name() == "headless":
		music_on = false
	Net.state_changed.connect(_on_phase)
	_on_phase.call_deferred(Net.phase)
	# petit bouton « musique » cliquable, en bas à droite de tous les écrans
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	var b := MusicButton.new()
	b.sfx = self
	layer.add_child(b)


func play(name: String, volume_db := 0.0, pitch_var := 0.08) -> void:
	if not streams.has(name):
		return
	var p := pool[idx]
	idx = (idx + 1) % pool.size()
	p.stream = streams[name]
	if sfx_vol <= 0.01:
		return
	p.volume_db = volume_db - 4.0 + linear_to_db(sfx_vol)
	p.pitch_scale = randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	p.play()


## Petite voix (pas de variation de hauteur).
func voice(name: String, volume_db := 0.0) -> void:
	play("voice_" + name, volume_db + 2.0, 0.0)


# ------------------------------------------------------------------ musique
func _unhandled_input(event: InputEvent) -> void:
	# touche M (selon la disposition du clavier : marche en AZERTY comme en QWERTY)
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_M or k.key_label == KEY_M:
			toggle_music()


func music_db() -> float:
	return MUSIC_DB + linear_to_db(maxf(0.02, music_vol * 1.25))


## Règle les volumes (0..1), appliqué tout de suite et retenu pour la prochaine fois.
func set_volumes(m: float, s: float) -> void:
	music_vol = clampf(m, 0.0, 1.0)
	sfx_vol = clampf(s, 0.0, 1.0)
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("audio", "music_vol", music_vol)
	cfg.set_value("audio", "sfx_vol", sfx_vol)
	cfg.save("user://settings.cfg")
	if music_on and _mus[_cur].playing:
		_fade.erase(_mus[_cur])
		_mus[_cur].volume_db = music_db() if music_vol > 0.01 else -80.0


func toggle_music() -> void:
	music_on = not music_on
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("audio", "music", music_on)
	cfg.save("user://settings.cfg")
	if music_on:
		var n := _cur_name
		_cur_name = ""
		music(n if n != "" else "menu")
	else:
		_fade_to(_mus[_cur], -80.0, 3.0)
	Net.toast.emit("Musique activée" if music_on else "Musique coupée (M pour la remettre)")


## Change de morceau en fondu (rien si c'est déjà celui-là).
func music(name: String, loop := true) -> void:
	if name == _cur_name:
		return
	_cur_name = name
	if not music_on:
		return
	var old := _mus[_cur]
	_fade_to(old, -80.0, 1.2)
	if name == "" or not MUSIC.has(name):
		return
	_cur = 1 - _cur
	var p := _mus[_cur]
	var st = load(MUSIC[name])
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = loop
	p.stream = st
	p.volume_db = -30.0
	p.play()
	_fade_to(p, music_db(), 1.0)


func _fade_to(p: AudioStreamPlayer, target: float, dur: float) -> void:
	_fade[p] = [target, absf(target - p.volume_db) / maxf(0.05, dur)]


func _process(delta: float) -> void:
	for p in _fade.keys():
		var a: Array = _fade[p]
		p.volume_db = move_toward(p.volume_db, float(a[0]), float(a[1]) * delta)
		if is_equal_approx(p.volume_db, float(a[0])):
			_fade.erase(p)
			if float(a[0]) <= -79.0:
				p.stop()


func _on_phase(ph: String) -> void:
	match ph:
		"menu", "lobby":
			music("menu")
		"board":
			music("board%d" % (((Net.round_num - 1) % 3) + 1))
		"minigame":
			var t := str(Net.mg_data.get("type", ""))
			if str(Net.mg_data.get("mode", "")) == "duel":
				music("duel")
			elif t == "kart":
				music("kart")
			elif t == "quiz":
				music("quiz")
			else:
				var opts := ["mg1", "mg2", "mg3", "mg4", "mg5"]
				opts.erase(_last_mg)
				var pick: String = opts[(int(Net.mg_data.get("seed", 0)) % opts.size() + opts.size()) % opts.size()]
				_last_mg = pick
				music(pick)
		"mg_results":
			music("results", false)
		"final":
			music("final")


## Bouton rond avec une note de musique (barrée quand la musique est coupée).
class MusicButton extends Control:
	var sfx: Node
	var hover := false

	func _ready() -> void:
		size = Vector2(44, 44)
		position = Vector2(1280 - 56, 720 - 56)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "Couper / remettre la musique (M)"
		mouse_entered.connect(func(): hover = true; queue_redraw())
		mouse_exited.connect(func(): hover = false; queue_redraw())

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			sfx.toggle_music()
			accept_event()

	func _process(_d: float) -> void:
		# caché pendant les mini-jeux (il recouvrait des infos en bas à droite) ; la touche M marche toujours
		visible = Net.phase != "minigame"
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var on: bool = sfx.music_on
		draw_circle(c + Vector2(0, 3), 21.0, Color(0.13, 0.1, 0.25, 0.25))
		draw_circle(c, 21.0, Color.WHITE)
		draw_circle(c, 17.0, Color("#8e6cf0") if on else Color("#9aa0b4"))
		if hover:
			draw_circle(c, 17.0, Color(1, 1, 1, 0.15))
		# note de musique
		var w := Color.WHITE
		draw_circle(c + Vector2(-5, 7), 5.0, w)
		draw_line(c + Vector2(-1, 7), c + Vector2(-1, -9), w, 3.0)
		draw_line(c + Vector2(-1, -9), c + Vector2(8, -5), w, 3.0)
		if not on:
			draw_line(c + Vector2(-11, -11), c + Vector2(11, 11), Color("#ff5a5a"), 4.0)
