extends GdUnitTestSuite
## A how-to card's checks and its drawing (#254; prime-game-ui's P8 at ui-0.4.0): HowtoCard's
## problems, HowtoCards' dealable task types, and HowtoCardView's tree node for node (Head with the
## title and `howto.label`, Frame1 to Frame4 with the finish frame ToyHowtoFrameDone, the art's size
## per place, a placeholder naming a missing PNG, a basic's words with the bound key, both
## languages, Close on the map's card).

const MODE := "res://content/modes/base_mode.tres"
const Preview := preload("res://client/dev/screen_preview.gd")

var _mode: GameMode


func before() -> void:
	_mode = load(MODE) as GameMode


func after_test() -> void:
	TranslationServer.set_locale(Languages.ENGLISH)


func test_a_card_needs_three_to_four_frames_each_a_picture_or_words() -> void:
	var card := _card(3)
	assert_array(card.problems()).is_empty()
	assert_array(_card(2).problems()).is_not_empty()
	assert_array(_card(5).problems()).is_not_empty()
	card = _card(3)
	card.frames[1].art = ""
	assert_array(card.problems()).is_not_empty()
	card = _card(3)
	card.frames[1].text = &"task.delivery"
	assert_array(card.problems()).is_not_empty()
	card = _card(3)
	card.frames[0].done = true
	assert_str(card.problems()[0]).contains("not the last")
	card = _card(3)
	card.frames[0].art = "user://x.png"
	assert_array(card.problems()).is_not_empty()
	card = _card(3)
	card.title = &""
	assert_array(card.problems()).is_not_empty()


func test_the_dealable_types_leave_out_the_banned_ones() -> void:
	var model := Preview.fake_model(_mode, true)
	assert_array(HowtoCards.dealable(_mode, model)).is_equal([&"delivery"])
	model.id_sets[&"banned_task_types"] = PackedStringArray(["delivery"])
	assert_array(HowtoCards.dealable(_mode, model)).is_empty()
	assert_array(HowtoCards.dealable(_mode, null)).is_equal([&"delivery"])


func test_the_dealable_types_read_only_the_deals_banned_set() -> void:
	var model := Preview.fake_model(_mode, true)
	# Another set setting (say a later "banned roles") that happens to name a task type.
	model.id_sets[&"some_other_set"] = PackedStringArray(["delivery"])
	assert_array(HowtoCards.dealable(_mode, model)).is_equal([&"delivery"])
	assert_str(String(HowtoCards.deal_of(_mode).banned_setting)).is_equal("banned_task_types")
	var no_deal := GameMode.new()
	no_deal.task_types = _mode.task_types
	assert_object(HowtoCards.deal_of(no_deal)).is_null()
	assert_array(HowtoCards.dealable(no_deal, model)).is_empty()


func test_only_types_with_a_card_reach_the_loading_pick() -> void:
	var types: Array[StringName] = [&"no_such_type", &"delivery"]
	var with_card := HowtoCards.with_card(types)
	assert_array(with_card).is_equal([&"delivery"])
	assert_str(String(HowtoProgress.new().loading_pick(with_card))).is_equal("delivery")


func test_the_card_is_drawn_node_for_node() -> void:
	var made := HowtoCardView.raised(_card(4), HowtoCardView.MAP_ART, ToyHints.LIGHT, true)
	add_child(made)
	auto_free(made)
	var face := HowtoCardView.face_of(made)
	assert_str(face.name).is_equal("Card")
	assert_str(String(face.theme_type_variation)).is_equal("ToyPanelHowto")
	assert_str(String(made.base.theme_type_variation)).is_equal("ToyBasePanel")
	assert_str(String((face.get_node(^"V") as Control).theme_type_variation)).is_equal(
		"ToyColumnSixteen"
	)
	var title := face.get_node(^"V/Head/Title") as Label
	assert_str(String(title.theme_type_variation)).is_equal("ToyTitleOnLight")
	assert_int(title.size_flags_horizontal).is_equal(Control.SIZE_EXPAND_FILL)
	assert_str(title.text).is_equal("task.delivery")
	var note := face.get_node(^"V/Head/Note") as Label
	assert_str(String(note.theme_type_variation)).is_equal("ToyHowtoNote")
	assert_str(note.text).is_equal("howto.label")
	var frames := face.get_node(^"V/Frames") as HBoxContainer
	assert_str(String(frames.theme_type_variation)).is_equal("ToyRowTwelve")
	var looks: Array[String] = []
	for frame: Node in frames.get_children():
		looks.append(String((frame as Control).theme_type_variation))
		assert_int((frame as Control).size_flags_horizontal).is_equal(Control.SIZE_EXPAND_FILL)
	assert_array(looks).is_equal(
		["ToyHowtoFrame", "ToyHowtoFrame", "ToyHowtoFrame", "ToyHowtoFrameDone"]
	)
	assert_str(frames.get_child(0).name).is_equal("Frame1")
	var close := face.get_node(^"V/Bar/CloseRaised/Close") as Button
	assert_str(close.text).is_equal("common.close")
	assert_str(String(close.theme_type_variation)).is_equal("ToyButtonSecondary")
	assert_int((face.get_node(^"V/Bar") as BoxContainer).alignment).is_equal(
		BoxContainer.ALIGNMENT_END
	)
	var asked := [0]
	face.close_requested.connect(func() -> void: asked[0] += 1)
	close.pressed.emit()
	assert_int(asked[0]).is_equal(1)


func test_a_picture_fills_its_frame_and_a_missing_one_is_named() -> void:
	var card := _card(3)
	card.frames[0].art = "res://icon.svg.png"
	var face := HowtoCardView.new(card, HowtoCardView.GUIDE_ART)
	auto_free(face)
	assert_object(face.close_button).is_null()
	assert_bool(face.has_node(^"V/Bar")).is_false()
	var stand_in := face.get_node(^"V/Frames/Frame1/Placeholder") as Label
	assert_str(stand_in.text).is_equal("icon.svg.png")
	assert_str(String(stand_in.theme_type_variation)).is_equal("ToyTextMutedOnLight")
	assert_that(stand_in.custom_minimum_size).is_equal(Vector2(160, 120))
	# A picture that is in the game: a TextureRect at the place's size, keeping its aspect.
	card.frames[0].art = "res://icon.svg"
	face = HowtoCardView.new(card, HowtoCardView.LOADING_ART)
	auto_free(face)
	var art := face.get_node(^"V/Frames/Frame1/Art") as TextureRect
	assert_object(art.texture).is_not_null()
	assert_that(art.custom_minimum_size).is_equal(Vector2(352, 264))
	assert_int(art.expand_mode).is_equal(TextureRect.EXPAND_IGNORE_SIZE)
	assert_int(art.stretch_mode).is_equal(TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	assert_that(HowtoCardView.MAP_ART).is_equal(Vector2(320, 240))


func test_a_basics_words_fill_the_bound_key_in_both_languages() -> void:
	var card := HowtoCards.of_basic(&"downed")
	var face := HowtoCardView.new(card, HowtoCardView.GUIDE_ART)
	add_child(face)
	auto_free(face)
	var words := face.get_node(^"V/Frames/Frame2/Words") as Label
	var key := KeyLabel.of_action(&"give_up")
	assert_str(key).is_not_empty()
	assert_str(words.text).is_equal("Hold %s to give up" % key)
	assert_int(words.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	TranslationServer.set_locale(Languages.UKRAINIAN)
	face.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
	assert_str(words.text).is_equal("Щоб здатися, утримуй %s" % key)
	assert_str((face.get_node(^"V/Frames/Frame1/Words") as Label).text).is_equal(
		"Підніми гравця з нокдауну"
	)


## A card of `count` frames with pictures, the last the finish.
static func _card(count: int) -> HowtoCard:
	var card := HowtoCard.new()
	card.id = &"delivery"
	card.title = &"task.delivery"
	for i in count:
		var frame := HowtoFrame.new()
		frame.art = "res://nothing/frame-%d.png" % (i + 1)
		frame.done = i == count - 1
		card.frames.append(frame)
	return card
