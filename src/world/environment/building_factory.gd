class_name BuildingFactory
extends RefCounted
## Builds the village structures with a shared architectural kit: houses, the inn, the
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
var _architecture := BuildingArchitecture.new()

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
		VillageLayout.KIND_HOUSE, VillageLayout.KIND_INN, VillageLayout.KIND_HALL:
			_architecture.build(baker, placement)
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
			var long_body := placement.variant == 2
			var width := 5.8 if long_body else 4.4
			var depth := 3.4 if long_body else 4.0
			var wall_height := 4.2 if placement.variant == 1 else 2.6
			var collider_height := maxf(4.0, 0.42 + wall_height)
			shapes.append(
				_box_collider(
					Vector3(width + 0.2, collider_height, depth + 0.4) * scale,
					Vector3(0.0, collider_height * 0.5, 0.0) * scale
				)
			)
		VillageLayout.KIND_INN:
			shapes.append(_box_collider(Vector3(8.4, 6.0, 6.0) * scale, Vector3(0, 3.0, 0) * scale))
			# The L shaped wing needs its own box, or the player walks through it.
			shapes.append(
				_box_collider(Vector3(3.4, 3.4, 3.4) * scale, Vector3(-5.0, 1.7, 1.6) * scale)
			)
		VillageLayout.KIND_HALL:
			shapes.append(_box_collider(Vector3(10.0, 5.0, 6.0) * scale, Vector3(0, 2.5, 0) * scale))
			shapes.append(
				_box_collider(Vector3(3.2, 8.0, 3.2) * scale, Vector3(-5.4, 4.0, 0.0) * scale)
			)
		VillageLayout.KIND_WELL:
			shapes.append(_cylinder_collider(1.36 * scale, 1.1 * scale, Vector3.ZERO))
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


func _build_well(baker: MeshBaker) -> void:
	# Low solid footing under the stone ring; leaving its upper half open makes
	# the water surface visible instead of burying it inside a capped cylinder.
	baker.add_cylinder(
		"stone", 1.15, 1.25, 0.42, 12, _transform(Vector3(0.0, 0.21, 0.0)),
		Color.WHITE, 0.04
	)
	# Two staggered courses of rough ashlar wrap the basin, keeping the well's
	# round silhouette while replacing the featureless cylinder wall.
	for course in 2:
		var y := 0.24 + float(course) * 0.4
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
	# A segmented coping leaves a real opening over the well; a solid cylinder
	# here used to cap the basin and completely hide its water mesh.
	for segment in 12:
		var rim_angle := TAU * float(segment) / 12.0
		var rim_x := cos(rim_angle) * 1.18
		var rim_z := sin(rim_angle) * 1.18
		var rim_yaw := rad_to_deg(atan2(rim_x, rim_z))
		var rim_tint := Color.WHITE.darkened(rng.randf_range(0.025, 0.10))
		baker.add_box(
			"stone_dark", Vector3(0.58, 0.18, 0.26),
			_transform(Vector3(rim_x, 0.94, rim_z), rim_yaw), rim_tint, 0.08
		)
	baker.add_cylinder(
		"water", 0.92, 0.92, 0.06, 12, _transform(Vector3(0.0, 0.72, 0.0))
	)
	for side in [-1.0, 1.0]:
		baker.add_box(
			"timber", Vector3(0.2, 3.6, 0.2),
			_transform(Vector3(side * 1.4, 1.8, 0.0)), Color.WHITE, 0.04
		)
	var well_roof_center := _transform(Vector3(0.0, 3.15, 0.0), 90.0)
	baker.add_prism("roof_shingle", 3.2, 0.9, 3.1, well_roof_center)
	_surface_details.add_roof_details(
		baker, "roof_shingle", Color.WHITE, 3.2, 3.1, 0.9,
		2.7, well_roof_center, 1.0
	)
	baker.add_box("timber", Vector3(2.8, 0.16, 0.16), _transform(Vector3(0.0, 2.6, 0.0)))
	baker.add_box("plank", Vector3(0.6, 0.6, 0.6), _transform(Vector3(0.0, 1.9, 0.0)))
	# A bucket on the stones beside the basin: the well is used, not staged.
	# It sits outside the well collider (r 1.36), so it never blocks the ring.
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
		var post_height := 2.45 if corner.z < 0.0 else 2.2
		baker.add_box(
			"timber", Vector3(0.14, post_height, 0.14),
			_transform(Vector3(corner.x, post_height * 0.5, corner.z))
		)
	baker.add_box("plank", Vector3(2.6, 0.14, 1.5), _transform(Vector3(0.0, 1.05, -0.1)))
	baker.add_box(
		cloth_key, Vector3(2.9, 0.1, 2.0),
		_transform(Vector3(0.0, 2.3, 0.0), 0.0, 8.0)
	)
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
