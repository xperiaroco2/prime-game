extends GdUnitTestSuite
## BoothBook (#1397, ARCHITECTURE §4.7.62): the booth's steps folded into sessions, the strips
## bound to the session whose frames they show; and the real host's steps fed in.

const STATION := 4
const P1 := FixtureBooth.P1
const P2 := FixtureBooth.P2
const P3 := FixtureBooth.P3

var _book: BoothBook


func before_test() -> void:
	_book = BoothBook.new()


func _step(kind: int, strip := 1, extra: Dictionary = {}) -> void:
	var fields := {"station": STATION, "strip": strip, "step": kind}
	fields.merge(extra, true)
	_book.fold(&"BoothStep", fields)


func _row(peer: int, colour := 0) -> Dictionary:
	return {"peer": peer, "colour": colour, "position": Vector3.ZERO, "facing": Vector3.FORWARD}


func _flash(frame: int, rows: Array, strip := 1) -> void:
	_step(BoothStepEvent.FLASH, strip, {"frame": frame, "record": rows})


func _print(items: Array[int], strip := 1) -> void:
	_step(BoothStepEvent.PRINTED, strip, {"items": PackedInt32Array(items)})


func test_a_session_runs_from_started_and_keeps_its_frames_in_order() -> void:
	_step(BoothStepEvent.STARTED, 1, {"presser": P1, "frames": 4, "countdown": 60, "gap": 40})
	var session := _book.running_at(STATION)
	assert_object(session).is_not_null()
	assert_int(session.frames).is_equal(4)
	assert_int(session.countdown).is_equal(60)
	_flash(0, [_row(P1, 2)])
	_flash(1, [_row(P1, 2), _row(P2, 5)])
	assert_int(session.flashes()).is_equal(2)
	assert_int(session.record_of(1).size()).is_equal(2)
	assert_int(session.record_of(1)[1]["colour"]).is_equal(5)
	assert_array(session.record_of(3)).is_empty()
	assert_int(session.frame_count()).is_equal(4)


func test_printed_binds_every_strip_to_the_one_session_and_ends_it() -> void:
	_step(BoothStepEvent.STARTED)
	_flash(0, [_row(P1), _row(P2)])
	var session := _book.running_at(STATION)
	_print([30, 31])
	assert_object(_book.session_of(30)).is_same(session)
	assert_object(_book.session_of(31)).is_same(session)
	assert_object(_book.running_at(STATION)).is_null()
	assert_int(session.state).is_equal(BoothBook.State.PRINTED)
	assert_bool(_book.holds(session)).is_true()


func test_a_reused_strip_id_is_a_new_session() -> void:
	_step(BoothStepEvent.STARTED)
	_flash(0, [_row(P1)])
	_print([30])
	_step(BoothStepEvent.STARTED)
	assert_object(_book.running_at(STATION)).is_not_same(_book.session_of(30))
	assert_int(_book.running_at(STATION).flashes()).is_zero()


func test_stopped_prints_nothing_and_ends_the_session() -> void:
	_step(BoothStepEvent.STARTED)
	_flash(0, [_row(P1)])
	_step(BoothStepEvent.STOPPED)
	assert_object(_book.running_at(STATION)).is_null()
	assert_array(_book.running()).is_empty()


func test_a_vanished_or_respawned_id_shows_no_old_strip() -> void:
	_step(BoothStepEvent.STARTED)
	_flash(0, [_row(P1)])
	_print([30, 31])
	_book.fold(&"ItemVanished", {"item": 30})
	assert_object(_book.session_of(30)).is_null()
	# Freed and reused with no PRINTED (CE3): a new item.
	_book.fold(&"ItemSpawned", {"item": 31, "kind": &"strip", "position": Vector3.ZERO})
	assert_object(_book.session_of(31)).is_null()


func test_a_session_shown_by_no_strip_and_not_running_is_not_held() -> void:
	_step(BoothStepEvent.STARTED)
	_flash(0, [_row(P1)])
	var session := _book.running_at(STATION)
	_print([30])
	_book.fold(&"ItemVanished", {"item": 30})
	assert_bool(_book.holds(session)).is_false()


func test_a_handed_over_strip_keeps_its_session() -> void:
	_step(BoothStepEvent.STARTED)
	_flash(0, [_row(P1)])
	_print([30])
	var session := _book.session_of(30)
	_book.fold(&"ItemPickedUp", {"item": 30, "peer": P2})
	assert_object(_book.session_of(30)).is_same(session)


func test_a_fresh_strip_is_taken_once() -> void:
	_step(BoothStepEvent.STARTED)
	_print([30])
	assert_bool(_book.take_fresh(30)).is_true()
	assert_bool(_book.take_fresh(30)).is_false()


func test_a_joiner_after_started_counts_the_frames_it_saw() -> void:
	_flash(2, [_row(P1)], 9)
	var session := _book.running_at(STATION)
	assert_int(session.frames).is_zero()
	assert_int(session.frame_count()).is_equal(3)
	assert_array(session.record_of(0)).is_empty()


func test_bind_strip_takes_a_welcomes_frames() -> void:
	var session := _book.bind_strip(40, 2, [[_row(P1)], [_row(P1), _row(P2)]])
	assert_object(_book.session_of(40)).is_same(session)
	assert_int(session.frame_count()).is_equal(2)
	assert_int(session.record_of(1).size()).is_equal(2)


func test_load_match_forgets_every_session() -> void:
	_step(BoothStepEvent.STARTED)
	_print([30])
	_step(BoothStepEvent.STARTED, 2)
	_book.fold(&"LoadMatch", {})
	assert_object(_book.session_of(30)).is_null()
	assert_array(_book.running()).is_empty()


func test_the_real_hosts_steps_give_its_records_and_strips() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2, P3])
	FixtureBooth.press(game, P1)
	FixtureModes.run_ticks(game, FixtureBooth.whole())
	for event: MatchEvent in game.view_of(P2).events:
		_book.fold(event.event_name(), event.to_dict())
	var flashes := FixtureBooth.steps_of(game, P2, BoothStepEvent.FLASH)
	var printed := FixtureBooth.steps_of(game, P2, BoothStepEvent.PRINTED)
	assert_array(printed).has_size(1)
	var session := _book.session_of(printed[0].items[0])
	assert_object(session).is_not_null()
	assert_int(session.frame_count()).is_equal(FixtureBooth.FRAMES)
	for flash: BoothStepEvent in flashes:
		var rows := session.record_of(flash.frame)
		assert_int(rows.size()).is_equal(flash.record.size())
		for k in rows.size():
			for key: String in ["peer", "colour", "position", "crouched", "limp", "posed"]:
				assert_that(rows[k][key]).is_equal(flash.record[k][key])
	for id: int in printed[0].items:
		assert_object(_book.session_of(id)).is_same(session)
