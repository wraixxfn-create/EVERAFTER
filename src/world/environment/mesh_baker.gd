class_name MeshBaker
extends RefCounted
## Accumulates primitive solids and commits them as **one mesh per material**.
##
## Why this exists (and why props are not just a pile of `MeshInstance3D`):
## a stylised village built from boxes and cylinders can easily reach a thousand
## nodes, and a thousand draw calls is exactly what turns 60 fps into 25 fps on
## a GTX 1060 class GPU. Baking merges every solid that shares a material into a
## single `ArrayMesh`, so a house costs five draw calls instead of fifteen and
## the whole forest costs a handful.
##
## Colour variety survives the merge through **vertex colours**: one shared
## material with `vertex_color_use_as_albedo` multiplied by a per solid tint.
## That is what lets thirty roofs be four different reds without four materials.
##
## Winding order matters and is easy to get wrong — it decides which side of a
## triangle is the front face, and back face culling hides the other one. Godot
## was measured (4.7.2, see `tests/unit/test_mesh_baker.gd`) to derive the
## normal of a triangle `(a, b, c)` as `(c - a) x (b - a)`, so this baker emits
## corners clockwise when seen from outside and *also* writes explicit normals,
## so lighting is correct even if a caller transforms a solid oddly.

## One face of an axis aligned box: outward normal plus the two in-plane axes
## used to lay out its corners. `u x v == -normal` is what makes the emitted
## winding produce `+normal` under Godot's rule.
const BOX_FACES := [
	{"normal": Vector3(0, 1, 0), "u": Vector3(1, 0, 0), "v": Vector3(0, 0, 1)},
	{"normal": Vector3(0, -1, 0), "u": Vector3(1, 0, 0), "v": Vector3(0, 0, -1)},
	{"normal": Vector3(1, 0, 0), "u": Vector3(0, 0, 1), "v": Vector3(0, 1, 0)},
	{"normal": Vector3(-1, 0, 0), "u": Vector3(0, 0, 1), "v": Vector3(0, -1, 0)},
	{"normal": Vector3(0, 0, 1), "u": Vector3(-1, 0, 0), "v": Vector3(0, 1, 0)},
	{"normal": Vector3(0, 0, -1), "u": Vector3(1, 0, 0), "v": Vector3(0, 1, 0)},
]

var _surfaces := {}
var _triangle_count := 0


# --- solids ------------------------------------------------------------------


## Axis aligned box of [param size], placed by [param xform].
func add_box(
	material_key: String,
	size: Vector3,
	xform: Transform3D = Transform3D.IDENTITY,
	tint: Color = Color.WHITE,
	face_variation: float = 0.0
) -> void:
	var half := size * 0.5
	for face in BOX_FACES:
		var normal: Vector3 = face["normal"]
		var u: Vector3 = face["u"]
		var v: Vector3 = face["v"]
		var hu := _half_extent_along(u, half)
		var hv := _half_extent_along(v, half)
		# Faces must lie on the box boundary, not on the three centre planes.
		# Without this offset every beam/wall is a hollow cross of intersecting
		# sheets, producing missing corners and false seams at every joint.
		var center := normal * _half_extent_along(normal, half)
		var a := center - u * hu - v * hv
		var b := center + u * hu - v * hv
		var c := center + u * hu + v * hv
		var d := center - u * hu + v * hv
		_add_quad(material_key, xform, a, b, c, d, normal, _face_tint(tint, normal, face_variation))
	_triangle_count += 12


## Truncated cone. `top_radius == 0` gives a pyramid or a spike, and the
## matching cap is skipped so no degenerate triangles are emitted. Each cap is
## emitted once after the side facets, avoiding coincident duplicate surfaces.
func add_cylinder(
	material_key: String,
	top_radius: float,
	bottom_radius: float,
	height: float,
	segments: int,
	xform: Transform3D = Transform3D.IDENTITY,
	tint: Color = Color.WHITE,
	face_variation: float = 0.0
) -> void:
	var sides := maxi(segments, 3)
	var half_height := height * 0.5
	var step := TAU / float(sides)
	for index in sides:
		var angle_0 := step * float(index)
		var angle_1 := step * float(index + 1)
		var bottom_0 := _rim(bottom_radius, angle_0, -half_height)
		var bottom_1 := _rim(bottom_radius, angle_1, -half_height)
		var top_0 := _rim(top_radius, angle_0, half_height)
		var top_1 := _rim(top_radius, angle_1, half_height)
		var flat_normal := (top_1 - bottom_0).cross(bottom_1 - bottom_0).normalized()
		var segment_tint := _segment_tint(tint, index, sides, face_variation)
		if top_radius <= 0.0001:
			_add_triangle(material_key, xform, bottom_0, bottom_1, top_0, flat_normal, segment_tint)
			_triangle_count += 1
		elif bottom_radius <= 0.0001:
			flat_normal = (top_0 - bottom_0).cross(top_1 - bottom_0).normalized()
			_add_triangle(material_key, xform, bottom_0, top_1, top_0, flat_normal, segment_tint)
			_triangle_count += 1
		else:
			_add_quad(
				material_key, xform, bottom_0, bottom_1, top_1, top_0, flat_normal, segment_tint
			)
			_triangle_count += 2
	if top_radius > 0.0001:
		_add_cap(material_key, xform, top_radius, half_height, step, sides, 1.0, tint)
	if bottom_radius > 0.0001:
		_add_cap(material_key, xform, bottom_radius, -half_height, step, sides, -1.0, tint)


## Triangular prism with its ridge along Z: the gable end of a roof.
## `width` is the base, `height` the rise, `depth` the length of the ridge.
##
## A roof may give the end gables a separate material and narrower width. This
## lets the plaster/stone gable sit beneath the projecting verge instead of
## making the entire end of a house look like solid roof tile.
func add_prism(
	material_key: String, width: float, height: float, depth: float,
	xform: Transform3D = Transform3D.IDENTITY, tint: Color = Color.WHITE,
	gable_material_key: String = "", gable_width: float = 0.0,
	gable_tint: Color = Color.WHITE
) -> void:
	var half_width := width * 0.5
	var half_height := height * 0.5
	var half_depth := depth * 0.5
	var base_left := Vector3(-half_width, -half_height, 0.0)
	var base_right := Vector3(half_width, -half_height, 0.0)
	var apex := Vector3(0.0, half_height, 0.0)
	# Gable ends. A narrower facade leaves a slim roof-coloured verge on either
	# side, just as the roof overhang does in the silhouette.
	var front := Vector3(0.0, 0.0, half_depth)
	var back := Vector3(0.0, 0.0, -half_depth)
	var end_key := material_key if gable_material_key.is_empty() else gable_material_key
	var end_tint := tint if gable_material_key.is_empty() else gable_tint
	var split_gable := not gable_material_key.is_empty() and gable_width > 0.0
	var gable_half_width := half_width
	if split_gable:
		gable_half_width = minf(gable_width * 0.5, half_width)
		split_gable = gable_half_width < half_width - 0.0001
	if split_gable:
		var gable_left := Vector3(-gable_half_width, -half_height, 0.0)
		var gable_right := Vector3(gable_half_width, -half_height, 0.0)
		# Front: left verge, plaster/stone gable, right verge.
		_add_triangle(
			material_key, xform, base_left + front, apex + front, gable_left + front,
			Vector3(0, 0, 1), tint
		)
		_add_triangle(
			end_key, xform, gable_left + front, apex + front, gable_right + front,
			Vector3(0, 0, 1), gable_tint
		)
		_add_triangle(
			material_key, xform, gable_right + front, apex + front, base_right + front,
			Vector3(0, 0, 1), tint
		)
		# Back: reverse each winding so the faces point away from the building.
		_add_triangle(
			material_key, xform, base_left + back, gable_left + back, apex + back,
			Vector3(0, 0, -1), tint
		)
		_add_triangle(
			end_key, xform, gable_left + back, gable_right + back, apex + back,
			Vector3(0, 0, -1), gable_tint
		)
		_add_triangle(
			material_key, xform, gable_right + back, base_right + back, apex + back,
			Vector3(0, 0, -1), tint
		)
	else:
		_add_triangle(
			end_key, xform, base_left + front, apex + front, base_right + front,
			Vector3(0, 0, 1), end_tint
		)
		_add_triangle(
			end_key, xform, base_left + back, base_right + back, apex + back,
			Vector3(0, 0, -1), end_tint
		)
	# The two slopes. For an outward normal `n` the in-plane axis that satisfies
	# Godot's winding rule with `v = +Z` is `u = (n.y, -n.x, 0)`.
	var slope_length := Vector2(half_width, height).length()
	for side in [-1.0, 1.0]:
		var normal := Vector3(-height * side, half_width, 0.0).normalized()
		var along := Vector3(normal.y, -normal.x, 0.0)
		var base := base_right if normal.x > 0.0 else base_left
		var center := base.lerp(apex, 0.5)
		var half_slope := along * (slope_length * 0.5)
		_add_quad(
			material_key, xform, center - half_slope + back, center + half_slope + back,
			center + half_slope + front, center - half_slope + front, normal, tint
		)
	# Two gable faces plus two slope quads (or six triangles when the gable is
	# inset and leaves a material-matched verge at both ends).
	_triangle_count += 10 if split_gable else 6


## Closed extrusion of a simple XY profile along Z. Used for architectural
## sections (chamfered slabs, gables, corbels), not surface decoration.
## Profiles may be concave; cap triangulation and side winding are derived from
## the polygon, so mirrored roof halves keep outward normals and closed ends.
func add_profile(
	material_key: String,
	profile: PackedVector2Array,
	depth: float,
	xform: Transform3D = Transform3D.IDENTITY,
	tint: Color = Color.WHITE
) -> void:
	assert(profile.size() >= 3 and depth > 0.0)
	var points := profile
	if Geometry2D.is_polygon_clockwise(points):
		points.reverse()
	var indices := Geometry2D.triangulate_polygon(points)
	assert(not indices.is_empty(), "Architectural profile must be a simple polygon")
	for index in range(0, indices.size(), 3):
		var a := Vector3(points[indices[index]].x, points[indices[index]].y, depth * 0.5)
		var b := Vector3(points[indices[index + 1]].x, points[indices[index + 1]].y, depth * 0.5)
		var c := Vector3(points[indices[index + 2]].x, points[indices[index + 2]].y, depth * 0.5)
		if (c - a).cross(b - a).z < 0.0:
			var swap := b
			b = c
			c = swap
		_add_triangle(material_key, xform, a, b, c, Vector3.BACK, tint)
		_add_triangle(
			material_key,
			xform,
			Vector3(a.x, a.y, -a.z),
			Vector3(c.x, c.y, -c.z),
			Vector3(b.x, b.y, -b.z),
			Vector3.FORWARD,
			tint
		)
		_triangle_count += 2
	for index in points.size():
		var start := points[index]
		var end := points[(index + 1) % points.size()]
		var normal := Vector3(end.y - start.y, start.x - end.x, 0.0).normalized()
		_add_quad(
			material_key,
			xform,
			Vector3(start.x, start.y, -depth * 0.5),
			Vector3(start.x, start.y, depth * 0.5),
			Vector3(end.x, end.y, depth * 0.5),
			Vector3(end.x, end.y, -depth * 0.5),
			normal,
			tint
		)
		_triangle_count += 2


## UV sphere. `rings` is the number of latitude bands, `segments` the number of
## longitude slices. Low values (4 x 6) make stylised forms; default smooth
## normals suit foliage, while `flat_shading` preserves faceted rock planes.
##
## The winding was derived from the same measured rule as everything else here:
## the pole fans and the body quads are emitted so that `(c - a) x (b - a)`
## points outwards.
func add_sphere(
	material_key: String, radius: float, rings: int, segments: int,
	xform: Transform3D = Transform3D.IDENTITY, tint: Color = Color.WHITE,
	flat_shading: bool = false
) -> void:
	var band_count := maxi(rings, 2)
	var slice_count := maxi(segments, 3)
	var surface := _surface(material_key)
	var normal_basis := xform.basis.inverse().transposed()
	for slice in slice_count:
		var angle_0 := TAU * float(slice) / float(slice_count)
		var angle_1 := TAU * float(slice + 1) / float(slice_count)
		var first_ring := _ring_point(radius, angle_0, 1, band_count)
		var second_ring := _ring_point(radius, angle_1, 1, band_count)
		_add_sphere_triangle(
			surface, xform, normal_basis, Vector3(0.0, radius, 0.0), first_ring,
			second_ring, tint, flat_shading
		)
		_triangle_count += 1
		var last := band_count - 1
		var first_last := _ring_point(radius, angle_0, last, band_count)
		var second_last := _ring_point(radius, angle_1, last, band_count)
		_add_sphere_triangle(
			surface, xform, normal_basis, Vector3(0.0, -radius, 0.0), second_last,
			first_last, tint, flat_shading
		)
		_triangle_count += 1
	for band in range(1, band_count - 1):
		for slice in slice_count:
			var angle_0 := TAU * float(slice) / float(slice_count)
			var angle_1 := TAU * float(slice + 1) / float(slice_count)
			var p00 := _ring_point(radius, angle_0, band, band_count)
			var p10 := _ring_point(radius, angle_1, band, band_count)
			var p11 := _ring_point(radius, angle_1, band + 1, band_count)
			var p01 := _ring_point(radius, angle_0, band + 1, band_count)
			_add_sphere_triangle(
				surface, xform, normal_basis, p00, p11, p10, tint, flat_shading
			)
			_add_sphere_triangle(
				surface, xform, normal_basis, p00, p01, p11, tint, flat_shading
			)
			_triangle_count += 2


## Bent, tapered tube through a polyline of points and radii.
##
## Trees are the reason this exists: a trunk is not a cylinder, it is a curve
## that flares at the roots and narrows into the crown, and a branch is the same
## shape rotated. Each ring is built on a **parallel transported** frame, so a
## limb can bend sharply without the facets twisting or pinching halfway up.
## `radii` may end at zero, which emits a point instead of a cap.
func add_limb(
	material_key: String,
	points: PackedVector3Array,
	radii: PackedFloat32Array,
	sides: int = 6,
	xform: Transform3D = Transform3D.IDENTITY,
	tint: Color = Color.WHITE,
	face_variation: float = 0.0
) -> void:
	var count := mini(points.size(), radii.size())
	if count < 2:
		return
	var ring := maxi(sides, 3)
	var step := TAU / float(ring)
	var tangents := PackedVector3Array()
	for index in count:
		var tangent: Vector3
		if index == 0:
			tangent = points[1] - points[0]
		elif index == count - 1:
			tangent = points[count - 1] - points[count - 2]
		else:
			tangent = points[index + 1] - points[index - 1]
		if tangent.length_squared() < 0.000001:
			tangent = Vector3.UP
		tangents.append(tangent.normalized())
	# Carry one perpendicular axis from ring to ring. Recomputing it from a
	# global up vector would flip the cross-section when a branch turns vertical.
	var first := tangents[0]
	var helper := Vector3.UP if absf(first.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var carried := (helper - first * helper.dot(first)).normalized()
	var ring_points: Array[PackedVector3Array] = []
	for index in count:
		var axis := tangents[index]
		carried = carried - axis * carried.dot(axis)
		if carried.length_squared() < 0.000001:
			helper = Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
			carried = (helper - axis * helper.dot(axis)).normalized()
		carried = carried.normalized()
		var side_axis := carried.cross(axis).normalized()
		var points_on_ring := PackedVector3Array()
		for step_index in ring:
			var angle := step * float(step_index)
			points_on_ring.append(
				points[index]
				+ (carried * cos(angle) + side_axis * sin(angle)) * radii[index]
			)
		ring_points.append(points_on_ring)
	for index in count - 1:
		var lower := ring_points[index]
		var upper := ring_points[index + 1]
		for step_index in ring:
			var next := (step_index + 1) % ring
			var a := lower[step_index]
			var b := lower[next]
			var c := upper[next]
			var d := upper[step_index]
			var local_normal := (c - a).cross(b - a)
			if local_normal.length_squared() < 0.000001:
				continue
			_add_quad(
				material_key, xform, a, b, c, d, local_normal.normalized(),
				_segment_tint(tint, step_index, ring, face_variation)
			)
			_triangle_count += 2
	if radii[count - 1] > 0.0001:
		_add_limb_cap(material_key, xform, ring_points[count - 1], tangents[count - 1], false, tint)
	if radii[0] > 0.0001:
		_add_limb_cap(material_key, xform, ring_points[0], -tangents[0], true, tint)


## Irregular ellipsoidal foliage mass — a crown that is not a sphere.
##
## A canopy made of UV spheres reads as rows of identical lollipops: every angle
## has the same radius, every tree has the same ring. This keeps the cheap
## topology of a sphere but displaces each vertex by a smooth, phase-shifted,
## lobed function of the angle and the latitude, so the silhouette is ragged and
## `seed_value` makes the same seed rebuild the same crown. The wobble is a sum
## of sines of the *wrapped* angle, so opposite slices meet without a crack.
func add_foliage_clump(
	material_key: String,
	radii: Vector3,
	rings: int = 3,
	segments: int = 6,
	seed_value: int = 0,
	xform: Transform3D = Transform3D.IDENTITY,
	tint: Color = Color.WHITE,
	flat_shading: bool = false
) -> void:
	var band_count := maxi(rings, 2)
	var slice_count := maxi(segments, 3)
	var shaped := xform * Transform3D(Basis.IDENTITY.scaled(radii), Vector3.ZERO)
	var normal_basis := shaped.basis.inverse().transposed()
	var surface := _surface(material_key)
	var apex := Vector3.UP
	var nadir := Vector3.DOWN
	for slice in slice_count:
		var angle_0 := TAU * float(slice) / float(slice_count)
		var angle_1 := TAU * float(slice + 1) / float(slice_count)
		var top_0 := _clump_point(angle_0, 1, band_count, seed_value)
		var top_1 := _clump_point(angle_1, 1, band_count, seed_value)
		_add_sphere_triangle(surface, shaped, normal_basis, apex, top_0, top_1, tint, flat_shading)
		_triangle_count += 1
		var last := band_count - 1
		var bottom_0 := _clump_point(angle_0, last, band_count, seed_value)
		var bottom_1 := _clump_point(angle_1, last, band_count, seed_value)
		_add_sphere_triangle(
			surface, shaped, normal_basis, nadir, bottom_1, bottom_0, tint, flat_shading
		)
		_triangle_count += 1
	for band in range(1, band_count - 1):
		for slice in slice_count:
			var angle_0 := TAU * float(slice) / float(slice_count)
			var angle_1 := TAU * float(slice + 1) / float(slice_count)
			var p00 := _clump_point(angle_0, band, band_count, seed_value)
			var p10 := _clump_point(angle_1, band, band_count, seed_value)
			var p11 := _clump_point(angle_1, band + 1, band_count, seed_value)
			var p01 := _clump_point(angle_0, band + 1, band_count, seed_value)
			_add_sphere_triangle(
				surface, shaped, normal_basis, p00, p11, p10, tint, flat_shading
			)
			_add_sphere_triangle(
				surface, shaped, normal_basis, p00, p01, p11, tint, flat_shading
			)
			_triangle_count += 2


## Closed, stratified boulder with a broad buried foot, fractured shoulder and
## clipped crown. Unlike the foliage clump this is not a displaced sphere: the
## five independently shaped rings form deliberate stone planes, with bounded
## angular and radial variation. Every seed keeps its vertices ordered around
## the ring, so profiles vary without folds, zero-area faces or self-crossings.
## `size` is the nominal full width / height / depth; the bottom of the mesh
## starts below local y=0 so a placement anchored on the terrain cannot float.
func add_rock(
	material_key: String,
	size: Vector3,
	seed_value: int,
	xform: Transform3D = Transform3D.IDENTITY,
	tint: Color = Color.WHITE,
	face_variation: float = 0.12
) -> void:
	if size.x < 0.02 or size.y < 0.02 or size.z < 0.02:
		return
	var half_width := size.x * 0.5
	var half_depth := size.z * 0.5
	var side_count := 6 + mini(int(floor(_hash_unit(seed_value, 19, 0) * 3.0)), 2)
	var profile := posmod(seed_value, 3)
	var heights := PackedFloat32Array()
	var radii := PackedFloat32Array()
	match profile:
		0:
			# Low, broad shelf with a broken, nearly horizontal crown.
			heights = PackedFloat32Array([-0.26, -0.06, 0.28, 0.63, 0.72])
			radii = PackedFloat32Array([0.68, 0.89, 1.0, 0.82, 0.55])
		1:
			# A taller shoulder that narrows decisively toward its chipped top.
			heights = PackedFloat32Array([-0.25, -0.05, 0.34, 0.72, 0.82])
			radii = PackedFloat32Array([0.69, 0.90, 0.98, 0.68, 0.38])
		_:
			# Low, oblong weathered stone; deliberately distinct from a sphere.
			heights = PackedFloat32Array([-0.24, -0.045, 0.25, 0.61, 0.70])
			radii = PackedFloat32Array([0.77, 0.96, 1.0, 0.76, 0.48])

	var phase_a := _hash_unit(seed_value, 23, 1) * TAU
	var phase_b := _hash_unit(seed_value, 29, 2) * TAU
	var phase_c := _hash_unit(seed_value, 31, 3) * TAU
	var angles := PackedFloat32Array()
	var radial_factors := PackedFloat32Array()
	var angle_step := TAU / float(side_count)
	for side in side_count:
		var base_angle := angle_step * float(side)
		# Bounded jitter is less than one eighth of a sector: adjacent vertices
		# can never exchange order, even at the minimum six-sided profile.
		var angle_jitter := (
			(_hash_unit(seed_value, side + 41, 4) * 2.0 - 1.0) * angle_step * 0.12
		)
		var angle := base_angle + angle_jitter
		var radial := 0.94 + 0.065 * sin(angle * 2.0 + phase_a)
		radial += 0.045 * cos(angle * 3.0 + phase_b)
		angles.append(angle)
		radial_factors.append(clampf(radial, 0.82, 1.12))

	var shift_factors := PackedFloat32Array([0.0, 0.04, 0.20, 0.70, 1.0])
	var rings: Array[PackedVector3Array] = []
	for layer in heights.size():
		var ring := PackedVector3Array()
		var t := float(layer) / float(heights.size() - 1)
		var shift := Vector2(cos(phase_c), sin(phase_c)) * shift_factors[layer]
		for side in side_count:
			var angle: float = angles[side]
			var radial: float = radii[layer] * radial_factors[side]
			var vertical_wobble := 0.0
			if layer > 0 and layer < heights.size() - 1:
				vertical_wobble = sin(angle * 2.0 + phase_b + t) * size.y * 0.018
			var point := Vector3(
				cos(angle) * half_width * radial + shift.x * half_width * 0.12,
				size.y * heights[layer] + vertical_wobble,
				sin(angle) * half_depth * radial + shift.y * half_depth * 0.12
			)
			ring.append(point)
		rings.append(ring)

	var variation := clampf(face_variation, 0.0, 0.22)
	for layer in range(rings.size() - 1):
		var lower := rings[layer]
		var upper := rings[layer + 1]
		for side in side_count:
			var next := (side + 1) % side_count
			var a := lower[side]
			var b := lower[next]
			var c := upper[next]
			var d := upper[side]
			# Godot's measured winding uses (c-a) x (b-a). Calculate a
			# separate normal for each triangle so the chipped planes stay flat.
			var normal_a := (c - a).cross(b - a)
			var normal_b := (d - a).cross(c - a)
			if normal_a.length_squared() < 0.000000000001 or normal_b.length_squared() < 0.000000000001:
				continue
			var band_tint := _scaled_tint(tint, 0.94 + float(layer) * 0.025)
			var facet_tint := _segment_tint(band_tint, side + layer, side_count, variation)
			_add_triangle(material_key, xform, a, b, c, normal_a.normalized(), facet_tint)
			_add_triangle(material_key, xform, a, c, d, normal_b.normalized(), facet_tint)
			_triangle_count += 2

	# Closed fan caps. The basal cap sits below the anchor and is normally
	# swallowed by the ground; the clipped top catches a broad, readable facet.
	var bottom_center := Vector3(0.0, size.y * heights[0], 0.0)
	var top_center := Vector3(
		cos(phase_c) * half_width * 0.12,
		size.y * heights[heights.size() - 1],
		sin(phase_c) * half_depth * 0.12
	)
	var bottom := rings[0]
	var top := rings[rings.size() - 1]
	for side in side_count:
		var next := (side + 1) % side_count
		var bottom_a := bottom[side]
		var bottom_b := bottom[next]
		var bottom_normal := (bottom_a - bottom_center).cross(bottom_b - bottom_center)
		var top_a := top[side]
		var top_b := top[next]
		var top_normal := (top_b - top_center).cross(top_a - top_center)
		if bottom_normal.length_squared() >= 0.000000000001:
			_add_triangle(
				material_key, xform, bottom_center, bottom_b, bottom_a,
				bottom_normal.normalized(), _scaled_tint(tint, 0.88)
			)
			_triangle_count += 1
		if top_normal.length_squared() >= 0.000001:
			_add_triangle(
				material_key, xform, top_center, top_a, top_b,
				top_normal.normalized(), _scaled_tint(tint, 1.04)
			)
			_triangle_count += 1


## One tapered blade of grass or one flower stem: a quad in the local XY plane
## whose tip is bent in X/Z. The written normal points **up** on purpose. A blade
## is a sliver of a surface, not a wall; giving it a sideways normal makes half of
## every tuft go black from the wrong side, while a meadow-lit normal keeps the
## whole tuft the colour the terrain under it says it should be. The grass
## material therefore has back face culling disabled (see `VillageMaterials`).
func add_blade(
	material_key: String,
	height: float,
	base_width: float,
	tip_width: float,
	bend: Vector2 = Vector2.ZERO,
	xform: Transform3D = Transform3D.IDENTITY,
	tint: Color = Color.WHITE,
	root_shade: float = 0.22,
	double_sided: bool = false
) -> void:
	if height <= 0.0:
		return
	var half_base := maxf(base_width, 0.0) * 0.5
	var half_tip := maxf(tip_width, 0.0) * 0.5
	var a := Vector3(-half_base, 0.0, 0.0)
	var b := Vector3(half_base, 0.0, 0.0)
	var c := Vector3(half_tip + bend.x, height, bend.y)
	var d := Vector3(-half_tip + bend.x, height, bend.y)
	var surface := _surface(material_key)
	var normal := (xform.basis.inverse().transposed() * Vector3.UP).normalized()
	var root_tint := _scaled_tint(tint, 1.0 - clampf(root_shade, 0.0, 0.9))
	var pa := xform * a
	var pb := xform * b
	var pc := xform * c
	var pd := xform * d
	_add_vertex(surface, pa, normal, root_tint)
	_add_vertex(surface, pb, normal, root_tint)
	_add_vertex(surface, pc, normal, tint)
	_add_vertex(surface, pa, normal, root_tint)
	_add_vertex(surface, pc, normal, tint)
	_add_vertex(surface, pd, normal, tint)
	_triangle_count += 2
	if not double_sided:
		return
	# A leaf or a stem hangs on a material that culls back faces, so the same
	# quad is emitted again with the opposite winding. Grass does not need this:
	# its material is double-sided already.
	_add_vertex(surface, pa, normal, root_tint)
	_add_vertex(surface, pd, normal, tint)
	_add_vertex(surface, pc, normal, tint)
	_add_vertex(surface, pa, normal, root_tint)
	_add_vertex(surface, pc, normal, tint)
	_add_vertex(surface, pb, normal, root_tint)
	_triangle_count += 2


## Flat rectangle, useful for signs, blades of grass and water.
func add_quad(
	material_key: String, size: Vector2, xform: Transform3D = Transform3D.IDENTITY,
	tint: Color = Color.WHITE, double_sided: bool = false
) -> void:
	var a := Vector3(-size.x * 0.5, -size.y * 0.5, 0.0)
	var b := Vector3(size.x * 0.5, -size.y * 0.5, 0.0)
	var c := Vector3(size.x * 0.5, size.y * 0.5, 0.0)
	var d := Vector3(-size.x * 0.5, size.y * 0.5, 0.0)
	_add_quad(material_key, xform, a, b, c, d, Vector3(0, 0, 1), tint)
	_triangle_count += 2
	if double_sided:
		_add_quad(material_key, xform, d, c, b, a, Vector3(0, 0, -1), tint)
		_triangle_count += 2


# --- commit ------------------------------------------------------------------


## Builds one `MeshInstance3D` per material actually used. Callers add them to
## the scene tree; nothing here knows about nodes' parents or names.
func commit(materials: VillageMaterials) -> Array:
	var result: Array = []
	for key in _surfaces.keys():
		var surface := _surfaces[key] as SurfaceTool
		var mesh := surface.commit()
		if mesh == null:
			continue
		var instance := MeshInstance3D.new()
		instance.name = "Baked_%s" % key
		instance.mesh = mesh
		instance.material_override = materials.get_material(key)
		result.append(instance)
	return result


func get_material_keys_used() -> PackedStringArray:
	var keys: PackedStringArray = []
	for key in _surfaces.keys():
		keys.append(key)
	keys.sort()
	return keys


func get_triangle_count() -> int:
	return _triangle_count


func is_empty() -> bool:
	return _surfaces.is_empty()


# --- internals ---------------------------------------------------------------


func _surface(material_key: String) -> SurfaceTool:
	if _surfaces.has(material_key):
		return _surfaces[material_key] as SurfaceTool
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_surfaces[material_key] = surface
	return surface


## Emits two triangles `a b c` / `a c d` with an explicit flat normal.
func _add_quad(
	material_key: String, xform: Transform3D, a: Vector3, b: Vector3, c: Vector3,
	d: Vector3, local_normal: Vector3, tint: Color
) -> void:
	var surface := _surface(material_key)
	var normal_basis := xform.basis.inverse().transposed()
	var normal := (normal_basis * local_normal).normalized()
	var pa := xform * a
	var pb := xform * b
	var pc := xform * c
	var pd := xform * d
	_add_vertex(surface, pa, normal, tint)
	_add_vertex(surface, pb, normal, tint)
	_add_vertex(surface, pc, normal, tint)
	_add_vertex(surface, pa, normal, tint)
	_add_vertex(surface, pc, normal, tint)
	_add_vertex(surface, pd, normal, tint)


func _add_cap(
	material_key: String, xform: Transform3D, radius: float, y: float, step: float,
	sides: int, direction: float, tint: Color
) -> void:
	var surface := _surface(material_key)
	var normal_basis := xform.basis.inverse().transposed()
	var normal := (normal_basis * Vector3(0, direction, 0)).normalized()
	var center := xform * Vector3(0.0, y, 0.0)
	for index in sides:
		var first := xform * _rim(radius, step * float(index), y)
		var second := xform * _rim(radius, step * float(index + 1), y)
		# Increasing angle is the winding that produces +Y; reverse it for -Y.
		if direction > 0.0:
			_add_vertex(surface, center, normal, tint)
			_add_vertex(surface, first, normal, tint)
			_add_vertex(surface, second, normal, tint)
		else:
			_add_vertex(surface, center, normal, tint)
			_add_vertex(surface, second, normal, tint)
			_add_vertex(surface, first, normal, tint)
	_triangle_count += sides


## Fan cap for a limb. `flip` reverses the winding for the start of the tube,
## whose outward direction is opposite to the tangent.
func _add_limb_cap(
	material_key: String, xform: Transform3D, ring_points: PackedVector3Array,
	outward: Vector3, flip: bool, tint: Color
) -> void:
	if ring_points.is_empty():
		return
	var surface := _surface(material_key)
	var normal := (xform.basis.inverse().transposed() * outward).normalized()
	var center := Vector3.ZERO
	for point in ring_points:
		center += point
	center /= float(ring_points.size())
	var center_world := xform * center
	for index in ring_points.size():
		var first := xform * ring_points[index]
		var second := xform * ring_points[(index + 1) % ring_points.size()]
		_add_vertex(surface, center_world, normal, tint)
		if flip:
			_add_vertex(surface, second, normal, tint)
			_add_vertex(surface, first, normal, tint)
		else:
			_add_vertex(surface, first, normal, tint)
			_add_vertex(surface, second, normal, tint)
	_triangle_count += ring_points.size()


## Unit-sphere point with the clump wobble applied. Poles are exact, so the cap
## fan closes without a hole and without a spike.
func _clump_point(angle: float, band: int, band_count: int, seed_value: int) -> Vector3:
	if band <= 0:
		return Vector3.UP
	if band >= band_count:
		return Vector3.DOWN
	var polar := PI * float(band) / float(band_count)
	var t := float(band) / float(band_count)
	var radial := 1.0 + _clump_wobble(angle, t, seed_value)
	return Vector3(sin(polar) * cos(angle), cos(polar), sin(polar) * sin(angle)) * radial


## Smooth low-frequency deformation of a foliage clump. Integer lobe counts make
## the function periodic in the angle, so slice 0 and slice N close seamlessly.
func _clump_wobble(angle: float, t: float, seed_value: int) -> float:
	var phase_a := _hash_unit(seed_value, 1, 0) * TAU
	var phase_b := _hash_unit(seed_value, 2, 0) * TAU
	var phase_c := _hash_unit(seed_value, 3, 0) * TAU
	var lobes_a := 3.0 + floorf(_hash_unit(seed_value, 4, 0) * 3.0)
	var lobes_b := 6.0 + floorf(_hash_unit(seed_value, 5, 0) * 4.0)
	var taper := sin(clampf(t, 0.0, 1.0) * PI)
	var wobble := 0.085 * sin(angle * lobes_a + phase_a + t * 1.7)
	wobble += 0.050 * sin(angle * lobes_b - phase_b + t * 3.4)
	wobble += 0.045 * sin(t * 4.2 + phase_c)
	return wobble * (0.30 + 0.70 * taper)


## Deterministic 0..1 hash on three integers, used to derive stable phases for
## foliage shapes without depending on the caller's RNG stream.
func _hash_unit(a: int, b: int, c: int) -> float:
	var h: int = (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


func _add_sphere_triangle(
	surface: SurfaceTool, xform: Transform3D, normal_basis: Basis, a: Vector3, b: Vector3,
	c: Vector3, tint: Color, flat_shading: bool = false
) -> void:
	var point_a := xform * a
	var point_b := xform * b
	var point_c := xform * c
	if flat_shading:
		# Match Godot's measured winding convention used by the baker tests.
		var flat_normal := (point_c - point_a).cross(point_b - point_a).normalized()
		_add_vertex(surface, point_a, flat_normal, tint)
		_add_vertex(surface, point_b, flat_normal, tint)
		_add_vertex(surface, point_c, flat_normal, tint)
		return
	_add_vertex(surface, point_a, _sphere_normal(normal_basis, a), tint)
	_add_vertex(surface, point_b, _sphere_normal(normal_basis, b), tint)
	_add_vertex(surface, point_c, _sphere_normal(normal_basis, c), tint)


func _face_tint(tint: Color, normal: Vector3, amount: float) -> Color:
	if amount <= 0.0:
		return tint
	# Subtle orientation-based albedo shifts give the edges of stone and timber
	# blocks a tactile read without introducing another material or texture.
	var factor := 1.0 + (normal.y * 0.42 + normal.z * 0.22 - normal.x * 0.12) * amount
	return _scaled_tint(tint, factor)


func _segment_tint(tint: Color, index: int, count: int, amount: float) -> Color:
	if amount <= 0.0:
		return tint
	# A bounded sinusoid is used only on low-poly stave-like cylinders, not as
	# a repeating world texture.
	var phase := TAU * float(index) / float(maxi(count, 1))
	var factor := 1.0 + sin(phase * 2.0 + 0.7) * amount
	return _scaled_tint(tint, factor)


func _scaled_tint(tint: Color, factor: float) -> Color:
	return Color(
		clampf(tint.r * factor, 0.0, 1.0),
		clampf(tint.g * factor, 0.0, 1.0),
		clampf(tint.b * factor, 0.0, 1.0),
		tint.a
	)


func _sphere_normal(normal_basis: Basis, local_point: Vector3) -> Vector3:
	return (normal_basis * local_point.normalized()).normalized()


func _ring_point(radius: float, angle: float, band: int, band_count: int) -> Vector3:
	var polar := PI * float(band) / float(band_count)
	return Vector3(
		sin(polar) * cos(angle) * radius, cos(polar) * radius, sin(polar) * sin(angle) * radius
	)


func _add_triangle(
	material_key: String, xform: Transform3D, a: Vector3, b: Vector3, c: Vector3,
	local_normal: Vector3, tint: Color
) -> void:
	var surface := _surface(material_key)
	var normal := (xform.basis.inverse().transposed() * local_normal).normalized()
	_add_vertex(surface, xform * a, normal, tint)
	_add_vertex(surface, xform * b, normal, tint)
	_add_vertex(surface, xform * c, normal, tint)


func _add_vertex(surface: SurfaceTool, position: Vector3, normal: Vector3, tint: Color) -> void:
	surface.set_normal(normal)
	surface.set_color(tint)
	surface.add_vertex(position)


func _rim(radius: float, angle: float, y: float) -> Vector3:
	return Vector3(cos(angle) * radius, y, sin(angle) * radius)


func _half_extent_along(axis: Vector3, half: Vector3) -> float:
	return absf(axis.x) * half.x + absf(axis.y) * half.y + absf(axis.z) * half.z
