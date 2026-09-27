## Third-person camera. It always rides behind the surfer looking down the line, from a point measured off
## the wave face toward the hollow: the barrel view. Out on the open face it hangs well back (Follow); when
## the surfer is inside the breaking section it dollies in close (Barrel), and eases back out with hysteresis.
## World-aligned: it never rotates with the board.
class_name ChaseCamera
extends Camera3D

@export_node_path("Node3D") var target_path: NodePath = ^"../Surfer"
@export_node_path("Node3D") var wave_path: NodePath = ^"../Wave"

@export_group("Rig")
@export var face_h := 0.45                      ## Face height fraction the camera point is measured from. Shared by both distances so the angle stays the same.
@export var look_ahead := 1.5                   ## Metres ahead of the surfer along the wave to aim at.
@export var look_up := 2.5                      ## Aim above the rider so the lip folding overhead stays in frame.
@export var smoothing := 6.0                    ## Per second. Higher = tighter follow.
@export var break_margin := 0.5                 ## The camera never drops further back than this many metres ahead of the break, so it cannot end up in the whitewater.

@export_group("Follow")
@export var follow_back := 11.0                 ## Metres behind the surfer, down the line, out on the open face. The "how far away" knob.
@export var follow_depth := 4.0                 ## Metres off the face toward the flats. A little more than in the barrel keeps the angle similar from further back.
@export var follow_fov := 72.0
@export var fov_per_speed := 0.5                ## Degrees of extra FOV per m/s of surfer speed. Cheap sense of speed. Fades out in the barrel.

@export_group("Barrel")
@export var barrel_enter := 6.0                 ## Surfer this close to the break (metres ahead of it): camera zooms in.
@export var barrel_exit := 9.5                  ## Surfer this far ahead again: camera pulls back out.
@export var barrel_back := 6.0                  ## Metres behind the surfer while zoomed in.
@export var barrel_depth := 3.0                 ## Metres off the face toward the tube centre while zoomed in.
@export var barrel_fov := 72.0
@export var barrel_transition := 1.4            ## Seconds to dolly between the two distances.

var target: Node3D
var wave: Wave
var in_barrel := false
var _blend := 0.0                               ## 0 follow, 1 barrel; eased in time.


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
	global_position = global_position.lerp(_rig_position(w), 1.0 - exp(-smoothing * delta))
	look_at(_aim(), Vector3.UP)
	var speed_fov := (target as Surfer).speed() * fov_per_speed if target is Surfer else 0.0
	fov = lerpf(fov, lerpf(follow_fov + speed_fov, barrel_fov, w), 1.0 - exp(-4.0 * delta))


func snap() -> void:
	if target == null:
		return
	_update_mode()
	_blend = 1.0 if in_barrel else 0.0
	global_position = _rig_position(_blend)
	look_at(_aim(), Vector3.UP)
	fov = lerpf(follow_fov, barrel_fov, _blend)


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


func _rig_position(w: float) -> Vector3:
	# One rig for both modes: a point behind the surfer, off the face toward the hollow. Only the distances
	# change between follow (w = 0) and barrel (w = 1), so zooming in is a straight dolly along the same view.
	var back := lerpf(follow_back, barrel_back, w)
	var depth := lerpf(follow_depth, barrel_depth, w)
	if wave == null:
		return target.global_position + Vector3(-back * _dir(), look_up, depth)
	var cam_u := maxf(_surfer_u() - back, wave.foam_u + break_margin)
	return wave.world_point(cam_u, face_h) + wave.normal(cam_u, face_h) * depth


func _aim() -> Vector3:
	return target.global_position + Vector3(look_ahead * _dir(), look_up, 0.0)
