extends GdUnitTestSuite
## The print (#1489; ARCHITECTURE §3.4, §4.2): at the respawn's deadline a drone starts printing the
## dead player on a free respawn marker for Respawn.print_s: PrintStarted (everyone) removes the
## body, the player stands PRINTING and cannot move, act or be hit; at the print's end Respawned
## (everyone) and the invulnerability. Driven by the knife's Use and FixtureHallModes' numbers.

const P1 := 1
const P2 := 2
const P3 := 3
const NORTH := Vector3(0, 0, 1)
const INVULNERABLE_TICKS := 60
const FULL := 100000


func test_the_print_starts_at_the_deadline_the_body_goes_and_no_respawned_yet() -> void:
	var game := _duel()
	_kill(game)
	var dead := game.state.player(P2)
	assert_int(dead.life).is_equal(PlayerState.Life.DEAD)
	assert_dict(game.state.bodies).contains_keys([P2])
	var own_seen := game.view_of(P2).events.size()
	_run_out(game)
	assert_int(dead.life).is_equal(PlayerState.Life.PRINTING)
	assert_int(dead.life_deadline).is_equal(game.ticked_through() + FixtureHallModes.PRINT_TICKS)
	assert_dict(game.state.bodies).is_empty()
	assert_bool(FixtureModes.RESPAWNS.has(dead.position)).is_true()
	assert_int(dead.health).is_equal(FULL)
	assert_int(dead.stamina).is_equal(FULL)
	for peer: int in [P1, P2, P3]:
		var started := FixtureCombatModes.received(game, peer, &"PrintStarted")
		assert_array(started).has_size(1)
		assert_dict(started[0].to_dict()).is_equal(
			{"peer": P2, "position": dead.position, "print_ms": 2000}
		)
		assert_array(FixtureCombatModes.received(game, peer, &"Respawned")).is_empty()
	assert_array(FixtureItemModes.names_after(game, P2, own_seen)).is_equal(
		[&"PrintStarted", &"Correction", &"SelfStatus"]
	)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_printing_player_is_not_hit_cannot_move_and_is_shown_invulnerable() -> void:
	var game := _duel()
	_kill(game)
	_run_out(game)
	var printing := game.state.player(P2)
	assert_bool(printing.is_alive()).is_false()
	# P1's knife reaches the marker: stand next to it and strike.
	FixtureItemModes.stand(game, P1, printing.position + Vector3(0, 0, -1))
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(printing.health).is_equal(FULL)
	assert_int(printing.life).is_equal(PlayerState.Life.PRINTING)
	# A claim is dropped; the avatar stands, flagged invulnerable, to P1.
	var at := printing.position
	FixtureMoves.claim(game, P2, at + Vector3(1, 0, 0), {"moving": true})
	assert_vector(printing.position).is_equal(at)
	FixtureModes.send(game, Intents.USE, P2, {"facing": NORTH})
	FixtureModes.run_ticks(game, 1)
	var seen: Dictionary = game.view_of(P1).snapshots[game.ticked_through()]
	assert_bool(seen["avatars"][P2]["invulnerable"]).is_true()


func test_the_print_ends_living_invulnerable_and_public() -> void:
	var game := _duel()
	_kill(game)
	_run_out(game)
	var back := game.state.player(P2)
	var epoch := back.epoch
	var own_seen := game.view_of(P2).events.size()
	FixtureModes.run_ticks(game, FixtureHallModes.PRINT_TICKS)
	assert_int(back.life).is_equal(PlayerState.Life.ALIVE)
	assert_int(back.life_deadline).is_equal(-1)
	assert_int(back.epoch).is_equal(epoch)
	assert_bool(back.is_invulnerable(game.ticked_through() + INVULNERABLE_TICKS - 1)).is_true()
	assert_bool(back.is_invulnerable(game.ticked_through() + INVULNERABLE_TICKS)).is_false()
	for peer: int in [P1, P2, P3]:
		var respawned := FixtureCombatModes.received(game, peer, &"Respawned")
		assert_array(respawned).has_size(1)
		assert_dict(respawned[0].to_dict()).is_equal({"peer": P2, "position": back.position})
	assert_array(FixtureItemModes.names_after(game, P2, own_seen)).is_equal(
		[&"Respawned", &"SelfStatus"]
	)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_printing_player_keeps_its_marker_from_the_next_draw() -> void:
	var game := _duel()
	_kill(game)
	_run_out(game)
	var printing := game.state.player(P2)
	var spots := PackedVector3Array(FixtureModes.RESPAWNS)
	assert_bool(Respawn.free_markers(game.state, spots).has(printing.position)).is_false()


func test_the_print_is_not_heard_and_the_printing_player_hears_nobody() -> void:
	var game := _duel()
	_kill(game)
	_run_out(game)
	assert_bool(game.speakers_for(P1).has(P2)).is_false()
	assert_array(Array(game.speakers_for(P2))).is_empty()


func test_what_a_dead_player_holds_in_the_hall_drops_there_with_no_error() -> void:
	var game := _duel()
	_kill(game)
	FixtureModes.run_ticks(game, 1)
	var dead := game.state.player(P2)
	assert_bool(dead.in_hall).is_true()
	var mug := FixtureItemModes.lay(game, &"tool", dead.position)
	FixtureItemModes.pick_up(game, P2, mug)
	assert_array(Array(dead.carried_items())).has_size(1)
	var hall_floor := dead.position
	_run_out(game)
	assert_int(dead.life).is_equal(PlayerState.Life.PRINTING)
	assert_array(Array(dead.carried_items())).is_empty()
	assert_int(mug.where).is_equal(ItemState.Where.GROUND)
	assert_vector(mug.position).is_equal(hall_floor)
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_match_ending_while_printing_resets_as_any_life_state() -> void:
	var game := _duel()
	_kill(game)
	_run_out(game)
	var printing := game.state.player(P2)
	assert_int(printing.life).is_equal(PlayerState.Life.PRINTING)
	game.state.reset_match()
	assert_int(printing.life).is_equal(PlayerState.Life.ALIVE)
	assert_int(printing.life_deadline).is_equal(-1)
	assert_bool(printing.in_hall).is_false()


func _duel(seed_value: int = 7) -> Match:
	var game := FixtureCombatModes.in_round(FixtureHallModes.mode(), [P1, P2, P3], null, seed_value)
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1))
	FixtureItemModes.stand(game, P3, Vector3(5, 0, 5))
	return game


## P1 hits P2 twice, the cooldown apart, and P2's knockdown runs out: P2 is dead.
func _kill(game: Match) -> void:
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, NORTH)
	_run_out(game)


## Runs ticks through P2's life deadline: the tick it dies or the print starts.
func _run_out(game: Match) -> void:
	FixtureModes.run_ticks(game, game.state.player(P2).life_deadline - game.ticked_through())
