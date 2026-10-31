extends GdUnitTestSuite
## A Welcome's item rows folded into the ClientModel (ARCHITECTURE §4.2, §4.6, #1404): every rest
## state, the carriers' hands, belts and selected places, a locked item, the rows a client skips,
## a Welcome without rows, and a second Welcome replacing the first's items. The client's copies
## of core/'s rest states are pinned here.

const P1 := 1
const P3 := 3
const OWN := 4


func test_the_rest_states_are_core_s_in_the_same_order() -> void:
	for copy: Dictionary in [WelcomeItems.Rest, ScenarioBot.Where]:
		for state: String in WelcomeItems.Rest:
			assert_int(copy[state]).override_failure_message(state).is_equal(ItemState.Where[state])
	assert_int(ScenarioBot.Where.FLYING).is_equal(ItemState.Where.FLYING)


func test_every_rest_state_folds_as_the_host_has_it() -> void:
	var model := _welcomed(
		[
			_row(11, &"tool", ItemState.Where.BELT, P1, 0, Vector3.ZERO),
			_row(12, &"mug", ItemState.Where.HAND, P1, 2, Vector3.ZERO),
			_row(13, &"tool", ItemState.Where.BELT, P1, 1, Vector3.ZERO),
			_row(14, &"mug", ItemState.Where.HAND, P3, 0, Vector3.ZERO),
			_row(20, &"mug", ItemState.Where.GROUND, 0, 0, Vector3(1, 0, 2)),
			_row(21, &"tool", ItemState.Where.LOCKED, 0, 0, Vector3(3, 0.5, -3)),
		]
	)
	assert_array(model.items.keys()).contains_exactly_in_any_order([11, 12, 13, 14, 20, 21])
	assert_int(model.hand_item(P1)).is_equal(12)
	assert_int(model.belt_item(P1)).is_equal(11)
	assert_int(model.belt_item2(P1)).is_equal(13)
	assert_int(model.selected_place(P1)).is_equal(2)
	assert_int(model.item_in_place(P1, 1)).is_equal(13)
	assert_int(model.hand_item(P3)).is_equal(14)
	assert_int(model.belt_item(P3)).is_equal(-1)
	assert_int(model.hand_item(OWN)).is_equal(-1)
	assert_str(String(model.items[12].kind)).is_equal("mug")
	var lying := model.items[20]
	assert_bool(lying.rests()).is_true()
	assert_bool(lying.locked).is_false()
	assert_vector(lying.position).is_equal(Vector3(1, 0, 2))
	assert_int(lying.carry_place).is_equal(-1)
	var locked := model.items[21]
	assert_bool(locked.rests()).is_true()
	assert_bool(locked.locked).is_true()
	assert_int(locked.on_station).is_equal(-1)
	assert_int(locked.holder).is_equal(ClientModel.NO_HOLDER)


func test_rows_this_build_cannot_place_are_skipped() -> void:
	var model := _welcomed(
		[
			_row(1, &"tool", ItemState.Where.FLYING, 0, 0, Vector3.ZERO),
			_row(2, &"tool", 9, 0, 0, Vector3.ZERO),
			_row(3, &"tool", ItemState.Where.HAND, P1, 3, Vector3.ZERO),
			_row(4, &"tool", ItemState.Where.BELT, 0, 1, Vector3.ZERO),
			_row(5, &"tool", ItemState.Where.GROUND, P1, 0, Vector3.ZERO),
			_row(6, &"tool", ItemState.Where.GROUND, 0, 0, Vector3.ONE),
		]
	)
	assert_array(model.items.keys()).is_equal([6])
	assert_int(model.hand_item(P1)).is_equal(-1)
	assert_dict(model.selected_places).is_empty()


func test_a_welcome_without_rows_folds_and_a_second_one_replaces_the_items() -> void:
	var model := ClientModel.new(FixtureBaseMode.mode())
	var bare := _welcome([])
	bare.erase("items")
	model.fold(&"Welcome", bare)
	assert_int(model.own_peer).is_equal(OWN)
	assert_dict(model.items).is_empty()
	model.fold(&"Welcome", _welcome([_row(7, &"tool", ItemState.Where.HAND, P1, 1, Vector3.ZERO)]))
	assert_int(model.hand_item(P1)).is_equal(7)
	model.fold(&"Welcome", _welcome([_row(8, &"tool", ItemState.Where.GROUND, 0, 0, Vector3.ONE)]))
	assert_array(model.items.keys()).is_equal([8])
	assert_int(model.hand_item(P1)).is_equal(-1)
	assert_int(model.selected_place(P1)).is_equal(0)


func _welcomed(rows: Array[Dictionary]) -> ClientModel:
	var model := ClientModel.new(FixtureBaseMode.mode())
	model.fold(&"Welcome", _welcome(rows))
	return model


func _welcome(rows: Array[Dictionary]) -> Dictionary:
	var welcome := WelcomeEvent.new(OWN, Vector3.ZERO, 1)
	welcome.roster.assign([{"peer": OWN, "name": "Ann", "ready": false, "colour": 0}])
	welcome.map = FixtureBaseMode.MAP
	welcome.phase = &"lobby"
	welcome.items = rows
	return welcome.to_dict()


func _row(
	id: int, kind: StringName, where: int, holder: int, place: int, at: Vector3
) -> Dictionary:
	return {
		"item": id, "kind": kind, "where": where, "holder": holder, "place": place, "position": at
	}
