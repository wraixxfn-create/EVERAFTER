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

const PLAZA_KERB_SEGMENTS := 44
const PLAZA_KERB_RADIUS := 12.2
## Road edging: stone spacing along the verge, and how often one is missing.
const ROAD_KERB_SPACING := 2.4
const ROAD_KERB_GAP_CHANCE := 0.12
## Flat pads drifting on the pond surface.
const POND_LILY_COUNT := 7

var layout: VillageLayout = null
var terrain: TerrainGenerator = null
var materials: VillageMaterials = null

var _buildings: BuildingFactory = null
var _vegetation: VegetationBuilder = null
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
	_detail_rng.seed = layout.world_seed + 31


## Builds the whole village. Called once, at world startup.
func build_village() -> Node3D:
	var root := Node3D.new()
	root.name = "Village"
	root.add_child(_build_structures())
	root.add_child(_build_props())
	root.add_child(_build_vegetation())
	root.add_child(_vegetation.build_grass(layout, terrain, materials))
	root.add_child(_build_water())
	_mesh_count += 1
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
		"%d structures, %d props, %d plants/rocks, %d meshes, %d colliders, ~%d tris"
		% [
			_structure_count,
			_prop_count,
			_vegetation_count,
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
	_bake_plaza_kerb(baker)
	_bake_road_kerb(baker)
	_bake_pond_lilies(baker)
	_bake_pond_shore_pebbles(baker)
	for placement in layout.placements:
		if BuildingFactory.is_structure(placement.kind):
			continue
		if placement.kind in [
			VillageLayout.KIND_TREE_PINE,
			VillageLayout.KIND_TREE_OAK,
			VillageLayout.KIND_TREE_BIRCH,
			VillageLayout.KIND_BUSH,
			VillageLayout.KIND_ROCK,
		]:
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
		var is_plant := placement.kind in [
			VillageLayout.KIND_TREE_PINE,
			VillageLayout.KIND_TREE_OAK,
			VillageLayout.KIND_TREE_BIRCH,
			VillageLayout.KIND_BUSH,
			VillageLayout.KIND_ROCK,
		]
		if not is_plant:
			continue
		var origin := _placement_transform(placement)
		_vegetation.append(baker, placement, origin)
		_vegetation_count += 1
		for shape in _vegetation.colliders_for(placement):
			shape.transform = origin * shape.transform
			colliders.add_child(shape)
			_collider_count += 1
	for baked in baker.commit(materials):
		root.add_child(baked)
		_mesh_count += 1
	_triangle_count += baker.get_triangle_count()
	root.add_child(colliders)
	return root


## A low stone kerb around the plaza: the cheapest possible way to make the
## square read as built ground rather than a patch of yellow grass.
## Visual polish 06 slightly varies each segment length and height so the ring
## never reads as a perfect extruded torus — a few centimetres of irregularity
## are enough to suggest hand-laid stone.
func _bake_plaza_kerb(baker: MeshBaker) -> void:
	var step := TAU / float(PLAZA_KERB_SEGMENTS)
	for index in PLAZA_KERB_SEGMENTS:
		var angle := step * (float(index) + 0.5)
		var x := cos(angle) * PLAZA_KERB_RADIUS
		var z := sin(angle) * PLAZA_KERB_RADIUS
		var yaw := rad_to_deg(atan2(x, z))
		var height := terrain.height_at(x, z)
		var tint := Color.WHITE.darkened(0.05 + _detail_rng.randf_range(0.0, 0.08) + 0.02 * float(index % 2))
		var length := _detail_rng.randf_range(1.75, 2.05)
		var h := _detail_rng.randf_range(0.26, 0.30)
		baker.add_box(
			"cobble",
			Vector3(length, h, 0.66 + _detail_rng.randf_range(-0.06, 0.06)),
			Transform3D(
				Basis.from_euler(Vector3(0, deg_to_rad(yaw + _detail_rng.randf_range(-2.0, 2.0)), 0)),
				Vector3(x, height + 0.11 + _detail_rng.randf_range(-0.015, 0.015), z)
			),
			tint,
			0.06
		)


## The same edging along both verges of every road: it turns the painted dirt
## strip into a built path and gives the eye a line where pavement meets
## ground. Stones are irregularly spaced and occasionally missing, so the edge
## reads as hand-laid. Merged into the prop meshes, no colliders: the player
## steps over it like the plaza kerb.
func _bake_road_kerb(baker: MeshBaker) -> void:
	for road in layout.roads:
		for index in road.size() - 1:
			var start: Vector2 = road[index]
			var end: Vector2 = road[index + 1]
			var span := end - start
			var length := span.length()
			if length < 3.0:
				continue
			var along := span / length
			var outward := Vector2(-along.y, along.x)
			var yaw := atan2(-along.y, along.x)
			var steps := int(length / ROAD_KERB_SPACING)
			for step in steps:
				var t := (float(step) + 0.5 + _detail_rng.randf_range(-0.35, 0.35)) \
					* ROAD_KERB_SPACING / length
				t = clampf(t, 0.02, 0.98)
				if _detail_rng.randf() < ROAD_KERB_GAP_CHANCE:
					continue
				for side in [-1.0, 1.0]:
					var lateral := (VillageLayout.ROAD_WIDTH * 0.5 + 0.32) * side
					var point := start + span * t + outward * lateral
					if point.length() < VillageLayout.PLAZA_RADIUS + 2.0:
						continue
					if layout.pond_weight(point.x, point.y) > 0.25:
						continue
					# Leave a gap wherever a building fronts the road: the
					# break in the edging is where a doorstep or a path to a
					# door crosses it, so nothing collides with a stoop.
					if _near_structure(point, 1.0):
						continue
					var height := terrain.height_at(point.x, point.y)
					var tint := Color.WHITE.darkened(_detail_rng.randf_range(0.02, 0.14))
					var size := Vector3(
						_detail_rng.randf_range(0.8, 1.1), 0.22, 0.38
					)
					baker.add_box(
						"cobble",
						size,
						Transform3D(
							Basis.from_euler(Vector3(0.0, yaw, 0.0)),
							Vector3(point.x, height + 0.08, point.y)
						),
						tint,
						0.06
					)


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
## extra draw call.  Visual polish 06: makes the shore read as shore, not as a
## texture edge.
func _bake_pond_shore_pebbles(baker: MeshBaker) -> void:
	var center := layout.pond_center
	var ring := layout.pond_radius
	for index in 18:
		var angle := TAU * (float(index) + _detail_rng.randf_range(-0.25, 0.25)) / 18.0
		# Two concentric rings: the inner one half-buried in the mud, the outer
		# one on the grass verge.  Jitter keeps them from forming a ruler.
		for band in [0.88, 1.06]:
			if _detail_rng.randf() < 0.18:
				continue
			var dist := ring * (band + _detail_rng.randf_range(-0.07, 0.07))
			var point := center + Vector2(cos(angle), sin(angle)) * dist
			if layout.road_weight(point.x, point.y) > 0.15:
				continue
			if _near_structure(point, 0.6):
				continue
			var h := terrain.height_at(point.x, point.y)
			var size := Vector3(
				_detail_rng.randf_range(0.55, 0.95),
				_detail_rng.randf_range(0.12, 0.18),
				_detail_rng.randf_range(0.45, 0.75)
			)
			var yaw := _detail_rng.randf_range(0.0, 360.0)
			var key := "rock" if _detail_rng.randf() < 0.55 else "stone"
			var tint := Color.WHITE.darkened(_detail_rng.randf_range(0.04, 0.16))
			baker.add_box(
				key,
				size,
				Transform3D(
					Basis.from_euler(Vector3(0, deg_to_rad(yaw), deg_to_rad(_detail_rng.randf_range(-4.0, 4.0)))),
					Vector3(point.x, h + 0.06, point.y)
				),
				tint,
				0.08
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


## Grounded, yawed transform of a placement. `VillageLayout` stores XZ only; the
## height always comes from the terrain, so props sit on the surface instead of
## floating above it or sinking into it.
func _placement_transform(placement: VillageLayout.Placement) -> Transform3D:
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
