class_name VegetationBuilder
extends RefCounted
## Trees, shrubs, meadow flowers, rocks and ground cover.
##
## Visual polish 16 rebuilt the vegetation. The previous pass could already vary
## a tree's height and lean, but every plant was still assembled from the same
## three primitives: a **cylinder** trunk, a **UV sphere** crown and a **stack of
## cones** for a pine. From the plaza that reads as a row of lollipops, and from
## the meadow as a traffic cone. The replacement is a small vocabulary of organic
## solids in [MeshBaker], extended with a rock-specific profile in Visual Polish 17:
##
## * `add_limb` — a tapered tube through a bent polyline, used for trunks, roots
##   and branches. It carries a root flare and narrows into the crown, so the
##   silhouette is a tree, not a pipe.
## * `add_foliage_clump` — a lobed, irregular ellipsoid whose radius varies with
##   the angle and the latitude. No crown is a sphere, and no two seeds repeat.
## * `add_blade` — a tapered blade for grass and flower stems, lit with an
##   upward normal so a single quad works from both sides without transparency.
## * `add_rock` — a closed, layered stone with a buried foot, flat facets and a
##   clipped crown. Its bounded ring variation changes the silhouette without
##   deforming topology or making a sphere/cube.
##
## Three species remain, each with three genuinely different variants (see
## `_pine_profile`, `_oak_profile`, `_birch_profile`), plus a new
## `flower_patch` kind and a rebuilt grass tuft. Distribution was revised at the
## same time: species grow in stands, the forest has real clearings, trees keep a
## wider verge from the roads and a longer sightline from every door.
##
## Two performance rules still drive this file:
## * **everything static is merged.** `VillageBuilder` hands one [MeshBaker] to
##   the whole forest, so hundreds of trees become a handful of meshes.
## * **detail follows distance.** Trees near the village and along the roads are
##   built with more clumps and rings; the outer forest uses a cheaper silhouette
##   that is still species-specific. `VillageBuilder` decides with
##   [method needs_detail].
##
## Grass is not built here: it is the one instanced part of the vegetation and
## lives in [MeadowBuilder], which this class reaches through [method
## build_grass].

const LEAF_KEYS := ["leaf_deep", "leaf_mid", "leaf_bright"]
const TREE_COLLIDER_KINDS := [
	VillageLayout.KIND_TREE_PINE, VillageLayout.KIND_TREE_OAK, VillageLayout.KIND_TREE_BIRCH
]
## Trees this close to the plaza are built at full detail. Outside the radius,
## only the ones lining a road are, because those are the ones the player walks
## past; the rest of the border forest keeps a cheaper silhouette.
const DETAIL_RADIUS := 44.0
const ROAD_DETAIL_CORRIDOR := 6.0

var rng := RandomNumberGenerator.new()
## Shape facts of the plant built by the last `append` call. Exposed for the
## headless suite, which uses them to prove that variants differ and that a
## trunk really tapers; not read by the game.
var last_stats := {}

## See `BuildingFactory._origin`: merged vegetation has no node of its own, so
## every solid is emitted already placed in the world.
var _origin := Transform3D.IDENTITY
## Builds the instanced grass tufts and their colour field.
var _meadow: MeadowBuilder = null


func _init(seed_value: int = 0) -> void:
	rng.seed = seed_value
	_meadow = MeadowBuilder.new(seed_value + 13)


## Builds one placement. [param detail] false selects the cheaper far silhouette;
## `VillageBuilder` derives it from distance and from the road corridor.
func append(
	baker: MeshBaker,
	placement: VillageLayout.Placement,
	origin: Transform3D,
	detail: bool = true
) -> void:
	_origin = origin
	last_stats = {}
	match placement.kind:
		VillageLayout.KIND_TREE_PINE:
			_build_pine(baker, placement, detail)
		VillageLayout.KIND_TREE_OAK:
			_build_oak(baker, placement, detail)
		VillageLayout.KIND_TREE_BIRCH:
			_build_birch(baker, placement, detail)
		VillageLayout.KIND_BUSH:
			_build_bush(baker, placement, detail)
		VillageLayout.KIND_FLOWER_PATCH:
			_build_flower_patch(baker, placement, detail)
		VillageLayout.KIND_ROCK:
			_build_rock(baker, placement)
	_origin = Transform3D.IDENTITY


## True when a placement is close enough to the plaza, or to a road the player
## actually walks, to deserve the full-detail silhouette.
func needs_detail(layout: VillageLayout, placement: VillageLayout.Placement) -> bool:
	if placement.position.length() <= DETAIL_RADIUS:
		return true
	if VillageLayout.TREE_KINDS.has(placement.kind):
		return layout.distance_to_roads(placement.position) <= ROAD_DETAIL_CORRIDOR
	return false


## Trunk and boulder colliders. Only trees and large boulders block the player;
## shrubs, flowers and grass are walkable, which keeps the village open instead
## of a pinball table. Radii follow the species' real trunk: a birch used to
## block more than its visible stem, an oak less than its root flare.
func colliders_for(placement: VillageLayout.Placement) -> Array:
	var shapes: Array = []
	var scale := placement.scale
	match placement.kind:
		VillageLayout.KIND_TREE_PINE:
			shapes.append(_cylinder_collider(0.32 * scale, 2.4 * scale, Vector3.ZERO))
		VillageLayout.KIND_TREE_OAK:
			shapes.append(_cylinder_collider(0.42 * scale, 2.1 * scale, Vector3.ZERO))
		VillageLayout.KIND_TREE_BIRCH:
			shapes.append(_cylinder_collider(0.22 * scale, 2.6 * scale, Vector3.ZERO))
		VillageLayout.KIND_ROCK:
			if scale > 0.9:
				# Preserve the original obstacle exactly; visual rock silhouettes
				# evolve, but the player's collision footprint does not.
				shapes.append(
					_box_collider(
						Vector3(1.5, 1.0, 1.4) * scale,
						Vector3(0.0, 0.4, 0.0) * scale
					)
				)
	return shapes


func build_grass(
	layout: VillageLayout, terrain: TerrainGenerator, materials: VillageMaterials,
	count: int = MeadowBuilder.GRASS_COUNT
) -> MultiMeshInstance3D:
	return _meadow.build_grass(layout, terrain, materials, count)


# --- species -----------------------------------------------------------------
#
# Every builder starts from a profile dictionary. Three numbers decide a
# silhouette: where the crown starts, how tall it is and how wide its lobed
# masses spread. The variants below are deliberately far apart — a spruce, a
# scots pine and a young mugo; a broad oak, a tall oak and a leaning oak; a
# slender birch, a twin-stem birch and an autumn birch — because "two shades of
# the same lollipop" is exactly what this pass removes.


func _pine_profile(variant: int) -> Dictionary:
	match variant:
		1:
			# Scots pine: a long bare trunk under a flat, umbrella-like crown.
			return {
				"trunk": 3.2, "radius": 0.19, "start": 0.70, "span": 0.95,
				"tiers": 3, "tufts": 5, "base": 1.55, "top": 0.55, "lift": 0.0
			}
		2:
			# Young mugo pine: short, dense and wide, like a bush with a trunk.
			return {
				"trunk": 1.45, "radius": 0.17, "start": 0.30, "span": 1.25,
				"tiers": 4, "tufts": 4, "base": 1.45, "top": 0.38, "lift": 0.0
			}
	return {
		"trunk": 2.35, "radius": 0.20, "start": 0.42, "span": 1.35,
		"tiers": 5, "tufts": 5, "base": 1.30, "top": 0.30, "lift": 0.0
	}


func _oak_profile(variant: int) -> Dictionary:
	match variant:
		1:
			# Tall oak: narrow, high crown, almost twice the trunk of the broad one.
			return {
				"trunk": 2.95, "radius": 0.25, "lift": 0.95,
				"x": 1.75, "y": 1.70, "z": 1.70, "clumps": 6, "limb": 0.9,
				"lean_x": 0.0, "lean_z": 0.0, "twist": 0.7
			}
		2:
			# Leaning oak: thrown to one side, low and broad, the tree you shelter under.
			return {
				"trunk": 1.75, "radius": 0.31, "lift": 0.75,
				"x": 2.45, "y": 1.30, "z": 1.95, "clumps": 7, "limb": 1.25,
				"lean_x": 0.55, "lean_z": -0.30, "twist": 1.9
			}
	return {
		"trunk": 2.15, "radius": 0.29, "lift": 0.80,
		"x": 2.20, "y": 1.55, "z": 2.00, "clumps": 6, "limb": 1.0,
		"lean_x": 0.0, "lean_z": 0.0, "twist": 0.0
	}


func _birch_profile(variant: int) -> Dictionary:
	match variant:
		1:
			# Twin stem: two pale trunks from one root, the shape birches actually take.
			return {"trunk": 2.95, "stems": 2, "spread": 0.75, "start": 0.56, "crown": 1.0}
		2:
			# Autumn birch: taller, sparse crown, one warm accent in the treeline.
			return {"trunk": 3.65, "stems": 1, "spread": 0.0, "start": 0.60, "crown": 1.05}
	return {"trunk": 3.05, "stems": 1, "spread": 0.0, "start": 0.52, "crown": 0.95}


func _build_pine(baker: MeshBaker, placement: VillageLayout.Placement, detail: bool) -> void:
	var start := baker.get_triangle_count()
	var scale := placement.scale
	var variant := placement.variant % 3
	var profile := _pine_profile(variant)
	var bark_tint := Color.WHITE.darkened(rng.randf_range(0.02, 0.09))
	var needle_tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.15))
	var trunk_height := float(profile["trunk"]) * scale * rng.randf_range(0.93, 1.07)
	var base_radius := float(profile["radius"]) * scale * rng.randf_range(0.92, 1.08)
	var lean := Vector3(rng.randf_range(-0.26, 0.26), 0.0, rng.randf_range(-0.26, 0.26)) * scale
	var bend := Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12)) * scale
	var trunk_segments := 4 if detail else 3
	var points := _trunk_points(trunk_height, lean, bend, trunk_segments)
	var trunk_radii := _trunk_radii(base_radius, base_radius * 0.15, trunk_segments, 1.55)
	baker.add_limb(
		"trunk", points, trunk_radii, 7 if detail else 5, _origin, bark_tint, 0.05
	)
	if detail:
		_add_root_flare(baker, base_radius, bark_tint, 3)

	var crown_start := trunk_height * float(profile["start"])
	var crown_span := trunk_height * float(profile["span"])
	var tier_count := int(profile["tiers"]) if detail else maxi(int(profile["tiers"]) - 2, 2)
	var tuft_count := int(profile["tufts"]) if detail else 2
	var widest_tier := float(profile["base"]) * scale
	var top := points[points.size() - 1]
	for tier in tier_count:
		var t := 0.0 if tier_count <= 1 else float(tier) / float(tier_count - 1)
		var y := crown_start + crown_span * t
		var tier_radius: float = (
			lerpf(float(profile["base"]), float(profile["top"]), pow(t, 0.75))
			* scale * rng.randf_range(0.86, 1.16)
		)
		var along := clampf(y / trunk_height, 0.0, 1.25)
		var tier_center := Vector3(lean.x * along, y, lean.z * along)
		_add_pine_tier(
			baker, tier_center, tier_radius, rng.randf() * TAU, tuft_count, needle_tint, detail
		)
	# A spire above the top tier closes the cone without a flat lid, and hides
	# the point where the last skirt meets the trunk.
	var spire_height := (0.55 + 0.45 * float(profile["top"])) * scale
	var spire_radius := float(profile["top"]) * scale * 0.85
	baker.add_cylinder(
		"pine", 0.0, spire_radius, spire_height, 5,
		_origin * Transform3D(
			Basis.IDENTITY,
			Vector3(lean.x, crown_start + crown_span + spire_height * 0.5, lean.z)
		),
		needle_tint, 0.05
	)
	# A scots pine shows its branches under the umbrella. Two or three visible
	# limbs are what tell it apart from the spruce at a glance.
	if detail and variant == 1:
		for index in 3:
			var angle := TAU * float(index) / 3.0 + rng.randf_range(-0.35, 0.35)
			var at := rng.randf_range(0.58, 0.82)
			var origin := Vector3(lean.x * at, trunk_height * at - 0.16, lean.z * at)
			var direction := Vector3(
				cos(angle), rng.randf_range(0.22, 0.45), sin(angle)
			).normalized()
			var end := origin + direction * rng.randf_range(0.95, 1.55) * scale
			baker.add_limb(
				"trunk", PackedVector3Array([origin, end]),
				PackedFloat32Array([base_radius * 0.34, base_radius * 0.10]),
				4, _origin, bark_tint, 0.06
			)
	last_stats = {
		"kind": placement.kind, "variant": variant, "detail": detail,
		"trunk_base_radius": base_radius,
		"trunk_top_radius": trunk_radii[trunk_radii.size() - 1],
		"crown_extent": Vector3(widest_tier, crown_span, widest_tier),
		"crown_clumps": tier_count * (tuft_count + 1),
		"triangles": baker.get_triangle_count() - start,
		"top": Vector3(top.x, crown_start + crown_span, top.z),
	}


func _add_pine_tier(
	baker: MeshBaker, center: Vector3, radius: float, yaw: float, tufts: int,
	tint: Color, detail: bool
) -> void:
	var segments := 5 if detail else 4
	var rings := 2
	var clump_tint := tint.lightened(rng.randf_range(-0.02, 0.06))
	# Central mass: the tier is a volume, not a ring of separate balls.
	baker.add_foliage_clump(
		"pine", Vector3(radius * 0.66, radius * 0.34, radius * 0.66),
		rings, segments, rng.randi(),
		_origin * Transform3D(Basis.IDENTITY, center), clump_tint, true
	)
	for index in tufts:
		var angle := TAU * float(index) / float(tufts) + yaw + rng.randf_range(-0.16, 0.16)
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var distance := radius * rng.randf_range(0.30, 0.52)
		var length := radius * rng.randf_range(0.46, 0.72)
		var height := radius * 0.22 * rng.randf_range(0.75, 1.20)
		var tuft_center := (
			center + outward * distance
			+ Vector3(0.0, rng.randf_range(-0.10, 0.10) * radius, 0.0)
		)
		# Local X points radially outward, so the tuft is longer along the branch
		# than across it, and a small roll drops the outer tip the way pine
		# needles hang.
		var basis := Basis.from_euler(
			Vector3(0.0, -angle, rng.randf_range(-0.17, 0.17))
		)
		baker.add_foliage_clump(
			"pine", Vector3(length, height, length * 0.66),
			rings, segments, rng.randi(),
			_origin * Transform3D(basis, tuft_center),
			clump_tint.lightened(rng.randf_range(-0.03, 0.05)), true
		)


func _build_oak(baker: MeshBaker, placement: VillageLayout.Placement, detail: bool) -> void:
	var start := baker.get_triangle_count()
	var scale := placement.scale
	var variant := placement.variant % 3
	var profile := _oak_profile(variant)
	var trunk_height := float(profile["trunk"]) * scale * rng.randf_range(0.93, 1.06)
	var base_radius := float(profile["radius"]) * scale * rng.randf_range(0.92, 1.10)
	var lean := Vector3(
		rng.randf_range(-0.28, 0.28) + float(profile["lean_x"]),
		0.0,
		rng.randf_range(-0.26, 0.26) + float(profile["lean_z"])
	) * scale
	var bend := Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-0.15, 0.15)) * scale
	var bark_tint := Color.WHITE.darkened(rng.randf_range(0.03, 0.11))
	var trunk_segments := 4 if detail else 3
	var points := _trunk_points(trunk_height, lean, bend, trunk_segments)
	var trunk_radii := _trunk_radii(base_radius, base_radius * 0.44, trunk_segments, 1.60)
	baker.add_limb(
		"trunk", points, trunk_radii, 7 if detail else 5, _origin, bark_tint, 0.06
	)
	if detail:
		_add_root_flare(baker, base_radius, bark_tint, 3)

	var top := points[points.size() - 1]
	var crown_center := Vector3(
		top.x, trunk_height - 0.16 + float(profile["lift"]) * scale, top.z
	)
	var extents := Vector3(
		float(profile["x"]), float(profile["y"]), float(profile["z"])
	) * scale * rng.randf_range(0.94, 1.06)
	var leaf_key: String = LEAF_KEYS[variant % LEAF_KEYS.size()]
	var tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.10))

	# Visible limbs, each ending just inside the crown: without them a broad
	# canopy floats. Far trees keep a single cheap limb so the crown is still
	# carried rather than pasted on.
	var limb_count := 3 if detail else 1
	var tips: Array[Vector3] = []
	var twist := float(profile["twist"])
	for index in limb_count:
		var angle := TAU * float(index) / float(limb_count) + twist + rng.randf_range(-0.35, 0.35)
		var at := rng.randf_range(0.55, 0.82)
		var origin := Vector3(
			lean.x * pow(at, 1.35), -0.16 + trunk_height * at, lean.z * pow(at, 1.35)
		)
		var direction := Vector3(
			cos(angle) * rng.randf_range(0.75, 1.20),
			rng.randf_range(0.42, 0.82),
			sin(angle) * rng.randf_range(0.75, 1.20)
		).normalized()
		var length := rng.randf_range(0.95, 1.45) * scale * float(profile["limb"])
		var mid := origin + direction * length * 0.55 + Vector3(0.0, 0.10 * scale, 0.0)
		var end := origin + direction * length
		baker.add_limb(
			"trunk", PackedVector3Array([origin, mid, end]),
			PackedFloat32Array([base_radius * 0.55, base_radius * 0.33, base_radius * 0.09]),
			5 if detail else 4, _origin, bark_tint, 0.06
		)
		tips.append(end)

	_add_oak_crown(
		baker, crown_center, extents, int(profile["clumps"]), leaf_key, tint, detail, tips
	)
	# Two bare twigs above the leaf mass: a crown that ends in a clean dome is
	# the tell of a primitive, and branches poking out cost four triangles each.
	if detail:
		for _index in 2:
			var angle := rng.randf() * TAU
			var origin := crown_center + Vector3(
				cos(angle) * extents.x * 0.28, extents.y * 0.20, sin(angle) * extents.z * 0.28
			)
			var tip := origin + Vector3(
				cos(angle) * extents.x * 0.34,
				extents.y * rng.randf_range(0.40, 0.66),
				sin(angle) * extents.z * 0.34
			)
			baker.add_limb(
				"trunk", PackedVector3Array([origin, tip]),
				PackedFloat32Array([base_radius * 0.16, base_radius * 0.035]),
				4, _origin, bark_tint, 0.05
			)
	last_stats = {
		"kind": placement.kind, "variant": variant, "detail": detail,
		"trunk_base_radius": base_radius,
		"trunk_top_radius": trunk_radii[trunk_radii.size() - 1],
		"crown_extent": extents,
		"crown_clumps": int(profile["clumps"]),
		"triangles": baker.get_triangle_count() - start,
		"top": crown_center + Vector3(0.0, extents.y, 0.0),
	}


## Core mass plus offset lobes. The core guarantees the crown is one volume;
## the lobes, placed on the branch tips and then on jittered rings, guarantee it
## is not a sphere. Radii on three axes are independent, so one variant can be
## tall and narrow, another low and wide.
func _add_oak_crown(
	baker: MeshBaker, center: Vector3, extents: Vector3, count: int, leaf_key: String,
	tint: Color, detail: bool, tips: Array[Vector3]
) -> void:
	var rings := 3 if detail else 2
	var segments := 7 if detail else 5
	baker.add_foliage_clump(
		leaf_key, Vector3(extents.x * 0.60, extents.y * 0.80, extents.z * 0.60),
		rings, segments, rng.randi(),
		_origin * Transform3D(Basis.IDENTITY, center), tint, false
	)
	var placed := 1
	for tip in tips:
		var offset := (tip - center) * 0.86
		baker.add_foliage_clump(
			leaf_key,
			Vector3(
				extents.x * rng.randf_range(0.34, 0.46),
				extents.y * rng.randf_range(0.38, 0.54),
				extents.z * rng.randf_range(0.34, 0.46)
			),
			rings, segments, rng.randi(),
			_origin * Transform3D(
				Basis.from_euler(
					Vector3(rng.randf_range(-0.22, 0.22), rng.randf() * TAU, rng.randf_range(-0.22, 0.22))
				),
				center + offset
			),
			tint.lightened(rng.randf_range(-0.03, 0.06)), false
		)
		placed += 1
	while placed < count:
		var angle := rng.randf() * TAU
		var radial := rng.randf_range(0.28, 0.82)
		var offset := Vector3(
			cos(angle) * extents.x * radial,
			rng.randf_range(-0.58, 0.58) * extents.y,
			sin(angle) * extents.z * radial
		)
		baker.add_foliage_clump(
			leaf_key,
			Vector3(
				extents.x * rng.randf_range(0.26, 0.42),
				extents.y * rng.randf_range(0.30, 0.48),
				extents.z * rng.randf_range(0.26, 0.42)
			),
			rings, segments, rng.randi(),
			_origin * Transform3D(
				Basis.from_euler(
					Vector3(rng.randf_range(-0.28, 0.28), rng.randf() * TAU, rng.randf_range(-0.28, 0.28))
				),
				center + offset
			),
			tint.lightened(rng.randf_range(-0.04, 0.08)), false
		)
		placed += 1


func _build_birch(baker: MeshBaker, placement: VillageLayout.Placement, detail: bool) -> void:
	var start := baker.get_triangle_count()
	var scale := placement.scale
	var variant := placement.variant % 3
	var profile := _birch_profile(variant)
	var trunk_height := float(profile["trunk"]) * scale * rng.randf_range(0.92, 1.08)
	var base_radius := 0.15 * scale * rng.randf_range(0.94, 1.10)
	var bark_tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.05))
	var leaf_key := "leaf_autumn" if variant == 2 else "leaf_bright"
	var tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.08))
	var stems := int(profile["stems"])
	var crown_bases: Array[Vector3] = []
	for stem in stems:
		var stem_scale := 1.0 if stem == 0 else 0.78
		var lean := Vector3(
			rng.randf_range(-0.30, 0.30) + (float(profile["spread"]) if stem == 1 else 0.0),
			0.0,
			rng.randf_range(-0.24, 0.24)
		) * scale
		var bend := Vector3(rng.randf_range(-0.10, 0.10), 0.0, rng.randf_range(-0.10, 0.10)) * scale
		var height := trunk_height * stem_scale
		var segments := 3 if detail else 2
		var points := _trunk_points(height, lean, bend, segments)
		var trunk_radii := _trunk_radii(
			base_radius * stem_scale, base_radius * 0.22 * stem_scale, segments, 1.35
		)
		baker.add_limb(
			"trunk_birch", points, trunk_radii, 6 if detail else 4, _origin, bark_tint, 0.07
		)
		var top := points[points.size() - 1]
		crown_bases.append(Vector3(top.x, height - 0.16, top.z))
		# The dark scars that make a birch a birch. Two short wider cylinders
		# read as bark breaks from the walking camera; the cost is 32 triangles.
		if detail:
			for _band in 2:
				var at := rng.randf_range(0.22, 0.66)
				var radius := lerpf(trunk_radii[0], trunk_radii[segments], at) * 1.10
				baker.add_cylinder(
					"trunk", radius, radius, 0.035 * scale, 4,
					_origin * Transform3D(
						Basis.IDENTITY,
						Vector3(lean.x * pow(at, 1.35), -0.16 + height * at, lean.z * pow(at, 1.35))
					),
					Color.WHITE.darkened(rng.randf_range(0.25, 0.4))
				)
		# Two slim ascending limbs per stem: birches do not have a bare pole
		# between the ground and the leaves.
		var limb_count := 2 if detail else 1
		for index in limb_count:
			var angle := TAU * float(index) / float(maxi(limb_count, 1)) + rng.randf() * TAU * 0.25
			var at := rng.randf_range(float(profile["start"]), 0.92)
			var origin := Vector3(
				lean.x * pow(at, 1.35), -0.16 + height * at, lean.z * pow(at, 1.35)
			)
			var direction := Vector3(
				cos(angle) * 0.5, rng.randf_range(0.8, 1.25), sin(angle) * 0.5
			).normalized()
			var end := origin + direction * rng.randf_range(0.65, 1.1) * scale * stem_scale
			baker.add_limb(
				"trunk_birch", PackedVector3Array([origin, end]),
				PackedFloat32Array([base_radius * 0.28 * stem_scale, base_radius * 0.06]),
				4, _origin, bark_tint, 0.06
			)
	_add_birch_crown(
		baker, crown_bases[0], float(profile["start"]), float(profile["crown"]),
		leaf_key, tint, detail
	)
	if stems > 1:
		_add_birch_crown(
			baker, crown_bases[1] + Vector3(0.15, -0.25, 0.0), float(profile["start"]) + 0.06,
			float(profile["crown"]) * 0.8, leaf_key, tint.lightened(0.03), detail
		)
	last_stats = {
		"kind": placement.kind, "variant": variant, "detail": detail,
		"trunk_base_radius": base_radius,
		"trunk_top_radius": base_radius * 0.22,
		"crown_extent": Vector3(1.9, 2.4, 1.9) * scale * float(profile["crown"]),
		"crown_clumps": 4 if detail else 2,
		"triangles": baker.get_triangle_count() - start,
		"top": crown_bases[0] + Vector3(0.0, 1.6 * scale, 0.0),
	}


## Airy birch canopy: a few small clumps spread along the upper third with gaps
## between them, so the crown is a loose veil of leaves rather than a ball.
func _add_birch_crown(
	baker: MeshBaker, base: Vector3, start: float, crown_scale: float, leaf_key: String,
	tint: Color, detail: bool
) -> void:
	var count := 4 if detail else 2
	var rings := 3 if detail else 2
	var segments := 6 if detail else 5
	var scale := 1.0
	for index in count:
		var angle := TAU * float(index) / float(count) + rng.randf_range(-0.5, 0.5)
		var radial := rng.randf_range(0.30, 0.90) * crown_scale
		var height := rng.randf_range(-0.15, 0.95 + float(index) * 0.15) * crown_scale
		var center := base + Vector3(
			cos(angle) * radial, height * 1.2 + 0.55 * crown_scale, sin(angle) * radial
		)
		baker.add_foliage_clump(
			leaf_key,
			Vector3(
				rng.randf_range(0.62, 0.92) * crown_scale * scale,
				rng.randf_range(0.52, 0.78) * crown_scale * scale,
				rng.randf_range(0.62, 0.92) * crown_scale * scale
			),
			rings, segments, rng.randi(),
			_origin * Transform3D(
				Basis.from_euler(
					Vector3(rng.randf_range(-0.30, 0.30), rng.randf() * TAU, rng.randf_range(-0.30, 0.30))
				),
				center
			),
			tint.lightened(rng.randf_range(-0.04, 0.07)), false
		)
	# One central puff binds the airy clumps into a crown.
	baker.add_foliage_clump(
		leaf_key,
		Vector3(0.62, 0.58, 0.62) * crown_scale * scale,
		rings, segments, rng.randi(),
		_origin * Transform3D(
			Basis.IDENTITY,
			base + Vector3(0.0, 1.05 * crown_scale + 0.35 * start, 0.0)
		),
		tint, false
	)


func _build_bush(baker: MeshBaker, placement: VillageLayout.Placement, detail: bool) -> void:
	var start := baker.get_triangle_count()
	var scale := placement.scale * 0.82
	var variant := placement.variant % 3
	var tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.13))
	var lumps := 4 if detail else 3
	var spread := (0.92 if variant == 1 else 0.64) * scale
	var top := (0.95 if variant == 2 else 0.66) * scale
	var rings := 3 if detail else 2
	var segments := 6 if detail else 5
	for index in lumps:
		var angle := TAU * float(index) / float(lumps) + rng.randf_range(-0.45, 0.45)
		var radial := spread * rng.randf_range(0.18, 0.95)
		var offset := Vector3(cos(angle) * radial, 0.0, sin(angle) * radial)
		var radii := Vector3(
			rng.randf_range(0.38, 0.52),
			rng.randf_range(0.30, 0.48),
			rng.randf_range(0.36, 0.50)
		) * scale
		var key := "leaf_deep" if index % 2 == 0 else "leaf_mid"
		baker.add_foliage_clump(
			key, radii, rings, segments, rng.randi(),
			_origin * Transform3D(
				Basis.from_euler(
					Vector3(rng.randf_range(-0.22, 0.22), rng.randf() * TAU, rng.randf_range(-0.22, 0.22))
				),
				Vector3(offset.x, top * rng.randf_range(0.45, 0.95), offset.z)
			),
			tint.lightened(rng.randf_range(-0.04, 0.06)), false
		)
	# Two twigs keep the mass from reading as a single green pillow.
	if detail:
		for _index in 2:
			var angle := rng.randf() * TAU
			var base := Vector3(cos(angle) * 0.12 * scale, 0.02, sin(angle) * 0.12 * scale)
			var tip := base + Vector3(
				cos(angle) * rng.randf_range(0.22, 0.42) * scale,
				rng.randf_range(0.40, 0.62) * scale,
				sin(angle) * rng.randf_range(0.22, 0.42) * scale
			)
			baker.add_limb(
				"trunk", PackedVector3Array([base, tip]),
				PackedFloat32Array([0.022 * scale, 0.006 * scale]),
				3, _origin, Color.WHITE.darkened(0.15), 0.04
			)
	# Variant 2 is a flowering shrub: bright heads on the green, in the same
	# palette as awnings and shutters, so the meadow edge and the pond shore get
	# a seasonal accent without a single new material.
	var flowers := 0
	if variant == 2:
		flowers = 8 if detail else 4
		for index in flowers:
			var angle := rng.randf() * TAU
			var away := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.12, 0.62) * scale
			var key := "cloth_cream" if index % 3 != 1 else "cloth_red"
			baker.add_sphere(
				key, rng.randf_range(0.065, 0.095) * scale, 2, 4,
				_origin * Transform3D(
					Basis.IDENTITY.scaled(Vector3(1.0, 0.62, 1.0)),
					Vector3(
						away.x,
						top * rng.randf_range(0.55, 0.95),
						away.z
					)
				),
				Color.WHITE.darkened(rng.randf_range(0.0, 0.08))
			)
	last_stats = {
		"kind": placement.kind, "variant": variant, "detail": detail,
		"trunk_base_radius": 0.0, "trunk_top_radius": 0.0,
		"crown_extent": Vector3(spread * 2.0, top, spread * 2.0),
		"crown_clumps": lumps, "flowers": flowers,
		"triangles": baker.get_triangle_count() - start,
		"top": Vector3(0.0, top, 0.0),
	}


## A flower patch is deliberately not a new material: stems use the leaf greens
## and heads reuse the cloth and autumn colours already in the palette. Three
## variants (daisy cream, poppy red, marigold orange) are enough to break the
## green edge of the meadow without turning it into a colour chart.
func _build_flower_patch(
	baker: MeshBaker, placement: VillageLayout.Placement, detail: bool
) -> void:
	var start := baker.get_triangle_count()
	var scale := placement.scale
	var variant := placement.variant % 3
	var head_key: String = ["cloth_cream", "cloth_red", "leaf_autumn"][variant]
	var stem_tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.10))
	var stems := 6 if detail else 4
	for index in stems:
		var angle := rng.randf() * TAU
		var base := Vector3(
			cos(angle) * rng.randf_range(0.0, 0.40) * scale,
			0.0,
			sin(angle) * rng.randf_range(0.0, 0.40) * scale
		)
		var height := rng.randf_range(0.30, 0.56) * scale
		var lean_angle := rng.randf() * TAU
		var lean := Vector3(cos(lean_angle), 0.0, sin(lean_angle)) * rng.randf_range(0.04, 0.12) * scale
		# The blade's local Z points away from the clump, so the bend leans out.
		var basis := Basis.from_euler(
			Vector3(0.0, PI * 0.5 - angle, rng.randf_range(-0.18, 0.18))
		)
		baker.add_blade(
			"leaf_mid", height, 0.034 * scale, 0.011 * scale,
			Vector2(rng.randf_range(-0.02, 0.02), rng.randf_range(0.04, 0.12) * scale),
			_origin * Transform3D(basis, base), stem_tint, 0.28, true
		)
		var head_position := base + Vector3(lean.x, height, lean.z)
		baker.add_sphere(
			head_key, rng.randf_range(0.065, 0.095) * scale, 2, 4,
			_origin * Transform3D(
				Basis.IDENTITY.scaled(Vector3(1.0, 0.62, 1.0)), head_position
			),
			Color.WHITE.darkened(rng.randf_range(0.0, 0.06))
		)
		# A warm centre on the pale daisy; on the other variants the head is the
		# accent, and a second colour there would turn it muddy.
		if detail and variant == 0:
			baker.add_sphere(
				"leaf_autumn", 0.030 * scale, 2, 4,
				_origin * Transform3D(
					Basis.IDENTITY, head_position + Vector3(0.0, 0.015 * scale, 0.0)
				),
				Color.WHITE
			)
	# A rosette of low leaves anchors the stems to the ground.
	for index in 3:
		var angle := TAU * float(index) / 3.0 + rng.randf_range(-0.4, 0.4)
		var basis := Basis.from_euler(Vector3(0.0, PI * 0.5 - angle, rng.randf_range(-0.5, -0.2)))
		baker.add_blade(
			"leaf_bright", 0.16 * scale, 0.075 * scale, 0.020 * scale, Vector2.ZERO,
			_origin * Transform3D(basis, Vector3(0.0, 0.01, 0.0)),
			Color.WHITE.darkened(rng.randf_range(0.0, 0.10)), 0.20, true
		)
	last_stats = {
		"kind": placement.kind, "variant": variant, "detail": detail,
		"trunk_base_radius": 0.0, "trunk_top_radius": 0.0,
		"crown_extent": Vector3(0.8, 0.5, 0.8) * scale,
		"crown_clumps": 0, "flowers": stems,
		"triangles": baker.get_triangle_count() - start,
		"top": Vector3(0.0, 0.5 * scale, 0.0),
	}


static func rock_dimensions(variant: int) -> Vector3:
	match posmod(variant, 3):
		0:
			# Broad ledge stone, around knee height at unit scale.
			return Vector3(1.58, 0.88, 1.18)
		1:
			# Taller shoulder with a narrower footprint.
			return Vector3(1.34, 1.08, 1.48)
		_:
			# Long, low, oblong boulder for damp ground and stream edges.
			return Vector3(1.72, 0.78, 1.26)


func _build_rock(baker: MeshBaker, placement: VillageLayout.Placement) -> void:
	var start := baker.get_triangle_count()
	var scale := placement.scale
	var variant := posmod(placement.variant, 3)
	var rock_key := "rock_wet" if variant == 2 else "rock"
	var tint := Color.WHITE.darkened(rng.randf_range(0.025, 0.16))
	if scale < 0.55:
		# Pebbles are a small, irregular knot rather than one scaled-down boulder.
		# Their bases are sunk into the terrain and they deliberately have no
		# collider, so walking across a gravel edge stays unobstructed.
		var pebble_count := 3 if rng.randf() < 0.78 else 4
		var scale_factor := maxf(scale, 0.25) / 0.5
		var phase := rng.randf() * TAU
		for pebble in pebble_count:
			var angle := phase + TAU * float(pebble) / float(pebble_count)
			angle += rng.randf_range(-0.22, 0.22)
			var distance := rng.randf_range(0.16, 0.30) * scale_factor
			var offset := Vector2(cos(angle), sin(angle)) * distance
			var pebble_size := Vector3(
				rng.randf_range(0.38, 0.54),
				rng.randf_range(0.22, 0.34),
				rng.randf_range(0.32, 0.48)
			) * scale_factor
			var pebble_yaw := rng.randf_range(0.0, TAU)
			var pebble_transform := Transform3D(
				Basis.from_euler(Vector3(0.0, pebble_yaw, 0.0)),
				Vector3(offset.x, 0.0, offset.y)
			)
			var pebble_seed := rng.randi() * 3 + (variant + pebble) % 3
			baker.add_rock(
				rock_key, pebble_size, pebble_seed, _origin * pebble_transform,
				tint.lightened(rng.randf_range(0.0, 0.07)), 0.10
			)
		last_stats = {
			"kind": placement.kind, "variant": variant, "detail": true,
			"triangles": baker.get_triangle_count() - start,
			"rock_pieces": pebble_count,
			"grounded_base": true,
		}
		return

	var dimensions := rock_dimensions(variant) * scale
	var main_seed := rng.randi() * 3 + variant
	baker.add_rock(rock_key, dimensions, main_seed, _origin, tint, 0.14)
	var pieces := 1

	# A smaller shoulder overlaps one edge of the main body. The intentional
	# overlap hides a seam; both profiles begin below the terrain anchor, so it
	# reads as one buried cluster rather than two clean shapes balanced together.
	var chip_angle := rng.randf() * TAU
	var chip_offset := Vector3(
		cos(chip_angle) * dimensions.x * 0.32,
		0.0,
		sin(chip_angle) * dimensions.z * 0.31
	)
	var chip_size := Vector3(0.58, 0.46, 0.62) * scale
	var chip_transform := Transform3D(
		Basis.from_euler(Vector3(0.0, rng.randf() * TAU, 0.0)), chip_offset
	)
	baker.add_rock(
		rock_key, chip_size, rng.randi() * 3 + (variant + 1) % 3,
		_origin * chip_transform, tint.lightened(0.04), 0.11
	)
	pieces += 1
	if rng.randf() < 0.32:
		var shard_offset := Vector3(
			-cos(chip_angle) * dimensions.x * 0.36,
			0.0,
			-sin(chip_angle) * dimensions.z * 0.34
		)
		var shard_size := Vector3(0.42, 0.34, 0.48) * scale
		baker.add_rock(
			rock_key, shard_size, rng.randi() * 3 + (variant + 2) % 3,
			_origin * Transform3D(Basis.IDENTITY, shard_offset),
			tint.lightened(rng.randf_range(0.02, 0.07)), 0.10
		)
		pieces += 1
	last_stats = {
		"kind": placement.kind, "variant": variant, "detail": true,
		"triangles": baker.get_triangle_count() - start,
		"rock_dimensions": dimensions,
		"rock_pieces": pieces,
		"grounded_base": true,
	}


# --- shared plant geometry ---------------------------------------------------


## Trunk axis: a curve that starts buried under the ground line, bends towards
## `lean` with height and returns most of the way. The points are what `add_limb`
## needs; no separate cylinder is involved.
func _trunk_points(
	height: float, lean: Vector3, bend: Vector3, segments: int
) -> PackedVector3Array:
	var points := PackedVector3Array()
	for index in segments + 1:
		var t := float(index) / float(maxi(segments, 1))
		var sway := sin(t * PI * 0.9) * bend
		points.append(
			Vector3(
				lean.x * pow(t, 1.35) + sway.x * t,
				-0.16 + height * t,
				lean.z * pow(t, 1.35) + sway.z * t
			)
		)
	return points


## Radius per trunk point: a root flare at the very bottom, a fast first taper,
## then a gentle narrowing towards the crown. A cylinder with a uniform radius
## was the most obvious primitive tell on the old trees.
func _trunk_radii(
	base: float, top: float, segments: int, flare: float
) -> PackedFloat32Array:
	var radii := PackedFloat32Array()
	for index in segments + 1:
		var t := float(index) / float(maxi(segments, 1))
		var radius := lerpf(base, top, pow(t, 0.85))
		if index == 0:
			radius *= flare
		elif index == 1:
			radius *= 1.0 + (flare - 1.0) * 0.35
		radii.append(radius)
	return radii


## Two or three buttresses from the trunk into the ground. They hide the point
## where a trunk meets a slope, which a straight cylinder can never do from
## close up.
func _add_root_flare(
	baker: MeshBaker, base_radius: float, tint: Color, count: int
) -> void:
	for index in count:
		var angle := TAU * float(index) / float(maxi(count, 1)) + rng.randf_range(-0.35, 0.35)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var reach := base_radius * rng.randf_range(2.0, 2.9)
		var points := PackedVector3Array([
			direction * base_radius * 0.5 + Vector3(0.0, base_radius * 1.7, 0.0),
			direction * base_radius * 1.5 + Vector3(0.0, base_radius * 0.7, 0.0),
			direction * reach + Vector3(0.0, -0.05, 0.0)
		])
		var radii := PackedFloat32Array([
			base_radius * 0.62, base_radius * 0.36, base_radius * 0.08
		])
		baker.add_limb("trunk", points, radii, 4, _origin, tint.darkened(0.04), 0.06)


func _cylinder_collider(radius: float, height: float, offset: Vector3) -> Node3D:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	return _collider_node(shape, offset + Vector3(0.0, height * 0.5, 0.0))


func _box_collider(size: Vector3, offset: Vector3) -> Node3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return _collider_node(shape, offset)


func _collider_node(shape: Shape3D, offset: Vector3) -> Node3D:
	var node := CollisionShape3D.new()
	node.shape = shape
	node.position = offset
	return node
