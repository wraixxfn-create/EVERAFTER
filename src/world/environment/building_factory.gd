class_name BuildingFactory
extends RefCounted
## Builds the village structures out of merged primitives: houses, the inn, the
## council hall, the well, the market stalls and the small props.
##
## Art direction (deliberate and consistent):
## * plaster walls over a dark timber frame, stone plinth, pitched tile roof,
##   one chimney, small shuttered windows — the silhouette of a northern
##   European village, readable at a glance and cheap to draw;
## * three house variants with different footprints, storeys and roof pitches,
##   so the skyline is not a row of identical boxes;
## * one shared palette (`VillageMaterials`) with per solid vertex colour tint,
##   so every building differs slightly without a single extra material.
##
## Every solid goes through [MeshBaker], so a house is a handful of draw calls
## instead of a dozen, and the whole market row costs almost nothing.
##
## Colliders are returned separately from the meshes: a building blocks the
## player, a lamp post and a blade of grass do not.

const WALL_KEYS := ["wall_cream", "wall_ochre", "wall_ash", "wall_pale"]
const ROOF_KEYS := ["roof_tile", "roof_shingle", "roof_slate", "roof_moss"]
const CLOTH_KEYS := ["cloth_red", "cloth_blue", "cloth_cream"]

var materials: VillageMaterials = null
var rng := RandomNumberGenerator.new()

## Transform every solid built from now on is relative to. Structures leave it
## at identity (their own node carries the placement transform); merged props
## set it to the placement's world transform, because they share one mesh and
## have no node of their own.
var _origin := Transform3D.IDENTITY


func _init(shared_materials: VillageMaterials, seed_value: int = 0) -> void:
	materials = shared_materials
	rng.seed = seed_value


## True for the kinds that get their own node and their own collider body.
static func is_structure(kind: String) -> bool:
	return kind in [
		VillageLayout.KIND_HOUSE,
		VillageLayout.KIND_INN,
		VillageLayout.KIND_HALL,
		VillageLayout.KIND_WELL,
		VillageLayout.KIND_STALL,
	]


## Builds one structure as a self contained node: baked meshes plus a
## `StaticBody3D` with the colliders that keep the player outside.
func build_structure(placement: VillageLayout.Placement) -> Node3D:
	var node := Node3D.new()
	node.name = placement.id
	var baker := MeshBaker.new()
	bake_structure(baker, placement)
	for baked in baker.commit(materials):
		node.add_child(baked)
	var shapes := colliders_for(placement)
	if not shapes.is_empty():
		var body := StaticBody3D.new()
		body.name = "Collision"
		for shape in shapes:
			body.add_child(shape)
		node.add_child(body)
	return node


## Adds every solid of a structure to [param baker]. Exposed so that the tests
## can inspect which materials a building needs without instantiating nodes.
func bake_structure(baker: MeshBaker, placement: VillageLayout.Placement) -> void:
	match placement.kind:
		VillageLayout.KIND_HOUSE:
			_build_house(baker, placement)
		VillageLayout.KIND_INN:
			_build_inn(baker)
		VillageLayout.KIND_HALL:
			_build_hall(baker)
		VillageLayout.KIND_WELL:
			_build_well(baker)
		VillageLayout.KIND_STALL:
			_build_stall(baker, placement)


## Collision shapes for a placement, positioned in the placement's local space.
## Empty for props that must not block the player.
func colliders_for(placement: VillageLayout.Placement) -> Array:
	var shapes: Array = []
	var scale := placement.scale
	match placement.kind:
		VillageLayout.KIND_HOUSE:
			shapes.append(_box_collider(Vector3(4.6, 4.0, 4.4) * scale, Vector3(0, 2.0, 0) * scale))
		VillageLayout.KIND_INN:
			shapes.append(_box_collider(Vector3(8.4, 6.0, 6.0) * scale, Vector3(0, 3.0, 0) * scale))
			# The L shaped wing needs its own box, or the player walks through it.
			shapes.append(
				_box_collider(Vector3(3.4, 3.4, 3.4) * scale, Vector3(-5.0, 1.7, 1.6) * scale)
			)
		VillageLayout.KIND_HALL:
			shapes.append(_box_collider(Vector3(10.0, 5.0, 6.0) * scale, Vector3(0, 2.5, 0) * scale))
			shapes.append(
				_box_collider(Vector3(3.2, 9.0, 3.2) * scale, Vector3(-5.4, 4.5, 0.0) * scale)
			)
		VillageLayout.KIND_WELL:
			shapes.append(_cylinder_collider(1.15 * scale, 1.1 * scale, Vector3.ZERO))
		VillageLayout.KIND_STALL:
			shapes.append(
				_box_collider(Vector3(2.6, 1.1, 1.6) * scale, Vector3(0.0, 0.55, -0.55) * scale)
			)
		VillageLayout.KIND_CART:
			shapes.append(_box_collider(Vector3(1.8, 1.0, 3.0) * scale, Vector3(0, 0.6, 0) * scale))
		VillageLayout.KIND_LOGPILE:
			shapes.append(_box_collider(Vector3(2.6, 1.2, 1.4) * scale, Vector3(0, 0.6, 0) * scale))
		VillageLayout.KIND_CRATE:
			shapes.append(_box_collider(Vector3(1.2, 1.2, 1.2) * scale, Vector3(0, 0.6, 0) * scale))
		VillageLayout.KIND_BARREL:
			shapes.append(_cylinder_collider(0.5 * scale, 1.1 * scale, Vector3.ZERO))
		VillageLayout.KIND_FENCE:
			shapes.append(_box_collider(Vector3(3.0, 1.1, 0.2) * scale, Vector3(0, 0.55, 0) * scale))
	return shapes


## Adds a small prop to a shared baker. Called for every lamp, fence, cart,
## crate, barrel, log pile and signpost, so all of them end up in one mesh.
func append_prop(
	baker: MeshBaker, placement: VillageLayout.Placement, origin: Transform3D
) -> void:
	_origin = origin
	match placement.kind:
		VillageLayout.KIND_LAMP:
			_build_lamp(baker)
		VillageLayout.KIND_FENCE:
			_build_fence(baker)
		VillageLayout.KIND_CART:
			_build_cart(baker)
		VillageLayout.KIND_CRATE:
			_build_crate(baker, placement)
		VillageLayout.KIND_BARREL:
			_build_barrel(baker)
		VillageLayout.KIND_LOGPILE:
			_build_logpile(baker)
		VillageLayout.KIND_SIGNPOST:
			_build_signpost(baker)
	_origin = Transform3D.IDENTITY


# --- structures --------------------------------------------------------------


func _build_house(baker: MeshBaker, placement: VillageLayout.Placement) -> void:
	var scale := placement.scale
	var two_storey := placement.variant == 1
	var long_body := placement.variant == 2
	var width := (4.4 if not long_body else 5.8) * scale
	var depth := (4.0 if not long_body else 3.4) * scale
	var wall_height := (4.2 if two_storey else 2.6) * scale
	var roof_rise := (1.9 if two_storey else 1.6) * scale
	var wall_key: String = WALL_KEYS[
		(placement.variant + rng.randi_range(0, 1)) % WALL_KEYS.size()
	]
	var roof_key: String = ROOF_KEYS[placement.variant % ROOF_KEYS.size()]
	var roof_tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.12))

	_body(baker, wall_key, roof_key, roof_tint, width, depth, wall_height, roof_rise, scale)
	_timber_frame(baker, width, depth, wall_height, scale)
	# Door on the +Z face, which the layout turns towards the road.
	baker.add_box(
		"door", Vector3(0.95, 1.85, 0.14) * scale,
		_transform(Vector3(0.0, 0.92, depth * 0.5) * scale)
	)
	baker.add_box(
		"timber", Vector3(1.25, 0.16, 0.2) * scale,
		_transform(Vector3(0.0, 1.92, depth * 0.5) * scale)
	)
	_windows(baker, width, depth, wall_height, 2 + placement.variant, scale)
	if not two_storey:
		_chimney(baker, Vector3(width * 0.28, wall_height + roof_rise, -depth * 0.18), scale)
	else:
		_chimney(baker, Vector3(width * 0.3, wall_height + roof_rise * 0.6, -depth * 0.2), scale)
	if long_body:
		_porch(baker, width, depth, scale)


func _build_inn(baker: MeshBaker) -> void:
	var width := 8.2
	var depth := 5.6
	var wall_height := 5.0
	var roof_rise := 2.4
	_body(baker, "wall_ochre", "roof_shingle", Color.WHITE, width, depth, wall_height, roof_rise, 1.0)
	_timber_frame(baker, width, depth, wall_height, 1.0)
	# A second, lower wing gives the inn an L shaped silhouette.
	var wing := Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(90), 0)), Vector3(-5.0, 0, 1.6))
	var wing_baker := baker
	wing_baker.add_box(
		"stone_dark", Vector3(3.6, 0.4, 3.6), _compose(wing, Vector3(0, 0.2, 0))
	)
	wing_baker.add_box(
		"wall_ash", Vector3(3.2, 2.8, 3.2), _compose(wing, Vector3(0, 1.8, 0))
	)
	wing_baker.add_prism(
		"roof_tile", 4.0, 1.5, 3.6, _compose(wing, Vector3(0, 3.95, 0)), Color(0.94, 0.94, 0.94)
	)
	# Porch along the front: two posts and a leaning canopy over the entrance.
	for side in [-1.0, 1.0]:
		baker.add_box(
			"timber", Vector3(0.26, 2.6, 0.26), _transform(Vector3(side * 2.2, 1.3, depth * 0.5 + 1.4))
		)
	baker.add_box(
		"plank", Vector3(5.2, 0.18, 1.9),
		_transform(Vector3(0.0, 2.75, depth * 0.5 + 0.8), -14.0)
	)
	# Hanging sign: the one thing that says "inn" from across the plaza.
	baker.add_box(
		"timber", Vector3(0.16, 0.16, 2.2), _transform(Vector3(width * 0.5, 3.6, depth * 0.5 + 1.1))
	)
	baker.add_box(
		"plank", Vector3(1.5, 1.0, 0.12),
		_transform(Vector3(width * 0.5, 2.9, depth * 0.5 + 2.0))
	)
	baker.add_box(
		"cloth_red", Vector3(1.2, 0.7, 0.16),
		_transform(Vector3(width * 0.5, 2.9, depth * 0.5 + 2.02))
	)
	_windows(baker, width, depth, wall_height, 6, 1.0)
	_chimney(baker, Vector3(width * 0.3, wall_height + roof_rise * 0.7, -depth * 0.15), 1.3)
	baker.add_box(
		"door", Vector3(1.5, 2.4, 0.16), _transform(Vector3(0.0, 1.2, depth * 0.5))
	)


func _build_hall(baker: MeshBaker) -> void:
	var width := 9.4
	var depth := 5.4
	var wall_height := 3.8
	# Long body with the ridge across it, so the gable faces the plaza.
	baker.add_box(
		"stone_dark", Vector3(width + 0.6, 0.5, depth + 0.6), _transform(Vector3(0, 0.25, 0))
	)
	baker.add_box("stone", Vector3(width, wall_height, depth), _transform(Vector3(0, 2.4, 0)))
	baker.add_prism(
		"roof_slate", depth + 1.0, 2.1, width + 1.0,
		_transform(Vector3(0.0, wall_height + 1.55, 0.0), 90.0)
	)
	# Bell tower on the west end: the tallest thing in the village.
	baker.add_box("stone_dark", Vector3(3.2, 9.0, 3.2), _transform(Vector3(-5.4, 4.5, 0.0)))
	baker.add_box("stone", Vector3(3.5, 0.4, 3.5), _transform(Vector3(-5.4, 8.2, 0.0)))
	baker.add_cylinder("roof_slate", 0.0, 2.5, 2.6, 4, _transform(Vector3(-5.4, 9.7, 0.0), 45.0))
	baker.add_box("iron", Vector3(0.12, 1.6, 0.12), _transform(Vector3(-5.4, 11.6, 0.0)))
	baker.add_box("window", Vector3(1.1, 1.5, 0.2), _transform(Vector3(-5.4, 7.2, 1.65)))
	# Arched entrance: a wide door between two pilasters.
	for side in [-1.0, 1.0]:
		baker.add_box(
			"stone_dark", Vector3(0.5, 3.4, 0.5),
			_transform(Vector3(side * 1.3, 1.9, depth * 0.5))
		)
	baker.add_box("door", Vector3(2.2, 3.0, 0.18), _transform(Vector3(0.0, 1.7, depth * 0.5)))
	baker.add_box("stone_dark", Vector3(2.8, 0.5, 0.6), _transform(Vector3(0.0, 3.35, depth * 0.5)))
	# Tall windows along the south wall.
	for index in 3:
		var x := -2.6 + float(index) * 2.6
		baker.add_box("window", Vector3(0.9, 2.0, 0.18), _transform(Vector3(x, 2.4, depth * 0.5 + 0.02)))
		baker.add_box("timber", Vector3(1.1, 0.12, 0.22), _transform(Vector3(x, 3.5, depth * 0.5)))
		baker.add_box("timber", Vector3(1.1, 0.12, 0.22), _transform(Vector3(x, 1.3, depth * 0.5)))


func _build_well(baker: MeshBaker) -> void:
	baker.add_cylinder("stone", 1.15, 1.25, 0.95, 12, _transform(Vector3(0, 0.48, 0)))
	baker.add_cylinder("stone_dark", 1.0, 1.05, 0.2, 12, _transform(Vector3(0, 1.0, 0)))
	baker.add_cylinder("water", 0.92, 0.92, 0.06, 12, _transform(Vector3(0, 0.72, 0)))
	for side in [-1.0, 1.0]:
		baker.add_box("timber", Vector3(0.2, 2.3, 0.2), _transform(Vector3(side * 1.0, 1.6, 0.0)))
	baker.add_prism("roof_shingle", 2.9, 0.9, 2.2, _transform(Vector3(0.0, 3.15, 0.0), 90.0))
	baker.add_box("timber", Vector3(2.2, 0.16, 0.16), _transform(Vector3(0.0, 2.6, 0.0)))
	baker.add_box("plank", Vector3(0.6, 0.6, 0.6), _transform(Vector3(0.0, 1.9, 0.0)))


func _build_stall(baker: MeshBaker, placement: VillageLayout.Placement) -> void:
	var cloth_key: String = CLOTH_KEYS[placement.variant % CLOTH_KEYS.size()]
	var corners := [
		Vector3(-1.2, 0, -0.7), Vector3(1.2, 0, -0.7),
		Vector3(-1.2, 0, 0.7), Vector3(1.2, 0, 0.7),
	]
	for corner in corners:
		baker.add_box("timber", Vector3(0.14, 2.2, 0.14), _transform(corner + Vector3(0, 1.1, 0)))
	baker.add_box("plank", Vector3(2.6, 0.14, 1.5), _transform(Vector3(0.0, 1.05, -0.1)))
	baker.add_box(cloth_key, Vector3(2.9, 0.1, 2.0), _transform(Vector3(0.0, 2.3, 0.0), -10.0))
	# Goods on the counter.
	for index in 3:
		baker.add_box(
			"timber_warm" if index == 1 else "plank",
			Vector3(0.42, 0.34, 0.42),
			_transform(Vector3(-0.8 + float(index) * 0.8, 1.29, -0.1)),
			Color(0.9, 0.85, 0.75) if index != 1 else Color.WHITE
		)


# --- small props -------------------------------------------------------------


func _build_lamp(baker: MeshBaker) -> void:
	baker.add_cylinder("stone_dark", 0.22, 0.3, 0.35, 8, _transform(Vector3(0, 0.18, 0)))
	baker.add_cylinder("iron", 0.09, 0.12, 3.1, 6, _transform(Vector3(0, 1.9, 0)))
	baker.add_box("iron", Vector3(0.7, 0.1, 0.1), _transform(Vector3(0.3, 3.4, 0.0)))
	baker.add_box("lantern", Vector3(0.34, 0.44, 0.34), _transform(Vector3(0.62, 3.15, 0.0)))
	baker.add_cylinder("iron", 0.02, 0.26, 0.16, 4, _transform(Vector3(0.62, 3.44, 0.0)))


func _build_fence(baker: MeshBaker) -> void:
	for side in [-1.0, 1.0]:
		baker.add_box("timber_warm", Vector3(0.16, 1.15, 0.16), _transform(Vector3(side * 1.4, 0.58, 0)))
	for height in [0.55, 0.95]:
		baker.add_box("timber_warm", Vector3(3.0, 0.12, 0.09), _transform(Vector3(0.0, height, 0.0)))


func _build_cart(baker: MeshBaker) -> void:
	baker.add_box("plank", Vector3(1.7, 0.16, 2.9), _transform(Vector3(0.0, 0.72, 0.0)))
	for side in [-1.0, 1.0]:
		baker.add_box("plank", Vector3(0.12, 0.5, 2.9), _transform(Vector3(side * 0.82, 1.0, 0.0)))
	baker.add_box("plank", Vector3(1.7, 0.5, 0.12), _transform(Vector3(0.0, 1.0, -1.42)))
	for side in [-1.0, 1.0]:
		baker.add_cylinder(
			"timber", 0.52, 0.52, 0.14, 10,
			_transform(Vector3(side * 0.9, 0.52, 0.9), 0.0, 90.0)
		)
	baker.add_box("timber", Vector3(0.12, 0.12, 1.6), _transform(Vector3(0.0, 0.66, 2.1), -12.0))
	baker.add_box("cloth_cream", Vector3(1.4, 0.5, 1.4), _transform(Vector3(0.0, 1.1, -0.4)))


func _build_crate(baker: MeshBaker, placement: VillageLayout.Placement) -> void:
	var size := 1.05 * placement.scale
	baker.add_box("plank", Vector3(size, size, size), _transform(Vector3(0.0, size * 0.5, 0.0)))
	for offset in [-size * 0.35, size * 0.35]:
		baker.add_box(
			"timber", Vector3(size * 1.02, 0.1, size * 1.02),
			_transform(Vector3(0.0, size * 0.5 + offset, 0.0))
		)
	if placement.variant == 1:
		baker.add_box(
			"plank", Vector3(size * 0.8, size * 0.8, size * 0.8),
			_transform(Vector3(0.2, size * 1.4, 0.15), 18.0)
		)


func _build_barrel(baker: MeshBaker) -> void:
	baker.add_cylinder("plank", 0.42, 0.46, 1.05, 10, _transform(Vector3(0, 0.52, 0)))
	for height in [0.25, 0.8]:
		baker.add_cylinder("iron", 0.47, 0.47, 0.08, 10, _transform(Vector3(0.0, height, 0.0)))


func _build_logpile(baker: MeshBaker) -> void:
	for row in 3:
		var count := 4 - row
		for index in count:
			var x := (float(index) - float(count - 1) * 0.5) * 0.62
			baker.add_cylinder(
				"trunk", 0.28, 0.28, 2.4, 7,
				_transform(Vector3(x, 0.3 + float(row) * 0.55, 0.0), 0.0, 90.0),
				Color.WHITE.darkened(float(row) * 0.05)
			)


func _build_signpost(baker: MeshBaker) -> void:
	baker.add_cylinder("timber", 0.1, 0.13, 2.5, 6, _transform(Vector3(0, 1.25, 0)))
	baker.add_box("plank", Vector3(1.7, 0.36, 0.1), _transform(Vector3(0.6, 2.1, 0.0), 0.0, 0.0, 8.0))
	baker.add_box(
		"plank", Vector3(1.4, 0.32, 0.1), _transform(Vector3(-0.5, 1.7, 0.0), 0.0, 0.0, -6.0)
	)
	baker.add_cylinder("iron", 0.0, 0.14, 0.3, 4, _transform(Vector3(0.0, 2.6, 0.0)))


# --- shared parts ------------------------------------------------------------


func _body(
	baker: MeshBaker, wall_key: String, roof_key: String, roof_tint: Color, width: float,
	depth: float, wall_height: float, roof_rise: float, scale: float
) -> void:
	# Stone plinth, plaster walls, gable roof with a small eaves overhang.
	baker.add_box(
		"stone_dark", Vector3(width + 0.4, 0.42, depth + 0.4) * scale,
		_transform(Vector3(0.0, 0.21, 0.0) * scale)
	)
	baker.add_box(
		wall_key, Vector3(width, wall_height, depth) * scale,
		_transform(Vector3(0.0, 0.42 + wall_height * 0.5, 0.0) * scale),
		Color.WHITE.darkened(rng.randf_range(0.0, 0.06))
	)
	var roof_width := (width + 0.7) * scale
	var roof_depth := (depth + 0.7) * scale
	baker.add_prism(
		roof_key, roof_width, roof_rise * scale, roof_depth,
		_transform(Vector3(0.0, (0.42 + wall_height + roof_rise * 0.5) * scale, 0.0)),
		roof_tint
	)
	# Ridge beam: one dark line that ties the roof together.
	baker.add_box(
		"timber", Vector3(0.2, 0.16, roof_depth) * scale,
		_transform(Vector3(0.0, (0.42 + wall_height + roof_rise) * scale, 0.0))
	)


func _timber_frame(
	baker: MeshBaker, width: float, depth: float, wall_height: float, scale: float
) -> void:
	var top := (0.42 + wall_height) * scale
	var bottom := 0.42 * scale
	var height := top - bottom
	for side in [-1.0, 1.0]:
		# Corner posts on the front and back faces.
		for depth_side in [-1.0, 1.0]:
			baker.add_box(
				"timber", Vector3(0.2, height, 0.2) * scale,
				_transform(Vector3(side * width * 0.5, (bottom + top) * 0.5, depth_side * depth * 0.5))
			)
		# Sill and head beams.
		for y in [bottom + 0.1 * scale, top - 0.1 * scale]:
			baker.add_box(
				"timber", Vector3(width, 0.18, 0.22) * scale,
				_transform(Vector3(0.0, y, depth * 0.5))
			)
			baker.add_box(
				"timber", Vector3(width, 0.18, 0.22) * scale,
				_transform(Vector3(0.0, y, -depth * 0.5))
			)
		# One diagonal brace per side face: the cheapest way to read "timber frame".
		var brace_length := sqrt(pow(depth, 2) + pow(height * 0.55, 2)) * scale
		var brace_angle := rad_to_deg(atan2(height * 0.55, depth))
		baker.add_box(
			"timber", Vector3(0.16, brace_length, 0.16),
			_transform(
				Vector3(side * width * 0.5, bottom + height * 0.35, 0.0),
				0.0, 0.0, brace_angle * side
			)
		)


func _windows(
	baker: MeshBaker, width: float, depth: float, wall_height: float, count: int, scale: float
) -> void:
	var y := (0.42 + wall_height * 0.6) * scale
	for index in count:
		var side := 1.0 if index % 2 == 0 else -1.0
		var spread := (floorf(float(index) * 0.5) - 0.5) * width * 0.45
		# Front and back walls.
		baker.add_box(
			"window", Vector3(0.72, 0.85, 0.14) * scale,
			_transform(Vector3(spread, y, side * depth * 0.5))
		)
		baker.add_box(
			"timber", Vector3(0.9, 0.1, 0.2) * scale,
			_transform(Vector3(spread, y + 0.5 * scale, side * depth * 0.5))
		)
	# One window on each gable end.
	for side in [-1.0, 1.0]:
		baker.add_box(
			"window", Vector3(0.14, 0.7, 0.6) * scale,
			_transform(Vector3(side * width * 0.5, y * 0.95, 0.0))
		)


func _chimney(baker: MeshBaker, position: Vector3, scale: float) -> void:
	baker.add_box("stone", Vector3(0.75, 2.4, 0.75) * scale, _transform(position))
	baker.add_box(
		"stone_dark", Vector3(0.95, 0.2, 0.95) * scale,
		_transform(position + Vector3(0, 1.2, 0) * scale)
	)


func _porch(baker: MeshBaker, width: float, depth: float, scale: float) -> void:
	for side in [-1.0, 1.0]:
		baker.add_box(
			"timber", Vector3(0.2, 2.2, 0.2) * scale,
			_transform(Vector3(side * width * 0.3, 1.1, depth * 0.5 + 1.0))
		)
	baker.add_box(
		"roof_shingle", Vector3(width * 0.8, 0.14, 1.6) * scale,
		_transform(Vector3(0.0, 2.35, depth * 0.5 + 0.6), -12.0)
	)


# --- helpers -----------------------------------------------------------------


func _transform(
	position: Vector3, yaw_deg: float = 0.0, pitch_deg: float = 0.0, roll_deg: float = 0.0
) -> Transform3D:
	var basis := Basis.from_euler(
		Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), deg_to_rad(roll_deg))
	)
	return _origin * Transform3D(basis, position)


func _compose(outer: Transform3D, offset: Vector3) -> Transform3D:
	return _origin * outer * Transform3D(Basis.IDENTITY, offset)


func _box_collider(size: Vector3, offset: Vector3) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return _collider_node(shape, offset)


func _cylinder_collider(radius: float, height: float, offset: Vector3) -> CollisionShape3D:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	return _collider_node(shape, offset + Vector3(0.0, height * 0.5, 0.0))


func _collider_node(shape: Shape3D, offset: Vector3) -> CollisionShape3D:
	var node := CollisionShape3D.new()
	node.shape = shape
	node.position = offset
	return node
