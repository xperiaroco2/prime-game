extends GdUnitTestSuite
## HandOverUse's pure parts (client/world/hand_over_use.gd, #1411; ARCHITECTURE §4.7.10): the
## reach is the client's own mode's TargetInReach of HandOver, the hint's a margin short of it;
## E offers a hand-over only of a handable, one-handed hand item, in a phase whose own copy accepts
## HandOver from the living, to a present living player other than the own, within the reach of
## the feet. Against the physics of a joined Game: tests/integration/client/world/
## hand_over_network_test.gd.

const OWN := 2
const FRIEND := 1
const DOWNED := 3
const GONE := 9
const FEET := Vector3(0, 0, 0)

var _mode: GameMode
var _model: ClientModel


func before_test() -> void:
	_mode = FixtureHandOverModes.basic()
	_mode.find_phase(&"lobby").accepts.append(
		AcceptSpec.of(Intents.HAND_OVER, AcceptSpec.From.LIVING)
	)
	_model = ClientModel.new(_mode)
	var welcome := WelcomeEvent.new(OWN, Vector3.ZERO, 3)
	for peer: int in [FRIEND, OWN, DOWNED]:
		welcome.roster.append({"peer": peer, "name": "P%d" % peer, "ready": false, "colour": peer})
	welcome.settings = _mode.default_settings()
	welcome.map = _mode.default_map()
	welcome.phase = &"lobby"
	_model.fold(&"Welcome", welcome.to_dict())
	_model.fold(&"KnockedDown", {"peer": DOWNED, "position": Vector3(1, 0, 0)})


func test_the_reach_is_the_modes_target_in_reach_of_hand_over_less_the_hints_margin() -> void:
	assert_float(HandOverUse.reach_of(_mode)).is_equal(FixtureHandOverModes.REACH_M)
	var hint := TargetChoice.hint_reach(FixtureHandOverModes.REACH_M, _mode)
	assert_float(HandOverUse.hint_reach_of(_mode)).is_equal_approx(hint, 1e-6)
	assert_float(HandOverUse.hint_reach_of(_mode)).is_less(FixtureHandOverModes.REACH_M)
	# A mode with no HandOver offers nothing.
	assert_float(HandOverUse.reach_of(FixtureItemModes.basic())).is_equal(0.0)
	assert_float(HandOverUse.hint_reach_of(FixtureItemModes.basic())).is_equal(0.0)


func test_the_base_modes_hand_over_reaches_two_metres() -> void:
	var base := load("res://content/modes/base_mode.tres") as GameMode
	assert_float(HandOverUse.reach_of(base)).is_equal(2.0)


func test_only_a_handable_one_handed_hand_item_can_be_handed() -> void:
	# An empty hand hands nothing.
	assert_bool(HandOverUse.can_hand(_model, _mode)).is_false()
	_hold(41, &"gift")
	assert_bool(HandOverUse.can_hand(_model, _mode)).is_true()
	# Not handable (`tool`), and two-handed (`package`): the host's HandHandable, HandNotTwoHanded.
	_hold(42, &"tool")
	assert_bool(HandOverUse.can_hand(_model, _mode)).is_false()
	_hold(43, &"package")
	assert_bool(HandOverUse.can_hand(_model, _mode)).is_false()


func test_only_a_phase_that_takes_hand_over_from_the_living_offers_it() -> void:
	_hold(41, &"gift")
	assert_bool(HandOverUse.can_hand(_model, _mode)).is_true()
	_mode.find_phase(&"lobby").accepts = _mode.find_phase(&"lobby").accepts.filter(
		func(entry: AcceptSpec) -> bool: return entry.intent != Intents.HAND_OVER
	)
	assert_bool(HandOverUse.can_hand(_model, _mode)).is_false()
	# A phase that takes HandOver only from others than the living (the downed here) refuses the
	# living sender, as the host's accept check does.
	_mode.find_phase(&"lobby").accepts.append(
		AcceptSpec.of(Intents.HAND_OVER, AcceptSpec.From.DOWNED)
	)
	assert_bool(HandOverUse.can_hand(_model, _mode)).is_false()


func test_the_own_player_hands_over_only_while_living() -> void:
	_hold(41, &"gift")
	_model.fold(&"KnockedDown", {"peer": OWN, "position": FEET})
	assert_bool(HandOverUse.can_hand(_model, _mode)).is_false()
	assert_bool(HandOverUse.offers(_model, _mode, FRIEND, FEET, Vector3(1, 0, 0), 2.0)).is_false()


func test_the_target_is_a_present_living_other_player_within_the_reach_of_the_feet() -> void:
	_hold(41, &"gift")
	var near := Vector3(1.5, 0, 0)
	assert_bool(HandOverUse.offers(_model, _mode, FRIEND, FEET, near, 1.7)).is_true()
	# Out of reach of the feet, measured on the ground as the host measures it.
	assert_bool(HandOverUse.offers(_model, _mode, FRIEND, FEET, Vector3(1.8, 0, 0), 1.7)).is_false()
	# The own player, a downed one, a peer not on the roster, none: the host's TargetLiving.
	assert_bool(HandOverUse.offers(_model, _mode, OWN, FEET, near, 1.7)).is_false()
	assert_bool(HandOverUse.offers(_model, _mode, DOWNED, FEET, near, 1.7)).is_false()
	assert_bool(HandOverUse.offers(_model, _mode, GONE, FEET, near, 1.7)).is_false()
	assert_bool(HandOverUse.offers(_model, _mode, 0, FEET, near, 1.7)).is_false()
	# No reach (a mode with no HandOver) offers nothing.
	assert_bool(HandOverUse.offers(_model, _mode, FRIEND, FEET, near, 0.0)).is_false()


func test_nothing_aimed_at_sends_nothing_and_cues_nothing() -> void:
	var use: HandOverUse = auto_free(HandOverUse.new())
	use.setup(null, _mode)
	use.model = _model
	_hold(41, &"gift")
	assert_int(use.target()).is_equal(0)
	assert_str(use.cue()).is_empty()
	assert_int(use.hand_over()).is_equal(-1)


## `item` of `kind` spawned and taken into the own hand (its earlier hand item on the belt).
func _hold(item: int, kind: StringName) -> void:
	_model.fold(&"ItemSpawned", {"item": item, "kind": kind, "position": FEET})
	var before := _model.hand_item(OWN)
	if before >= 0:
		_model.fold(&"ItemPlaced", {"item": before, "position": FEET, "cause": &"put_down"})
	_model.fold(&"ItemPickedUp", {"peer": OWN, "item": item})


## E has another thing to do (an item or station ItemInteractions offers, the open viewfinder): the
## hand-over gives way, and takes E again when that is gone. Before #1408's tap it was the item
## alone; in the lobby the mug holder at the tap with a friend beside it must pour, not hand over.
func test_the_hand_over_yields_to_an_item_a_station_or_the_viewfinder() -> void:
	var use: HandOverUse = auto_free(HandOverUse.new())
	use.setup(null, _mode)
	var stub: StubInteractions = auto_free(StubInteractions.new())
	use.interactions = stub
	assert_bool(use._yields()).is_false()
	stub.item = 5
	assert_bool(use._yields()).is_true()
	stub.item = -1
	stub.station = 2
	assert_bool(use._yields()).is_true()
	stub.station = -1
	stub.open = true
	assert_bool(use._yields()).is_true()
	stub.open = false
	assert_bool(use._yields()).is_false()


## What ItemInteractions offers, set by the test.
class StubInteractions:
	extends ItemInteractions
	var item := -1
	var station := -1
	var open := false

	func target() -> int:
		return item

	func station_target() -> int:
		return station

	func viewing() -> bool:
		return open
