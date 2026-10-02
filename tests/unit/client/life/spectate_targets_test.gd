extends GdUnitTestSuite
## SpectateTargets (ARCHITECTURE §4.7 Spectating, V9, answer 6): the first target is a random
## living player other than the own one from the client's own seeded generator, else a random
## downed one, else none; next and previous cycle the living and the downed in peer-id order; a
## target that goes down, dies or leaves is lost.

const OWN := 3
const SEED := 4242

var _model: ClientModel


func before_test() -> void:
	_model = ClientModel.new(FixtureBaseMode.mode())
	_model.own_peer = OWN
	for peer: int in [1, 2, OWN, 5, 7]:
		var member := ClientModel.Member.new()
		member.name = "Player%d" % peer
		_model.roster[peer] = member
	_model.lives[OWN] = ClientModel.Life.DEAD


func test_the_first_target_is_a_living_player_drawn_from_the_seed() -> void:
	_model.lives[2] = ClientModel.Life.DOWNED
	_model.lives[7] = ClientModel.Life.DEAD
	var drawn: Array[int] = []
	var targets := SpectateTargets.new(_seeded())
	for i: int in 40:
		drawn.append(targets.first(_model, OWN))
	# Only the living, 1 and 5, both come up; the same seed draws the same sequence.
	for peer: int in drawn:
		assert_array([1, 5]).contains([peer])
	assert_array(drawn).contains([1, 5])
	var again := SpectateTargets.new(_seeded())
	for i: int in drawn.size():
		assert_int(again.first(_model, OWN)).is_equal(drawn[i])


func test_with_nobody_living_a_downed_player_and_else_none() -> void:
	for peer: int in [1, 5, 7]:
		_model.lives[peer] = ClientModel.Life.DEAD
	_model.lives[2] = ClientModel.Life.DOWNED
	var targets := SpectateTargets.new(_seeded())
	assert_int(targets.first(_model, OWN)).is_equal(2)
	_model.lives[2] = ClientModel.Life.LEFT
	assert_int(targets.first(_model, OWN)).is_equal(0)


func test_cycling_goes_through_the_living_and_the_downed_in_peer_order() -> void:
	_model.lives[5] = ClientModel.Life.DOWNED
	_model.lives[7] = ClientModel.Life.DEAD
	assert_array(SpectateTargets.candidates(_model, OWN)).contains_exactly([1, 2, 5])
	assert_int(SpectateTargets.cycle(_model, OWN, 1, 1)).is_equal(2)
	assert_int(SpectateTargets.cycle(_model, OWN, 2, 1)).is_equal(5)
	assert_int(SpectateTargets.cycle(_model, OWN, 5, 1)).is_equal(1)
	assert_int(SpectateTargets.cycle(_model, OWN, 1, -1)).is_equal(5)
	# From none, or from a target no longer watchable, it starts at an end.
	assert_int(SpectateTargets.cycle(_model, OWN, 0, 1)).is_equal(1)
	assert_int(SpectateTargets.cycle(_model, OWN, 7, -1)).is_equal(5)
	for peer: int in [1, 2, 5]:
		_model.lives[peer] = ClientModel.Life.DEAD
	assert_int(SpectateTargets.cycle(_model, OWN, 1, 1)).is_equal(0)


func test_a_target_that_goes_down_dies_or_leaves_is_lost() -> void:
	var alive := ClientModel.Life.ALIVE
	var downed := ClientModel.Life.DOWNED
	assert_bool(SpectateTargets.lost(alive, alive)).is_false()
	assert_bool(SpectateTargets.lost(alive, downed)).is_true()
	assert_bool(SpectateTargets.lost(alive, ClientModel.Life.DEAD)).is_true()
	assert_bool(SpectateTargets.lost(alive, ClientModel.Life.LEFT)).is_true()
	# A downed target chosen by cycling stays while downed and when revived.
	assert_bool(SpectateTargets.lost(downed, downed)).is_false()
	assert_bool(SpectateTargets.lost(downed, alive)).is_false()
	assert_bool(SpectateTargets.lost(downed, ClientModel.Life.DEAD)).is_true()


func _seeded() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	return rng
