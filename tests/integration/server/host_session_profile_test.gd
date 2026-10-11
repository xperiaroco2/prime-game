extends GdUnitTestSuite
## Body colours and SetProfile over the wire (ARCHITECTURE §3.5, §4.3, #551): joiners take the
## first free colour, a SetProfile in the lobby renames and recolours with the clash rule (a taken
## colour gives the first free one), ProfileChanged reaches every client, a late joiner's Welcome
## holds every colour, and outside the lobby SetProfile is refused to its sender alone. Over a
## LoopbackHub with a fake clock (host_session_harness.gd).

const Harness := preload("res://tests/integration/server/host_session_harness.gd")

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_the_clash_rule_and_every_clients_roster() -> void:
	_h = Harness.new()
	var first := _h.join(null, "Dima")
	assert_bool(_h.welcome_all()).is_true()
	var second := _h.join(null, "Olena")
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_frames(4)
	assert_dict(_colours(_h.own)).is_equal({1: 0, _h.peer_of(first): 1, _h.peer_of(second): 2})
	# A free colour is taken as asked; a taken one (the host's 0) gives the first free one: 1,
	# which Dima left.
	first.send_intent(Intents.SET_PROFILE, {"name": "Dima", "colour": 7})
	_h.pump_frames(4)
	second.send_intent(Intents.SET_PROFILE, {"name": "dima", "colour": 0})
	_h.pump_frames(4)
	var third := _h.join(null, "Taras")
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_frames(4)
	var expected := {
		1: 0,
		_h.peer_of(first): 7,
		_h.peer_of(second): 1,
		_h.peer_of(third): 2,
	}
	for client: ClientSession in [_h.own, first, second, third]:
		assert_dict(_colours(client)).override_failure_message(str(_colours(client))).is_equal(
			expected
		)
		assert_str(client.model.roster[_h.peer_of(second)].name).is_equal("dima 2")
		assert_array(_h.mismatches(client)).is_empty()
	# Each of the three who were there received each change once, as the host settled it.
	for client: ClientSession in [_h.own, first, second]:
		var changed := client.view.events_named(&"ProfileChanged")
		assert_int(changed.size()).is_equal(2)
		assert_dict(changed[1].fields).is_equal(
			{"peer": _h.peer_of(second), "name": "dima 2", "colour": 1}
		)
	# The late joiner learned every colour from its Welcome.
	var welcome := third.view.events_named(&"Welcome")[0]
	var roster: Array = welcome.fields["roster"]
	assert_int(roster.size()).is_equal(4)
	for entry: Dictionary in roster:
		assert_int(entry["colour"] as int).is_equal(expected[entry["peer"] as int])
	for peer: int in expected:
		assert_int(_h.session.game.state.player(peer).colour).is_equal(expected[peer])


func test_outside_the_lobby_a_profile_is_refused_to_its_sender_alone() -> void:
	_h = Harness.new()
	var first := _h.join(null, "Dima")
	assert_bool(_h.welcome_all()).is_true()
	_h.ready_all()
	assert_bool(_h.run_until_phase(&"countdown", 30)).is_true()
	var seq := first.send_intent(Intents.SET_PROFILE, {"name": "Hacked", "colour": 5})
	_h.pump_frames(4)
	var rejected := first.view.events_named(&"Rejected")
	assert_int(rejected.size()).is_equal(1)
	assert_dict(rejected[0].fields).is_equal({"seq": seq, "reason": &"not_accepted"})
	assert_array(_h.own.view.events_named(&"Rejected")).is_empty()
	for client: ClientSession in [_h.own, first]:
		assert_array(client.view.events_named(&"ProfileChanged")).is_empty()
		assert_str(client.model.roster[_h.peer_of(first)].name).is_equal("Dima")
		assert_int(client.model.colour_of(_h.peer_of(first))).is_equal(1)


func test_a_colour_past_the_ten_or_a_name_that_is_not_utf8() -> void:
	_h = Harness.new()
	var raw := _h.raw()
	_h.pump()
	assert_int(raw.hello(_h.session.content_hash, WireSchema.VERSION, "Ann")).is_equal(OK)
	_h.pump_frames(4)
	# The wire takes any u8; core refuses what is not one of the ten.
	var profile := WireMessage.new(&"SetProfile", {"name": "Ann", "colour": 200}, 5)
	assert_int(raw.send(profile)).is_equal(OK)
	_h.pump_frames(4)
	var rejected := raw.named(&"Rejected")
	assert_int(rejected.size()).is_equal(1)
	assert_dict(rejected[0].fields).is_equal({"seq": 5, "reason": &"out_of_bounds"})
	# A name that is not UTF-8 never reaches core: the codec refuses the message.
	var payload := PackedByteArray()
	payload.resize(4)
	payload.encode_u32(0, 6)
	payload.append_array(PackedByteArray([2, 0xC3, 0x28, 3]))
	var bad_before := _h.session.bad_payloads
	assert_int(raw.send_bytes(_h.schema.kind_of(&"SetProfile"), payload)).is_equal(OK)
	_h.pump_frames(4)
	assert_int(_h.session.bad_payloads).is_equal(bad_before + 1)
	assert_int(raw.named(&"Rejected").size()).is_equal(1)
	assert_array(_h.own.view.events_named(&"ProfileChanged")).is_empty()
	assert_str(_h.session.game.state.player(raw.peer).name).is_equal("Ann")
	assert_int(_h.session.game.state.player(raw.peer).colour).is_equal(1)


## Each peer of `client`'s roster to its colour.
func _colours(client: ClientSession) -> Dictionary:
	var found := {}
	for peer: int in client.model.roster:
		found[peer] = client.model.colour_of(peer)
	return found
