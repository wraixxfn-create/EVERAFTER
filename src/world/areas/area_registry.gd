class_name AreaRegistry
extends RefCounted
## Named regions of the world, used to tell the player where they are.
##
## Pure data: no nodes, no terrain, no rendering, so it can be unit tested
## headless and reused later by the simulation (an NPC that "is at the market"
## needs exactly this lookup) and by the chronicles.
##
## An area is a polyline plus a radius: a single point gives a circular region
## (the plaza, the pond), a multi point polyline gives a corridor (a road).
## [method area_at] returns the area whose *edge* is closest to the query, and
## breaks ties with [member Area.priority], so a small named place inside a
## larger one (the inn standing on a road) wins.

const FALLBACK_AREA_NAME := "Campi di Everafter"


## One named region. `points` are world XZ coordinates.
class Area extends RefCounted:
	var area_name: String = ""
	var points := PackedVector2Array()
	var radius: float = 1.0
	## Higher wins when two areas both contain the point.
	var priority: int = 0

	func contains(world_position: Vector2) -> bool:
		return edge_distance(world_position) <= radius

	## Distance from the point to the area border: negative inside.
	func edge_distance(world_position: Vector2) -> float:
		return distance_to_polyline(world_position) - radius

	## Shortest distance to the polyline (or to the single point).
	func distance_to_polyline(world_position: Vector2) -> float:
		return AreaRegistry.distance_to_polyline(world_position, points)


var _areas: Array[Area] = []


## Shortest distance from [param point] to a polyline (a single point is a
## valid, degenerate polyline). Shared with `VillageLayout`, which needs the
## same measure to keep roads clear of props.
static func distance_to_polyline(point: Vector2, points: PackedVector2Array) -> float:
	if points.size() == 0:
		return INF
	if points.size() == 1:
		return point.distance_to(points[0])
	var best := INF
	for index in points.size() - 1:
		best = minf(best, distance_to_segment(point, points[index], points[index + 1]))
	return best


## Shortest distance from [param point] to the segment `start`-`end`.
static func distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var span := end - start
	var length_sq := span.length_squared()
	if length_sq <= 0.0001:
		return point.distance_to(start)
	var t := clampf((point - start).dot(span) / length_sq, 0.0, 1.0)
	return point.distance_to(start + span * t)


func add_area(
	area_name: String, points: PackedVector2Array, radius: float, priority: int = 0
) -> void:
	var area := Area.new()
	area.area_name = area_name
	area.points = points
	area.radius = maxf(radius, 0.0)
	area.priority = priority
	_areas.append(area)


## Convenience for circular areas.
func add_circle(area_name: String, center: Vector2, radius: float, priority: int = 0) -> void:
	add_area(area_name, PackedVector2Array([center]), radius, priority)


func get_area_count() -> int:
	return _areas.size()


func get_area_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for area in _areas:
		names.append(area.area_name)
	return names


## Name of the region containing [param world_position], or
## [constant FALLBACK_AREA_NAME] when the player is out in the open country.
func area_at(world_position: Vector2) -> String:
	var best: Area = null
	var best_score := INF
	for area in _areas:
		var edge := area.edge_distance(world_position)
		if edge > 0.0:
			continue
		# Inside the area: prefer the highest priority, then the tightest fit.
		var score := -float(area.priority) * 1000.0 + edge
		if score < best_score:
			best_score = score
			best = area
	if best == null:
		return FALLBACK_AREA_NAME
	return best.area_name


## True when [param world_position] falls inside any named region.
func is_inside_named_area(world_position: Vector2) -> bool:
	for area in _areas:
		if area.contains(world_position):
			return true
	return false
