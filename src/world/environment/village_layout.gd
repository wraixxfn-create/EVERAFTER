class_name VillageLayout
extends RefCounted
## The plan of the starting village: where the ground is flat, where the roads
## run, and what stands where.
##
## This is the spine of the world. It is pure data with no nodes, which buys
## three things:
## * **determinism** — the same seed always rebuilds the identical village, on
##   every machine, because every random choice comes from a seeded
##   [RandomNumberGenerator] consumed in a fixed order;
## * **one source of truth** — `TerrainGenerator` flattens the ground using this
##   plan, `VillageBuilder` places props using the same plan, and `AreaRegistry`
##   names the same places. Nothing can disagree with anything else;
## * **testability** — the layout can be asserted headless, without a GPU, so a
##   house standing in the middle of a road is caught by a test and not by a
##   player walking into it.
##
## The world is a square of `2 * half_extent` units centred on the origin. The
## plaza sits at the origin; three roads leave it; the forest closes in towards
## the border.

## Kinds understood by `BuildingFactory`.
const KIND_HOUSE := "house"
const KIND_INN := "inn"
const KIND_HALL := "hall"
const KIND_WELL := "well"
const KIND_STALL := "stall"
const KIND_LAMP := "lamp"
const KIND_FENCE := "fence"
const KIND_CART := "cart"
const KIND_CRATE := "crate"
const KIND_BARREL := "barrel"
const KIND_LOGPILE := "logpile"
const KIND_SIGNPOST := "signpost"
## Kinds understood by `VegetationBuilder`.
const KIND_TREE_PINE := "tree_pine"
const KIND_TREE_OAK := "tree_oak"
const KIND_TREE_BIRCH := "tree_birch"
const KIND_BUSH := "bush"
const KIND_ROCK := "rock"

## Kinds that level the ground around themselves, so a building never ends up
## half buried in a slope or floating above it.
const GROUND_LEVELLING_KINDS := [
	KIND_HOUSE, KIND_INN, KIND_HALL, KIND_WELL, KIND_STALL, KIND_CART, KIND_LOGPILE
]
## Kinds that must never stand on a road. Lamps and fences are excluded because
## they are placed right at the kerb on purpose.
const ROAD_CLEARING_KINDS := [
	KIND_HOUSE, KIND_INN, KIND_HALL, KIND_WELL, KIND_STALL, KIND_CART, KIND_CRATE,
	KIND_BARREL, KIND_LOGPILE, KIND_SIGNPOST, KIND_TREE_PINE, KIND_TREE_OAK,
	KIND_TREE_BIRCH, KIND_BUSH, KIND_ROCK
]

const PLAZA_RADIUS := 11.0
const PLAZA_FALLOFF := 4.5
const ROAD_WIDTH := 3.6
const ROAD_FALLOFF := 2.4
const ROAD_STEP := 17.0
const PLOT_FALLOFF := 2.6
## Compass bearings (degrees, 0 = +X, counter-clockwise in XZ) of the three
## roads leaving the plaza. The plaza ring buildings sit between them.
const ROAD_BEARINGS_DEG := [270.0, 30.0, 150.0]
const POND_RADIUS := 8.5
const POND_DEPTH := 0.085
const POND_FALLOFF := 5.0

## One object to place in the world.
class Placement extends RefCounted:
	var id: String = ""
	var kind: String = ""
	## World XZ position. The Y coordinate is decided by the terrain.
	var position := Vector2.ZERO
	## Yaw in degrees. 0 means the prop faces +Z.
	var rotation_deg: float = 0.0
	## Variant selector interpreted by the factory that builds this kind.
	var variant: int = 0
	var scale: float = 1.0
	## Radius used to reject overlapping placements and to flatten the ground.
	var footprint_radius: float = 2.0

	func _to_string() -> String:
		return "%s(%s at %s)" % [id, kind, position]


var world_seed: int = 0
var half_extent: float = 63.5
var roads: Array[PackedVector2Array] = []
var placements: Array[Placement] = []
var pond_center := Vector2(33.0, -27.0)
var pond_radius: float = POND_RADIUS
## Level of the water surface, in the same units as the terrain height field.
## Computed by `TerrainGenerator` once it knows its height scale.
var water_level: float = 0.0

var _rng := RandomNumberGenerator.new()
var _occupied: Array[Vector2] = []
var _occupied_radius: PackedFloat32Array = PackedFloat32Array()
var _next_id := 0


func _init(initial_seed: int = 0, initial_half_extent: float = 63.5) -> void:
	world_seed = initial_seed
	half_extent = maxf(initial_half_extent, PLAZA_RADIUS * 3.0)
	_rng.seed = initial_seed
	_build_roads()
	_build_plaza_landmarks()
	_build_road_plots()
	_build_road_details()
	_build_pond()
	_build_field_fence()
	_build_forest()
	_build_scatter()


# --- queries -----------------------------------------------------------------


## Every placement of a given kind, in generation order.
func get_placements_of_kind(kind: String) -> Array[Placement]:
	var result: Array[Placement] = []
	for placement in placements:
		if placement.kind == kind:
			result.append(placement)
	return result


func get_placement_count() -> int:
	return placements.size()


func find_placement(placement_id: String) -> Placement:
	for placement in placements:
		if placement.id == placement_id:
			return placement
	return null


## 1.0 on the plaza and on the roads, 0.0 in open country. `TerrainGenerator`
## multiplies the *detail* octaves by `1 - weight`, so paths stay walkable
## without digging a flat trench through the hills.
func flatten_weight(world_x: float, world_z: float) -> float:
	var weight := plaza_weight(world_x, world_z)
	weight = maxf(weight, road_weight(world_x, world_z))
	var point := Vector2(world_x, world_z)
	for index in placements.size():
		if not GROUND_LEVELLING_KINDS.has(placements[index].kind):
			continue
		var distance := point.distance_to(placements[index].position)
		var radius: float = placements[index].footprint_radius
		weight = maxf(weight, 1.0 - clampf((distance - radius) / PLOT_FALLOFF, 0.0, 1.0))
	return weight


## 1.0 at the centre of the plaza, fading to 0.0 past its rim.
func plaza_weight(world_x: float, world_z: float) -> float:
	var distance := Vector2(world_x, world_z).length()
	return 1.0 - clampf((distance - PLAZA_RADIUS) / PLAZA_FALLOFF, 0.0, 1.0)


## 1.0 on a road, 0.0 away from every road.
func road_weight(world_x: float, world_z: float) -> float:
	var distance := road_distance(world_x, world_z)
	return 1.0 - clampf((distance - ROAD_WIDTH * 0.5) / ROAD_FALLOFF, 0.0, 1.0)


## Shortest distance from a point to any road centre line.
func road_distance(world_x: float, world_z: float) -> float:
	var point := Vector2(world_x, world_z)
	return distance_to_roads(point)


## Shortest distance from a point to any road centre line.
func distance_to_roads(point: Vector2) -> float:
	var best := INF
	for road in roads:
		for index in road.size() - 1:
			best = minf(
				best, AreaRegistry.distance_to_segment(point, road[index], road[index + 1])
			)
	return best


## 1.0 inside the pond, 0.0 outside its basin.
func pond_weight(world_x: float, world_z: float) -> float:
	var distance := Vector2(world_x, world_z).distance_to(pond_center)
	return 1.0 - clampf((distance - pond_radius * 0.55) / (pond_radius * 0.6), 0.0, 1.0)


## Basin depth at a point, as a fraction of the terrain height scale. Negative,
## so `TerrainGenerator` simply adds it.
func terrain_offset(world_x: float, world_z: float) -> float:
	return -POND_DEPTH * _smoothstep(pond_weight(world_x, world_z))


## True where the player walks on level, built ground.
func is_built_ground(world_x: float, world_z: float) -> bool:
	return plaza_weight(world_x, world_z) > 0.5 or road_weight(world_x, world_z) > 0.5


## Named regions derived from this very plan, so the HUD, the map and any future
## system agree on what "the market" means.
func build_area_registry() -> AreaRegistry:
	var registry := AreaRegistry.new()
	registry.add_circle("Piazza del Pozzo", Vector2.ZERO, PLAZA_RADIUS + 2.0, 5)
	var road_names := ["Via del Nord", "Via del Mercato", "Sentiero dello Stagno"]
	for index in roads.size():
		registry.add_area(
			road_names[index % road_names.size()], roads[index], ROAD_WIDTH + 2.0, 2
		)
	registry.add_circle("Stagno delle Anatre", pond_center, pond_radius + 3.0, 4)
	for placement in placements:
		match placement.kind:
			KIND_INN:
				registry.add_circle("Locanda del Cervo Bianco", placement.position, 10.0, 8)
			KIND_HALL:
				registry.add_circle("Sala del Consiglio", placement.position, 10.0, 8)
	registry.add_area(
		"Bosco di Ontano",
		PackedVector2Array([Vector2(0.0, -half_extent * 0.55), Vector2(0.0, -half_extent * 0.95)]),
		half_extent * 0.75,
		1
	)
	return registry


## Point at [param distance] units along a road, measured from the plaza.
## Used for the player spawn and by the tests, so both stand on the same ground.
func point_on_road(road_index: int, distance: float) -> Vector2:
	if roads.is_empty():
		return Vector2.ZERO
	var road := roads[posmod(road_index, roads.size())]
	var travelled := 0.0
	for index in road.size() - 1:
		var start: Vector2 = road[index]
		var end: Vector2 = road[index + 1]
		var length := start.distance_to(end)
		if travelled + length >= distance:
			var t := (distance - travelled) / maxf(length, 0.0001)
			return start.lerp(end, clampf(t, 0.0, 1.0))
		travelled += length
	return road[road.size() - 1]


## Total flat, built area as a fraction of the terrain: a crude but honest
## measure of how much of the map the player can actually use.
func built_ground_coverage(sample_step: float = 4.0) -> float:
	var samples := 0
	var built := 0
	var position := -half_extent
	while position <= half_extent:
		var other := -half_extent
		while other <= half_extent:
			samples += 1
			if is_built_ground(position, other):
				built += 1
			other += sample_step
		position += sample_step
	if samples == 0:
		return 0.0
	return float(built) / float(samples)


# --- generation --------------------------------------------------------------


func _build_roads() -> void:
	for bearing in ROAD_BEARINGS_DEG:
		var direction := Vector2(cos(deg_to_rad(bearing)), sin(deg_to_rad(bearing)))
		var side := Vector2(-direction.y, direction.x)
		var points := PackedVector2Array([direction * (PLAZA_RADIUS - 2.0)])
		var distance := PLAZA_RADIUS
		var offset := 0.0
		while distance < half_extent - 6.0:
			distance += ROAD_STEP
			offset = clampf(offset + _rng.randf_range(-4.5, 4.5), -11.0, 11.0)
			points.append(direction * distance + side * offset)
		roads.append(points)


func _build_plaza_landmarks() -> void:
	_add_placement(KIND_WELL, Vector2.ZERO, 0.0, 0, 1.0, 2.6)
	# The three ring buildings sit between the roads, facing the plaza centre.
	_add_ring(KIND_INN, 90.0, 17.5, 0, 1.0, 6.0)
	_add_ring(KIND_HALL, 210.0, 18.5, 0, 1.0, 6.5)
	_add_ring(KIND_HOUSE, 330.0, 15.5, 0, 1.0, 3.6)
	_add_ring(KIND_HOUSE, 5.0, 16.0, 1, 1.0, 3.6)
	# Market row: stalls on the plaza rim, away from the road mouths.
	_add_ring(KIND_STALL, 52.0, 14.0, 0, 1.0, 2.4)
	_add_ring(KIND_STALL, 66.0, 14.6, 1, 1.0, 2.4)
	_add_ring(KIND_STALL, 122.0, 14.2, 2, 1.0, 2.4)
	_add_ring(KIND_SIGNPOST, 178.0, 12.4, 0, 1.0, 1.0)
	_add_ring(KIND_BARREL, 96.0, 13.6, 0, 1.0, 0.8)
	_add_ring(KIND_CRATE, 101.0, 13.9, 1, 1.0, 0.9)


## Houses along the roads, alternating sides, always facing the road.
func _build_road_plots() -> void:
	for road in roads:
		var side := 1.0
		for index in road.size() - 1:
			var start: Vector2 = road[index]
			var end: Vector2 = road[index + 1]
			var span := end - start
			if span.length() < 4.0:
				continue
			var along := span.normalized()
			var outward := Vector2(-along.y, along.x) * side
			side = -side
			for fraction in [0.32, 0.72]:
				var at := start + span * float(fraction)
				var depth := _rng.randf_range(3.4, 5.0)
				var position := at + outward * (ROAD_WIDTH * 0.5 + depth * 0.5 + 1.6)
				if position.length() > half_extent - 10.0:
					continue
				var faces_road := rad_to_deg(
					atan2(at.x - position.x, at.y - position.y)
				)
				var kind := KIND_HOUSE
				if _rng.randf() < 0.22:
					kind = KIND_LOGPILE
				_add_placement(
					kind,
					position,
					faces_road + _rng.randf_range(-6.0, 6.0),
					_rng.randi_range(0, 2),
					_rng.randf_range(0.85, 1.25),
					depth * 0.9
				)


func _build_road_details() -> void:
	for road in roads:
		var side := 1.0
		for index in road.size() - 1:
			var start: Vector2 = road[index]
			var end: Vector2 = road[index + 1]
			var span := end - start
			if span.length() < 4.0:
				continue
			var along := span.normalized()
			var outward := Vector2(-along.y, along.x)
			side = -side
			var position := start + span * 0.5 + outward * (ROAD_WIDTH * 0.5 + 1.1) * side
			if position.length() > half_extent - 8.0:
				continue
			_add_placement(KIND_LAMP, position, 0.0, 0, 1.0, 0.7)
			if _rng.randf() < 0.3:
				var near := start + span * 0.15 - outward * (ROAD_WIDTH * 0.5 + 1.3) * side
				_add_placement(
					KIND_CART if _rng.randf() < 0.5 else KIND_BARREL,
					near,
					_rng.randf_range(0.0, 360.0),
					_rng.randi_range(0, 1),
					_rng.randf_range(0.9, 1.1),
					1.4
				)


func _build_pond() -> void:
	# Reeds and stones around the water: no collider, so the shore stays open.
	for index in 14:
		var angle := _rng.randf() * TAU
		var distance := pond_radius * _rng.randf_range(0.95, 1.35)
		var position := pond_center + Vector2(cos(angle), sin(angle)) * distance
		_add_placement(
			KIND_BUSH if index % 3 == 0 else KIND_ROCK,
			position,
			_rng.randf_range(0.0, 360.0),
			index % 3,
			_rng.randf_range(0.5, 1.0),
			0.8
		)


func _build_field_fence() -> void:
	# A fenced paddock south-east of the plaza: reads as "farmland" at a glance.
	var corner := Vector2(-28.0, 22.0)
	var direction := Vector2(1.0, 0.16).normalized()
	for index in 9:
		var position := corner + direction * float(index) * 3.0
		_add_placement(
			KIND_FENCE, position, rad_to_deg(atan2(direction.x, direction.y)), 0, 1.0, 1.5
		)
	var turn := Vector2(-direction.y, direction.x)
	for index in 5:
		var position := corner + direction * 24.0 + turn * float(index + 1) * 3.0
		_add_placement(
			KIND_FENCE, position, rad_to_deg(atan2(turn.x, turn.y)), 0, 1.0, 1.5
		)


func _build_forest() -> void:
	var target := int(half_extent * 3.2)
	var placed := 0
	var attempts := 0
	while placed < target and attempts < target * 12:
		attempts += 1
		var angle := _rng.randf() * TAU
		# Trees crowd the border and thin out towards the village.
		var distance := lerpf(half_extent * 0.62, half_extent * 1.02, pow(_rng.randf(), 0.7))
		var position := Vector2(cos(angle), sin(angle)) * distance
		if absf(position.x) > half_extent - 3.0 or absf(position.y) > half_extent - 3.0:
			continue
		if _overlaps(position, 2.6):
			continue
		var roll := _rng.randf()
		var kind := KIND_TREE_OAK
		if roll < 0.42:
			kind = KIND_TREE_PINE
		elif roll < 0.58:
			kind = KIND_TREE_BIRCH
		_add_placement(
			kind,
			position,
			_rng.randf_range(0.0, 360.0),
			_rng.randi_range(0, 2),
			_rng.randf_range(0.75, 1.35),
			1.6
		)
		placed += 1
	# Shrubs filling the edge between the fields and the wood.
	for index in int(half_extent * 0.7):
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(half_extent * 0.42, half_extent * 0.72)
		var position := Vector2(cos(angle), sin(angle)) * distance
		if _overlaps(position, 1.6):
			continue
		_add_placement(
			KIND_BUSH,
			position,
			_rng.randf_range(0.0, 360.0),
			_rng.randi_range(0, 2),
			_rng.randf_range(0.7, 1.4),
			1.0
		)


func _build_scatter() -> void:
	# A few lone trees and rocks inside the village so it does not read as a
	# bare stage set, plus boulders out in the fields.
	for index in 26:
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(PLAZA_RADIUS + 6.0, half_extent * 0.55)
		var position := Vector2(cos(angle), sin(angle)) * distance
		if _overlaps(position, 3.0):
			continue
		var kind := KIND_TREE_OAK if index % 4 != 0 else KIND_ROCK
		_add_placement(
			kind,
			position,
			_rng.randf_range(0.0, 360.0),
			_rng.randi_range(0, 2),
			_rng.randf_range(0.8, 1.25),
			1.8
		)


# --- helpers -----------------------------------------------------------------


## Places a prop at a bearing from the plaza centre, facing the centre.
func _add_ring(
	kind: String, bearing_deg: float, radius: float, variant: int, scale: float, footprint: float
) -> void:
	var bearing := deg_to_rad(bearing_deg)
	var position := Vector2(cos(bearing), sin(bearing)) * radius
	# Yaw so that the prop's +Z faces the plaza centre.
	var yaw := rad_to_deg(atan2(-position.x, -position.y))
	_add_placement(kind, position, yaw, variant, scale, footprint)


func _add_placement(
	kind: String,
	position: Vector2,
	rotation_deg: float,
	variant: int,
	scale: float,
	footprint_radius: float
) -> void:
	if absf(position.x) > half_extent - 2.0 or absf(position.y) > half_extent - 2.0:
		return
	var extent := footprint_radius * scale
	if _overlaps(position, extent):
		return
	if ROAD_CLEARING_KINDS.has(kind):
		# Keep the carriageway walkable.
		if distance_to_roads(position) < ROAD_WIDTH * 0.5 + extent * 0.6:
			return
		# Nothing taller than a shrub may stand in the water.
		if kind != KIND_BUSH and kind != KIND_ROCK and pond_weight(position.x, position.y) > 0.2:
			return
	var placement := Placement.new()
	_next_id += 1
	placement.id = "%s_%03d" % [kind, _next_id]
	placement.kind = kind
	placement.position = position
	placement.rotation_deg = fposmod(rotation_deg, 360.0)
	placement.variant = variant
	placement.scale = scale
	placement.footprint_radius = footprint_radius
	placements.append(placement)
	_occupied.append(position)
	_occupied_radius.append(footprint_radius * scale)


## Simple O(n) rejection: good enough for a few hundred props and, unlike a
## spatial hash, trivially deterministic.
func _overlaps(position: Vector2, radius: float) -> bool:
	for index in _occupied.size():
		var clearance: float = _occupied_radius[index]
		if position.distance_to(_occupied[index]) < (radius + clearance) * 0.92:
			return true
	return false


func _smoothstep(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
