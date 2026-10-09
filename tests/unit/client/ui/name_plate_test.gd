extends GdUnitTestSuite
## NamePlate and TeammateMark (#257): the UI handoff's tree (Plate ToyNamePlate > Row ToyRowEight >
## Name ToyNamePlateText and Mark), the name as data that is never translated, the mark hidden
## unless asked for and tinted with the plate text's colour; and NamePlates.marked, the per-peer
## rule: the mark only for a teammate in the own role's Teammates, never the own player, never on
## a client without Teammates for its role (an engineer's), and GameUi shows the plate layer only
## in the lobby and the round, under every other screen.

const OWN := 1


func test_the_plate_is_the_handoffs_tree_with_the_name_as_data() -> void:
	var ui: GameUi = auto_free(GameUi.new())
	add_child(ui)
	var plate := NamePlate.new()
	ui.plates.add_child(plate)
	assert_str(String(plate.theme_type_variation)).is_equal("ToyNamePlate")
	assert_str(String(plate.row.theme_type_variation)).is_equal("ToyRowEight")
	assert_str(String(plate.name_label.theme_type_variation)).is_equal("ToyNamePlateText")
	assert_int(plate.name_label.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	assert_array(plate.row.get_children()).is_equal([plate.name_label, plate.mark])
	assert_bool(plate.is_marked()).is_false()
	for node: Control in [plate, plate.row, plate.name_label, plate.mark]:
		assert_int(node.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	plate.show_player("Olena", true)
	assert_str(plate.name_label.text).is_equal("Olena")
	assert_bool(plate.is_marked()).is_true()
	plate.show_player("Taras", false)
	assert_bool(plate.is_marked()).is_false()
	assert_vector(plate.mark.custom_minimum_size).is_equal(Vector2(20, 20))
	var text := GameUi.THEME.get_color(&"font_color", &"ToyNamePlateText")
	assert_object(plate.mark.tint()).is_equal(text)


func test_the_plate_centres_on_the_point() -> void:
	var ui: GameUi = auto_free(GameUi.new())
	add_child(ui)
	var plate := NamePlate.new()
	ui.plates.add_child(plate)
	plate.show_player("Olena", true)
	plate.centre_on(Vector2(538, 302))
	assert_vector(plate.position + plate.size * 0.5).is_equal_approx(
		Vector2(538, 302), Vector2.ONE * 0.01
	)
	assert_float(plate.size.x).is_greater(20.0)


func test_the_plate_shrinks_when_the_large_text_theme_is_swapped_back() -> void:
	var plate: NamePlate = auto_free(NamePlate.new())
	plate.theme = GameUi.THEME_LARGE
	add_child(plate)
	plate.show_player("Olena", false)
	await get_tree().process_frame
	var large := plate.size.x
	plate.theme = GameUi.THEME
	await get_tree().process_frame
	assert_float(plate.size.x).is_less(large)
	assert_vector(plate.size).is_equal_approx(plate.get_combined_minimum_size(), Vector2.ONE * 0.01)


func test_a_dissident_marks_its_teammates_only_never_itself() -> void:
	var model := _model()
	model.fold(&"RoleAssigned", {"role": &"dissident"})
	model.fold(&"Teammates", {"role": &"dissident", "peers": PackedInt32Array([OWN, 3, 5])})
	assert_bool(NamePlates.marked(model, 3)).is_true()
	assert_bool(NamePlates.marked(model, 5)).is_true()
	assert_bool(NamePlates.marked(model, 2)).is_false()
	assert_bool(NamePlates.marked(model, OWN)).is_false()


func test_an_engineers_client_never_marks_anyone() -> void:
	var model := _model()
	model.fold(&"RoleAssigned", {"role": &"engineer"})
	for peer: int in [OWN, 2, 3, 4]:
		assert_bool(NamePlates.marked(model, peer)).is_false()
	# Even a list for another role (the host never sends one) marks nobody: the own role's only.
	model.fold(&"Teammates", {"role": &"dissident", "peers": PackedInt32Array([2, 3])})
	for peer: int in [OWN, 2, 3, 4]:
		assert_bool(NamePlates.marked(model, peer)).is_false()
	# Before any role (the lobby): nobody.
	assert_bool(NamePlates.marked(_model(), 2)).is_false()


func test_the_layer_shows_in_the_lobby_and_the_round_under_every_screen() -> void:
	var ui: GameUi = auto_free(GameUi.new())
	add_child(ui)
	assert_object(ui.get_child(0)).is_same(ui.plates)
	assert_object(ui.plates.theme).is_same(GameUi.THEME)
	for screen: GameFlow.Screen in GameFlow.Screen.values():
		ui.show_screen(screen)
		var walking := screen == GameFlow.Screen.LOBBY or screen == GameFlow.Screen.ROUND
		assert_bool(ui.plates.visible).override_failure_message(str(screen)).is_equal(walking)


func _model() -> ClientModel:
	var model := ClientModel.new(FixtureBaseMode.mode())
	var welcome := WelcomeEvent.new(OWN, Vector3.ZERO, 1)
	welcome.roster.assign([{"peer": OWN, "name": "Me", "ready": false}])
	welcome.settings = FixtureBaseMode.mode().default_settings()
	welcome.phase = &"lobby"
	model.fold(&"Welcome", welcome.to_dict())
	return model
