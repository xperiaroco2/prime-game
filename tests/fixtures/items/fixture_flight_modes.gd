class_name FixtureFlightModes
extends RefCounted
## Game modes and drivers for the unit tests of a thrown item's flight (core/items/, §7.1.16),
## built in code on FixtureItemModes.basic() (a part's unit tests never load `content/`, §9.6).
##
## basic(effect): the item fixture mode (PickUp, PutDown, kinds `package` and `tool`, the note
## "rested <item> <cause> <position>" on item_rested) whose `Use` with an item in hand runs
## `throw` (FixtureThrow: 10 m/s by default), and whose Round lists FlightTicks after LifeTicks.
## The fixture capsule: radius 0.4 m, height 1.8 m, eye at 1.6 m.
##
## with_throw(mode, effect): the same `Use` rule and FlightTicks added to another fixture mode built
## on FixtureItemModes.basic() (FixtureDeliveryModes.basic(), for a thrown package).


static func basic(effect: FixtureThrow = null) -> GameMode:
	return with_throw(FixtureItemModes.basic(), effect)


static func with_throw(mode: GameMode, effect: FixtureThrow = null) -> GameMode:
	var thrown_by := effect if effect != null else FixtureThrow.new()
	mode.actions.append(FixtureModes.rule(Intents.USE, [HoldsItem.new()], [thrown_by]))
	mode.find_phase(&"round").tick_systems.append(FlightTicks.new())
	return mode


## A round of `mode` (basic() by default) asking `world` (a flat floor at 0 by default) with
## `peers`, P1 holding a package at `feet`, which it then throws along `facing`: the launch is
## the next tick's command, and that tick has not run yet.
static func thrown(
	facing: Vector3,
	feet: Vector3 = Vector3.ZERO,
	world: WorldQuery = null,
	mode: GameMode = null,
	peers: Array[int] = [1, 2]
) -> Match:
	var game := FixtureItemModes.in_round(mode if mode != null else basic(), peers, world)
	holding(game, peers[0], feet)
	throw(game, peers[0], facing)
	return game


## The one item in flight, or null.
static func flying(game: Match) -> ItemState:
	for id: int in game.state.items:
		if game.state.items[id].is_in_flight():
			return game.state.items[id]
	return null


## `peer` stands at `feet` and picks up a new package lying there.
static func holding(game: Match, peer: int, feet: Vector3) -> ItemState:
	FixtureItemModes.stand(game, peer, feet)
	var item := FixtureItemModes.lay(game, &"package", feet)
	FixtureItemModes.pick_up(game, peer, item)
	return item


## `peer` throws its hand item along `facing`: a Use stamped with the next tick, the launch tick.
static func throw(game: Match, peer: int, facing: Vector3) -> void:
	FixtureModes.send(game, Intents.USE, peer, {"facing": facing})
