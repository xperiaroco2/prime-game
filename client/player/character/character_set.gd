class_name CharacterSet
extends RefCounted
## The art character the avatars wear (#522, ARCHITECTURE §4.7.53): its scene (the GLB: the
## body, the skeleton, the clips) and its ragdoll data (the art's `<id>.ragdoll.json`, art #115).
## Injected: `Game` loads it once and hands it to AvatarViews and BodyViews; null everywhere else
## means today's placeholder capsule, so tests, previews and CI (no LFS content: `check` imports an
## empty glTF stand-in in the GLB's place, the LFS ADR) need no character.
##
## A set exists only for a scene that is the character: one Skeleton3D with the bones the rig
## names and one AnimationPlayer with every clip AvatarClips plays. The decision comes from the
## instantiated scene, never the GLB's bytes (an export ships no source GLB), so the stand-in and a
## missing file give null silently, and a real but broken character gives null with one warning.

const DEFAULT_GLB := "res://assets/characters/slice_m1/slice_m1.glb"
const DEFAULT_RAGDOLL := "res://assets/characters/slice_m1/slice_m1.ragdoll.json"
## The bones CharacterRig names: the carry layer's root and the sockets' bones.
const NEEDED_BONES: Array[StringName] = [&"Hips", &"Torso", &"Chest", &"Wrist.R"]

## The character's scene.
var scene: PackedScene
## The ragdoll data (the art's prime-ragdoll format, version 1), or empty: then no PhysicalBone3D
## ragdoll, the capsule stands in.
var ragdoll: Dictionary = {}
## Each clip's length in seconds at rate 1, read once from the scene's AnimationPlayer (#1334).
var cycles: Dictionary[StringName, float] = {}


## The shipped character, or null without it (see above).
static func load_default() -> CharacterSet:
	if not ResourceLoader.exists(DEFAULT_GLB):
		return null
	var packed := load(DEFAULT_GLB) as PackedScene
	return from_scene(packed, read_ragdoll(DEFAULT_RAGDOLL))


## The set of `packed` with `data`, or null when `packed` is not a character (problems_of()).
static func from_scene(packed: PackedScene, data: Dictionary) -> CharacterSet:
	if packed == null or not packed.can_instantiate():
		return null
	var root := packed.instantiate()
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	var problems := problems_of(root)
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
	out.ragdoll = data if valid_ragdoll(data) and missing.is_empty() else {}
	out.cycles = cycles
	return out


## `clip`'s length in seconds at rate 1, as CharacterRig.cycle_of has it; 0 for a clip it lacks.
## The own player's footsteps time by it, as the others' clients time this character's (#1334).
func cycle_of(clip: StringName) -> float:
	return cycles.get(clip, 0.0)


## The bones `data`'s bodies name that `skeleton` lacks: the builder would skip each, and without
## the parentless one the ragdoll never falls.
static func missing_bones(skeleton: Skeleton3D, data: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Variant in data["bones"] as Array:
		var bone := str((entry as Dictionary).get("bone", "")) if entry is Dictionary else ""
		if skeleton.find_bone(bone) < 0:
			out.append(bone)
	return out


## What keeps `root` from being a character, one line each; empty when it is one.
static func problems_of(root: Node) -> PackedStringArray:
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
	for bone: StringName in NEEDED_BONES:
		if skeleton.find_bone(bone) < 0:
			problems.append("no bone %s" % bone)
	var player := players[0] as AnimationPlayer
	for clip: StringName in AvatarClips.all_clips():
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
