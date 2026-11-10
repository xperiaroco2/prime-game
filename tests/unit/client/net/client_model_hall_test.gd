extends GdUnitTestSuite
## The client's half of the dead's hall (#1489): ClientModel says a dead player waits there only in
## a phase that lets the dead move, its body then runs as a living one's, PrintStarted makes it a
## printing player with no body left..

const OWN := 2

var _model: ClientModel


func before_test() -> void:
	_model = ClientModel.new(FixtureHallModes.mode())
	_model.own_peer = OWN
	_model.phase = &"round"


func test_a_dead_player_waits_in_the_hall_where_the_phase_lets_the_dead_move() -> void:
	assert_bool(_model.waits_in_hall()).is_false()
	_model.lives[OWN] = ClientModel.Life.DEAD
	assert_bool(_model.waits_in_hall()).is_true()
	assert_int(_model.body_life_of(OWN)).is_equal(ClientModel.Life.ALIVE)
	_model.phase = &"lobby"
	assert_bool(_model.waits_in_hall()).is_false()
	assert_int(_model.body_life_of(OWN)).is_equal(ClientModel.Life.DEAD)


func test_the_print_takes_the_body_and_respawned_ends_it() -> void:
	_model.lives[OWN] = ClientModel.Life.DEAD
	_model.bodies[OWN] = Vector3(3, 0, 3)
	var fields := {"peer": OWN, "position": Vector3(1, 0, 1), "print_ms": 2000}
	_model.fold(&"PrintStarted", fields)
	assert_int(_model.life_of(OWN)).is_equal(ClientModel.Life.PRINTING)
	assert_bool(_model.bodies.has(OWN)).is_false()
	assert_bool(_model.waits_in_hall()).is_false()
	_model.fold(&"Respawned", {"peer": OWN, "position": Vector3(1, 0, 1)})
	assert_int(_model.life_of(OWN)).is_equal(ClientModel.Life.ALIVE)
