class_name FootstepSurface
extends RefCounted
## Which floor a footstep is on (#525; ARCHITECTURE §4.7.40): the tag `surface` (metadata) of the
## floor's collider or its nearest ancestor that has one, one of SURFACES; an untagged floor or an
## unknown tag is DEFAULT. The greybox tags nothing, so every step there is DEFAULT; the house's
## floors (#523, the content area) tag theirs. One ray down from above the feet against the world
## layer finds the floor; nothing there means the feet are off the ground (a jump), and no step.

## The tag a floor's collider or an ancestor carries.
const META := &"surface"
## The surfaces with sounds (SfxSet's footsteps), and the one an untagged floor is. Which surfaces
## and which default: placeholders, "not a decision".
const SURFACES: Array[StringName] = [&"concrete", &"wood", &"carpet", &"grass"]
const DEFAULT := &"concrete"
## How far above and below the feet the ray looks for the floor: a step's height up, and a
## stair's edge or a slope down.
const ABOVE_M := 0.3
const BELOW_M := 0.5


## The surface a tag names, DEFAULT for anything else.
static func resolve(tag: Variant) -> StringName:
	if tag is String or tag is StringName:
		var name := StringName(tag as String)
		if name in SURFACES:
			return name
	return DEFAULT


## The surface of `collider`: the tag of the nearest of it and its ancestors that has one.
static func of(collider: Object) -> StringName:
	var node := collider as Node
	while node != null:
		if node.has_meta(META):
			return resolve(node.get_meta(META))
		node = node.get_parent()
	return DEFAULT


## The surface under the feet at `feet`, or null when no floor is there.
static func under(space: PhysicsDirectSpaceState3D, feet: Vector3) -> Variant:
	var query := PhysicsRayQueryParameters3D.create(
		feet + Vector3.UP * ABOVE_M, feet + Vector3.DOWN * BELOW_M, PhysicsLayers.WORLD
	)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	return of(hit["collider"] as Object)
