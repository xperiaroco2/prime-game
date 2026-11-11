extends GdUnitTestSuite
## The mirror's colour menu (#1394, the placeholder until #1395): it shows on the lobby screen only
## while the own player holds a mirror place in a phase that takes SetProfile (the lobby, not the
## countdown); a swatch per body colour; the own colour's swatch is pressed, from the host's
## ProfileChanged only (a click predicts nothing); a click asks for that colour with the own name
## kept; GameUi hides it, and gives the mouse back, on any screen but the lobby's.

const OWN := 2


func _model() -> ClientModel:
	var model := ClientModel.new(FixtureMirror.mode())
	model.own_peer = OWN
	model.fold(&"PhaseChanged", {"phase": &"lobby", "end_tick": -1})
	model.fold(&"PlayerJoined", {"peer": OWN, "name": "Olena", "spot": Vector3.ZERO, "colour": 1})
	model.fold(&"PlayerJoined", {"peer": 3, "name": "Dima", "spot": Vector3.ZERO, "colour": 2})
	return model


func test_it_shows_on_the_lobby_screen_while_the_own_player_holds_a_place() -> void:
	var model := _model()
	assert_bool(MirrorMenu.shown_for(model, GameFlow.Screen.LOBBY)).is_false()
	model.fold(&"MirrorPlaces", _places([4], [3]))
	assert_bool(MirrorMenu.shown_for(model, GameFlow.Screen.LOBBY)).is_false()
	model.fold(&"MirrorPlaces", _places([4, 5], [3, OWN]))
	assert_bool(MirrorMenu.shown_for(model, GameFlow.Screen.LOBBY)).is_true()
	assert_bool(MirrorMenu.shown_for(model, GameFlow.Screen.ROUND)).is_false()
	assert_bool(MirrorMenu.shown_for(null, GameFlow.Screen.LOBBY)).is_false()


## The countdown keeps the places (MirrorTicks) but takes no SetProfile: no menu whose clicks would
## all be refused.
func test_the_countdown_hides_it() -> void:
	var model := _model()
	model.fold(&"MirrorPlaces", _places([5], [OWN]))
	model.fold(&"PhaseChanged", {"phase": &"countdown", "end_tick": 100})
	assert_bool(MirrorMenu.shown_for(model, GameFlow.Screen.LOBBY)).is_false()


func test_a_swatch_per_body_colour_and_the_own_one_pressed() -> void:
	var model := _model()
	model.fold(&"MirrorPlaces", _places([5], [OWN]))
	var menu: MirrorMenu = auto_free(MirrorMenu.new())
	menu.refresh(model, GameFlow.Screen.LOBBY)
	assert_bool(menu.visible).is_true()
	assert_int(menu.swatches.size()).is_equal(BodyColours.HEXES.size())
	for index: int in menu.swatches.size():
		assert_bool(menu.swatches[index].button_pressed).is_equal(index == 1)
	model.fold(&"ProfileChanged", {"peer": OWN, "name": "Olena", "colour": 6})
	menu.refresh(model, GameFlow.Screen.LOBBY)
	for index: int in menu.swatches.size():
		assert_bool(menu.swatches[index].button_pressed).is_equal(index == 6)
	model.fold(&"MirrorPlaces", _places([], []))
	menu.refresh(model, GameFlow.Screen.LOBBY)
	assert_bool(menu.visible).is_false()


## A click on a toggle flips it before `pressed`: the menu sets it back, the host decides.
func test_a_click_asks_for_the_colour_and_predicts_nothing() -> void:
	var model := _model()
	model.fold(&"MirrorPlaces", _places([5], [OWN]))
	var menu: MirrorMenu = auto_free(MirrorMenu.new())
	menu.refresh(model, GameFlow.Screen.LOBBY)
	var chosen: Array[int] = []
	menu.colour_chosen.connect(func(colour: int) -> void: chosen.append(colour))
	_click(menu.swatches[4])
	assert_array(chosen).is_equal([4])
	assert_bool(menu.swatches[4].button_pressed).is_false()
	assert_bool(menu.swatches[1].button_pressed).is_true()
	# The own swatch clicked again stays pressed.
	_click(menu.swatches[1])
	assert_array(chosen).is_equal([4, 1])
	assert_bool(menu.swatches[1].button_pressed).is_true()
	assert_dict(MirrorMenu.profile_of(model, 4)).is_equal({"name": "Olena", "colour": 4})


## The code review of #1394: a leave (the main menu), or the match's screens, hide the menu and free
## no mouse any more, with one mirror_toggled(false).
func test_game_ui_hides_it_off_the_lobby_screen_and_gives_the_mouse_back() -> void:
	var model := _model()
	model.fold(&"MirrorPlaces", _places([5], [OWN]))
	var ui: GameUi = auto_free(GameUi.new())
	ui.show_screen(GameFlow.Screen.LOBBY)
	var toggled: Array[bool] = []
	ui.mirror_toggled.connect(func(on: bool) -> void: toggled.append(on))
	ui.refresh(model, FixtureMirror.mode(), 0, false)
	assert_bool(ui.mirror.visible).is_true()
	assert_bool(ui.frees_mouse()).is_true()
	ui.show_screen(GameFlow.Screen.MENU)
	assert_bool(ui.mirror.visible).is_false()
	assert_bool(ui.frees_mouse()).is_false()
	assert_array(toggled).is_equal([true, false])


## What a mouse click does to a toggle button: it flips, then `pressed` fires.
static func _click(button: Button) -> void:
	button.set_pressed_no_signal(not button.button_pressed)
	button.pressed.emit()


## A MirrorPlaces' fields as the wire decodes them.
static func _places(stations: Array[int], peers: Array[int]) -> Dictionary:
	return MirrorPlacesEvent.new(PackedInt32Array(stations), PackedInt32Array(peers)).to_dict()
