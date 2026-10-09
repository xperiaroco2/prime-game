extends GdUnitTestSuite
## The how-to cards in `content/howto/` (#254): every task type of every mode in content/modes/
## has a valid card (HowtoCards.problems_of), Delivery's has the UI pack's four pictures with the
## finish last, the Guide's basics are the tutorial's words, and every deck key a card names is in
## the copy deck. A task type without a card fails the check. Loads `content/` on purpose, as the
## mode check does (§9.6).

const MODES := "res://content/modes/"
const DECK := "res://client/i18n/strings.csv"
## Where #520 imports the UI pack's card pictures; once the folder is in the game every picture a
## card names must be there.
const PACK_CARDS := "res://assets/ui/toy_pack/cards/"


func test_every_task_type_of_every_mode_has_a_valid_card() -> void:
	var modes := _modes()
	assert_array(modes).is_not_empty()
	for mode: GameMode in modes:
		(
			assert_array(HowtoCards.problems_of(mode))
			. override_failure_message("\n".join(HowtoCards.problems_of(mode)))
			. is_empty()
		)


func test_a_task_type_without_a_card_fails_the_check() -> void:
	var mode := load(MODES + "base_mode.tres").duplicate() as GameMode
	var stray := Delivery.new()
	stray.id = &"no_such_task"
	mode.task_types = mode.task_types.duplicate()
	mode.task_types.append(stray)
	var problems := HowtoCards.problems_of(mode)
	assert_int(problems.size()).is_equal(1)
	assert_str(problems[0]).contains("no_such_task has no how-to card")


func test_delivery_has_the_packs_four_pictures_and_the_finish_last() -> void:
	var card := HowtoCards.of_task(&"delivery")
	assert_object(card).is_not_null()
	assert_str(String(card.title)).is_equal("task.delivery")
	var art: Array[String] = []
	var done: Array[bool] = []
	for frame: HowtoFrame in card.frames:
		art.append(frame.art)
		done.append(frame.done)
		assert_str(String(frame.text)).is_empty()
	(
		assert_array(art)
		. is_equal(
			[
				PACK_CARDS + "delivery-1.png",
				PACK_CARDS + "delivery-2.png",
				PACK_CARDS + "delivery-3.png",
				PACK_CARDS + "delivery-4.png",
			]
		)
	)
	assert_array(done).is_equal([false, false, false, true])


func test_the_basics_are_the_tutorials_words() -> void:
	# prime-game-ui's spec, Guide: the basics pages are cards from the tutorial's keys.
	var expected := {
		&"moving":
		[
			"tutorial.step.move.title",
			"tutorial.step.pick_up.title",
			"tutorial.step.put_down.title",
			"tutorial.step.hand_belt.title",
		],
		&"voice": ["tutorial.step.voice.title", "tutorial.step.voice.how", "tutorial.list.death"],
		&"downed":
		[
			"tutorial.step.downed.title",
			"downed.give_up_hold",
			"tutorial.step.death.title",
			"tutorial.step.death.how",
		],
	}
	assert_array(HowtoCards.BASICS).is_equal([&"moving", &"voice", &"downed"])
	for id: StringName in HowtoCards.BASICS:
		var card := HowtoCards.of_basic(id)
		assert_object(card).is_not_null()
		assert_array(card.problems()).is_empty()
		assert_str(String(card.title)).is_equal("guide.%s" % id)
		var words: Array[String] = []
		for frame: HowtoFrame in card.frames:
			words.append(String(frame.text))
			if "{key}" in String(TranslationServer.translate(frame.text)):
				(
					assert_bool(InputMap.has_action(frame.key_action))
					. override_failure_message("%s fills {key} from no action" % frame.text)
					. is_true()
				)
		assert_array(words).is_equal(expected[id])


func test_every_key_a_card_names_is_in_the_deck_and_every_picture_is_in_the_game() -> void:
	var deck := _deck_keys()
	var cards: Array[HowtoCard] = []
	for mode: GameMode in _modes():
		cards.append_array(HowtoCards.of_tasks(mode))
	for id: StringName in HowtoCards.BASICS:
		cards.append(HowtoCards.of_basic(id))
	var pack_here := DirAccess.dir_exists_absolute(PACK_CARDS)
	for card: HowtoCard in cards:
		assert_bool(deck.has(String(card.title))).override_failure_message(card.title).is_true()
		for frame: HowtoFrame in card.frames:
			if not frame.text.is_empty():
				(
					assert_bool(deck.has(String(frame.text)))
					. override_failure_message(frame.text)
					. is_true()
				)
			if pack_here and not frame.art.is_empty():
				(
					assert_bool(ResourceLoader.exists(frame.art))
					. override_failure_message(frame.art)
					. is_true()
				)


func _modes() -> Array[GameMode]:
	var found: Array[GameMode] = []
	for file: String in DirAccess.get_files_at(MODES):
		if file.ends_with(".tres"):
			found.append(load(MODES + file) as GameMode)
	return found


func _deck_keys() -> Array[String]:
	var keys: Array[String] = []
	var file := FileAccess.open(DECK, FileAccess.READ)
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if not row.is_empty() and not row[0].is_empty():
			keys.append(row[0])
	return keys
