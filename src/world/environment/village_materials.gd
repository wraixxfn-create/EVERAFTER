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
## The materials are deliberately plain: no textures to download, no external
## assets, no shaders. Variety comes from geometry, silhouette and vertex
## colours, which is what a stylised look needs and what keeps the repository
## text only.
##
## `apply_night_glow()` is called once per frame by `SkyRig` with the daylight
## factor. It writes two properties on two shared materials, so the whole
## village lights up at dusk without any per-node work.

const PALETTE := {
	# Walls: plaster over wattle and daub, three tones so houses differ.
	"wall_cream": Color(0.86, 0.80, 0.68),
	"wall_ochre": Color(0.76, 0.65, 0.49),
	"wall_ash": Color(0.68, 0.67, 0.66),
	"wall_pale": Color(0.80, 0.79, 0.72),
	# Timber frame, doors, planks, handles.
	"timber": Color(0.30, 0.21, 0.15),
	"timber_warm": Color(0.41, 0.29, 0.19),
	"plank": Color(0.52, 0.38, 0.25),
	"door": Color(0.26, 0.18, 0.13),
	# Roofs: tiles, shingles, slate.
	"roof_tile": Color(0.62, 0.32, 0.24),
	"roof_shingle": Color(0.44, 0.30, 0.25),
	"roof_slate": Color(0.36, 0.38, 0.42),
	"roof_moss": Color(0.40, 0.42, 0.28),
	# Masonry and metal.
	"stone": Color(0.58, 0.57, 0.54),
	"stone_dark": Color(0.41, 0.40, 0.39),
	"iron": Color(0.22, 0.22, 0.25),
	# Cloth: awnings, banners, the inn sign.
	"cloth_red": Color(0.62, 0.22, 0.22),
	"cloth_blue": Color(0.27, 0.35, 0.52),
	"cloth_cream": Color(0.84, 0.79, 0.66),
	# Nature.
	"trunk": Color(0.33, 0.24, 0.17),
	"trunk_birch": Color(0.76, 0.74, 0.68),
	"leaf_deep": Color(0.16, 0.34, 0.19),
	"leaf_mid": Color(0.23, 0.44, 0.22),
	"leaf_bright": Color(0.34, 0.53, 0.24),
	"leaf_autumn": Color(0.62, 0.48, 0.20),
	"pine": Color(0.14, 0.30, 0.22),
	"grass": Color(0.30, 0.47, 0.24),
	"grass_blade": Color(0.85, 0.90, 0.70),
	"rock": Color(0.47, 0.46, 0.44),
	"rock_wet": Color(0.34, 0.35, 0.36),
	# Ground.
	"dirt": Color(0.55, 0.44, 0.31),
	"cobble": Color(0.60, 0.58, 0.54),
	"water": Color(0.20, 0.36, 0.44),
	# Emissive parts: dark albedo by day, lit by `apply_night_glow()` at night.
	"window": Color(0.16, 0.19, 0.26),
	"lantern": Color(0.30, 0.28, 0.24),
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
	material.roughness = 0.88
	# `MeshBaker` merges many solids into one mesh and keeps them apart with
	# vertex colours, so every material has to read them as albedo.
	material.vertex_color_use_as_albedo = true
	match key:
		"iron":
			material.metallic = 0.75
			material.roughness = 0.42
		"water":
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color = Color(PALETTE["water"], 0.82)
			material.roughness = 0.12
			material.metallic = 0.1
			material.emission_enabled = true
			material.emission = PALETTE["water"].lightened(0.15)
			material.emission_energy_multiplier = 0.25
		"window", "lantern":
			material.emission_enabled = true
			material.emission = GLOW_COLOR
			material.emission_energy_multiplier = 0.0
			material.roughness = 0.55
		"stone", "stone_dark", "cobble", "rock", "rock_wet":
			material.roughness = 0.95
		"leaf_deep", "leaf_mid", "leaf_bright", "leaf_autumn", "pine", "grass":
			material.roughness = 0.92
	return material
