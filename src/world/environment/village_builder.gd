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

var layout: VillageLayout = null
var terrain: TerrainGenerator = null
var materials: VillageMaterials = null

var _buildings: BuildingFactory = null
var _vegetation: VegetationBuilder = null
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
func _bake_plaza_kerb(baker: MeshBaker) -> void:
	var step := TAU / float(PLAZA_KERB_SEGMENTS)
	for index in PLAZA_KERB_SEGMENTS:
		var angle := step * (float(index) + 0.5)
		var x := cos(angle) * PLAZA_KERB_RADIUS
		var z := sin(angle) * PLAZA_KERB_RADIUS
		var yaw := rad_to_deg(atan2(x, z))
		var height := terrain.height_at(x, z)
		var tint := Color.WHITE.darkened(0.06 * float(index % 3))
		baker.add_box(
			"cobble",
			Vector3(1.9, 0.28, 0.7),
			Transform3D(
				Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0)), Vector3(x, height + 0.12, z)
			),
			tint
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
