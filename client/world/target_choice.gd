class_name TargetChoice
extends RefCounted
## Which item the crosshair would pick up (ARCHITECTURE §4.7, Interactions; M4-8), pure. The
## camera's ray picks the candidate: the first item lying on the ground (not held, not delivered)
## whose look the ray enters, nearer than the first wall along it. The hint and the key then apply
## only if the mode's InReach of PickUp holds, measured as the host measures it: from the feet of
## the player to where the item lies, not along the ray from the eye 1.6 m higher. So a crate-top
## item the host would refuse gets no hint, and a floor item it would accept does. The hint stops
## a margin short of the reach (hint_reach_of, #319): the host measures from the feet of the last
## claim it accepted, which trail the player's own while walking in. The client mirrors the
## host's OnGround, InReach and (in ItemInteractions) InSight; the host checks everything again
## (§7.1); this only decides what to offer.
##
## Stations (#801, §4.7.54): choose_target() weighs the item against the stations StationUse
## offers. A station is a candidate only where the ray meets its device (the station scene's own
## collision, hit at `blocked_at`: ItemInteractions asks StationViews whose it is) or its use spot
## (a sphere of STATION_AIM_RADIUS_M a little above the floor point StationPlaced gives, entered no
## farther than `blocked_at`), and only while the feet stand in its cylinder (the host's AtStation)
## less the hint's walking margin. The nearest along the ray wins, an item on a tie: an item lying
## inside a station's cylinder in front of the device is named, one behind the device's face never.

## How far the camera's ray looks for an item, in metres: past any reach the host grants, since
## the reach is checked from the feet afterwards.
const RAY_M := 4.0
## How close the ray must pass to an item's middle to pick it, in metres (a look, not a rule).
const PICK_RADIUS_M := 0.3
## How far short of the host's reach the hint stops, in seconds of walking at the mode's
## `walk_speed_mps` (#319; a look, not a rule; the number is not a decision). The host measures
## InReach from the feet of the last MoveClaim it accepted, which trail the feet the hint
## measures from (§7.1): a claim goes once per client tick (20 Hz, Ticks.RATE) against 60 Hz
## physics, and it carries the step before it (the session claims at the start of the physics
## step, before the controller moves). E's PickUp (or Raise: LifeView's raise hint stops the same
## margin short, #352) goes before the next claim, so on an even clock the host's feet trail by 1
## to 3 steps: one claim interval, 1/20 s. A clock that stalls and then jumps puts 4 steps into a
## claim interval now and then, so the margin is one claim interval plus one physics step, 1/20 +
## 1/60 s = 4/60 s: 0.3 m at the base mode's 4.5 m/s, and the hint shows from 1.7 m of its 2 m.
## Sprinting in (7 m/s) can still outrun it; once the player stands, the host catches up within a
## claim.
const HINT_MARGIN_S := 1.0 / Ticks.RATE + 1.0 / 60.0
## The use spot's sphere the ray may name a station by, in metres, and how far above the floor
## point its middle sits (looks, not rules; placeholders, "not a decision"): where no station scene
## stands (a greybox level) the use spot is all there is to aim at.
const STATION_AIM_RADIUS_M := 0.4
const STATION_AIM_LIFT_M := 0.4
## Float noise under a station's floor the feet may stand at, as the host's AtStation allows.
const FLOOR_SLACK_M := 0.005


## What the crosshair names: an item, a station, or nothing; `t` how far along the ray.
class Target:
	extends RefCounted

	enum Kind { NONE, ITEM, STATION }

	var kind := Kind.NONE
	var id := -1
	var t := INF

	func _init(target_kind: Kind = Kind.NONE, target_id: int = -1, at: float = INF) -> void:
		kind = target_kind
		id = target_id
		t = at

	func is_item() -> bool:
		return kind == Kind.ITEM

	func is_station() -> bool:
		return kind == Kind.STATION


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


## The reach the hint and E offer an item within, in metres from the feet: the mode's PickUp
## reach less the walking margin (hint_reach()), so E at the first hint while walking in is not
## refused `out_of_reach` (#319); 0 when the mode has no PickUp.
static func hint_reach_of(mode: GameMode) -> float:
	return hint_reach(reach_of(mode), mode)


## The reach a hint offers within, in metres from the feet, for an action the host grants within
## `reach_m` of the feet of the last claim it accepted (PickUp's InReach; the raise's
## TargetInReach in LifeView, #352): `reach_m` less the distance walked at `mode`'s
## `walk_speed_mps` in HINT_MARGIN_S. Never less than half the reach, so a short reach in a fast
## mode still offers something; 0 for a reach of 0.
static func hint_reach(reach_m: float, mode: GameMode) -> float:
	var walk := mode.player_rules.walk_speed_mps if mode.player_rules != null else 0.0
	return maxf(reach_m - walk * HINT_MARGIN_S, reach_m / 2.0)


## The item the crosshair is on that passes the host's OnGround and InReach, or -1: the ray from
## `eye` along `look` (a unit vector) reaches `blocked_at` metres before the level stops it. The
## host's third check, InSight, needs the physics space: ItemInteractions casts it afterwards.
static func choose(
	model: ClientModel,
	eye: Vector3,
	look: Vector3,
	blocked_at: float,
	feet: Vector3,
	reach: float,
	aim_of: Callable = Callable()
) -> int:
	var picked := along_ray(model, eye, look, minf(blocked_at, RAY_M), aim_of)
	if picked < 0:
		return -1
	return picked if feet.distance_to(model.items[picked].position) <= reach else -1


## What the crosshair names (see the class doc): the item choose() offers within `item_reach` of
## the feet (0: none), or a station StationUse offers that the ray meets, at its device
## (`device_station`, the station whose scene the level's ray hit at `blocked_at`; -1 for none) or
## at its use spot, while `feet` stand in its cylinder less the hint's margin; the nearest along the
## ray, an item on a tie; NONE for nothing. The host's InSight of a station (StationInSight) needs
## the physics space: ItemInteractions casts it afterwards.
static func choose_target(
	model: ClientModel,
	mode: GameMode,
	eye: Vector3,
	look: Vector3,
	blocked_at: float,
	feet: Vector3,
	item_reach: float,
	device_station: int,
	aim_of: Callable = Callable()
) -> Target:
	var best := Target.new()
	var length := minf(blocked_at, RAY_M)
	if item_reach > 0.0:
		var picked := choose(model, eye, look, blocked_at, feet, item_reach, aim_of)
		var item: ClientModel.Item = model.items.get(picked)
		# A wrong ingredient on a place the hand can use there: the put wins (#776).
		if (
			item != null
			and item.on_station >= 0
			and StationUse.usable(model, mode, item.on_station)
		):
			picked = -1
		if picked >= 0:
			var centre: Vector3 = aim_at(model, picked, aim_of)
			best = Target.new(Target.Kind.ITEM, picked, enters_at(eye, look, centre, PICK_RADIUS_M))
	for id: int in model.stations:
		var station := model.stations[id]
		# Where the feet stand first: it culls all but the few stations in reach before the
		# costlier usable (#1530: every station of the estate each physics tick).
		if not stands_at(station, mode, feet) or not StationUse.usable(model, mode, id):
			continue
		var t := blocked_at if id == device_station else INF
		var spot := enters_at(eye, look, aim_point(station), STATION_AIM_RADIUS_M)
		if spot >= 0.0 and spot <= length:
			t = minf(t, spot)
		if t < best.t:
			best = Target.new(Target.Kind.STATION, id, t)
	return best


## The middle of a station's use-spot sphere: STATION_AIM_LIFT_M above its floor point.
static func aim_point(station: ClientModel.Station) -> Vector3:
	return station.position + Vector3.UP * STATION_AIM_LIFT_M


## Whether `feet` stand in `station`'s cylinder as the host's AtStation measures it (its kind's
## radius across, from its floor up to its height, with float noise below), the radius less the
## hint's walking margin (hint_reach()); false for a kind the mode does not name.
static func stands_at(station: ClientModel.Station, mode: GameMode, feet: Vector3) -> bool:
	var kind := StationUse.kind_of(mode, station.kind)
	if kind == null:
		return false
	var flat := Vector2(feet.x - station.position.x, feet.z - station.position.z).length()
	var rise := feet.y - station.position.y
	return (
		flat <= hint_reach(kind.radius_m, mode) and rise >= -FLOOR_SLACK_M and rise <= kind.height_m
	)


## The item on the ground whose middle the ray from `eye` along `look` passes within PICK_RADIUS_M
## of, entering that sphere no farther than `length` metres; -1 for none. Of several, the one the
## crosshair is closest to wins (the smallest miss), then the nearer along the ray: a package a
## hand's width off the aim line never wins over a knife the crosshair is on.
static func along_ray(
	model: ClientModel, eye: Vector3, look: Vector3, length: float, aim_of: Callable = Callable()
) -> int:
	var best := -1
	var best_miss := INF
	var best_t := INF
	for id: int in model.items:
		var item := model.items[id]
		if not item.rests() or item.delivered or item.locked:
			continue
		var aim: Variant = aim_at(model, id, aim_of)
		if aim == null:
			continue
		var centre: Vector3 = aim
		var t := enters_at(eye, look, centre, PICK_RADIUS_M)
		if t < 0.0 or t > length:
			continue
		var to_centre := centre - eye
		var along := to_centre.dot(look)
		var miss := snappedf(sqrt(maxf(to_centre.length_squared() - along * along, 0.0)), 0.001)
		if miss < best_miss or (miss == best_miss and t < best_t):
			best = id
			best_miss = miss
			best_t = t
	return best


## Where the crosshair aims at item `id`: the middle of its look where it lies; for an item lying
## on a cooking station (a wrong ingredient on a plate, #776) the point `aim_of` (CookingViews.
## aim_of: id -> Vector3, or null) gives where the plate draws it, never its floor point (the use
## spot the host measures reach from); a photo on the printer's tray or taken down on the board at
## where PhotoViews draws it (#787); null when it is drawn nowhere aimable (the film in a camera).
static func aim_at(model: ClientModel, id: int, aim_of: Callable = Callable()) -> Variant:
	var item: ClientModel.Item = model.items.get(id)
	if item == null:
		return null
	var aim: Variant = aim_of.call(id) if aim_of.is_valid() else null
	if item.on_station < 0:
		return aim if aim is Vector3 else ItemView.centre_of(item.kind, item.position)
	return aim


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
