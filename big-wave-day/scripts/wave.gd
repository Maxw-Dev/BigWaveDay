## The wave. Its geometry is fixed relative to the breaking section, so the whole node travels down
## the line at `peel_speed` and the shape "builds up" at any given spot as the break approaches.
## `direction` mirrors the world along X: 1 is a left (face on the left of the screen), -1 a right.
## The sim always works in face coordinates (u along the wave, h up the face); only the mapping flips.
class_name Wave
extends Node3D

@export var shape: WaveShape
@export_enum("Left:1", "Right:-1") var direction: int = 1
@export var peel_speed := 6.2            ## m/s the break advances along the wave. Close to cruising speed, so only real pumping pulls ahead.
@export var generate_collision := false  ## Adds a StaticBody3D trimesh. Nothing uses it; it only costs startup time and memory.
@export var u_step := 1.0
@export var face_rows := 50              ## Rows from trough to lip.
@export var flat_rows := 0               ## Rows of flat water in front of the trough. 0: the ocean is that water, so there is no seam.
@export var curl_rows := 24              ## Rows for the folding lip above the face.
@export var back_rows := 10              ## Rows down the back of the wave, crest to sea level. Visual only.
@export var face_color := Color(0.15, 0.45, 0.75)
@export var water_scroll := Vector2(0.0, -0.06)   ## UV drift per second. Water draws up the face on a real wave.
@export var band_length := 5.0           ## World-anchored shade bands every N metres along the wave, so the rider's travel reads.
@export var band_shade := 1.0            ## 1 = no bands. The sections and chop carry the motion now; set lower to bring the debug bands back.
@export var ocean_color := Color(0.05, 0.22, 0.42)

const FACE_SHADER := preload("res://shaders/water_face.gdshader")
const OCEAN_SHADER := preload("res://shaders/water_ocean.gdshader")

@export var taper_length := 150.0        ## Metres over which the wave line runs down to nothing at end_u. Long, so the end reads as a decline, not a fin.
@export var min_size := 0.04             ## Smallest the wave ever gets, as a fraction of full size. Avoids a zero-height face.

var foam_u := 0.0                        ## Position of the break along the wave, metres.
var amplitude := 1.0                     ## 1 = full wave. The run lowers it as a timed wave runs out.
var end_u := INF                         ## Metres along the wave where it runs out (at the island). INF = never.
var _spray_base := Vector3.ZERO
var _spray_v_min := 4.0
var _spray_v_max := 9.0
var _faces := {}                         ## direction -> MeshInstance3D. Both are built once; only one is shown.
var _face_mat: ShaderMaterial
var _ocean_mat: ShaderMaterial
var _noise: NoiseTexture2D
var _shallow_center := Vector3(0.0, 0.0, 1000000.0)
var _shallow_radius := Vector2(110.0, 115.0)

@onready var face_mesh: MeshInstance3D = $FaceMesh
@onready var ocean: MeshInstance3D = $Ocean
@onready var crash_spray: CPUParticles3D = $CrashSpray


func _ready() -> void:
	if shape == null:
		shape = WaveShape.new()
	_faces[1] = _build_face(1, face_mesh)
	var right := MeshInstance3D.new()
	right.name = "FaceMeshRight"
	add_child(right)
	_faces[-1] = _build_face(-1, right)
	set_direction(direction)
	_setup_ocean()
	_setup_crash_spray()
	reset()


func reset() -> void:
	foam_u = 0.0
	_place()


func set_size(new_amplitude: float, new_end_u: float = end_u) -> void:
	# Shrink or restore the whole wave. Drawn in the shader, ridden through world_point/arc_length below.
	amplitude = new_amplitude
	end_u = new_end_u
	_push_size_uniforms()
	_place()


func size_at(u: float) -> float:
	var taper := 1.0
	if end_u != INF:
		taper = 1.0 - smoothstep(end_u - taper_length, end_u, u)
	return maxf(amplitude * taper, min_size)


func set_shallows(center: Vector3, radius: Vector2) -> void:
	# Where the water turns shallow and see-through (around the home island and the end of the wave line).
	_shallow_center = center
	_shallow_radius = radius
	_push_size_uniforms()


func _push_size_uniforms() -> void:
	# Both water materials get the same size and shallows, so the face and the ocean always agree.
	for mat in [_face_mat, _ocean_mat]:
		if mat == null:
			continue
		mat.set_shader_parameter("amplitude", amplitude)
		mat.set_shader_parameter("end_u", end_u if end_u != INF else 1000000.0)
		mat.set_shader_parameter("taper_len", taper_length)
		mat.set_shader_parameter("wave_dir", float(direction))
		mat.set_shader_parameter("min_size", min_size)
		mat.set_shader_parameter("shallow_center", _shallow_center)
		mat.set_shader_parameter("shallow_radius", _shallow_radius)


func set_break(u: float) -> void:
	# Used by the replay to scrub the break back to where it was.
	foam_u = u
	_place()


func set_direction(dir: int) -> void:
	# Switch between the prebuilt left and right faces. Cheap enough to do every wave.
	direction = dir
	for d in _faces:
		var mi: MeshInstance3D = _faces[d]
		var active: bool = d == dir
		mi.visible = active
		for child in mi.get_children():
			if child is StaticBody3D:
				child.collision_layer = 1 if active else 0
				child.collision_mask = 1 if active else 0
	if _faces.has(dir):
		face_mesh = _faces[dir]
	_push_size_uniforms()
	_place()


func _physics_process(delta: float) -> void:
	foam_u += peel_speed * delta
	_place()


func _process(delta: float) -> void:
	pass   # Both water shaders scroll themselves.


func _place() -> void:
	# The mesh lives in the break's frame; the node carries it down the line. The water pattern on it is
	# world-anchored in the shader, so only the shape appears to move.
	position = Vector3(foam_u * direction, 0.0, 0.0)
	if crash_spray != null:
		# The crash at the break shrinks with the wave.
		var s := size_at(foam_u)
		crash_spray.position = Vector3(_spray_base.x, _spray_base.y * s, _spray_base.z * s)
		crash_spray.initial_velocity_min = _spray_v_min * sqrt(s)
		crash_spray.initial_velocity_max = _spray_v_max * sqrt(s)


# ---- geometry for riders: u = metres along the wave, h = height fraction on the face ----

func along() -> Vector3:
	return Vector3(direction, 0.0, 0.0)


func ahead_of_break(u: float) -> float:
	return u - foam_u


func world_point(u: float, h: float) -> Vector3:
	var p := shape.local_point(ahead_of_break(u), h)
	if h <= 0.0:
		return Vector3(u * direction, p.y, p.z)   # flat water keeps its size, as in the shader
	var s := size_at(u)
	return Vector3(u * direction, p.y * s, p.z * s)


func tangent_up(u: float, h: float) -> Vector3:
	return shape.tangent_up(ahead_of_break(u), h)


func normal(u: float, h: float) -> Vector3:
	return shape.normal(ahead_of_break(u), h)


func slope_angle(u: float, h: float) -> float:
	return shape.slope_angle(ahead_of_break(u), h)


func arc_length(u: float) -> float:
	# Metres of face from trough to lip here, at the wave's current size.
	return shape.arc_length(ahead_of_break(u)) * size_at(u)


func metres_per_h(u: float, h: float) -> float:
	# Converts a height fraction to metres along the surface: the face scales with the wave, the flats do not.
	return arc_length(u) if h > 0.0 else shape.arc_length(ahead_of_break(u))


func steepness(u: float) -> float:
	return shape.steepness(ahead_of_break(u))


func height_fraction_at_z(u: float, z: float) -> float:
	# Which height fraction of the face sits at this world z, here along the wave. Flat water is negative.
	var d := ahead_of_break(u)
	if z >= 0.0:
		return -z / shape.arc_length(d)
	z /= size_at(u)
	var r := shape.arc_radius(d)
	var a := asin(clampf(-z / r, 0.0, 1.0))
	return clampf(a / shape.lip_angle(d), 0.0, 1.0)


func top_height(u: float) -> float:
	# Highest point of the wave (lip, curl or whitewater) at this point along it.
	return shape.top_height(ahead_of_break(u)) * size_at(u)


func lip_top(u: float) -> float:
	# Height of the face's lip here, ignoring the curl.
	return shape.lip_height(ahead_of_break(u)) * size_at(u)


# ---- visuals ----

func _build_face(dir: int, mi: MeshInstance3D) -> MeshInstance3D:
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
			st.set_color(Color(shape.foam_amount(d, h), shape.fold_amount(d, h), shape.tip_amount(d, h), clampf(h, 0.0, 1.0)))
			st.add_vertex(Vector3(p.x * dir, p.y, p.z))
	var stride := rows + 1
	for i in range(nu):
		for j in range(rows):
			var a := i * stride + j
			var b := a + 1
			var c := a + stride
			var e := c + 1
			# Godot treats clockwise triangles as front faces. Wind them clockwise as seen from the rider's side;
			# mirroring X flips handedness, so a right-hander uses the opposite order.
			if dir > 0:
				st.add_index(a); st.add_index(b); st.add_index(c)
				st.add_index(b); st.add_index(e); st.add_index(c)
			else:
				st.add_index(a); st.add_index(c); st.add_index(b)
				st.add_index(b); st.add_index(c); st.add_index(e)
	# The back of the wave: a second strip from the lip line over the crest and down to sea level behind it.
	# Same surface and material, so it is still one draw call. Alpha carries crest (1) to foot (0).
	var base := (nu + 1) * stride
	for i in range(nu + 1):
		var d := minf(-shape.back_extent + i * u_step, shape.length)
		for k in range(back_rows + 1):
			var t := float(k) / back_rows
			var p := shape.back_point(d, t)
			st.set_color(Color(shape.foam_amount(d, 1.0), 0.0, 0.0, 1.0 - t))
			st.add_vertex(Vector3(p.x * dir, p.y, p.z))
	var bstride := back_rows + 1
	for i in range(nu):
		for k in range(back_rows):
			var a := base + i * bstride + k
			var b := a + 1
			var c := a + bstride
			var e := c + 1
			# Rows run away from the viewer here, so the winding is the mirror of the face's.
			if dir > 0:
				st.add_index(a); st.add_index(c); st.add_index(b)
				st.add_index(b); st.add_index(c); st.add_index(e)
			else:
				st.add_index(a); st.add_index(b); st.add_index(c)
				st.add_index(b); st.add_index(e); st.add_index(c)
	st.generate_normals()
	mi.mesh = st.commit()
	if _face_mat == null:
		_face_mat = _make_face_material()
	mi.material_override = _face_mat
	if generate_collision:
		mi.create_trimesh_collision()
	return mi


func _make_face_material() -> ShaderMaterial:
	_face_mat = ShaderMaterial.new()
	_face_mat.shader = FACE_SHADER
	_apply_water_params(_face_mat)
	_face_mat.set_shader_parameter("band_length", band_length)
	_face_mat.set_shader_parameter("band_shade", band_shade)
	_push_size_uniforms()
	return _face_mat


func _apply_water_params(mat: ShaderMaterial) -> void:
	# The settings both water shaders share. One noise texture, so the patterns line up exactly.
	if _noise == null:
		_noise = _noise_texture()
	mat.set_shader_parameter("base_color", face_color)
	mat.set_shader_parameter("ocean_color", ocean_color)
	mat.set_shader_parameter("noise_tex", _noise)
	mat.set_shader_parameter("water_scroll", water_scroll)


func _setup_ocean() -> void:
	# World-fixed: it must not travel with the wave.
	ocean.top_level = true
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000.0, 4000.0)
	ocean.mesh = plane
	ocean.global_position = Vector3(0.0, -0.03, 0.0)
	# Same water as the face (shared shader include), so there is no line where they meet.
	_ocean_mat = ShaderMaterial.new()
	_ocean_mat.shader = OCEAN_SHADER
	_ocean_mat.render_priority = -10   # transparent, so draw it before spray and wake, which sit on top
	_apply_water_params(_ocean_mat)
	_push_size_uniforms()
	ocean.material_override = _ocean_mat
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _setup_crash_spray() -> void:
	# Spray fountain where the thrown lip lands, travelling with the break.
	var impact := shape.local_point(0.0, 2.0)
	_spray_base = Vector3(0.0, maxf(impact.y - 1.0, 0.5), impact.z)
	crash_spray.position = _spray_base
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
	crash_spray.initial_velocity_min = _spray_v_min
	crash_spray.initial_velocity_max = _spray_v_max
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
