class_name ItemArc
extends RefCounted
## One thrown item's arc as this client draws it (ARCHITECTURE §4.7.25, §7.1.16; the throwing
## ADR's TE5 (a); 37e), pure: no Nodes, no physics. ItemFlights keeps one per item in flight and
## moves its drawn time; ItemViews draws the item's view where position() says.
##
## The drawn time `n` is in ticks after the launch, a float: the thrower's own arc runs on its own
## clock from the key press, every other arc on the host-tick timeline the avatars are drawn on
## (the host tick drawn less the launch tick), so the item leaves the hand as the thrower's body is
## seen throwing it. Between two whole ticks the item is on the straight line from point(k) to
## point(k + 1), the segment the host's FlightTicks sweeps, never on a second copy of the formula:
## at a whole tick it is ItemFlight.point() exactly.
##
## The thrower's prediction starts from its own camera with the vectors ThrowItem would build from
## the client's own copy of the mode (predict(), rule_of()); adopt() swaps in the host's vectors
## from ItemThrown and eases the drawn item onto them over EASE_S. Until the arc's ItemPlaced the
## thrower's client may hold the drawn item at the first wall of its own scene (`blocked_at`,
## ItemFlights' sweep; presentation only).
##
## The end (end_at(), from ItemPlaced with the cause `thrown`): the host drops a stopped item
## straight down (floor_below keeps x and z), so the stop is the arc's point above the rest, found
## from the horizontal distance (stop_of(); a throw with no horizontal speed falls to the rest's
## height). The drawn item flies on to the stop, then falls to the rest with the arc's gravity
## (a short fall). A rest that is not below the arc (the no-floor fallback at the thrower's feet,
## TD11 (a)), or a stop the drawn item has already flown past, ends the arc at once at the rest.

## How far sideways of the arc's line a rest may lie and still be below it, in metres; and how far
## below the rest the stop may seem to be. floor_below keeps x and z, so only float error counts.
## A placeholder, "not a decision".
const REST_TOLERANCE_M := 0.05
## How long the thrower's predicted item takes to ease onto the host's arc, in seconds. A
## placeholder, "not a decision".
const EASE_S := 0.2
## How many ticks past the latest tick the stop can have been at (the host-tick estimate's error)
## a stop may lie: a later point is no stop of this flight. A placeholder, "not a decision".
const STOP_SLACK_TICKS := 3.0
## How many ticks the drawn item may have flown past the stop and still fall from the stop.
const PAST_STOP_TICKS := 1.0
## A squared horizontal speed below this (m²/s²) is a throw straight up or down.
const VERTICAL_SPEED_SQ := 1e-6
## stop_of()'s answer for a rest that is not below the arc.
const NO_STOP := -1.0

var item := -1
var thrower := 0
## o, v and g: the prediction's, then exactly the Vector3s ItemThrown carries.
var origin := Vector3.ZERO
var velocity := Vector3.ZERO
var gravity := Vector3.ZERO
## L: the host tick of the launch (ItemThrown's `tick`); 0 while only predicted.
var launch_tick := 0
## The sphere the thrower's client sweeps through its own scene (the rule's radius); 0: none.
var radius := 0.0
## Drawn on the thrower's own clock from the key press, rather than on the avatars' timeline.
var own := false
## The thrower's prediction, before its ItemThrown arrived.
var predicted := false
## The drawn time, in ticks after the launch; below 0 the launch is not drawn yet.
var n := -INF
## Where the thrower's client held the drawn item at a wall of its own scene; INF: nowhere.
var blocked_at := Vector3.INF
## Where the drawn item was last placed (the sweep starts there).
var drawn := Vector3.INF
## ItemPlaced arrived: where the item rests, and its fields (the landing sound plays with them).
var ended := false
var rest := Vector3.INF
var landing := {}
## The launch sound was played (or is not this arc's to play).
var launch_heard := false

## The fall: from `fall_from` at drawn time `fall_start_n`, lasting `fall_s` seconds.
var _fall_from := Vector3.INF
var _fall_start_n := 0.0
var _fall_s := 0.0
## Ended at once at the rest.
var _snapped := false
## What adopt() added to keep the drawn item where it was, fading out over EASE_S.
var _offset := Vector3.ZERO
var _ease_left_s := 0.0


## The ThrowItem of the first Throw rule core would run for an item of kind `item_kind` in the
## hand of a player of role `role_id`: the item kind's actions, then the role's, then the mode's
## (ARCHITECTURE §9.2), the first rule whose trigger is Throw, its first ThrowItem; null when that
## rule holds none, or no rule is found (the client then throws nothing).
static func rule_of(mode: GameMode, item_kind: StringName, role_id: StringName) -> ThrowItem:
	if mode == null:
		return null
	var kind := mode.find_item_kind(item_kind)
	var rule := _first_throw(kind.actions) if kind != null else null
	var role := mode.find_role(role_id)
	if rule == null and role != null:
		rule = _first_throw(role.actions)
	if rule == null:
		rule = _first_throw(mode.actions)
	if rule == null:
		return null
	for effect: RuleEffect in rule.effects:
		if effect is ThrowItem:
			return effect as ThrowItem
	return null


## The thrower's prediction of item `item_id` thrown by `peer` with `rule`'s numbers from its own
## camera at `eye` along `look`: the velocity and gravity built as ThrowItem builds them, so for
## the same facing they are the host's bit for bit.
static func predict(
	rule: ThrowItem, item_id: int, peer: int, eye: Vector3, look: Vector3
) -> ItemArc:
	var arc := ItemArc.new()
	arc.item = item_id
	arc.thrower = peer
	arc.origin = eye
	arc.velocity = ThrowItem.unit_facing(look, Vector3.FORWARD) * rule.speed_mps
	arc.gravity = Vector3(0.0, -rule.gravity_mps2, 0.0)
	arc.radius = rule.radius_m
	arc.own = true
	arc.predicted = true
	arc.n = 0.0
	arc.drawn = eye
	arc.launch_heard = true
	return arc


## The arc of an ItemThrown (`fields`), drawn on the avatars' timeline.
static func thrown(fields: Dictionary) -> ItemArc:
	var arc := ItemArc.new()
	arc.item = fields["item"] as int
	arc.thrower = fields["peer"] as int
	arc.origin = fields["origin"] as Vector3
	arc.velocity = fields["velocity"] as Vector3
	arc.gravity = fields["gravity"] as Vector3
	arc.launch_tick = fields["tick"] as int
	return arc


## The arc's point at drawn time `at_n` (ticks after the launch, at least 0): ItemFlight.point()
## at a whole tick, on the straight line between two whole ticks' points in between.
static func point_at(from: Vector3, speed: Vector3, down: Vector3, at_n: float) -> Vector3:
	var whole := floori(at_n)
	var part := at_n - whole
	var before := ItemFlight.point(from, speed, down, whole)
	if part <= 0.0:
		return before
	return before.lerp(ItemFlight.point(from, speed, down, whole + 1), part)


## The drawn time of the stop above rest `at`, for a flight that cannot have stopped after tick
## `latest_n` (ticks after the launch, give or take STOP_SLACK_TICKS): the arc's point whose x
## and z are the rest's; with no horizontal speed, where the arc falls back to the rest's height.
## NO_STOP when the rest is not below the arc: off its line, behind the launch, above the arc's
## point, or under a point the flight cannot have reached yet.
static func stop_of(
	from: Vector3, speed: Vector3, down: Vector3, at: Vector3, latest_n: float
) -> float:
	var flat := Vector2(speed.x, speed.z)
	var away := Vector2(at.x - from.x, at.z - from.z)
	var stop := 0.0
	if flat.length_squared() < VERTICAL_SPEED_SQ:
		if away.length() > REST_TOLERANCE_M or down.y >= 0.0:
			return NO_STOP
		# Straight up or down: the later root of from.y + v·s + ½·g·s² = at.y, no later than the
		# latest tick (a ceiling may have stopped it on the way up).
		var a := 0.5 * down.y
		var discriminant := speed.y * speed.y - 4.0 * a * (from.y - at.y)
		if discriminant < 0.0:
			return NO_STOP
		var seconds := (-speed.y - sqrt(discriminant)) / (2.0 * a)
		stop = clampf(seconds * Ticks.RATE, 0.0, maxf(0.0, latest_n + STOP_SLACK_TICKS))
	else:
		var seconds := away.dot(flat) / flat.length_squared()
		var beside := away - flat * seconds
		if beside.length() > REST_TOLERANCE_M or seconds * flat.length() < -REST_TOLERANCE_M:
			return NO_STOP
		stop = maxf(0.0, seconds * Ticks.RATE)
		if stop > latest_n + STOP_SLACK_TICKS:
			return NO_STOP
	if point_at(from, speed, down, stop).y < at.y - REST_TOLERANCE_M:
		return NO_STOP
	return stop


## Where the item is drawn now: Vector3.INF before the launch is drawn (n < 0).
func position() -> Vector3:
	return position_at(n)


## Where the item is drawn at drawn time `at_n`.
func position_at(at_n: float) -> Vector3:
	if _snapped:
		return rest
	if _fall_from.is_finite() and at_n >= _fall_start_n:
		var seconds := (at_n - _fall_start_n) / Ticks.RATE
		if seconds >= _fall_s:
			return rest
		var flat := Vector2(_fall_from.x, _fall_from.z).lerp(
			Vector2(rest.x, rest.z), seconds / _fall_s
		)
		var height := _fall_from.y - 0.5 * gravity.length() * seconds * seconds
		return Vector3(flat.x, maxf(height, rest.y), flat.y)
	if blocked_at.is_finite():
		return blocked_at
	if at_n < 0.0:
		return Vector3.INF
	return point_at(origin, velocity, gravity, at_n) + _offset * (_ease_left_s / EASE_S)


## The host's ItemThrown for the thrower's own prediction: its vectors and launch tick replace the
## prediction's, and the drawn item eases from where it is onto the host's arc over EASE_S. The
## drawn time stays on the thrower's clock: it never jumps back.
func adopt(fields: Dictionary) -> void:
	var before := position()
	origin = fields["origin"] as Vector3
	velocity = fields["velocity"] as Vector3
	gravity = fields["gravity"] as Vector3
	launch_tick = fields["tick"] as int
	predicted = false
	if before.is_finite() and not blocked_at.is_finite() and n >= 0.0:
		_offset = before - point_at(origin, velocity, gravity, n)
		_ease_left_s = EASE_S


## The easing's clock: `delta` seconds passed.
func ease_by(delta: float) -> void:
	_ease_left_s = maxf(0.0, _ease_left_s - delta)


## ItemPlaced with the cause `thrown` (`fields`): the item rests at its position. `latest_n` is
## the latest drawn time its flight can have stopped at: the thrower's own clock now, or the
## estimated host tick when it arrived less the launch tick.
func end_at(fields: Dictionary, latest_n: float) -> void:
	ended = true
	landing = fields
	rest = fields["position"] as Vector3
	var stop := stop_of(origin, velocity, gravity, rest, latest_n)
	if blocked_at.is_finite():
		_fall_from = blocked_at
		_fall_start_n = maxf(n, 0.0)
	elif stop == NO_STOP or n > stop + PAST_STOP_TICKS:
		_snapped = true
		return
	else:
		_fall_from = position_at(stop)
		_fall_start_n = stop
	var drop := maxf(0.0, _fall_from.y - rest.y)
	var pull := gravity.length()
	_fall_s = sqrt(2.0 * drop / pull) if pull > 0.0 else 0.0


## The item lies at its rest in the drawing too (ItemPlaced came and the fall is over).
func finished() -> bool:
	if _snapped:
		return true
	return _fall_from.is_finite() and n >= _fall_start_n + _fall_s * Ticks.RATE


static func _first_throw(rules: Array[Rule]) -> Rule:
	for rule: Rule in rules:
		if rule.trigger == Intents.THROW:
			return rule
	return null
