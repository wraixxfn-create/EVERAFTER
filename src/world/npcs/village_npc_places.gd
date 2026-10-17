class_name VillageNpcPlaces
extends RefCounted
## Turns the village plan into the pure-data place registry used by the NPC
## simulation.
##
## This is the only file that knows both sides: `VillageLayout` (world data) and
## `NpcPlace`/`NpcRouteGraph` (simulation data). Keeping it in `world/` means the
## simulation itself never imports the 3D world, while the positions it uses are
## still the real positions of the village rather than magic numbers invented
## in `src/npcs`.
##
## Homes are assigned to the starting inhabitants in roster order, so a given
## NPC always wakes up in the same house. Workplaces, food places and social
## places are named locations derived from the layout.

const CLEARANCE_MARGIN := 0.9
const ANCHOR_STEP := 2.0
const ANCHOR_RINGS := 7
const ANCHOR_DIRECTIONS := 8


## Builds every place the simulation can talk about.
static func build(
	layout: VillageLayout, records: Array[NpcRecord]
) -> NpcPlaceRegistry:
	var registry := NpcPlaceRegistry.new()
	var obstacles := build_obstacles(layout)
	var houses := _sorted_by_distance(
		layout.get_placements_of_kind(VillageLayout.KIND_HOUSE), Vector2.ZERO
	)
	_add_homes(registry, layout, records, houses, obstacles)
	var inn := _first_of_kind(layout, VillageLayout.KIND_INN)
	var hall := _first_of_kind(layout, VillageLayout.KIND_HALL)
	var market_position := _market_anchor(layout, obstacles)
	var field_position := _find_clear_anchor(
		layout, layout.point_on_road(2, 34.0), obstacles, false
	)
	var garden_position := _find_clear_anchor(
		layout, Vector2(-30.0, 4.0), obstacles, false
	)
	var pond_position := _find_clear_anchor(
		layout,
		layout.pond_center + (Vector2.ZERO - layout.pond_center).normalized()
		* (layout.pond_radius + 2.2),
		obstacles,
		true
	)
	var forge_position := _anchor_for_house(layout, houses, Vector2(13.0, -6.0), obstacles)
	var workshop_position := _anchor_for_house(
		layout, houses, Vector2(-11.0, 9.0), obstacles
	)
	var inn_door := _clear_door_anchor(layout, inn, obstacles) if inn != null \
		else market_position
	var hall_door := _clear_door_anchor(layout, hall, obstacles) if hall != null \
		else market_position

	registry.add(
		"work_field", "Campi del villaggio", NpcPlace.Kind.WORK, field_position
	)
	registry.add(
		"work_inn", "Locanda del Cervo Bianco", NpcPlace.Kind.WORK, inn_door
	)
	registry.add("work_market", "Bancarelle del mercato", NpcPlace.Kind.WORK, market_position)
	registry.add("work_hall", "Sala del Consiglio", NpcPlace.Kind.WORK, hall_door)
	registry.add("work_forge", "Fucina", NpcPlace.Kind.WORK, forge_position)
	registry.add(
		"work_garden", "Giardino delle erbe", NpcPlace.Kind.WORK, garden_position
	)
	registry.add("work_pond", "Riva dello stagno", NpcPlace.Kind.WORK, pond_position)
	registry.add(
		"work_workshop", "Bottega dei mestieri", NpcPlace.Kind.WORK, workshop_position
	)

	registry.add(
		"food_inn",
		"Locanda del Cervo Bianco",
		NpcPlace.Kind.FOOD,
		inn_door,
		11 * 60,
		23 * 60,
		true,
		12
	)
	registry.add(
		"food_market",
		"Bancarelle del mercato",
		NpcPlace.Kind.FOOD,
		market_position,
		8 * 60,
		18 * 60,
		true,
		10
	)
	registry.add(
		"social_plaza",
		"Piazza del Pozzo",
		NpcPlace.Kind.SOCIAL,
		_find_clear_anchor(layout, Vector2(0.0, -7.5), obstacles, false)
	)
	registry.add(
		"social_inn",
		"Locanda del Cervo Bianco",
		NpcPlace.Kind.SOCIAL,
		inn_door,
		11 * 60,
		23 * 60
	)
	registry.add(
		"rest_inn",
		"Camere della locanda",
		NpcPlace.Kind.REST,
		inn_door,
		11 * 60,
		23 * 60
	)
	registry.add(
		"leisure_pond",
		"Riva dello stagno",
		NpcPlace.Kind.LEISURE,
		pond_position,
		6 * 60,
		20 * 60
	)
	return registry


## Obstacles used to validate walkable connectors. Radii are conservative
## approximations of the real colliders, not the visual footprint.
static func build_obstacles(layout: VillageLayout) -> Array[NpcRouteGraph.Obstacle]:
	var obstacles: Array[NpcRouteGraph.Obstacle] = []
	for placement in layout.placements:
		var radius := _obstacle_radius(placement)
		if radius <= 0.01:
			continue
		obstacles.append(
			NpcRouteGraph.Obstacle.new(placement.id, placement.position, radius)
		)
	# Do not walk through the pond, only around it.
	obstacles.append(
		NpcRouteGraph.Obstacle.new(
			"pond_water", layout.pond_center, layout.pond_radius + 0.6
		)
	)
	return obstacles


static func _add_homes(
	registry: NpcPlaceRegistry,
	layout: VillageLayout,
	records: Array[NpcRecord],
	houses: Array[VillageLayout.Placement],
	obstacles: Array[NpcRouteGraph.Obstacle]
) -> void:
	if records.is_empty():
		return
	for index in records.size():
		var position := Vector2.ZERO
		if not houses.is_empty():
			var house: VillageLayout.Placement = houses[index % houses.size()]
			var anchor := _door_anchor(layout, house)
			# When the population outnumbers the houses, the same door is shared:
			# shift the extra inhabitants aside instead of stacking capsules.
			var share := index / houses.size()
			if share > 0:
				anchor += Vector2(1.8 * float(share), -1.8 * float(share))
			position = _find_clear_anchor(layout, anchor, obstacles, false)
		else:
			# Degenerate layout: still give every record a unique, reachable
			# starting point instead of failing to spawn.
			position = _find_clear_anchor(
				layout,
				Vector2(6.0 + float(index) * 1.5, -8.0),
				obstacles,
				false
			)
		var first_name := records[index].display_name.get_slice(" ", 0)
		registry.add(
			"home_%03d" % (index + 1),
			"Casa di %s" % first_name,
			NpcPlace.Kind.HOME,
			position,
			0,
			0,
			true,
			1
		)


static func _first_of_kind(layout: VillageLayout, kind: String) -> VillageLayout.Placement:
	var placements := layout.get_placements_of_kind(kind)
	if placements.is_empty():
		return null
	return placements[0]


static func _anchor_for_house(
	layout: VillageLayout,
	houses: Array[VillageLayout.Placement],
	target: Vector2,
	obstacles: Array[NpcRouteGraph.Obstacle]
) -> Vector2:
	if houses.is_empty():
		return _find_clear_anchor(layout, target, obstacles, false)
	var best := _nearest_placement(houses, target)
	return _clear_door_anchor(layout, best, obstacles)


static func _market_anchor(
	layout: VillageLayout, obstacles: Array[NpcRouteGraph.Obstacle]
) -> Vector2:
	var stalls := layout.get_placements_of_kind(VillageLayout.KIND_STALL)
	if stalls.is_empty():
		return _find_clear_anchor(layout, Vector2(8.0, 10.0), obstacles, false)
	var center := Vector2.ZERO
	for stall in stalls:
		center += stall.position
	center /= float(stalls.size())
	var toward_plaza := (Vector2.ZERO - center).normalized()
	return _find_clear_anchor(
		layout, center + toward_plaza * 4.0, obstacles, false
	)


static func _nearest_placement(
	placements: Array[VillageLayout.Placement], target: Vector2
) -> VillageLayout.Placement:
	var best: VillageLayout.Placement = null
	var best_distance := INF
	for placement in placements:
		var distance := placement.position.distance_to(target)
		if distance < best_distance:
			best_distance = distance
			best = placement
	return best


static func _door_anchor(layout: VillageLayout, placement: VillageLayout.Placement) -> Vector2:
	var nearest := _nearest_road_point(layout, placement.position)
	var outward := (nearest - placement.position).normalized()
	if outward.length_squared() < 0.0001:
		outward = Vector2(0.0, -1.0)
	var distance := placement.footprint_radius * placement.scale + 2.1
	var anchor := placement.position + outward * distance
	var limit := layout.half_extent - 3.0
	return Vector2(
		clampf(anchor.x, -limit, limit), clampf(anchor.y, -limit, limit)
	)


## Door anchor with a walkability check: the straight offset from a building
## can land inside a cart, a fence or a tree, so the anchor is nudged to the
## clearest nearby point. Deterministic, like every other anchor.
static func _clear_door_anchor(
	layout: VillageLayout,
	placement: VillageLayout.Placement,
	obstacles: Array[NpcRouteGraph.Obstacle]
) -> Vector2:
	if placement == null:
		return Vector2.ZERO
	return _find_clear_anchor(layout, _door_anchor(layout, placement), obstacles, false)


static func _nearest_road_point(layout: VillageLayout, point: Vector2) -> Vector2:
	var best := point
	var best_distance := INF
	for road in layout.roads:
		for index in maxi(road.size() - 1, 0):
			var closest := _closest_on_segment(point, road[index], road[index + 1])
			var distance := point.distance_to(closest)
			if distance < best_distance:
				best_distance = distance
				best = closest
	return best


static func _closest_on_segment(point: Vector2, start: Vector2, end: Vector2) -> Vector2:
	var span := end - start
	var length_sq := span.length_squared()
	if length_sq <= 0.0001:
		return start
	var t := clampf((point - start).dot(span) / length_sq, 0.0, 1.0)
	return start + span * t


## Finds a point near [param desired] with as much obstacle clearance as
## possible. Sampling is fixed (rings and eight directions), so the result is
## deterministic and can be asserted by a test.
static func _find_clear_anchor(
	layout: VillageLayout,
	desired: Vector2,
	obstacles: Array[NpcRouteGraph.Obstacle],
	avoid_water: bool
) -> Vector2:
	var best := desired
	var best_score := -INF
	var limit := layout.half_extent - 4.0
	for ring in ANCHOR_RINGS:
		var radius := float(ring) * ANCHOR_STEP
		var directions := 1 if ring == 0 else ANCHOR_DIRECTIONS
		for direction_index in directions:
			var angle := TAU * float(direction_index) / float(ANCHOR_DIRECTIONS)
			var candidate := desired + Vector2(cos(angle), sin(angle)) * radius
			if absf(candidate.x) > limit or absf(candidate.y) > limit:
				continue
			if avoid_water:
				if candidate.distance_to(layout.pond_center) < layout.pond_radius + 1.4:
					continue
			var clearance := _clearance(candidate, obstacles)
			var score := clearance - float(ring) * 0.15
			if score > best_score:
				best_score = score
				best = candidate
	return best


static func _clearance(
	point: Vector2, obstacles: Array[NpcRouteGraph.Obstacle]
) -> float:
	var best := INF
	for obstacle in obstacles:
		best = minf(best, point.distance_to(obstacle.position) - obstacle.radius)
	return best


static func _obstacle_radius(placement: VillageLayout.Placement) -> float:
	var scale: float = placement.scale
	match placement.kind:
		VillageLayout.KIND_HOUSE, VillageLayout.KIND_INN, VillageLayout.KIND_HALL, \
				VillageLayout.KIND_WELL, VillageLayout.KIND_STALL:
			return placement.footprint_radius * scale * 0.9
		VillageLayout.KIND_CART, VillageLayout.KIND_CRATE, VillageLayout.KIND_BARREL, \
				VillageLayout.KIND_LOGPILE:
			return placement.footprint_radius * scale * 0.8
		VillageLayout.KIND_TREE_PINE, VillageLayout.KIND_TREE_OAK, VillageLayout.KIND_TREE_BIRCH:
			return 1.0 * scale
		VillageLayout.KIND_BUSH:
			return 0.55 * scale
		VillageLayout.KIND_ROCK:
			return placement.footprint_radius * scale * 0.8
		VillageLayout.KIND_LAMP:
			return 0.35 * scale
		VillageLayout.KIND_FENCE:
			return 0.25 * scale
		VillageLayout.KIND_SIGNPOST:
			return 0.3 * scale
		_:
			return 0.0


static func _sorted_by_distance(
	placements: Array[VillageLayout.Placement], center: Vector2
) -> Array[VillageLayout.Placement]:
	var result: Array[VillageLayout.Placement] = placements.duplicate()
	# Insertion sort: tiny arrays, and it keeps ties in generation order, which
	# is part of the deterministic contract.
	for index in range(1, result.size()):
		var current := result[index]
		var cursor := index - 1
		while cursor >= 0 and _is_closer(current, result[cursor], center):
			result[cursor + 1] = result[cursor]
			cursor -= 1
		result[cursor + 1] = current
	return result


static func _is_closer(
	first: VillageLayout.Placement,
	second: VillageLayout.Placement,
	center: Vector2
) -> bool:
	return first.position.distance_to(center) < second.position.distance_to(center)
