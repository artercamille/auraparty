extends CharacterBody2D
## Un perso. En local : physique + commandes. À distance : on suit les positions reçues, lissées.

signal died(attacker: int)

const SCALE := 0.38
const RUN := 390.0
const ACC_GROUND := 3400.0
const DEC_GROUND := 3900.0
const ACC_AIR := 2400.0
const DEC_AIR := 900.0
const GRAV_UP := 2500.0
const GRAV_DOWN := 3300.0
const GRAV_APEX := 1250.0
const MAX_FALL := 1150.0
const FAST_FALL := 1550.0
const JUMP_V := 880.0
const JUMP2_V := 790.0
const JUMP_CUT := 0.6
const COYOTE := 0.1
const BUFFER := 0.16
const PUSH_TIME := 0.17
const PUSH_SPEED := 760.0
const PUSH_CD := 1.2
const SPRING_V := 1250.0
const KNOCK := Vector2(1060.0, -500.0)
const INTERP := 0.1
const HALF_W := 21.0
const HEIGHT := 62.0

enum { A_IDLE, A_WALK, A_JUMP, A_FALL, A_HIT, A_DUCK, A_PUSH }

var pid := 0
var is_local := false
var is_bot := false
var color_idx := 0
var tex := {}
var fx: Node2D

var facing := 1
var coyote := 0.0
var buffer := 0.0
var air_jumps := 1
var push_t := 0.0
var push_cd := 0.0
var air_push_used := false
var stun := 0.0
var invuln := 0.0
var dead := false
var respawn_t := 0.0
var last_hitter := 0
var last_hit_age := 99.0
var squash := Vector2.ONE
var spin := 0.0
var walk_t := 0.0
var was_on_floor := true
var jump_cut_ok := false
var drop_t := 0.0
var hitstop := 0.0
var send_acc := 0.0
var anim := A_IDLE
var t := 0.0

# distant
var snaps: Array = []
var remote_has_data := false
var prev_remote_anim := A_IDLE

# bot
var bot_t := 0.0
var bot_dir := 0.0
var bot_jump := false
var bot_push := false
var bot_target: Node2D

var sprite: Sprite2D
var hit_ids := {}
var kill_rect := Rect2(-260, -2000, 1800, 2860)   # hors de cette zone = chute


func setup(id: int, local: bool, c: int, effects: Node2D) -> void:
	pid = id
	is_local = local
	color_idx = c
	fx = effects
	is_bot = local and Net.autotest != ""
	for p in ["idle", "walk_a", "walk_b", "jump", "hit", "duck"]:
		tex[p] = UI.char_tex(c, p)


func _ready() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(HALF_W * 2.0, HEIGHT)
	shape.shape = rect
	shape.position = Vector2(0, -HEIGHT / 2.0)
	add_child(shape)
	collision_layer = 0
	collision_mask = 1 | 2
	floor_snap_length = 6.0
	sprite = Sprite2D.new()
	sprite.texture = tex["idle"]
	sprite.offset = Vector2(0, -128)
	sprite.scale = Vector2.ONE * SCALE
	add_child(sprite)
	z_index = 5
	if not is_local:
		visible = false


func color() -> Color:
	return Net.COLORS[color_idx]


# ------------------------------------------------------------------ commandes
func _input_state() -> Dictionary:
	if get_meta("blocked", false):
		_q_jump = false
		_q_push = false
		return {"x": 0.0, "down": false, "jump": false, "jump_held": false, "push": false}
	if is_bot:
		return _bot_input()
	return {
		"x": Input.get_axis("left", "right"),
		"down": Input.is_action_pressed("down"),
		"jump": _take_jump(),
		"jump_held": Input.is_action_pressed("jump"),
		"push": _take_push(),
	}


func _bot_input() -> Dictionary:
	if OS.get_environment("BOTIDLE") != "":
		return {"x": 0.0, "down": false, "jump": false, "jump_held": false, "push": false}
	if has_meta("goal_x"):
		var gx: float = get_meta("goal_x")
		var gd := {"x": signf(gx - position.x) if absf(gx - position.x) > 8.0 else 0.0, "down": get_meta("goal_down", false) and not is_on_floor(),
			"jump": false, "jump_held": true, "push": false}
		bot_t -= get_physics_process_delta_time()
		if bot_t <= 0.0:
			bot_t = 0.25
			if is_on_floor() and (absf(velocity.x) < 30.0 and absf(gx - position.x) > 20.0 or get_meta("goal_jump", false)):
				gd["jump"] = true
		if get_meta("jump_now", false):
			gd["jump"] = true
			set_meta("jump_now", false)
		return gd
	bot_t -= get_physics_process_delta_time()
	var d := {"x": bot_dir, "down": false, "jump": false, "jump_held": true, "push": false}
	if bot_t <= 0.0:
		bot_t = randf_range(0.2, 0.6)
		var best: Node2D = null
		var bd := 1e9
		for n in get_parent().get_children():
			var p := n as Node2D
			if p != null and p != self and p.visible:
				var dd := position.distance_to(p.position)
				if dd < bd:
					bd = dd
					best = p
		bot_target = best
		if best and randf() < 0.75:
			bot_dir = signf(best.position.x - position.x)
		else:
			bot_dir = [-1.0, 0.0, 1.0].pick_random()
		if position.x < 360:
			bot_dir = 1.0
		elif position.x > 920:
			bot_dir = -1.0
		bot_jump = randf() < 0.3 or (best != null and best.position.y < position.y - 60)
		bot_push = best != null and bd < 110
	d["x"] = bot_dir
	# zones dangereuses signalées par le mini-jeu (ex : ombres des blocs)
	var danger: Array = get_meta("danger", [])
	for z in danger:
		if position.x > float(z[0]) - 26.0 and position.x < float(z[1]) + 26.0:
			var mid := (float(z[0]) + float(z[1])) / 2.0
			d["x"] = -1.0 if position.x < mid else 1.0
			if (d["x"] < 0 and position.x < 260) or (d["x"] > 0 and position.x > 1020):
				d["x"] = -d["x"]
			bot_push = false
			break
	if bot_jump:
		d["jump"] = true
		bot_jump = false
	if bot_push:
		d["push"] = true
		bot_push = false
	if not is_on_floor() and position.y > 470:
		d["jump"] = true
		d["x"] = signf(640 - position.x)
	return d


# ------------------------------------------------------------------ physique locale
func _physics_process(delta: float) -> void:
	t += delta
	if not is_local:
		return
	if dead:
		respawn_t -= delta
		return
	last_hit_age += delta
	invuln = maxf(0.0, invuln - delta)
	push_cd = maxf(0.0, push_cd - delta)
	if hitstop > 0.0:
		hitstop -= delta
		if _q_jump:
			buffer = BUFFER
		return
	var inp := _input_state()
	var on_floor := is_on_floor()
	if on_floor:
		coyote = COYOTE
		air_jumps = 1
		air_push_used = false
	else:
		coyote -= delta
	if inp["jump"]:
		buffer = BUFFER
	else:
		buffer -= delta

	# atterrissage
	if on_floor and not was_on_floor:
		squash = Vector2(1.32, 0.72)
		if fx:
			fx.dust(global_position, 4, 1.0)

	# horizontal
	var ix: float = inp["x"]
	if stun > 0.0:
		stun -= delta
		velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
	elif push_t > 0.0:
		push_t -= delta
		velocity.x = facing * PUSH_SPEED
	else:
		var target := ix * RUN
		var acc: float
		if on_floor:
			acc = ACC_GROUND if absf(target) > 1.0 else DEC_GROUND
			if target != 0.0 and signf(target) != signf(velocity.x) and absf(velocity.x) > 40.0:
				acc *= 1.7
				if absf(velocity.x) > 250.0 and fx and int(t * 30) % 3 == 0:
					fx.dust(global_position, 1, 0.6)
		else:
			acc = ACC_AIR if absf(target) > 1.0 else DEC_AIR
		velocity.x = move_toward(velocity.x, target, acc * delta)
		if ix != 0.0:
			facing = int(signf(ix))

	# descendre d'une plateforme fine
	if inp["down"] and inp["jump"] and on_floor and _on_oneway():
		set_collision_mask_value(2, false)
		drop_t = 0.25
		buffer = 0.0
		position.y += 2.0
	if drop_t > 0.0:
		drop_t -= delta
		if drop_t <= 0.0:
			set_collision_mask_value(2, true)

	# saut / double saut
	if buffer > 0.0 and stun <= 0.0:
		if coyote > 0.0:
			_jump(JUMP_V)
			coyote = 0.0
			buffer = 0.0
			Sfx.play("jump", -6.0)
			if fx:
				fx.dust(global_position, 3, 0.8)
		elif air_jumps > 0:
			_jump(JUMP2_V)
			air_jumps -= 1
			buffer = 0.0
			spin = 1.0
			Sfx.play("jump", -6.0, 0.05)
			if fx:
				fx.ring(global_position + Vector2(0, -10), color())
	if not inp["jump_held"] and jump_cut_ok and velocity.y < 0.0:
		velocity.y *= JUMP_CUT
		jump_cut_ok = false

	# gravité
	var g := GRAV_UP if velocity.y < 0.0 else GRAV_DOWN
	if inp["jump_held"] and absf(velocity.y) < 140.0 and stun <= 0.0:
		g = GRAV_APEX
	if push_t > 0.0:
		g *= 0.2
	var max_fall := FAST_FALL if (inp["down"] and not on_floor and stun <= 0.0) else MAX_FALL
	velocity.y = minf(velocity.y + g * delta, max_fall)

	# poussée
	if inp["push"] and push_cd <= 0.0 and stun <= 0.0 and (on_floor or not air_push_used):
		push_t = PUSH_TIME
		push_cd = PUSH_CD
		hit_ids.clear()
		if not on_floor:
			air_push_used = true
			velocity.y = minf(velocity.y, -160.0)
		squash = Vector2(1.35, 0.8)
		Sfx.play("whoosh", -4.0)
		if fx:
			fx.dust(global_position + Vector2(-facing * 20, -20), 2, 0.7)

	was_on_floor = on_floor
	move_and_slide()
	spin = maxf(0.0, spin - delta * 3.2)
	_update_anim(is_on_floor(), inp["down"])

	if not kill_rect.has_point(position):
		_die()

	send_acc += delta
	if send_acc >= 1.0 / 30.0:
		send_acc = 0.0
		Net.send_state(position, velocity, _pack_state())


func _jump(v: float) -> void:
	velocity.y = -v
	jump_cut_ok = true
	squash = Vector2(0.72, 1.32)
	push_t = 0.0


func _on_oneway() -> bool:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var col := c.get_collider()
		if col is StaticBody2D and col.get_collision_layer_value(2):
			return true
	return false


func spring_bounce() -> void:
	velocity.y = -SPRING_V
	jump_cut_ok = false
	air_jumps = 1
	air_push_used = false
	squash = Vector2(0.65, 1.4)
	Sfx.play("jump2", -3.0)


func _update_anim(on_floor: bool, down: bool) -> void:
	if stun > 0.0:
		anim = A_HIT
	elif push_t > 0.0:
		anim = A_PUSH
	elif not on_floor:
		anim = A_JUMP if velocity.y < 0.0 else A_FALL
	elif down and absf(velocity.x) < 40.0:
		anim = A_DUCK
	elif absf(velocity.x) > 30.0:
		anim = A_WALK
	else:
		anim = A_IDLE


func _pack_state() -> int:
	var s := anim
	if facing < 0:
		s |= 16
	if dead:
		s |= 32
	if invuln > 0.0:
		s |= 64
	if spin > 0.0:
		s |= 128
	return s


# ------------------------------------------------------------------ coups reçus
func receive_hit(kind: int, dir: Vector2, from_id: int) -> void:
	if not is_local or dead or invuln > 0.0:
		return
	last_hitter = from_id
	last_hit_age = 0.0
	push_t = 0.0
	hitstop = 0.05
	if kind == 0:
		velocity = dir
		stun = 0.4
		squash = Vector2(0.7, 1.3)
		Sfx.play("hurt", -2.0)
	else:
		velocity = Vector2(velocity.x * 0.3, 520.0)
		stun = 0.45
		squash = Vector2(1.6, 0.5)
		Sfx.play("bump", -2.0)
	if fx:
		fx.stars(global_position + Vector2(0, -40), 5)
		fx.shake(6.0)


func _die() -> void:
	if dead:
		return
	dead = true
	visible = false
	var attacker := last_hitter if last_hit_age < 4.0 else 0
	Sfx.play("fall", -2.0)
	Net.send_state(position, velocity, _pack_state())
	died.emit(attacker)


## Éliminé par le mini-jeu (écrasé...) : on disparaît, les effets sont gérés par la scène.
func eliminate() -> void:
	if dead:
		return
	dead = true
	visible = false
	Net.send_state(position, velocity, _pack_state())
	died.emit(0)


func respawn(at: Vector2) -> void:
	dead = false
	visible = true
	position = at
	velocity = Vector2.ZERO
	stun = 0.0
	push_t = 0.0
	invuln = 1.6
	squash = Vector2(0.6, 1.4)
	Sfx.play("spawn", -6.0)
	if fx:
		fx.ring(at + Vector2(0, -30), color())
	Net.send_state(position, velocity, _pack_state())


# ------------------------------------------------------------------ distant
func push_snapshot(pos: Vector2, vel: Vector2, st: int) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	snaps.append([now, pos, vel, st])
	if snaps.size() > 30:
		snaps.pop_front()
	if not remote_has_data:
		remote_has_data = true
		position = pos


func remote_dead() -> bool:
	return snaps.size() > 0 and (int(snaps[-1][3]) & 32) != 0


func remote_invuln() -> bool:
	return snaps.size() > 0 and (int(snaps[-1][3]) & 64) != 0


var _q_jump := false
var _q_push := false


func _take_jump() -> bool:
	var v := _q_jump
	_q_jump = false
	return v


func _take_push() -> bool:
	var v := _q_push
	_q_push = false
	return v


func _process(delta: float) -> void:
	if is_local and not is_bot:
		if Input.is_action_just_pressed("jump"):
			_q_jump = true
		if Input.is_action_just_pressed("push"):
			_q_push = true
	if not is_local:
		_remote_update(delta)
	_visuals(delta)


func _remote_update(_delta: float) -> void:
	if snaps.is_empty():
		return
	var rt := Time.get_ticks_msec() / 1000.0 - INTERP
	var st := int(snaps[-1][3])
	if rt >= float(snaps[-1][0]):
		var ahead := minf(rt - float(snaps[-1][0]), 0.15)
		position = snaps[-1][1] + snaps[-1][2] * ahead
		velocity = snaps[-1][2]
	else:
		for i in range(snaps.size() - 1, 0, -1):
			var a: Array = snaps[i - 1]
			var b: Array = snaps[i]
			if float(a[0]) <= rt:
				var k := clampf((rt - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0])), 0.0, 1.0)
				var pa: Vector2 = a[1]
				var pb: Vector2 = b[1]
				if pa.distance_to(pb) > 300.0:
					position = pb
				else:
					position = pa.lerp(pb, k)
				velocity = (a[2] as Vector2).lerp(b[2], k)
				st = int(b[3])
				break
	var was_dead := dead
	dead = (st & 32) != 0
	visible = not dead and remote_has_data
	if was_dead and not dead and fx:
		fx.ring(position + Vector2(0, -30), color())
	facing = -1 if (st & 16) != 0 else 1
	invuln = 1.0 if (st & 64) != 0 else 0.0
	if (st & 128) != 0 and spin <= 0.0:
		spin = 1.0
	var new_anim := st & 15
	if new_anim != prev_remote_anim:
		if new_anim in [A_IDLE, A_WALK] and prev_remote_anim in [A_JUMP, A_FALL]:
			squash = Vector2(1.3, 0.75)
			if fx:
				fx.dust(position, 3, 0.8)
		elif new_anim == A_JUMP and prev_remote_anim in [A_IDLE, A_WALK]:
			squash = Vector2(0.75, 1.3)
		elif new_anim == A_PUSH:
			squash = Vector2(1.35, 0.8)
		prev_remote_anim = new_anim
	anim = new_anim


# ------------------------------------------------------------------ rendu
func _visuals(delta: float) -> void:
	if not is_local:
		spin = maxf(0.0, spin - delta * 3.2)
	squash = squash.lerp(Vector2.ONE, 1.0 - exp(-delta * 13.0))
	var key := "idle"
	var rot := 0.0
	match anim:
		A_WALK:
			walk_t += delta * (6.0 + absf(velocity.x) / 40.0)
			key = "walk_a" if int(walk_t) % 2 == 0 else "walk_b"
			rot = clampf(velocity.x / RUN, -1.0, 1.0) * 0.07
		A_JUMP:
			key = "jump"
		A_FALL:
			key = "jump"
		A_HIT:
			key = "hit"
			rot = sin(t * 40.0) * 0.12
		A_DUCK:
			key = "duck"
		A_PUSH:
			key = "walk_b"
			rot = facing * 0.22
		_:
			key = "idle"
	sprite.texture = tex[key]
	var breathe := 1.0 + sin(t * 3.0) * 0.015 if anim == A_IDLE else 1.0
	sprite.scale = Vector2(SCALE * squash.x * facing, SCALE * squash.y * breathe)
	sprite.rotation = rot - facing * spin * TAU
	sprite.position = Vector2(0, -HEIGHT * 0.5) if spin > 0.0 else Vector2.ZERO
	sprite.offset = Vector2(0, -128 + (HEIGHT * 0.5 / SCALE if spin > 0.0 else 0.0))
	sprite.modulate.a = 0.35 + 0.65 * absf(sin(t * 18.0)) if invuln > 0.0 else 1.0
	queue_redraw()


func _draw() -> void:
	if dead:
		return
	var y := -HEIGHT - 30.0
	UI.text(self, Vector2(0, y), Net.name_of(pid), 17, color(), 6)
	if is_local and not is_bot:
		var c := color()
		var p := Vector2(0, y - 22.0 + sin(t * 5.0) * 3.0)
		var tri := PackedVector2Array([p + Vector2(-9, -8), p + Vector2(9, -8), p + Vector2(0, 4)])
		draw_colored_polygon(tri, UI.DARK)
		var tri2 := PackedVector2Array([p + Vector2(-5.5, -5.5), p + Vector2(5.5, -5.5), p + Vector2(0, 1)])
		draw_colored_polygon(tri2, c)
