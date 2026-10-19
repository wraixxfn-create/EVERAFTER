class_name GroundSurfaces
extends RefCounted
## Visual polish 15 — the walkable surfaces of the village.
##
## Before this module the square and the roads existed only as *paint* on the
## 1 m terrain grid plus a ring of kerb boxes. That cost nothing, but it could
## not do the three things a paved surface has to do at eye level: hold a stone
## scale smaller than a grid cell, change tone where stone meets dirt, and sit
## on the ground instead of hovering over it. This module adds a thin,
## terrain-following paving sheet — never a collider, never a second terrain.
##
## Design rules, each one a response to a defect seen in the old village:
## * **one sheet, not a thousand stones.** The cobbles are a texture on a coarse
##   grid; the geometry only follows the ground and cuts the silhouette. The
##   whole pavement budget is a few thousand triangles and two draw calls.
## * **everything samples `terrain.height_at`.** A paving vertex is never placed
##   at a design height, so the sheet cannot float over a dip or sink into a
##   rise. The lift is at most 2.6 cm, below the capsule's step tolerance.
## * **irregular boundaries are authored, not painted.** The plaza rim, the road
##   verge and the door aprons have a deterministic noise edge, then fade their
##   colour through gravel to meadow instead of stopping on a perfect curve.
## * **nothing is built in a doorway or under a foundation.** Road ribbons and
##   paving cells are rejected against the real oriented footprints of the
##   buildings, so a road can never disappear under a wall.
## * **kerbs follow the slope.** Each kerb stone samples the ground at both ends
##   and is tilted and embedded, so a 0.9 m stone on a grade does not hover.
##
## The module is pure geometry: `build()` returns nodes, `bake_kerbs()` appends
## to the shared prop baker, and `build_geometry()` can be inspected headless by
## the unit tests without creating a material or a texture.

## Plaza geometry. The paved disc stops just inside the kerb ring; the gap is a
## gravel apron that blends stone into the meadow.
const PLAZA_SEGMENTS := 56
const PLAZA_EDGE_BASE := 10.72
const PLAZA_EDGE_WOBBLE := 0.9
const PLAZA_APRON_OUTER := 11.92
const WELL_HOLE_RADIUS := 1.52
## Bands that make the square legible: a worn court around the well, a dark
## drainage course, a broad field and a soldier course near the rim.
const WELL_COURT_RADIUS := 3.2
const COURT_RING_INNER := 3.52
const OUTER_COURSE_INNER := 8.95
const OUTER_COURSE_OUTER := 9.7

## Lifts above the terrain, in metres. Below a doorstep, above z-fighting.
const PAVING_LIFT := 0.026
const APRON_LIFT := 0.020
const ROAD_LIFT := 0.018
const ROAD_VERGE_LIFT := 0.008

## Road ribbon: a constant-width strip would have looked like tape laid on the
## grass, so the visible edge meanders by a few centimetres while the physical
## road corridor in `VillageLayout` stays exactly as wide as before.
const ROAD_CORE_HALF := 1.8
const ROAD_VERGE_WIDTH := 0.92
const ROAD_SAMPLE_STEP := 1.4
const ROAD_MOUTH_WIDEN := 0.55
const ROAD_MOUTH_FADE := 3.4

## Door aprons: a stone threshold and a short path to the road, generous enough
## for the NPC door anchors but never long enough to reach the carriageway.
const APRON_HALF_EXTRA := 0.42
const APRON_LENGTH := 1.55
## Gap left between the path and the carriageway. The yard between a house
## stoop and the road edge is under a metre in this village, so the apron is a
## threshold strip that bridges the two, not a garden walk that overlaps both.
const APRON_ROAD_MARGIN := 0.05

## Kerb stones are measured against a 4 m door and a 1.8 m human: long enough to
## read as edging, short enough not to look like megaliths.
const PLAZA_KERB_STONES := 64
const PLAZA_KERB_RADIUS := 12.2
const ROAD_KERB_SPACING := 2.2
const ROAD_KERB_GAP_CHANCE := 0.14

var layout: VillageLayout = null
var terrain: TerrainGenerator = null
var materials: VillageMaterials = null

var triangle_count: int = 0
var vertex_count: int = 0
var kerb_stone_count: int = 0

var _rng := RandomNumberGenerator.new()
var _tools: Dictionary = {}
var _vertices := PackedVector3Array()


func _init(
	initial_layout: VillageLayout, initial_terrain: TerrainGenerator,
	initial_materials: VillageMaterials
) -> void:
	layout = initial_layout
	terrain = initial_terrain
	materials = initial_materials


## Builds the paving sheets and returns one node holding one mesh per material.
## Two draw calls, no collider, no per-stone node.
func build() -> Node3D:
	build_geometry()
	var root := Node3D.new()
	root.name = "Paving"
	for key in _tools.keys():
		var tool := _tools[key] as SurfaceTool
		# Non-indexed is deliberate: every quad owns its corners, so each strip
		# keeps its own vertex colours and edge gradient. MikkTSpace generates
		# tangents for the non-indexed triangles just as well.
		tool.generate_tangents()
		var instance := MeshInstance3D.new()
		instance.name = "Paving_%s" % key
		instance.mesh = tool.commit()
		instance.material_override = materials.get_material(String(key))
		# A flat sheet of ground has no silhouette to cast: skipping shadows
		# saves a shadow pass over the largest new surface in the scene.
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instance)
	return root


## Geometry only, no materials and no textures. The unit suite calls this so it
## can assert heights, triangle budget and boundaries on a plain headless run.
func build_geometry() -> void:
	triangle_count = 0
	vertex_count = 0
	_tools.clear()
	_vertices.clear()
	_rng.seed = layout.world_seed + 151
	_build_plaza()
	_build_plaza_apron()
	_build_roads()
	_build_door_aprons()


func get_triangle_count() -> int:
	return triangle_count


func get_vertex_count() -> int:
	return vertex_count


## Every emitted vertex, in build order. Used by the tests to prove the sheet
## follows the terrain and never enters a building.
func get_vertices() -> PackedVector3Array:
	return _vertices


func get_material_keys() -> PackedStringArray:
	var keys := PackedStringArray()
	for key in _tools.keys():
		keys.append(String(key))
	keys.sort()
	return keys


## Outward boundary of the paved square at [param angle]: a smooth, low
## frequency wobble so the rim reads as hand-laid rather than as a compass
## circle. Shared with the kerb so the stones sit just outside it.
func plaza_edge_radius(angle: float) -> float:
	var wobble := sin(angle * 3.0 + 0.8) * 0.20
	wobble += sin(angle * 7.0 + 2.1) * 0.11
	wobble += sin(angle * 13.0 + 4.4) * 0.05
	return PLAZA_EDGE_BASE + wobble * PLAZA_EDGE_WOBBLE


## Visible half width of a road at a point. It widens slightly at the plaza
## mouth (carts turning, water running off the square) and then settles to the
## structural half width, with a small meander so both verges are not parallel
## rulers.
func road_half_width(point: Vector2, travelled: float, road_index: int) -> float:
	var radius := point.length()
	var mouth := 1.0 - clampf(
		(radius - (VillageLayout.PLAZA_RADIUS - 2.5)) / ROAD_MOUTH_FADE, 0.0, 1.0
	)
	var width := ROAD_CORE_HALF + mouth * ROAD_MOUTH_WIDEN
	width += sin(travelled * 0.23 + float(road_index) * 2.1) * 0.06
	return width


## True when [param point] is inside the oriented footprint of a structure,
## with [param margin] metres of clearance. Paving is rejected here so a ribbon
## or a patch can never reappear under a wall.
func inside_structure(point: Vector2, margin: float = 0.0) -> bool:
	for placement in layout.placements:
		if not BuildingFactory.is_structure(placement.kind):
			continue
		var footprint := _structure_footprint(placement)
		var yaw := deg_to_rad(placement.rotation_deg)
		var delta := point - placement.position
		var local_x := delta.x * cos(yaw) - delta.y * sin(yaw)
		var local_z := delta.x * sin(yaw) + delta.y * cos(yaw)
		if absf(local_x) <= footprint.x + margin \
				and absf(local_z) <= footprint.y + margin:
			return true
	return false


## Bakes the two kerb runs into the shared prop mesh. Stones are tilted to the
## local grade and embedded, so they read as edging rather than as floating
## dominoes, and both runs leave the road mouths and door aprons open.
func bake_kerbs(baker: MeshBaker) -> void:
	kerb_stone_count = 0
	_rng.seed = layout.world_seed + 157
	_bake_plaza_kerb(baker)
	_bake_road_kerb(baker)


# --- plaza -------------------------------------------------------------------


func _build_plaza() -> void:
	var radii := PackedFloat32Array([
		WELL_HOLE_RADIUS, 2.0, 2.55, WELL_COURT_RADIUS, COURT_RING_INNER, 4.1,
		4.75, 5.45, 6.2, 6.95, 7.7, 8.45, OUTER_COURSE_INNER,
		OUTER_COURSE_OUTER, 10.25,
	])
	var step := TAU / float(PLAZA_SEGMENTS)
	for ring in radii.size():
		var inner := radii[ring]
		var has_outer := ring + 1 < radii.size()
		var outer := radii[ring + 1] if has_outer else -1.0
		for segment in PLAZA_SEGMENTS:
			var angle_0 := step * float(segment)
			var angle_1 := step * float(segment + 1)
			var r0 := plaza_edge_radius(angle_0) if inner < 0.0 else inner
			var r1 := plaza_edge_radius(angle_1) if outer < 0.0 else outer
			var mid_angle := (angle_0 + angle_1) * 0.5
			var mid_radius := (r0 + r1) * 0.5
			var mid := Vector2(cos(mid_angle), sin(mid_angle)) * mid_radius
			if _plaza_cell_skipped(mid, mid_radius):
				continue
			var points: Array[Vector3] = [
				_ground_point(cos(angle_0) * r0, sin(angle_0) * r0, PAVING_LIFT),
				_ground_point(cos(angle_0) * r1, sin(angle_0) * r1, PAVING_LIFT),
				_ground_point(cos(angle_1) * r1, sin(angle_1) * r1, PAVING_LIFT),
				_ground_point(cos(angle_1) * r0, sin(angle_1) * r0, PAVING_LIFT),
			]
			var tint := _plaza_tint(mid_radius, segment, mid)
			# The square is laid in concentric courses: the U axis follows the
			# arc (so the stones never stretch at the rim) and V follows the
			# radius. A world-aligned UV grid would have cut every ring at the
			# same angle and read as a tiled floor rather than as a piazza.
			var uvs: Array[Vector2] = [
				_polar_uv(r0, angle_0), _polar_uv(r1, angle_0),
				_polar_uv(r1, angle_1), _polar_uv(r0, angle_1),
			]
			_add_ground_quad("paving_cobble", points, uvs, [tint, tint, tint, tint])


func _plaza_cell_skipped(mid: Vector2, mid_radius: float) -> bool:
	# Road mouths: the stone stops and a compacted-earth tongue takes over.
	if mid_radius > VillageLayout.PLAZA_RADIUS - 2.65:
		if layout.distance_to_roads(mid) < 3.35:
			return true
	if inside_structure(mid, 0.3):
		return true
	return false


## Bands of the square, from the well court outwards. The composition is
## readable from the game camera without any new mechanic: a court, a ring of
## slabs, a broad field, a soldier course and a dusty outer edge.
func _plaza_tint(mid_radius: float, segment: int, point: Vector2) -> Color:
	var grain := sin(point.x * 0.41 + point.y * 0.27) * 0.022
	grain += sin(point.x * 0.13 - point.y * 0.37) * 0.014
	var tint := Color.WHITE
	if mid_radius < WELL_COURT_RADIUS:
		# Worn court around the well: slightly darker and warmer than the field.
		tint = Color(0.93, 0.91, 0.88)
	elif mid_radius < COURT_RING_INNER:
		# The drainage ring: a deliberately darker course of slabs.
		tint = Color(0.80, 0.78, 0.75)
	elif mid_radius > OUTER_COURSE_INNER and mid_radius < OUTER_COURSE_OUTER:
		# Alternating slabs frame the square. Reading as a composed circle is
		# worth more than one more tone of random cobble.
		tint = Color(0.88, 0.86, 0.83) if segment % 2 == 0 else Color(0.96, 0.94, 0.90)
	elif mid_radius > OUTER_COURSE_OUTER:
		# Outer field: a broad ring of flags between the soldier course and the
		# edge. It varies from course to course rather than wedge by wedge,
		# because the cobble UV now runs around the square: a wedge checker
		# would fight the stones under it.
		var dust := clampf(
			(mid_radius - OUTER_COURSE_OUTER) / (PLAZA_EDGE_BASE - OUTER_COURSE_OUTER),
			0.0, 1.0
		)
		var course := sin(mid_radius * 4.7 + 1.3) * 0.022
		tint = Color(1.0 + course, 1.0 + course * 0.9, 1.0 + course * 0.7)
		tint = tint.lerp(Color(0.90, 0.84, 0.74), dust * 0.45)
	else:
		# Centre of the square is lighter where generations of feet polished it.
		var polish := clampf(1.0 - mid_radius / 7.5, 0.0, 1.0) * 0.035
		tint = Color(1.0 + polish, 1.0 + polish, 1.0 + polish)
	var row := float(segment % 3) * 0.004
	return Color(
		clampf(tint.r + grain - row, 0.0, 1.15),
		clampf(tint.g + grain * 0.8 - row, 0.0, 1.15),
		clampf(tint.b + grain * 0.6 - row, 0.0, 1.15)
	)


## Gravel apron between the stone and the kerb: two ragged rings whose colour
## travels from warm stone dust to gravel to meadow. This is the transition the
## old perfect circle never had.
func _build_plaza_apron() -> void:
	var step := TAU / float(PLAZA_SEGMENTS)
	for segment in PLAZA_SEGMENTS:
		var angle_0 := step * float(segment)
		var angle_1 := step * float(segment + 1)
		var edge_0 := plaza_edge_radius(angle_0)
		var edge_1 := plaza_edge_radius(angle_1)
		var mid_angle := (angle_0 + angle_1) * 0.5
		var mid_edge := (edge_0 + edge_1) * 0.5
		var mid := Vector2(cos(mid_angle), sin(mid_angle)) * (mid_edge + 0.6)
		if layout.distance_to_roads(mid) < 3.5:
			continue
		var inner_0: Array[float] = [edge_0, edge_0 + 0.6, PLAZA_APRON_OUTER]
		var inner_1: Array[float] = [edge_1, edge_1 + 0.6, PLAZA_APRON_OUTER]
		for band in 2:
			var points: Array[Vector3] = [
				_ground_point(
					cos(angle_0) * inner_0[band],
					sin(angle_0) * inner_0[band], APRON_LIFT + 0.004
				),
				_ground_point(
					cos(angle_0) * inner_0[band + 1],
					sin(angle_0) * inner_0[band + 1], APRON_LIFT * 0.35
				),
				_ground_point(
					cos(angle_1) * inner_1[band + 1],
					sin(angle_1) * inner_1[band + 1], APRON_LIFT * 0.35
				),
				_ground_point(
					cos(angle_1) * inner_1[band],
					sin(angle_1) * inner_1[band], APRON_LIFT + 0.004
				),
			]
			var metres := PavingTextures.ROAD_METRES
			var uvs: Array[Vector2] = [
				_polar_uv(inner_0[band], angle_0, metres),
				_polar_uv(inner_0[band + 1], angle_0, metres),
				_polar_uv(inner_1[band + 1], angle_1, metres),
				_polar_uv(inner_1[band], angle_1, metres),
			]
			var dust := float(band)
			var inner_tint := Color(0.62, 0.58, 0.50).lerp(
				Color(0.52, 0.49, 0.43), dust
			)
			var outer_tint := Color(0.56, 0.53, 0.46).lerp(
				Color(0.36, 0.45, 0.20), 0.35 + dust * 0.45
			)
			_add_ground_quad(
				"paving_road", points, uvs,
				[inner_tint, outer_tint, outer_tint, inner_tint]
			)


# --- roads -------------------------------------------------------------------


func _build_roads() -> void:
	for road_index in layout.roads.size():
		var road := layout.roads[road_index]
		var length := VillageLayout.polyline_length(road)
		if length < 6.0:
			continue
		# Start a little inside the first waypoint so the compacted earth runs
		# under the ragged stone mouth instead of stopping at a visible arc.
		var first := VillageLayout.sample_polyline(road, 0.0)
		# Start one metre inside the square: the road sheet then runs under the
		# plaza stone instead of meeting it on a visible seam.
		var start_point: Vector2 = first.point - (first.tangent as Vector2) * 1.0
		var distance := 0.0
		var previous := _road_cross_section(
			start_point, first.tangent, -1.0, road_index
		)
		while distance < length:
			distance = minf(distance + ROAD_SAMPLE_STEP, length)
			var sample := VillageLayout.sample_polyline(road, distance)
			var current := _road_cross_section(
				sample.point, sample.tangent, distance, road_index
			)
			var centre: Vector2 = sample.point
			var current_points: Array = current.points
			if _road_quad_skipped(centre, current_points):
				previous = current
				continue
			var previous_points: Array = previous.points
			var previous_uvs: Array = previous.uvs
			var current_uvs: Array = current.uvs
			var previous_tints: Array = previous.tints
			var current_tints: Array = current.tints
			# Five lateral lanes: core centre, core edge and verge on each side.
			# The wheel ruts live in the road texture, so the geometry stays
			# cheap while the rut follows the curve exactly.
			for lane in previous_points.size() - 1:
				_add_ground_quad(
					"paving_road",
					[
						previous_points[lane], previous_points[lane + 1],
						current_points[lane + 1], current_points[lane],
					],
					[
						previous_uvs[lane], previous_uvs[lane + 1],
						current_uvs[lane + 1], current_uvs[lane],
					],
					[
						previous_tints[lane], previous_tints[lane + 1],
						current_tints[lane + 1], current_tints[lane],
					]
				)
			previous = current


## One cross-section of the road: positions, UVs and vertex colours, from the
## right verge to the left verge (the order that winds the quads upward).
## U runs along the curve and V across it, so the texture grain and the wheel
## ruts stay aligned with the road instead of stretching at every bend.
func _road_cross_section(
	centre: Vector2, tangent: Vector2, travelled: float, road_index: int
) -> Dictionary:
	var outward := Vector2(-tangent.y, tangent.x)
	var half := road_half_width(centre, travelled, road_index)
	var right := 0.92 + sin(travelled * 0.71 + float(road_index)) * 0.10
	var left := 0.92 + sin(travelled * 0.53 + 1.7 + float(road_index)) * 0.10
	var lanes: Array[float] = [
		half + ROAD_VERGE_WIDTH * right, half, 0.0, -half,
		-(half + ROAD_VERGE_WIDTH * left),
	]
	var points: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	var tints: Array[Color] = []
	for index in lanes.size():
		var lane: float = lanes[index]
		var lift := ROAD_LIFT
		if absf(lane) >= half:
			lift = ROAD_VERGE_LIFT
		var flat := centre + outward * lane
		points.append(_ground_point(flat.x, flat.y, lift))
		uvs.append(
			Vector2(
				travelled / PavingTextures.ROAD_METRES,
				clampf(0.5 + lane / (2.0 * ROAD_CORE_HALF), 0.0, 1.0)
			)
		)
		tints.append(_road_lane_tint(index, centre, road_index))
	return {"points": points, "uvs": uvs, "tints": tints}


func _road_quad_skipped(centre: Vector2, points: Array) -> bool:
	if centre.length() < VillageLayout.PLAZA_RADIUS - 2.7:
		return true
	if inside_structure(centre, 0.45):
		return true
	# The four corners matter: a ribbon whose centre is outside a corner of a
	# house could still slice through it.
	for point in points:
		if inside_structure(Vector2(point.x, point.z), 0.2):
			return true
	return false


## Vertex colours for the five road lanes. The core is packed earth, the verge
## is gravel, and the outermost lane leans into meadow green: the colour change
## that hides the geometric edge.
func _road_lane_tint(index: int, centre: Vector2, road_index: int) -> Color:
	var noise := sin(centre.x * 0.37 + centre.y * 0.19) * 0.5
	noise += sin(centre.x * 0.11 - centre.y * 0.43 + float(road_index)) * 0.5
	var dirt := Color(0.58, 0.43, 0.25)
	var gravel := Color(0.52, 0.49, 0.43)
	var meadow := Color(0.33, 0.45, 0.19)
	var core := dirt.lerp(gravel, 0.18 + noise * 0.04)
	if index == 1 or index == 3:
		return gravel.lerp(meadow, 0.18 + noise * 0.05)
	if index == 0 or index == 4:
		return gravel.lerp(meadow, 0.52 + noise * 0.08)
	return core


# --- door aprons -------------------------------------------------------------


## Every doorway gets a stone threshold and a short path, which is the detail
## that makes a road stop *at* a house instead of running past it. Paths are
## cut short before the carriageway and skipped where another structure owns
## the ground.
func _build_door_aprons() -> void:
	for placement in layout.placements:
		if not VillageLayout.DOOR_BUILDING_KINDS.has(placement.kind):
			continue
		var dimensions := _door_dimensions(placement)
		if dimensions.is_empty():
			continue
		var half_width: float = dimensions.half_width
		var half_depth: float = dimensions.half_depth
		var yaw := deg_to_rad(placement.rotation_deg)
		var facing := Vector2(sin(yaw), cos(yaw))
		var right := Vector2(cos(yaw), -sin(yaw))
		var start := Vector2(placement.position.x, placement.position.y) \
			+ facing * (half_depth + 0.72)
		var available := layout.road_distance(start.x, start.y)
		available -= VillageLayout.ROAD_WIDTH * 0.5 + APRON_ROAD_MARGIN
		var length := minf(APRON_LENGTH, available)
		if length < 0.35:
			continue
		var columns := 4
		var rows := 3
		for row in rows:
			for column in columns:
				var along_0 := length * float(row) / float(rows)
				var along_1 := length * float(row + 1) / float(rows)
				var across_0 := -half_width \
					+ 2.0 * half_width * float(column) / float(columns)
				var across_1 := -half_width \
					+ 2.0 * half_width * float(column + 1) / float(columns)
				# Ragged edges: the outer row and the flanks wander a little;
				# the threshold row stays true so it meets the doorstep.
				if row == rows - 1:
					along_1 += sin(float(column) * 2.4 + start.x) * 0.10
					along_0 += sin(float(column) * 1.7 + start.y) * 0.05
				if column == 0 or column == columns - 1:
					across_0 += sin(float(row) * 1.9 + start.y) * 0.06
					across_1 += sin(float(row) * 1.3 + start.x) * 0.06
				var points: Array[Vector3] = []
				for corner in [
					Vector2(across_0, along_0), Vector2(across_1, along_0),
					Vector2(across_1, along_1), Vector2(across_0, along_1),
				]:
					var flat: Vector2 = start + right * corner.x + facing * corner.y
					points.append(_ground_point(flat.x, flat.y, APRON_LIFT * 0.9))
				var centre: Vector2 = start + right * (across_0 + across_1) * 0.5 \
					+ facing * (along_0 + along_1) * 0.5
				if inside_structure(centre, 0.15):
					continue
				var wear := clampf(float(row) / float(rows - 1), 0.0, 1.0)
				var tint := Color(0.94, 0.92, 0.88).lerp(
					Color(0.78, 0.74, 0.66), wear * 0.7
				)
				_add_ground_quad(
					"paving_cobble", points, _world_uv(points), [tint, tint, tint, tint]
				)
		# The threshold itself: one wider, paler slab at the foot of the steps.
		var threshold := Vector2(placement.position.x, placement.position.y) \
			+ facing * (half_depth + 0.67)
		var threshold_points: Array[Vector3] = [
			_ground_point(
				threshold.x - right.x * (half_width + 0.18),
				threshold.y - right.y * (half_width + 0.18), APRON_LIFT + 0.004
			),
			_ground_point(
				threshold.x + right.x * (half_width + 0.18),
				threshold.y + right.y * (half_width + 0.18), APRON_LIFT + 0.004
			),
			_ground_point(
				threshold.x + right.x * (half_width + 0.18) + facing.x * 0.34,
				threshold.y + right.y * (half_width + 0.18) + facing.y * 0.34,
				APRON_LIFT + 0.004
			),
			_ground_point(
				threshold.x - right.x * (half_width + 0.18) + facing.x * 0.34,
				threshold.y - right.y * (half_width + 0.18) + facing.y * 0.34,
				APRON_LIFT + 0.004
			),
		]
		_add_ground_quad(
			"paving_cobble", threshold_points, _world_uv(threshold_points),
			[
				Color(1.0, 0.98, 0.94), Color(1.0, 0.98, 0.94),
				Color(0.93, 0.90, 0.84), Color(0.93, 0.90, 0.84),
			]
		)


# --- kerbs -------------------------------------------------------------------


func _bake_plaza_kerb(baker: MeshBaker) -> void:
	var step := TAU / float(PLAZA_KERB_STONES)
	for index in PLAZA_KERB_STONES:
		var angle := step * (float(index) + 0.5)
		var tangent := Vector2(-sin(angle), cos(angle))
		var point := Vector2(cos(angle), sin(angle)) * PLAZA_KERB_RADIUS
		if layout.distance_to_roads(point) < VillageLayout.ROAD_WIDTH * 0.5 + 0.85:
			continue
		if inside_structure(point, 0.35):
			continue
		if _rng.randf() < 0.07:
			continue
		var length := _rng.randf_range(0.92, 1.08)
		var width := _rng.randf_range(0.30, 0.36)
		# A real kerb stands 6–11 cm proud of the paving. Anything taller is a
		# step the collider-free stone would let the player walk through.
		var height := _rng.randf_range(0.13, 0.17)
		_bake_kerb_stone(
			baker, point, tangent, length, width, height, 0.06,
			_rng.randf_range(0.0, 2.0)
		)
		kerb_stone_count += 1


func _bake_road_kerb(baker: MeshBaker) -> void:
	for road_index in layout.roads.size():
		var road := layout.roads[road_index]
		var length := VillageLayout.polyline_length(road)
		var distance := 3.8
		while distance < length - 2.0:
			var sample := VillageLayout.sample_polyline(road, distance)
			var point: Vector2 = sample.point
			var tangent: Vector2 = sample.tangent
			var outward := Vector2(-tangent.y, tangent.x)
			var half := road_half_width(point, distance, road_index)
			for side: float in [-1.0, 1.0]:
				if _rng.randf() < ROAD_KERB_GAP_CHANCE:
					continue
				var stone_point := point + outward * (half + 0.12) * side
				if stone_point.length() < PLAZA_KERB_RADIUS + 0.35:
					continue
				if layout.pond_weight(stone_point.x, stone_point.y) > 0.12:
					continue
				if inside_structure(stone_point, 0.45) \
						or _near_door_apron(stone_point, 0.3):
					continue
				var stone_length := _rng.randf_range(0.72, 0.98)
				var stone_width := _rng.randf_range(0.24, 0.30)
				var stone_height := _rng.randf_range(0.12, 0.15)
				_bake_kerb_stone(
					baker, stone_point, tangent, stone_length, stone_width,
					stone_height, 0.05, 0.0
				)
				kerb_stone_count += 1
			distance += ROAD_KERB_SPACING


## Places one kerb stone on the grade: the ground is sampled at both ends of
## its length, the stone is tilted to match, and it is embedded by
## [param embed] metres. A box placed at the centre height alone used to float
## at one end on every slope.
func _bake_kerb_stone(
	baker: MeshBaker, point: Vector2, tangent: Vector2, length: float, width: float,
	height: float, embed: float, yaw_jitter: float
) -> void:
	var start := point - tangent * (length * 0.5)
	var end := point + tangent * (length * 0.5)
	var start_height := terrain.height_at(start.x, start.y)
	var end_height := terrain.height_at(end.x, end.y)
	var grade := atan2(end_height - start_height, length)
	var yaw := rad_to_deg(atan2(-tangent.y, tangent.x)) \
		+ _rng.randf_range(-yaw_jitter, yaw_jitter)
	var centre_y := (start_height + end_height) * 0.5 + height * 0.5 - embed
	var tint := Color.WHITE.darkened(_rng.randf_range(0.02, 0.15))
	baker.add_box(
		"cobble",
		Vector3(length, height, width),
		Transform3D(
			Basis.from_euler(Vector3(0.0, deg_to_rad(yaw), grade)),
			Vector3(point.x, centre_y, point.y)
		),
		tint,
		0.07
	)


func _near_door_apron(point: Vector2, margin: float) -> bool:
	for placement in layout.placements:
		if not VillageLayout.DOOR_BUILDING_KINDS.has(placement.kind):
			continue
		var dimensions := _door_dimensions(placement)
		if dimensions.is_empty():
			continue
		var yaw := deg_to_rad(placement.rotation_deg)
		var facing := Vector2(sin(yaw), cos(yaw))
		var right := Vector2(cos(yaw), -sin(yaw))
		var start: Vector2 = placement.position \
			+ facing * (dimensions.half_depth + 0.3)
		var delta := point - start
		var local_x := delta.dot(right)
		var local_z := delta.dot(facing)
		if absf(local_x) < dimensions.half_width + margin \
				and local_z > -margin and local_z < APRON_LENGTH + margin:
			return true
	return false


# --- shared helpers ----------------------------------------------------------


## Oriented half width and half depth of a structure's foundation, in world
## metres. Taken from the actual building kit, not from the conservative
## placement footprint used for prop rejection: a door apron must hug the wall.
func _structure_footprint(placement: VillageLayout.Placement) -> Vector2:
	var scale: float = placement.scale
	match placement.kind:
		VillageLayout.KIND_HOUSE:
			var variant := posmod(placement.variant, 3)
			var width := 5.8 if variant == 2 else 4.4
			var depth := 3.4 if variant == 2 else 4.0
			return Vector2(width * 0.5, depth * 0.5) * scale
		VillageLayout.KIND_INN:
			return Vector2(4.1, 2.8) * scale
		VillageLayout.KIND_HALL:
			return Vector2(4.7, 2.7) * scale
		VillageLayout.KIND_WELL:
			return Vector2(1.4, 1.4) * scale
		VillageLayout.KIND_STALL:
			return Vector2(1.4, 0.9) * scale
	return Vector2(placement.footprint_radius, placement.footprint_radius) * scale


func _door_dimensions(placement: VillageLayout.Placement) -> Dictionary:
	var scale: float = placement.scale
	match placement.kind:
		VillageLayout.KIND_HOUSE:
			var variant := posmod(placement.variant, 3)
			var depth := 3.4 if variant == 2 else 4.0
			return {
				"half_depth": depth * 0.5 * scale,
				"half_width": (1.0 * 0.5 + APRON_HALF_EXTRA) * scale,
			}
		VillageLayout.KIND_INN:
			return {
				"half_depth": 2.8 * scale,
				"half_width": (1.5 * 0.5 + APRON_HALF_EXTRA) * scale,
			}
		VillageLayout.KIND_HALL:
			return {
				"half_depth": 2.7 * scale,
				"half_width": (2.2 * 0.5 + APRON_HALF_EXTRA) * scale,
			}
	return {}


func _ground_point(x: float, z: float, lift: float) -> Vector3:
	return Vector3(x, terrain.height_at(x, z) + lift, z)


func _paving_normal(x: float, z: float) -> Vector3:
	# Blend the terrain normal with straight up: a paved surface is laid flat,
	# but it still has to follow a graded shelf without looking like a ribbon
	# of origami.
	var step := 0.6
	var dx := (terrain.height_at(x + step, z) - terrain.height_at(x - step, z)) \
		/ (step * 2.0)
	var dz := (terrain.height_at(x, z + step) - terrain.height_at(x, z - step)) \
		/ (step * 2.0)
	var slope := Vector3(-dx, 1.0, -dz).normalized()
	return (slope + Vector3.UP * 1.6).normalized()


## Arc-length UV for a ring cell: U follows the circumference, V the radius.
## Distortion is zero by construction, so a 0.4 m stone stays 0.4 m wide at the
## well and at the rim.
func _polar_uv(
	radius: float, angle: float, metres: float = PavingTextures.COBBLE_METRES
) -> Vector2:
	return Vector2(radius * angle / metres, radius / metres)


func _world_uv(
	points: Array[Vector3], metres: float = PavingTextures.COBBLE_METRES
) -> Array[Vector2]:
	var uvs: Array[Vector2] = []
	for point in points:
		uvs.append(Vector2(point.x, point.z) / metres)
	return uvs


## Emits one flat ground quad. Winding is (inner, outer, next-outer, next-inner)
## so the front face points up; normals are per-vertex and smooth, which keeps
## the sheet from shading like a pile of cardboard tiles.
func _add_ground_quad(key: String, points: Array, uvs: Array, tints: Array) -> void:
	var tool := _surface(key)
	var normals: Array[Vector3] = []
	for point in points:
		normals.append(_paving_normal(point.x, point.z))
	for index in 6:
		var vertex := index
		if index == 3:
			vertex = 0
		elif index == 4:
			vertex = 2
		elif index == 5:
			vertex = 3
		_emit_vertex(tool, points[vertex], normals[vertex], uvs[vertex], tints[vertex])
	triangle_count += 2


func _emit_vertex(
	tool: SurfaceTool, position: Vector3, normal: Vector3, uv: Vector2, tint: Color
) -> void:
	tool.set_normal(normal)
	tool.set_uv(uv)
	tool.set_color(tint)
	tool.add_vertex(position)
	_vertices.append(position)
	vertex_count += 1


func _surface(key: String) -> SurfaceTool:
	if _tools.has(key):
		return _tools[key] as SurfaceTool
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tools[key] = tool
	return tool
