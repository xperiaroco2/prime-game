extends GdUnitTestSuite
## The base mode's return in M8 (#1683, the engineer's word of 2026-11-23: no drone, the player just
## appears): no phase's Respawn prints anybody (print_s 0: Respawned at once, no PrintStarted; the
## print itself is tests/unit/life/print_test.gd on a fixture, the return from the hall without it
## dead_hall_test.gd, the drone #1684), the round's dead still wait in the hall, and the
## invulnerability after the return stays.

const BASE_MODE := "res://content/modes/base_mode.tres"


func test_the_round_returns_the_dead_at_once_from_the_hall_still_invulnerable() -> void:
	var mode := load(BASE_MODE) as GameMode
	var returning: Array[StringName] = []
	for phase: PhaseSpec in mode.phases:
		for system: TickSystem in phase.tick_systems:
			var ticks := system as LifeTicks
			if ticks == null or ticks.respawn == null:
				continue
			returning.append(phase.id)
			var respawn := ticks.respawn
			assert_float(respawn.print_s).override_failure_message(String(phase.id)).is_zero()
			if phase.id == &"round":
				assert_str(String(respawn.tag)).is_equal("respawn")
				assert_str(String(respawn.hall_tag)).is_equal("dead")
	assert_array(returning).contains([&"round"])
	assert_float(mode.player_rules.invulnerable_s).is_greater(0.0)
