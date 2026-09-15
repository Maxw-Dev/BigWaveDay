## Pure geometry of the wave face. Shared by the mesh builder (wave.gd) and the surfer sim (surfer.gd).
##
## Face coordinates: u = metres along the wave (world +X), s = arc length up the face in metres
## (0 = trough, arc_length = lip). Negative s is flat water in front of the wave.
## The profile is an arc of a circle, so the slope angle at s is simply s / radius.
class_name WaveShape
extends Resource

@export var radius := 6.0                                ## R in metres. Face height is about 1.17 R at 100 degrees.
@export_range(30.0, 130.0) var max_angle_deg := 100.0    ## Above 90 the lip overhangs the rider.
@export var length := 500.0                              ## Metres along the wave. 25 s at 15 m/s is 375 m.
@export var flat_extent := 30.0                          ## Flat water rendered in front of the trough.

var arc_length: float:
	get:
		return radius * deg_to_rad(max_angle_deg)


func slope_angle(s: float) -> float:
	# Radians from horizontal. 0 on the flats, full vertical at s = radius * PI/2.
	return clampf(s, 0.0, arc_length) / radius


func surface_point(u: float, s: float) -> Vector3:
	if s <= 0.0:
		return Vector3(u, 0.0, -s)
	var a := s / radius
	return Vector3(u, radius * (1.0 - cos(a)), -radius * sin(a))


func tangent_up(s: float) -> Vector3:
	# Unit tangent in the +s direction.
	if s <= 0.0:
		return Vector3(0.0, 0.0, -1.0)
	var a := s / radius
	return Vector3(0.0, sin(a), -cos(a))


func normal(s: float) -> Vector3:
	# Points off the face toward the rider. +Y on the flats, +Z on the vertical section.
	return Vector3.RIGHT.cross(tangent_up(s))
