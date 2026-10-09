## Root of surf_prototype.tscn. Owns the wave lifecycle: timer, fail states, the end-of-wave card,
## and the reset to a fresh wave with a random direction, rider and board.
class_name SurfPrototype
extends Node3D

enum State { TITLE, RIDING, ENDING, REPLAY, CARD, STARTING }

@export var endless := false          ## No timer: the wave only ends when you wipe out. Hold on the card to toggle.
@export var wave_duration_min := 25.0
@export var wave_duration_max := 35.0
@export var start_lead := 12.0        ## Spawn distance ahead of the foam, metres.
@export var spawn_speed := 8.0
@export var bog_speed := 1.0          ## Below this on the flats the wave is over.
@export var caught_margin := 1.5      ## Metres behind the break line you may be before the foam has you. Inside the collapsing tube still counts as riding.
@export var random_direction := true  ## Pick left or right each wave.

@export_group("Wave ending")
@export var wave_fade_seconds := 8.0  ## Over the last this-many seconds of a timed wave, the whole wave shrinks...
@export var wave_end_size := 0.18     ## ...down to this fraction of its full size.
@export var wave_end_margin := 160.0  ## The wave line runs out this many metres past where the break will be at the end. With the 150 m taper, a rider
									  ## far down the line only meets the shrinking part in the last ~11 s.
@export var died_size := 0.5          ## Bogging where the wave is smaller than this counts as the wave ending, not a wipeout.

@export_group("Reset flow")
@export var ending_slowmo := 0.3      ## Time scale while the wipeout plays out.
@export var ending_seconds := 1.6     ## Real seconds of slow motion before the replay or card.
@export var card_min_seconds := 0.7   ## The card cannot be dismissed before this.
@export var card_auto_seconds := 5.0  ## The card dismisses itself after this.
@export var card_hold_toggle := 0.8   ## Holding this long on the card toggles endless mode.
@export var fade_seconds := 0.35

@export_group("Replay")
@export var replay_enabled := true
@export var replay_window := 5.0          ## Seconds of the ride shown, chosen as the highest-scoring stretch.
@export var replay_speed := 0.85          ## Playback rate. Under 1 is a little slow-motion.
@export var replay_min_ride := 5.0        ## Rides shorter than this skip the replay.
@export var replay_barrel_bias := 0.4                      ## Aim point sits this far from the rider toward the barrel's lip (0 = rider only, 1 = barrel only).
@export var replay_out_min := 9.0                          ## Camera distance out over the flats when the rider is in the tube...
@export var replay_out_max := 26.0                         ## ...and the most it backs off when the rider is far down the line.
@export var replay_out_per_metre := 0.5                    ## Extra metres of distance per metre between rider and barrel.
@export var replay_ahead_ratio := 0.35                     ## How far ahead of the rider (down the line) the camera sits, as a fraction of its distance out.
@export var replay_up_ratio := 0.32                        ## Camera height as a fraction of its distance out.
@export var replay_look_up := 1.2
@export var replay_cam_fov := 50.0
@export var replay_cam_smoothing := 5.0
@export var show_first_wave_hints := false  ## Text hints on the first wave. Off: the game shows, it does not tell.

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
var _frames: Array[Dictionary] = []
var _replay_cursor := 0.0
var _replay_start := 0
var _replay_end := 0
var _replay_cam: Camera3D
var _replay_anchor := Vector3.ZERO
var _title_hold := 0.0
var _title_toggled := false
var sfx: Sfx

var _state_t := 0.0
var _live_t := 0.0
var _hint_step := 0
var _was_sharp := false

@onready var wave: Wave = $Wave
@onready var surfer: Surfer = $Surfer
@onready var camera: ChaseCamera = $ChaseCamera
@onready var ui: RunUi = $RunUi
@onready var wind: Wind = get_node_or_null("Wind")
@onready var backdrop: Backdrop = get_node_or_null("Backdrop")


func _ready() -> void:
	surfer.pumped.connect(_on_pumped)
	surfer.air_started.connect(_on_air_started)
	surfer.air_landed.connect(_on_air_landed)
	_replay_cam = Camera3D.new()
	_replay_cam.name = "ReplayCam"
	_replay_cam.fov = replay_cam_fov
	add_child(_replay_cam)
	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	surfer.flipped.connect(func(s: float): sfx.splash(s / 12.0))
	surfer.snapped.connect(sfx.splash_big)
	start_wave()
	_enter_title()


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
	_frames.clear()
	_was_sharp = false
	_live_t = 0.0
	_hint_step = 0
	if random_direction:
		wave.set_direction([1, -1].pick_random())
	wave.reset()
	_apply_wave_end()
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
	if not surfer.is_live:
		# Waiting to drop in: the wave waits with you. Nothing can catch you, and the clock has not started.
		wave.set_physics_process(false)
		return
	if not wave.is_physics_processing():
		wave.set_physics_process(true)
	ride_time += delta
	if not endless:
		time_left -= delta
		# The wave visibly dies as time runs out: the whole thing shrinks over the last few seconds.
		var k := clampf(1.0 - time_left / wave_fade_seconds, 0.0, 1.0)
		wave.set_size(lerpf(1.0, wave_end_size, smoothstep(0.0, 1.0, k)))
		camera.outro = clampf(k * 2.0, 0.0, 1.0)   # pulled out to the wide shot by halfway through the fade
	wave.rider_at(surfer.pos.x, surfer.speed(), delta)
	if backdrop != null:
		backdrop.stream(surfer.global_position.x, wave.direction)
	_track_highlights(delta)
	_record_frame()
	var reason := ""
	if time_left <= 0.0:
		reason = "closed out"
	elif surfer.pos.x < wave.foam_u - caught_margin:
		reason = "caught by the foam"
	elif not surfer.forgiving and not surfer.soft_lip and surfer.pos.y > 1.0:
		reason = "over the lip"
	elif surfer.pos.y <= 0.0 and surfer.speed() < bog_speed:
		# If the wave has died under you, that is the end of the wave, not a mistake.
		reason = "closed out" if wave.size_at(surfer.pos.x) < died_size else "bogged in the flats"
	if reason != "":
		wave_over(reason)


func _process(delta: float) -> void:
	_state_t += delta / maxf(Engine.time_scale, 0.001)
	_update_feel_overlays()
	if Input.is_action_just_pressed("ui_cancel") and state != State.TITLE:
		_to_title()
		return
	match state:
		State.TITLE:
			_update_title_input(delta)
		State.RIDING:
			_update_prompts(delta)
		State.ENDING:
			if _state_t >= ending_seconds:
				if replay_enabled and ride_time >= replay_min_ride and _frames.size() > 60:
					_start_replay()
				else:
					_show_card()
		State.REPLAY:
			_update_replay(delta)
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
	if reason == "caught by the foam" and sfx != null:
		sfx.wipeout()


func _enter_title() -> void:
	# The wave sits still behind the title; the surfer is already placed on it.
	state = State.TITLE
	_state_t = 0.0
	_title_hold = 0.0
	_title_toggled = false
	surfer.input_enabled = false
	surfer.set_physics_process(false)
	wave.set_physics_process(false)
	ui.hide_prompt()
	ui.show_title(_title_mode_text())


func _apply_wave_end() -> void:
	# A timed wave runs out at the home island; an endless one never does. Called per wave, and again when
	# leaving the title, since endless can be toggled there after the wave was set up.
	time_left = INF if endless else wave_duration
	var end_u := INF if endless else wave.peel_speed * wave_duration + wave_end_margin
	wave.set_size(1.0, end_u)
	camera.outro = 0.0
	camera.outro_focus = Vector3.INF
	if backdrop != null:
		backdrop.arrange(wave.direction, end_u, endless)
		wave.set_shallows(backdrop.shallows_center(), backdrop.shallow_radius)
		if not endless:
			camera.outro_focus = backdrop.home_focus()


func _leave_title() -> void:
	_apply_wave_end()
	ui.hide_title()
	surfer.set_physics_process(true)
	wave.set_physics_process(true)
	surfer.input_enabled = true
	state = State.RIDING
	_state_t = 0.0
	ui.show_prompt("TAP to drop in")


func _to_title() -> void:
	Engine.time_scale = 1.0
	camera.current = true
	surfer.trail.visible = surfer.show_trail
	ui.set_letterbox(false)
	ui.hide_card()
	surfer.set_physics_process(true)
	wave.set_physics_process(true)
	start_wave()
	_enter_title()


func _title_mode_text() -> String:
	return "HOLD for endless mode: %s" % ("ON" if endless else "OFF")


func _update_title_input(delta: float) -> void:
	if Input.is_action_pressed(Surfer.ACTION):
		_title_hold += delta
		if _title_hold >= card_hold_toggle and not _title_toggled:
			_title_toggled = true
			endless = not endless
			ui.set_title_mode(_title_mode_text())
		return
	if Input.is_action_just_released(Surfer.ACTION):
		var was_tap := _title_hold < card_hold_toggle and not _title_toggled
		_title_hold = 0.0
		_title_toggled = false
		if was_tap and _state_t > 0.3:
			_leave_title()


func _record_frame() -> void:
	var f := surfer.capture_frame()
	f["foam"] = wave.foam_u
	f["amp"] = wave.amplitude
	var d := wave.ahead_of_break(surfer.pos.x)
	f["score"] = surfer.speed() * 0.1 + (1.5 if d < camera.barrel_enter else 0.0) + (0.8 if surfer.is_sharp else 0.0) + (3.0 if surfer.airborne else 0.0) + float(f.glow)
	_frames.append(f)


func _start_replay() -> void:
	# Find the highest-scoring stretch of the ride and play it back through a fixed camera on the flats.
	Engine.time_scale = 1.0
	surfer.set_physics_process(false)
	wave.set_physics_process(false)
	var n := _frames.size()
	var win := mini(int(replay_window * 60.0), n)
	var best := 0
	var best_sum := -1.0
	var sum := 0.0
	for i in range(n):
		sum += float(_frames[i].score)
		if i >= win:
			sum -= float(_frames[i - win].score)
		if i >= win - 1 and sum > best_sum:
			best_sum = sum
			best = i - win + 1
	_replay_start = best
	_replay_end = best + win
	_replay_cursor = float(best)
	_replay_cam.fov = replay_cam_fov
	_replay_cam.current = true
	surfer.trail.visible = false
	ui.set_letterbox(true)
	state = State.REPLAY
	_state_t = 0.0
	_apply_replay_frame(best)
	_replay_cam.global_position = _replay_cam_target()
	_replay_cam.look_at(_replay_aim(), Vector3.UP)


func _replay_barrel_point() -> Vector3:
	# The lip of the tube, just ahead of the break line of the frame being shown.
	return wave.world_point(wave.foam_u + 2.5, 0.92)


func _replay_cam_target() -> Vector3:
	# Stand out on the flats, a little ahead of the rider, far enough back that the barrel fits in the frame too.
	var sep := surfer.global_position.distance_to(_replay_barrel_point())
	var out := clampf(replay_out_min + sep * replay_out_per_metre, replay_out_min, replay_out_max)
	return surfer.global_position + Vector3(replay_ahead_ratio * out * wave.direction, replay_up_ratio * out, out)


func _replay_aim() -> Vector3:
	var rider := surfer.global_position + Vector3(0.0, replay_look_up, 0.0)
	return rider.lerp(_replay_barrel_point(), replay_barrel_bias)


func _apply_replay_frame(i: int) -> void:
	var f: Dictionary = _frames[clampi(i, 0, _frames.size() - 1)]
	surfer.apply_frame(f)
	wave.set_size(float(f.get("amp", 1.0)))
	wave.set_break(float(f.foam))


func _update_replay(delta: float) -> void:
	_replay_cursor += delta * 60.0 * replay_speed
	var skip := Input.is_action_just_released(Surfer.ACTION) and _state_t > 0.4
	if _replay_cursor >= _replay_end or skip:
		_end_replay()
		return
	_apply_replay_frame(int(_replay_cursor))
	# Tracking shot: slide along ahead of and outside the rider, always looking back at them.
	_replay_cam.global_position = _replay_cam.global_position.lerp(_replay_cam_target(), 1.0 - exp(-replay_cam_smoothing * delta))
	_replay_cam.look_at(_replay_aim(), Vector3.UP)


func _end_replay() -> void:
	# Back to the wipeout moment for the card.
	_apply_replay_frame(_frames.size() - 1)
	camera.current = true
	surfer.trail.visible = surfer.show_trail
	ui.set_letterbox(false)
	_show_card()


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
			sub = "The wave ran out by the island. That's the end of it, not a mistake."
		"caught by the foam":
			sub = "The whitewater caught you. Pump to stay ahead of the break."
		"bogged in the flats":
			sub = "You bogged in the flats. Stay up on the face."
		"over the lip":
			sub = "You went over the back."
	var lines := PackedStringArray()
	var top_line: String = "[b][color=#%s]%s [/color][/b]on a[b][color=#%s] %s[/color][/b]   ·   %.0f s ride" % [surfer.rider.end_screen_color.to_html(false), surfer.rider_name(), surfer.board_color.to_html(false), surfer.board_description(), last_wave_time]
	lines.append(top_line)
	if (air_count == 1): lines.append("[b][color=goldenrod]%d air[/color][/b]   ·   Biggest air %.1f m" % [air_count, biggest_air])
	else: lines.append("[b][color=goldenrod]%d airs[/color][/b]   ·   Biggest air %.1f m" % [air_count, biggest_air])
	lines.append("Longest barrel %.1f s   ·   %.0f s in the pocket" % [longest_barrel, pocket_seconds])
	lines.append("Top speed %.1f m/s   ·   %d snaps" % [top_speed, sharp_turns])
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
	#if _state_t >= card_auto_seconds:
		#_restart()


func _update_feel_overlays() -> void:
	var riding := state == State.RIDING
	var spd := surfer.speed()
	ui.set_speed_lines(clampf((spd - 7.0) / 5.0, 0.0, 1.0) * 0.75 if riding else 0.0)
	if wind != null:
		wind.set_speed(spd if riding else 0.0)
	if sfx != null:
		var d := wave.ahead_of_break(surfer.pos.x)
		sfx.set_break_closeness(clampf(1.0 - d / 25.0, 0.0, 1.0) if riding else 0.3)



func _on_pumped(quality: float, _gain: float) -> void:
	if quality >= 0.5 and sfx != null:
		sfx.pump(quality)


func _on_air_started(_vertical: float) -> void:
	if sfx != null:
		sfx.whoosh()


func _on_air_landed(height: float, _spin_deg: float, _clean: bool) -> void:
	air_count += 1
	biggest_air = maxf(biggest_air, height)
	if sfx != null:
		sfx.splash_big()


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
