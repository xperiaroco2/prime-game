class_name CharacterSet
extends RefCounted
## The art character the avatars wear (#522, ARCHITECTURE §4.7.53): its scene (the GLB: the
## body, the skeleton, the clips) and its ragdoll data (the art's `<id>.ragdoll.json`, art #115).
## Injected: `Game` loads it once and hands it to AvatarViews and BodyViews; null everywhere else
## means today's placeholder capsule, so tests, previews and CI (no LFS content: `check` imports an
## empty glTF stand-in in the GLB's place, the LFS ADR) need no character.
##
## A set exists only for a scene that is the character: one Skeleton3D with the bones its profile
## (CharacterProfile, #1693: the bone map, the clips' speeds, the scale) names and one
## AnimationPlayer with every base clip AvatarClips plays (the carry and the one-shot clips are
## optional: a character without them plays its base clip, CharacterRig). The decision comes from
## the instantiated scene, never the GLB's bytes (an export ships no source GLB), so the stand-in
## and a missing file give null silently, and a real but broken character gives null with one
## warning.

## The character's scene.
var scene: PackedScene
## Its profile: the bones the rig hangs on, the clips' speeds, the scale.
var profile: CharacterProfile
## The ragdoll data (the art's prime-ragdoll format, version 1), or empty: then no PhysicalBone3D
## ragdoll, the capsule stands in.
var ragdoll: Dictionary = {}
## Each clip's length in seconds at rate 1, read once from the scene's AnimationPlayer (#1334).
var cycles: Dictionary[StringName, float] = {}


## The shipped character's profile: the base alien (#1693).
static func default_profile() -> CharacterProfile:
	return CharacterProfile.alien()


## The profiles a scene is tried against, in order: the one whose bones it has is its own.
static func profiles() -> Array[CharacterProfile]:
	return [CharacterProfile.alien(), CharacterProfile.slice_m1()]


## The shipped character, or null without it (see above).
static func load_default() -> CharacterSet:
	var own := default_profile()
	if not ResourceLoader.exists(own.glb):
		return null
	var packed := load(own.glb) as PackedScene
	return from_scene(packed, read_ragdoll(own.ragdoll), own)


## The set of `packed` with `data` (in the art's sizes: scaled here by the profile), or null when
## `packed` is not a character (problems_of()). `own`: its profile; null: the first of profiles()
## whose bones the scene has.
static func from_scene(
	packed: PackedScene, data: Dictionary, own: CharacterProfile = null
) -> CharacterSet:
	if packed == null or not packed.can_instantiate():
		return null
	var root := packed.instantiate()
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	if own == null:
		own = profile_of(root)
	var problems := problems_of(root, own)
	data = scaled_ragdoll(data, own.scale)
	var missing := PackedStringArray()
	if problems.is_empty() and valid_ragdoll(data):
		missing = missing_bones(skeletons[0] as Skeleton3D, data)
	var cycles: Dictionary[StringName, float] = {}
	if problems.is_empty():
		var player := root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		for clip: StringName in player.get_animation_list():
			cycles[clip] = player.get_animation(clip).length
	root.free()
	if not problems.is_empty():
		if not skeletons.is_empty():
			push_warning("CharacterSet: %s: %s" % [packed.resource_path, "; ".join(problems)])
		return null
	if not missing.is_empty():
		push_warning("CharacterSet: the ragdoll names no such bone: %s" % ", ".join(missing))
	var out := CharacterSet.new()
	out.scene = packed
	out.profile = own
	out.ragdoll = data if valid_ragdoll(data) and missing.is_empty() else {}
	out.cycles = cycles
	return out


## `clip`'s length in seconds at rate 1, as CharacterRig.cycle_of has it; 0 for a clip it lacks.
## The own player's footsteps time by it, as the others' clients time this character's (#1334).
func cycle_of(clip: StringName) -> float:
	return cycles.get(clip, 0.0)


## AvatarClips.EXTRA_CLIPS this character has, as CharacterRig.extra_clips has them (#1334).
func extra_clips() -> Array[StringName]:
	var out: Array[StringName] = []
	for clip: StringName in AvatarClips.EXTRA_CLIPS:
		if cycles.has(clip):
			out.append(clip)
	return out


## The bones `data`'s bodies name that `skeleton` lacks: the builder would skip each, and without
## the parentless one the ragdoll never falls.
static func missing_bones(skeleton: Skeleton3D, data: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Variant in data["bones"] as Array:
		var bone := str((entry as Dictionary).get("bone", "")) if entry is Dictionary else ""
		if skeleton.find_bone(bone) < 0:
			out.append(bone)
	return out


## The profile of profiles() whose bones `root`'s skeleton has (the first), else the default.
static func profile_of(root: Node) -> CharacterProfile:
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() == 1:
		var skeleton := skeletons[0] as Skeleton3D
		for candidate: CharacterProfile in profiles():
			var fits := true
			for bone: StringName in candidate.needed_bones():
				fits = fits and skeleton.find_bone(bone) >= 0
			if fits:
				return candidate
	return default_profile()


## `data` with its lengths (each body's offset, size, radius, height and joint anchor) times
## `factor`: the art's sizes to the drawn character's (CharacterProfile.scale); a copy, `data` as
## it is at 1.
static func scaled_ragdoll(data: Dictionary, factor: float) -> Dictionary:
	if is_equal_approx(factor, 1.0) or not valid_ragdoll(data):
		return data
	var out := data.duplicate(true)
	for entry: Variant in out["bones"] as Array:
		var bone := entry as Dictionary
		for key: String in ["offset", "size"]:
			if bone.get(key) is Array:
				bone[key] = _scaled_list(bone[key] as Array, factor)
		for key: String in ["radius", "height"]:
			if bone.has(key):
				bone[key] = (bone[key] as float) * factor
		var joint: Variant = bone.get("joint")
		if joint is Dictionary and (joint as Dictionary).get("anchor") is Array:
			(joint as Dictionary)["anchor"] = _scaled_list(
				(joint as Dictionary)["anchor"] as Array, factor
			)
	return out


static func _scaled_list(values: Array, factor: float) -> Array:
	var out: Array = []
	for value: Variant in values:
		out.append((value as float) * factor)
	return out


## What keeps `root` from being a character of `own` (null: profile_of(root)), one line each;
## empty when it is one.
static func problems_of(root: Node, own: CharacterProfile = null) -> PackedStringArray:
	if own == null:
		own = profile_of(root)
	var problems := PackedStringArray()
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	var players := root.find_children("*", "AnimationPlayer", true, false)
	if skeletons.size() != 1:
		problems.append("%d Skeleton3D, want 1" % skeletons.size())
	if players.size() != 1:
		problems.append("%d AnimationPlayer, want 1" % players.size())
	if not problems.is_empty():
		return problems
	var skeleton := skeletons[0] as Skeleton3D
	for bone: StringName in own.needed_bones():
		if skeleton.find_bone(bone) < 0:
			problems.append("no bone %s" % bone)
	var player := players[0] as AnimationPlayer
	for clip: StringName in AvatarClips.base_clips():
		if not player.has_animation(clip):
			problems.append("no clip %s" % clip)
	return problems


## The parsed ragdoll file at `path`, or empty if it is missing or not JSON.
static func read_ragdoll(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


## Whether `data` has what RagdollBuilder reads: the format, the collision, the mass and bodies.
static func valid_ragdoll(data: Dictionary) -> bool:
	if data.get("format") != "prime-ragdoll" or not data.get("bones") is Array:
		return false
	if not data.get("collision") is Dictionary or not data.has("total_mass_kg"):
		return false
	return not (data["bones"] as Array).is_empty()
