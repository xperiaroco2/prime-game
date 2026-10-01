extends GdUnitTestSuite
## The end reasons in words (client/app/end_reasons.gd, ARCHITECTURE §4.7): every way a session
## ends has its words, and the host's own reasons, which client/ may not name through HostSession
## (E18), are pinned to server/'s here.


func test_every_end_has_its_words() -> void:
	var reasons: Array[StringName] = [
		RejectReasons.WRONG_VERSION,
		RejectReasons.WRONG_CONTENT,
		RejectReasons.JOINS_CLOSED,
		RejectReasons.FULL,
		ClientSession.CONNECT_FAILED,
		ClientSession.HOST_LOST,
		ClientSession.UNKNOWN_MAP,
		ClientSession.LOAD_FAILED,
		ClientSession.LEFT,
		DisconnectingEvent.LOAD_DEADLINE,
		HostSession.CLOSED,
		HostSession.ROW_ERROR,
		HostSession.OWN_CLIENT_MALFORMED,
		HostSession.OWN_CLIENT_DISCONNECTED,
		EndReasons.CANNOT_HOST,
	]
	for reason: StringName in reasons:
		assert_bool(EndReasons.WORDS.has(reason)).override_failure_message(reason).is_true()
		assert_str(EndReasons.words(reason)).is_not_empty()
		assert_str(EndReasons.text(reason)).is_equal("%s (%s)" % [reason, EndReasons.words(reason)])
	assert_int(EndReasons.WORDS.size()).is_equal(reasons.size())


func test_the_hosts_own_reasons_are_server_s() -> void:
	assert_str(String(EndReasons.CLOSED)).is_equal(String(HostSession.CLOSED))
	assert_str(String(EndReasons.ROW_ERROR)).is_equal(String(HostSession.ROW_ERROR))
	assert_str(String(EndReasons.OWN_CLIENT_MALFORMED)).is_equal(
		String(HostSession.OWN_CLIENT_MALFORMED)
	)
	assert_str(String(EndReasons.OWN_CLIENT_DISCONNECTED)).is_equal(
		String(HostSession.OWN_CLIENT_DISCONNECTED)
	)


func test_an_unknown_reason_is_its_id() -> void:
	assert_str(EndReasons.words(&"no_such_reason")).is_equal("no_such_reason")
	assert_str(EndReasons.text(&"no_such_reason")).is_equal("no_such_reason")
	assert_str(EndReasons.words(&"load_deadline")).contains("too long to load")
