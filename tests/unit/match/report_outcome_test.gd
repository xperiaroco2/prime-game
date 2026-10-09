extends GdUnitTestSuite
## ReportOutcome (ARCHITECTURE §9.4.2; #599): the host's NextStage reports `next` through it, and
## the phase's one `next` row moves the match on; the outcome itself reaches no peer; any other
## sender, or a phase that lists no NextStage, gets `not_accepted`; run as a row's action it is a
## row error; the mode check wants an outcome and a row for it. Driven through a seeded Match on
## FixtureStageModes (no `content/`, §9.6).

const P1 := 1
const P2 := 2
const P3 := 3


func test_the_hosts_next_stage_reports_next_and_its_row_runs() -> void:
	var note := FixtureNote.of("stage")
	note.with_argument = true
	var mode := FixtureStageModes.staged([note])
	var game := FixtureCombatModes.in_round(mode, [P1, P2, P3])
	assert_str(game.phase_id()).is_equal("round")
	var from_index := game.emitted().size()
	FixtureStageModes.next_stage(game, P1, 4)
	assert_str(game.phase_id()).is_equal(str(FixtureStageModes.STAGE))
	# The row ran with the outcome's argument (none: null), and nobody was refused.
	assert_array(FixtureModes.notes(game)).contains_exactly(["stage <null>"])
	for peer: int in [P1, P2, P3]:
		assert_array(FixtureModes.rejections(game, peer)).is_empty()
		var changed := game.view_of(peer).events_named(&"PhaseChanged")
		assert_str(str((changed[-1] as PhaseChangedEvent).phase)).is_equal("stage")
	# ReportOutcome adds no event of its own: the step's events are the row's and the entry's.
	var step: Array[StringName] = []
	for emitted: EmittedEvent in game.emitted().slice(from_index):
		step.append(emitted.event.event_name())
	assert_array(step).contains([&"FixtureNote", &"PhaseChanged"])
	assert_array(step).not_contains([&"Rejected"])
	assert_array(ReportOutcome.new().emits()).is_empty()
	assert_int(game.row_error_count()).is_equal(0)


func test_the_argument_reaches_the_row() -> void:
	var note := FixtureNote.of("stage")
	note.with_argument = true
	var mode := FixtureStageModes.staged([note])
	mode.actions[-1] = FixtureStageModes.next_stage_rule(&"lesson_six")
	var game := FixtureCombatModes.in_round(mode, [P1, P2])
	FixtureStageModes.next_stage(game, P1, 4)
	assert_array(FixtureModes.notes(game)).contains_exactly(["stage lesson_six"])


func test_only_the_host_and_only_where_a_phase_lists_it() -> void:
	var mode := FixtureStageModes.staged()
	var game := FixtureModes.started(mode, [P1, P2])
	# The lobby lists no NextStage: the host's is refused too.
	FixtureStageModes.next_stage(game, P1, 2)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_accepted"])
	game = FixtureCombatModes.in_round(mode, [P1, P2])
	FixtureStageModes.next_stage(game, P2, 3)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"not_accepted"])
	assert_str(game.phase_id()).is_equal("round")
	# Two steps, two rows: round -> stage -> last; `last` lists no NextStage.
	FixtureStageModes.next_stage(game, P1, 4)
	FixtureStageModes.next_stage(game, P1, 5)
	assert_str(game.phase_id()).is_equal(str(FixtureStageModes.LAST))
	FixtureStageModes.next_stage(game, P1, 6)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_accepted"])
	assert_str(game.phase_id()).is_equal(str(FixtureStageModes.LAST))


func test_run_as_a_rows_action_it_is_a_row_error() -> void:
	# Reported while the row moves the match on, an outcome would be taken as the next phase's.
	var mode := FixtureStageModes.staged([FixtureStageModes.report(&"next")])
	var game := FixtureCombatModes.in_round(mode, [P1, P2])
	FixtureStageModes.next_stage(game, P1, 4)
	assert_int(game.row_error_count()).is_equal(1)
	assert_str(game.phase_id()).is_equal(str(FixtureStageModes.STAGE))
	assert_str(str(game.diagnostics[-1])).contains("reported during the row actions")


func test_the_mode_check_wants_an_outcome_and_its_row() -> void:
	var fine := ModeCheck.run(FixtureStageModes.staged())
	assert_array(Array(fine.errors)).is_empty()
	assert_array(Array(FixtureStageModes.report(&"").check(GameMode.new()))).contains_exactly(
		["ReportOutcome names no outcome"]
	)
	var no_row := FixtureStageModes.staged()
	no_row.transitions.pop_back()
	var check := ModeCheck.run(no_row)
	assert_array(Array(check.errors)).contains(
		["phase stage can report next, which has no transition row"]
	)
	var empty := FixtureStageModes.staged()
	empty.actions[-1] = FixtureModes.rule(Intents.NEXT_STAGE, [], [FixtureStageModes.report(&"")])
	var errors := "\n".join(ModeCheck.run(empty).errors)
	assert_str(errors).contains("ReportOutcome names no outcome")
