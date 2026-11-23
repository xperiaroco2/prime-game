class_name CharacterProfile
extends RefCounted
## What the game needs to know of one art character beyond its scene (#1693): its files, the bones
## it hangs things on (a map, so a character with other bone names needs only a profile of its
## own), the clips' ground speeds at rate 1 and the scale it is drawn at. CharacterSet carries
## one; CharacterRig, RagdollView and the clips' rates read it. alien() is the shipped character
## (M8's base alien, the chameleon of art#398, the engineer's pick of 2026-11-24); slice_m1()
## the one
## before it, kept for its files and the tests' fixture, whose bones carry its names.

## The alien's size in the game: its eyes at 1.702 m and its top at 1.938 m as built, to the
## game's 1.6 m eye (PlayerRules) and under its 1.8 m capsule (the art's swap note).
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
	out.clip_mps = {
		&"Jog_Fwd": 4.74,
		&"Strafe_Left": 3.17,
		&"Strafe_Right": 3.26,
		&"Jog_Bwd": 2.0,
		&"Crouch_Fwd": 2.07,
		&"Sprint_Fwd": 7.0,
	}
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
