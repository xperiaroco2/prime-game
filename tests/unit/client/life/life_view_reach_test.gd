extends GdUnitTestSuite
## LifeView's raise reach (client/life/life_view.gd; ARCHITECTURE §4.7, Interactions): the host's
## is the client's own mode's TargetInReach of Raise, and the raise hint's a walking margin short
## of it, the pick-up hint's (TargetChoice.hint_reach, #352). Walking in over the network:
## tests/integration/client/life/life_raise_network_test.gd.

const MODE := "res://content/modes/base_mode.tres"


func test_the_raise_reach_is_the_modes_target_in_reach_of_raise() -> void:
	assert_float(LifeView.raise_reach_of(load(MODE) as GameMode)).is_equal(2.0)
	# A mode with no raise offers none.
	assert_float(LifeView.raise_reach_of(FixtureBaseMode.mode())).is_equal(0.0)


func test_the_raise_hint_stops_short_of_the_reach_by_the_walking_margin() -> void:
	# The base mode: 2 m less 4.5 m/s for 4/60 s, as the pick-up hint.
	var base := load(MODE) as GameMode
	assert_float(LifeView.raise_hint_reach_of(base)).is_equal_approx(1.7, 1e-5)
	assert_float(LifeView.raise_hint_reach_of(base)).is_equal_approx(
		TargetChoice.hint_reach_of(base), 1e-5
	)
	# A mode with no raise offers none.
	assert_float(LifeView.raise_hint_reach_of(FixtureBaseMode.mode())).is_equal(0.0)
	# Its own reach and walk: 3 m less 6 m/s for 4/60 s.
	var own := FixtureCombatModes.basic()
	own.player_rules.walk_speed_mps = 6.0
	own.actions = [FixtureCombatModes.raise_rule(FixtureCombatModes.RAISE_S, 3.0)]
	assert_float(LifeView.raise_hint_reach_of(own)).is_equal_approx(2.6, 1e-5)
