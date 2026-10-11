extends GdUnitTestSuite
## The instant kill and the kill queue (LifeRules.kill, kill_later, settle_kills; the car repair
## ADR's RE6, RE17 and RD16 (c), #806; ARCHITECTURE §9.3): a living or downed player, invulnerable
## or not, dies at once as at the end of a knockdown (its channels stop first, then Died,
## player_died, the drop at the body, the respawn time), with no KnockedDown and no Correction. A
## queued kill lands once the command or the channel's step that queued it has finished, in
## peer-id order, skips a player already dead or gone with no rule error, and kills nobody once
## the step has an outcome or a transition runs. Driven by FixtureKill on a one-handed `trap`'s
## Use (P1 holds it) and FixtureKillingChannel on the mode's Use with an empty hand, in
## FixtureCombatModes.raising() (the knife, the raise, the respawn after 30 s, 600 ticks).

const P1 := 1
const P2 := 2
const P3 := 3
const P4 := 4
const NORTH := Vector3(0, 0, 1)
const TRAP_AT := Vector3(3, 0, 0)
const P2_AT := Vector3(0, 0, 1)
const RESPAWN_TICKS := 600


func test_a_living_player_killed_dies_at_once_and_drops_its_items_at_the_body() -> void:
	var game := _round(FixtureKill.of([], [P2]))
	FixtureItemModes.stand(game, P2, P2_AT + Vector3(0, 0.3, 0))
	var tool := FixtureItemModes.lay(game, &"tool", P2_AT)
	FixtureItemModes.pick_up(game, P2, tool)
	FixtureModes.run_ticks(game, 1)
	var seen := game.view_of(P3).events.size()
	var own := game.view_of(P2).events.size()
	var at_tick := game.ticked_through() + 1
	_spring(game)
	var dead := game.state.player(P2)
	assert_int(dead.life).is_equal(PlayerState.Life.DEAD)
	assert_int(dead.health).is_equal(0)
	assert_int(dead.life_deadline).is_equal(at_tick + RESPAWN_TICKS)
	assert_dict(game.state.bodies).is_equal({P2: P2_AT})
	# Died, the fact, then the drop at the body: no knockdown on the way.
	assert_array(FixtureItemModes.names_after(game, P3, seen)).is_equal(
		[&"Died", &"FixtureNote", &"ItemPlaced", &"FixtureNote", &"FixtureNote"]
	)
	assert_str(FixtureModes.notes(game)[-3]).is_equal("task player_died")
	var died := FixtureCombatModes.received(game, P3, &"Died")
	assert_dict(died[0].to_dict()).is_equal({"peer": P2, "position": P2_AT})
	assert_int(tool.where).is_equal(ItemState.Where.GROUND)
	assert_vector(tool.position).is_equal(P2_AT)
	FixtureModes.run_ticks(game, 1)
	# Its own view: no KnockedDown and no Correction; its SelfStatus says 0 health.
	var own_names := FixtureItemModes.names_after(game, P2, own)
	assert_array(own_names).not_contains([&"KnockedDown", &"Correction"])
	var status := FixtureCombatModes.received(game, P2, &"SelfStatus")
	assert_int((status[-1] as SelfStatusEvent).health).is_equal(0)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_downed_player_killed_stops_its_raise_first_then_dies_and_drops() -> void:
	var game := _round(FixtureKill.of([], [P2]))
	FixtureCombatModes.arm(game, P3, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, P2_AT)
	var tool := FixtureItemModes.lay(game, &"tool", P2_AT)
	FixtureItemModes.pick_up(game, P2, tool)
	FixtureCombatModes.use(game, P3, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P3, NORTH)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DOWNED)
	FixtureItemModes.stand(game, P4, Vector3(-1, 0, 1))
	FixtureCombatModes.raise(game, P4, P2)
	assert_object(Channels.of_actor(game.state, P4)).is_not_null()
	FixtureModes.run_ticks(game, 1)
	var seen := game.view_of(P1).events.size()
	_spring(game)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DEAD)
	assert_object(Channels.of_actor(game.state, P4)).is_null()
	assert_array(FixtureItemModes.names_after(game, P1, seen)).is_equal(
		[&"RaiseStopped", &"Died", &"FixtureNote", &"ItemPlaced", &"FixtureNote", &"FixtureNote"]
	)
	assert_int(tool.where).is_equal(ItemState.Where.GROUND)
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_killed_respawn_and_an_invulnerable_player_is_killed_all_the_same() -> void:
	var game := _round(FixtureKill.of([], [P2]))
	_spring(game)
	var deadline := game.state.player(P2).life_deadline
	FixtureModes.run_ticks(game, deadline - game.ticked_through())
	var back := game.state.player(P2)
	assert_int(back.life).is_equal(PlayerState.Life.ALIVE)
	assert_array(FixtureCombatModes.received(game, P3, &"Respawned")).has_size(1)
	assert_bool(back.is_invulnerable(game.ticked_through() + 1)).is_true()
	_spring(game)
	assert_int(back.life).is_equal(PlayerState.Life.DEAD)
	assert_array(FixtureCombatModes.received(game, P3, &"Died")).has_size(2)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_kill_of_a_player_neither_living_nor_downed_is_a_rule_error() -> void:
	var game := _round(FixtureKill.of([], [P2]))
	_spring(game)
	var dead := game.state.player(P2)
	var deadline := dead.life_deadline
	LifeRules.kill(_context(game), P2)
	assert_int(dead.life).is_equal(PlayerState.Life.DEAD)
	assert_int(dead.life_deadline).is_equal(deadline)
	assert_array(FixtureCombatModes.received(game, P3, &"Died")).has_size(1)
	FixtureModes.send(game, Intents.PEER_LEFT, P4)
	LifeRules.kill(_context(game), P4)
	assert_int(game.state.player(P4).life).is_equal(PlayerState.Life.LEFT)
	assert_array(FixtureCombatModes.received(game, P3, &"Died")).has_size(1)
	var errors := ";".join(game.diagnostics)
	assert_str(errors).contains("kill: player 2 is not living or downed")
	assert_str(errors).contains("kill: player 4 is not living or downed")


func test_queued_kills_land_after_the_commands_own_events_in_peer_id_order() -> void:
	var game := _round(FixtureKill.of([P3, P2], [], "sprung"))
	var seen := game.view_of(P4).events.size()
	_spring(game)
	assert_array(FixtureItemModes.names_after(game, P4, seen)).is_equal(
		[&"FixtureNote", &"Died", &"FixtureNote", &"Died", &"FixtureNote"]
	)
	assert_array(FixtureModes.notes(game).slice(-3)).is_equal(
		["sprung", "task player_died", "task player_died"]
	)
	var died := FixtureCombatModes.received(game, P4, &"Died")
	assert_int((died[0] as DiedEvent).peer).is_equal(P2)
	assert_int((died[1] as DiedEvent).peer).is_equal(P3)
	assert_bool(LifeRules.kills_queued(game.state)).is_false()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_queued_kill_of_a_player_who_died_meanwhile_is_skipped() -> void:
	var game := _round(FixtureKill.of([P2, P3, P3], [P2], "sprung"))
	_spring(game)
	var died := FixtureCombatModes.received(game, P4, &"Died")
	assert_array(died).has_size(2)
	assert_int((died[0] as DiedEvent).peer).is_equal(P2)
	assert_int((died[1] as DiedEvent).peer).is_equal(P3)
	# P2's at-once kill comes before the note; the queue's skip of it logs nothing.
	assert_array(FixtureModes.notes(game).slice(-3)).is_equal(
		["task player_died", "sprung", "task player_died"]
	)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_queued_kill_of_a_player_who_left_meanwhile_is_skipped() -> void:
	var game := _round(FixtureKill.of([], []))
	var ctx := _context(game)
	LifeRules.kill_later(ctx, P3)
	LifeRules.leave(ctx, P3)
	LifeRules.settle_kills(ctx)
	assert_int(game.state.player(P3).life).is_equal(PlayerState.Life.LEFT)
	assert_array(FixtureCombatModes.received(game, P4, &"Died")).is_empty()
	assert_bool(LifeRules.kills_queued(game.state)).is_false()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_holders_own_pick_up_runs_for_it_living_then_its_queued_kill_drops_the_item() -> void:
	var channel := FixtureKillingChannel.killing(5.0)
	channel.queues_on_stop = {P2: P2}
	var game := _round(null, channel)
	_hold(game, P2)
	var tool := FixtureItemModes.lay(game, &"tool", P2_AT)
	var seen := game.view_of(P4).events.size()
	FixtureItemModes.pick_up(game, P2, tool)
	var names := FixtureItemModes.names_after(game, P4, seen)
	# The stop, the pick-up for a living actor, and only then its Died and the drop at its body.
	assert_array(names).is_equal(
		[
			&"FixtureNote",
			&"ItemPickedUp",
			&"Died",
			&"FixtureNote",
			&"ItemPlaced",
			&"FixtureNote",
			&"FixtureNote"
		]
	)
	assert_str(FixtureModes.notes(game)[-4]).is_equal("stopped 2 after 0")
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DEAD)
	assert_int(game.state.player(P2).held_item).is_equal(-1)
	assert_int(tool.where).is_equal(ItemState.Where.GROUND)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_kill_queued_in_a_channel_step_lands_before_the_next_channels_step() -> void:
	# P1's channel completes first (actor-id order) and stops P2's, whose stop queues P3: P3 dies
	# in that channel's step, so its own channel stops there, one tick short, and never completes.
	var channel := FixtureKillingChannel.killing(1.0)
	channel.stops_on_completion = P2
	channel.queues_on_stop = {P2: P3}
	var game := _round(null, channel)
	for peer: int in [P1, P2, P3]:
		_hold(game, peer)
	FixtureModes.run_ticks(game, 25)
	var notes := FixtureModes.notes(game)
	var completed := notes.find("completed 1 after 20")
	assert_int(completed).is_greater(-1)
	assert_array(notes.slice(completed)).is_equal(
		["completed 1 after 20", "stopped 2 after 19", "stopped 3 after 19", "task player_died"]
	)
	assert_int(game.state.player(P3).life).is_equal(PlayerState.Life.DEAD)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_kill_queued_after_the_steps_outcome_kills_nobody() -> void:
	# P1's completion records the crew's win in the channel advance; P2's stop after it queues P3:
	# nothing dies after the outcome (RD16 (c)), and the round ends.
	var channel := FixtureKillingChannel.killing(1.0)
	channel.wins = true
	channel.stops_on_completion = P2
	channel.queues_on_stop = {P2: P3}
	var game := _round(null, channel)
	for peer: int in [P1, P2, P3]:
		_hold(game, peer)
	FixtureModes.run_ticks(game, 25)
	assert_str(game.phase_id()).is_equal("end")
	assert_int(game.state.player(P3).life).is_equal(PlayerState.Life.ALIVE)
	for peer: int in [P1, P2, P3, P4]:
		assert_array(FixtureCombatModes.received(game, peer, &"Died")).is_empty()
	assert_array(FixtureModes.notes(game)).contains(["stopped 2 after 19", "won crew"])
	assert_bool(LifeRules.kills_queued(game.state)).is_false()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_kill_queued_by_a_transition_row_is_dropped() -> void:
	var mode := _mode(FixtureKill.of([], []), null)
	var trap_rule := FixtureModes.rule(Intents.USE, [], [FixtureBump.of(&"crew_win")])
	_kind(mode, &"trap").actions = [trap_rule]
	mode.find_transition(&"round", Match.WON).actions.append(FixtureKill.of([P2]))
	var game := _game(mode)
	_spring(game)
	assert_str(game.phase_id()).is_equal("end")
	assert_bool(LifeRules.kills_queued(game.state)).is_false()
	FixtureModes.run_ticks(game, 5)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.ALIVE)
	assert_array(FixtureCombatModes.received(game, P3, &"Died")).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_kill_queued_by_a_tick_system_lands_before_the_next_tick_system_runs() -> void:
	var mode := _mode(FixtureKill.new(), null)
	mode.find_phase(&"round").tick_systems.append_array(
		[FixtureKillTick.queuing([P2]), FixtureKillTick.reporting(P2)]
	)
	var game := _game(mode, false)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.notes(game)).is_equal(["task player_died", "P2 DEAD"])
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DEAD)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_kill_queued_by_the_phases_own_timers_lands_before_any_tick_system() -> void:
	var mode := _mode(FixtureKill.new(), null)
	var round_spec := mode.find_phase(&"round")
	round_spec.phase_class = FixtureKillingRound
	round_spec.settings = {&"kills": float(P2)}
	round_spec.tick_systems.push_front(FixtureKillTick.reporting(P2))
	var game := _game(mode, false)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.notes(game)).is_equal(["task player_died", "P2 DEAD"])
	assert_array(Array(game.diagnostics)).is_empty()


## FixtureCombatModes.raising() with a one-handed `trap` whose Use runs `trap`, and, when
## `channel` is given, the mode's Use (an empty hand) starting it under ChannelFree.
func _mode(trap: FixtureKill, channel: FixtureKillingChannel) -> GameMode:
	var mode := FixtureCombatModes.raising()
	var trap_rule := FixtureModes.rule(Intents.USE, [], [trap])
	mode.item_kinds.append(FixtureItemModes.item_kind(&"trap", [trap_rule]))
	if channel != null:
		mode.actions.append(FixtureModes.rule(Intents.USE, [ChannelFree.new()], [channel]))
	return mode


## A round of _mode(trap, channel) for P1 to P4: P1 at TRAP_AT with the trap in hand (when
## `trap` is given), P2 at P2_AT, P3 and P4 away.
func _round(trap: FixtureKill, channel: FixtureKillingChannel = null) -> Match:
	var game := _game(_mode(trap if trap != null else FixtureKill.new(), channel), trap != null)
	return game


func _game(mode: GameMode, armed := true) -> Match:
	var game := FixtureCombatModes.in_round(mode, [P1, P2, P3, P4])
	FixtureItemModes.stand(game, P1, TRAP_AT)
	if armed:
		FixtureItemModes.pick_up(game, P1, FixtureItemModes.lay(game, &"trap", TRAP_AT))
	FixtureItemModes.stand(game, P2, P2_AT)
	FixtureItemModes.stand(game, P3, Vector3(5, 0, 5))
	FixtureItemModes.stand(game, P4, Vector3(-5, 0, 5))
	return game


func _kind(mode: GameMode, id: StringName) -> ItemKind:
	for kind: ItemKind in mode.item_kinds:
		if kind.id == id:
			return kind
	return null


## P1 uses the trap, applied on the next host tick.
func _spring(game: Match) -> void:
	FixtureCombatModes.use(game, P1, NORTH)


## `peer`, its hand empty, starts the mode's channel with a Use.
func _hold(game: Match, peer: int) -> void:
	FixtureCombatModes.use(game, peer, NORTH)


func _context(game: Match) -> MatchContext:
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = game.mode
	ctx.world = FlatWorldQuery.new()
	ctx.tick = game.ticked_through() + 1
	return ctx
