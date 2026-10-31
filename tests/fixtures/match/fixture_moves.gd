class_name FixtureMoves
extends RefCounted
## Drives the movement rule and the stamina ledger (ARCHITECTURE §7.1) in unit tests: a round of
## FixtureModes.basic() on a given world, and MoveClaims. A claim's client tick is the host tick it
## is applied on, as an honest client in step with the host sends it, unless a test gives one.
##
## The numbers are FixtureModes.player_rules(), the MVP's (§9.5): per 20 Hz tick a living player
## walks 0.225 m and sprints 0.35 m, may be pushed 0.35 m more near another living player (within
## MovementRule.push_reach(), 2.2 m, of the claim's path), and the check adds 0.05 m; sprint
## costs 1000 thousandths per tick, regeneration gives 750; a downed player moves nothing (its
## claims carry its facing only, KE4).
##
## posing(mode): `mode` with a Pose rule (AtMarker on SEAT_TAG, TakePose) and Round accepting it
## from the living (#1296, #1383); seat(game, peer) puts a seat beside `peer`.
##
## wheeling(mode): `mode` with the pose wheel (#1485): WheelPoses of LEGS leg and ARMS arm ids, a
## WheelPose rule as the base mode's (WheelPoseInRange, Posed negated, CrouchedOrSneaking negated,
## HandNotTwoHanded; TakeWheelPose), and Lobby and Round accepting it from the living.

## The spawn tag of the fixture's seats (posing, seat).
const SEAT_TAG := &"seat"
## The seat's cylinder: the base mode's placeholders (not a decision).
const SEAT_RADIUS_M := 1.0
const SEAT_HEIGHT_M := 2.0
## Where seat() puts a seat from the player: inside the radius, off the player's own spot.
const SEAT_OFFSET := Vector3(0.5, 0, 0)
## How many leg stances and arm gestures wheeling() gives the mode (fixture ids, not the content's).
const LEGS := 3
const ARMS := 4


## A match of the fixture mode on `world` (FixtureTerrainWorld when null) whose `peers` joined,
## readied and were placed in the round (epoch 1, on the ground at y = 0).
static func in_round(peers: Array[int], world: WorldQuery = null) -> Match:
	var used := world if world != null else FixtureTerrainWorld.new()
	var game := Match.new(FixtureModes.basic(), 7, used, FixtureModes.layouts())
	game.keep_history = true
	game.start(0)
	for peer: int in peers:
		FixtureModes.send(game, Intents.HELLO, peer, {"name": "p%d" % peer})
	for peer: int in peers:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	return game


## A MoveClaim of `peer` at `position` in its current epoch, applied on the next host tick. On the
## floor, standing still and without sprint unless `fields` says otherwise; `fields` may also set
## the epoch, the client tick, the velocity, the facing and the jump count, which is by default
## the count the host last accepted in the epoch (jumps_of): no new jump. jumped() adds one.
static func claim(game: Match, peer: int, position: Vector3, fields: Dictionary = {}) -> void:
	var player := game.state.player(peer)
	var args := {
		"epoch": player.epoch,
		"client_tick": game.ticked_through() + 1,
		"position": position,
		"velocity": Vector3.ZERO,
		"facing": Vector3.FORWARD,
		"sprint": false,
		"moving": false,
		"jumps": jumps_of(game, peer),
		"on_floor": true,
	}
	args.merge(fields, true)
	FixtureModes.send(game, Intents.MOVE_CLAIM, peer, args)


## Claims `peer` moved by `offset` from where the host has it, then runs the tick.
static func step(game: Match, peer: int, offset: Vector3, fields: Dictionary = {}) -> void:
	claim(game, peer, game.state.player(peer).position + offset, fields)
	FixtureModes.run_ticks(game, 1)


## The fields of a claim that jumps once more than the host last accepted, in the air, plus `more`.
static func jumped(game: Match, peer: int, more: Dictionary = {}) -> Dictionary:
	var fields := {"jumps": jumps_of(game, peer) + 1, "on_floor": false}
	fields.merge(more, true)
	return fields


## The jump count of `peer`'s last accepted claim in its current epoch (0 before any, and after a
## placement or a Correction): what an honest client in step with the host counts (§4.3, E2).
static func jumps_of(game: Match, peer: int) -> int:
	var table := (
		game.state.part_state(
			MovementRule.PART_KEY, func() -> RefCounted: return MovementRule.MotionTable.new()
		)
		as MovementRule.MotionTable
	)
	var motion: MovementRule.Motion = table.by_peer.get(peer)
	if motion == null or motion.epoch != game.state.player(peer).epoch:
		return 0
	return motion.jumps


## `count` steps of `offset`.
static func steps(
	game: Match, peer: int, count: int, offset: Vector3, fields: Dictionary = {}
) -> void:
	for i in count:
		step(game, peer, offset, fields)


## The sprint flags of a player sprinting by its own input.
static func sprinting() -> Dictionary:
	return {"sprint": true, "moving": true}


## The Corrections `peer` received, in order.
static func corrections(game: Match, peer: int) -> Array[CorrectionEvent]:
	var found: Array[CorrectionEvent] = []
	for event: MatchEvent in game.view_of(peer).events_named(&"Correction"):
		found.append(event as CorrectionEvent)
	return found


## The SelfStatus events `peer` received, in order.
static func statuses(game: Match, peer: int) -> Array[SelfStatusEvent]:
	var found: Array[SelfStatusEvent] = []
	for event: MatchEvent in game.view_of(peer).events_named(&"SelfStatus"):
		found.append(event as SelfStatusEvent)
	return found


## `mode` with a Pose rule appended to its actions, gated by the seat (AtMarker on SEAT_TAG,
## SEAT_RADIUS_M wide, SEAT_HEIGHT_M tall; TakePose requires it), and Round accepting Pose from
## the living only (#1296, #1383). The fixture layouts hold no seat: a test puts one with seat().
static func posing(mode: GameMode) -> GameMode:
	var rule := FixtureModes.rule(Intents.POSE, [seat_condition()], [TakePose.new()])
	mode.actions.append(rule)
	mode.find_phase(&"round").accepts.append(AcceptSpec.of(Intents.POSE, AcceptSpec.From.LIVING))
	return mode


## The fixture's seat condition: AtMarker on SEAT_TAG.
static func seat_condition() -> AtMarker:
	var at := AtMarker.new()
	at.tag = SEAT_TAG
	at.radius_m = SEAT_RADIUS_M
	at.height_m = SEAT_HEIGHT_M
	return at


## Puts a seat (a SEAT_TAG marker) SEAT_OFFSET from `peer`'s position into the layout of the map
## `game` plays, so `peer` stands at it. The layout is the object the match was handed (Match keeps
## the layouts it got), changed after the match checked it; a marker beside the player, never on
## a spot of another tag, as LayoutCheck wants of a level (one tag per position).
static func seat(game: Match, peer: int) -> Vector3:
	var spot := game.state.player(peer).position + SEAT_OFFSET
	game.layout(game.state.map).add_marker(SEAT_TAG, spot)
	return spot


## `peer` sends the Pose intent, applied on the next host tick.
static func pose(game: Match, peer: int, seq: int = 0) -> void:
	FixtureModes.send(game, Intents.POSE, peer, {}, seq)


## A context of `game` on its next tick, for calling a rule helper (LifeRules.kill) between ticks,
## as kill_test.gd does: whatever it touches is flushed at the end of that tick.
static func context(game: Match) -> MatchContext:
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = game.mode
	ctx.world = FlatWorldQuery.new()
	ctx.tick = game.ticked_through() + 1
	return ctx


## `mode` with the pose wheel (#1485): WheelPoses of LEGS and ARMS fixture ids, the WheelPose rule
## with the base mode's conditions in its order, and Lobby and Round accepting WheelPose from the
## living only.
static func wheeling(mode: GameMode) -> GameMode:
	var poses := WheelPoses.new()
	for index in LEGS:
		poses.legs.append("legs_%d" % index)
	for index in ARMS:
		poses.arms.append("arms_%d" % index)
	mode.wheel_poses = poses
	var posed := Posed.new()
	posed.negate = true
	var lowered := CrouchedOrSneaking.new()
	lowered.negate = true
	var conditions: Array[Condition] = [
		WheelPoseInRange.new(), posed, lowered, HandNotTwoHanded.new()
	]
	mode.actions.append(FixtureModes.rule(Intents.WHEEL_POSE, conditions, [TakeWheelPose.new()]))
	for phase: StringName in [&"lobby", &"round"]:
		mode.find_phase(phase).accepts.append(
			AcceptSpec.of(Intents.WHEEL_POSE, AcceptSpec.From.LIVING)
		)
	return mode


## `peer` sends the WheelPose intent of (`legs`, `arms`), applied on the next host tick.
static func wheel_pose(game: Match, peer: int, legs: int, arms: int, seq: int = 0) -> void:
	FixtureModes.send(game, Intents.WHEEL_POSE, peer, {"legs": legs, "arms": arms}, seq)
