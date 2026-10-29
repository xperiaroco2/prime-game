class_name PoseUse
extends RefCounted
## Whether E offers Pose (#1383; ARCHITECTURE §7.1.19), pure: from the client's own copy of the
## mode and the level's chair markers, never `core/` state. The base mode gates its Pose row with
## an AtMarker (the camera wall's chair, the engineer's answer 1a on PR #1382), so the key reads
## that condition's tag, radius and height from the row itself and tests the own feet with the
## host's own geometry (AtMarker.contains): a number retuned in the mode moves the key with it,
## and no tag or number is written here. The host still decides (§7.1); this only keeps E from
## sending a Pose the host would refuse with `out_of_reach`.

## The spawn group prefix of a marker tag (ARCHITECTURE §9.6), as StationViews and MapData read it.
const GROUP_PREFIX := "spawn_"


## The AtMarker of `mode`'s first Pose action rule, or null when the mode has no Pose rule or the
## rule no such condition (ModeCheck refuses the latter, so the key sends nothing for it).
static func chair_of(mode: GameMode) -> AtMarker:
	if mode == null:
		return null
	for rule: Rule in mode.actions:
		if rule == null or rule.trigger != Intents.POSE:
			continue
		for condition: Condition in rule.conditions:
			if condition is AtMarker and not condition.negate:
				return condition
		return null
	return null


## The group whose Marker3Ds stand for `chair`'s markers in the loaded level.
static func group_of(chair: AtMarker) -> StringName:
	return StringName(GROUP_PREFIX + String(chair.tag))


## Whether `feet` stands inside `chair`'s cylinder at any of `spots` (the level's markers of
## its tag).
static func at_chair(chair: AtMarker, spots: PackedVector3Array, feet: Vector3) -> bool:
	if chair == null:
		return false
	for spot: Vector3 in spots:
		if AtMarker.contains(feet, spot, chair.radius_m, chair.height_m):
			return true
	return false
