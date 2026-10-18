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
var _surface_details: BuildingSurfaceDetails = null

## Transform every solid built from now on is relative to. Structures leave it
## at identity (their own node carries the placement transform); merged props
## set it to the placement's world transform, because they share one mesh and
## have no node of their own.
var _origin := Transform3D.IDENTITY


func _init(shared_materials: VillageMaterials, seed_value: int = 0) -> void:
	materials = shared_materials
	rng.seed = seed_value
	_surface_details = BuildingSurfaceDetails.new(rng)


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
		VillageLayout.KIND_FLOWER_BOX:
			_build_flower_box(baker, placement)
		VillageLayout.KIND_BENCH:
			_build_bench(baker)
	_origin = Transform3D.IDENTITY


# --- structures --------------------------------------------------------------


func _build_house(baker: MeshBaker, placement: VillageLayout.Placement) -> void:
	var scale := placement.scale
	var two_storey := placement.variant == 1
	var long_body := placement.variant == 2
	# Keep dimensions in model space here: the shared builders apply the
	# placement scale exactly once to both size and offset.
	var width := 4.4 if not long_body else 5.8
	var depth := 4.0 if not long_body else 3.4
	var wall_height := 4.2 if two_storey else 2.6
	var roof_rise := 1.9 if two_storey else 1.6
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
	_surface_details.add_door_details(baker, 0.0, 0.92, 0.95, 1.85, depth * 0.5, scale)
	# Stone stoop in front of the door, from the ground to just above the
	# plinth: grounds the entrance instead of letting it float on the plaster.
	baker.add_box(
		"stone_dark", Vector3(1.35, 0.5, 0.8) * scale,
		_transform(Vector3(0.0, 0.25, depth * 0.5 + 0.35) * scale)
	)
	_windows(
		baker, width, depth, wall_height, 2 + placement.variant, scale,
		CLOTH_KEYS[placement.variant % CLOTH_KEYS.size()]
	)
	_window_flower_boxes(baker, width, depth, wall_height, 2 + placement.variant, scale)
	if not two_storey:
		_chimney(
			baker, Vector3(width * 0.28, wall_height + roof_rise, -depth * 0.18),
			scale, scale
		)
	else:
		_chimney(
			baker, Vector3(width * 0.3, wall_height + roof_rise * 0.6, -depth * 0.2),
			scale, scale
		)
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
	var wing_roof_center := _compose(wing, Vector3(0.0, 3.95, 0.0))
	wing_baker.add_prism(
		"roof_tile", 4.0, 1.5, 3.6, wing_roof_center, Color(0.94, 0.94, 0.94)
	)
	_surface_details.add_roof_details(
		baker, "roof_tile", Color(0.94, 0.94, 0.94), 4.0, 3.6, 1.5,
		3.2, wing_roof_center, 1.0
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
	_windows(baker, width, depth, wall_height, 6, 1.0, "cloth_cream")
	_window_flower_boxes(baker, width, depth, wall_height, 6, 1.0)
	# Lived-in porch: a bench against the wall beside the door and a barrel by
	# the far post. Both clear the entrance corridor and the L shaped wing.
	_build_bench(baker, Vector3(2.85, 0.0, depth * 0.5 + 0.55))
	_build_barrel(baker, Vector3(-2.9, 0.0, depth * 0.5 + 1.3))
	_chimney(baker, Vector3(width * 0.3, wall_height + roof_rise * 0.7, -depth * 0.15), 1.3)
	baker.add_box(
		"door", Vector3(1.5, 2.4, 0.16), _transform(Vector3(0.0, 1.2, depth * 0.5))
	)
	_surface_details.add_door_details(baker, 0.0, 1.2, 1.5, 2.4, depth * 0.5, 1.0)


func _build_hall(baker: MeshBaker) -> void:
	var width := 9.4
	var depth := 5.4
	var wall_height := 3.8
	# Long stone body with a roof whose gable faces the plaza.
	baker.add_box(
		"stone_dark", Vector3(width + 0.6, 0.5, depth + 0.6),
		_transform(Vector3(0.0, 0.25, 0.0)), Color.WHITE, 0.08
	)
	_surface_details.add_masonry_plinth(baker, width, depth, 0.5)
	baker.add_box(
		"stone", Vector3(width, wall_height, depth),
		_transform(Vector3(0.0, 2.4, 0.0)), Color.WHITE, 0.06
	)
	_surface_details.add_stone_wall_courses(baker, width, depth, wall_height, 0.5)
	var roof_center := _transform(Vector3(0.0, wall_height + 1.55, 0.0), 90.0)
	var roof_width := depth + 1.0
	var roof_depth := width + 1.0
	baker.add_prism("roof_slate", roof_width, 2.1, roof_depth, roof_center)
	_surface_details.add_roof_details(
		baker, "roof_slate", Color.WHITE, roof_width, roof_depth, 2.1,
		0.5 + wall_height, roof_center, 1.0
	)
	# Bell tower on the west end: the tallest thing in the village. Its block
	# courses and inset openings make the height read as masonry, not one pillar.
	var tower_center := Vector3(-5.4, 0.0, 0.0)
	baker.add_box(
		"stone_dark", Vector3(3.2, 9.0, 3.2),
		_transform(Vector3(-5.4, 4.5, 0.0)), Color.WHITE, 0.08
	)
	_surface_details.add_stone_wall_courses(baker, 3.2, 3.2, 9.0, 0.0, tower_center)
	baker.add_box(
		"stone", Vector3(3.5, 0.4, 3.5), _transform(Vector3(-5.4, 8.2, 0.0)),
		Color.WHITE, 0.08
	)
	baker.add_cylinder(
		"roof_slate", 0.0, 2.5, 2.6, 4,
		_transform(Vector3(-5.4, 9.7, 0.0), 45.0), Color.WHITE, 0.05
	)
	baker.add_box("iron", Vector3(0.12, 1.6, 0.12), _transform(Vector3(-5.4, 11.6, 0.0)))
	baker.add_box(
		"window", Vector3(1.1, 1.5, 0.2), _transform(Vector3(-5.4, 7.2, 1.65))
	)
	# Narrow bell vents on the side faces echo medieval belfries and help break
	# the tower's broad stone silhouette.
	for side in [-1.0, 1.0]:
		baker.add_box(
			"window", Vector3(0.18, 0.9, 0.12),
			_transform(Vector3(-5.4 + side * 1.65, 7.0, 0.0))
		)
	# Arched entrance: a wide door between two pilasters.
	for side in [-1.0, 1.0]:
		baker.add_box(
			"stone_dark", Vector3(0.5, 3.4, 0.5),
			_transform(Vector3(side * 1.3, 1.9, depth * 0.5))
		)
	baker.add_box("door", Vector3(2.2, 3.0, 0.18), _transform(Vector3(0.0, 1.7, depth * 0.5)))
	_surface_details.add_door_details(baker, 0.0, 1.7, 2.2, 3.0, depth * 0.5, 1.0, false)
	baker.add_box("stone_dark", Vector3(2.8, 0.5, 0.6), _transform(Vector3(0.0, 3.35, depth * 0.5)))
	# Tall windows flanking the entrance (the old centre slot collided with the
	# door and read as a prototype artifact).
	for x in [-3.5, 3.5]:
		var window_y := 2.4
		var window_z := depth * 0.5 + 0.08
		var frame_z := depth * 0.5 + 0.18
		baker.add_box(
			"window", Vector3(0.9, 2.0, 0.18),
			_transform(Vector3(x, window_y, window_z))
		)
		for side in [-1.0, 1.0]:
			baker.add_box(
				"timber", Vector3(0.12, 2.2, 0.18),
				_transform(Vector3(x + side * 0.51, window_y, frame_z)),
				Color.WHITE, 0.04
			)
		baker.add_box(
			"timber", Vector3(1.12, 0.13, 0.2),
			_transform(Vector3(x, 3.48, frame_z)), Color.WHITE, 0.04
		)
		baker.add_box(
			"stone", Vector3(1.18, 0.16, 0.28),
			_transform(Vector3(x, 1.28, frame_z)), Color.WHITE.darkened(0.04), 0.06
		)
		baker.add_box(
			"timber", Vector3(0.055, 1.84, 0.06),
			_transform(Vector3(x, window_y, frame_z + 0.02)), Color.WHITE, 0.04
		)
		baker.add_box(
			"timber", Vector3(0.88, 0.055, 0.06),
			_transform(Vector3(x, window_y, frame_z + 0.02)), Color.WHITE, 0.04
		)
	# Civic banners flanking the entrance: one bold colour accent on the stone.
	for side in [-1.0, 1.0]:
		baker.add_box(
			"timber", Vector3(0.95, 0.12, 0.16), _transform(Vector3(side * 2.1, 4.05, depth * 0.5 + 0.1))
		)
		baker.add_box(
			"cloth_red", Vector3(0.75, 2.35, 0.08),
			_transform(Vector3(side * 2.1, 2.8, depth * 0.5 + 0.1))
		)
	# A lantern over the entrance arch: the door the village looks for after
	# dark. `SkyRig` lights the shared lantern material at dusk.
	baker.add_box(
		"iron", Vector3(0.1, 0.1, 0.55),
		_transform(Vector3(0.0, 3.95, depth * 0.5 + 0.28))
	)
	baker.add_box(
		"lantern", Vector3(0.32, 0.42, 0.32),
		_transform(Vector3(0.0, 3.62, depth * 0.5 + 0.5))
	)
	baker.add_cylinder(
		"iron", 0.02, 0.22, 0.14, 4,
		_transform(Vector3(0.0, 3.9, depth * 0.5 + 0.5))
	)


func _build_well(baker: MeshBaker) -> void:
	baker.add_cylinder(
		"stone", 1.15, 1.25, 0.95, 12, _transform(Vector3(0.0, 0.48, 0.0)),
		Color.WHITE, 0.04
	)
	# Two staggered courses of rough ashlar wrap the basin, keeping the well's
	# round silhouette while replacing the featureless cylinder wall.
	for course in 2:
		var y := 0.24 + float(course) * 0.45
		var stagger := 0.5 if course % 2 == 1 else 0.0
		for segment in 12:
			var angle := TAU * (float(segment) + stagger) / 12.0
			var x := cos(angle) * 1.18
			var z := sin(angle) * 1.18
			var yaw := rad_to_deg(atan2(x, z))
			var tint := Color.WHITE.darkened(rng.randf_range(0.015, 0.12))
			baker.add_box(
				"stone", Vector3(0.56, 0.38, 0.22),
				_transform(Vector3(x, y, z), yaw), tint, 0.1
			)
	baker.add_cylinder(
		"stone_dark", 1.0, 1.05, 0.2, 12,
		_transform(Vector3(0.0, 1.0, 0.0)), Color.WHITE, 0.05
	)
	baker.add_cylinder(
		"water", 0.92, 0.92, 0.06, 12, _transform(Vector3(0.0, 0.72, 0.0))
	)
	for side in [-1.0, 1.0]:
		baker.add_box(
			"timber", Vector3(0.2, 2.3, 0.2),
			_transform(Vector3(side * 1.0, 1.6, 0.0)), Color.WHITE, 0.04
		)
	var well_roof_center := _transform(Vector3(0.0, 3.15, 0.0), 90.0)
	baker.add_prism("roof_shingle", 2.9, 0.9, 2.2, well_roof_center)
	_surface_details.add_roof_details(
		baker, "roof_shingle", Color.WHITE, 2.9, 2.2, 0.9,
		2.7, well_roof_center, 1.0
	)
	baker.add_box("timber", Vector3(2.2, 0.16, 0.16), _transform(Vector3(0.0, 2.6, 0.0)))
	baker.add_box("plank", Vector3(0.6, 0.6, 0.6), _transform(Vector3(0.0, 1.9, 0.0)))
	# A bucket on the stones beside the basin: the well is used, not staged.
	# It sits outside the well collider (r 1.15), so it never blocks the ring.
	var bucket_turn := rng.randf_range(0.0, 360.0)
	baker.add_cylinder(
		"plank", 0.26, 0.21, 0.34, 8,
		_transform(Vector3(1.55, 0.17, 0.85), bucket_turn), Color.WHITE, 0.06
	)
	baker.add_cylinder(
		"iron", 0.27, 0.27, 0.05, 8,
		_transform(Vector3(1.55, 0.36, 0.85), bucket_turn)
	)


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
	# Hanging valance along the front edge: turns the flat awning into a stall.
	for index in 4:
		baker.add_box(
			cloth_key, Vector3(0.6, 0.26, 0.07),
			_transform(Vector3(-1.02 + float(index) * 0.68, 2.15, 1.0))
		)
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
		baker.add_box(
			"timber_warm", Vector3(0.16, 1.15, 0.16),
			_transform(Vector3(side * 1.4, 0.58, 0.0)), Color.WHITE, 0.06
		)
		# A restrained cut point on each post gives the fence a hand-hewn top.
		baker.add_cylinder(
			"timber_warm", 0.0, 0.13, 0.2, 4,
			_transform(Vector3(side * 1.4, 1.2, 0.0)), Color.WHITE, 0.04
		)
	for height in [0.55, 0.95]:
		baker.add_box(
			"timber_warm", Vector3(3.0, 0.12, 0.09),
			_transform(Vector3(0.0, height, 0.0)), Color.WHITE, 0.06
		)


func _build_cart(baker: MeshBaker) -> void:
	baker.add_box(
		"plank", Vector3(1.7, 0.16, 2.9),
		_transform(Vector3(0.0, 0.72, 0.0)), Color.WHITE, 0.05
	)
	# Individual bed boards and corner stakes replace the single empty tray.
	for board in 5:
		var x := (float(board) - 2.0) * 0.32
		var board_tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.06))
		baker.add_box(
			"plank", Vector3(0.29, 0.035, 2.65),
			_transform(Vector3(x, 0.815, 0.0)), board_tint, 0.045
		)
	for side in [-1.0, 1.0]:
		baker.add_box(
			"plank", Vector3(0.12, 0.5, 2.9),
			_transform(Vector3(side * 0.82, 1.0, 0.0)), Color.WHITE, 0.045
		)
		for end in [-1.0, 1.0]:
			baker.add_box(
				"timber", Vector3(0.14, 0.62, 0.14),
				_transform(Vector3(side * 0.78, 1.03, end * 1.28)),
				Color.WHITE, 0.04
			)
	baker.add_box(
		"plank", Vector3(1.7, 0.5, 0.12),
		_transform(Vector3(0.0, 1.0, -1.42)), Color.WHITE, 0.045
	)
	# A properly oriented axle and six spokes make the cart wheels read as wood
	# wheels rather than solid discs. This is static display geometry only.
	baker.add_cylinder(
		"timber", 0.08, 0.08, 2.0, 8,
		_transform(Vector3(0.0, 0.52, 0.9), 0.0, 0.0, 90.0), Color.WHITE, 0.04
	)
	for side in [-1.0, 1.0]:
		baker.add_cylinder(
			"timber", 0.52, 0.52, 0.14, 10,
			_transform(Vector3(side * 0.9, 0.52, 0.9), 0.0, 0.0, 90.0),
			Color.WHITE, 0.06
		)
		for spoke in 6:
			var angle := TAU * float(spoke) / 6.0
			var spoke_center := Vector3(
				side * 0.99, 0.52 + cos(angle) * 0.23, 0.9 + sin(angle) * 0.23
			)
			baker.add_box(
				"timber_warm", Vector3(0.08, 0.42, 0.07),
				_transform(spoke_center, 0.0, rad_to_deg(angle), 0.0),
				Color.WHITE, 0.04
			)
		baker.add_cylinder(
			"timber_warm", 0.13, 0.13, 0.1, 8,
			_transform(Vector3(side * 1.02, 0.52, 0.9), 0.0, 0.0, 90.0),
			Color.WHITE, 0.04
		)
	baker.add_box(
		"timber", Vector3(0.12, 0.12, 1.6),
		_transform(Vector3(0.0, 0.66, 2.1), -12.0), Color.WHITE, 0.04
	)
	var bundle_basis := Basis.IDENTITY.scaled(Vector3(0.78, 0.45, 0.78))
	baker.add_sphere(
		"cloth_cream", 1.0, 4, 7,
		_origin * Transform3D(bundle_basis, Vector3(0.0, 1.12, -0.4)),
		Color.WHITE.darkened(0.035)
	)


func _build_crate(baker: MeshBaker, placement: VillageLayout.Placement) -> void:
	var size := 1.05 * placement.scale
	baker.add_box(
		"plank", Vector3(size, size, size),
		_transform(Vector3(0.0, size * 0.5, 0.0)), Color.WHITE, 0.06
	)
	for offset in [-size * 0.35, size * 0.35]:
		baker.add_box(
			"timber", Vector3(size * 1.02, 0.1, size * 1.02),
			_transform(Vector3(0.0, size * 0.5 + offset, 0.0)),
			Color.WHITE, 0.05
		)
	# Corner battens and top slats give the crate a boarded construction instead
	# of a single featureless cube.
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:
			baker.add_box(
				"timber_warm", Vector3(0.075, size * 0.92, 0.075),
				_transform(Vector3(side * size * 0.44, size * 0.5, end * size * 0.44)),
				Color.WHITE.darkened(rng.randf_range(0.0, 0.04)), 0.04
			)
	for board in 3:
		baker.add_box(
			"plank", Vector3(size * 0.88, 0.035, size * 0.24),
			_transform(Vector3(0.0, size * 1.01, (float(board) - 1.0) * size * 0.27)),
			Color.WHITE.darkened(rng.randf_range(0.0, 0.06)), 0.04
		)
	if placement.variant == 1:
		baker.add_box(
			"plank", Vector3(size * 0.8, size * 0.8, size * 0.8),
			_transform(Vector3(0.2, size * 1.4, 0.15), 18.0)
		)


func _build_barrel(baker: MeshBaker, offset: Vector3 = Vector3.ZERO) -> void:
	var turn := rng.randf_range(0.0, 360.0)
	var barrel_transform := _transform(offset + Vector3(0.0, 0.52, 0.0), turn)
	baker.add_cylinder(
		"plank", 0.42, 0.46, 1.05, 10, barrel_transform, Color.WHITE, 0.07
	)
	for height in [0.25, 0.8]:
		baker.add_cylinder(
			"iron", 0.47, 0.47, 0.08, 10,
			_transform(offset + Vector3(0.0, height, 0.0), turn), Color.WHITE, 0.035
		)


func _build_logpile(baker: MeshBaker) -> void:
	for row in 3:
		var count := 4 - row
		for index in count:
			var x := (float(index) - float(count - 1) * 0.5) * 0.62
			baker.add_cylinder(
				"trunk", 0.28, 0.28, 2.4, 7,
				_transform(Vector3(x, 0.3 + float(row) * 0.55, 0.0), 0.0, 90.0),
				Color.WHITE.darkened(float(row) * 0.05), 0.055
			)


func _build_signpost(baker: MeshBaker) -> void:
	baker.add_cylinder("timber", 0.1, 0.13, 2.5, 6, _transform(Vector3(0, 1.25, 0)))
	baker.add_box("plank", Vector3(1.7, 0.36, 0.1), _transform(Vector3(0.6, 2.1, 0.0), 0.0, 0.0, 8.0))
	baker.add_box(
		"plank", Vector3(1.4, 0.32, 0.1), _transform(Vector3(-0.5, 1.7, 0.0), 0.0, 0.0, -6.0)
	)
	baker.add_cylinder("iron", 0.0, 0.14, 0.3, 4, _transform(Vector3(0.0, 2.6, 0.0)))


## Standing planter: a half-barrel tub of flowers. Decorative by design — no
## collider and no NPC obstacle — so a square can be dressed without ever
## narrowing a walk.
func _build_flower_box(baker: MeshBaker, placement: VillageLayout.Placement) -> void:
	var scale := placement.scale
	var turn := rng.randf_range(0.0, 360.0)
	baker.add_cylinder(
		"plank", 0.52, 0.42, 0.52, 10,
		_transform(Vector3(0.0, 0.26, 0.0) * scale, turn),
		Color.WHITE.darkened(rng.randf_range(0.0, 0.07)), 0.05
	)
	for hoop in [0.12, 0.44]:
		baker.add_cylinder(
			"iron", 0.53, 0.53, 0.05, 10,
			_transform(Vector3(0.0, hoop, 0.0) * scale, turn)
		)
	baker.add_cylinder(
		"stone_dark", 0.46, 0.46, 0.06, 10,
		_transform(Vector3(0.0, 0.5, 0.0) * scale, turn), Color.WHITE, 0.05
	)
	for flower in 7:
		var angle := rng.randf() * TAU
		var spread := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.08, 0.34)
		var key: String = ["cloth_red", "cloth_cream", "leaf_bright"][flower % 3]
		baker.add_sphere(
			key, rng.randf_range(0.08, 0.13), 3, 5,
			_transform(
				Vector3(spread.x, 0.56 + rng.randf() * 0.2, spread.z) * scale
			),
			Color.WHITE.darkened(rng.randf_range(0.0, 0.06))
		)


## Park bench: stone feet, plank legs, a slatted seat and a leaning back.
## Faces +Z, so the placement yaw aims it at whatever is worth sitting for.
## Decorative: no collider, so it never blocks the player or an NPC walk.
func _build_bench(baker: MeshBaker, offset: Vector3 = Vector3.ZERO) -> void:
	for side in [-1.0, 1.0]:
		baker.add_box(
			"stone_dark", Vector3(0.34, 0.16, 0.5),
			_transform(offset + Vector3(side * 0.72, 0.08, 0.0)), Color.WHITE, 0.06
		)
		baker.add_box(
			"timber_warm", Vector3(0.14, 0.42, 0.42),
			_transform(offset + Vector3(side * 0.72, 0.32, 0.0)), Color.WHITE, 0.04
		)
		baker.add_box(
			"timber_warm", Vector3(0.12, 0.62, 0.12),
			_transform(offset + Vector3(side * 0.72, 0.72, -0.22), 0.0, -8.0),
			Color.WHITE, 0.04
		)
	for plank in 3:
		baker.add_box(
			"plank", Vector3(1.75, 0.05, 0.15),
			_transform(offset + Vector3(0.0, 0.56, -0.16 + float(plank) * 0.16)),
			Color.WHITE.darkened(rng.randf_range(0.0, 0.05)), 0.04
		)
	baker.add_box(
		"plank", Vector3(1.75, 0.18, 0.05),
		_transform(offset + Vector3(0.0, 0.96, -0.28), 0.0, -8.0),
		Color.WHITE.darkened(0.03), 0.04
	)


# --- shared parts ------------------------------------------------------------


func _body(
	baker: MeshBaker, wall_key: String, roof_key: String, roof_tint: Color, width: float,
	depth: float, wall_height: float, roof_rise: float, scale: float
) -> void:
	# Stone plinth, plaster walls, and a pitched roof with a real eaves overhang.
	baker.add_box(
		"stone_dark", Vector3(width + 0.4, 0.42, depth + 0.4) * scale,
		_transform(Vector3(0.0, 0.21, 0.0) * scale)
	)
	_surface_details.add_foundation_masonry(baker, width, depth, scale)
	baker.add_box(
		wall_key, Vector3(width, wall_height, depth) * scale,
		_transform(Vector3(0.0, 0.42 + wall_height * 0.5, 0.0) * scale),
		Color.WHITE.darkened(rng.randf_range(0.0, 0.06))
	)
	var roof_width := (width + 0.7) * scale
	var roof_depth := (depth + 0.7) * scale
	var roof_rise_scaled := roof_rise * scale
	var wall_top := (0.42 + wall_height) * scale
	var roof_center := _transform(Vector3(0.0, wall_top + roof_rise_scaled * 0.5, 0.0))
	baker.add_prism(roof_key, roof_width, roof_rise_scaled, roof_depth, roof_center, roof_tint)
	_surface_details.add_roof_details(
		baker, roof_key, roof_tint, roof_width, roof_depth, roof_rise_scaled,
		wall_top, roof_center, scale
	)



func _timber_frame(
	baker: MeshBaker, width: float, depth: float, wall_height: float, scale: float
) -> void:
	var top := (0.42 + wall_height) * scale
	var bottom := 0.42 * scale
	var frame_height := wall_height * scale
	var scaled_width := width * scale
	var scaled_depth := depth * scale
	for side in [-1.0, 1.0]:
		# Corner posts on the front and back faces.
		for depth_side in [-1.0, 1.0]:
			baker.add_box(
				"timber", Vector3(0.2 * scale, frame_height, 0.2 * scale),
				_transform(
					Vector3(side * scaled_width * 0.5, (bottom + top) * 0.5,
						depth_side * scaled_depth * 0.5)
				),
				Color.WHITE, 0.035
			)
		# One diagonal brace on each short side: a small structural cue, not trim.
		var brace_length := sqrt(pow(depth, 2) + pow(wall_height * 0.55, 2)) * scale
		var brace_angle := rad_to_deg(atan2(wall_height * 0.55, depth))
		baker.add_box(
			"timber", Vector3(0.16 * scale, brace_length, 0.16 * scale),
			_transform(
				Vector3(side * scaled_width * 0.5, bottom + frame_height * 0.35, 0.0),
				0.0, 0.0, brace_angle * side
			),
			Color.WHITE, 0.035
		)
	# Sill and head beams across both faces. These are emitted once rather than
	# once per corner post, avoiding coincident duplicate surfaces.
	for y in [bottom + 0.1 * scale, top - 0.1 * scale]:
		for depth_side in [-1.0, 1.0]:
			baker.add_box(
				"timber", Vector3(scaled_width, 0.18 * scale, 0.22 * scale),
				_transform(Vector3(0.0, y, depth_side * scaled_depth * 0.5)),
				Color.WHITE, 0.035
			)
	# Vertical studs on the long faces break up the plaster without turning it
	# into a dense lattice.
	for depth_side in [-1.0, 1.0]:
		for stud in [-0.22, 0.22]:
			baker.add_box(
				"timber", Vector3(0.16 * scale, frame_height * 0.96, 0.18 * scale),
				_transform(
					Vector3(stud * scaled_width, (bottom + top) * 0.5,
						depth_side * scaled_depth * 0.5)
				),
				Color.WHITE, 0.035
			)



## Horizontal offset of window [param index] of [param count] on a face of
## [param width]. Shared by the window builder and by the planters under the
## street windows, so a flower box can never drift off its window.
func _window_spread(index: int, count: int, width: float, scale: float) -> float:
	var pair_count := int(ceil(float(count) / 2.0))
	var pair_index := floorf(float(index) * 0.5)
	return (pair_index - float(pair_count - 1) * 0.5) * width * 0.35 * scale


## Window planters under the street-facing windows: the cheapest "people live
## here" signal a facade can carry. A plank box on the sill line, a dark soil
## board and a few flower heads in the shared palette — no new materials.
func _window_flower_boxes(
	baker: MeshBaker, width: float, depth: float, wall_height: float, count: int, scale: float
) -> void:
	var y := (0.42 + wall_height * 0.6) * scale
	var face_z := depth * 0.5 * scale
	for index in count:
		if index % 2 != 0:
			continue
		if rng.randf() > 0.55:
			continue
		var spread := _window_spread(index, count, width, scale)
		var box_y := y - 0.7 * scale
		baker.add_box(
			"plank", Vector3(0.95, 0.28, 0.34) * scale,
			_transform(Vector3(spread, box_y, face_z + 0.2 * scale)),
			Color.WHITE.darkened(rng.randf_range(0.0, 0.08)), 0.04
		)
		baker.add_box(
			"stone_dark", Vector3(0.85, 0.06, 0.26) * scale,
			_transform(Vector3(spread, box_y + 0.15 * scale, face_z + 0.2 * scale)),
			Color.WHITE, 0.05
		)
		for flower in 4:
			var offset := (float(flower) - 1.5) * 0.22 * scale
			var key: String = "cloth_red" if flower % 2 == 0 else "cloth_cream"
			baker.add_sphere(
				key, 0.09 * scale, 3, 5,
				_transform(Vector3(spread + offset, box_y + 0.26 * scale, face_z + 0.2 * scale)),
				Color.WHITE.darkened(rng.randf_range(0.0, 0.06))
			)


func _windows(
	baker: MeshBaker, width: float, depth: float, wall_height: float, count: int, scale: float,
	shutter_key: String = "timber_warm"
) -> void:
	var y := (0.42 + wall_height * 0.6) * scale
	for index in count:
		var side := 1.0 if index % 2 == 0 else -1.0
		var spread := _window_spread(index, count, width, scale)
		var face_z := side * depth * 0.5 * scale
		var trim_z := face_z + side * 0.08 * scale
		# Front and back windows get a deep timber frame, divided light, and a
		# projecting sill. The muntins sit forward of the glass so they read at
		# village scale instead of disappearing into the wall.
		baker.add_box(
			"window", Vector3(0.72, 0.85, 0.14) * scale,
			_transform(Vector3(spread, y, face_z))
		)
		for jamb_side in [-1.0, 1.0]:
			baker.add_box(
				"timber", Vector3(0.09, 0.94, 0.18) * scale,
				_transform(Vector3(spread + jamb_side * 0.4 * scale, y, trim_z)),
				Color.WHITE, 0.035
			)
		baker.add_box(
			"timber", Vector3(0.96, 0.12, 0.2) * scale,
			_transform(Vector3(spread, y + 0.49 * scale, trim_z)),
			Color.WHITE, 0.035
		)
		baker.add_box(
			"stone", Vector3(1.0, 0.12, 0.24) * scale,
			_transform(Vector3(spread, y - 0.49 * scale, trim_z)),
			Color.WHITE.darkened(0.04), 0.06
		)
		baker.add_box(
			"timber", Vector3(0.045, 0.76, 0.045) * scale,
			_transform(Vector3(spread, y, face_z + side * 0.105 * scale)),
			Color.WHITE, 0.035
		)
		baker.add_box(
			"timber", Vector3(0.72, 0.045, 0.045) * scale,
			_transform(Vector3(spread, y, face_z + side * 0.105 * scale)),
			Color.WHITE, 0.035
		)
		# Painted shutter leaves with two restrained battens, not blank coloured
		# blocks pasted beside each opening.
		for shutter_side in [-1.0, 1.0]:
			var shutter_x: float = spread + shutter_side * 0.56 * scale
			baker.add_box(
				shutter_key, Vector3(0.3, 0.85, 0.1) * scale,
				_transform(Vector3(shutter_x, y, trim_z)),
				Color.WHITE.darkened(rng.randf_range(0.0, 0.045)), 0.025
			)
			for batten_side in [-1.0, 1.0]:
				baker.add_box(
					"timber", Vector3(0.3, 0.04, 0.04) * scale,
					_transform(Vector3(
						shutter_x, y + batten_side * 0.24 * scale,
						trim_z + side * 0.07 * scale
					)),
					Color.WHITE, 0.025
				)
	# Small framed windows on the gable ends balance the street-facing openings.
	for side in [-1.0, 1.0]:
		var end_x: float = side * width * 0.5 * scale
		var end_trim_x: float = end_x + side * 0.08 * scale
		var end_y := y * 0.95
		baker.add_box(
			"window", Vector3(0.14, 0.7, 0.6) * scale,
			_transform(Vector3(end_x, end_y, 0.0))
		)
		for end_side in [-1.0, 1.0]:
			baker.add_box(
				"timber", Vector3(0.18, 0.78, 0.1) * scale,
				_transform(Vector3(end_trim_x, end_y, end_side * 0.34 * scale))
			)
		baker.add_box(
			"timber", Vector3(0.18, 0.08, 0.74) * scale,
			_transform(Vector3(end_trim_x, end_y + 0.39 * scale, 0.0))
		)
		baker.add_box(
			"stone", Vector3(0.22, 0.1, 0.78) * scale,
			_transform(Vector3(end_trim_x, end_y - 0.39 * scale, 0.0))
		)


func _chimney(
	baker: MeshBaker, position: Vector3, size_scale: float, position_scale: float = 1.0
) -> void:
	var scaled_position := position * position_scale
	baker.add_box(
		"stone", Vector3(0.75, 2.4, 0.75) * size_scale,
		_transform(scaled_position), Color.WHITE, 0.08
	)
	baker.add_box(
		"stone_dark", Vector3(0.95, 0.2, 0.95) * size_scale,
		_transform(scaled_position + Vector3(0.0, 1.2, 0.0) * size_scale),
		Color.WHITE, 0.06
	)


func _porch(baker: MeshBaker, width: float, depth: float, scale: float) -> void:
	for side in [-1.0, 1.0]:
		baker.add_box(
			"timber", Vector3(0.2, 2.2, 0.2) * scale,
			_transform(Vector3(side * width * 0.3, 1.1, depth * 0.5 + 1.0) * scale),
			Color.WHITE, 0.04
		)
	baker.add_box(
		"roof_shingle", Vector3(width * 0.8, 0.14, 1.6) * scale,
		_transform(Vector3(0.0, 2.35, depth * 0.5 + 0.6) * scale, -12.0),
		Color.WHITE, 0.06
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
