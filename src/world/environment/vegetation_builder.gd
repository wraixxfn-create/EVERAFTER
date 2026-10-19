class_name VegetationBuilder
extends RefCounted
## Trees, shrubs, meadow flowers, rocks and ground cover.
##
## Two passes built this. Polish 16 replaced cylinders and UV spheres with a
## small vocabulary of organic solids in [MeshBaker] — a tapered `limb`, a lobed
## `foliage_clump`, a tapered `blade`, a stratified `rock`. Polish 18 rebuilt
## **how a tree is grown** on top of them, because a crown tied to a pole still
## read as a boulder on a stick:
##
## * **conifers** (spruce, mugo, scots pine) are whorls of needles, not stacks of
##   cones or discs: `add_frond_ring` lays out a star-shaped rim of pointed
##   needles hanging from a solid inner cone, and consecutive whorls overlap.
##   The scots pine keeps its long bare trunk and carries flat leaf clouds over
##   it, which is what separates a pine from a spruce at a glance.
## * **broadleaves** (oaks) grow a skeleton first — tapered trunk with a root
##   flare, five primaries, secondaries, a couple of bare twigs — and then hang
##   many small, flattened leaf bunches on the tips and inside the crown.
## * **birches** are a loose veil: a pale tapering stem, ascending branches and
##   clusters with visible gaps between them, never a solid ball.
## * every clump carries a vertical tint gradient (lit top, dark underside), so
##   a crown made of dozens of masses still reads as one volume.
##
## Heights stay believable next to a 1.8 m player: oak 4–5 m to the crown, birch
## 3.5–4.5 m, spruce 5–6 m, scots pine 4.5–5 m with half of it bare trunk, mugo
## under 2.5 m. The three variants of a species differ in *shape*, not in scale.
##
## Two performance rules still drive this file:
## * **everything static is merged.** `VillageBuilder` hands one [MeshBaker] to
##   the whole forest, so hundreds of trees become a handful of meshes.
## * **detail follows distance.** Trees inside [constant DETAIL_RADIUS] or along
##   a road get the full crown; the outer forest uses a cheap silhouette that is
##   still species-specific. `VillageBuilder` decides with [method needs_detail].
## Grass, the one instanced part, lives in [MeadowBuilder] and is reached through
## [method build_grass].

const LEAF_KEYS := ["leaf_deep", "leaf_mid", "leaf_bright"]
const TREE_COLLIDER_KINDS := [
	VillageLayout.KIND_TREE_PINE, VillageLayout.KIND_TREE_OAK, VillageLayout.KIND_TREE_BIRCH
]
## Full detail inside this radius, and along the roads the player walks; the
## rest of the border forest keeps a cheaper silhouette. It shrank from 44 m to
## 22 m: the new crowns cost more per tree, and the branch structure is worth
## paying for only where the player actually walks.
const DETAIL_RADIUS := 22.0
const ROAD_DETAIL_CORRIDOR := 6.0

var rng := RandomNumberGenerator.new()
## Shape facts of the plant built by the last `append` call, for the headless
## suite (variants differ, trunks really taper). Not read by the game.
var last_stats := {}

## See `BuildingFactory._origin`: merged vegetation has no node of its own, so
## every solid is emitted already placed in the world.
var _origin := Transform3D.IDENTITY
## Builds the instanced grass tufts and their colour field.
var _meadow: MeadowBuilder = null


func _init(seed_value: int = 0) -> void:
	rng.seed = seed_value
	_meadow = MeadowBuilder.new(seed_value + 13)


## Builds one placement; [param detail] false selects the far silhouette.
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
## shrubs, flowers and grass are walkable, or the village becomes a pinball
## table. Radii follow the species' real trunk.
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
# Visual Polish 18 rebuilt the trees a second time. Polish 16 had already
# replaced the lollipop with lobed clumps, but the construction was still "a
# few big balls tied to a pole": from the plaza an oak read as a green boulder
# on a stick, and a spruce as a pile of separate cones. This pass changes how a
# tree is *grown*:
#
# * **conifers** are whorls of needles. [method MeshBaker.add_frond_ring] builds
#   a star-shaped rim of pointed, drooping needles around a solid inner cone,
#   and consecutive whorls overlap: the silhouette is a spiky spire that changes
#   with every ring instead of a stack of discs.
# * **broadleaves** grow a skeleton first — trunk, five primaries, secondaries —
#   and then hang many small, flattened leaf clumps at the branch tips and
#   inside the crown. The wood carries the leaves and the outline is ragged.
# * **the scots pine** keeps its long bare trunk and carries flat, wide leaf
#   clouds above it: an umbrella, not a cone.
# * every clump carries a vertical tint gradient (lit top, dark underside), so
#   a crown made of dozens of masses still reads as one volume.
#
# Heights are realistic next to a 1.8 m player: oak 5–7 m to the crown, birch
# 4–5.5 m, spruce 5–6 m, scots pine 4.5–5 m with half of it bare trunk,
# mugo pine under 2.5 m. The variants of each species differ in *shape*, not in
# scale: broad and tall and leaning for oaks, slender and twin-stemmed and
# autumn for birches.


func _pine_profile(variant: int) -> Dictionary:
	match variant:
		1:
			# Scots pine: a long bare trunk under a flat umbrella of needles.
			return {
				"kind": "umbrella", "trunk": 4.4, "radius": 0.20, "start": 0.58,
				"levels": 0, "spread": 0.0, "short": 0.80,
			}
		2:
			# Young mugo pine: short, wide, almost a bush with a trunk.
			return {
				"kind": "whorl", "trunk": 2.10, "radius": 0.18, "start": 0.08,
				"levels": 7, "spread": 0.62, "short": 0.54,
			}
	# Norway spruce: the full spire, needles almost to the ground.
	return {
		"kind": "whorl", "trunk": 5.30, "radius": 0.20, "start": 0.10,
		"levels": 8, "spread": 0.27, "short": 0.62,
	}


func _oak_profile(variant: int) -> Dictionary:
	match variant:
		1:
			# Tall oak: a longer trunk and a high, narrow crown.
			return {
				"trunk": 3.30, "radius": 0.30, "x": 2.65, "y": 0.98, "z": 0.95,
				"lean_x": 0.0, "lean_z": 0.0, "limbs": 5, "reach": 0.62,
			}
		2:
			# Leaning oak: thrown to one side, low and broad, the tree you
			# shelter under.
			return {
				"trunk": 2.20, "radius": 0.36, "x": 3.45, "y": 0.70, "z": 1.10,
				"lean_x": 0.48, "lean_z": -0.26, "limbs": 5, "reach": 0.68,
			}
	# Broad oak: the reference silhouette, as wide as it is tall.
	return {
		"trunk": 2.70, "radius": 0.33, "x": 3.15, "y": 0.80, "z": 1.05,
		"lean_x": 0.0, "lean_z": 0.0, "limbs": 5, "reach": 0.58,
	}


func _birch_profile(variant: int) -> Dictionary:
	match variant:
		1:
			# Twin stem: two pale trunks from one root, staggered crowns.
			return {
				"trunk": 3.55, "stems": 2, "spread": 0.40, "crown": 1.0,
				"leaf": "leaf_bright", "branches": 5,
			}
		2:
			# Autumn birch: the one warm crown in the treeline.
			return {
				"trunk": 3.95, "stems": 1, "spread": 0.0, "crown": 1.04,
				"leaf": "leaf_autumn", "branches": 5,
			}
	return {
		"trunk": 3.45, "stems": 1, "spread": 0.0, "crown": 0.96,
		"leaf": "leaf_bright", "branches": 5,
	}


func _build_pine(baker: MeshBaker, placement: VillageLayout.Placement, detail: bool) -> void:
	var start := baker.get_triangle_count()
	var scale := placement.scale
	var variant := placement.variant % 3
	var profile := _pine_profile(variant)
	var bark_tint := Color.WHITE.darkened(rng.randf_range(0.02, 0.09))
	var needle_tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.12))
	var trunk_height := float(profile["trunk"]) * scale * rng.randf_range(0.94, 1.06)
	var base_radius := float(profile["radius"]) * scale * rng.randf_range(0.94, 1.06)
	var lean := Vector3(rng.randf_range(-0.10, 0.10), 0.0, rng.randf_range(-0.10, 0.10)) * scale
	var bend := Vector3(rng.randf_range(-0.06, 0.06), 0.0, rng.randf_range(-0.06, 0.06)) * scale
	var trunk_segments := 4 if detail else 3
	var points := _trunk_points(trunk_height, lean, bend, trunk_segments)
	var trunk_radii := _trunk_radii(base_radius, base_radius * 0.12, trunk_segments, 1.55)
	baker.add_limb(
		"trunk", points, trunk_radii, 7 if detail else 4, _origin, bark_tint, 0.05
	)
	if detail:
		_add_root_flare(baker, base_radius, bark_tint, 3)
	var crown_base := trunk_height * float(profile["start"])
	var crown_clumps := 0
	if String(profile["kind"]) == "umbrella":
		crown_clumps = _build_scots_crown(
			baker, trunk_height, crown_base, base_radius, lean, bark_tint, needle_tint,
			detail
		)
	else:
		crown_clumps = _build_whorled_crown(
			baker, profile, trunk_height, crown_base, needle_tint, scale, detail
		)
	var top := points[points.size() - 1]
	last_stats = {
		"kind": placement.kind, "variant": variant, "detail": detail,
		"trunk_base_radius": base_radius,
		"trunk_top_radius": trunk_radii[trunk_radii.size() - 1],
		"crown_extent": Vector3(
			float(profile["spread"]) * trunk_height * 2.0 + 0.60,
			trunk_height * (0.30 if String(profile["kind"]) == "umbrella" else 0.90),
			float(profile["spread"]) * trunk_height * 2.0 + 0.60
		),
		"crown_clumps": crown_clumps,
		"triangles": baker.get_triangle_count() - start,
		"top": Vector3(top.x, trunk_height * 0.95, top.z),
	}


## Spruce and mugo: a column of overlapping needle whorls, each hanging
## `drop` below its own ring height. That sag is what makes them branches.
func _build_whorled_crown(
	baker: MeshBaker, profile: Dictionary, trunk_height: float, crown_start: float,
	needle_tint: Color, scale: float, detail: bool
) -> int:
	var levels := int(profile["levels"])
	if detail:
		levels = mini(levels, 6)
	else:
		levels = maxi(levels - 4, 4)
	var spread := float(profile["spread"]) * trunk_height
	var top := trunk_height * 0.92
	var step := (top - crown_start) / float(maxi(levels - 1, 1))
	var segments := 12 if detail else 5
	var clumps := 0
	for level in levels:
		var fraction := float(level) / float(maxi(levels - 1, 1))
		var y := crown_start + step * float(level)
		var radius := spread * pow(1.0 - fraction * 0.80, 0.75) + 0.10 * scale
		var drop := step * (1.40 if detail else 1.10)
		var tone := 0.16 * float((level * 5) % 3) * 0.5
		baker.add_frond_ring(
			"pine", y, radius, drop, segments, 91 + level,
			_origin, needle_tint.lightened(tone), float(profile["short"])
		)
		clumps += 1
	# The spire: three shrinking clumps rising out of the last whorl, so the top
	# is a needle tip instead of a diamond floating over the tree.
	var tip_y := top + step * 0.15
	for index in (3 if detail else 2):
		var f := float(index) / 2.0
		baker.add_foliage_clump(
			"pine",
			Vector3(0.26 * (1.0 - f * 0.65) + 0.04, 0.30 * (1.0 - f * 0.55) + 0.05,
				0.26 * (1.0 - f * 0.65) + 0.04) * scale,
			2, 5, 311 + index,
			_origin * Transform3D(Basis.IDENTITY, Vector3(0.0, tip_y + f * 0.42, 0.0)),
			needle_tint.lightened(0.06 * f), false, 0.14
		)
		clumps += 1
	return clumps


## Scots pine: four exposed limbs above the bare trunk, each carrying a flat
## cloud of needles. That shape separates a pine from a spruce at a glance.
func _build_scots_crown(
	baker: MeshBaker, trunk_height: float, crown_start: float, base_radius: float,
	lean: Vector3, bark_tint: Color, needle_tint: Color, detail: bool
) -> int:
	var clumps := 0
	var fork := Vector3(lean.x * 0.62, -0.16 + crown_start, lean.z * 0.62)
	var limbs := 4
	for index in limbs:
		var angle := TAU * float(index) / float(limbs) + rng.randf_range(-0.30, 0.30)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var length := trunk_height * rng.randf_range(0.15, 0.21)
		var tip := fork + direction * length + Vector3(
			0.0, length * rng.randf_range(0.80, 1.10), 0.0
		)
		baker.add_limb(
			"trunk", PackedVector3Array([fork, tip]),
			PackedFloat32Array([base_radius * 0.55, base_radius * 0.18]),
			5 if detail else 4, _origin, bark_tint, 0.06
		)
		clumps += _add_leaf_cloud(
			baker, "pine", tip, length * 1.20, length * 0.42, needle_tint, detail
		)
		if detail:
			for branch in 1:
				var along := rng.randf_range(0.30, 0.65)
				var origin := fork + (tip - fork) * along
				var side_angle := angle + (1.0 if branch == 0 else -1.0) * rng.randf_range(0.45, 0.85)
				var side := Vector3(cos(side_angle), 0.0, sin(side_angle))
				var side_tip := origin + side * length * rng.randf_range(0.45, 0.75) + Vector3(
					0.0, length * rng.randf_range(0.10, 0.40), 0.0
				)
				baker.add_limb(
					"trunk", PackedVector3Array([origin, side_tip]),
					PackedFloat32Array([base_radius * 0.22, base_radius * 0.07]),
					4, _origin, bark_tint, 0.06
				)
				clumps += _add_leaf_cloud(
					baker, "pine", side_tip, length * 0.85, length * 0.32, needle_tint, detail
				)
	# The crown itself: a wider, flatter cloud over the fork.
	var crown_center := Vector3(lean.x, -0.16 + trunk_height * 0.90, lean.z)
	clumps += _add_leaf_cloud(
		baker, "pine", crown_center, trunk_height * 0.11, trunk_height * 0.055,
		needle_tint, detail
	)
	return clumps


## A flat cloud of needle clumps: lobes spread over a squashed ellipsoid by a
## golden-angle spiral, so they overlap evenly instead of clustering in a line.
func _add_leaf_cloud(
	baker: MeshBaker, material_key: String, center: Vector3, radius_x: float,
	radius_y: float, tint: Color, detail: bool
) -> int:
	var lumps := 4 if detail else 3
	var rings := 2
	var segments := 5 if detail else 3
	var golden := PI * (3.0 - sqrt(5.0))
	var radius_z := radius_x * rng.randf_range(0.85, 1.15)
	for index in lumps:
		var latitude := 1.0 - 2.0 * (float(index) + 0.5) / float(lumps)
		var band := sqrt(maxf(0.0, 1.0 - latitude * latitude))
		var angle := golden * float(index) + rng.randf_range(-0.20, 0.20)
		var offset := Vector3(cos(angle) * band, latitude, sin(angle) * band)
		var position := center + Vector3(
			offset.x * radius_x, offset.y * radius_y, offset.z * radius_z
		) * rng.randf_range(0.45, 0.80)
		var size := maxf(radius_x, radius_z) * rng.randf_range(0.34, 0.46)
		baker.add_foliage_clump(
			material_key,
			Vector3(size, size * rng.randf_range(0.55, 0.75), size),
			rings, segments, rng.randi(),
			_origin * Transform3D(
				Basis.from_euler(
					Vector3(rng.randf_range(-0.22, 0.22), rng.randf() * TAU,
						rng.randf_range(-0.22, 0.22))
				),
				position
			),
			tint.lightened(rng.randf_range(-0.05, 0.07)), false, 0.28
		)
	return lumps


func _build_oak(baker: MeshBaker, placement: VillageLayout.Placement, detail: bool) -> void:
	var start := baker.get_triangle_count()
	var scale := placement.scale
	var variant := placement.variant % 3
	var profile := _oak_profile(variant)
	var trunk_height := float(profile["trunk"]) * scale * rng.randf_range(0.94, 1.06)
	var base_radius := float(profile["radius"]) * scale * rng.randf_range(0.92, 1.08)
	var lean := Vector3(
		rng.randf_range(-0.14, 0.14) + float(profile["lean_x"]),
		0.0,
		rng.randf_range(-0.12, 0.12) + float(profile["lean_z"])
	) * scale
	var bend := Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12)) * scale
	var bark_tint := Color.WHITE.darkened(rng.randf_range(0.03, 0.11))
	var leaf_tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.10))
	var trunk_segments := 4 if detail else 3
	var points := _trunk_points(trunk_height, lean, bend, trunk_segments)
	var trunk_radii := _trunk_radii(base_radius, base_radius * 0.42, trunk_segments, 1.60)
	baker.add_limb(
		"trunk", points, trunk_radii, 7 if detail else 4, _origin, bark_tint, 0.06
	)
	if detail:
		_add_root_flare(baker, base_radius, bark_tint, 3)
	var fork := points[points.size() - 1]
	var extents := Vector3(
		float(profile["x"]), float(profile["y"]) * float(profile["x"]), float(profile["z"])
	) * scale
	extents *= rng.randf_range(0.94, 1.06)
	var leaf_cycle := 0
	var tips: Array[Vector3] = []
	var limb_count := int(profile["limbs"])
	for index in limb_count:
		var angle := TAU * float(index) / float(limb_count) + rng.randf_range(-0.28, 0.28)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var length := extents.x * float(profile["reach"]) * rng.randf_range(0.85, 1.10)
		var tip := fork + direction * length + Vector3(
			0.0, extents.y * rng.randf_range(0.30, 0.95), 0.0
		)
		baker.add_limb(
			"trunk", PackedVector3Array([fork, tip]),
			PackedFloat32Array([base_radius * 0.50, base_radius * 0.18]),
			6 if detail else 3, _origin, bark_tint, 0.06
		)
		tips.append(tip)
		if detail:
			# One secondary per primary: a fork is what a broadleaf branch does,
			# and it doubles the number of places the leaves can hang from.
			var along := rng.randf_range(0.38, 0.62)
			var origin := fork + (tip - fork) * along
			var side_angle := angle + (1.0 if index % 2 == 0 else -1.0) * rng.randf_range(0.5, 0.95)
			var side := Vector3(cos(side_angle), 0.0, sin(side_angle))
			var side_tip := origin + side * length * rng.randf_range(0.55, 0.90) + Vector3(
				0.0, extents.y * rng.randf_range(-0.10, 0.45), 0.0
			)
			baker.add_limb(
				"trunk", PackedVector3Array([origin, side_tip]),
				PackedFloat32Array([base_radius * 0.22, base_radius * 0.07]),
				5, _origin, bark_tint, 0.06
			)
			tips.append(side_tip)
	var crown_center := fork + Vector3(0.0, extents.y * 0.62, 0.0)
	var inside := 2 if detail else 1
	for index in inside:
		var angle := TAU * float(index) / float(inside) + 0.7
		var position := crown_center + Vector3(
			cos(angle) * extents.x * 0.34,
			extents.y * rng.randf_range(-0.20, 0.60),
			sin(angle) * extents.z * 0.34
		)
		_add_leaf_bunch(
			baker, position, extents.x * 0.34, 3 if detail else 1,
			leaf_tint, detail, leaf_cycle
		)
		leaf_cycle += 1
	for index in tips.size():
		# A primary tip carries a fuller bunch than a secondary: that is what
		# keeps the crown edge varied instead of a ring of equal balls.
		var count := (3 if index < limb_count else 1) if detail else 1
		_add_leaf_bunch(
			baker, tips[index], extents.x * 0.38, count,
			leaf_tint, detail, leaf_cycle
		)
		leaf_cycle += 1
	# A ring of bunches above the fork closes the top of the crown. Without it
	# an oak seen from the path is an umbrella: wide, flat and hollow.
	var dome := 3 if detail else 1
	for index in dome:
		var angle := TAU * float(index) / float(dome) + 0.35
		var position := fork + Vector3(
			cos(angle) * extents.x * 0.26,
			extents.y * rng.randf_range(0.95, 1.45),
			sin(angle) * extents.z * 0.26
		)
		_add_leaf_bunch(
			baker, position, extents.x * 0.30, 3 if detail else 1,
			leaf_tint, detail, leaf_cycle
		)
		leaf_cycle += 1
	# Two bare twigs above the crown: a leaf mass that ends in a clean dome is
	# the most obvious tell of a primitive.
	if detail:
		for _index in 2:
			var angle := rng.randf() * TAU
			var origin := crown_center + Vector3(
				cos(angle) * extents.x * 0.30, extents.y * 0.62, sin(angle) * extents.x * 0.30
			)
			var tip := origin + Vector3(
				cos(angle) * extents.x * 0.10, extents.y * rng.randf_range(0.24, 0.40),
				sin(angle) * extents.x * 0.10
			)
			baker.add_limb(
				"trunk", PackedVector3Array([origin, tip]),
				PackedFloat32Array([base_radius * 0.09, base_radius * 0.02]),
				4, _origin, bark_tint, 0.05
			)
	last_stats = {
		"kind": placement.kind, "variant": variant, "detail": detail,
		"trunk_base_radius": base_radius,
		"trunk_top_radius": trunk_radii[trunk_radii.size() - 1],
		"crown_extent": Vector3(extents.x, extents.y * 2.0, extents.z),
		"crown_clumps": leaf_cycle,
		"triangles": baker.get_triangle_count() - start,
		"top": fork + Vector3(0.0, extents.y, 0.0),
	}


## Many small, flattened leaf clumps in a loose sphere. Equal sizes read as
## foliage; one big and three small balls read as a model.
func _add_leaf_bunch(
	baker: MeshBaker, center: Vector3, size: float, count: int,
	tint: Color, detail: bool, cycle: int
) -> void:
	var rings := 2
	var segments := 5 if detail else 3
	var golden := PI * (3.0 - sqrt(5.0))
	for index in count:
		var latitude := 1.0 - 2.0 * (float(index) + 0.5) / float(count)
		var band := sqrt(maxf(0.0, 1.0 - latitude * latitude))
		var angle := golden * float(index) + rng.randf_range(-0.30, 0.30)
		var offset := Vector3(cos(angle) * band, latitude * 0.78, sin(angle) * band)
		var position := center + offset * size * rng.randf_range(0.20, 0.60)
		var lump := size * rng.randf_range(0.62, 0.88)
		var key: String = LEAF_KEYS[(cycle + index) % LEAF_KEYS.size()]
		baker.add_foliage_clump(
			key,
			Vector3(lump, lump * rng.randf_range(0.62, 0.80), lump * 1.05),
			rings, segments, rng.randi(),
			_origin * Transform3D(
				Basis.from_euler(
					Vector3(rng.randf_range(-0.35, 0.35), rng.randf() * TAU,
						rng.randf_range(-0.35, 0.35))
				),
				position
			),
			tint.lightened(rng.randf_range(-0.06, 0.06)), false, 0.34
		)


func _build_birch(baker: MeshBaker, placement: VillageLayout.Placement, detail: bool) -> void:
	var start := baker.get_triangle_count()
	var scale := placement.scale
	var variant := placement.variant % 3
	var profile := _birch_profile(variant)
	var trunk_height := float(profile["trunk"]) * scale * rng.randf_range(0.94, 1.06)
	var base_radius := 0.15 * scale * rng.randf_range(0.94, 1.08)
	var bark_tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.05))
	var leaf_key := String(profile["leaf"])
	var leaf_tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.08))
	var stems := int(profile["stems"])
	var clusters := 0
	var crown_tops: Array[Vector3] = []
	for stem in stems:
		var stem_scale := 1.0 if stem == 0 else 0.82
		var stem_offset := Vector3(float(profile["spread"]) if stem == 1 else 0.0, 0.0, 0.0)
		var lean := Vector3(
			rng.randf_range(-0.16, 0.16), 0.0, rng.randf_range(-0.14, 0.14)
		) * scale
		var bend := Vector3(rng.randf_range(-0.08, 0.08), 0.0, rng.randf_range(-0.08, 0.08)) * scale
		var height := trunk_height * stem_scale
		var segments := 3 if detail else 2
		var points := _trunk_points(height, lean, bend, segments)
		for index in points.size():
			points[index] = points[index] + stem_offset
		var trunk_radii := _trunk_radii(
			base_radius * stem_scale, base_radius * 0.45 * stem_scale, segments, 1.35
		)
		baker.add_limb(
			"trunk_birch", points, trunk_radii, 6 if detail else 4, _origin, bark_tint, 0.07
		)
		var top := points[points.size() - 1]
		# Two short dark scars on the white bark: a box, not a ring, so the
		# trunk keeps its taper instead of growing a lump.
		if detail:
			for band in 2:
				var along := rng.randf_range(0.20, 0.60)
				var angle := rng.randf() * TAU
				var radius := lerpf(trunk_radii[0], trunk_radii[segments], along)
				var position := Vector3(
					lean.x * pow(along, 1.35), -0.16 + height * along, lean.z * pow(along, 1.35)
				) + stem_offset + Vector3(cos(angle), 0.0, sin(angle)) * radius * 0.80
				baker.add_box(
					"trunk",
					Vector3(0.11, 0.030, 0.055) * scale,
					_origin * Transform3D(
						Basis.from_euler(Vector3(0.0, -angle, 0.0)), position
					),
					Color.WHITE.darkened(rng.randf_range(0.28, 0.42))
				)
		# Ascending branches from the upper half, foliage in loose clusters at
		# the tips: a birch is a veil of leaves, never a ball.
		var branches := int(profile["branches"]) if detail else 1
		var crown_center := Vector3(top.x, -0.16 + height, top.z)
		for index in branches:
			var angle := TAU * float(index) / float(branches) + rng.randf_range(-0.40, 0.40)
			var direction := Vector3(cos(angle), 0.0, sin(angle))
			var origin := crown_center + Vector3(0.0, rng.randf_range(-0.90, 0.10), 0.0) * scale
			var length := height * rng.randf_range(0.20, 0.32)
			var tip := origin + direction * length + Vector3(
				0.0, length * rng.randf_range(0.95, 1.40), 0.0
			)
			baker.add_limb(
				"trunk_birch", PackedVector3Array([origin, tip]),
				PackedFloat32Array([base_radius * 0.34, base_radius * 0.10]),
				4, _origin, bark_tint, 0.06
			)
			clusters += _add_leaf_cluster(
				baker, leaf_key, tip, height * rng.randf_range(0.11, 0.15),
				leaf_tint, detail
			)
		var crown_lumps := 4 if detail else 1
		for index in crown_lumps:
			var angle := TAU * float(index) / float(crown_lumps) + rng.randf_range(-0.5, 0.5)
			var position := crown_center + Vector3(
				cos(angle) * height * rng.randf_range(0.05, 0.22),
				height * rng.randf_range(-0.06, 0.16),
				sin(angle) * height * rng.randf_range(0.05, 0.22)
			)
			clusters += _add_leaf_cluster(
				baker, leaf_key, position, height * rng.randf_range(0.11, 0.15),
				leaf_tint, detail
			)
		crown_tops.append(crown_center + Vector3(0.0, height * 0.16, 0.0))
	last_stats = {
		"kind": placement.kind, "variant": variant, "detail": detail,
		"trunk_base_radius": base_radius,
		"trunk_top_radius": base_radius * 0.45,
		"crown_extent": Vector3(1.9, 2.4, 1.9) * scale * float(profile["crown"]),
		"crown_clumps": clusters,
		"triangles": baker.get_triangle_count() - start,
		"top": crown_tops[0],
	}


## A loose handful of leaf clumps around one point, with gaps: a veil.
func _add_leaf_cluster(
	baker: MeshBaker, key: String, center: Vector3, size: float,
	tint: Color, detail: bool
) -> int:
	var lumps := 4 if detail else 2
	var rings := 2
	var segments := 5 if detail else 3
	for index in lumps:
		var angle := TAU * float(index) / float(lumps) + rng.randf_range(-0.4, 0.4)
		var lift := rng.randf_range(-1.05, 1.15)
		var offset := Vector3(
			cos(angle) * rng.randf_range(0.55, 1.45),
			lift,
			sin(angle) * rng.randf_range(0.55, 1.45)
		) * size
		var lump := size * rng.randf_range(0.45, 0.72)
		baker.add_foliage_clump(
			key,
			Vector3(lump, lump * rng.randf_range(0.70, 0.95), lump),
			rings, segments, rng.randi(),
			_origin * Transform3D(
				Basis.from_euler(
					Vector3(rng.randf_range(-0.30, 0.30), rng.randf() * TAU,
						rng.randf_range(-0.30, 0.30))
				),
				center + offset
			),
			tint.lightened(rng.randf_range(-0.05, 0.07)), false, 0.32
		)
	return lumps


func _build_bush(baker: MeshBaker, placement: VillageLayout.Placement, detail: bool) -> void:
	var start := baker.get_triangle_count()
	var scale := placement.scale * 0.82
	var variant := placement.variant % 3
	var tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.13))
	var lumps := 6 if detail else 3
	var spread := (1.05 if variant == 1 else 0.76) * scale
	var top := (0.95 if variant == 2 else 0.72) * scale
	var rings := 2
	var segments := 6 if detail else 4
	for index in lumps:
		var angle := TAU * float(index) / float(lumps) + rng.randf_range(-0.40, 0.40)
		var radial := spread * rng.randf_range(0.10, 0.85)
		var offset := Vector3(cos(angle) * radial, 0.0, sin(angle) * radial)
		var radii := Vector3(
			rng.randf_range(0.34, 0.48),
			rng.randf_range(0.28, 0.44),
			rng.randf_range(0.32, 0.46)
		) * scale
		var key := "leaf_deep" if index % 2 == 0 else "leaf_mid"
		baker.add_foliage_clump(
			key, radii, rings, segments, rng.randi(),
			_origin * Transform3D(
				Basis.from_euler(
					Vector3(rng.randf_range(-0.20, 0.20), rng.randf() * TAU,
						rng.randf_range(-0.20, 0.20))
				),
				Vector3(offset.x, top * rng.randf_range(0.40, 0.90), offset.z)
			),
			tint.lightened(rng.randf_range(-0.04, 0.06)), false, 0.30
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
					Vector3(away.x, top * rng.randf_range(0.55, 0.95), away.z)
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


## A flower patch adds no material: stems use the leaf greens, heads reuse the
## cloth and autumn colours. Daisy cream, poppy red and marigold orange break
## the green edge of the meadow without turning it into a colour chart.
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
		# Pebbles are an irregular knot, not one scaled-down boulder, and they
		# have no collider: a gravel edge stays walkable.
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

	# A smaller shoulder overlapping one edge hides the seam; both profiles
	# start below the terrain anchor, so it reads as one buried cluster.
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

## Trunk axis: a curve starting under the ground line and bending towards
## `lean`. These are the points `add_limb` needs; no cylinder is involved.
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


## Radius per trunk point: root flare, fast first taper, then a gentle
## narrowing towards the crown. A uniform radius is the primitive tell.
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


## Buttresses from the trunk into the ground: they hide the point where a
## trunk meets a slope, which a cylinder can never do from close up.
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
		baker.add_limb("trunk", points, radii, 3, _origin, tint.darkened(0.04), 0.06)


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
