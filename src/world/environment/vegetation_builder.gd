class_name VegetationBuilder
extends RefCounted
## Trees, shrubs, boulders and ground cover.
##
## Two performance rules drive this file:
## * **everything static is merged.** `VillageBuilder` hands one [MeshBaker] to
##   the whole forest, so 250 trees become four or five meshes. A tree per node
##   would be a thousand draw calls for scenery nobody looks at closely.
## * **grass is a `MultiMesh`.** Thousands of blades, one draw call, one mesh of
##   two crossed quads, per instance colour for variety.
##
## Silhouettes are deliberately distinct: conifers are stacked cones, oaks are
## faceted blobs, birches are pale and light. That is what makes the tree line
## readable from the plaza without any texture work.

const LEAF_KEYS := ["leaf_deep", "leaf_mid", "leaf_bright"]
const TREE_COLLIDER_KINDS := [
	VillageLayout.KIND_TREE_PINE, VillageLayout.KIND_TREE_OAK, VillageLayout.KIND_TREE_BIRCH
]
const GRASS_COUNT := 3600


var rng := RandomNumberGenerator.new()

## See `BuildingFactory._origin`: merged vegetation has no node of its own, so
## every solid is emitted already placed in the world.
var _origin := Transform3D.IDENTITY


func _init(seed_value: int = 0) -> void:
	rng.seed = seed_value


func append(
	baker: MeshBaker, placement: VillageLayout.Placement, origin: Transform3D
) -> void:
	_origin = origin
	match placement.kind:
		VillageLayout.KIND_TREE_PINE:
			_build_pine(baker, placement)
		VillageLayout.KIND_TREE_OAK:
			_build_oak(baker, placement)
		VillageLayout.KIND_TREE_BIRCH:
			_build_birch(baker, placement)
		VillageLayout.KIND_BUSH:
			_build_bush(baker, placement)
		VillageLayout.KIND_ROCK:
			_build_rock(baker, placement)
	_origin = Transform3D.IDENTITY


## Trunk colliders. Only trees and boulders block the player; shrubs and grass
## are walkable, which keeps the village open instead of a pinball table.
func colliders_for(placement: VillageLayout.Placement) -> Array:
	var shapes: Array = []
	var scale := placement.scale
	if TREE_COLLIDER_KINDS.has(placement.kind):
		shapes.append(_cylinder_collider(0.34 * scale, 2.0 * scale, Vector3.ZERO))
	elif placement.kind == VillageLayout.KIND_ROCK and scale > 0.9:
		shapes.append(_box_collider(Vector3(1.5, 1.0, 1.4) * scale, Vector3(0.0, 0.4, 0.0) * scale))
	return shapes


## Ground cover as a single `MultiMeshInstance3D`.
func build_grass(
	layout: VillageLayout, terrain: TerrainGenerator, materials: VillageMaterials,
	count: int = GRASS_COUNT
) -> MultiMeshInstance3D:
	var blade := MeshBaker.new()
	for yaw in [0.0, 90.0]:
		blade.add_quad(
			"grass_blade",
			Vector2(0.38, 0.68),
			Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0)), Vector3(0, 0.34, 0)),
			Color(1, 1, 1),
			true
		)
	var baked: Array = blade.commit(materials)
	var mesh: Mesh = null
	for node in baked:
		mesh = (node as MeshInstance3D).mesh

	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.use_colors = true
	multi_mesh.mesh = mesh
	multi_mesh.instance_count = 0

	var transforms: Array[Transform3D] = []
	var colors := PackedColorArray()
	var attempts := 0
	var limit := maxi(count, 1) * 6
	while transforms.size() < count and attempts < limit:
		attempts += 1
		var x := rng.randf_range(-terrain.get_half_extent(), terrain.get_half_extent())
		var z := rng.randf_range(-terrain.get_half_extent(), terrain.get_half_extent())
		if layout.plaza_weight(x, z) > 0.05 or layout.road_weight(x, z) > 0.15:
			continue
		if layout.pond_weight(x, z) > 0.25:
			continue
		var scale := rng.randf_range(0.7, 1.6)
		var basis := Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3.ONE * scale)
		transforms.append(
			Transform3D(basis, Vector3(x, terrain.height_at(x, z) - 0.02, z))
		)
		colors.append(_grass_tint())

	multi_mesh.instance_count = transforms.size()
	for index in transforms.size():
		multi_mesh.set_instance_transform(index, transforms[index])
		multi_mesh.set_instance_color(index, colors[index])

	var instance := MultiMeshInstance3D.new()
	instance.name = "Grass"
	instance.multimesh = multi_mesh
	instance.material_override = materials.get_material("grass_blade")
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


# --- species -----------------------------------------------------------------


func _build_pine(baker: MeshBaker, placement: VillageLayout.Placement) -> void:
	var scale := placement.scale
	var trunk_height := 2.2 * scale
	var tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.1))
	baker.add_cylinder(
		"trunk", 0.14 * scale, 0.26 * scale, trunk_height, 6,
		_transform(Vector3(0.0, trunk_height * 0.5, 0.0))
	)
	var tiers := 3 + placement.variant % 2
	for tier in tiers:
		var t := float(tier) / float(tiers)
		var radius := lerpf(1.5, 0.45, t) * scale
		var height := lerpf(2.0, 1.3, t) * scale
		var y := lerpf(trunk_height * 0.75, trunk_height + 2.6 * scale, t)
		baker.add_cylinder(
			"pine", 0.0, radius, height, 7, _transform(Vector3(0.0, y, 0.0)),
			tint.lightened(t * 0.1)
		)


func _build_oak(baker: MeshBaker, placement: VillageLayout.Placement) -> void:
	var scale := placement.scale
	var trunk_height := (2.0 + float(placement.variant) * 0.4) * scale
	baker.add_cylinder(
		"trunk", 0.2 * scale, 0.34 * scale, trunk_height, 6,
		_transform(Vector3(0.0, trunk_height * 0.5, 0.0))
	)
	var leaf_key: String = LEAF_KEYS[placement.variant % LEAF_KEYS.size()]
	var tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.12))
	var crown_y := trunk_height + 0.9 * scale
	baker.add_sphere(
		leaf_key, 1.85 * scale, 4, 7, _transform(Vector3(0.0, crown_y, 0.0)), tint
	)
	for _lobe in 2:
		var angle := rng.randf() * TAU
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * 1.15 * scale
		baker.add_sphere(
			leaf_key, 1.18 * scale, 4, 6,
			_transform(Vector3(offset.x, crown_y + 0.5 * scale, offset.z)), tint
		)


func _build_birch(baker: MeshBaker, placement: VillageLayout.Placement) -> void:
	var scale := placement.scale
	var trunk_height := (3.0 + float(placement.variant) * 0.5) * scale
	baker.add_cylinder(
		"trunk_birch", 0.13 * scale, 0.2 * scale, trunk_height, 6,
		_transform(Vector3(0.0, trunk_height * 0.5, 0.0))
	)
	var tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.08))
	for index in 3:
		var angle := rng.randf() * TAU
		var radius := (0.9 - float(index) * 0.18) * scale
		var y := trunk_height - 0.2 * scale + float(index) * 0.85 * scale
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * 0.5 * scale
		baker.add_sphere(
			"leaf_autumn" if placement.variant == 2 else "leaf_bright",
			radius, 4, 6, _transform(Vector3(offset.x, y, offset.z)), tint
		)


func _build_bush(baker: MeshBaker, placement: VillageLayout.Placement) -> void:
	var scale := placement.scale * 0.8
	var tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.15))
	for index in 2:
		var angle := rng.randf() * TAU
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * 0.35 * scale
		baker.add_sphere(
			"leaf_deep" if index == 0 else "leaf_mid",
			(0.7 - float(index) * 0.2) * scale, 4, 6,
			_transform(Vector3(offset.x, 0.45 * scale, offset.z)), tint
		)


func _build_rock(baker: MeshBaker, placement: VillageLayout.Placement) -> void:
	var scale := placement.scale
	var tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.2))
	var squash := Vector3(
		rng.randf_range(0.8, 1.3), rng.randf_range(0.6, 0.95), rng.randf_range(0.8, 1.3)
	)
	baker.add_sphere(
		"rock_wet" if placement.variant == 2 else "rock",
		0.9 * scale, 3, 5,
		_origin * Transform3D(
			Basis.from_euler(
				Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))
			).scaled(squash),
			Vector3(0.0, 0.35 * scale, 0.0)
		),
		tint
	)


# --- helpers -----------------------------------------------------------------


func _grass_tint() -> Color:
	var roll := rng.randf()
	# Instance colours multiply the shared blade albedo, so these stay light and
	# push the hue: deep meadow greens, sun-dried gold and a few pale tips.
	var base := Color(0.68, 0.82, 0.48)
	if roll < 0.3:
		base = Color(0.52, 0.72, 0.36)
	elif roll < 0.55:
		base = Color(0.80, 0.88, 0.55)
	elif roll < 0.68:
		base = Color(0.78, 0.74, 0.42)
	elif roll < 0.82:
		base = Color(0.60, 0.80, 0.44)
	return base.darkened(rng.randf_range(0.0, 0.2))


func _transform(position: Vector3) -> Transform3D:
	return _origin * Transform3D(Basis.IDENTITY, position)


func _cylinder_collider(radius: float, height: float, offset: Vector3) -> Node3D:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	return _collider_node(shape, offset + Vector3(0.0, height * 0.5, 0.0))


func _box_collider(size: Vector3, offset: Vector3) -> Node3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return _collider_node(shape, offset)


func _collider_node(shape: Shape3D, offset: Vector3) -> Node3D:
	var node := CollisionShape3D.new()
	node.shape = shape
	node.position = offset
	return node
