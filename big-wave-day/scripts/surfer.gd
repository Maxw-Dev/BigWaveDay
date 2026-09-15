## One-button surfer. Simulates in 2D wave-face coordinates and writes the result to the 3D transform.
##
## pos.x = u (metres along the wave), pos.y = s (arc length up the face).
## Steering rotates the velocity vector, so the board always points where it travels.
## Tap = flip turn direction (and a pump check). Hold past the threshold = sharp turn until release.
class_name Surfer
extends Node3D

const ACTION := "surf"

@export var shape: WaveShape
@export var forgiving := false            ## Clamp s at the bottom too, so nothing ends the wave but the foam and the timer.
@export var soft_lip := true              ## Going over the lip pins you to it and scrubs speed instead of ending the wave.
@export var lip_drag := 1.5               ## Linear drag per second while pinned to the lip.

@export_group("Turning")
@export var turn_rate := 150.0            ## deg/s while carving. Bots: 110 cannot build speed against gravity, 150 can.
@export var sharp_turn_rate := 420.0      ## deg/s while the button is held past the threshold.
@export var sharp_hold_threshold := 0.18  ## Seconds of hold before a turn becomes sharp.
@export var bank_deg := 25.0
@export var sharp_bank_deg := 55.0
@export var bank_smoothing := 12.0        ## Per second. ~80 ms time constant.

@export_group("Speed")
@export var gravity := 9.8
@export var gravity_scale := 0.7          ## 1.0 makes mid-face gravity match the turn authority and the face plays like a wall.
@export var drag := 0.02                  ## Quadratic drag per metre. 2 m/s^2 at 10 m/s.
@export var sharp_drag_extra := 0.08      ## Added to drag while sharp: the speed scrub.
@export var flat_drag := 0.8              ## Linear drag per second on the flats (s <= 0). Makes bogging real.

@export_group("Pumping")
@export var pump_gain := 4.0              ## m/s added by a perfect pump.
@export var pump_cooldown := 0.3          ## Spamming must never out-earn rhythm.
@export var pump_curve: Curve             ## x: heading, 0 = straight down the face, 1 = straight up. y: quality 0..1.

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

var _hold_armed := false                  ## A hold only counts after a fresh press (not one carried across a respawn).
var _forward := Vector3.RIGHT
var _bank := 0.0
var _trail_points := PackedVector3Array()
var _trail_mesh := ImmediateMesh.new()

@onready var board: Node3D = $Board
@onready var trail: MeshInstance3D = $Trail


func _ready() -> void:
	_ensure_input_action()
	if shape == null:
		shape = WaveShape.new()
	if pump_curve == null:
		pump_curve = _default_pump_curve()
	trail.top_level = true
	trail.mesh = _trail_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.55, 0.1)
	trail.material_override = mat
	reset(Vector2(12.0, shape.arc_length * 0.5), Vector2(8.0, 0.0))


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
	_forward = Vector3.RIGHT
	_trail_points.clear()
	_trail_mesh.clear_surfaces()
	board.rotation = Vector3.ZERO
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
		var g_along := gravity * gravity_scale * sin(shape.slope_angle(pos.y))
		vel.y -= g_along * delta

	# 4. Drag: quadratic, plus the sharp-turn scrub, plus sticky flats.
	var k := drag + (sharp_drag_extra if is_sharp else 0.0)
	vel -= vel * vel.length() * k * delta
	if pos.y <= 0.0:
		vel -= vel * flat_drag * delta

	# 5. Integrate.
	pos += vel * delta
	if soft_lip and pos.y > shape.arc_length:
		pos.y = shape.arc_length
		vel.y = minf(vel.y, 0.0)
		vel -= vel * lip_drag * delta
	if forgiving:
		pos.y = clampf(pos.y, -shape.flat_extent, shape.arc_length)
	pump_timer = maxf(pump_timer - delta, 0.0)
	time_since_pump += delta

	# 6. Write to 3D.
	_update_bank(delta)
	_apply_to_transform()
	_update_trail()


func _try_pump() -> void:
	if pump_timer > 0.0 or vel.length() < 0.5:
		return
	# Quality comes from the heading at the moment of the flip: flipping while climbing is a pump.
	var t := (rad_to_deg(vel.angle()) + 90.0) / 180.0
	var quality := pump_curve.sample(clampf(t, 0.0, 1.0))
	vel += vel.normalized() * pump_gain * quality
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
	# Board forward is local -Z, so a positive roll about Z dips the lip-side rail: bank into the turn.
	var target := 0.0
	if is_live:
		target = turn_dir * deg_to_rad(sharp_bank_deg if is_sharp else bank_deg)
	_bank = lerpf(_bank, target, 1.0 - exp(-bank_smoothing * delta))
	board.rotation = Vector3(0.0, 0.0, _bank)


func _apply_to_transform() -> void:
	var n := shape.normal(pos.y)
	if vel.length_squared() > 1e-4:
		var d := vel.normalized()
		_forward = Vector3.RIGHT * d.x + shape.tangent_up(pos.y) * d.y
	# Keep the remembered forward in the tangent plane of the current spot.
	_forward = _forward - n * _forward.dot(n)
	if _forward.length_squared() < 1e-6:
		_forward = Vector3.RIGHT
	_forward = _forward.normalized()
	global_transform = Transform3D(Basis.looking_at(_forward, n), shape.surface_point(pos.x, pos.y))


func _update_trail() -> void:
	_trail_points.push_back(global_position + shape.normal(pos.y) * 0.05)
	while _trail_points.size() > trail_length:
		_trail_points.remove_at(0)
	_trail_mesh.clear_surfaces()
	if _trail_points.size() < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in _trail_points:
		_trail_mesh.surface_add_vertex(p)
	_trail_mesh.surface_end()


func _default_pump_curve() -> Curve:
	# 0 for any downhill heading, ramping to 1 by about +60 degrees (climbing steeply).
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(0.5, 0.0))
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
