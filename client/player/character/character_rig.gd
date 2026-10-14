class_name CharacterRig
extends Node3D
## One avatar's character (#522, ARCHITECTURE §4.7.53): an instance of a CharacterSet's scene,
## turned to face -Z (the art faces +Z), playing AvatarClips' plan on an AnimationTree:
##
##   base (a Transition of the base clips, cross-faded) -> rate (TimeScale) -> carry (Blend2 with
##   Carry_Upper, filtered to Torso and every bone below it) -> shot (a OneShot of the pick-up or
##   put-down clip) -> output
##
## The tree runs in the physics step (callback PHYSICS), so the bones, and the sockets on them,
## move in the step the item views read them. No root motion: the clips are in place, the tree
## has no root motion track, and the rig node never moves itself; the body's code moves the body.
## Its meshes take a tint (the player's body colour, #551; grey for a dead body) multiplied into
## each surface's albedo. It has no PhysicalBoneSimulator3D: a living rig is no ray target.

## The base clips' cross-fade, the carry layer's fade and the one-shot's fades, in seconds:
## placeholders, "not a decision".
const XFADE_S := 0.15
const CARRY_FADE_S := 0.2
const SHOT_FADE_S := 0.15
## The bone the carry layer starts at (the art: "Torso and every bone below it").
const CARRY_ROOT := &"Torso"
## The sockets: name -> [bone, the point in the rig's frame at the idle pose]. The points are the
## placeholder capsule's (RemotePlayerBody.HAND_POINT, BELT_POINT, CARRY_POINT), so an item sits
## where it did until a shot places it better: placeholders, "not a decision".
const SOCKETS := {
	&"Hand": [&"Wrist.R", Vector3(0.45, 0.95, -0.15)],
	&"Belt": [&"Hips", Vector3(-0.48, 0.85, 0.0)],
	&"Carry": [&"Chest", Vector3(0.0, 0.8, -0.72)],
}

## The character's scene root, its skeleton, its player and the tree driving it.
var model: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var tree: AnimationTree

var _base: StringName = AvatarClips.IDLE
var _carry_target := 0.0
var _carry := 0.0
var _tint := Color.WHITE
var _sockets: Dictionary[StringName, Node3D] = {}
var _materials: Array[BaseMaterial3D] = []
var _albedo: Array[Color] = []


## A rig of `character`'s scene, standing in its idle clip.
static func make(character: CharacterSet) -> CharacterRig:
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
	return rig


## Plays `plan` (AvatarClips.plan()); a RAGDOLL plan changes nothing (the body hides the rig).
func apply(plan: AvatarClips.Plan) -> void:
	if plan.base == AvatarClips.RAGDOLL:
		return
	if plan.base != _base and player.has_animation(plan.base):
		_base = plan.base
		tree.set("parameters/base/transition_request", String(plan.base))
	tree.set("parameters/rate/scale", plan.rate)
	_carry_target = 1.0 if plan.carry else 0.0


## Plays `clip` once over the base and the carry layer, then fades back.
func play_one_shot(clip: StringName) -> void:
	if not player.has_animation(clip):
		return
	var node := (tree.tree_root as AnimationNodeBlendTree).get_node(&"shot_clip")
	(node as AnimationNodeAnimation).animation = clip
	tree.set("parameters/shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## The base clip playing.
func base_clip() -> StringName:
	return _base


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


func _physics_process(delta: float) -> void:
	step(delta)


func _build_tree() -> void:
	var blend := AnimationNodeBlendTree.new()
	var base := AnimationNodeTransition.new()
	base.xfade_time = XFADE_S
	var clips := AvatarClips.base_clips()
	base.input_count = clips.size()
	for i: int in clips.size():
		base.set_input_name(i, String(clips[i]))
		var clip := AnimationNodeAnimation.new()
		clip.animation = clips[i]
		blend.add_node(clips[i], clip)
	blend.add_node(&"base", base)
	for i: int in clips.size():
		blend.connect_node(&"base", i, clips[i])
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


## Each socket is fitted at the pose the clips play (the idle clip's first frame), not the rest:
## the art's rest is an arms-out bind pose, against which the hand's point would swing up with the
## arm as soon as a clip lowers it.
func _add_sockets() -> void:
	var to_skeleton := _frame_of(skeleton)
	for socket_name: StringName in SOCKETS:
		var entry: Array = SOCKETS[socket_name]
		var bone := skeleton.find_bone(entry[0] as StringName)
		var attach := BoneAttachment3D.new()
		attach.name = "%sBone" % socket_name
		attach.bone_name = str(entry[0])
		skeleton.add_child(attach)
		var at := Node3D.new()
		at.name = "%sSocket" % socket_name
		at.transform = socket_offset(to_skeleton * _idle_pose(bone), entry[1] as Vector3)
		attach.add_child(at)
		_sockets[socket_name] = at


## The socket's transform in its bone's frame, for a bone at `bone_pose` in the rig's frame and a
## socket at `point` (no turn against the rig) there.
static func socket_offset(bone_pose: Transform3D, point: Vector3) -> Transform3D:
	return bone_pose.affine_inverse() * Transform3D(Basis.IDENTITY, point)


## `bone`'s pose in the skeleton's frame at the idle clip's first frame, sampled from its tracks (a
## bone or a part the clip leaves alone keeps its rest), so no tree has to run first.
func _idle_pose(bone: int) -> Transform3D:
	var idle := player.get_animation(AvatarClips.IDLE)
	var prefix := String(model.get_path_to(skeleton)) + ":"
	var out := Transform3D.IDENTITY
	var at := bone
	while at >= 0:
		out = _idle_local(idle, NodePath(prefix + skeleton.get_bone_name(at)), at) * out
		at = skeleton.get_bone_parent(at)
	return out


func _idle_local(idle: Animation, path: NodePath, bone: int) -> Transform3D:
	var rest := skeleton.get_bone_rest(bone)
	var origin := rest.origin
	var turn := rest.basis.get_rotation_quaternion()
	var size := rest.basis.get_scale()
	var track := idle.find_track(path, Animation.TYPE_POSITION_3D)
	if track >= 0:
		origin = idle.position_track_interpolate(track, 0.0)
	track = idle.find_track(path, Animation.TYPE_ROTATION_3D)
	if track >= 0:
		turn = idle.rotation_track_interpolate(track, 0.0)
	track = idle.find_track(path, Animation.TYPE_SCALE_3D)
	if track >= 0:
		size = idle.scale_track_interpolate(track, 0.0)
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
