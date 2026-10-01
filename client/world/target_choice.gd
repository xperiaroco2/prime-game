class_name TargetChoice
extends RefCounted
## Which item the crosshair would pick up (ARCHITECTURE §4.7, Interactions; M4-8), pure. The
## camera's ray picks the candidate: the first item lying on the ground (not held, not delivered)
## whose look the ray enters, nearer than the first wall along it. The hint and the key then apply
## only if the mode's InReach of PickUp holds, measured as the host measures it: from the feet of
## the player to where the item lies, not along the ray from the eye 1.6 m higher. So a crate-top
## item the host would refuse gets no hint, and a floor item it would accept does. The client
## mirrors the host's OnGround, InReach and (in ItemInteractions) InSight; the host checks
## everything again (§7.1); this only decides what to offer.

## How far the camera's ray looks for an item, in metres: past any reach the host grants, since
## the reach is checked from the feet afterwards.
const RAY_M := 4.0
## How close the ray must pass to an item's middle to pick it, in metres (a look, not a rule).
const PICK_RADIUS_M := 0.3


## The reach of the mode's PickUp (its InReach), in metres from the feet; 0 when the mode has
## none, which offers nothing.
static func reach_of(mode: GameMode) -> float:
	for rule: Rule in mode.actions:
		if rule.trigger != Intents.PICK_UP:
			continue
		for condition: Condition in rule.conditions:
			var reach := condition as InReach
			if reach != null:
				return reach.reach_m
	return 0.0


## The item the crosshair is on that passes the host's OnGround and InReach, or -1: the ray from
## `eye` along `look` (a unit vector) reaches `blocked_at` metres before the level stops it. The
## host's third check, InSight, needs the physics space: ItemInteractions casts it afterwards.
static func choose(
	model: ClientModel, eye: Vector3, look: Vector3, blocked_at: float, feet: Vector3, reach: float
) -> int:
	var picked := along_ray(model, eye, look, minf(blocked_at, RAY_M))
	if picked < 0:
		return -1
	return picked if feet.distance_to(model.items[picked].position) <= reach else -1


## The first item on the ground whose middle the ray from `eye` along `look` passes within
## PICK_RADIUS_M of, no farther than `length` metres; -1 for none.
static func along_ray(model: ClientModel, eye: Vector3, look: Vector3, length: float) -> int:
	var best := -1
	var best_t := INF
	for id: int in model.items:
		var item := model.items[id]
		if item.holder != ClientModel.NO_HOLDER or item.delivered:
			continue
		var t := enters_at(eye, look, ItemView.centre_of(item.kind, item.position), PICK_RADIUS_M)
		if t >= 0.0 and t <= length and t < best_t:
			best = id
			best_t = t
	return best


## How far along the ray from `origin` along the unit `direction` it enters the sphere of `radius`
## around `centre` (0 when it starts inside); -1 when it misses or the sphere is behind.
static func enters_at(origin: Vector3, direction: Vector3, centre: Vector3, radius: float) -> float:
	var to_centre := centre - origin
	var along := to_centre.dot(direction)
	var miss_sq := to_centre.length_squared() - along * along
	if miss_sq > radius * radius:
		return -1.0
	var half_chord := sqrt(radius * radius - miss_sq)
	var t := along - half_chord
	if t < 0.0:
		return 0.0 if along + half_chord >= 0.0 else -1.0
	return t
