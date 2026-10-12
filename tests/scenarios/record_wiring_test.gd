extends GdUnitTestSuite
## The record invariant's wiring in ScenarioInvariants (the photo ADR §8, #781): check_event reads
## the camera's lens from the station and the mode's PhotoTask, the life states and the accepted
## positions from the match, and accepts a real shot's record, while a record altered after the
## fact (a dead player, a player named twice, a row far from the lens, a station that is no camera)
## is caught. P9 (#788) plants the record builder's bug over House's shots.

const P1 := 1
const P2 := 2
const P3 := 3
const PEERS: Array[int] = [P1, P2, P3]

var _game: Match
var _event: ShotTakenEvent


## A round where P1 loads and shoots with P2 in the frame; the shot's event as P3 got it.
func _shot() -> void:
	_game = FixturePhotoModes.in_round(FixturePhotoModes.basic(), PEERS)
	FixturePhotoModes.take(_game, P1, FixturePhotoModes.dealt_film(_game))
	FixturePhotoModes.use(_game, P1, FixturePhotoModes.camera_of(_game))
	FixtureItemModes.stand(_game, P2, FixturePhotoModes.IN_FRAME)
	FixtureItemModes.stand(_game, P3, Vector3(30, 0, 0))
	FixturePhotoModes.use(_game, P1, FixturePhotoModes.camera_of(_game))
	var taken := _game.view_of(P3).events_named(&"ShotTaken")
	assert_int(taken.size()).is_equal(1)
	_event = taken[0] as ShotTakenEvent


func _problems(event: ShotTakenEvent) -> String:
	var invariants := ScenarioInvariants.new(_game, BotScenario.new())
	var emitted := EmittedEvent.new(_game.ticked_through(), event, PackedInt32Array(PEERS), false)
	return "\n".join(invariants.check_event(emitted))


func test_a_real_shots_record_passes() -> void:
	_shot()
	assert_str(_problems(_event)).is_empty()


func test_a_row_for_a_player_who_is_dead_now_is_caught() -> void:
	_shot()
	_game.state.player(P2).life = PlayerState.Life.DEAD
	assert_str(_problems(_event)).contains("not alive or downed")


func test_a_peer_named_twice_is_caught() -> void:
	_shot()
	var twin := ShotTakenEvent.new(
		_event.station, _event.film, _event.shot, [_event.record[0], _event.record[0]]
	)
	assert_str(_problems(twin)).contains("twice")


func test_a_row_far_from_every_accepted_position_is_caught() -> void:
	_shot()
	var moved: Dictionary = _event.record[0].duplicate()
	moved["position"] = (moved["position"] as Vector3) + Vector3(0, 0, _step() + 1.0)
	var forged := ShotTakenEvent.new(_event.station, _event.film, _event.shot, [moved])
	assert_str(_problems(forged)).contains("a step away")


func test_a_row_beyond_the_range_from_the_cameras_lens_is_caught() -> void:
	_shot()
	var reach := FixturePhotoModes.RANGE_M + PhotoTask.RECORD_MARGIN_M + _step()
	var far := FixturePhotoModes.CAMERA_AT + Vector3(0, 0, reach + 1.0)
	_game.state.player(P2).position = far
	var moved: Dictionary = _event.record[0].duplicate()
	moved["position"] = far
	var forged := ShotTakenEvent.new(_event.station, _event.film, _event.shot, [moved])
	assert_str(_problems(forged)).contains("from the lens")


func test_a_shot_naming_a_station_that_is_no_camera_is_caught() -> void:
	_shot()
	var other := FixturePhotoModes.state_of(_game).printer
	var forged := ShotTakenEvent.new(other, _event.film, _event.shot, _event.record)
	assert_str(_problems(forged)).contains("no camera")


## The record invariant's step for the fixture mode's rules.
func _step() -> float:
	return ScenarioInvariants.record_step(_game.mode.player_rules)
