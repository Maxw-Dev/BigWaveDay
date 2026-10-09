## One-button surfer. Simulates in 2D wave-face coordinates and writes the result to the 3D transform.
##
## pos.x = u (metres along the wave), pos.y = h (height on the face as a fraction, 0 trough, 1 lip).
## vel is metres/second on the face; the vertical part is converted to a height fraction using the
## local face height, so the shape changing under you (pocket to shoulder) never throws you off it.
## Steering rotates the velocity vector, so the board always points where it travels.
## Tap = flip turn direction (and a pump check). Hold past the threshold = sharp turn until release.
class_name Surfer
extends Node3D

const ACTION := "surf"

signal pumped(quality: float, gain: float)
signal flipped(speed: float)
signal snapped()
signal air_started(vertical_speed: float)
signal air_landed(height: float, spin_deg: float, clean: bool)

@export_node_path("Node3D") var wave_path: NodePath = ^"../Wave"   ## The Wave to ride. Geometry and direction come from it.
@export var forgiving := false            ## Clamp s at the bottom too, so nothing ends the wave but the foam and the timer.
@export var soft_lip := true              ## Going over the lip pins you to it and scrubs speed instead of ending the wave.
@export var lip_drag := 0.6               ## Linear drag per second while pinned to the lip. Kept gentle: the shoulder lip is low and easy to hit at speed.

@export_group("Turning")
@export var turn_rate := 150.0            ## deg/s while carving. Bots: 110 cannot build speed against gravity, 150 can.
@export var sharp_turn_rate := 420.0      ## deg/s while the button is held past the threshold.
@export var sharp_hold_threshold := 0.18  ## Seconds of hold before a turn becomes sharp.
@export var bank_deg := 25.0
@export var sharp_bank_deg := 65.0
@export var bank_smoothing := 12.0        ## Per second. ~80 ms time constant.

@export_group("Speed")
@export var gravity := 9.8
@export var gravity_scale := 0.7          ## 1.0 makes mid-face gravity match the turn authority and the face plays like a wall.
@export var drag := 0.02                  ## Quadratic drag per metre. 2 m/s^2 at 10 m/s.
@export var sharp_drag_extra := 0.08      ## Added to drag while sharp: the speed scrub.
@export var sharp_scrub_fade_deg := 40.0  ## The scrub fades out as the heading rises to this angle: a held bottom turn drives up the face at speed; a snap at the top still scrubs on the way down.
@export var flat_drag := 0.8              ## Linear drag per second on the flats (s <= 0). Makes bogging real.

@export_group("Pumping")
@export var pump_gain := 4.0              ## m/s added by a perfect pump, fed in over pump_ramp_seconds.
@export var pump_ramp_seconds := 0.3      ## The fed-in part of the boost arrives over this long after the flip.
@export var pump_instant_fraction := 0.5  ## This much of the boost lands at the flip itself (it is what launches airs); the rest feeds in.
@export var pump_cooldown := 0.4          ## Spamming must never out-earn rhythm.
@export var pump_curve: Curve             ## x: heading at the flip, 0 = straight down the face, 1 = straight up. y: timing quality 0..1. Peaks on the top turn.
@export var shoulder_pump_scale := 0.25   ## Pump gain multiplier out on the shoulder (1 in the pocket). The pocket is where speed comes from; the shoulder is for spending it.

@export_group("Juice")
@export var spray_full_intensity := 60.0    ## speed (m/s) x turn rate (rad/s) that makes a full-size spray fan. A sharp turn at 10 m/s is ~73.
@export var spray_min_intensity := 8.0      ## Below this no spray, just the wake.
@export var crouch_scale := 0.65             ## Rider height while holding a sharp turn.
@export var pump_glow_color := Color(1.0, 0.9, 0.6)    ## Spray tint after a good pump, eased in and fading back to white. The burst itself stays gold.
@export var pump_burst_color := Color(1.0, 0.82, 0.3)
@export var pump_glow_seconds := 1.2
@export var pump_glow_rise := 0.3        ## Seconds for the tint to ease in, so it never snaps.
@export var wake_min_speed := 2.0

@export_group("Airs")
@export var airs_enabled := true
@export var air_min_vertical := 1.5        ## m/s of climb at the lip needed to leave the face. Slower than this rides the lip instead.
@export var climb_gravity_keep := 0.45     ## Fraction of gravity felt on a straight climb for an air (the face pushes you up). 1 = no help. Carving turns are unaffected.
@export var climb_drag_keep := 0.5         ## Fraction of drag felt on that climb.
@export var climb_assist_from_deg := 45.0  ## Heading where the climb help starts (0 = down the line, 90 = straight up)...
@export var climb_assist_full_deg := 70.0  ## ...and where it is full.
@export var air_gravity_scale := 1.0       ## Airs under normal gravity: a fast launch goes three-plus metres over the lip. Raise to shorten.
@export var air_land_h := 0.5              ## Height fraction of the face you come back down onto.
@export var air_land_heading_deg := -20.0  ## Heading you land with: slightly down the line, so speed carries.
@export var land_blend_seconds := 0.3      ## The board eases from its air orientation onto the face over this long.
@export var air_spin_rate := 150.0         ## deg/s the board spins in the air while carving (a typical air is ~1.5 s, so about a 180). Tap flips the spin, hold spins faster.
@export var air_sharp_spin_rate := 520.0
@export var air_landing_keep := 0.9        ## Fraction of speed kept on landing.

@export_group("Look")
@export var visual_scale := 1.25             ## Board and rider size relative to the wave.
@export var generate_board_mesh := true       ## Replace the placeholder box with a procedural surfboard.
@export var board_length := 2.7
@export var board_width := 0.62
@export var board_thickness := 0.1

@export var rider_scenes: Array[PackedScene]
@export var new_rider_every_wave := true      ## Off: keep the first animal for the whole session, only the colours re-roll.
@export_group("Board feel from length")
@export var turn_ref_length := 2.7            ## The board length at which turn_rate and sharp_turn_rate apply as written.
@export var turn_length_exponent := 0.8       ## Carve rate scales by (ref / length) ^ this. 0.8: a 3.1 m gun carves ~11% slower, a 2.3 m fish ~14% faster.
@export var sharp_length_exponent := 0.7      ## Snap rate scales by (ref / length) ^ this.
@export var deck_colors: Array[Color] = [Color(1.0, 0.45, 0.05), Color(0.95, 0.85, 0.2), Color(0.2, 0.75, 0.55), Color(0.9, 0.3, 0.35), Color(0.35, 0.55, 0.95), Color(0.95, 0.95, 0.9), Color(0.55, 0.3, 0.75)]
@export var stripe_colors: Array[Color] = [Color(0.1, 0.1, 0.12), Color(0.98, 0.98, 0.98), Color(0.9, 0.2, 0.2), Color(0.1, 0.4, 0.9)]


@export_group("Debug")
@export var trail_length := 120
@export var show_trail := false           ## The orange path line behind the rider. A tuning aid; F3 toggles it with the debug readout.
@export var override_rider: bool = false
@export var override_rider_num: int = 0

var pos := Vector2.ZERO
var vel := Vector2.ZERO
var turn_dir := 1                         ## +1 = turning toward the lip, -1 = toward the flats.
var hold_time := 0.0
var is_sharp := false
var pump_timer := 0.0
var last_pump_quality := 0.0
var time_since_pump := 999.0
var is_live := false                      ## False until the first press on a fresh wave: cruise straight, no steering, no gravity.

var wave: Wave

var _hold_armed := false                  ## A hold only counts after a fresh press (not one carried across a respawn).
var _pump_glow := 0.0                     ## 0..1, how recently and how well you pumped. Drives the spray tint.
var _pump_glow_target := 0.0
var _pump_left := 0.0                     ## m/s of pump boost still to feed in.
var _pump_rate := 0.0                     ## m/s per second it feeds in at.
var _forward := Vector3.RIGHT
var _bank := 0.0
var _trail_points := PackedVector3Array()
var _trail_mesh := ImmediateMesh.new()
var _spawn_vel := Vector2.ZERO           ## Velocity handed over on the first tap: the drop-in push.

@onready var board: Node3D = $Board
var rider: Rider
var input_enabled := true                 ## The run turns this off while a wave is ending.
var airborne := false
var air_height := 0.0                     ## Metres above the water directly below, while airborne.
var air_peak := 0.0
var air_spin := 0.0                       ## Degrees spun this air.
var _air_pos := Vector3.ZERO
var _air_vel := Vector3.ZERO
var _air_yaw := 0.0
var _air_launch_y := 0.0
var _air_t := 0.0
var _air_T := 1.0
var _air_vy := 0.0
var _air_vx := 0.0
var _air_x0 := 0.0
var _air_z0 := 0.0
var _air_speed0 := 0.0
var _land_blend := 0.0
var _land_from_forward := Vector3.RIGHT
var _land_from_up := Vector3.UP
var board_look := {}                      ## deck, stripe, tip colours and length, rolled per spawn.
var board_color: Color
var _rider_index := -1
@onready var spray: CPUParticles3D = $Board/Spray
@onready var burst: CPUParticles3D = $Board/SharpBurst
@onready var flip_splash: CPUParticles3D = $Board/FlipSplash
@onready var pump_burst: CPUParticles3D = $Board/PumpBurst
@onready var air_trail: CPUParticles3D = $Board/AirTrail
@onready var land_ring: CPUParticles3D = $LandRing
@onready var wake: CPUParticles3D = $Wake
@onready var trail: MeshInstance3D = $Trail

var _rider_rest_y := 0.0
var _base_board_length := 2.7
var _base_turn_rate := 140.0
var _base_sharp_rate := 375.0
var _was_sharp := false


func _ready() -> void:
	_ensure_input_action()
	wave = get_node_or_null(wave_path) as Wave
	if wave == null:
		push_error("Surfer: wave_path %s did not resolve. The surfer needs a Wave to ride." % wave_path)
		set_physics_process(false)
		return
	if pump_curve == null:
		pump_curve = _default_pump_curve()
	_base_board_length = board_length
	_base_turn_rate = turn_rate
	_base_sharp_rate = sharp_turn_rate
	board.scale = Vector3.ONE * visual_scale
	wake.position *= visual_scale
	_setup_particles()
	spawn_rider()
	trail.top_level = true
	trail.mesh = _trail_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.55, 0.1)
	trail.material_override = mat
	reset(Vector2(12.0, 0.5), Vector2(8.0, 0.0))


func spawn_rider() -> void:
	# Called every wave. A fresh animal (random unless overridden) brings its own board shape and feel;
	# the board's colours are re-rolled regardless.
	if rider != null and not new_rider_every_wave:
		if generate_board_mesh:
			_setup_board()
		return
	if rider != null:
		rider.queue_free()
		rider = null
	if rider_scenes.is_empty():
		push_warning("Surfer: no rider scenes assigned")
		return
	var index := override_rider_num
	if not override_rider:
		# Random, but never the same animal twice in a row, so the variety is visible.
		var choices: Array[int] = []
		for i in range(rider_scenes.size()):
			if i != _rider_index or rider_scenes.size() == 1:
				choices.append(i)
		index = choices.pick_random()
	index = clampi(index, 0, rider_scenes.size() - 1)
	_rider_index = index
	rider = rider_scenes[index].instantiate()
	board.add_child(rider)
	_rider_rest_y = rider.y_offset
	rider.position.y = _rider_rest_y
	board_width = rider.rider_width
	board_length = _base_board_length
	_apply_stats(rider.stats)
	if generate_board_mesh:
		_setup_board()


func _apply_stats(stats: RiderStats) -> void:
	if stats == null:
		return
	board_length = stats.board_length
	board_width = stats.board_width
	drag = stats.drag
	pump_gain = stats.pump_gain
	# Turning comes from the board: longer boards carve and snap slower, in wider arcs.
	var ratio := turn_ref_length / maxf(board_length, 0.5)
	turn_rate = _base_turn_rate * pow(ratio, turn_length_exponent) * stats.agility
	sharp_turn_rate = _base_sharp_rate * pow(ratio, sharp_length_exponent) * stats.agility


func rider_name() -> String:
	if rider != null and rider.model != null:
		return rider.model.name
	return "Rider"


func board_description() -> String:
	# Quoted at real-board scale (before visual_scale), so a gun reads as 10'6", not 13'.
	var metres: float = board_look.get("length", board_length)
	var inches := int(round(metres / 0.0254))
	var style := "board"
	if rider != null and rider.stats != null:
		style = rider.stats.style_name
	return "%d'%d\" %s %s" % [inches / 12, inches % 12, board_look.get("name", ""), style]


func reset(p: Vector2, v: Vector2) -> void:
	pos = p
	vel = v
	_spawn_vel = v
	turn_dir = 1
	hold_time = 0.0
	is_sharp = false
	is_live = false
	airborne = false
	air_height = 0.0
	air_peak = 0.0
	air_spin = 0.0
	_hold_armed = false
	pump_timer = 0.0
	last_pump_quality = 0.0
	time_since_pump = 999.0
	_pump_left = 0.0
	_bank = 0.0
	_was_sharp = false
	_forward = wave.along()
	_trail_points.clear()
	_trail_mesh.clear_surfaces()
	board.rotation = Vector3.ZERO
	if spray != null:
		spray.emitting = false
		wake.emitting = false
		rider.scale = Vector3.ONE
		rider.position.y = _rider_rest_y
	_apply_to_transform()


func _physics_process(delta: float) -> void:
	# 1. Input. The flip lands on the same tick as the press; nothing is buffered or locked out.
	if input_enabled and Input.is_action_just_pressed(ACTION):
		hold_time = 0.0
		_hold_armed = true
		if is_live:
			turn_dir = -turn_dir
			if not airborne:
				_try_pump()
				_flip_splash()
				flipped.emit(speed())
		else:
			is_live = true   # First press on a fresh wave drops in without flipping: the first arc is a climb.
			vel = _spawn_vel
	if input_enabled and _hold_armed and Input.is_action_pressed(ACTION):
		hold_time += delta
		is_sharp = hold_time >= sharp_hold_threshold
	else:
		is_sharp = false
		hold_time = 0.0

	var climb := 0.0   # 0..1, how much this tick is a straight climb for an air
	if airborne:
		_air_step(delta)
		_update_bank(delta)
		_update_trail()
		_update_juice(delta)
		return

	if is_live:
		# 2. Steer: rotate the velocity. The board always points where it travels.
		var rate := deg_to_rad(sharp_turn_rate if is_sharp else turn_rate)
		vel = vel.rotated(turn_dir * rate * delta)

		# 2b. Feed the pump boost in gradually after the top turn, along the heading as it comes back down.
		# Flipping back up early abandons whatever boost was left.
		if _pump_left > 0.0:
			if turn_dir != -1:
				_pump_left = 0.0
			else:
				var dose := minf(_pump_rate * delta, _pump_left)
				vel += vel.normalized() * dose
				_pump_left -= dose

		# 3. Gravity along the face: zero on the flats, full g on a vertical section. A committed straight climb
		# for an air feels less of it, and less drag, so you reach the lip with the speed you built.
		climb = smoothstep(climb_assist_from_deg, climb_assist_full_deg, heading_deg())
		var g_along := gravity * gravity_scale * sin(wave.slope_angle(pos.x, pos.y)) * lerpf(1.0, climb_gravity_keep, climb)
		vel.y -= g_along * delta

	# 4. Drag: quadratic, plus the sharp-turn scrub, plus sticky flats. The scrub is the snap: it bites while
	# turning down the face, not while driving up out of a bottom turn. Eased further on the climb for an air.
	var scrub := sharp_drag_extra * (1.0 - smoothstep(0.0, sharp_scrub_fade_deg, heading_deg())) if is_sharp else 0.0
	var k := (drag + scrub) * lerpf(1.0, climb_drag_keep, climb)
	vel -= vel * vel.length() * k * delta
	if pos.y <= 0.0:
		vel -= vel * flat_drag * delta

	if not is_live:
		vel = Vector2.ZERO   # Waiting to drop in: hold still. The run holds the wave still too.

	# 5. Integrate. Vertical metres become a height fraction of the local face.
	pos.x += vel.x * delta
	pos.y += vel.y * delta / wave.metres_per_h(pos.x, pos.y)
	if pos.y > 1.0 and airs_enabled and is_live and vel.y > air_min_vertical and wave.steepness(pos.x) > 0.05:
		_launch_air()
		_update_bank(delta)
		_update_trail()
		_update_juice(delta)
		return
	if soft_lip and pos.y > 1.0:
		pos.y = 1.0
		vel.y = minf(vel.y, 0.0)
		vel -= vel * lip_drag * delta
	if forgiving:
		pos.y = maxf(pos.y, -wave.shape.flat_extent / wave.metres_per_h(pos.x, -1.0))
		pos.y = minf(pos.y, 1.0)
	pump_timer = maxf(pump_timer - delta, 0.0)
	time_since_pump += delta
	_land_blend = maxf(_land_blend - delta, 0.0)

	# 6. Write to 3D.
	_update_bank(delta)
	_apply_to_transform()
	_update_trail()
	_update_juice(delta)


func _try_pump() -> void:
	if pump_timer > 0.0 or vel.length() < 0.5:
		return
	# Quality is pure timing, from the heading at the moment of the flip: flipping near the top of a steep
	# climb is the pump.
	var t := (rad_to_deg(vel.angle()) + 90.0) / 180.0
	var quality := pump_curve.sample(clampf(t, 0.0, 1.0))
	var where := lerpf(shoulder_pump_scale, 1.0, wave.steepness(pos.x))
	var gain := pump_gain * quality * where
	vel += vel.normalized() * gain * pump_instant_fraction
	_pump_left = gain * (1.0 - pump_instant_fraction)
	_pump_rate = _pump_left / maxf(pump_ramp_seconds, 0.05)
	last_pump_quality = quality
	time_since_pump = 0.0
	pump_timer = pump_cooldown
	if quality > 0.05:
		pumped.emit(quality, gain)
	_pump_glow_target = maxf(_pump_glow_target, quality)
	if quality >= 0.5:
		# A visible reward in the world: a gold burst off the rail, bigger the better the timing.
		pump_burst.direction = Vector3(float(wave.direction * turn_dir) * 0.5, 0.9, 0.4)
		pump_burst.scale_amount_min = 0.4 + 0.5 * quality
		pump_burst.scale_amount_max = 0.8 + 0.9 * quality
		pump_burst.initial_velocity_max = 5.0 + 6.0 * quality
		pump_burst.restart()


func pump_readiness() -> float:
	# How good a tap right now would be, 0..1. Only meaningful while climbing toward the lip.
	if not is_live or airborne or turn_dir != 1 or vel.y <= 0.0 or vel.length() < 0.5:
		return 0.0
	var t := (rad_to_deg(vel.angle()) + 90.0) / 180.0
	return pump_curve.sample(clampf(t, 0.0, 1.0)) * lerpf(shoulder_pump_scale, 1.0, wave.steepness(pos.x))


func _launch_air() -> void:
	# Leave the lip on a designed arc: real ballistics up and down, but the sideways drift is steered so you
	# always come back onto the face at air_land_h. That is what the wave moving under you does in real life.
	pos.y = 1.0
	_air_pos = wave.world_point(pos.x, 1.0)
	_air_launch_y = _air_pos.y
	_pump_left = 0.0
	_air_x0 = _air_pos.x
	_air_z0 = _air_pos.z
	_air_vy = vel.y
	_air_vx = vel.x
	_air_speed0 = vel.length()
	var g := gravity * air_gravity_scale
	var land_y := wave.world_point(pos.x, air_land_h).y
	var drop := maxf(_air_launch_y - land_y, 0.0)
	_air_T = (_air_vy + sqrt(_air_vy * _air_vy + 2.0 * g * drop)) / g
	_air_t = 0.0
	_air_vel = wave.along() * _air_vx + Vector3.UP * _air_vy
	_air_yaw = 0.0
	air_spin = 0.0
	air_peak = 0.0
	air_height = 0.0
	airborne = true
	burst.direction = Vector3(0.0, 1.0, 0.4)
	burst.restart()
	air_started.emit(vel.y)


func _air_step(delta: float) -> void:
	_air_t += delta
	var g := gravity * air_gravity_scale
	var rate := deg_to_rad(air_sharp_spin_rate if is_sharp else air_spin_rate)
	var step := turn_dir * rate * delta
	_air_yaw += step
	air_spin += absf(rad_to_deg(step))
	var u := (_air_x0 + _air_vx * _air_t * wave.direction) * wave.direction
	pos.x = u
	var land := wave.world_point(u, air_land_h)
	var k := smoothstep(0.0, 1.0, _air_t / _air_T)
	_air_pos = Vector3(u * wave.direction, _air_launch_y + _air_vy * _air_t - 0.5 * g * _air_t * _air_t, lerpf(_air_z0, land.z, k))
	_air_vel = Vector3(wave.direction * _air_vx, _air_vy - g * _air_t, 0.0)
	air_height = maxf(_air_pos.y - _air_launch_y, 0.0)
	air_peak = maxf(air_peak, air_height)
	if _air_t >= _air_T:
		_land(u)
		return
	var forward := wave.along().rotated(Vector3.UP, _air_yaw)
	global_transform = Transform3D(Basis.looking_at(forward, Vector3.UP), _air_pos)


func _land(u: float) -> void:
	# Back on the face halfway up, heading slightly down the line, with most of your speed. The board's
	# orientation eases over from the air pose instead of snapping.
	airborne = false
	_land_from_forward = -global_transform.basis.z
	_land_from_up = global_transform.basis.y
	_land_blend = land_blend_seconds
	pos = Vector2(u, air_land_h)
	# Landing VFX: a ring of spray on the water, sized by the air.
	var big := clampf(0.5 + air_peak * 0.5, 0.5, 2.0)
	land_ring.scale_amount_min = 0.6 * big
	land_ring.scale_amount_max = 1.3 * big
	land_ring.initial_velocity_max = 2.0 + 3.0 * big
	var heading := deg_to_rad(air_land_heading_deg)
	vel = Vector2(cos(heading), sin(heading)) * _air_speed0 * air_landing_keep
	turn_dir = 1   # Landing sets you up climbing, which reads as a natural recovery.
	_apply_to_transform()
	land_ring.global_position = global_position + wave.normal(pos.x, pos.y) * 0.1
	land_ring.restart()
	burst.direction = Vector3(0.0, 0.9, 0.5)
	burst.restart()
	air_landed.emit(air_peak, air_spin, true)


func capture_frame() -> Dictionary:
	# Everything the replay needs to re-pose the surfer and its particles for one tick.
	return {
		"xf": global_transform,
		"board": board.rotation,
		"rider_y": rider.position.y if rider != null else 0.0,
		"rider_sy": rider.scale.y if rider != null else 1.0,
		"spray": spray.emitting,
		"spray_dir": spray.direction,
		"spray_v": spray.initial_velocity_max,
		"wake": wake.emitting,
		"air": airborne,
		"glow": _pump_glow,
		"speed": speed(),
		"sharp": is_sharp,
	}


func apply_frame(f: Dictionary) -> void:
	global_transform = f.xf
	board.rotation = f.board
	if rider != null:
		rider.position.y = f.rider_y
		rider.scale = Vector3(1.0, f.rider_sy, 1.0)
	spray.emitting = f.spray
	spray.direction = f.spray_dir
	spray.initial_velocity_max = f.spray_v
	wake.emitting = f.wake
	air_trail.emitting = f.air
	spray.color = Color.WHITE.lerp(pump_glow_color, f.glow)
	wake.color = Color.WHITE


func speed() -> float:
	return _air_vel.length() if airborne else vel.length()


func heading_deg() -> float:
	# 0 = straight down the line, +90 = straight up the face, -90 = straight down the face.
	if vel.length_squared() < 1e-6:
		return 0.0
	return rad_to_deg(vel.angle())


func _update_bank(delta: float) -> void:
	# Board forward is local -Z. On a left a positive roll about Z dips the lip-side rail; mirrored on a right.
	var target := 0.0
	if is_live:
		target = wave.direction * turn_dir * deg_to_rad(sharp_bank_deg if is_sharp else bank_deg)
	_bank = lerpf(_bank, target, 1.0 - exp(-bank_smoothing * delta))
	board.rotation = Vector3(0.0, 0.0, _bank)


func _apply_to_transform() -> void:
	var n := wave.normal(pos.x, pos.y)
	if vel.length_squared() > 1e-4:
		var d := vel.normalized()
		_forward = wave.along() * d.x + wave.tangent_up(pos.x, pos.y) * d.y
	# Keep the remembered forward in the tangent plane of the current spot.
	_forward = _forward - n * _forward.dot(n)
	if _forward.length_squared() < 1e-6:
		_forward = wave.along()
	_forward = _forward.normalized()
	var fwd := _forward
	var up := n
	if _land_blend > 0.0:
		var k := 1.0 - _land_blend / land_blend_seconds
		fwd = _land_from_forward.slerp(_forward, k).normalized()
		up = _land_from_up.slerp(n, k).normalized()
		if absf(fwd.dot(up)) > 0.99:
			fwd = _forward
			up = n
	global_transform = Transform3D(Basis.looking_at(fwd, up), wave.world_point(pos.x, pos.y))


func _update_trail() -> void:
	trail.visible = show_trail
	if not show_trail:
		if _trail_points.size() > 0:
			_trail_points.clear()
			_trail_mesh.clear_surfaces()
		return
	_trail_points.push_back(global_position + wave.normal(pos.x, pos.y) * 0.05)
	while _trail_points.size() > trail_length:
		_trail_points.remove_at(0)
	_trail_mesh.clear_surfaces()
	if _trail_points.size() < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in _trail_points:
		_trail_mesh.surface_add_vertex(p)
	_trail_mesh.surface_end()


func _update_juice(delta: float) -> void:
	var rate := deg_to_rad(sharp_turn_rate if is_sharp else turn_rate) if (is_live and not airborne) else 0.0
	var intensity := clampf((speed() * rate - spray_min_intensity) / (spray_full_intensity - spray_min_intensity), 0.0, 1.5)
	# Spray fan off the rail, thrown to the outside of the turn. Size follows how hard you are turning.
	var outward := float(wave.direction * turn_dir)
	spray.emitting = is_live and intensity > 0.0
	spray.direction = Vector3(outward * 0.9, 0.5, 0.5)
	spray.initial_velocity_min = 1.5 + 6.0 * intensity
	spray.initial_velocity_max = 3.0 + 9.0 * intensity
	spray.scale_amount_min = (0.4 + 0.5 * intensity) * (1.0 + 0.4 * _pump_glow)
	spray.scale_amount_max = (0.8 + 0.9 * intensity) * (1.0 + 0.6 * _pump_glow)
	# Foamy wake dropped on the water behind the board: the cheapest way to say "this is water".
	wake.emitting = is_live and not airborne and speed() > wake_min_speed
	# Pump glow: the spray warms up after a good pump, easing in and fading back out. The wake stays white.
	_pump_glow_target = move_toward(_pump_glow_target, 0.0, delta / pump_glow_seconds)
	if _pump_glow < _pump_glow_target:
		_pump_glow = move_toward(_pump_glow, _pump_glow_target, delta / pump_glow_rise)
	else:
		_pump_glow = _pump_glow_target
	spray.color = Color.WHITE.lerp(pump_glow_color, _pump_glow)
	wake.color = Color.WHITE
	# Air trail: streaks off the board while airborne.
	air_trail.emitting = airborne
	# Sharp turn: one big splash on entry, and the rider crouches while it lasts.
	if is_sharp and not _was_sharp:
		burst.direction = Vector3(outward * 0.8, 0.7, 0.4)
		burst.restart()
		snapped.emit()
	_was_sharp = is_sharp
	var crouch := crouch_scale if is_sharp else 1.0
	var k := 1.0 - exp(-14.0 * delta)
	rider.scale = rider.scale.lerp(Vector3(1.0, crouch, 1.0), k)
	rider.position.y = lerpf(rider.position.y, _rider_rest_y * crouch, k)


func _setup_board() -> void:
	# Roll a look: deck colour, an optional centre stripe, a contrasting nose, and a little length variation.
	var deck: Color = deck_colors.pick_random() if not deck_colors.is_empty() else Color(1.0, 0.45, 0.05)
	var stripe: Color = stripe_colors.pick_random() if not stripe_colors.is_empty() else Color.BLACK
	var names := {"orange": Color(1.0, 0.45, 0.05), "yellow": Color(0.95, 0.85, 0.2), "green": Color(0.2, 0.75, 0.55), "red": Color(0.9, 0.3, 0.35), "blue": Color(0.35, 0.55, 0.95), "white": Color(0.95, 0.95, 0.9), "purple": Color(0.55, 0.3, 0.75)}
	var deck_name := ""
	for n in names:
		if names[n].is_equal_approx(deck):
			deck_name = n
			board_color = n
	board_look = {"deck": deck, "stripe": stripe, "has_stripe": randf() < 0.6, "tip": stripe if randf() < 0.5 else deck.darkened(0.3),
		"length": board_length, "name": deck_name}
	board.mesh = _build_board_mesh(board_look.length, board_width, board_thickness)
	for child in board.get_children():
		if child.name == "Fin":
			child.queue_free()
	if board.material_override is BaseMaterial3D:
		var m := board.material_override as BaseMaterial3D
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color.WHITE
		m.vertex_color_use_as_albedo = true
	var fin := MeshInstance3D.new()
	fin.name = "Fin"
	var prism := PrismMesh.new()
	prism.size = Vector3(0.025, 0.24, 0.26)
	prism.left_to_right = 0.85
	fin.mesh = prism
	# PrismMesh points up along +Y; hang it under the tail, raked back.
	fin.rotation_degrees = Vector3(180.0, 0.0, 0.0)
	fin.position = Vector3(0.0, -board_thickness * 0.5 - 0.11, board_look.get("length", board_length) * 0.34)
	var fin_mat := StandardMaterial3D.new()
	fin_mat.albedo_color = Color(0.1, 0.1, 0.12)
	fin_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fin.material_override = fin_mat
	board.add_child(fin)


func _build_board_mesh(length: float, width: float, thick: float) -> ArrayMesh:
	# A surfboard lofted from elliptical rail sections: pointed nose at -Z (forward), wider ahead of the
	# middle, narrower rounded tail at +Z, a little rocker. No modelling tool needed.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_len := 28
	var n_around := 14
	for i in range(n_len + 1):
		var t := float(i) / n_len                     # 0 = tail, 1 = nose
		var z := (0.5 - t) * length
		var half_w := width * 0.5 * _board_outline(t)
		var half_t := thick * 0.5 * _board_thickness(t)
		var rocker := 0.045 * length * pow(absf(t - 0.45) / 0.55, 2.2)
		for j in range(n_around):
			var a := TAU * float(j) / n_around
			var col: Color = board_look.get("deck", Color(1.0, 0.45, 0.05))
			if t > 0.86:
				col = board_look.get("tip", col)
			elif board_look.get("has_stripe", false) and sin(a) > 0.0 and absf(cos(a)) < 0.28:
				col = board_look.get("stripe", col)
			st.set_color(col)
			st.add_vertex(Vector3(cos(a) * half_w, sin(a) * half_t + rocker, z))
	for i in range(n_len):
		for j in range(n_around):
			var a := i * n_around + j
			var b := i * n_around + (j + 1) % n_around
			var c := a + n_around
			var d := b + n_around
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	st.generate_normals()
	return st.commit()


func _board_outline(t: float) -> float:
	# Half-width factor along the board. Widest at 45% from the tail, elliptical taper to the nose point,
	# gentle pull-in to a rounded tail.
	var nose := 1.0
	if t > 0.45:
		var q := (t - 0.45) / 0.55
		nose = sqrt(maxf(1.0 - q * q, 0.0))
	var tail := lerpf(0.62, 1.0, smoothstep(0.0, 0.45, t)) * sqrt(smoothstep(0.0, 0.07, t))
	return nose * tail


func _board_thickness(t: float) -> float:
	var q := (t - 0.5) / 0.5
	return maxf(sqrt(maxf(1.0 - q * q, 0.0)), 0.12)


func _flip_splash() -> void:
	# A small splash on every direction switch, scaled by speed. The sharp-turn burst stays bigger.
	if speed() < 3.0:
		return
	var k := clampf(speed() / 10.0, 0.3, 1.5)
	flip_splash.initial_velocity_min = 1.5 * k
	flip_splash.initial_velocity_max = 4.0 * k
	flip_splash.direction = Vector3(float(wave.direction * turn_dir) * 0.6, 0.8, 0.5)
	flip_splash.restart()


func _setup_particles() -> void:
	var drop := SphereMesh.new()
	drop.radius = 0.12
	drop.height = 0.24
	drop.radial_segments = 6
	drop.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color.WHITE
	drop.material = mat
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.95))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))

	spray.mesh = drop
	spray.amount = 120
	spray.lifetime = 0.6
	spray.spread = 35.0
	spray.gravity = Vector3(0.0, -9.8, 0.0)
	spray.color_ramp = fade
	spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	spray.emission_sphere_radius = 0.15

	burst.mesh = drop
	burst.amount = 70
	burst.lifetime = 0.8
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.spread = 60.0
	burst.gravity = Vector3(0.0, -9.8, 0.0)
	burst.initial_velocity_min = 5.0
	burst.initial_velocity_max = 11.0
	burst.scale_amount_min = 0.8
	burst.scale_amount_max = 1.8
	burst.color_ramp = fade
	burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 0.3

	flip_splash.mesh = drop
	flip_splash.amount = 26
	flip_splash.lifetime = 0.45
	flip_splash.one_shot = true
	flip_splash.explosiveness = 1.0
	flip_splash.spread = 50.0
	flip_splash.gravity = Vector3(0.0, -9.8, 0.0)
	flip_splash.scale_amount_min = 0.5
	flip_splash.scale_amount_max = 1.0
	flip_splash.color_ramp = fade
	flip_splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flip_splash.emission_sphere_radius = 0.25

	pump_burst.mesh = drop
	pump_burst.amount = 48
	pump_burst.lifetime = 0.7
	pump_burst.one_shot = true
	pump_burst.explosiveness = 1.0
	pump_burst.spread = 55.0
	pump_burst.gravity = Vector3(0.0, -9.8, 0.0)
	pump_burst.initial_velocity_min = 3.0
	pump_burst.initial_velocity_max = 8.0
	pump_burst.color = pump_burst_color
	pump_burst.color_ramp = fade
	pump_burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	pump_burst.emission_sphere_radius = 0.3

	air_trail.mesh = drop
	air_trail.amount = 70
	air_trail.lifetime = 0.7
	air_trail.direction = Vector3(0.0, -0.3, 1.0)
	air_trail.spread = 25.0
	air_trail.gravity = Vector3(0.0, -6.0, 0.0)
	air_trail.initial_velocity_min = 1.0
	air_trail.initial_velocity_max = 3.0
	air_trail.scale_amount_min = 0.35
	air_trail.scale_amount_max = 0.8
	air_trail.color = Color(0.85, 0.95, 1.0)
	air_trail.color_ramp = fade
	air_trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	air_trail.emission_box_extents = Vector3(0.3, 0.05, 0.9)

	land_ring.top_level = true
	land_ring.mesh = drop
	land_ring.amount = 70
	land_ring.lifetime = 0.8
	land_ring.one_shot = true
	land_ring.explosiveness = 1.0
	land_ring.direction = Vector3(0.0, 1.0, 0.0)
	land_ring.spread = 180.0
	land_ring.gravity = Vector3(0.0, -7.0, 0.0)
	land_ring.radial_accel_min = 18.0
	land_ring.radial_accel_max = 26.0
	land_ring.initial_velocity_min = 1.0
	land_ring.initial_velocity_max = 3.0
	land_ring.color_ramp = fade
	land_ring.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	land_ring.emission_ring_radius = 0.7
	land_ring.emission_ring_inner_radius = 0.4
	land_ring.emission_ring_height = 0.1
	land_ring.emission_ring_axis = Vector3.UP

	var foam_mesh := SphereMesh.new()
	foam_mesh.radius = 0.16
	foam_mesh.height = 0.08
	foam_mesh.radial_segments = 10
	foam_mesh.rings = 3
	foam_mesh.material = mat
	wake.mesh = foam_mesh
	wake.amount = 90
	wake.lifetime = 1.6
	wake.gravity = Vector3.ZERO
	wake.initial_velocity_min = 0.0
	wake.initial_velocity_max = 0.3
	wake.spread = 180.0
	wake.scale_amount_min = 0.5
	wake.scale_amount_max = 1.1
	wake.color_ramp = fade
	wake.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	wake.emission_sphere_radius = 0.35


func _default_pump_curve() -> Curve:
	# Nothing until the flip is ~10 degrees into a climb, full payoff by about +60 degrees.
	# Early, timid flips earn little; flipping near the top of a steep climb is the pump.
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(0.56, 0.0))
	c.add_point(Vector2(0.83, 1.0))
	c.add_point(Vector2(1.0, 1.0))
	return c


func _ensure_input_action() -> void:
	# Registered in code so project.godot stays untouched. Define "surf" in the Input Map to override.
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION)
	# Still one button, on three inputs: Space, left mouse (phone taps arrive as emulated clicks), gamepad A.
	# Every binding is for ALL devices (-1). Events created in code default to device 0, and an emulated
	# click from a phone tap carries device -1 (DEVICE_ID_EMULATION), which a device-0 binding silently ignores.
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.device = -1
	InputMap.action_add_event(ACTION, key)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.device = -1
	InputMap.action_add_event(ACTION, mouse)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.device = -1
	InputMap.action_add_event(ACTION, pad)
