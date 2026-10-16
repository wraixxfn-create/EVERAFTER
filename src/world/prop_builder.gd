class_name PropBuilder
extends RefCounted
## Builds the provisional, stylised village out of engine primitives.
##
## Scope of this phase: a recognisable 3D settlement (a central monument, a ring
## of houses, a scatter of trees) with *no* external assets, so the repository
## stays text-only and the environment is obviously a placeholder for the real
## art direction (see `docs/ROADMAP.md`).
##
## Everything is placed with the terrain height field, so props sit on the
## ground instead of floating, and every random choice comes from a seeded
## [RandomNumberGenerator]: the same seed rebuilds the same village.
##
## Not implemented here on purpose: interiors, doors, pathfinding cost,
## ownership. Those belong to the future `npcs` / `economy` modules and need
## data structures that do not exist yet.

const HOUSE_RING_MIN_RADIUS := 18.0
const HOUSE_RING_MAX_RADIUS := 26.0
const TREE_RING_MIN_RADIUS := 28.0
const TREE_RING_MAX_RADIUS := 46.0

const COLOR_WALLS := [Color(0.82, 0.76, 0.63), Color(0.69, 0.60, 0.50), Color(0.58, 0.52, 0.48)]
const COLOR_ROOF := Color(0.55, 0.28, 0.22)
const COLOR_WOOD := Color(0.42, 0.31, 0.21)
const COLOR_STONE := Color(0.62, 0.62, 0.60)
const COLOR_LEAVES := Color(0.22, 0.42, 0.24)

var terrain: TerrainGenerator
var rng := RandomNumberGenerator.new()

var _materials := {}


func _init(terrain_reference: TerrainGenerator, seed_value: int = 0) -> void:
	terrain = terrain_reference
	rng.seed = seed_value


## Assembles the whole village under a single node, ready to be added to the
## world scene. Draw calls stay low because materials are shared.
func build_village(house_count: int = 8, tree_count: int = 24) -> Node3D:
	var root := Node3D.new()
	root.name = "Village"
	root.add_child(_build_monument())
	for i in maxi(house_count, 0):
		var angle := TAU * float(i) / float(maxi(house_count, 1)) + 0.35
		var radius := rng.randf_range(HOUSE_RING_MIN_RADIUS, HOUSE_RING_MAX_RADIUS)
		root.add_child(_build_house(i, Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)))
	for i in maxi(tree_count, 0):
		var tree_angle := rng.randf_range(0.0, TAU)
		var tree_radius := rng.randf_range(TREE_RING_MIN_RADIUS, TREE_RING_MAX_RADIUS)
		root.add_child(
			_build_tree(i, Vector3(cos(tree_angle) * tree_radius, 0.0, sin(tree_angle) * tree_radius))
		)
	return root


# --- individual props --------------------------------------------------------


func _build_monument() -> Node3D:
	var monument := Node3D.new()
	monument.name = "Monument"

	var platform := MeshInstance3D.new()
	platform.mesh = _cylinder(4.5, 4.5, 0.2, 24)
	platform.material_override = _material(COLOR_STONE)
	platform.position = Vector3(0.0, 0.1, 0.0)
	monument.add_child(platform)

	var obelisk := MeshInstance3D.new()
	obelisk.mesh = _box(Vector3(1.1, 4.6, 1.1))
	obelisk.material_override = _material(COLOR_STONE.darkened(0.15))
	obelisk.position = Vector3(0.0, 2.5, 0.0)
	monument.add_child(obelisk)

	var cap := MeshInstance3D.new()
	cap.mesh = _cylinder(0.0, 0.85, 1.0, 4)
	cap.material_override = _material(COLOR_ROOF)
	cap.position = Vector3(0.0, 5.3, 0.0)
	cap.rotation.y = PI * 0.25
	monument.add_child(cap)

	var collider := StaticBody3D.new()
	collider.add_child(_box_collision(Vector3(1.1, 4.6, 1.1), Vector3(0.0, 2.5, 0.0)))
	monument.add_child(collider)

	monument.position = _on_ground(Vector3.ZERO)
	return monument


func _build_house(index: int, position: Vector3) -> Node3D:
	var house := Node3D.new()
	house.name = "House_%02d" % (index + 1)

	var width := rng.randf_range(3.4, 5.0)
	var depth := rng.randf_range(3.4, 5.0)
	var wall_height := rng.randf_range(2.4, 3.2)
	var roof_height := rng.randf_range(1.4, 2.0)

	var walls := MeshInstance3D.new()
	walls.mesh = _box(Vector3(width, wall_height, depth))
	walls.material_override = _material(COLOR_WALLS[index % COLOR_WALLS.size()])
	walls.position = Vector3(0.0, wall_height * 0.5, 0.0)
	house.add_child(walls)

	var roof := MeshInstance3D.new()
	roof.mesh = _prism(Vector3(width * 1.16, roof_height, depth * 1.16))
	roof.material_override = _material(COLOR_ROOF)
	roof.position = Vector3(0.0, wall_height + roof_height * 0.5, 0.0)
	house.add_child(roof)

	var door := MeshInstance3D.new()
	door.mesh = _box(Vector3(0.9, 1.8, 0.12))
	door.material_override = _material(COLOR_WOOD)
	door.position = Vector3(0.0, 0.9, depth * 0.5 + 0.02)
	house.add_child(door)

	var collider := StaticBody3D.new()
	var body_size := Vector3(width, wall_height + roof_height, depth)
	collider.add_child(_box_collision(body_size, Vector3(0.0, body_size.y * 0.5, 0.0)))
	house.add_child(collider)

	house.position = _on_ground(position)
	# Yaw that makes the door (-Z is the node's front) face the plaza centre.
	house.rotation.y = atan2(position.x, position.z)
	return house


func _build_tree(index: int, position: Vector3) -> Node3D:
	var tree := Node3D.new()
	tree.name = "Tree_%02d" % (index + 1)

	var trunk_height := rng.randf_range(1.2, 1.9)
	var crown_radius := rng.randf_range(0.9, 1.5)
	var crown_height := rng.randf_range(2.2, 3.4)

	var trunk := MeshInstance3D.new()
	trunk.mesh = _cylinder(crown_radius * 0.16, crown_radius * 0.22, trunk_height, 6)
	trunk.material_override = _material(COLOR_WOOD)
	trunk.position = Vector3(0.0, trunk_height * 0.5, 0.0)
	tree.add_child(trunk)

	var crown := MeshInstance3D.new()
	crown.mesh = _cylinder(0.0, crown_radius, crown_height, 8)
	crown.material_override = _material(COLOR_LEAVES.lightened(rng.randf_range(0.0, 0.12)))
	crown.position = Vector3(0.0, trunk_height + crown_height * 0.5, 0.0)
	tree.add_child(crown)

	var collider := StaticBody3D.new()
	collider.add_child(_cylinder_collision(crown_radius * 0.3, trunk_height, Vector3.ZERO))
	tree.add_child(collider)

	tree.position = _on_ground(position)
	return tree


# --- helpers -----------------------------------------------------------------


func _on_ground(position: Vector3) -> Vector3:
	return Vector3(position.x, terrain.height_at(position.x, position.z), position.z)


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _prism(size: Vector3) -> PrismMesh:
	var mesh := PrismMesh.new()
	mesh.size = size
	return mesh


func _cylinder(
	top_radius: float, bottom_radius: float, height: float, segments: int
) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = maxi(segments, 3)
	mesh.rings = 1
	return mesh


func _box_collision(size: Vector3, offset: Vector3) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	var node := CollisionShape3D.new()
	node.shape = shape
	node.position = offset
	return node


func _cylinder_collision(radius: float, height: float, offset: Vector3) -> CollisionShape3D:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var node := CollisionShape3D.new()
	node.shape = shape
	node.position = offset + Vector3(0.0, height * 0.5, 0.0)
	return node


## One shared material per colour: keeps draw call state changes low, which is
## what keeps this scene comfortable on a GTX 1060 class GPU.
func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.0
	material.roughness = 0.9
	_materials[key] = material
	return material
