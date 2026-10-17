class_name TestNpcRouteGraph
extends RefCounted
## Checks the deterministic waypoint network: paths exist where the village is
## walkable, every path segment avoids the obstacles, unreachable places are
## reported instead of being silently connected, and two identical builds
## produce identical paths.


static func run_tests(harness: TestHarness) -> void:
	harness.suite("NpcRouteGraph")
	var places := _places()
	var roads: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-40, 0), Vector2(40, 0)])
	]
	var obstacles: Array[NpcRouteGraph.Obstacle] = [
		NpcRouteGraph.Obstacle.new("rock", Vector2(0, 5), 3.0)
	]
	var graph := NpcRouteGraph.new(places, roads, obstacles)
	harness.check(graph.get_node_count() > 20, "roads are sampled into nodes")
	harness.check(graph.get_edge_count() > 20, "road samples are connected")
	if graph.path_is_clear(PackedVector2Array([Vector2(0, 10), Vector2(0, 0)])):
		harness.check(false, "a segment through an obstacle is not clear")
	else:
		harness.check(true, "a segment through an obstacle is not clear")
	harness.check(graph.is_place_reachable("west"), "a connected place is reachable")
	harness.check(graph.is_place_reachable("east"), "a second connected place is reachable")
	harness.check(
		not graph.is_place_reachable("blocked"),
		"a place with no walkable connector is unreachable"
	)
	harness.check(
		graph.get_unreachable_place_ids().has("blocked"),
		"the unreachable place is reported by id"
	)
	var path := graph.find_path(Vector2(-30, 5), "east")
	harness.check(not path.is_empty(), "a path exists between two connected places")
	harness.check(path.size() >= 2, "the path has a real start and end")
	if not path.is_empty():
		harness.check_almost(path[0].x, -30.0, 0.001, "the path starts at the NPC position")
		harness.check_almost(path[path.size() - 1].x, 30.0, 0.001, "the path ends at the place")
		harness.check_almost(path[path.size() - 1].y, -5.0, 0.001, "the path ends at the place")
		harness.check(graph.path_is_clear(path), "the whole path avoids the obstacles")
		harness.check(graph.path_length(path) > 60.0, "the path length is plausible")
	harness.check(
		graph.find_path(Vector2(-30, 5), "blocked").is_empty(),
		"no path is invented for an unreachable place"
	)
	harness.check(
		graph.find_path(Vector2(-30, 5), "missing").is_empty(),
		"no path is invented for an unknown place"
	)

	var second_graph := NpcRouteGraph.new(places, roads, obstacles)
	var second_path := second_graph.find_path(Vector2(-30, 5), "east")
	harness.check_equals(path, second_path, "two identical graphs produce the same path")
	harness.check_equals(
		graph.get_node_count(), second_graph.get_node_count(), "node count is deterministic"
	)
	harness.check_equals(
		graph.get_edge_count(), second_graph.get_edge_count(), "edge count is deterministic"
	)

	# A place already at the arrival distance needs no walk.
	var nearby := NpcRouteGraph.new(places, roads, obstacles)
	var at_place := nearby.find_path(Vector2(30, -4.5), "east")
	harness.check_equals(at_place.size(), 1, "a place already reached yields a single point")
	if at_place.size() == 1:
		harness.check_almost(at_place[0].x, 30.0, 0.001, "the single point is the place")


static func _places() -> NpcPlaceRegistry:
	var registry := NpcPlaceRegistry.new()
	registry.add("west", "Ovest", NpcPlace.Kind.WORK, Vector2(-30, 5))
	registry.add("east", "Est", NpcPlace.Kind.WORK, Vector2(30, -5))
	# Far outside the connector range of the road: no edge can be invented for
	# it. The obstacle check is exercised separately by `path_is_clear()`.
	registry.add("blocked", "Bloccata", NpcPlace.Kind.WORK, Vector2(0, 60))
	return registry
