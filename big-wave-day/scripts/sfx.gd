## Minimum viable sound, synthesized at startup so the game has audio before real samples exist.
## Splashes are filtered noise bursts, the pump is a short two-partial ding, the air is a rising whoosh,
## and the break is a low roar whose volume follows how close it is. Swap any of these for a real
## AudioStreamWAV by assigning it in the Inspector.
class_name Sfx
extends Node

const RATE := 22050.0

@export var enabled := true
@export var master_db := -6.0
@export var roar_max_db := -14.0
@export var roar_min_db := -42.0
@export var splash_sample: AudioStream       ## Optional real samples. Leave empty to use the synthesized ones.
@export var big_splash_sample: AudioStream
@export var pump_sample: AudioStream
@export var whoosh_sample: AudioStream
@export var roar_sample: AudioStream

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _roar: AudioStreamPlayer
var _closeness := 0.0


func _ready() -> void:
	if not enabled:
		return
	if splash_sample == null:
		splash_sample = _noise_burst(0.3, 0.3, 0.1, 0.06)
	if big_splash_sample == null:
		big_splash_sample = _noise_burst(0.7, 0.18, 0.22, 0.02)
	if pump_sample == null:
		pump_sample = _ding()
	if whoosh_sample == null:
		whoosh_sample = _whoosh()
	if roar_sample == null:
		roar_sample = _roar_loop(2.5)
	for i in range(6):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_roar = AudioStreamPlayer.new()
	_roar.stream = roar_sample
	_roar.volume_db = roar_min_db
	add_child(_roar)
	_roar.play()


func _process(delta: float) -> void:
	if _roar == null:
		return
	var target := lerpf(roar_min_db, roar_max_db, _closeness) + master_db
	_roar.volume_db = lerpf(_roar.volume_db, target, 1.0 - exp(-3.0 * delta))


func set_break_closeness(c: float) -> void:
	_closeness = clampf(c, 0.0, 1.0)


func splash(strength: float) -> void:
	_play(splash_sample, -10.0 + 6.0 * clampf(strength, 0.0, 1.0), randf_range(0.85, 1.15))


func splash_big() -> void:
	_play(big_splash_sample, -5.0, randf_range(0.9, 1.1))


func pump(quality: float) -> void:
	_play(pump_sample, -14.0 + 6.0 * clampf(quality, 0.0, 1.0), 0.95 + 0.12 * clampf(quality, 0.0, 1.0))


func whoosh() -> void:
	_play(whoosh_sample, -6.0, randf_range(0.95, 1.05))


func _play(stream: AudioStream, db: float, pitch: float) -> void:
	if not enabled or stream == null or _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = db + master_db
	p.pitch_scale = pitch
	p.play()


# ---- synthesis ----

func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var peak := 0.001
	for s in samples:
		peak = maxf(peak, absf(s))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i] / peak * 0.8, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(RATE)
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


func _noise_burst(seconds: float, lp: float, tau: float, hp: float) -> AudioStreamWAV:
	# Filtered white noise with a fast attack and an exponential decay.
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var rumble := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var white := randf() * 2.0 - 1.0
		low += (white - low) * lp
		rumble += (low - rumble) * hp
		var env := minf(t / 0.006, 1.0) * exp(-t / tau)
		out[i] = (low - rumble) * env
	return _to_wav(out, false)


func _ding() -> AudioStreamWAV:
	# A low, soft surge: a warm tone with a fifth on top and a swell of water noise under it. Says "yes",
	# not "alarm".
	var n := int(0.45 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var attack := minf(t / 0.04, 1.0)
		var tone := sin(TAU * 196.0 * t) * exp(-t / 0.28) + 0.5 * sin(TAU * 293.7 * t) * exp(-t / 0.2)
		var white := randf() * 2.0 - 1.0
		low += (white - low) * 0.07
		var swell := low * 0.9 * sin(PI * minf(t / 0.45, 1.0))
		out[i] = (tone * 0.7 + swell) * attack
	return _to_wav(out, false)


func _whoosh() -> AudioStreamWAV:
	# Noise through a lowpass that opens up over the sound: a rising swish.
	var n := int(0.55 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var k := t / 0.55
		var white := randf() * 2.0 - 1.0
		low += (white - low) * lerpf(0.04, 0.5, k * k)
		var env := sin(PI * k)
		out[i] = low * env
	return _to_wav(out, false)


func _roar_loop(seconds: float) -> AudioStreamWAV:
	# Brown noise, low-passed, with the loop seam cross-faded so it never clicks.
	var n := int(seconds * RATE)
	var raw := PackedFloat32Array()
	raw.resize(n)
	var brown := 0.0
	var low := 0.0
	for i in range(n):
		brown = brown * 0.995 + (randf() * 2.0 - 1.0) * 0.08
		low += (brown - low) * 0.06
		raw[i] = low
	var fade := int(0.2 * RATE)
	var out := PackedFloat32Array()
	out.resize(n - fade)
	for i in range(n - fade):
		if i < fade:
			var k := float(i) / fade
			out[i] = raw[i + (n - fade)] * (1.0 - k) + raw[i] * k
		else:
			out[i] = raw[i]
	return _to_wav(out, true)
