extends Node
## Autoload. Plays one-shot sound effects by name from res://sounds.

const FILES := {
	"step": "step.wav", "land": "land.wav", "bump": "bump.wav", "slide": "slide.wav",
	"crumble": "crumble.wav", "key": "key.wav", "burn": "burn.wav", "fall": "fall.wav",
	"lift": "lift.ogg", "field": "unlock.ogg", "win": "win.ogg", "lose": "lose.ogg",
	"click": "click.wav", "switch": "switch.ogg",
	"splash": "splash.ogg", "paddle": "paddle.ogg", "pour": "pour.ogg", "drain": "drain.ogg", "hiss": "hiss.ogg",
}
const VOLUME_DB := {
	"step": -8.0, "slide": -6.0, "burn": -4.0, "lift": -6.0,
	"splash": -6.0, "paddle": -8.0, "pour": -9.0, "drain": -11.0, "hiss": -6.0,
}

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for key in FILES:
		_streams[key] = load("res://sounds/" + FILES[key])
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(key: String, pitch_spread := 0.0) -> void:
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[key]
	p.volume_db = VOLUME_DB.get(key, -3.0)
	p.pitch_scale = 1.0 + randf_range(-pitch_spread, pitch_spread)
	p.play()
