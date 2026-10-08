extends "res://minigames/stage.gd"
## « Gare aux blocs ! » : des blocs grincheux s'écrasent du ciel. On esquive, on pousse
## les autres dessous, le dernier debout gagne. Le motif de chute est le même chez tout le monde.

const COLS := 7
const X0 := 192.0
const GROUND := 592.0
const HOVER := 100.0
const FALL := 0.24
const REST := 0.95
const RISE := 0.6

var blocks: Array = []      # {body, sprite, x}
var attacks: Array = []     # {col, t, warn}
var impacted := {}
var shadows: Node2D
var tex := {}


func _setup() -> void:
	title = "Gare aux blocs !"
	rules = "Des blocs grincheux s'écrasent du ciel !\nRegarde leur ombre au sol et esquive-les.\nPousse les autres dessous... Le dernier debout gagne !"
	duration = 60.0
	for k in ["idle", "fall", "rest"]:
		tex[k] = load("res://assets/enemies/block_%s.png" % k)
	for i in 8:
		spawn_points.append(Vector2(250 + i * 112, GROUND))
	_make_schedule()
	if Net.autotest != "":
		for a in attacks.slice(0, 6):
			print("[attack] col=", a["col"], " t=", snappedf(a["t"], 0.01), " impact=", snappedf(float(a["t"]) + float(a["warn"]) + FALL, 0.01))


func _make_schedule() -> void:
	var busy := []
	for c in COLS:
		busy.append(0.0)
	var tt := 1.2
	while tt < duration:
		var prog := tt / duration
		var interval := lerpf(1.7, 0.72, prog)
		var warn := lerpf(1.0, 0.62, prog)
		var k := 1 + int(prog * 2.6 + rng.randf() * 1.4)
		if prog > 0.2 and rng.randf() < 0.14:
			k = COLS - rng.randi_range(1, 2)   # grosse vague : il ne reste qu'un ou deux trous
			warn += 0.35
		var free := []
		for c in COLS:
			if busy[c] <= tt:
				free.append(c)
		# mélange déterministe
		for i in range(free.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = free[i]
			free[i] = free[j]
			free[j] = tmp
		for i in mini(k, free.size()):
			var c: int = free[i]
			attacks.append({"col": c, "t": tt, "warn": warn})
			busy[c] = tt + warn + FALL + REST + RISE + 0.15
		tt += interval


func _build_level() -> void:
	shadows = Node2D.new()
	shadows.z_index = 1
	world.add_child(shadows)
	shadows.draw.connect(_draw_shadows)
	tile("bush", Vector2(X0 - 20, GROUND - T))
	tile("bush", Vector2(X0 + COLS * 128 - 44, GROUND - T))
	island(3, GROUND, 14)
	for c in COLS:
		var b := AnimatableBody2D.new()
		b.sync_to_physics = true
		b.collision_layer = 0
		b.collision_mask = 0
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = Vector2(122, 124)
		cs.shape = rs
		cs.position = Vector2(64, 64)
		b.add_child(cs)
		var s := Sprite2D.new()
		s.texture = tex["idle"]
		s.centered = false
		b.add_child(s)
		b.position = Vector2(X0 + c * 128, HOVER)
		b.z_index = 8
		world.add_child(b)
		blocks.append({"body": b, "sprite": s, "x": X0 + c * 128})


## État d'une colonne à l'instant tt : [y du haut, phase, avancement, n° d'attaque]
func _col_state(c: int, tt: float) -> Array:
	for i in range(attacks.size() - 1, -1, -1):
		var a: Dictionary = attacks[i]
		if int(a["col"]) != c:
			continue
		var s: float = tt - float(a["t"])
		if s < 0.0:
			continue
		var w: float = a["warn"]
		if s < w:
			return [HOVER - 10.0 * sin(s / w * PI * 0.5), "warn", s / w, i]
		s -= w
		if s < FALL:
			var k := s / FALL
			return [HOVER + (GROUND - 128.0 - HOVER) * k * k, "fall", k, i]
		s -= FALL
		if s < REST:
			return [GROUND - 128.0, "rest", s / REST, i]
		s -= REST
		if s < RISE:
			var k2 := s / RISE
			var e := k2 * k2 * (3.0 - 2.0 * k2)
			return [GROUND - 128.0 + (HOVER - GROUND + 128.0) * e, "rise", k2, i]
		break
	return [HOVER, "idle", 0.0, -1]


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	var tt := play_t if state != "intro" else 0.0
	var danger := []
	for c in COLS:
		var st := _col_state(c, tt)
		if st[1] in ["warn", "fall"]:
			danger.append([X0 + c * 128.0, X0 + c * 128.0 + 128.0])
		var b: Dictionary = blocks[c]
		var body: AnimatableBody2D = b["body"]
		var y: float = st[0]
		var ph: String = st[1]
		var x: float = b["x"]
		if ph == "warn":
			x += sin(tt * 70.0 + c) * 3.0 * float(st[2])
		elif ph == "idle":
			y += sin(tt * 2.0 + c * 0.9) * 4.0
		body.position = Vector2(x, y)
		body.collision_layer = 1 if ph in ["rest", "rise"] else 0
		var spr: Sprite2D = b["sprite"]
		match ph:
			"warn", "fall":
				spr.texture = tex["fall"]
			"rest":
				spr.texture = tex["rest"]
			_:
				spr.texture = tex["idle"]
		# impact
		if ph == "rest" and not impacted.has(st[3]):
			impacted[st[3]] = true
			fx.dust(Vector2(x + 64, GROUND), 6, 1.4)
			fx.shake(4.0)
			Sfx.play("bump", -10.0, 0.15)
		# écrasement (vérifié par chacun pour son propre perso)
		if state == "play" and me and not me.dead and ph in ["fall", "rest"] and (ph == "fall" or float(st[2]) < 0.05):
			var br := Rect2(Vector2(x + 8, y + 12), Vector2(112, 114))
			var mr := Rect2(me.position + Vector2(-17, -56), Vector2(34, 54))
			if br.intersects(mr):
				fx.stars(me.position + Vector2(0, -20), 6)
				fx.popup(me.position + Vector2(0, -60), "ÉCRASÉ !", me.color())
				Sfx.play("hurt", 0.0)
				eliminate_me("écrasé")
	if me:
		me.set_meta("danger", danger)
	shadows.queue_redraw()


func _draw_shadows() -> void:
	var tt := play_t if state != "intro" else 0.0
	for c in COLS:
		var st := _col_state(c, tt)
		var ph: String = st[1]
		var cx: float = X0 + c * 128 + 64
		var k := 0.0
		if ph == "warn":
			k = 0.3 + 0.7 * float(st[2])
		elif ph == "fall":
			k = 1.0
		if k <= 0.0:
			continue
		var w := 40.0 + 70.0 * k
		var pts := PackedVector2Array()
		for i in 24:
			var a := TAU * i / 24.0
			pts.append(Vector2(cx + cos(a) * w, GROUND + 4 + sin(a) * 12.0))
		shadows.draw_colored_polygon(pts, Color(UI.DARK, 0.18 + 0.32 * k))


func _draw_extra_hud() -> void:
	draw_timer()
