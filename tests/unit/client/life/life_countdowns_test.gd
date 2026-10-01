extends GdUnitTestSuite
## LifeCountdowns (ARCHITECTURE §4.7 Countdowns, V13): the own knockdown, paused while raised, the
## respawn, the invulnerability and a raise's progress, from public events at the estimated host
## tick of each one's arrival and the mode's numbers (FixtureModes.player_rules(), knockdown 10 s,
## respawn 30 s, invulnerable 3 s; a raise of 3 s).

const OWN := 2
const OTHER := 5

var _countdowns: LifeCountdowns


func before_test() -> void:
	_countdowns = LifeCountdowns.new(FixtureModes.player_rules(), 3.0)


func test_nothing_runs_at_first() -> void:
	for left: float in [
		_countdowns.knockdown_left_s(0.0),
		_countdowns.respawn_left_s(0.0),
		_countdowns.invulnerable_left_s(0.0),
		_countdowns.raise_progress(0.0),
	]:
		assert_float(left).is_equal(LifeCountdowns.NONE)


func test_the_knockdown_counts_down_from_its_arrival_and_pauses_while_raised() -> void:
	_on(&"KnockedDown", {"peer": OWN, "position": Vector3.ZERO}, 100.0)
	assert_float(_countdowns.knockdown_left_s(100.0)).is_equal_approx(10.0, 1e-4)
	assert_float(_countdowns.knockdown_left_s(140.0)).is_equal_approx(8.0, 1e-4)
	_on(&"RaiseStarted", {"raiser": OTHER, "target": OWN}, 140.0)
	assert_bool(_countdowns.knockdown_paused()).is_true()
	assert_float(_countdowns.knockdown_left_s(170.0)).is_equal_approx(8.0, 1e-4)
	assert_float(_countdowns.raise_progress(170.0)).is_equal_approx(0.5, 1e-4)
	_on(&"RaiseStopped", {"raiser": OTHER, "target": OWN}, 180.0)
	assert_bool(_countdowns.knockdown_paused()).is_false()
	assert_float(_countdowns.raise_progress(180.0)).is_equal(LifeCountdowns.NONE)
	assert_float(_countdowns.knockdown_left_s(200.0)).is_equal_approx(7.0, 1e-4)
	assert_float(_countdowns.knockdown_left_s(1000.0)).is_equal(0.0)


func test_a_revive_ends_the_knockdown_and_makes_the_own_player_invulnerable() -> void:
	_on(&"KnockedDown", {"peer": OWN, "position": Vector3.ZERO}, 0.0)
	_on(&"RaiseStarted", {"raiser": OTHER, "target": OWN}, 20.0)
	_on(&"Revived", {"peer": OWN}, 80.0)
	assert_float(_countdowns.knockdown_left_s(80.0)).is_equal(LifeCountdowns.NONE)
	assert_float(_countdowns.raise_progress(80.0)).is_equal(LifeCountdowns.NONE)
	assert_float(_countdowns.invulnerable_left_s(80.0)).is_equal_approx(3.0, 1e-4)
	assert_float(_countdowns.invulnerable_left_s(120.0)).is_equal_approx(1.0, 1e-4)
	assert_float(_countdowns.invulnerable_left_s(200.0)).is_equal(0.0)


func test_a_death_starts_the_respawn_and_the_respawn_the_invulnerability() -> void:
	_on(&"KnockedDown", {"peer": OWN, "position": Vector3.ZERO}, 0.0)
	_on(&"Died", {"peer": OWN, "position": Vector3.ZERO}, 200.0)
	assert_float(_countdowns.knockdown_left_s(200.0)).is_equal(LifeCountdowns.NONE)
	assert_float(_countdowns.respawn_left_s(200.0)).is_equal_approx(30.0, 1e-4)
	assert_float(_countdowns.respawn_left_s(500.0)).is_equal_approx(15.0, 1e-4)
	_on(&"Respawned", {"peer": OWN, "position": Vector3.ZERO}, 800.0)
	assert_float(_countdowns.respawn_left_s(800.0)).is_equal(LifeCountdowns.NONE)
	assert_float(_countdowns.invulnerable_left_s(800.0)).is_equal_approx(3.0, 1e-4)


func test_the_raiser_sees_its_raise_progress_until_it_ends() -> void:
	_on(&"RaiseStarted", {"raiser": OWN, "target": OTHER}, 10.0)
	assert_int(_countdowns.raising()).is_equal(OTHER)
	assert_float(_countdowns.raise_progress(40.0)).is_equal_approx(0.5, 1e-4)
	_on(&"Revived", {"peer": OTHER}, 70.0)
	assert_int(_countdowns.raising()).is_equal(0)
	assert_float(_countdowns.raise_progress(70.0)).is_equal(LifeCountdowns.NONE)
	_on(&"RaiseStarted", {"raiser": OWN, "target": OTHER}, 100.0)
	_on(&"RaiseStopped", {"raiser": OWN, "target": OTHER}, 110.0)
	assert_float(_countdowns.raise_progress(110.0)).is_equal(LifeCountdowns.NONE)
	_on(&"RaiseStarted", {"raiser": OWN, "target": OTHER}, 120.0)
	_on(&"PlayerLeft", {"peer": OTHER}, 130.0)
	assert_float(_countdowns.raise_progress(130.0)).is_equal(LifeCountdowns.NONE)


func test_other_players_events_start_nothing_and_a_new_match_clears() -> void:
	_on(&"KnockedDown", {"peer": OTHER, "position": Vector3.ZERO}, 0.0)
	_on(&"Died", {"peer": OTHER, "position": Vector3.ZERO}, 0.0)
	_on(&"RaiseStarted", {"raiser": 7, "target": OTHER}, 0.0)
	assert_float(_countdowns.knockdown_left_s(0.0)).is_equal(LifeCountdowns.NONE)
	assert_float(_countdowns.respawn_left_s(0.0)).is_equal(LifeCountdowns.NONE)
	assert_float(_countdowns.raise_progress(0.0)).is_equal(LifeCountdowns.NONE)
	_on(&"Died", {"peer": OWN, "position": Vector3.ZERO}, 0.0)
	_on(&"LoadMatch", {"match_id": 2}, 10.0)
	assert_float(_countdowns.respawn_left_s(10.0)).is_equal(LifeCountdowns.NONE)


func test_the_raise_time_comes_from_the_modes_raise_rule() -> void:
	assert_float(LifeCountdowns.raise_seconds_of(FixtureCombatModes.raising())).is_equal(3.0)
	assert_float(LifeCountdowns.raise_seconds_of(FixtureBaseMode.mode())).is_equal(0.0)


func _on(event_name: StringName, fields: Dictionary, tick: float) -> void:
	_countdowns.on_event(event_name, fields, OWN, tick)
