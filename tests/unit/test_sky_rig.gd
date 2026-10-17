class_name TestSkyRig
extends RefCounted
## Checks for `SkyRig`: the tuning contract of the lighting rig.
##
## These tests cannot see pixels, but they pin the values that decide whether
## the image reads as a lit day or as mud: energies stay inside the tonemapper's
## usable band, the night palette never crushes to black, the fog stays a light
## haze, and the golden-hour / moon curves behave at every sun elevation.


static func run_tests(harness: TestHarness) -> void:
	harness.suite("SkyRig")

	# --- key light ------------------------------------------------------------
	harness.check(
		SkyRig.SUN_ENERGY_NIGHT > 0.0 and SkyRig.SUN_ENERGY_NIGHT < 0.3,
		"the moon light is dim, but never off (night must stay readable)"
	)
	harness.check(
		SkyRig.SUN_ENERGY_DAY > 1.0 and SkyRig.SUN_ENERGY_DAY < 2.0,
		"the day sun is strong, but under the filmic knee (no blown-out plaster)"
	)
	harness.check(
		SkyRig.SUN_ENERGY_DAY > SkyRig.SUN_ENERGY_NIGHT,
		"day is brighter than night"
	)
	harness.check(
		SkyRig.SUN_COLOR_NOON.r > SkyRig.SUN_COLOR_NOON.b,
		"the noon sun is warm, never clinical white"
	)
	harness.check(
		SkyRig.SUN_COLOR_GOLDEN.r > SkyRig.SUN_COLOR_GOLDEN.g
		and SkyRig.SUN_COLOR_GOLDEN.g > SkyRig.SUN_COLOR_GOLDEN.b,
		"the golden sun is a warm gradient, not a fluorescent spike"
	)
	harness.check(
		SkyRig.SUN_COLOR_MOON.b > SkyRig.SUN_COLOR_MOON.r,
		"the moon light is cool (night reads blue, not grey)"
	)

	# --- fill light ------------------------------------------------------------
	harness.check(
		SkyRig.FILL_ENERGY_NIGHT > SkyRig.FILL_ENERGY_DAY,
		"the fill works hardest at night, so shadows never go pitch black"
	)
	harness.check(
		SkyRig.FILL_ENERGY_DAY > 0.0 and SkyRig.FILL_ENERGY_DAY < 0.5,
		"the day fill only tints the shade, it does not flatten the sun"
	)
	harness.check(
		SkyRig.FILL_ELEVATION_DEG > 25.0 and SkyRig.FILL_ELEVATION_DEG < 80.0,
		"the fill comes from up high (sky bounce, not a second sun)"
	)

	# --- ambient floor ---------------------------------------------------------
	harness.check(
		SkyRig.AMBIENT_ENERGY_NIGHT > 0.3,
		"the night ambient floor keeps silhouettes visible"
	)
	harness.check(
		SkyRig.AMBIENT_ENERGY_DAY < SkyRig.AMBIENT_ENERGY_NIGHT * 2.0,
		"day ambient stays moderate, or shadows lose their depth"
	)

	# --- night palette never black ---------------------------------------------
	for color in [
		SkyRig.SKY_TOP_NIGHT, SkyRig.SKY_HORIZON_NIGHT, SkyRig.GROUND_NIGHT
	]:
		harness.check(
			_luminance(color) > 0.02,
			"night colour %s is above black (no crushed shadows)" % color
		)
	harness.check(
		_luminance(SkyRig.SKY_TOP_DAY) > _luminance(SkyRig.SKY_TOP_NIGHT),
		"the day sky is brighter than the night sky"
	)
	harness.check(
		SkyRig.SKY_HORIZON_GOLDEN.r > SkyRig.SKY_HORIZON_GOLDEN.b,
		"the golden horizon band is warm"
	)

	# --- fog stays a light haze -------------------------------------------------
	for density in [SkyRig.FOG_DENSITY_DAY, SkyRig.FOG_DENSITY_NIGHT]:
		harness.check(
			density > 0.0005 and density < 0.01,
			"fog density %.4f is a light haze, not milk" % density
		)
	harness.check(
		SkyRig.FOG_SUN_SCATTER_MAX > 0.0 and SkyRig.FOG_SUN_SCATTER_MAX <= 0.6,
		"sun scatter in the fog is noticeable but restrained"
	)

	# --- golden hour curve ------------------------------------------------------
	harness.check_almost(
		SkyRig.horizon_glow(SkyRig.HORIZON_GLOW_ELEVATION_DEG), 1.0, 0.001,
		"the warm accent peaks with the sun on the horizon band"
	)
	harness.check_almost(
		SkyRig.horizon_glow(DayCycleSystem.MAX_SUN_ELEVATION_DEG), 0.0, 0.001,
		"there is no sunset tint at noon"
	)
	harness.check_almost(
		SkyRig.horizon_glow(-DayCycleSystem.MAX_SUN_ELEVATION_DEG), 0.0, 0.001,
		"there is no sunset tint at midnight"
	)
	harness.check(
		SkyRig.horizon_glow(0.0) > 0.2,
		"sunset itself is still warm when the sun touches the horizon"
	)
	harness.check(
		SkyRig.horizon_glow(-10.0) > 0.0,
		"the afterglow keeps a tail below the horizon"
	)
	for elevation in range(-70, 71, 5):
		var glow := SkyRig.horizon_glow(float(elevation))
		harness.check(
			glow >= 0.0 and glow <= 1.0,
			"horizon_glow stays in 0..1 at %d degrees" % elevation
		)

	# --- all-day sun warmth ----------------------------------------------------
	harness.check_almost(
		SkyRig.sun_warmth(DayCycleSystem.MAX_SUN_ELEVATION_DEG), 0.0, 0.001,
		"the noon sun is neutral-warm, not golden"
	)
	harness.check(
		SkyRig.sun_warmth(31.0) > 0.05 and SkyRig.sun_warmth(31.0) < 0.5,
		"the morning sun is warmer than noon, without turning orange"
	)
	harness.check(
		SkyRig.sun_warmth(0.0) > 0.9,
		"the sun at the horizon is fully golden"
	)
	for elevation in range(-30, 71, 5):
		var warmth := SkyRig.sun_warmth(float(elevation))
		harness.check(
			warmth >= 0.0 and warmth <= 1.0,
			"sun_warmth stays in 0..1 at %d degrees" % elevation
		)

	# --- moon blend --------------------------------------------------------------
	harness.check_almost(
		SkyRig.moon_weight(0.0), 0.0, 0.001,
		"the light stays on the true sun pose at sunset (no drift on the horizon)"
	)
	harness.check_almost(
		SkyRig.moon_weight(-SkyRig.MOON_BLEND_END_DEG), 1.0, 0.001,
		"the moon pose is fully in place deep in the night"
	)
	harness.check_almost(
		SkyRig.moon_weight(SkyRig.MOON_BLEND_END_DEG), 0.0, 0.001,
		"the moon pose is fully gone in full daylight"
	)
	for elevation in range(-40, 41, 4):
		var weight := SkyRig.moon_weight(float(elevation))
		harness.check(
			weight >= 0.0 and weight <= 1.0,
			"moon_weight stays in 0..1 at %d degrees" % elevation
		)

	# --- coherence with the day cycle ------------------------------------------
	harness.check(
		DayCycleSystem.DAYLIGHT_SATURATION_ELEVATION_DEG
		<= DayCycleSystem.MAX_SUN_ELEVATION_DEG,
		"the daylight curve can reach 1.0 under this sun path"
	)
	harness.check(
		DayCycleSystem.DAYLIGHT_SATURATION_ELEVATION_DEG >= 15.0,
		"the light keeps evolving through the morning and the afternoon"
	)


static func _luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
