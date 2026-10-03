class_name Ears
extends AudioListener3D
## The own player's ears (E40, the M5 ADR §1.5 and §3 item 4): the AudioListener3D every voice and
## world sound is heard from, made current while a session runs. LifeView places it each physics
## step from point() and turns it with the current camera, so a sound on the screen's left is
## heard on the left:
## - living: the own eye (the first-person camera);
## - downed: the own body's head where it lies (vision revision 1: the downed hear the living
##   "from where they lie"), never the downed camera up to 2 m behind and 1.6 m above, whose ray
##   would pass over the crate the body lies against;
## - dead, spectating a living target: the target's eye; a downed target: its body's head; no
##   target: the own body's head. The dead hear no voice (the host routes none and VoiceViews
##   plays none), so there the ears serve the world sounds around the target (V11).
## SoundChooser measures its hearing range from here too (E40's amendment of E33). Godot mixes a
## 3D player for the current listener only while the world has a Camera3D, which the game always
## has.


## Where the ears are. `own_life` is the own life fold; `own_feet` the own body (the controller's
## transform while living or downed, the body's place while dead); `own_eye` the first-person
## camera's position; `target` 0 or the spectated peer, `target_life` its life fold and
## `target_feet` its RemotePlayerBody's transform; `rules` the client's own PlayerRules.
static func point(
	own_life: ClientModel.Life,
	own_feet: Transform3D,
	own_eye: Vector3,
	target: int,
	target_life: ClientModel.Life,
	target_feet: Transform3D,
	rules: PlayerRules
) -> Vector3:
	match own_life:
		ClientModel.Life.ALIVE:
			return own_eye
		ClientModel.Life.DOWNED:
			return lying_head(own_feet, rules)
	if target == 0:
		return lying_head(own_feet, rules)
	if target_life == ClientModel.Life.ALIVE:
		return target_feet.origin + Vector3.UP * rules.eye_height_m
	return lying_head(target_feet, rules)


## The eyes of a player lying at `feet` (the downed pose, LifeLooks.lying, turned with the body):
## where the standing eye height lies once the capsule lies on its side.
static func lying_head(feet: Transform3D, rules: PlayerRules) -> Vector3:
	var standing := LifeLooks.standing(rules)
	var in_mesh := standing.affine_inverse() * Vector3(0.0, rules.eye_height_m, 0.0)
	return feet * (LifeLooks.lying(rules) * in_mesh)
