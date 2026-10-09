## Islands, rocks and moored boats around the wave, built from primitives at startup.
## Each island is one merged, flat-shaded mesh with vertex colours: one draw call, cheap enough for phones,
## and faceted like the animals. The run calls arrange() every wave so the scenery mirrors with the wave's
## direction and the home island sits where the wave runs out.
class_name Backdrop
extends Node3D

@export var boat_scene: PackedScene                  ## Alex's rowboat. Optional; no boats if empty.
@export var boat_scale := 1.7
@export var home_radius := 42.0
@export var home_past_end := 30.0                    ## Home island centre: this many metres past where the wave runs out...
@export var home_out := 78.0                         ## ...and this far out toward the shore (+z), clear of the wave.
@export var endless_home_u := 650.0                  ## In endless mode the wave never runs out; the island just sits far down the line.
@export var shallow_radius := Vector2(110.0, 115.0)  ## Size of the see-through shallows around the home island (along, out).
@export var chain_count := 7                         ## Islands streamed along the coast, so endless mode never runs out of land ahead.
@export var chain_spacing := Vector2(240.0, 400.0)   ## Metres between chain islands (min, max).
@export var chain_behind := 320.0                    ## A chain island this far behind the rider moves to the front of the chain.

## Background islets: (metres along the wave, metres out (+ shore side, - behind the wave), size). Mirrored with the wave.
const ISLETS := [
	Vector3(-150.0, 220.0, 20.0),
	Vector3(150.0, 230.0, 15.0),
	Vector3(210.0, 380.0, 27.0),
	Vector3(620.0, 340.0, 19.0),
	Vector3(60.0, -340.0, 38.0),
	Vector3(330.0, -310.0, 23.0),
]
## Rock stacks: (along, out, size).
const STACKS := [
	Vector3(-60.0, 160.0, 1.0),
	Vector3(440.0, 250.0, 1.3),
	Vector3(-210.0, -420.0, 1.6),
]

const SAND := Color(0.93, 0.84, 0.6)
const GRASS := Color(0.28, 0.6, 0.3)
const GRASS_DARK := Color(0.2, 0.47, 0.25)
const TRUNK := Color(0.47, 0.33, 0.2)
const LEAF := Color(0.24, 0.62, 0.28)
const LEAF_DARK := Color(0.17, 0.48, 0.22)
const COCONUT := Color(0.35, 0.22, 0.12)
const ROCK := Color(0.47, 0.47, 0.5)
const SEABED := Color(0.76, 0.72, 0.55)
const REEF_ROCK := Color(0.36, 0.34, 0.33)
const REEF_TINTS := [Color(0.42, 0.5, 0.36), Color(0.6, 0.42, 0.4), Color(0.5, 0.45, 0.32)]

var _mat: StandardMaterial3D
var _home: MeshInstance3D
var _reef: MeshInstance3D
var _islets: Array[MeshInstance3D] = []
var _stacks: Array[MeshInstance3D] = []
var _boats: Array[Node3D] = []
var _chain: Array[MeshInstance3D] = []
var _chain_front := 0.0                  ## Along-the-wave position (unsigned) of the furthest chain island.
var _rng := RandomNumberGenerator.new()
var _t := 0.0


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.95
	_home = _instance(_build_island(home_radius, 10.0, 7, 10, 11))
	_reef = _instance(_build_reef(shallow_radius, home_radius, 21))
	for i in range(ISLETS.size()):
		var spec: Vector3 = ISLETS[i]
		_islets.append(_instance(_build_island(spec.z, spec.z * 0.28, clampi(int(spec.z / 9.0), 1, 4), 4, 100 + i)))
	for i in range(STACKS.size()):
		_stacks.append(_instance(_build_stack(STACKS[i].z, 200 + i)))
	# The chain: a mix of sizes, a couple of low sandbars, one big one.
	var specs := [[26.0, 7.0, 4], [18.0, 1.0, 1], [34.0, 9.5, 6], [22.0, 5.5, 3], [40.0, 12.0, 8], [16.0, 0.6, 0], [30.0, 8.0, 5]]
	for i in range(chain_count):
		var sp: Array = specs[i % specs.size()]
		_chain.append(_instance(_build_island(sp[0], sp[1], sp[2], 3 + i % 5, 300 + i)))
	if boat_scene != null:
		for i in range(2):
			var b: Node3D = boat_scene.instantiate()
			b.scale = Vector3.ONE * boat_scale
			add_child(b)
			_boats.append(b)
	arrange(1, INF, true)


func _process(delta: float) -> void:
	# Moored boats bob a little.
	_t += delta
	for i in range(_boats.size()):
		var b := _boats[i]
		b.position.y = 0.06 * sin(_t * 1.3 + i * 2.0)
		b.rotation.z = 0.04 * sin(_t * 0.9 + i)
		b.rotation.x = 0.03 * sin(_t * 1.1 + i * 1.7)


func arrange(dir: int, end_u: float, endless: bool) -> void:
	var home_u := endless_home_u if (endless or end_u == INF) else end_u + home_past_end
	_home.position = Vector3(home_u * dir, 0.0, home_out)
	_home.rotation.y = 0.0 if dir > 0 else PI
	_reef.position = _home.position
	_reef.rotation.y = _home.rotation.y
	for i in range(_islets.size()):
		var spec: Vector3 = ISLETS[i]
		_islets[i].position = Vector3(spec.x * dir, 0.0, spec.y)
		_islets[i].rotation.y = 0.0 if dir > 0 else PI
	for i in range(_stacks.size()):
		_stacks[i].position = Vector3(STACKS[i].x * dir, 0.0, STACKS[i].y)
	# The chain starts beyond the home island (timed) or a little way down the line (endless), both sides of the wave.
	_rng.seed = 7
	_chain_front = 330.0 if (endless or end_u == INF) else end_u + 220.0
	for i in range(_chain.size()):
		_place_chain(i, dir, _chain_front)
		_chain_front += _rng.randf_range(chain_spacing.x, chain_spacing.y)
	# One dinghy moored off the home island, one further up the coast.
	var spots := [Vector2(home_u - 30.0, home_out - home_radius * 0.8 - 6.0), Vector2(home_u + 45.0, home_out - 10.0)]
	for i in range(_boats.size()):
		_boats[i].position = Vector3(spots[i].x * dir, 0.0, spots[i].y)
		_boats[i].rotation.y = (0.7 + i * 1.9) * dir


func stream(rider_x: float, dir: int) -> void:
	# Keep the chain ahead of the rider: anything left far behind goes to the front with a fresh spot.
	for i in range(_chain.size()):
		if (rider_x - _chain[i].position.x) * dir > chain_behind:
			_chain_front += _rng.randf_range(chain_spacing.x, chain_spacing.y)
			_place_chain(i, dir, _chain_front)


func _place_chain(i: int, dir: int, u: float) -> void:
	# Alternating sides with some scatter: the shore side (+z) beyond the home island's lane, or behind the wave,
	# where it shows over the shoulder.
	var shore := (i % 2 == 0) == (_rng.randf() < 0.8)
	var z := _rng.randf_range(150.0, 250.0) if shore else -_rng.randf_range(170.0, 300.0)
	_chain[i].position = Vector3(u * dir, 0.0, z)
	_chain[i].rotation.y = (0.0 if dir > 0 else PI) + _rng.randf_range(-0.6, 0.6)


func shallows_center() -> Vector3:
	return _home.global_position


func home_focus() -> Vector3:
	# A point on the home island worth looking at: its hill, a little above the beach.
	return _home.global_position + Vector3(0.0, 6.0, 0.0)


func _instance(mesh: ArrayMesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


# ---- building ----

func _build_island(radius: float, hill: float, palms: int, rocks: int, seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := _begin()
	# Sand: a low, flattened dome that sinks below the waterline at its edge.
	_add(st, _sphere(12, 5), _xf(Vector3(0.0, -radius * 0.02, 0.0), 0.0, Vector3(radius, radius * 0.08, radius * 0.8)), SAND)
	# Two hills of jungle for a silhouette.
	_add(st, _sphere(9, 6), _xf(Vector3(-radius * 0.12, 0.0, -radius * 0.1), rng.randf() * TAU, Vector3(radius * 0.55, hill, radius * 0.42)), GRASS)
	_add(st, _sphere(8, 5), _xf(Vector3(radius * 0.3, 0.0, -radius * 0.22), rng.randf() * TAU, Vector3(radius * 0.32, hill * 0.7, radius * 0.28)), GRASS_DARK)
	# Palms on the beach ring.
	for i in range(palms):
		var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / maxf(palms, 1)
		var r := rng.randf_range(0.62, 0.84)
		var base := Vector3(cos(a) * r * radius, _dune(r, radius) - 0.3, sin(a) * r * radius * 0.8)
		_palm(st, base, rng.randf_range(9.0, 14.0) * clampf(radius / 40.0, 0.55, 1.0), rng)
	# Rocks at the waterline.
	for i in range(rocks):
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(0.88, 1.05)
		var s := rng.randf_range(1.2, 3.5) * clampf(radius / 40.0, 0.5, 1.0)
		var size := Vector3(s * rng.randf_range(0.8, 1.4), s * rng.randf_range(0.5, 1.0), s)
		_add(st, _sphere(6, 4), _xf(Vector3(cos(a) * r * radius, 0.0, sin(a) * r * radius * 0.8), rng.randf() * TAU, size), ROCK.darkened(rng.randf() * 0.25))
	return _end(st)


func _build_reef(radius: Vector2, island: float, seed: int) -> ArrayMesh:
	# The seabed seen through the shallows: a sandy floor that rises toward the island, with rocks and
	# weedy or coral-coloured lumps scattered on it. All of it stays under the surface.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := _begin()
	# Floor: about 3 m deep at the edge of the shallows, under half a metre near the beach.
	_add(st, _sphere(16, 6), _xf(Vector3(0.0, -3.4, 0.0), 0.0, Vector3(radius.x * 1.05, 2.9, radius.y * 1.05)), SEABED)
	for i in range(5):
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(0.35, 0.75)
		var patch := Vector3(rng.randf_range(14.0, 26.0), 0.6, rng.randf_range(10.0, 20.0))
		_add(st, _sphere(10, 4), _xf(Vector3(cos(a) * r * radius.x, -1.3, sin(a) * r * radius.y), rng.randf() * TAU, patch), SEABED.darkened(rng.randf_range(0.05, 0.15)))
	# Rocks and reef lumps, kept off the island itself and below the waterline.
	var placed := 0
	var tries := 0
	while placed < 55 and tries < 400:
		tries += 1
		var a := rng.randf_range(0.0, TAU)
		var r := sqrt(rng.randf_range(0.0, 1.0)) * 0.95
		var at := Vector3(cos(a) * r * radius.x, 0.0, sin(a) * r * radius.y)
		if Vector2(at.x, at.z / 0.8).length() < island * 1.05:
			continue
		var floor_y := -3.4 + 2.9 * sqrt(maxf(1.0 - pow(at.x / (radius.x * 1.05), 2.0) - pow(at.z / (radius.y * 1.05), 2.0), 0.0))
		var s := rng.randf_range(0.7, 2.4)
		var size := Vector3(s * rng.randf_range(0.9, 1.6), s * rng.randf_range(0.5, 0.9), s * rng.randf_range(0.9, 1.4))
		var top := floor_y + size.y * 0.6
		if top > -0.35:
			size.y = maxf(-0.35 - floor_y, 0.2) / 0.6
		var col: Color = REEF_ROCK.darkened(rng.randf() * 0.25)
		if rng.randf() < 0.35:
			col = REEF_TINTS[rng.randi() % REEF_TINTS.size()]
		_add(st, _sphere(7, 4), _xf(Vector3(at.x, floor_y, at.z), rng.randf() * TAU, size), col)
		placed += 1
	return _end(st)


func _build_stack(size: float, seed: int) -> ArrayMesh:
	# A cluster of tall rocks standing in the sea.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := _begin()
	for i in range(5):
		var off := Vector3(rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(-4.0, 4.0)) * size
		var h := rng.randf_range(4.0, 11.0) * size * (1.0 if i == 0 else 0.6)
		var w := rng.randf_range(2.0, 4.0) * size
		_add(st, _sphere(6, 4), _xf(off, rng.randf() * TAU, Vector3(w, h, w * rng.randf_range(0.7, 1.1))), ROCK.darkened(rng.randf() * 0.3))
	return _end(st)


func _palm(st: SurfaceTool, base: Vector3, height: float, rng: RandomNumberGenerator) -> void:
	# A trunk of tapering segments that lean more the higher they go, a crown of drooping fronds, coconuts.
	var lean_dir := rng.randf_range(0.0, TAU)
	var lean := deg_to_rad(rng.randf_range(8.0, 24.0))
	var axis := Vector3(cos(lean_dir), 0.0, sin(lean_dir)).cross(Vector3.UP).normalized()
	var segs := 6
	var seg_h := height / segs
	var at := base
	var basis := Basis()
	for i in range(segs):
		basis = Basis(axis, -lean * float(i + 1) / segs)
		var k := float(i) / segs
		var cyl := CylinderMesh.new()
		cyl.top_radius = lerpf(0.26, 0.17, k + 1.0 / segs)
		cyl.bottom_radius = lerpf(0.26, 0.17, k)
		cyl.height = seg_h * 1.05
		cyl.radial_segments = 6
		cyl.rings = 1
		_add(st, cyl, Transform3D(basis, at) * Transform3D(Basis(), Vector3(0.0, seg_h * 0.5, 0.0)), TRUNK.darkened(0.12 * (i % 2)))
		at = Transform3D(basis, at) * Vector3(0.0, seg_h, 0.0)
	var fronds := 7
	for k in range(fronds):
		var yaw := TAU * float(k) / fronds + rng.randf_range(-0.2, 0.2)
		var droop := deg_to_rad(rng.randf_range(18.0, 42.0))
		var length := rng.randf_range(1.2, 1.7) * height / 11.0
		var frond := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, droop), at) \
			* Transform3D(Basis.from_scale(Vector3(0.45, 0.05, length)), Vector3(0.0, 0.0, length))
		_add(st, _sphere(6, 3), frond, LEAF if k % 2 == 0 else LEAF_DARK)
	for k in range(3):
		var a := TAU * float(k) / 3.0
		_add(st, _sphere(6, 3), _xf(at + Vector3(cos(a) * 0.3, -0.35, sin(a) * 0.3), 0.0, Vector3.ONE * 0.22), COCONUT)


func _dune(r: float, radius: float) -> float:
	# Height of the sand dome at fraction r of the island radius.
	return radius * 0.08 * sqrt(maxf(1.0 - r * r, 0.0)) - radius * 0.02


# ---- mesh helpers ----

func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # flat, faceted normals like the animals
	return st


func _end(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	return st.commit()


func _add(st: SurfaceTool, prim: PrimitiveMesh, xf: Transform3D, col: Color) -> void:
	var arrays := prim.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	st.set_color(col)
	for i in idx:
		st.add_vertex(xf * verts[i])


func _xf(origin: Vector3, yaw: float, size: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(size), origin)


func _sphere(radial: int, rings: int) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = radial
	s.rings = rings
	return s
