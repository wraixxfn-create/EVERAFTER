class_name TerrainRelaxer
extends RefCounted
## Geometry guards for [TerrainGenerator] — Visual Polish 14.
##
## The generator shapes the land first; this module then guarantees that the
## shaped grid stays physically walkable and that building pads blend instead
## of stepping. It is deliberately a pure, static helper over arrays and plain
## data: it owns no noise, no nodes and no second terrain. The one height grid
## produced by [TerrainGenerator] is the only source of truth, and both the
## visible mesh and the `HeightMapShape3D` are built from it after this pass.
##
## Two responsibilities:
## * **talus relaxation** — enforce a maximum height difference between
##   neighbouring cells on open ground, so a rocky ridge can never become a
##   cliff the player capsule cannot climb (and no accidental spike survives);
## * **platform blending** — the eased, weighted-average height of the levelling
##   pads a point belongs to, so two adjacent plots never meet in a step.


## 1 where a cell must not be moved by the relaxation pass: plaza, carriageways
## and levelled plots, with a small safety margin so a foundation is never shaved.
## The mask covers exactly the same built ground the layout declares, which is
## what keeps roads and squares dead level while open country is relaxed.
static func build_protected_mask(
	size_cells: int, layout: VillageLayout, pads: Array[Dictionary]
) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(size_cells * size_cells)
	if layout == null:
		return mask
	var half := float(size_cells - 1) * 0.5
	# Same shortcut the generator uses: outside this box no pad can reach, so
	# only the plaza and road weights need to be sampled.
	var pad_bounds := Rect2()
	if not pads.is_empty():
		var widest := 0.0
		for pad in pads:
			widest = maxf(widest, float(pad["radius"]))
		var first: Vector2 = pads[0]["pos"]
		pad_bounds = Rect2(first, Vector2.ZERO)
		for pad in pads:
			var pad_position: Vector2 = pad["pos"]
			pad_bounds = pad_bounds.expand(pad_position)
		var grow := widest + VillageLayout.PLOT_FALLOFF
		pad_bounds = Rect2(
			pad_bounds.position - Vector2.ONE * grow,
			pad_bounds.size + Vector2.ONE * grow * 2.0
		)
	for iz in size_cells:
		var z := float(iz) - half
		for ix in size_cells:
			var x := float(ix) - half
			var protected := layout.plaza_weight(x, z) > 0.80
			if not protected:
				protected = layout.road_distance(x, z) < VillageLayout.ROAD_WIDTH * 0.5 + 0.5
			if not protected and pad_bounds.has_point(Vector2(x, z)):
				var point := Vector2(x, z)
				for pad in pads:
					var radius: float = pad["radius"]
					var pad_position: Vector2 = pad["pos"]
					if point.distance_to(pad_position) < radius + 0.5:
						protected = true
						break
			if protected:
				mask[iz * size_cells + ix] = 1
	return mask


## Two-sided talus relaxation, in place, written as two monotone halves so that
## it converges instead of oscillating. Open ground below a protected neighbour
## is filled up to one step below it (a pad gets a skirt, not a plinth); open
## ground above any neighbour is then cut down to one step above it (a road cut
## gets a walkable ramp). Protected cells are never written but act as
## neighbours. Deterministic: same grid, same mask, same result.
static func relax_heights(
	heights: PackedFloat32Array,
	size_cells: int,
	max_step: float,
	passes: int,
	protected: PackedByteArray
) -> void:
	if heights.is_empty() or size_cells < 3:
		return
	# Two monotone halves instead of one bidirectional clamp. A cell can be
	# *filled* only toward a protected neighbour (a foundation, a road or the
	# square), which keeps a levelled pad from becoming a plinth with a wall
	# around it; then open ground is *cut* toward its lowest neighbour, which is
	# what grading a road into a slope needs. Each half only moves heights in one
	# direction, so it converges: reading a neighbour and then overwriting the
	# current cell (Gauss–Seidel) propagates a constraint one cell per pass. The
	# old symmetric clamp used the midpoint whenever the two bounds crossed and
	# repeated passes amplified the contradiction into steps of several metres.
	var has_mask := protected.size() == heights.size()
	for _pass in passes:
		var changed := false
		# Fill: raise open ground that sits below protected ground.
		for iz in size_cells:
			for ix in size_cells:
				var index := iz * size_cells + ix
				if index < protected.size() and protected[index] == 1:
					continue
				var target := -INF
				if ix > 0 and has_mask and protected[index - 1] == 1:
					target = maxf(target, heights[index - 1] - max_step)
				if ix < size_cells - 1 and has_mask and protected[index + 1] == 1:
					target = maxf(target, heights[index + 1] - max_step)
				if iz > 0 and has_mask and protected[index - size_cells] == 1:
					target = maxf(target, heights[index - size_cells] - max_step)
				if iz < size_cells - 1 and has_mask and protected[index + size_cells] == 1:
					target = maxf(target, heights[index + size_cells] - max_step)
				if target > heights[index] + 0.00001:
					heights[index] = target
					changed = true
		# Cut: lower open ground that sits above any neighbour.
		for iz in size_cells:
			for ix in size_cells:
				var index := iz * size_cells + ix
				if index < protected.size() and protected[index] == 1:
					continue
				var lowest := INF
				if ix > 0:
					lowest = minf(lowest, heights[index - 1])
				if ix < size_cells - 1:
					lowest = minf(lowest, heights[index + 1])
				if iz > 0:
					lowest = minf(lowest, heights[index - size_cells])
				if iz < size_cells - 1:
					lowest = minf(lowest, heights[index + size_cells])
				if lowest == INF:
					continue
				var cap := lowest + max_step
				if heights[index] > cap + 0.00001:
					heights[index] = cap
					changed = true
		if not changed:
			break

## Nearest point on any of the layout's road centrelines. Roads are polylines
## of a handful of vertices, so a linear scan is both correct and cheap; the
## generator calls it to know which ground a road is following beside the cut.
static func nearest_road_point(roads: Array[PackedVector2Array], point: Vector2) -> Vector2:
	var best := point
	var best_distance := INF
	for road in roads:
		for index in road.size() - 1:
			var start := road[index]
			var span := road[index + 1] - start
			var length_squared := span.length_squared()
			if length_squared <= 0.0001:
				continue
			var t := clampf((point - start).dot(span) / length_squared, 0.0, 1.0)
			var nearest := start + span * t
			var distance := point.distance_squared_to(nearest)
			if distance < best_distance:
				best_distance = distance
				best = nearest
	return best


## Eased, weighted-average height of every pad whose falloff reaches the point.
## Weighted average rather than "nearest wins": neighbouring plots with slightly
## different heights must blend, never meet in a step. The average is sharpened
## (cubed weights) so a point inside one footprint takes that pad's height
## almost exactly: a foundation is level, not a 20 % compromise. Returns
## `{"weight": 0..1, "height": metres}`; weight 0 means "not on a pad".
static func pad_blend(x: float, z: float, pads: Array[Dictionary]) -> Dictionary:
	if pads.is_empty():
		return {"weight": 0.0, "height": 0.0}
	var point := Vector2(x, z)
	var best_weight := 0.0
	var weighted_height := 0.0
	var weight_sum := 0.0
	for pad in pads:
		var radius: float = pad["radius"]
		var pad_position: Vector2 = pad["pos"]
		var distance := point.distance_to(pad_position)
		if distance > radius + VillageLayout.PLOT_FALLOFF:
			continue
		var weight := smoothstep01(
			1.0 - clampf((distance - radius) / VillageLayout.PLOT_FALLOFF, 0.0, 1.0)
		)
		if weight <= 0.001:
			continue
		# Cubed weight: inside a footprint the dominant pad wins almost
		# completely (a foundation must be exactly level), while on the falloff
		# ring two neighbours still blend smoothly with no step.
		var sharpened := weight * weight * weight
		weighted_height += float(pad["height"]) * sharpened
		weight_sum += sharpened
		best_weight = maxf(best_weight, weight)
	if weight_sum <= 0.0:
		return {"weight": 0.0, "height": 0.0}
	return {"weight": best_weight, "height": weighted_height / weight_sum}


## Hermite ease on 0..1. Local copy so this helper has no dependency on the
## generator's private methods.
static func smoothstep01(t: float) -> float:
	var value := clampf(t, 0.0, 1.0)
	return value * value * (3.0 - 2.0 * value)


# --- read-only measurements over a shaped grid --------------------------------


## Lowest and highest point of the grid, as `Vector2(minimum, maximum)`.
static func height_range(heights: PackedFloat32Array) -> Vector2:
	if heights.is_empty():
		return Vector2.ZERO
	var lowest := heights[0]
	var highest := heights[0]
	for value in heights:
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
	return Vector2(lowest, highest)


## Largest height difference between a cell and any of its four neighbours.
## With [param open_ground_only] any pair that touches a protected cell is
## ignored, because a road cut or a plaza edge is a deliberate bank.
static func max_neighbour_step(
	heights: PackedFloat32Array,
	size_cells: int,
	protected: PackedByteArray,
	open_ground_only: bool = false
) -> float:
	var worst := 0.0
	for iz in size_cells:
		for ix in size_cells:
			var index := iz * size_cells + ix
			if ix + 1 < size_cells:
				worst = maxf(worst, _step(heights, protected, index, index + 1, open_ground_only))
			if iz + 1 < size_cells:
				worst = maxf(
					worst, _step(heights, protected, index, index + size_cells, open_ground_only)
				)
	return worst


static func _step(
	heights: PackedFloat32Array,
	protected: PackedByteArray,
	a: int,
	b: int,
	open_ground_only: bool
) -> float:
	if open_ground_only and not protected.is_empty():
		if protected[a] == 1 or protected[b] == 1:
			return 0.0
	return absf(heights[a] - heights[b])


## Mean height of the outermost ring minus the mean of the inner field.
static func horizon_rise(heights: PackedFloat32Array, size_cells: int) -> float:
	if size_cells < 8 or heights.is_empty():
		return 0.0
	var border := 0.0
	var border_count := 0
	var inner := 0.0
	var inner_count := 0
	var limit := int(float(size_cells) * 0.8)
	for iz in size_cells:
		for ix in size_cells:
			var value := heights[iz * size_cells + ix]
			if iz == 0 or ix == 0 or iz == size_cells - 1 or ix == size_cells - 1:
				border += value
				border_count += 1
			elif iz > size_cells - limit and iz < limit and ix > size_cells - limit \
					and ix < limit:
				inner += value
				inner_count += 1
	if border_count == 0 or inner_count == 0:
		return 0.0
	return border / float(border_count) - inner / float(inner_count)
