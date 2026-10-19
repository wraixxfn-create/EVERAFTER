class_name VillageMaterials
extends RefCounted
## Single source of truth for the village palette and its materials.
##
## Why this exists:
## * one place decides the art direction, so a house, a stall and a fence can
##   never drift apart in colour;
## * every colour maps to **one shared** `StandardMaterial3D` instance. Godot
##   batches by material, so a village of 300 meshes with 14 materials costs far
##   less than 300 unique materials. This is the main reason the scene stays
##   comfortable on a GTX 1060 class GPU.
##
## Materials stay asset-light: there are no external textures or per-object
## shader instances. Surface character comes from shared PBR responses, subtle
## per-solid / per-face vertex colour and a small amount of purposeful geometry.
## That keeps the repository text-only and the draw-call budget predictable.
##
## `apply_night_glow()` is called once per frame by `SkyRig` with the daylight
## factor. It writes two properties on two shared materials, so the whole
## village lights up at dusk without any per-node work.

const PALETTE := {
	# Walls: plaster over wattle and daub, four warm tones so houses differ
	# without ever leaving the same family.
	"wall_cream": Color(0.88, 0.80, 0.64),
	"wall_ochre": Color(0.82, 0.62, 0.40),
	"wall_ash": Color(0.62, 0.58, 0.51),
	"wall_pale": Color(0.87, 0.81, 0.68),
	# Timber frame, doors, planks, handles: dark walnut against light plaster.
	"timber": Color(0.24, 0.15, 0.09),
	"timber_warm": Color(0.42, 0.26, 0.13),
	"plank": Color(0.58, 0.41, 0.23),
	"door": Color(0.28, 0.17, 0.09),
	# Roofs: terracotta tiles, dark shingles, blue slate, mossy thatch.
	"roof_tile": Color(0.72, 0.30, 0.18),
	"roof_shingle": Color(0.42, 0.23, 0.15),
	"roof_slate": Color(0.31, 0.35, 0.44),
	"roof_moss": Color(0.36, 0.43, 0.21),
	# Masonry and metal: warm stone, never cold grey.
	"stone": Color(0.61, 0.57, 0.50),
	"stone_dark": Color(0.39, 0.36, 0.31),
	"iron": Color(0.19, 0.19, 0.23),
	# Cloth: awnings, banners, the inn sign.
	"cloth_red": Color(0.66, 0.17, 0.14),
	"cloth_blue": Color(0.21, 0.33, 0.55),
	"cloth_cream": Color(0.91, 0.82, 0.62),
	# Nature: saturated greens with one warm autumn accent.
	"trunk": Color(0.31, 0.21, 0.12),
	"trunk_birch": Color(0.83, 0.79, 0.70),
	"leaf_deep": Color(0.12, 0.31, 0.13),
	"leaf_mid": Color(0.19, 0.43, 0.16),
	"leaf_bright": Color(0.33, 0.55, 0.19),
	"leaf_autumn": Color(0.80, 0.47, 0.12),
	"pine": Color(0.09, 0.27, 0.17),
	"grass": Color(0.28, 0.46, 0.17),
	"grass_blade": Color(0.80, 0.88, 0.62),
	"rock": Color(0.48, 0.45, 0.40),
	"rock_wet": Color(0.32, 0.33, 0.34),
	# Ground: packed earth roads, worn cobbles, deep pond water.
	"dirt": Color(0.58, 0.43, 0.25),
	"cobble": Color(0.59, 0.55, 0.48),
	# Visual polish 15 — paved sheets. The cobble sheet is tinted with the warm
	# stone family; the road sheet is white because its colour comes entirely
	# from vertex colours (dirt core, gravel verge, meadow edge), exactly like
	# the painted terrain it replaces.
	"paving_cobble": Color(0.70, 0.66, 0.58),
	"paving_road": Color(1.0, 1.0, 1.0),
	"water": Color(0.15, 0.33, 0.40),
	# Emissive parts: dark albedo by day, lit by `apply_night_glow()` at night.
	"window": Color(0.15, 0.18, 0.26),
	"lantern": Color(0.32, 0.28, 0.22),
}

## Emissive colour of windows and lanterns, modulated by the night glow.
const GLOW_COLOR := Color(1.0, 0.72, 0.38)
## How strongly windows glow when it is fully dark.
const GLOW_MAX_ENERGY := 2.6

## Materials whose emission follows the simulated night. Written once a frame.
const GLOW_KEYS := ["window", "lantern"]

var _cache := {}


## Returns the shared material for a palette key. Never creates two materials
## for the same key, which is what keeps the draw call count low.
func get_material(key: String) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key] as StandardMaterial3D
	var material := _make_material(key)
	_cache[key] = material
	return material


## A copy of a palette colour, so callers can vary a prop without touching the
## shared material (used for MultiMesh instance colours and vertex colours).
func get_color(key: String) -> Color:
	return PALETTE.get(key, Color.MAGENTA)


func has_color(key: String) -> bool:
	return PALETTE.has(key)


## Number of distinct materials created so far. Used by the diagnostics log and
## by `tests/unit/test_village_materials.gd` to keep the palette honest.
func get_material_count() -> int:
	return _cache.size()


## 0.0 in full daylight, 1.0 in full darkness. Cheap: two property writes.
func apply_night_glow(night: float) -> void:
	var amount := clampf(night, 0.0, 1.0)
	for key in GLOW_KEYS:
		if not _cache.has(key):
			continue
		var material := _cache[key] as StandardMaterial3D
		material.emission_energy_multiplier = GLOW_MAX_ENERGY * amount


# --- internals ---------------------------------------------------------------


func _make_material(key: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = PALETTE.get(key, Color.MAGENTA)
	material.metallic = 0.0
	# A restrained roughness range keeps broad stylised surfaces matte, while
	# giving worn wood, slate and iron a controlled highlight under the sun.
	material.roughness = 0.9
	match key:
		"wall_cream", "wall_ochre", "wall_ash", "wall_pale":
			material.roughness = 0.95
		"timber", "timber_warm", "plank":
			material.roughness = 0.84
		"door":
			material.roughness = 0.8
		"roof_tile", "roof_shingle":
			material.roughness = 0.86
		"roof_slate":
			material.roughness = 0.78
		"roof_moss":
			material.roughness = 0.94
		"cloth_red", "cloth_blue", "cloth_cream":
			material.roughness = 0.96
	# `MeshBaker` merges many solids into one mesh and keeps them apart with
	# vertex colours, so every material has to read them as albedo.
	material.vertex_color_use_as_albedo = true
	match key:
		"iron":
			# Aged wrought iron: metallic, but dark and broad rather than chrome.
			material.metallic = 0.38
			material.roughness = 0.62
		"water":
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color = Color(PALETTE["water"], 0.82)
			material.roughness = 0.34
			material.metallic = 0.0
			material.emission_enabled = true
			material.emission = PALETTE["water"].lightened(0.12)
			material.emission_energy_multiplier = 0.12
		"window", "lantern":
			material.emission_enabled = true
			material.emission = GLOW_COLOR
			material.emission_energy_multiplier = 0.0
			material.roughness = 0.62 if key == "window" else 0.72
		"stone", "stone_dark", "cobble", "rock":
			material.roughness = 0.94
		"paving_cobble":
			# The procedural cobble pattern: an almost-grey tiling albedo carries
			# the courses and joints, the palette colour carries the warm stone,
			# and a normal map gives the bevels real relief under the sun.
			material.albedo_texture = PavingTextures.cobble_albedo()
			material.normal_enabled = true
			material.normal_texture = PavingTextures.cobble_normal()
			material.normal_scale = 0.9
			material.roughness = 0.93
			# A paving sheet is flat ground seen from one side. Turning off
			# culling makes the surface independent of quad winding — one less
			# way for a whole square to vanish because a ring was authored
			# clockwise instead of counter-clockwise.
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material.texture_filter = (
				BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			)
		"paving_road":
			material.albedo_texture = PavingTextures.road_albedo()
			material.normal_enabled = true
			material.normal_texture = PavingTextures.road_normal()
			material.normal_scale = 0.55
			material.roughness = 0.96
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material.texture_filter = (
				BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			)
		"rock_wet":
			material.roughness = 0.72
		"leaf_deep", "leaf_mid", "leaf_bright", "leaf_autumn", "pine", "grass":
			material.roughness = 0.94
		"grass_blade", "trunk", "trunk_birch", "dirt":
			material.roughness = 0.92
	return material
