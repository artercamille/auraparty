extends Node
## Réseau + règles. L'hôte (id 1) décide de tout (dés, cases, étoile, classements),
## les autres affichent. Chaque joueur pilote son propre perso dans les mini-jeux.

signal players_changed
signal state_changed(state: String)
signal toast(msg: String)
# plateau
# mini-jeux
signal remote_state(id: int, pos: Vector2, vel: Vector2, st: int)
signal got_hit(kind: int, dir: Vector2, from_id: int)
signal hit_fx(pos: Vector2, kind: int)
signal mg_player_out(id: int, how: String)
signal mg_ending
signal mg_ready_changed(ids: Array)
signal mg_go
signal mg_msg(from_id: int, data: Dictionary)   # reçu par l'hôte
signal mg_state(data: Dictionary)               # envoyé par l'hôte à tous

const VERSION := "0.19"
const PORT := 7777
const MAX_PLAYERS := 8
const COLOR_IDS := ["rouge", "orange", "jaune", "vert", "turquoise", "bleu", "violet", "rose"]
const COLORS := [
	Color("#e0404a"), Color("#ff8a1e"), Color("#f5c400"), Color("#5bba4d"),
	Color("#3fb8bd"), Color("#6f9fe0"), Color("#a57ce0"), Color("#ee86a8"),
]
const STAR_COST := 20
const START_COINS := 10
const DICE_MAX := 10
const ROLL_TIMEOUT := 15.0
const READY_MAX := 20.0
const REPO := "artercamille/auraparty"   # "proprietaire/depot" sur GitHub : le jeu y vérifie s'il existe une version plus récente
const REWARDS := [8, 5, 3, 2, 1, 1, 0, 0]
const MINIGAMES := {
	"blocks": {"name": "Gare aux blocs !", "path": "res://minigames/blocks.gd", "max": 60.0},
	"paint": {"name": "Coup de tampon !", "path": "res://minigames/paint.gd", "max": 50.0},
	"keys": {"name": "La bonne clé !", "path": "res://minigames/keys.gd", "max": 60.0},
	"parcours": {"name": "Le grand parcours !", "path": "res://minigames/parcours.gd", "max": 75.0},
	"rock": {"name": "Le rocher fou !", "path": "res://minigames/rock.gd", "max": 55.0},
	"logs": {"name": "Défilé de bûches !", "path": "res://minigames/logs.gd", "max": 65.0},
	"quiz": {"name": "Quiz sous le chapiteau !", "path": "res://minigames/quiz.gd", "max": 95.0},
	"kart": {"name": "Grand Prix Aura !", "path": "res://minigames/kart.gd", "max": 165.0},
	"triathlon": {"name": "Mini-triathlon !", "path": "res://minigames/triathlon.gd", "max": 110.0},
	"rocket": {"name": "Fusées en folie !", "path": "res://minigames/rocket.gd", "max": 95.0},
	"mushroom": {"name": "Champi-couleurs !", "path": "res://minigames/mushroom.gd", "max": 80.0},
	"bumper": {"name": "Boules-tamponneuses !", "path": "res://minigames/bumper.gd", "max": 80.0},
}

var my_name := ""
var my_color_wish := -1
var players: Dictionary = {}   # id -> {name, color, coins, stars, pos, ping}
var phase := "menu"
var autotest := ""

# état de partie (copié chez tout le monde)
var order: Array = []
var round_num := 1
var total_rounds := 10
var star_pos := 20
var mg_data: Dictionary = {}
var mg_results: Array = []
var final_ranking: Array = []

# hôte uniquement
var _gen := 0
var _kick_msg := ""
var _ping_acc := 0.0
var _mg_id := 0
var _mg_running := false
var _mg_out: Dictionary = {}     # id -> [temps tenu, comment]
var _mg_final: Dictionary = {}   # id -> [score, texte] fourni par le mini-jeu
var _mg_ending := false
var _last_mg := ""
var _recent_mg: Array = []   # mini-jeux déjà joués dans la partie (pioche : pas de répétition avant d'avoir tout joué)
var practice := false   # mini-jeu lancé depuis le salon (sans plateau)
var opt_bonus := true      # étoiles bonus à la fin
var opt_excluded: Array = []   # mini-jeux retirés par l'hôte
var _last_order: Array = []
var bonus_awards: Array = []
var mg_ready_ids: Array = []
var _mg_go_sent := false
var mg_parts: Array = []   # joueurs qui participent au mini-jeu en cours (tous, ou les 2 du duel)


func _ready() -> void:
	randomize()
	_setup_inputs()
	load_party_options()
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	var args := OS.get_cmdline_user_args()
	if "--checkall" in args:
		for f in ["res://main.gd", "res://ui.gd", "res://screens/menu.gd", "res://screens/lobby.gd",
				"res://game.gd", "res://board/board.gd", "res://board/map.gd", "res://board/items.gd", "res://board/island.gd", "res://minigames/stage.gd", "res://minigames/blocks.gd",
				"res://minigames/paint.gd", "res://minigames/keys.gd", "res://minigames/parcours.gd", "res://minigames/rock.gd", "res://minigames/logs.gd", "res://minigames/quiz.gd", "res://minigames/kart.gd", "res://minigames/triathlon.gd", "res://minigames/rocket.gd", "res://minigames/mushroom.gd", "res://minigames/bumper.gd",
				"res://arena/player.gd", "res://arena/fx.gd", "res://screens/backdrop.gd",
				"res://screens/mg_results.gd", "res://screens/final.gd"]:
			var s = load(f)
			print("CHECK ", f, " -> ", "OK" if s != null and s.can_instantiate() else "FAIL")
		get_tree().quit.call_deferred()
	for a in args:
		if a.begins_with("--debug-screen="):
			_debug_data()
			_set_phase_local.call_deferred(a.split("=")[1])
		if a.begins_with("--autotest-host"):
			autotest = "host"
			Engine.time_scale = float(OS.get_environment("SPEED")) if OS.get_environment("SPEED") != "" else 1.0
			host_game.call_deferred("Hote")
		elif a.begins_with("--autotest-join"):
			autotest = "join"
			Engine.time_scale = float(OS.get_environment("SPEED")) if OS.get_environment("SPEED") != "" else 1.0
			join_game.call_deferred("Bot%d" % randi_range(10, 99), "127.0.0.1")


func _debug_data() -> void:
	players = {1: {"name": "Camille", "color": 2, "coins": 25, "stars": 2, "pos": 9, "ping": 0, "items": ["double", "boo"]},
		2: {"name": "Lucas", "color": 0, "coins": 12, "stars": 1, "pos": 9, "ping": 40, "items": ["mushroom"]},
		3: {"name": "Inès", "color": 5, "coins": 30, "stars": 1, "pos": 14, "ping": 80, "items": []},
		4: {"name": "Tom", "color": 6, "coins": 4, "stars": 0, "pos": 0, "ping": 60, "items": ["pipe", "poison", "swap"]}}
	order = [1, 2, 3, 4]
	mg_data = {"type": "blocks", "seed": 7, "players": [1, 2, 3, 4]}
	mg_results = [{"id": 1, "name": "Camille", "color": 2, "rank": 0, "label": "Survivant !", "reward": 10},
		{"id": 2, "name": "Lucas", "color": 0, "rank": 1, "label": "Tenu 41.2 s", "reward": 6},
		{"id": 3, "name": "Inès", "color": 5, "rank": 2, "label": "Tenu 30.0 s", "reward": 4},
		{"id": 4, "name": "Tom", "color": 6, "rank": 3, "label": "Tenu 12.5 s", "reward": 3}]
	bonus_awards = [{"title": "Roi des mini-jeux", "desc": "le plus de mini-jeux gagnés", "value": 4, "who": [{"id": 1, "name": "Camille", "color": 2}]},
		{"title": "Pas de chance", "desc": "le plus de cases rouges", "value": 3, "who": [{"id": 2, "name": "Lucas", "color": 0}, {"id": 4, "name": "Tom", "color": 6}]}]
	final_ranking = [{"id": 1, "name": "Camille", "color": 2, "rank": 0, "stars": 2, "coins": 25},
		{"id": 3, "name": "Inès", "color": 5, "rank": 1, "stars": 1, "coins": 30},
		{"id": 2, "name": "Lucas", "color": 0, "rank": 2, "stars": 1, "coins": 12},
		{"id": 4, "name": "Tom", "color": 6, "rank": 3, "stars": 0, "coins": 4}]


func _process(delta: float) -> void:
	if not is_host() or players.size() < 2:
		return
	_ping_acc += delta
	if _ping_acc < 3.0:
		return
	_ping_acc = 0.0
	var peer := multiplayer.multiplayer_peer
	if not (peer is ENetMultiplayerPeer):
		return
	var changed := false
	for id in players:
		if id == 1:
			continue
		var pp: ENetPacketPeer = peer.get_peer(id)
		if pp:
			var ping := int(pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
			if absi(ping - int(players[id].get("ping", 0))) > 5:
				players[id]["ping"] = ping
				changed = true
	if changed and phase == "lobby":
		_broadcast_players()


# ---------------------------------------------------------------- commandes
func _setup_inputs() -> void:
	_add("left", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_add("right", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_add("up", [KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP], JOY_AXIS_LEFT_Y, -1.0)
	_add("down", [KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN], JOY_AXIS_LEFT_Y, 1.0)
	_add("jump", [KEY_SPACE, KEY_W, KEY_UP], [JOY_BUTTON_A], -1, 0.0)
	_add("push", [KEY_SHIFT, KEY_X, KEY_E, KEY_J], [JOY_BUTTON_X, JOY_BUTTON_B], -1, 0.0)
	_add("menu", [KEY_ESCAPE], [JOY_BUTTON_START], -1, 0.0)
	_add("fullscreen", [KEY_F11], [], -1, 0.0)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("push", mb)


func _add(action: String, keys: Array, joy: Array, axis: int, axis_val: float) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.35)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k   # touches physiques : ZQSD en AZERTY = WASD en QWERTY
		InputMap.action_add_event(action, e)
	for b in joy:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(action, jb)
	if axis >= 0:
		var jm := InputEventJoypadMotion.new()
		jm.axis = axis
		jm.axis_value = axis_val
		InputMap.action_add_event(action, jm)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen"):
		toggle_fullscreen()


func toggle_fullscreen() -> void:
	var w := get_window()
	w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


# ---------------------------------------------------------------- utilitaires
func my_id() -> int:
	return multiplayer.get_unique_id()


func is_host() -> bool:
	return multiplayer.is_server()


func color_idx(id: int) -> int:
	return int(players[id]["color"]) if players.has(id) else 0


func color_of(id: int) -> Color:
	return COLORS[color_idx(id)]


func name_of(id: int) -> String:
	return str(players[id]["name"]) if players.has(id) else "?"


func local_ips() -> Dictionary:
	var radmin := []
	var other := []
	for a in IP.get_local_addresses():
		if ":" in a or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		if a.begins_with("26."):
			radmin.append(a)
		else:
			other.append(a)
	return {"radmin": radmin, "other": other}


func ranking_key(id: int) -> int:
	return int(players[id]["stars"]) * 100000 + int(players[id]["coins"])


func _later(t: float, f: Callable) -> void:
	var g := _gen
	await get_tree().create_timer(t).timeout
	if g == _gen and is_host():
		f.call()


# ---------------------------------------------------------------- connexion
func host_game(n: String) -> bool:
	leave(false)
	my_name = n
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_PLAYERS) != OK:
		toast.emit("Impossible de créer la partie : le port %d est peut-être déjà utilisé." % PORT)
		_set_phase_local("menu")
		return false
	multiplayer.multiplayer_peer = peer
	players.clear()
	_add_player(1, n, my_color_wish)
	_set_phase_local("lobby")
	_maybe_autostart()
	return true


func join_game(n: String, ip: String) -> bool:
	leave(false)
	my_name = n
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, PORT) != OK:
		toast.emit("Adresse IP invalide.")
		_set_phase_local("menu")
		return false
	multiplayer.multiplayer_peer = peer
	phase = "connecting"
	return true


func leave(go_menu := true) -> void:
	_gen += 1
	var p := multiplayer.multiplayer_peer
	if p != null and not (p is OfflineMultiplayerPeer):
		p.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	order.clear()
	_mg_running = false
	Game.stop()
	if go_menu:
		_set_phase_local("menu")


func _on_connected_ok() -> void:
	_register.rpc_id(1, my_name, VERSION, my_color_wish)


func _on_connection_failed() -> void:
	leave()
	toast.emit("Connexion impossible. Vérifie l'IP de l'hôte et que vous êtes tous sur le même réseau Radmin VPN.")


func _on_server_disconnected() -> void:
	var m := _kick_msg if _kick_msg != "" else "L'hôte a fermé la partie."
	_kick_msg = ""
	leave()
	toast.emit(m)


func _on_peer_disconnected(id: int) -> void:
	if not is_host() or not players.has(id):
		return
	var n := name_of(id)
	players.erase(id)
	var idx := order.find(id)
	if idx != -1:
		order.remove_at(idx)
		if idx < Game.turn_idx:
			Game.turn_idx -= 1
	_broadcast_players()
	_toast.rpc("%s a quitté la partie." % n)
	_check_all_ready()
	if phase == "board":
		Game.player_left(id)
	elif phase == "minigame" and _mg_running:
		_check_mg_end()


@rpc("any_peer", "call_remote", "reliable")
func _register(n: String, ver: String, wish: int) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if ver != VERSION:
		_kick(id, "Tu n'as pas la même version du jeu que l'hôte (v%s). Récupère la dernière version !" % VERSION)
		return
	if phase != "lobby":
		_kick(id, "La partie a déjà commencé, attends la prochaine !")
		return
	if players.size() >= MAX_PLAYERS:
		_kick(id, "La partie est pleine (8 joueurs max).")
		return
	_add_player(id, n, wish)
	_set_phase.rpc_id(id, phase)
	_toast.rpc("%s a rejoint la partie !" % name_of(id))


func _kick(id: int, msg: String) -> void:
	_kicked.rpc_id(id, msg)
	await get_tree().create_timer(0.4).timeout
	var p := multiplayer.multiplayer_peer
	if p is ENetMultiplayerPeer:
		p.disconnect_peer(id)


@rpc("authority", "call_remote", "reliable")
func _kicked(msg: String) -> void:
	_kick_msg = msg


func _add_player(id: int, n: String, wish: int) -> void:
	n = n.strip_edges().substr(0, 14)
	if n == "":
		n = "Joueur"
	var base := n
	var k := 2
	var taken := true
	while taken:
		taken = false
		for o in players:
			if str(players[o]["name"]) == n:
				taken = true
		if taken:
			n = "%s %d" % [base, k]
			k += 1
	var used := _used_colors()
	var c := wish if wish >= 0 and wish < 8 and wish not in used else 0
	while c in used:
		c += 1
	players[id] = {"name": n, "color": c, "coins": START_COINS, "stars": 0, "pos": 0, "ping": 0}
	_broadcast_players()
	_maybe_autostart()


func _maybe_autostart() -> void:
	var need := int(OS.get_environment("AUTOTEST_PLAYERS")) if OS.get_environment("AUTOTEST_PLAYERS") != "" else 2
	if autotest == "host" and phase == "lobby" and players.size() >= need:
		var rounds := int(OS.get_environment("ROUNDS")) if OS.get_environment("ROUNDS") != "" else 2
		if OS.get_environment("PRACTICE") != "":
			_later(1.0, func(): start_practice(OS.get_environment("PRACTICE")))
			return
		_later(1.0, func(): start_game(rounds))


func _used_colors() -> Array:
	var used := []
	for o in players:
		used.append(int(players[o]["color"]))
	return used


func next_color() -> void:
	if is_host():
		_change_color(1)
	else:
		_request_color.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_color() -> void:
	if is_host():
		_change_color(multiplayer.get_remote_sender_id())


func _change_color(id: int) -> void:
	if not players.has(id) or phase != "lobby":
		return
	var used := _used_colors()
	var c := int(players[id]["color"])
	for i in 8:
		c = (c + 1) % 8
		if c not in used:
			players[id]["color"] = c
			break
	_broadcast_players()


func _broadcast_players() -> void:
	_sync.rpc(players, order, star_pos, round_num, total_rounds)
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _sync(p: Dictionary, o: Array, star: int, rnd: int, total: int) -> void:
	players = p
	order = o
	star_pos = star
	round_num = rnd
	total_rounds = total
	if players.has(my_id()):
		my_color_wish = int(players[my_id()]["color"])
	players_changed.emit()


@rpc("authority", "call_local", "reliable")
func _toast(msg: String) -> void:
	toast.emit(msg)


@rpc("authority", "call_local", "reliable")
func _set_phase(p: String) -> void:
	_set_phase_local(p)


func _set_phase_local(p: String) -> void:
	phase = p
	print("[phase] ", p)
	state_changed.emit(p)


# ---------------------------------------------------------------- partie
func start_game(rounds: int) -> void:
	if not is_host() or phase != "lobby":
		return
	_gen += 1
	practice = false
	total_rounds = rounds
	round_num = 1
	order = players.keys()
	order.shuffle()
	var start_coins := int(OS.get_environment("START_COINS")) if autotest != "" and OS.get_environment("START_COINS") != "" else START_COINS
	for id in players:
		players[id]["coins"] = start_coins
		players[id]["stars"] = 0
		players[id]["mg_wins"] = 0
		players[id]["coins_won"] = 0
		players[id]["reds"] = 0
		players[id]["steps"] = 0
		players[id]["used"] = 0
	_last_order = []
	_last_mg = ""
	_recent_mg.clear()
	Game.reset()
	_broadcast_players()
	_set_phase.rpc("board")
	_later(3.0, Game.start_round)


## Salon -> un mini-jeu précis, sans plateau (pour tester). Retour au salon après les résultats.
func start_practice(t: String) -> void:
	if not is_host() or phase != "lobby" or not MINIGAMES.has(t):
		return
	_gen += 1
	practice = true
	_start_minigame(t)


func back_to_lobby() -> void:
	if not is_host():
		return
	_gen += 1
	_mg_running = false
	Game.stop()
	order.clear()
	_broadcast_players()
	_set_phase.rpc("lobby")


# ---------------------------------------------------------------- mini-jeux
## Fin du tour de table : mini-jeu pour tout le monde.
func start_round_minigame() -> void:
	if is_host() and phase == "board":
		_start_minigame()


## Duel 1 contre 1 sur le plateau : le gagnant prend `stake` pièces au perdant.
func start_duel(a: int, b: int, stake: int) -> void:
	if not is_host() or phase != "board":
		return
	var types := MINIGAMES.keys()
	types.erase("kart")   # trop long pour un duel
	_drop_recent(types, false)   # (si seul le kart reste dans la pioche, on ne la vide pas)
	_start_minigame(types.pick_random(), [a, b], "duel", stake)


## Pioche : on retire les mini-jeux déjà joués. Quand tout est passé, on repart de zéro
## (sans reprendre celui qu'on vient juste de jouer).
func load_party_options() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		opt_bonus = bool(cfg.get_value("party", "bonus", true))
		opt_excluded = Array(cfg.get_value("party", "excluded", []))


func save_party_options() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("party", "bonus", opt_bonus)
	cfg.set_value("party", "excluded", opt_excluded)
	cfg.save("user://settings.cfg")


func _drop_recent(types: Array, can_reset := true) -> void:
	# mini-jeux retirés par l'hôte (s'il en reste au moins un)
	var kept := types.duplicate()
	for x in opt_excluded:
		kept.erase(x)
	if kept.size() > 0:
		types.clear()
		types.append_array(kept)
	var left := types.duplicate()
	for r in _recent_mg:
		left.erase(r)
	if left.is_empty():
		if can_reset:
			_recent_mg.clear()
		left = types.duplicate()
		if left.size() > 1:
			left.erase(_last_mg)
	types.clear()
	types.append_array(left)


func _start_minigame(force := "", parts: Array = [], mode := "round", stake := 0) -> void:
	var types := MINIGAMES.keys()
	_drop_recent(types)
	var t: String = types.pick_random()
	if force != "":
		t = force
	if autotest != "" and OS.get_environment("MG") != "" and mode != "duel":
		t = OS.get_environment("MG")
	if autotest != "" and OS.get_environment("DUEL_MG") != "" and mode == "duel":
		t = OS.get_environment("DUEL_MG")
	_last_mg = t
	if autotest != "":
		print("[mg] ", t, " ", mode)
	if not practice and not _recent_mg.has(t):
		_recent_mg.append(t)
	_mg_id += 1
	var my_mg := _mg_id
	_mg_out.clear()
	_mg_final.clear()
	_mg_running = true
	_mg_ending = false
	mg_ready_ids = []
	_mg_go_sent = false
	mg_parts = parts.duplicate() if parts.size() > 0 else players.keys()
	_begin_minigame.rpc({"type": t, "seed": randi(), "players": mg_parts, "practice": practice, "mode": mode, "stake": stake})
	# départ quand tout le monde est prêt, ou au bout de READY_MAX secondes
	_later(READY_MAX, func(): if my_mg == _mg_id: _send_go())
	var g := _gen
	await get_tree().create_timer(READY_MAX + 4.0 + float(MINIGAMES[t]["max"]) + 10.0).timeout
	if g == _gen and _mg_running and my_mg == _mg_id:
		_finish_minigame()


## Les participants encore connectés.
func mg_alive_parts() -> Array:
	var out := []
	for id in mg_parts:
		if players.has(id):
			out.append(id)
	return out


@rpc("authority", "call_local", "reliable")
func _begin_minigame(d: Dictionary) -> void:
	mg_ready_ids = []
	mg_data = d
	mg_parts = d.get("players", [])
	_set_phase_local("minigame")


## « Prêt ! » avant chaque mini-jeu.
func mg_set_ready() -> void:
	if is_host():
		_on_ready(1)
	else:
		_ready_up.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _ready_up() -> void:
	if is_host():
		_on_ready(multiplayer.get_remote_sender_id())


func _on_ready(id: int) -> void:
	if not _mg_running or _mg_go_sent or mg_ready_ids.has(id) or not mg_parts.has(id):
		return
	mg_ready_ids.append(id)
	_ready_state.rpc(mg_ready_ids)
	_check_all_ready()


func _check_all_ready() -> void:
	if not is_host() or not _mg_running or _mg_go_sent:
		return
	for pid in mg_alive_parts():
		if not mg_ready_ids.has(pid):
			return
	_send_go()


func _send_go() -> void:
	if _mg_go_sent or not _mg_running:
		return
	_mg_go_sent = true
	_mg_go.rpc()


@rpc("authority", "call_local", "reliable")
func _ready_state(ids: Array) -> void:
	mg_ready_ids = ids
	mg_ready_changed.emit(ids)


@rpc("authority", "call_local", "reliable")
func _mg_go() -> void:
	mg_go.emit()


## L'hôte exclut un joueur du salon.
func kick_player(id: int) -> void:
	if is_host() and id != 1 and players.has(id):
		_kick(id, "L'hôte t'a exclu de la partie.")


## Messages libres des mini-jeux : joueur -> hôte, et hôte -> tout le monde.
func mg_to_host(data: Dictionary) -> void:
	if is_host():
		mg_msg.emit(1, data)
	else:
		_mg_up.rpc_id(1, data)


@rpc("any_peer", "call_remote", "reliable")
func _mg_up(data: Dictionary) -> void:
	if is_host():
		mg_msg.emit(multiplayer.get_remote_sender_id(), data)


func mg_broadcast(data: Dictionary) -> void:
	if is_host():
		_mg_down.rpc(data)


@rpc("authority", "call_local", "reliable")
func _mg_down(data: Dictionary) -> void:
	mg_state.emit(data)


## Mon perso est éliminé (écrasé, tombé...) après avoir tenu `held` secondes.
func report_out(held: float, how: String) -> void:
	if is_host():
		_on_out(1, held, how)
	else:
		_report_out.rpc_id(1, held, how)


@rpc("any_peer", "call_remote", "reliable")
func _report_out(held: float, how: String) -> void:
	if is_host():
		_on_out(multiplayer.get_remote_sender_id(), held, how)


func _on_out(id: int, held: float, how: String) -> void:
	if not _mg_running or _mg_out.has(id) or not players.has(id) or not mg_parts.has(id):
		return
	_mg_out[id] = [held, how]
	_out_announce.rpc(id, how)
	_check_mg_end()


@rpc("authority", "call_local", "reliable")
func _out_announce(id: int, how: String) -> void:
	mg_player_out.emit(id, how)


## Fin du chrono (jeux d'élimination : les survivants gagnent).
func report_time_up() -> void:
	if is_host() and _mg_running and not _mg_ending:
		_mg_ending = true
		_mg_end_soon.rpc()
		_later(2.0, _finish_minigame)


## Fin avec des scores calculés par le mini-jeu : id -> [score (plus haut = mieux), texte].
func mg_end_with_scores(scores: Dictionary) -> void:
	if not is_host() or not _mg_running or _mg_ending:
		return
	_mg_final = scores
	_mg_ending = true
	_mg_end_soon.rpc()
	_later(2.2, _finish_minigame)


func _check_mg_end() -> void:
	if not _mg_running or _mg_ending:
		return
	var alive := 0
	var parts := mg_alive_parts()
	for id in parts:
		if not _mg_out.has(id):
			alive += 1
	if alive == 0 or (mg_parts.size() >= 2 and alive <= 1):
		_mg_ending = true
		_mg_end_soon.rpc()
		_later(2.2, _finish_minigame)


@rpc("authority", "call_local", "reliable")
func _mg_end_soon() -> void:
	mg_ending.emit()


func _finish_minigame() -> void:
	if not _mg_running:
		return
	_mg_running = false
	var duel := str(mg_data.get("mode", "round")) == "duel"
	var stake := int(mg_data.get("stake", 0))
	var max_t := float(MINIGAMES[str(mg_data.get("type", "blocks"))]["max"])
	var score := func(id) -> float:
		if not _mg_final.is_empty():
			return float(_mg_final[id][0]) if _mg_final.has(id) else -1.0e9
		return float(_mg_out[id][0]) if _mg_out.has(id) else max_t + 1000.0
	var ids := mg_alive_parts()
	ids.sort_custom(func(a, b): return score.call(a) > score.call(b))
	var results := []
	var rank := 0
	var tie := duel and ids.size() == 2 and absf(score.call(ids[0]) - score.call(ids[1])) <= 0.05
	for i in ids.size():
		var id: int = ids[i]
		if i > 0 and absf(score.call(id) - score.call(ids[i - 1])) > 0.05:
			rank = i
		var reward: int = REWARDS[mini(rank, REWARDS.size() - 1)]
		var star_bonus := 0
		if duel:
			reward = 0
			if not tie and ids.size() == 2:
				var loser: int = ids[1]
				var real := mini(stake, int(players[loser]["coins"]))
				reward = real if i == 0 else -real
			players[id]["coins"] = maxi(0, int(players[id]["coins"]) + reward)
			if reward > 0:
				players[id]["coins_won"] = int(players[id].get("coins_won", 0)) + reward
		elif not practice:
			players[id]["coins"] = int(players[id]["coins"]) + reward
			players[id]["coins_won"] = int(players[id].get("coins_won", 0)) + reward
			if rank == 0:
				players[id]["mg_wins"] = int(players[id].get("mg_wins", 0)) + 1
				if round_num >= total_rounds:
					star_bonus = 1
					players[id]["stars"] = int(players[id]["stars"]) + 1
		var label := "Survivant !"
		if not _mg_final.is_empty():
			label = str(_mg_final[id][1]) if _mg_final.has(id) else "-"
		elif _mg_out.has(id):
			label = "Tenu %.1f s" % float(_mg_out[id][0])
		results.append({"id": id, "name": name_of(id), "color": color_idx(id), "rank": rank, "label": label, "reward": reward, "star": star_bonus})
	if not duel:
		_last_order = ids.duplicate()
	_broadcast_players()
	_show_mg_results.rpc(results)
	_later(7.5, _after_minigame)


@rpc("authority", "call_local", "reliable")
func _show_mg_results(r: Array) -> void:
	mg_results = r
	_set_phase_local("mg_results")


func _after_minigame() -> void:
	if practice:
		practice = false
		_broadcast_players()
		_set_phase.rpc("lobby")
		return
	if str(mg_data.get("mode", "round")) == "duel":
		_broadcast_players()
		_set_phase.rpc("board")
		Game.on_duel_finished()
		return
	round_num += 1
	if round_num > total_rounds:
		_end_game()
		return
	# le gagnant du mini-jeu joue en premier, puis dans l'ordre du classement
	var new_order := []
	for id in _last_order:
		if players.has(id):
			new_order.append(id)
	for id in order:
		if players.has(id) and not new_order.has(id):
			new_order.append(id)
	order = new_order
	_broadcast_players()
	_set_phase.rpc("board")
	_later(2.5, Game.start_round)


func _end_game() -> void:
	var awards := []
	for a in ([] if not opt_bonus else [["mg_wins", "Roi des mini-jeux", "le plus de mini-jeux gagnés"],
			["coins_won", "Pluie de pièces", "le plus de pièces gagnées"],
			["reds", "Pas de chance", "le plus de cases rouges"]]):
		var best := 0
		for id in players:
			best = maxi(best, int(players[id].get(a[0], 0)))
		if best <= 0:
			continue
		var winners := []
		for id in players:
			if int(players[id].get(a[0], 0)) == best:
				winners.append({"id": id, "name": name_of(id), "color": color_idx(id)})
				players[id]["stars"] = int(players[id]["stars"]) + 1
		awards.append({"title": a[1], "desc": a[2], "value": best, "who": winners})
	var ids := players.keys()
	ids.sort_custom(func(a, b): return ranking_key(a) > ranking_key(b))
	var ranking := []
	var rank := 0
	for i in ids.size():
		var id: int = ids[i]
		if i > 0 and ranking_key(id) != ranking_key(ids[i - 1]):
			rank = i
		ranking.append({"id": id, "name": name_of(id), "color": color_idx(id), "rank": rank,
			"stars": int(players[id]["stars"]), "coins": int(players[id]["coins"])})
	_game_over.rpc(ranking, awards)


@rpc("authority", "call_local", "reliable")
func _game_over(r: Array, awards: Array = []) -> void:
	final_ranking = r
	bonus_awards = awards
	_set_phase_local("final")
	if autotest != "":
		print("AUTOTEST_OK ", autotest, " ", r)
		await get_tree().create_timer(3.0).timeout
		get_tree().quit()


# ---------------------------------------------------------------- persos en temps réel
func send_state(pos: Vector2, vel: Vector2, st: int) -> void:
	_st.rpc(pos, vel, st)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _st(pos: Vector2, vel: Vector2, st: int) -> void:
	remote_state.emit(multiplayer.get_remote_sender_id(), pos, vel, st)


func send_hit(victim: int, kind: int, dir: Vector2) -> void:
	_hit.rpc_id(victim, kind, dir)


@rpc("any_peer", "call_remote", "reliable")
func _hit(kind: int, dir: Vector2) -> void:
	got_hit.emit(kind, dir, multiplayer.get_remote_sender_id())


func send_fx(pos: Vector2, kind: int) -> void:
	_hitfx.rpc(pos, kind)


@rpc("any_peer", "call_remote", "unreliable")
func _hitfx(pos: Vector2, kind: int) -> void:
	hit_fx.emit(pos, kind)
