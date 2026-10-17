class_name BuildingSurfaceDetails
extends RefCounted
## Shared, low-cost surface work for the existing building meshes.
##
## This helper only appends solids to an existing [MeshBaker]. It creates no
## nodes, materials, colliders or game state; its random colour shifts use the
## same seeded generator as [BuildingFactory] so rebuilds remain deterministic.

var rng: RandomNumberGenerator = null


func _init(shared_rng: RandomNumberGenerator) -> void:
	rng = shared_rng


func add_foundation_masonry(
	baker: MeshBaker, width: float, depth: float, scale: float
) -> void:
	var outer_width := (width + 0.4) * scale
	var outer_depth := (depth + 0.4) * scale
	var block_height := 0.17 * scale
	var block_depth := 0.1 * scale
	var joint := 0.035 * scale
	var first_course_y := 0.025 * scale + block_height * 0.5
	var course_step := block_height + 0.03 * scale
	for course in 2:
		var y := first_course_y + float(course) * course_step
		var stagger := 0.0 if course % 2 == 0 else 0.5
		for side in [-1.0, 1.0]:
			_add_masonry_row(
				baker, outer_width, block_height, block_depth,
				Vector3(0.0, y, side * (outer_depth * 0.5 - block_depth * 0.5 + 0.02 * scale)),
				true, stagger, joint, scale
			)
			_add_masonry_row(
				baker, outer_depth, block_height, block_depth,
				Vector3(side * (outer_width * 0.5 - block_depth * 0.5 + 0.02 * scale), y, 0.0),
				false, stagger, joint, scale
			)
	# The cap separates plaster from rough stone and protects the joint line.
	baker.add_box(
		"stone", Vector3(width + 0.48, 0.07, depth + 0.48) * scale,
		_transform(Vector3(0.0, 0.405, 0.0) * scale), Color.WHITE, 0.08
	)


func add_masonry_plinth(
	baker: MeshBaker, width: float, depth: float, plinth_height: float
) -> void:
	var outer_width := width + 0.6
	var outer_depth := depth + 0.6
	var block_height := 0.18
	var block_depth := 0.12
	var joint := 0.035
	var first_y := 0.03 + block_height * 0.5
	var course_step := block_height + 0.035
	for course in 2:
		var y := first_y + float(course) * course_step
		var stagger := 0.0 if course % 2 == 0 else 0.5
		for side in [-1.0, 1.0]:
			_add_masonry_row(
				baker, outer_width, block_height, block_depth,
				Vector3(0.0, y, side * (outer_depth * 0.5 - block_depth * 0.5 + 0.02)),
				true, stagger, joint, 1.0
			)
			_add_masonry_row(
				baker, outer_depth, block_height, block_depth,
				Vector3(side * (outer_width * 0.5 - block_depth * 0.5 + 0.02), y, 0.0),
				false, stagger, joint, 1.0
			)
	baker.add_box(
		"stone", Vector3(width + 0.72, 0.08, depth + 0.72),
		_transform(Vector3(0.0, plinth_height - 0.04, 0.0)), Color.WHITE, 0.08
	)


func add_stone_wall_courses(
	baker: MeshBaker, width: float, depth: float, wall_height: float,
	base_y: float, center: Vector3 = Vector3.ZERO
) -> void:
	var course_count := maxi(3, int(ceil(wall_height / 0.65)))
	var course_pitch := wall_height / float(course_count)
	var block_height := course_pitch * 0.86
	var joint := maxf(0.025, course_pitch * 0.045)
	var thickness := 0.06
	for course in course_count:
		var y := base_y + (float(course) + 0.5) * course_pitch
		var stagger := 0.0 if course % 2 == 0 else 0.5
		for side in [-1.0, 1.0]:
			_add_masonry_row(
				baker, width, block_height, thickness,
				Vector3(center.x, y, center.z + side * (depth * 0.5 + thickness * 0.3)),
				true, stagger, joint, 1.0
			)
			_add_masonry_row(
				baker, depth, block_height, thickness,
				Vector3(center.x + side * (width * 0.5 + thickness * 0.3), y, center.z),
				false, stagger, joint, 1.0
			)


func add_roof_details(
	baker: MeshBaker, roof_key: String, roof_tint: Color, roof_width: float,
	roof_depth: float, roof_rise: float, wall_top: float, roof_center: Transform3D,
	scale: float
) -> void:
	var half_width := roof_width * 0.5
	var half_depth := roof_depth * 0.5
	var slope_length := Vector2(half_width, roof_rise).length()
	var pitch_angle := atan2(roof_rise, half_width)
	_add_roof_tiles(
		baker, roof_key, roof_tint, roof_width, roof_depth, roof_rise,
		wall_top, roof_center, scale
	)
	# Eave fascia and paired bargeboards turn the roof edge into carpentry.
	for side in [-1.0, 1.0]:
		var fascia_transform := roof_center * Transform3D(
			Basis.IDENTITY, Vector3(side * half_width, -roof_rise * 0.5, 0.0)
		)
		baker.add_box(
			"timber", Vector3(0.14 * scale, 0.18 * scale, roof_depth),
			fascia_transform, Color.WHITE, 0.06
		)
		for end in [-1.0, 1.0]:
			var barge_basis := Basis.from_euler(
				Vector3(0.0, 0.0, -side * pitch_angle)
			)
			var barge_center := Vector3(0.0, 0.0, end * (half_depth + 0.02 * scale))
			var barge_transform := roof_center * Transform3D(barge_basis, barge_center)
			baker.add_box(
				"timber", Vector3(slope_length + 0.1 * scale, 0.14 * scale, 0.16 * scale),
				barge_transform, Color.WHITE.darkened(0.025), 0.06
			)
	var ridge_transform := roof_center * Transform3D(
		Basis.IDENTITY, Vector3(0.0, roof_rise * 0.5 + 0.03 * scale, 0.0)
	)
	baker.add_box(
		"timber", Vector3(0.18 * scale, 0.14 * scale, roof_depth),
		ridge_transform, Color.WHITE, 0.06
	)


func add_door_details(
	baker: MeshBaker, center_x: float, center_y: float, door_width: float,
	door_height: float, wall_face_z: float, scale: float, add_frame: bool = true
) -> void:
	var width := door_width * scale
	var height := door_height * scale
	var x_center := center_x * scale
	var y_center := center_y * scale
	var wall_z := wall_face_z * scale
	var board_gap := 0.025 * scale
	var board_count := maxi(3, int(ceil(door_width / 0.36)))
	var board_width := (width - board_gap * float(board_count + 1)) / float(board_count)
	var board_front_z := wall_z + 0.09 * scale
	for board in board_count:
		var x := (
			x_center - width * 0.5 + board_gap + board_width * 0.5
			+ float(board) * (board_width + board_gap)
		)
		var board_tint := Color.WHITE.darkened(rng.randf_range(0.0, 0.07))
		baker.add_box(
			"door", Vector3(board_width, height - 0.1 * scale, 0.05 * scale),
			_transform(Vector3(x, y_center, board_front_z)), board_tint, 0.035
		)
	# Cross-battens and forged hinges explain how the door is made and hung.
	for vertical_sign in [-1.0, 1.0]:
		baker.add_box(
			"timber_warm", Vector3(width * 0.82, 0.065 * scale, 0.055 * scale),
			_transform(Vector3(
				x_center, y_center + vertical_sign * height * 0.24,
				wall_z + 0.12 * scale
			)),
			Color.WHITE.darkened(0.04), 0.04
		)
		for hinge_side in [-1.0, 1.0]:
			baker.add_box(
				"iron", Vector3(0.14 * scale, 0.055 * scale, 0.04 * scale),
				_transform(Vector3(
					x_center + hinge_side * (width * 0.5 - 0.03 * scale),
					y_center + vertical_sign * height * 0.31,
					wall_z + 0.15 * scale
				))
			)
	baker.add_sphere(
		"iron", 0.055 * scale, 3, 6,
		_transform(Vector3(x_center + width * 0.34, y_center, wall_z + 0.15 * scale))
	)
	if add_frame:
		for side in [-1.0, 1.0]:
			baker.add_box(
				"timber", Vector3(0.13 * scale, height + 0.12 * scale, 0.17 * scale),
				_transform(Vector3(
					x_center + side * (width * 0.5 + 0.055 * scale),
					y_center, wall_z + 0.065 * scale
				)),
				Color.WHITE, 0.035
			)
		baker.add_box(
			"timber", Vector3(width + 0.24 * scale, 0.14 * scale, 0.18 * scale),
			_transform(Vector3(
				x_center, y_center + height * 0.5 + 0.055 * scale,
				wall_z + 0.065 * scale
			)),
			Color.WHITE, 0.035
		)


func _add_masonry_row(
	baker: MeshBaker, length: float, height: float, thickness: float, center: Vector3,
	along_x: bool, stagger: float, joint: float, scale: float
) -> void:
	var segment_count := maxi(2, int(ceil(length / (1.05 * scale))))
	var pitch := length / float(segment_count)
	var block_length := pitch - joint
	var row_offset := pitch * stagger
	for segment in range(-1, segment_count + 1):
		var raw_center := -length * 0.5 + (float(segment) + 0.5) * pitch + row_offset
		var left := maxf(raw_center - block_length * 0.5, -length * 0.5 + joint * 0.5)
		var right := minf(raw_center + block_length * 0.5, length * 0.5 - joint * 0.5)
		if right - left < pitch * 0.28:
			continue
		var block_center := center
		var block_size := Vector3.ZERO
		if along_x:
			block_center.x += (left + right) * 0.5
			block_size = Vector3(right - left, height, thickness)
		else:
			block_center.z += (left + right) * 0.5
			block_size = Vector3(thickness, height, right - left)
		var stone_tint := Color.WHITE.darkened(rng.randf_range(0.015, 0.105))
		baker.add_box(
			"stone", block_size, _transform(block_center), stone_tint, 0.1
		)


func _add_roof_tiles(
	baker: MeshBaker, roof_key: String, roof_tint: Color, roof_width: float,
	roof_depth: float, roof_rise: float, wall_top: float, roof_center: Transform3D,
	scale: float
) -> void:
	var half_width := roof_width * 0.5
	var half_depth := roof_depth * 0.5
	var slope_length := Vector2(half_width, roof_rise).length()
	var row_count := maxi(2, int(ceil(slope_length / (0.78 * scale))))
	var row_pitch := slope_length / float(row_count)
	var tile_length := row_pitch * 0.88
	var tile_depth := 1.35 * scale
	var segment_count := maxi(2, int(ceil(roof_depth / tile_depth)))
	var segment_pitch := roof_depth / float(segment_count)
	var joint := 0.045 * scale
	for side in [-1.0, 1.0]:
		var roll: float = -side * atan2(roof_rise, half_width)
		var surface_normal := Vector3(
			side * roof_rise / slope_length, half_width / slope_length, 0.0
		)
		for row in row_count:
			var distance_from_ridge := (float(row) + 0.5) * row_pitch
			var local_center := Vector3(
				side * half_width * distance_from_ridge / slope_length,
				wall_top + roof_rise * (1.0 - distance_from_ridge / slope_length)
					- roof_center.origin.y,
				0.0
			)
			var stagger := segment_pitch * 0.5 if row % 2 == 1 else 0.0
			for segment in range(-1, segment_count + 1):
				var raw_start := -half_depth + float(segment) * segment_pitch + stagger
				var tile_start := maxf(raw_start + joint * 0.5, -half_depth)
				var tile_end := minf(raw_start + segment_pitch - joint * 0.5, half_depth)
				if tile_end - tile_start < segment_pitch * 0.28:
					continue
				var tile_center := local_center
				tile_center.z = (tile_start + tile_end) * 0.5
				var outward := roof_center.basis * surface_normal
				var position := roof_center * tile_center
				position += outward * (0.03 * scale)
				var tile_basis := roof_center.basis * Basis.from_euler(Vector3(0.0, 0.0, roll))
				var tint_shift := rng.randf_range(-0.035, 0.025)
				var tile_tint := Color(
					clampf(roof_tint.r + tint_shift, 0.0, 1.0),
					clampf(roof_tint.g + tint_shift, 0.0, 1.0),
					clampf(roof_tint.b + tint_shift, 0.0, 1.0)
				)
				baker.add_box(
					roof_key, Vector3(tile_length, 0.055 * scale, tile_end - tile_start),
					Transform3D(tile_basis, position), tile_tint, 0.045
				)


func _transform(position: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, position)
