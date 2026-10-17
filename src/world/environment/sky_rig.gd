class_name SkyRig
extends Node
## SkyRig — turns the simulated hour into light.
##
## Separated from `MainWorld` on purpose: `MainWorld` is the composition root
## (it builds the terrain and the village), while this node owns one thing only,
## the mapping `DayCycleSystem -> sun, sky, fog, ambient, night glow`. Keeping
## the two apart is what lets the palette be tuned without touching world
## assembly, and it is the hook a future weather system will plug into.
##
## The light narrative is one fantasy medieval day:
## * a warm key light (`Sun`) arcs east -> south -> west, golden and low at the
##   flanks of the day, neutral-warm at noon;
## * after dusk the same light eases to a fixed cool moon pose, so nothing ever
##   lights the world from below the horizon;
## * a shadowless cool `Fill` from the anti-solar side keeps shaded faces
##   readable (key/fill contrast, never black shadows);
## * ambient is a sky-biased mix: cool from above, warm bounce in the shadows;
## * exponential fog + gentle valley haze + aerial perspective tie the ground
##   to the sky, and a soft sun scatter warms the haze at golden hour.
##
## Cost discipline, because the target is a GTX 1060 class GPU:
## * **one** shadow casting light (`Sun`). A second shadow map is the single
##   most expensive thing that could be added here, so it is not added.
## * one shadowless `Fill` light: a whole extra directional light without a
##   shadow map is nearly free and it is what keeps night and dawn readable
##   instead of black. It is marked `SKY_MODE_LIGHT_ONLY` in the scene so this
##   cheat light never shows up as a second sun in the sky.
## * the sky is a `ProceduralSkyMaterial` recoloured in place. No new
##   resources are allocated per frame: the same material object is mutated.
## * the atmosphere is the cheap fog path (exponential + height + aerial
##   perspective + sun scatter). Volumetric fog stays **off**: it is the
##   first effect that would not fit the GPU budget.
## * `apply_night_glow()` writes two floats on two shared materials, so every
##   window and lantern in the village lights up at dusk for free.
##
## Every constant below is a tuned value, not a default: see `docs/LIGHTING.md`
## for the reasoning and for how the day arc reads at each hour.

# --- sky palette -------------------------------------------------------------
# Night values sit just above pure black on purpose: crushed blacks hide silhouettes.
const SKY_TOP_NIGHT := Color(0.045, 0.055, 0.125)
const SKY_TOP_DAY := Color(0.15, 0.34, 0.66)
const SKY_HORIZON_NIGHT := Color(0.09, 0.10, 0.19)
const SKY_HORIZON_DAY := Color(0.86, 0.79, 0.66)
## Horizon band at sunrise/sunset: the warm accent of the whole day.
const SKY_HORIZON_GOLDEN := Color(0.99, 0.62, 0.36)
const GROUND_NIGHT := Color(0.045, 0.05, 0.075)
## Ground hemisphere close to the terrain's own value family, so the sky dome
## under the horizon never reads as a different planet than the map.
const GROUND_DAY := Color(0.24, 0.23, 0.18)

# --- sun (key light) ---------------------------------------------------------
## Neutral-warm at noon. Never pure white: white key light looks clinical.
const SUN_COLOR_NOON := Color(1.0, 0.95, 0.87)
## Golden hour. Kept below fluorescent saturation (no neon oranges).
const SUN_COLOR_GOLDEN := Color(1.0, 0.60, 0.30)
## The same light after dusk: a cool moon, so night reads as blue, not grey.
const SUN_COLOR_MOON := Color(0.58, 0.68, 0.95)
## Day energy is set so lit plaster (~0.88 albedo) stays under the filmic
## shoulder: bright, but not blown out to flat white.
const SUN_ENERGY_DAY := 1.35
## Moon energy: visible silhouettes and cool shapes, far from daylight.
const SUN_ENERGY_NIGHT := 0.11

# --- fill (shadowless bounce) ------------------------------------------------
const FILL_COLOR_DAY := Color(0.58, 0.70, 0.90)
const FILL_COLOR_NIGHT := Color(0.30, 0.38, 0.62)
## Fill is stronger at night than by day: during the day the sun dominates and
## the fill only tints the shade; at night it is half of the light there is.
const FILL_ENERGY_DAY := 0.20
const FILL_ENERGY_NIGHT := 0.36
## Fill sits high on the anti-solar side: shade is lifted, forms stay legible.
const FILL_ELEVATION_DEG := 52.0

# --- ambient -----------------------------------------------------------------
## `ambient_light_sky_contribution` (scene) mixes the sky IBL with a warm
## bounce colour; this only scales the mix over the day. The night value is
## deliberately not tiny, because night sky radiance is already dim.
const AMBIENT_ENERGY_DAY := 0.72
const AMBIENT_ENERGY_NIGHT := 0.55

# --- fog ---------------------------------------------------------------------
## Light haze: enough to layer the hills, never enough to milk the village.
const FOG_DENSITY_DAY := 0.0028
const FOG_DENSITY_NIGHT := 0.0042
## Peak of `fog_sun_scatter`: the sun burning through the haze at golden hour.
const FOG_SUN_SCATTER_MAX := 0.42

# --- sun/moon continuity -----------------------------------------------------
## Fixed moon pose: a calm night sky instead of a second racing sun arc.
const MOON_POSE_ELEVATION_DEG := 54.0
const MOON_POSE_AZIMUTH_DEG := 250.0
## Below these sun elevations the key light eases from the true sun pose to the
## moon pose. The blend starts only a few degrees under the horizon (afterglow)
## and completes quickly, so the light never keeps shining from below the
## ground once the sun is down.
const MOON_BLEND_BEGIN_DEG := 3.0
const MOON_BLEND_END_DEG := 14.0

# --- golden hour curve -------------------------------------------------------
## Sun elevation (degrees) where the warm horizon accent is at its peak.
const HORIZON_GLOW_ELEVATION_DEG := 6.0
## How far the accent reaches: by +28 degrees (mid-morning) it is gone, and it
## fades to nothing ~16 degrees below the horizon (short afterglow).
const HORIZON_GLOW_SPAN_DEG := 22.0

# --- sun disc (procedural sky) ----------------------------------------------
## A tight disc at night (the moon), a wide soft halo at golden hour.
const SUN_DISC_ANGLE_MIN_DEG := 4.0
const SUN_DISC_ANGLE_SPAN_DEG := 30.0

## Set by `MainWorld` right after the village is built. Optional: without it the
## rig simply does not drive the window and lantern glow.
var village_materials: VillageMaterials = null

@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _sun: DirectionalLight3D = $Sun
@onready var _fill: DirectionalLight3D = $Fill


func _process(_delta: float) -> void:
	var day_cycle := Game.get_day_cycle()
	if day_cycle == null:
		return
	var daylight := day_cycle.get_daylight_factor()
	var glow := horizon_glow(day_cycle.sun_elevation_deg)
	# Afterglow: the sky keeps some of the day's colour for a while after the
	# sun is down. Keyed on `glow`, not `daylight`, so dusk has a tail.
	var sky_light := clampf(maxf(daylight, glow * 0.8), 0.0, 1.0)
	var ambient_light := clampf(maxf(daylight, glow * 0.35), 0.0, 1.0)
	_apply_sun(day_cycle, daylight, glow)
	_apply_fill(day_cycle, daylight)
	_apply_sky(day_cycle, sky_light, ambient_light, glow)
	if village_materials != null:
		village_materials.apply_night_glow(1.0 - daylight)


# --- pure curves (static so they can be unit tested without a scene) ---------


## 0.0 at noon and deep in the night, 1.0 with the sun on the horizon band.
## This is the "golden hour" accent: it drives sky warmth, fog scatter and the
## sun colour. Because it is keyed on elevation (not on daylight), sunrise,
## sunset and a short afterglow all read warm.
static func horizon_glow(sun_elevation_deg: float) -> float:
	return clampf(
		1.0 - absf(sun_elevation_deg - HORIZON_GLOW_ELEVATION_DEG) / HORIZON_GLOW_SPAN_DEG,
		0.0,
		1.0
	)


## 0.0 at the zenith, 1.0 at the horizon: sunlight is warm at low angles all
## day long, not only inside the golden band, so the morning never reads as a
## copy of noon. Squared to keep the shift subtle until the sun is low.
static func sun_warmth(sun_elevation_deg: float) -> float:
	var t := clampf(1.0 - sun_elevation_deg / 52.0, 0.0, 1.0)
	return t * t


## 0.0 while the sun is up (or still glowing on the horizon), 1.0 once the
## night is established. Drives the eased rotation from sun pose to moon pose.
static func moon_weight(sun_elevation_deg: float) -> float:
	return smoothstep(MOON_BLEND_BEGIN_DEG, MOON_BLEND_END_DEG, -sun_elevation_deg)


# --- internals ---------------------------------------------------------------


func _apply_sun(day_cycle: DayCycleSystem, daylight: float, glow: float) -> void:
	if _sun == null:
		return
	var weight := moon_weight(day_cycle.sun_elevation_deg)
	var sun_pose := _pose_basis(day_cycle.sun_azimuth_deg, day_cycle.sun_elevation_deg)
	var moon_pose := _pose_basis(MOON_POSE_AZIMUTH_DEG, MOON_POSE_ELEVATION_DEG)
	_sun.transform = Transform3D(sun_pose.slerp(moon_pose, weight), Vector3.ZERO)
	# The low sun is warm all day (not only in the golden band): mornings and
	# afternoons get their own colour, noon stays neutral-warm.
	var warmth := maxf(glow, sun_warmth(day_cycle.sun_elevation_deg))
	var warm := SUN_COLOR_NOON.lerp(SUN_COLOR_GOLDEN, warmth)
	_sun.light_color = warm.lerp(SUN_COLOR_MOON, weight)
	_sun.light_energy = lerpf(SUN_ENERGY_NIGHT, SUN_ENERGY_DAY, daylight)


func _apply_fill(day_cycle: DayCycleSystem, daylight: float) -> void:
	if _fill == null:
		return
	# Anti-solar azimuth: the shade side always receives the fill, so buildings
	# keep their form against the sun instead of turning into flat cutouts.
	var azimuth := fposmod(day_cycle.sun_azimuth_deg + 180.0, 360.0)
	_fill.transform = Transform3D(_pose_basis(azimuth, FILL_ELEVATION_DEG), Vector3.ZERO)
	_fill.light_energy = lerpf(FILL_ENERGY_NIGHT, FILL_ENERGY_DAY, daylight)
	_fill.light_color = FILL_COLOR_NIGHT.lerp(FILL_COLOR_DAY, daylight)


func _apply_sky(
	day_cycle: DayCycleSystem,
	sky_light: float,
	ambient_light: float,
	glow: float
) -> void:
	if _world_environment == null or _world_environment.environment == null:
		return
	var environment := _world_environment.environment
	environment.ambient_light_energy = lerpf(
		AMBIENT_ENERGY_NIGHT, AMBIENT_ENERGY_DAY, ambient_light
	)
	environment.fog_density = lerpf(FOG_DENSITY_NIGHT, FOG_DENSITY_DAY, sky_light)
	# Scatter only while the sun is at or above the horizon: fog lit from below
	# looks like a glitch, not like weather.
	var scatter := FOG_SUN_SCATTER_MAX * glow * smoothstep(-6.0, 2.0, day_cycle.sun_elevation_deg)
	environment.fog_sun_scatter = scatter
	if environment.sky == null:
		return
	var sky_material := environment.sky.sky_material as ProceduralSkyMaterial
	if sky_material == null:
		return
	var horizon := SKY_HORIZON_DAY.lerp(SKY_HORIZON_GOLDEN, glow)
	sky_material.sky_top_color = SKY_TOP_NIGHT.lerp(SKY_TOP_DAY, sky_light)
	sky_material.sky_horizon_color = SKY_HORIZON_NIGHT.lerp(horizon, sky_light)
	# The ground hemisphere matches the horizon band: no seam where the hills
	# meet the sky dome.
	sky_material.ground_horizon_color = SKY_HORIZON_NIGHT.lerp(horizon, sky_light)
	sky_material.ground_bottom_color = GROUND_NIGHT.lerp(GROUND_DAY, sky_light)
	environment.fog_light_color = SKY_HORIZON_NIGHT.lerp(horizon, sky_light)
	# A wider, warmer sun disc near the horizon: the cheapest sunset there is.
	# At night this is a small, pale moon disc for the same low price.
	sky_material.sun_angle_max = SUN_DISC_ANGLE_MIN_DEG + SUN_DISC_ANGLE_SPAN_DEG * glow


## The light shines along -Z, so a positive elevation has to pitch it down.
static func _pose_basis(azimuth_deg: float, elevation_deg: float) -> Basis:
	var basis := Basis()
	basis = basis.rotated(Vector3.UP, deg_to_rad(azimuth_deg))
	basis = basis.rotated(basis.x, deg_to_rad(-elevation_deg))
	return basis.orthonormalized()
