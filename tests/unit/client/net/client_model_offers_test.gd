extends GdUnitTestSuite
## ClientModel's offers (#1434, ARCHITECTURE §4.6): OfferMade records whom a giver offers its hand
## item to; OfferEnded of that pair forgets it (an end of an older pair changes nothing); a leave of
## either side and a new match forget it too.

const OWN := 2
const FRIEND := 1
const THIRD := 3

var _model: ClientModel


func before_test() -> void:
	_model = ClientModel.new(FixtureBaseMode.mode())
	var welcome := WelcomeEvent.new(OWN, Vector3(1, 0, 2), 3)
	for peer: int in [FRIEND, OWN, THIRD]:
		welcome.roster.append({"peer": peer, "name": "P%d" % peer, "ready": false, "colour": peer})
	welcome.settings = {&"knives": 2}
	welcome.map = "res://levels/a.tscn"
	welcome.phase = &"lobby"
	_fold(welcome)


func test_an_offer_made_is_known_until_it_ends() -> void:
	assert_int(_model.offer_of(FRIEND)).is_equal(0)
	_fold(OfferMadeEvent.new(FRIEND, OWN))
	assert_int(_model.offer_of(FRIEND)).is_equal(OWN)
	assert_int(_model.offer_of(OWN)).is_equal(0)
	# The end of another pair (an older offer of the same giver) forgets nothing.
	_fold(OfferEndedEvent.new(FRIEND, THIRD))
	assert_int(_model.offer_of(FRIEND)).is_equal(OWN)
	_fold(OfferEndedEvent.new(FRIEND, OWN))
	assert_int(_model.offer_of(FRIEND)).is_equal(0)


func test_a_new_offer_of_the_same_giver_replaces_the_old_one() -> void:
	_fold(OfferMadeEvent.new(FRIEND, OWN))
	_fold(OfferEndedEvent.new(FRIEND, OWN))
	_fold(OfferMadeEvent.new(FRIEND, THIRD))
	assert_int(_model.offer_of(FRIEND)).is_equal(THIRD)


func test_a_leave_of_either_side_forgets_the_offer() -> void:
	_fold(OfferMadeEvent.new(FRIEND, OWN))
	_fold(OfferMadeEvent.new(OWN, THIRD))
	_fold(PlayerLeftEvent.new(FRIEND))
	assert_int(_model.offer_of(FRIEND)).is_equal(0)
	assert_int(_model.offer_of(OWN)).is_equal(THIRD)
	_fold(PlayerLeftEvent.new(THIRD))
	assert_int(_model.offer_of(OWN)).is_equal(0)
	assert_dict(_model.offers).is_empty()


func test_a_new_match_forgets_the_offers() -> void:
	_fold(OfferMadeEvent.new(FRIEND, OWN))
	var settings: Dictionary[StringName, int] = {&"knives": 1}
	_fold(LoadMatchEvent.new(4, "res://levels/c.tscn", settings))
	assert_dict(_model.offers).is_empty()


func _fold(event: MatchEvent) -> void:
	_model.fold(event.event_name(), event.to_dict())
