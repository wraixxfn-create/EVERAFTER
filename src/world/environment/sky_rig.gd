extends Node
## SkyRig — turns the simulated hour into light.
##
## Separated from `MainWorld` on purpose: `MainWorld` is the composition root
## (it builds the terrain and the village), while this node owns one thing only,
## the mapping `DayCycleSystem -> sun, sky, fog, ambient, night glow`. Keeping
## the two apart is what lets the palette be tuned without touching world
## assembly, and it is the hook a future weather system will plug into.
##
## Cost discipline, because the target is a GTX 1060 class GPU:
## * **one** shadow casting light (`Sun`). A second shadow map is the single
##   most expensive thing that could be added here, so it is not added.
## * one shadowless `Fill` light: a whole extra directional light without a
##   shadow map is nearly free and it is what keeps night and dawn readable
##   instead of black.
## * the sky is a `ProceduralSkyMaterial` recoloured in place. No new
##   resources are allocated per frame: the same material object is mutated.
## * `apply_night_glow()` writes two floats on two shared materials, so every
##   window and lantern in the village lights up at dusk for free.

const SKY_TOP_NIGHT := Color(0.03, 0.04, 0.10)
const SKY_TOP_DAY := Color(0.18, 0.40, 0.72)
const SKY_HORIZON_NIGHT := Color(0.08, 0.09, 0.16)
const SKY_HORIZON_DAY := Color(0.92, 0.83, 0.68)
const GROUND_NIGHT := Color(0.04, 0.05, 0.07)
const GROUND_DAY := Color(0.30, 0.27, 0.21)

const SUN_COLOR_HIGH := Color(1.00, 0.94, 0.84)
const SUN_COLOR_LOW := Color(1.00, 0.52, 0.22)
const SUN_ENERGY_DAY := 1.50
const SUN_ENERGY_NIGHT := 0.05
const FILL_COLOR_DAY := Color(0.52, 0.66, 0.92)
const FILL_COLOR_NIGHT := Color(0.26, 0.34, 0.58)
const FILL_ENERGY_DAY := 0.22
const FILL_ENERGY_NIGHT := 0.30
const AMBIENT_ENERGY_DAY := 0.90
const AMBIENT_ENERGY_NIGHT := 0.28
const FOG_DENSITY_NIGHT := 0.0058
const FOG_DENSITY_DAY := 0.0032

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
	var glow := _horizon_glow(daylight)
	_apply_sun(day_cycle, daylight, glow)
	_apply_fill(daylight)
	_apply_sky(daylight, glow)
	if village_materials != null:
		village_materials.apply_night_glow(1.0 - daylight)


# --- internals ---------------------------------------------------------------


func _apply_sun(day_cycle: DayCycleSystem, daylight: float, glow: float) -> void:
	if _sun == null:
		return
	_sun.transform = Transform3D(_sun_basis(day_cycle), Vector3.ZERO)
	_sun.light_energy = lerpf(SUN_ENERGY_NIGHT, SUN_ENERGY_DAY, daylight)
	_sun.light_color = SUN_COLOR_HIGH.lerp(SUN_COLOR_LOW, glow)


func _apply_fill(daylight: float) -> void:
	if _fill == null:
		return
	_fill.light_energy = lerpf(FILL_ENERGY_NIGHT, FILL_ENERGY_DAY, daylight)
	_fill.light_color = FILL_COLOR_NIGHT.lerp(FILL_COLOR_DAY, daylight)


func _apply_sky(daylight: float, glow: float) -> void:
	if _world_environment == null or _world_environment.environment == null:
		return
	var environment := _world_environment.environment
	environment.ambient_light_energy = lerpf(AMBIENT_ENERGY_NIGHT, AMBIENT_ENERGY_DAY, daylight)
	environment.fog_density = lerpf(FOG_DENSITY_NIGHT, FOG_DENSITY_DAY, daylight)
	environment.fog_light_color = SKY_HORIZON_NIGHT.lerp(SKY_HORIZON_DAY, daylight)
	if environment.sky == null:
		return
	var sky_material := environment.sky.sky_material as ProceduralSkyMaterial
	if sky_material == null:
		return
	sky_material.sky_top_color = SKY_TOP_NIGHT.lerp(SKY_TOP_DAY, daylight)
	sky_material.sky_horizon_color = SKY_HORIZON_NIGHT.lerp(SKY_HORIZON_DAY, daylight)
	sky_material.ground_horizon_color = SKY_HORIZON_NIGHT.lerp(SKY_HORIZON_DAY, daylight)
	sky_material.ground_bottom_color = GROUND_NIGHT.lerp(GROUND_DAY, daylight)
	# A wider, warmer sun disc near the horizon: the cheapest sunset there is.
	sky_material.sun_angle_max = 7.0 + 26.0 * glow


## The light shines along -Z, so a positive elevation has to pitch it down.
func _sun_basis(day_cycle: DayCycleSystem) -> Basis:
	var basis := Basis()
	basis = basis.rotated(Vector3.UP, deg_to_rad(day_cycle.sun_azimuth_deg))
	basis = basis.rotated(basis.x, deg_to_rad(-day_cycle.sun_elevation_deg))
	return basis.orthonormalized()


## 0.0 when the sun is high or far below the horizon, 1.0 around sunrise/sunset.
func _horizon_glow(daylight: float) -> float:
	return clampf(1.0 - absf(daylight - 0.3) / 0.3, 0.0, 1.0)
