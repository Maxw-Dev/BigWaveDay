## Procedural wind: filtered noise whose volume and pitch follow the surfer's speed.
## Placeholder until real sound lands; it already sells "you are going fast".
class_name Wind
extends AudioStreamPlayer

@export var min_speed := 3.0
@export var full_speed := 12.0
@export var max_db := -10.0
@export var enabled := true

var _pb: AudioStreamGeneratorPlayback
var _lp := 0.0
var _lp2 := 0.0
var _level := 0.0


func _ready() -> void:
	if not enabled:
		return
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.12
	stream = gen
	volume_db = -60.0
	play()
	_pb = get_stream_playback()


func set_speed(s: float) -> void:
	_level = clampf((s - min_speed) / (full_speed - min_speed), 0.0, 1.0)


func _process(_delta: float) -> void:
	if _pb == null:
		return
	volume_db = lerpf(-45.0, max_db, _level)
	pitch_scale = lerpf(0.7, 1.4, _level)
	var n := _pb.get_frames_available()
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in range(n):
		var white := randf() * 2.0 - 1.0
		_lp += (white - _lp) * 0.10
		_lp2 += (_lp - _lp2) * 0.10
		var v := _lp2 * 4.0
		buf[i] = Vector2(v, v)
	_pb.push_buffer(buf)
