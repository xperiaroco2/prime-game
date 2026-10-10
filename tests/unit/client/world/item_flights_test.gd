extends GdUnitTestSuite
## ItemFlights (client/world/item_flights.gd; ARCHITECTURE §4.7.25, §7.1.16; the throwing ADR's
## TE5 (a)): the own key press predicts the arc and hides the hand item until the host answers;
## its Rejected (by seq) or no answer gives the item back; the own ItemThrown is adopted, another
## throw drawn on the avatars' timeline; ItemPlaced (thrown) ends an arc at its stop with a short
## fall; a phase change or a new match hides every arc; only the own arc is swept; the launch
## sound and the landing sound are due once each, when the drawn item gets there. A hand-folded
## ClientModel of the throw fixture mode (FixtureThrowModes: 10 m/s, 9.8 m/s²).

const OWN := 1
const OTHER := 2
const FRAME_S := 1.0 / 60.0
const EYE := Vector3(0, 1.6, 0)
const LOOK := Vector3(0, 0, -1)

var _mode: GameMode
var _model: ClientModel
var _flights: ItemFlights
var _swept := 0
## What the fake sweep answers: INF lets every segment through.
var _wall_at := Vector3.INF


func before_test() -> void:
	_mode = FixtureThrowModes.basic()
	_model = ClientModel.new(_mode)
	_model.own_peer = OWN
	_model.phase = &"round"
	_flights = ItemFlights.new()
	_swept = 0
	_wall_at = Vector3.INF
	_spawn(1, OWN)
	_spawn(2, OTHER)


func test_the_press_hides_the_hand_item_and_its_rejected_gives_it_back() -> void:
	assert_bool(_flights.predict(_model, _mode, 7, EYE, LOOK)).is_true()
	assert_bool(_flights.hides_hand(1)).is_true()
	assert_bool(_flights.has(1)).is_true()
	var due := _flights.take_due()
	assert_int(due.size()).is_equal(1)
	assert_str(String(due[0][0] as StringName)).is_equal("ItemThrown")
	assert_vector((due[0][1] as Dictionary)["origin"] as Vector3).is_equal(EYE)
	# A second press waits for the first answer.
	assert_bool(_flights.predict(_model, _mode, 8, EYE, LOOK)).is_false()
	# Another intent's Rejected changes nothing; the Throw's own drops the prediction.
	_flights.on_event(&"Rejected", {"seq": 6, "reason": &"x"}, _model, 0.0)
	assert_bool(_flights.hides_hand(1)).is_true()
	_flights.on_event(&"Rejected", {"seq": 7, "reason": &"no_floor"}, _model, 0.0)
	assert_bool(_flights.hides_hand(1)).is_false()
	assert_bool(_flights.has(1)).is_false()
	assert_array(_flights.take_due()).is_empty()


func test_no_answer_gives_the_item_back() -> void:
	_flights.predict(_model, _mode, 7, EYE, LOOK)
	_advance(ItemFlights.PREDICTION_TIMEOUT_S - 0.1)
	assert_bool(_flights.hides_hand(1)).is_true()
	_advance(0.2)
	assert_bool(_flights.hides_hand(1)).is_false()
	assert_bool(_flights.has(1)).is_false()


func test_the_own_throw_answered_after_the_timeout_is_not_heard_twice() -> void:
	_flights.predict(_model, _mode, 7, EYE, LOOK)
	assert_int(_flights.take_due().size()).is_equal(1)
	_advance(ItemFlights.PREDICTION_TIMEOUT_S + 0.1)
	assert_bool(_flights.has(1)).is_false()
	# The late ItemThrown draws on the avatars' timeline; the launch already sounded at the press.
	_throw(_launch(1, OWN, 10))
	_advance(FRAME_S, 12.0)
	assert_bool(_flights.has(1)).is_true()
	assert_array(_flights.take_due()).is_empty()
	# Another player's launch is heard when it is drawn.
	_throw(_launch(2, OTHER, 10))
	_advance(FRAME_S, 12.0)
	assert_int(_flights.take_due().size()).is_equal(1)


func test_nothing_is_predicted_without_a_rule_or_a_hand_item() -> void:
	var plain_mode := FixtureItemModes.basic()
	var plain := ClientModel.new(plain_mode)
	plain.own_peer = OWN
	plain.fold(&"ItemSpawned", {"item": 1, "kind": &"package", "position": Vector3.ZERO})
	plain.fold(&"ItemPickedUp", {"peer": OWN, "item": 1})
	assert_bool(_flights.predict(plain, plain_mode, 7, EYE, LOOK)).is_false()
	_model.fold(&"ItemPlaced", {"item": 1, "position": Vector3.ZERO, "cause": &"put_down"})
	assert_bool(_flights.predict(_model, _mode, 7, EYE, LOOK)).is_false()
	assert_bool(_flights.is_predicting()).is_false()


func test_the_own_item_thrown_is_adopted_with_no_second_launch_sound() -> void:
	_flights.predict(_model, _mode, 7, EYE, LOOK)
	_flights.take_due()
	_advance(0.1)
	var launch := _launch(1, OWN, 30)
	launch["origin"] = EYE + Vector3(0, -0.1, 0)
	_throw(launch)
	var arc: ItemArc = _flights.arcs[1]
	assert_bool(arc.predicted).is_false()
	assert_bool(arc.own).is_true()
	assert_vector(arc.origin).is_equal(launch["origin"] as Vector3)
	assert_bool(_flights.hides_hand(1)).is_false()
	# The thrower's clock goes on from the press: no jump back to the launch.
	assert_float(arc.n).is_equal_approx(0.1 * Ticks.RATE, 0.01)
	_advance(0.5)
	assert_array(_flights.take_due()).is_empty()


func test_another_players_throw_is_drawn_on_the_avatars_timeline() -> void:
	_throw(_launch(2, OTHER, 30))
	_advance(FRAME_S, 28.0)
	assert_bool((_flights.position_of(2) as Vector3).is_finite()).is_false()
	assert_array(_flights.take_due()).is_empty()
	_advance(FRAME_S, 30.0)
	assert_vector(_flights.position_of(2) as Vector3).is_equal(_point(2, 0))
	var due := _flights.take_due()
	assert_int(due.size()).is_equal(1)
	assert_str(String(due[0][0] as StringName)).is_equal("ItemThrown")
	_advance(FRAME_S, 36.0)
	assert_vector(_flights.position_of(2) as Vector3).is_equal(_point(2, 6))
	assert_array(_flights.take_due()).is_empty()
	# Another player's arc is never swept.
	assert_int(_swept).is_equal(0)


func test_the_arc_holds_to_its_stop_falls_and_then_lands_with_its_sound() -> void:
	var launch := _launch(2, OTHER, 30)
	_throw(launch)
	var stop := _point(2, 12)
	var rest := Vector3(stop.x, 0, stop.z)
	var placed := {"item": 2, "position": rest, "cause": Items.THROWN}
	_model.fold(&"ItemPlaced", placed)
	_flights.on_event(&"ItemPlaced", placed, _model, 43.0)
	_advance(FRAME_S, 35.0)
	assert_vector(_flights.position_of(2) as Vector3).is_equal(_point(2, 5))
	_advance(FRAME_S, 42.0)
	var falling := _flights.position_of(2) as Vector3
	assert_float(falling.y).is_between(0.0, stop.y)
	_flights.take_due()
	_advance(FRAME_S, 42.0 + sqrt(2.0 * stop.y / 9.8) * Ticks.RATE + 0.1)
	assert_bool(_flights.has(2)).is_false()
	var due := _flights.take_due()
	assert_int(due.size()).is_equal(1)
	assert_str(String(due[0][0] as StringName)).is_equal("ItemPlaced")
	assert_dict(due[0][1] as Dictionary).is_equal(placed)


func test_an_item_placed_with_no_arc_lands_at_once_and_a_put_down_is_not_a_landing() -> void:
	var placed := {"item": 2, "position": Vector3(3, 0, 0), "cause": Items.THROWN}
	_flights.on_event(&"ItemPlaced", placed, _model, 10.0)
	assert_int(_flights.take_due().size()).is_equal(1)
	_flights.on_event(
		&"ItemPlaced", {"item": 1, "position": Vector3.ZERO, "cause": &"put_down"}, _model, 10.0
	)
	assert_array(_flights.take_due()).is_empty()


func test_the_own_arc_stops_at_the_first_wall_until_its_item_placed() -> void:
	_flights.predict(_model, _mode, 7, EYE, LOOK)
	_advance(0.05)
	assert_int(_swept).is_greater(0)
	var wall := EYE + LOOK * 1.0
	_wall_at = wall
	_advance(FRAME_S)
	assert_vector(_flights.position_of(1) as Vector3).is_equal(wall)
	_wall_at = Vector3.INF
	_advance(0.3)
	assert_vector(_flights.position_of(1) as Vector3).is_equal(wall)
	# The host's answer: the item dropped below the wall; the drawn one falls from where it was held.
	var launch := _launch(1, OWN, 30)
	launch["velocity"] = LOOK * 10.0
	_throw(launch)
	var placed := {"item": 1, "position": Vector3(wall.x, 0, wall.z), "cause": Items.THROWN}
	_model.fold(&"ItemPlaced", placed)
	_flights.on_event(&"ItemPlaced", placed, _model, 40.0)
	var swept := _swept
	_advance(FRAME_S)
	assert_int(_swept).is_equal(swept)
	assert_float((_flights.position_of(1) as Vector3).y).is_less(wall.y)
	_advance(1.0)
	assert_bool(_flights.has(1)).is_false()


func test_a_phase_change_or_a_new_match_drops_every_arc() -> void:
	for event_name: StringName in [&"PhaseChanged", &"LoadMatch"]:
		_flights.predict(_model, _mode, 7, EYE, LOOK)
		_throw(_launch(2, OTHER, 30))
		_flights.on_event(event_name, {}, _model, 31.0)
		assert_bool(_flights.has(1)).is_false()
		assert_bool(_flights.has(2)).is_false()
		assert_bool(_flights.is_predicting()).is_false()
		_spawn(2, OTHER)


func test_an_item_picked_up_loses_its_arc() -> void:
	_throw(_launch(2, OTHER, 30))
	_model.fold(&"ItemPlaced", {"item": 2, "position": Vector3(0, 0, -3), "cause": Items.THROWN})
	_model.fold(&"ItemPickedUp", {"peer": OWN, "item": 2})
	_advance(FRAME_S, 31.0)
	assert_bool(_flights.has(2)).is_false()


func _spawn(id: int, holder: int) -> void:
	_model.fold(&"ItemSpawned", {"item": id, "kind": &"tool", "position": Vector3.ZERO})
	_model.fold(&"ItemPickedUp", {"peer": holder, "item": id})


func _launch(id: int, peer: int, tick: int) -> Dictionary:
	return {
		"item": id,
		"peer": peer,
		"origin": Vector3(4, 1.6, 0),
		"velocity": Vector3(0, 4, -8),
		"gravity": Vector3(0, -9.8, 0),
		"tick": tick,
	}


func _throw(launch: Dictionary) -> void:
	_model.fold(&"ItemThrown", launch)
	_flights.on_event(&"ItemThrown", launch, _model, float(launch["tick"] as int))


func _point(id: int, n: int) -> Vector3:
	var arc: ItemArc = _flights.arcs[id]
	return ItemFlight.point(arc.origin, arc.velocity, arc.gravity, n)


func _advance(seconds: float, drawn_tick := -1.0) -> void:
	_flights.advance(seconds, drawn_tick, _model, _sweep)


func _sweep(from: Vector3, to: Vector3, _radius: float) -> Vector3:
	_swept += 1
	if _wall_at.is_finite() and from != to:
		return _wall_at
	return to
