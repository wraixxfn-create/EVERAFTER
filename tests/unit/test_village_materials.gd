class_name TestVillageMaterials
extends RefCounted
## Checks for `VillageMaterials`: the sharing that keeps draw calls down, the
## vertex colour contract `MeshBaker` depends on, and the night glow.


static func run_tests(harness: TestHarness) -> void:
	harness.suite("VillageMaterials")

	var materials := VillageMaterials.new()
	harness.check_equals(materials.get_material_count(), 0, "nothing is built up front")

	var stone := materials.get_material("stone")
	harness.check(stone != null, "a palette key returns a material")
	harness.check_equals(materials.get_material_count(), 1, "one material was created")
	harness.check(
		materials.get_material("stone") == stone,
		"the same key always returns the same shared material"
	)
	harness.check_equals(materials.get_material_count(), 1, "and no second one is created")
	harness.check(
		materials.get_material("timber") != stone, "different keys give different materials"
	)
	harness.check_equals(materials.get_material_count(), 2, "two keys, two materials")

	harness.check(
		stone.vertex_color_use_as_albedo,
		"materials must read vertex colours, or merged meshes would lose their tint"
	)
	harness.check_equals(stone.metallic, 0.0, "stone is not metal")
	harness.check(
		materials.get_material("iron").metallic > 0.5, "iron is metallic"
	)
	harness.check(
		materials.get_material("water").transparency
			== BaseMaterial3D.TRANSPARENCY_ALPHA,
		"water is translucent"
	)

	# --- unknown keys fail loudly, never silently ------------------------------
	harness.check(
		not materials.has_color("no_such_key"), "has_color reports unknown keys"
	)
	harness.check_equals(
		materials.get_color("no_such_key"),
		Color.MAGENTA,
		"an unknown key is magenta so the mistake is visible in game"
	)

	# --- palette sanity --------------------------------------------------------
	for key in materials.PALETTE.keys():
		var color: Color = materials.PALETTE[key]
		harness.check(
			color.a > 0.99 or key == "water",
			"palette entry '%s' is opaque (transparency is a material property)" % key
		)
	harness.check(materials.PALETTE.size() >= 20, "the palette covers the village")

	# --- night glow --------------------------------------------------------------
	var window := materials.get_material("window")
	var lantern := materials.get_material("lantern")
	var stone_material := materials.get_material("stone")
	materials.apply_night_glow(0.0)
	harness.check_almost(window.emission_energy_multiplier, 0.0, 0.0001, "windows are dark by day")
	materials.apply_night_glow(1.0)
	harness.check(
		window.emission_energy_multiplier > 1.0, "windows glow at night"
	)
	harness.check(
		lantern.emission_energy_multiplier > 1.0, "lanterns glow at night"
	)
	harness.check_equals(
		stone_material.emission_enabled, false, "walls do not glow"
	)
	materials.apply_night_glow(-3.0)
	harness.check_almost(
		window.emission_energy_multiplier, 0.0, 0.0001, "the glow factor is clamped low"
	)
	materials.apply_night_glow(9.0)
	harness.check_almost(
		window.emission_energy_multiplier,
		VillageMaterials.GLOW_MAX_ENERGY,
		0.0001,
		"the glow factor is clamped high"
	)
