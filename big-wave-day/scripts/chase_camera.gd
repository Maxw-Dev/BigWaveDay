## Third-person camera that sits high above and behind the surfer, back toward the breaking section.
## When the foam is close it hangs over the break; when the surfer pulls away it follows at `offset`.
## World-aligned: it never rotates with the board, so turns read clearly.
class_name ChaseCamera
extends Camera3D

@export_node_path("Node3D") var target_path: NodePath = ^"../Surfer"
@export_node_path("Node3D") var wave_path: NodePath = ^"../Wave"
@export var offset := Vector3(-8.0, 7.0, 5.0)   ## From the surfer: back toward the break (-X), up, and a little out over the flats (+Z).
@export var keep_foam_in_view := true           ## Hang back over the foam while it is close, so the player sees what is chasing them.
@export var foam_watch_distance := 20.0         ## Only while the foam is within this many metres of the surfer. Further away, follow at `offset`.
@export var foam_margin := 2.5                  ## Metres behind the foam wall when hanging over the break.
@export var look_ahead := 2.0                   ## Metres ahead of the surfer along the wave to aim at.
@export var look_up := 1.0                      ## Metres above the surfer to aim at, so the rider sits a little below centre.
@export var smoothing := 6.0                    ## Per second. Higher = tighter follow.

var target: Node3D
var wave: Wave


func _ready() -> void:
	target = get_node_or_null(target_path) as Node3D
	wave = get_node_or_null(wave_path) as Wave
	if target == null:
		push_warning("ChaseCamera: target_path %s did not resolve" % target_path)
	snap()


func _physics_process(delta: float) -> void:
	if target == null:
		return
	global_position = global_position.lerp(_desired_position(), 1.0 - exp(-smoothing * delta))
	look_at(_aim(), Vector3.UP)


func snap() -> void:
	if target == null:
		return
	global_position = _desired_position()
	look_at(_aim(), Vector3.UP)


func _desired_position() -> Vector3:
	var p := target.global_position + offset
	if keep_foam_in_view and wave != null and target.global_position.x - wave.foam_u < foam_watch_distance:
		p.x = minf(p.x, wave.foam_u - foam_margin)
	return p


func _aim() -> Vector3:
	return target.global_position + Vector3(look_ahead, look_up, 0.0)
