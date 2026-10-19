class_name TestVegetation
extends RefCounted
## Headless checks for visual polish 16 — the rebuilt vegetation.
##
## These are the properties that separate a tree from a traffic cone and that a
## screenshot alone cannot prove on a machine without a GPU:
##
## * **determinism** — the same seed rebuilds the same plant;
## * **distinct silhouettes** — the three variants of every species differ in
##   height or width, measured from the baked mesh bounds, not from comments;
## * **trunks taper** — base radius at least twice the top radius;
## * **detail levels** — the far forest is cheaper but never empty;
## * **budget** — the whole vegetation stays inside its triangle allowance;
## * **placement** — no tree in a door sightline, a real verge along roads, open
##   glades, flowers out of the water;
## * **collision** — trunk colliders cover the trunk, shrubs and flowers do not
##   block the player at all;
## * **grass** — a tuft is five opaque tapered blades, not a transparent quad.

const SEED := 20261019
const SIZE_CELLS := 160
const HALF_EXTENT := 79.5
## Guard rail for this pass. The measured world budget has about 30 k triangles
## of headroom; vegetation is the largest single contributor, so a regression of
## this test is the earliest warning that the scene no longer fits.
const MAX_VEGETATION_TRIANGLES := 90000


static func run_tests(harness: TestHarness) -> void:
	harness.suite("Vegetation")
	var materials := VillageMaterials.new()

	# --- determinism and distinguishable variants ----------------------------
	# Flowers vary by colour, not by shape; the species and the shrubs vary by
	# silhouette, and that is what this block measures.
	for kind in [
		VillageLayout.KIND_TREE_PINE, VillageLayout.KIND_TREE_OAK,
		VillageLayout.KIND_TREE_BIRCH, VillageLayout.KIND_BUSH,
	]:
		var signatures := {}
		for variant in 3:
			var first := _bake(materials, kind, variant, true)
			var second := _bake(materials, kind, variant, true)
			harness.check_equals(
				first["triangles"], second["triangles"],
				"%s variant %d rebuilds with the same triangle count" % [kind, variant]
			)
			var a: Vector3 = first["size"]
			var b: Vector3 = second["size"]
			harness.check_almost(a.x, b.x, 0.0001, "%s variant %d is deterministic in x" % [kind, variant])
			harness.check_almost(a.y, b.y, 0.0001, "%s variant %d is deterministic in y" % [kind, variant])
			harness.check_almost(a.z, b.z, 0.0001, "%s variant %d is deterministic in z" % [kind, variant])
			signatures[_signature(a)] = true
		harness.check(
			signatures.size() >= 2,
			"%s variants differ in silhouette (%d distinct shapes)" % [kind, signatures.size()]
		)

	# Stones are separate designed silhouettes too: they use a broad ledge, a
	# taller shoulder and a long low form, while every individual seed remains
	# deterministic and inexpensive to bake.
	var rock_signatures := {}
	for variant in 3:
		var first_rock := _bake(materials, VillageLayout.KIND_ROCK, variant, true)
		var second_rock := _bake(materials, VillageLayout.KIND_ROCK, variant, true)
		harness.check_equals(
			first_rock["triangles"], second_rock["triangles"],
			"rock variant %d rebuilds with the same triangle count" % variant
		)
		var first_size: Vector3 = first_rock["size"]
		var second_size: Vector3 = second_rock["size"]
		harness.check_almost(first_size.x, second_size.x, 0.0001, "rock x bounds are deterministic")
		harness.check_almost(first_size.y, second_size.y, 0.0001, "rock y bounds are deterministic")
		harness.check_almost(first_size.z, second_size.z, 0.0001, "rock z bounds are deterministic")
		rock_signatures[_signature(first_size)] = true
		harness.check(
			int(first_rock["triangles"]) >= 120 and int(first_rock["triangles"]) <= 240,
			"rock clusters stay low-poly (%d triangles)" % int(first_rock["triangles"])
		)
	harness.check(
		rock_signatures.size() >= 2,
		"placed rock variants differ in silhouette (%d distinct shapes)" % rock_signatures.size()
	)

	# --- trunk and crown structure -------------------------------------------
	# Visual polish 18 rebuilt the trees again: conifers are whorls of needles,
	# broadleaves are a skeleton with many small leaf masses hung on it. These
	# checks are the ones that tell that construction apart from "a ball on a
	# pole", and they read the measurements out of the baked geometry.
	for kind in VillageLayout.TREE_KINDS:
		var baked := _bake(materials, kind, 0, true)
		var stats: Dictionary = baked["stats"]
		var base: float = float(stats["trunk_base_radius"])
		var top: float = float(stats["trunk_top_radius"])
		harness.check(
			base > top * 2.0,
			"%s trunk tapers instead of being a pipe (%.2f -> %.2f)" % [kind, base, top]
		)
		# A crown is now a crowd of masses: six needle whorls for a spruce, a
		# dozen leaf bunches for an oak, a loose veil for a birch.
		harness.check(
			int(stats["crown_clumps"]) >= 6,
			"%s crown is built from many masses, not one ball (%d)"
			% [kind, int(stats["crown_clumps"])]
		)
		# A tree has to be a tree next to a 1.8 m player: a crown at knee height
		# or at ten metres both read as a mistake from the walking camera.
		var tree_top: Vector3 = stats["top"]
		harness.check(
			tree_top.y > 3.0 and tree_top.y < 6.5,
			"%s stands at a believable height (%.1f m at scale 1)" % [kind, tree_top.y]
		)

	# --- far detail is cheaper, never empty ----------------------------------
	for kind in [
		VillageLayout.KIND_TREE_PINE, VillageLayout.KIND_TREE_OAK,
		VillageLayout.KIND_TREE_BIRCH, VillageLayout.KIND_BUSH,
		VillageLayout.KIND_FLOWER_PATCH,
	]:
		var near := _bake(materials, kind, 0, true)
		var far := _bake(materials, kind, 0, false)
		harness.check(
			int(far["triangles"]) > 0,
			"%s keeps a silhouette at distance" % kind
		)
		harness.check(
			int(far["triangles"]) < int(near["triangles"]),
			"%s far detail is cheaper (%d < %d triangles)"
			% [kind, int(far["triangles"]), int(near["triangles"])]
		)

	# --- flowers reuse the palette, they do not add materials ----------------
	var accents := {}
	for variant in 3:
		var baked := _bake(materials, VillageLayout.KIND_FLOWER_PATCH, variant, true)
		for key in baked["keys"]:
			if key != "leaf_mid" and key != "leaf_bright":
				accents[key] = true
	harness.check(
		accents.size() >= 3,
		"flowers use three existing palette accents (%s)" % ", ".join(PackedStringArray(accents.keys()))
	)

	# --- the real village -----------------------------------------------------
	var layout := VillageLayout.new(SEED, HALF_EXTENT)
	var terrain := TerrainGenerator.new(SIZE_CELLS, 5.0, SEED, layout)

	_check_placement(harness, layout)
	_check_collision(harness)
	_check_rock_contact(harness, layout, terrain, materials)
	_check_grass(harness, layout, terrain, materials)
	_check_budget(harness, layout)


# --- placement ---------------------------------------------------------------


static func _check_placement(harness: TestHarness, layout: VillageLayout) -> void:
	var trees: Array[Vector2] = []
	var rocks := layout.get_placements_of_kind(VillageLayout.KIND_ROCK)
	var species := {}
	for placement in layout.placements:
		if not VillageLayout.TREE_KINDS.has(placement.kind):
			continue
		trees.append(placement.position)
		species[placement.kind] = int(species.get(placement.kind, 0)) + 1
	harness.check(trees.size() > 100, "there is still a forest (%d trees)" % trees.size())
	harness.check(
		rocks.size() > 20,
		"stones remain scattered around shore and fields (%d)" % rocks.size()
	)
	var road_stones := 0
	for rock in rocks:
		var clearance := (
			VillageLayout.ROAD_WIDTH * 0.5
			+ rock.footprint_radius * rock.scale * 0.6
		)
		if layout.distance_to_roads(rock.position) < clearance - 0.001:
			road_stones += 1
	harness.check_equals(road_stones, 0, "placed stones keep the carriageway clear")
	for kind in VillageLayout.TREE_KINDS:
		harness.check(
			int(species.get(kind, 0)) >= 5,
			"%s survives in the mix (%d trees)" % [kind, int(species.get(kind, 0))]
		)

	# A tree keeps a real verge from the carriageway: a trunk on the kerb closes
	# the road visually even where the player can walk past it.
	var tight := 0
	for placement in layout.placements:
		if not VillageLayout.TREE_KINDS.has(placement.kind):
			continue
		var clearance := (
			VillageLayout.ROAD_WIDTH * 0.5
			+ placement.footprint_radius * placement.scale * 0.6
			+ VillageLayout.TREE_ROAD_VERGE
		)
		if layout.distance_to_roads(placement.position) < clearance - 0.001:
			tight += 1
	harness.check_equals(tight, 0, "every tree keeps a verge from the road")

	# No tall vegetation inside the longer sightline in front of a door.
	var blocked := 0
	for host in layout.placements:
		if not VillageLayout.DOOR_BUILDING_KINDS.has(host.kind):
			continue
		var yaw := deg_to_rad(host.rotation_deg)
		var reach := (
			host.footprint_radius * host.scale + VillageLayout.DOOR_CORRIDOR_REACH
			+ VillageLayout.TREE_DOOR_SIGHTLINE
		)
		for other in layout.placements:
			if not VillageLayout.TREE_KINDS.has(other.kind):
				continue
			var delta := other.position - host.position
			var local_z := delta.x * sin(yaw) + delta.y * cos(yaw)
			if local_z <= 0.0 or local_z > reach:
				continue
			var local_x := delta.x * cos(yaw) - delta.y * sin(yaw)
			var half_width := (
				VillageLayout.DOOR_CORRIDOR_HALF_WIDTH
				+ other.footprint_radius * other.scale * 0.5
				+ VillageLayout.TREE_DOOR_EXTRA_WIDTH
			)
			if absf(local_x) < half_width:
				blocked += 1
	harness.check_equals(blocked, 0, "no tree stands in a door sightline")

	# The glades the layout advertises have to be real.
	harness.check_equals(layout.forest_clearings.size(), 3, "the wood has three glades")
	var cleared := 0
	for clearing in layout.forest_clearings:
		for placement in layout.placements:
			if not VillageLayout.TREE_KINDS.has(placement.kind):
				continue
			if placement.position.distance_to(clearing) < 9.0:
				cleared += 1
	harness.check_equals(cleared, 0, "the glades stay open")

	# Spacing is irregular, not a measured grid. Coefficient of variation of the
	# nearest-neighbour distance: 0 for a grid, well above 0.2 for a wood.
	var nearest: Array[float] = []
	for index in trees.size():
		var best := INF
		for other in trees.size():
			if other == index:
				continue
			best = minf(best, trees[index].distance_to(trees[other]))
		nearest.append(best)
	var mean := 0.0
	for distance in nearest:
		mean += distance
	mean /= float(nearest.size())
	var variance := 0.0
	for distance in nearest:
		variance += (distance - mean) * (distance - mean)
	variance /= float(nearest.size())
	var variation := sqrt(variance) / maxf(mean, 0.0001)
	harness.check(
		variation > 0.15,
		"tree spacing is irregular, not a repeated grid (CV %.2f)" % variation
	)

	# Flowers are real placements, outside the water.
	var flowers := layout.get_placements_of_kind(VillageLayout.KIND_FLOWER_PATCH)
	harness.check(
		flowers.size() >= 30, "flowers grow in the meadow (%d patches)" % flowers.size()
	)
	var wet := 0
	for flower in flowers:
		if layout.pond_weight(flower.position.x, flower.position.y) > 0.2:
			wet += 1
	harness.check_equals(wet, 0, "no flower patch stands in the water")


# --- collision ---------------------------------------------------------------


static func _check_collision(harness: TestHarness) -> void:
	var builder := VegetationBuilder.new(SEED)
	for kind in VillageLayout.TREE_KINDS:
		var baked := _bake(VillageMaterials.new(), kind, 0, true)
		var base: float = float((baked["stats"] as Dictionary)["trunk_base_radius"])
		var shapes := builder.colliders_for(_placement(kind, 0, 1.0))
		harness.check_equals(shapes.size(), 1, "%s has a trunk collider" % kind)
		if shapes.size() == 1:
			var shape := (shapes[0] as CollisionShape3D).shape as CylinderShape3D
			harness.check(
				shape.radius >= base,
				"%s collider covers its trunk (%.2f >= %.2f)" % [kind, shape.radius, base]
			)
			harness.check(
				shape.height >= 1.8,
				"%s collider is tall enough to stop the player" % kind
			)
		for shape in shapes:
			(shape as CollisionShape3D).free()

	# Low vegetation is walkable: a flower patch or a shrub that blocks the
	# player would turn the meadow into a maze.
	for kind in [VillageLayout.KIND_BUSH, VillageLayout.KIND_FLOWER_PATCH]:
		var shapes := builder.colliders_for(_placement(kind, 0, 1.2))
		harness.check_equals(shapes.size(), 0, "%s is walkable" % kind)
		for shape in shapes:
			(shape as CollisionShape3D).free()
	var pebble_shapes := builder.colliders_for(_placement(VillageLayout.KIND_ROCK, 0, 0.4))
	harness.check_equals(pebble_shapes.size(), 0, "pebbles are walkable")
	for shape in pebble_shapes:
		(shape as CollisionShape3D).free()
	var boulder_shapes := builder.colliders_for(_placement(VillageLayout.KIND_ROCK, 0, 1.2))
	harness.check_equals(
		boulder_shapes.size(), 1, "a large placed boulder keeps its existing collider"
	)
	if boulder_shapes.size() == 1:
		var collider := boulder_shapes[0] as CollisionShape3D
		var shape := collider.shape as BoxShape3D
		var expected_size := Vector3(1.5, 1.0, 1.4) * 1.2
		var expected_offset := Vector3(0.0, 0.4, 0.0) * 1.2
		harness.check_equals(
			shape.size, expected_size, "the existing boulder collision dimensions are unchanged"
		)
		harness.check_equals(
			collider.position, expected_offset, "the existing boulder collider offset is unchanged"
		)
	for collision in boulder_shapes:
		(collision as CollisionShape3D).free()


static func _check_rock_contact(
	harness: TestHarness, layout: VillageLayout, terrain: TerrainGenerator,
	materials: VillageMaterials
) -> void:
	var rocks := layout.get_placements_of_kind(VillageLayout.KIND_ROCK)
	harness.check(not rocks.is_empty(), "the world has grounded rock placements to inspect")
	if rocks.is_empty():
		return
	var builder := VillageBuilder.new(layout, terrain, materials)
	var checked := 0
	for rock in rocks:
		var transform := builder._placement_transform(rock)
		var expected_up := terrain._surface_normal_at(rock.position.x, rock.position.y)
		harness.check_almost(
			transform.origin.y, terrain.height_at(rock.position.x, rock.position.y), 0.0001,
			"rock anchor samples the terrain height"
		)
		harness.check(
			transform.basis.y.dot(expected_up) > 0.999,
			"rock base follows the exact heightmap triangle normal"
		)
		checked += 1
		if checked >= 4:
			break


# --- grass -------------------------------------------------------------------


static func _check_grass(
	harness: TestHarness, layout: VillageLayout, terrain: TerrainGenerator,
	materials: VillageMaterials
) -> void:
	var builder := VegetationBuilder.new(SEED + 7)
	var grass := builder.build_grass(layout, terrain, materials, 900)
	harness.check(grass != null and grass.multimesh != null, "ground cover exists")
	if grass == null or grass.multimesh == null:
		return
	var instances := grass.multimesh.instance_count
	harness.check(
		instances > 500 and instances <= 900,
		"tufts are scattered over the meadow (%d instances)" % instances
	)
	var tuft := grass.multimesh.mesh
	harness.check(tuft != null, "the tuft mesh is baked")
	var tuft_triangles := 0
	if tuft != null:
		for surface in tuft.get_surface_count():
			tuft_triangles += int(
				tuft.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size() / 3
			)
	harness.check(
		tuft_triangles >= 8 and tuft_triangles <= 16,
		"a tuft is five tapered blades (%d triangles)" % tuft_triangles
	)
	harness.check(
		grass.material_override != null
		and grass.material_override.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
		"grass is opaque geometry, without a cut-out fringe"
	)
	harness.check_equals(
		grass.cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"thousands of blades cast no shadow"
	)
	grass.free()


# --- budget ------------------------------------------------------------------


static func _check_budget(harness: TestHarness, layout: VillageLayout) -> void:
	var builder := VegetationBuilder.new(SEED + 7)
	var baker := MeshBaker.new()
	for placement in layout.placements:
		if not VillageLayout.is_vegetation(placement.kind):
			continue
		builder.append(
			baker, placement, Transform3D.IDENTITY,
			builder.needs_detail(layout, placement)
		)
	var total := baker.get_triangle_count()
	harness.check(total > 20000, "the rebuilt vegetation is real geometry (%d triangles)" % total)
	harness.check(
		total < MAX_VEGETATION_TRIANGLES,
		"vegetation stays inside its budget (%d < %d triangles)"
		% [total, MAX_VEGETATION_TRIANGLES]
	)


# --- helpers -----------------------------------------------------------------


static func _placement(
	kind: String, variant: int, scale: float = 1.0
) -> VillageLayout.Placement:
	var placement := VillageLayout.Placement.new()
	placement.id = "%s_test" % kind
	placement.kind = kind
	placement.variant = variant
	placement.scale = scale
	placement.footprint_radius = 1.6
	return placement


## Bakes one plant at the origin and reports what the geometry actually is.
static func _bake(
	materials: VillageMaterials, kind: String, variant: int, detail: bool
) -> Dictionary:
	var builder := VegetationBuilder.new(SEED)
	var baker := MeshBaker.new()
	builder.append(baker, _placement(kind, variant), Transform3D.IDENTITY, detail)
	var bounds := AABB()
	var has_bounds := false
	for node in baker.commit(materials):
		var instance := node as MeshInstance3D
		var box := instance.mesh.get_aabb()
		if not has_bounds:
			bounds = box
			has_bounds = true
		else:
			bounds = bounds.merge(box)
		instance.free()
	return {
		"triangles": baker.get_triangle_count(),
		"size": bounds.size,
		"keys": baker.get_material_keys_used(),
		"stats": builder.last_stats.duplicate(true),
	}


static func _signature(size: Vector3) -> String:
	return "%0.1f/%0.1f/%0.1f" % [
		snappedf(size.x, 0.1), snappedf(size.y, 0.1), snappedf(size.z, 0.1)
	]
