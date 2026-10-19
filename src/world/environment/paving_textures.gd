class_name PavingTextures
extends RefCounted
## Procedural, deterministic surface textures for the paved ground.
##
## Visual polish 15 adds two paved sheet materials: a cobbled square and the
## compacted-earth carriageway that runs out of it. Modelling every cobble as a
## solid would cost tens of thousands of triangles for detail only visible under
## the player's feet; instead the module bakes **one tiling albedo and one normal
## map per surface**, generated in code at startup. Nobody has to download an
## image, the repository stays text-only, and the paving sheet keeps a coarse,
## terrain-following grid with a UV that repeats every few metres.
##
## Why the albedo textures are almost grey
## * `VillageMaterials` supplies the actual warm stone tint as the material
##   colour and the mesh supplies vertex colours. The texture only carries the
##   *stone pattern* (courses, joints, bevelled edges, grain, wear). That keeps
##   the paving in the same palette and colour space as every other material,
##   instead of introducing a second, incompatible look.
##
## Everything is generated once, cached statically, and depends only on integer
## hashes: the same build produces the same stones on every machine.

## Metres covered by one repeat of the cobble texture.
const COBBLE_METRES := 3.2
const COBBLE_SIZE := 384
## The road texture is finer in absolute terms but repeats over a longer span;
## the terrain paint still supplies the broad dirt/clay variation underneath.
const ROAD_METRES := 4.0
const ROAD_SIZE := 256

static var _cobble_albedo: ImageTexture = null
static var _cobble_normal: ImageTexture = null
static var _road_albedo: ImageTexture = null
static var _road_normal: ImageTexture = null


## Tiling cobble pattern: irregular courses of rounded, jointed stones.
static func cobble_albedo() -> ImageTexture:
	if _cobble_albedo == null:
		var generated := _build_cobble()
		_cobble_albedo = generated["albedo"]
		_cobble_normal = generated["normal"]
	return _cobble_albedo


static func cobble_normal() -> ImageTexture:
	if _cobble_normal == null:
		cobble_albedo()
	return _cobble_normal


## Tiling compacted-earth pattern: pale grit, scattered pebbles, faint drag
## marks. The colour comes from the mesh's vertex colours, so this texture is
## deliberately neutral.
static func road_albedo() -> ImageTexture:
	if _road_albedo == null:
		var generated := _build_road()
		_road_albedo = generated["albedo"]
		_road_normal = generated["normal"]
	return _road_albedo


static func road_normal() -> ImageTexture:
	if _road_normal == null:
		road_albedo()
	return _road_normal


# --- cobbles -----------------------------------------------------------------


## One pass builds the colour image and the height field used for the normal
## map, so a stone's bevel and its shading can never disagree.
static func _build_cobble() -> Dictionary:
	var size := COBBLE_SIZE
	var pixels := PackedByteArray()
	pixels.resize(size * size * 3)
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	var rng := RandomNumberGenerator.new()
	rng.seed = 15015
	# Mortar first: joints are packed earth, not black gaps.
	var joint_color := Color(0.46, 0.42, 0.36)
	for y in size:
		for x in size:
			var grain := 0.94 + _hash01(x, y, 17) * 0.12
			_write_pixel(pixels, size, x, y, joint_color * grain)
			heights[y * size + x] = 0.16 + _hash01(x, y, 29) * 0.05
	# Course heights are random but sum exactly to the texture height, so the
	# tile wraps without a visible seam.
	var rows := _split_span(rng, size, 34, 52)
	var y0 := 0
	var row_index := 0
	for row_height: int in rows:
		var widths := _split_span(rng, size, 42, 62)
		var bond := 0.0
		if row_index % 2 == 1:
			bond = float(widths[0]) * 0.5
		var stone_x := bond
		for width: int in widths:
			_paint_stone(
				pixels, heights, size, stone_x, y0, width, row_height, row_index,
				widths.size()
			)
			stone_x += float(width)
		y0 += row_height
		row_index += 1
	return {
		"albedo": _image_texture(pixels, size),
		"normal": _normal_texture(heights, size, 1.7),
	}


## Draws one stone with a bevelled, slightly domed crown and a per-stone tint.
## Wrapping is explicit: a stone that crosses the right edge is drawn twice, so
## the running bond survives tiling.
static func _paint_stone(
	pixels: PackedByteArray, heights: PackedFloat32Array, size: int,
	start_x: float, start_y: int, width: int, height: int, row: int, row_stones: int
) -> void:
	var bevel := 3 + int(_hash01(width, height + row, 41) * 3.0)
	# A restrained warm family: the material colour stays the same stone the
	# buildings are built from, the stones only differ in brightness.
	var warmth := _hash01(row, int(start_x), 53) - 0.5
	var base := Color(0.98 + warmth * 0.10, 0.96 + warmth * 0.04, 0.92 - warmth * 0.05)
	base = base * (0.88 + _hash01(int(start_x), row, 67) * 0.20)
	var gravel_roll := _hash01(row * 7 + width, row_stones, 71)
	var chip_x := int(_hash01(int(start_x), row, 79) * float(width))
	var chip_y := int(_hash01(height, int(start_x), 83) * float(height))
	# One pixel of mortar on every side: at 120 px/m that is an 8 mm joint,
	# enough to read as packed earth without turning the stone into a tile.
	for offset in range(1, width - 1):
		var x := posmod(int(start_x) + offset, size)
		for local_y in range(1, height - 1):
			var y := posmod(start_y + local_y, size)
			var dx: int = mini(offset, width - 1 - offset)
			var dy: int = mini(local_y, height - 1 - local_y)
			var edge: int = mini(dx, dy)
			if edge >= bevel:
				continue
			var t := float(edge) / float(maxi(bevel, 1))
			var shade := lerpf(0.62, 1.0, t)
			# A chip in the arris of a few stones: a small dark notch, only once
			# per texture tile, so the wear reads as stone rather than noise.
			var chipped := (
				gravel_roll < 0.10
				and absi(offset - chip_x) < 3
				and absi(local_y - chip_y) < 3
			)
			if chipped:
				shade *= 0.72
			var grain := 0.95 + _hash01(x, y, 89) * 0.10
			_write_pixel(pixels, size, x, y, base * shade * grain)
			heights[y * size + x] = lerpf(0.20, 0.92, t) + _hash01(x, y, 97) * 0.05
	# A little moss and dirt in the joint just below the stone: the square is
	# old, not freshly laid.
	for offset in width:
		if _hash01(offset, row * 13 + width, 101) > 0.22:
			continue
		var x := posmod(int(start_x) + offset, size)
		var y := posmod(start_y + height, size)
		var existing := _read_pixel(pixels, size, x, y)
		_write_pixel(pixels, size, x, y, existing.lerp(Color(0.40, 0.44, 0.33), 0.35))


# --- compacted road ----------------------------------------------------------


static func _build_road() -> Dictionary:
	var size := ROAD_SIZE
	var pixels := PackedByteArray()
	pixels.resize(size * size * 3)
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	for y in size:
		for x in size:
			var grain := 0.86 + _hash01(x, y, 131) * 0.20
			# Broad drag/wear bands along the direction of travel, plus the
			# tooth of loose grit. The two wheel ruts are baked at the V that
			# `GroundSurfaces` maps across the 3.6 m carriageway, so they follow
			# every bend of the curve without extra geometry.
			# Drag marks run *along* the road, so they vary with U (image x) and
			# stay continuous across V.
			var drag := 1.0 + sin(float(x) / float(size) * TAU * 6.0) * 0.025
			var across := float(y) / float(size)
			var rut := exp(-pow((across - 0.347) / 0.055, 2.0))
			rut += exp(-pow((across - 0.653) / 0.055, 2.0))
			grain *= 1.0 - rut * 0.10
			var grit := _hash01(x / 2, y / 2, 137)
			if grit > 0.965:
				grain += 0.20
			elif grit < 0.035:
				grain -= 0.14
			_write_pixel(
				pixels, size, x, y, Color(0.96, 0.94, 0.90) * grain * drag
			)
			heights[y * size + x] = 0.45 + grain * 0.18 + grit * 0.25 - rut * 0.14
	# A handful of embedded pebbles. Big enough to read underfoot, small enough
	# that the texture still tiles into a road rather than a riverbed.
	var rng := RandomNumberGenerator.new()
	rng.seed = 15016
	for index in 26:
		var cx := rng.randi_range(0, size - 1)
		var cy := rng.randi_range(0, size - 1)
		var radius := rng.randf_range(1.4, 3.2)
		var tint := 0.82 + rng.randf() * 0.20
		for oy in range(-int(radius) - 1, int(radius) + 2):
			for ox in range(-int(radius) - 1, int(radius) + 2):
				var distance := sqrt(float(ox * ox + oy * oy))
				if distance > radius:
					continue
				var x := posmod(cx + ox, size)
				var y := posmod(cy + oy, size)
				var edge := clampf(1.0 - distance / radius, 0.0, 1.0)
				var shade := lerpf(0.72, 1.0, edge) * tint
				_write_pixel(pixels, size, x, y, Color(0.94, 0.91, 0.86) * shade)
				heights[y * size + x] = 0.55 + edge * 0.35
	return {
		"albedo": _image_texture(pixels, size),
		"normal": _normal_texture(heights, size, 0.75),
	}


# --- helpers -----------------------------------------------------------------


## Splits [param total] pixels into deterministic random chunks within
## [param minimum, param maximum], with the last chunk absorbing the remainder
## so the sum is exact (this is what makes the texture tile).
static func _split_span(rng: RandomNumberGenerator, total: int, minimum: int,
		maximum: int) -> PackedInt32Array:
	var chunks := PackedInt32Array()
	var remaining := total
	while remaining > maximum:
		var chunk := rng.randi_range(minimum, maximum)
		chunks.append(chunk)
		remaining -= chunk
	if remaining < minimum and not chunks.is_empty():
		# Give the short tail to the previous chunk instead of emitting a
		# sliver that would read as a seam.
		chunks[chunks.size() - 1] += remaining
	else:
		chunks.append(remaining)
	return chunks


static func _write_pixel(
	pixels: PackedByteArray, size: int, x: int, y: int, color: Color
) -> void:
	var index := (y * size + x) * 3
	pixels[index] = int(clampf(color.r, 0.0, 1.0) * 255.0)
	pixels[index + 1] = int(clampf(color.g, 0.0, 1.0) * 255.0)
	pixels[index + 2] = int(clampf(color.b, 0.0, 1.0) * 255.0)


static func _read_pixel(pixels: PackedByteArray, size: int, x: int, y: int) -> Color:
	var index := (y * size + x) * 3
	return Color(
		float(pixels[index]) / 255.0,
		float(pixels[index + 1]) / 255.0,
		float(pixels[index + 2]) / 255.0
	)


static func _image_texture(pixels: PackedByteArray, size: int) -> ImageTexture:
	var image := Image.create_from_data(size, size, false, Image.FORMAT_RGB8, pixels)
	# Mipmaps matter more than the base resolution here: the square is seen from
	# 20 m away far more often than from 2 m, and without them the cobble joints
	# turn into a shimmering moiré on every distant road.
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## Sobel-style normal map from the same height field the colour pass wrote.
## Half resolution is plenty for a 0.4 m stone bevel and quarters the boot cost.
static func _normal_texture(
	heights: PackedFloat32Array, size: int, strength: float
) -> ImageTexture:
	var half := maxi(size / 2, 2)
	var pixels := PackedByteArray()
	pixels.resize(half * half * 3)
	for y in half:
		for x in half:
			var sx := x * 2
			var sy := y * 2
			var left := heights[sy * size + posmod(sx - 2, size)]
			var right := heights[sy * size + posmod(sx + 2, size)]
			var down := heights[posmod(sy - 2, size) * size + sx]
			var up := heights[posmod(sy + 2, size) * size + sx]
			var normal := Vector3(
				-(right - left) * strength, -(up - down) * strength, 1.0
			).normalized()
			var index := (y * half + x) * 3
			pixels[index] = int((normal.x * 0.5 + 0.5) * 255.0)
			pixels[index + 1] = int((normal.y * 0.5 + 0.5) * 255.0)
			pixels[index + 2] = int((normal.z * 0.5 + 0.5) * 255.0)
	return _image_texture(pixels, half)


## Deterministic byte hash in [0, 1]. No RNG state, no time, no GPU: the same
## pixel always receives the same stone grain on every machine.
static func _hash01(x: int, y: int, seed_value: int) -> float:
	var value := x * 374761393 + y * 668265263 + seed_value * 2147483647
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return float(value & 0xFFFF) / 65535.0
