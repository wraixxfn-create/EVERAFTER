class_name TestNpcVisuals
extends RefCounted
## Unit checks for `NpcVisualFactory` and `UiTheme`: character proportions,
## profession outfit differentiation, articulated rig structure, procedural
## activity pose targets and shared medieval UI theme helpers.


static func run_tests(harness: TestHarness) -> void:
	harness.suite("NpcVisualsAndTheme")
	_test_stature_and_proportions(harness)
	_test_profession_profiles(harness)
	_test_articulated_rig_construction(harness)
	_test_procedural_pose_targets(harness)
	_test_ui_theme_helpers(harness)


static func _test_stature_and_proportions(harness: TestHarness) -> void:
	var roster := NpcRoster.build(NpcRoster.MAX_POPULATION)
	for record in roster:
		var scale := NpcVisualFactory.stature_scale_for(record.id, record.age)
		var total_height := NpcVisualFactory.BASE_HEIGHT * scale.y
		harness.check(
			total_height >= 1.60 and total_height <= 1.82,
			"%s height (%.2f m) fits under 1.85 m house doorways"
			% [record.id, total_height]
		)
		harness.check(
			scale.x >= 0.94 and scale.x <= 1.06,
			"%s shoulder width scale stays natural" % record.id
		)
	var scale_a := NpcVisualFactory.stature_scale_for("npc_001", 38)
	var scale_b := NpcVisualFactory.stature_scale_for("npc_001", 38)
	harness.check_equals(scale_a, scale_b, "stature scale is deterministic")


static func _test_profession_profiles(harness: TestHarness) -> void:
	var roster := NpcRoster.build(10)
	var garments := {}
	var headgears := {}
	var accessories := {}
	for record in roster:
		var profile := NpcVisualFactory.profile_for_profession(record.profession_id)
		var g := String(profile.get("garment", ""))
		var h := String(profile.get("headgear", ""))
		var a := String(profile.get("accessory", ""))
		harness.check(not g.is_empty(), "%s has a garment archetype" % record.profession_id)
		harness.check(not h.is_empty(), "%s has headgear" % record.profession_id)
		harness.check(not a.is_empty(), "%s has a profession accessory" % record.profession_id)
		garments[g] = true
		headgears[h] = true
		accessories[a] = true
	harness.check(
		garments.size() >= 6,
		"default 10 villagers span at least 6 garment silhouettes (got %d)" % garments.size()
	)
	harness.check(
		headgears.size() >= 7,
		"default 10 villagers span at least 7 headgear silhouettes (got %d)" % headgears.size()
	)
	harness.check(
		accessories.size() >= 7,
		"default 10 villagers span at least 7 accessory silhouettes (got %d)" % accessories.size()
	)
	var fallback := NpcVisualFactory.profile_for_profession("unknown_job")
	harness.check(
		not String(fallback.get("garment", "")).is_empty(),
		"unknown profession falls back to a valid villager outfit"
	)


static func _test_articulated_rig_construction(harness: TestHarness) -> void:
	var factory := NpcVisualFactory.new()
	harness.check(factory.get_mesh_count() >= 25, "shared primitive meshes are pre-built")
	harness.check(factory.get_material_count() >= 15, "shared materials are pre-built")
	var roster := NpcRoster.build(4)
	for index in roster.size():
		var record := roster[index]
		var selected := index == 0
		var body := StaticBody3D.new()
		factory.populate_character_view(body, record, selected)
		var rig := body.get_node_or_null("BodyRig") as Node3D
		harness.check(rig != null, "%s view has a BodyRig" % record.id)
		if rig != null:
			for part in [
				"LeftLeg",
				"RightLeg",
				"TorsoPivot",
				"TorsoPivot/Torso",
				"TorsoPivot/TunicSkirt",
				"TorsoPivot/Belt",
				"TorsoPivot/OutfitDetail",
				"TorsoPivot/LeftArm",
				"TorsoPivot/RightArm",
				"TorsoPivot/HeadPivot",
				"TorsoPivot/HeadPivot/Head",
				"TorsoPivot/HeadPivot/Hair",
				"TorsoPivot/HeadPivot/Headgear",
			]:
				harness.check(
					rig.get_node_or_null(part) != null,
					"%s BodyRig contains %s" % [record.id, part]
				)
		var ring := body.get_node_or_null("SelectedRing") as Node3D
		var role_label := body.get_node_or_null("RoleLabel") as Label3D
		harness.check(ring != null and ring.visible == selected, "SelectedRing visibility matches")
		harness.check(
			role_label != null and role_label.visible == selected,
			"RoleLabel visibility matches selection"
		)
		body.free()


static func _test_procedural_pose_targets(harness: TestHarness) -> void:
	var walk_pose := NpcVisualFactory.compute_pose_targets(
		NpcRecord.Activity.WALKING, 1.2, 0.9
	)
	var work_pose := NpcVisualFactory.compute_pose_targets(
		NpcRecord.Activity.WORKING, 1.2, 0.0
	)
	var eat_pose := NpcVisualFactory.compute_pose_targets(
		NpcRecord.Activity.EATING, 1.2, 0.0
	)
	var sleep_pose := NpcVisualFactory.compute_pose_targets(
		NpcRecord.Activity.SLEEPING, 1.2, 0.0
	)
	harness.check(
		absf(float(walk_pose["left_leg_pitch"])) > 0.1,
		"walking pose swings the legs"
	)
	harness.check_almost(
		float(walk_pose["left_leg_pitch"]),
		-float(walk_pose["right_leg_pitch"]),
		0.0001,
		"walking legs swing in opposite phase"
	)
	harness.check(
		float(work_pose["right_arm_pitch"]) < -0.25,
		"working pose raises the arms forward"
	)
	harness.check(
		float(eat_pose["right_arm_pitch"]) < -0.45,
		"eating pose lifts the right hand toward the mouth"
	)
	harness.check(
		float(sleep_pose["head_pitch"]) < -0.20,
		"sleeping posture bows the head in rest"
	)


static func _test_ui_theme_helpers(harness: TestHarness) -> void:
	var theme := UiTheme.shared_theme()
	harness.check(theme != null, "shared medieval UI theme is constructed")
	harness.check(UiTheme.header_font() != null, "serif header font variation exists")
	harness.check(UiTheme.body_font() != null, "humanist body font exists")
	harness.check_not_equals(
		UiTheme.color_for_energy(90.0),
		UiTheme.color_for_energy(10.0),
		"energy bar colour distinguishes rested vs exhausted"
	)
	harness.check_not_equals(
		UiTheme.color_for_hunger(15.0),
		UiTheme.color_for_hunger(90.0),
		"hunger bar colour distinguishes sated vs starving"
	)
	harness.check_not_equals(
		UiTheme.color_for_activity(NpcRecord.Activity.WORKING),
		UiTheme.color_for_activity(NpcRecord.Activity.BLOCKED),
		"activity colours distinguish working vs blocked"
	)
