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
@export var flat_drag := 0.8              ## Linear drag per second on the flats (s <= 0). Makes bogging real.

@export_group("Pumping")
@export var pump_gain := 4.0              ## m/s added by a perfect pump.
@export var pump_cooldown := 0.4          ## Spamming must never out-earn rhythm.
@export var pump_curve: Curve             ## x: heading, 0 = straight down the face, 1 = straight up. y: quality 0..1.
@export var shoulder_pump_scale := 0.25   ## Pump gain multiplier out on the shoulder (1 in the pocket). The pocket is where speed comes from; the shoulder is for spending it.

@export_group("Juice")
@export var spray_full_intensity := 60.0    ## speed (m/s) x turn rate (rad/s) that makes a full-size spray fan. A sharp turn at 10 m/s is ~73.
@export var spray_min_intensity := 8.0      ## Below this no spray, just the wake.
@export var crouch_scale := 0.65             ## Rider height while holding a sharp turn.
@export var wake_min_speed := 2.0

@export_group("Look")
@export var visual_scale := 1.25             ## Board and rider size relative to the wave.
@export var generate_board_mesh := true       ## Replace the placeholder box with a procedural surfboard.
@export var board_length := 2.7
@export var board_width := 0.62
@export var board_thickness := 0.1

@export_group("Debug")
@export var trail_length := 120

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
var _forward := Vector3.RIGHT
var _bank := 0.0
var _trail_points := PackedVector3Array()
var _trail_mesh := ImmediateMesh.new()

@onready var board: Node3D = $Board
@onready var rider: Node3D = $Board/Rider
@onready var spray: CPUParticles3D = $Board/Spray
@onready var burst: CPUParticles3D = $Board/SharpBurst
@onready var wake: CPUParticles3D = $Wake
@onready var trail: MeshInstance3D = $Trail

var _rider_rest_y := 0.0
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
	_rider_rest_y = rider.position.y
	board.scale = Vector3.ONE * visual_scale
	wake.position *= visual_scale
	if generate_board_mesh:
		_setup_board()
	_setup_particles()
	trail.top_level = true
	trail.mesh = _trail_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.55, 0.1)
	trail.material_override = mat
	reset(Vector2(12.0, 0.5), Vector2(8.0, 0.0))


func reset(p: Vector2, v: Vector2) -> void:
	pos = p
	vel = v
	turn_dir = 1
	hold_time = 0.0
	is_sharp = false
	is_live = false
	_hold_armed = false
	pump_timer = 0.0
	last_pump_quality = 0.0
	time_since_pump = 999.0
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
	if Input.is_action_just_pressed(ACTION):
		hold_time = 0.0
		_hold_armed = true
		if is_live:
			turn_dir = -turn_dir
			_try_pump()
		else:
			is_live = true   # First press on a fresh wave drops in without flipping: the first arc is a climb.
	if _hold_armed and Input.is_action_pressed(ACTION):
		hold_time += delta
		is_sharp = hold_time >= sharp_hold_threshold
	else:
		is_sharp = false
		hold_time = 0.0

	if is_live:
		# 2. Steer: rotate the velocity. The board always points where it travels.
		var rate := deg_to_rad(sharp_turn_rate if is_sharp else turn_rate)
		vel = vel.rotated(turn_dir * rate * delta)

		# 3. Gravity along the face: zero on the flats, full g on a vertical section.
		var g_along := gravity * gravity_scale * sin(wave.slope_angle(pos.x, pos.y))
		vel.y -= g_along * delta

	# 4. Drag: quadratic, plus the sharp-turn scrub, plus sticky flats.
	var k := drag + (sharp_drag_extra if is_sharp else 0.0)
	vel -= vel * vel.length() * k * delta
	if pos.y <= 0.0:
		vel -= vel * flat_drag * delta

	# 5. Integrate. Vertical metres become a height fraction of the local face.
	pos.x += vel.x * delta
	pos.y += vel.y * delta / wave.arc_length(pos.x)
	if soft_lip and pos.y > 1.0:
		pos.y = 1.0
		vel.y = minf(vel.y, 0.0)
		vel -= vel * lip_drag * delta
	if forgiving:
		pos.y = maxf(pos.y, -wave.shape.flat_extent / wave.arc_length(pos.x))
		pos.y = minf(pos.y, 1.0)
	pump_timer = maxf(pump_timer - delta, 0.0)
	time_since_pump += delta

	# 6. Write to 3D.
	_update_bank(delta)
	_apply_to_transform()
	_update_trail()
	_update_juice(delta)


func _try_pump() -> void:
	if pump_timer > 0.0 or vel.length() < 0.5:
		return
	# Quality comes from the heading at the moment of the flip: flipping while climbing is a pump.
	var t := (rad_to_deg(vel.angle()) + 90.0) / 180.0
	var quality := pump_curve.sample(clampf(t, 0.0, 1.0))
	var where := lerpf(shoulder_pump_scale, 1.0, wave.steepness(pos.x))
	vel += vel.normalized() * pump_gain * quality * where
	last_pump_quality = quality
	time_since_pump = 0.0
	pump_timer = pump_cooldown


func speed() -> float:
	return vel.length()


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
	global_transform = Transform3D(Basis.looking_at(_forward, n), wave.world_point(pos.x, pos.y))


func _update_trail() -> void:
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
	var rate := deg_to_rad(sharp_turn_rate if is_sharp else turn_rate) if is_live else 0.0
	var intensity := clampf((speed() * rate - spray_min_intensity) / (spray_full_intensity - spray_min_intensity), 0.0, 1.5)
	# Spray fan off the rail, thrown to the outside of the turn. Size follows how hard you are turning.
	var outward := float(wave.direction * turn_dir)
	spray.emitting = is_live and intensity > 0.0
	spray.direction = Vector3(outward * 0.9, 0.5, 0.5)
	spray.initial_velocity_min = 1.5 + 6.0 * intensity
	spray.initial_velocity_max = 3.0 + 9.0 * intensity
	spray.scale_amount_min = 0.4 + 0.5 * intensity
	spray.scale_amount_max = 0.8 + 0.9 * intensity
	# Foamy wake dropped on the water behind the board: the cheapest way to say "this is water".
	wake.emitting = is_live and speed() > wake_min_speed
	# Sharp turn: one big splash on entry, and the rider crouches while it lasts.
	if is_sharp and not _was_sharp:
		burst.direction = Vector3(outward * 0.8, 0.7, 0.4)
		burst.restart()
	_was_sharp = is_sharp
	var crouch := crouch_scale if is_sharp else 1.0
	var k := 1.0 - exp(-14.0 * delta)
	rider.scale = rider.scale.lerp(Vector3(1.0, crouch, 1.0), k)
	rider.position.y = lerpf(rider.position.y, _rider_rest_y * crouch, k)


func _setup_board() -> void:
	board.mesh = _build_board_mesh(board_length, board_width, board_thickness)
	if board.material_override is BaseMaterial3D:
		(board.material_override as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	var fin := MeshInstance3D.new()
	fin.name = "Fin"
	var prism := PrismMesh.new()
	prism.size = Vector3(0.025, 0.24, 0.26)
	prism.left_to_right = 0.85
	fin.mesh = prism
	# PrismMesh points up along +Y; hang it under the tail, raked back.
	fin.rotation_degrees = Vector3(180.0, 0.0, 0.0)
	fin.position = Vector3(0.0, -board_thickness * 0.5 - 0.11, board_length * 0.34)
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
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	InputMap.action_add_event(ACTION, key)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event(ACTION, mouse)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	InputMap.action_add_event(ACTION, pad)
