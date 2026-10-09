extends GdUnitTestSuite
## The player's own name over the wire (ARCHITECTURE §3.5, §4.3, #550): Hello asks for it, the
## host cleans it, falls back to Player<n> and suffixes a duplicate, and every client's roster
## holds the host's final names. Over a LoopbackHub with a fake clock (host_session_harness.gd).

const Harness := preload("res://tests/integration/server/host_session_harness.gd")

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_every_client_sees_the_hosts_final_names() -> void:
	_h = Harness.new()
	var first := _h.join(null, "Dima")
	assert_bool(_h.welcome_all()).is_true()
	var second := _h.join(null, "  dima ")
	assert_bool(_h.welcome_all()).is_true()
	var third := _h.join(null, "Діма")
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_frames(4)
	var expected := {
		1: "Player1",
		_h.peer_of(first): "Dima",
		_h.peer_of(second): "dima 2",
		_h.peer_of(third): "Діма",
	}
	# The host's own client, the first joiners (through PlayerJoined) and the last (through its
	# Welcome) agree.
	for client: ClientSession in [_h.own, first, second, third]:
		var names := {}
		for peer: int in client.model.roster:
			names[peer] = client.model.roster[peer].name
		assert_dict(names).override_failure_message(str(names)).is_equal(expected)
		assert_array(_h.mismatches(client)).is_empty()
	for peer: int in expected:
		assert_str(_h.session.game.state.player(peer).name).is_equal(expected[peer])


func test_a_long_name_is_cut_to_16_characters_by_the_host() -> void:
	_h = Harness.new()
	var raw := _h.raw()
	_h.pump()
	var long := "Дмитро".repeat(5)
	assert_int(raw.hello(_h.session.content_hash, WireSchema.VERSION, long)).is_equal(OK)
	_h.pump_frames(4)
	var welcomes := raw.named(&"Welcome")
	assert_int(welcomes.size()).is_equal(1)
	if welcomes.is_empty():
		return
	var roster: Array = welcomes[0].fields["roster"]
	assert_str(roster[-1]["name"]).is_equal(long.left(16))
	var joined := _h.own.view.events_named(&"PlayerJoined")
	assert_str(joined[-1].fields["name"]).is_equal(long.left(16))


func test_a_hello_whose_name_is_not_utf8_is_malformed() -> void:
	_h = Harness.new()
	var raw := _h.raw()
	_h.pump()
	var payload := PackedByteArray()
	payload.resize(10)
	payload.encode_u16(0, WireSchema.VERSION)
	payload.encode_s64(2, _h.session.content_hash)
	payload.append_array(PackedByteArray([2, 0xC3, 0x28]))
	var bad_before := _h.session.bad_payloads
	assert_int(raw.send_bytes(WireSchema.HELLO, payload)).is_equal(OK)
	_h.pump_frames(4)
	assert_int(_h.session.bad_payloads).is_equal(bad_before + 1)
	assert_array(raw.named(&"Welcome")).is_empty()
	assert_bool(_h.session.game.state.newcomers.has(raw.peer)).is_true()
	# The same Hello with its name fixed joins.
	assert_int(raw.hello(_h.session.content_hash, WireSchema.VERSION, "Ann")).is_equal(OK)
	_h.pump_frames(4)
	assert_str(_h.session.game.state.player(raw.peer).name).is_equal("Ann")
