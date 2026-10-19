class_name VillageBuilder
extends RefCounted
## Assembles the village: one deterministic pass over [VillageLayout] that
## produces meshes, colliders, ground cover and water.
##
## Node layout of what it returns:
##
##     Village
##     ├── Structures          one node per house / inn / hall / well / stall,
##     │                       each with its own merged meshes and Collision body
##     ├── Props               every lamp, fence, cart, crate, barrel, log pile,
##     │   │                   signpost and the plaza kerb, merged into a few
##     │   │                   meshes
##     │   └── PropCollision   one StaticBody3D holding every small prop collider
##     ├── Vegetation          the whole forest, merged into a few meshes
##     │   └── TreeCollision   one StaticBody3D holding every trunk collider
##     ├── Grass               one MultiMeshInstance3D
##     └── Water               the pond surface
##
## Structures stay separate nodes on purpose: the simulation will later need to
## address "house 7" as a thing with an owner and a door. Scenery does not, so
## scenery is merged until it is nearly free.

## Flat pads drifting on the pond surface.
const POND_LILY_COUNT := 7
## Visual polish 17: low rock outcrops on real slopes. They are partly buried,
## deliberately collider-free, and assembled as a boulder plus downhill chips.
const SLOPE_OUTCROP_COUNT := 18
const SLOPE_OUTCROP_MIN_SLOPE := 0.17
const SLOPE_OUTCROP_MIN_SPACING := 3.4

var layout: VillageLayout = null
var terrain: TerrainGenerator = null
var materials: VillageMaterials = null
## Deterministic centers of the collider-free slope outcrops, exposed for review.
var slope_outcrop_positions: Array[Vector2] = []

var _buildings: BuildingFactory = null
var _vegetation: VegetationBuilder = null
var _ground: GroundSurfaces = null
var _detail_rng := RandomNumberGenerator.new()
var _structure_count := 0
var _prop_count := 0
var _vegetation_count := 0
var _collider_count := 0
var _mesh_count := 0
var _triangle_count := 0


func _init(
	initial_layout: VillageLayout, initial_terrain: TerrainGenerator,
	initial_materials: VillageMaterials
) -> void:
	layout = initial_layout
	terrain = initial_terrain
	materials = initial_materials
	_buildings = BuildingFactory.new(materials, layout.world_seed)
	_vegetation = VegetationBuilder.new(layout.world_seed + 7)
	_ground = GroundSurfaces.new(layout, terrain, materials)
	_detail_rng.seed = layout.world_seed + 31


## Builds the whole village. Called once, at world startup.
func build_village() -> Node3D:
	var root := Node3D.new()
	root.name = "Village"
	root.add_child(_build_structures())
	root.add_child(_build_props())
	root.add_child(_build_vegetation())
	var paving := _ground.build()
	root.add_child(paving)
	for child in paving.get_children():
		if child is MeshInstance3D:
			_mesh_count += 1
			_triangle_count += _mesh_triangles((child as MeshInstance3D).mesh)
	root.add_child(_vegetation.build_grass(layout, terrain, materials))
	root.add_child(_build_water())
	return root


# --- stats, used by the boot log and by the tests ----------------------------


func get_structure_count() -> int:
	return _structure_count


func get_prop_count() -> int:
	return _prop_count


func get_vegetation_count() -> int:
	return _vegetation_count


func get_collider_count() -> int:
	return _collider_count


## Draw calls contributed by the village: one per baked mesh, plus the grass.
func get_mesh_count() -> int:
	return _mesh_count


func get_triangle_count() -> int:
	return _triangle_count


func summary() -> String:
	return (
		"%d structures, %d props, %d plants/rocks, %d kerb stones, %d meshes, "
		+ "%d colliders, ~%d tris"
		% [
			_structure_count,
			_prop_count,
			_vegetation_count,
			_ground.kerb_stone_count if _ground != null else 0,
			_mesh_count,
			_collider_count,
			_triangle_count,
		]
	)


# --- passes ------------------------------------------------------------------


func _build_structures() -> Node3D:
	var root := Node3D.new()
	root.name = "Structures"
	for placement in layout.placements:
		if not BuildingFactory.is_structure(placement.kind):
			continue
		var node := _buildings.build_structure(placement)
		node.transform = _placement_transform(placement)
		root.add_child(node)
		_structure_count += 1
		for child in node.get_children():
			if child is MeshInstance3D:
				_mesh_count += 1
				_triangle_count += _mesh_triangles((child as MeshInstance3D).mesh)
			elif child is StaticBody3D:
				_collider_count += child.get_child_count()
	return root


func _build_props() -> Node3D:
	var root := Node3D.new()
	root.name = "Props"
	var baker := MeshBaker.new()
	var colliders := StaticBody3D.new()
	colliders.name = "PropCollision"
	_ground.bake_kerbs(baker)
	_bake_pond_lilies(baker)
	_bake_pond_shore_pebbles(baker)
	_bake_slope_outcrops(baker)
	root.set_meta("slope_outcrop_count", slope_outcrop_positions.size())
	for placement in layout.placements:
		if BuildingFactory.is_structure(placement.kind):
			continue
		if VillageLayout.is_vegetation(placement.kind):
			continue
		var origin := _placement_transform(placement)
		_buildings.append_prop(baker, placement, origin)
		_prop_count += 1
		for shape in _buildings.colliders_for(placement):
			shape.transform = origin * shape.transform
			colliders.add_child(shape)
			_collider_count += 1
	for baked in baker.commit(materials):
		root.add_child(baked)
		_mesh_count += 1
	_triangle_count += baker.get_triangle_count()
	root.add_child(colliders)
	return root


func _build_vegetation() -> Node3D:
	var root := Node3D.new()
	root.name = "Vegetation"
	var baker := MeshBaker.new()
	var colliders := StaticBody3D.new()
	colliders.name = "TreeCollision"
	for placement in layout.placements:
		if not VillageLayout.is_vegetation(placement.kind):
			continue
		var origin := _placement_transform(placement)
		# Detail follows distance: near trees and the ones lining a road get the
		# full silhouette, the outer forest a cheaper one. Both stay species
		# specific, so the tree line still reads from the square.
		_vegetation.append(
			baker, placement, origin, _vegetation.needs_detail(layout, placement)
		)
		_vegetation_count += 1
		var collider_origin := origin
		if placement.kind == VillageLayout.KIND_ROCK:
			# Preserve the pre-existing upright/yawed boulder collider. The new
			# slope-aligned rotation is a render-only improvement.
			var yaw := deg_to_rad(placement.rotation_deg)
			collider_origin = Transform3D(
				Basis.from_euler(Vector3(0.0, yaw, 0.0)), origin.origin
			)
		for shape in _vegetation.colliders_for(placement):
			shape.transform = collider_origin * shape.transform
			colliders.add_child(shape)
			_collider_count += 1
	for baked in baker.commit(materials):
		root.add_child(baked)
		_mesh_count += 1
	_triangle_count += baker.get_triangle_count()
	root.add_child(colliders)
	return root


## Flat lily pads drifting near the pond shore: a handful of horizontal quads
## just above the water, cheap and enough to make the surface look alive.
func _bake_pond_lilies(baker: MeshBaker) -> void:
	var center := layout.pond_center
	var water_level := terrain.get_pond_water_level()
	for index in POND_LILY_COUNT:
		var angle := _detail_rng.randf() * TAU
		var distance := layout.pond_radius * _detail_rng.randf_range(0.15, 0.62)
		var point := center + Vector2(cos(angle), sin(angle)) * distance
		var tint := Color.WHITE.darkened(_detail_rng.randf_range(0.0, 0.12))
		baker.add_quad(
			"leaf_mid",
			Vector2(0.85, 0.75),
			Transform3D(
				Basis.from_euler(Vector3(-PI * 0.5, _detail_rng.randf() * TAU, 0.0)),
				Vector3(point.x, water_level + 0.045, point.y)
			),
			tint,
			true
		)


## Pebble-and-gravel ring at the water line: small, flat stones that hide the
## hard circular cut between the water disc and the terrain mesh.  No collider —
## the player steps over them — and merged into the prop mesh so they cost no
## extra draw call. Visual Polish 17 replaces the old boxes with small faceted
## stones whose bases follow the bank and remain collider-free.
func _bake_pond_shore_pebbles(baker: MeshBaker) -> void:
	var center := layout.pond_center
	var ring := layout.pond_radius
	for index in 18:
		var angle := TAU * (float(index) + _detail_rng.randf_range(-0.25, 0.25)) / 18.0
		# Two concentric rings: the inner one half-buried in the mud, the outer
		# one on the grass verge.  Jitter keeps them from forming a ruler.
		for band: float in [0.88, 1.06]:
			if _detail_rng.randf() < 0.18:
				continue
			var dist: float = ring * (band + _detail_rng.randf_range(-0.07, 0.07))
			var point: Vector2 = center + Vector2(cos(angle), sin(angle)) * dist
			if layout.road_weight(point.x, point.y) > 0.15:
				continue
			if _near_structure(point, 0.6):
				continue
			var size := Vector3(
				_detail_rng.randf_range(0.42, 0.76),
				_detail_rng.randf_range(0.24, 0.42),
				_detail_rng.randf_range(0.36, 0.68)
			)
			var yaw := _detail_rng.randf_range(0.0, 360.0)
			var key := "rock_wet" if _detail_rng.randf() < 0.55 else "rock"
			var tint := Color.WHITE.darkened(_detail_rng.randf_range(0.04, 0.16))
			var shape_seed := _detail_rng.randi() * 3 + index % 3
			baker.add_rock(
				key, size, shape_seed, _surface_transform(point, yaw), tint, 0.10
			)
		# Occasional reed clump just outside the water — two crossed quads,
		# purely decorative, very cheap.
		if _detail_rng.randf() < 0.42:
			var dist := ring * _detail_rng.randf_range(1.02, 1.22)
			var point := center + Vector2(cos(angle), sin(angle)) * dist
			if layout.road_weight(point.x, point.y) > 0.08:
				continue
			var h := terrain.height_at(point.x, point.y)
			var reed_h := _detail_rng.randf_range(0.55, 0.85)
			var reed_tint := Color.WHITE.darkened(_detail_rng.randf_range(0.02, 0.10))
			baker.add_quad(
				"leaf_deep",
				Vector2(0.12, reed_h),
				Transform3D(
					Basis.from_euler(Vector3(0, _detail_rng.randf() * TAU, deg_to_rad(8.0))),
					Vector3(point.x, h + reed_h * 0.5, point.y)
				),
				reed_tint,
				true
			)
			baker.add_quad(
				"leaf_deep",
				Vector2(0.12, reed_h * 0.9),
				Transform3D(
					Basis.from_euler(Vector3(0, _detail_rng.randf() * TAU + PI * 0.5, deg_to_rad(8.0))),
					Vector3(point.x, h + reed_h * 0.45, point.y)
				),
				reed_tint.lightened(0.06),
				true
			)


## Visual polish 17 — low stone outcrops on real slopes. The terrain already
## paints exposed rock and scree; these closed, angular boulders add a silhouette
## and a small downhill talus group. Their own RNG keeps kerbs, lilies and the
## existing prop placement sequence deterministic.
##
## No colliders: these remain scenery over the existing heightfield; no new
## movement rule or physical obstruction is added to a route.
func _bake_slope_outcrops(baker: MeshBaker) -> void:
	slope_outcrop_positions.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = layout.world_seed + 97
	var placed: Array[Vector2] = []
	var attempts := 0
	while placed.size() < SLOPE_OUTCROP_COUNT and attempts < SLOPE_OUTCROP_COUNT * 18:
		attempts += 1
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(
			VillageLayout.PLAZA_RADIUS + 7.0, layout.half_extent - 4.5
		)
		var point := Vector2(cos(angle), sin(angle)) * distance
		if layout.flatten_weight(point.x, point.y) > 0.22:
			continue
		if layout.road_weight(point.x, point.y) > 0.10:
			continue
		if layout.pond_weight(point.x, point.y) > 0.12:
			continue
		var slope := terrain.slope_at(point.x, point.y)
		if slope < SLOPE_OUTCROP_MIN_SLOPE:
			continue
		if _near_structure(point, 1.1) or _near_vegetation(point, 0.9):
			continue
		var crowded := false
		for other in placed:
			if point.distance_to(other) < SLOPE_OUTCROP_MIN_SPACING:
				crowded = true
				break
		if crowded:
			continue
		placed.append(point)
		slope_outcrop_positions.append(point)
		var size := rng.randf_range(0.58, 1.15) * clampf(slope * 2.2, 0.75, 1.25)
		var key := "rock_wet" if layout.pond_weight(point.x, point.y) > 0.02 else "rock"
		var tint := Color.WHITE.darkened(rng.randf_range(0.02, 0.16))
		var yaw := rng.randf_range(0.0, 360.0)
		var main_size := Vector3(1.55, 0.92, 1.34) * size
		var main_seed := rng.randi() * 3 + (slope_outcrop_positions.size() - 1) % 3
		# The mesh is rooted below the exact terrain plane and its local up axis
		# follows the slope. This replaces the old tilted UV sphere whose lower
		# edge could peek above one side of the hill.
		baker.add_rock(
			key, main_size, main_seed, _surface_transform(point, yaw), tint, 0.14
		)

		# A talus ribbon of one or two chips follows gravity downhill. Each piece
		# re-samples the actual terrain, so chips stay grounded across a slope
		# instead of copying the parent's height and hovering over a dip.
		var up := terrain._surface_normal_at(point.x, point.y)
		var downhill := Vector2(up.x, up.z).normalized()
		if downhill.length_squared() < 0.001:
			var fallback_angle := rng.randf() * TAU
			downhill = Vector2(cos(fallback_angle), sin(fallback_angle))
		var across := Vector2(-downhill.y, downhill.x)
		var chip_count := 2 if rng.randf() < 0.40 else 1
		for chip_index in chip_count:
			var offset := size * (0.52 + float(chip_index) * 0.30)
			var lateral := rng.randf_range(-0.16, 0.16) * size
			var chip_point := point + downhill * offset + across * lateral
			if layout.road_weight(chip_point.x, chip_point.y) > 0.10:
				continue
			if layout.flatten_weight(chip_point.x, chip_point.y) > 0.22:
				continue
			if _near_structure(chip_point, 0.45) or _near_vegetation(chip_point, 0.35):
				continue
			var chip_size := Vector3(0.56, 0.40, 0.60) * size
			chip_size *= rng.randf_range(0.88, 1.08)
			var chip_yaw := yaw + rng.randf_range(-32.0, 32.0)
			var chip_seed := rng.randi() * 3 + (chip_index + 1) % 3
			baker.add_rock(
				key, chip_size, chip_seed, _surface_transform(chip_point, chip_yaw),
				tint.lightened(rng.randf_range(0.025, 0.075)), 0.12
			)


func _build_water() -> Node3D:
	var node := MeshInstance3D.new()
	node.name = "Water"
	# A flat disc (not a quad) so the pond surface is guaranteed horizontal and
	# circular; its radius stops just inside the basin rim, so the shoreline is
	# where the terrain meets the water level instead of a visible square edge.
	var disc := CylinderMesh.new()
	disc.top_radius = layout.pond_radius * 0.92
	disc.bottom_radius = layout.pond_radius * 0.92
	disc.height = 0.06
	disc.radial_segments = 24
	node.mesh = disc
	node.material_override = materials.get_material("water")
	var center := layout.pond_center
	node.position = Vector3(center.x, terrain.get_pond_water_level(), center.y)
	_mesh_count += 1
	_triangle_count += 24 * 2 + 24 * 2
	return node


# --- helpers -----------------------------------------------------------------


## True when [param point] stands within the plot of a structure plus
## [param margin]: used to keep baked ground detail out of stoops and door
## yards.
func _near_structure(point: Vector2, margin: float) -> bool:
	for placement in layout.placements:
		if not BuildingFactory.is_structure(placement.kind):
			continue
		var radius: float = placement.footprint_radius * placement.scale + margin
		if point.distance_to(placement.position) < radius:
			return true
	return false


## True when a scenic outcrop would visibly overlap an existing tree, shrub,
## flower patch or placed stone. These are visual clearances only; no gameplay
## or NPC navigation data is edited.
func _near_vegetation(point: Vector2, margin: float) -> bool:
	for placement in layout.placements:
		if not VillageLayout.is_vegetation(placement.kind):
			continue
		var radius: float = placement.footprint_radius * placement.scale + margin
		if point.distance_to(placement.position) < radius:
			return true
	return false


## Terrain-aligned transform for stone only. A projected forward vector fixes
## the rock's yaw around the actual surface normal while keeping an orthogonal
## local basis for both the baked mesh and its existing collider.
func _surface_transform(point: Vector2, yaw_degrees: float) -> Transform3D:
	var up := terrain._surface_normal_at(point.x, point.y)
	var yaw := deg_to_rad(yaw_degrees)
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	forward -= up * forward.dot(up)
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
	forward = forward.normalized()
	var right := up.cross(forward).normalized()
	forward = right.cross(up).normalized()
	var basis := Basis(right, up, forward)
	return Transform3D(
		basis, Vector3(point.x, terrain.height_at(point.x, point.y), point.y)
	)


## Grounded transform of a placement. `VillageLayout` stores XZ only; the
## height always comes from the terrain. Stones also follow the exact local
## slope plane so their partially buried bases meet the mesh instead of hovering.
func _placement_transform(placement: VillageLayout.Placement) -> Transform3D:
	if placement.kind == VillageLayout.KIND_ROCK:
		return _surface_transform(placement.position, placement.rotation_deg)
	var x := placement.position.x
	var z := placement.position.y
	var basis := Basis.from_euler(Vector3(0, deg_to_rad(placement.rotation_deg), 0))
	return Transform3D(basis, Vector3(x, terrain.height_at(x, z), z))


func _mesh_triangles(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for surface in mesh.get_surface_count():
		total += mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size() / 3
	return total
