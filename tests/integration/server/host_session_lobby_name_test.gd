extends GdUnitTestSuite
## The lobby's name over the wire (ARCHITECTURE §3.5, §4.1 to §4.3, #214): the host's own client
## names the lobby with ChangeSettings's `lobby_name`, the host cleans it (20 characters), every
## client's model and decoded SettingsChanged hold it, a joiner gets it in its Welcome, a
## non-host's rename is Rejected, and a payload whose name breaks the `name` type is malformed.
## Over a LoopbackHub with a fake clock (host_session_harness.gd).

const Harness := preload("res://tests/integration/server/host_session_harness.gd")

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_the_hosts_rename_reaches_every_client() -> void:
	_h = Harness.new()
	var clients := _three_joined()
	for client: ClientSession in clients:
		assert_str(client.model.lobby_name).is_empty()
		assert_str(client.model.host_name()).is_equal("Player1")
	assert_int(_h.own.send_intent(Intents.CHANGE_SETTINGS, _renamed("Dima's den"))).is_greater(0)
	_h.pump_frames(4)
	assert_str(_h.session.game.state.lobby_name).is_equal("Dima's den")
	for client: ClientSession in clients:
		assert_str(client.model.lobby_name).is_equal("Dima's den")
		var changed := client.view.events_named(&"SettingsChanged")
		assert_str(changed[-1].fields["lobby_name"]).is_equal("Dima's den")
		assert_array(_h.mismatches(client)).is_empty()
	# Back to the default.
	_h.own.send_intent(Intents.CHANGE_SETTINGS, _renamed(""))
	_h.pump_frames(4)
	for client: ClientSession in clients:
		assert_str(client.model.lobby_name).is_empty()
	assert_int(_h.session.bad_payloads).is_equal(0)


func test_a_joiner_gets_the_name_in_its_welcome() -> void:
	_h = Harness.new()
	var raw := _h.raw()
	_h.pump()
	assert_int(raw.hello(_h.session.content_hash, WireSchema.VERSION, "Ann")).is_equal(OK)
	_h.pump_frames(4)
	assert_str(raw.named(&"Welcome")[0].fields["lobby_name"]).is_empty()
	_h.own.send_intent(Intents.CHANGE_SETTINGS, _renamed("Den"))
	_h.pump_frames(4)
	var late := _h.raw()
	_h.pump()
	assert_int(late.hello(_h.session.content_hash, WireSchema.VERSION, "Bo")).is_equal(OK)
	_h.pump_frames(4)
	# The host's answer itself carries it, before the SettingsChanged that follows.
	assert_array(late.names().slice(0, 1)).is_equal([&"Welcome"])
	assert_str(late.named(&"Welcome")[0].fields["lobby_name"]).is_equal("Den")
	var joiner := _h.join()
	var welcomed: Array[String] = []
	joiner.welcomed.connect(
		func(_peer: int) -> void: welcomed.append(joiner.model.lobby_name), CONNECT_ONE_SHOT
	)
	assert_bool(_h.welcome_all()).is_true()
	assert_array(welcomed).is_equal(["Den"])


func test_only_the_host_renames_the_lobby() -> void:
	_h = Harness.new()
	var clients := _three_joined()
	_h.own.send_intent(Intents.CHANGE_SETTINGS, _renamed("Den"))
	_h.pump_frames(4)
	var guest := clients[1]
	var seq := guest.send_intent(Intents.CHANGE_SETTINGS, _renamed("Hacked"))
	_h.pump_frames(4)
	var rejected := guest.view.events_named(&"Rejected")
	assert_int(rejected.size()).is_equal(1)
	assert_int(rejected[0].fields["seq"]).is_equal(seq)
	assert_str(rejected[0].fields["reason"]).is_equal("not_accepted")
	for client: ClientSession in clients:
		assert_str(client.model.lobby_name).is_equal("Den")
	assert_str(_h.session.game.state.lobby_name).is_equal("Den")


func test_the_host_enforces_the_limits() -> void:
	_h = Harness.new()
	var clients := _three_joined()
	# 25 characters on the wire (25 bytes, a valid `name`): the host keeps 20.
	_h.own.send_intent(Intents.CHANGE_SETTINGS, _renamed("  " + "abcde".repeat(5)))
	_h.pump_frames(4)
	var cut := "abcde".repeat(4)
	assert_str(_h.session.game.state.lobby_name).is_equal(cut)
	for client: ClientSession in clients:
		assert_str(client.model.lobby_name).is_equal(cut)
	# A name of 81 bytes, or with a control character, is no `name`: the payload is malformed
	# and nothing changes.
	var raw := _h.raw()
	_h.pump()
	raw.hello(_h.session.content_hash, WireSchema.VERSION, "Raw")
	_h.pump_frames(4)
	var longest := _h.schema.encode(
		WireMessage.new(&"ChangeSettings", _renamed("x".repeat(WireField.NAME_MAX_BYTES)), 1)
	)
	assert_bool(longest.is_empty()).is_false()
	var too_long := longest.duplicate()
	too_long[too_long.size() - WireField.NAME_MAX_BYTES - 1] = WireField.NAME_MAX_BYTES + 1
	too_long.append("x".unicode_at(0))
	var bell := longest.duplicate()
	bell[bell.size() - 1] = 0x07
	var bad_before := _h.session.bad_payloads
	var kind := _h.schema.kind_of(&"ChangeSettings")
	for payload: PackedByteArray in [too_long, bell]:
		assert_int(raw.send_bytes(kind, payload)).is_equal(OK)
	_h.pump_frames(4)
	assert_int(_h.session.bad_payloads).is_equal(bad_before + 2)
	assert_array(raw.named(&"Rejected")).is_empty()
	assert_str(_h.session.game.state.lobby_name).is_equal(cut)
	# The same bytes with an 80-byte name are a good message (the guest's: Rejected, not malformed).
	assert_int(raw.send_bytes(kind, longest)).is_equal(OK)
	_h.pump_frames(4)
	assert_int(_h.session.bad_payloads).is_equal(bad_before + 2)
	assert_int(raw.named(&"Rejected").size()).is_equal(1)


## The host's own client and two joined clients, all welcomed.
func _three_joined() -> Array[ClientSession]:
	_h.join(null, "Ann")
	assert_bool(_h.welcome_all()).is_true()
	_h.join(null, "Bo")
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_frames(4)
	assert_object(_h.clients[0]).is_same(_h.own)
	return _h.clients.duplicate()


func _renamed(lobby: String) -> Dictionary:
	return {"settings": {}, "lobby_name": lobby}
