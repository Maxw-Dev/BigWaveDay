## Root of surf_prototype.tscn. Owns the wave lifecycle: timer, fail states, instant respawn.
class_name SurfPrototype
extends Node3D

@export var wave_duration_min := 15.0
@export var wave_duration_max := 25.0
@export var start_lead := 12.0        ## Spawn distance ahead of the foam, metres.
@export var spawn_speed := 8.0
@export var bog_speed := 1.0          ## Below this on the flats the wave is over.
@export var caught_margin := 1.5      ## Metres behind the break line you may be before the foam has you. Inside the collapsing tube still counts as riding.

var wave_count := 0
var wave_duration := 0.0
var time_left := 0.0
var last_reason := "-"
var last_wave_time := 0.0

@onready var wave: Wave = $Wave
@onready var surfer: Surfer = $Surfer
@onready var camera: ChaseCamera = $ChaseCamera


func _ready() -> void:
	start_wave()


func start_wave() -> void:
	wave_count += 1
	wave_duration = randf_range(wave_duration_min, wave_duration_max)
	time_left = wave_duration
	wave.reset()
	surfer.reset(Vector2(start_lead, 0.5), Vector2(spawn_speed, 0.0))
	camera.snap()


func _physics_process(delta: float) -> void:
	time_left -= delta
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


func wave_over(reason: String) -> void:
	last_reason = reason
	last_wave_time = wave_duration - time_left
	print("Wave %d over after %.1f s: %s" % [wave_count, last_wave_time, reason])
	start_wave()   # Instant. The replay cam slots in here later.
