extends GdUnitTestSuite
## ModeCheck's rule for a task type that can kill (TaskType.kills(); the car repair ADR's RE6,
## #806; ARCHITECTURE §9.4.5): every phase that accepts Interact lists LifeTicks with a Respawn,
## so a dead player always comes back. Found on FixtureStationModes.holding() (Round accepts
## Interact and lists LifeTicks with a Respawn) with one thing taken away.

const MISSING := (
	"phase round accepts Interact, and task type fixture_station can kill (TaskType.kills()),"
	+ " but lists no LifeTicks with a Respawn"
)


func test_a_killing_type_passes_where_the_dead_respawn() -> void:
	var mode := _killing(true)
	var check := ModeCheck.run(mode)
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).is_empty()


func test_a_killing_type_needs_a_respawn_in_life_ticks() -> void:
	var mode := _killing(true)
	FixtureCombatModes.life_ticks(mode).respawn = null
	assert_str(";".join(ModeCheck.run(mode).errors)).contains(MISSING)


func test_a_killing_type_needs_life_ticks() -> void:
	var mode := _killing(true)
	var round_spec := mode.find_phase(&"round")
	var kept: Array[TickSystem] = []
	for system: TickSystem in round_spec.tick_systems:
		if not system is LifeTicks:
			kept.append(system)
	round_spec.tick_systems = kept
	assert_str(";".join(ModeCheck.run(mode).errors)).contains(MISSING)


func test_a_type_that_cannot_kill_needs_no_respawn() -> void:
	assert_bool(TaskType.new().kills()).is_false()
	var mode := _killing(false)
	FixtureCombatModes.life_ticks(mode).respawn = null
	assert_str(";".join(ModeCheck.run(mode).errors)).not_contains("can kill")


func test_a_phase_that_takes_no_interact_needs_no_respawn() -> void:
	# The lobby takes no Interact and lists no LifeTicks: the rule leaves it alone.
	var check := ModeCheck.run(_killing(true))
	assert_str(";".join(check.errors)).not_contains("phase lobby")


## FixtureStationModes.holding() with a timed hold, its task type's kills() answering `can_kill`.
func _killing(can_kill: bool) -> GameMode:
	var mode := FixtureStationModes.holding(FixtureStationModes.hold(1.0))
	FixtureStationModes.type_of(mode).killing = can_kill
	return mode
