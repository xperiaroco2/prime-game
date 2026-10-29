extends RefCounted
## A character built in memory for the tests of #522 (no LFS content needed): a Skeleton3D with
## a few of the contract's bones, one mesh, and an AnimationPlayer whose clips carry AvatarClips'
## names, each turning a known bone about X to a known angle, so a test reads which clip plays from
## a bone's pose: a base clip turns UpperLeg.L to base_angle(clip) (and UpperArm.R to 0),
## Carry_Upper turns UpperArm.R to CARRY_ARM, Chest to CARRY_CHEST (a lean, as the art's does) and
## UpperLeg.L to CARRY_LEG (which its filter must drop), a one-shot turns Chest to SHOT_CHEST.
## Jog_Fwd also moves the Root bone (a root track).
## Plus a small ragdoll in the art's prime-ragdoll format.

const BONES: Array[StringName] = [
	&"Root",
	&"Body",
	&"Hips",
	&"Abdomen",
	&"Torso",
	&"Chest",
	&"UpperArm.R",
	&"Wrist.R",
	&"UpperLeg.L",
	&"Foot.L",
	&"Neck",
	&"Head",
]
const PARENTS: Array[int] = [-1, 0, 1, 2, 3, 4, 5, 6, 2, 8, 5, 10]
const OFFSETS: Array[Vector3] = [
	Vector3.ZERO,
	Vector3(0.0, 0.9, 0.0),
	Vector3(0.0, 0.05, 0.0),
	Vector3(0.0, 0.1, 0.0),
	Vector3(0.0, 0.15, 0.0),
	Vector3(0.0, 0.2, 0.0),
	Vector3(0.2, 0.15, 0.0),
	Vector3(0.0, 0.5, 0.0),
	Vector3(-0.1, -0.05, 0.0),
	Vector3(0.0, -0.8, 0.0),
	Vector3(0.0, 0.25, 0.0),
	Vector3(0.0, 0.1, 0.0),
]
const SKELETON_PATH := "Armature/Skeleton3D"
const CARRY_ARM := 1.0
const CARRY_LEG := 1.5
const CARRY_CHEST := 0.4
const SHOT_CHEST := 0.7
const SHOT_S := 0.5
const ALBEDO := Color(0.8, 0.6, 0.4)


## The angle a base clip (or one of Locomotion's optional points, #1334) turns UpperLeg.L to.
static func base_angle(clip: StringName) -> float:
	var at := AvatarClips.base_clips().find(clip)
	if at < 0:
		at = AvatarClips.base_clips().size() + Locomotion.optional_clips().find(clip)
	return 0.1 * (at + 1)


## Every clip AvatarClips plays plus Locomotion's optional points (the alien set's diagonals).
static func eight_way_clips() -> Array[StringName]:
	var out := AvatarClips.all_clips()
	out.append_array(Locomotion.optional_clips())
	return out


## A plan playing the base `clip` as AvatarClips.plan() would: a move clip in its family's slot at
## its point's direction.
static func plan(clip: StringName, rate := 1.0, carry := false) -> AvatarClips.Plan:
	var out := AvatarClips.Plan.new()
	out.base = clip
	out.rate = rate
	out.carry = carry
	out.slot = clip
	for point: Dictionary in Locomotion.POINTS:
		if point["clip"] == clip:
			out.slot = point["family"] as StringName
			out.back = out.slot == Locomotion.BACK
			out.blend = Locomotion.blend_position(deg_to_rad(point["heading_deg"] as float))
	return out


## A character scene with `clips` (default: all AvatarClips plays) and `bones` (default: BONES);
## `arms_out`: its rest pose holds UpperArm.R out sideways (the art's bind pose), which every base
## clip turns back down, so the rest pose and the pose the clips play differ.
static func scene(
	clips: Array[StringName] = AvatarClips.all_clips(),
	bones: Array[StringName] = BONES,
	arms_out := false
) -> PackedScene:
	var root := Node3D.new()
	root.name = "Fixture"
	var armature := Node3D.new()
	armature.name = "Armature"
	root.add_child(armature)
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	armature.add_child(skeleton)
	for i: int in BONES.size():
		if not bones.has(BONES[i]):
			continue
		var at := skeleton.add_bone(BONES[i])
		var parent := skeleton.find_bone(BONES[PARENTS[i]]) if PARENTS[i] >= 0 else -1
		if parent >= 0:
			skeleton.set_bone_parent(at, parent)
		var turn := Basis.IDENTITY
		if arms_out and BONES[i] == &"UpperArm.R":
			turn = Basis(Vector3.BACK, -PI * 0.5)
		skeleton.set_bone_rest(at, Transform3D(turn, OFFSETS[i]))
	skeleton.reset_bone_poses()
	var mesh := MeshInstance3D.new()
	mesh.name = "Body"
	var box := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = ALBEDO
	box.material = material
	mesh.mesh = box
	skeleton.add_child(mesh)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	var library := AnimationLibrary.new()
	for clip: StringName in clips:
		library.add_animation(clip, _clip(clip))
	player.add_animation_library(&"", library)
	for node: Node in root.find_children("*", "", true, false):
		node.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


## A small ragdoll: the pelvis, the spine (a cone), the chest (a cone) and a thigh (a hinge);
## `with_foot`: also a foot on the thigh (a hinge), a body that stands on the floor.
static func ragdoll(with_foot := false) -> Dictionary:
	var cone := {"type": "cone", "swing_deg": 30.0, "twist_deg": 15.0, "anchor": [0, 0, 0]}
	var hinge := {
		"type": "hinge", "axis": [1, 0, 0], "min_deg": 0.0, "max_deg": 120.0, "anchor": [0, 0, 0]
	}
	var bones: Array = [
		_body("Body", null, null, 0.4),
		_body("Abdomen", "Body", cone, 0.2),
		_body("Torso", "Abdomen", cone, 0.3),
		_body("UpperLeg.L", "Body", hinge, 0.1),
	]
	if with_foot:
		bones.append(_body("Foot.L", "UpperLeg.L", hinge, 0.05))
	return {
		"format": "prime-ragdoll",
		"version": 1,
		"total_mass_kg": 70.0,
		"collision": {"layer": 3, "mask": [1]},
		"material": {"friction": 0.8, "bounce": 0.0, "linear_damp": 0.1, "angular_damp": 6.0},
		"bones": bones,
	}


static func _body(bone: String, parent: Variant, joint: Variant, share: float) -> Dictionary:
	return {
		"bone": bone,
		"parent": parent,
		"joint": joint,
		"shape": "box",
		"size": [0.2, 0.15, 0.15],
		"offset": [0.0, 0.07, 0.0],
		"rotation": [0.0, 0.0, 0.0, 1.0],
		"mass_share": share,
	}


static func _clip(clip: StringName) -> Animation:
	var animation := Animation.new()
	var once := AvatarClips.shot_clips().has(clip)
	animation.length = SHOT_S if once else 1.0
	animation.loop_mode = Animation.LOOP_NONE if once else Animation.LOOP_LINEAR
	if once:
		_turn(animation, &"Chest", SHOT_CHEST)
	elif clip == AvatarClips.CARRY_UPPER:
		_turn(animation, &"UpperArm.R", CARRY_ARM)
		_turn(animation, &"UpperLeg.L", CARRY_LEG)
		_turn(animation, &"Chest", CARRY_CHEST)
	else:
		_turn(animation, &"UpperLeg.L", base_angle(clip))
		_turn(animation, &"UpperArm.R", 0.0)
		_turn(animation, &"Chest", 0.0)
	if clip == AvatarClips.JOG_FWD:
		var track := animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(track, NodePath(SKELETON_PATH + ":Root"))
		animation.position_track_insert_key(track, 0.0, Vector3.ZERO)
		animation.position_track_insert_key(track, 1.0, Vector3(0.0, 0.0, -2.0))
	return animation


static func _turn(animation: Animation, bone: StringName, angle: float) -> void:
	var track := animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, NodePath(SKELETON_PATH + ":" + String(bone)))
	var turn := Quaternion(Vector3.RIGHT, angle)
	animation.rotation_track_insert_key(track, 0.0, turn)
	animation.rotation_track_insert_key(track, animation.length, turn)
