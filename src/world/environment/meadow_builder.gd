class_name MeadowBuilder
extends RefCounted
## The meadow: one [MultiMesh] of tufts plus the colour field that tints it.
##
## Visual polish 16 moved ground cover out of [VegetationBuilder] because the
## two halves of the vegetation are built in completely different ways. Trees,
## shrubs, flowers and boulders are *baked*: every solid is merged into a few
## meshes, so their cost is triangles. Grass is *instanced*: one mesh, one draw
## call, thousands of copies, so its cost is memory and fill rate. Keeping them
## apart keeps either file readable, and it makes the trade explicit.
##
## The tuft itself is five tapered, bent blades ([method MeshBaker.add_blade])
## instead of the old pair of crossed alpha quads: opaque geometry needs no
## cut-out, so there is no fringe to see at grazing angles and no sorting.
##
## Distribution is two-scale: half the tufts cluster in loose clumps, the other
## half is a thin wash. The colour is a slow patch field (see [method
## _meadow_tint]) rather than per-blade dice, because a per-blade roll at this
## density reads as confetti from the game camera.

const GRASS_COUNT := 3200
## Kinds whose footprint grass must stay out of: a blade on a stoop, inside a
## crate or through a flower patch is the cheapest way to make a village look
## unfinished. Trees, shrubs and stones are excluded on purpose — grass grows
## around those.
const GRASS_EXCLUSION_KINDS := [
	VillageLayout.KIND_HOUSE, VillageLayout.KIND_INN, VillageLayout.KIND_HALL,
	VillageLayout.KIND_WELL, VillageLayout.KIND_STALL, VillageLayout.KIND_CART,
	VillageLayout.KIND_CRATE, VillageLayout.KIND_BARREL, VillageLayout.KIND_LOGPILE,
	VillageLayout.KIND_FENCE, VillageLayout.KIND_FLOWER_BOX, VillageLayout.KIND_BENCH,
	VillageLayout.KIND_FLOWER_PATCH
]
## Blades per tuft and tuft footprint for the two-scale grass scatter. Five
## tapered blades read as a tuft from the walking camera; the old pair of
## crossed quads read as a green billboard.
const GRASS_BLADES := 5
const GRASS_CLUMPS := 260
const GRASS_CLUMP_RADIUS := 3.6
const GRASS_CLUMP_CHANCE := 0.50
## Meadow palette. Instance colours multiply the shared blade albedo, so these
## are pushed towards the colour of the ground they grow from: deep green in the
## hollows, sun-bleached gold on the dry patches. They are chosen in *patches*
## (see `_meadow_tint`), not per blade, so the meadow reads as fields.
const MEADOW_GREEN := Color(0.60, 0.78, 0.42)
const MEADOW_LUSH := Color(0.46, 0.68, 0.34)
const MEADOW_DRY := Color(0.80, 0.76, 0.44)


var rng := RandomNumberGenerator.new()
## Two phases of the low-frequency meadow patchiness, drawn once from the seed
## so the same meadow rebuilds identically.
var _patch_phase := Vector2.ZERO


func _init(seed_value: int = 0) -> void:
	rng.seed = seed_value
	_patch_phase = Vector2(rng.randf() * TAU, rng.randf() * TAU)


## Ground cover as a single `MultiMeshInstance3D`. Two scales of scatter: a
## uniform wash plus loose clumps, so the meadow reads as tufts and clearings
## instead of a noise field of evenly spaced blades. Grass near the pond grows
## taller (reeds), and the colour follows a slow patch field rather than the
## per-blade dice roll that used to produce confetti.
func build_grass(
	layout: VillageLayout, terrain: TerrainGenerator, materials: VillageMaterials,
	count: int = GRASS_COUNT
) -> MultiMeshInstance3D:
	var mesh := _bake_grass_tuft(materials)
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.use_colors = true
	multi_mesh.mesh = mesh
	multi_mesh.instance_count = 0

	var half := terrain.get_half_extent()
	var clumps: Array[Vector2] = []
	for index in GRASS_CLUMPS:
		clumps.append(Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half)))
	var transforms: Array[Transform3D] = []
	var colors := PackedColorArray()
	var attempts := 0
	var limit := maxi(count, 1) * 6
	while transforms.size() < count and attempts < limit:
		attempts += 1
		var x := 0.0
		var z := 0.0
		if rng.randf() < GRASS_CLUMP_CHANCE:
			var clump := clumps[rng.randi_range(0, clumps.size() - 1)]
			var angle := rng.randf() * TAU
			var radius := rng.randf() * GRASS_CLUMP_RADIUS
			x = clump.x + cos(angle) * radius
			z = clump.y + sin(angle) * radius
		else:
			x = rng.randf_range(-half, half)
			z = rng.randf_range(-half, half)
		if absf(x) > half or absf(z) > half:
			continue
		if layout.plaza_weight(x, z) > 0.05 or layout.road_weight(x, z) > 0.15:
			continue
		if layout.pond_weight(x, z) > 0.30:
			continue
		if _inside_prop_footprint(layout, x, z):
			continue
		var wet := clampf(layout.pond_weight(x, z), 0.0, 1.0)
		var scale := rng.randf_range(0.68, 1.48) * (1.0 + wet * 0.55)
		var basis := Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3.ONE * scale)
		transforms.append(
			Transform3D(basis, Vector3(x, terrain.height_at(x, z) - 0.03, z))
		)
		colors.append(_meadow_tint(x, z))

	multi_mesh.instance_count = transforms.size()
	for index in transforms.size():
		multi_mesh.set_instance_transform(index, transforms[index])
		multi_mesh.set_instance_color(index, colors[index])

	var instance := MultiMeshInstance3D.new()
	instance.name = "Grass"
	instance.multimesh = multi_mesh
	instance.material_override = materials.get_material("grass_blade")
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## One tuft, baked once. Five slender blades at different heights, each one
## tapered and bent outward; no transparency, no billboard cross.
func _bake_grass_tuft(materials: VillageMaterials) -> Mesh:
	var tuft := MeshBaker.new()
	for index in GRASS_BLADES:
		var angle := TAU * float(index) / float(GRASS_BLADES) + rng.randf_range(-0.35, 0.35)
		var height := rng.randf_range(0.38, 0.72)
		var base := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.0, 0.06)
		var basis := Basis.from_euler(
			Vector3(0.0, PI * 0.5 - angle, rng.randf_range(-0.22, 0.22))
		)
		tuft.add_blade(
			"grass_blade", height, 0.055, 0.012,
			Vector2(rng.randf_range(-0.03, 0.03), rng.randf_range(0.06, 0.18)),
			Transform3D(basis, base),
			Color(0.96, 1.0, 0.90).darkened(rng.randf_range(0.0, 0.12)), 0.30
		)
	var mesh: Mesh = null
	for node in tuft.commit(materials):
		var instance := node as MeshInstance3D
		mesh = instance.mesh
		instance.free()
	return mesh


## Slow, coherent colour field: nearby tufts share a hue, so the meadow reads as
## patches of lush green and dry gold instead of a pixel-noise confetti. A small
## per-blade jitter stays on top so a patch is not a flat colour either.
func _meadow_tint(x: float, z: float) -> Color:
	var wave := sin(x * 0.115 + _patch_phase.x) * cos(z * 0.092 + _patch_phase.y)
	var patch := 0.5 + 0.5 * wave
	var tint := MEADOW_GREEN.lerp(MEADOW_DRY, smoothstep(0.56, 0.94, patch))
	tint = tint.lerp(MEADOW_LUSH, smoothstep(0.34, 0.02, patch) * 0.55)
	return tint.darkened(rng.randf_range(0.0, 0.14))


# --- helpers -----------------------------------------------------------------


## True where a blade would poke through a solid prop, stand on a doorstep or
## sprout out of a flower patch.
func _inside_prop_footprint(layout: VillageLayout, x: float, z: float) -> bool:
	var point := Vector2(x, z)
	for placement in layout.placements:
		if not GRASS_EXCLUSION_KINDS.has(placement.kind):
			continue
		var radius: float = placement.footprint_radius * placement.scale + 0.55
		if point.distance_to(placement.position) < radius:
			return true
	return false
