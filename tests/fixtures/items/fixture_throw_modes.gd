class_name FixtureThrowModes
extends RefCounted
## Game modes and drivers for the unit tests of the Throw intent and ThrowItem (core/items/,
## §7.1.16), built in code on FixtureItemModes.basic() (a part's unit tests never load `content/`,
## §9.6).
##
## basic(from): the item fixture mode (PickUp, PutDown, kinds `package` and `tool`, the note
## "rested <item> <cause> <position>" on item_rested) with the mode's Throw rule, HoldsItem and
## OverFloor then ThrowItem at the numbers below, and a Round that accepts Throw from `from`
## (living players by default) and lists FlightTicks after LifeTicks. The fixture capsule: radius
## 0.4 m, height 1.8 m, eye at 1.6 m, so a throw radius up to 0.19 m fits it.
##
## The numbers are a test's, not a decision: the base mode's are in content/ (#646).

const SPEED_MPS := 10.0
const GRAVITY_MPS2 := 9.8
const RADIUS_M := 0.15
const LONGEST_FLIGHT_S := 3.0


static func basic(from: int = AcceptSpec.From.LIVING) -> GameMode:
	return with_throw(FixtureItemModes.basic(), from)


## The Throw rule and FlightTicks added to another fixture mode built on FixtureItemModes.basic().
static func with_throw(mode: GameMode, from: int = AcceptSpec.From.LIVING) -> GameMode:
	mode.actions.append(throw_rule(effect()))
	var round_spec := mode.find_phase(&"round")
	round_spec.accepts.append(AcceptSpec.of(Intents.THROW, from))
	round_spec.tick_systems.append(FlightTicks.new())
	return mode


## A ThrowItem at `speed` and the fixture's other numbers.
static func effect(speed: float = SPEED_MPS) -> ThrowItem:
	var thrown_by := ThrowItem.new()
	thrown_by.speed_mps = speed
	thrown_by.gravity_mps2 = GRAVITY_MPS2
	thrown_by.radius_m = RADIUS_M
	thrown_by.longest_flight_s = LONGEST_FLIGHT_S
	return thrown_by


## A Throw rule: HoldsItem, OverFloor, then `thrown_by`.
static func throw_rule(thrown_by: ThrowItem) -> Rule:
	return FixtureModes.rule(Intents.THROW, [HoldsItem.new(), OverFloor.new()], [thrown_by])


## `peer` throws its hand item along `facing`: a Throw stamped with the next tick, the launch tick.
static func throw(game: Match, peer: int, facing: Vector3, seq: int = 0) -> void:
	FixtureModes.send(game, Intents.THROW, peer, {"facing": facing}, seq)


## The one item in flight, or null.
static func flying(game: Match) -> ItemState:
	return FixtureFlightModes.flying(game)


## The ItemThrown events `peer` received.
static func thrown_seen_by(game: Match, peer: int) -> Array[ItemThrownEvent]:
	var found: Array[ItemThrownEvent] = []
	for event: MatchEvent in game.view_of(peer).events_named(&"ItemThrown"):
		found.append(event as ItemThrownEvent)
	return found
