extends GdUnitTestSuite
## HandOverUse's pure parts (client/world/hand_over_use.gd, #1411, #1434; ARCHITECTURE §4.7.10):
## the reach is the client's own mode's TargetInReach of HandOver (and of TakeOffer for a take), the
## hint's a margin short of it; E takes an offer made to the own player, cancels the own open offer
## wherever it aims, or offers any hand item, in a phase whose own copy accepts the intent from the
## living, to a present standing player other than the own, within the reach of the feet. Against
## the physics of a joined Game: tests/integration/client/world/hand_over_network_test.gd.

const OWN := 2
const FRIEND := 1
const DOWNED := 3
const THIRD := 4
const GONE := 9
const FEET := Vector3(0, 0, 0)
const NEAR := Vector3(1.5, 0, 0)

var _mode: GameMode
var _model: ClientModel


func before_test() -> void:
	_mode = FixtureHandOverModes.basic()
	for intent: StringName in [Intents.HAND_OVER, Intents.TAKE_OFFER, Intents.CANCEL_OFFER]:
		_mode.find_phase(&"lobby").accepts.append(AcceptSpec.of(intent, AcceptSpec.From.LIVING))
	_model = ClientModel.new(_mode)
	var welcome := WelcomeEvent.new(OWN, Vector3.ZERO, 3)
	for peer: int in [FRIEND, OWN, DOWNED, THIRD]:
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
	# The take has its own TargetInReach.
	var take := HandOverUse.reach_of(_mode, Intents.TAKE_OFFER)
	assert_float(take).is_equal(FixtureHandOverModes.REACH_M)
	# A mode with no HandOver offers nothing.
	assert_float(HandOverUse.reach_of(FixtureItemModes.basic())).is_equal(0.0)
	assert_float(HandOverUse.hint_reach_of(FixtureItemModes.basic())).is_equal(0.0)
	assert_float(HandOverUse.reach_of(FixtureItemModes.basic(), Intents.TAKE_OFFER)).is_equal(0.0)


func test_the_base_modes_hand_over_and_take_reach_two_metres() -> void:
	var base := load("res://content/modes/base_mode.tres") as GameMode
	assert_float(HandOverUse.reach_of(base)).is_equal(2.0)
	assert_float(HandOverUse.reach_of(base, Intents.TAKE_OFFER)).is_equal(2.0)


## #1434: any item can be offered, a two-handed one too (the pick-up's hand rules at the take).
func test_any_hand_item_can_be_offered() -> void:
	# An empty hand hands nothing.
	assert_bool(HandOverUse.can_hand(_model, _mode)).is_false()
	for kind: StringName in [&"gift", &"tool", &"package"]:
		_hold(40 + kind.length(), kind)
		assert_bool(HandOverUse.can_hand(_model, _mode)).override_failure_message(kind).is_true()


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


## §7.1.21 (#1393): a limp own player is living, but the host refuses it every action, HandOver
## and TakeOffer included: its own avatar's limp flag in the snapshot keeps the key from offering,
## taking and sending.
func test_a_limp_own_player_hands_over_and_takes_nothing() -> void:
	_hold(41, &"gift")
	assert_bool(HandOverUse.can_hand(_model, _mode)).is_true()
	_model.fold(&"OfferMade", {"giver": FRIEND, "target": OWN})
	_limp(OWN)
	assert_int(_model.life_of(OWN)).is_equal(ClientModel.Life.ALIVE)
	assert_bool(HandOverUse.can_hand(_model, _mode)).is_false()
	assert_bool(HandOverUse.offers(_model, _mode, FRIEND, FEET, Vector3(1, 0, 0), 2.0)).is_false()
	assert_bool(HandOverUse.takes(_model, FRIEND, FEET, NEAR, 2.0)).is_false()
	assert_int(_choose(FRIEND)).is_equal(HandOverUse.Prompt.NONE)


func test_the_target_is_a_present_living_other_player_within_the_reach_of_the_feet() -> void:
	_hold(41, &"gift")
	assert_bool(HandOverUse.offers(_model, _mode, FRIEND, FEET, NEAR, 1.7)).is_true()
	# Out of reach of the feet, measured on the ground as the host measures it.
	assert_bool(HandOverUse.offers(_model, _mode, FRIEND, FEET, Vector3(1.8, 0, 0), 1.7)).is_false()
	# The own player, a downed one, a peer not on the roster, none: the host's TargetLiving.
	assert_bool(HandOverUse.offers(_model, _mode, OWN, FEET, NEAR, 1.7)).is_false()
	assert_bool(HandOverUse.offers(_model, _mode, DOWNED, FEET, NEAR, 1.7)).is_false()
	assert_bool(HandOverUse.offers(_model, _mode, GONE, FEET, NEAR, 1.7)).is_false()
	assert_bool(HandOverUse.offers(_model, _mode, 0, FEET, NEAR, 1.7)).is_false()
	# No reach (a mode with no HandOver) offers nothing.
	assert_bool(HandOverUse.offers(_model, _mode, FRIEND, FEET, NEAR, 0.0)).is_false()


## #1434: TargetLiving refuses a limp target, so the key offers nothing to one (body_life_of).
func test_a_limp_target_gets_no_offer() -> void:
	_hold(41, &"gift")
	assert_int(_choose(FRIEND)).is_equal(HandOverUse.Prompt.OFFER)
	_limp(FRIEND)
	assert_bool(HandOverUse.offers(_model, _mode, FRIEND, FEET, NEAR, 2.0)).is_false()
	assert_int(_choose(FRIEND)).is_equal(HandOverUse.Prompt.NONE)


## E aimed at a giver who offers to the own player takes it; an offer to someone else, a giver out
## of reach or no TakeOffer accepted in the phase does not.
func test_e_takes_an_offer_made_to_the_own_player() -> void:
	assert_int(_choose(FRIEND)).is_equal(HandOverUse.Prompt.NONE)
	_model.fold(&"OfferMade", {"giver": FRIEND, "target": THIRD})
	assert_int(_choose(FRIEND)).is_equal(HandOverUse.Prompt.NONE)
	_model.fold(&"OfferEnded", {"giver": FRIEND, "target": THIRD})
	_model.fold(&"OfferMade", {"giver": FRIEND, "target": OWN})
	assert_int(_choose(FRIEND)).is_equal(HandOverUse.Prompt.TAKE)
	assert_bool(HandOverUse.takes(_model, FRIEND, FEET, Vector3(2.5, 0, 0), 2.0)).is_false()
	_mode.find_phase(&"lobby").accepts = _mode.find_phase(&"lobby").accepts.filter(
		func(entry: AcceptSpec) -> bool: return entry.intent != Intents.TAKE_OFFER
	)
	assert_int(_choose(FRIEND)).is_equal(HandOverUse.Prompt.NONE)


## A take wins over an offer: holding an item, E at a giver who offers to the own player takes.
func test_a_take_wins_over_an_offer() -> void:
	_hold(41, &"gift")
	_model.fold(&"OfferMade", {"giver": FRIEND, "target": OWN})
	assert_int(_choose(FRIEND)).is_equal(HandOverUse.Prompt.TAKE)


## The critique's E order (#1434): with an offer of its own open the giver cancels it with E,
## aiming at its receiver or at anyone else, and never offers twice.
func test_a_giver_with_an_open_offer_cancels_wherever_it_aims() -> void:
	_hold(41, &"gift")
	_model.fold(&"OfferMade", {"giver": OWN, "target": FRIEND})
	assert_bool(HandOverUse.can_hand(_model, _mode)).is_false()
	assert_int(_choose(FRIEND)).is_equal(HandOverUse.Prompt.CANCEL)
	assert_int(_choose(THIRD)).is_equal(HandOverUse.Prompt.CANCEL)
	assert_int(_choose(0)).is_equal(HandOverUse.Prompt.CANCEL)
	_model.fold(&"OfferEnded", {"giver": OWN, "target": FRIEND})
	assert_int(_choose(FRIEND)).is_equal(HandOverUse.Prompt.OFFER)


func test_nothing_aimed_at_sends_nothing_and_cues_nothing() -> void:
	var use: HandOverUse = auto_free(HandOverUse.new())
	use.setup(null, _mode)
	use.model = _model
	_hold(41, &"gift")
	assert_int(use.target()).is_equal(0)
	assert_int(use.prompt()).is_equal(HandOverUse.Prompt.NONE)
	assert_str(use.cue()).is_empty()
	assert_str(use.cue_key()).is_empty()
	assert_int(use.hand_over()).is_equal(-1)


## E sends by the prompt: HandOver(target), TakeOffer(target) or CancelOffer, each its deck key.
func test_e_sends_the_intent_of_the_prompt() -> void:
	var use: HandOverUse = auto_free(HandOverUse.new())
	use.setup(null, _mode)
	use.model = _model
	var session := StubSession.new(_mode)
	use.session = session
	_hold(41, &"gift")
	_prompt(use, FRIEND)
	assert_int(use.prompt()).is_equal(HandOverUse.Prompt.OFFER)
	assert_str(use.cue_key()).is_equal(HudText.HAND_OVER_CUE)
	assert_int(use.hand_over()).is_equal(1)
	assert_array(session.sent).is_equal([[Intents.HAND_OVER, {"target": FRIEND}]])
	session.sent.clear()
	_model.fold(&"OfferMade", {"giver": OWN, "target": FRIEND})
	_prompt(use, FRIEND)
	assert_int(use.target()).is_equal(FRIEND)
	assert_str(use.cue_key()).is_equal(HudText.OFFERING_CUE)
	use.hand_over()
	assert_array(session.sent).is_equal([[Intents.CANCEL_OFFER, {}]])
	session.sent.clear()
	_model.fold(&"OfferEnded", {"giver": OWN, "target": FRIEND})
	_model.fold(&"OfferMade", {"giver": THIRD, "target": OWN})
	_prompt(use, THIRD)
	assert_str(use.cue_key()).is_equal(HudText.TAKE_OFFER_CUE)
	use.hand_over()
	assert_array(session.sent).is_equal([[Intents.TAKE_OFFER, {"target": THIRD}]])


## `item` of `kind` spawned and taken into the own hand (its earlier hand item on the belt).
func _hold(item: int, kind: StringName) -> void:
	_model.fold(&"ItemSpawned", {"item": item, "kind": kind, "position": FEET})
	var before := _model.hand_item(OWN)
	if before >= 0:
		_model.fold(&"ItemPlaced", {"item": before, "position": FEET, "cause": &"put_down"})
	_model.fold(&"ItemPickedUp", {"peer": OWN, "item": item})


## What E would do aimed at `aimed` (0: nobody) standing NEAR, both reaches 2 m.
func _choose(aimed: int) -> HandOverUse.Prompt:
	return HandOverUse.choose(_model, _mode, aimed, FEET, NEAR, 2.0, 2.0)


## Sets `use`'s prompt and target as its physics step would, aimed at `aimed` standing NEAR.
func _prompt(use: HandOverUse, aimed: int) -> void:
	use._prompt = _choose(aimed)
	use._target = 0
	match use._prompt:
		HandOverUse.Prompt.OFFER, HandOverUse.Prompt.TAKE:
			use._target = aimed
		HandOverUse.Prompt.CANCEL:
			use._target = _model.offer_of(OWN)


## The newest snapshot shows `peer` limp (§7.1.21).
func _limp(peer: int) -> void:
	var avatar := {
		"position": FEET,
		"velocity": Vector3.ZERO,
		"facing": Vector3.FORWARD,
		"downed": false,
		"limp": true,
		"held_item": -1,
	}
	_model.fold_snapshot({"tick": 1, "avatars": {peer: avatar}})


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


## A session that records what it would send.
class StubSession:
	extends ClientSession
	var sent: Array = []

	func _init(mode: GameMode) -> void:
		super(LoopbackTransport.new(WireSchema.game(true).kind_table()), mode)

	func send_intent(intent: StringName, args: Dictionary = {}) -> int:
		sent.append([intent, args])
		return sent.size()
