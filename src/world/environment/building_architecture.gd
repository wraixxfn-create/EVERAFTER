class_name BuildingArchitecture
extends RefCounted
## Structural kit for the inhabited buildings. Model-space metres throughout;
## the placement scale is composed ONCE at the entry point. Facades are shells
## assembled around openings, not a solid box hidden behind applied windows.
## The kit emits only baked geometry: gameplay nodes and collision stay owned
## by BuildingFactory. No imported assets, textures or new materials.

const PLINTH := 0.42
const WALL_THICKNESS := 0.22
const OVERHANG := 0.32

var _baker: MeshBaker
var _root := Transform3D.IDENTITY
var _wall := "wall_cream"
var _roof := "roof_tile"
var _roof_kit := RoofArchitecture.new()


func build(baker: MeshBaker, placement: VillageLayout.Placement) -> void:
	_baker = baker
	_root = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * placement.scale), Vector3.ZERO)
	match placement.kind:
		VillageLayout.KIND_HOUSE:
			_house(placement.variant, placement.id)
		VillageLayout.KIND_INN:
			_inn()
		VillageLayout.KIND_HALL:
			_hall()
	_baker = null


func _house(variant: int, placement_id: String = "") -> void:
	var v := posmod(variant, 3)
	var base_wall: String = ["wall_cream", "wall_ochre", "wall_pale"][v]
	var base_roof: String = ["roof_tile", "roof_shingle", "roof_slate"][v]
	var v_cfg := _house_variation(v, placement_id, base_wall, base_roof)
	_wall = String(v_cfg.wall_key)
	_roof = String(v_cfg.roof_key)
	var pitch_scale: float = v_cfg.pitch_scale
	var c_side: float = v_cfg.chimney_side
	var crown: int = v_cfg.crown_style
	var width := 5.8 if v == 2 else 4.4
	var depth := 3.4 if v == 2 else 4.0
	_foundation(width, depth)
	if v == 1:
		# The upper storey jets out 10 cm on each side, within the old box
		# collider. Corbels carry the sill rather than a floating upper cube.
		_storey(width - 0.2, depth - 0.18, PLINTH, 2.26, true)
		_storey(width, depth, 2.68, 1.94, false)
		for side in [-1.0, 1.0]:
			for x in [-1.65, -0.68, 0.68, 1.65]:
				_profile(
					"timber",
					PackedVector2Array(
						[
							Vector2(-0.15, 0.0),
							Vector2(0.15, 0.0),
							Vector2(0.15, -0.33),
							Vector2(-0.15, -0.12)
						]
					),
					0.16,
					_at(Vector3(x, 2.68, side * (depth * 0.5 - 0.06)))
				)
		var spec1 := _roof_spec(width, depth, 4.62, 2.2 * pitch_scale, true, v_cfg)
		_roof_kit.build_pitched_roof(_baker, _root, Transform3D.IDENTITY, spec1)
		_roof_kit.build_gable_dormer(
			_baker, _root, Transform3D.IDENTITY, spec1, -c_side, 0.15, 0.96
		)
		_entry_hood(depth * 0.5, 2.62, 1.48)
		_chimney_on_roof(Transform3D.IDENTITY, spec1, Vector2(c_side * 1.25, -0.85), 7.25, crown)
	elif v == 2:
		# A broad crofter's house uses a transverse ridge, not the same
		# cottage stretched sideways. Entry hood is cantilevered, no road posts.
		_storey(width, depth, PLINTH, 2.85, true)
		var transverse := _at(Vector3.ZERO, PI * 0.5)
		var spec2 := _roof_spec(depth, width, 3.27, 1.85 * pitch_scale, true, v_cfg)
		_roof_kit.build_pitched_roof(_baker, _root, transverse, spec2)
		if bool(v_cfg.twin_dormers):
			for dz in [-1.35, 1.35]:
				_roof_kit.build_gable_dormer(_baker, _root, transverse, spec2, -1.0, dz, 0.88)
		else:
			_roof_kit.build_gable_dormer(
				_baker, _root, transverse, spec2, -1.0, float(v_cfg.dormer_z), 0.98
			)
		_entry_hood(depth * 0.5, 2.65, 1.65)
		_chimney_on_roof(transverse, spec2, Vector2(0.75, c_side * 1.85), 5.9, crown)
	else:
		_storey(width, depth, PLINTH, 2.65, true)
		var spec0 := _roof_spec(width, depth, 3.07, 2.05 * pitch_scale, true, v_cfg)
		_roof_kit.build_pitched_roof(_baker, _root, Transform3D.IDENTITY, spec0)
		_roof_kit.build_gable_dormer(
			_baker, _root, Transform3D.IDENTITY, spec0, -c_side, -0.15, 0.92
		)
		_entry_hood(depth * 0.5, 2.64, 1.45)
		_chimney_on_roof(Transform3D.IDENTITY, spec0, Vector2(c_side * 1.25, -0.85), 5.65, crown)
	_steps(depth, 1.0)


func _house_variation(
	v: int, placement_id: String, base_wall: String, base_roof: String
) -> Dictionary:
	var cfg := {
		"wall_key": base_wall,
		"roof_key": base_roof,
		"pitch_scale": 1.0,
		"overhang_eave": 0.34 + float(v) * 0.015,
		"bell_cast": 0.08,
		"tint_shift": 0.0,
		"seed_val": v * 17 + 3,
		"chimney_side": -1.0 if v == 2 else 1.0,
		"crown_style": v,
		"twin_dormers": false,
		"dormer_z": 0.0,
	}
	if not placement_id.begins_with("house_"):
		return cfg
	var num := int(placement_id.trim_prefix("house_"))
	var pitch_table := [0.94, 1.04, 0.98, 1.07, 0.95, 1.02, 1.06]
	var shift_table := [-0.05, 0.03, -0.02, 0.04, -0.04, 0.02]
	cfg.pitch_scale = pitch_table[posmod(num, pitch_table.size())]
	cfg.overhang_eave = 0.32 + float(posmod(num * 3, 4)) * 0.022
	cfg.bell_cast = 0.06 + float(posmod(num * 5, 4)) * 0.02
	cfg.tint_shift = shift_table[posmod(num, shift_table.size())]
	cfg.seed_val = num * 19 + v * 7
	cfg.chimney_side = -1.0 if posmod(num, 2) == 1 else 1.0
	cfg.crown_style = posmod(num + v, 3)
	cfg.twin_dormers = v == 2 and posmod(num, 3) == 0
	cfg.dormer_z = -0.85 if posmod(num, 2) == 0 else 0.85
	if num in [19, 24, 28]:
		cfg.roof_key = "roof_moss"
	elif num in [16, 27]:
		cfg.roof_key = "roof_shingle"
	elif num in [21, 25]:
		cfg.roof_key = "roof_tile"
	return cfg


func _roof_spec(
	span: float, length: float, eave_y: float, rise: float, timbered: bool, v_cfg: Dictionary = {}
) -> Dictionary:
	return {
		"span": span,
		"length": length,
		"eave_y": eave_y,
		"rise": rise,
		"overhang_eave": float(v_cfg.get("overhang_eave", OVERHANG)),
		"overhang_front": OVERHANG,
		"overhang_back": OVERHANG,
		"roof_key": _roof,
		"wall_key": _wall,
		"timbered": timbered,
		"bell_cast": float(v_cfg.get("bell_cast", 0.08)),
		"tint_shift": float(v_cfg.get("tint_shift", 0.0)),
		"seed_val": int(v_cfg.get("seed_val", 0)),
	}


func _inn() -> void:
	_wall = "wall_ochre"
	_roof = "roof_shingle"
	_foundation(8.2, 5.6)
	_storey(8.0, 5.4, PLINTH, 2.5, true, Transform3D.IDENTITY, 1.5, "-X")
	_storey(8.2, 5.6, 2.92, 2.5, false)
	var inn_spec := {
		"span": 8.2,
		"length": 5.6,
		"eave_y": 5.42,
		"rise": 3.25,
		"overhang_eave": 0.36,
		"overhang_front": 0.34,
		"overhang_back": 0.34,
		"roof_key": "roof_shingle",
		"wall_key": "wall_ochre",
		"timbered": true,
		"bell_cast": 0.1,
		"seed_val": 41,
	}
	_roof_kit.build_pitched_roof(_baker, _root, Transform3D.IDENTITY, inn_spec)
	for side in [-1.0, 1.0]:
		_roof_kit.build_gable_dormer(
			_baker, _root, Transform3D.IDENTITY, inn_spec, side, 0.72, 1.02
		)
	_chimney_on_roof(Transform3D.IDENTITY, inn_spec, Vector2(2.35, -1.35), 9.1, 2)
	# Wing joins the main body's west wall; no buried facade or window in
	# the junction. All of its walls remain inside the existing wing collider.
	var wing := _at(Vector3(-5.0, 0.0, 1.6), PI * 0.5)
	_wall = "wall_ash"
	_foundation(2.8, 3.2, wing)
	_storey(2.8, 3.2, PLINTH, 2.7, false, wing, 1.0, "+Z")
	_roof = "roof_tile"
	var wing_spec := {
		"span": 2.8,
		"length": 3.2,
		"eave_y": 3.12,
		"rise": 1.4,
		"overhang_eave": 0.3,
		"overhang_front": 0.0,
		"overhang_back": 0.32,
		"gable_front": false,
		"gable_back": true,
		"roof_key": "roof_tile",
		"wall_key": "wall_ash",
		"timbered": true,
		"bell_cast": 0.08,
		"seed_val": 53,
	}
	_roof_kit.build_pitched_roof(_baker, _root, wing, wing_spec)
	_chimney_on_roof(wing, wing_spec, Vector2(-0.72, -0.45), 5.05, 0)
	_roof = "roof_shingle"
	_entry_hood(2.8, 3.03, 2.7)
	_steps(5.4, 1.5)
	# Pegged bracket, iron suspension and framed sign identify the inn.
	_beam(Vector3(3.7, 3.3, 2.8), Vector3(3.7, 3.3, 3.55), 0.13)
	_beam(Vector3(3.7, 2.94, 2.8), Vector3(3.7, 3.3, 3.38), 0.09)
	for x in [3.42, 3.98]:
		_box("iron", Vector3(0.035, 0.3, 0.035), Vector3(x, 3.13, 3.49))
	_box("timber", Vector3(1.05, 0.78, 0.14), Vector3(3.7, 2.65, 3.49))
	_box("cloth_red", Vector3(0.85, 0.57, 0.025), Vector3(3.7, 2.65, 3.58))
	_box("plank", Vector3(0.32, 0.33, 0.035), Vector3(3.7, 2.65, 3.6))


func _hall() -> void:
	_wall = "stone"
	_roof = "roof_slate"
	_foundation(9.4, 5.4)
	# Tall civic bays with a double door; pitched roof runs along the nave.
	var front := _at(Vector3(0.0, 0.0, 2.7))
	var openings: Array[Dictionary] = [
		_opening(0.0, PLINTH, 2.2, 2.75, "door"),
		_opening(-3.35, 1.38, 0.92, 2.05),
		_opening(3.35, 1.38, 0.92, 2.05)
	]
	_facade(9.4, PLINTH, 4.28, front, openings, true)
	_facade(
		9.4,
		PLINTH,
		4.28,
		_at(Vector3(0.0, 0.0, -2.7), PI),
		[
			_opening(-2.6, 1.38, 0.92, 2.05),
			_opening(0.0, 1.38, 0.92, 2.05),
			_opening(2.6, 1.38, 0.92, 2.05)
		],
		true
	)
	for side in [-1.0, 1.0]:
		_facade(
			5.4,
			PLINTH,
			4.28,
			_at(Vector3(side * 4.7, 0.0, 0.0), side * PI * 0.5),
			[_opening(-1.4, 1.38, 0.8, 2.05), _opening(1.4, 1.38, 0.8, 2.05)],
			true
		)
		for x in [-2.1, 2.1]:
			# Tapered buttresses are bonded into the stone bays, not pillars
			# pasted onto windows. Projection stays within the hall collider.
			_profile(
				"stone_dark",
				PackedVector2Array(
					[
						Vector2(-0.22, PLINTH),
						Vector2(0.22, PLINTH),
						Vector2(0.14, 3.95),
						Vector2(-0.14, 3.95)
					]
				),
				0.36,
				_at(Vector3(x, 0.0, side * 2.73))
			)
	# Nave roof spans the full 9.4 m nave and joins the belfry east wall (x = -3.925)
	# with a stepped stone saddle flashing collar around the tower intersection.
	var nave_r_frame := _at(Vector3.ZERO, PI * 0.5)
	var hall_spec := {
		"span": 5.4,
		"length": 9.4,
		"eave_y": 4.7,
		"rise": 2.48,
		"overhang_eave": 0.36,
		"overhang_front": 0.34,
		"overhang_back": 0.2,
		"gable_front": true,
		"gable_back": true,
		"roof_key": "roof_slate",
		"wall_key": "stone",
		"timbered": false,
		"bell_cast": 0.09,
		"seed_val": 71,
	}
	_roof_kit.build_pitched_roof(_baker, _root, nave_r_frame, hall_spec)
	var h_pitch := atan2(2.48, 2.7)
	for side in [-1.0, 1.0]:
		var b_flash := nave_r_frame * _at(Vector3(0.0, 7.18, -3.88), 0.0, -side * h_pitch)
		_box("stone_dark", Vector3(1.95, 0.16, 0.2), Vector3(side * 0.96, 0.15, 0.0), b_flash)
	for dz in [-1.4, 1.9]:
		_roof_kit.build_gable_dormer(_baker, _root, nave_r_frame, hall_spec, -1.0, dz, 1.02)
	_chimney_on_roof(nave_r_frame, hall_spec, Vector2(1.25, 2.35), 7.85, 1)
	_entry_hood(2.7, 3.6, 2.8)
	_steps(5.4, 2.2)
	_belfry()
	for side in [-1.0, 1.0]:
		_box("timber", Vector3(0.85, 0.1, 0.16), Vector3(side * 2.1, 4.06, 2.85))
		_profile(
			"cloth_red",
			PackedVector2Array(
				[
					Vector2(-0.34, 0.0),
					Vector2(0.34, 0.0),
					Vector2(0.34, -1.7),
					Vector2(0.0, -1.95),
					Vector2(-0.34, -1.7)
				]
			),
			0.045,
			_at(Vector3(side * 2.1, 3.98, 2.94))
		)


func _storey(
	width: float,
	depth: float,
	bottom: float,
	height: float,
	entrance: bool,
	frame: Transform3D = Transform3D.IDENTITY,
	door_width: float = 1.0,
	joined_face: String = ""
) -> void:
	var front: Array[Dictionary] = []
	var rear: Array[Dictionary] = []
	var window_h := 0.88 if height < 2.3 else 1.12
	var window_bottom := bottom + 0.76
	var bay_x := width * 0.315
	for x in [-bay_x, bay_x]:
		front.append(_opening(x, window_bottom, 0.66, window_h))
		rear.append(_opening(x, window_bottom, 0.66, window_h))
	if entrance:
		front.append(_opening(0.0, PLINTH, door_width, 2.05, "door"))
	else:
		front.append(_opening(0.0, window_bottom, 0.66, window_h))
	if joined_face == "+Z":
		front.clear()
	_facade(width, bottom, height, frame * _at(Vector3(0.0, 0.0, depth * 0.5)), front)
	_facade(width, bottom, height, frame * _at(Vector3(0.0, 0.0, -depth * 0.5), PI), rear)
	for side in [-1.0, 1.0]:
		var side_openings: Array[Dictionary] = [_opening(0.0, window_bottom, 0.72, window_h)]
		if side < 0.0 and joined_face == "-X":
			side_openings.clear()
		_facade(
			depth,
			bottom,
			height,
			frame * _at(Vector3(side * width * 0.5, 0.0, 0.0), side * PI * 0.5),
			side_openings
		)
	# Floor decks close the shell inside the wall returns. The facade owns
	# its exposed sill, avoiding a coplanar deck edge across plaster/door.
	_box(
		"timber", Vector3(width - 0.44, 0.16, depth - 0.44), Vector3(0.0, bottom + 0.04, 0.0), frame
	)


func _opening(x: float, bottom: float, width: float, height: float, kind := "window") -> Dictionary:
	return {"rect": Rect2(x - width * 0.5, bottom, width, height), "kind": kind}


## A panelized, 22 cm thick wall with genuinely empty aperture rectangles.
## Splitting at every aperture edge gives solid jamb returns and lintel soffits
## without coplanar overlays or glass buried in a full plaster volume.
func _facade(
	width: float,
	bottom: float,
	height: float,
	frame: Transform3D,
	openings: Array[Dictionary],
	masonry: bool = false
) -> void:
	var xs: Array[float] = [-width * 0.5, width * 0.5]
	var ys: Array[float] = [bottom, bottom + height]
	for opening in openings:
		var rect: Rect2 = opening.rect
		xs.append(rect.position.x)
		xs.append(rect.end.x)
		ys.append(rect.position.y)
		ys.append(rect.end.y)
	xs.sort()
	ys.sort()
	for ix in xs.size() - 1:
		for iy in ys.size() - 1:
			var cell := Rect2(xs[ix], ys[iy], xs[ix + 1] - xs[ix], ys[iy + 1] - ys[iy])
			if cell.size.x < 0.001 or cell.size.y < 0.001:
				continue
			var empty := false
			for opening in openings:
				if opening.rect.has_point(cell.get_center()):
					empty = true
			if not empty:
				_box(
					_wall,
					Vector3(cell.size.x, cell.size.y, WALL_THICKNESS),
					Vector3(cell.get_center().x, cell.get_center().y, -WALL_THICKNESS * 0.5),
					frame
				)
	for opening in openings:
		_portal(opening.rect, opening.kind, frame, masonry)
	var timber_key := "stone_dark" if masonry else "timber"
	# Load-bearing corner posts and plates occupy the wall thickness.
	for x in [-width * 0.5 + 0.09, width * 0.5 - 0.09]:
		_box(
			timber_key, Vector3(0.2, height, 0.27), Vector3(x, bottom + height * 0.5, -0.06), frame
		)
	_box(timber_key, Vector3(width, 0.18, 0.28), Vector3(0.0, bottom + height - 0.09, -0.04), frame)
	for ix in xs.size() - 1:
		var mid := (xs[ix] + xs[ix + 1]) * 0.5
		var at_door := false
		for opening in openings:
			if opening.kind == "door" and opening.rect.has_point(Vector2(mid, bottom + 0.08)):
				at_door = true
		if not at_door and xs[ix + 1] - xs[ix] > 0.001:
			_box(
				timber_key,
				Vector3(xs[ix + 1] - xs[ix], 0.16, 0.28),
				Vector3(mid, bottom + 0.08, -0.04),
				frame
			)
	# Knee braces meet the head plate and end posts, away from openings.
	if not masonry:
		for side in [-1.0, 1.0]:
			_beam(
				Vector3(side * (width * 0.5 - 0.16), bottom + height - 0.73, -0.02),
				Vector3(side * (width * 0.5 - 0.73), bottom + height - 0.16, -0.02),
				0.115,
				frame
			)


func _portal(rect: Rect2, kind: String, frame: Transform3D, masonry: bool) -> void:
	var center := rect.get_center()
	var trim := "stone_dark" if masonry else "timber"
	var casing := 0.14 if kind == "door" else 0.09
	# Casing projects beyond the infill and continues through the wall reveal.
	for side in [-1.0, 1.0]:
		_box(
			trim,
			Vector3(casing, rect.size.y + casing, 0.32),
			Vector3(center.x + side * (rect.size.x + casing) * 0.5, center.y, -0.06),
			frame
		)
	_box(
		trim,
		Vector3(rect.size.x + casing * 2.0, casing, 0.32),
		Vector3(center.x, rect.end.y + casing * 0.5, -0.06),
		frame
	)
	_box(
		"stone",
		Vector3(rect.size.x + casing * 2.5, 0.12, 0.4),
		Vector3(center.x, rect.position.y, -0.015),
		frame
	)
	if kind == "door":
		# Planks lie 9 cm behind the wall face. Hardware remains inside the
		# casing, leaving an obvious reveal even from a grazing angle.
		var count := maxi(4, int(ceil(rect.size.x / 0.2)))
		for index in count:
			var pitch := rect.size.x / float(count)
			_box(
				"door",
				Vector3(pitch - 0.012, rect.size.y - 0.03, 0.08),
				Vector3(rect.position.x + pitch * (float(index) + 0.5), center.y, -0.13),
				frame,
				Color.WHITE.darkened(float(index % 3) * 0.025)
			)
		for y in [rect.position.y + 0.38, rect.end.y - 0.38]:
			_box(
				"iron", Vector3(rect.size.x * 0.78, 0.07, 0.035), Vector3(center.x, y, -0.07), frame
			)
		_box(
			"iron",
			Vector3(0.08, 0.15, 0.08),
			Vector3(center.x + rect.size.x * 0.28, center.y, -0.04),
			frame
		)
	else:
		_box(
			"window",
			Vector3(rect.size.x, rect.size.y, 0.04),
			Vector3(center.x, center.y, -0.15),
			frame
		)
		_box("timber", Vector3(0.045, rect.size.y, 0.06), Vector3(center.x, center.y, -0.1), frame)
		_box(
			"timber",
			Vector3(rect.size.x, 0.045, 0.06),
			Vector3(center.x, center.y + 0.1, -0.1),
			frame
		)
		# Open shutters fold into the reveal instead of covering adjacent bays.
		for side in [-1.0, 1.0]:
			var shutter := (
				frame
				* _at(
					Vector3(center.x + side * (rect.size.x * 0.5 - 0.035), center.y, -0.05),
					side * 0.38
				)
			)
			_box("plank", Vector3(0.065, rect.size.y - 0.08, 0.24), Vector3.ZERO, shutter)


func _foundation(width: float, depth: float, frame: Transform3D = Transform3D.IDENTITY) -> void:
	_box(
		"stone_dark",
		Vector3(width + 0.18, PLINTH, depth + 0.18),
		Vector3(0.0, PLINTH * 0.5, 0.0),
		frame
	)
	# Staggered bonded courses, recessed mortar, and a continuous dressed cap.
	for course in 2:
		for side in [-1.0, 1.0]:
			_course(
				width + 0.16,
				course,
				(
					frame
					* _at(
						Vector3(0.0, 0.0, side * (depth * 0.5 + 0.075)), PI if side < 0.0 else 0.0
					)
				)
			)
			_course(
				depth,
				course,
				frame * _at(Vector3(side * (width * 0.5 + 0.075), 0.0, 0.0), side * PI * 0.5)
			)
	_box("stone", Vector3(width + 0.2, 0.09, depth + 0.2), Vector3(0.0, PLINTH - 0.045, 0.0), frame)


func _course(length: float, course: int, frame: Transform3D) -> void:
	var cursor := -length * 0.5
	var first := true
	while cursor < length * 0.5 - 0.001:
		var size := minf(0.37 if first and course == 1 else 0.73, length * 0.5 - cursor)
		if length * 0.5 - cursor - size < 0.1:
			size = length * 0.5 - cursor
		_box(
			"stone",
			Vector3(size - 0.018, 0.17, 0.08),
			Vector3(cursor + size * 0.5, 0.105 + float(course) * 0.19, 0.0),
			frame,
			Color.WHITE.darkened(0.035 * float((course + int(cursor * 3.0)) % 3))
		)
		cursor += size
		first = false


## Separate gable walls and CLOSED chamfered roof sections delegated to
## `RoofArchitecture` with non-degenerate parameter clamping.
func _roof_pair(
	width: float,
	depth: float,
	top: float,
	rise: float,
	frame: Transform3D = Transform3D.IDENTITY,
	timbered: bool = true
) -> void:
	var spec := _roof_spec(width, depth, top, rise, timbered)
	_roof_kit.build_pitched_roof(_baker, _root, frame, spec)


func _entry_hood(face_z: float, top: float, width: float) -> void:
	_roof_kit.build_entry_hood(_baker, _root, Transform3D.IDENTITY, _roof, face_z, top, width)


func _steps(depth: float, width: float) -> void:
	_box("stone_dark", Vector3(width + 0.48, 0.14, 0.75), Vector3(0.0, 0.07, depth * 0.5 + 0.3))
	_box("stone", Vector3(width + 0.26, 0.28, 0.45), Vector3(0.0, 0.14, depth * 0.5 + 0.14))


func _chimney_on_roof(
	frame: Transform3D, parent_spec: Dictionary, pos: Vector2, top: float, crown_style: int = 0
) -> void:
	_roof_kit.build_chimney(_baker, _root, frame, parent_spec, pos, top, crown_style)


func _belfry() -> void:
	var frame := _at(Vector3(-5.4, 0.0, 0.0))
	_foundation(2.95, 2.95, frame)
	var saved_wall := _wall
	_wall = "stone_dark"
	for quarter in 4:
		var angle := float(quarter) * PI * 0.5
		var face := frame * _at(Vector3(sin(angle), 0.0, cos(angle)) * 1.475, angle)
		var b_openings: Array[Dictionary] = []
		if quarter != 1:
			b_openings.append(_opening(0.0, 4.35, 0.45, 1.25))
		_facade(2.95, PLINTH, 7.38, face, b_openings, true)
	_wall = saved_wall
	# Corner piers carry an open chamber ABOVE the nave ridge cap (7.63 m),
	# so the main roof never slices through the bell or its four openings.
	for x in [-1.27, 1.27]:
		for z in [-1.27, 1.27]:
			_box("stone", Vector3(0.41, 1.6, 0.41), Vector3(x, 8.6, z), frame)
	for y in [1.0, 3.3, 7.75, 9.4]:
		_box("stone", Vector3(3.12, 0.2, 3.12), Vector3(0.0, y, 0.0), frame)
	_box("timber", Vector3(2.6, 0.22, 0.22), Vector3(0.0, 9.13, 0.0), frame)
	_box("iron", Vector3(0.08, 0.48, 0.08), Vector3(0.0, 8.83, 0.0), frame)
	_baker.add_cylinder(
		"iron",
		0.22,
		0.46,
		0.6,
		10,
		_root * frame * _at(Vector3(0.0, 8.33, 0.0)),
		Color(1.4, 1.16, 0.75)
	)
	_roof_kit.build_belfry_spire(_baker, _root, frame, 9.5, 2.48, 2.65)


func _box(
	key: String,
	size: Vector3,
	position: Vector3,
	frame: Transform3D = Transform3D.IDENTITY,
	tint: Color = Color.WHITE
) -> void:
	_baker.add_box(key, size, _root * frame * _at(position), tint, 0.035)


func _profile(key: String, points: PackedVector2Array, depth: float, frame: Transform3D) -> void:
	_baker.add_profile(key, points, depth, _root * frame)


func _beam(
	a: Vector3, b: Vector3, thickness: float, frame: Transform3D = Transform3D.IDENTITY
) -> void:
	var along := (b - a).normalized()
	var reference := Vector3.FORWARD if absf(along.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var across := along.cross(reference).normalized()
	var basis := Basis(across, along, across.cross(along))
	_baker.add_box(
		"timber",
		Vector3(thickness, a.distance_to(b), thickness),
		_root * frame * Transform3D(basis, (a + b) * 0.5),
		Color.WHITE,
		0.035
	)


func _at(position: Vector3, yaw: float = 0.0, roll: float = 0.0) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(0.0, yaw, roll)), position)
