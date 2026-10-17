class_name TestWorldScene
extends RefCounted
## Integration checks for the explorable village.
##
## These are the checks that cannot be done with pure logic: they need a real
## scene tree, a real physics server and a real heightmap shape. They exist
## because the previous phase shipped a terrain whose triangles faced the wrong
## way — a bug that no amount of reading catches and one frame of running does.
##
## Run with:
##
##     godot --headless --path . --script res://tests/run_world_tests.gd
##
## What is verified here:
## * the physics surface and `TerrainGenerator.height_at()` agree everywhere, so
##   what the player sees is what the player walks on;
## * the player rests on the ground, does not sink and does not fall through;
## * building walls actually stop the player capsule (`body_test_motion` against
##   the live capsule shape, not a stand-in);
## * the village stays inside its performance budget.

## Tolerance between the generated height field and the physics hit. Half a
## grid cell of disagreement would mean the mesh and the heightmap use
## different triangles.
const HEIGHT_TOLERANCE := 0.05
## The capsule is 1.8 tall, so its centre rests this far above the surface.
const CAPSULE_HALF_HEIGHT := 0.9
const SETTLE_FRAMES := 40

## Performance budget, checked so that a future change cannot quietly double the
## cost of the scene. Measured, not guessed: see the boot log line.
const MAX_VILLAGE_MESHES := 260
const MAX_TOTAL_TRIANGLES := 260000
const MAX_COLLIDERS := 900


## Node tree and budget: the scene assembled itself and stayed affordable.
static func check_structure(harness: TestHarness, world: Node3D) -> void:
	harness.suite("WorldScene")
	harness.check(world != null, "main_world.tscn instantiated")
	if world == null:
		return
	for node_name in [
		"Sky", "Terrain", "Village", "Player", "WorldHud", "EconomyPanel",
		"NpcPanel", "DiagnosticsHud"
	]:
		harness.check(world.get_node_or_null(node_name) != null, "world has a %s node" % node_name)
	var village := world.get_node_or_null("Village") as Node3D
	if village == null:
		return
	var built := village.get_node_or_null("Village") as Node3D
	harness.check(built != null, "the village content was built")
	if built == null:
		return
	var parts := ["Structures", "Props", "Vegetation", "Grass", "Water"]
	for part in parts:
		harness.check(built.get_node_or_null(part) != null, "village has a %s node" % part)
	for body_path in ["Props/PropCollision", "Vegetation/TreeCollision"]:
		harness.check(
			built.get_node_or_null(body_path) != null, "village has a %s body" % body_path
		)
	var structures := built.get_node_or_null("Structures") as Node3D
	harness.check(
		structures != null and structures.get_child_count() >= 12,
		"at least 12 structures were placed (got %d)"
		% (structures.get_child_count() if structures != null else 0)
	)
	var grass := built.get_node_or_null("Grass") as MultiMeshInstance3D
	harness.check(grass != null, "ground cover exists")
	if grass != null and grass.multimesh != null:
		harness.check(
			grass.multimesh.instance_count > 500,
			"ground cover is dense enough to read as a meadow (%d blades)"
			% grass.multimesh.instance_count
		)


## The physics heightmap and the generator must describe the same surface.
static func check_terrain_collision(
	harness: TestHarness, world: Node3D, space: PhysicsDirectSpaceState3D
) -> void:
	harness.suite("TerrainCollision")
	if space == null:
		harness.skip("no physics space available in this run")
		return
	var terrain: TerrainGenerator = world.get_terrain()
	harness.check(terrain != null, "the world exposes its terrain generator")
	if terrain == null:
		return
	var query := PhysicsRayQueryParameters3D.new()
	query.collide_with_areas = false
	query.collide_with_bodies = true
	# Only the ground may answer: without excluding roofs, walls and trunks a ray
	# over the plaza hits the well and the test measures the well, not the map.
	query.exclude = _non_terrain_bodies(world)
	var worst := 0.0
	var samples := 0
	var step := 11.0
	var position := -terrain.get_half_extent() + 4.0
	while position < terrain.get_half_extent() - 4.0:
		var other := -terrain.get_half_extent() + 4.0
		while other < terrain.get_half_extent() - 4.0:
			var expected := terrain.height_at(position, other)
			query.from = Vector3(position, expected + 25.0, other)
			query.to = Vector3(position, expected - 25.0, other)
			var hit := space.intersect_ray(query)
			samples += 1
			if hit.is_empty():
				harness.check(
					false, "a downward ray hit nothing at (%.1f, %.1f)" % [position, other]
				)
			else:
				worst = maxf(worst, absf((hit["position"] as Vector3).y - expected))
			other += step
		position += step
	harness.check(samples > 100, "sampled enough of the map (%d rays)" % samples)
	harness.check_almost(
		worst, 0.0, HEIGHT_TOLERANCE,
		"worst physics-vs-mesh height difference over %d samples" % samples
	)


## The player rests on the ground and stays there.
static func check_player_settles(harness: TestHarness, world: Node3D) -> void:
	harness.suite("PlayerOnGround")
	var player: CharacterBody3D = world.get_player()
	var terrain: TerrainGenerator = world.get_terrain()
	if player == null or terrain == null:
		harness.check(false, "world exposes a player and a terrain")
		return
	harness.check(player is CharacterBody3D, "the player is a CharacterBody3D")
	harness.check(player.is_on_floor(), "the player is standing on the floor after settling")
	var ground := terrain.height_at(player.global_position.x, player.global_position.z)
	harness.check_almost(
		player.global_position.y - ground,
		CAPSULE_HALF_HEIGHT,
		0.2,
		"the capsule centre sits one half-height above the terrain"
	)
	harness.check(
		player.global_position.y - ground > 0.0,
		"the player is above the terrain, not inside it"
	)
	harness.check(
		player.global_position.is_finite(), "the player position is a finite number"
	)
	# The player spawns on a road, looking at the plaza: the first frame has to
	# be a view of the village, not of an empty field.
	harness.check(
		world.get_layout().road_distance(player.global_position.x, player.global_position.z) < 4.0,
		"the player spawns on a road"
	)
	var forward := -player.global_transform.basis.z
	var to_plaza := (Vector3.ZERO - player.global_position).normalized()
	harness.check(
		forward.dot(to_plaza) > 0.8, "the player spawns facing the plaza centre"
	)


## The player capsule cannot be pushed through a wall or through the floor.
static func check_player_collides(harness: TestHarness, world: Node3D) -> void:
	harness.suite("PlayerCollisions")
	var player: CharacterBody3D = world.get_player()
	var terrain: TerrainGenerator = world.get_terrain()
	var layout: VillageLayout = world.get_layout()
	if player == null or terrain == null or layout == null:
		harness.check(false, "world exposes player, terrain and layout")
		return

	# 1. Downward: a capsule resting on the ground cannot sink into it. Measured
	# as travel, because that is the quantity `body_test_motion` always fills in.
	var downward := _motion_result(player, player.global_position, Vector3(0.0, -3.0, 0.0))
	harness.check(downward != null, "body_test_motion returned a result")
	if downward != null:
		harness.check(
			downward.get_travel().length() < 0.5,
			"the ground stops a 3 m push downwards after %.3f m"
			% downward.get_travel().length()
		)

	# 2. Into a house: pick the nearest structure and push straight at it.
	var target := _nearest_structure_position(layout, player.global_position)
	harness.check(target != null, "the layout contains at least one structure")
	if target == null:
		return
	var ground := terrain.height_at(target.x, target.z)
	# Stand 6 units away from the wall and try to walk 12 units: if the collider
	# is real, the travel stops at the wall, long before the 12 units are used.
	var from := Vector3(target.x, ground + 1.2, target.z) + Vector3(6.0, 0.0, 6.0)
	var into := (Vector3(target.x, ground + 1.2, target.z) - from).normalized()
	var result := _motion_result(player, from, into * 12.0)
	harness.check(result != null, "body_test_motion returned a result")
	if result == null:
		return
	harness.check(
		result.get_travel().length() < 7.0,
		"the wall stopped the capsule early (travelled %.2f of 12.00)"
		% result.get_travel().length()
	)

	# 3. Along the ground: a flat stride must not be blocked by nothing.
	# 3. Not stuck: the capsule must be free to move sideways. The test starts a
	# little above the resting pose on purpose — a capsule exactly tangent to the
	# ground touches it after a centimetre of horizontal travel, and
	# `body_test_motion` reports that instead of sliding the way
	# `move_and_slide` does.
	var lifted := player.global_position + Vector3(0.0, 0.25, 0.0)
	var flat := _motion_result(player, lifted, Vector3(1.0, 0.0, 0.0) * 0.5)
	harness.check(flat != null, "body_test_motion works on open ground")
	if flat != null:
		harness.check(
			flat.get_travel().length() > 0.35,
			"open ground lets the capsule move (travelled %.3f of 0.50)"
			% flat.get_travel().length()
		)


## Inhabitants: the simulation exists, is stable, advances without frames, and
## the 3D layer plus the panel reflect the same records. `tree` is needed to give
## `NpcPresenter` and `NpcPanel` one idle frame to synchronise their views.
static func check_npcs(harness: TestHarness, world: Node3D, tree: SceneTree) -> void:
	harness.suite("Inhabitants")
	var system: NpcSimulationSystem = world.get_npc_system()
	var presenter: NpcPresenter = world.get_npc_presenter()
	var panel := world.get_node_or_null("NpcPanel") as NpcPanel
	harness.check(system != null, "the world exposes its NPC simulation")
	harness.check(presenter != null, "the world exposes its NPC presenter")
	harness.check(panel != null, "the world contains the observation panel")
	if system == null or presenter == null or panel == null:
		return
	# This file is a static dependency of the entry-point runner, which is
	# compiled before the autoloads are registered: naming `Game` here would be
	# a compile error. Resolve the singleton through the tree instead.
	var game := _autoload(tree, "Game")
	var event_bus := _autoload(tree, "EventBus")
	var config := _config_from(game)
	harness.check(game != null, "the Game autoload is available")
	harness.check(config != null, "the Game autoload exposes the configuration")
	if config != null:
		harness.check_equals(
			system.get_record_count(),
			mini(config.npc_population_size, NpcRoster.MAX_POPULATION),
			"the population follows GameConfig.npc_population_size"
		)
	harness.check(
		game != null and game.call("get_npc_system") == system,
		"the simulation is registered with Game, not driven by the scene"
	)
	var view_ids := presenter.get_view_ids()
	var known_views := 0
	for view_id in view_ids:
		if system.get_record(view_id) != null:
			known_views += 1
	harness.check_equals(known_views, view_ids.size(), "every view maps to a record")
	harness.check(
		view_ids.size() <= system.get_record_count(), "there are no orphan views"
	)

	var ids := {}
	var names_match := true
	var expected_roster := NpcRoster.build(system.get_record_count())
	for index in system.get_records().size():
		var record := system.get_records()[index]
		ids[record.id] = true
		if record.display_name != expected_roster[index].display_name:
			names_match = false
	harness.check_equals(ids.size(), system.get_record_count(), "NPC ids are unique")
	harness.check(names_match, "names are stable across constructions")

	# Simulated time advances needs without any rendered frame.
	var watched := system.get_records()[0]
	var hunger_before := watched.needs.hunger
	if game != null:
		game.call("advance_simulation", 60)
	harness.check(
		not is_equal_approx(watched.needs.hunger, hunger_before),
		"needs evolve when the simulation advances"
	)

	# Hide every view: the records must keep changing.
	if event_bus != null:
		event_bus.emit_signal("npc_selected", "")
	presenter.set_render_distance(0.0)
	# `process_frame` fires before Node._process, so one await only reaches the
	# frame in which the views are about to be synchronised. Two awaits guarantee
	# that the synchronisation itself has run.
	await tree.process_frame
	await tree.process_frame
	harness.check_equals(presenter.get_view_count(), 0, "nobody is rendered at distance 0")
	var hunger_unrendered := watched.needs.hunger
	if game != null:
		game.call("advance_simulation", 90)
	harness.check(
		not is_equal_approx(watched.needs.hunger, hunger_unrendered),
		"the simulation advances while the NPC has no view"
	)
	harness.check(watched.position.is_finite(), "an unrendered NPC keeps a valid position")
	harness.check(
		not watched.current_place_name.is_empty(),
		"an unrendered NPC still knows where it is"
	)
	harness.check(
		watched.goal != NpcRecord.Goal.BLOCKED,
		"an unrendered NPC keeps a coherent goal"
	)

	# Selection: the presenter, the event bus and the panel agree, and the panel
	# shows the selected record rather than a placeholder.
	presenter.set_render_distance(500.0)
	await tree.process_frame
	await tree.process_frame
	harness.check_equals(
		presenter.get_view_count(), system.get_record_count(), "all views exist within 500 units"
	)
	var target := system.get_records()[2]
	harness.check(presenter.select_npc(target.id), "selecting a known NPC succeeds")
	harness.check_equals(presenter.get_selected_id(), target.id, "the presenter remembers it")
	harness.check_equals(panel.get_selected_id(), target.id, "the panel receives the event")
	harness.check(presenter.get_view_node(target.id) != null, "the selected NPC has a view")
	await tree.process_frame
	harness.check_equals(panel.get_displayed_name(), target.display_name, "the panel shows the name")
	harness.check_equals(
		panel.get_selector_item_count(), system.get_record_count() + 1, "the selector lists everyone"
	)
	harness.check(
		panel.get_displayed_activity().contains(target.activity_label()),
		"the panel shows the live activity"
	)
	harness.check(
		panel.get_displayed_summary().contains(target.display_name),
		"the panel shows a status summary of that character"
	)
	harness.check_almost(
		panel.get_displayed_energy(), target.needs.energy, 1.0, "need bars read the record"
	)
	harness.check(not presenter.select_npc("npc_999"), "an unknown id cannot be selected")
	harness.check_equals(panel.get_selected_id(), target.id, "a failed selection changes nothing")
	presenter.set_render_distance(
		config.npc_view_distance if config != null else presenter.render_distance
	)
	if event_bus != null:
		event_bus.emit_signal("npc_selected", "")


## Economy and UI panel: verifies that the economy is registered with `Game`,
## advances deterministically in the live world, and `EconomyPanel` displays
## exact live data without independent counters.
static func check_economy(harness: TestHarness, world: Node3D, tree: SceneTree) -> void:
	harness.suite("EconomyAndPanel")
	var economy: EconomySystem = world.get_economy_system()
	var panel := world.get_node_or_null("EconomyPanel") as EconomyPanel
	var game := _autoload(tree, "Game")
	harness.check(economy != null, "the world exposes its economy system")
	harness.check(panel != null, "the world contains the EconomyPanel")
	if economy == null or panel == null:
		return
	harness.check(
		game != null and game.call("get_economy_system") == economy,
		"the economy system is registered with Game"
	)

	# Advance simulated time through daytime work shifts so production and
	# consumption occur in the real village.
	if game != null:
		game.call("advance_simulation", 300)
	await tree.process_frame
	await tree.process_frame

	for res_id in ResourceType.ALL_IDS:
		harness.check_equals(
			panel.get_displayed_amount(res_id),
			economy.get_village_resource(res_id),
			"EconomyPanel displays exact %s amount" % res_id
		)
	for mat_id in ResourceType.MATERIAL_IDS:
		var expected_flow := "+%d / -%d" % [
			economy.get_production(mat_id, true),
			economy.get_consumption(mat_id, true),
		]
		harness.check_equals(
			panel.get_displayed_flow_text(mat_id),
			expected_flow,
			"EconomyPanel displays exact %s flow (+prod / -cons)" % mat_id
		)
	harness.check_equals(
		panel.get_displayed_shortages(),
		"Carenze: %s" % EconomyRules.format_shortages(economy),
		"EconomyPanel displays exact shortages summary"
	)
	harness.check_equals(
		panel.get_displayed_projects(),
		EconomyRules.format_projects(economy),
		"EconomyPanel displays exact community project summary"
	)
	var recent := EconomyRules.recent_transactions(economy, 1, true)
	if not recent.is_empty():
		harness.check(
			panel.get_displayed_transactions().contains(recent[0].reason),
			"EconomyPanel displays recent important transactions"
		)

	# Mutate the underlying economy (e.g. a validated transfer) and verify the
	# UI reflects the change on the very next refresh with no separate counter.
	var food_before := economy.get_village_resource(ResourceType.FOOD)
	if food_before >= 2:
		harness.check(
			economy.transfer_resource("village", "npc_001", ResourceType.FOOD, 2),
			"transferring 2 Food to npc_001 succeeds"
		)
		panel.refresh_view()
		harness.check_equals(
			panel.get_displayed_amount(ResourceType.FOOD),
			food_before - 2,
			"EconomyPanel immediately reflects the updated village Food stock"
		)
		economy.transfer_resource("npc_001", "village", ResourceType.FOOD, 2)
		panel.refresh_view()


## The village has to stay cheap enough for a GTX 1060 class GPU.
static func check_budget(harness: TestHarness, world: Node3D) -> void:
	harness.suite("PerformanceBudget")
	var village_root := world.get_node_or_null("Village") as Node3D
	if village_root == null:
		harness.check(false, "world has a Village node")
		return
	var meshes := 0
	var triangles := 0
	var colliders := 0
	var stack: Array = [village_root, world.get_node_or_null("Terrain")]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node == null:
			continue
		if node is MeshInstance3D:
			meshes += 1
			triangles += _mesh_triangles((node as MeshInstance3D).mesh)
		elif node is MultiMeshInstance3D:
			meshes += 1
			var multi := (node as MultiMeshInstance3D).multimesh
			if multi != null and multi.mesh != null:
				triangles += _mesh_triangles(multi.mesh) * multi.instance_count
		elif node is CollisionShape3D:
			colliders += 1
		for child in node.get_children():
			stack.append(child)
	harness.check(meshes > 0, "the world contains meshes")
	harness.check(
		meshes <= MAX_VILLAGE_MESHES,
		"draw calls stay in budget: %d meshes (limit %d)" % [meshes, MAX_VILLAGE_MESHES]
	)
	harness.check(
		triangles <= MAX_TOTAL_TRIANGLES,
		"triangle count stays in budget: %d (limit %d)" % [triangles, MAX_TOTAL_TRIANGLES]
	)
	harness.check(
		colliders <= MAX_COLLIDERS,
		"static collider count stays in budget: %d (limit %d)" % [colliders, MAX_COLLIDERS]
	)


## Named areas cover the village, and the player's own position resolves to one.
static func check_areas(harness: TestHarness, world: Node3D) -> void:
	harness.suite("Areas")
	var registry: AreaRegistry = world.get_area_registry()
	harness.check(registry != null, "the world exposes an area registry")
	if registry == null:
		return
	harness.check(registry.get_area_count() >= 6, "the village is divided into named areas")
	harness.check(
		registry.get_area_names().has("Piazza del Pozzo"), "the plaza has a name"
	)
	harness.check_equals(
		registry.area_at(Vector2.ZERO), "Piazza del Pozzo", "the plaza centre is the plaza"
	)
	harness.check_equals(
		registry.area_at(Vector2(500.0, 500.0)),
		AreaRegistry.FALLBACK_AREA_NAME,
		"far outside the village is open country"
	)
	var player: CharacterBody3D = world.get_player()
	if player != null:
		var area_name := registry.area_at(
			Vector2(player.global_position.x, player.global_position.z)
		)
		harness.check(not area_name.is_empty(), "the player position resolves to an area name")


# --- helpers -----------------------------------------------------------------


static func _nearest_structure_position(layout: VillageLayout, from: Vector3) -> Vector3:
	var best: VillageLayout.Placement = null
	var best_distance := INF
	for placement in layout.placements:
		var is_building := (
			placement.kind == VillageLayout.KIND_HOUSE
			or placement.kind == VillageLayout.KIND_INN
		)
		if not is_building:
			continue
		var flat := Vector2(placement.position.x, placement.position.y)
		var distance := Vector2(from.x, from.z).distance_to(flat)
		if distance < best_distance:
			best_distance = distance
			best = placement
	if best == null:
		return Vector3.ZERO
	return Vector3(best.position.x, 0.0, best.position.y)


## RID of every body that is not the terrain, plus the player. Used to make the
## ground rays ignore the village standing on top of the ground.
static func _non_terrain_bodies(world: Node3D) -> Array:
	var rids: Array = []
	var terrain_body := world.get_node_or_null("Terrain")
	var player: CharacterBody3D = world.get_player()
	if player != null:
		rids.append(player.get_rid())
	var stack: Array = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is StaticBody3D and node != terrain_body:
			rids.append((node as StaticBody3D).get_rid())
		for child in node.get_children():
			stack.append(child)
	return rids


static func _motion_result(
	player: CharacterBody3D, from: Vector3, motion: Vector3
) -> PhysicsTestMotionResult3D:
	var parameters := PhysicsTestMotionParameters3D.new()
	parameters.from = Transform3D(Basis.IDENTITY, from)
	parameters.motion = motion
	parameters.margin = 0.001
	var result := PhysicsTestMotionResult3D.new()
	PhysicsServer3D.body_test_motion(player.get_rid(), parameters, result)
	return result


static func _mesh_triangles(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		# A primitive without an index array has `null` in ARRAY_INDEX, not an
		# empty PackedInt32Array: calling `is_empty()` on it is a script error.
		var indices = arrays[Mesh.ARRAY_INDEX]
		if indices != null and not (indices as PackedInt32Array).is_empty():
			total += (indices as PackedInt32Array).size() / 3
		else:
			var vertices = arrays[Mesh.ARRAY_VERTEX]
			if vertices != null:
				total += (vertices as PackedVector3Array).size() / 3
	return total


## The player must never end up below the surface while the world runs.
## [param min_clearance] is the smallest `player.y - terrain.height_at()` seen
## over the observation window, measured by the runner.
static func check_player_stays_up(harness: TestHarness, min_clearance: float) -> void:
	harness.suite("PlayerStaysUp")
	if min_clearance == INF:
		harness.skip("no player or terrain available to watch")
		return
	harness.check(
		min_clearance > -0.25,
		"the player never sinks into the terrain (worst clearance %.3f)" % min_clearance
	)
	harness.check(
		min_clearance < 5.0,
		"the player never floats away from the terrain (worst clearance %.3f)" % min_clearance
	)


## Resolves an autoload by node name without naming it statically.
static func _autoload(tree: SceneTree, autoload_name: String) -> Node:
	return tree.root.get_node_or_null(autoload_name)


static func _config_from(game: Node) -> GameConfig:
	if game == null:
		return null
	return game.get("config") as GameConfig
