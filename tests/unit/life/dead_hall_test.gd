extends GdUnitTestSuite
## The dead's hall (#1489; ARCHITECTURE §3.4, §5, §6): a dead player waits at a random hall marker
## of a phase whose Respawn has a hall_tag, its body staying where it died; it walks and uses what
## is there, its claims and named targets outside the hall refused; it hears and talks only with
## the dead there and sees only them; the living learn neither its place nor its voice.

const P1 := 1
const P2 := 2
const P3 := 3
const P4 := 4
const NORTH := Vector3(0, 0, 1)
const KILLED_AT := Vector3(0, 0, 1)


func test_the_dead_is_placed_in_the_hall_and_its_body_stays_where_it_died() -> void:
	var game := _duel()
	_kill(game, P2)
	FixtureModes.run_ticks(game, 1)
	var dead := game.state.player(P2)
	assert_int(dead.life).is_equal(PlayerState.Life.DEAD)
	assert_bool(dead.in_hall).is_true()
	assert_bool(FixtureModes.HALLS.has(dead.position)).is_true()
	assert_vector(game.state.bodies[P2]).is_equal(KILLED_AT)
	assert_int(dead.life_deadline).is_greater(game.ticked_through())
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_correction_reaches_only_the_dead_player() -> void:
	var game := _duel()
	var seen := FixtureMoves.corrections(game, P1).size()
	_kill(game, P2)
	FixtureModes.run_ticks(game, 1)
	var dead := game.state.player(P2)
	var own := FixtureMoves.corrections(game, P2)
	assert_vector(own[own.size() - 1].position).is_equal(dead.position)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_array(FixtureCombatModes.received(game, P1, &"Died")).has_size(1)


func test_a_dead_player_walks_inside_the_hall() -> void:
	var game := _duel()
	var dead := _in_hall(game, P2)
	var near := dead.position + Vector3(0.2, 0, 0)
	FixtureMoves.claim(game, P2, near, {"moving": true})
	FixtureModes.run_ticks(game, 1)
	assert_vector(dead.position).is_equal(near)


func test_a_claim_out_of_the_hall_is_corrected() -> void:
	var game := _duel()
	var dead := _in_hall(game, P2)
	var at := dead.position
	var seen := FixtureMoves.corrections(game, P2).size()
	var epoch := dead.epoch
	FixtureMoves.claim(game, P2, FixtureHallModes.MIDDLE + Vector3(30, 0, 0), {"moving": true})
	assert_vector(dead.position).is_equal(at)
	assert_int(dead.epoch).is_equal(epoch + 1)
	assert_int(FixtureMoves.corrections(game, P2).size()).is_equal(seen + 1)


func test_a_step_across_the_edge_of_the_hall_is_corrected() -> void:
	var game := _duel()
	var dead := _in_hall(game, P2)
	var edge := FixtureHallModes.MIDDLE + Vector3(FixtureHallModes.RADIUS_M - 0.05, 0, 0)
	dead.position = edge
	var seen := FixtureMoves.corrections(game, P2).size()
	var epoch := dead.epoch
	FixtureMoves.claim(game, P2, edge + Vector3(0.1, 0, 0), {"moving": true})
	assert_vector(dead.position).is_equal(edge)
	assert_int(dead.epoch).is_equal(epoch + 1)
	assert_int(FixtureMoves.corrections(game, P2).size()).is_equal(seen + 1)


func test_a_dead_player_naming_a_station_outside_the_hall_is_refused() -> void:
	var game := _duel()
	_in_hall(game, P2)
	var out := _station(game, 900, Vector3(5, 0, 5))
	FixtureModes.send(game, Intents.INTERACT, P2, {"station": out.id}, 1)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([RejectReasons.OUT_OF_HALL])


func test_a_dead_player_naming_an_item_outside_the_hall_is_refused() -> void:
	var game := _duel()
	_in_hall(game, P2)
	var far := FixtureItemModes.lay(game, &"tool", Vector3(5, 0, 5))
	FixtureModes.send(game, Intents.INTERACT, P2, {"item": far.id}, 1)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([RejectReasons.OUT_OF_HALL])


func test_a_dead_player_cannot_pick_up_what_lies_outside_the_hall() -> void:
	var game := _duel()
	var dead := _in_hall(game, P2)
	var far := FixtureItemModes.lay(game, &"tool", Vector3(5, 0, 5))
	FixtureModes.send(game, Intents.PICK_UP, P2, {"item": far.id}, 1)
	assert_int(dead.held_item).is_equal(-1)
	assert_int(far.where).is_equal(ItemState.Where.GROUND)


func test_a_dead_player_uses_a_station_in_the_hall() -> void:
	var game := _duel()
	var dead := _in_hall(game, P2)
	var kind := _used_kind()
	var near := _station(game, 901, dead.position, kind)
	FixtureModes.send(game, Intents.INTERACT, P2, {"station": near.id}, 1)
	assert_array(FixtureModes.rejections(game, P2)).is_empty()
	assert_int((kind.actions[0].effects[0] as RanEffect).ran).is_equal(1)


func test_a_dead_players_use_reaches_no_rule_of_a_role_or_the_mode() -> void:
	var game := _duel()
	game.mode.actions.append(FixtureModes.rule(Intents.USE, [], [RanEffect.new()]))
	_in_hall(game, P2)
	FixtureModes.send(game, Intents.USE, P2, {"facing": NORTH}, 1)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([RejectReasons.NOTHING_TO_DO])


func test_a_dead_player_not_in_a_hall_sends_nothing() -> void:
	var mode := FixtureHallModes.mode()
	FixtureCombatModes.life_ticks(mode).respawn.hall_tag = &""
	var game := FixtureCombatModes.in_round(mode, [P1, P2, P3], null, 7)
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, KILLED_AT)
	_kill(game, P2)
	FixtureModes.run_ticks(game, 1)
	var dead := game.state.player(P2)
	assert_bool(dead.in_hall).is_false()
	assert_vector(dead.position).is_equal(KILLED_AT)
	var epoch := dead.epoch
	FixtureMoves.claim(game, P2, KILLED_AT + Vector3(0.1, 0, 0), {"moving": true})
	assert_int(dead.epoch).is_equal(epoch)
	FixtureModes.send(game, Intents.INTERACT, P2, {"station": 1}, 1)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([RejectReasons.NOT_ACCEPTED])


func test_the_dead_hear_only_the_dead_and_the_living_hear_no_dead() -> void:
	var game := _duel()
	_in_hall(game, P2)
	_in_hall(game, P3)
	assert_array(Array(game.speakers_for(P2))).is_equal([P3])
	assert_array(Array(game.speakers_for(P3))).is_equal([P2])
	assert_array(Array(game.speakers_for(P1))).is_equal([P4])


func test_the_dead_see_only_the_dead_and_the_living_no_dead() -> void:
	var game := _duel()
	_in_hall(game, P2)
	_in_hall(game, P3)
	FixtureModes.run_ticks(game, 1)
	var tick := game.ticked_through()
	var dead_view: Dictionary = game.view_of(P2).snapshots[tick]["avatars"]
	assert_array(dead_view.keys()).is_equal([P3])
	assert_vector(dead_view[P3]["position"]).is_equal(game.state.player(P3).position)
	var living_view: Dictionary = game.view_of(P1).snapshots[tick]["avatars"]
	assert_array(living_view.keys()).is_equal([P4])


func test_pinball_keeps_a_dead_player_on_the_seat_only_in_the_hall() -> void:
	var game := _duel()
	var dead := _in_hall(game, P2)
	assert_bool(Pinball.standing(dead)).is_true()
	dead.leave_hall()
	assert_bool(Pinball.standing(dead)).is_false()


func test_a_fall_into_the_limp_passes_a_dead_player_by() -> void:
	var game := _duel()
	var dead := _in_hall(game, P2)
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.actor = P2
	var goes := GoLimp.new()
	goes.limp_s = 6.0
	goes.run(ctx)
	assert_object(dead.limp).is_null()


func test_the_hall_is_a_demand_of_the_map() -> void:
	var respawn := Respawn.new()
	respawn.tag = FixtureModes.RESPAWN_TAG
	respawn.hall_tag = FixtureModes.HALL_TAG
	var demands := Demands.new(GameMode.new())
	var settings: Dictionary[StringName, int] = {}
	respawn.add_demands(settings, 0, demands)
	var map := LevelLayout.new("map")
	map.add_marker(FixtureModes.RESPAWN_TAG, Vector3.ZERO)
	assert_array(demands.shortfalls(map)).has_size(1)
	map.add_marker(FixtureModes.HALL_TAG, Vector3(1, 0, 0))
	assert_array(demands.shortfalls(map)).is_empty()


func test_the_mode_check_refuses_a_half_set_hall() -> void:
	var respawn := FixtureCombatModes.respawn()
	respawn.hall_tag = FixtureModes.HALL_TAG
	assert_array(Array(respawn.check(GameMode.new()))).has_size(2)
	respawn.hall_rng_purpose = &"hall"
	respawn.hall_radius_m = 20.0
	assert_array(Array(respawn.check(GameMode.new()))).is_empty()


func _duel(seed_value: int = 7) -> Match:
	var game := FixtureCombatModes.in_round(
		FixtureHallModes.mode(), [P1, P2, P3, P4], null, seed_value
	)
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, KILLED_AT)
	FixtureItemModes.stand(game, P3, Vector3(0, 0, -1))
	FixtureItemModes.stand(game, P4, Vector3(5, 0, 5))
	return game


## P1 hits `peer` twice, the cooldown apart, and its knockdown runs out: `peer` is dead.
func _kill(game: Match, peer: int) -> void:
	var at := game.state.player(peer).position
	FixtureCombatModes.use(game, P1, (at - game.state.player(P1).position).normalized())
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, (at - game.state.player(P1).position).normalized())
	FixtureModes.run_ticks(game, game.state.player(peer).life_deadline - game.ticked_through())


## Kills `peer` and has it waiting in the hall, with a tick for the draw.
func _in_hall(game: Match, peer: int) -> PlayerState:
	_kill(game, peer)
	FixtureModes.run_ticks(game, 1)
	return game.state.player(peer)


func _station(game: Match, id: int, at: Vector3, kind: StationKind = null) -> StationState:
	var station := StationState.new(
		id, kind if kind != null else StationKind.new(), at, Color.WHITE
	)
	game.state.stations[id] = station
	return station


func _used_kind() -> StationKind:
	var kind := StationKind.new()
	kind.id = &"used"
	kind.actions.append(FixtureModes.rule(Intents.INTERACT, [], [RanEffect.new()]))
	return kind


## Counts its runs (a stand-in for what a station does).
class RanEffect:
	extends RuleEffect

	var ran := 0

	func run(_ctx: MatchContext) -> void:
		ran += 1


## The match's end is the end it was (#1489, as today): the dead are out of the hall, so a dead
## viewer gets the living again and no dead.
func test_the_end_of_the_match_takes_the_dead_out_of_the_hall() -> void:
	var game := _duel()
	assert_bool(_in_hall(game, P2).in_hall).is_true()
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = game.mode
	ctx.outcome = Match.WON
	ctx.outcome_argument = game.mode.sides[0].id
	EndMatch.new().run(ctx)
	assert_bool(game.state.player(P2).in_hall).is_false()
	var seen := Snapshots.avatars_for(game.state, P2, game.ticked_through())
	assert_bool(seen.has(P1)).is_true()
	assert_bool(seen.has(P2)).is_false()
