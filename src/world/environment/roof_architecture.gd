class_name RoofArchitecture
extends RefCounted
## Reusable procedural roof kit for EVERAFTER structures.
##
## Every roof derives from a single validated specification (`sanitize_spec`) so
## slopes, under-decks, rafter tails, eaves, stepped courses, ridges, gable
## purlins, bargeboards, dormers, entry hoods and chimney flashings share one
## coherent pitch equation and cannot degenerate when building dimensions vary.

const MIN_SPAN := 1.2
const MIN_LENGTH := 1.2
const MIN_PITCH_RATIO := 0.24
const MAX_PITCH_RATIO := 0.95

var _baker: MeshBaker = null
var _root := Transform3D.IDENTITY


static func sanitize_spec(spec: Dictionary) -> Dictionary:
	var span := maxf(float(spec.get("span", 4.4)), MIN_SPAN)
	var length := maxf(float(spec.get("length", 4.0)), MIN_LENGTH)
	var eave_y := maxf(float(spec.get("eave_y", 3.0)), 0.4)
	var raw_rise := float(spec.get("rise", span * 0.46))
	var rise := clampf(raw_rise, span * MIN_PITCH_RATIO, span * MAX_PITCH_RATIO)
	var overhang_eave := clampf(
		float(spec.get("overhang_eave", 0.32)), 0.14, minf(0.52, span * 0.24)
	)
	var max_verge := minf(0.48, length * 0.24)
	var gable_front := bool(spec.get("gable_front", true))
	var gable_back := bool(spec.get("gable_back", true))
	var default_front := 0.32 if gable_front else 0.0
	var default_back := 0.32 if gable_back else 0.0
	var overhang_front := clampf(float(spec.get("overhang_front", default_front)), 0.0, max_verge)
	var overhang_back := clampf(float(spec.get("overhang_back", default_back)), 0.0, max_verge)
	var roof_key := String(spec.get("roof_key", "roof_tile"))
	var style := String(spec.get("style", _infer_style(roof_key)))
	return {
		"span": span,
		"length": length,
		"eave_y": eave_y,
		"rise": rise,
		"overhang_eave": overhang_eave,
		"overhang_front": overhang_front,
		"overhang_back": overhang_back,
		"roof_key": roof_key,
		"wall_key": String(spec.get("wall_key", "wall_cream")),
		"style": style,
		"timbered": bool(spec.get("timbered", true)),
		"gable_front": gable_front,
		"gable_back": gable_back,
		"gable_vent": bool(spec.get("gable_vent", true)),
		"open_truss": bool(spec.get("open_truss", false)),
		"bell_cast": clampf(float(spec.get("bell_cast", 0.08)), 0.0, 0.16),
		"tint_shift": clampf(float(spec.get("tint_shift", 0.0)), -0.08, 0.08),
		"seed_val": int(spec.get("seed_val", 0)),
	}


static func roof_surface_y(spec: Dictionary, local_x: float) -> float:
	var clean := sanitize_spec(spec)
	var half: float = clean.span * 0.5
	var rise: float = clean.rise
	var eave_y: float = clean.eave_y
	var pitch := atan2(rise, half)
	return eave_y + rise * (1.0 - absf(local_x) / half) + 0.145 / maxf(cos(pitch), 0.35)


static func _infer_style(roof_key: String) -> String:
	match roof_key:
		"roof_shingle":
			return "shingle"
		"roof_slate":
			return "slate"
		"roof_moss":
			return "moss"
		_:
			return "tile"


func build_pitched_roof(
	baker: MeshBaker, root: Transform3D, frame: Transform3D, raw_spec: Dictionary
) -> Dictionary:
	_baker = baker
	_root = root
	var spec := sanitize_spec(raw_spec)
	var span: float = spec.span
	var length: float = spec.length
	var top: float = spec.eave_y
	var rise: float = spec.rise
	var overhang: float = spec.overhang_eave
	var half := span * 0.5
	var pitch := atan2(rise, half)
	var slope := Vector2(half + overhang, rise * (1.0 + overhang / half)).length()
	var z_min: float = -length * 0.5 - float(spec.overhang_back)
	var z_max: float = length * 0.5 + float(spec.overhang_front)
	var z_mid := (z_min + z_max) * 0.5
	var total_len := z_max - z_min

	for side in [-1.0, 1.0]:
		var section := frame * _at(Vector3(0.0, top + rise, z_mid), 0.0, -side * pitch)
		_build_slope_structure(frame, section, spec, side, slope, total_len, z_mid)
		_build_slope_courses(section, spec, side, slope, total_len)

	_build_ridge(frame, spec, z_mid, total_len)
	for end in [-1.0, 1.0]:
		var has_gable := bool(spec.gable_front) if end > 0.0 else bool(spec.gable_back)
		var verge := float(spec.overhang_front) if end > 0.0 else float(spec.overhang_back)
		if has_gable:
			_build_gable_end(frame, spec, end, slope, pitch, verge)
		else:
			_build_wall_junction_flashing(frame, spec, end, pitch)
	return spec


func _build_slope_structure(
	frame: Transform3D,
	section: Transform3D,
	spec: Dictionary,
	side: float,
	slope: float,
	total_len: float,
	z_mid: float
) -> void:
	var roof_key: String = spec.roof_key
	var span: float = spec.span
	var length: float = spec.length
	var top: float = spec.eave_y
	var half := span * 0.5
	var profile := PackedVector2Array(
		[
			Vector2(0.0, 0.02),
			Vector2(side * (slope - 0.055), 0.02),
			Vector2(side * slope, 0.065),
			Vector2(side * slope, 0.14),
			Vector2(0.0, 0.14),
		]
	)
	_baker.add_profile(roof_key, profile, total_len, _root * section, _base_tint(spec, -0.03))
	var deck_pos := Vector3(side * (slope * 0.5 + 0.01), -0.015, 0.0)
	var deck_size := Vector3(slope - 0.1, 0.032, maxf(0.4, total_len - 0.16))
	_box("plank", deck_size, section * _at(deck_pos), _dark(0.14))
	if not bool(spec.open_truss):
		var plate_pos := Vector3(side * (half - 0.02), top - 0.02, 0.0)
		_box("timber", Vector3(0.18, 0.16, length + 0.08), frame * _at(plate_pos), _dark(0.24))
	var rafter_count := maxi(3, int(round(length / 0.72)) + 1)
	var tail_len := clampf(float(spec.overhang_eave) * 1.45, 0.36, slope * 0.45)
	for index in rafter_count:
		var t := float(index) / float(rafter_count - 1)
		var z_local := lerpf(-length * 0.5 + 0.16, length * 0.5 - 0.16, t) - z_mid
		var pos := Vector3(side * (slope - tail_len * 0.5 - 0.045), -0.055, z_local)
		var r_tint := _dark(0.08 + float(index % 2) * 0.03)
		_box("timber", Vector3(tail_len, 0.105, 0.095), section * _at(pos), r_tint)
	var fascia_pos := Vector3(side * (slope - 0.025), 0.02, 0.0)
	_box("timber", Vector3(0.11, 0.19, total_len + 0.02), section * _at(fascia_pos), _dark(0.06))
	var gutter_key := "stone_dark" if String(spec.style) == "slate" else "timber"
	var gut_pos := Vector3(side * (slope + 0.035), 0.065, 0.0)
	_box(gutter_key, Vector3(0.075, 0.07, total_len + 0.05), section * _at(gut_pos), _dark(0.16))
	var bell_kick: float = spec.bell_cast
	var kick_x := section * _at(Vector3(side * (slope - 0.05), 0.145, 0.0), 0.0, side * bell_kick)
	_box(roof_key, Vector3(0.26, 0.052, total_len + 0.04), kick_x, _base_tint(spec, -0.05))


func _build_slope_courses(
	section: Transform3D, spec: Dictionary, side: float, slope: float, total_len: float
) -> void:
	var roof_key: String = spec.roof_key
	var style: String = spec.style
	var seed_val: int = spec.seed_val
	var target_pitch := 0.48 if style == "slate" else (0.52 if style != "tile" else 0.56)
	var rows := clampi(int(ceil(slope / target_pitch)), 4, 6)
	var row_pitch := slope / float(rows)
	var half_len := total_len * 0.5
	for row in rows:
		var s_center := (float(row) + 0.52) * row_pitch
		var bed_tint := _base_tint(spec, -0.11 - float(row % 2) * 0.03)
		var kick := side * (0.12 if row < rows - 1 else 0.15)
		var c_pos := Vector3(side * s_center, 0.148, 0.0)
		var c_size := Vector3(row_pitch * 0.96, 0.048, total_len - 0.02)
		_box(roof_key, c_size, section * _at(c_pos, 0.0, kick), bed_tint)
	if style == "tile":
		_build_terracotta_coppi(section, spec, side, slope, total_len, rows, row_pitch)
	elif style == "slate":
		_build_slate_courses(section, spec, side, total_len, half_len, rows, row_pitch)
	else:
		_build_shingle_courses(section, spec, side, total_len, half_len, rows, row_pitch)


func _build_terracotta_coppi(
	section: Transform3D,
	spec: Dictionary,
	side: float,
	slope: float,
	total_len: float,
	rows: int,
	row_pitch: float
) -> void:
	var roof_key: String = spec.roof_key
	var seed_val: int = spec.seed_val
	var half_len := total_len * 0.5
	# Staggered terracotta pan plates along alternate courses.
	var pan_cols := clampi(int(ceil(total_len / 1.55)), 3, 5)
	var pan_pitch := total_len / float(pan_cols)
	for row in rows:
		for col in pan_cols:
			var stagger := (float(row % 2) - 0.5) * pan_pitch * 0.36
			var z := -half_len + (float(col) + 0.5) * pan_pitch + stagger
			var w := minf(pan_pitch * 0.72, half_len - absf(z) - 0.04)
			if w < 0.14:
				continue
			var hash_v := posmod(row * 11 + col * 7 + seed_val, 5)
			var delta := -0.05 + float(hash_v) * 0.024
			var p_pos := Vector3(side * (float(row) + 0.54) * row_pitch, 0.168, z)
			var p_size := Vector3(row_pitch * 0.82, 0.042, w)
			_box(roof_key, p_size, section * _at(p_pos, 0.0, side * 0.11), _base_tint(spec, delta))
	# Longitudinal barrel-tile ribs (coppi) projecting slightly past the eave.
	var rib_count := clampi(int(round(total_len / 0.68)), 5, 11)
	for rib in rib_count:
		var t_rib := float(rib) / float(maxi(rib_count - 1, 1))
		var z := lerpf(-half_len + 0.18, half_len - 0.18, t_rib)
		var hash_v := posmod(rib * 5 + seed_val, 4)
		var rib_tint := _base_tint(spec, 0.035 - float(hash_v) * 0.028)
		var r_pos := Vector3(side * (slope * 0.52), 0.186, z)
		var r_size := Vector3(slope * 0.98, 0.056, 0.115)
		_box(roof_key, r_size, section * _at(r_pos, 0.0, side * 0.03), rib_tint)


func _build_shingle_courses(
	section: Transform3D,
	spec: Dictionary,
	side: float,
	total_len: float,
	half_len: float,
	rows: int,
	row_pitch: float
) -> void:
	var roof_key: String = spec.roof_key
	var seed_val: int = spec.seed_val
	var cols := clampi(int(ceil(total_len / 1.25)), 3, 6)
	var col_pitch := total_len / float(cols)
	for row in rows:
		for col in cols + 1:
			var start := -half_len + (float(col) - float(row % 2) * 0.5) * col_pitch
			var end := minf(start + col_pitch, half_len - 0.03)
			start = maxf(start, -half_len + 0.03)
			if end - start < 0.12:
				continue
			var z := (start + end) * 0.5
			var h_val := posmod(row * 13 + col * 7 + seed_val * 3, 7)
			var s_jit := (float(h_val % 3) - 1.0) * 0.028
			var thick := 0.045 + float(h_val % 3) * 0.011
			var tone := -0.085 + float(h_val) * 0.026
			var s_pos := Vector3(side * ((float(row) + 0.54) * row_pitch + s_jit), 0.168, z)
			var s_size := Vector3(row_pitch * 0.88, thick, end - start - 0.024)
			_box(roof_key, s_size, section * _at(s_pos, 0.0, side * 0.125), _base_tint(spec, tone))


func _build_slate_courses(
	section: Transform3D,
	spec: Dictionary,
	side: float,
	total_len: float,
	half_len: float,
	rows: int,
	row_pitch: float
) -> void:
	var roof_key: String = spec.roof_key
	var seed_val: int = spec.seed_val
	var cols := clampi(int(ceil(total_len / 1.28)), 3, 7)
	var col_pitch := total_len / float(cols)
	var belt_row := int(rows / 2)
	for row in rows:
		var is_belt := row == belt_row
		for col in cols + 1:
			var start := -half_len + (float(col) - float(row % 2) * 0.5) * col_pitch
			var end := minf(start + col_pitch, half_len - 0.03)
			start = maxf(start, -half_len + 0.03)
			if end - start < 0.12:
				continue
			var z := (start + end) * 0.5
			var h_val := posmod(row * 9 + col * 5 + seed_val, 5)
			var tone := 0.055 if is_belt else (-0.065 + float(h_val) * 0.024)
			var thick := 0.052 if is_belt else 0.042
			var s_pos := Vector3(side * (float(row) + 0.52) * row_pitch, 0.166, z)
			var s_size := Vector3(row_pitch * 0.9, thick, end - start - 0.026)
			_box(roof_key, s_size, section * _at(s_pos, 0.0, side * 0.105), _base_tint(spec, tone))


func _build_ridge(frame: Transform3D, spec: Dictionary, z_mid: float, total_len: float) -> void:
	var roof_key: String = spec.roof_key
	var style: String = spec.style
	var apex_y: float = float(spec.eave_y) + float(spec.rise)
	var front_out := 0.16 if bool(spec.gable_front) else 0.0
	var back_out := 0.16 if bool(spec.gable_back) else 0.0
	var beam_len := total_len + front_out + back_out
	var beam_z := z_mid + (front_out - back_out) * 0.5
	var b_pos := Vector3(0.0, apex_y - 0.03, beam_z)
	_box("timber", Vector3(0.16, 0.18, beam_len), frame * _at(b_pos), _dark(0.08))
	var ridge_prof := PackedVector2Array(
		[
			Vector2(-0.22, -0.01),
			Vector2(0.0, 0.155),
			Vector2(0.22, -0.01),
			Vector2(0.17, -0.09),
			Vector2(-0.17, -0.09),
		]
	)
	_baker.add_profile(
		roof_key,
		ridge_prof,
		total_len + 0.08,
		_root * frame * _at(Vector3(0.0, apex_y + 0.165, z_mid)),
		_base_tint(spec, 0.02)
	)
	var cap_count := clampi(int(round(total_len / 0.82)), 4, 11)
	var half_len := total_len * 0.5
	for index in cap_count:
		var t := float(index) / float(maxi(cap_count - 1, 1))
		var z := z_mid + lerpf(-half_len + 0.22, half_len - 0.22, t)
		if style == "tile":
			var cap_tint := _base_tint(spec, 0.04 - float(index % 2) * 0.05)
			var t_pos := Vector3(0.0, apex_y + 0.245, z)
			_box(roof_key, Vector3(0.32, 0.11, 0.28), frame * _at(t_pos), cap_tint)
		elif style == "slate":
			var sl_pos := Vector3(0.0, apex_y + 0.245, z)
			_box("stone_dark", Vector3(0.3, 0.1, 0.14), frame * _at(sl_pos), _dark(0.08))
		else:
			for side in [-1.0, 1.0]:
				var c_p := Vector3(side * 0.08, apex_y + 0.235, z)
				var c_xform := frame * _at(c_p, 0.0, -side * 0.62)
				_box("timber", Vector3(0.42, 0.075, 0.085), c_xform, _dark(0.05))


func _build_gable_end(
	frame: Transform3D, spec: Dictionary, end: float, slope: float, pitch: float, verge: float
) -> void:
	var span: float = spec.span
	var length: float = spec.length
	var top: float = spec.eave_y
	var rise: float = spec.rise
	var half := span * 0.5
	var wall_key: String = spec.wall_key
	var timbered: bool = spec.timbered
	var open_truss: bool = spec.open_truss
	var z_wall := end * (length * 0.5 - 0.1)
	var z_face := end * length * 0.5
	var z_verge := end * (length * 0.5 + verge)

	if not open_truss:
		var gable := frame * _at(Vector3(0.0, top, z_wall))
		var g_prof := PackedVector2Array(
			[Vector2(-half, 0.0), Vector2(half, 0.0), Vector2(0.0, rise)]
		)
		_baker.add_profile(wall_key, g_prof, 0.2, _root * gable)
	var face := frame * _at(Vector3(0.0, 0.0, z_face), PI if end < 0.0 else 0.0)
	if timbered:
		_beam(Vector3(-half, top + 0.02, 0.0), Vector3(half, top + 0.02, 0.0), 0.18, face)
		_beam(Vector3(0.0, top, 0.0), Vector3(0.0, top + rise - 0.06, 0.0), 0.14, face)
		var collar_y := top + rise * 0.52
		var collar_half := half * (1.0 - 0.52)
		_beam(Vector3(-collar_half, collar_y, 0.0), Vector3(collar_half, collar_y, 0.0), 0.12, face)
		for side in [-1.0, 1.0]:
			_beam(
				Vector3(side * half * 0.88, top + 0.04, 0.0),
				Vector3(0.0, top + rise * 0.86, 0.0),
				0.115,
				face
			)
		if bool(spec.gable_vent) and not open_truss and rise >= 1.55:
			var vent_y := top + rise * 0.28
			_box("timber", Vector3(0.46, 0.54, 0.16), face * _at(Vector3(0.0, vent_y, 0.02)))
			_box("window", Vector3(0.32, 0.4, 0.08), face * _at(Vector3(0.0, vent_y, 0.05)))
			_box("plank", Vector3(0.34, 0.05, 0.12), face * _at(Vector3(0.0, vent_y, 0.07)))
	else:
		for side in [-1.0, 1.0]:
			_beam(
				Vector3(side * (half + 0.12), top - 0.04, 0.02),
				Vector3(0.0, top + rise + 0.06, 0.02),
				0.18,
				face,
				"stone_dark"
			)
			var k_pos := Vector3(side * (half + 0.04), top - 0.04, 0.02)
			_box("stone_dark", Vector3(0.34, 0.24, 0.34), face * _at(k_pos))
		if bool(spec.gable_vent) and rise >= 1.8:
			var vent_y := top + rise * 0.42
			_box("stone_dark", Vector3(0.56, 0.96, 0.22), face * _at(Vector3(0.0, vent_y, 0.02)))
			_box("window", Vector3(0.34, 0.74, 0.1), face * _at(Vector3(0.0, vent_y, 0.06)))
	if verge > 0.08:
		var purlin_key := "timber" if timbered else "stone_dark"
		var z_purlin := end * (length * 0.5 + verge * 0.48)
		for side in [-1.0, 1.0]:
			var p1 := Vector3(side * (half - 0.08), top - 0.02, z_purlin)
			var p2 := Vector3(side * half * 0.48, top + rise * 0.5 - 0.02, z_purlin)
			_box(purlin_key, Vector3(0.16, 0.16, verge + 0.18), frame * _at(p1))
			_box(purlin_key, Vector3(0.14, 0.15, verge + 0.16), frame * _at(p2))
			if not open_truss:
				_beam(
					Vector3(side * (half - 0.08), top - 0.46, 0.0),
					Vector3(side * (half - 0.08), top - 0.04, verge * 0.78),
					0.1,
					face,
					purlin_key
				)
	var barge_key := "timber" if timbered else "stone_dark"
	var trim_key := "timber" if timbered else "stone_dark"
	for side in [-1.0, 1.0]:
		var rake := frame * _at(Vector3(0.0, top + rise, z_verge), 0.0, -side * pitch)
		var b_pos := Vector3(side * slope * 0.5, 0.03, 0.0)
		var t_pos := Vector3(side * slope * 0.5, 0.145, 0.0)
		var f_pos := Vector3(side * (slope - 0.04), -0.02, 0.0)
		_box(barge_key, Vector3(slope + 0.06, 0.18, 0.13), rake * _at(b_pos), _dark(0.04))
		_box(trim_key, Vector3(slope + 0.09, 0.055, 0.165), rake * _at(t_pos), _dark(0.18))
		_box(barge_key, Vector3(0.22, 0.22, 0.16), rake * _at(f_pos), _dark(0.08))
	var finial_h := 0.46 if String(spec.style) in ["shingle", "moss"] else 0.34
	var fin_pos := Vector3(0.0, top + rise + 0.12, z_verge + end * 0.02)
	_box(barge_key, Vector3(0.15, finial_h, 0.15), frame * _at(fin_pos), _dark(0.06))


func _build_wall_junction_flashing(
	frame: Transform3D, spec: Dictionary, end: float, pitch: float
) -> void:
	var half: float = float(spec.span) * 0.5
	var top: float = spec.eave_y
	var rise: float = spec.rise
	var slope_wall := Vector2(half + 0.16, rise * (1.0 + 0.16 / half)).length()
	var z_join := end * (float(spec.length) * 0.5 - 0.02)
	for side in [-1.0, 1.0]:
		var rake := frame * _at(Vector3(0.0, top + rise, z_join), 0.0, -side * pitch)
		var r_pos := Vector3(side * slope_wall * 0.5, 0.15, 0.0)
		_box("stone_dark", Vector3(slope_wall, 0.16, 0.18), rake * _at(r_pos), _dark(0.08))
	var cap_pos := Vector3(0.0, top + rise + 0.18, z_join)
	_box("stone_dark", Vector3(0.36, 0.22, 0.22), frame * _at(cap_pos), _dark(0.1))


func build_gable_dormer(
	baker: MeshBaker,
	root: Transform3D,
	frame: Transform3D,
	raw_spec: Dictionary,
	side: float,
	z_offset: float,
	dormer_width: float = 1.06
) -> void:
	_baker = baker
	_root = root
	var spec := sanitize_spec(raw_spec)
	var half: float = spec.span * 0.5
	var top: float = spec.eave_y
	var rise: float = spec.rise
	var pitch := atan2(rise, half)
	var x_front := side * half * 0.68
	var x_back := side * half * 0.30
	var x_mid := (x_front + x_back) * 0.5
	var d_depth := absf(x_front - x_back)
	var y_base := top + rise * (1.0 - absf(x_front) / half) + 0.06
	var d_wall_h := clampf((top + rise * (1.0 - absf(x_back) / half) + 0.12) - y_base, 0.72, 1.04)
	var d_rise := 0.42
	var d_frame := frame * _at(Vector3(x_mid, 0.0, z_offset), side * PI * 0.5)
	var flash_y := roof_surface_y(spec, x_mid)
	var f_xform := frame * _at(Vector3(x_mid, flash_y - 0.02, z_offset), 0.0, -side * pitch)
	_box("stone_dark", Vector3(d_depth + 0.22, 0.08, dormer_width + 0.24), f_xform, _dark(0.14))
	var body_pos := Vector3(0.0, y_base + d_wall_h * 0.5, 0.0)
	_box(String(spec.wall_key), Vector3(dormer_width, d_wall_h, d_depth), d_frame * _at(body_pos))
	for s in [-1.0, 1.0]:
		var post_p := Vector3(
			s * (dormer_width * 0.5 - 0.05), y_base + d_wall_h * 0.5, d_depth * 0.5 - 0.04
		)
		_box("timber", Vector3(0.12, d_wall_h + 0.04, 0.14), d_frame * _at(post_p))
	var win_y := y_base + d_wall_h * 0.54
	_box("timber", Vector3(0.56, 0.54, 0.12), d_frame * _at(Vector3(0.0, win_y, d_depth * 0.5)))
	var w_pos := Vector3(0.0, win_y, d_depth * 0.5 + 0.04)
	_box("window", Vector3(0.42, 0.42, 0.06), d_frame * _at(w_pos))
	var sill_pos := Vector3(0.0, win_y - 0.26, d_depth * 0.5 + 0.04)
	_box("stone", Vector3(0.64, 0.08, 0.18), d_frame * _at(sill_pos))
	var d_half := dormer_width * 0.5 + 0.14
	var d_slope := Vector2(d_half, d_rise).length()
	var d_pitch := atan2(d_rise, d_half)
	var d_apex := y_base + d_wall_h + d_rise
	var d_roof_len := d_depth + 0.24
	var d_gable := PackedVector2Array(
		[Vector2(-dormer_width * 0.5, 0.0), Vector2(dormer_width * 0.5, 0.0), Vector2(0.0, d_rise)]
	)
	_baker.add_profile(
		String(spec.wall_key),
		d_gable,
		0.14,
		_root * d_frame * _at(Vector3(0.0, y_base + d_wall_h, d_depth * 0.5 - 0.07))
	)
	for s in [-1.0, 1.0]:
		var d_sec := d_frame * _at(Vector3(0.0, d_apex, 0.04), 0.0, -s * d_pitch)
		var dk_pos := Vector3(s * d_slope * 0.5, 0.02, 0.0)
		_box("plank", Vector3(d_slope, 0.04, d_roof_len), d_sec * _at(dk_pos), _dark(0.12))
		for r in 2:
			var r_pos := Vector3(s * (float(r) + 0.5) * d_slope * 0.48, 0.065, 0.0)
			var r_size := Vector3(d_slope * 0.52, 0.05, d_roof_len + 0.02)
			var r_tint := _base_tint(spec, -0.02 * float(r))
			_box(String(spec.roof_key), r_size, d_sec * _at(r_pos, 0.0, s * 0.11), r_tint)
		var bg_pos := Vector3(s * d_slope * 0.5, 0.03, d_roof_len * 0.5)
		_box("timber", Vector3(d_slope + 0.04, 0.11, 0.09), d_sec * _at(bg_pos))
	var rc_pos := Vector3(0.0, d_apex + 0.07, 0.04)
	_box(
		String(spec.roof_key),
		Vector3(0.2, 0.1, d_roof_len + 0.06),
		d_frame * _at(rc_pos),
		_base_tint(spec, 0.03)
	)


func build_entry_hood(
	baker: MeshBaker,
	root: Transform3D,
	frame: Transform3D,
	roof_key: String,
	face_z: float,
	top_y: float,
	width: float
) -> void:
	_baker = baker
	_root = root
	var clean_w := maxf(width, 1.1)
	var hood := frame * _at(Vector3(0.0, top_y, face_z + 0.28), 0.0)
	hood.basis = hood.basis * Basis(Vector3.RIGHT, 0.28)
	var fl_pos := Vector3(0.0, top_y + 0.12, face_z + 0.04)
	_box("stone_dark", Vector3(clean_w + 0.14, 0.09, 0.14), frame * _at(fl_pos), _dark(0.12))
	_box("plank", Vector3(clean_w, 0.045, 0.78), hood * _at(Vector3(0.0, -0.02, 0.0)), _dark(0.1))
	_box("timber", Vector3(clean_w + 0.1, 0.14, 0.11), hood * _at(Vector3(0.0, -0.04, 0.39)))
	for row in 3:
		var z_c := -0.25 + float(row) * 0.25
		var course_frame := hood * _at(Vector3(0.0, 0.038 + float(row) * 0.008, z_c))
		course_frame.basis = course_frame.basis * Basis(Vector3.RIGHT, -0.1)
		var h_tint := _dark(float(row % 2) * 0.045)
		_box(roof_key, Vector3(clean_w + 0.06, 0.048, 0.28), course_frame, h_tint)
	for side in [-1.0, 1.0]:
		var x: float = side * (clean_w * 0.5 - 0.13)
		_beam(
			Vector3(x, top_y - 0.65, face_z), Vector3(x, top_y - 0.18, face_z + 0.52), 0.11, frame
		)
		_box("timber", Vector3(0.11, 0.13, 0.74), hood * _at(Vector3(x, -0.1, 0.0)))
		var b_pos := Vector3(side * (clean_w * 0.5 + 0.02), 0.01, 0.0)
		_box("timber", Vector3(0.09, 0.14, 0.82), hood * _at(b_pos), _dark(0.06))


func build_chimney(
	baker: MeshBaker,
	root: Transform3D,
	frame: Transform3D,
	raw_spec: Dictionary,
	pos: Vector2,
	top_y: float,
	crown_style: int = 0
) -> void:
	_baker = baker
	_root = root
	var spec := sanitize_spec(raw_spec)
	var half: float = spec.span * 0.5
	var pitch := atan2(float(spec.rise), half)
	var side_sign := -1.0 if pos.x < 0.0 else 1.0
	var y_roof := roof_surface_y(spec, pos.x)
	var bottom_y := maxf(float(spec.eave_y) - 0.15, y_roof - 0.65)
	var safe_top := maxf(top_y, y_roof + 1.15)
	var c_frame := frame * _at(Vector3(pos.x, 0.0, pos.y))
	var flash_frame := frame * _at(Vector3(pos.x, y_roof + 0.02, pos.y), 0.0, -side_sign * pitch)
	_box("stone_dark", Vector3(0.86, 0.12, 0.84), flash_frame, _dark(0.14))
	_box("iron", Vector3(0.92, 0.045, 0.88), flash_frame * _at(Vector3(0.0, -0.04, 0.0)))
	var shoulder_y := minf(y_roof + 0.42, safe_top - 0.65)
	var base_h := maxf(0.28, shoulder_y - bottom_y)
	var b_pos := Vector3(0.0, bottom_y + base_h * 0.5, 0.0)
	_box("stone_dark", Vector3(0.64, base_h, 0.64), c_frame * _at(b_pos), _dark(0.06))
	_box("stone", Vector3(0.7, 0.1, 0.7), c_frame * _at(Vector3(0.0, shoulder_y + 0.04, 0.0)))
	var shaft_bottom := shoulder_y + 0.08
	var shaft_h := maxf(0.45, safe_top - shaft_bottom)
	var courses := maxi(3, int(ceil(shaft_h / 0.25)))
	var c_step := shaft_h / float(courses)
	var shaft_w := 0.68 if crown_style == 2 else 0.56
	for course in courses:
		var y := shaft_bottom + (float(course) + 0.5) * c_step
		var shade := float((course + int(absf(pos.x) * 3.0)) % 3) * 0.04
		var c_pos := Vector3(0.0, y, 0.0)
		_box("stone", Vector3(shaft_w, c_step - 0.012, 0.56), c_frame * _at(c_pos), _dark(shade))
	var n_pos := Vector3(0.0, safe_top - 0.04, 0.0)
	_box("stone_dark", Vector3(shaft_w + 0.12, 0.1, 0.68), c_frame * _at(n_pos))
	_box(
		"iron",
		Vector3(shaft_w - 0.14, 0.025, 0.4),
		c_frame * _at(Vector3(0.0, safe_top + 0.015, 0.0))
	)
	for side in [-1.0, 1.0]:
		var s_x: float = side * (shaft_w * 0.5 + 0.02)
		_box(
			"stone_dark",
			Vector3(0.16, 0.18, 0.76),
			c_frame * _at(Vector3(s_x, safe_top + 0.09, 0.0))
		)
		var z_c: float = side * 0.3
		_box(
			"stone_dark",
			Vector3(shaft_w - 0.1, 0.18, 0.16),
			c_frame * _at(Vector3(0.0, safe_top + 0.09, z_c))
		)
	_build_chimney_crown(c_frame, spec, safe_top, crown_style)


func _build_chimney_crown(
	c_frame: Transform3D, spec: Dictionary, safe_top: float, crown_style: int
) -> void:
	if crown_style == 1:
		for sx in [-0.2, 0.2]:
			for sz in [-0.2, 0.2]:
				var p_pos := Vector3(sx, safe_top + 0.32, sz)
				_box("stone", Vector3(0.11, 0.28, 0.11), c_frame * _at(p_pos))
		for s in [-1.0, 1.0]:
			var h_xform := c_frame * _at(Vector3(s * 0.16, safe_top + 0.52, 0.0), 0.0, -s * 0.42)
			_box("stone_dark", Vector3(0.46, 0.08, 0.76), h_xform)
		return
	var spread := 0.17 if crown_style == 2 else 0.13
	var pot_key := "roof_tile" if String(spec.roof_key) == "roof_tile" else "iron"
	for s in [-1.0, 1.0]:
		var pot_pos := Vector3(s * spread, safe_top + 0.32, 0.0)
		_baker.add_cylinder(
			pot_key, 0.095, 0.115, 0.34, 8, _root * c_frame * _at(pot_pos), _dark(0.08), 0.05
		)
		var rim_pos := pot_pos + Vector3(0.0, 0.16, 0.0)
		_baker.add_cylinder("iron", 0.115, 0.115, 0.05, 8, _root * c_frame * _at(rim_pos))


func build_belfry_spire(
	baker: MeshBaker,
	root: Transform3D,
	frame: Transform3D,
	base_y: float = 9.5,
	base_radius: float = 2.46,
	total_height: float = 2.35
) -> void:
	_baker = baker
	_root = root
	for quarter in 4:
		var side_frame := frame * _at(Vector3.ZERO, float(quarter) * PI * 0.5)
		for offset in [-0.95, 0.0, 0.95]:
			var cb_pos := Vector3(offset, base_y - 0.12, 1.48)
			_box("stone_dark", Vector3(0.22, 0.22, 0.26), side_frame * _at(cb_pos))
	_box(
		"timber", Vector3(3.2, 0.12, 3.2), frame * _at(Vector3(0.0, base_y + 0.04, 0.0)), _dark(0.1)
	)
	var tiers := [
		{"r_bot": base_radius, "r_top": base_radius * 0.67, "y0": 0.05, "h": 0.58, "shade": 0.07},
		{
			"r_bot": base_radius * 0.71,
			"r_top": base_radius * 0.36,
			"y0": 0.6,
			"h": 0.82,
			"shade": 0.0
		},
		{
			"r_bot": base_radius * 0.4,
			"r_top": 0.0,
			"y0": 1.38,
			"h": total_height - 1.35,
			"shade": 0.06
		},
	]
	for tier in tiers:
		var t_h := float(tier.h)
		var t_y := base_y + float(tier.y0) + t_h * 0.5
		_baker.add_cylinder(
			"roof_slate",
			float(tier.r_top),
			float(tier.r_bot),
			t_h,
			4,
			_root * frame * _at(Vector3(0.0, t_y, 0.0), PI * 0.25),
			_dark(float(tier.shade)),
			0.05
		)
	var spire_base := base_y + 0.58
	var peak := Vector3(0.0, base_y + total_height, 0.0)
	for corner in 4:
		var c_angle := float(corner) * PI * 0.5 + PI * 0.25
		var c_dir := Vector3(cos(c_angle), 0.0, sin(c_angle))
		var r_start := c_dir * (base_radius * 0.69) + Vector3(0.0, spire_base, 0.0)
		_beam(r_start, peak, 0.11, frame, "stone_dark")
	for quarter in 4:
		var luc := frame * _at(Vector3.ZERO, float(quarter) * PI * 0.5)
		_box(
			"stone_dark",
			Vector3(0.44, 0.44, 0.34),
			luc * _at(Vector3(0.0, spire_base + 0.24, 1.08))
		)
		_box("iron", Vector3(0.22, 0.28, 0.08), luc * _at(Vector3(0.0, spire_base + 0.22, 1.24)))
		for s in [-1.0, 1.0]:
			var l_xform := luc * _at(Vector3(s * 0.13, spire_base + 0.5, 1.1), 0.0, -s * 0.52)
			_box("roof_slate", Vector3(0.34, 0.07, 0.42), l_xform, Color.WHITE.lightened(0.05))
	var top_y := base_y + total_height
	_box("iron", Vector3(0.08, 0.78, 0.08), frame * _at(Vector3(0.0, top_y + 0.34, 0.0)))
	_box("iron", Vector3(0.42, 0.055, 0.055), frame * _at(Vector3(0.0, top_y + 0.48, 0.0)))
	_box("iron", Vector3(0.3, 0.04, 0.14), frame * _at(Vector3(0.16, top_y + 0.62, 0.0)))


func _box(key: String, size: Vector3, xform: Transform3D, tint: Color = Color.WHITE) -> void:
	_baker.add_box(key, size, _root * xform, tint, 0.05)


func _dark(amount: float) -> Color:
	return Color.WHITE.darkened(amount)


func _base_tint(spec: Dictionary, delta: float = 0.0) -> Color:
	var shift := float(spec.get("tint_shift", 0.0)) + delta
	if shift >= 0.0:
		return Color.WHITE.lightened(minf(shift, 0.18))
	return Color.WHITE.darkened(minf(-shift, 0.28))


func _beam(
	a: Vector3,
	b: Vector3,
	thickness: float,
	frame: Transform3D = Transform3D.IDENTITY,
	key: String = "timber"
) -> void:
	var along := (b - a).normalized()
	var reference := Vector3.FORWARD if absf(along.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var across := along.cross(reference).normalized()
	var basis := Basis(across, along, across.cross(along))
	var b_size := Vector3(thickness, a.distance_to(b), thickness)
	_box(key, b_size, frame * Transform3D(basis, (a + b) * 0.5))


func _at(position: Vector3, yaw: float = 0.0, roll: float = 0.0) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(0.0, yaw, roll)), position)
