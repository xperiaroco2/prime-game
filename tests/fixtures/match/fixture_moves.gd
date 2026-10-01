class_name FixtureMoves
extends RefCounted
## Drives the movement rule and the stamina ledger (ARCHITECTURE §7.1) in unit tests: a round of
## FixtureModes.basic() on a given world, and MoveClaims. A claim's client tick is the host tick it
## is applied on, as an honest client in step with the host sends it, unless a test gives one.
##
## The numbers are FixtureModes.player_rules(), the MVP's (§9.5): per 20 Hz tick a living player
## walks 0.225 m and sprints 0.35 m, may be pushed 0.35 m more near another living player (within
## MovementRule.push_reach(), 2.2 m, of the claim's path), and the check adds 0.05 m; sprint
## costs 1000 thousandths per tick, regeneration gives 750; a downed player crawls 0.05 m, with
## no sprint and no push allowance.


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
