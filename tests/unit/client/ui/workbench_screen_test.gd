extends GdUnitTestSuite
## The mutation workbench's screen (client/ui/WorkbenchScreen, #1572) under the shared theme: the UI
## handoff's s11 at ui-2.5.4 node for node in its three states (idle, choose, step), a card's look
## and button by the points, the card under the pointer drawn pointed, the signals, the price's
## plural in English and Ukrainian. The mutations here are the handoff's samples (the game has no
## points or mutations yet).

var _locale := ""


func before_test() -> void:
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_test() -> void:
	TranslationServer.set_locale(_locale)


func test_idle_is_the_machines_name_and_start() -> void:
	var screen := await _screen()
	assert_str(String(screen.name)).is_equal("Screen")
	assert_str(String(screen.theme_type_variation)).is_equal("ToyPanelDialog")
	assert_vector(screen.custom_minimum_size).is_equal(Vector2(960, 540))
	assert_int(screen.state).is_equal(WorkbenchScreen.State.IDLE)
	assert_bool(screen.idle.visible).is_true()
	assert_bool(screen.choose.visible or screen.step.visible).is_false()
	var column := screen.get_node("Idle/V") as VBoxContainer
	assert_str(String(column.theme_type_variation)).is_equal("ToyColumnTwentyFour")
	assert_int(column.alignment).is_equal(BoxContainer.ALIGNMENT_CENTER)
	var title := screen.get_node("Idle/V/Title") as Label
	assert_str(String(title.theme_type_variation)).is_equal("ToyTitleMachine")
	assert_str(title.text).is_equal("workbench.title")
	assert_str(String(screen.start_button.theme_type_variation)).is_equal("ToyButtonPrimary")
	assert_str(screen.start_button.text).is_equal("workbench.start")
	assert_vector(screen.start_button.custom_minimum_size).is_equal(Vector2(288, 0))
	assert_int(screen.start_button.size_flags_horizontal).is_equal(Control.SIZE_SHRINK_CENTER)
	var started: Array[int] = [0]
	screen.start_pressed.connect(func() -> void: started[0] += 1)
	screen.start_button.pressed.emit()
	assert_int(started[0]).is_equal(1)


func test_choose_shows_the_points_and_a_card_per_mutation() -> void:
	var screen := await _screen()
	screen.show_choose(7, _offer())
	assert_bool(screen.choose.visible).is_true()
	assert_bool(screen.idle.visible or screen.step.visible).is_false()
	assert_str(String(screen.choose.theme_type_variation)).is_equal("ToyColumnTwentyFour")
	var top := screen.get_node("Choose/Top") as HBoxContainer
	assert_str(String(top.theme_type_variation)).is_equal("ToyRowSixteen")
	var top_title := top.get_node("Title") as Label
	assert_int(top_title.size_flags_horizontal).is_equal(Control.SIZE_EXPAND_FILL)
	assert_int(top_title.size_flags_vertical).is_equal(Control.SIZE_SHRINK_CENTER)
	var balance := screen.get_node("Choose/Top/Balance") as PanelContainer
	assert_str(String((balance.get_node("Row") as Control).theme_type_variation)).is_equal(
		"ToyRowSixteen"
	)
	assert_int(screen.points_label.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	assert_str(String(balance.theme_type_variation)).is_equal("ToyPlateBalance")
	assert_str((balance.get_node("Row/Label") as Label).text).is_equal("workbench.points")
	assert_str(String(screen.points_label.theme_type_variation)).is_equal("ToyPlateTimer")
	assert_str(screen.points_label.text).is_equal("7")
	assert_str(String(screen.cards.theme_type_variation)).is_equal("ToyRowTwentyFour")
	var names: Array[String] = []
	for card: Node in screen.cards.get_children():
		names.append(String(card.name))
	assert_array(names).is_equal(["Fast", "Jump", "Health"])
	# Affordable: its name and price, Mutate enabled.
	var fast := screen.card_of(&"fast")
	assert_str(String(fast.theme_type_variation)).is_equal("ToyMutationCard")
	assert_str((fast.get_node("V/Name") as Label).text).is_equal("mutation.fast.name")
	assert_str((fast.get_node("V/Name") as Label).theme_type_variation).is_equal(
		&"ToyMutationCardName"
	)
	var effect := fast.get_node("V/Effect") as Label
	assert_str(String(effect.theme_type_variation)).is_equal("ToyMutationCardText")
	assert_int(effect.size_flags_vertical).is_equal(Control.SIZE_EXPAND_FILL)
	assert_vector(effect.custom_minimum_size).is_equal(Vector2(200, 0))
	assert_int(effect.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
	for path: String in ["V/Cost", "V/Buy"]:
		assert_int((fast.get_node(path) as Control).auto_translate_mode).is_equal(
			Node.AUTO_TRANSLATE_MODE_DISABLED
		)
	assert_str((fast.get_node("V/Cost") as Label).text).is_equal("4 points")
	var buy := fast.get_node("V/Buy") as Button
	assert_str(String(buy.theme_type_variation)).is_equal("ToyButtonMutate")
	assert_bool(buy.disabled).is_false()
	assert_str(buy.text).is_equal("Mutate")
	# Short of points: the name and price dimmed, the button disabled with the shortfall.
	var health := screen.card_of(&"health")
	assert_str((health.get_node("V/Name") as Label).theme_type_variation).is_equal(
		&"ToyMutationCardNameOff"
	)
	assert_str((health.get_node("V/Cost") as Label).theme_type_variation).is_equal(
		&"ToyMutationCardCostOff"
	)
	var short := health.get_node("V/Buy") as Button
	assert_bool(short.disabled).is_true()
	assert_str(short.text).is_equal("2 short")
	# Mutate says which.
	var bought: Array[StringName] = []
	screen.mutate_pressed.connect(func(id: StringName) -> void: bought.append(id))
	(screen.card_of(&"jump").get_node("V/Buy") as Button).pressed.emit()
	assert_array(bought).is_equal([&"jump"])


func test_the_card_under_the_pointer_is_drawn_pointed() -> void:
	var screen := await _screen()
	screen.show_choose(7, _offer())
	var jump := screen.card_of(&"jump")
	jump.mouse_entered.emit()
	assert_str(String(jump.theme_type_variation)).is_equal("ToyMutationCardPointed")
	jump.mouse_exited.emit()
	assert_str(String(jump.theme_type_variation)).is_equal("ToyMutationCard")


func test_step_names_the_mutation_and_fills_ten_pips() -> void:
	var screen := await _screen()
	screen.show_step("mutation.jump.name", 0.6)
	assert_bool(screen.step.visible).is_true()
	assert_bool(screen.idle.visible or screen.choose.visible).is_false()
	assert_str(String(screen.chosen_label.theme_type_variation)).is_equal("ToyKicker")
	assert_bool(screen.chosen_label.uppercase).is_true()
	assert_str(screen.chosen_label.text).is_equal("mutation.jump.name")
	assert_int(screen.chosen_label.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_CENTER)
	var step_in := screen.get_node("Step/V/StepIn") as Label
	assert_str(String(step_in.theme_type_variation)).is_equal("ToyTitleOnLight")
	assert_int(step_in.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_CENTER)
	assert_str(String(screen.pips.theme_type_variation)).is_equal("ToyRowFour")
	assert_int(screen.pips.size_flags_horizontal).is_equal(Control.SIZE_SHRINK_CENTER)
	assert_str(step_in.text).is_equal("workbench.step_in")
	var full := 0
	for pip: Node in screen.pips.get_children():
		if (pip as Panel).theme_type_variation == &"ToyPipHealth":
			full += 1
	assert_int(screen.pips.get_child_count()).is_equal(10)
	assert_int(full).is_equal(6)


func test_the_words_follow_the_language() -> void:
	var screen := await _screen()
	screen.show_choose(7, _offer())
	TranslationServer.set_locale("uk")
	await get_tree().process_frame
	var fast := screen.card_of(&"fast")
	assert_str((fast.get_node("V/Cost") as Label).text).is_equal("4 очки")
	assert_str((screen.card_of(&"health").get_node("V/Cost") as Label).text).is_equal("9 очок")
	assert_str((screen.card_of(&"health").get_node("V/Buy") as Button).text).is_equal("Бракує 2")
	assert_str((fast.get_node("V/Buy") as Button).text).is_equal("Мутувати")


func test_every_look_it_names_is_in_the_theme() -> void:
	# The looks the theme test's line scan misses (set through a local or a wrapped line).
	for variation: StringName in [
		&"ToyMutationCard",
		&"ToyMutationCardPointed",
		&"ToyMutationCardName",
		&"ToyMutationCardNameOff",
		&"ToyMutationCardCost",
		&"ToyMutationCardCostOff",
		&"ToyButtonMutate",
		&"ToyPlateBalance",
		&"ToyTitleMachine",
		&"ToyRosterName",
		&"ToyRosterNameSelf",
		&"ToyRosterNameDead",
	]:
		(
			assert_str(String(GameUi.THEME.get_type_variation_base(variation)))
			. override_failure_message(variation)
			. is_not_empty()
		)


## The handoff's sample: Quick feet (4), Spring legs (3), Thick skin (9).
static func _offer() -> Array[WorkbenchScreen.Mutation]:
	var offer: Array[WorkbenchScreen.Mutation] = [
		WorkbenchScreen.Mutation.new(&"fast", "mutation.fast.name", "mutation.fast.effect", 4),
		WorkbenchScreen.Mutation.new(&"jump", "mutation.jump.name", "mutation.jump.effect", 3),
		WorkbenchScreen.Mutation.new(
			&"health", "mutation.health.name", "mutation.health.effect", 9
		),
	]
	return offer


func _screen() -> WorkbenchScreen:
	var holder: Control = auto_free(Control.new())
	holder.theme = GameUi.THEME
	add_child(holder)
	var screen := WorkbenchScreen.new()
	holder.add_child(screen)
	await get_tree().process_frame
	return screen
