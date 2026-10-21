extends GdUnitTestSuite
## The lift crash (#811, #1192) sounds in the play phase of the client's own copy of the mode,
## asked of the PhaseSpec (`clock_runs`), not by the literal id `round`: a mode whose play phase has
## another id still crashes, and a phase called `round` that is no play phase does not.

const F := preload("res://tests/fixtures/client/fixture_car_repair_client.gd")
const RANGE := SoundChooser.HEARING_RANGE_M
const CAR_AT := FixtureCarRepairModes.CAR_AT


func test_a_play_phase_of_another_id_crashes() -> void:
	var mode := FixtureCarRepairModes.basic()
	mode.find_phase(&"round").id = &"play"
	var model := F.dealt(mode)
	F.fold(model, PhaseChangedEvent.new(&"play", 2000))
	assert_bool(SoundChooser.in_play(model)).is_true()
	var sound := _lift_down(model, mode)
	assert_object(sound).is_not_null()
	assert_str(String(sound.id)).is_equal(String(SoundChooser.LIFT_CRASH))


func test_a_phase_called_round_that_is_no_play_phase_makes_no_crash() -> void:
	var mode := FixtureCarRepairModes.basic()
	mode.find_phase(&"round").clock_runs = false
	var model := F.dealt(mode)
	assert_str(String(model.phase)).is_equal("round")
	assert_bool(SoundChooser.in_play(model)).is_false()
	assert_object(_lift_down(model, mode)).is_null()


func test_the_base_round_and_the_phases_after_it() -> void:
	var mode := FixtureCarRepairModes.basic()
	var model := F.dealt(mode)
	assert_bool(SoundChooser.in_play(model)).is_true()
	F.fold(model, PhaseChangedEvent.new(&"end", 2000))
	assert_bool(SoundChooser.in_play(model)).is_false()
	assert_bool(SoundChooser.in_play(null)).is_false()


func _lift_down(model: ClientModel, mode: GameMode) -> SoundChooser.Sound:
	var fields := {"station": F.PANEL, "up": false, "tick": 20}
	model.fold(&"LiftChanged", fields)
	return SoundChooser.choose(
		&"LiftChanged",
		fields,
		model,
		func(_peer: int) -> Variant: return null,
		CAR_AT,
		RANGE,
		0.0,
		mode
	)
