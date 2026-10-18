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
const DEFAULT_SIZE_CELLS := 160
const DEFAULT_HEIGHT_SCALE := 5.0
const DEFAULT_SEED := 20261016

## Noise octaves. The lowest one survives on roads and building plots, the two
## higher ones are faded out there, which is what makes a path walkable without
## flattening the whole landscape into a trench.
const LOW_FREQUENCY := 0.021
const MID_FREQUENCY := 0.053
const HIGH_FREQUENCY := 0.121

## Legacy plaza used when no [VillageLayout] is supplied (unit tests, and any
## caller that only wants raw hills). With a layout the plaza comes from it.
const PLAZA_RADIUS := 15.0
const PLAZA_FALLOFF := 12.0

const COLOR_GRASS := Color(0.30, 0.48, 0.21)
const COLOR_GRASS_DARK := Color(0.17, 0.31, 0.13)
const COLOR_MEADOW := Color(0.43, 0.55, 0.22)
const COLOR_ROCK := Color(0.45, 0.41, 0.35)
const COLOR_SAND := Color(0.72, 0.62, 0.42)
const COLOR_DIRT := Color(0.56, 0.41, 0.23)
const COLOR_COBBLE := Color(0.57, 0.53, 0.47)
const COLOR_MUD := Color(0.29, 0.25, 0.19)

# --- Visual polish 06 — extended terrain palette --------------------------------
# New colours are *variations* of the existing family, not replacements.  The
# original eight colours remain the anchors so the village keeps its identity;
# these add the subtleties a real ground needs: dry sun-bleached tufts,
# clay streaks in the road, gravel at the verge, moss on damp slopes, a
# trampling skirt around buildings and a warmer sand at the water line.
const COLOR_GRASS_DRY := Color(0.46, 0.52, 0.20)
const COLOR_HEATH := Color(0.38, 0.44, 0.22)
const COLOR_CLAY := Color(0.62, 0.38, 0.20)
const COLOR_GRAVEL := Color(0.52, 0.49, 0.43)
const COLOR_MOSS := Color(0.22, 0.36, 0.18)
const COLOR_SAND_LIGHT := Color(0.78, 0.71, 0.52)
const COLOR_SOIL := Color(0.36, 0.28, 0.19)
const COLOR_STONE_WARM := Color(0.60, 0.55, 0.46)

## Grid points per side. The terrain is (size_cells - 1) units across.
var size_cells: int = DEFAULT_SIZE_CELLS
var height_scale: float = DEFAULT_HEIGHT_SCALE
var terrain_seed: int = DEFAULT_SEED

## Optional village plan. When present, the generator levels the plaza and the
## plots, fades the detail octaves along the roads, carves the pond and paints
## the ground to match. When null the terrain is plain hills with a flat disc.
var layout: VillageLayout = null

## Cached height grid, row major: index = iz * size_cells + ix.
var _heights := PackedFloat32Array()
var _plaza_level := 0.0
var _pond_level := 0.0


func _init(
	initial_size_cells: int = DEFAULT_SIZE_CELLS,
	initial_height_scale: float = DEFAULT_HEIGHT_SCALE,
	initial_seed: int = DEFAULT_SEED,
	initial_layout: VillageLayout = null
) -> void:
	size_cells = maxi(initial_size_cells, 4)
	height_scale = maxf(initial_height_scale, 0.0)
	terrain_seed = initial_seed
	layout = initial_layout
	# Without a village plan the legacy plaza is levelled to y = 0, exactly as it
	# was before the layout existed; with a plan the plaza follows the hill it
	# sits on, so it does not become a bowl in the middle of the map.
	_plaza_level = 0.0
	if layout != null:
		_plaza_level = _value_noise(0.0, 0.0, LOW_FREQUENCY, 1.0) * height_scale
		_pond_level = (
			_value_noise(layout.pond_center.x, layout.pond_center.y, LOW_FREQUENCY, 1.0)
			* height_scale
		)
	_heights = _compute_heights()


## Height of the pond surface. The basin is carved below `_pond_level`, so the
## water sits a little under the rim and the shore stays visible.
func get_pond_water_level() -> float:
	if layout == null:
		return 0.0
	var center := layout.pond_center
	return height_at(center.x, center.y) + 0.3


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
			# Winding order decides which side is the front face, and the front
			# face is the side `generate_normals()` points the normal to.
			# Measured on Godot 4.7.2: the order (BL, TL, BR) produces normals
			# pointing DOWN (-Y), which back-face culling then hides from above.
			# Reversing each triangle ((BL, BR, TL) and (TL, BR, TR)) keeps the
			# *same* two triangles — so `height_at()` still matches the physics
			# heightmap — and turns the normals up. See
			# `tests/unit/test_terrain_generator.gd`.
			surface.add_index(bottom_left)
			surface.add_index(bottom_right)
			surface.add_index(top_left)
			surface.add_index(top_left)
			surface.add_index(bottom_right)
			surface.add_index(top_right)
	surface.generate_normals()
	surface.generate_tangents()
	return surface.commit()


## Unlit-texture-free material: the vertex colours carry all the shading variety.
func build_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.metallic = 0.0
	material.roughness = 0.93
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
	var low := _value_noise(x, z, LOW_FREQUENCY, 1.0)
	# Structural correction 11: broad ridge/valley — gentle but readable
	# at aerial. Two overlapping low frequencies with phase offset create
	# an undulating field pattern, not one perfect wave.
	low += _value_noise(x + 17.3, z - 11.7, 0.011, 0.38)
	low += _value_noise(x - 43.2, z + 28.4, 0.0065, 0.22)
	var detail := _value_noise(x, z, MID_FREQUENCY, 0.45)
	detail += _value_noise(x, z, HIGH_FREQUENCY, 0.18)
	var flat := flatten_weight(x, z)
	var height := (low + detail * (1.0 - flat)) * height_scale
	# Field warp — open country only, walkable slope preserved.
	# Increased from 0.13 to 0.22 for visible rolling at medium distance,
	# still <0.75 m peak on 5.0 scale.
	if layout != null and flat < 0.95:
		var field_weight := 1.0 - flat
		var field_warp := _value_noise(x, z, 0.038, 1.0) * 0.42
		field_warp += _value_noise(x + 91.4, z - 47.2, 0.074, 1.0) * 0.24
		field_warp += _value_noise(x - 27.0, z + 64.0, 0.016, 1.0) * 0.20
		height += field_warp * field_weight * height_scale * 0.22
		# Subtle roadside swale: very shallow ditch where road meets field,
		# makes the carriageway read as built, not painted. Masked strictly
		# to road edge (weight 0.25-0.65) so the centre stays flat for walking.
		var rw := layout.road_weight(x, z)
		if rw > 0.28 and rw < 0.68:
			var swale := sin((rw - 0.28) / 0.40 * PI) * field_weight
			height -= swale * height_scale * 0.032
	var plaza := plaza_weight(x, z)
	if plaza > 0.0:
		height = lerpf(height, _plaza_level, plaza)
	if layout != null:
		var pond := layout.pond_weight(x, z)
		if pond > 0.0:
			height = lerpf(height, _pond_level, clampf(pond * 2.0, 0.0, 1.0))
			height += layout.terrain_offset(x, z) * height_scale
		# Shore berm: readable lip before the basin drops — now 0.42 m peak
		# (was 0.27) so the hollow reads as hollow at eye level.
		var pond_w2 := layout.pond_weight(x, z)
		if pond_w2 > 0.05 and pond_w2 < 0.88:
			var berm := sin(pond_w2 * PI) * (1.0 - flat * 0.35)
			height += berm * height_scale * 0.082
			# Secondary undulation on berm crest for naturalism
			var berm_n := _value_noise(x, z, 0.086, 1.0) * 0.12
			height += berm_n * height_scale * 0.02 * (1.0 - flat)
	return height


## 1.0 where the ground must be walkable and level (plaza, roads, plots), 0.0 in
## open country. Delegates to the layout when there is one.
func flatten_weight(x: float, z: float) -> float:
	if layout != null:
		return layout.flatten_weight(x, z)
	var distance := sqrt(x * x + z * z)
	return _smoothstep(clampf((distance - PLAZA_RADIUS) / PLAZA_FALLOFF, 0.0, 1.0))


## 1.0 at the centre of the plaza, fading out past its rim.
func plaza_weight(x: float, z: float) -> float:
	if layout != null:
		return layout.plaza_weight(x, z)
	return 1.0 - clampf((sqrt(x * x + z * z) - PLAZA_RADIUS) / PLAZA_FALLOFF, 0.0, 1.0)


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
	var x := cell_to_world_x(ix)
	var z := cell_to_world_z(iz)

	# -----------------------------------------------------------------------
	# 1) Base grass — altitude + two-scale meadow patchwork.
	# -----------------------------------------------------------------------
	var color := COLOR_GRASS_DARK.lerp(COLOR_GRASS, height_t)
	# Two meadow scales: broad fields (~50 m) + smaller clearings (~20 m).  The
	# blend is deliberately uneven so the terrain never reads as a single tone.
	var meadow_big := clampf(_value_noise(x, z, 0.019, 1.0) * 0.5 + 0.5, 0.0, 1.0)
	var meadow_small := clampf(_value_noise(x + 17.3, z - 9.8, 0.041, 1.0) * 0.5 + 0.5, 0.0, 1.0)
	var patch := meadow_big * 0.62 + meadow_small * 0.38
	# Sun-bleached dry variation on higher ground: warm gold-green where the
	# hill catches the light.  Masked by slope (not on cliffs) and pond.
	var dry_noise := clampf(_value_noise(x * 0.72, z * 0.68, 0.014, 1.0) * 0.5 + 0.5, 0.0, 1.0)
	var dry_t := clampf((dry_noise - 0.66) / 0.28, 0.0, 1.0) * 0.20 * height_t
	color = color.lerp(COLOR_MEADOW, patch * 0.48)
	color = color.lerp(COLOR_GRASS_DRY, dry_t)
	# Heath / field weed tint: a cooler, slightly desaturated wash over broad
	# low-frequency patches, again masked on steep ground.
	var heath_noise := clampf(_value_noise(x + 53.1, z - 71.4, 0.009, 1.0) * 0.5 + 0.5, 0.0, 1.0)
	var heath_t := clampf((heath_noise - 0.58) / 0.32, 0.0, 1.0) * 0.16
	color = color.lerp(COLOR_HEATH, heath_t * (1.0 - clampf((slope - 0.25) / 0.4, 0.0, 1.0)))

	# -----------------------------------------------------------------------
	# 2) Rock & scree — slope-driven, with altitude bias and noise wobble.
	# -----------------------------------------------------------------------
	var slope_jitter := _value_noise(x, z, 0.11, 1.0) * 0.08
	var slope_adj := slope + slope_jitter
	var rock_t := clampf((slope_adj - 0.30) / 0.52, 0.0, 1.0)
	# Higher ground is naturally a touch more exposed.
	var altitude_rock := clampf((height / maxf(height_scale, 0.001) - 0.25) / 0.75, 0.0, 1.0) * 0.18
	rock_t = clampf(rock_t + altitude_rock, 0.0, 1.0)
	# Wet, pond-adjacent rock reads as moss-covered rather than pale stone.
	var pond_hint := 0.0
	if layout != null:
		pond_hint = layout.pond_weight(x, z)
	var rock_key := COLOR_ROCK
	# Subtle in-palette variation per rock face: warm stone vs gravelly tint.
	var rock_var := clampf(_value_noise(x + 7.4, z - 22.8, 0.095, 1.0) * 0.5 + 0.5, 0.0, 1.0)
	rock_key = rock_key.lerp(COLOR_GRAVEL, rock_var * 0.32)
	if pond_hint > 0.08:
		rock_key = rock_key.lerp(COLOR_MOSS, clampf((pond_hint - 0.08) / 0.42, 0.0, 1.0) * 0.55)
	color = color.lerp(rock_key, rock_t)
	# Scree fringe just below the rock threshold: a gravel speckle at the foot
	# of steep ground.  Intentionally sparse so it never turns cliffs into a
	# gravel field.
	var scree_t := clampf((slope_adj - 0.18) / 0.18, 0.0, 1.0) * (1.0 - rock_t) * 0.28
	if scree_t > 0.02:
		color = color.lerp(COLOR_GRAVEL, scree_t)

	var road_t := 0.0
	var pond_t := 0.0
	var plaza_t := 0.0
	var building_t := 0.0

	if layout == null:
		# Legacy disc: warm sand apron with a noise-broken edge.
		var distance := sqrt(x * x + z * z)
		var edge_n := _value_noise(x, z, 0.068, 1.0) * 2.2
		var sand_t := clampf(1.0 - (distance + edge_n - PLAZA_RADIUS) / 8.0, 0.0, 1.0) * (1.0 - rock_t)
		var sand_col := COLOR_SAND.lerp(COLOR_SAND_LIGHT, clampf(_value_noise(x, z, 0.12, 1.0) * 0.5 + 0.5, 0.0, 1.0) * 0.18)
		color = color.lerp(sand_col, sand_t)
	else:
		# -------------------------------------------------------------------
		# 3) Prepare organic edge jitter and shared weights.
		# -------------------------------------------------------------------
		var raw_road := layout.road_weight(x, z)
		var raw_plaza := layout.plaza_weight(x, z)
		var raw_pond := layout.pond_weight(x, z)
		# Two-frequency edge wobble: the visible colour edge is deliberately
		# softer and slightly irregular compared to the physics flatten weight,
		# so roads and plaza never read as a perfect geometric mask.
		var edge_jitter := _value_noise(x, z, 0.082, 1.0) * 0.22
		edge_jitter += _value_noise(x + 41.2, z - 27.6, 0.156, 1.0) * 0.10
		# Small secondary wobble at a different phase for the road verge.
		var road_extra_jitter := _value_noise(x - 18.4, z + 33.9, 0.19, 1.0) * 0.08
		var road_w := clampf(raw_road + edge_jitter * 0.65 + road_extra_jitter - 0.04, 0.0, 1.0) * (1.0 - rock_t * 0.45)
		var plaza_w := clampf(raw_plaza + edge_jitter * 0.55 - 0.03, 0.0, 1.0) * (1.0 - rock_t * 0.35)
		var pond_w := raw_pond
		road_t = road_w
		plaza_t = plaza_w
		pond_t = pond_w

		# Derive building proximity from the flatten weight: when flatten is
		# high but neither plaza nor road claims the point, it must be a plot.
		# This gives a cheap, O(1) building skirt without iterating placements.
		var flat := layout.flatten_weight(x, z)
		var mrw := maxf(raw_road, raw_plaza)
		if flat > mrw + 0.025:
			building_t = clampf((flat - mrw) / maxf(1.0 - mrw, 0.001), 0.0, 1.0) * (1.0 - rock_t * 0.5)
			# Keep the skirt subtle where it overlaps roads/plaza.
			building_t *= 1.0 - maxf(road_w, plaza_w) * 0.45

		# -------------------------------------------------------------------
		# 4) Roads — dirt core, clay streaks, gravel shoulder, centre wear.
		# -------------------------------------------------------------------
		if road_w > 0.02:
			# Core vs shoulder split: smoothstep gives a soft centre plateau.
			var road_core := _smoothstep(clampf((road_w - 0.45) / 0.50, 0.0, 1.0))
			var road_shoulder := clampf(road_w - road_core * 0.68, 0.0, 1.0)
			# Clay-streaked dirt: warmer, slightly redder ribbons along the
			# length of the road.  Uses a stretched noise field so streaks run
			# along the road rather than as spots.
			var clay_n := clampf(_value_noise(x * 1.08, z * 0.92, 0.062, 1.0) * 0.5 + 0.5, 0.0, 1.0)
			var clay_t_local := clay_n * road_core * 0.24
			var dirt_col := COLOR_DIRT.lerp(COLOR_CLAY, clay_t_local)
			# Gravel at the verge: where the verge meets the grass the ground
			# is looser and paler, with a little in-palette noise break-up.
			var gravel_n := clampf(_value_noise(x + 12.4, z - 33.1, 0.098, 1.0) * 0.5 + 0.5, 0.0, 1.0)
			dirt_col = dirt_col.lerp(COLOR_GRAVEL, gravel_n * road_shoulder * 0.18)
			color = color.lerp(dirt_col, road_core * (1.0 - pond_w * 0.65))
			color = color.lerp(COLOR_GRAVEL, road_shoulder * 0.52 * (0.55 + gravel_n * 0.45))
			# Centre darkening: the compacted strip where feet and wheels run.
			# Uses road distance (0 at centre line) so the darkening is always
			# centred on the carriageway, not smeared across the whole width.
			var dist_to_road := layout.road_distance(x, z)
			var centre_mask := clampf(1.0 - dist_to_road / (VillageLayout.ROAD_WIDTH * 0.48), 0.0, 1.0)
			centre_mask = _smoothstep(centre_mask) * road_core
			# Split into two faint ruts for the most travelled section: two
			# parallel dips 0.55 m off centre.  We approximate with a cosine of
			# the across-road distance so the effect is symmetric.
			var rut_phase := dist_to_road * 1.85
			var rut_mod := 0.55 + 0.45 * cos(rut_phase * TAU * 0.9)
			centre_mask *= rut_mod
			color = color.darkened(centre_mask * 0.10)
			# Slight warmth in the ruts where mud shows through.
			color = color.lerp(COLOR_SOIL, centre_mask * 0.14)

		# -------------------------------------------------------------------
		# 5) Pond — mud centre, sand fringe, mossy shore.
		# -------------------------------------------------------------------
		if pond_w > 0.02:
			# Concentric shore model: centre -> shallow -> shoreline.
			var mud_t := _smoothstep(clampf((pond_w - 0.58) / 0.38, 0.0, 1.0))
			var shallow_t := clampf(pond_w, 0.0, 1.0) - mud_t
			# Sand fringe lives in the shallow band: the ring where water meets
			# earth.  Extra noise breaks the perfect circle.
			var sand_n := clampf(_value_noise(x + 22.7, z - 14.4, 0.088, 1.0) * 0.5 + 0.5, 0.0, 1.0)
			var sand_t := shallow_t * (0.55 + sand_n * 0.35)
			var sand_col := COLOR_SAND.lerp(COLOR_SAND_LIGHT, sand_n * 0.22)
			color = color.lerp(sand_col, sand_t * 0.72)
			color = color.lerp(COLOR_MUD, mud_t)
			# Damp moss at the water line where the two meet.
			var moss_edge := clampf(1.0 - absf(pond_w - 0.52) / 0.28, 0.0, 1.0)
			color = color.lerp(COLOR_MOSS, moss_edge * 0.22 * (1.0 - rock_t))
			# General wet darkening toward the centre.
			color = color.darkened(pond_w * 0.08)

		# -------------------------------------------------------------------
		# 6) Plaza — variegated cobble, wear ring, dirt bleed at road mouths.
		# -------------------------------------------------------------------
		if plaza_w > 0.02:
			var plaza_core := _smoothstep(clampf((plaza_w - 0.30) / 0.60, 0.0, 1.0))
			var plaza_edge := clampf(plaza_w - plaza_core * 0.75, 0.0, 1.0)
			# Cobble variation: two noise scales, one broad warmth, one tighter
			# tile-to-tile speckle.
			var cobble_big := clampf(_value_noise(x + 9.1, z - 18.7, 0.062, 1.0) * 0.5 + 0.5, 0.0, 1.0)
			var cobble_small := clampf(_value_noise(x - 31.2, z + 11.8, 0.22, 1.0) * 0.5 + 0.5, 0.0, 1.0)
			var cobble_col := COLOR_COBBLE.lerp(COLOR_STONE_WARM, cobble_big * 0.24)
			cobble_col = cobble_col.lerp(COLOR_GRAVEL, cobble_small * 0.14)
			# Dirt in the joints: pockets of earth between the stones.
			var joint_dirt := clampf((cobble_small - 0.62) / 0.32, 0.0, 1.0) * 0.10
			cobble_col = cobble_col.lerp(COLOR_DIRT, joint_dirt)
			color = color.lerp(cobble_col, plaza_core)
			# Foot polish: the very centre of the square is slightly lighter
			# where generations of feet have worn the stone smooth.
			var dist_plaza := sqrt(x * x + z * z)
			var centre_polish := clampf(1.0 - dist_plaza / (VillageLayout.PLAZA_RADIUS * 0.62), 0.0, 1.0)
			centre_polish = _smoothstep(centre_polish) * plaza_core
			color = color.lerp(Color.WHITE, centre_polish * 0.055)
			# Edge wear: darker at the rim where rain and boots drag dirt onto
			# the stones.
			color = color.darkened(plaza_edge * 0.09)
			# Road mouths bleed a little dirt into the square: where both
			# weights are high, the plaza reads as a continuation of the road.
			var overlap := plaza_w * raw_road
			if overlap > 0.02:
				color = color.lerp(COLOR_DIRT, overlap * 0.22)

		# -------------------------------------------------------------------
		# 7) Building skirts — trampled earth and gravel apron.
		# -------------------------------------------------------------------
		if building_t > 0.02:
			# Trampled soil: a warm, compacted ring where people walk around
			# their homes, distinct from the looser field grass.
			color = color.lerp(COLOR_SOIL, building_t * 0.34)
			# Very close to a building (high skirt) the ground is firmer and
			# gravelly — the foundation splash.
			if building_t > 0.62:
				var skirt := clampf((building_t - 0.62) / 0.38, 0.0, 1.0)
				color = color.lerp(COLOR_GRAVEL, skirt * 0.32)

	# -----------------------------------------------------------------------
	# 8) Surface mottling — three-scale grain that survives the 1 m vertex
	#    grid.  Large grain gives field-scale warmth, medium survives the grid,
	#    fine keeps stone/earth/meadow from reading as flat fills. All three
	#    are deterministic hashes, so every machine paints the same world.
	# -----------------------------------------------------------------------
	var medium_grain := _value_noise(x + 31.7, z - 18.3, 0.29, 0.055)
	var fine_grain := _value_noise(x - 47.2, z + 63.1, 0.61, 0.020)
	var large_grain := _value_noise(x + 11.4, z - 52.8, 0.088, 0.038)
	var surface_grain := medium_grain + fine_grain + large_grain * 0.55
	var built_weight := 0.0
	if layout != null:
		built_weight = maxf(road_t, maxf(pond_t, maxf(plaza_t, building_t)))
		built_weight = maxf(built_weight, rock_t * 0.45)
	var grain_strength := 0.44 + built_weight * 0.22
	# Built ground gets a touch more grain so cobble/dirt never look like a
	# flat colour field — but never so much that it turns into noise.
	if surface_grain >= 0.0:
		color = color.lerp(Color.WHITE, surface_grain * grain_strength)
	else:
		color = color.darkened(-surface_grain * grain_strength)

	# -----------------------------------------------------------------------
	# 9) Valley ambient occlusion — subtle darkening in low, sheltered ground.
	#    Purely colour-based (no extra texture), it deepens the perceived
	#    topography at no performance cost.
	# -----------------------------------------------------------------------
	var ao_t := clampf((0.45 - height_t) / 0.45, 0.0, 1.0) * (1.0 - built_weight * 0.65) * 0.07
	color = color.darkened(ao_t)
	return color
