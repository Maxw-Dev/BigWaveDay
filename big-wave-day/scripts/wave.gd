## Builds the wave face mesh from a WaveShape and owns the foam wall that chases the surfer.
## The wave itself never moves: everything lives in the wave's reference frame.
class_name Wave
extends Node3D

@export var shape: WaveShape
@export var peel_speed := 5.0            ## m/s the foam advances along the wave.
@export var generate_collision := true   ## Adds a StaticBody3D trimesh so physics bodies can stand on the face too.
@export var u_step := 1.0
@export var s_step := 0.5
@export var face_color := Color(0.15, 0.45, 0.75)
@export var band_length := 5.0           ## Alternating shade every N metres along the wave so movement reads on a bare face.
@export var band_shade := 0.8
@export var ocean_color := Color(0.05, 0.22, 0.42)

var foam_u := 0.0

@onready var face_mesh: MeshInstance3D = $FaceMesh
@onready var ocean: MeshInstance3D = $Ocean
@onready var foam: MeshInstance3D = $Foam


func _ready() -> void:
	if shape == null:
		shape = WaveShape.new()
	_build_face()
	_setup_ocean()
	_setup_foam()
	reset()


func reset() -> void:
	foam_u = 0.0
	_place_foam()


func _physics_process(delta: float) -> void:
	foam_u += peel_speed * delta
	_place_foam()


func _place_foam() -> void:
	foam.position = Vector3(foam_u, shape.radius * 0.6, -shape.radius * 0.45)


func _build_face() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s_min := -shape.flat_extent
	var s_max := shape.arc_length
	var nu := int(ceil(shape.length / u_step))
	var ns := int(ceil((s_max - s_min) / s_step))
	for i in range(nu + 1):
		var u := minf(i * u_step, shape.length)
		for j in range(ns + 1):
			var s := minf(s_min + j * s_step, s_max)
			st.set_normal(shape.normal(s))
			st.set_uv(Vector2(u * 0.1, s * 0.1))
			var odd := int(floor(u / band_length)) % 2 == 1
			st.set_color(Color(band_shade, band_shade, band_shade) if odd else Color.WHITE)
			st.add_vertex(shape.surface_point(u, s))
	var stride := ns + 1
	for i in range(nu):
		for j in range(ns):
			var a := i * stride + j
			var b := a + 1
			var c := a + stride
			var d := c + 1
			# Godot treats clockwise triangles as front faces. Wind them clockwise as seen from the rider's side.
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	face_mesh.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = face_color
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.45
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	face_mesh.material_override = mat
	if generate_collision:
		face_mesh.create_trimesh_collision()


func _setup_ocean() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000.0, 4000.0)
	ocean.mesh = plane
	ocean.position = Vector3(shape.length * 0.5, -0.05, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ocean_color
	mat.roughness = 0.6
	ocean.material_override = mat


func _setup_foam() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(2.0, shape.radius * 1.4, shape.radius * 2.4)
	foam.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foam.material_override = mat
