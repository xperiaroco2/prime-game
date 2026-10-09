extends GdUnitTestSuite
## HostTextView (#548): a shortfall's id worded by the deck's key in the current language, the
## plural by its count; an id the deck has no key for (ui-0.4.0: players_many, markers, colours,
## no_layout) or an unknown one as plain(), the id and its arguments with no words of a language.

var _locale := ""


func before_test() -> void:
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_test() -> void:
	TranslationServer.set_locale(_locale)


func test_players_few_is_the_decks_need_more_by_its_count() -> void:
	assert_str(HostTextView.shortfall(_text(&"players_few", [], {&"count": 1}))).is_equal(
		"1 more player to start"
	)
	assert_str(HostTextView.shortfall(_text(&"players_few", [], {&"count": 3}))).is_equal(
		"3 more players to start"
	)


func test_an_id_without_a_key_is_its_plain_line() -> void:
	var markers := _text(&"markers", ["package"], {&"need": 4, &"have": 2})
	assert_str(HostTextView.shortfall(markers)).is_equal("markers package have=2 need=4")
	var many := _text(&"players_many", [], {&"count": 2, &"min": 1, &"max": 10})
	assert_str(HostTextView.shortfall(many)).is_equal("players_many count=2 max=10 min=1")
	assert_str(HostTextView.shortfall(_text(&"no_layout", [], {}))).is_equal("no_layout")
	assert_str(HostTextView.shortfall(_text(&"what_now", ["a", "b"], {}))).is_equal("what_now a b")
	for id: StringName in [&"players_many", &"markers", &"colours", &"no_layout"]:
		assert_bool(HostTextView.SHORTFALL_KEYS.has(id)).override_failure_message(id).is_false()


func test_every_key_of_the_table_is_in_the_deck() -> void:
	for id: StringName in HostTextView.SHORTFALL_KEYS:
		var key := HostTextView.SHORTFALL_KEYS[id]
		assert_str(TranslationServer.translate(key)).override_failure_message(key).is_not_equal(key)


func test_the_shortfalls_are_one_per_line_in_order() -> void:
	var texts: Array[Dictionary] = [
		_text(&"players_few", [], {&"count": 2}), _text(&"colours", ["circle"], {&"need": 3})
	]
	assert_str(HostTextView.shortfalls(texts)).is_equal(
		"2 more players to start\ncolours circle need=3"
	)
	assert_str(HostTextView.shortfalls([])).is_empty()


func _text(id: StringName, subjects: Array, numbers: Dictionary) -> Dictionary:
	var typed: Dictionary[StringName, int] = {}
	typed.assign(numbers)
	return {"id": id, "ids": PackedStringArray(subjects), "numbers": typed}
