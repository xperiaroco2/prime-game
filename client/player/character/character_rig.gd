class_name CharacterRig
extends Node3D
## One avatar's character (#522, ARCHITECTURE §4.7.53): an instance of a CharacterSet's scene,
## turned to face -Z (the art faces +Z), playing AvatarClips' plan on an AnimationTree:
##
##   base (a Transition of SLOTS, cross-faded) -> rate (TimeScale) -> carry (Blend2 with
##   Carry_Upper, filtered to Torso and every bone below it) -> shot (a OneShot of the pick-up or
##   put-down clip) -> output
##
## A slot is a clip (Idle, Sprint_Fwd, Crouch_Idle, Crouch_Fwd) or a move family of Locomotion
## (Front, Back, #1334): an AnimationNodeBlendSpace2D of the family's points whose clip the
## character has, at the plan's direction, its clips kept in step (SYNC_MODE_CYCLIC_MUTABLE: the
## art MVP set's clips differ in length); a family with fewer than three such points plays its
## main clip (Jog_Fwd, Jog_Bwd) alone. The two families are never blended into each other: the
## Transition cross-fades between them as between any two slots. A rig made `with_look` also has a
## HeadLook on its skeleton (when it has the Neck and Head bones), turned by set_look().
##
## The tree runs in the physics callback (PHYSICS); the skeleton applies the pose in its deferred
## update, so a socket (and an item view on it) may show the previous step's bone pose: a one-step
## lag, accepted (ARCHITECTURE §4.7.53). No root motion: the clips are in place, the tree
## has no root motion track, and the rig node never moves itself; the body's code moves the body.
## Its meshes take a tint (the player's body colour, #551; grey for a dead body) multiplied into
## each surface's albedo. It has no PhysicalBoneSimulator3D: a living rig is no ray target.

## The base clips' cross-fade, the carry layer's fade and the one-shot's fades, in seconds:
## placeholders, "not a decision".
const XFADE_S := 0.15
## The Transition's inputs, in order.
const SLOTS: Array[StringName] = [
	AvatarClips.IDLE,
	Locomotion.FRONT,
	Locomotion.BACK,
	AvatarClips.SPRINT_FWD,
	AvatarClips.CROUCH_IDLE,
	AvatarClips.CROUCH_FWD,
]
const CARRY_FADE_S := 0.2
const SHOT_FADE_S := 0.15
## The bone the carry layer starts at (the art: "Torso and every bone below it").
const CARRY_ROOT := &"Torso"
## The sockets: name -> [bone, the point in the bone's own frame, fitted carrying]. Each point
## was measured on the art (slice_m1) from close-up shots (#1050): Hand at the right palm, where a
## one-handed item's bottom sits in the fist; Belt on the outside of the left hip at the waist;
## Carry the bottom of a two-handed item held between both palms in front of the chest. A socket
## stands upright in the rig at its fitting pose (the idle clip's first frame; carrying: with
## Carry_Upper's first frame on the carry layer's bones), the pose its item shows in.
const SOCKETS := {
	&"Hand": [&"Wrist.R", Vector3(0.0, 0.125, 0.0), false],
	&"Belt": [&"Hips", Vector3(0.19, 0.065, -0.06), false],
	&"Carry": [&"Chest", Vector3(0.015, -0.265, 0.525), true],
}

## The character's scene root, its skeleton, its player and the tree driving it.
var model: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var tree: AnimationTree

var _base: StringName = AvatarClips.IDLE
var _slot: StringName = AvatarClips.IDLE
## The slots built as blend spaces.
var _spaces: Array[StringName] = []
var _look: HeadLook
var _carry_target := 0.0
var _carry := 0.0
var _tint := Color.WHITE
var _sockets: Dictionary[StringName, Node3D] = {}
var _materials: Array[BaseMaterial3D] = []
var _albedo: Array[Color] = []


## A rig of `character`'s scene, standing in its idle clip; `with_look`: with a HeadLook (a living
## body's rig; a ragdoll's or a picture's has none).
static func make(character: CharacterSet, with_look := false) -> CharacterRig:
	var rig := CharacterRig.new()
	rig.name = "Character"
	rig.model = character.scene.instantiate() as Node3D
	rig.model.name = "Model"
	rig.model.rotation = Vector3(0.0, PI, 0.0)
	rig.add_child(rig.model)
	rig.skeleton = rig.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	rig.player = rig.model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	rig._build_tree()
	rig._add_sockets()
	rig._own_materials()
	if with_look:
		rig._add_look()
	return rig


## Plays `plan` (AvatarClips.plan()); a RAGDOLL plan changes nothing (the body hides the rig).
func apply(plan: AvatarClips.Plan) -> void:
	if plan.base == AvatarClips.RAGDOLL:
		return
	if plan.base != _base and player.has_animation(plan.base):
		_base = plan.base
	if plan.slot != _slot and SLOTS.has(plan.slot):
		_slot = plan.slot
		tree.set("parameters/base/transition_request", String(plan.slot))
	if _spaces.has(plan.slot):
		tree.set("parameters/%s/blend_position" % plan.slot, plan.blend)
	tree.set("parameters/rate/scale", plan.rate)
	_carry_target = 1.0 if plan.carry else 0.0


## Plays `clip` once over the base and the carry layer, then fades back.
func play_one_shot(clip: StringName) -> void:
	if not player.has_animation(clip):
		return
	var node := (tree.tree_root as AnimationNodeBlendTree).get_node(&"shot_clip")
	(node as AnimationNodeAnimation).animation = clip
	tree.set("parameters/shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## The base clip playing: the plan's `base`, the art MVP set's clip nearest the move (a family
## blends it with its neighbours).
func base_clip() -> StringName:
	return _base


## The Transition's input playing (a clip, or Locomotion.FRONT or BACK).
func base_slot() -> StringName:
	return _slot


## Whether `slot` plays as a blend space of its family's points (else as one clip).
func is_blended(slot: StringName) -> bool:
	return _spaces.has(slot)


## Turns the head by the aim against the body: `yaw` (positive to the left) and `pitch`
## (positive up), radians; nothing for a rig without a HeadLook.
func set_look(yaw: float, pitch: float) -> void:
	if _look != null:
		_look.aim_yaw = yaw
		_look.aim_pitch = pitch


## The rig's HeadLook, or null.
func head_look() -> HeadLook:
	return _look


## The carry layer's weight now (0 off, 1 on).
func carry_weight() -> float:
	return _carry


## Whether a one-shot plays.
func is_shot_active() -> bool:
	return tree.get("parameters/shot/active") as bool


## The socket `socket_name` (Hand, Belt, Carry): a node that follows its bone.
func socket(socket_name: StringName) -> Node3D:
	return _sockets.get(socket_name) as Node3D


## Tints every surface by `colour` (white: the art's own look).
func set_tint(colour: Color) -> void:
	_tint = colour
	for i: int in _materials.size():
		_materials[i].albedo_color = _albedo[i] * colour


func tint() -> Color:
	return _tint


## The bones the carry layer moves: CARRY_ROOT and every bone below it.
func carry_bones() -> PackedStringArray:
	var out := PackedStringArray()
	var root := skeleton.find_bone(CARRY_ROOT)
	for i: int in skeleton.get_bone_count():
		var at := i
		while at >= 0 and at != root:
			at = skeleton.get_bone_parent(at)
		if at == root and root >= 0:
			out.append(skeleton.get_bone_name(i))
	return out


## Advances the carry fade and the tree by `delta` (the physics step; tests call it by hand).
func step(delta: float) -> void:
	var fade := delta / CARRY_FADE_S
	_carry = move_toward(_carry, _carry_target, fade)
	tree.set("parameters/carry/blend_amount", _carry)


## Stands the rig in the plan applied this instant, `seconds` into its clips with every fade done:
## the tree evaluated, the skeleton and the sockets updated now. For a rig drawn before its first
## physics step (a picture's puppet, #787), which the tree would leave in the arms-out rest.
func pose_now(seconds := XFADE_S) -> void:
	_carry = _carry_target
	tree.set("parameters/carry/blend_amount", _carry)
	tree.advance(0.0)
	tree.advance(seconds)
	skeleton.force_update_all_bone_transforms()
	for at: Node3D in _sockets.values():
		(at.get_parent() as BoneAttachment3D).on_skeleton_update()


func _physics_process(delta: float) -> void:
	step(delta)


func _build_tree() -> void:
	var blend := AnimationNodeBlendTree.new()
	var base := AnimationNodeTransition.new()
	base.xfade_time = XFADE_S
	base.input_count = SLOTS.size()
	for i: int in SLOTS.size():
		base.set_input_name(i, String(SLOTS[i]))
		blend.add_node(SLOTS[i], _slot_node(SLOTS[i]))
	blend.add_node(&"base", base)
	for i: int in SLOTS.size():
		blend.connect_node(&"base", i, SLOTS[i])
	blend.add_node(&"rate", AnimationNodeTimeScale.new())
	blend.connect_node(&"rate", 0, &"base")
	var carry_clip := AnimationNodeAnimation.new()
	carry_clip.animation = AvatarClips.CARRY_UPPER
	blend.add_node(&"carry_clip", carry_clip)
	var carry := AnimationNodeBlend2.new()
	carry.filter_enabled = true
	var prefix := String(model.get_path_to(skeleton)) + ":"
	for bone: String in carry_bones():
		carry.set_filter_path(NodePath(prefix + bone), true)
	blend.add_node(&"carry", carry)
	blend.connect_node(&"carry", 0, &"rate")
	blend.connect_node(&"carry", 1, &"carry_clip")
	var shot_clip := AnimationNodeAnimation.new()
	shot_clip.animation = AvatarClips.PICKUP_ONE
	blend.add_node(&"shot_clip", shot_clip)
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = SHOT_FADE_S
	shot.fadeout_time = SHOT_FADE_S
	blend.add_node(&"shot", shot)
	blend.connect_node(&"shot", 0, &"carry")
	blend.connect_node(&"shot", 1, &"shot_clip")
	blend.connect_node(&"output", 0, &"shot")
	tree = AnimationTree.new()
	tree.name = "Tree"
	tree.tree_root = blend
	model.add_child(tree)
	tree.root_node = tree.get_path_to(model)
	tree.anim_player = tree.get_path_to(player)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	tree.active = true
	tree.set("parameters/base/transition_request", String(AvatarClips.IDLE))


## `slot`'s node: its clip, or its family's blend space (or main clip, below three points).
func _slot_node(slot: StringName) -> AnimationRootNode:
	if slot != Locomotion.FRONT and slot != Locomotion.BACK:
		return _clip_node(slot)
	var points: Array[Dictionary] = []
	for point: Dictionary in Locomotion.points_of(slot):
		if player.has_animation(point["clip"] as StringName):
			points.append(point)
	if points.size() < 3:
		return _clip_node(AvatarClips.JOG_FWD if slot == Locomotion.FRONT else AvatarClips.JOG_BWD)
	var space := AnimationNodeBlendSpace2D.new()
	space.sync_mode = AnimationNodeBlendSpace2D.SYNC_MODE_CYCLIC_MUTABLE
	for point: Dictionary in points:
		var at := Locomotion.blend_position(deg_to_rad(point["heading_deg"] as float))
		space.add_blend_point(_clip_node(point["clip"] as StringName), at)
	_spaces.append(slot)
	return space


static func _clip_node(clip: StringName) -> AnimationNodeAnimation:
	var out := AnimationNodeAnimation.new()
	out.animation = clip
	return out


## A HeadLook on the skeleton when it has both bones the look turns.
func _add_look() -> void:
	if skeleton.find_bone(HeadLook.NECK) < 0 or skeleton.find_bone(HeadLook.HEAD) < 0:
		return
	_look = HeadLook.new()
	_look.name = "HeadLook"
	_look.frame = _frame_of(skeleton).basis.orthonormalized()
	skeleton.add_child(_look)


## Each socket sits at its point on its bone, turned to stand upright at the pose its item shows
## in, never the rest: the art's rest is an arms-out bind pose, against which the hand's item would
## turn with the arm as soon as a clip lowers it.
func _add_sockets() -> void:
	for socket_name: StringName in SOCKETS:
		var entry: Array = SOCKETS[socket_name]
		var bone := skeleton.find_bone(entry[0] as StringName)
		var attach := BoneAttachment3D.new()
		attach.name = "%sBone" % socket_name
		attach.bone_name = str(entry[0])
		skeleton.add_child(attach)
		var at := Node3D.new()
		at.name = "%sSocket" % socket_name
		at.transform = socket_transform(fit_pose(bone, entry[2] as bool), entry[1] as Vector3)
		attach.add_child(at)
		_sockets[socket_name] = at


## The socket's transform in its bone's frame: at `point` there, turned so it stands upright (no
## turn against the rig) while the bone is at `bone_pose` in the rig's frame.
static func socket_transform(bone_pose: Transform3D, point: Vector3) -> Transform3D:
	return Transform3D(bone_pose.basis.inverse(), point)


## `bone`'s pose in the rig's frame at a socket's fitting pose: the idle clip's first frame, with
## Carry_Upper's first frame on the carry layer's bones when `carrying` (the layer at full weight),
## sampled from the clips' tracks (a bone or a part a clip leaves alone keeps its rest), so no tree
## has to run first.
func fit_pose(bone: int, carrying: bool) -> Transform3D:
	var idle := player.get_animation(AvatarClips.IDLE)
	var carry := player.get_animation(AvatarClips.CARRY_UPPER)
	var layered := carry_bones() if carrying else PackedStringArray()
	var prefix := String(model.get_path_to(skeleton)) + ":"
	var out := Transform3D.IDENTITY
	var at := bone
	while at >= 0:
		var bone_name := skeleton.get_bone_name(at)
		var clip := carry if layered.has(bone_name) else idle
		out = _first_frame(clip, NodePath(prefix + bone_name), at) * out
		at = skeleton.get_bone_parent(at)
	return _frame_of(skeleton) * out


func _first_frame(clip: Animation, path: NodePath, bone: int) -> Transform3D:
	var rest := skeleton.get_bone_rest(bone)
	var origin := rest.origin
	var turn := rest.basis.get_rotation_quaternion()
	var size := rest.basis.get_scale()
	var track := clip.find_track(path, Animation.TYPE_POSITION_3D)
	if track >= 0:
		origin = clip.position_track_interpolate(track, 0.0)
	track = clip.find_track(path, Animation.TYPE_ROTATION_3D)
	if track >= 0:
		turn = clip.rotation_track_interpolate(track, 0.0)
	track = clip.find_track(path, Animation.TYPE_SCALE_3D)
	if track >= 0:
		size = clip.scale_track_interpolate(track, 0.0)
	return Transform3D(Basis(turn) * Basis.from_scale(size), origin)


## `node`'s transform in the rig's frame, from the local transforms (no tree needed).
func _frame_of(node: Node3D) -> Transform3D:
	var out := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != self:
		if at is Node3D:
			out = (at as Node3D).transform * out
		at = at.get_parent()
	return out


## Gives each surface its own copy of its material, so one avatar's tint leaves the others'.
func _own_materials() -> void:
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for i: int in mesh.get_surface_override_material_count():
			var material := mesh.get_active_material(i) as BaseMaterial3D
			if material == null:
				continue
			var own := material.duplicate() as BaseMaterial3D
			mesh.set_surface_override_material(i, own)
			_materials.append(own)
			_albedo.append(own.albedo_color)
