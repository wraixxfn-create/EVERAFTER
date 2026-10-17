class_name NpcRouteGraph
extends RefCounted
## Deterministic walkable route network used by the NPC simulation.
##
## Why not `NavigationServer3D`: the village is procedural and the simulation
## must run headless, without a viewport, without baked navigation data and
## without depending on the physics frame. A road-and-place waypoint graph gives
## the same guarantees we need — paths only use walkable ground, every visible
## move is continuous, unreachable places are detected instead of teleported
## into — and it can be asserted by a unit test in a few milliseconds.
##
## Construction:
## 1. sample every road polyline at [constant SAMPLE_SPACING] metres;
## 2. link consecutive samples and the three road ends around the plaza;
## 3. add one node per place and connect it to the nearest road nodes with a
##    straight, obstacle-checked segment;
## 4. link nearby places directly when a clear line of sight exists.
##
## Every connector edge is rejected if it passes within
## `obstacle.radius + NPC_RADIUS + EDGE_CLEARANCE` of an obstacle. A place whose
## node does not end up in the main connected component is reported as
## unreachable; callers must handle that, and [NpcSimulationSystem] does.
##
## The graph is pure data (AStar2D is a RefCounted helper, not a node).

class Obstacle extends RefCounted:
	var label: String = ""
	var position := Vector2.ZERO
	var radius: float = 1.0

	func _init(
		initial_label: String = "", initial_position: Vector2 = Vector2.ZERO,
		initial_radius: float = 1.0
	) -> void:
		label = initial_label
		position = initial_position
		radius = maxf(initial_radius, 0.0)


const SAMPLE_SPACING := 3.0
const NODE_DEDUPE_DISTANCE := 0.9
const MAX_CONNECTOR_DISTANCE := 45.0
const MAX_PLACE_LINK_DISTANCE := 24.0
const MAX_ROAD_LINK_DISTANCE := 24.0
const ROAD_CONNECTIONS_PER_PLACE := 3
const MAX_CONNECTOR_ATTEMPTS := 24
const PLACE_CONNECTIONS_PER_PLACE := 2
const NPC_RADIUS := 0.42
const EDGE_CLEARANCE := 0.12
const ARRIVAL_RADIUS := 0.9

var _astar := AStar2D.new()
var _node_points: Array[Vector2] = []
var _road_node_ids: Array[int] = []
var _place_node_ids: Dictionary = {}
var _reachable_node_ids: Dictionary = {}
var _unreachable_place_ids: PackedStringArray = []
var _places: NpcPlaceRegistry = null
var _roads: Array[PackedVector2Array] = []
var _obstacles: Array[Obstacle] = []
var _edge_count: int = 0


func _init(
	place_registry: NpcPlaceRegistry,
	road_polylines: Array[PackedVector2Array],
	obstacles: Array[Obstacle]
) -> void:
	_places = place_registry
	_roads = road_polylines
	_obstacles = obstacles
	_build()


func get_node_count() -> int:
	return _astar.get_point_count()


func get_edge_count() -> int:
	return _edge_count


func get_unreachable_place_ids() -> PackedStringArray:
	return _unreachable_place_ids


## True when the place node belongs to the main connected component.
func is_place_reachable(place_id: String) -> bool:
	if not _place_node_ids.has(place_id):
		return false
	return _reachable_node_ids.has(int(_place_node_ids[place_id]))


## Returns the walkable path from [param from] to the place, or an empty array
## when the place is unknown or unreachable. The returned path starts at
## [param from] (when it is not exactly on a node) and ends at the place.
func find_path(from: Vector2, to_place_id: String) -> PackedVector2Array:
	var empty: PackedVector2Array = []
	if _places == null:
		return empty
	var target_place := _places.get_place(to_place_id)
	if target_place == null or not _place_node_ids.has(to_place_id):
		return empty
	if not is_place_reachable(to_place_id):
		return empty
	if from.distance_to(target_place.position) <= ARRIVAL_RADIUS:
		return PackedVector2Array([target_place.position])
	var target_id := int(_place_node_ids[to_place_id])
	var start_id := _nearest_reachable_node(from)
	var raw := _astar.get_point_path(start_id, target_id) if start_id >= 0 \
		else PackedVector2Array()
	if raw.is_empty():
		return empty
	var path := PackedVector2Array()
	if from.distance_to(raw[0]) > 0.05:
		path.append(from)
	for point in raw:
		if path.is_empty() or path[path.size() - 1].distance_to(point) > 0.01:
			path.append(point)
	return path


## Checks every segment of a path against the obstacles. Public so the test
## suite can prove that "a path exists" does not merely mean "a line was drawn".
func path_is_clear(path: PackedVector2Array) -> bool:
	for index in maxi(path.size() - 1, 0):
		if not _segment_is_clear(path[index], path[index + 1]):
			return false
	return true


func path_length(path: PackedVector2Array) -> float:
	var total := 0.0
	for index in maxi(path.size() - 1, 0):
		total += path[index].distance_to(path[index + 1])
	return total


# --- construction ------------------------------------------------------------


func _build() -> void:
	var road_endpoints: Array[int] = []
	for road in _roads:
		var samples := _sample_polyline(road)
		if samples.is_empty():
			continue
		var ids: Array[int] = []
		for point in samples:
			var node_id := _add_node(point, false)
			ids.append(node_id)
			if not _road_node_ids.has(node_id):
				_road_node_ids.append(node_id)
		for index in ids.size() - 1:
			_connect_nodes(ids[index], ids[index + 1])
		road_endpoints.append(ids[0])
		road_endpoints.append(ids[ids.size() - 1])
	# The three roads leave the plaza independently; link their ends into a ring
	# so the network is connected without crossing the well.
	for first in road_endpoints.size():
		for second in range(first + 1, road_endpoints.size()):
			_link_if_near(road_endpoints[first], road_endpoints[second], MAX_ROAD_LINK_DISTANCE)
	# One node per place, plus checked connectors.
	for place in _places.all_places():
		var node_id := _add_node(place.position, true)
		_place_node_ids[place.id] = node_id
		_connect_place_to_roads(node_id, place.position)
	_connect_nearby_places()
	_compute_reachable_component()


func _sample_polyline(road: PackedVector2Array) -> Array[Vector2]:
	var samples: Array[Vector2] = []
	if road.is_empty():
		return samples
	if road.size() == 1:
		samples.append(road[0])
		return samples
	for index in road.size() - 1:
		var start := road[index]
		var end := road[index + 1]
		var span := end - start
		var length := span.length()
		if length <= 0.0001:
			continue
		var direction := span / length
		var travelled := 0.0
		while travelled < length:
			samples.append(start + direction * travelled)
			travelled += SAMPLE_SPACING
	# The last point of a road must be a node, not an approximation.
	samples.append(road[road.size() - 1])
	return samples


func _add_node(point: Vector2, allow_dedupe: bool) -> int:
	if allow_dedupe:
		for index in _node_points.size():
			if _node_points[index].distance_to(point) <= NODE_DEDUPE_DISTANCE:
				return index
	var node_id := _astar.get_point_count()
	_astar.add_point(node_id, point)
	_node_points.append(point)
	return node_id


func _connect_place_to_roads(place_node_id: int, place_position: Vector2) -> void:
	# Try more than the final number of connectors: the road nodes closest to a
	# place are often on the same side of a fence, a tree line or the pond, and
	# rejecting them all would make a perfectly reachable place look unreachable.
	var tried: Array[int] = []
	var connected := 0
	while tried.size() < MAX_CONNECTOR_ATTEMPTS \
			and connected < ROAD_CONNECTIONS_PER_PLACE:
		var best_id := -1
		var best_distance := INF
		for road_node_id in _road_node_ids:
			if road_node_id == place_node_id or tried.has(road_node_id):
				continue
			var distance := place_position.distance_to(_node_points[road_node_id])
			if distance <= MAX_CONNECTOR_DISTANCE and distance < best_distance:
				best_distance = distance
				best_id = road_node_id
		if best_id < 0:
			break
		tried.append(best_id)
		if _segment_is_clear(place_position, _node_points[best_id]):
			_link_if_clear(place_node_id, best_id)
			connected += 1
	# A few direct links between neighbouring places make clusters (inn, market,
	# houses) usable even when the nearest road is across a fence.
	var place_neighbours: Array[int] = []
	for _attempt in PLACE_CONNECTIONS_PER_PLACE:
		var best_id := -1
		var best_distance := INF
		for other_id in _place_node_ids.values():
			var candidate := int(other_id)
			if candidate == place_node_id or place_neighbours.has(candidate):
				continue
			var distance := place_position.distance_to(_node_points[candidate])
			if distance <= MAX_PLACE_LINK_DISTANCE and distance < best_distance:
				best_distance = distance
				best_id = candidate
		if best_id < 0:
			break
		place_neighbours.append(best_id)
		_link_if_clear(place_node_id, best_id)


func _connect_nearby_places() -> void:
	var ids: Array[int] = []
	for value in _place_node_ids.values():
		var node_id := int(value)
		if not ids.has(node_id):
			ids.append(node_id)
	for first in ids.size():
		for second in range(first + 1, ids.size()):
			_link_if_near(ids[first], ids[second], MAX_PLACE_LINK_DISTANCE)


func _link_if_near(first_id: int, second_id: int, max_distance: float) -> void:
	if first_id == second_id:
		return
	if _node_points[first_id].distance_to(_node_points[second_id]) > max_distance:
		return
	_link_if_clear(first_id, second_id)


func _link_if_clear(first_id: int, second_id: int) -> void:
	if first_id == second_id:
		return
	if _astar.are_points_connected(first_id, second_id):
		return
	if not _segment_is_clear(_node_points[first_id], _node_points[second_id]):
		return
	_astar.connect_points(first_id, second_id, true)
	_edge_count += 1


func _connect_nodes(first_id: int, second_id: int) -> void:
	_link_if_clear(first_id, second_id)


func _segment_is_clear(start: Vector2, end: Vector2) -> bool:
	for obstacle in _obstacles:
		var clearance := obstacle.radius + NPC_RADIUS + EDGE_CLEARANCE
		if _distance_to_segment(obstacle.position, start, end) < clearance:
			return false
	return true


func _compute_reachable_component() -> void:
	var visited: Dictionary = {}
	var best: Array[int] = []
	for point_id in _astar.get_point_ids():
		var node_id := int(point_id)
		if visited.has(node_id):
			continue
		var component: Array[int] = []
		var queue: Array[int] = [node_id]
		visited[node_id] = true
		while not queue.is_empty():
			var current := queue.pop_back()
			component.append(current)
			for neighbour in _astar.get_point_connections(current):
				var neighbour_id := int(neighbour)
				if not visited.has(neighbour_id):
					visited[neighbour_id] = true
					queue.append(neighbour_id)
		if component.size() > best.size():
			best = component
	_reachable_node_ids.clear()
	for node_id in best:
		_reachable_node_ids[node_id] = true
	_unreachable_place_ids.clear()
	for place_id in _place_node_ids.keys():
		if not _reachable_node_ids.has(int(_place_node_ids[place_id])):
			_unreachable_place_ids.append(String(place_id))


func _nearest_reachable_node(point: Vector2) -> int:
	var best_id := -1
	var best_distance := INF
	for node_id in _reachable_node_ids.keys():
		var distance := point.distance_to(_node_points[int(node_id)])
		if distance < best_distance:
			best_distance = distance
			best_id = int(node_id)
	return best_id


static func _distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var span := end - start
	var length_sq := span.length_squared()
	if length_sq <= 0.0001:
		return point.distance_to(start)
	var t := clampf((point - start).dot(span) / length_sq, 0.0, 1.0)
	return point.distance_to(start + span * t)


func _to_string() -> String:
	return "NpcRouteGraph(%d nodes, %d edges, %d places, %d unreachable)" % [
		get_node_count(), _edge_count, _places.get_count() if _places != null else 0,
		_unreachable_place_ids.size(),
	]
