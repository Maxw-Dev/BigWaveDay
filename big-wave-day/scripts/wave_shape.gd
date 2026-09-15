## Geometry of the wave, defined relative to the breaking section.
##
## d = metres ahead of the break (negative = behind it, already broken).
## h = height on the face as a fraction: 0 = trough, 1 = lip. Negative h is flat water in front of
##     the trough, measured in metres of arc. h in (1, 2] is the curl: the lip folding over, visual only.
## Near the break (the pocket) the face is tall and steep. Past `pocket_length` it blends into a lower,
## gentler shoulder. Within `curl_reach` of the break the lip throws over with a tighter radius and
## comes down ahead of the face; behind the break the profile collapses into a rounded whitewater
## mound that fades out. The face at any d is an arc of a circle, so the slope at height fraction h is
## simply h * lip_angle(d).
class_name WaveShape
extends Resource

@export_group("Pocket (at the break)")
@export var radius := 6.0                                ## Arc radius in the pocket. Lip height is radius * (1 - cos(max_angle)).
@export_range(30.0, 130.0) var max_angle_deg := 100.0    ## Above 90 the pocket lip overhangs the rider.

@export_group("Shoulder (down the line)")
@export var pocket_length := 30.0                        ## Metres ahead of the break that stay full size.
@export var shoulder_blend := 10.0                       ## Metres over which the pocket fades into the shoulder.
@export var shoulder_height := 3.0                       ## Lip height on the shoulder, metres.
@export_range(15.0, 100.0) var shoulder_angle_deg := 45.0 ## Steepest slope on the shoulder.

@export_group("Curl and whitewater")
@export var curl_reach := 8.0                            ## Metres ahead of the break where the lip starts to throw over.
@export var curl_radius := 5.5                           ## Radius of the folding lip, metres. Close to the face radius makes a round barrel.
@export_range(0.0, 300.0) var curl_angle_deg := 250.0    ## How far round the lip folds right at the break.
@export var crash_length := 4.0                          ## Metres behind the break over which the curl collapses into whitewater.
@export var whitewater_height := 4.0                     ## Height of the whitewater mound just behind the break.
@export var whitewater_fade := 25.0                      ## Metres behind the break over which the mound fades to flat water.

@export_group("Extents")
@export var length := 400.0                              ## Metres of wave rendered ahead of the break.
@export var back_extent := 40.0                          ## Metres rendered behind the break.
@export var flat_extent := 30.0                          ## Flat water rendered in front of the trough.

var pocket_height: float:
	get:
		return radius * (1.0 - cos(deg_to_rad(max_angle_deg)))


func steepness(d: float) -> float:
	# 1 in the pocket, 0 on the shoulder, smooth in between. Behind the break it falls to 0.
	if d < 0.0:
		return clampf(1.0 + d / crash_length, 0.0, 1.0)
	return 1.0 - smoothstep(pocket_length, pocket_length + shoulder_blend, d)


func broken(d: float) -> float:
	# 0 ahead of the break, 1 once the curl has fully collapsed into whitewater.
	return smoothstep(0.0, -crash_length, d) if d < 0.0 else 0.0


func lip_height(d: float) -> float:
	if d < 0.0:
		var mound := whitewater_height * clampf(1.0 + d / whitewater_fade, 0.0, 1.0)
		return maxf(lerpf(pocket_height, mound, broken(d)), 0.05)
	return lerpf(shoulder_height, pocket_height, steepness(d))


func lip_angle(d: float) -> float:
	# Radians. The face's steepest slope at this point down the line. Behind the break the profile rounds
	# off into a semicircular mound (180 degrees).
	if d < 0.0:
		return lerpf(deg_to_rad(max_angle_deg), PI, broken(d))
	return deg_to_rad(lerpf(shoulder_angle_deg, max_angle_deg, steepness(d)))


func curl_angle(d: float) -> float:
	# Radians of lip fold at this point: none out on the face, full at the break, gone once it has crashed.
	var amount: float
	if d < 0.0:
		amount = 1.0 - broken(d)
	else:
		amount = 1.0 - smoothstep(0.0, curl_reach, d)
	return maxf(deg_to_rad(curl_angle_deg) * amount, 0.01)


func arc_radius(d: float) -> float:
	return lip_height(d) / (1.0 - cos(lip_angle(d)))


func arc_length(d: float) -> float:
	# Metres of face from trough to lip at this point down the line.
	return arc_radius(d) * lip_angle(d)


func slope_angle(d: float, h: float) -> float:
	# Radians from horizontal at height fraction h. 0 on the flats.
	return clampf(h, 0.0, 1.0) * lip_angle(d)


func local_point(d: float, h: float) -> Vector3:
	# Position in the break's frame: x = d (not yet mirrored for direction).
	if h > 1.0:
		return _curl_point(d, (h - 1.0) * curl_angle(d))
	var s := h * arc_length(d)
	if s <= 0.0:
		return Vector3(d, 0.0, -s)
	var r := arc_radius(d)
	var a := s / r
	return Vector3(d, r * (1.0 - cos(a)), -r * sin(a))


func _curl_point(d: float, phi: float) -> Vector3:
	# The lip keeps turning past the face's end angle, but about a tighter circle tangent to the face there.
	var a := lip_angle(d)
	var lip := local_point(d, 1.0)
	var centre := Vector2(lip.z, lip.y) + curl_radius * Vector2(sin(a), cos(a))
	var p := centre + curl_radius * Vector2(-sin(a + phi), -cos(a + phi))
	return Vector3(d, p.y, p.x)


func top_height(d: float) -> float:
	# Highest point of the profile here, curl included. Used to keep the camera out of the wave.
	var top := lip_height(d)
	var a := lip_angle(d)
	var beta := curl_angle(d)
	if beta > 0.02:
		var lip := local_point(d, 1.0)
		var centre_y := lip.y + curl_radius * cos(a)
		if a + beta >= PI:
			top = maxf(top, centre_y + curl_radius)
		else:
			top = maxf(top, _curl_point(d, beta).y)
	return top


func throw_amount(d: float) -> float:
	# How much the lip is throwing here: 1 at the break, 0 beyond curl_reach.
	return 1.0 - smoothstep(0.0, curl_reach, maxf(d, 0.0))


func foam_amount(d: float, h: float) -> float:
	# 0 = clean water, 1 = whitewater, as seen on the OUTSIDE of the surface. The broken section behind the
	# break, the folding lip (white on its outside from the lip line to its tip), and a light feathering lip line.
	# The shader keeps the tube's interior glassy except at the tip; see fold_amount and tip_amount.
	var ww := 1.0 - smoothstep(-crash_length * 0.5, 1.5, d)
	var throw := throw_amount(d)
	var fold := 0.0
	if h > 1.0:
		fold = throw * clampf(0.5 + 0.5 * (h - 1.0), 0.0, 1.0)
	var lip_line := smoothstep(0.92, 1.0, minf(h, 1.0)) * throw * 0.5
	return maxf(ww, maxf(fold, lip_line))


func fold_amount(d: float, h: float) -> float:
	# 1 on the folding lip (h > 1) while it is throwing, 0 on the face. Lets the shader tint the tube's interior.
	return throw_amount(d) if h > 1.0 else 0.0


func tip_amount(d: float, h: float) -> float:
	# Rises toward the lip's tip so the tip is whitewater on both sides.
	return smoothstep(1.6, 2.0, h) if h > 1.0 else 0.0


func tangent_up(d: float, h: float) -> Vector3:
	# Unit tangent in the +h direction on the face, ignoring the slow change of shape along d.
	if h <= 0.0:
		return Vector3(0.0, 0.0, -1.0)
	var a := slope_angle(d, h)
	return Vector3(0.0, sin(a), -cos(a))


func normal(d: float, h: float) -> Vector3:
	# Points off the face toward the rider.
	return Vector3.RIGHT.cross(tangent_up(d, h))
