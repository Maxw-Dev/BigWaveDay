## The wave. Its geometry is fixed relative to the breaking section, so the whole node travels down
## the line at `peel_speed` and the shape "builds up" at any given spot as the break approaches.
## `direction` mirrors the world along X: 1 is a left (face on the left of the screen), -1 a right.
## The sim always works in face coordinates (u along the wave, h up the face); only the mapping flips.
class_name Wave
extends Node3D

@export var shape: WaveShape
@export_enum("Left:1", "Right:-1") var direction: int = 1
@export var peel_speed := 6.2            ## m/s the break advances along the wave. Close to cruising speed, so only real pumping pulls ahead.
@export var generate_collision := true   ## Adds a StaticBody3D trimesh so physics bodies can stand on the face too.
@export var u_step := 1.0
@export var face_rows := 50              ## Rows from trough to lip.
@export var flat_rows := 20              ## Rows of flat water in front of the trough.
@export var curl_rows := 24              ## Rows for the folding lip above the face.
@export var face_color := Color(0.15, 0.45, 0.75)
@export var water_scroll := Vector2(0.0, -0.06)   ## UV drift per second. Water draws up the face on a real wave.
@export var band_length := 5.0           ## World-anchored shade bands every N metres along the wave, so the rider's travel reads.
@export var band_shade := 0.85
@export var ocean_color := Color(0.05, 0.22, 0.42)

const FACE_SHADER := preload("res://shaders/water_face.gdshader")

var foam_u := 0.0                        ## Position of the break along the wave, metres.
var _face_mat: ShaderMaterial
var _ocean_mat: StandardMaterial3D

@onready var face_mesh: MeshInstance3D = $FaceMesh
@onready var ocean: MeshInstance3D = $Ocean
@onready var crash_spray: CPUParticles3D = $CrashSpray


func _ready() -> void:
	if shape == null:
		shape = WaveShape.new()
	_build_face()
	_setup_ocean()
	_setup_crash_spray()
	reset()


func reset() -> void:
	foam_u = 0.0
	_place()


func _physics_process(delta: float) -> void:
	foam_u += peel_speed * delta
	_place()


func _process(delta: float) -> void:
	# Scrolling noise on the ocean. The face does the same inside its shader.
	var drift := Vector3(water_scroll.x, water_scroll.y, 0.0) * delta
	_ocean_mat.uv1_offset += drift


func _place() -> void:
	# The mesh lives in the break's frame; the node carries it down the line. The water pattern on it is
	# world-anchored in the shader, so only the shape appears to move.
	position = Vector3(foam_u * direction, 0.0, 0.0)


# ---- geometry for riders: u = metres along the wave, h = height fraction on the face ----

func along() -> Vector3:
	return Vector3(direction, 0.0, 0.0)


func ahead_of_break(u: float) -> float:
	return u - foam_u


func world_point(u: float, h: float) -> Vector3:
	var p := shape.local_point(ahead_of_break(u), h)
	return Vector3(u * direction, p.y, p.z)


func tangent_up(u: float, h: float) -> Vector3:
	return shape.tangent_up(ahead_of_break(u), h)


func normal(u: float, h: float) -> Vector3:
	return shape.normal(ahead_of_break(u), h)


func slope_angle(u: float, h: float) -> float:
	return shape.slope_angle(ahead_of_break(u), h)


func arc_length(u: float) -> float:
	return shape.arc_length(ahead_of_break(u))


func steepness(u: float) -> float:
	return shape.steepness(ahead_of_break(u))


func top_height(u: float) -> float:
	# Highest point of the wave (lip, curl or whitewater) at this point along it.
	return shape.top_height(ahead_of_break(u))


func lip_top(u: float) -> float:
	# Height of the face's lip here, ignoring the curl.
	return shape.lip_height(ahead_of_break(u))


# ---- visuals ----

func _build_face() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := int(ceil((shape.length + shape.back_extent) / u_step))
	var rows := flat_rows + face_rows + curl_rows
	for i in range(nu + 1):
		var d := minf(-shape.back_extent + i * u_step, shape.length)
		for j in range(rows + 1):
			# Flat rows are metres of flat water in front of the trough; face rows are height fractions 0..1;
			# curl rows continue to 2 (the lip folding over).
			var h: float
			if j < flat_rows:
				var s := -shape.flat_extent * (1.0 - float(j) / flat_rows)
				h = s / shape.arc_length(d)
			elif j <= flat_rows + face_rows:
				h = float(j - flat_rows) / face_rows
			else:
				h = 1.0 + float(j - flat_rows - face_rows) / curl_rows
			var p := shape.local_point(d, h)
			# Vertex colour carries: r = foam on the outside, g = fold (tube ceiling), b = lip tip.
			st.set_color(Color(shape.foam_amount(d, h), shape.fold_amount(d, h), shape.tip_amount(d, h), 1.0))
			st.add_vertex(Vector3(p.x * direction, p.y, p.z))
	var stride := rows + 1
	for i in range(nu):
		for j in range(rows):
			var a := i * stride + j
			var b := a + 1
			var c := a + stride
			var e := c + 1
			# Godot treats clockwise triangles as front faces. Wind them clockwise as seen from the rider's side;
			# mirroring X flips handedness, so a right-hander uses the opposite order.
			if direction > 0:
				st.add_index(a); st.add_index(b); st.add_index(c)
				st.add_index(b); st.add_index(e); st.add_index(c)
			else:
				st.add_index(a); st.add_index(c); st.add_index(b)
				st.add_index(b); st.add_index(c); st.add_index(e)
	st.generate_normals()
	face_mesh.mesh = st.commit()
	_face_mat = ShaderMaterial.new()
	_face_mat.shader = FACE_SHADER
	_face_mat.set_shader_parameter("base_color", face_color)
	_face_mat.set_shader_parameter("noise_tex", _noise_texture())
	_face_mat.set_shader_parameter("water_scroll", water_scroll)
	_face_mat.set_shader_parameter("band_length", band_length)
	_face_mat.set_shader_parameter("band_shade", band_shade)
	face_mesh.material_override = _face_mat
	if generate_collision:
		face_mesh.create_trimesh_collision()


func _setup_ocean() -> void:
	# World-fixed: it must not travel with the wave.
	ocean.top_level = true
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000.0, 4000.0)
	ocean.mesh = plane
	ocean.global_position = Vector3(0.0, -0.05, 0.0)
	# PlaneMesh UVs span the whole plane, so scale them to the same 10 m tile the face uses.
	_ocean_mat = _water_material(ocean_color, 0.72, Vector3(400.0, 400.0, 1.0))
	ocean.material_override = _ocean_mat


func _setup_crash_spray() -> void:
	# Spray fountain where the thrown lip lands, travelling with the break.
	var impact := shape.local_point(0.0, 2.0)
	crash_spray.position = Vector3(0.0, maxf(impact.y - 1.0, 0.5), impact.z)
	var drop := SphereMesh.new()
	drop.radius = 0.25
	drop.height = 0.5
	drop.radial_segments = 6
	drop.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.material = mat
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.9))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	crash_spray.mesh = drop
	crash_spray.amount = 160
	crash_spray.lifetime = 1.3
	crash_spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	crash_spray.emission_box_extents = Vector3(1.5, 0.4, shape.radius * 0.5)
	crash_spray.direction = Vector3(0.0, 1.0, 0.4)
	crash_spray.spread = 40.0
	crash_spray.gravity = Vector3(0.0, -9.8, 0.0)
	crash_spray.initial_velocity_min = 4.0
	crash_spray.initial_velocity_max = 9.0
	crash_spray.scale_amount_min = 0.7
	crash_spray.scale_amount_max = 1.8
	crash_spray.color_ramp = fade
	crash_spray.emitting = true


func _noise_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.03
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	return tex


func _water_material(color: Color, dark: float, uv_scale: Vector3) -> StandardMaterial3D:
	# Glossy surface with a seamless scrolling noise tint. `dark` is how dark the noise troughs get (1 = no noise).
	var tex := _noise_texture()
	var ramp := Gradient.new()
	ramp.set_color(0, Color(dark, dark, dark))
	ramp.set_color(1, Color.WHITE)
	tex.color_ramp = ramp
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = tex
	mat.uv1_scale = uv_scale
	mat.roughness = 0.18
	mat.metallic_specular = 0.7
	return mat
