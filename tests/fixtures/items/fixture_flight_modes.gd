class_name FixtureFlightModes
extends RefCounted
## Game modes and drivers for the unit tests of a thrown item's flight (core/items/, §7.1.16),
## built in code on FixtureItemModes.basic() (a part's unit tests never load `content/`, §9.6).
##
## basic(throw): the item fixture mode (PickUp, PutDown, kinds `package` and `tool`, the note
## "rested <item> <cause> <position>" on item_rested) whose `Use` with an item in hand runs
## `throw` (FixtureThrow: 10 m/s by default).

const P1 := 1
const P2 := 2
const P3 := 3


static func basic(throw: FixtureThrow = null) -> GameMode:
	var mode := FixtureItemModes.basic()
	var effect := throw if throw != null else FixtureThrow.new()
	mode.actions.append(FixtureModes.rule(Intents.USE, [HoldsItem.new()], [effect]))
	return mode


## `peer` stands at `feet` and picks up a new package lying there.
static func holding(game: Match, peer: int, feet: Vector3) -> ItemState:
	FixtureItemModes.stand(game, peer, feet)
	var item := FixtureItemModes.lay(game, &"package", feet)
	FixtureItemModes.pick_up(game, peer, item)
	return item


## `peer` throws its hand item along `facing`: a Use stamped with the next tick, the launch tick.
static func throw(game: Match, peer: int, facing: Vector3) -> void:
	FixtureModes.send(game, Intents.USE, peer, {"facing": facing})
