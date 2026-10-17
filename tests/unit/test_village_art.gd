class_name TestVillageArt
extends RefCounted
## Checks that the village is actually *built* out of the palette.
##
## A prop that asks for a material key nobody defined renders magenta, which is
## the ugliest possible bug to ship and the easiest to miss in review: nothing
## crashes, the village simply has a fluorescent pink cart in it. This suite
## builds every kind the layout can emit and asserts that every material key it
## touches exists in `VillageMaterials.PALETTE`.

const ALL_KINDS := [
	VillageLayout.KIND_HOUSE,
	VillageLayout.KIND_INN,
	VillageLayout.KIND_HALL,
	VillageLayout.KIND_WELL,
	VillageLayout.KIND_STALL,
	VillageLayout.KIND_LAMP,
	VillageLayout.KIND_FENCE,
	VillageLayout.KIND_CART,
	VillageLayout.KIND_CRATE,
	VillageLayout.KIND_BARREL,
	VillageLayout.KIND_LOGPILE,
	VillageLayout.KIND_SIGNPOST,
	VillageLayout.KIND_TREE_PINE,
	VillageLayout.KIND_TREE_OAK,
	VillageLayout.KIND_TREE_BIRCH,
	VillageLayout.KIND_BUSH,
	VillageLayout.KIND_ROCK,
]


static func run_tests(harness: TestHarness) -> void:
	harness.suite("VillageArt")

	var materials := VillageMaterials.new()
	var buildings := BuildingFactory.new(materials, 1)
	var vegetation := VegetationBuilder.new(2)
	var unknown: PackedStringArray = []
	var kinds_built := 0

	for kind in ALL_KINDS:
		for variant in 3:
			var placement := VillageLayout.Placement.new()
			placement.id = "%s_%d" % [kind, variant]
			placement.kind = kind
			placement.variant = variant
			placement.scale = 0.9 + 0.1 * float(variant)
			var keys: PackedStringArray = []
			if BuildingFactory.is_structure(kind):
				keys = _structure_keys(buildings, placement, materials)
				kinds_built += 1
			else:
				keys = _baked_keys(buildings, vegetation, placement, materials)
				kinds_built += 1
			for key in keys:
				if not materials.has_color(key) and not _is_emissive(key):
					if not unknown.has(key):
						unknown.append(key)

	harness.check_equals(kinds_built, ALL_KINDS.size() * 3, "every kind was built")
	harness.check_equals(
		unknown.size(),
		0,
		"every material key exists in the palette (unknown: %s)" % ", ".join(unknown)
	)
	harness.check(
		materials.get_material_count() <= 24,
		"the whole village uses at most 24 materials, got %d" % materials.get_material_count()
	)
	harness.check(
		materials.get_material_count() >= 12,
		"the village is not painted with three colours, got %d materials"
		% materials.get_material_count()
	)

	# Structures must come with something that stops the player.
	var blocking := 0
	for kind in [
		VillageLayout.KIND_HOUSE, VillageLayout.KIND_INN, VillageLayout.KIND_HALL,
		VillageLayout.KIND_WELL,
	]:
		var placement := VillageLayout.Placement.new()
		placement.kind = kind
		placement.variant = 0
		placement.scale = 1.0
		var shapes := buildings.colliders_for(placement)
		if not shapes.is_empty():
			blocking += 1
		for shape in shapes:
			# Nodes created in a test must be freed, or the shape RIDs leak and
			# the engine says so loudly at exit.
			(shape as CollisionShape3D).free()
	harness.check_equals(blocking, 4, "every building kind has at least one collider")


static func _is_emissive(key: String) -> bool:
	return VillageMaterials.GLOW_KEYS.has(key)


static func _structure_keys(
	buildings: BuildingFactory, placement: VillageLayout.Placement,
	_materials: VillageMaterials
) -> PackedStringArray:
	var baker := MeshBaker.new()
	buildings.bake_structure(baker, placement)
	return baker.get_material_keys_used()


static func _baked_keys(
	buildings: BuildingFactory, vegetation: VegetationBuilder,
	placement: VillageLayout.Placement, materials: VillageMaterials
) -> PackedStringArray:
	var baker := MeshBaker.new()
	var plants := [
		VillageLayout.KIND_TREE_PINE, VillageLayout.KIND_TREE_OAK,
		VillageLayout.KIND_TREE_BIRCH, VillageLayout.KIND_BUSH, VillageLayout.KIND_ROCK,
	]
	if plants.has(placement.kind):
		vegetation.append(baker, placement, Transform3D.IDENTITY)
	else:
		buildings.append_prop(baker, placement, Transform3D.IDENTITY)
	var keys := baker.get_material_keys_used()
	for node in baker.commit(materials):
		(node as MeshInstance3D).free()
	return keys
