class_name NpcVisualFactory
extends RefCounted
## Builds shared procedural 3D character rigs, profession outfits and activity
## poses for [NpcPresenter].
##
## Architectural note: EVERAFTER is a text-only repository with no imported
## `.glb`/`.fbx` skeletal meshes or keyframe `AnimationPlayer` clips. Every
## villager is assembled from shared low-poly primitive meshes and shared
## `StandardMaterial3D` instances, scaled to match the village architecture
## (~1.72 m tall against 1.85 m house doorways and 1.80 m player height).
##
## Movement and activity feedback are procedural: articulated pivots (`LeftLeg`,
## `RightLeg`, `TorsoPivot`, `LeftArm`, `RightArm`, `HeadPivot`) interpolate
## smoothly between `WALKING`, `WORKING`, `EATING`, `SOCIALIZING`, `RESTING`,
## `SLEEPING`, `IDLE` and `BLOCKED` postures without claiming skeletal clips.

const BASE_HEIGHT := 1.72
const HIP_HEIGHT := 0.72

const GARMENT_APRON_FULL := "apron_full"
const GARMENT_FIELD_TUNIC := "field_tunic"
const GARMENT_HOODED_CLOAK := "hooded_cloak"
const GARMENT_FISHER_VEST := "fisher_vest"
const GARMENT_LEATHER_HARNESS := "leather_harness"
const GARMENT_ARTISAN_SMOCK := "artisan_smock"
const GARMENT_CIVIC_MANTLE := "civic_mantle"

const HEADGEAR_STRAW_HAT := "straw_hat"
const HEADGEAR_CHEF_TOQUE := "chef_toque"
const HEADGEAR_KERCHIEF := "kerchief"
const HEADGEAR_PEAKED_HOOD := "peaked_hood"
const HEADGEAR_ANGLER_HAT := "angler_hat"
const HEADGEAR_WOOL_CAP := "wool_cap"
const HEADGEAR_WORK_BAND := "work_band"
const HEADGEAR_ARTISAN_BERET := "artisan_beret"
const HEADGEAR_MERCHANT_CHAPERON := "merchant_chaperon"
const HEADGEAR_SCHOLAR_CAP := "scholar_cap"

const ACCESSORY_SEED_SATCHEL := "seed_satchel"
const ACCESSORY_WICKER_BASKET := "wicker_basket"
const ACCESSORY_SHEPHERD_PACK := "shepherd_pack"
const ACCESSORY_CREEL_PACK := "creel_pack"
const ACCESSORY_INN_POUCH := "inn_pouch"
const ACCESSORY_TIMBER_PACK := "timber_pack"
const ACCESSORY_STONE_PACK := "stone_pack"
const ACCESSORY_POTTERY_PACK := "pottery_pack"
const ACCESSORY_WEAVER_PACK := "weaver_pack"
const ACCESSORY_LEDGER_POUCH := "ledger_pouch"

const PROFESSION_PROFILES := {
	"farmer": {
		"garment": GARMENT_FIELD_TUNIC,
		"headgear": HEADGEAR_STRAW_HAT,
		"accessory": ACCESSORY_SEED_SATCHEL,
		"trim": Color(0.84, 0.74, 0.44),
	},
	"farmhand": {
		"garment": GARMENT_FIELD_TUNIC,
		"headgear": HEADGEAR_STRAW_HAT,
		"accessory": ACCESSORY_SEED_SATCHEL,
		"trim": Color(0.76, 0.66, 0.38),
	},
	"gardener": {
		"garment": GARMENT_FIELD_TUNIC,
		"headgear": HEADGEAR_STRAW_HAT,
		"accessory": ACCESSORY_SEED_SATCHEL,
		"trim": Color(0.86, 0.78, 0.52),
	},
	"forager": {
		"garment": GARMENT_HOODED_CLOAK,
		"headgear": HEADGEAR_PEAKED_HOOD,
		"accessory": ACCESSORY_WICKER_BASKET,
		"trim": Color(0.32, 0.46, 0.28),
	},
	"shepherd": {
		"garment": GARMENT_HOODED_CLOAK,
		"headgear": HEADGEAR_PEAKED_HOOD,
		"accessory": ACCESSORY_SHEPHERD_PACK,
		"trim": Color(0.78, 0.74, 0.64),
	},
	"healer": {
		"garment": GARMENT_HOODED_CLOAK,
		"headgear": HEADGEAR_PEAKED_HOOD,
		"accessory": ACCESSORY_WICKER_BASKET,
		"trim": Color(0.82, 0.86, 0.78),
	},
	"fisher": {
		"garment": GARMENT_FISHER_VEST,
		"headgear": HEADGEAR_ANGLER_HAT,
		"accessory": ACCESSORY_CREEL_PACK,
		"trim": Color(0.24, 0.34, 0.40),
	},
	"innkeeper": {
		"garment": GARMENT_APRON_FULL,
		"headgear": HEADGEAR_KERCHIEF,
		"accessory": ACCESSORY_INN_POUCH,
		"trim": Color(0.92, 0.86, 0.74),
	},
	"baker": {
		"garment": GARMENT_APRON_FULL,
		"headgear": HEADGEAR_CHEF_TOQUE,
		"accessory": ACCESSORY_INN_POUCH,
		"trim": Color(0.95, 0.91, 0.82),
	},
	"cook": {
		"garment": GARMENT_APRON_FULL,
		"headgear": HEADGEAR_CHEF_TOQUE,
		"accessory": ACCESSORY_INN_POUCH,
		"trim": Color(0.92, 0.87, 0.76),
	},
	"woodcutter": {
		"garment": GARMENT_LEATHER_HARNESS,
		"headgear": HEADGEAR_WOOL_CAP,
		"accessory": ACCESSORY_TIMBER_PACK,
		"trim": Color(0.36, 0.22, 0.13),
	},
	"carpenter": {
		"garment": GARMENT_LEATHER_HARNESS,
		"headgear": HEADGEAR_WOOL_CAP,
		"accessory": ACCESSORY_TIMBER_PACK,
		"trim": Color(0.44, 0.28, 0.16),
	},
	"quarry_worker": {
		"garment": GARMENT_LEATHER_HARNESS,
		"headgear": HEADGEAR_WORK_BAND,
		"accessory": ACCESSORY_STONE_PACK,
		"trim": Color(0.38, 0.35, 0.32),
	},
	"miner": {
		"garment": GARMENT_LEATHER_HARNESS,
		"headgear": HEADGEAR_WORK_BAND,
		"accessory": ACCESSORY_STONE_PACK,
		"trim": Color(0.34, 0.32, 0.30),
	},
	"blacksmith": {
		"garment": GARMENT_LEATHER_HARNESS,
		"headgear": HEADGEAR_WORK_BAND,
		"accessory": ACCESSORY_STONE_PACK,
		"trim": Color(0.24, 0.22, 0.24),
	},
	"potter": {
		"garment": GARMENT_ARTISAN_SMOCK,
		"headgear": HEADGEAR_ARTISAN_BERET,
		"accessory": ACCESSORY_POTTERY_PACK,
		"trim": Color(0.78, 0.46, 0.28),
	},
	"weaver": {
		"garment": GARMENT_ARTISAN_SMOCK,
		"headgear": HEADGEAR_ARTISAN_BERET,
		"accessory": ACCESSORY_WEAVER_PACK,
		"trim": Color(0.86, 0.74, 0.48),
	},
	"merchant": {
		"garment": GARMENT_CIVIC_MANTLE,
		"headgear": HEADGEAR_MERCHANT_CHAPERON,
		"accessory": ACCESSORY_LEDGER_POUCH,
		"trim": Color(0.68, 0.19, 0.16),
	},
	"clerk": {
		"garment": GARMENT_CIVIC_MANTLE,
		"headgear": HEADGEAR_SCHOLAR_CAP,
		"accessory": ACCESSORY_LEDGER_POUCH,
		"trim": Color(0.24, 0.32, 0.52),
	},
	"archivist": {
		"garment": GARMENT_CIVIC_MANTLE,
		"headgear": HEADGEAR_SCHOLAR_CAP,
		"accessory": ACCESSORY_LEDGER_POUCH,
		"trim": Color(0.32, 0.26, 0.48),
	},
}

var _meshes: Dictionary = {}
var _materials: Dictionary = {}
var _skin_materials: Array[StandardMaterial3D] = []
var _hair_materials: Array[StandardMaterial3D] = []


func _init() -> void:
	_build_shared_materials()
	_build_shared_meshes()


## Returns the visual profile dictionary for a profession id, falling back to a
## sensible villager tunic when an unknown id is passed.
static func profile_for_profession(profession_id: String) -> Dictionary:
	if PROFESSION_PROFILES.has(profession_id):
		return PROFESSION_PROFILES[profession_id]
	return {
		"garment": GARMENT_FIELD_TUNIC,
		"headgear": HEADGEAR_WOOL_CAP,
		"accessory": ACCESSORY_SEED_SATCHEL,
		"trim": Color(0.78, 0.72, 0.58),
	}


## Deterministic stature scale around 1.0 so villagers have subtle individual
## build without floating or clipping through 1.85 m house doors.
static func stature_scale_for(npc_id: String, age: int) -> Vector3:
	var h := absi(npc_id.hash())
	var height_scale := 0.96 + float(h % 9) * 0.01
	if age >= 55:
		height_scale -= 0.015
	var width_scale := 0.95 + float((h / 11) % 11) * 0.01
	return Vector3(width_scale, height_scale, width_scale)


## Computes target limb angles and body offset for a given activity and phase.
## Returns a Dictionary of floats used by NpcPresenter to interpolate smoothly.
static func compute_pose_targets(
	activity: int, phase: float, move_ratio: float
) -> Dictionary:
	var pose := {
		"bob_y": 0.0,
		"torso_pitch": 0.0,
		"torso_roll": 0.0,
		"torso_yaw": 0.0,
		"head_pitch": 0.0,
		"head_yaw": 0.0,
		"left_leg_pitch": 0.0,
		"right_leg_pitch": 0.0,
		"left_arm_pitch": 0.0,
		"right_arm_pitch": 0.0,
		"left_arm_roll": 0.06,
		"right_arm_roll": -0.06,
	}
	if move_ratio > 0.08 or activity == NpcRecord.Activity.WALKING:
		var stride := clampf(maxf(move_ratio, 0.65), 0.35, 1.15)
		var swing := sin(phase) * 0.54 * stride
		pose["bob_y"] = absf(sin(phase)) * 0.034 * stride
		pose["torso_pitch"] = -0.055 * stride
		pose["torso_roll"] = cos(phase) * 0.035 * stride
		pose["torso_yaw"] = -sin(phase) * 0.06 * stride
		pose["head_pitch"] = 0.03 * stride
		pose["left_leg_pitch"] = swing
		pose["right_leg_pitch"] = -swing
		pose["left_arm_pitch"] = -swing * 0.82
		pose["right_arm_pitch"] = swing * 0.82
		return pose
	match activity:
		NpcRecord.Activity.WORKING:
			var cycle := sin(phase * 1.35)
			var secondary := cos(phase * 0.68)
			pose["bob_y"] = absf(cycle) * 0.015
			pose["torso_pitch"] = -0.14 + cycle * 0.05
			pose["torso_yaw"] = secondary * 0.08
			pose["head_pitch"] = -0.16 + cycle * 0.04
			pose["left_arm_pitch"] = -0.52 + secondary * 0.22
			pose["right_arm_pitch"] = -0.68 + cycle * 0.38
			pose["left_arm_roll"] = 0.12
			pose["right_arm_roll"] = -0.14
		NpcRecord.Activity.EATING:
			var lift := maxf(0.0, sin(phase * 0.9))
			pose["torso_pitch"] = -0.05
			pose["head_pitch"] = -0.08 + lift * 0.10
			pose["left_arm_pitch"] = -0.42
			pose["right_arm_pitch"] = -0.50 - lift * 0.52
			pose["right_arm_roll"] = -0.18
		NpcRecord.Activity.SOCIALIZING:
			var gesture := sin(phase * 0.85)
			var nod := cos(phase * 1.1)
			pose["torso_yaw"] = gesture * 0.08
			pose["head_yaw"] = -gesture * 0.14
			pose["head_pitch"] = nod * 0.06
			pose["left_arm_pitch"] = -0.28 + maxf(0.0, gesture) * -0.28
			pose["right_arm_pitch"] = -0.28 + maxf(0.0, -gesture) * -0.28
			pose["left_arm_roll"] = 0.14
			pose["right_arm_roll"] = -0.14
		NpcRecord.Activity.RESTING:
			var breath := sin(phase * 0.45)
			pose["bob_y"] = -0.03 + breath * 0.006
			pose["torso_pitch"] = -0.06 + breath * 0.015
			pose["head_pitch"] = -0.10 + breath * 0.02
			pose["left_arm_pitch"] = -0.12
			pose["right_arm_pitch"] = -0.12
		NpcRecord.Activity.SLEEPING:
			var sleep_breath := sin(phase * 0.32)
			pose["bob_y"] = -0.05 + sleep_breath * 0.005
			pose["torso_pitch"] = -0.10 + sleep_breath * 0.012
			pose["head_pitch"] = -0.26 + sleep_breath * 0.015
			pose["left_arm_pitch"] = -0.08
			pose["right_arm_pitch"] = -0.08
			pose["left_arm_roll"] = 0.03
			pose["right_arm_roll"] = -0.03
		NpcRecord.Activity.BLOCKED:
			var scan := sin(phase * 1.2)
			pose["head_yaw"] = scan * 0.32
			pose["torso_yaw"] = scan * 0.10
			pose["left_arm_roll"] = 0.15
			pose["right_arm_roll"] = -0.15
		_:
			var idle_breath := sin(phase * 0.55)
			pose["bob_y"] = idle_breath * 0.005
			pose["torso_pitch"] = idle_breath * 0.01
			pose["head_yaw"] = sin(phase * 0.28) * 0.08
	return pose


## Populates [param body] (`NpcView_<id>`) with the articulated `BodyRig`,
## profession outfit, overhead labels and selection ring.
func populate_character_view(
	body: StaticBody3D, record: NpcRecord, is_selected: bool
) -> void:
	var profile := profile_for_profession(record.profession_id)
	var primary_mat := _tunic_material(record.profession_id, record.profession_color)
	var trim_color: Color = profile.get("trim", Color(0.82, 0.74, 0.58))
	var trim_mat := _trim_material(record.profession_id, trim_color)
	var skin_mat := _skin_for(record.id)
	var hair_mat := _hair_for(record.id, record.age)

	var rig := Node3D.new()
	rig.name = "BodyRig"
	rig.scale = stature_scale_for(record.id, record.age)
	body.add_child(rig)

	_build_legs(rig, profile)
	var torso_pivot := _build_torso(rig, primary_mat, trim_mat, profile)
	_build_arms(torso_pivot, primary_mat, trim_mat, skin_mat, profile)
	_build_head(torso_pivot, skin_mat, hair_mat, trim_mat, record, profile)
	_build_labels(body, record, is_selected)
	_build_selection_indicators(body, is_selected)


func get_material_count() -> int:
	return _materials.size() + _skin_materials.size() + _hair_materials.size()


func get_mesh_count() -> int:
	return _meshes.size()


# --- rig construction --------------------------------------------------------


func _build_legs(rig: Node3D, profile: Dictionary) -> void:
	var boot_mat := _materials["boot_dark"] as StandardMaterial3D
	var hose_mat := _materials["hose_cloth"] as StandardMaterial3D
	if String(profile.get("garment", "")) == GARMENT_FISHER_VEST:
		boot_mat = _materials["leather_dark"] as StandardMaterial3D
	for side_index in 2:
		var side := -1.0 if side_index == 0 else 1.0
		var leg := Node3D.new()
		leg.name = "LeftLeg" if side < 0.0 else "RightLeg"
		leg.position = Vector3(side * 0.105, HIP_HEIGHT, 0.0)
		var thigh := _mesh_node("Thigh", "leg_upper", hose_mat, Vector3(0.0, -0.20, 0.0))
		leg.add_child(thigh)
		var boot := _mesh_node("Boot", "leg_boot", boot_mat, Vector3(0.0, -0.52, 0.0))
		leg.add_child(boot)
		var toe := _mesh_node(
			"BootToe", "boot_toe", boot_mat, Vector3(0.0, -0.67, -0.055), false
		)
		leg.add_child(toe)
		rig.add_child(leg)


func _build_torso(
	rig: Node3D,
	primary_mat: StandardMaterial3D,
	trim_mat: StandardMaterial3D,
	profile: Dictionary
) -> Node3D:
	var torso_pivot := Node3D.new()
	torso_pivot.name = "TorsoPivot"
	torso_pivot.position = Vector3(0.0, HIP_HEIGHT, 0.0)
	rig.add_child(torso_pivot)

	var skirt := _mesh_node("TunicSkirt", "tunic_skirt", primary_mat, Vector3(0.0, 0.04, 0.0))
	torso_pivot.add_child(skirt)

	var torso := _mesh_node("Torso", "torso_upper", primary_mat, Vector3(0.0, 0.37, 0.0))
	torso_pivot.add_child(torso)

	var collar := _mesh_node(
		"Collar", "collar_ring", trim_mat, Vector3(0.0, 0.59, 0.0), false
	)
	torso_pivot.add_child(collar)

	var belt := _mesh_node(
		"Belt", "belt_ring", _materials["leather_dark"], Vector3(0.0, 0.16, 0.0), false
	)
	torso_pivot.add_child(belt)

	var buckle := _mesh_node(
		"BeltBuckle", "buckle_box", _materials["brass"], Vector3(0.0, 0.16, -0.225), false
	)
	torso_pivot.add_child(buckle)

	var detail := Node3D.new()
	detail.name = "OutfitDetail"
	torso_pivot.add_child(detail)
	_build_garment_detail(detail, trim_mat, profile)
	_build_accessory_detail(detail, trim_mat, profile)
	return torso_pivot


func _build_arms(
	torso_pivot: Node3D,
	primary_mat: StandardMaterial3D,
	trim_mat: StandardMaterial3D,
	skin_mat: StandardMaterial3D,
	profile: Dictionary
) -> void:
	var garment := String(profile.get("garment", ""))
	var rolled_sleeves := garment in [
		GARMENT_APRON_FULL, GARMENT_FIELD_TUNIC, GARMENT_LEATHER_HARNESS
	]
	var sleeve_mat := primary_mat
	if garment == GARMENT_APRON_FULL:
		sleeve_mat = _materials["linen_cream"] as StandardMaterial3D
	var forearm_mat := skin_mat if rolled_sleeves else trim_mat
	for side_index in 2:
		var side := -1.0 if side_index == 0 else 1.0
		var arm := Node3D.new()
		arm.name = "LeftArm" if side < 0.0 else "RightArm"
		arm.position = Vector3(side * 0.245, 0.55, 0.0)
		var upper := _mesh_node(
			"Sleeve", "arm_upper", sleeve_mat, Vector3(0.0, -0.12, 0.0)
		)
		arm.add_child(upper)
		var lower := _mesh_node(
			"Forearm", "arm_lower", forearm_mat, Vector3(0.0, -0.30, 0.0), false
		)
		arm.add_child(lower)
		var hand := _mesh_node(
			"Hand", "hand_sphere", skin_mat, Vector3(0.0, -0.42, 0.0), false
		)
		arm.add_child(hand)
		torso_pivot.add_child(arm)


func _build_head(
	torso_pivot: Node3D,
	skin_mat: StandardMaterial3D,
	hair_mat: StandardMaterial3D,
	trim_mat: StandardMaterial3D,
	record: NpcRecord,
	profile: Dictionary
) -> void:
	var head_pivot := Node3D.new()
	head_pivot.name = "HeadPivot"
	head_pivot.position = Vector3(0.0, 0.62, 0.0)
	torso_pivot.add_child(head_pivot)

	head_pivot.add_child(
		_mesh_node("Neck", "neck_cyl", skin_mat, Vector3(0.0, 0.04, 0.0), false)
	)
	head_pivot.add_child(
		_mesh_node("Head", "head_sphere", skin_mat, Vector3(0.0, 0.19, 0.0))
	)
	head_pivot.add_child(
		_mesh_node("Nose", "nose_box", skin_mat, Vector3(0.0, 0.185, -0.152), false)
	)
	for side in [-1.0, 1.0]:
		var eye_name := "LeftEye" if side < 0.0 else "RightEye"
		head_pivot.add_child(
			_mesh_node(
				eye_name,
				"eye_dot",
				_materials["eye_dark"],
				Vector3(side * 0.055, 0.205, -0.142),
				false
			)
		)

	var hair := _mesh_node("Hair", "hair_cap", hair_mat, Vector3(0.0, 0.255, 0.02), false)
	head_pivot.add_child(hair)
	var hair_back := _mesh_node(
		"HairBack", "hair_nape", hair_mat, Vector3(0.0, 0.16, 0.105), false
	)
	head_pivot.add_child(hair_back)
	if absi(record.id.hash()) % 2 == 1:
		head_pivot.add_child(
			_mesh_node("HairBun", "hair_bun", hair_mat, Vector3(0.0, 0.18, 0.175), false)
		)

	var headgear := Node3D.new()
	headgear.name = "Headgear"
	head_pivot.add_child(headgear)
	_build_headgear_detail(
		headgear, String(profile.get("headgear", "")), trim_mat
	)


func _build_garment_detail(
	detail: Node3D, trim_mat: StandardMaterial3D, profile: Dictionary
) -> void:
	var garment := String(profile.get("garment", ""))
	match garment:
		GARMENT_APRON_FULL:
			var linen := _materials["linen_cream"] as StandardMaterial3D
			detail.add_child(
				_mesh_node("ApronBib", "apron_bib", linen, Vector3(0.0, 0.39, -0.195), false)
			)
			detail.add_child(
				_mesh_node("ApronSkirt", "apron_skirt", linen, Vector3(0.0, 0.05, -0.215), false)
			)
		GARMENT_FIELD_TUNIC:
			detail.add_child(
				_mesh_node("ChestBib", "apron_bib", trim_mat, Vector3(0.0, 0.42, -0.192), false)
			)
		GARMENT_HOODED_CLOAK:
			detail.add_child(
				_mesh_node("ShoulderCape", "mantle_cape", trim_mat, Vector3(0.0, 0.48, 0.02), false)
			)
		GARMENT_FISHER_VEST:
			var vest_mat := _materials["slate_vest"] as StandardMaterial3D
			detail.add_child(
				_mesh_node("WorkVest", "vest_wrap", vest_mat, Vector3(0.0, 0.38, 0.0), false)
			)
		GARMENT_LEATHER_HARNESS:
			var leather := _materials["leather_warm"] as StandardMaterial3D
			detail.add_child(
				_mesh_node("LeatherVest", "vest_wrap", leather, Vector3(0.0, 0.38, 0.0), false)
			)
		GARMENT_ARTISAN_SMOCK:
			detail.add_child(
				_mesh_node("ArtisanTabard", "apron_skirt", trim_mat, Vector3(0.0, 0.06, -0.215), false)
			)
			detail.add_child(
				_mesh_node("ArtisanBib", "apron_bib", trim_mat, Vector3(0.0, 0.40, -0.195), false)
			)
		GARMENT_CIVIC_MANTLE:
			detail.add_child(
				_mesh_node("CivicMantle", "mantle_cape", trim_mat, Vector3(0.0, 0.50, 0.0), false)
			)
			detail.add_child(
				_mesh_node(
					"BrassBrooch",
					"brooch_disc",
					_materials["brass"],
					Vector3(0.0, 0.52, -0.215),
					false
				)
			)


func _build_headgear_detail(
	headgear: Node3D, style: String, trim_mat: StandardMaterial3D
) -> void:
	match style:
		HEADGEAR_STRAW_HAT:
			var straw := _materials["straw_gold"] as StandardMaterial3D
			headgear.add_child(
				_mesh_node("HatBrim", "straw_brim", straw, Vector3(0.0, 0.30, 0.0), false)
			)
			headgear.add_child(
				_mesh_node("HatCrown", "straw_crown", straw, Vector3(0.0, 0.36, 0.0), false)
			)
			headgear.add_child(
				_mesh_node("HatBand", "hat_band", trim_mat, Vector3(0.0, 0.32, 0.0), false)
			)
		HEADGEAR_CHEF_TOQUE:
			var linen := _materials["linen_cream"] as StandardMaterial3D
			headgear.add_child(
				_mesh_node("ToqueBand", "straw_crown", linen, Vector3(0.0, 0.33, 0.0), false)
			)
			headgear.add_child(
				_mesh_node("ToquePuff", "toque_puff", linen, Vector3(0.0, 0.42, 0.0), false)
			)
		HEADGEAR_KERCHIEF:
			headgear.add_child(
				_mesh_node(
					"Kerchief",
					"kerchief_cap",
					_materials["linen_cream"],
					Vector3(0.0, 0.28, 0.02),
					false
				)
			)
		HEADGEAR_PEAKED_HOOD:
			headgear.add_child(
				_mesh_node("PeakedHood", "hood_cone", trim_mat, Vector3(0.0, 0.33, 0.03), false)
			)
		HEADGEAR_ANGLER_HAT:
			var slate := _materials["slate_vest"] as StandardMaterial3D
			headgear.add_child(
				_mesh_node("AnglerBrim", "angler_brim", slate, Vector3(0.0, 0.29, 0.0), false)
			)
			headgear.add_child(
				_mesh_node("AnglerCrown", "straw_crown", slate, Vector3(0.0, 0.35, 0.0), false)
			)
		HEADGEAR_WOOL_CAP:
			headgear.add_child(
				_mesh_node(
					"WoolCap",
					"wool_beanie",
					_materials["cloth_rust"],
					Vector3(0.0, 0.31, 0.01),
					false
				)
			)
		HEADGEAR_WORK_BAND:
			headgear.add_child(
				_mesh_node(
					"WorkBand",
					"hat_band",
					_materials["leather_dark"],
					Vector3(0.0, 0.26, 0.0),
					false
				)
			)
		HEADGEAR_ARTISAN_BERET:
			headgear.add_child(
				_mesh_node("ArtisanBeret", "beret_disc", trim_mat, Vector3(0.02, 0.32, 0.0), false)
			)
		HEADGEAR_MERCHANT_CHAPERON:
			headgear.add_child(
				_mesh_node("Chaperon", "beret_disc", trim_mat, Vector3(0.0, 0.33, 0.0), false)
			)
			headgear.add_child(
				_mesh_node(
					"ChaperonPin",
					"brooch_disc",
					_materials["brass"],
					Vector3(0.08, 0.33, -0.14),
					false
				)
			)
		HEADGEAR_SCHOLAR_CAP:
			headgear.add_child(
				_mesh_node("ScholarCap", "scholar_top", trim_mat, Vector3(0.0, 0.33, 0.0), false)
			)


func _build_accessory_detail(
	detail: Node3D, trim_mat: StandardMaterial3D, profile: Dictionary
) -> void:
	var accessory := String(profile.get("accessory", ""))
	var leather := _materials["leather_warm"] as StandardMaterial3D
	var wood := _materials["wood_pack"] as StandardMaterial3D
	match accessory:
		ACCESSORY_SEED_SATCHEL:
			detail.add_child(
				_mesh_node("HipSatchel", "hip_pouch", leather, Vector3(0.22, 0.10, 0.04), false)
			)
		ACCESSORY_WICKER_BASKET:
			detail.add_child(
				_mesh_node("BackBasket", "wicker_basket", wood, Vector3(0.0, 0.36, 0.24), false)
			)
		ACCESSORY_SHEPHERD_PACK:
			detail.add_child(
				_mesh_node("Bedroll", "pack_roll", trim_mat, Vector3(0.0, 0.42, 0.22), false)
			)
		ACCESSORY_CREEL_PACK:
			detail.add_child(
				_mesh_node("FishCreel", "hip_pouch", wood, Vector3(-0.22, 0.12, 0.08), false)
			)
		ACCESSORY_INN_POUCH:
			detail.add_child(
				_mesh_node(
					"SideTowel",
					"towel_strip",
					_materials["linen_cream"],
					Vector3(0.21, 0.04, -0.06),
					false
				)
			)
		ACCESSORY_TIMBER_PACK:
			detail.add_child(
				_mesh_node("TimberPack", "pack_box", wood, Vector3(0.0, 0.36, 0.23), false)
			)
		ACCESSORY_STONE_PACK:
			detail.add_child(
				_mesh_node(
					"StonePack",
					"pack_box",
					_materials["stone_pack"],
					Vector3(0.0, 0.35, 0.23),
					false
				)
			)
		ACCESSORY_POTTERY_PACK:
			detail.add_child(
				_mesh_node(
					"PotteryJar",
					"jar_cyl",
					_materials["clay_terracotta"],
					Vector3(0.22, 0.12, 0.06),
					false
				)
			)
		ACCESSORY_WEAVER_PACK:
			detail.add_child(
				_mesh_node("ClothRoll", "pack_roll", trim_mat, Vector3(-0.22, 0.12, 0.05), false)
			)
		ACCESSORY_LEDGER_POUCH:
			detail.add_child(
				_mesh_node("LedgerCase", "ledger_box", leather, Vector3(-0.22, 0.10, -0.02), false)
			)
			detail.add_child(
				_mesh_node(
					"CoinPurse",
					"hand_sphere",
					_materials["brass"],
					Vector3(0.20, 0.12, -0.08),
					false
				)
			)


func _build_labels(body: StaticBody3D, record: NpcRecord, is_selected: bool) -> void:
	var label := Label3D.new()
	label.name = "NameLabel"
	label.text = record.display_name
	label.font_size = 34
	label.pixel_size = 0.0024
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.outline_size = 6
	label.outline_modulate = Color(0.06, 0.05, 0.04, 0.92)
	label.modulate = (
		Color(1.0, 0.92, 0.62, 1.0) if is_selected else Color(0.95, 0.91, 0.82, 0.94)
	)
	label.position.y = BASE_HEIGHT + 0.34
	body.add_child(label)

	var role_label := Label3D.new()
	role_label.name = "RoleLabel"
	role_label.text = "%s · %s" % [record.profession_label, record.activity_label()]
	role_label.font_size = 24
	role_label.pixel_size = 0.0022
	role_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	role_label.no_depth_test = false
	role_label.outline_size = 5
	role_label.outline_modulate = Color(0.05, 0.04, 0.03, 0.92)
	role_label.modulate = Color(0.92, 0.84, 0.64, 0.95)
	role_label.position.y = BASE_HEIGHT + 0.20
	role_label.visible = is_selected
	body.add_child(role_label)


func _build_selection_indicators(body: StaticBody3D, is_selected: bool) -> void:
	var ring := MeshInstance3D.new()
	ring.name = "SelectedRing"
	ring.mesh = _meshes["select_torus"] as Mesh
	ring.material_override = _materials["select_gold"] as StandardMaterial3D
	ring.position.y = 0.03
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = is_selected
	var inner := MeshInstance3D.new()
	inner.name = "InnerRing"
	inner.mesh = _meshes["select_inner_torus"] as Mesh
	inner.material_override = _materials["select_amber"] as StandardMaterial3D
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.add_child(inner)
	var beacon := MeshInstance3D.new()
	beacon.name = "SelectionBeacon"
	beacon.mesh = _meshes["select_beacon"] as Mesh
	beacon.material_override = _materials["select_gold"] as StandardMaterial3D
	beacon.position.y = BASE_HEIGHT + 0.50
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.add_child(beacon)
	body.add_child(ring)


# --- shared resources --------------------------------------------------------


func _mesh_node(
	node_name: String,
	mesh_key: String,
	material: StandardMaterial3D,
	pos: Vector3,
	shadows: bool = true
) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = _meshes[mesh_key] as Mesh
	inst.material_override = material
	inst.position = pos
	if not shadows:
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst


func _tunic_material(profession_id: String, base_color: Color) -> StandardMaterial3D:
	var key := "tunic_%s" % profession_id
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var mat := _make_matte(base_color, 0.88)
	_materials[key] = mat
	return mat


func _trim_material(profession_id: String, trim_color: Color) -> StandardMaterial3D:
	var key := "trim_%s" % profession_id
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var mat := _make_matte(trim_color, 0.86)
	_materials[key] = mat
	return mat


func _skin_for(npc_id: String) -> StandardMaterial3D:
	return _skin_materials[absi(npc_id.hash()) % _skin_materials.size()]


func _hair_for(npc_id: String, age: int) -> StandardMaterial3D:
	if age >= 55:
		return _hair_materials[_hair_materials.size() - 1]
	return _hair_materials[absi(npc_id.hash()) % (_hair_materials.size() - 1)]


func _build_shared_materials() -> void:
	for skin_color in [
		Color(0.89, 0.71, 0.56),
		Color(0.84, 0.65, 0.50),
		Color(0.79, 0.59, 0.44),
		Color(0.91, 0.74, 0.60),
	]:
		_skin_materials.append(_make_matte(skin_color, 0.76))
	for hair_color in [
		Color(0.14, 0.10, 0.08),
		Color(0.30, 0.18, 0.10),
		Color(0.46, 0.28, 0.14),
		Color(0.62, 0.46, 0.24),
		Color(0.72, 0.69, 0.64),
	]:
		_hair_materials.append(_make_matte(hair_color, 0.82))
	_materials["boot_dark"] = _make_matte(Color(0.18, 0.12, 0.08), 0.74)
	_materials["hose_cloth"] = _make_matte(Color(0.28, 0.25, 0.22), 0.90)
	_materials["leather_dark"] = _make_matte(Color(0.22, 0.14, 0.09), 0.66)
	_materials["leather_warm"] = _make_matte(Color(0.42, 0.26, 0.14), 0.72)
	_materials["linen_cream"] = _make_matte(Color(0.92, 0.87, 0.76), 0.92)
	_materials["straw_gold"] = _make_matte(Color(0.85, 0.72, 0.40), 0.88)
	_materials["slate_vest"] = _make_matte(Color(0.24, 0.28, 0.32), 0.80)
	_materials["cloth_rust"] = _make_matte(Color(0.62, 0.24, 0.18), 0.90)
	_materials["wood_pack"] = _make_matte(Color(0.50, 0.34, 0.19), 0.86)
	_materials["stone_pack"] = _make_matte(Color(0.56, 0.53, 0.48), 0.92)
	_materials["clay_terracotta"] = _make_matte(Color(0.74, 0.38, 0.24), 0.80)
	_materials["eye_dark"] = _make_matte(Color(0.10, 0.09, 0.08), 0.45)

	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.84, 0.68, 0.32)
	brass.metallic = 0.45
	brass.roughness = 0.42
	_materials["brass"] = brass

	var select_gold := StandardMaterial3D.new()
	select_gold.albedo_color = Color(0.98, 0.84, 0.36, 0.92)
	select_gold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	select_gold.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials["select_gold"] = select_gold

	var select_amber := StandardMaterial3D.new()
	select_amber.albedo_color = Color(0.95, 0.68, 0.24, 0.65)
	select_amber.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	select_amber.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials["select_amber"] = select_amber


static func _make_matte(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 0.0
	return mat


func _build_shared_meshes() -> void:
	_meshes["leg_upper"] = _cyl(0.082, 0.072, 0.36, 8)
	_meshes["leg_boot"] = _cyl(0.076, 0.086, 0.36, 8)
	_meshes["boot_toe"] = _box(Vector3(0.13, 0.09, 0.18))
	_meshes["tunic_skirt"] = _cyl(0.195, 0.255, 0.34, 10)
	_meshes["torso_upper"] = _cyl(0.215, 0.192, 0.46, 10)
	_meshes["collar_ring"] = _cyl(0.155, 0.225, 0.08, 10)
	_meshes["belt_ring"] = _cyl(0.224, 0.228, 0.075, 10)
	_meshes["buckle_box"] = _box(Vector3(0.085, 0.085, 0.03))
	_meshes["arm_upper"] = _cyl(0.068, 0.060, 0.24, 8)
	_meshes["arm_lower"] = _cyl(0.058, 0.050, 0.22, 8)
	_meshes["hand_sphere"] = _sphere(0.054, 0.108, 8, 4)
	_meshes["neck_cyl"] = _cyl(0.066, 0.074, 0.10, 8)
	_meshes["head_sphere"] = _sphere(0.155, 0.32, 10, 6)
	_meshes["nose_box"] = _box(Vector3(0.036, 0.056, 0.044))
	_meshes["eye_dot"] = _sphere(0.021, 0.042, 6, 4)
	_meshes["hair_cap"] = _sphere(0.166, 0.21, 10, 5)
	_meshes["hair_nape"] = _box(Vector3(0.24, 0.18, 0.12))
	_meshes["hair_bun"] = _sphere(0.068, 0.136, 8, 4)
	_meshes["apron_bib"] = _box(Vector3(0.25, 0.26, 0.035))
	_meshes["apron_skirt"] = _box(Vector3(0.28, 0.34, 0.04))
	_meshes["mantle_cape"] = _cyl(0.17, 0.285, 0.22, 10)
	_meshes["vest_wrap"] = _cyl(0.225, 0.205, 0.38, 10)
	_meshes["brooch_disc"] = _sphere(0.042, 0.05, 8, 4)
	_meshes["straw_brim"] = _cyl(0.31, 0.32, 0.028, 12)
	_meshes["angler_brim"] = _cyl(0.25, 0.27, 0.03, 10)
	_meshes["straw_crown"] = _cyl(0.155, 0.168, 0.11, 10)
	_meshes["hat_band"] = _cyl(0.168, 0.170, 0.04, 10)
	_meshes["toque_puff"] = _sphere(0.185, 0.20, 10, 5)
	_meshes["kerchief_cap"] = _sphere(0.172, 0.18, 10, 5)
	_meshes["hood_cone"] = _cyl(0.04, 0.185, 0.22, 8)
	_meshes["wool_beanie"] = _sphere(0.170, 0.19, 10, 5)
	_meshes["beret_disc"] = _cyl(0.21, 0.165, 0.075, 10)
	_meshes["scholar_top"] = _box(Vector3(0.30, 0.07, 0.30))
	_meshes["hip_pouch"] = _box(Vector3(0.11, 0.16, 0.15))
	_meshes["wicker_basket"] = _cyl(0.15, 0.12, 0.28, 8)
	_meshes["pack_roll"] = _cyl(0.085, 0.085, 0.34, 8)
	_meshes["towel_strip"] = _box(Vector3(0.05, 0.22, 0.10))
	_meshes["pack_box"] = _box(Vector3(0.26, 0.30, 0.16))
	_meshes["jar_cyl"] = _cyl(0.065, 0.095, 0.20, 8)
	_meshes["ledger_box"] = _box(Vector3(0.07, 0.19, 0.15))
	_meshes["select_torus"] = _torus(0.50, 0.62, 24, 8)
	_meshes["select_inner_torus"] = _torus(0.36, 0.42, 20, 6)
	_meshes["select_beacon"] = _cyl(0.0, 0.09, 0.18, 4)


static func _cyl(top_r: float, bottom_r: float, h: float, segs: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _sphere(r: float, h: float, segs: int, rings: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = segs
	m.rings = rings
	return m


static func _torus(inner_r: float, outer_r: float, rings: int, ring_segs: int) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner_r
	m.outer_radius = outer_r
	m.rings = rings
	m.ring_segments = ring_segs
	return m
