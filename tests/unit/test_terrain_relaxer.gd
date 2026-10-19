class_name TestTerrainRelaxer
extends RefCounted
## Checks for `TerrainRelaxer`, the geometry guard used by `TerrainGenerator`.
##
## The generator shapes the landform; these checks prove that the guard really
## delivers what it promises on synthetic grids, where the expected answer can
## be computed by hand:
## * a spike is cut down until no cell differs from a neighbour by more than
##   the allowed step;
## * built ground (plaza, roads, plots) is never moved, while its surroundings
##   are relaxed into a walkable skirt;
## * building pads blend with a weighted average instead of meeting in a step;
## * the same input always produces the same output (the world stays
##   deterministic, which the save system relies on).


static func run_tests(harness: TestHarness) -> void:
	harness.suite("TerrainRelaxer")

	_spike_is_relaxed(harness)
	protected_ground_is_never_moved(harness)
	pads_blend(harness)
	measurements_are_honest(harness)
	mask_matches_the_layout(harness)


## A single tall spike on flat ground must be levelled down until every
## neighbouring pair respects the cap.
static func _spike_is_relaxed(harness: TestHarness) -> void:
	var size := 21
	var heights := _flat_grid(size)
	heights[10 * size + 10] = 4.0
	heights[5 * size + 15] = -3.0
	var before := heights.duplicate()
	var protected := PackedByteArray()
	protected.resize(size * size)
	TerrainRelaxer.relax_heights(heights, size, 0.5, 24, protected)
	harness.check(
		absf(heights[10 * size + 10] - before[10 * size + 10]) > 0.5,
		"the spike was actually lowered"
	)
	harness.check(
		TerrainRelaxer.max_neighbour_step(heights, size, protected) <= 0.5 + 0.0001,
		"no neighbouring pair is steeper than the allowed step"
	)
	var flat_far := true
	for index in [0, size * size - 1, 3 * size + 3]:
		if not is_equal_approx(heights[index], before[index]):
			flat_far = false
	harness.check(flat_far, "flat ground far from the spike is left alone")

	# The same input must produce the same grid: a second run is byte-identical.
	var again := before.duplicate()
	TerrainRelaxer.relax_heights(again, size, 0.5, 24, protected)
	harness.check_equals(again, heights, "relaxation is deterministic")


## A protected cell keeps its value even when it is the tallest thing around,
## and the open ground beside it is graded instead.
static func _protected_ground_is_never_moved(harness: TestHarness) -> void:
	var size := 17
	var heights := _flat_grid(size)
	heights[8 * size + 8] = 2.0
	var protected := PackedByteArray()
	protected.resize(size * size)
	protected[8 * size + 8] = 1
	var before := heights.duplicate()
	TerrainRelaxer.relax_heights(heights, size, 0.5, 60, protected)
	harness.check_almost(
		heights[8 * size + 8], before[8 * size + 8], 0.0001,
		"a protected cell (plaza, road, plot) is not moved"
	)
	harness.check(
		heights[8 * size + 7] > before[8 * size + 7],
		"the open ground beside the protected cell is graded upward instead"
	)
	harness.check(
		TerrainRelaxer.max_neighbour_step(heights, size, protected, true) <= 0.5001,
		"the skirt around protected ground stays within the step cap"
	)
	# The contrast proves the mask is what preserves it: the same spike on the
	# same grid, with nothing protected, is relaxed away.
	var unprotected := before.duplicate()
	var no_mask := PackedByteArray()
	no_mask.resize(size * size)
	TerrainRelaxer.relax_heights(unprotected, size, 0.5, 60, no_mask)
	harness.check(
		unprotected[8 * size + 8] < before[8 * size + 8] - 0.5,
		"without protection the same spike would be cut down"
	)


## Two pads with different heights must produce a smooth weighted average, and
## a point outside every falloff must not be claimed by any pad.
static func _pads_blend(harness: TestHarness) -> void:
	var pads: Array[Dictionary] = [
		{"pos": Vector2(0.0, 0.0), "radius": 3.0, "height": 10.0},
		{"pos": Vector2(8.0, 0.0), "radius": 3.0, "height": 4.0},
	]
	var centre_left := TerrainRelaxer.pad_blend(2.0, 0.0, pads)
	var between := TerrainRelaxer.pad_blend(4.0, 0.0, pads)
	var centre_right := TerrainRelaxer.pad_blend(5.0, 0.0, pads)
	harness.check(
		centre_left["weight"] > 0.99, "the centre of a pad has full weight"
	)
	harness.check_almost(
		float(centre_left["height"]), 10.0, 0.001, "the centre of a pad takes its own height"
	)
	harness.check(
		float(between["height"]) < 10.0 and float(between["height"]) > 4.0,
		"between two pads the height is a blend, not a step"
	)
	harness.check(
		float(centre_right["height"]) < float(between["height"]),
		"the blend moves toward the second pad as the point approaches it"
	)
	harness.check_almost(
		float(centre_right["height"]), 4.0, 0.2,
		"a point well inside a footprint takes that pad's own height"
	)
	var outside := TerrainRelaxer.pad_blend(60.0, 60.0, pads)
	harness.check_almost(float(outside["weight"]), 0.0, 0.0001, "far from every pad there is no pad")
	var no_pads: Array[Dictionary] = []
	harness.check_almost(
		float(TerrainRelaxer.pad_blend(0.0, 0.0, no_pads)["weight"]), 0.0, 0.0001,
		"an empty pad list never claims ground"
	)


## The public measurements must describe the same grid the mesh is built from.
static func _measurements_are_honest(harness: TestHarness) -> void:
	var heights := PackedFloat32Array([-2.0, 0.0, 1.0, 3.0])
	var span := TerrainRelaxer.height_range(heights)
	harness.check_almost(span.x, -2.0, 0.0001, "height_range reports the minimum")
	harness.check_almost(span.y, 3.0, 0.0001, "height_range reports the maximum")
	harness.check_almost(
		TerrainRelaxer.height_range(PackedFloat32Array()).length(), 0.0, 0.0001,
		"an empty grid has no span"
	)
	var grid := PackedFloat32Array([0.0, 1.0, 0.0, 1.0])
	var no_mask := PackedByteArray()
	harness.check_almost(
		TerrainRelaxer.max_neighbour_step(grid, 2, no_mask), 1.0, 0.0001,
		"max_neighbour_step finds the steepest pair"
	)
	var rise := TerrainRelaxer.horizon_rise(_ramp_grid(20), 20)
	harness.check(rise > 0.0, "a rim that is higher than the field reads as a positive rise")
	var flat := PackedFloat32Array()
	flat.resize(20 * 20)
	harness.check_almost(
		TerrainRelaxer.horizon_rise(flat, 20), 0.0, 0.0001, "no rim means no rise"
	)


## `build_protected_mask` must protect exactly what the village uses.
static func _mask_matches_the_layout(harness: TestHarness) -> void:
	var layout := VillageLayout.new(20261016, 79.5)
	var size := 160
	var no_pads: Array[Dictionary] = []
	var mask := TerrainRelaxer.build_protected_mask(size, layout, no_pads)
	harness.check_equals(mask.size(), size * size, "the mask has one entry per grid point")
	var half := float(size - 1) * 0.5
	var index_of := func(x: float, z: float) -> int:
		return int(round(z + half)) * size + int(round(x + half))
	harness.check_equals(mask[index_of.call(0.0, 0.0)], 1, "the plaza centre is protected")
	var road_point := layout.point_on_road(0, 30.0)
	harness.check_equals(
		mask[index_of.call(road_point.x, road_point.y)], 1, "a road centreline is protected"
	)
	harness.check_equals(
		mask[index_of.call(0.0, 55.0)], 0, "open country between two roads is not protected"
	)
	var empty := TerrainRelaxer.build_protected_mask(size, null, no_pads)
	var marked := 0
	for value in empty:
		if value != 0:
			marked += 1
	harness.check_equals(marked, 0, "without a layout nothing is protected")


static func _flat_grid(size: int) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	return heights


## A grid whose outer ring is higher than its interior, by one metre.
static func _ramp_grid(size: int) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	for iz in size:
		for ix in size:
			var on_border := iz == 0 or ix == 0 or iz == size - 1 or ix == size - 1
			heights[iz * size + ix] = 1.0 if on_border else 0.0
	return heights
