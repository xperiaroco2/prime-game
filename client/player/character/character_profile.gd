class_name CharacterProfile
extends RefCounted
## What the game needs to know of one art character beyond its scene (#1693): its files, the bones
## it hangs things on (a map, so a character with other bone names needs only a profile of its own),
## the clips' ground speeds at rate 1 and the scale it is drawn at. CharacterSet carries one;
## CharacterRig, RagdollView and the clips' rates read it. alien() is the shipped character (M8's
## base alien, the chameleon of art#398, the engineer's pick of 2026-11-23, confirmed on
## 2026-11-24); slice_m1() the one before it, kept for its files and the tests' fixture, whose bones
## carry its names.

## The alien's size in the game: its eyes at 1.702 m and its top at 1.938 m as built, to the game's
## 1.6 m eye (PlayerRules), its top then 1.82 m, about the 1.8 m capsule (the art's swap note).
const ALIEN_SCALE := 0.94

## The character's GLB, its ragdoll data and its look (the art's look JSON; empty: the GLB's own
## materials, tinted by their albedo).
var glb: String
var ragdoll: String
var look: String
## The bone the carry layer starts at: it and every bone below it play the carry clip.
var carry_root: StringName
## The sockets: name -> [bone, the point in the bone's own frame in metres as drawn, fitted
## carrying]; see CharacterRig.
var sockets: Dictionary
## Each move clip's ground speed at rate 1 in m/s, where it differs from AvatarClips' (the art
## package's measured rows); a clip left out moves at AvatarClips' speed.
var clip_mps: Dictionary[StringName, float] = {}
## The factor the GLB is imported at (its `.import` nodes/root_scale, applied to the meshes, the
## skeleton and the clips) and the ragdoll data is scaled by: the art's sizes to the game's eye.
var scale := 1.0


## The bones the rig names: the carry layer's root and the sockets' bones.
func needed_bones() -> Array[StringName]:
	var out: Array[StringName] = [carry_root]
	for socket: StringName in sockets:
		var bone := (sockets[socket] as Array)[0] as StringName
		if not out.has(bone):
			out.append(bone)
	return out


## `clip`'s ground speed at rate 1: its own, else `assumed` (AvatarClips' for that clip).
func mps_of(clip: StringName, assumed: float) -> float:
	return clip_mps.get(clip, assumed)


## The ground speed at rate 1 of the move a plan draws (AvatarClips.Plan's base, slot and blend): in
## a move family (Locomotion.FRONT, BACK) between the two family points nearest the blend's heading,
## by how near each is, so the rate never jumps where the plan's base clip changes (the alien's
## forward jog and strafe differ by half); else `base`'s own; 0 for a clip that does not move.
func move_mps(base: StringName, slot: StringName, blend: Vector2) -> float:
	var assumed := AvatarClips.assumed_mps(base)
	if assumed <= 0.0:
		return 0.0
	if slot != Locomotion.FRONT and slot != Locomotion.BACK:
		return mps_of(base, assumed)
	var heading := rad_to_deg(atan2(-blend.x, blend.y))
	var near: Array[Dictionary] = []
	for point: Dictionary in Locomotion.points_of(slot):
		var off := absf(wrapf(heading - (point["heading_deg"] as float), -180.0, 180.0))
		near.append({"off": off, "mps": mps_of(point["clip"] as StringName, AvatarClips.JOG_MPS)})
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["off"] < b["off"])
	if near.size() < 2 or (near[0]["off"] as float) < 0.001:
		return near[0]["mps"] as float
	var first := near[0]["off"] as float
	var t := first / (first + (near[1]["off"] as float))
	return lerpf(near[0]["mps"] as float, near[1]["mps"] as float, t)


## How much faster than AvatarClips' rate the plan's clips play on this character: the speed
## AvatarClips assumes for `base` over move_mps, so each step covers the ground the move does
## (#1693). CharacterRig plays the tree at it and the footsteps time the contacts by it.
func rate_factor(base: StringName, slot: StringName, blend: Vector2) -> float:
	var assumed := AvatarClips.assumed_mps(base)
	if assumed <= 0.0:
		return 1.0
	return assumed / maxf(move_mps(base, slot, blend), 0.01)


## The shipped character: the base alien (art#398's HANDOFF and swap note). Its sockets: the Hand in
## the curled fingers (it has no grip pose), the Belt on the hip, the Carry in front of the chest
## (fitted on the idle clip: no carry clip); the art measured them on the GLB at its own size, so
## each point is scaled to the drawn one.
static func alien() -> CharacterProfile:
	var out := CharacterProfile.new()
	out.glb = "res://assets/characters/alien_chameleon/alien_chameleon.glb"
	out.ragdoll = "res://assets/characters/alien_chameleon/alien_chameleon.ragdoll.json"
	out.look = "res://assets/characters/alien_chameleon/look/alien_chameleon_look.json"
	out.scale = ALIEN_SCALE
	out.carry_root = &"Chest"
	out.sockets = {
		&"Hand": [&"RightHand", Vector3(-0.0262, 0.1645, 0.0123) * ALIEN_SCALE, false],
		&"Belt": [&"Hips", Vector3(0.1810, 0.0455, -0.0533) * ALIEN_SCALE, false],
		&"Carry": [&"UpperChest", Vector3(0.0147, -0.3519, 0.4038) * ALIEN_SCALE, true],
	}
	# The package's measured speeds (package.json's clip_rows) at the GLB's own size: the import's
	# 0.94 shortens every stride with it.
	var measured: Dictionary[StringName, float] = {
		&"Jog_Fwd": 4.74,
		&"Jog_Fwd_Left": 3.8,
		&"Jog_Fwd_Right": 3.88,
		&"Strafe_Left": 3.17,
		&"Strafe_Right": 3.26,
		&"Jog_Bwd": 2.0,
		&"Jog_Bwd_Left": 2.0,
		&"Jog_Bwd_Right": 2.0,
		&"Crouch_Fwd": 2.07,
		&"Crouch_Run": 2.89,
		&"Walk": 0.9,
		&"Sprint_Fwd": 7.0,
	}
	for clip: StringName in measured:
		out.clip_mps[clip] = measured[clip] * ALIEN_SCALE
	return out


## The slice character before the alien (#522): the Ultimate Modular rig's names; its sockets as
## measured on it (#1050).
static func slice_m1() -> CharacterProfile:
	var out := CharacterProfile.new()
	out.glb = "res://assets/characters/slice_m1/slice_m1.glb"
	out.ragdoll = "res://assets/characters/slice_m1/slice_m1.ragdoll.json"
	out.carry_root = &"Torso"
	out.sockets = {
		&"Hand": [&"Wrist.R", Vector3(0.0, 0.125, 0.0), false],
		&"Belt": [&"Hips", Vector3(0.19, 0.065, -0.06), false],
		&"Carry": [&"Chest", Vector3(0.015, -0.265, 0.525), true],
	}
	return out
