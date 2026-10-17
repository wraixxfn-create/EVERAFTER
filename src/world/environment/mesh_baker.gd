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
	material_key: String, size: Vector3, xform: Transform3D = Transform3D.IDENTITY,
	tint: Color = Color.WHITE, face_variation: float = 0.0
) -> void:
	var half := size * 0.5
	for face in BOX_FACES:
		var normal: Vector3 = face["normal"]
		var u: Vector3 = face["u"]
		var v: Vector3 = face["v"]
		var hu := _half_extent_along(u, half)
		var hv := _half_extent_along(v, half)
		var a := -u * hu - v * hv
		var b := u * hu - v * hv
		var c := u * hu + v * hv
		var d := -u * hu + v * hv
		_add_quad(
			material_key, xform, a, b, c, d, normal,
			_face_tint(tint, normal, face_variation)
		)
	_triangle_count += 12


## Truncated cone. `top_radius == 0` gives a pyramid or a spike, and the
## matching cap is skipped so no degenerate triangles are emitted. Each cap is
## emitted once after the side facets, avoiding coincident duplicate surfaces.
func add_cylinder(
	material_key: String, top_radius: float, bottom_radius: float, height: float,
	segments: int, xform: Transform3D = Transform3D.IDENTITY, tint: Color = Color.WHITE,
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
		var flat_normal := Vector3(
			cos((angle_0 + angle_1) * 0.5), 0.0, sin((angle_0 + angle_1) * 0.5)
		)
		var segment_tint := _segment_tint(tint, index, sides, face_variation)
		_add_quad(
			material_key, xform, bottom_0, bottom_1, top_1, top_0, flat_normal,
			segment_tint
		)
		_triangle_count += 2
	if top_radius > 0.0001:
		_add_cap(material_key, xform, top_radius, half_height, step, sides, 1.0, tint)
	if bottom_radius > 0.0001:
		_add_cap(material_key, xform, bottom_radius, -half_height, step, sides, -1.0, tint)


## Triangular prism with its ridge along Z: the gable end of a roof.
## `width` is the base, `height` the rise, `depth` the length of the ridge.
func add_prism(
	material_key: String, width: float, height: float, depth: float,
	xform: Transform3D = Transform3D.IDENTITY, tint: Color = Color.WHITE
) -> void:
	var half_width := width * 0.5
	var half_height := height * 0.5
	var half_depth := depth * 0.5
	var base_left := Vector3(-half_width, -half_height, 0.0)
	var base_right := Vector3(half_width, -half_height, 0.0)
	var apex := Vector3(0.0, half_height, 0.0)
	# Gable ends. The winding that yields +Z is (base_left, apex, base_right).
	var front := Vector3(0.0, 0.0, half_depth)
	var back := Vector3(0.0, 0.0, -half_depth)
	_add_triangle(
		material_key, xform, base_left + front, apex + front, base_right + front,
		Vector3(0, 0, 1), tint
	)
	_add_triangle(
		material_key, xform, base_left + back, base_right + back, apex + back,
		Vector3(0, 0, -1), tint
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
	# Two end triangles plus two slope quads.
	_triangle_count += 6


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
