extends Node
## Petits bruitages du pack Kenney.

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
}

var streams := {}
var pool: Array[AudioStreamPlayer] = []
var idx := 0


func _ready() -> void:
	for k in FILES:
		streams[k] = load(FILES[k])
	for i in 16:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)


func play(name: String, volume_db := 0.0, pitch_var := 0.08) -> void:
	if not streams.has(name):
		return
	var p := pool[idx]
	idx = (idx + 1) % pool.size()
	p.stream = streams[name]
	p.volume_db = volume_db - 4.0
	p.pitch_scale = randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	p.play()
