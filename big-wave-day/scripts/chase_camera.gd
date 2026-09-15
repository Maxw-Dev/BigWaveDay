## Third-person camera. Outside the tube it sits close, high, and well out over the flats, facing the wave.
## When the surfer is inside the breaking section it moves into the barrel behind them, looking down the
## line with the lip overhead, and comes back out with hysteresis. World-aligned: it never rotates with the board.
class_name ChaseCamera
extends Camera3D

@export_node_path("Node3D") var target_path: NodePath = ^"../Surfer"
@export_node_path("Node3D") var wave_path: NodePath = ^"../Wave"

@export_group("Outside")
@export var offset := Vector3(-4.0, 6.0, 10.0)  ## From the surfer: a little behind (-X), up, and out over the flats (+Z) so it faces the wave.
@export var look_ahead := 1.5                   ## Metres ahead of the surfer along the wave to aim at.
@export var look_up := 1.0                      ## Metres above the surfer to aim at, so the rider sits a little below centre.
@export var smoothing := 6.0                    ## Per second. Higher = tighter follow.
@export var clearance := 1.5                    ## Metres the camera stays above the face's lip at its own position.
@export var keep_foam_in_view := false          ## Hang back over the break while it is close. Off: the tube is better seen from the side.
@export var foam_watch_distance := 20.0
@export var foam_margin := 2.5
@export var fov_base := 60.0
@export var fov_per_speed := 0.5                ## Degrees of extra FOV per m/s of surfer speed. Cheap sense of speed.

@export_group("Barrel")
@export var barrel_enter := 6.0                 ## Surfer this close to the break (metres ahead of it): camera goes inside the tube.
@export var barrel_exit := 9.5                  ## Surfer this far ahead again: camera comes back out.
@export var barrel_back := 6.0                  ## Metres behind the surfer, down the line, inside the tube.
@export var barrel_face_h := 0.45               ## Face height fraction the interior point is measured from...
@export var barrel_depth := 3.0                 ## ...and how far off the face toward the tube centre.
@export var barrel_look_up := 2.5               ## Aim above the rider so the lip folding overhead stays in frame.
@export var barrel_fov := 72.0
@export var barrel_transition := 1.4            ## Seconds to dolly between the outside and inside positions.

var target: Node3D
var wave: Wave
var in_barrel := false
var _blend := 0.0                               ## 0 outside, 1 inside; eased in time.


func _ready() -> void:
	target = get_node_or_null(target_path) as Node3D
	wave = get_node_or_null(wave_path) as Wave
	if target == null:
		push_warning("ChaseCamera: target_path %s did not resolve" % target_path)
	snap()


func _physics_process(delta: float) -> void:
	if target == null:
		return
	_update_mode()
	_blend = move_toward(_blend, 1.0 if in_barrel else 0.0, delta / barrel_transition)
	var w := smoothstep(0.0, 1.0, _blend)
	var desired := _outside_position().lerp(_inside_position(), w)
	global_position = global_position.lerp(desired, 1.0 - exp(-smoothing * delta))
	look_at(_outside_aim().lerp(_inside_aim(), w), Vector3.UP)
	var outside_fov := fov_base + ((target as Surfer).speed() * fov_per_speed if target is Surfer else 0.0)
	fov = lerpf(fov, lerpf(outside_fov, barrel_fov, w), 1.0 - exp(-4.0 * delta))


func snap() -> void:
	if target == null:
		return
	_update_mode()
	_blend = 1.0 if in_barrel else 0.0
	global_position = _inside_position() if in_barrel else _outside_position()
	look_at(_inside_aim() if in_barrel else _outside_aim(), Vector3.UP)


func _dir() -> int:
	return wave.direction if wave != null else 1


func _surfer_u() -> float:
	return target.global_position.x * _dir()


func _update_mode() -> void:
	if wave == null:
		in_barrel = false
		return
	var d := wave.ahead_of_break(_surfer_u())
	if in_barrel and (d > barrel_exit or d < -1.0):
		in_barrel = false
	elif not in_barrel and d < barrel_enter and d > -1.0:
		in_barrel = true


func _inside_position() -> Vector3:
	# Inside the tube, behind the surfer: a point off the face toward the hollow's centre.
	if wave == null:
		return _outside_position()
	var cam_u := maxf(_surfer_u() - barrel_back, wave.foam_u + 0.5)
	return wave.world_point(cam_u, barrel_face_h) + wave.normal(cam_u, barrel_face_h) * barrel_depth


func _outside_position() -> Vector3:
	var dir := _dir()
	var surfer_u := _surfer_u()
	var cam_u := surfer_u + offset.x
	if keep_foam_in_view and wave != null and surfer_u - wave.foam_u < foam_watch_distance:
		cam_u = minf(cam_u, wave.foam_u - foam_margin)
	var p := Vector3(cam_u * dir, target.global_position.y + offset.y, target.global_position.z + offset.z)
	if wave != null:
		p.y = maxf(p.y, wave.lip_top(cam_u) + clearance)
	return p


func _outside_aim() -> Vector3:
	return target.global_position + Vector3(look_ahead * _dir(), look_up, 0.0)


func _inside_aim() -> Vector3:
	return target.global_position + Vector3(look_ahead * _dir(), barrel_look_up, 0.0)
