class_name TerrainGenerator
extends RefCounted
## Deterministic procedural terrain: one height grid, used for both the visible
## mesh and the physics heightmap.
##
## Why a custom generator instead of a mesh from a 3D tool:
## * no binary assets in the repository yet, so the project stays openable and
##   reviewable as pure text;
## * the same (size, height scale, seed) triple rebuilds the *identical* world
##   on every machine, because the noise is an integer hash and there is no
##   time dependent input;
## * the grid is generated to match Godot's `HeightMapShape3D` layout exactly
##   (1 unit spacing, centred on the origin, `size_cells - 1` units across,
##   row = Z, column = X, index = iz * size_cells + ix), so what you see is
##   precisely what the player collides with.
##
## Triangle layout also matches the physics shape (diagonal from the
## +X/-Z corner to the -X/+Z corner of each cell), which is why
## [method height_at] interpolates over the same two triangles instead of a
## plain bilinear filter: objects placed with `height_at` sit exactly on the
## surface the engine simulates.
##
## Unit tests: `tests/unit/test_terrain_generator.gd`.

const CELL_SIZE := 1.0
const DEFAULT_SIZE_CELLS := 128
const DEFAULT_HEIGHT_SCALE := 5.0
const DEFAULT_SEED := 20261016

## Flat, sand coloured plaza around the origin where the village is built.
const PLAZA_RADIUS := 15.0
const PLAZA_FALLOFF := 12.0

const COLOR_GRASS := Color(0.30, 0.50, 0.26)
const COLOR_GRASS_DARK := Color(0.19, 0.33, 0.18)
const COLOR_ROCK := Color(0.44, 0.41, 0.37)
const COLOR_SAND := Color(0.70, 0.62, 0.44)

## Grid points per side. The terrain is (size_cells - 1) units across.
var size_cells: int = DEFAULT_SIZE_CELLS
var height_scale: float = DEFAULT_HEIGHT_SCALE
var terrain_seed: int = DEFAULT_SEED

## Cached height grid, row major: index = iz * size_cells + ix.
var _heights := PackedFloat32Array()


func _init(
	initial_size_cells: int = DEFAULT_SIZE_CELLS,
	initial_height_scale: float = DEFAULT_HEIGHT_SCALE,
	initial_seed: int = DEFAULT_SEED
) -> void:
	size_cells = maxi(initial_size_cells, 4)
	height_scale = maxf(initial_height_scale, 0.0)
	terrain_seed = initial_seed
	_heights = _compute_heights()


# --- geometry queries (pure) -------------------------------------------------


## Total width/depth of the terrain in world units.
func get_extent() -> float:
	return float(size_cells - 1) * CELL_SIZE


func get_half_extent() -> float:
	return get_extent() * 0.5


## World X of grid column [param ix].
func cell_to_world_x(ix: int) -> float:
	return (float(ix) - float(size_cells - 1) * 0.5) * CELL_SIZE


## World Z of grid row [param iz].
func cell_to_world_z(iz: int) -> float:
	return (float(iz) - float(size_cells - 1) * 0.5) * CELL_SIZE


## Height stored in the grid, indices clamped to the valid range.
func grid_height(ix: int, iz: int) -> float:
	var cx := clampi(ix, 0, size_cells - 1)
	var cz := clampi(iz, 0, size_cells - 1)
	return _heights[cz * size_cells + cx]


## Exact surface height at any world position, using the same triangle split
## as the physics heightmap. Clamped to the terrain bounds.
func height_at(world_x: float, world_z: float) -> float:
	var half := get_half_extent()
	var fx := clampf((world_x + half) / CELL_SIZE, 0.0, float(size_cells - 1))
	var fz := clampf((world_z + half) / CELL_SIZE, 0.0, float(size_cells - 1))
	var ix := mini(floori(fx), size_cells - 2)
	var iz := mini(floori(fz), size_cells - 2)
	var u := fx - float(ix)
	var v := fz - float(iz)
	var bottom_left := grid_height(ix, iz)
	var bottom_right := grid_height(ix + 1, iz)
	var top_left := grid_height(ix, iz + 1)
	var top_right := grid_height(ix + 1, iz + 1)
	if u + v <= 1.0:
		# Triangle (bottom_left, top_left, bottom_right).
		return bottom_left + u * (bottom_right - bottom_left) + v * (top_left - bottom_left)
	# Triangle (top_left, top_right, bottom_right).
	return top_right + (1.0 - u) * (top_left - top_right) + (1.0 - v) * (bottom_right - top_right)


func get_vertex_count() -> int:
	return size_cells * size_cells


func get_triangle_count() -> int:
	return (size_cells - 1) * (size_cells - 1) * 2


# --- build products ----------------------------------------------------------


## Copy of the raw height grid, in `HeightMapShape3D.map_data` order.
func build_height_map_data() -> PackedFloat32Array:
	return _heights.duplicate()


## Physics shape covering exactly the generated mesh.
func build_collision_shape() -> HeightMapShape3D:
	var shape := HeightMapShape3D.new()
	# Width/depth first: assigning them resizes map_data internally.
	shape.map_width = size_cells
	shape.map_depth = size_cells
	shape.map_data = build_height_map_data()
	return shape


## Visible terrain mesh with per vertex colours and smooth normals.
func build_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var last_index := float(size_cells - 1)
	for iz in size_cells:
		for ix in size_cells:
			surface.set_uv(Vector2(float(ix) / last_index, float(iz) / last_index))
			surface.set_color(_vertex_color(ix, iz))
			surface.add_vertex(Vector3(cell_to_world_x(ix), grid_height(ix, iz), cell_to_world_z(iz)))
	for iz in size_cells - 1:
		for ix in size_cells - 1:
			var bottom_left := ix + iz * size_cells
			var bottom_right := bottom_left + 1
			var top_left := bottom_left + size_cells
			var top_right := top_left + 1
			# Counter-clockwise seen from above (+Y), so generated normals point up.
			surface.add_index(bottom_left)
			surface.add_index(top_left)
			surface.add_index(bottom_right)
			surface.add_index(top_left)
			surface.add_index(top_right)
			surface.add_index(bottom_right)
	surface.generate_normals()
	surface.generate_tangents()
	return surface.commit()


## Unlit-texture-free material: the vertex colours carry all the shading variety.
func build_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.metallic = 0.0
	material.roughness = 0.95
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.cull_mode = BaseMaterial3D.CULL_BACK
	return material


# --- internals ---------------------------------------------------------------


func _compute_heights() -> PackedFloat32Array:
	var data := PackedFloat32Array()
	data.resize(size_cells * size_cells)
	for iz in size_cells:
		var z := cell_to_world_z(iz)
		for ix in size_cells:
			data[iz * size_cells + ix] = _base_height(cell_to_world_x(ix), z)
	return data


func _base_height(x: float, z: float) -> float:
	var height := 0.0
	height += _value_noise(x, z, 0.021, 1.0)
	height += _value_noise(x, z, 0.053, 0.45)
	height += _value_noise(x, z, 0.121, 0.18)
	height *= height_scale
	# Flatten the village plaza around the origin.
	var distance := sqrt(x * x + z * z)
	var flatten := clampf((distance - PLAZA_RADIUS) / PLAZA_FALLOFF, 0.0, 1.0)
	return height * _smoothstep(flatten)


## Classic value noise: hashed lattice corners, smoothstep interpolation.
func _value_noise(x: float, z: float, frequency: float, amplitude: float) -> float:
	var fx := x * frequency
	var fz := z * frequency
	var x0 := floori(fx)
	var z0 := floori(fz)
	var tx := _smoothstep(fx - float(x0))
	var tz := _smoothstep(fz - float(z0))
	var top := lerpf(_hash(x0, z0), _hash(x0 + 1, z0), tx)
	var bottom := lerpf(_hash(x0, z0 + 1), _hash(x0 + 1, z0 + 1), tx)
	return lerpf(top, bottom, tz) * amplitude


## Deterministic 2D integer hash in [-1, 1). Every intermediate value is masked
## to 31 bits so the products stay inside the 64-bit integer range.
func _hash(ix: int, iz: int) -> float:
	var h := (ix * 73856093) ^ (iz * 19349663) ^ (terrain_seed * 83492791)
	h = h & 0x7FFFFFFF
	h = (h ^ (h >> 13)) & 0x7FFFFFFF
	h = (h * 1274126177) & 0x7FFFFFFF
	h = (h ^ (h >> 16)) & 0x7FFFFFFF
	return float(h & 0xFFFF) / 32767.5 - 1.0


func _smoothstep(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## Approximate gradient magnitude at a grid point, used to paint rock on steep
## ground. Central differences over the grid, so it is deterministic too.
func _slope_at(ix: int, iz: int) -> float:
	var dx := (grid_height(ix + 1, iz) - grid_height(ix - 1, iz)) / (2.0 * CELL_SIZE)
	var dz := (grid_height(ix, iz + 1) - grid_height(ix, iz - 1)) / (2.0 * CELL_SIZE)
	return sqrt(dx * dx + dz * dz)


func _vertex_color(ix: int, iz: int) -> Color:
	var height := grid_height(ix, iz)
	var slope := _slope_at(ix, iz)
	var height_t := clampf((height + height_scale) / (2.0 * maxf(height_scale, 0.001)), 0.0, 1.0)
	var color := COLOR_GRASS_DARK.lerp(COLOR_GRASS, height_t)
	var rock_t := clampf((slope - 0.35) / 0.6, 0.0, 1.0)
	color = color.lerp(COLOR_ROCK, rock_t)
	var x := cell_to_world_x(ix)
	var z := cell_to_world_z(iz)
	var distance := sqrt(x * x + z * z)
	var sand_t := clampf(1.0 - (distance - PLAZA_RADIUS) / 8.0, 0.0, 1.0) * (1.0 - rock_t)
	color = color.lerp(COLOR_SAND, sand_t)
	var variation := clampf(_value_noise(x, z, 0.42, 0.05), 0.0, 0.12)
	return color.darkened(variation)
