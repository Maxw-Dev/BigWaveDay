## Root of surf_prototype.tscn. Owns the wave lifecycle: timer, fail states, the end-of-wave card,
## and the reset to a fresh wave with a random direction, rider and board.
class_name SurfPrototype
extends Node3D

enum State { RIDING, ENDING, CARD, STARTING }

@export var wave_duration_min := 15.0
@export var wave_duration_max := 25.0
@export var start_lead := 12.0        ## Spawn distance ahead of the foam, metres.
@export var spawn_speed := 8.0
@export var bog_speed := 1.0          ## Below this on the flats the wave is over.
@export var caught_margin := 1.5      ## Metres behind the break line you may be before the foam has you. Inside the collapsing tube still counts as riding.
@export var random_direction := true  ## Pick left or right each wave.

@export_group("Reset flow")
@export var ending_slowmo := 0.3      ## Time scale while the wipeout plays out.
@export var ending_seconds := 0.7     ## Real seconds of slow motion before the card.
@export var card_min_seconds := 1.2   ## The card cannot be dismissed before this.
@export var card_auto_seconds := 4.0  ## The card dismisses itself after this.
@export var fade_seconds := 0.35
@export var show_first_wave_hints := true

var state := State.RIDING
var wave_count := 0
var wave_duration := 0.0
var time_left := 0.0
var last_reason := "-"
var last_wave_time := 0.0
var barrel_seconds := 0.0
var pocket_seconds := 0.0
var top_speed := 0.0
var sharp_turns := 0

var _state_t := 0.0
var _live_t := 0.0
var _hint_step := 0
var _was_sharp := false

@onready var wave: Wave = $Wave
@onready var surfer: Surfer = $Surfer
@onready var camera: ChaseCamera = $ChaseCamera
@onready var ui: RunUi = $RunUi


func _ready() -> void:
	start_wave()


func start_wave() -> void:
	# Immediate reset onto a fresh wave. The card flow calls this in the middle of its fade.
	wave_count += 1
	wave_duration = randf_range(wave_duration_min, wave_duration_max)
	time_left = wave_duration
	barrel_seconds = 0.0
	pocket_seconds = 0.0
	top_speed = 0.0
	sharp_turns = 0
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
	match state:
		State.RIDING:
			_update_prompts(delta)
		State.ENDING:
			if _state_t >= ending_seconds:
				_show_card()
		State.CARD:
			var pressed := Input.is_action_just_pressed(Surfer.ACTION) and _state_t >= card_min_seconds
			if pressed or _state_t >= card_auto_seconds:
				_restart()


func wave_over(reason: String) -> void:
	if state != State.RIDING:
		return
	last_reason = reason
	last_wave_time = wave_duration - time_left
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
	lines.append("Top speed %.1f m/s   ·   %.1f s in the barrel   ·   %d snaps" % [top_speed, barrel_seconds, sharp_turns])
	ui.show_card(title, colour, sub, lines, "TAP to ride again", card_min_seconds)


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
