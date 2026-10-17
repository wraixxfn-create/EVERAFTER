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
	for node_name in ["Sky", "Terrain", "Village", "Player", "WorldHud", "DiagnosticsHud"]:
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
		if not arrays[Mesh.ARRAY_INDEX].is_empty():
			total += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		else:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
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
