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
## Decorative furnishings: standing planters and benches. Pure scenery — no
## collider, no NPC obstacle — so they can dress a square or a shore without
## ever blocking a walk.
const KIND_FLOWER_BOX := "flower_box"
const KIND_BENCH := "bench"
## Kinds understood by `VegetationBuilder`.
const KIND_TREE_PINE := "tree_pine"
const KIND_TREE_OAK := "tree_oak"
const KIND_TREE_BIRCH := "tree_birch"
const KIND_BUSH := "bush"
const KIND_ROCK := "rock"
## Visual polish 16 — meadow flowers are their own placement kind, not a
## decoration painted on the grass. They are baked vegetation (stems, low
## leaves and heads), so they survive the walk, cast no separate draw call and
## can be kept out of roads and doorways by the same rules as every other plant.
const KIND_FLOWER_PATCH := "flower_patch"

## Every kind handled by `VegetationBuilder` instead of `BuildingFactory`.
const VEGETATION_KINDS := [
	KIND_TREE_PINE, KIND_TREE_OAK, KIND_TREE_BIRCH, KIND_BUSH, KIND_ROCK,
	KIND_FLOWER_PATCH
]
const TREE_KINDS := [KIND_TREE_PINE, KIND_TREE_OAK, KIND_TREE_BIRCH]


static func is_vegetation(kind: String) -> bool:
	return VEGETATION_KINDS.has(kind)

## Buildings with a doorway on their +Z face. `BuildingFactory.is_structure()`
## stays the authority on what gets its own node; this list only says which
## placements cast a door corridor that nothing may stand in.
const DOOR_BUILDING_KINDS := [KIND_HOUSE, KIND_INN, KIND_HALL]

## Kinds that level the ground around themselves, so a building never ends up
## half buried in a slope or floating above it.
const GROUND_LEVELLING_KINDS := [
	KIND_HOUSE, KIND_INN, KIND_HALL, KIND_WELL, KIND_STALL, KIND_CART, KIND_LOGPILE
]
## Kinds that must never stand on a road. Lamps and fences are excluded because
## they are placed right at the kerb on purpose.
const ROAD_CLEARING_KINDS := [
	KIND_HOUSE, KIND_INN, KIND_HALL, KIND_WELL, KIND_STALL, KIND_CART, KIND_CRATE,
	KIND_BARREL, KIND_LOGPILE, KIND_SIGNPOST, KIND_FLOWER_BOX, KIND_BENCH,
	KIND_TREE_PINE, KIND_TREE_OAK, KIND_TREE_BIRCH, KIND_BUSH, KIND_ROCK,
	KIND_FLOWER_PATCH
]

const PLAZA_RADIUS := 11.0
const PLAZA_FALLOFF := 4.5
const ROAD_WIDTH := 3.6
## Half width of the doorway corridor in front of a building: nothing may stand
## in it, so doors, stoops and paths to the road stay open for the player and
## for the NPC door anchors.
const DOOR_CORRIDOR_HALF_WIDTH := 1.5
## How far past a building's footprint the door corridor is kept clear.
const DOOR_CORRIDOR_REACH := 1.5
## Visual polish 16 — a tree is not a crate: it may not stand just outside the
## door corridor either, because a trunk two metres to the side still hides the
## door from the road. Tall vegetation therefore keeps a longer, wider sightline
## in front of every entrance. Low shrubs keep the shorter corridor.
const TREE_DOOR_SIGHTLINE := 3.2
const TREE_DOOR_EXTRA_WIDTH := 0.9
## Extra verge between a tree trunk and the carriageway. Without it the forest
## closed over the roads and the paths stopped reading from inside the village.
const TREE_ROAD_VERGE := 1.0
## Half a fence is 1.5 m long; the extra margin keeps the gate wider than the
## fence module so a 0.4 m player capsule and a 0.42 m NPC never clip a post.
const FENCE_GATE_MARGIN := 1.6
const ROAD_FALLOFF := 2.4
## Visual polish 15 — the road is sampled as a smooth curve, not as a chain of
## 17 m chords with a random kink at every joint. Three metres is short enough
## that the terrain, the collision and the paving ribbon follow the same line
## invisibly, and long enough that the height field still costs little to query.
const ROAD_SAMPLE_STEP := 3.0
## Long, low-amplitude meander: a road that wanders because the land does,
## instead of the old random walk that read as a zigzag of straight sticks.
const ROAD_MEANDER := 2.0
const ROAD_MEANDER_WAVELENGTH := 44.0
## Slower drift across the map, so each road has its own broad bend.
const ROAD_DRIFT := 3.0
const ROAD_DRIFT_WAVELENGTH := 168.0
## Distance over which a road leaves the plaza radially and starts to bend.
## Keeping the mouth straight is what makes the three entrances read as a
## composed square instead of three lines arriving at random angles.
const ROAD_MOUTH_BLEND := 24.0
## House plots are spaced by travelled distance now that a road is a dense
## polyline: one plot every nine metres, never on consecutive segments.
const ROAD_PLOT_SPACING := 9.0
const ROAD_PLOT_START := 16.0
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
## Open glades kept inside the tree ring. Exposed so the suite can prove the
## clearings exist rather than trusting the placement loop.
var forest_clearings: Array[Vector2] = []
## Level of the water surface, in the same units as the terrain height field.
## Computed by `TerrainGenerator` once it knows its height scale.
var water_level: float = 0.0

var _rng := RandomNumberGenerator.new()
## Bounding rectangle of every road (grown by the widest query threshold). A
## point outside a road's rectangle cannot be near it, so a distance query skips
## its segments entirely: with the dense curves of visual polish 15 this keeps
## the terrain paint pass as cheap as it was with coarse polylines.
var _road_bounds: Array[Rect2] = []
var _occupied: Array[Vector2] = []
var _occupied_radius: PackedFloat32Array = PackedFloat32Array()
var _next_id := 0


func _init(initial_seed: int = 0, initial_half_extent: float = 63.5) -> void:
	world_seed = initial_seed
	half_extent = maxf(initial_half_extent, PLAZA_RADIUS * 3.0)
	_rng.seed = initial_seed
	_build_roads()
	_cache_road_bounds()
	_build_plaza_landmarks()
	_build_road_plots()
	_build_homestead_details()
	_build_road_details()
	_build_pond()
	_build_field_fence()
	_build_forest()
	_build_scatter()
	_build_meadow_flowers()


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
	for road_index in roads.size():
		if road_index < _road_bounds.size() and not _road_bounds[road_index].has_point(point):
			continue
		var road := roads[road_index]
		for index in road.size() - 1:
			best = minf(
				best, AreaRegistry.distance_to_segment(point, road[index], road[index + 1])
			)
	return best


## Caches one grown rectangle per road. The margin is larger than every
## distance threshold used by the layout, the terrain and the nav graph, so a
## skipped road can only be reported as "far away", never as "at the threshold".
func _cache_road_bounds() -> void:
	_road_bounds.clear()
	for road in roads:
		if road.is_empty():
			_road_bounds.append(Rect2())
			continue
		var bounds := Rect2(road[0], Vector2.ZERO)
		for index in road.size() - 1:
			bounds = bounds.expand(road[index + 1])
		_road_bounds.append(bounds.grow(14.0))


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


## Visual polish 15: roads are continuous low-frequency curves.
##
## The previous generator advanced 17 m along a bearing and then applied an
## independent random sideways offset, so every joint was a visible knee and
## the village was ringed by three broken sticks. This version evaluates two
## long sine terms — a 44 m meander and a 168 m drift — and fades them in over
## the first 24 m so each road still leaves the square radially. The result is
## deterministic, has a bounded heading (no hairpins), and costs one sin per
## sample instead of a random walk whose shape depended on the previous step.
func _build_roads() -> void:
	var end_distance := half_extent - 6.0
	for bearing in ROAD_BEARINGS_DEG:
		var direction := Vector2(cos(deg_to_rad(bearing)), sin(deg_to_rad(bearing)))
		var side := Vector2(-direction.y, direction.x)
		var meander_phase := _rng.randf_range(0.0, TAU)
		var drift_phase := _rng.randf_range(0.0, TAU)
		var meander_scale := _rng.randf_range(0.62, 1.0)
		var drift_scale := _rng.randf_range(-1.0, 1.0)
		var points := PackedVector2Array()
		var cursor := PLAZA_RADIUS - 2.0
		while true:
			var along := minf(cursor, end_distance)
			var mouth := _smoothstep(
				clampf((along - PLAZA_RADIUS) / ROAD_MOUTH_BLEND, 0.0, 1.0)
			)
			var offset := meander_scale * ROAD_MEANDER * mouth * sin(
				along / ROAD_MEANDER_WAVELENGTH * TAU + meander_phase
			)
			offset += drift_scale * ROAD_DRIFT * mouth * sin(
				along / ROAD_DRIFT_WAVELENGTH * TAU + drift_phase
			)
			points.append(direction * along + side * offset)
			# Stop exactly on the border, so the road comes out of the valley
			# instead of ending wherever the last 3 m step happened to land.
			if along >= end_distance:
				break
			cursor = minf(cursor + ROAD_SAMPLE_STEP, end_distance)
		roads.append(points)


func _build_plaza_landmarks() -> void:
	_add_placement(KIND_WELL, Vector2.ZERO, 0.0, 0, 1.0, 2.6)
	# The three ring buildings sit between the roads, facing the plaza centre.
	_add_ring(KIND_INN, 90.0, 17.5, 0, 1.0, 6.0)
	_add_ring(KIND_HALL, 210.0, 18.5, 0, 1.0, 6.5)
	_add_ring(KIND_HOUSE, 330.0, 15.5, 0, 1.0, 3.6)
	_add_ring(KIND_HOUSE, 5.0, 16.0, 1, 1.0, 3.6)
	# Market row: stalls now distributed across two plaza sectors so the
	# market does not read as a single clump east of the inn — structural
	# composition fix 11: even skyline, more readable from aerial.
	_add_ring(KIND_STALL, 48.0, 14.0, 0, 1.0, 2.4)
	_add_ring(KIND_STALL, 64.0, 14.6, 1, 1.0, 2.4)
	_add_ring(KIND_STALL, 286.0, 14.3, 2, 1.0, 2.4)
	_add_ring(KIND_SIGNPOST, 178.0, 12.4, 0, 1.0, 1.0)
	_add_ring(KIND_BARREL, 108.0, 13.2, 0, 1.0, 0.8)
	_add_ring(KIND_CRATE, 101.0, 13.9, 1, 1.0, 0.9)
	# Street furniture on the open stretches of the rim: two benches facing the
	# well and two planters dressing the market edge and the road to the hall.
	# All four sit between the road mouths, so the carriageways stay open.
	_add_ring(KIND_BENCH, 172.0, 10.6, 0, 1.0, 1.1)
	_add_ring(KIND_BENCH, 252.0, 10.4, 0, 1.0, 1.1)
	_add_ring(KIND_FLOWER_BOX, 58.0, 10.8, 0, 1.0, 0.9)
	_add_ring(KIND_FLOWER_BOX, 135.0, 11.8, 0, 1.0, 0.9)


## Houses along the roads, alternating sides, always facing the road.
##
## Plots are spaced by arc length rather than by polyline segment: the road is
## now a dense curve, and "two houses per segment" would have packed the whole
## verge. Alternating sides and a small along-track jitter keep the row from
## reading as a measured colonnade of identical plots.
func _build_road_plots() -> void:
	for road in roads:
		var length := polyline_length(road)
		var side := 1.0
		var distance := ROAD_PLOT_START
		while distance < length - 4.0:
			var sample := sample_polyline(road, distance + _rng.randf_range(-1.4, 1.4))
			var along: Vector2 = sample.tangent
			var outward := Vector2(-along.y, along.x) * side
			side = -side
			var at: Vector2 = sample.point
			var depth := _rng.randf_range(3.4, 5.0)
			var position := at + outward * (ROAD_WIDTH * 0.5 + depth * 0.5 + 1.6)
			if position.length() <= half_extent - 10.0:
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
			distance += ROAD_PLOT_SPACING + _rng.randf_range(-1.0, 1.6)


## Small yard clutter beside every building: a crate stack by the wall, a
## barrel at the back corner, a log pile for the hearth, an occasional planter.
## Everything is placed on the flanks or behind the building — the door
## corridor on the +Z face is never used, so entrances and the walk to the road
## stay open.
func _build_homestead_details() -> void:
	# Snapshot: the pass appends clutter to `placements`, and a plain for-in
	# would walk those newcomers too.
	for placement in placements.duplicate():
		if not DOOR_BUILDING_KINDS.has(placement.kind):
			continue
		var yaw := deg_to_rad(placement.rotation_deg)
		var facing := Vector2(sin(yaw), cos(yaw))
		var right := Vector2(cos(yaw), -sin(yaw))
		var radius: float = placement.footprint_radius * placement.scale
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var roll := _rng.randf()
		var kind := KIND_CRATE
		if roll < 0.3:
			kind = KIND_BARREL
		elif roll < 0.5:
			kind = KIND_LOGPILE
		elif roll < 0.62:
			kind = KIND_FLOWER_BOX
		var lateral: float = radius + _rng.randf_range(1.0, 2.0)
		var along: float = _rng.randf_range(-0.45, 0.15) * radius
		_add_placement(
			kind,
			placement.position + right * lateral * side + facing * along,
			_rng.randf_range(0.0, 360.0),
			_rng.randi_range(0, 1),
			_rng.randf_range(0.85, 1.1),
			0.9 if kind != KIND_LOGPILE else 1.4
		)
		# A second container at the back: kitchens need somewhere to put things.
		if placement.kind != KIND_HOUSE or _rng.randf() < 0.45:
			var back_kind := KIND_BARREL if _rng.randf() < 0.5 else KIND_CRATE
			var back: float = radius + _rng.randf_range(0.7, 1.6)
			_add_placement(
				back_kind,
				placement.position - facing * back + right * _rng.randf_range(-1.2, 1.2),
				_rng.randf_range(0.0, 360.0),
				_rng.randi_range(0, 1),
				_rng.randf_range(0.85, 1.1),
				0.9
			)


## Street furniture is placed by travelled distance, at an irregular rhythm,
## instead of once per polyline segment (which now would have put a lamp every
## three metres).
func _build_road_details() -> void:
	for road in roads:
		var length := polyline_length(road)
		var side := 1.0
		var distance := 13.0
		while distance < length - 8.0:
			var sample := sample_polyline(road, distance)
			var along: Vector2 = sample.tangent
			var outward := Vector2(-along.y, along.x)
			var at: Vector2 = sample.point
			side = -side
			if _rng.randf() < 0.82:
				var lamp_out := ROAD_WIDTH * 0.5 + _rng.randf_range(0.9, 1.5)
				var position := at + outward * lamp_out * side
				if position.length() <= half_extent - 8.0:
					_add_placement(KIND_LAMP, position, 0.0, 0, 1.0, 0.7)
			if _rng.randf() < 0.3:
				var near := at - outward * (ROAD_WIDTH * 0.5 + 1.3) * side
				near += along * _rng.randf_range(-2.2, 2.2)
				if near.length() <= half_extent - 8.0:
					_add_placement(
						KIND_CART if _rng.randf() < 0.5 else KIND_BARREL,
						near,
						_rng.randf_range(0.0, 360.0),
						_rng.randi_range(0, 1),
						_rng.randf_range(0.9, 1.1),
						1.4
					)
			distance += _rng.randf_range(19.0, 27.0)


func _build_pond() -> void:
	# The bench first, so the shore dressing around it is placed *around* it
	# instead of on top of it. It faces the water and is nudged sideways off
	# the line between the pond and the plaza, where the NPC shore anchor is,
	# so nobody stands inside the seat.
	var shore_dir := (Vector2.ZERO - pond_center).normalized()
	var bank := pond_center + shore_dir * (pond_radius + 3.2)
	var alongshore := Vector2(-shore_dir.y, shore_dir.x)
	bank += alongshore * 3.5
	_add_placement(
		KIND_BENCH,
		bank,
		rad_to_deg(atan2(pond_center.x - bank.x, pond_center.y - bank.y)),
		0, 1.0, 1.1
	)
	# Two planters flanking the seat: a small shore terrace, and the guaranteed
	# standing greenery of the village (the plaza pair is the other half).
	for side in [-1.0, 1.0]:
		_add_placement(
			KIND_FLOWER_BOX,
			bank + alongshore * 2.6 * side + shore_dir * 0.9,
			_rng.randf_range(0.0, 360.0),
			0, 1.0, 0.9
		)
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
	# Pebbles at the water line: the small stones the shore is missing between
	# the bigger rocks, all walkable, all under the knee.
	for index in 8:
		var angle := _rng.randf() * TAU
		var distance := pond_radius * _rng.randf_range(0.85, 1.15)
		var position := pond_center + Vector2(cos(angle), sin(angle)) * distance
		_add_placement(
			KIND_ROCK, position, _rng.randf_range(0.0, 360.0), _rng.randi_range(0, 1),
			_rng.randf_range(0.32, 0.5), 0.5
		)


func _build_field_fence() -> void:
	# A fenced paddock south-east of the plaza: reads as "farmland" at a glance.
	# The road to the fields runs through the paddock, so the posts that would
	# barricade the carriageway are skipped: the gap is the gate the farmers
	# (and the player) walk through. Without it a 3 m fence box would cut the
	# only road to `work_field` and the fields would be unreachable.
	var corner := Vector2(-28.0, 22.0)
	var direction := Vector2(1.0, 0.16).normalized()
	var gate_clearance := ROAD_WIDTH * 0.5 + FENCE_GATE_MARGIN
	for index in 9:
		var position := corner + direction * float(index) * 3.0
		if distance_to_roads(position) < gate_clearance:
			continue
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
	var target := int(half_extent * 3.4)
	# Three glades first: real openings the player can walk into. They are what
	# keeps the tree line from reading as a wall around the map, and they are
	# stored so the suite can prove the clearings really stayed clear.
	forest_clearings.clear()
	var clearing_phase := _rng.randf() * TAU
	for index in 3:
		var angle := (
			clearing_phase + TAU * float(index) / 3.0 + _rng.randf_range(-0.30, 0.30)
		)
		var distance := lerpf(half_extent * 0.66, half_extent * 0.88, _rng.randf())
		forest_clearings.append(Vector2(cos(angle), sin(angle)) * distance)
	var density_phase := _rng.randf() * TAU
	var placed := 0
	var attempts := 0
	while placed < target and attempts < target * 14:
		attempts += 1
		var angle := _rng.randf() * TAU
		# Trees crowd the border and thin out towards the village. A slow density
		# wave and a radial wobble remove both the perfectly circular edge and
		# the evenly spaced ring that the previous polar scatter produced.
		var distance := lerpf(half_extent * 0.60, half_extent * 1.02, pow(_rng.randf(), 0.7))
		distance += sin(angle * 4.0 + density_phase) * half_extent * 0.022
		var position := Vector2(cos(angle), sin(angle)) * distance
		if absf(position.x) > half_extent - 3.0 or absf(position.y) > half_extent - 3.0:
			continue
		if _in_forest_clearing(position, 1.2):
			continue
		var density := 0.55 + 0.45 * (0.5 + 0.5 * sin(angle * 3.0 + density_phase * 0.8))
		if _rng.randf() > density:
			continue
		if _overlaps(position, 2.6):
			continue
		# Species grow in belts, not as a confetti of needles and leaves: a slow
		# angular wave decides which stand a tree belongs to, with a little
		# mixing at the seams.
		var stand := 0.5 + 0.5 * sin(angle * 2.0 + density_phase * 1.3)
		var kind := KIND_TREE_OAK
		if stand > 0.64:
			kind = KIND_TREE_PINE
		elif stand < 0.22:
			kind = KIND_TREE_BIRCH
		if _rng.randf() < 0.20:
			kind = [KIND_TREE_OAK, KIND_TREE_PINE, KIND_TREE_BIRCH][_rng.randi_range(0, 2)]
		var before := placements.size()
		_add_placement(
			kind,
			position,
			_rng.randf_range(0.0, 360.0),
			_rng.randi_range(0, 2),
			_rng.randf_range(0.72, 1.32),
			1.6
		)
		if placements.size() > before:
			placed += 1
	# A few tight groves inside the ring: real woods grow in knots of one
	# species, elliptical rather than on a compass circle.
	for grove in 3:
		var grove_angle := _rng.randf() * TAU
		var grove_distance := lerpf(half_extent * 0.46, half_extent * 0.6, _rng.randf())
		var grove_center := Vector2(cos(grove_angle), sin(grove_angle)) * grove_distance
		if road_distance(grove_center.x, grove_center.y) < 6.0:
			continue
		if _in_forest_clearing(grove_center, 4.0):
			continue
		var species: String = [KIND_TREE_OAK, KIND_TREE_PINE, KIND_TREE_BIRCH][grove % 3]
		var stretch := Vector2(
			_rng.randf_range(0.75, 1.35), _rng.randf_range(0.75, 1.35)
		)
		for member in _rng.randi_range(3, 5):
			var spread := _rng.randf() * TAU
			var offset := Vector2(cos(spread), sin(spread)) * _rng.randf_range(1.6, 4.2)
			var position := grove_center + offset * stretch
			if absf(position.x) > half_extent - 3.0 or absf(position.y) > half_extent - 3.0:
				continue
			if _in_forest_clearing(position, 0.0):
				continue
			if _overlaps(position, 2.4):
				continue
			_add_placement(
				species,
				position,
				_rng.randf_range(0.0, 360.0),
				_rng.randi_range(0, 2),
				_rng.randf_range(0.7, 1.2),
				1.5
			)
	# Understorey in knots at the edge of the wood, not a bead necklace of
	# shrubs at one radius. Flowering variants cluster together, because a
	# stand of the same plant is what the meadow would actually grow.
	for cluster in 9:
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(half_extent * 0.44, half_extent * 0.74)
		var center := Vector2(cos(angle), sin(angle)) * distance
		if road_distance(center.x, center.y) < 4.5:
			continue
		if _in_forest_clearing(center, 3.5):
			continue
		var variant := _rng.randi_range(0, 2)
		for member in _rng.randi_range(3, 5):
			var spread := _rng.randf() * TAU
			var offset := Vector2(cos(spread), sin(spread)) * _rng.randf_range(0.9, 3.4)
			_add_placement(
				KIND_BUSH,
				center + offset,
				_rng.randf_range(0.0, 360.0),
				variant,
				_rng.randf_range(0.72, 1.30),
				1.0
			)
	for index in 16:
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(half_extent * 0.42, half_extent * 0.72)
		_add_placement(
			KIND_BUSH,
			Vector2(cos(angle), sin(angle)) * distance,
			_rng.randf_range(0.0, 360.0),
			_rng.randi_range(0, 2),
			_rng.randf_range(0.70, 1.20),
			1.0
		)


func _build_scatter() -> void:
	# Trees and boulders inside the village, in loose knots rather than one even
	# ring. The mix still matters: three species, flowering shrubs and stone
	# break the "oak or nothing" pattern, but the spacing is now irregular.
	for cluster in 16:
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(PLAZA_RADIUS + 8.0, half_extent * 0.56)
		var center := Vector2(cos(angle), sin(angle)) * distance
		for member in _rng.randi_range(1, 3):
			var spread := _rng.randf() * TAU
			var position := center + Vector2(cos(spread), sin(spread)) * _rng.randf_range(1.4, 4.6)
			var roll := _rng.randf()
			var kind := KIND_TREE_OAK
			var footprint := 1.8
			if roll < 0.20:
				kind = KIND_TREE_PINE
			elif roll < 0.36:
				kind = KIND_TREE_BIRCH
			elif roll < 0.56:
				kind = KIND_BUSH
				footprint = 1.1
			elif roll < 0.70:
				kind = KIND_ROCK
				footprint = 0.9
			_add_placement(
				kind,
				position,
				_rng.randf_range(0.0, 360.0),
				_rng.randi_range(0, 2),
				_rng.randf_range(0.75, 1.25),
				footprint
			)
	# A handful of field stones further out: they belong to the open country,
	# not to the village, so they are scattered instead of clustered.
	for index in 14:
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(half_extent * 0.52, half_extent * 0.80)
		_add_placement(
			KIND_ROCK,
			Vector2(cos(angle), sin(angle)) * distance,
			_rng.randf_range(0.0, 360.0),
			_rng.randi_range(0, 2),
			_rng.randf_range(0.35, 1.10),
			0.9
		)


## Flowers are placed last: they fill the gaps left by trees, shrubs and props,
## and the placer's own rules keep them off the carriageway, out of doorways and
## out of the pond. Three deliberately composed groups are added on top of the
## meadow clusters: the plaza rim (where the eye leaves the square), the pond
## bank (damp meadow) and the field margins.
func _build_meadow_flowers() -> void:
	for cluster in 22:
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(PLAZA_RADIUS + 2.0, half_extent * 0.62)
		var center := Vector2(cos(angle), sin(angle)) * distance
		if pond_weight(center.x, center.y) > 0.05:
			continue
		var variant := _rng.randi_range(0, 2)
		for member in _rng.randi_range(3, 6):
			var spread := _rng.randf() * TAU
			var position := center + Vector2(cos(spread), sin(spread)) * _rng.randf_range(0.3, 2.0)
			if absf(position.x) > half_extent - 3.0 or absf(position.y) > half_extent - 3.0:
				continue
			_add_placement(
				KIND_FLOWER_PATCH,
				position,
				_rng.randf_range(0.0, 360.0),
				variant,
				_rng.randf_range(0.85, 1.25),
				0.55
			)
	for index in 12:
		var angle := TAU * float(index) / 12.0 + _rng.randf_range(-0.16, 0.16)
		var distance := _rng.randf_range(PLAZA_RADIUS + 1.6, PLAZA_RADIUS + 2.9)
		_add_placement(
			KIND_FLOWER_PATCH,
			Vector2(cos(angle), sin(angle)) * distance,
			_rng.randf_range(0.0, 360.0),
			_rng.randi_range(0, 2),
			_rng.randf_range(0.90, 1.20),
			0.50
		)
	for index in 8:
		var angle := _rng.randf() * TAU
		var distance := pond_radius * _rng.randf_range(1.10, 1.35)
		var position := pond_center + Vector2(cos(angle), sin(angle)) * distance
		if road_weight(position.x, position.y) > 0.10:
			continue
		_add_placement(
			KIND_FLOWER_PATCH,
			position,
			_rng.randf_range(0.0, 360.0),
			_rng.randi_range(0, 2),
			_rng.randf_range(0.80, 1.15),
			0.50
		)


## True inside a glade (plus a margin). Glades are kept clear of trunks and of
## the understorey, so they read as open grass rather than as thinner woods.
func _in_forest_clearing(point: Vector2, margin: float) -> bool:
	for clearing in forest_clearings:
		if point.distance_to(clearing) < 9.0 + margin:
			return true
	return false


# --- helpers -----------------------------------------------------------------


## Total length of a polyline, in metres.
static func polyline_length(road: PackedVector2Array) -> float:
	var total := 0.0
	for index in maxi(road.size() - 1, 0):
		total += road[index].distance_to(road[index + 1])
	return total


## Point and unit tangent at [param distance] along a polyline, clamped to its
## ends. Used by house plots, street furniture and the paving builder so all
## three read the same curve.
static func sample_polyline(road: PackedVector2Array, distance: float) -> Dictionary:
	var travelled := 0.0
	for index in maxi(road.size() - 1, 0):
		var start: Vector2 = road[index]
		var end: Vector2 = road[index + 1]
		var span := end - start
		var length := span.length()
		if length < 0.0001:
			continue
		if travelled + length >= distance or index == road.size() - 2:
			var t := clampf((distance - travelled) / length, 0.0, 1.0)
			return {"point": start + span * t, "tangent": span / length}
		travelled += length
	return {"point": road[road.size() - 1], "tangent": Vector2(1.0, 0.0)}


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
	# Doors and stoops stay open: the placer rejects anything that would stand
	# in the doorway corridor of a building, whichever pass wanted it there.
	# Tall vegetation keeps a longer sightline than a crate or a barrel.
	if _blocks_a_doorway(position, extent, kind):
		return
	if ROAD_CLEARING_KINDS.has(kind):
		# Keep the carriageway walkable, and give trees a real verge: a trunk at
		# the very edge of the falloff closes the road visually even when the
		# player can physically walk past it.
		var road_clearance := ROAD_WIDTH * 0.5 + extent * 0.6
		if TREE_KINDS.has(kind):
			road_clearance += TREE_ROAD_VERGE
		if distance_to_roads(position) < road_clearance:
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


## True when a prop of the given radius would stand in the doorway corridor of
## a building: the strip on the +Z (door) face, from just outside the wall to
## [constant DOOR_CORRIDOR_REACH] past the footprint, half as wide as
## [constant DOOR_CORRIDOR_HALF_WIDTH] plus half the prop. The corridor faces
## the road by construction (houses are yawed towards it), so keeping it clear
## keeps the walk from every door open for the player and for the NPC door
## anchors. A tree gets an even longer and wider corridor
## ([constant TREE_DOOR_SIGHTLINE]): a trunk beside the path still hides the
## door from the square, even when it does not block the walk.
func _blocks_a_doorway(position: Vector2, extent: float, kind: String = "") -> bool:
	var extra_reach := TREE_DOOR_SIGHTLINE if TREE_KINDS.has(kind) else 0.0
	var extra_width := TREE_DOOR_EXTRA_WIDTH if TREE_KINDS.has(kind) else 0.0
	for placement in placements:
		if not DOOR_BUILDING_KINDS.has(placement.kind):
			continue
		var yaw := deg_to_rad(placement.rotation_deg)
		var delta := position - placement.position
		var local_z := delta.x * sin(yaw) + delta.y * cos(yaw)
		var reach := (
			placement.footprint_radius * placement.scale + DOOR_CORRIDOR_REACH + extra_reach
		)
		if local_z <= 0.0 or local_z > reach:
			continue
		var local_x := delta.x * cos(yaw) - delta.y * sin(yaw)
		if absf(local_x) < DOOR_CORRIDOR_HALF_WIDTH + extent * 0.5 + extra_width:
			return true
	return false


func _smoothstep(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
