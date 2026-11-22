extends GdUnitTestSuite
## The base mode's return in M8 (#1683, the engineer's word of 2026-11-23: no drone, the player just
## appears): the round's Respawn prints nobody (print_s 0: Respawned at once, no PrintStarted;
## the print itself is tests/unit/life/print_test.gd on a fixture, the drone #1684), the dead still
## wait in the hall and the invulnerability after the return stays.

const BASE_MODE := "res://content/modes/base_mode.tres"


func test_the_round_returns_the_dead_at_once_from_the_hall_still_invulnerable() -> void:
	var mode := load(BASE_MODE) as GameMode
	var life := mode.find_phase(&"round").tick_systems[0] as LifeTicks
	assert_object(life).is_not_null()
	var respawn := life.respawn
	assert_float(respawn.print_s).is_equal(0.0)
	assert_str(String(respawn.tag)).is_equal("respawn")
	assert_str(String(respawn.hall_tag)).is_equal("dead")
	assert_float(mode.player_rules.invulnerable_s).is_greater(0.0)
	# PrintStarted needs a print: with none, no phase of the base mode prints anyone.
	for phase: PhaseSpec in mode.phases:
		for system: TickSystem in phase.tick_systems:
			var ticks := system as LifeTicks
			if ticks != null and ticks.respawn != null:
				assert_float(ticks.respawn.print_s).override_failure_message(String(phase.id)).is_zero()
