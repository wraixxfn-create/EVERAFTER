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
const GRASS_COUNT := 4200
## Kinds whose footprint grass must stay out of: a blade on a stoop or inside a
## crate is the cheapest way to make a village look unfinished. Trees, shrubs
## and stones are excluded on purpose — grass grows around those.
const GRASS_EXCLUSION_KINDS := [
	VillageLayout.KIND_HOUSE, VillageLayout.KIND_INN, VillageLayout.KIND_HALL,
	VillageLayout.KIND_WELL, VillageLayout.KIND_STALL, VillageLayout.KIND_CART,
	VillageLayout.KIND_CRATE, VillageLayout.KIND_BARREL, VillageLayout.KIND_LOGPILE,
	VillageLayout.KIND_FENCE, VillageLayout.KIND_FLOWER_BOX, VillageLayout.KIND_BENCH
]
## Blades per meadow clump and clump footprint, for the two-scale grass scatter.
const GRASS_CLUMPS := 240
const GRASS_CLUMP_RADIUS := 3.6
const GRASS_CLUMP_CHANCE := 0.45


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


## Ground cover as a single `MultiMeshInstance3D`. Two scales of scatter: a
## uniform wash plus loose clumps, so the meadow reads as tufts and clearings
## instead of a noise field of evenly spaced blades.
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

	var half := terrain.get_half_extent()
	var clumps: Array[Vector2] = []
	for index in GRASS_CLUMPS:
		clumps.append(Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half)))
	var transforms: Array[Transform3D] = []
	var colors := PackedColorArray()
	var attempts := 0
	var limit := maxi(count, 1) * 6
	while transforms.size() < count and attempts < limit:
		attempts += 1
		var x := 0.0
		var z := 0.0
		if rng.randf() < GRASS_CLUMP_CHANCE:
			var clump := clumps[rng.randi_range(0, clumps.size() - 1)]
			var angle := rng.randf() * TAU
			var radius := rng.randf() * GRASS_CLUMP_RADIUS
			x = clump.x + cos(angle) * radius
			z = clump.y + sin(angle) * radius
		else:
			x = rng.randf_range(-half, half)
			z = rng.randf_range(-half, half)
		if absf(x) > half or absf(z) > half:
			continue
		if layout.plaza_weight(x, z) > 0.05 or layout.road_weight(x, z) > 0.15:
			continue
		if layout.pond_weight(x, z) > 0.25:
			continue
		if _inside_prop_footprint(layout, x, z):
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
	# Structural correction 11: trunk lean, height variation and irregular tiers
	# so pines no longer read as identical traffic cones.
	var trunk_height := (2.0 + rng.randf_range(0.0, 0.6)) * scale
	var trunk_lean := Vector3(rng.randf_range(-0.08, 0.08), 0.0, rng.randf_range(-0.08, 0.08)) * scale
	var tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.1))
	var bark_tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.09))
	baker.add_cylinder(
		"trunk", 0.13 * scale, 0.26 * scale, trunk_height, 6,
		_transform(Vector3(trunk_lean.x, trunk_height * 0.5, trunk_lean.z), 0.0, 0.0, rng.randf_range(-1.5, 1.5)),
		bark_tint, 0.055
	)
	var tiers := 3 + placement.variant % 2 + (1 if rng.randf() < 0.35 else 0)
	for tier in tiers:
		var t := float(tier) / float(tiers)
		var radius := lerpf(1.55, 0.42, t) * scale * rng.randf_range(0.78, 1.22)
		var height := lerpf(2.1, 1.15, t) * scale * rng.randf_range(0.88, 1.12)
		var y := lerpf(trunk_height * 0.68, trunk_height + 2.7 * scale, t) + rng.randf_range(-0.08, 0.08) * scale
		var lean := Vector3(rng.randf_range(-0.22, 0.22), 0.0, rng.randf_range(-0.22, 0.22)) * scale
		# Slight trunk taper per tier: larger base tiers branch wider
		var twist := rng.randf_range(0.0, 360.0)
		baker.add_cylinder(
			"pine", 0.0, radius, height, 7 if tier % 2 == 0 else 6,
			_transform(Vector3(lean.x + trunk_lean.x * (1.0 - t), y, lean.z + trunk_lean.z * (1.0 - t)), twist),
			tint.lightened(t * 0.12 + rng.randf_range(-0.03, 0.03)), 0.035
		)


func _build_oak(baker: MeshBaker, placement: VillageLayout.Placement) -> void:
	var scale := placement.scale
	var trunk_height := (1.9 + float(placement.variant) * 0.45 + rng.randf_range(-0.15, 0.22)) * scale
	var trunk_tilt := Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.10, 0.10)) * scale
	var bark_tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.1))
	baker.add_cylinder(
		"trunk", 0.19 * scale, 0.34 * scale, trunk_height, 6,
		_transform(Vector3(trunk_tilt.x, trunk_height * 0.5, trunk_tilt.z), rng.randf_range(-2.0, 2.0)),
		bark_tint, 0.06
	)
	var leaf_key: String = LEAF_KEYS[placement.variant % LEAF_KEYS.size()]
	var tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.12))
	var crown_y := trunk_height + 0.85 * scale + rng.randf_range(-0.12, 0.18) * scale
	# Structural correction 11: crown asymmetry — squash, tilt, lobe count
	# varied so oak line no longer a field of identical lollipops.
	var crown_radius := 1.85 * scale * rng.randf_range(0.82, 1.22)
	var crown_squash := Vector3(rng.randf_range(1.05, 1.18), rng.randf_range(0.78, 0.92), rng.randf_range(0.95, 1.12))
	var crown_basis := Basis.from_euler(Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * TAU, rng.randf_range(-0.12, 0.12))).scaled(crown_squash)
	baker.add_sphere(
		leaf_key, crown_radius, 4, 7,
		_origin * Transform3D(crown_basis, Vector3(trunk_tilt.x, crown_y, trunk_tilt.z)), tint
	)
	var lobe_count := 2 + (1 if rng.randf() < 0.42 else 0)
	for _lobe in lobe_count:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(0.85, 1.35) * scale
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * dist
		var lobe_r := 1.08 * scale * rng.randf_range(0.78, 1.18)
		var lobe_y := crown_y + rng.randf_range(0.15, 0.68) * scale
		var lobe_squash := Vector3(rng.randf_range(0.92, 1.08), rng.randf_range(0.85, 1.0), rng.randf_range(0.92, 1.08))
		var lobe_basis := Basis.IDENTITY.scaled(lobe_squash)
		baker.add_sphere(
			leaf_key, lobe_r, 4, 6,
			_origin * Transform3D(lobe_basis, Vector3(offset.x + trunk_tilt.x, lobe_y, offset.z + trunk_tilt.z)), tint.lightened(rng.randf_range(-0.04, 0.06))
		)


func _build_birch(baker: MeshBaker, placement: VillageLayout.Placement) -> void:
	var scale := placement.scale
	var trunk_height := (2.9 + float(placement.variant) * 0.55 + rng.randf_range(-0.18, 0.24)) * scale
	var trunk_tilt := Vector3(rng.randf_range(-0.14, 0.14), 0.0, rng.randf_range(-0.08, 0.08)) * scale
	var bark_tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.06))
	baker.add_cylinder(
		"trunk_birch", 0.12 * scale, 0.20 * scale, trunk_height, 6,
		_transform(Vector3(trunk_tilt.x, trunk_height * 0.5, trunk_tilt.z), rng.randf_range(-3.0, 3.0)),
		bark_tint, 0.08
	)
	var tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.08))
	# Structural correction 11: birch canopy less columnar — 3 main clusters
	# plus 1 occasional side puff, varied height/radius, trunk lean.
	for index in 3:
		var angle := rng.randf() * TAU + trunk_tilt.x * 0.5
		var radius := (0.95 - float(index) * 0.16) * scale * rng.randf_range(0.88, 1.15)
		var y := trunk_height - 0.15 * scale + float(index) * 0.82 * scale + rng.randf_range(-0.08, 0.12) * scale
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.35, 0.72) * scale
		baker.add_sphere(
			"leaf_autumn" if placement.variant == 2 else "leaf_bright",
			radius, 4, 6,
			_transform(Vector3(offset.x + trunk_tilt.x * 0.5, y, offset.z + trunk_tilt.z * 0.5)),
			tint.lightened(rng.randf_range(-0.03, 0.04))
		)
	if rng.randf() < 0.38:
		var angle := rng.randf() * TAU
		var y := trunk_height + rng.randf_range(0.45, 0.95) * scale
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.42, 0.85) * scale
		baker.add_sphere(
			"leaf_bright", 0.55 * scale * rng.randf_range(0.8, 1.1), 4, 6,
			_transform(Vector3(offset.x + trunk_tilt.x * 0.3, y, offset.z + trunk_tilt.z * 0.3)),
			tint
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
	# Variant 2 is a flowering shrub: a handful of bright heads on the green,
	# in the same palette as awnings and shutters, so the meadow edge and the
	# pond shore get a seasonal accent without a single new material.
	if placement.variant == 2:
		var flower_keys := ["cloth_cream", "cloth_red", "cloth_cream"]
		for flower in 4:
			var angle := rng.randf() * TAU
			var spread := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.25, 0.6)
			var key: String = flower_keys[flower % flower_keys.size()]
			baker.add_sphere(
				key, 0.11 * scale, 3, 5,
				_transform(Vector3(spread.x, (0.55 + rng.randf() * 0.45) * scale, spread.z)),
				Color.WHITE.darkened(rng.randf_range(0.0, 0.08))
			)


func _build_rock(baker: MeshBaker, placement: VillageLayout.Placement) -> void:
	var scale := placement.scale
	var rock_key := "rock_wet" if placement.variant == 2 else "rock"
	var tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.18))
	if scale < 0.55:
		# Pebble cluster: three little stones in a loose triangle. A single
		# scaled-down boulder reads as a marble; a knot of them reads as a
		# shore or a path edge. Walkable, so no collider is added for these.
		for pebble in 3:
			var angle := rng.randf() * TAU
			var spread := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.18, 0.42)
			var squash := Vector3(
				rng.randf_range(0.85, 1.25), rng.randf_range(0.55, 0.8), rng.randf_range(0.85, 1.25)
			)
			var pebble_basis := Basis.from_euler(
				Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
			).scaled(squash)
			baker.add_sphere(
				rock_key, rng.randf_range(0.22, 0.34), 3, 5,
				_origin * Transform3D(
					pebble_basis,
					Vector3(spread.x, 0.12, spread.z)
				),
				tint.lightened(rng.randf_range(0.0, 0.06)), true
			)
		return
	var squash := Vector3(
		rng.randf_range(0.8, 1.3), rng.randf_range(0.6, 0.95), rng.randf_range(0.8, 1.3)
	)
	var main_basis := Basis.from_euler(
		Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))
	).scaled(squash)
	baker.add_sphere(
		rock_key, 0.9 * scale, 3, 5,
		_origin * Transform3D(main_basis, Vector3(0.0, 0.35 * scale, 0.0)),
		tint, true
	)
	# A small attached chip breaks the perfect-egg silhouette without turning
	# scattered stones into a separate pile of high-poly props.
	var chip_basis := Basis.from_euler(
		Vector3(rng.randf_range(-0.25, 0.25), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))
	).scaled(Vector3(0.62, 0.52, 0.7) * scale)
	baker.add_sphere(
		rock_key, 0.46, 3, 5,
		_origin * Transform3D(chip_basis, Vector3(0.38 * scale, 0.18 * scale, -0.16 * scale)),
		tint.lightened(0.035), true
	)


# --- helpers -----------------------------------------------------------------


## True where a blade would poke through a solid prop or stand on a doorstep.
func _inside_prop_footprint(layout: VillageLayout, x: float, z: float) -> bool:
	var point := Vector2(x, z)
	for placement in layout.placements:
		if not GRASS_EXCLUSION_KINDS.has(placement.kind):
			continue
		var radius: float = placement.footprint_radius * placement.scale + 0.7
		if point.distance_to(placement.position) < radius:
			return true
	return false


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


func _transform(
	position: Vector3, yaw_deg: float = 0.0, pitch_deg: float = 0.0, roll_deg: float = 0.0
) -> Transform3D:
	# Existing callers supply trunk lean / crown twist; accept those rotations
	# so the world can compile when reviewing the rebuilt architecture in situ.
	var basis := Basis.from_euler(
		Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), deg_to_rad(roll_deg))
	)
	return _origin * Transform3D(basis, position)


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
