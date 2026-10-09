extends Node
## Règles du plateau, décidées par l'hôte : tours, dés, objets, choix de route, cases spéciales,
## étoile, banque, boutique et duels. Tout le monde reçoit les événements (signal `event`)
## et le plateau les met en scène. Les joueurs répondent aux questions avec send_request().

signal event(d: Dictionary)
signal emote_shown(id: int, name: String)

const ACTION_TIMEOUT := 15.0
const CHOICE_TIMEOUT := 12.0
const STAR_COST := 20
const DUEL_STAKE := 10
const BANK_FEE := 5

# état partagé (copie chez tout le monde)
var star_node := 30
var bank := 0
var cur := 0
var turn_idx := 0
var ask: Dictionary = {}

# hôte
var rng := RandomNumberGenerator.new()
var _flow := 0
var _ans = null
var _ask_id := 0
var _ask_what := ""
var _duel_done := false
var _forced_i := 0


func _ready() -> void:
	rng.randomize()
	BoardMap.build()


# ------------------------------------------------------------------ réseau
func _send(d: Dictionary) -> void:
	d["star"] = star_node
	d["bank"] = bank
	d["cur"] = cur
	d["players"] = Net.players
	_ev.rpc(d)


@rpc("authority", "call_local", "reliable")
func _ev(d: Dictionary) -> void:
	star_node = int(d.get("star", star_node))
	bank = int(d.get("bank", bank))
	cur = int(d.get("cur", cur))
	if d.has("players") and not Net.is_host():
		Net.players = d["players"]
		Net.players_changed.emit()
	var k := str(d.get("k", ""))
	ask = d if k == "ask" else {}
	if Net.autotest != "" and Net.is_host():
		var dd := d.duplicate()
		dd.erase("players")
		print("[game] ", Time.get_ticks_msec() / 1000, " ", dd)
	event.emit(d)
	if Net.autotest != "" and int(d.get("id", 0)) == Net.my_id() and k == "ask":
		_bot_answer(d)


## Un joueur répond à la question en cours (action, route, boutique, duel).
func send_request(d: Dictionary) -> void:
	if Net.is_host():
		_on_request(1, d)
	else:
		_req.rpc_id(1, d)


@rpc("any_peer", "call_remote", "reliable")
func _req(d: Dictionary) -> void:
	if Net.is_host():
		_on_request(multiplayer.get_remote_sender_id(), d)


func _on_request(from: int, d: Dictionary) -> void:
	if from != _ask_id or _ans != null or str(d.get("what", "")) != _ask_what:
		return
	_ans = d


func _wait(s: float, flow: int) -> bool:
	await get_tree().create_timer(s).timeout
	return flow == _flow and Net.phase in ["board", "minigame", "mg_results"]


func _ask_and_wait(id: int, what: String, payload: Dictionary, timeout: float, flow: int):
	_ask_id = id
	_ask_what = what
	_ans = null
	var d := payload.duplicate()
	d["k"] = "ask"
	d["id"] = id
	d["what"] = what
	d["timeout"] = timeout
	_send(d)
	var t := 0.0
	while _ans == null and t < timeout and flow == _flow and Net.players.has(id):
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	_ask_id = 0
	_ask_what = ""
	var a = _ans
	_ans = null
	return a


## Émotes envoyées par les joueurs sur le plateau (touches 1 à 6).
func send_emote(name: String) -> void:
	_emote.rpc(name)


@rpc("any_peer", "call_local", "unreliable")
func _emote(name: String) -> void:
	var from := multiplayer.get_remote_sender_id()
	if from == 0:
		from = Net.my_id()
	if Net.players.has(from):
		emote_shown.emit(from, name)


# ------------------------------------------------------------------ partie
func reset() -> void:
	_flow += 1
	bank = 0
	cur = 0
	turn_idx = 0
	ask = {}
	for id in Net.players:
		var p: Dictionary = Net.players[id]
		p["pos"] = BoardMap.start()
		p["items"] = []
		p["poison"] = false
	star_node = _new_star(BoardMap.start(), 9, 22)


## Arrête tout ce que l'hôte était en train de faire (retour salon, déconnexion).
func stop() -> void:
	_flow += 1
	cur = 0
	ask = {}
	_ask_id = 0
	_ans = null


func start_round() -> void:
	if not Net.is_host():
		return
	_flow += 1
	turn_idx = 0
	_next_turn(_flow)


func player_left(id: int) -> void:
	if Net.is_host() and cur == id and Net.phase == "board":
		_flow += 1
		turn_idx = maxi(0, turn_idx)
		_next_turn(_flow)


func _next_turn(flow: int) -> void:
	if flow != _flow or not Net.is_host():
		return
	while turn_idx < Net.order.size() and not Net.players.has(Net.order[turn_idx]):
		turn_idx += 1
	if turn_idx >= Net.order.size():
		cur = 0
		var last := Net.round_num >= Net.total_rounds
		_send({"k": "announce", "text": "Dernier mini-jeu : le gagnant remporte une ÉTOILE !" if last else "Place au mini-jeu !"})
		if not await _wait(3.2 if last else 2.4, flow):
			return
		Net.start_round_minigame()
		return
	_turn(Net.order[turn_idx], flow)


func _turn(id: int, flow: int) -> void:
	cur = id
	_send({"k": "turn", "id": id, "round": Net.round_num, "total": Net.total_rounds})
	if not await _wait(0.6, flow):
		return
	var mods := {"dice": 1, "bonus": 0, "fixed": 0}
	var used := false
	var skip_roll := false
	while true:
		var a = await _ask_and_wait(id, "action", {"used": used}, ACTION_TIMEOUT, flow)
		if flow != _flow:
			return
		if a != null and str(a.get("do", "")) == "item" and not used:
			var r: String = await _use_item(id, a, mods, flow)
			if flow != _flow:
				return
			if r == "":
				continue
			used = true
			if r == "end":
				skip_roll = true
				break
			continue
		break
	if not skip_roll and Net.players.has(id):
		var p: Dictionary = Net.players[id]
		var vals := []
		var poison: bool = p.get("poison", false)
		p["poison"] = false
		if int(mods["fixed"]) > 0:
			vals.append(int(mods["fixed"]))
		else:
			for i in int(mods["dice"]):
				vals.append(rng.randi_range(1, 3 if poison else 10))
		var total := int(mods["bonus"])
		for v in vals:
			total += int(v)
		_send({"k": "roll", "id": id, "dice": vals, "bonus": mods["bonus"], "total": total, "poison": poison})
		if not await _wait(1.5 + 0.35 * vals.size(), flow):
			return
		await _move(id, total, flow)
		if flow != _flow:
			return
		if Net.players.has(id):
			await _land(id, flow)
			if flow != _flow:
				return
	_send({"k": "end", "id": id})
	if not await _wait(0.9, flow):
		return
	turn_idx += 1
	_next_turn(flow)


# ------------------------------------------------------------------ déplacement
func _move(id: int, steps: int, flow: int) -> void:
	while steps > 0 and flow == _flow and Net.players.has(id):
		var p: Dictionary = Net.players[id]
		var at := int(p["pos"])
		var opts: Array = BoardMap.next(at)
		var to: int = opts[0]
		if opts.size() > 1:
			var choices := []
			for o in opts:
				choices.append({"to": o, "cost": BoardMap.cost(at, o), "name": BoardMap.route_name(o)})
			var a = await _ask_and_wait(id, "branch", {"at": at, "options": choices, "left": steps}, CHOICE_TIMEOUT, flow)
			if flow != _flow or not Net.players.has(id):
				return
			var pick := -1
			if a != null and opts.has(int(a.get("to", -1))):
				pick = int(a["to"])
			if pick < 0 or BoardMap.cost(at, pick) > int(p["coins"]):
				var free := []
				for o in opts:
					if BoardMap.cost(at, o) <= int(p["coins"]):
						free.append(o)
				pick = free[rng.randi() % free.size()] if free.size() > 0 else opts[0]
			to = pick
			var c := BoardMap.cost(at, to)
			if c > 0:
				p["coins"] = int(p["coins"]) - c
				_send({"k": "coins", "id": id, "delta": -c, "text": "Péage du pont : -%d pièces" % c})
				if not await _wait(1.0, flow):
					return
		p["pos"] = to
		steps -= 1
		_send({"k": "step", "id": id, "node": to, "left": steps})
		if not await _wait(0.32, flow):
			return
		if to == star_node:
			await _star_visit(id, flow)
			if flow != _flow:
				return
		if steps > 0:
			match BoardMap.kind(to):
				"S":
					var bonus := _coins(id, 5)
					_send({"k": "coins", "id": id, "delta": bonus, "text": "Prime du village : +%d pièces !" % bonus})
					if not await _wait(1.0, flow):
						return
				"K":
					if int(p["coins"]) >= BANK_FEE:
						p["coins"] = int(p["coins"]) - BANK_FEE
						bank += BANK_FEE
						_send({"k": "coins", "id": id, "delta": -BANK_FEE, "text": "Banque : tu déposes %d pièces" % BANK_FEE})
						if not await _wait(1.0, flow):
							return
				"H":
					await _shop(id, flow)
					if flow != _flow:
						return


func _star_visit(id: int, flow: int) -> void:
	var p: Dictionary = Net.players[id]
	if int(p["coins"]) >= STAR_COST:
		p["coins"] = int(p["coins"]) - STAR_COST
		p["stars"] = int(p["stars"]) + 1
		var old := star_node
		star_node = _new_star(int(p["pos"]))
		_send({"k": "star", "id": id, "bought": true, "from": old})
		await _wait(3.2, flow)
	else:
		_send({"k": "star", "id": id, "bought": false})
		await _wait(1.8, flow)


func _new_star(from: int, lo := 12, hi := 34) -> int:
	var d := BoardMap.dist_from(from)
	var cands := []
	for i in BoardMap.count():
		if BoardMap.kind(i) == "B" and i != star_node and d.has(i) and int(d[i]) >= lo and int(d[i]) <= hi:
			cands.append(i)
	if cands.is_empty():
		for i in BoardMap.count():
			if BoardMap.kind(i) == "B" and i != star_node:
				cands.append(i)
	return cands[rng.randi() % cands.size()]


# ------------------------------------------------------------------ cases
func _coins(id: int, delta: int) -> int:
	var p: Dictionary = Net.players[id]
	var before := int(p["coins"])
	p["coins"] = maxi(0, before + delta)
	var real := int(p["coins"]) - before
	if real > 0:
		p["coins_won"] = int(p.get("coins_won", 0)) + real
	return real


func _land(id: int, flow: int) -> void:
	var p: Dictionary = Net.players[id]
	var at := int(p["pos"])
	var kind := BoardMap.kind(at)
	if Net.autotest != "" and OS.get_environment("FORCE_SPACE") != "":
		var forced := OS.get_environment("FORCE_SPACE").split(",")
		kind = forced[_forced_i % forced.size()]
		_forced_i += 1
	match kind:
		"B", "S":
			_send({"k": "coins", "id": id, "delta": _coins(id, 3), "text": "", "land": true})
		"R":
			p["reds"] = int(p.get("reds", 0)) + 1
			_send({"k": "coins", "id": id, "delta": _coins(id, -3), "text": "", "land": true})
		"E":
			await _zone_event(id, flow)
		"C":
			await _chance(id, flow)
		"I":
			var it := Items.random_gift(rng)
			if (p["items"] as Array).size() < Items.MAX_HELD:
				(p["items"] as Array).append(it)
				_send({"k": "msg", "id": id, "title": "Case objet !", "text": "Tu gagnes : %s" % Items.item_name(it), "item": it})
			else:
				_send({"k": "msg", "id": id, "title": "Case objet !", "text": "Ton sac est plein (3 objets max)..."})
		"D":
			await _duel(id, flow)
			return
		"T":
			var lost := -_coins(id, -10)
			bank += lost
			_send({"k": "msg", "id": id, "title": "PIÈGE !", "text": "Tu perds %d pièces... elles tombent dans la banque !" % lost, "delta": -lost, "bad": true})
		"K":
			var gain := bank
			bank = 0
			_coins(id, gain)
			_send({"k": "msg", "id": id, "title": "Banque !", "text": "Tu ramasses toute la banque : +%d pièces !" % gain if gain > 0 else "La banque est vide...", "delta": gain})
		"H":
			await _shop(id, flow)
			return
		"P":
			var to := BoardMap.pipe_pair(at)
			p["pos"] = to
			_send({"k": "teleport", "id": id, "from": at, "node": to, "text": "Le tuyau t'emmène de l'autre côté de l'île !"})
			await _wait(2.4, flow)
			return
	await _wait(1.9, flow)


func _others(id: int) -> Array:
	var out := []
	for o in Net.players:
		if o != id:
			out.append(o)
	return out


func _gift(id: int) -> String:
	var p: Dictionary = Net.players[id]
	var it := Items.random_gift(rng)
	if (p["items"] as Array).size() < Items.MAX_HELD:
		(p["items"] as Array).append(it)
		return it
	return ""


func _zone_event(id: int, flow: int) -> void:
	var p: Dictionary = Net.players[id]
	var z := BoardMap.zone(int(p["pos"]))
	var title := "Événement : " + str(BoardMap.ZONE_NAMES.get(z, z))
	var text := ""
	var heads := 50
	match z:
		"village":
			for o in Net.players:
				_coins(o, 5)
			text = "Fête au village ! Tout le monde gagne 5 pièces."
		"foret":
			if rng.randi() % 100 < heads:
				text = "Un écureuil farceur te vole %d pièces !" % -_coins(id, -5)
			else:
				var it := _gift(id)
				text = "Tu trouves un objet dans un tronc creux : %s !" % Items.item_name(it) if it != "" else "Un tronc creux... vide."
		"lac":
			if rng.randi() % 100 < heads:
				text = "Pêche miraculeuse : +%d pièces !" % _coins(id, 8)
			else:
				var lake := []
				for i in BoardMap.count():
					if BoardMap.zone(i) == "lac" and BoardMap.kind(i) == "B" and i != int(p["pos"]):
						lake.append(i)
				var to: int = lake[rng.randi() % lake.size()]
				var from := int(p["pos"])
				p["pos"] = to
				_send({"k": "teleport", "id": id, "from": from, "node": to, "text": "Le bateau t'emmène ailleurs sur le lac !"})
				await _wait(2.6, flow)
				return
		"chateau":
			var others := _others(id)
			if rng.randi() % 100 < heads and others.size() > 0:
				var o: int = others[rng.randi() % others.size()]
				var a := int(p["coins"])
				p["coins"] = int(Net.players[o]["coins"])
				Net.players[o]["coins"] = a
				text = "Le roi fantôme échange tes pièces avec celles de %s !" % Net.name_of(o)
			else:
				text = "Trésor royal : +%d pièces !" % _coins(id, 15)
		"volcan":
			var hit := []
			for o in Net.players:
				if BoardMap.zone(int(Net.players[o]["pos"])) == "volcan":
					_coins(o, -10)
					hit.append(Net.name_of(o))
			text = "ÉRUPTION ! Les joueurs sur le volcan perdent 10 pièces : %s." % ", ".join(hit)
		"plage":
			if rng.randi() % 100 < heads:
				text = "Coup de soleil : -%d pièces." % -_coins(id, -5)
			else:
				var it2 := _gift(id)
				text = "Un coquillage magique : %s !" % Items.item_name(it2) if it2 != "" else "Un joli coquillage... mais ton sac est plein."
	_send({"k": "msg", "id": id, "title": title, "text": text, "zone": z})
	await _wait(3.4, flow)


const CARDS := [
	["Jackpot !", "+10 pièces", 3],
	["Trou dans la poche", "-10 pièces", 3],
	["Échange de pièces", "Tu échanges tes pièces avec un joueur", 2],
	["Échange de place", "Tu échanges ta place avec un joueur", 2],
	["Anniversaire !", "Chaque joueur te donne 3 pièces", 2],
	["Tournée générale", "Tu donnes 3 pièces à chaque joueur", 2],
	["Cadeau", "Un objet gratuit", 3],
	["Téléportation", "Tu vas sur une case au hasard", 2],
	["Coup de vent", "L'étoile s'envole ailleurs !", 1],
	["Pile ou face", "+15 ou -15 pièces", 2],
]


func _chance(id: int, flow: int) -> void:
	var total := 0
	for c in CARDS:
		total += int(c[2])
	var r := rng.randi() % total
	var card: Array = CARDS[0]
	for c in CARDS:
		r -= int(c[2])
		if r < 0:
			card = c
			break
	var p: Dictionary = Net.players[id]
	var others := _others(id)
	var result := ""
	var tele_from := -1
	match str(card[0]):
		"Jackpot !":
			result = "+%d pièces !" % _coins(id, 10)
		"Trou dans la poche":
			result = "-%d pièces..." % -_coins(id, -10)
		"Échange de pièces":
			if others.size() > 0:
				var o: int = others[rng.randi() % others.size()]
				var a := int(p["coins"])
				p["coins"] = int(Net.players[o]["coins"])
				Net.players[o]["coins"] = a
				result = "Avec %s !" % Net.name_of(o)
			else:
				result = "Personne avec qui échanger..."
		"Échange de place":
			if others.size() > 0:
				var o2: int = others[rng.randi() % others.size()]
				var a2 := int(p["pos"])
				p["pos"] = int(Net.players[o2]["pos"])
				Net.players[o2]["pos"] = a2
				result = "Avec %s !" % Net.name_of(o2)
			else:
				result = "Personne avec qui échanger..."
		"Anniversaire !":
			var got := 0
			for o3 in others:
				got -= _coins(o3, -3)
			_coins(id, got)
			result = "+%d pièces !" % got
		"Tournée générale":
			for o4 in others:
				var give := mini(3, int(p["coins"]))
				_coins(id, -give)
				_coins(o4, give)
			result = "Tes potes te remercient !"
		"Cadeau":
			var it := _gift(id)
			result = "%s !" % Items.item_name(it) if it != "" else "Sac plein..."
		"Téléportation":
			tele_from = int(p["pos"])
			p["pos"] = rng.randi_range(8, BoardMap.count() - 1)
			result = "Hop !"
		"Coup de vent":
			star_node = _new_star(int(p["pos"]))
			result = "Regarde où elle est partie !"
		"Pile ou face":
			if rng.randi() % 2 == 0:
				result = "Pile : +%d pièces !" % _coins(id, 15)
			else:
				result = "Face : -%d pièces..." % -_coins(id, -15)
	_send({"k": "card", "id": id, "title": card[0], "text": card[1], "result": result, "tele_from": tele_from, "node": int(p["pos"])})
	await _wait(4.2, flow)


func _shop(id: int, flow: int) -> void:
	for n in 3:
		var a = await _ask_and_wait(id, "shop", {"stock": Items.SHOP, "n": n}, 20.0, flow)
		if flow != _flow or not Net.players.has(id):
			return
		if a == null or str(a.get("buy", "")) == "":
			break
		var p: Dictionary = Net.players[id]
		var k := str(a["buy"])
		if Items.DATA.has(k) and int(p["coins"]) >= Items.price(k) and (p["items"] as Array).size() < Items.MAX_HELD:
			p["coins"] = int(p["coins"]) - Items.price(k)
			(p["items"] as Array).append(k)
			_send({"k": "bought", "id": id, "item": k, "price": Items.price(k)})
			if not await _wait(0.8, flow):
				return
	_send({"k": "shop_done", "id": id})
	await _wait(0.6, flow)


func _duel(id: int, flow: int) -> void:
	var others := _others(id)
	if others.is_empty():
		_send({"k": "msg", "id": id, "title": "Duel !", "text": "Personne à défier... dommage !"})
		await _wait(2.0, flow)
		return
	var a = await _ask_and_wait(id, "duel", {"options": others}, CHOICE_TIMEOUT, flow)
	if flow != _flow or not Net.players.has(id):
		return
	var target := -1
	if a != null and others.has(int(a.get("target", -1))):
		target = int(a["target"])
	if target < 0:
		target = others[rng.randi() % others.size()]
	var stake := mini(DUEL_STAKE, mini(int(Net.players[id]["coins"]), int(Net.players[target]["coins"])))
	_send({"k": "duel", "id": id, "target": target, "stake": stake})
	if not await _wait(3.0, flow):
		return
	_duel_done = false
	Net.start_duel(id, target, stake)
	while not _duel_done and flow == _flow:
		await get_tree().create_timer(0.2).timeout
	await _wait(2.5, flow)


## Appelé par Net quand le duel est fini et qu'on est revenu sur le plateau.
func on_duel_finished() -> void:
	_duel_done = true


# ------------------------------------------------------------------ objets
## Renvoie "" si refusé, "ok" si utilisé, "end" si le tour s'arrête là (tuyau doré).
func _use_item(id: int, a: Dictionary, mods: Dictionary, flow: int) -> String:
	var p: Dictionary = Net.players[id]
	var k := str(a.get("item", ""))
	var items: Array = p["items"]
	if not items.has(k):
		return ""
	var target := int(a.get("target", -1))
	if Items.needs_target(k) and (target == id or not Net.players.has(target)):
		var others := _others(id)
		if others.is_empty():
			return ""
		target = others[rng.randi() % others.size()]
	items.erase(k)
	var text := ""
	var res := "ok"
	match k:
		"mushroom":
			mods["bonus"] = int(mods["bonus"]) + 3
			text = "+3 à ton lancer !"
		"double":
			mods["dice"] = 2
			text = "Tu lances 2 dés !"
		"triple":
			mods["dice"] = 3
			text = "Tu lances 3 dés !"
		"custom":
			mods["fixed"] = clampi(int(a.get("value", 6)), 1, 10)
			text = "Tu feras %d !" % int(mods["fixed"])
		"poison":
			Net.players[target]["poison"] = true
			text = "%s ne fera que 1 à 3 au prochain dé !" % Net.name_of(target)
		"boo":
			var stolen := -_coins(target, -10)
			_coins(id, stolen)
			text = "Le fantôme vole %d pièces à %s !" % [stolen, Net.name_of(target)]
		"swap":
			var a2 := int(p["pos"])
			p["pos"] = int(Net.players[target]["pos"])
			Net.players[target]["pos"] = a2
			text = "Tu échanges ta place avec %s !" % Net.name_of(target)
		"pipe":
			var from := int(p["pos"])
			p["pos"] = star_node
			text = "Direction l'étoile !"
			_send({"k": "item", "id": id, "item": k, "target": target, "text": text})
			if not await _wait(1.2, flow):
				return "end"
			_send({"k": "teleport", "id": id, "from": from, "node": star_node, "text": ""})
			if not await _wait(1.6, flow):
				return "end"
			await _star_visit(id, flow)
			return "end"
	_send({"k": "item", "id": id, "item": k, "target": target, "text": text})
	await _wait(2.0, flow)
	return res


# ------------------------------------------------------------------ bots (tests automatiques)
func _bot_answer(d: Dictionary) -> void:
	var delay := float(OS.get_environment("BOT_DELAY")) if OS.get_environment("BOT_DELAY") != "" else 0.6
	await get_tree().create_timer(delay).timeout
	var me := Net.my_id()
	var p: Dictionary = Net.players.get(me, {})
	match str(d["what"]):
		"action":
			var items: Array = p.get("items", [])
			if not d.get("used", false) and items.size() > 0 and randf() < 0.5:
				var others := _others(me)
				send_request({"what": "action", "do": "item", "item": items[0], "value": 10,
					"target": others[0] if others.size() > 0 else -1})
			else:
				send_request({"what": "action", "do": "roll"})
		"branch":
			var opts: Array = d["options"]
			send_request({"what": "branch", "to": int(opts[randi() % opts.size()]["to"])})
		"shop":
			var cheap := []
			for k in Items.SHOP:
				if Items.price(k) <= int(p.get("coins", 0)):
					cheap.append(k)
			send_request({"what": "shop", "buy": cheap[randi() % cheap.size()] if cheap.size() > 0 and randf() < 0.5 else ""})
		"duel":
			var o: Array = d["options"]
			send_request({"what": "duel", "target": o[randi() % o.size()]})
