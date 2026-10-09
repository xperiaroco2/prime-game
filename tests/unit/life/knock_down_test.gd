extends GdUnitTestSuite
## KnockDown (ARCHITECTURE §9.4.3; #599, the tutorial's stages): a row's action that downs the
## host's player (pick 0) or the n-th other present player in peer-id order, and with then_die
## kills it at once. Driven by the host's NextStage through a seeded Match on FixtureStageModes
## (no `content/`, §9.6), asserted on the events, who received them, and the row error count.

const P1 := 1
const P2 := 2
const P3 := 3
const P4 := 4
## Far apart, so nobody's floor or reach meets another's.
const SPOTS: Array[Vector3] = [
	Vector3(0, 0, 0), Vector3(0, 0, 20), Vector3(20, 0, 0), Vector3(20, 0, 20)
]


func test_pick_one_downs_the_first_other_player_and_only_it_is_corrected() -> void:
	var game := _round(FixtureStageModes.staged([FixtureStageModes.knock_down(1)]), [P1, P2, P3])
	var from_index := game.emitted().size()
	var epoch := game.state.player(P2).epoch
	FixtureStageModes.next_stage(game, P1, 4)
	assert_str(game.phase_id()).is_equal(str(FixtureStageModes.STAGE))
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DOWNED)
	assert_int(game.state.player(P2).epoch).is_equal(epoch + 1)
	for peer: int in [P1, P3]:
		assert_int(game.state.player(peer).life).is_equal(PlayerState.Life.ALIVE)
	var knocked := _emitted(game, from_index, &"KnockedDown")
	assert_int(knocked.size()).is_equal(1)
	assert_int((knocked[0].event as KnockedDownEvent).peer).is_equal(P2)
	assert_array(Array(knocked[0].recipients)).contains_exactly_in_any_order([P1, P2, P3])
	# The Correction is the downed player's alone (its new epoch): no other peer receives it.
	var corrections := _emitted(game, from_index, &"Correction")
	assert_int(corrections.size()).is_equal(1)
	assert_array(Array(corrections[0].recipients)).is_equal([P2])
	assert_int((corrections[0].event as CorrectionEvent).epoch).is_equal(epoch + 1)
	assert_array(_emitted(game, from_index, &"Died")).is_empty()
	assert_int(game.row_error_count()).is_equal(0)


func test_pick_names_the_host_or_the_nth_other_present_player() -> void:
	var cases: Array[Array] = [[0, P1], [1, P2], [2, P3], [3, P4]]
	for case: Array in cases:
		var pick: int = case[0]
		var mode := FixtureStageModes.staged([FixtureStageModes.knock_down(pick)])
		var game := _round(mode, [P4, P3, P2, P1])
		FixtureStageModes.next_stage(game, P1, 4)
		for peer: int in [P1, P2, P3, P4]:
			var want := PlayerState.Life.DOWNED if peer == case[1] else PlayerState.Life.ALIVE
			assert_int(game.state.player(peer).life).override_failure_message(str(case)).is_equal(
				want
			)
	# Present players only: with P2 gone, the first other is P3.
	var left := _round(FixtureStageModes.staged([FixtureStageModes.knock_down(1)]), [P1, P2, P3])
	FixtureModes.send(left, Intents.PEER_LEFT, P2)
	FixtureStageModes.next_stage(left, P1, 4)
	assert_int(left.state.player(P3).life).is_equal(PlayerState.Life.DOWNED)
	assert_int(left.row_error_count()).is_equal(0)


func test_then_die_kills_at_once_and_drops_the_carried_item() -> void:
	var mode := FixtureStageModes.staged([FixtureStageModes.knock_down(0, true)])
	mode.reactions = [
		FixtureModes.rule(Facts.PLAYER_DIED, [], [FixtureNote.of("died")]),
		FixtureModes.rule(Facts.ITEM_RESTED, [], [FixtureNote.of("rested")]),
	]
	var game := _round(mode, [P1, P2, P3])
	var knife := FixtureCombatModes.arm(game, P1, SPOTS[0])
	var notes := FixtureModes.notes(game).size()
	var from_index := game.emitted().size()
	FixtureStageModes.next_stage(game, P1, 4)
	var host := game.state.player(P1)
	assert_int(host.life).is_equal(PlayerState.Life.DEAD)
	assert_bool(game.state.bodies.has(P1)).is_true()
	assert_int(knife.where).is_equal(ItemState.Where.GROUND)
	assert_int(knife.holder).is_equal(0)
	assert_array(_names(game, from_index)).contains_exactly(
		[&"KnockedDown", &"Correction", &"Died", &"ItemPlaced"]
	)
	for wanted: StringName in [&"KnockedDown", &"Died", &"ItemPlaced"]:
		var emitted := _emitted(game, from_index, wanted)
		assert_array(Array(emitted[0].recipients)).contains_exactly_in_any_order([P1, P2, P3])
	var placed := _emitted(game, from_index, &"ItemPlaced")[0].event as ItemPlacedEvent
	assert_int(placed.item).is_equal(knife.id)
	assert_str(str(placed.cause)).is_equal(str(Items.DEATH))
	# The facts in order: player_died, then item_rested (the fixture task type notes each too).
	var facts := FixtureModes.notes(game).slice(notes).filter(
		func(n: String) -> bool: return n in ["died", "rested"]
	)
	assert_array(facts).is_equal(["died", "rested"])
	assert_int(game.row_error_count()).is_equal(0)


func test_a_pick_that_names_nobody_present_is_one_row_error() -> void:
	var game := _round(FixtureStageModes.staged([FixtureStageModes.knock_down(3)]), [P1, P2, P3])
	var from_index := game.emitted().size()
	FixtureStageModes.next_stage(game, P1, 4)
	assert_int(game.row_error_count()).is_equal(1)
	assert_str(game.diagnostics[-1]).contains("KnockDown: pick 3 names no present player")
	assert_array(_emitted(game, from_index, &"KnockedDown")).is_empty()
	for peer: int in [P1, P2, P3]:
		assert_int(game.state.player(peer).life).is_equal(PlayerState.Life.ALIVE)


func test_then_die_on_a_pick_that_is_not_alive_is_one_error_and_kills_nobody() -> void:
	for life: PlayerState.Life in [PlayerState.Life.DOWNED, PlayerState.Life.DEAD]:
		var mode := FixtureStageModes.staged([FixtureStageModes.knock_down(1, true)])
		var game := _round(mode, [P1, P2, P3])
		game.state.player(P2).life = life
		var from_index := game.emitted().size()
		FixtureStageModes.next_stage(game, P1, 4)
		assert_int(game.row_error_count()).is_equal(1)
		assert_str(game.diagnostics[-1]).contains("knock_down: player 2 is not alive")
		assert_int(game.state.player(P2).life).is_equal(life)
		assert_array(_emitted(game, from_index, &"Died")).is_empty()
		assert_array(_emitted(game, from_index, &"KnockedDown")).is_empty()


func test_the_downed_stay_downed_without_life_ticks_and_die_on_time_with_them() -> void:
	# `stage` lists no LifeTicks (the tutorial's raise_stage): the knockdown never runs out.
	var mode := FixtureStageModes.staged([FixtureStageModes.knock_down(1)])
	var game := _round(mode, [P1, P2, P3])
	FixtureStageModes.next_stage(game, P1, 4)
	FixtureModes.run_ticks(game, 600)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DOWNED)
	# Entering `last`, which lists LifeTicks: a knockdown there runs out after knockdown_s.
	var timed := _round(FixtureStageModes.staged([], [FixtureStageModes.knock_down(1)]), [P1, P2])
	FixtureStageModes.next_stage(timed, P1, 4)
	FixtureStageModes.next_stage(timed, P1, 5)
	assert_str(timed.phase_id()).is_equal(str(FixtureStageModes.LAST))
	var knockdown_ticks := Ticks.from_seconds(FixtureModes.player_rules().knockdown_s)
	FixtureModes.run_ticks(timed, knockdown_ticks - 1)
	assert_int(timed.state.player(P2).life).is_equal(PlayerState.Life.DOWNED)
	FixtureModes.run_ticks(timed, 2)
	assert_int(timed.state.player(P2).life).is_equal(PlayerState.Life.DEAD)


func test_it_lists_what_it_can_emit() -> void:
	var downs := FixtureStageModes.knock_down(1)
	assert_array(downs.emits()).contains_exactly(
		[RaiseStoppedEvent, KnockedDownEvent, CorrectionEvent]
	)
	var kills := FixtureStageModes.knock_down(0, true)
	assert_array(kills.emits()).contains_exactly(
		[RaiseStoppedEvent, KnockedDownEvent, CorrectionEvent, DiedEvent, ItemPlacedEvent]
	)


## A round of `mode` whose `peers` joined and were placed, then stood far apart (SPOTS by peer).
func _round(mode: GameMode, peers: Array[int]) -> Match:
	var game := FixtureCombatModes.in_round(mode, peers)
	for peer: int in peers:
		FixtureItemModes.stand(game, peer, SPOTS[peer - 1])
	return game


## The emitted events named `wanted` from index `from` on.
func _emitted(game: Match, from: int, wanted: StringName) -> Array[EmittedEvent]:
	var found: Array[EmittedEvent] = []
	for emitted: EmittedEvent in game.emitted().slice(from):
		if emitted.event.event_name() == wanted:
			found.append(emitted)
	return found


## The life and item events emitted from index `from` on, by name, in order.
func _names(game: Match, from: int) -> Array[StringName]:
	var found: Array[StringName] = []
	for emitted: EmittedEvent in game.emitted().slice(from):
		var named := emitted.event.event_name()
		if named in [&"KnockedDown", &"Correction", &"Died", &"ItemPlaced"]:
			found.append(named)
	return found
