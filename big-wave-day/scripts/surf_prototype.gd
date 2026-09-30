## Root of surf_prototype.tscn. Owns the wave lifecycle: timer, fail states, the end-of-wave card,
## and the reset to a fresh wave with a random direction, rider and board.
class_name SurfPrototype
extends Node3D

enum State { RIDING, ENDING, CARD, STARTING }

@export var endless := false          ## No timer: the wave only ends when you wipe out. Hold on the card to toggle.
@export var wave_duration_min := 25.0
@export var wave_duration_max := 35.0
@export var start_lead := 12.0        ## Spawn distance ahead of the foam, metres.
@export var spawn_speed := 8.0
@export var bog_speed := 1.0          ## Below this on the flats the wave is over.
@export var caught_margin := 1.5      ## Metres behind the break line you may be before the foam has you. Inside the collapsing tube still counts as riding.
@export var random_direction := true  ## Pick left or right each wave.

@export_group("Reset flow")
@export var ending_slowmo := 0.3      ## Time scale while the wipeout plays out.
@export var ending_seconds := 0.7     ## Real seconds of slow motion before the card.
@export var card_min_seconds := 1.2   ## The card cannot be dismissed before this.
@export var card_auto_seconds := 5.0  ## The card dismisses itself after this.
@export var card_hold_toggle := 0.8   ## Holding this long on the card toggles endless mode.
@export var fade_seconds := 0.35
@export var show_first_wave_hints := true

var state := State.RIDING
var wave_count := 0
var wave_duration := 0.0
var time_left := 0.0
var last_reason := "-"
var last_wave_time := 0.0
var ride_time := 0.0
var barrel_seconds := 0.0
var longest_barrel := 0.0
var pocket_seconds := 0.0
var top_speed := 0.0
var sharp_turns := 0
var biggest_air := 0.0
var air_count := 0

var _barrel_streak := 0.0
var _card_hold := 0.0
var _card_toggled := false

var _state_t := 0.0
var _live_t := 0.0
var _hint_step := 0
var _was_sharp := false

@onready var wave: Wave = $Wave
@onready var surfer: Surfer = $Surfer
@onready var camera: ChaseCamera = $ChaseCamera
@onready var ui: RunUi = $RunUi
@onready var wind: Wind = get_node_or_null("Wind")


func _ready() -> void:
	surfer.pumped.connect(_on_pumped)
	surfer.air_started.connect(_on_air_started)
	surfer.air_landed.connect(_on_air_landed)
	start_wave()


func start_wave() -> void:
	# Immediate reset onto a fresh wave. The card flow calls this in the middle of its fade.
	wave_count += 1
	wave_duration = randf_range(wave_duration_min, wave_duration_max)
	time_left = INF if endless else wave_duration
	ride_time = 0.0
	barrel_seconds = 0.0
	longest_barrel = 0.0
	_barrel_streak = 0.0
	pocket_seconds = 0.0
	top_speed = 0.0
	sharp_turns = 0
	biggest_air = 0.0
	air_count = 0
	_was_sharp = false
	_live_t = 0.0
	_hint_step = 0
	if random_direction:
		wave.set_direction([1, -1].pick_random())
	wave.reset()
	surfer.spawn_rider()
	surfer.reset(Vector2(start_lead, 0.5), Vector2(spawn_speed, 0.0))
	surfer.input_enabled = true
	camera.snap()
	state = State.RIDING
	_state_t = 0.0
	if ui != null:
		ui.show_prompt("TAP to drop in")


func _physics_process(delta: float) -> void:
	if state != State.RIDING:
		return
	ride_time += delta
	if not endless:
		time_left -= delta
	_track_highlights(delta)
	var reason := ""
	if time_left <= 0.0:
		reason = "closed out"
	elif surfer.pos.x < wave.foam_u - caught_margin:
		reason = "caught by the foam"
	elif not surfer.forgiving and not surfer.soft_lip and surfer.pos.y > 1.0:
		reason = "over the lip"
	elif surfer.pos.y <= 0.0 and surfer.speed() < bog_speed:
		reason = "bogged in the flats"
	if reason != "":
		wave_over(reason)


func _process(delta: float) -> void:
	_state_t += delta / maxf(Engine.time_scale, 0.001)
	_update_feel_overlays()
	match state:
		State.RIDING:
			_update_prompts(delta)
		State.ENDING:
			if _state_t >= ending_seconds:
				_show_card()
		State.CARD:
			_update_card_input(delta)


func wave_over(reason: String) -> void:
	if state != State.RIDING:
		return
	last_reason = reason
	last_wave_time = ride_time
	print("Wave %d over after %.1f s: %s" % [wave_count, last_wave_time, reason])
	state = State.ENDING
	_state_t = 0.0
	surfer.input_enabled = false
	ui.hide_prompt()
	Engine.time_scale = ending_slowmo


func _show_card() -> void:
	Engine.time_scale = 1.0
	surfer.set_physics_process(false)
	wave.set_physics_process(false)
	state = State.CARD
	_state_t = 0.0
	var title := "WIPEOUT"
	var colour := Color(1.0, 0.55, 0.45)
	var sub := ""
	match last_reason:
		"closed out":
			title = "NICE RIDE"
			colour = Color(0.6, 1.0, 0.75)
			sub = "The wave closed out. That's the end of it, not a mistake."
		"caught by the foam":
			sub = "The whitewater caught you. Pump to stay ahead of the break."
		"bogged in the flats":
			sub = "You bogged in the flats. Stay up on the face."
		"over the lip":
			sub = "You went over the back."
	var lines := PackedStringArray()
	lines.append("%s on a %s   ·   %.0f s ride" % [surfer.rider_name(), surfer.board_description(), last_wave_time])
	lines.append("Top speed %.1f m/s   ·   Longest barrel %.1f s   ·   Biggest air %.1f m" % [top_speed, longest_barrel, biggest_air])
	lines.append("%d airs   ·   %d snaps   ·   %.0f s in the pocket" % [air_count, sharp_turns, pocket_seconds])
	ui.show_card(title, colour, sub, lines, "TAP to ride again", card_min_seconds)
	_card_hold = 0.0
	_card_toggled = false
	ui.set_mode_text(_mode_text())


func _mode_text() -> String:
	return "Endless mode: %s   ·   HOLD to switch" % ("ON" if endless else "OFF")


func _update_card_input(delta: float) -> void:
	# Tap (short press) = next wave. Hold = toggle endless mode. Auto-continue if nobody touches anything.
	if Input.is_action_pressed(Surfer.ACTION):
		_card_hold += delta
		if _card_hold >= card_hold_toggle and not _card_toggled:
			_card_toggled = true
			endless = not endless
			ui.set_mode_text(_mode_text())
		return
	if Input.is_action_just_released(Surfer.ACTION):
		var was_tap := _card_hold < card_hold_toggle and not _card_toggled
		_card_hold = 0.0
		_card_toggled = false
		if was_tap and _state_t >= card_min_seconds:
			_restart()
		return
	if _state_t >= card_auto_seconds:
		_restart()


func _update_feel_overlays() -> void:
	var riding := state == State.RIDING
	var spd := surfer.speed()
	ui.set_speed_lines(clampf((spd - 7.0) / 5.0, 0.0, 1.0) * 0.75 if riding else 0.0)
	if wind != null:
		wind.set_speed(spd if riding else 0.0)
	var anchor := surfer.global_position + Vector3(0.0, 2.4, 0.0)
	var show := riding and surfer.is_live and not camera.is_position_behind(anchor)
	ui.update_pump_ring(camera.unproject_position(anchor), surfer.pump_readiness(), show)


func _screen_at_rider() -> Vector2:
	return camera.unproject_position(surfer.global_position + Vector3(0.0, 2.0, 0.0))


func _on_pumped(quality: float, gain: float) -> void:
	if state != State.RIDING:
		return
	var text := "PUMP +%.1f" % gain
	if quality >= 0.8:
		text = "PERFECT PUMP +%.1f" % gain
	var colour := Color(0.75, 0.9, 1.0).lerp(Color(1.0, 0.85, 0.2), clampf((quality - 0.3) / 0.5, 0.0, 1.0))
	ui.popup(text, _screen_at_rider(), int(22 + 30 * quality), colour)


func _on_air_started(_vertical: float) -> void:
	if state == State.RIDING:
		ui.popup("AIR!", _screen_at_rider(), 34, Color(1, 1, 1))


func _on_air_landed(height: float, spin_deg: float, clean: bool) -> void:
	air_count += 1
	biggest_air = maxf(biggest_air, height)
	if state != State.RIDING:
		return
	var text := "%.1f m AIR" % height
	var spins := int(round(spin_deg / 180.0)) * 180
	if spins >= 180:
		text += "  %d°" % spins
	ui.popup(text, _screen_at_rider(), 30, Color(1.0, 0.85, 0.2))


func _restart() -> void:
	state = State.STARTING
	_state_t = 0.0
	await ui.fade_to(1.0, fade_seconds).finished
	ui.hide_card()
	surfer.set_physics_process(true)
	wave.set_physics_process(true)
	start_wave()
	await ui.fade_to(0.0, fade_seconds).finished


func _track_highlights(delta: float) -> void:
	top_speed = maxf(top_speed, surfer.speed())
	var d := wave.ahead_of_break(surfer.pos.x)
	if d < camera.barrel_enter:
		barrel_seconds += delta
		_barrel_streak += delta
		longest_barrel = maxf(longest_barrel, _barrel_streak)
	else:
		_barrel_streak = 0.0
	if wave.steepness(surfer.pos.x) > 0.5:
		pocket_seconds += delta
	if surfer.is_sharp and not _was_sharp:
		sharp_turns += 1
	_was_sharp = surfer.is_sharp


func _update_prompts(delta: float) -> void:
	if not surfer.is_live:
		return
	if _live_t == 0.0:
		ui.hide_prompt()
	_live_t += delta
	if not show_first_wave_hints or wave_count != 1:
		return
	if _hint_step == 0 and _live_t >= 1.0:
		_hint_step = 1
		ui.show_hint("TAP to switch direction", 3.0)
	elif _hint_step == 1 and _live_t >= 5.5:
		_hint_step = 2
		ui.show_hint("HOLD for a snap", 3.0)
	elif _hint_step == 2 and _live_t >= 10.0:
		_hint_step = 3
		ui.show_hint("Climb, then TAP at the top to pump", 3.5)
